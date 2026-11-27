// SelfTest.swift
// Copyright (C) 2026 Gabriel Castiglia. Licensed under the GNU GPL, version 2 only.
// SPDX-License-Identifier: GPL-2.0-only
//
// This program is free software; you can redistribute it and/or modify it
// under the terms of the GNU General Public License version 2 as published by
// the Free Software Foundation.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with
// this program; if not, see <https://www.gnu.org/licenses/>.

import AppKit
import Foundation

/// End-to-end check of the running app, driven through the same ChatModel the window uses:
///   Citadel --self-test --memory-folder /tmp/some-folder
/// Nothing is written to the conversations folder; memories go only to the given folder.
@MainActor
enum SelfTest {
    private static func say(_ s: String) {
        FileHandle.standardOutput.write(Data((s + "\n").utf8))
    }

    private static func waitWhile(_ timeout: Double, _ busy: () -> Bool) async -> Bool {
        let start = Date()
        while busy() {
            if Date().timeIntervalSince(start) > timeout { return false }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return true
    }

    /// The search in the messages, the export to Markdown and the update checks (no network, no Ollama).
    static func offlineChecks(_ check: (Bool, String) -> Void) {
        var c = Conversation()
        c.title = "Viaje en camión: notas/ideas"
        var u = ChatMessage(role: .user, content: "¿Cuánto tarda el Camión\nde la mañana?")
        u.attachments = [Attachment(name: "a.txt", text: "x ```` y")]
        var a = ChatMessage(role: .assistant, content: "Tarda dos  horas.\n```swift\nlet x = 1")
        a.thinking = "pensando"
        a.stats = AnswerStats(model: "qwen3:8b", tokens: 10, tokensPerSecond: 12.34, seconds: 2.5)
        c.messages = [u, a, ChatMessage(role: .notice, content: "camion en un aviso")]
        let hits = ConversationSearch.find([c], "camion de la")
        check(hits.count == 1 && hits.first?.match == "Camión de la", "search: case, accents and line breaks do not matter (\(hits.first?.match ?? "-"))")
        check(ConversationSearch.find([c], "dos horas").first?.match == "dos horas", "search: runs of spaces are one space")
        check(ConversationSearch.find([c], "aviso").isEmpty, "search: notes of the app are not searched")
        check(ConversationSearch.find([c], "c").isEmpty, "search: one letter is too short")
        let long = ChatMessage(role: .user, content: String(repeating: "palabra ", count: 40) + "AGUJA " + String(repeating: "otra ", count: 40))
        var c2 = Conversation(); c2.messages = [long]
        if let h = ConversationSearch.find([c2], "aguja").first {
            check(h.before.hasPrefix("…") && h.after.hasSuffix("…") && h.before.hasSuffix(" ") && h.after.hasPrefix(" "),
                  "search: the fragment is cut at spaces, with … on both sides")
        } else { check(false, "search: a match inside a long message") }
        // 1.4.0: what Citadel for Windows 1.4.0 fixed, on the Mac
        var many = Conversation()
        many.messages = (0 ..< 5).map { _ in ChatMessage(role: .user, content: "aguja") }
        check(ConversationSearch.find(Array(repeating: many, count: 41), "aguja").count == 200, "search: at most 200 results, not 201")
        check(ChatModel.partialTag(at: "hola <thi") == 4 && ChatModel.partialTag(at: "fin </th") == 4
              && ChatModel.partialTag(at: "a < b") == 0 && ChatModel.partialTag(at: "listo") == 0,
              "<think>: the start of a tag cut at the end of a piece waits for the next one")
        let sjis = Data([0x93, 0xFA, 0x96, 0x7B, 0x8C, 0xEA])   // 日本語 in Shift_JIS
        check(ChatModel.text(of: sjis) == "日本語", "attachments: a Shift_JIS file is read in its own encoding")
        check(ChatModel.text(of: Data([0xEF, 0xBB, 0xBF, 0x61])) == "a" && ChatModel.text(of: Data([0xFF, 0xFE, 0x61, 0x00])) == "a",
              "attachments: byte order marks of UTF-8 and UTF-16")
        check(ChatModel.text(of: Data("cami\u{F3}n".utf8)) == "camión", "attachments: UTF-8 stays UTF-8")
        check(ChatModel.maxAttachmentBytes == 2 * 1024 * 1024, "attachments: at most 2 MB per file")
        check(MarkdownExport.render(c, language: "ja", zone: TimeZone(identifier: "UTC")!, version: "9.9.9").contains("## ユーザー\n"),
              "export: headings in Japanese")
        let md = MarkdownExport.render(c, language: "en", zone: TimeZone(identifier: "UTC")!, version: "9.9.9")
        check(md.hasPrefix("# Viaje en camión: notas/ideas\n"), "export: the title is the heading")
        check(md.contains("## User\n") && md.contains("## Assistant\n") && !md.contains("camion en un aviso"), "export: one heading per turn, no app notes")
        check(md.contains("`````text\nx ```` y\n`````"), "export: an attachment in a fence longer than any inside it")
        check(md.contains("let x = 1\n```\n"), "export: a code block left open is closed")
        check(md.contains("_qwen3:8b · 12.3 tok/s · 2.5 s_") && md.contains("- Model: qwen3:8b"), "export: model and speed")
        check(md.contains("<summary>Reasoning</summary>") && md.hasSuffix("\n"), "export: reasoning folded, final line break")
        check(MarkdownExport.fileName(c) == "Viaje en camión- notas-ideas.md", "export: file name without / or : (\(MarkdownExport.fileName(c)))")
        for (what, ok) in SelfUpdate.selfTest() { check(ok, what) }
    }

    static func run() async -> Bool {
        let m = ChatModel.shared
        var failures = 0
        func check(_ ok: Bool, _ what: String) {
            say((ok ? "PASS  " : "FAIL  ") + what)
            if !ok { failures += 1 }
        }

        let args = CommandLine.arguments

        // First the parts that need no Ollama: the search, the export and the update's pure functions.
        offlineChecks(check)
        if args.contains("--offline") { return failures == 0 }

        guard args.contains("--memory-folder") else {
            say("FAIL  --self-test needs --memory-folder <temporary folder>")
            return false
        }
        // Never write test memories into a folder the user really uses.
        let folder = MemoryStore.folder.standardizedFileURL.path
        let library = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var inUse = [library.appendingPathComponent("Citadel/memories").standardizedFileURL.path]
        if let saved = UserDefaults.standard.string(forKey: "memoryFolder") {
            inUse.append(URL(fileURLWithPath: (saved as NSString).expandingTildeInPath).standardizedFileURL.path)
        }
        guard !inUse.contains(folder) else {
            say("FAIL  refusing to test against a memory folder in use: \(folder)")
            return false
        }
        say("memory folder: \(folder)")
        let savedReason = m.reason

        await m.refreshStatus()
        check(m.reachable == true, "Ollama reachable")
        say("      models: \(m.models.joined(separator: ", "))")
        check(m.models.contains(AppInfo.defaultModel), "default model \(AppInfo.defaultModel) installed")
        if m.models.contains(AppInfo.defaultModel) { m.selectedModel = AppInfo.defaultModel }
        let system = ChatModel.systemPrompt(for: Conversation())
        check(system.hasPrefix("## How to answer (every reply)"), "system message starts with the rules file")

        // 1. Reason off
        m.reason = false
        m.composer = "What is 17 times 23? Reply with only the number."
        m.send()
        check(m.isGenerating, "stream started (Reason off)")
        _ = await waitWhile(300) { m.isGenerating }
        if let a = m.current?.messages.last(where: { $0.role == .assistant }) {
            say("      answer: \(a.content.trimmed.prefix(200))")
            say(String(format: "      %.1f tok/s, %.1f s, thinking chars: %d", a.stats?.tokensPerSecond ?? 0, a.stats?.seconds ?? 0, a.thinking.count))
            check(!a.content.isEmpty && a.thinking.isEmpty, "answer streamed with no thinking (Reason off)")
            check(a.content.contains("391"), "answer is correct (391)")
        } else { check(false, "answer streamed (Reason off)") }

        // 2. Reason on
        m.reason = true
        m.composer = "How many times does the letter r appear in the word strawberry? Reply with only the number."
        m.send()
        _ = await waitWhile(400) { m.isGenerating }
        if let a = m.current?.messages.last(where: { $0.role == .assistant }) {
            say("      answer: \(a.content.trimmed.prefix(200))")
            say(String(format: "      %.1f tok/s, %.1f s, thinking chars: %d", a.stats?.tokensPerSecond ?? 0, a.stats?.seconds ?? 0, a.thinking.count))
            check(!a.thinking.isEmpty, "thinking streamed (Reason on)")
            check(!a.content.isEmpty, "answer streamed after thinking (Reason on)")
        } else { check(false, "answer streamed (Reason on)") }

        // 3. Stop closes the stream
        m.reason = false
        m.composer = "Write a long story of about 800 words about a lighthouse keeper."
        m.send()
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        m.stop()
        let stopped = await waitWhile(15) { m.isGenerating }
        let last = m.current?.messages.last(where: { $0.role == .assistant })
        check(stopped && last?.stopped == true, "Stop cancels the stream (\(last?.content.count ?? 0) chars kept)")

        // 4. /save writes a memory and its index line
        m.composer = "/save"
        m.send()
        _ = await waitWhile(300) { m.isDraftingMemory }
        if let draft = m.memoryDraft {
            say("      draft file: \(draft.file)")
            say("      draft index line: \(draft.indexLine)")
            let lines = draft.content.components(separatedBy: "\n")
            check(lines.count >= 2 && lines[0].hasPrefix("# ") && lines[1].hasPrefix("_Updated: ") && lines[1].contains("| Model: \(m.selectedModel)_"),
                  "memory starts with title and _Updated line")
            let saved = m.confirmMemory(draft)
            let url = MemoryStore.folder.appendingPathComponent(draft.file)
            let onDisk = FileManager.default.fileExists(atPath: url.path)
            let raw = (try? Data(contentsOf: url)) ?? Data()
            let noBOM = !(raw.count >= 3 && raw[0] == 0xEF && raw[1] == 0xBB && raw[2] == 0xBF)
            let index = MemoryStore.indexText()
            check(saved && onDisk && noBOM, "memory file written (UTF-8, no BOM): \(url.path)")
            check(index.contains("`\(draft.file)` — "), "index line written in _index.md")
            say("      _index.md:\n" + index.components(separatedBy: "\n").map { "        " + $0 }.joined(separator: "\n"))

            // 5. /mem loads it back
            m.newConversation()
            m.composer = "/mem " + draft.indexLine
            m.send()
            let chip = m.current?.messages.last
            check(chip?.role == .memory && chip?.memoryFile == draft.file, "/mem loads \(draft.file)")
            check(ChatModel.systemPrompt(for: m.current ?? Conversation()).contains("### \(draft.file)"),
                  "loaded memory is in the system message")
        } else {
            check(false, "/save produced a draft")
        }
        m.composer = "/mem zzzz qqqq"
        m.send()
        check(m.current?.messages.last?.role == .notice, "/mem with no match says so")

        m.reason = savedReason

        // Theme: the twelve icons are in the app, and the appearance follows the choice.
        let theme = ThemePrefs.shared
        check(Accent.all.allSatisfy { $0.icon != nil } && Accent.all.count == 12, "twelve theme colours, each with its icon")
        let (savedLook, savedAccent) = (theme.appearance, theme.accent)
        theme.appearance = "light"
        let light = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .aqua
        theme.appearance = "dark"
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        check(light && dark, "light and dark appearance applied")
        theme.accent = "purple"
        check(theme.dockIcon == "purple" && NSApp.applicationIconImage != nil,
              "the Dock icon takes the chosen colour")
        theme.appearance = savedLook; theme.accent = savedAccent

        say(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
        return failures == 0
    }
}
