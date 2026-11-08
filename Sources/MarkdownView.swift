// MarkdownView.swift
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

import SwiftUI

/// A block of Markdown: enough for chat answers (headings, lists, quotes, code).
enum MDBlock: Hashable {
    case heading(Int, String)
    case paragraph(String)
    case bullets([MDItem])
    case numbered([MDItem])
    case quote(String)
    case code(String, String)
    case rule
    case table([String])
}

struct MDItem: Hashable {
    var indent: Int
    var marker: String
    var text: String
}

enum MarkdownParser {
    static func parse(_ text: String) -> [MDBlock] {
        var blocks: [MDBlock] = []
        var paragraph: [String] = []
        var bullets: [MDItem] = []
        var numbered: [MDItem] = []
        var quote: [String] = []
        var table: [String] = []
        var code: [String]? = nil
        var codeLang = ""

        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))); paragraph = [] }
            if !bullets.isEmpty { blocks.append(.bullets(bullets)); bullets = [] }
            if !numbered.isEmpty { blocks.append(.numbered(numbered)); numbered = [] }
            if !quote.isEmpty { blocks.append(.quote(quote.joined(separator: "\n"))); quote = [] }
            if !table.isEmpty { blocks.append(.table(table)); table = [] }
        }

        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = raw
            let t = line.trimmingCharacters(in: .whitespaces)
            if code != nil {
                if t.hasPrefix("```") {
                    blocks.append(.code(codeLang, code!.joined(separator: "\n")))
                    code = nil
                } else {
                    code!.append(line)
                }
                continue
            }
            if t.hasPrefix("```") {
                flush()
                codeLang = String(t.dropFirst(3)).trimmed
                code = []
                continue
            }
            if t.isEmpty { flush(); continue }

            if t.hasPrefix("#") {
                let level = t.prefix(while: { $0 == "#" }).count
                if level <= 6, t.dropFirst(level).first == " " {
                    flush()
                    blocks.append(.heading(level, String(t.dropFirst(level)).trimmed))
                    continue
                }
            }
            if t == "---" || t == "***" || t == "___" { flush(); blocks.append(.rule); continue }
            if t.hasPrefix("|") {
                if !table.isEmpty || paragraph.isEmpty { if table.isEmpty { flush() }; table.append(t); continue }
            }
            if t.hasPrefix(">") {
                if quote.isEmpty { flush() }
                quote.append(String(t.dropFirst()).trimmed)
                continue
            }
            let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).count / 2
            if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ") {
                if bullets.isEmpty { flush() }
                bullets.append(MDItem(indent: indent, marker: "•", text: String(t.dropFirst(2))))
                continue
            }
            if let dot = t.firstIndex(where: { $0 == "." || $0 == ")" }),
               t[..<dot].allSatisfy(\.isNumber), !t[..<dot].isEmpty,
               t[t.index(after: dot)...].first == " " {
                if numbered.isEmpty { flush() }
                numbered.append(MDItem(indent: indent, marker: String(t[...dot]), text: String(t[t.index(after: dot)...]).trimmed))
                continue
            }
            // A continuation line of a list item stays with it.
            if !bullets.isEmpty, indent > 0 { bullets[bullets.count - 1].text += " " + t; continue }
            if !numbered.isEmpty, indent > 0 { numbered[numbered.count - 1].text += " " + t; continue }
            if !bullets.isEmpty || !numbered.isEmpty || !quote.isEmpty || !table.isEmpty { flush() }
            paragraph.append(t)
        }
        if let code { blocks.append(.code(codeLang, code.joined(separator: "\n"))) }
        flush()
        return blocks
    }

    /// Inline Markdown (bold, italics, inline code, links) as an AttributedString.
    static func inline(_ s: String) -> AttributedString {
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard var out = try? AttributedString(markdown: s, options: opts) else { return AttributedString(s) }
        // Give inline code a subtle box so it stands out from the text around it.
        for run in out.runs where run.inlinePresentationIntent?.contains(.code) == true {
            out[run.range].backgroundColor = Color.white.opacity(0.10)
        }
        return out
    }
}

struct MarkdownView: View {
    let text: String
    var baseSize: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(MarkdownParser.parse(text).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MDBlock) -> some View {
        switch block {
        case .heading(let level, let s):
            Text(MarkdownParser.inline(s))
                .font(.system(size: level == 1 ? baseSize + 8 : level == 2 ? baseSize + 5 : baseSize + 2, weight: .semibold))
                .padding(.top, 4)
        case .paragraph(let s):
            Text(MarkdownParser.inline(s))
                .font(.system(size: baseSize))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        case .bullets(let items), .numbered(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.marker)
                            .font(.system(size: baseSize, weight: item.marker == "•" ? .bold : .regular).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 14, alignment: .trailing)
                        Text(MarkdownParser.inline(item.text))
                            .font(.system(size: baseSize))
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(item.indent) * 18)
                }
            }
        case .quote(let s):
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5).fill(Color.secondary.opacity(0.5)).frame(width: 3)
                Text(MarkdownParser.inline(s)).font(.system(size: baseSize)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .code(let lang, let code):
            CodeBlockView(language: lang, code: code)
        case .rule:
            Divider()
        case .table(let rows):
            tableView(Self.cells(rows))
        }
    }

    /// Table rows split into cells, without the |---| separator line.
    static func cells(_ rows: [String]) -> [[String]] {
        rows.filter { row in
            !row.replacingOccurrences(of: "|", with: "").allSatisfy { "-: ".contains($0) }
        }.map { row in
            row.trimmingCharacters(in: CharacterSet(charactersIn: "| "))
                .components(separatedBy: "|").map { $0.trimmed }
        }
    }

    private func tableView(_ rows: [[String]]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                tableRow(row, header: i == 0)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1)))
    }

    private func tableRow(_ row: [String], header: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                Text(MarkdownParser.inline(cell))
                    .font(.system(size: baseSize - 1, weight: header ? .semibold : .regular))
                    .frame(minWidth: 80, maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
            }
        }
        .background(header ? Color.white.opacity(0.06) : Color.clear)
    }
}

struct CodeBlockView: View {
    let language: String
    let code: String
    @StateObject private var copied = Flag()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? "code" : language)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    copyToPasteboard(code)
                    copied.on = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied.on = false }
                } label: {
                    Label(copied.on ? tr("Copiado", "Copied") : tr("Copiar", "Copy"),
                          systemImage: copied.on ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.04))
            Divider().opacity(0.5)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 12.5, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(12)
            }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.35)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08)))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
