//
//  GenerateWorkbenchView.swift
//  DrawThingsStudio
//
//  Unified Generate Image workbench — sidebar + left panel + canvas + gallery + right panel.
//

import SwiftUI
import SwiftData
import Combine
import UniformTypeIdentifiers

// MARK: - Sidebar nav entries for the workbench

private struct WorkbenchNavEntry {
    let icon: String
    let label: String
    let item: SidebarItem
}

private let workbenchNavEntries: [WorkbenchNavEntry] = [
    WorkbenchNavEntry(icon: "photo.badge.plus",         label: "Generate",     item: .generateImage),
    WorkbenchNavEntry(icon: "cylinder.split.1x2",       label: "DT Projects",  item: .projectBrowser),
    WorkbenchNavEntry(icon: "hammer",                   label: "StoryFlow",    item: .workflow),
    WorkbenchNavEntry(icon: "book.pages",               label: "Story Studio", item: .storyStudio),
    WorkbenchNavEntry(icon: "photo.stack",              label: "Image Browser",item: .imageBrowser),
    WorkbenchNavEntry(icon: "gearshape",                label: "Preferences",  item: .settings),
]

// MARK: - Main View

struct GenerateWorkbenchView: View {
    @ObservedObject var viewModel: ImageGenerationViewModel
    @ObservedObject var storyStudioViewModel: StoryStudioViewModel
    @ObservedObject var inspectorViewModel: ImageInspectorViewModel
    @Binding var selectedSidebarItem: SidebarItem?
    var isActive: Bool = true

