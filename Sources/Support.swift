// Support.swift
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
import SwiftUI

// MARK: - App constants

enum AppInfo {
    static let name = "Citadel"
    /// Set once, in scripts/compilar.sh, and read back from Info.plist.
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    static let author = "Gabriel Castiglia"
    static let bundleID = "io.github.gabriel-castiglia.citadel"
    static let defaultModel = "qwen3-8b-32k:latest"
    static let ollamaBase = URL(string: "http://127.0.0.1:11434")!
}

// MARK: - Interface language

/// Holds the interface language ("en" or "es"). English on first launch.
final class L10n: ObservableObject {
    static let shared = L10n()

    @Published var language: String {
        didSet { UserDefaults.standard.set(language, forKey: "language") }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: "language")
        language = (saved == "es") ? "es" : "en"
    }

    var isSpanish: Bool { language == "es" }
}

/// Returns the Spanish or English text for the current interface language.
func tr(_ es: String, _ en: String) -> String {
    L10n.shared.isSpanish ? es : en
}

// MARK: - Paths

enum Paths {
    /// `~/Library/Application Support/Citadel`, or the folder given with `--data-folder`
    /// (used for tests, so they never touch the real conversations).
    static var appSupport: URL {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--data-folder"), i + 1 < args.count {
            return URL(fileURLWithPath: (args[i + 1] as NSString).expandingTildeInPath, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Citadel", isDirectory: true)
    }

    static var conversations: URL {
        appSupport.appendingPathComponent("conversations", isDirectory: true)
    }

    static var rules: URL {
        appSupport.appendingPathComponent("rules.md")
    }

    static var defaultMemoryFolder: URL {
        appSupport.appendingPathComponent("memories", isDirectory: true)
    }

    static func ensure(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}

// MARK: - Rules file

enum Rules {
    static let defaultText = """
    ## How to answer (every reply)
    1. Answer in the user's language. Answer exactly what was asked. If the user asks for only the result, give only the result: no preamble, no explanation, no closing offer.
    2. Do not invent. If you do not know, if it happened after your training data, if it is private data you cannot access, or if a book, person or event may not exist, say that you do not know ("No lo sé" in Spanish) and why, in one sentence. Never make up details.
    3. Check the premise. If the question assumes something false, say it is false first.
    4. Exact formats: when asked for only JSON, only a list, or exactly N items, output exactly that and nothing else.
    5. Code: put it in one fenced Markdown code block (```python ... ```) with the complete function; no input() and no example calls unless asked.
    6. Translation: copy text between backticks, paths, commands, numbers and names unchanged; reply only with the translation.
    7. You run locally on this Mac through Ollama; nothing the user writes leaves the computer.

    """

    /// Creates the rules file with the default content on first run.
    static func ensureExists() {
        Paths.ensure(Paths.appSupport)
        if !FileManager.default.fileExists(atPath: Paths.rules.path) {
            try? Data(defaultText.utf8).write(to: Paths.rules, options: .atomic)
        }
    }

    static func load() -> String {
        ensureExists()
        return (try? String(contentsOf: Paths.rules, encoding: .utf8)) ?? defaultText
    }

    static func save(_ text: String) throws {
        Paths.ensure(Paths.appSupport)
        try Data(text.utf8).write(to: Paths.rules, options: .atomic)
    }
}

// MARK: - Text helpers

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Lowercased, without accents or other diacritics.
    var folded: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
    }

    /// The path with the home folder shown as `~`.
    var tildePath: String { (self as NSString).abbreviatingWithTildeInPath }

    /// Words of letters and digits, folded, for simple matching.
    var words: [String] {
        folded.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }
}

func copyToPasteboard(_ text: String) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(text, forType: .string)
}

/// A tiny observable flag, used where SwiftUI's @State would normally go.
final class Flag: ObservableObject {
    @Published var on: Bool
    init(_ on: Bool = false) { self.on = on }
}

/// A tiny observable text box, used where SwiftUI's @State would normally go.
final class TextBox: ObservableObject {
    @Published var text: String
    init(_ text: String = "") { self.text = text }
}

// MARK: - AppKit bridges

/// Translucent background (sidebar material) behind SwiftUI content.
struct SidebarBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .followsWindowActiveState
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blending
    }
}
