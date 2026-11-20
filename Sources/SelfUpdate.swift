// SelfUpdate.swift: updates that install themselves (macOS).
// Copyright (C) 2026 Gabriel Castiglia. Licensed under the GNU GPL, version 2 only.
// Date: November 20, 2026
// SPDX-License-Identifier: GPL-2.0-only
//
// The same file in Vigía, Forja, Haul and Citadel for macOS; each app sets the values at the top of
// SelfUpdate.shared when it starts. It follows the Windows versions of the same apps:
//   Help → Check for updates, and once a day by itself, asks GitHub for the latest release. When it is newer, one
//   question: Update now, What's new or Later. Then everything happens alone: <App>-<version>.pkg is downloaded and
//   checked against the release's SHA256SUMS.txt (a file that does not match is deleted and never opened); the app
//   inside the package must carry this app's identifier, the version of the release and a signature that meets this
//   app's own designated requirement. The new app is put beside /Applications/<App>.app, the app quits as when it is
//   quit by hand (it saves or asks first), the two are swapped while it quits, and the new one opens.
//   A copy that is not /Applications/<App>.app, or one this user cannot replace, is offered the download page or
//   the package in Installer instead.

import AppKit
import CryptoKit
import Security

/// Used from the main thread only (menus, alerts, the app delegate).
final class SelfUpdate: NSObject, @unchecked Sendable {
    static let shared = SelfUpdate()

    // Set by the app when it starts.
    var appName = ""                          // "Vigia": /Applications/Vigia.app, Vigia-<version>.pkg
    var displayName = ""                      // "Vigía": how the texts name the app (appName when empty)
    private var shown: String { displayName.isEmpty ? appName : displayName }
    var repo = ""                             // "Gabriel-Castiglia/vigia"
    var version = "0.0.0"
    var language: () -> String = { "en" }     // "en", "es" or "ja"
    var dailyCheckOn: () -> Bool = { true }
    /// Asked once the new app is ready, before quitting: false stops the update (Citadel lets an answer finish or
    /// stops it, as the user chooses).
    var readyToQuit: @MainActor () async -> Bool = { true }
    /// Called right before the app quits for the update (Haul keeps its queue, Citadel its draft).
    var beforeQuit: () -> Void = {}

    struct Release: Equatable {
        var tag = "", page: URL?, pkg: URL?, pkgName: String?, sums: URL?
    }

    private var busy = false
    private var staged: URL?                  // the new app, beside the installed one
    private var stagedAt = Date.distantPast
    private var panel: NSPanel?
    private var panelText: NSTextField?
    private var panelBar: NSProgressIndicator?

