// Ollama.swift
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

/// One message as sent to /api/chat.
struct WireMessage: Codable {
    var role: String
    var content: String
}

/// One NDJSON line of a streamed /api/chat answer (or the whole non-streamed answer).
struct ChatChunk: Decodable {
    struct Msg: Decodable {
        var role: String?
        var content: String?
        var thinking: String?
    }

    var message: Msg?
    var done: Bool?
    var eval_count: Int?
    var eval_duration: Int64?
    var total_duration: Int64?
    var load_duration: Int64?
    var error: String?
}

enum OllamaError: LocalizedError {
    case unreachable
    case server(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .unreachable:
            return tr("No se puede conectar con Ollama. Prueba: brew services start ollama",
                      "Cannot reach Ollama. Try: brew services start ollama")
        case .server(let s):
            return "Ollama: \(s)"
        case .badResponse:
            return tr("Respuesta inesperada de Ollama.", "Unexpected response from Ollama.")
        }
    }
}

/// Minimal client for the local Ollama HTTP API.
struct OllamaClient {
    var base: URL = AppInfo.ollamaBase

    private struct TagsResponse: Decodable {
        struct Model: Decodable { var name: String }
        var models: [Model]
    }

    /// Installed models (/api/tags), sorted by name.
    func listModels() async throws -> [String] {
        var req = URLRequest(url: base.appendingPathComponent("api/tags"))
        req.timeoutInterval = 4
        let data: Data
        do { (data, _) = try await URLSession.shared.data(for: req) } catch { throw OllamaError.unreachable }
        let decoded = try JSONDecoder().decode(TagsResponse.self, from: data)
        return decoded.models.map(\.name).sorted()
    }

    /// Models currently loaded in memory (/api/ps).
    func loadedModels() async throws -> [String] {
        var req = URLRequest(url: base.appendingPathComponent("api/ps"))
        req.timeoutInterval = 4
        let data: Data
        do { (data, _) = try await URLSession.shared.data(for: req) } catch { throw OllamaError.unreachable }
        let decoded = try JSONDecoder().decode(TagsResponse.self, from: data)
        return decoded.models.map(\.name)
    }

    private func chatRequest(model: String, messages: [WireMessage], think: Bool, stream: Bool,
                             numPredict: Int, jsonFormat: Bool) throws -> URLRequest {
        var body: [String: Any] = [
            "model": model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "stream": stream,
            "think": think,
            "options": ["num_predict": numPredict],
        ]
        if jsonFormat { body["format"] = "json" }
        var req = URLRequest(url: base.appendingPathComponent("api/chat"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        // Loading a model and long reasoning can take minutes between bytes.
        req.timeoutInterval = 900
        return req
    }

    /// Streams /api/chat as NDJSON. Cancelling the consuming task closes the connection,
    /// which makes Ollama stop generating.
    func streamChat(model: String, messages: [WireMessage], think: Bool, numPredict: Int)
        -> AsyncThrowingStream<ChatChunk, Error>
    {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let req = try chatRequest(model: model, messages: messages, think: think,
                                              stream: true, numPredict: numPredict, jsonFormat: false)
                    let bytes: URLSession.AsyncBytes
                    let response: URLResponse
                    do { (bytes, response) = try await URLSession.shared.bytes(for: req) } catch {
                        if Task.isCancelled { throw CancellationError() }
                        throw OllamaError.unreachable
                    }
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    let decoder = JSONDecoder()
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard let data = line.data(using: .utf8), !data.isEmpty else { continue }
                        guard let chunk = try? decoder.decode(ChatChunk.self, from: data) else { continue }
                        if let err = chunk.error { throw OllamaError.server(err) }
                        continuation.yield(chunk)
                        if chunk.done == true { break }
                    }
                    if status != 200 && status != 0 { throw OllamaError.server("HTTP \(status)") }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// One non-streamed /api/chat call; returns the answer text.
    func complete(model: String, messages: [WireMessage], think: Bool, numPredict: Int,
                  jsonFormat: Bool) async throws -> String
    {
        let req = try chatRequest(model: model, messages: messages, think: think, stream: false,
                                  numPredict: numPredict, jsonFormat: jsonFormat)
        let data: Data
        do { (data, _) = try await URLSession.shared.data(for: req) } catch {
            if Task.isCancelled { throw CancellationError() }
            throw OllamaError.unreachable
        }
        let chunk = try JSONDecoder().decode(ChatChunk.self, from: data)
        if let err = chunk.error { throw OllamaError.server(err) }
        guard let text = chunk.message?.content else { throw OllamaError.badResponse }
        return text
    }
}
