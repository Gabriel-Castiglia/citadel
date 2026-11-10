// Theme.swift
// Copyright (C) 2026 Gabriel Castiglia. Licensed under the GNU GPL, version 2 only.
// SPDX-License-Identifier: GPL-2.0-only
//
// This program is free software; you can redistribute it and/or modify it
// under the terms of the GNU General Public License version 2 as published by
// the Free Software Foundation. It is distributed WITHOUT ANY WARRANTY; see
// the GNU General Public License for more details.
//
// Appearance (as macOS, light or dark) and twelve accent colours, as in Wyrmhold and Gryphmark.
// The accent colours the buttons, the selection and the glow behind the citadel in the icon;
// the app shows that icon in the Dock (icono/accents/<key>.png, made by icono/render-accents.sh).
// The icon in Finder stays green: changing it would break the app's signature.

import AppKit
import SwiftUI

struct Accent {
    let key, es, en: String
    let light, dark: UInt32          // the deeper tone for light windows, the brighter one for dark

    var name: String { tr(es, en) }

    /// A colour that is the light or the dark tone, following the window's appearance.
    var color: Color { Color(nsColor: nsColor) }

    var nsColor: NSColor {
        NSColor(name: nil) { appearance in
            let v = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? self.dark : self.light
            return NSColor(srgbRed: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255,
                           blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        }
    }

    var icon: NSImage? {
        Bundle.main.url(forResource: key, withExtension: "png", subdirectory: "accents").flatMap(NSImage.init(contentsOf:))
    }

    /// Text on a button filled with this colour: dark on the pale tones, white otherwise.
    var onAccent: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let v = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? self.dark : self.light
            let lum = 0.2126 * Double(v >> 16 & 0xFF) + 0.7152 * Double(v >> 8 & 0xFF) + 0.0722 * Double(v & 0xFF)
            return lum / 255 > 0.6 ? NSColor(white: 0.07, alpha: 1) : .white
        })
    }

    static let all: [Accent] = [
        Accent(key: "green", es: "Verde", en: "Green", light: 0x2A9D57, dark: 0x3CCF75),   // the original
        Accent(key: "gold", es: "Dorado", en: "Gold", light: 0x9A6F00, dark: 0xE2B84C),
        Accent(key: "purple", es: "Morado", en: "Purple", light: 0x5B2A86, dark: 0xB392E0),
        Accent(key: "sky", es: "Celeste", en: "Sky blue", light: 0x1A8CD8, dark: 0x5CB8F0),
        Accent(key: "ember", es: "Naranja", en: "Orange", light: 0xD9652F, dark: 0xF08A5D),
        Accent(key: "red", es: "Rojo", en: "Red", light: 0xC8102E, dark: 0xF2545B),
        Accent(key: "yellow", es: "Amarillo", en: "Yellow", light: 0xB88A00, dark: 0xF5C842),
        Accent(key: "teal", es: "Verde azulado", en: "Teal", light: 0x00796B, dark: 0x4DB6AC),
        Accent(key: "blue", es: "Azul", en: "Blue", light: 0x1F5FD1, dark: 0x6E9BFF),
        Accent(key: "pink", es: "Rosa", en: "Pink", light: 0xC2185B, dark: 0xF06292),
        Accent(key: "black", es: "Negro", en: "Black", light: 0x1D1D1F, dark: 0xC7C7CC),
        Accent(key: "white", es: "Blanco", en: "White", light: 0x8E8E93, dark: 0xF5F5F7),
    ]

    static func get(_ key: String) -> Accent { all.first { $0.key == key } ?? all[0] }
}

final class ThemePrefs: ObservableObject {
    static let shared = ThemePrefs()

    /// "auto" (as macOS), "light" or "dark". Dark until 1.1.0, so dark is the default.
    @Published var appearance: String { didSet { save(); apply() } }
    @Published var accent: String { didSet { save(); apply() } }
    var persist = true
    /// The colour of the icon last put in the Dock.
    private(set) var dockIcon: String?

    private init() {
        let d = UserDefaults.standard
        appearance = d.string(forKey: "Appearance") ?? "dark"
        accent = d.string(forKey: "Accent") ?? "green"
    }

    private func save() {
        guard persist else { return }
        UserDefaults.standard.set(appearance, forKey: "Appearance")
        UserDefaults.standard.set(accent, forKey: "Accent")
    }

    var current: Accent { Accent.get(accent) }

    func apply() {
        switch appearance {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "auto": NSApp.appearance = nil
        default: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        if let img = current.icon { NSApp.applicationIconImage = img; dockIcon = current.key }
    }
}

extension Color {
    /// A light veil on dark windows and a faint shadow on light ones (raised fields, chips).
    static func raised(_ opacity: Double) -> Color {
        Color(nsColor: NSColor(name: nil) { a in
            a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 1, alpha: opacity) : NSColor(white: 0, alpha: opacity * 0.7)
        })
    }

    /// A darker well on dark windows and a soft grey one on light ones (code blocks, dividers).
    static func sunken(_ opacity: Double) -> Color {
        Color(nsColor: NSColor(name: nil) { a in
            a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 0, alpha: opacity) : NSColor(white: 0, alpha: min(0.08, opacity * 0.2))
        })
    }

    /// The chosen accent colour.
    static var theme: Color { ThemePrefs.shared.current.color }
    static var onTheme: Color { ThemePrefs.shared.current.onAccent }
}

struct ThemeSettings: View {
    @ObservedObject var theme = ThemePrefs.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tr("Apariencia", "Appearance")).font(.system(size: 13, weight: .semibold))
            Picker("", selection: $theme.appearance) {
                Text(tr("Como macOS", "As macOS")).tag("auto")
                Text(tr("Claro", "Light")).tag("light")
                Text(tr("Oscuro", "Dark")).tag("dark")
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            Text(tr("Color de los botones y del ícono", "Colour of the buttons and the icon"))
                .font(.system(size: 13, weight: .semibold)).padding(.top, 6)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(88), spacing: 8), count: 6), spacing: 12) {
                ForEach(Accent.all, id: \.key) { a in
                    let on = theme.accent == a.key
                    Button { theme.accent = a.key } label: {
                        VStack(spacing: 4) {
                            if let img = a.icon { Image(nsImage: img).resizable().interpolation(.high).frame(width: 56, height: 56) }
                            Text(a.name).font(.system(size: 11)).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .padding(5).frame(width: 88)
                        .background(RoundedRectangle(cornerRadius: 8).fill(on ? a.color.opacity(0.18) : .clear))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(on ? a.color : .clear, lineWidth: 2))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(tr("El color se usa en los botones, la selección y el ícono del Dock. El ícono del Finder sigue verde: cambiarlo rompería la firma de la app.",
                    "The colour is used for the buttons, the selection and the icon in the Dock. The icon in the Finder stays green: changing it would break the app's signature."))
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(20)
    }
}