    var installedURL: URL { URL(fileURLWithPath: "/Applications/\(appName).app") }
    private var stagedURL: URL { URL(fileURLWithPath: "/Applications/.\(appName).app.new") }
    private var oldURL: URL { URL(fileURLWithPath: "/Applications/.\(appName).app.old") }
    private var workDir: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent((Bundle.main.bundleIdentifier ?? appName) + ".update", isDirectory: true)
    }

    // MARK: pure functions (the self-tests check them)

    /// 2 to 4 numbers separated by dots, a leading v or V ignored; nil for anything else.
    nonisolated static func parts(_ s: String) -> [Int]? {
        var t = Substring(s)
        while let c = t.first, c == "v" || c == "V" { t = t.dropFirst() }
        let p = t.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...4).contains(p.count) else { return nil }
        var out: [Int] = []
        for x in p {
            guard !x.isEmpty, x.count <= 9, x.allSatisfy({ $0.isASCII && $0.isNumber }), let n = Int(x) else { return nil }
            out.append(n)
        }
        return out
    }

    /// Whether a published tag is newer than mine. A missing part is lower than 0 (2.1 < 2.1.0), as in the Windows
    /// versions; anything that is not a version is never newer.
    nonisolated static func isNewer(_ tag: String, than mine: String) -> Bool {
        guard let a = parts(tag), let b = parts(mine) else { return false }
        for i in 0..<4 {
            let x = i < a.count ? a[i] : -1, y = i < b.count ? b[i] : -1
            if x != y { return x > y }
        }
        return false
    }

    /// The hash of one file in a SHA256SUMS.txt ("hash  name" or "hash *name" per line), in lower case; nil if absent.
    nonisolated static func hash(for name: String, in sums: String) -> String? {
        for raw in sums.split(whereSeparator: \.isNewline) {   // "\r\n" is one Character in Swift
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let sp = line.firstIndex(where: { $0 == " " || $0 == "\t" }),
                  line.distance(from: line.startIndex, to: sp) == 64 else { continue }
            let hex = line[..<sp]
            guard hex.allSatisfy({ $0.isHexDigit }) else { continue }
            var file = line[sp...].trimmingCharacters(in: .whitespaces)
            while file.hasPrefix("*") { file.removeFirst() }
            if file.caseInsensitiveCompare(name) == .orderedSame { return hex.lowercased() }
        }
        return nil
    }

    /// A file name that can be saved as it is: letters, digits, dot, hyphen, underscore.
    nonisolated static func safeName(_ s: String) -> Bool {
        !s.isEmpty && !s.hasPrefix(".") && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }
    }

    /// The latest release out of the GitHub API's answer; nil without a tag.
    nonisolated static func parse(_ data: Data, app: String) -> Release? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let tag = root["tag_name"] as? String, !tag.isEmpty else { return nil }
        var r = Release(tag: tag)
        if let p = root["html_url"] as? String, p.hasPrefix("https://") { r.page = URL(string: p) }
        for a in root["assets"] as? [[String: Any]] ?? [] {
            guard let name = a["name"] as? String, let u = a["browser_download_url"] as? String,
                  u.hasPrefix("https://"), let url = URL(string: u) else { continue }
            if name.lowercased().hasPrefix(app.lowercased() + "-"), name.lowercased().hasSuffix(".pkg"), safeName(name) {
                r.pkg = url; r.pkgName = name
            } else if name.caseInsensitiveCompare("SHA256SUMS.txt") == .orderedSame {
                r.sums = url
            }
        }
        return r
    }

    nonisolated static func sha256(of file: URL) throws -> String {
        let h = try FileHandle(forReadingFrom: file)
        defer { try? h.close() }
        var sha = SHA256()
        while let chunk = try h.read(upToCount: 1 << 20), !chunk.isEmpty { sha.update(data: chunk) }
        return sha.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Known answers for the functions above: (what, passed).
    nonisolated static func selfTest() -> [(String, Bool)] {
        let sums = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef  App-9.9.9.pkg\r\n"
            + "FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210 *other.pdf\n"
            + "short  Short.pkg\n"
            + "  1111111111111111111111111111111111111111111111111111111111111111\tTabbed.pkg  \n"
            + "zz23456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef  NotHex.pkg\n"
        let json = #"{"tag_name": "v9.9.9", "html_url": "https://github.com/o/r/releases/tag/v9.9.9", "assets": ["#
            + #"{"name": "SHA256SUMS.txt", "browser_download_url": "https://github.com/o/r/releases/download/v9.9.9/SHA256SUMS.txt"},"#
            + #"{"name": "App-9.9.9.pkg", "browser_download_url": "https://github.com/o/r/releases/download/v9.9.9/App-9.9.9.pkg"},"#
            + #"{"name": "App-..%2f.pkg", "browser_download_url": "https://github.com/o/r/releases/download/v9.9.9/x.pkg"},"#
            + #"{"name": "App-manual-en.pdf", "browser_download_url": "http://github.com/x.pdf"}]}"#
        let r = parse(Data(json.utf8), app: "App")
        return [
            ("update: v2.1.0 is newer than 2.0.2", isNewer("v2.1.0", than: "2.0.2")),
            ("update: 2.0.10 is newer than 2.0.9 (numbers, not text)", isNewer("2.0.10", than: "2.0.9")),
            ("update: 2.1.0 is newer than 2.1 (a missing part is lower)", isNewer("2.1.0", than: "2.1")),
            ("update: the same version is not newer", !isNewer("v2.1.0", than: "2.1.0")),
            ("update: an older version is not newer", !isNewer("v2.0.2", than: "2.1.0")),
            ("update: a tag with a suffix is ignored", !isNewer("v2.2.0-beta", than: "2.1.0")),
            ("update: one number or five are not a version", !isNewer("3", than: "2.1.0") && !isNewer("1.2.3.4.5", than: "1.0")),
            ("update: hash \"hash  name\"", hash(for: "App-9.9.9.pkg", in: sums) == "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"),
            ("update: hash \"hash *name\", any case, lower case out", hash(for: "OTHER.PDF", in: sums) == "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"),
            ("update: hash with a tab and spaces around the line", hash(for: "Tabbed.pkg", in: sums)?.first == "1"),
            ("update: a short or non-hex hash is not a hash", hash(for: "Short.pkg", in: sums) == nil && hash(for: "NotHex.pkg", in: sums) == nil),
            ("update: a missing file has no hash", hash(for: "App-9.9.pkg", in: sums) == nil),
            ("update: release tag and page", r?.tag == "v9.9.9" && r?.page?.absoluteString == "https://github.com/o/r/releases/tag/v9.9.9"),
            ("update: the package (an unsafe name is ignored)", r?.pkgName == "App-9.9.9.pkg" && r?.pkg?.lastPathComponent == "App-9.9.9.pkg"),
            ("update: SHA256SUMS.txt", r?.sums?.lastPathComponent == "SHA256SUMS.txt"),
            ("update: no tag, no release", parse(Data(#"{"message":"Not Found"}"#.utf8), app: "App") == nil),
        ]
    }

    // MARK: texts

    private func T(_ key: String, _ args: CVarArg...) -> String {
        let lang = language()
        let t = SelfUpdate.texts[key] ?? [key, key, key]
        let s = lang == "es" ? t[1] : lang == "ja" ? t[2] : t[0]
        return args.isEmpty ? s : String(format: s, arguments: args)
    }

    // [English, Spanish, Japanese]
    private static let texts: [String: [String]] = [
        "UpToDate": ["%@ %@ is the latest version.", "%@ %@ es la versión más reciente.", "%@ %@ は最新バージョンです。"],
        "AskHead": ["%@ %@ is available", "Hay una versión nueva: %@ %@", "%@ %@ が公開されています"],
        "Ask": ["You have %@. %@ can download it, check it, install it and open again by itself.",
                "Tienes la %@. %@ puede descargarla, comprobarla, instalarla y volver a abrirse sola.",
                "現在のバージョンは %@ です。%@ はダウンロード、確認、インストールを行い、自動的に再起動します。"],
        "Now": ["Update now", "Actualizar ahora", "今すぐアップデート"],
        "Notes": ["What's new", "Ver novedades", "新機能を見る"],
        "Later": ["Later", "Más tarde", "後で"],
        "OK": ["OK", "Aceptar", "OK"],
        "OpenPage": ["Open the page", "Abrir la página", "ページを開く"],
        "NotInstalled": ["You have %@. This copy is not /Applications/%@.app, so it cannot update itself: download the new version from its page.",
                         "Tienes la %@. Esta copia no es /Applications/%@.app, así que no puede actualizarse sola: descarga la versión nueva desde su página.",
                         "現在のバージョンは %@ です。このコピーは /Applications/%@.app ではないため自動アップデートできません。ページから新しいバージョンをダウンロードしてください。"],
        "NoPackage": ["You have %@. This release does not include what is needed to update by itself.",
                      "Tienes la %@. Esta versión no trae lo necesario para actualizarse sola.",
                      "現在のバージョンは %@ です。このリリースには自動アップデートに必要なファイルがありません。"],
        "Downloading": ["Downloading %@ %@… %@", "Descargando %@ %@… %@", "%@ %@ をダウンロード中… %@"],
        "Checking": ["Checking the new version…", "Comprobando la versión nueva…", "新しいバージョンを確認中…"],
        "Installer": ["The package was checked and opens in Installer: this user cannot replace /Applications/%@.app by itself.",
                      "El paquete se comprobó y se abre en el Instalador: este usuario no puede reemplazar /Applications/%@.app por sí solo.",
                      "パッケージを確認しました。このユーザーは /Applications/%@.app を置き換えられないため、インストーラで開きます。"],
        "Failed": ["The update could not be installed: %@", "No se pudo actualizar: %@", "アップデートをインストールできませんでした: %@"],
        "CheckFailed": ["Could not check for updates: %@", "No se pudo buscar actualizaciones: %@", "アップデートを確認できませんでした: %@"],
        "NoHash": ["SHA256SUMS.txt does not list the package.", "SHA256SUMS.txt no nombra el paquete.", "SHA256SUMS.txt にパッケージが記載されていません。"],
        "BadHash": ["the downloaded package does not match its checksum: it was deleted without opening it.",
                    "el paquete descargado no coincide con su suma de comprobación: se borró sin abrirlo.",
                    "ダウンロードしたパッケージがチェックサムと一致しないため、開かずに削除しました。"],
        "BadApp": ["the app in the package is not this app, or not the announced version, or not signed like this one.",
                   "la app del paquete no es esta, o no es la versión anunciada, o no está firmada como esta.",
                   "パッケージ内のアプリがこのアプリではないか、告知されたバージョンではないか、同じ署名ではありません。"],
        "BadReply": ["GitHub's answer could not be read.", "No se pudo leer la respuesta de GitHub.", "GitHub の応答を読み取れませんでした。"],
        "Http": ["GitHub answered %ld.", "GitHub respondió %ld.", "GitHub の応答: %ld"],
    ]

    // MARK: checking

    private static let stampKey = "SelfUpdateLastCheck"

    /// The daily check: at most one try a day, even without network.
    func checkDaily() {
        guard dailyCheckOn() else { return }
        let last = UserDefaults.standard.double(forKey: SelfUpdate.stampKey), now = Date().timeIntervalSince1970
        guard now - last >= 24 * 3600 || now < last else { return }
        check(interactive: false)
    }

    func check(interactive: Bool) {
        guard !busy else { return }
        busy = true
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: SelfUpdate.stampKey)
        Task { @MainActor in
            do {
                var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!, timeoutInterval: 15)
                req.setValue("\(appName)/\(version)", forHTTPHeaderField: "User-Agent")
                req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                let (data, resp) = try await URLSession.shared.data(for: req)
                if let code = (resp as? HTTPURLResponse)?.statusCode, code != 200 { throw Problem(T("Http", code)) }
                guard let rel = SelfUpdate.parse(data, app: appName) else { throw Problem(T("BadReply")) }
                try await decide(rel, interactive: interactive)
            } catch {
                if interactive { say(T("CheckFailed", error.localizedDescription)) }
            }
            busy = false
        }
    }

    private struct Problem: LocalizedError {
        let text: String
        init(_ t: String) { text = t }
        var errorDescription: String? { text }
    }

    @MainActor
    private func decide(_ rel: Release, interactive: Bool) async throws {
        var bare = rel.tag
        while bare.hasPrefix("v") || bare.hasPrefix("V") { bare.removeFirst() }
        guard SelfUpdate.isNewer(rel.tag, than: version) else {
            if interactive { say(T("UpToDate", shown, version)) }
            return
        }
        let head = T("AskHead", shown, bare)
        guard Bundle.main.bundleURL.standardizedFileURL.path == installedURL.path else {
            return offerPage(rel, head: head, text: T("NotInstalled", version, appName))
        }
        guard rel.pkg != nil, rel.sums != nil, rel.pkgName != nil else {
            return offerPage(rel, head: head, text: T("NoPackage", version))
        }
        let a = NSAlert()
        a.messageText = head
        a.informativeText = T("Ask", version, shown)
        a.addButton(withTitle: T("Now"))
        a.addButton(withTitle: T("Notes"))
        a.addButton(withTitle: T("Later"))
        NSApp.activate(ignoringOtherApps: true)
        switch a.runModal() {
        case .alertFirstButtonReturn:
            do { try await install(rel, bare: bare) }
            catch {
                closePanel()
                try? FileManager.default.removeItem(at: workDir)
                say(T("Failed", error.localizedDescription), warning: true)
            }
        case .alertSecondButtonReturn:
            if let p = rel.page { NSWorkspace.shared.open(p) }
        default: break
        }
    }

    @MainActor
    private func offerPage(_ rel: Release, head: String, text: String) {
        let a = NSAlert()
        a.messageText = head
        a.informativeText = text
        a.addButton(withTitle: T("OpenPage"))
        a.addButton(withTitle: T("Later"))
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(rel.page ?? URL(string: "https://github.com/\(repo)/releases/latest")!)
        }
    }

    @MainActor
    private func say(_ text: String, warning: Bool = false) {
        let a = NSAlert()
        a.messageText = shown
        a.informativeText = text
        a.alertStyle = warning ? .warning : .informational
        a.addButton(withTitle: T("OK"))
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    // MARK: installing

    @MainActor
    private func install(_ rel: Release, bare: String) async throws {
        guard let pkgURL = rel.pkg, let sumsURL = rel.sums, let pkgName = rel.pkgName else { return }
        let fm = FileManager.default
        try? fm.removeItem(at: workDir)
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
        showPanel(T("Downloading", shown, bare, "0 %"))

        var req = URLRequest(url: sumsURL, timeoutInterval: 30)
        req.setValue("\(appName)/\(version)", forHTTPHeaderField: "User-Agent")
        let (sumsData, sumsResp) = try await URLSession.shared.data(for: req)
        if let code = (sumsResp as? HTTPURLResponse)?.statusCode, code != 200 { throw Problem(T("Http", code)) }
        guard let expected = SelfUpdate.hash(for: pkgName, in: String(decoding: sumsData, as: UTF8.self)) else { throw Problem(T("NoHash")) }

        let pkg = workDir.appendingPathComponent(pkgName)
        try await Downloader(url: pkgURL, agent: "\(appName)/\(version)") { [weak self] pct, done in
            guard let self else { return }
            self.panelText?.stringValue = self.T("Downloading", self.shown, bare, pct >= 0 ? "\(pct) %" : "\(done >> 20) MB")
            if pct >= 0 { self.panelBar?.isIndeterminate = false; self.panelBar?.doubleValue = Double(pct) }
        }.run(to: pkg)

        panelText?.stringValue = T("Checking")
        panelBar?.isIndeterminate = true
        panelBar?.startAnimation(nil)
        let actual = try await Task.detached { try SelfUpdate.sha256(of: pkg) }.value
        guard actual == expected else {
            try? fm.removeItem(at: pkg)
            throw Problem(T("BadHash"))
        }

        // The user cannot replace the installed app (installed by an administrator): Installer, with the checked package.
        guard canReplaceInstalled() else {
            closePanel()
            say(T("Installer", appName))
            NSWorkspace.shared.open(pkg)
            return
        }

        let expanded = workDir.appendingPathComponent("expanded")
        try await run("/usr/sbin/pkgutil", ["--expand-full", pkg.path, expanded.path])
        guard let app = findApp(in: expanded), checkApp(app, version: bare) else {
            try? fm.removeItem(at: workDir)
            throw Problem(T("BadApp"))
        }
        try? fm.removeItem(at: stagedURL)
        try await run("/usr/bin/ditto", [app.path, stagedURL.path])
        try? fm.removeItem(at: workDir)
        guard checkApp(stagedURL, version: bare) else {
            try? fm.removeItem(at: stagedURL)
            throw Problem(T("BadApp"))
        }
        closePanel()
        guard await readyToQuit() else {
            try? fm.removeItem(at: stagedURL)
            return
        }
        staged = stagedURL
        stagedAt = Date()
        beforeQuit()
        NSApp.terminate(nil)
        // Still here: the quit was cancelled (a question answered Cancel). The new app waits beside the old one and
        // goes in when the app quits; it opens again by itself only right after an update.
    }

    /// The installed app belongs to this user and /Applications can be written: the swap needs no administrator.
    private func canReplaceInstalled() -> Bool {
        let fm = FileManager.default
        guard let owner = (try? fm.attributesOfItem(atPath: installedURL.path))?[.ownerAccountID] as? NSNumber else { return false }
        return owner.uint32Value == getuid() && fm.isWritableFile(atPath: "/Applications")
    }

    private func findApp(in dir: URL) -> URL? {
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { return nil }
        for case let u as URL in e {
            if u.lastPathComponent == "\(appName).app", u.deletingLastPathComponent().lastPathComponent == "Applications",
               u.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "Payload" { return u }
            if u.pathExtension == "app" { e.skipDescendants() }
        }
        return nil
    }

    /// The same identifier, the announced version, and a signature that meets this app's designated requirement.
    private func checkApp(_ app: URL, version v: String) -> Bool {
        guard let b = Bundle(url: app), b.bundleIdentifier == Bundle.main.bundleIdentifier,
              (b.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) == v else { return false }
        var me: SecCode?, meStatic: SecStaticCode?, req: SecRequirement?, other: SecStaticCode?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
              SecCodeCopyStaticCode(me, [], &meStatic) == errSecSuccess, let meStatic,
              SecCodeCopyDesignatedRequirement(meStatic, [], &req) == errSecSuccess, let req,
              SecStaticCodeCreateWithPath(app as CFURL, [], &other) == errSecSuccess, let other else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        return SecStaticCodeCheckValidity(other, flags, req) == errSecSuccess
    }

    private func run(_ tool: String, _ args: [String]) async throws {
        try await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: tool)
            p.arguments = args
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try p.run()
            p.waitUntilExit()
            if p.terminationStatus != 0 { throw Problem("\(URL(fileURLWithPath: tool).lastPathComponent) \(p.terminationStatus)") }
        }.value
    }

    /// From applicationWillTerminate: with a new app waiting, the two are swapped now (two renames), and the new one
    /// opens once this process is gone, if the quit came from the update.
    func finishIfStaged() {
        let fm = FileManager.default
        let waiting = staged ?? (fm.fileExists(atPath: stagedURL.path) ? stagedURL : nil)
        guard let new = waiting, fm.fileExists(atPath: new.path) else { return }
        try? fm.removeItem(at: oldURL)
        do {
            try fm.moveItem(at: installedURL, to: oldURL)
            do { try fm.moveItem(at: new, to: installedURL) }
            catch { try? fm.moveItem(at: oldURL, to: installedURL); return }
        } catch { return }
        let reopen = staged != nil && Date().timeIntervalSince(stagedAt) < 600
        // Removing the old app and opening the new one happen after this process ends.
        let script = """
            while /bin/kill -0 \(getpid()) 2>/dev/null; do /bin/sleep 0.2; done
            /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$1"
            /bin/rm -rf "$2"
            [ "$3" = 1 ] && /usr/bin/open "$1"
            exit 0
            """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-c", script, "selfupdate", installedURL.path, oldURL.path, reopen ? "1" : "0"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    /// At start: what an update left beside the installed app that no update is waiting for (a copy cut halfway).
    func cleanUpAtStart() {
        let fm = FileManager.default
        if fm.fileExists(atPath: oldURL.path) { try? fm.removeItem(at: oldURL) }
        if fm.fileExists(atPath: stagedURL.path), Bundle(url: stagedURL)?.bundleIdentifier != Bundle.main.bundleIdentifier
            || !SelfUpdate.isNewer((Bundle(url: stagedURL)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "", than: version) {
            try? fm.removeItem(at: stagedURL)
        }
        try? fm.removeItem(at: workDir)
    }

    // MARK: the progress window

    @MainActor
    private func showPanel(_ text: String) {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 92), styleMask: [.titled], backing: .buffered, defer: false)
        p.title = shown
        p.isReleasedWhenClosed = false
        let label = NSTextField(labelWithString: text)
        label.frame = NSRect(x: 20, y: 50, width: 340, height: 20)
        let bar = NSProgressIndicator(frame: NSRect(x: 20, y: 22, width: 340, height: 16))
        bar.style = .bar
        bar.minValue = 0
        bar.maxValue = 100
        bar.isIndeterminate = false
        p.contentView?.addSubview(label)
        p.contentView?.addSubview(bar)
        p.center()
        p.makeKeyAndOrderFront(nil)
        panel = p; panelText = label; panelBar = bar
    }

    @MainActor
    private func closePanel() {
        panel?.close()
        panel = nil; panelText = nil; panelBar = nil
    }
}

