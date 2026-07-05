//
//  HelpWindow.swift
//  TanqueStudio
//
//  The Help window: topic sidebar + rendered markdown page, plus the small
//  block renderer for the bundled (trusted, controlled) Help markdown.
//

import SwiftUI

// MARK: - Help Window

struct HelpWindowView: View {
    @State private var router = HelpRouter.shared

    private var selectedTopic: HelpTopic? {
        router.selectedTopicID.flatMap { HelpLibrary.topic(id: $0) }
            ?? HelpLibrary.topics.first
    }

    var body: some View {
        HSplitView {
            topicSidebar
                .frame(minWidth: 190, idealWidth: 220, maxWidth: 280)
            detailPane
                .frame(minWidth: 420, maxWidth: .infinity)
        }
        .frame(minWidth: 680, minHeight: 440)
        .background(TanqueDS.Color.surface0)
        .preferredColorScheme(.dark)
    }

    private var topicSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                Text("Topics")
                    .tanqueSectionLabel()
                    .padding(.horizontal, 12)
                    .padding(.top, 14)
                    .padding(.bottom, 6)

                ForEach(HelpLibrary.topics) { topic in
                    let isSelected = topic.id == selectedTopic?.id
                    Button {
                        router.selectedTopicID = topic.id
                    } label: {
                        Text(topic.title)
                            .font(TanqueDS.Font.navItem)
                            .foregroundStyle(isSelected ? TanqueDS.Color.textPrimary
                                                        : TanqueDS.Color.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(isSelected ? TanqueDS.Color.brassSubtle : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: TanqueDS.Layout.inputCornerRadius))
                            .overlay(alignment: .leading) {
                                if isSelected {
                                    Rectangle()
                                        .fill(TanqueDS.Color.brass)
                                        .frame(width: 2)
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 6)
                }
            }
            .padding(.bottom, 12)
        }
        .frame(maxHeight: .infinity)
        .background(TanqueDS.Color.surface1)
    }

    private var detailPane: some View {
        ScrollView {
            if let topic = selectedTopic {
                HelpMarkdownView(markdown: topic.markdown)
                    .padding(28)
                    .frame(maxWidth: 640, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(topic.id)   // reset scroll position on topic change
            } else {
                Text("No help topics bundled.")
                    .font(TanqueDS.Font.body)
                    .foregroundStyle(TanqueDS.Color.textMuted)
                    .padding(28)
            }
        }
        .background(TanqueDS.Color.surface0)
    }
}

// MARK: - Markdown block model

/// Deliberately dumb renderer for the bundled Help pages: the content is
/// controlled, not arbitrary. Splits into block segments and renders each
/// with TanqueDS type styles; inline styling (bold, code, links) comes from
/// `AttributedString(markdown:)` per block.
struct HelpMarkdownView: View {

    fileprivate enum Block: Identifiable {
        case heading(level: Int, text: String)
        case paragraph(String)
        case bullets([String])
        case numbered([(marker: String, text: String)])
        case code(String)

        var id: UUID { UUID() }
    }

    private let blocks: [Block]

    init(markdown: String) {
        blocks = Self.parse(markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(blocks) { block in
                blockView(block)
            }
        }
        .textSelection(.enabled)
        .tint(TanqueDS.Color.brass)
    }

    // MARK: Rendering

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(headingFont(level))
                .foregroundStyle(level == 2 ? TanqueDS.Color.brass : TanqueDS.Color.textPrimary)
                .padding(.top, level == 1 ? 0 : 8)

        case .paragraph(let text):
            Text(inline(text))
                .font(TanqueDS.Font.body)
                .foregroundStyle(TanqueDS.Color.textPrimary)
                .lineSpacing(3.5)
                .fixedSize(horizontal: false, vertical: true)

        case .bullets(let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .font(TanqueDS.Font.body)
                            .foregroundStyle(TanqueDS.Color.brass)
                        Text(inline(item))
                            .font(TanqueDS.Font.body)
                            .foregroundStyle(TanqueDS.Color.textPrimary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.leading, 4)

        case .numbered(let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text(item.marker)
                            .font(TanqueDS.Font.bodyMedium)
                            .foregroundStyle(TanqueDS.Color.brass)
                            .frame(minWidth: 18, alignment: .trailing)
                        Text(inline(item.text))
                            .font(TanqueDS.Font.body)
                            .foregroundStyle(TanqueDS.Color.textPrimary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.leading, 4)

        case .code(let text):
            Text(text)
                .font(TanqueDS.Font.bodySmall)
                .foregroundStyle(TanqueDS.Color.textPrimary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(TanqueDS.Color.surface2)
                .clipShape(RoundedRectangle(cornerRadius: TanqueDS.Layout.panelCornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: TanqueDS.Layout.panelCornerRadius)
                        .strokeBorder(TanqueDS.Color.surfaceBorder, lineWidth: 1)
                )
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1:  return TanqueDS.Font.monoSemiBold(19)
        case 2:  return TanqueDS.Font.monoSemiBold(14)
        default: return TanqueDS.Font.monoMedium(12.5)
        }
    }

    /// Inline markdown (bold, italic, code spans, links) via Foundation's parser.
    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }

    // MARK: Parsing

    fileprivate static func parse(_ markdown: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var bullets: [String] = []
        var numbered: [(String, String)] = []
        var codeLines: [String] = []
        var inCode = false

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph = []
            }
        }
        func flushLists() {
            if !bullets.isEmpty { blocks.append(.bullets(bullets)); bullets = [] }
            if !numbered.isEmpty { blocks.append(.numbered(numbered)); numbered = [] }
        }
        func flushAll() {
            flushParagraph()
            flushLists()
        }

        for rawLine in markdown.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                if inCode {
                    blocks.append(.code(codeLines.joined(separator: "\n")))
                    codeLines = []
                    inCode = false
                } else {
                    flushAll()
                    inCode = true
                }
                continue
            }
            if inCode {
                codeLines.append(rawLine)
                continue
            }

            if line.isEmpty {
                flushAll()
            } else if line.hasPrefix("#") {
                flushAll()
                let level = line.prefix(while: { $0 == "#" }).count
                let text = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                blocks.append(.heading(level: min(level, 3), text: text))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushParagraph()
                if !numbered.isEmpty { blocks.append(.numbered(numbered)); numbered = [] }
                bullets.append(String(line.dropFirst(2)))
            } else if let match = orderedItem(line) {
                flushParagraph()
                if !bullets.isEmpty { blocks.append(.bullets(bullets)); bullets = [] }
                numbered.append(match)
            } else if !bullets.isEmpty {
                // continuation of the previous bullet (soft-wrapped source line)
                bullets[bullets.count - 1] += " " + line
            } else if !numbered.isEmpty {
                numbered[numbered.count - 1].1 += " " + line
            } else {
                paragraph.append(line)
            }
        }
        if inCode, !codeLines.isEmpty { blocks.append(.code(codeLines.joined(separator: "\n"))) }
        flushAll()
        return blocks
    }

    /// Matches "1. text" ordered-list items; returns (marker, text).
    private static func orderedItem(_ line: String) -> (String, String)? {
        guard let dot = line.firstIndex(of: "."), dot != line.startIndex else { return nil }
        let head = line[line.startIndex..<dot]
        guard head.allSatisfy(\.isNumber) else { return nil }
        let rest = line[line.index(after: dot)...]
        guard rest.hasPrefix(" ") else { return nil }
        return (String(head) + ".", rest.trimmingCharacters(in: .whitespaces))
    }
}
