// Conversations.swift
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

/// A text file attached to a user message.
struct Attachment: Codable, Hashable {
    var name: String
    var text: String
}

/// Speed and time of a finished answer.
struct AnswerStats: Codable, Hashable {
    var model: String
    var tokens: Int
    var tokensPerSecond: Double
    var seconds: Double
}

enum Role: String, Codable {
    case user, assistant
    /// A memory file loaded with /mem; sent to the model as context.
    case memory
    /// A note from the app (errors, "nothing matched"); never sent to the model.
    case notice
}

struct ChatMessage: Codable, Identifiable, Hashable {
    var id = UUID()
    var role: Role
    var content: String
    var thinking: String = ""
    var attachments: [Attachment] = []
    var memoryFile: String? = nil
    var stats: AnswerStats? = nil
    var reasoned: Bool = false
    var stopped: Bool = false
    var date = Date()

    init(role: Role, content: String, attachments: [Attachment] = []) {
        self.role = role
        self.content = content
        self.attachments = attachments
    }

    /// Missing keys fall back to their defaults, so files from other versions still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        role = try c.decode(Role.self, forKey: .role)
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        thinking = try c.decodeIfPresent(String.self, forKey: .thinking) ?? ""
        attachments = try c.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
        memoryFile = try c.decodeIfPresent(String.self, forKey: .memoryFile)
        stats = try c.decodeIfPresent(AnswerStats.self, forKey: .stats)
        reasoned = try c.decodeIfPresent(Bool.self, forKey: .reasoned) ?? false
        stopped = try c.decodeIfPresent(Bool.self, forKey: .stopped) ?? false
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? Date()
    }
}

struct Conversation: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String = ""
    var created = Date()
    var updated = Date()
    var messages: [ChatMessage] = []

    var displayTitle: String {
        title.isEmpty ? tr("Conversación nueva", "New conversation") : title
    }

    /// Title = the first user message, trimmed to one short line.
    static func title(from text: String) -> String {
        let oneLine = text.trimmed.components(separatedBy: .newlines).first?.trimmed ?? ""
        let collapsed = oneLine.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
        return collapsed.count > 60 ? String(collapsed.prefix(60)).trimmed + "…" : collapsed
    }
}

/// Stores each conversation as one JSON file.
enum ConversationStore {
    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    static func url(for id: UUID) -> URL {
        Paths.conversations.appendingPathComponent("\(id.uuidString).json")
    }

    static func loadAll() -> [Conversation] {
        Paths.ensure(Paths.conversations)
        let files = (try? FileManager.default.contentsOfDirectory(at: Paths.conversations, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(Conversation.self, from: Data(contentsOf: $0)) }
            .sorted { $0.updated > $1.updated }
    }

    static func save(_ c: Conversation) {
        Paths.ensure(Paths.conversations)
        if let data = try? encoder.encode(c) {
            try? data.write(to: url(for: c.id), options: .atomic)
        }
    }

    static func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: url(for: id))
    }
}