/// One download to a file, with its progress (percentage, or -1 with the bytes so far when the size is unknown).
private final class Downloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let url: URL, agent: String
    private let progress: @MainActor (Int, Int64) -> Void
    private var target: URL?
    private var cont: CheckedContinuation<Void, Error>?
    private var lastPct = -2
    private var moveError: Error?

    init(url: URL, agent: String, progress: @escaping @MainActor (Int, Int64) -> Void) {
        self.url = url; self.agent = agent; self.progress = progress
    }

    func run(to file: URL) async throws {
        target = file
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            cont = c
            var req = URLRequest(url: url, timeoutInterval: 60)
            req.setValue(agent, forHTTPHeaderField: "User-Agent")
            session.downloadTask(with: req).resume()
        }
    }

    func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten done: Int64,
                    totalBytesExpectedToWrite total: Int64) {
        let pct = total > 0 ? Int(done * 100 / total) : -1
        guard pct != lastPct else { return }
        lastPct = pct
        let report = progress
        Task { @MainActor in report(pct, done) }
    }

    func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let code = (downloadTask.response as? HTTPURLResponse)?.statusCode, code != 200 {
            moveError = NSError(domain: "HTTP", code: code, userInfo: [NSLocalizedDescriptionKey: "HTTP \(code)"])
            return
        }
        do {
            if let t = target {
                try? FileManager.default.removeItem(at: t)
                try FileManager.default.moveItem(at: location, to: t)
            }
        } catch { moveError = error }
    }

    func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let c = cont
        cont = nil
        if let e = error ?? moveError { c?.resume(throwing: e) } else { c?.resume() }
    }
}
