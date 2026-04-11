import SwiftUI
import AppKit
import Combine
import SwiftData

// MARK: - Root View

struct GenerateView: View {
    let vm: GenerateViewModel
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TSImage.createdAt, order: .reverse) private var savedImages: [TSImage]

    @State private var toastMessage: String? = nil
    @State private var toastTask: Task<Void, Never>? = nil

    private func showToast(_ message: String) {
        toastTask?.cancel()
        toastMessage = message
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation { toastMessage = nil }
        }
    }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                // Left panel — fixed 260pt, collapses to 0
                ZStack(alignment: .topTrailing) {
                    GenerateLeftPanel(vm: vm)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { vm.leftPanelCollapsed = true }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(6)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    .padding(.trailing, 4)
                }
                .frame(width: vm.leftPanelCollapsed ? 0 : 260)
                .clipped()

                GenerateCenterPanel(vm: vm)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .topLeading) {
                        if vm.leftPanelCollapsed {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { vm.leftPanelCollapsed = false }
                            } label: {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(6)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 4)
                            .padding(.top, 8)
                            .transition(.opacity)
                        }
                    }

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

                GenerateRightPanel(vm: vm, onToast: showToast)
                    .frame(width: vm.rightPanelWidth)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let msg = toastMessage {
                VStack {
                    Spacer()
                    Text(msg)
                        .font(.callout)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .shadow(radius: 4)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .allowsHitTesting(false)
                .animation(.spring(duration: 0.3), value: toastMessage)
            }

            if vm.showImmersive {
                ImmersiveOverlay(vm: vm, savedImages: savedImages, onDismiss: { vm.showImmersive = false })
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

    @State private var canvasScale: CGFloat = 1.0
    @State private var canvasOffset: CGSize  = .zero
    @State private var lastScale: CGFloat    = 1.0
    @State private var lastOffset: CGSize    = .zero

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                canvasScale = min(6.0, max(0.5, lastScale * value))
            }
            .onEnded { _ in
                if abs(canvasScale - 1.0) < 0.05 {
                    withAnimation(.spring(response: 0.3)) {
                        canvasScale  = 1.0
                        canvasOffset = .zero
                        lastOffset   = .zero
                    }
                }
                lastScale = canvasScale
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard canvasScale > 1.05 else { return }
                canvasOffset = CGSize(
                    width:  lastOffset.width  + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in lastOffset = canvasOffset }
    }

    private var doubleTapGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                withAnimation(.spring(response: 0.3)) {
                    canvasScale  = 1.0
                    canvasOffset = .zero
                    lastScale    = 1.0
                    lastOffset   = .zero
                }
            }
    }

    private func resetZoom() {
        canvasScale  = 1.0
        canvasOffset = .zero
        lastScale    = 1.0
        lastOffset   = .zero
    }

    var body: some View {
        ZStack {
            Color.black

            if let image = vm.generatedImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(16)
                    .scaleEffect(canvasScale)
                    .offset(canvasOffset)
                    .onTapGesture { vm.showImmersive = true }
                    .simultaneousGesture(magnificationGesture)
                    .simultaneousGesture(dragGesture)
                    .simultaneousGesture(doubleTapGesture)
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

            // Zoom indicator
            VStack {
                Spacer()
                Text("\(Int(canvasScale * 100))%")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .padding(.bottom, 10)
                    .opacity(abs(canvasScale - 1.0) < 0.01 ? 0 : 1)
                    .animation(.easeInOut(duration: 0.2), value: canvasScale)
            }
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            let ext = url.pathExtension.lowercased()
            guard ext == "png" || ext == "jpg" || ext == "jpeg" else { return false }
            vm.handleDroppedImageURL(url)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .onChange(of: vm.generatedImage) { _, _ in resetZoom() }
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

// MARK: - Key Event Monitor

/// Ties NSEvent monitor lifetime to ARC — deinit always removes the monitor.
private final class KeyEventMonitor: ObservableObject {
    var monitor: Any?
    deinit { if let m = monitor { NSEvent.removeMonitor(m) } }
}

// MARK: - Immersive Overlay

private struct ImmersiveOverlay: View {
    let vm: GenerateViewModel
    let savedImages: [TSImage]
    let onDismiss: () -> Void

    @StateObject private var keyMonitor = KeyEventMonitor()

    private var currentIndex: Int? {
        guard let id = vm.selectedGalleryID else { return nil }
        return savedImages.firstIndex(where: { $0.id == id })
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.95)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            if let image = vm.generatedImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(currentIndex != nil ? 80 : 48)
                    .allowsHitTesting(false)
            }

            // Navigation arrows — only when current image is in the gallery
            if let idx = currentIndex {
                HStack {
                    navButton(systemName: "chevron.left.circle.fill", enabled: idx > 0) {
                        if idx > 0 { Self.navigate(to: savedImages[idx - 1], vm: vm) }
                    }
                    Spacer()
                    navButton(systemName: "chevron.right.circle.fill", enabled: idx < savedImages.count - 1) {
                        if idx < savedImages.count - 1 { Self.navigate(to: savedImages[idx + 1], vm: vm) }
                    }
                }
                .padding(.horizontal, 16)
            }

            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 26))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color.white.opacity(0.9), Color.white.opacity(0.15))
                    }
                    .buttonStyle(.plain)
                    .padding(20)
                }
                Spacer()
            }
        }
        .transition(.opacity.animation(.easeInOut(duration: 0.15)))
        .zIndex(999)
        .onAppear {
            let vm = self.vm
            let images = self.savedImages
            let dismiss = self.onDismiss
            keyMonitor.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                switch event.keyCode {
                case 53:   // Escape
                    dismiss()
                    return nil
                case 123:  // Left arrow
                    if let id = vm.selectedGalleryID,
                       let idx = images.firstIndex(where: { $0.id == id }),
                       idx > 0 {
                        Self.navigate(to: images[idx - 1], vm: vm)
                    }
                    return nil
                case 124:  // Right arrow
                    if let id = vm.selectedGalleryID,
                       let idx = images.firstIndex(where: { $0.id == id }),
                       idx < images.count - 1 {
                        Self.navigate(to: images[idx + 1], vm: vm)
                    }
                    return nil
                default:
                    return event
                }
            }
        }
        .onDisappear {
            if let m = keyMonitor.monitor { NSEvent.removeMonitor(m); keyMonitor.monitor = nil }
        }
    }

    @ViewBuilder
    private func navButton(systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        if enabled {
            Button(action: action) {
                Image(systemName: systemName)
                    .font(.system(size: 40))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.white.opacity(0.85), Color.white.opacity(0.18))
            }
            .buttonStyle(.plain)
        } else {
            Color.clear.frame(width: 56, height: 56)
        }
    }

    /// Load a gallery image into the ViewModel (updates generatedImage, metadata, selection).
    private static func navigate(to tsImage: TSImage, vm: GenerateViewModel) {
        let url = URL(fileURLWithPath: tsImage.filePath)
        guard FileManager.default.fileExists(atPath: tsImage.filePath),
              let data = try? Data(contentsOf: url),
              let image = NSImage(data: data) else { return }
        vm.generatedImage   = image
        vm.selectedGalleryID = tsImage.id
        vm.currentImageSource = tsImage.source
        if let json = tsImage.configJSON, let meta = metadataFromJSON(json) {
            vm.currentMetadata = meta
        } else if tsImage.source == .imported {
            vm.currentMetadata = PNGMetadataParser.parse(url: url)
        } else {
            vm.currentMetadata = nil
        }
    }

    private static func metadataFromJSON(_ json: String) -> PNGMetadata? {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var m = PNGMetadata()
        m.prompt         = dict["prompt"]         as? String
        m.negativePrompt = dict["negativePrompt"] as? String
        m.model          = dict["model"]          as? String
        m.sampler        = dict["sampler"]        as? String
        m.steps          = (dict["steps"]         as? NSNumber)?.intValue
        m.guidanceScale  = (dict["guidanceScale"] as? NSNumber)?.doubleValue
        m.seed           = (dict["seed"]          as? NSNumber)?.intValue
        m.seedMode       = dict["seedMode"]       as? String
        m.width          = (dict["width"]         as? NSNumber)?.intValue
        m.height         = (dict["height"]        as? NSNumber)?.intValue
        m.shift          = (dict["shift"]         as? NSNumber)?.doubleValue
        m.strength       = (dict["strength"]      as? NSNumber)?.doubleValue
        if let loras = dict["loras"] as? [[String: Any]] {
            m.loras = loras.compactMap { d in
                guard let file   = d["file"]   as? String,
                      let weight = d["weight"] as? Double else { return nil }
                return PNGMetadataLoRA(file: file, weight: weight)
            }
        }
        m.format = .drawThings
        return m
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
                            withAnimation(.interactiveSpring()) {
                                width = min(maxWidth, max(minWidth, base + delta))
                            }
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
