//
//  SearchExport.swift
//  Citadel: local AI chat for macOS.
//
//  Copyright (C) 2026 Gabriel Castiglia. Licensed under the GNU GPL, version 2 only.
//  Date: November 20, 2026
//  SPDX-License-Identifier: GPL-2.0-only
//
//  Search in the text of every saved conversation, and the export of one conversation to Markdown, as in
//  Citadel 1.3.0 for Windows (Search.cs and Export.cs there).
//

import AppKit
import Foundation

/// One place where the searched text appears: a message of a conversation, with the text around it.
struct SearchHit: Identifiable, Hashable {
    let conversation: UUID
    let title: String
    let message: UUID
    let date: Date
    /// The fragment shown in the results: before + match + after, on one line.
    let before: String, match: String, after: String
    var id: String { "\(message)-\(before.count)" }
}

/// Upper and lower case, accents and runs of spaces or line breaks do not matter: "camion" finds "Camión",
/// "dos  palabras" finds "dos\npalabras". The fragment keeps the original text, so the match is shown as written.
enum ConversationSearch {
    /// Shortest query searched in the messages; shorter ones would match almost everything.
    static let minLength = 2

    /// The text folded (lowercase, no accents, every run of white space one space) and, for each Character of the
    /// result, the index of the original Character it came from.
    static func foldWithMap(_ text: String) -> (folded: [Character], map: [String.Index]) {
        var out: [Character] = [], map: [String.Index] = []
        out.reserveCapacity(text.count)
        var space = false
        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            if c.isWhitespace {
                if !space { out.append(" "); map.append(i); space = true }
            } else {
                space = false
                let f = c.isASCII ? String(c).lowercased() : String(c).folded
                for x in f { out.append(x); map.append(i) }
            }
            i = text.index(after: i)
        }
        return (out, map)
    }

    static func foldQuery(_ q: String) -> [Character] { foldWithMap(q.trimmed).folded }

    private static func firstIndex(of q: [Character], in s: [Character]) -> Int? {
        guard !q.isEmpty, s.count >= q.count else { return nil }
        let first = q[0]
        var i = 0
        let last = s.count - q.count
        while i <= last {
            if s[i] == first {
                var k = 1
                while k < q.count && s[i + k] == q[k] { k += 1 }
                if k == q.count { return i }
            }
            i += 1
        }
        return nil
    }

    /// Every message (of the user or an answer) that contains the query, in the order of the list given (most recent
    /// conversation first) and, inside a conversation, in the order of the messages. At most `perConversation` hits
    /// per conversation and `max` in all.
    static func find(_ conversations: [Conversation], _ query: String, perConversation: Int = 5, max: Int = 200) -> [SearchHit] {
        var hits: [SearchHit] = []
        let q = foldQuery(query)
        guard q.count >= minLength else { return hits }
        for c in conversations {
            var inThis = 0
            for m in c.messages where (m.role == .user || m.role == .assistant) && !m.content.isEmpty {
                let (folded, map) = foldWithMap(m.content)
                guard let at = firstIndex(of: q, in: folded) else { continue }
                let start = map[at]
                let end = m.content.index(after: map[at + q.count - 1])
                hits.append(fragment(c, m, start ..< end))
                inThis += 1
                if inThis >= perConversation { break }
                if hits.count >= max { return hits }
            }
        }
        return hits
    }

    /// The match with some words before and after it, on one line, cut at spaces.
    private static func fragment(_ c: Conversation, _ m: ChatMessage, _ r: Range<String.Index>,
                                 before: Int = 40, after: Int = 90) -> SearchHit {
        let text = m.content
        var from = text.index(r.lowerBound, offsetBy: -before, limitedBy: text.startIndex) ?? text.startIndex
        if from > text.startIndex, let sp = text[from ..< r.lowerBound].firstIndex(where: { $0.isWhitespace }) {
            from = text.index(after: sp)
        }
        var to = text.index(r.upperBound, offsetBy: after, limitedBy: text.endIndex) ?? text.endIndex
        if to < text.endIndex, let sp = text[r.upperBound ..< to].lastIndex(where: { $0.isWhitespace }), sp > r.upperBound { to = sp }
        func line(_ s: Substring) -> String { s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
        var pre = line(text[from ..< r.lowerBound]), post = line(text[r.upperBound ..< to])
        if !pre.isEmpty, r.lowerBound > text.startIndex, text[text.index(before: r.lowerBound)].isWhitespace { pre += " " }
        if !post.isEmpty, text[r.upperBound].isWhitespace { post = " " + post }
        return SearchHit(conversation: c.id, title: c.displayTitle, message: m.id, date: m.date,
                         before: (from > text.startIndex ? "…" : "") + pre, match: line(text[r]),
                         after: post + (to < text.endIndex ? "…" : ""))
    }
}