    @ObservedObject private var assetManager = DrawThingsAssetManager.shared
    @ObservedObject private var storageManager = ImageStorageManager.shared
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \ModelConfig.name) private var modelConfigs: [ModelConfig]

    // Layout
    @State private var isLeftPanelCollapsed = false

    // Canvas zoom/pan
    @State private var canvasZoomScale: CGFloat = 1.0
    @State private var canvasBaseZoom: CGFloat = 1.0
    @State private var canvasPanOffset: CGSize = .zero
    @State private var canvasLastPan: CGSize = .zero
    @State private var canvasSize: CGSize = .zero
    @State private var canvasZoomIndicatorVisible = false
    @State private var canvasZoomTask: Task<Void, Never>? = nil

    // Left panel state
    @State private var selectedPresetID: String = ""
    @State private var showingConfigImport = false
    @State private var showSourceImagePicker = false
    @State private var isSourceDropTargeted = false
    @State private var showEnhanceStylePicker = false
    @State private var showEnhanceStyleEditor = false
    @State private var enhanceError: String?
    @State private var importMessage: String?

    // Gallery
    @State private var galleryMode: GalleryMode = .history
    @State private var selectedGalleryImageID: UUID? = nil

    // Right panel
    @State private var rightPanelTab: RightPanelTab = .metadata
    @State private var droppedEntry: InspectedImage? = nil
    @State private var rightDropTargeted = false
    @State private var showSendBar = false
    @State private var rightPanelImmersive = false
    @State private var immersiveNavIndex: Int = 0

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar — 36pt fixed
            workbenchSidebar

            // Left panel — 210pt, hidden when collapsed
            if !isLeftPanelCollapsed {
                workbenchLeftPanel
                    .frame(width: 210)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            // Canvas — flexible
            workbenchCanvas
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Gallery strip — 88pt fixed
            workbenchGalleryStrip
                .frame(width: 88)

            // Right panel — 270pt fixed
            workbenchRightPanel
                .frame(width: 270)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .neuBackground()
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: isLeftPanelCollapsed)
        // Auto-select most recently generated image in gallery
        .onChange(of: storageManager.savedImages.count) { _, _ in
            if let first = storageManager.savedImages.first, selectedGalleryImageID == nil {
                selectedGalleryImageID = first.id
            }
        }
        .onChange(of: storageManager.savedImages.first?.id) { _, newID in
            if let id = newID { selectedGalleryImageID = id }
        }
        // Inspector Actions tab: "Send to Generate" — wired via inspectorViewModel signals
        .onChange(of: inspectorViewModel.pendingSendToGenerate) { _, req in
            guard let req else { return }
            viewModel.prompt = req.prompt
            viewModel.negativePrompt = req.negativePrompt
            viewModel.config = req.config
            if req.config.steps > 0 { viewModel.stepsText = "\(req.config.steps)" }
            if req.config.guidanceScale > 0 { viewModel.guidanceText = String(format: "%.1f", req.config.guidanceScale) }
            if req.config.shift > 0 { viewModel.shiftText = String(format: "%.1f", req.config.shift) }
            viewModel.loadInputImage(from: req.sourceImage, name: "Inspector Image")
            inspectorViewModel.pendingSendToGenerate = nil
        }
        .onChange(of: inspectorViewModel.pendingCropForGenerate) { _, cropped in
            guard let cropped else { return }
            viewModel.loadInputImage(from: cropped, name: "Cropped Image")
            inspectorViewModel.pendingCropForGenerate = nil
        }
        .onChange(of: inspectorViewModel.pendingInpaintForGenerate) { _, req in
            guard let req else { return }
            viewModel.loadInputImage(from: req.image, name: "Inpainting Source")
            viewModel.inputMask = req.mask
            inspectorViewModel.pendingInpaintForGenerate = nil
        }
        .onChange(of: inspectorViewModel.pendingAssistPrompt) { _, prompt in
            guard let prompt else { return }
            viewModel.prompt = prompt
            inspectorViewModel.pendingAssistPrompt = nil
        }
        .sheet(isPresented: $showEnhanceStyleEditor) {
            PromptStyleEditorView()
        }
        .background(
            Group {
                Color.clear
                    .fileImporter(isPresented: $showingConfigImport, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
                        handleConfigImport(result)
                    }
                Color.clear
                    .fileImporter(isPresented: $showSourceImagePicker, allowedContentTypes: [.png, .jpeg, .image], allowsMultipleSelection: false) { result in
                        if case .success(let urls) = result, let url = urls.first {
                            let hasAccess = url.startAccessingSecurityScopedResource()
                            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                            viewModel.loadInputImage(from: url)
                        }
                    }
            }
        )
    }

    // MARK: - Right Panel

    private enum RightPanelTab: String, CaseIterable { case metadata, assist, actions }

    // The entry to display in the right panel: dropped image takes priority over gallery selection
    private var rightPanelEntry: InspectedImage? {
        if let dropped = droppedEntry { return dropped }
        guard let gi = selectedGalleryImage else { return nil }
        return inspectedImage(from: gi)
    }

    private var rightPanelIsGenerated: Bool {
        droppedEntry == nil  // gallery selection is always generated; dropped may be imported
    }

    private func inspectedImage(from gi: GeneratedImage) -> InspectedImage {
        var meta = PNGMetadata()
        meta.prompt = gi.prompt.isEmpty ? nil : gi.prompt
        meta.negativePrompt = gi.negativePrompt.isEmpty ? nil : gi.negativePrompt
        meta.model = gi.config.model.isEmpty ? nil : gi.config.model
        meta.steps = gi.config.steps > 0 ? gi.config.steps : nil
        meta.guidanceScale = gi.config.guidanceScale > 0 ? gi.config.guidanceScale : nil
        meta.seed = gi.config.seed
        meta.sampler = gi.config.sampler.isEmpty ? nil : gi.config.sampler
        meta.width = gi.config.width > 0 ? gi.config.width : nil
        meta.height = gi.config.height > 0 ? gi.config.height : nil
        meta.shift = gi.config.shift > 0 ? gi.config.shift : nil
        meta.strength = gi.config.strength < 1.0 ? gi.config.strength : nil
        meta.seedMode = gi.config.seedMode.isEmpty ? nil : gi.config.seedMode
        meta.resolutionDependentShift = gi.config.resolutionDependentShift
        meta.loras = gi.config.loras.map { PNGMetadataLoRA(file: $0.file, weight: $0.weight) }
        meta.format = .drawThings
        return InspectedImage(
            image: gi.image,
            metadata: meta,
            sourceName: gi.config.model.isEmpty ? "Generated" : gi.config.model,
            inspectedAt: gi.generatedAt,
            source: .drawThings(projectURL: nil)
        )
    }

    private var workbenchRightPanel: some View {
        ZStack {
            VStack(spacing: 0) {
                // Inspect viewer (200pt)
                rightPanelViewer

                Divider()

                // Tab bar
                rightPanelTabBar

                Divider()

                // Tab content
                Group {
                    switch rightPanelTab {
                    case .metadata:
                        DTImageInspectorMetadataView(entry: rightPanelEntry)
                    case .assist:
                        DTImageInspectorAssistView(entry: rightPanelEntry, viewModel: inspectorViewModel)
                    case .actions:
                        DTImageInspectorActionsView(entry: rightPanelEntry, viewModel: inspectorViewModel)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Send bar (visible after drop)
                if showSendBar, let entry = droppedEntry {
                    Divider()
                    rightPanelSendBar(entry: entry)
                }

                // Drop zone (always visible)
                Divider()
                rightPanelDropZone
            }
            .background(
                rightPanelIsGenerated
                    ? Color.green.opacity(0.04)
                    : Color.gray.opacity(0.06)
            )
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.neuShadowDark.opacity(0.1))
                    .frame(width: 1)
            }

            // Immersive overlay
            if rightPanelImmersive {
                rightPanelImmersiveOverlay
            }
        }
    }

    private var rightPanelViewer: some View {
        ZStack(alignment: .topLeading) {
            if let entry = rightPanelEntry {
                Button {
                    // Build nav index for immersive
                    immersiveNavIndex = galleryImages.firstIndex { $0.id == selectedGalleryImageID } ?? 0
                    rightPanelImmersive = true
                } label: {
                    Image(nsImage: entry.image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            rightPanelIsGenerated
                                ? Color.green.opacity(0.08)
                                : Color.gray.opacity(0.08)
                        )
                }
                .buttonStyle(.plain)
                .help("Click to view full size")

                // Badge
                Text(droppedEntry != nil ? "Imported" : "Generated")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(droppedEntry != nil ? Color.gray.opacity(0.7) : Color.green.opacity(0.7))
                    )
                    .padding(8)
            } else {
                Color.gray.opacity(0.05)
                Text("Select an image")
                    .font(.caption2)
                    .foregroundColor(.neuTextSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: 200)
        .clipped()
    }

    private var rightPanelTabBar: some View {
        HStack(spacing: 0) {
            ForEach(RightPanelTab.allCases, id: \.self) { tab in
                Button {
                    rightPanelTab = tab
                } label: {
                    Text(tab.rawValue.capitalized)
                        .font(.system(size: 11, weight: rightPanelTab == tab ? .semibold : .regular))
                        .foregroundColor(rightPanelTab == tab ? .neuAccent : .neuTextSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .overlay(alignment: .bottom) {
                            if rightPanelTab == tab {
                                Rectangle()
                                    .fill(Color.neuAccent)
                                    .frame(height: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.neuSurface.opacity(0.5))
    }

    private var rightPanelDropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 0)
                .fill(rightDropTargeted ? Color.neuAccent.opacity(0.06) : Color.clear)

            HStack(spacing: 6) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.caption)
                    .foregroundColor(rightDropTargeted ? .neuAccent : .neuTextSecondary)
                Text("Drop image to inspect · click to browse")
                    .font(.system(size: 10))
                    .foregroundColor(rightDropTargeted ? .neuAccent : .neuTextSecondary)
            }
            .padding(.vertical, 12)
        }
        .frame(height: 48)
        .onDrop(of: [.image, .fileURL], isTargeted: $rightDropTargeted) { providers in
            handleRightPanelDrop(providers)
        }
        .onTapGesture {
            browseForRightPanelImage()
        }
        .overlay(
            Rectangle()
                .stroke(
                    rightDropTargeted ? Color.neuAccent.opacity(0.4) : Color.neuShadowDark.opacity(0.08),
                    style: StrokeStyle(lineWidth: 1, dash: rightDropTargeted ? [] : [4, 3])
                )
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func rightPanelSendBar(entry: InspectedImage) -> some View {
        VStack(spacing: 6) {
            Button {
                sendToGenerate(entry: entry, image: true, prompt: true, config: true)
            } label: {
                Text("Send all to Generate")
                    .font(.caption)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(NeumorphicButtonStyle(isProminent: true))

            HStack(spacing: 6) {
                Button("Image only") { sendToGenerate(entry: entry, image: true, prompt: false, config: false) }
                Button("Prompt only") { sendToGenerate(entry: entry, image: false, prompt: true, config: false) }
                Button("Config only") { sendToGenerate(entry: entry, image: false, prompt: false, config: true) }
            }
            .font(.caption2)
            .buttonStyle(NeumorphicButtonStyle())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.neuSurface.opacity(0.5))
    }

    private var rightPanelImmersiveOverlay: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()

            if let img = rightPanelEntry?.image {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(40)
                    .onTapGesture { rightPanelImmersive = false }
            }

            // ‹ › nav
            HStack {
                Button {
                    navigateImmersive(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 12)
                .disabled(galleryImages.isEmpty)

                Spacer()

                Button {
                    navigateImmersive(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.title2)
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
                .disabled(galleryImages.isEmpty)
            }
        }
        .onKeyPress(.leftArrow)  { navigateImmersive(by: -1); return .handled }
        .onKeyPress(.rightArrow) { navigateImmersive(by: 1);  return .handled }
    }

    private func navigateImmersive(by delta: Int) {
        guard !galleryImages.isEmpty else { return }
        immersiveNavIndex = (immersiveNavIndex + delta + galleryImages.count) % galleryImages.count
        selectedGalleryImageID = galleryImages[immersiveNavIndex].id
    }

    // MARK: - Right Panel Actions

    private func sendToGenerate(entry: InspectedImage, image: Bool, prompt: Bool, config: Bool) {
        if image { viewModel.loadInputImage(from: entry.image, name: entry.sourceName) }
        if prompt, let p = entry.metadata?.prompt { viewModel.prompt = p }
        if let meta = entry.metadata, config {
            if let model = meta.model { viewModel.config.model = model }
            if let steps = meta.steps { viewModel.config.steps = steps; viewModel.stepsText = "\(steps)" }
            if let cfg = meta.guidanceScale { viewModel.config.guidanceScale = cfg; viewModel.guidanceText = String(format: "%.1f", cfg) }
            if let shift = meta.shift { viewModel.config.shift = shift; viewModel.shiftText = String(format: "%.1f", shift) }
            if let seed = meta.seed { viewModel.config.seed = seed }
            if let sampler = meta.sampler { viewModel.config.sampler = sampler }
            if let w = meta.width { viewModel.config.width = w }
            if let h = meta.height { viewModel.config.height = h }
        }
    }

    private func handleRightPanelDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        Task {
            // Try file URL first
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                if let url = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? URL,
                   let image = NSImage(contentsOf: url) {
                    let meta = PNGMetadataParser.parse(url: url)
                    let entry = InspectedImage(image: image, metadata: meta, sourceName: url.lastPathComponent,
                                               inspectedAt: Date(), source: .imported(sourceURL: url))
                    await MainActor.run { droppedEntry = entry; showSendBar = true; rightPanelTab = .metadata }
                    return
                }
            }
            // Fallback: raw image data
            if provider.canLoadObject(ofClass: NSImage.self) {
                let image = try? await withCheckedThrowingContinuation { (cont: CheckedContinuation<NSImage?, Error>) in
                    provider.loadObject(ofClass: NSImage.self) { obj, err in
                        if let err { cont.resume(throwing: err) } else { cont.resume(returning: obj as? NSImage) }
                    }
                }
                if let image {
                    let entry = InspectedImage(image: image, metadata: nil, sourceName: "Dropped Image",
                                               inspectedAt: Date(), source: .imported(sourceURL: nil))
                    await MainActor.run { droppedEntry = entry; showSendBar = true; rightPanelTab = .metadata }
                }
            }
        }
        return true
    }

    private func browseForRightPanelImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let image = NSImage(contentsOf: url) else { return }
            let meta = PNGMetadataParser.parse(url: url)
            let entry = InspectedImage(image: image, metadata: meta, sourceName: url.lastPathComponent,
                                       inspectedAt: Date(), source: .imported(sourceURL: url))
            droppedEntry = entry
            showSendBar = true
            rightPanelTab = .metadata
        }
    }

    // MARK: - Gallery Strip

    private enum GalleryMode { case history, siblings }

    private var galleryImages: [GeneratedImage] {
        let all = storageManager.savedImages
        switch galleryMode {
        case .history:
            return all
        case .siblings:
            guard let sel = selectedGalleryImage else { return all }
            return all.filter { $0.prompt == sel.prompt }
        }
    }

    private var selectedGalleryImage: GeneratedImage? {
        guard let id = selectedGalleryImageID else { return nil }
        return storageManager.savedImages.first { $0.id == id }
    }

    private var workbenchGalleryStrip: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 2) {
                Text("Gallery")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color.green.opacity(0.85))

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        galleryMode = galleryMode == .history ? .siblings : .history
                    }
                } label: {
                    Text(galleryMode == .history ? "History" : "Siblings")
                        .font(.system(size: 9))
                        .foregroundColor(Color.green.opacity(0.7))
                        .underline()
                }
                .buttonStyle(.plain)
                .help(galleryMode == .history ? "Switch to Siblings (same prompt)" : "Switch to History (all images)")
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Color.green.opacity(0.06))

            Divider()
                .overlay(Color.green.opacity(0.3))

            // Thumbnails
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 4) {
                    ForEach(galleryImages) { img in
                        let isSelected = selectedGalleryImageID == img.id
                        let isGenerated = true  // all storageManager images are generated by this app

                        Button {
                            selectedGalleryImageID = img.id
                            // Selecting a gallery thumbnail clears any dropped image
                            // so the right panel shows the gallery selection's metadata
                            droppedEntry = nil
                            showSendBar = false
                        } label: {
                            Image(nsImage: img.image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 76, height: 76)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(
                                            isSelected
                                                ? (isGenerated ? Color.green.opacity(0.9) : Color.gray.opacity(0.8))
                                                : (isGenerated ? Color.green.opacity(0.35) : Color.gray.opacity(0.3)),
                                            lineWidth: isSelected ? 3 : 2
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 6)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.vertical, 6)
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: galleryImages.count)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 0)
                .fill(Color.green.opacity(0.04))
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.green.opacity(0.25))
                .frame(width: 1)
        }
    }

    // MARK: - Canvas

    // Canvas shows the most recently generated image — gallery selection updates the right panel only
    private var canvasActiveImage: NSImage? {
        viewModel.generatedImages.first?.image
    }

    private var workbenchCanvas: some View {
        VStack(spacing: 0) {
            // Canvas toolbar
            HStack(spacing: 4) {
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.2)) {
                        canvasZoomScale = 1.0; canvasBaseZoom = 1.0
                        canvasPanOffset = .zero; canvasLastPan = .zero
                    }
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption)
                }
                .buttonStyle(NeumorphicIconButtonStyle())
                .help("Reset zoom")
                .disabled(canvasActiveImage == nil)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.neuSurface.opacity(0.7))

            Divider()

            // Stage
            GeometryReader { geo in
                ZStack {
                    Color.black

                    if let img = canvasActiveImage {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .scaleEffect(canvasZoomScale)
                            .offset(canvasPanOffset)
                            .allowsHitTesting(false)
                    } else {
                        canvasEmptyState
                    }

                    // Zoom indicator
                    if canvasZoomScale != 1.0 {
                        Text(String(format: "%.1f×", canvasZoomScale))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .padding(10)
                            .opacity(canvasZoomIndicatorVisible ? 1 : 0)
                            .animation(.easeOut(duration: 0.3), value: canvasZoomIndicatorVisible)
                    }

                    // Gesture overlay
                    Color.clear
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    canvasZoomScale = max(1.0, min(8.0, canvasBaseZoom * value))
                                    if canvasZoomScale <= 1.0 { canvasPanOffset = .zero; canvasLastPan = .zero }
                                    flashCanvasZoomIndicator()
                                }
                                .onEnded { value in
                                    canvasBaseZoom = max(1.0, min(8.0, canvasBaseZoom * value))
                                    canvasZoomScale = canvasBaseZoom
                                    if canvasZoomScale <= 1.0 { canvasPanOffset = .zero; canvasLastPan = .zero }
                                }
                        )
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 1)
                                .onChanged { value in
                                    guard canvasZoomScale > 1.0 else { return }
                                    canvasPanOffset = CGSize(
                                        width: canvasLastPan.width + value.translation.width,
                                        height: canvasLastPan.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in canvasLastPan = canvasPanOffset }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(response: 0.25)) {
                                canvasZoomScale = 1.0; canvasBaseZoom = 1.0
                                canvasPanOffset = .zero; canvasLastPan = .zero
                            }
                        }
                        .background(
                            ScrollWheelHandler(
                                onZoom: { delta, location in
                                    guard canvasActiveImage != nil else { return }
                                    let oldScale = canvasZoomScale
                                    let newScale = max(1.0, min(8.0, canvasZoomScale + delta * 0.05))
                                    guard newScale != oldScale else { return }
                                    let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                                    let ratio = newScale / oldScale
                                    let newPan = CGSize(
                                        width: (location.x - center.x) + (canvasPanOffset.width - (location.x - center.x)) * ratio,
                                        height: (center.y - location.y) + (canvasPanOffset.height - (center.y - location.y)) * ratio
                                    )
                                    withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.9)) {
                                        canvasZoomScale = newScale; canvasBaseZoom = newScale
                                        canvasPanOffset = newScale > 1.0 ? newPan : .zero
                                        canvasLastPan = canvasPanOffset
                                    }
                                    flashCanvasZoomIndicator()
                                },
                                onPan: { translation in
                                    guard canvasZoomScale > 1.0 else { return }
                                    let newPan = CGSize(
                                        width: canvasPanOffset.width + translation.width,
                                        height: canvasPanOffset.height - translation.height
                                    )
                                    canvasPanOffset = newPan; canvasLastPan = newPan
                                }
                            )
                        )
                }
                .onAppear { canvasSize = geo.size }
                .onChange(of: geo.size) { _, sz in canvasSize = sz }
            }
            .clipShape(Rectangle())

            Divider()

            // Footer bar
            canvasFooter
        }
    }

    private var canvasEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.2))
                .symbolEffect(.pulse, options: .repeating)
            Text("No Image Generated")
                .font(.caption)
                .foregroundColor(.white.opacity(0.35))
        }
    }

    private var canvasFooter: some View {
        HStack(spacing: 12) {
            if let selected = viewModel.selectedImage ?? viewModel.generatedImages.first {
                let cfg = selected.config
                Text("\(cfg.width)×\(cfg.height)")
                    .font(.caption2)
                    .foregroundColor(.neuTextSecondary)
                if !cfg.model.isEmpty {
                    Text(cfg.model)
                        .font(.caption2)
                        .foregroundColor(.neuTextSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text(selected.generatedAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.neuTextSecondary)
            } else {
                Text("Canvas")
                    .font(.caption2)
                    .foregroundColor(.neuTextSecondary)
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.neuSurface.opacity(0.7))
    }

    private func flashCanvasZoomIndicator() {
        canvasZoomIndicatorVisible = true
        canvasZoomTask?.cancel()
        canvasZoomTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            canvasZoomIndicatorVisible = false
        }
    }

    // MARK: - Sidebar

    private var workbenchSidebar: some View {
        VStack(spacing: 0) {
            // Collapse/expand toggle
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    isLeftPanelCollapsed.toggle()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.neuTextSecondary)
                    .rotationEffect(.degrees(isLeftPanelCollapsed ? 180 : 0))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
            .help(isLeftPanelCollapsed ? "Expand panel" : "Collapse panel")

            Divider()
                .padding(.vertical, 6)
                .padding(.horizontal, 6)

            // Nav icons
            ForEach(workbenchNavEntries, id: \.item.rawValue) { entry in
                let isActiveItem = selectedSidebarItem == entry.item
                Button {
                    if !isActiveItem {
                        selectedSidebarItem = entry.item
                    }
                } label: {
                    Image(systemName: entry.icon)
                        .font(.system(size: 14))
                        .foregroundColor(isActiveItem ? .neuAccent : .neuTextSecondary)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(isActiveItem ? Color.neuAccent.opacity(0.15) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help(entry.label)
                .padding(.vertical, 2)
            }

            Spacer()
        }
        .frame(width: 36)
        .background(Color.neuSurface.opacity(0.6))
    }

    // MARK: - Left Panel

    private var workbenchLeftPanel: some View {
        VStack(spacing: 0) {
            // Header: prompt + buttons
            leftPanelHeader

            Divider()

            // Config form
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    leftPanelConfigForm
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            }
        }
        .background(Color.neuSurface.opacity(0.4))
        .overlay(alignment: .trailing) {
            Divider()
        }
    }

    private var leftPanelHeader: some View {
        VStack(spacing: 8) {
            // Prompt
            TextEditor(text: $viewModel.prompt)
                .font(.caption)
                .frame(minHeight: 64, maxHeight: 120)
                .padding(6)
                .scrollContentBackground(.hidden)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.neuBackground.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.neuShadowDark.opacity(0.1), lineWidth: 0.5)
                )
                .accessibilityIdentifier("workbench_promptField")

            // Generate + Enhance
            if viewModel.isGenerating {
                VStack(spacing: 4) {
                    NeumorphicProgressBar(value: viewModel.progressFraction)
                    Text(viewModel.progress.description)
                        .font(.caption2)
                        .foregroundColor(.neuTextSecondary)
                }
                Button("Cancel") { viewModel.cancelGeneration() }
                    .buttonStyle(NeumorphicButtonStyle())
                    .controlSize(.small)
            } else {
                HStack(spacing: 6) {
                    Button(action: { viewModel.generateOrRunPipeline() }) {
                        HStack(spacing: 4) {
                            Image(systemName: viewModel.inputImage != nil ? "photo.on.rectangle.angled" : "wand.and.stars")
                            Text("Generate")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NeumorphicButtonStyle(isProminent: true))
                    .controlSize(.regular)
                    .disabled(viewModel.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              viewModel.config.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityIdentifier("workbench_generateButton")

                    if viewModel.isEnhancing {
                        ProgressView().scaleEffect(0.7).frame(width: 36)
                    } else {
                        Button {
                            showEnhanceStylePicker = true
                        } label: {
                            Label("Enhance", systemImage: "sparkles")
                                .labelStyle(.iconOnly)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(NeumorphicButtonStyle())
                        .disabled(viewModel.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help("Enhance prompt with AI")
                        .popover(isPresented: $showEnhanceStylePicker) {
                            leftPanelEnhanceStylePicker
                        }
                    }
                }
            }

            if let error = enhanceError {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.red)
            }
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }
        }
        .padding(10)
    }

    private var leftPanelEnhanceStylePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Enhance Style").font(.headline)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(PromptStyleManager.shared.styles) { style in
                        Button {
                            showEnhanceStylePicker = false
                            runEnhance(style: style)
                        } label: {
                            HStack {
                                Image(systemName: style.icon).frame(width: 24)
                                Text(style.name)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                    }
                }
            }
            .frame(maxHeight: 240)
            Divider()
            Button { showEnhanceStylePicker = false; showEnhanceStyleEditor = true } label: {
                HStack { Image(systemName: "pencil").frame(width: 24); Text("Edit Styles..."); Spacer() }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
        }
        .padding()
        .frame(width: 280)
    }

    @ViewBuilder
    private var leftPanelConfigForm: some View {
        // Model
        ModelSelectorView(
            availableModels: assetManager.allModels,
            selection: $viewModel.config.model,
            isLoading: assetManager.isLoading || assetManager.isCloudLoading,
            onRefresh: { Task { await assetManager.forceRefresh() } }
        )

        // Sampler
        VStack(alignment: .leading, spacing: 4) {
            Text("Sampler").font(.caption).foregroundColor(.neuTextSecondary)
            SimpleSearchableDropdown(
                title: "Sampler",
                items: DrawThingsSampler.builtIn.map { $0.name },
                selection: $viewModel.config.sampler,
                placeholder: "Search samplers..."
            )
        }

        // Dimensions
        HStack(spacing: 8) {
            wbConfigField("W", value: $viewModel.config.width)
            wbConfigField("H", value: $viewModel.config.height)
        }

        // Steps & Guidance
        HStack(spacing: 8) {
            wbSweepIntField("Steps", text: $viewModel.stepsText) { viewModel.config.steps = $0 }
            wbSweepDoubleField("CFG", text: $viewModel.guidanceText) { viewModel.config.guidanceScale = $0 }
        }

        // Seed
        VStack(alignment: .leading, spacing: 4) {
            Text("Seed").font(.caption).foregroundColor(.neuTextSecondary)
            TextField("", value: $viewModel.config.seed, format: .number.grouping(.never))
                .textFieldStyle(NeumorphicTextFieldStyle())
        }

        // Shift
        wbSweepDoubleField("Shift", text: $viewModel.shiftText) { viewModel.config.shift = $0 }

        // Strength (img2img)
        VStack(alignment: .leading, spacing: 4) {
            Text("Strength").font(.caption).foregroundColor(.neuTextSecondary)
            HStack(spacing: 6) {
                Slider(value: $viewModel.config.strength, in: 0...1, step: 0.05)
                    .tint(Color.neuAccent)
                Text(String(format: "%.2f", viewModel.config.strength))
                    .font(.caption2)
                    .foregroundColor(.neuTextSecondary)
                    .frame(width: 30)
            }
        }

        // LoRAs
        Divider()
        LoRAConfigurationView(
            availableLoRAs: assetManager.loras,
            selectedLoRAs: $viewModel.config.loras
        )
    }

    // MARK: - Left Panel Helpers

    private func wbConfigField(_ label: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundColor(.neuTextSecondary)
            TextField("", value: value, format: .number)
                .textFieldStyle(NeumorphicTextFieldStyle())
        }
    }

    @ViewBuilder
    private func wbSweepIntField(_ label: String, text: Binding<String>, onSingleValue: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundColor(.neuTextSecondary)
            TextField("", text: text)
                .textFieldStyle(NeumorphicTextFieldStyle())
                .onChange(of: text.wrappedValue) { _, new in
                    if let vals = SweepParser.parseInts(new), vals.count == 1 { onSingleValue(vals[0]) }
                }
            if let count = SweepParser.sweepCount(ints: text.wrappedValue) {
                Text("×\(count)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.neuAccent)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Color.neuAccent.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
    }

    @ViewBuilder
    private func wbSweepDoubleField(_ label: String, text: Binding<String>, onSingleValue: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundColor(.neuTextSecondary)
            TextField("", text: text)
                .textFieldStyle(NeumorphicTextFieldStyle())
                .onChange(of: text.wrappedValue) { _, new in
                    if let vals = SweepParser.parseDoubles(new), vals.count == 1 { onSingleValue(vals[0]) }
                }
            if let count = SweepParser.sweepCount(doubles: text.wrappedValue) {
                Text("×\(count)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.neuAccent)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Color.neuAccent.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
    }

    private func runEnhance(style: CustomPromptStyle) {
        enhanceError = nil
        Task {
            do {
                let result = try await viewModel.enhancePrompt(viewModel.prompt, customStyle: style)
                let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    enhanceError = "Enhancement returned empty result"
                } else {
                    viewModel.prompt = trimmed
                }
            } catch {
                enhanceError = error.localizedDescription
            }
        }
    }

    private func handleConfigImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let presets = try ConfigPresetsManager.shared.importPresetsFromData(data)
                for preset in presets { modelContext.insert(preset.toModelConfig()) }
                importMessage = "Imported \(presets.count) preset(s)"
            } catch {
                importMessage = "Import failed: \(error.localizedDescription)"
            }
        case .failure(let error):
            importMessage = "Import failed: \(error.localizedDescription)"
        }
    }
}
