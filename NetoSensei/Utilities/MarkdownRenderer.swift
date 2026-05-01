//
//  MarkdownRenderer.swift
//  NetoSensei
//
//  Renders markdown text from AI responses into styled SwiftUI views.
//  Supports headings, bold, italic, inline code, code blocks, lists,
//  blockquotes, and horizontal rules.
//

import SwiftUI

struct MarkdownText: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parseMarkdown(text).enumerated()), id: \.offset) { _, element in
                renderElement(element)
            }
        }
    }

    // MARK: - Element Types

    private enum Element {
        case heading1(String)
        case heading2(String)
        case heading3(String)
        case paragraph(String)
        case bulletList([String])
        case numberedList([String])
        case codeBlock(String, language: String?)
        case blockquote(String)
        case horizontalRule
    }

    // MARK: - Parser

    private func parseMarkdown(_ text: String) -> [Element] {
        var elements: [Element] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                i += 1
                continue
            }

            // Headings
            if trimmed.hasPrefix("### ") {
                elements.append(.heading3(String(trimmed.dropFirst(4))))
                i += 1
                continue
            }
            if trimmed.hasPrefix("## ") {
                elements.append(.heading2(String(trimmed.dropFirst(3))))
                i += 1
                continue
            }
            if trimmed.hasPrefix("# ") {
                elements.append(.heading1(String(trimmed.dropFirst(2))))
                i += 1
                continue
            }

            // Code block
            if trimmed.hasPrefix("```") {
                let language = trimmed.count > 3 ? String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces) : nil
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                elements.append(.codeBlock(codeLines.joined(separator: "\n"), language: language))
                if i < lines.count { i += 1 }
                continue
            }

            // Blockquote
            if trimmed.hasPrefix("> ") {
                var quoteLines: [String] = []
                while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("> ") {
                    quoteLines.append(String(lines[i].trimmingCharacters(in: .whitespaces).dropFirst(2)))
                    i += 1
                }
                elements.append(.blockquote(quoteLines.joined(separator: "\n")))
                continue
            }

            // Horizontal rule
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                elements.append(.horizontalRule)
                i += 1
                continue
            }

            // Bullet list
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                var items: [String] = []
                while i < lines.count {
                    let cur = lines[i].trimmingCharacters(in: .whitespaces)
                    if cur.hasPrefix("- ") || cur.hasPrefix("* ") {
                        items.append(String(cur.dropFirst(2)))
                        i += 1
                    } else {
                        break
                    }
                }
                elements.append(.bulletList(items))
                continue
            }

            // Numbered list
            if trimmed.range(of: #"^\d+\. "#, options: .regularExpression) != nil {
                var items: [String] = []
                while i < lines.count {
                    let cur = lines[i].trimmingCharacters(in: .whitespaces)
                    if let match = cur.range(of: #"^\d+\. "#, options: .regularExpression) {
                        items.append(String(cur[match.upperBound...]))
                        i += 1
                    } else {
                        break
                    }
                }
                elements.append(.numberedList(items))
                continue
            }

            // Paragraph — collect contiguous plain lines
            var paragraphLines: [String] = []
            while i < lines.count {
                let cur = lines[i].trimmingCharacters(in: .whitespaces)
                if cur.isEmpty || cur.hasPrefix("#") || cur.hasPrefix("```") ||
                   cur.hasPrefix("> ") || cur.hasPrefix("- ") || cur.hasPrefix("* ") ||
                   cur == "---" || cur == "***" || cur == "___" ||
                   cur.range(of: #"^\d+\. "#, options: .regularExpression) != nil {
                    break
                }
                paragraphLines.append(cur)
                i += 1
            }
            if !paragraphLines.isEmpty {
                elements.append(.paragraph(paragraphLines.joined(separator: " ")))
            }
        }

        return elements
    }

    // MARK: - Render Element

    @ViewBuilder
    private func renderElement(_ element: Element) -> some View {
        switch element {
        case .heading1(let text):
            Text(text)
                .font(.title2.bold())
                .padding(.top, 8)

        case .heading2(let text):
            Text(text)
                .font(.headline)
                .padding(.top, 6)

        case .heading3(let text):
            Text(text)
                .font(.subheadline.bold())
                .padding(.top, 4)

        case .paragraph(let text):
            renderInlineFormatting(text)

        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\u{2022}")
                            .foregroundColor(.secondary)
                        renderInlineFormatting(item)
                    }
                }
            }
            .padding(.leading, 4)

        case .numberedList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .foregroundColor(.secondary)
                            .frame(width: 20, alignment: .trailing)
                        renderInlineFormatting(item)
                    }
                }
            }
            .padding(.leading, 4)

        case .codeBlock(let code, let language):
            VStack(alignment: .leading, spacing: 4) {
                if let lang = language, !lang.isEmpty {
                    Text(lang.uppercased())
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    Text(code)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primary)
                }
                .padding(10)
                .background(Color(UIColor.systemGray6))
                .cornerRadius(8)
            }

        case .blockquote(let text):
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.blue)
                    .frame(width: 3)

                Text(text)
                    .font(.body)
                    .italic()
                    .foregroundColor(.secondary)
                    .padding(.leading, 12)
            }
            .padding(.vertical, 4)

        case .horizontalRule:
            Divider()
                .padding(.vertical, 8)
        }
    }

    // MARK: - Inline Formatting

    private func renderInlineFormatting(_ text: String) -> Text {
        var result = Text("")
        var remaining = text

        while !remaining.isEmpty {
            // Bold **text**
            if let boldRange = remaining.range(of: #"\*\*(.+?)\*\*"#, options: .regularExpression) {
                let before = String(remaining[..<boldRange.lowerBound])
                result = result + Text(before)
                let boldText = String(remaining[boldRange]).replacingOccurrences(of: "**", with: "")
                result = result + Text(boldText).bold()
                remaining = String(remaining[boldRange.upperBound...])
                continue
            }

            // Inline code `code`
            if let codeRange = remaining.range(of: #"`([^`]+)`"#, options: .regularExpression) {
                let before = String(remaining[..<codeRange.lowerBound])
                result = result + Text(before)
                let codeText = String(remaining[codeRange]).replacingOccurrences(of: "`", with: "")
                result = result + Text(codeText).font(.system(.body, design: .monospaced)).foregroundColor(.blue)
                remaining = String(remaining[codeRange.upperBound...])
                continue
            }

            // Italic *text* (non-greedy, not matching **)
            if let italicRange = remaining.range(of: #"(?<!\*)\*([^*]+)\*(?!\*)"#, options: .regularExpression) {
                let before = String(remaining[..<italicRange.lowerBound])
                result = result + Text(before)
                var italicText = String(remaining[italicRange])
                italicText = italicText.trimmingCharacters(in: CharacterSet(charactersIn: "*"))
                result = result + Text(italicText).italic()
                remaining = String(remaining[italicRange.upperBound...])
                continue
            }

            // No more formatting
            result = result + Text(remaining)
            break
        }

        return result
    }
}