/// A conversation as a Markdown file: title, date, model, and each turn under its own heading.
enum MarkdownExport {
    /// The Markdown text, with "\n" line endings and a final line break.
    static func render(_ c: Conversation, spanish es: Bool, zone: TimeZone = .current, version: String = AppInfo.version) -> String {
        func T(_ s: String, _ e: String) -> String { es ? s : e }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        var md = ""
        func line(_ s: String = "") { md += s + "\n" }

        let title = c.title.isEmpty ? T("Conversación nueva", "New conversation") : c.title
        line("# " + title.replacingOccurrences(of: "\n", with: " ").trimmed)
        line()
        var models: [String] = []
        for m in c.messages where m.role == .assistant {
            if let s = m.stats?.model, !s.isEmpty, !models.contains(s) { models.append(s) }
        }
        line("- \(T("Fecha", "Date")): \(f.string(from: c.created))")
        if c.updated.timeIntervalSince(c.created) >= 60 { line("- \(T("Última actividad", "Last activity")): \(f.string(from: c.updated))") }
        line("- \(models.count > 1 ? T("Modelos", "Models") : T("Modelo", "Model")): \(models.isEmpty ? "-" : models.joined(separator: ", "))")
        line("- \(T("Exportada con", "Exported with")) Citadel \(version)")

        for m in c.messages {
            switch m.role {
            case .user:
                line(); line("## " + T("Usuario", "User")); line()
                if !m.content.isEmpty { line(normalize(m.content)) }
                for (i, a) in m.attachments.enumerated() {
                    if !m.content.isEmpty || i > 0 { line() }
                    md += details(T("Adjunto: ", "Attachment: ") + a.name, a.text)
                }
            case .assistant:
                line(); line("## " + T("Asistente", "Assistant")); line()
                if !m.thinking.trimmed.isEmpty {
                    md += details(T("Razonamiento", "Reasoning"), m.thinking)
                    line()
                }
                if !m.content.isEmpty { line(closeFences(normalize(m.content))) }
                var notes: [String] = []
                if let s = m.stats {
                    if !s.model.isEmpty { notes.append(s.model) }
                    if s.tokensPerSecond > 0 { notes.append(String(format: "%.1f tok/s", s.tokensPerSecond)) }
                    if s.seconds > 0 { notes.append(String(format: "%.1f s", s.seconds)) }
                }
                if m.stopped { notes.append(T("detenida", "stopped")) }
                if !notes.isEmpty {
                    if !m.content.isEmpty { line() }
                    line("_" + notes.joined(separator: " · ") + "_")
                }
            case .memory:
                line()
                line("> \(T("Memoria cargada", "Memory loaded")): `\(m.memoryFile ?? "memory.md")`")
            case .notice:
                break
            }
        }
        return md
    }

    /// "\n" line endings and no line breaks at the start or the end.
    static func normalize(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        while t.hasPrefix("\n") { t.removeFirst() }
        while let l = t.last, l.isWhitespace { t.removeLast() }
        return t
    }

    /// Text shown folded: a <details> block with the text in a fence longer than any inside it.
    static func details(_ summary: String, _ text: String) -> String {
        var longest = 0, run = 0
        for ch in text { run = ch == "`" ? run + 1 : 0; longest = Swift.max(longest, run) }
        let fence = String(repeating: "`", count: Swift.max(3, longest + 1))
        let esc = summary.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        return "<details>\n<summary>\(esc)</summary>\n\n\(fence)text\n\(normalize(text))\n\(fence)\n\n</details>\n"
    }

    /// Adds the closing fence of a code block left open (an answer stopped while writing code).
    static func closeFences(_ text: String) -> String {
        var open: String?
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let l = raw.drop(while: { $0 == " " || $0 == "\t" })
            guard let first = l.first, first == "`" || first == "~" else { continue }
            let n = l.prefix(while: { $0 == first }).count
            guard n >= 3 else { continue }
            let marker = String(l.prefix(n))
            if open == nil { open = marker }
            else if let o = open, marker.first == o.first, marker.count >= o.count,
                    l.dropFirst(n).trimmingCharacters(in: .whitespaces).isEmpty { open = nil }
        }
        return open.map { text + "\n" + $0 } ?? text
    }

    /// A file name made from the title: no "/" or ":" (which macOS forbids or shows as "/"), at most 80 characters.
    static func fileName(_ c: Conversation) -> String {
        let cleaned = String(c.title.map { "/:\\\n\r\t".contains($0) || $0.asciiValue.map { $0 < 32 } == true ? "-" : $0 })
        var name = cleaned.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: ". -"))
        if name.count > 80 { name = String(name.prefix(80)).trimmingCharacters(in: CharacterSet(charactersIn: ". ")) }
        return (name.isEmpty ? "Citadel" : name) + ".md"
    }

    static let openAfterKey = "openAfterExport"

    /// Asks where to save the conversation and writes it; with "Open after exporting" on, opens it.
    @MainActor
    static func export(_ c: Conversation) {
        let panel = NSSavePanel()
        panel.title = tr("Exportar a Markdown", "Export to Markdown")
        panel.nameFieldStringValue = fileName(c)
        panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(render(c, spanish: L10n.shared.isSpanish).utf8).write(to: url, options: .atomic)
            if UserDefaults.standard.bool(forKey: openAfterKey) { NSWorkspace.shared.open(url) }
            ChatModel.shared.toast = tr("Exportada: \(url.lastPathComponent)", "Exported: \(url.lastPathComponent)")
        } catch {
            ChatModel.shared.toast = tr("No se pudo exportar: \(error.localizedDescription)", "Could not export: \(error.localizedDescription)")
        }
    }
}
