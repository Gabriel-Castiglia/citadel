// SettingsViews.swift
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

/// State of the Settings window.
final class SettingsState: ObservableObject {
    @Published var rulesText = Rules.load()
    @Published var rulesSaved = true
    @Published var folderPath = MemoryStore.folder.path.tildePath
    @Published var memories: [MemoryEntry] = MemoryStore.allMemories()
    @Published var deleting: MemoryEntry?
    @Published var message: String?

    func reloadMemories() {
        folderPath = MemoryStore.folder.path.tildePath
        memories = MemoryStore.allMemories()
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = MemoryStore.folder
        panel.prompt = tr("Elegir", "Choose")
        if panel.runModal() == .OK, let url = panel.url {
            UserDefaults.standard.set(url.path, forKey: "memoryFolder")
            reloadMemories()
        }
    }

    func resetFolder() {
        UserDefaults.standard.removeObject(forKey: "memoryFolder")
        reloadMemories()
    }

    func saveRules() {
        do {
            try Rules.save(rulesText)
            rulesSaved = true
            message = tr("Reglas guardadas.", "Rules saved.")
        } catch {
            message = error.localizedDescription
        }
    }
}

struct SettingsView: View {
    @ObservedObject var lang = L10n.shared

    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label(tr("Memorias", "Memories"), systemImage: "bookmark") }
            RulesSettings()
                .tabItem { Label(tr("Reglas", "Rules"), systemImage: "list.bullet.rectangle") }
            OllamaSettings()
                .tabItem { Label("Ollama", systemImage: "network") }
            ThemeSettings()
                .tabItem { Label(tr("Apariencia", "Appearance"), systemImage: "paintpalette") }
        }
        .tint(Color.theme)
        .frame(minWidth: 620, idealWidth: 680, minHeight: 460, idealHeight: 540)
        .id(lang.language)
    }
}

struct GeneralSettings: View {
    @StateObject private var state = SettingsState()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tr("Carpeta de memorias", "Memory folder"))
                .font(.system(size: 13, weight: .semibold))
            HStack(spacing: 8) {
                Text(state.folderPath)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.raised(0.06)))
                Button(tr("Elegir…", "Choose…")) { state.chooseFolder() }
                Button(tr("Por defecto", "Default")) { state.resetFolder() }
                    .help(Paths.defaultMemoryFolder.path)
            }
            Text(tr("El índice _index.md de esta carpeta se agrega a cada conversación. La app escribe las memorias (con /save), nunca el modelo.",
                    "The _index.md of this folder is added to every conversation. The app writes memories (with /save), never the model."))
                .font(.system(size: 11.5)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text(tr("Memorias (\(state.memories.count))", "Memories (\(state.memories.count))"))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    NSWorkspace.shared.open(MemoryStore.folder)
                } label: { Label(tr("Abrir carpeta", "Open folder"), systemImage: "folder") }
                Button { state.reloadMemories() } label: { Image(systemName: "arrow.clockwise") }
                    .help(tr("Actualizar", "Refresh"))
            }
            .padding(.top, 6)

            List {
                ForEach(state.memories) { m in
                    HStack(spacing: 10) {
                        Image(systemName: "doc.text").foregroundStyle(Color.theme)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.file).font(.system(size: 12.5, weight: .medium, design: .monospaced))
                            Text(m.topic.isEmpty ? tr("(no figura en el índice)", "(not in the index)") : m.topic)
                                .font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                        Button {
                            let url = MemoryStore.folder.appendingPathComponent(m.file)
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } label: { Image(systemName: "magnifyingglass") }
                            .buttonStyle(.borderless)
                            .help(tr("Mostrar en Finder", "Show in Finder"))
                        Button { state.deleting = m } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                            .help(tr("Eliminar", "Delete"))
                    }
                    .padding(.vertical, 3)
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: false))
            if let msg = state.message {
                Text(msg).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .alert(tr("¿Eliminar esta memoria?", "Delete this memory?"),
               isPresented: Binding(get: { state.deleting != nil }, set: { if !$0 { state.deleting = nil } })) {
            Button(tr("Cancelar", "Cancel"), role: .cancel) { state.deleting = nil }
            Button(tr("Eliminar", "Delete"), role: .destructive) {
                if let m = state.deleting {
                    do {
                        try MemoryStore.delete(m.file)
                        state.message = tr("Eliminada: \(m.file)", "Deleted: \(m.file)")
                    } catch { state.message = error.localizedDescription }
                }
                state.deleting = nil
                state.reloadMemories()
            }
        } message: {
            Text(tr("Se borra el archivo \(state.deleting?.file ?? "") y su línea del índice.",
                    "The file \(state.deleting?.file ?? "") and its index line will be removed."))
        }
    }
}

