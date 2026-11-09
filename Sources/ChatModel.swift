// ChatModel.swift
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
import SwiftUI

/// The state of the main window: conversations, composer, model and Ollama status.
@MainActor
final class ChatModel: ObservableObject {
    static let shared = ChatModel()

    // Conversations
    @Published var conversations: [Conversation] = []
    @Published var selectedID: UUID?
    @Published var search = ""

    // Composer
    @Published var composer = ""
    @Published var attachments: [Attachment] = []
    @Published var reason: Bool {
        didSet { UserDefaults.standard.set(reason, forKey: "reason") }
    }

    // Model and status
    @Published var models: [String] = []
    @Published var selectedModel: String {
        didSet { UserDefaults.standard.set(selectedModel, forKey: "model") }
    }
    /// Whether each installed model can reason, from its Ollama capabilities.
    @Published var reasoningModels: [String: Bool] = [:]
    /// Reason applies only to models that can reason; unknown models are given the benefit of the doubt.
    var canReason: Bool { reasoningModels[selectedModel] ?? true }
    @Published var reachable: Bool? = nil
    /// Why the last connection failed (SSH errors included), for the status line.
    @Published var connectionError: String?
    @Published var loadedModels: [String] = []
    @Published var isGenerating = false
    @Published var receivedFirstToken = false
    @Published var receivingThinking = false
    @Published var elapsed: Double = 0
    @Published var lastStats: AnswerStats?

    // Memories
    @Published var isDraftingMemory = false
    @Published var memoryDraft: MemoryDraft?
    @Published var draftReplaces = false
    @Published var toast: String?

    /// False in self-test mode: nothing is written to the conversations folder.
    var persist = true

    private let client = OllamaClient()
    private var streamTask: Task<Void, Never>?
    private var draftTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var startDate = Date()

    init() {
        reason = UserDefaults.standard.bool(forKey: "reason")
        selectedModel = UserDefaults.standard.string(forKey: "model") ?? AppInfo.defaultModel
    }

    // MARK: Lifecycle

    func start(loadSaved: Bool = true) {
        Rules.ensureExists()
        if loadSaved { conversations = ConversationStore.loadAll() }
        selectedID = conversations.first?.id
        if selectedID == nil { newConversation() }
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshStatus()
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
    }

    func refreshStatus() async {
        do {
            let list = try await client.listModels()
            models = list
            reachable = true
            if !list.isEmpty, !list.contains(selectedModel) {
                selectedModel = list.contains(AppInfo.defaultModel) ? AppInfo.defaultModel : list[0]
            }
            for name in list where reasoningModels[name] == nil {
                if let caps = try? await client.capabilities(of: name) { reasoningModels[name] = caps.contains("thinking") }
            }
            loadedModels = (try? await client.loadedModels()) ?? []
            connectionError = nil
        } catch {
            reachable = false
            connectionError = error.localizedDescription
            loadedModels = []
        }
    }

    var modelIsLoaded: Bool { loadedModels.contains(selectedModel) }

    // MARK: Conversations

    var current: Conversation? {
        guard let id = selectedID else { return nil }
        return conversations.first { $0.id == id }
    }

    var filteredConversations: [Conversation] {
        let q = search.trimmed.folded
        let visible = conversations.filter { !$0.messages.isEmpty || $0.id == selectedID }
        guard !q.isEmpty else { return visible }
        return visible.filter { $0.displayTitle.folded.contains(q) }
    }

    func newConversation() {
        if let c = current, c.messages.isEmpty { return }
        if let empty = conversations.first(where: { $0.messages.isEmpty }) {
            selectedID = empty.id
            return
        }
        let c = Conversation()
        conversations.insert(c, at: 0)
        selectedID = c.id
    }

    func select(_ id: UUID) {
        guard id != selectedID else { return }
        selectedID = id
        // Drop an untouched empty conversation when leaving it.
        conversations.removeAll { $0.messages.isEmpty && $0.id != id }
    }

    func rename(_ id: UUID, to title: String) {
        mutate(id) { $0.title = title.trimmed }
        save(id)
    }

    func delete(_ id: UUID) {
        if id == selectedID { stop() }
        conversations.removeAll { $0.id == id }
        ConversationStore.delete(id)
        if selectedID == id {
            selectedID = conversations.first?.id
            if selectedID == nil { newConversation() }
        }
    }

    private func mutate(_ id: UUID, _ change: (inout Conversation) -> Void) {
        guard let i = conversations.firstIndex(where: { $0.id == id }) else { return }
        change(&conversations[i])
    }

    private func save(_ id: UUID) {
        guard persist, let c = conversations.first(where: { $0.id == id }), !c.messages.isEmpty else { return }
        ConversationStore.save(c)
    }

    private func append(_ message: ChatMessage, to id: UUID) {
        mutate(id) {
            $0.messages.append(message)
            $0.updated = Date()
        }
    }

    private func notice(_ text: String) {
        guard let id = selectedID else { return }
        append(ChatMessage(role: .notice, content: text), to: id)
        save(id)
    }

