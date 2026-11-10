// MainViews.swift
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
import SwiftUI

// MARK: - Root

struct RootView: View {
    @ObservedObject var model: ChatModel
    @ObservedObject var lang = L10n.shared
    @ObservedObject var theme = ThemePrefs.shared

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(model: model)
                .frame(width: 264)
                .background(SidebarBlur(material: .sidebar))
            Rectangle().fill(Color.sunken(0.45)).frame(width: 1)
            ChatPane(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .ignoresSafeArea()
        .background(SettingsOpener())
        .frame(minWidth: 820, minHeight: 540)
        .tint(Color.theme)
        .id(theme.accent)
        .sheet(isPresented: Binding(get: { model.memoryDraft != nil },
                                    set: { if !$0 { model.memoryDraft = nil } })) {
            if let draft = model.memoryDraft {
                MemoryPreviewSheet(model: model, editor: DraftEditor(draft))
            }
        }
    }
}

// MARK: - Sidebar

/// Pending rename or delete in the sidebar.
final class SidebarState: ObservableObject {
    @Published var renaming: Conversation?
    @Published var renameText = ""
    @Published var deleting: Conversation?
}

struct SidebarView: View {
    @ObservedObject var model: ChatModel
    @StateObject private var state = SidebarState()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Citadel")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(action: model.newConversation) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 15, weight: .medium))
                }
                .buttonStyle(.borderless)
                .help(tr("Conversación nueva (⌘N)", "New conversation (⌘N)"))
            }
            .padding(.top, 40)
            .padding(.horizontal, 16)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 12))
                TextField(tr("Buscar", "Search"), text: $model.search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                if !model.search.isEmpty {
                    Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.raised(0.07)))
            .padding(.horizontal, 12)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(model.filteredConversations) { c in
                        ConversationRow(conversation: c, selected: c.id == model.selectedID)
                            .contentShape(Rectangle())
                            .onTapGesture { model.select(c.id) }
                            .contextMenu {
                                Button(tr("Renombrar…", "Rename…")) {
                                    state.renameText = c.displayTitle
                                    state.renaming = c
                                }
                                Divider()
                                Button(tr("Eliminar…", "Delete…"), role: .destructive) { state.deleting = c }
                            }
                    }
                    if model.filteredConversations.isEmpty, !model.search.isEmpty {
                        Text(tr("Sin resultados", "No results"))
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .padding(12)
                    }
                }
                .padding(.horizontal, 8)
            }

            Divider().opacity(0.4)
            SettingsLink {
                Label(tr("Ajustes", "Settings"), systemImage: "gearshape")
                    .font(.system(size: 13))
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
            .padding(.top, 2)
        }
        .alert(tr("Renombrar conversación", "Rename conversation"),
               isPresented: Binding(get: { state.renaming != nil }, set: { if !$0 { state.renaming = nil } })) {
            TextField(tr("Título", "Title"), text: $state.renameText)
            Button(tr("Cancelar", "Cancel"), role: .cancel) { state.renaming = nil }
            Button(tr("Renombrar", "Rename")) {
                if let c = state.renaming { model.rename(c.id, to: state.renameText) }
                state.renaming = nil
            }
        }
        .alert(tr("¿Eliminar esta conversación?", "Delete this conversation?"),
               isPresented: Binding(get: { state.deleting != nil }, set: { if !$0 { state.deleting = nil } })) {
            Button(tr("Cancelar", "Cancel"), role: .cancel) { state.deleting = nil }
            Button(tr("Eliminar", "Delete"), role: .destructive) {
                if let c = state.deleting { model.delete(c.id) }
                state.deleting = nil
            }
        } message: {
            Text(tr("«\(state.deleting?.displayTitle ?? "")» se borrará del disco. No se puede deshacer.",
                    "“\(state.deleting?.displayTitle ?? "")” will be removed from disk. This cannot be undone."))
        }
    }
}

