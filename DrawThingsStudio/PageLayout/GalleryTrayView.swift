//
//  GalleryTrayView.swift
//  TanqueStudio
//
//  Page Layout, Phase 1a: recent gallery images beside the page canvas.
//  The app's old gallery strip (`GalleryStripView`) is no longer shown
//  anywhere, and the Focus Room filmstrip is never on screen with Story Studio,
//  so this tray is the gallery's drag source for panels. Each image drags as
//  its file URL; a click places it in the selected panel.
//

import SwiftUI
import SwiftData

struct GalleryTrayView: View {
    /// Nil when no panel is selected (click does nothing then; drag still works).
    let onPlace: ((TSImage) -> Void)?

    @Query(sort: \TSImage.createdAt, order: .reverse) private var images: [TSImage]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Gallery").tanqueSectionLabel()
                Spacer()
                Text(onPlace == nil ? "drag onto a panel" : "click to place · or drag")
                    .font(TanqueDS.Font.badgeLabel)
                    .foregroundStyle(TanqueDS.Color.textMuted)
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 5)], spacing: 5) {
                    ForEach(images.prefix(80)) { image in
                        cell(image)
                    }
                }
            }
        }
        .padding(TanqueDS.Spacing.md)
        .background(TanqueDS.Color.surface1)
    }

    private func cell(_ image: TSImage) -> some View {
        Button {
            onPlace?(image)
        } label: {
            Group {
                if let data = image.thumbnailData, let ns = NSImage(data: data) {
                    Image(nsImage: ns).resizable().aspectRatio(contentMode: .fill)
                } else {
                    TanqueDS.Color.surface2
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(TanqueDS.Color.surfaceBorder, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .draggable(URL(fileURLWithPath: image.filePath))
        .accessibilityLabel("Gallery image \(image.createdAt.formatted(date: .abbreviated, time: .shortened))")
    }
}
