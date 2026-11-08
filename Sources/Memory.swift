// Memory.swift
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

import Foundation

/// One line of the memory index: `` `file.md` `` — topic.
struct MemoryEntry: Identifiable, Hashable {
    var file: String
    var topic: String
    var id: String { file }
}

/// A memory proposed by the model, waiting for the user's confirmation.
struct MemoryDraft {
    var file: String
    var indexLine: String
    var content: String
}

/// Reads and writes the memory folder. The app writes memories, never the model.
enum MemoryStore {
    static let indexName = "_index.md"

    /// The folder in use: a `--memory-folder` argument wins, then Settings, then the default.
    static var folder: URL {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--memory-folder"), i + 1 < args.count {
            return URL(fileURLWithPath: (args[i + 1] as NSString).expandingTildeInPath, isDirectory: true)
        }
        if let saved = UserDefaults.standard.string(forKey: "memoryFolder"), !saved.isEmpty {
            return URL(fileURLWithPath: (saved as NSString).expandingTildeInPath, isDirectory: true)
        }
        return Paths.defaultMemoryFolder
    }

    static var indexURL: URL { folder.appendingPathComponent(indexName) }

    static func indexText() -> String {
        (try? String(contentsOf: indexURL, encoding: .utf8)) ?? ""
    }

    /// Parses every index line that names a file between backticks.
    static func entries() -> [MemoryEntry] {
        var result: [MemoryEntry] = []
        for line in indexText().components(separatedBy: .newlines) {
            guard let (file, topic) = parseIndexLine(line) else { continue }
            if !result.contains(where: { $0.file == file }) {
                result.append(MemoryEntry(file: file, topic: topic))
            }
        }
        return result
    }

    static func parseIndexLine(_ line: String) -> (String, String)? {
        guard let open = line.firstIndex(of: "`") else { return nil }
        let rest = line[line.index(after: open)...]
        guard let close = rest.firstIndex(of: "`") else { return nil }
        let file = String(rest[..<close]).trimmed
        guard file.lowercased().hasSuffix(".md"), !file.contains("/") else { return nil }
        var topic = String(rest[rest.index(after: close)...]).trimmed
        for sep in ["—", "–", "-", ":"] where topic.hasPrefix(sep) {
            topic = String(topic.dropFirst(sep.count)).trimmed
            break
        }
        return (file, topic)
    }

    /// Every memory: the index entries plus any .md file in the folder that the index misses.
    static func allMemories() -> [MemoryEntry] {
        var list = entries()
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for f in files.sorted() where f.lowercased().hasSuffix(".md") && f != indexName {
            if !list.contains(where: { $0.file == f }) { list.append(MemoryEntry(file: f, topic: "")) }
        }
        return list
    }

    private static let stopWords: Set<String> = [
        "the", "and", "for", "with", "about", "from", "that", "this", "what", "las", "los", "del",
        "que", "con", "por", "para", "una", "uno", "sobre", "como", "mem", "md",
    ]

    /// Best index entry for a topic by simple word overlap, accents ignored.
    static func bestMatch(for topic: String) -> MemoryEntry? {
        let query = Set(topic.words.filter { $0.count >= 2 && !stopWords.contains($0) })
        guard !query.isEmpty else { return nil }
        var best: (MemoryEntry, Int)?
        for entry in entries() {
            let fileWords = Set(entry.file.replacingOccurrences(of: ".md", with: "").words)
            let topicWords = Set(entry.topic.words)
            var score = query.intersection(topicWords).count * 2 + query.intersection(fileWords).count * 2
            // Partial credit for prefixes (plural/singular, short forms).
            for q in query where q.count >= 4 {
                if topicWords.union(fileWords).contains(where: { $0 != q && ($0.hasPrefix(q) || q.hasPrefix($0)) && $0.count >= 4 }) {
                    score += 1
                }
            }
            if score > 0, score > (best?.1 ?? 0) { best = (entry, score) }
        }
        return best?.0
    }

    static func read(_ file: String) -> String? {
        try? String(contentsOf: folder.appendingPathComponent(file), encoding: .utf8)
    }

    static func exists(_ file: String) -> Bool {
        FileManager.default.fileExists(atPath: folder.appendingPathComponent(file).path)
    }

    /// Lowercase kebab-case file name ending in .md.
    static func sanitizeFileName(_ raw: String) -> String {
        var name = raw.trimmed
        if name.lowercased().hasSuffix(".md") { name = String(name.dropLast(3)) }
        name = (name as NSString).lastPathComponent
        let words = name.folded.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        var slug = words.joined(separator: "-")
        if slug.count > 60 { slug = String(slug.prefix(60)).trimmingCharacters(in: CharacterSet(charactersIn: "-")) }
        if slug.isEmpty { slug = "memory" }
        return slug + ".md"
    }

    /// Makes sure line 2 is `_Updated: YYYY-MM-DD | Model: <model>_` after a `# ` title.
    static func normalizeContent(_ raw: String, title: String, model: String, date: Date = Date()) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        let stamp = "_Updated: \(df.string(from: date)) | Model: \(model)_"
        var lines = raw.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        lines.removeAll { $0.trimmed.hasPrefix("_Updated:") }
        while let first = lines.first, first.trimmed.isEmpty { lines.removeFirst() }
        var titleLine = "# \(title)"
        if let first = lines.first, first.hasPrefix("# ") {
            titleLine = first.trimmed
            lines.removeFirst()
        }
        while let first = lines.first, first.trimmed.isEmpty { lines.removeFirst() }
        var out = [titleLine, stamp, ""] + lines
        while let last = out.last, last.trimmed.isEmpty { out.removeLast() }
        return out.joined(separator: "\n") + "\n"
    }

    /// Writes the memory file and its index line, then verifies both on disk.
    /// Returns the URL of the written file.
    @discardableResult
    static func save(_ draft: MemoryDraft) throws -> URL {
        let file = sanitizeFileName(draft.file)
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(file)
        // String.data(using: .utf8) never writes a byte order mark.
        try Data(draft.content.utf8).write(to: url, options: .atomic)

        let topic = draft.indexLine.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "`\(file)`", with: "").trimmed
        let newLine = "`\(file)` — \(topic)"
        var lines = indexText().replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        if let i = lines.firstIndex(where: { parseIndexLine($0)?.0 == file }) {
            lines[i] = newLine
        } else {
            lines.append(newLine)
        }
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: indexURL, options: .atomic)

        // Confirm only what is really on disk.
        guard fm.fileExists(atPath: url.path),
              let back = try? String(contentsOf: url, encoding: .utf8), back == draft.content,
              entries().contains(where: { $0.file == file })
        else {
            throw NSError(domain: "Citadel", code: 1, userInfo: [NSLocalizedDescriptionKey:
                tr("No se pudo verificar la memoria guardada en el disco.", "Could not verify the saved memory on disk.")])
        }
        return url
    }

    /// Deletes a memory file and its index line.
    static func delete(_ file: String) throws {
        let url = folder.appendingPathComponent(file)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        var lines = indexText().components(separatedBy: "\n")
        let before = lines.count
        lines.removeAll { parseIndexLine($0)?.0 == file }
        if lines.count != before {
            try Data(lines.joined(separator: "\n").utf8).write(to: indexURL, options: .atomic)
        }
    }

    /// Asks the model (Reason off) to write a memory from the conversation, as JSON.
    static func draft(from transcript: String, model: String, client: OllamaClient = OllamaClient()) async throws -> MemoryDraft {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        let today = df.string(from: Date())
        let existing = entries().map { "- `\($0.file)` — \($0.topic)" }.joined(separator: "\n")

        let system = """
        You write one memory file for a local memory folder, from the conversation the user gives you.
        Write it in the same language the user writes in. Keep only facts worth remembering in future conversations: decisions, preferences, data, results and open items. Never invent anything that is not in the conversation.
        The memory is Markdown: line 1 is a "# " title; line 2 is exactly `_Updated: \(today) | Model: \(model)_`; then the content, at most about 50 lines.
        Reply with ONLY a JSON object with three string keys:
        "file": a short kebab-case file name ending in .md,
        "index_line": one line that describes the topic in the user's words (without the file name),
        "content": the full Markdown of the memory.
        \(existing.isEmpty ? "" : "If one of these existing memories covers the same topic, reuse its file name:\n" + existing)
        """
        let messages = [
            WireMessage(role: "system", content: system),
            WireMessage(role: "user", content: "Conversation:\n\n" + transcript),
        ]
        let text = try await client.complete(model: model, messages: messages, think: false,
                                             numPredict: 3000, jsonFormat: true)
        guard let obj = parseJSONObject(text) else {
            throw NSError(domain: "Citadel", code: 2, userInfo: [NSLocalizedDescriptionKey:
                tr("El modelo no devolvió un JSON válido.", "The model did not return valid JSON.")])
        }
        let file = sanitizeFileName((obj["file"] as? String) ?? "memory")
        var indexLine = ((obj["index_line"] as? String) ?? "").trimmed
        let rawContent = (obj["content"] as? String) ?? ""
        if indexLine.isEmpty { indexLine = file.replacingOccurrences(of: ".md", with: "").replacingOccurrences(of: "-", with: " ") }
        let content = normalizeContent(rawContent, title: indexLine, model: model)
        return MemoryDraft(file: file, indexLine: indexLine, content: content)
    }

    static func parseJSONObject(_ text: String) -> [String: Any]? {
        if let d = text.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            return o
        }
        guard let a = text.firstIndex(of: "{"), let b = text.lastIndex(of: "}"), a < b else { return nil }
        let slice = String(text[a...b])
        guard let d = slice.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
    }
}