struct ConversationRow: View {
    let conversation: Conversation
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(conversation.displayTitle)
                .font(.system(size: 13, weight: selected ? .medium : .regular))
                .lineLimit(1)
            Text(conversation.updated, format: .dateTime.day().month(.abbreviated).hour().minute())
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Color.theme.opacity(0.28) : Color.clear)
        )
    }
}

// MARK: - Chat pane

struct ChatPane: View {
    @ObservedObject var model: ChatModel

    var body: some View {
        VStack(spacing: 0) {
            ChatHeader(model: model)
            Divider().opacity(0.5)
            if let c = model.current, !c.messages.isEmpty {
                MessagesList(model: model, conversation: c)
            } else {
                EmptyChatView()
            }
            ComposerView(model: model)
        }
        .overlay(alignment: .top) {
            if let toast = model.toast {
                Text(toast)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(.regularMaterial))
                    .padding(.top, 60)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { model.toast = nil }
                    }
            }
        }
    }
}

struct ChatHeader: View {
    @ObservedObject var model: ChatModel

    var body: some View {
        HStack(spacing: 12) {
            Text(model.current?.displayTitle ?? "Citadel")
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
            Spacer()
            LanguagePicker()
            ModelPicker(model: model)
        }
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .frame(height: 52)
    }
}

/// Interface language, shown next to the model so it is easy to find.
struct LanguagePicker: View {
    @ObservedObject var lang = L10n.shared

    var body: some View {
        Menu {
            ForEach([("en", "English"), ("es", "Español")], id: \.0) { code, name in
                Button {
                    lang.language = code
                } label: {
                    if lang.language == code { Label(name, systemImage: "checkmark") } else { Text(name) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                Text(lang.isSpanish ? "Español" : "English")
            }
            .font(.system(size: 12, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.raised(0.08)))
        .help(tr("Idioma de la interfaz", "Interface language"))
    }
}

struct ModelPicker: View {
    @ObservedObject var model: ChatModel

    var body: some View {
        Menu {
            if model.models.isEmpty {
                Text(model.reachable == false ? tr("Ollama no responde", "Ollama is not reachable")
                                              : tr("No hay modelos instalados", "No models installed"))
            }
            ForEach(model.models, id: \.self) { name in
                Button {
                    model.selectedModel = name
                } label: {
                    let title = model.reasoningModels[name] == false ? name + tr("  (sin Razonar)", "  (no Reason)") : name
                    if name == model.selectedModel {
                        Label(title, systemImage: "checkmark")
                    } else {
                        Text(title)
                    }
                }
            }
            Divider()
            Button(tr("Actualizar lista", "Refresh list")) { Task { await model.refreshStatus() } }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "cpu")
                Text(model.selectedModel)
            }
            .font(.system(size: 12, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.raised(0.08)))
        .help(tr("Modelo de Ollama", "Ollama model"))
    }
}

struct EmptyChatView: View {
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text(tr("¿En qué te ayudo?", "How can I help?"))
                .font(.system(size: 24, weight: .semibold))
            Text(tr("Todo corre en esta Mac con Ollama: nada de lo que escribas sale de la computadora.",
                    "Everything runs on this Mac through Ollama: nothing you write leaves the computer."))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 8) {
                hint("brain", tr("Razonar: más lento (20 a 90 s) y mucho más preciso en cuentas, conteos, lógica y fechas.",
                                 "Reason: slower (20 to 90 s) and much more accurate on math, counting, logic and dates."))
                hint("bookmark", tr("/mem <tema> carga una memoria guardada en la conversación.",
                                    "/mem <topic> loads a saved memory into the conversation."))
                hint("square.and.arrow.down", tr("/save escribe una memoria con lo importante de esta conversación.",
                                                 "/save writes a memory with what matters from this conversation."))
                hint("doc.text", tr("Arrastra un .txt o .md al cuadro de texto para adjuntarlo.",
                                    "Drag a .txt or .md file onto the text box to attach it."))
            }
            .padding(18)
            .frame(maxWidth: 520)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.raised(0.04)))
            .padding(.top, 8)
            Spacer()
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func hint(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(Color.theme).frame(width: 18)
            Text(text).font(.system(size: 12.5)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Messages

struct MessagesList: View {
    @ObservedObject var model: ChatModel
    let conversation: Conversation

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(conversation.messages) { m in
                        MessageRow(message: m, isStreaming: model.isGenerating && m.id == conversation.messages.last?.id,
                                   model: model)
                            .id(m.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
                .frame(maxWidth: 860)
                .frame(maxWidth: .infinity)
            }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: conversation.messages.last?.content.count ?? 0) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onChange(of: conversation.messages.last?.thinking.count ?? 0) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onChange(of: conversation.messages.count) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }
}

struct MessageRow: View {
    let message: ChatMessage
    let isStreaming: Bool
    @ObservedObject var model: ChatModel

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 80)
                VStack(alignment: .trailing, spacing: 6) {
                    ForEach(message.attachments, id: \.self) { a in
                        Chip(symbol: "doc.text", text: a.name)
                    }
                    if !message.content.isEmpty {
                        Text(message.content)
                            .font(.system(size: 14))
                            .textSelection(.enabled)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.theme.opacity(0.32)))
                    }
                }
            }
        case .assistant:
            AssistantMessageView(message: message, isStreaming: isStreaming, model: model)
        case .memory:
            Chip(symbol: "bookmark.fill", text: tr("memoria cargada: ", "memory loaded: ") + (message.memoryFile ?? ""))
        case .notice:
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "info.circle")
                Text(message.content).textSelection(.enabled)
            }
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
        }
    }
}

