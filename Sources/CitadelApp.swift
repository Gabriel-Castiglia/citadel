// CitadelApp.swift
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

@main
struct CitadelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject var lang = L10n.shared

    var body: some Scene {
        Window("Citadel", id: "main") {
            RootView(model: ChatModel.shared)
                .id(lang.language)
        }
        .windowStyle(.hiddenTitleBar)
        .commands { CitadelCommands(lang: lang, model: ChatModel.shared) }

        Window(tr("Acerca de Citadel", "About Citadel"), id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
        }
    }
}

struct CitadelCommands: Commands {
    @ObservedObject var lang: L10n
    let model: ChatModel

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            AboutMenuButton()
        }
        CommandGroup(replacing: .newItem) {
            Button(tr("Conversación nueva", "New Conversation")) { model.newConversation() }
                .keyboardShortcut("n", modifiers: .command)
        }
        CommandMenu(lang.isSpanish ? "Idioma" : "Language") {
            Button((lang.language == "en" ? "✓ " : "    ") + "English") { lang.language = "en" }
            Button((lang.language == "es" ? "✓ " : "    ") + "Español") { lang.language = "es" }
        }
    }
}

struct AboutMenuButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(tr("Acerca de Citadel", "About Citadel")) {
            openWindow(id: "about")
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

extension Notification.Name {
    /// Asks the main window to open Settings (used by the screenshot mode).
    static let citadelOpenSettings = Notification.Name("CitadelOpenSettings")
}

/// Opens the Settings window when asked through `citadelOpenSettings`.
struct SettingsOpener: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onReceive(NotificationCenter.default.publisher(for: .citadelOpenSettings)) { _ in openSettings() }
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let frameName = "CitadelMainWindow"
    private let minContent = NSSize(width: 820, height: 540)

    private func argument(after flag: String) -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let selfTest = CommandLine.arguments.contains("--self-test")
        let screenshot = argument(after: "--screenshot")
        MainActor.assumeIsolated {
            ChatModel.shared.persist = !selfTest
            ChatModel.shared.start(loadSaved: !selfTest)
        }
        DispatchQueue.main.async {
            self.configureMainWindow(fixedSize: screenshot != nil || selfTest)
        }
        if let path = screenshot {
            if let view = argument(after: "--screenshot-view") {
                Task { @MainActor in await self.showDocumentationView(view, then: path) }
            } else {
                captureAfterFrames(120, to: path)
            }
        }
        if selfTest {
            Task { @MainActor in
                let ok = await SelfTest.run()
                exit(ok ? 0 : 1)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.contains("main") == true }
            ?? NSApp.windows.first { $0.canBecomeMain && !($0 is NSPanel) }
    }

    /// `.defaultSize` is ignored with a hidden title bar, so size the window here.
    private func configureMainWindow(fixedSize: Bool) {
        guard let window = mainWindow else { return }
        window.contentMinSize = minContent
        window.minSize = NSSize(width: minContent.width, height: minContent.height + 28)
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        if fixedSize || !window.setFrameUsingName(frameName) {
            window.setContentSize(NSSize(width: 1180, height: 760))
            window.center()
        }
        if !fixedSize { window.setFrameAutosaveName(frameName) }
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: Screenshots for the manual

    /// Window captured by `--screenshot`; the main window unless a documentation view is shown.
    private var captureWindow: NSWindow?

    /// Shows one secondary view (`about`, `settings` or `save`) on its own and captures it.
    /// `save` asks the model for a real memory draft of the selected conversation first.
    @MainActor
    private func showDocumentationView(_ name: String, then path: String) async {
        let view: AnyView
        var title = ""
        switch name {
        case "about":
            view = AnyView(AboutView())
            title = tr("Acerca de Citadel", "About Citadel")
        case "settings":
            let main = mainWindow
            NotificationCenter.default.post(name: .citadelOpenSettings, object: nil)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            captureWindow = NSApp.windows.first { $0.isVisible && $0 !== main && $0.styleMask.contains(.titled) }
            guard captureWindow != nil else {
                FileHandle.standardError.write(Data("the Settings window did not open\n".utf8))
                exit(1)
            }
            mainWindow?.orderOut(nil)
            captureAfterFrames(90, to: path)
            return
        case "save":
            let model = ChatModel.shared
            guard let c = model.current,
                  let draft = try? await MemoryStore.draft(from: ChatModel.transcript(of: c), model: model.selectedModel)
            else {
                FileHandle.standardError.write(Data("could not draft a memory\n".utf8))
                exit(1)
            }
            model.draftReplaces = MemoryStore.exists(draft.file)
            view = AnyView(MemoryPreviewSheet(model: model, editor: DraftEditor(draft)).frame(width: 680, height: 600))
        default:
            FileHandle.standardError.write(Data("unknown view: \(name)\n".utf8))
            exit(1)
        }
        let host = NSHostingView(rootView: view.preferredColorScheme(.dark))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                              styleMask: title.isEmpty ? [.borderless] : [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = title
        window.contentView = host
        window.center()
        window.makeKeyAndOrderFront(nil)
        mainWindow?.orderOut(nil)
        captureWindow = window
        captureAfterFrames(90, to: path)
    }

    /// Draws `frames` frames, saves the window's picture as PNG and quits.
    private func captureAfterFrames(_ frames: Int, to path: String) {
        var count = 0
        Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { timer in
            count += 1
            (self.captureWindow ?? self.mainWindow)?.displayIfNeeded()
            guard count >= frames else { return }
            timer.invalidate()
            let ok = self.saveWindowPicture(to: path)
            FileHandle.standardError.write(Data((ok ? "screenshot saved: \(path)\n" : "screenshot failed\n").utf8))
            exit(ok ? 0 : 1)
        }
    }

    private func saveWindowPicture(to path: String) -> Bool {
        guard let window = captureWindow ?? mainWindow, let content = window.contentView else { return false }
        let view = content.superview ?? content
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return false }
        view.cacheDisplay(in: bounds, to: rep)
        // Composite on the window colour so translucent areas are not left transparent.
        let size = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        guard let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: rep.pixelsWide, pixelsHigh: rep.pixelsHigh,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return false }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
        NSColor(calibratedWhite: 0.13, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        rep.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1,
                 respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
        guard let png = out.representation(using: .png, properties: [:]) else { return false }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? png.write(to: url)) != nil
    }
}