    // MARK: Composer

    var canSend: Bool {
        !isGenerating && !isDraftingMemory && (!composer.trimmed.isEmpty || !attachments.isEmpty)
    }

    func attachFile(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        guard ["txt", "md", "markdown", "text"].contains(ext) else {
            toast = tr("Solo se pueden adjuntar archivos .txt o .md.", "Only .txt and .md files can be attached.")
            return
        }
        guard let text = (try? String(contentsOf: url, encoding: .utf8))
            ?? (try? String(contentsOf: url, encoding: .isoLatin1))
        else {
            toast = tr("No se pudo leer el archivo.", "Could not read the file.")
            return
        }
        attachments.append(Attachment(name: url.lastPathComponent, text: text))
    }

    func send() {
        let text = composer.trimmed
        guard canSend, let id = selectedID else { return }

        if text == "/save" || text.hasPrefix("/save ") {
            composer = ""
            startMemoryDraft()
            return
        }
        if text == "/mem" || text.hasPrefix("/mem ") {
            composer = ""
            loadMemory(topic: String(text.dropFirst(4)).trimmed)
            return
        }

        let message = ChatMessage(role: .user, content: text, attachments: attachments)
        composer = ""
        attachments = []
        mutate(id) {
            if $0.title.isEmpty {
                $0.title = Conversation.title(from: text.isEmpty ? (message.attachments.first?.name ?? "") : text)
            }
        }
        append(message, to: id)
        save(id)
        runAnswer(in: id)
    }

    // MARK: Answers

    /// The system message: rules file, memory index and any memory loaded with /mem.
    static func systemPrompt(for conversation: Conversation) -> String {
        var parts = [Rules.load().trimmed]
        let index = MemoryStore.indexText().trimmed
        if !index.isEmpty {
            parts.append("""
            ## Memory index
            These memories exist in the user's memory folder. You cannot open them yourself: the app loads one when the user types /mem <topic>.

            \(index)
            """)
        }
        let loaded = conversation.messages.filter { $0.role == .memory }
        if !loaded.isEmpty {
            var block = "## Loaded memories"
            for m in loaded { block += "\n\n### \(m.memoryFile ?? "memory.md")\n\(m.content.trimmed)" }
            parts.append(block)
        }
        return parts.joined(separator: "\n\n")
    }

    static func wireMessages(for conversation: Conversation) -> [WireMessage] {
        var out = [WireMessage(role: "system", content: systemPrompt(for: conversation))]
        for m in conversation.messages {
            switch m.role {
            case .user:
                var content = m.content
                for a in m.attachments {
                    content += "\n\n--- \(a.name) ---\n\(a.text)\n--- end of \(a.name) ---"
                }
                out.append(WireMessage(role: "user", content: content.trimmed))
            case .assistant:
                if !m.content.isEmpty { out.append(WireMessage(role: "assistant", content: m.content)) }
            case .memory, .notice:
                continue
            }
        }
        return out
    }

    private func runAnswer(in id: UUID) {
        guard let conversation = conversations.first(where: { $0.id == id }) else { return }
        let think = reason && canReason
        let model = selectedModel
        let wire = Self.wireMessages(for: conversation)
        var answer = ChatMessage(role: .assistant, content: "")
        answer.reasoned = think
        let answerID = answer.id
        append(answer, to: id)

        isGenerating = true
        receivedFirstToken = false
        receivingThinking = false
        startDate = Date()
        elapsed = 0

        streamTask = Task { [weak self] in
            guard let self else { return }
            let ticker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    guard let self else { return }
                    self.elapsed = Date().timeIntervalSince(self.startDate)
                }
            }
            defer { ticker.cancel() }

            var inThinkTag = false
            var final: ChatChunk?
            do {
                let stream = client.streamChat(model: model, messages: wire, think: think,
                                               numPredict: think ? 8000 : 3000)
                for try await chunk in stream {
                    var thinking = chunk.message?.thinking ?? ""
                    var content = chunk.message?.content ?? ""
                    // Fallback for models that put their reasoning inside <think> tags.
                    if content.contains("<think>") {
                        inThinkTag = true
                        content = content.replacingOccurrences(of: "<think>", with: "")
                    }
                    if inThinkTag {
                        if let r = content.range(of: "</think>") {
                            thinking += content[..<r.lowerBound]
                            content = String(content[r.upperBound...])
                            inThinkTag = false
                        } else {
                            thinking += content
                            content = ""
                        }
                    }
                    if !thinking.isEmpty || !content.isEmpty {
                        self.receivedFirstToken = true
                        self.receivingThinking = !thinking.isEmpty && content.isEmpty
                        let addThinking = thinking, addContent = content
                        self.mutateMessage(answerID, in: id) { m in
                            m.thinking += addThinking
                            if m.content.isEmpty, !addContent.isEmpty {
                                m.content = String(addContent.drop(while: { $0 == "\n" }))
                            } else {
                                m.content += addContent
                            }
                        }
                    }
                    if chunk.done == true { final = chunk }
                }
            } catch is CancellationError {
                self.mutateMessage(answerID, in: id) { $0.stopped = true }
            } catch {
                if Task.isCancelled {
                    self.mutateMessage(answerID, in: id) { $0.stopped = true }
                } else {
                    self.append(ChatMessage(role: .notice, content: error.localizedDescription), to: id)
                    if (error as? OllamaError).map({ switch $0 { case .unreachable, .remote: return true; default: return false } }) == true {
                        self.reachable = false
                    }
                }
            }
            if Task.isCancelled { self.mutateMessage(answerID, in: id) { $0.stopped = true } }

