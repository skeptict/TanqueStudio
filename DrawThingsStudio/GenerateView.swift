import SwiftUI
import AppKit
import SwiftData

// MARK: - Root View

struct GenerateView: View {
    let vm: GenerateViewModel
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                GenerateLeftPanel(vm: vm)
                    .frame(width: vm.leftPanelWidth)

                PanelDragHandle(
                    width: Binding(get: { vm.leftPanelWidth },  set: { vm.leftPanelWidth  = $0 }),
                    minWidth: 200, maxWidth: 440,
                    isLeadingPanel: true
                )

                GenerateCenterPanel(vm: vm)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                PanelDragHandle(
                    width: Binding(get: { vm.galleryStripWidth }, set: { vm.galleryStripWidth = $0 }),
                    minWidth: 80, maxWidth: 200,
                    isLeadingPanel: false
                )

                GalleryStripView(vm: vm)
                    .frame(width: vm.galleryStripWidth)

                PanelDragHandle(
                    width: Binding(get: { vm.rightPanelWidth }, set: { vm.rightPanelWidth = $0 }),
                    minWidth: 240, maxWidth: 440,
                    isLeadingPanel: false
                )

                GenerateRightPanel(vm: vm)
                    .frame(width: vm.rightPanelWidth)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if vm.showImmersive, let image = vm.generatedImage {
                ImmersiveOverlay(image: image, onDismiss: { vm.showImmersive = false })
            }
        }
        .onAppear { vm.loadAssets() }
        .onChange(of: vm.lastGenerationID) { _, id in
            guard id != nil, AppSettings.shared.autoSaveGenerated else { return }
            vm.saveCurrentImage(in: modelContext, source: .generated)
        }
    }
}

// MARK: - Center Panel

private struct GenerateCenterPanel: View {
    @Bindable var vm: GenerateViewModel
    @State private var isDropTargeted = false

    var body: some View {
        ZStack {
            Color.black

            if let image = vm.generatedImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(16)
                    .onTapGesture { vm.showImmersive = true }
            } else {
                emptyState
            }

            if vm.isGenerating {
                progressOverlay
            }

            if let error = vm.errorMessage {
                errorBanner(error)
            }

            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            let ext = url.pathExtension.lowercased()
            guard ext == "png" || ext == "jpg" || ext == "jpeg" else { return false }
            vm.handleDroppedImageURL(url)
            return true
        } isTargeted: { isDropTargeted = $0 }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No image yet")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Generate or drop a PNG here")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var progressOverlay: some View {
        VStack(spacing: 10) {
            ProgressView(value: vm.progress.fraction)
                .progressViewStyle(.linear)
                .frame(maxWidth: 200)
            Text(vm.progress.description)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Cancel") { vm.cancelGeneration() }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.red)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func errorBanner(_ message: String) -> some View {
        VStack {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(message)
                    .font(.caption)
                    .lineLimit(3)
                Spacer()
                Button {
                    vm.errorMessage = nil
                } label: {
                    Image(systemName: "xmark").font(.caption)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding()
            Spacer()
        }
    }
}

// MARK: - Immersive Overlay

private struct ImmersiveOverlay: View {
    let image: NSImage
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.92)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(32)
                .allowsHitTesting(false)
        }
        .transition(.opacity.animation(.easeInOut(duration: 0.15)))
        .zIndex(999)
    }
}

// MARK: - Panel Drag Handle

struct PanelDragHandle: View {
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    /// true = handle on the right edge of the left panel (drag right = wider)
    /// false = handle on the left edge of the right panel (drag right = narrower)
    let isLeadingPanel: Bool

    @State private var isHovered = false
    @State private var dragStart: CGFloat?

    var body: some View {
        ZStack {
            Color.clear
                .frame(width: 12)
                .contentShape(Rectangle())
                .onHover { hovering in
                    isHovered = hovering
                    if hovering {
                        NSCursor.resizeLeftRight.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if dragStart == nil { dragStart = width }
                            let base = dragStart ?? width
                            let delta = isLeadingPanel
                                ? value.translation.width
                                : -value.translation.width
                            width = min(maxWidth, max(minWidth, base + delta))
                        }
                        .onEnded { _ in dragStart = nil }
                )

            Rectangle()
                .fill(isHovered ? Color.primary.opacity(0.25) : Color.primary.opacity(0.07))
                .frame(width: 1)
                .allowsHitTesting(false)
        }
    }
}