/// Where Ollama runs: this Mac, or another computer through an SSH tunnel.
@MainActor
final class OllamaSettingsState: ObservableObject {
    @Published var remote = UserDefaults.standard.bool(forKey: "useSSH")
    @Published var host = UserDefaults.standard.string(forKey: "sshHost") ?? ""
    @Published var result = ""
    @Published var busy = false

    func apply() async {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        UserDefaults.standard.set(trimmed, forKey: "sshHost")
        UserDefaults.standard.set(remote && !trimmed.isEmpty, forKey: "useSSH")
        busy = true
        result = tr("Conectando…", "Connecting…")
        await Connection.shared.stop()
        do {
            let models = try await OllamaClient().listModels()
            result = tr("Conectado: \(models.count) modelo(s). ", "Connected: \(models.count) model(s). ") + models.joined(separator: ", ")
        } catch {
            result = error.localizedDescription
        }
        busy = false
        await ChatModel.shared.refreshStatus()
    }
}

struct OllamaSettings: View {
    @StateObject private var state = OllamaSettingsState()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("Dónde corre Ollama", "Where Ollama runs"))
                .font(.system(size: 13, weight: .semibold))
            Picker("", selection: $state.remote) {
                Text(tr("En esta Mac (127.0.0.1:11434)", "On this Mac (127.0.0.1:11434)")).tag(false)
                Text(tr("En otra computadora, por SSH", "On another computer, through SSH")).tag(true)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            TextField(tr("usuario@equipo, o un Host de ~/.ssh/config", "user@host, or a Host from ~/.ssh/config"), text: $state.host)
                .font(.system(size: 12, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 360)
                .padding(.leading, 20)
                .disabled(!state.remote)
            Text(tr("Citadel abre un túnel con el ssh de macOS hasta el puerto 11434 de esa computadora y lo cierra al salir. Usa tu llave SSH: nunca pide contraseña. El manual explica cómo preparar las dos computadoras.",
                    "Citadel opens a tunnel with the macOS ssh command to port 11434 of that computer and closes it on quit. It uses your SSH key and never asks for a password. The manual explains how to prepare both computers."))
                .font(.system(size: 11.5)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button(tr("Aplicar y probar", "Apply and test")) { Task { await state.apply() } }
                    .disabled(state.busy)
                Text(state.result)
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(20)
    }
}

struct RulesSettings: View {
    @StateObject private var state = SettingsState()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("Estas reglas van como mensaje de sistema en cada consulta, junto con el índice de memorias.",
                    "These rules go as the system message of every request, together with the memory index."))
                .font(.system(size: 11.5)).foregroundStyle(.secondary)
            Text(Paths.rules.path.tildePath)
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                .textSelection(.enabled)
            TextEditor(text: Binding(get: { state.rulesText }, set: { state.rulesText = $0; state.rulesSaved = false }))
                .font(.system(size: 12.5, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.sunken(0.3)))
            HStack {
                if let msg = state.message { Text(msg).font(.system(size: 11.5)).foregroundStyle(.secondary) }
                Spacer()
                Button(tr("Restaurar las originales", "Restore defaults")) {
                    state.rulesText = Rules.defaultText
                    state.rulesSaved = false
                }
                Button(tr("Descartar cambios", "Revert")) {
                    state.rulesText = Rules.load()
                    state.rulesSaved = true
                }
                .disabled(state.rulesSaved)
                Button(tr("Guardar", "Save")) { state.saveRules() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(state.rulesSaved)
            }
        }
        .padding(20)
    }
}

// MARK: - About

struct AboutView: View {
    @ObservedObject var lang = L10n.shared

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
            Text(AppInfo.name)
                .font(.system(size: 22, weight: .semibold))
            Text(tr("Versión \(AppInfo.version)", "Version \(AppInfo.version)"))
                .foregroundStyle(.secondary)
            Text(tr("Chat con modelos de lenguaje locales servidos por Ollama.",
                    "Chat with local language models served by Ollama."))
                .font(.system(size: 12.5))
                .multilineTextAlignment(.center)
            Divider().padding(.vertical, 4)
            Text(tr("Autor: \(AppInfo.author)", "Author: \(AppInfo.author)"))
                .font(.system(size: 12.5))
            Text("Copyright © 2026 \(AppInfo.author)")
                .font(.system(size: 11.5)).foregroundStyle(.secondary)
            Text(tr("Licencia: GNU GPL, solo la versión 2 (GPL-2.0-only).",
                    "License: GNU GPL, version 2 only (GPL-2.0-only)."))
                .font(.system(size: 11.5)).foregroundStyle(.secondary)
            Text(tr("Este programa es software libre y se distribuye SIN NINGUNA GARANTÍA.",
                    "This program is free software and comes with ABSOLUTELY NO WARRANTY."))
                .font(.system(size: 11)).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(width: 380)
        .id(lang.language)
    }
}