            let seconds = Date().timeIntervalSince(self.startDate)
            if let f = final, let count = f.eval_count {
                let evalSeconds = Double(f.eval_duration ?? 0) / 1e9
                let tps = evalSeconds > 0 ? Double(count) / evalSeconds : 0
                let stats = AnswerStats(model: model, tokens: count, tokensPerSecond: tps, seconds: seconds)
                self.lastStats = stats
                self.mutateMessage(answerID, in: id) { $0.stats = stats }
            } else {
                self.lastStats = AnswerStats(model: model, tokens: 0, tokensPerSecond: 0, seconds: seconds)
            }
            // Remove an empty answer that produced nothing at all.
            self.mutate(id) { c in
                c.messages.removeAll { $0.id == answerID && $0.content.isEmpty && $0.thinking.isEmpty && !$0.stopped }
            }
            self.elapsed = seconds
            self.isGenerating = false
            self.receivingThinking = false
            self.streamTask = nil
            self.save(id)
            await self.refreshStatus()
        }
    }

    private func mutateMessage(_ messageID: UUID, in id: UUID, _ change: (inout ChatMessage) -> Void) {
        mutate(id) { c in
            if let j = c.messages.firstIndex(where: { $0.id == messageID }) { change(&c.messages[j]) }
        }
    }

    /// Stops the answer in progress by closing the connection.
    func stop() {
        streamTask?.cancel()
        draftTask?.cancel()
    }

    // MARK: Memories

    func loadMemory(topic: String) {
        guard let id = selectedID else { return }
        guard !topic.isEmpty else {
            notice(tr("Uso: /mem <tema>", "Usage: /mem <topic>"))
            return
        }
        guard let entry = MemoryStore.bestMatch(for: topic) else {
            notice(tr("Ninguna memoria coincide con «\(topic)».", "No memory matches “\(topic)”."))
            return
        }
        guard let text = MemoryStore.read(entry.file) else {
            notice(tr("El índice nombra \(entry.file), pero el archivo no existe.",
                      "The index lists \(entry.file), but the file does not exist."))
            return
        }
        var m = ChatMessage(role: .memory, content: text)
        m.memoryFile = entry.file
        mutate(id) { if $0.title.isEmpty { $0.title = "/mem " + topic } }
        append(m, to: id)
        save(id)
    }

    static func transcript(of c: Conversation) -> String {
        var lines: [String] = []
        for m in c.messages {
            switch m.role {
            case .user:
                var t = "User: " + m.content
                for a in m.attachments { t += "\n[attached \(a.name)]\n" + a.text }
                lines.append(t)
            case .assistant where !m.content.isEmpty:
                lines.append("Assistant: " + m.content)
            case .memory:
                lines.append("[Memory \(m.memoryFile ?? "") loaded]\n" + m.content)
            default:
                continue
            }
        }
        var text = lines.joined(separator: "\n\n")
        if text.count > 24_000 { text = "…" + String(text.suffix(24_000)) }
        return text
    }

    func startMemoryDraft() {
        guard let c = current, c.messages.contains(where: { $0.role == .user || $0.role == .assistant }) else {
            notice(tr("No hay nada que guardar todavía.", "There is nothing to save yet."))
            return
        }
        let model = selectedModel
        let text = Self.transcript(of: c)
        isDraftingMemory = true
        startDate = Date()
        draftTask = Task { [weak self] in
            do {
                let draft = try await MemoryStore.draft(from: text, model: model)
                guard let self else { return }
                self.draftReplaces = MemoryStore.exists(draft.file)
                self.memoryDraft = draft
            } catch is CancellationError {
            } catch {
                self?.notice(tr("No se pudo preparar la memoria: ", "Could not prepare the memory: ") + error.localizedDescription)
            }
            self?.isDraftingMemory = false
        }
    }

    /// Writes the previewed memory; confirms only after checking it on disk.
    @discardableResult
    func confirmMemory(_ draft: MemoryDraft) -> Bool {
        do {
            var d = draft
            d.file = MemoryStore.sanitizeFileName(d.file)
            try MemoryStore.save(d)
            memoryDraft = nil
            notice(tr("Memoria guardada y verificada en el disco: \(d.file)", "Memory saved and verified on disk: \(d.file)"))
            return true
        } catch {
            toast = error.localizedDescription
            return false
        }
    }
}