struct Chip: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(Color.theme)
            Text(text)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.raised(0.08)))
    }
}

struct AssistantMessageView: View {
    let message: ChatMessage
    let isStreaming: Bool
    @ObservedObject var model: ChatModel
    @StateObject private var copied = Flag()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !message.thinking.isEmpty || (isStreaming && message.reasoned && message.content.isEmpty) {
                ThinkingBlock(thinking: message.thinking, live: isStreaming && message.content.isEmpty)
            }
            if message.content.isEmpty && isStreaming && message.thinking.isEmpty && !message.reasoned {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(model.modelIsLoaded ? tr("Pensando la respuesta…", "Working on it…")
                                             : tr("Cargando el modelo…", "Loading the model…"))
                        .font(.system(size: 12.5)).foregroundStyle(.secondary)
                }
            }
            if !message.content.isEmpty {
                MarkdownView(text: message.content)
                    .textSelection(.enabled)
            }
            if !isStreaming {
                footer
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            if !message.content.isEmpty {
                Button {
                    copyToPasteboard(message.content)
                    copied.on = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied.on = false }
                } label: {
                    Label(copied.on ? tr("Copiado", "Copied") : tr("Copiar", "Copy"),
                          systemImage: copied.on ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless)
            }
            if message.stopped {
                Label(tr("Detenido", "Stopped"), systemImage: "stop.circle")
            }
            if let s = message.stats {
                Text(statsText(s))
            }
        }
        .font(.system(size: 11.5))
        .foregroundStyle(.secondary)
    }

    private func statsText(_ s: AnswerStats) -> String {
        var parts = [s.model]
        if s.tokensPerSecond > 0 { parts.append(String(format: "%.1f tok/s", s.tokensPerSecond)) }
        parts.append(String(format: "%.1f s", s.seconds))
        if message.reasoned { parts.append(tr("razonado", "reasoned")) }
        return parts.joined(separator: " · ")
    }
}

