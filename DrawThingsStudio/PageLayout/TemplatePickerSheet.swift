//
//  TemplatePickerSheet.swift
//  TanqueStudio
//
//  Page Layout, Phase 1a: Add Page → choose a template that suits the
//  book format's orientation.
//

import SwiftUI
import AppKit

struct TemplatePickerSheet: View {
    let format: BookFormat
    let onPick: (PageTemplate) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var library = PageTemplateLibrary.all()

    private var suitable: [PageTemplate] {
        library.templates.filter { t in
            guard t.suits(format.orientation) else { return false }
            return format.isScroll ? t.kind == .scroll : t.kind != .scroll
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TanqueDS.Spacing.lg) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.split.3x1")
                    .foregroundStyle(TanqueDS.Color.brass)
                Text("Add Page")
                    .tanqueSectionLabel()
                Spacer()
                Text("\(format.preset.displayName)")
                    .font(TanqueDS.Font.bodySmall)
                    .foregroundStyle(TanqueDS.Color.textSecondary)
            }

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 14)], spacing: 14) {
                    ForEach(suitable) { template in
                        Button {
                            onPick(template)
                            dismiss()
                        } label: {
                            VStack(spacing: 6) {
                                TemplateDiagram(template: template, format: format)
                                    .frame(height: 120)
                                Text(template.name)
                                    .font(TanqueDS.Font.bodySmall)
                                    .foregroundStyle(TanqueDS.Color.textPrimary)
                                Text(detail(template))
                                    .font(TanqueDS.Font.badgeLabel)
                                    .foregroundStyle(TanqueDS.Color.textMuted)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .background(TanqueDS.Color.surface2)
                            .clipShape(RoundedRectangle(cornerRadius: TanqueDS.Layout.panelCornerRadius))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Template \(template.name)")
                    }
                }
            }
            .frame(minHeight: 280)

            if !library.skipped.isEmpty {
                Text("Skipped \(library.skipped.count) user template(s): \(library.skipped.joined(separator: "; "))")
                    .font(TanqueDS.Font.bodySmall)
                    .foregroundStyle(TanqueDS.Color.brass)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Reveal Templates Folder") { revealFolder() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(TanqueDS.Color.brass)
                    .help("Your own templates: JSON files here appear in this list.")
                Button("Reload") { library = PageTemplateLibrary.all() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(TanqueDS.Color.textSecondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(TanqueDS.Spacing.lg)
        .frame(width: 620, height: 520)
        .background(TanqueDS.Color.surface1)
        // System controls take their colours from the scheme, not from
        // TanqueDS; this sheet is painted dark, so tell them.
        .environment(\.colorScheme, .dark)
    }

    private func detail(_ t: PageTemplate) -> String {
        let n = "\(t.panels.count) panel\(t.panels.count == 1 ? "" : "s")"
        return t.isSpread ? "spread · \(n)" : n
    }

    private func revealFolder() {
        guard let folder = PageTemplateLibrary.userFolder else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }
}

/// A template's panel layout drawn as plain rectangles at the format's shape.
struct TemplateDiagram: View {
    let template: PageTemplate
    let format: BookFormat

    var body: some View {
        let geo = PageGeometry(format: format, template: template)
        Canvas { ctx, size in
            let content = geo.bleedRect
            let scale = min(size.width / content.width, size.height / content.height)
            let drawn = CGSize(width: content.width * scale, height: content.height * scale)
            let ox = (size.width - drawn.width) / 2 - content.minX * scale
            let oy = (size.height - drawn.height) / 2 - content.minY * scale
            func map(_ r: CGRect) -> CGRect {
                CGRect(x: ox + r.minX * scale, y: oy + r.minY * scale, width: r.width * scale, height: r.height * scale)
            }
            ctx.fill(Path(map(geo.trimRect)), with: .color(.white.opacity(0.92)))
            for item in geo.panelRects {
                let r = map(item.rect).intersection(map(geo.bleedRect))
                ctx.fill(Path(r), with: .color(Color(white: 0.55)))
                ctx.stroke(Path(r), with: .color(.black), lineWidth: 1)
            }
            if let fold = geo.foldX {
                let r = map(CGRect(x: fold, y: geo.trimRect.minY, width: 0, height: geo.trimRect.height))
                var p = Path()
                p.move(to: CGPoint(x: r.minX, y: r.minY))
                p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
                ctx.stroke(p, with: .color(.purple), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            }
        }
    }
}