struct ThinkingBlock: View {
    let thinking: String
    let live: Bool
    @StateObject private var expanded = Flag(false)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.on.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(expanded.on ? 90 : 0))
                        .font(.system(size: 10, weight: .semibold))
                    Image(systemName: "brain")
                    Text(live ? tr("Razonando…", "Reasoning…") : tr("Razonamiento", "Reasoning"))
                    if live { ProgressView().controlSize(.mini) }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded.on {
                Text(thinking.trimmed)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary.opacity(0.85))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Color.secondary.opacity(0.35)).frame(width: 2)
                    }
            } else if live, let last = thinking.trimmed.components(separatedBy: .newlines).last(where: { !$0.trimmed.isEmpty }) {
                Text(last)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .padding(.leading, 12)
            }
        }
        .opacity(0.9)
    }
}

// MARK: - Composer

/// Holds the composer's measured height, in place of @State.
final class ComposerLayout: ObservableObject {
    @Published var height: CGFloat = 34
}

struct ComposerView: View {
    @ObservedObject var model: ChatModel
    @StateObject private var layout = ComposerLayout()

    var body: some View {
        VStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                if !model.attachments.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(model.attachments.enumerated()), id: \.offset) { i, a in
                            HStack(spacing: 4) {
                                Chip(symbol: "doc.text", text: "\(a.name) · \(a.text.count) " + tr("caracteres", "chars"))
                                Button { model.attachments.remove(at: i) } label: {
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                ComposerTextView(text: $model.composer, height: $layout.height,
                                 placeholder: tr("Escribe un mensaje…  (/mem tema · /save)", "Message…  (/mem topic · /save)"),
                                 onSubmit: { model.send() },
                                 onDropFile: { model.attachFile($0) })
                    .frame(height: layout.height)

                HStack(spacing: 10) {
                    // A plain button: the system toggle style looks the same on and off in dark mode.
                    let reasonOn = model.reason && model.canReason
                    Button { model.reason.toggle() } label: {
                        Label(tr("Razonar", "Reason"), systemImage: reasonOn ? "brain.fill" : "brain")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(reasonOn ? Color.onTheme : Color.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(reasonOn ? Color.theme : Color.raised(0.08)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.canReason)
                    .opacity(model.canReason ? 1 : 0.45)
                    .accessibilityAddTraits(reasonOn ? .isSelected : [])
                    .help(model.canReason
                          ? tr("Más lento (unos 20 a 90 s) pero mucho más preciso en cuentas, conteos, lógica y fechas.",
                               "Slower (about 20 to 90 s) but much more accurate on math, counting, logic and dates.")
                          : tr("\(model.selectedModel) no puede razonar: elige otro modelo para usar Razonar.",
                               "\(model.selectedModel) cannot reason: choose another model to use Reason."))

                    if reasonOn {
                        Text(tr("Más lento (20 a 90 s), mucho más preciso en cuentas, conteos, lógica y fechas.",
                                "Slower (20-90 s), much more accurate on math, counting, logic and dates."))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 4)
                    if model.isGenerating || model.isDraftingMemory {
                        Button(action: model.stop) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 11, weight: .bold))
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(Color.primary.opacity(0.85)))
                                .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                        }
                        .buttonStyle(.plain)
                        .help(tr("Detener", "Stop"))
                        .keyboardShortcut(".", modifiers: .command)
                    } else {
                        Button(action: model.send) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 13, weight: .bold))
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(model.canSend ? Color.theme : Color.raised(0.12)))
                                .foregroundStyle(model.canSend ? Color.onTheme : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(!model.canSend)
                        .help(tr("Enviar (Enter) · Nueva línea (Shift+Enter)", "Send (Enter) · New line (Shift+Enter)"))
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.raised(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.raised(0.10)))

            StatusLine(model: model)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .padding(.top, 6)
        .frame(maxWidth: 860)
        .frame(maxWidth: .infinity)
    }
}

struct StatusLine: View {
    @ObservedObject var model: ChatModel

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
            Text(text)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer()
        }
        .font(.system(size: 11.5))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
    }

    private var dotColor: Color {
        switch model.reachable {
        case .some(true): return model.isGenerating ? .yellow : Color.theme
        case .some(false): return .orange
        case .none: return .gray
        }
    }

    private var text: String {
        guard let ok = model.reachable else { return tr("Buscando Ollama…", "Looking for Ollama…") }
        let remote = Connection.remoteHost
        if !ok {
            if remote != nil { return model.connectionError ?? OllamaError.unreachable.localizedDescription }
            return tr("Ollama no responde en 127.0.0.1:11434. Solución: brew services start ollama",
                      "Ollama is not reachable at 127.0.0.1:11434. Fix: brew services start ollama")
        }
        let n = model.models.count
        let place = remote.map { tr("Ollama en \($0) (SSH)", "Ollama on \($0) (SSH)") } ?? tr("Ollama conectado", "Ollama connected")
        var parts = [place + " · \(n) " + (n == 1 ? tr("modelo", "model") : tr("modelos", "models"))]
        if model.isDraftingMemory {
            parts.append(tr("Escribiendo la memoria…", "Writing the memory…"))
        } else if model.isGenerating {
            if !model.receivedFirstToken {
                parts.append(model.modelIsLoaded ? tr("\(model.selectedModel) cargado", "\(model.selectedModel) loaded")
                                                 : tr("cargando \(model.selectedModel)…", "loading \(model.selectedModel)…"))
            } else {
                parts.append(model.receivingThinking ? tr("razonando…", "reasoning…") : tr("escribiendo…", "writing…"))
            }
            parts.append(String(format: "%.1f s", model.elapsed))
        } else {
            parts.append(model.modelIsLoaded ? tr("\(model.selectedModel) cargado", "\(model.selectedModel) loaded")
                                             : tr("\(model.selectedModel) se carga con el primer mensaje",
                                                  "\(model.selectedModel) loads with the first message"))
            if let s = model.lastStats {
                if s.tokensPerSecond > 0 { parts.append(String(format: "%.1f tok/s", s.tokensPerSecond)) }
                parts.append(String(format: "%.1f s", s.seconds))
            }
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Memory preview

/// Editable copy of a memory draft for the preview sheet.
final class DraftEditor: ObservableObject {
    @Published var file: String
    @Published var indexLine: String
    @Published var content: String
    init(_ d: MemoryDraft) { file = d.file; indexLine = d.indexLine; content = d.content }
    var draft: MemoryDraft { MemoryDraft(file: file, indexLine: indexLine, content: content) }
}

struct MemoryPreviewSheet: View {
    @ObservedObject var model: ChatModel
    @StateObject var editor: DraftEditor

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tr("Guardar memoria", "Save memory"))
                .font(.system(size: 17, weight: .semibold))
            Text(MemoryStore.folder.path.tildePath)
                .font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text(tr("Archivo", "File")).foregroundStyle(.secondary)
                    TextField("", text: $editor.file).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text(tr("Índice", "Index")).foregroundStyle(.secondary)
                    TextField("", text: $editor.indexLine).textFieldStyle(.roundedBorder)
                }
            }
            .font(.system(size: 13))

            if MemoryStore.exists(MemoryStore.sanitizeFileName(editor.file)) {
                Label(tr("Ya existe \(MemoryStore.sanitizeFileName(editor.file)): se va a reemplazar.",
                         "\(MemoryStore.sanitizeFileName(editor.file)) already exists: it will be replaced."),
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 12.5, weight: .medium))
            }

            TextEditor(text: $editor.content)
                .font(.system(size: 12.5, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.sunken(0.3)))

            HStack {
                Text("\(editor.content.components(separatedBy: "\n").count) " + tr("líneas", "lines"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button(tr("Cancelar", "Cancel")) { model.memoryDraft = nil }
                    .keyboardShortcut(.cancelAction)
                Button(tr("Guardar", "Save")) { model.confirmMemory(editor.draft) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 620, idealWidth: 680, minHeight: 520, idealHeight: 600)
    }
}
