//
//  ImageInspectorView.swift
//  DrawThingsStudio
//
//  PNG metadata inspector with drag-and-drop, history timeline, and Discord support
//

import SwiftUI
import UniformTypeIdentifiers

struct ImageInspectorView: View {
    @ObservedObject var viewModel: ImageInspectorViewModel
    @Environment(\.colorScheme) private var colorScheme

    @State private var lightboxImage: NSImage?

    // Layout state indicator
    @State private var stageIndicatorVisible = true
    @State private var stageHovering = false
    @State private var indicatorTask: Task<Void, Never>?

    // Zoom / pan
    @State private var zoomScale: CGFloat = 1.0
    @State private var baseZoom: CGFloat = 1.0       // zoomScale at start of pinch gesture
    @State private var panOffset: CGSize = .zero
    @State private var lastPanOffset: CGSize = .zero
    @State private var zoomIndicatorVisible = false
    @State private var zoomIndicatorTask: Task<Void, Never>?

    // Crop
    @State private var cropSelection: CGRect? = nil     // normalized 0–1 in image-display space (y=0 top)
    @State private var cropDragAnchor: CGPoint = .zero  // normalized start of drag
    @State private var activeHandle: CropHandle? = nil  // handle being dragged
    @State private var cropFeedback: String? = nil      // "Saved to Inspector" etc.
    @State private var cropFeedbackTask: Task<Void, Never>? = nil
    @State private var stageSize: CGSize = .zero        // updated by GeometryReader

    // Paint (inpainting mask)
    @State private var brushSize: CGFloat = 40
    @State private var isEraser: Bool = false
    @State private var brushCursorPosition: CGPoint? = nil
    @State private var hasPainted: Bool = false
    @State private var showClearMaskAlert: Bool = false
    @State private var showDiscardMaskAlert: Bool = false

    @State private var selectedRightTab: RightPanelTab = .metadata
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                collectionSidebar
                    .frame(width: leftColumnWidth)
                    .clipped()
                    .allowsHitTesting(leftColumnWidth > 0)

                imageStage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                rightPanel
                    .frame(width: rightColumnWidth)
                    .clipped()
                    .allowsHitTesting(rightColumnWidth > 0)
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: viewModel.layoutState)

            Divider()

            filmstripPlaceholder
                .frame(height: 104)
        }
        .padding(20)
        .neuBackground()
        .lightbox(image: $lightboxImage, browseList: viewModel.filteredHistory.map(\.image))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                layoutStatePicker
            }
        }
        .focusable()
        .focused($isFocused)
        .onKeyPress(.upArrow)    { viewModel.selectPrevious(); return .handled }
        .onKeyPress(.leftArrow)  { viewModel.selectPrevious(); return .handled }
        .onKeyPress(.downArrow)  { viewModel.selectNext(); return .handled }
        .onKeyPress(.rightArrow) { viewModel.selectNext(); return .handled }
        .onAppear { isFocused = true; scheduleIndicatorFade() }
        .onChange(of: viewModel.layoutState) {
            withAnimation(.easeIn(duration: 0.15)) { stageIndicatorVisible = true }
            scheduleIndicatorFade()
        }
        .onChange(of: viewModel.sourceFilter) {
            // If selected image is no longer visible under new filter, pick first visible
            if let selected = viewModel.selectedImage,
               !viewModel.filteredHistory.contains(where: { $0.id == selected.id }) {
                viewModel.selectedImage = viewModel.filteredHistory.first
            }
        }
        .onChange(of: viewModel.selectedImage?.id) { resetZoom(animated: false) }
        .alert("Clear the mask?", isPresented: $showClearMaskAlert) {
            Button("Clear", role: .destructive) {
                viewModel.clearMask()
                hasPainted = false
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The painted mask will be reset to black.")
        }
        .alert("Discard mask painting?", isPresented: $showDiscardMaskAlert) {
            Button("Discard", role: .destructive) {
                viewModel.stageMode = .view
            }
            Button("Keep Painting", role: .cancel) { }
        }
    }

    // MARK: - Column Widths

    private var leftColumnWidth: CGFloat {
        switch viewModel.layoutState {
        case .balanced:  return 200
        case .focus:     return 48
        case .immersive: return 0
        }
    }

    private var rightColumnWidth: CGFloat {
        switch viewModel.layoutState {
        case .balanced:  return 300
        case .focus:     return 44
        case .immersive: return 0
        }
    }

    // MARK: - Image Stage

    private var imageStage: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                // Black background
                Color.black
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Image with zoom/pan applied
                if let selected = viewModel.selectedImage {
                    Image(nsImage: selected.image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .scaleEffect(zoomScale)
                        .offset(panOffset)
                        .allowsHitTesting(false)
                } else {
                    stageEmptyState
                }

                // Crop selection overlay (rendered below gesture layer so handles are above)
                if viewModel.stageMode == .crop, let sel = cropSelection,
                   let imgSize = viewModel.selectedImage?.image.size {
                    cropSelectionOverlay(sel: sel, imageSize: imgSize)
                }

                // Mask overlay (paint mode) — screen blend makes black transparent
                if viewModel.stageMode == .paint, let maskImg = viewModel.maskImage {
                    Image(nsImage: maskImg)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .blendMode(.screen)
                        .opacity(0.7)
                        .scaleEffect(zoomScale)
                        .offset(panOffset)
                        .allowsHitTesting(false)
                }

                // Unified gesture overlay — sits above image/overlays, below handles/toolbar
                Color.clear
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                guard viewModel.stageMode == .view else { return }
                                zoomScale = max(1.0, min(8.0, baseZoom * value))
                                if zoomScale <= 1.0 { panOffset = .zero; lastPanOffset = .zero }
                                showZoomIndicator()
                            }
                            .onEnded { value in
                                guard viewModel.stageMode == .view else { return }
                                baseZoom = max(1.0, min(8.0, baseZoom * value))
                                zoomScale = baseZoom
                                if zoomScale <= 1.0 { panOffset = .zero; lastPanOffset = .zero }
                            }
                    )
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if viewModel.stageMode == .crop {
                                    guard let imgSize = viewModel.selectedImage?.image.size else { return }
                                    if activeHandle == nil {
                                        if let normStart = stageToNorm(value.startLocation, imageSize: imgSize) {
                                            let clamped = clampNorm(normStart)
                                            if let normCur = stageToNorm(value.location, imageSize: imgSize) {
                                                let clampedCur = clampNorm(normCur)
                                                cropSelection = CGRect(
                                                    x: min(clamped.x, clampedCur.x),
                                                    y: min(clamped.y, clampedCur.y),
                                                    width: abs(clampedCur.x - clamped.x),
                                                    height: abs(clampedCur.y - clamped.y)
                                                )
                                                cropDragAnchor = clamped
                                            }
                                        }
                                    }
                                } else if viewModel.stageMode == .paint {
                                    guard let imgSize = viewModel.selectedImage?.image.size else { return }
                                    if let normPt = stageToNorm(value.location, imageSize: imgSize) {
                                        let clamped = clampNorm(normPt)
                                        let radius = brushRadiusNorm(for: imgSize)
                                        viewModel.paintMask(at: clamped, brushRadiusNorm: radius, erasing: isEraser)
                                        hasPainted = true
                                    }
                                } else {
                                    guard zoomScale > 1.0 else { return }
                                    panOffset = CGSize(
                                        width: lastPanOffset.width + value.translation.width,
                                        height: lastPanOffset.height + value.translation.height
                                    )
                                }
                            }
                            .onEnded { value in
                                if viewModel.stageMode == .crop {
                                    if let sel = cropSelection, sel.width < 0.01 || sel.height < 0.01 {
                                        cropSelection = nil
                                    }
                                } else if viewModel.stageMode != .paint {
                                    lastPanOffset = panOffset
                                }
                            }
                    )
                    .onTapGesture(count: 2) {
                        guard viewModel.stageMode == .view else { return }
                        if zoomScale > 1.0 {
                            resetZoom()
                        } else if let selected = viewModel.selectedImage {
                            lightboxImage = selected.image
                        }
                    }
                    .onTapGesture(count: 1) {
                        guard viewModel.stageMode == .view else { return }
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            viewModel.layoutState = viewModel.layoutState.next()
                        }
                    }
                    .onHover { hovering in
                        stageHovering = hovering
                        if hovering {
                            indicatorTask?.cancel()
                            withAnimation(.easeIn(duration: 0.15)) { stageIndicatorVisible = true }
                            if viewModel.stageMode == .crop { NSCursor.crosshair.push() }
                        } else {
                            if viewModel.stageMode == .crop { NSCursor.pop() }
                            brushCursorPosition = nil
                            scheduleIndicatorFade()
                        }
                    }
                    .onContinuousHover(coordinateSpace: .local) { phase in
                        if case .active(let location) = phase, viewModel.stageMode == .paint {
                            brushCursorPosition = location
                        } else {
                            brushCursorPosition = nil
                        }
                    }
                    .background(
                        ScrollWheelHandler(
                            onZoom: { delta, locationInView in
                                // Mouse-wheel → cursor-centered zoom
                                guard viewModel.selectedImage != nil, viewModel.stageMode == .view else { return }
                                let oldScale = zoomScale
                                let newScale = max(1.0, min(8.0, zoomScale + delta * 0.05))
                                guard newScale != oldScale else { return }
                                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                                let cx = locationInView.x - center.x
                                let cy = center.y - locationInView.y
                                let ratio = newScale / oldScale
                                let newPan = CGSize(
                                    width:  cx + (panOffset.width  - cx) * ratio,
                                    height: cy + (panOffset.height - cy) * ratio
                                )
                                withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.9)) {
                                    zoomScale = newScale
                                    baseZoom  = newScale
                                    panOffset = newScale > 1.0 ? newPan : .zero
                                    lastPanOffset = panOffset
                                }
                                showZoomIndicator()
                            },
                            onPan: { translation in
                                // Trackpad two-finger scroll → pan (only when zoomed in)
                                guard viewModel.selectedImage != nil,
                                      viewModel.stageMode == .view,
                                      zoomScale > 1.0 else { return }
                                let newPan = CGSize(
                                    width:  panOffset.width  + translation.width,
                                    height: panOffset.height - translation.height  // flip Y: NSView y-up → SwiftUI y-down
                                )
                                panOffset = newPan
                                lastPanOffset = newPan
                            }
                        )
                    )

                // Crop resize handles
                if viewModel.stageMode == .crop, let sel = cropSelection,
                   let imgSize = viewModel.selectedImage?.image.size {
                    cropHandles(sel: sel, imageSize: imgSize)
                }

                // Brush cursor preview (paint mode, screen coords — no zoom/pan applied)
                if viewModel.stageMode == .paint, let cursorPos = brushCursorPosition {
                    Circle()
                        .stroke(Color.white.opacity(0.5), lineWidth: 1)
                        .frame(width: brushSize, height: brushSize)
                        .position(cursorPos)
                        .allowsHitTesting(false)
                }

                // Layout state indicator (bottom-left) — view mode only
                if viewModel.stageMode == .view {
                    Text(viewModel.layoutState.indicatorText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
                        .padding(.leading, 12)
                        .padding(.bottom, 12)
                        .opacity((stageIndicatorVisible || stageHovering) ? 1 : 0)
                        .animation(.easeOut(duration: 0.35), value: stageIndicatorVisible)
                        .animation(.easeOut(duration: 0.35), value: stageHovering)
                }

                // Zoom indicator (bottom-right) — view mode only
                if viewModel.stageMode == .view {
                    Text(String(format: "%.1f×", zoomScale))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 12)
                        .padding(.bottom, 12)
                        .opacity(zoomIndicatorVisible ? 1 : 0)
                        .animation(.easeOut(duration: 0.5), value: zoomIndicatorVisible)
                }

                // Crop confirmation bar
                if viewModel.stageMode == .crop {
                    cropConfirmationBar
                        .frame(maxWidth: .infinity, alignment: .bottom)
                        .padding(.bottom, 12)
                        .padding(.horizontal, 12)
                }

                // Paint mode toolbar overlay (bottom-left) + confirmation bar (bottom-center)
                if viewModel.stageMode == .paint {
                    paintModeToolbarOverlay
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(.leading, 12)
                        .padding(.bottom, 12)
                        .allowsHitTesting(true)

                    if hasPainted {
                        paintConfirmationBar
                            .frame(maxWidth: .infinity, alignment: .bottom)
                            .padding(.bottom, 12)
                            .padding(.horizontal, 180)  // give room for the paint toolbar on the left
                    }
                }

                // Stage mode toolbar — top-right, above all other overlays
                stageToolbar
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 10)
                    .padding(.trailing, 10)
                    .allowsHitTesting(true)
            }
            .onAppear { stageSize = geo.size }
            .onChange(of: geo.size) { _, new in stageSize = new }
        }
        .onChange(of: viewModel.stageMode) { _, newMode in
            if newMode != .crop { cropSelection = nil; activeHandle = nil }
            if newMode == .paint { hasPainted = false }
            if newMode != .paint { brushCursorPosition = nil }
        }
    }

    // MARK: - Crop Overlay

    @ViewBuilder
    private func cropSelectionOverlay(sel: CGRect, imageSize: CGSize) -> some View {
        let tl = normToStage(CGPoint(x: sel.minX, y: sel.minY), imageSize: imageSize)
        let br = normToStage(CGPoint(x: sel.maxX, y: sel.maxY), imageSize: imageSize)
        let rect = CGRect(x: tl.x, y: tl.y, width: br.x - tl.x, height: br.y - tl.y)

        Canvas { ctx, _ in
            // Semi-transparent fill
            let path = Path(rect)
            ctx.fill(path, with: .color(.white.opacity(0.15)))
            // Dashed border
            var dashed = path
            _ = dashed // suppress warning
            let strokedPath = Path(rect).strokedPath(StrokeStyle(lineWidth: 1.5, dash: [6, 3]))
            ctx.fill(strokedPath, with: .color(.white.opacity(0.85)))
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func cropHandles(sel: CGRect, imageSize: CGSize) -> some View {
        ForEach(CropHandle.allCases, id: \.self) { handle in
            let normPt  = handle.anchorPoint(in: sel)
            let screenPt = normToStage(normPt, imageSize: imageSize)
            let handleSize: CGFloat = 10

            Color.white
                .frame(width: handleSize, height: handleSize)
                .border(Color.black.opacity(0.4), width: 0.5)
                .position(x: screenPt.x, y: screenPt.y)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            activeHandle = handle
                            if let newNorm = stageToNorm(value.location, imageSize: imageSize) {
                                let clamped = clampNorm(newNorm)
                                if let current = cropSelection {
                                    cropSelection = handle.adjustedRect(current, newNorm: clamped)
                                }
                            }
                        }
                        .onEnded { _ in activeHandle = nil }
                )
                .allowsHitTesting(true)
        }
    }

    // MARK: - Crop Confirmation Bar

    @ViewBuilder
    private var cropConfirmationBar: some View {
        if let feedback = cropFeedback {
            Text(feedback)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
        } else if cropSelection != nil {
            HStack(spacing: 8) {
                Button("Save to Inspector") { cropSaveToInspector() }
                    .buttonStyle(ConfirmationBarButtonStyle())
                Button("Export to File") { cropExportToFile() }
                    .buttonStyle(ConfirmationBarButtonStyle())
                Button("Send to Generate") { cropSendToGenerate() }
                    .buttonStyle(ConfirmationBarButtonStyle(accent: true))
                Button("Cancel") { cropSelection = nil }
                    .buttonStyle(ConfirmationBarButtonStyle(destructive: true))
            }
            .padding(8)
            .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else {
            // Empty state hint
            Text("Drag to select a crop region")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - Paint Mode Overlay

    private var paintModeToolbarOverlay: some View {
        HStack(spacing: 10) {
            Text("Brush")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.75))

            Slider(value: $brushSize, in: 10...200)
                .frame(width: 100)
                .tint(.white.opacity(0.8))

            Text("\(Int(brushSize))pt")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 32, alignment: .leading)

            // Eraser toggle
            let eraserActive = isEraser
            Button {
                isEraser.toggle()
            } label: {
                Image(systemName: "eraser")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(eraserActive ? .accentColor : .white.opacity(0.75))
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(eraserActive ? Color.accentColor.opacity(0.25) : Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(eraserActive ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            .help("Eraser — paints black to unmask")

            // Clear button
            Button {
                showClearMaskAlert = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.75))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("Clear mask")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var paintConfirmationBar: some View {
        HStack(spacing: 8) {
            Button("Send to Draw Things") {
                viewModel.sendMaskToDrawThings()
            }
            .buttonStyle(ConfirmationBarButtonStyle(accent: true))

            Button("Clear") {
                showClearMaskAlert = true
            }
            .buttonStyle(ConfirmationBarButtonStyle())

            Button("Cancel") {
                if hasPainted {
                    showDiscardMaskAlert = true
                } else {
                    viewModel.stageMode = .view
                }
            }
            .buttonStyle(ConfirmationBarButtonStyle(destructive: true))
        }
        .padding(8)
        .background(Color.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: - Stage Toolbar

    private var stageToolbar: some View {
        HStack(spacing: 6) {
            stageModeButton(
                icon: "crop",
                mode: .crop,
                help: "Crop mode"
            )
            stageModeButton(
                icon: "paintbrush",
                mode: .paint,
                help: "Inpainting mask"
            )
        }
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func stageModeButton(icon: String, mode: StageMode, help: String) -> some View {
        let isActive = viewModel.stageMode == mode
        Button {
            viewModel.stageMode = isActive ? .view : mode
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isActive ? .accentColor : .white.opacity(0.75))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isActive ? Color.accentColor.opacity(0.25) : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(isActive ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .disabled(viewModel.selectedImage == nil)
    }

    private var stageEmptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.badge.arrow.down")
                .font(.system(size: 56))
                .foregroundColor(.white.opacity(0.2))
                .symbolEffect(.pulse, options: .repeating)
            Text("Drop an Image to Inspect")
                .font(.title3)
                .foregroundColor(.white.opacity(0.5))
            Text("Drag a PNG from Finder, Discord, or any app.\nSupports A1111/Forge, Draw Things, and ComfyUI metadata.")
                .font(.callout)
                .foregroundColor(.white.opacity(0.3))
                .multilineTextAlignment(.center)
            Button("Open File…") { openFilePanel() }
                .buttonStyle(NeumorphicButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Right Panel (tabbed)

    private var rightPanel: some View {
        Group {
            if viewModel.layoutState == .focus {
                rightFocusRail
            } else {
                rightPanelContent
            }
        }
        .neuCard(cornerRadius: 20)
    }

    private var rightFocusRail: some View {
        VStack(spacing: 12) {
            Spacer()
            ForEach(RightPanelTab.allCases, id: \.self) { tab in
                Button {
                    selectedRightTab = tab
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        viewModel.layoutState = .balanced
                    }
                } label: {
                    Image(systemName: tab.icon)
                        .font(.system(size: 14))
                        .foregroundColor(selectedRightTab == tab ? .neuAccent : .neuTextSecondary)
                }
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selectedRightTab == tab ? Color.neuAccent.opacity(0.12) : Color.clear)
                )
                .buttonStyle(.plain)
                .help(tab.label)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var rightPanelContent: some View {
        VStack(spacing: 0) {
            rightTabBar
            Divider()
            Group {
                switch selectedRightTab {
                case .metadata:
                    DTImageInspectorMetadataView(
                        entry: viewModel.selectedImage,
                        errorMessage: viewModel.errorMessage
                    )
                case .assist:
                    assistTabContent
                case .actions:
                    actionsTabContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var rightTabBar: some View {
        HStack(spacing: 0) {
            ForEach(RightPanelTab.allCases, id: \.self) { tab in
                Button { selectedRightTab = tab } label: {
                    VStack(spacing: 0) {
                        Spacer()
                        Text(tab.label)
                            .font(.system(size: 12, weight: selectedRightTab == tab ? .semibold : .regular))
                            .foregroundColor(
                                selectedRightTab == tab
                                    ? Color(NSColor.labelColor)
                                    : Color(NSColor.secondaryLabelColor)
                            )
                            .padding(.bottom, 7)
                        Rectangle()
                            .fill(selectedRightTab == tab ? Color.accentColor : Color.clear)
                            .frame(height: 1.5)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, minHeight: 36)
            }
        }
    }

    private var assistTabContent: some View {
        DTImageInspectorAssistView(entry: viewModel.selectedImage, viewModel: viewModel)
    }

    private var actionsTabContent: some View {
        DTImageInspectorActionsView(entry: viewModel.selectedImage, viewModel: viewModel)
    }

    // MARK: - Filmstrip

    private var filmstripPlaceholder: some View { filmstrip }

    private var filmstrip: some View {
        HStack(spacing: 0) {
            // SIBLINGS section
            if !viewModel.filmstripSiblings.isEmpty {
                // Pinned label
                Text("SIBLINGS")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.neuTextSecondary.opacity(0.6))
                    .kerning(0.4)
                    .frame(width: 52)
                    .rotationEffect(.degrees(-90))
                    .fixedSize()
                    .frame(width: 18)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(viewModel.filmstripSiblings) { entry in
                            FilmstripCell(
                                entry: entry,
                                isSelected: viewModel.selectedImage?.id == entry.id
                            )
                            .onTapGesture {
                                viewModel.selectedImage = entry
                                viewModel.errorMessage = nil
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }

                // Divider between sections
                Rectangle()
                    .fill(Color(NSColor.separatorColor).opacity(0.5))
                    .frame(width: 0.5, height: 56)
                    .padding(.horizontal, 4)
            }

            // HISTORY section
            if !viewModel.filmstripHistory.isEmpty {
                // Pinned label
                Text("HISTORY")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.neuTextSecondary.opacity(0.6))
                    .kerning(0.4)
                    .frame(width: 52)
                    .rotationEffect(.degrees(-90))
                    .fixedSize()
                    .frame(width: 18)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(viewModel.filmstripHistory) { entry in
                            FilmstripCell(
                                entry: entry,
                                isSelected: viewModel.selectedImage?.id == entry.id
                            )
                            .onTapGesture {
                                viewModel.selectedImage = entry
                                viewModel.errorMessage = nil
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
            } else if viewModel.filmstripSiblings.isEmpty {
                // Empty state — no images at all
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "film.stack")
                        .font(.caption)
                        .foregroundColor(.neuTextSecondary.opacity(0.3))
                    Text("Drop images to inspect")
                        .font(.caption2)
                        .foregroundColor(.neuTextSecondary.opacity(0.3))
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.neuBackground)
    }

    // MARK: - Layout Picker (Toolbar)

    private var layoutStatePicker: some View {
        HStack(spacing: 2) {
            ForEach(LayoutState.allCases, id: \.self) { state in
                Button(state.label) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        viewModel.layoutState = state
                    }
                }
                .buttonStyle(LayoutPillButtonStyle(isActive: viewModel.layoutState == state))
            }
        }
    }

    // MARK: - Indicator Timer

    private func scheduleIndicatorFade() {
        indicatorTask?.cancel()
        stageIndicatorVisible = true
        indicatorTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, !stageHovering else { return }
            withAnimation(.easeOut(duration: 0.4)) {
                stageIndicatorVisible = false
            }
        }
    }

    // MARK: - Zoom Helpers

    private func resetZoom(animated: Bool = true) {
        let apply = {
            zoomScale = 1.0
            baseZoom  = 1.0
            panOffset = .zero
            lastPanOffset = .zero
        }
        if animated {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { apply() }
        } else {
            apply()
        }
        zoomIndicatorVisible = false
        zoomIndicatorTask?.cancel()
    }

    private func showZoomIndicator() {
        zoomIndicatorVisible = true
        zoomIndicatorTask?.cancel()
        zoomIndicatorTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.5)) { zoomIndicatorVisible = false }
        }
    }

    // MARK: - Collection Sidebar (left column)

    private var collectionSidebar: some View {
        Group {
            if viewModel.layoutState == .focus {
                focusRailContent
            } else {
                balancedSidebarContent
            }
        }
        .neuCard(cornerRadius: 20)
    }

    private var balancedSidebarContent: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("COLLECTION")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.neuTextSecondary)
                    .kerning(0.5)
                Spacer()
                Button(action: importFilePanel) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.caption)
                }
                .buttonStyle(NeumorphicIconButtonStyle())
                .help("Import image")
                .accessibilityIdentifier("inspector_importButton")
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Source filter tabs
            Picker("Source", selection: $viewModel.sourceFilter) {
                ForEach(SourceFilter.allCases, id: \.self) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .accessibilityIdentifier("inspector_sourceFilterPicker")

            // Thumbnail grid or empty state
            if viewModel.filteredHistory.isEmpty {
                sidebarEmptyState
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3),
                        spacing: 4
                    ) {
                        ForEach(viewModel.filteredHistory) { entry in
                            CollectionThumbnailCell(
                                entry: entry,
                                isSelected: viewModel.selectedImage?.id == entry.id,
                                fixedSize: nil
                            )
                            .onTapGesture {
                                viewModel.selectedImage = entry
                                viewModel.errorMessage = nil
                            }
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    viewModel.deleteImage(entry)
                                }
                            }
                        }
                    }
                    .padding(8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var focusRailContent: some View {
        VStack(spacing: 6) {
            // Import button
            Button(action: importFilePanel) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .medium))
            }
            .frame(width: 28, height: 28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            .buttonStyle(.plain)
            .help("Import image")
            .padding(.top, 8)

            // Mini thumbnails (32×32pt)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(viewModel.filteredHistory) { entry in
                        CollectionThumbnailCell(
                            entry: entry,
                            isSelected: viewModel.selectedImage?.id == entry.id,
                            fixedSize: 32
                        )
                        .onTapGesture {
                            viewModel.selectedImage = entry
                            viewModel.errorMessage = nil
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sidebarEmptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "photo.badge.arrow.down")
                .font(.title2)
                .foregroundColor(.neuTextSecondary.opacity(0.4))
                .symbolEffect(.pulse, options: .repeating)
            Text("Drop images here")
                .font(.caption)
                .foregroundColor(.neuTextSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func historyRow(_ entry: InspectedImage) -> some View {
        HistoryRowView(
            entry: entry,
            isSelected: viewModel.selectedImage?.id == entry.id,
            onSelect: {
                viewModel.selectedImage = entry
                viewModel.errorMessage = nil
            },
            onDelete: {
                viewModel.deleteImage(entry)
            }
        )
    }


    // MARK: - Crop Coordinate Helpers

    /// The letterbox/pillarbox rect that the image occupies inside the stage (at zoom=1).
    private func fitRect(imageSize: CGSize, stageSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              stageSize.width > 0, stageSize.height > 0 else { return .zero }
        let imgRatio  = imageSize.width / imageSize.height
        let stageRatio = stageSize.width / stageSize.height
        let fitW: CGFloat, fitH: CGFloat
        if imgRatio > stageRatio {
            fitW = stageSize.width
            fitH = stageSize.width / imgRatio
        } else {
            fitH = stageSize.height
            fitW = stageSize.height * imgRatio
        }
        let ox = (stageSize.width  - fitW) / 2
        let oy = (stageSize.height - fitH) / 2
        return CGRect(x: ox, y: oy, width: fitW, height: fitH)
    }

    /// Convert a point in stage-view coordinate space to normalized image space (0–1),
    /// accounting for current zoom and pan. Returns nil if outside image bounds.
    private func stageToNorm(_ pt: CGPoint, imageSize: CGSize) -> CGPoint? {
        let sz = stageSize
        guard sz.width > 0 else { return nil }
        let fit = fitRect(imageSize: imageSize, stageSize: sz)
        // Undo pan and zoom (pan is SwiftUI offset, center-anchored)
        let cx = sz.width / 2 + panOffset.width
        let cy = sz.height / 2 + panOffset.height
        let unpanned = CGPoint(
            x: (pt.x - cx) / zoomScale + sz.width / 2,
            y: (pt.y - cy) / zoomScale + sz.height / 2
        )
        let nx = (unpanned.x - fit.minX) / fit.width
        let ny = (unpanned.y - fit.minY) / fit.height
        return CGPoint(x: nx, y: ny)
    }

    /// Convert a normalized image-space point to stage-view coordinates.
    private func normToStage(_ norm: CGPoint, imageSize: CGSize) -> CGPoint {
        let sz = stageSize
        let fit = fitRect(imageSize: imageSize, stageSize: sz)
        let baseX = fit.minX + norm.x * fit.width
        let baseY = fit.minY + norm.y * fit.height
        // Apply zoom around center, then pan
        let cx = sz.width / 2
        let cy = sz.height / 2
        return CGPoint(
            x: (baseX - cx) * zoomScale + cx + panOffset.width,
            y: (baseY - cy) * zoomScale + cy + panOffset.height
        )
    }

    /// Clamp a normalized point to [0,1].
    private func clampNorm(_ pt: CGPoint) -> CGPoint {
        CGPoint(x: max(0, min(1, pt.x)), y: max(0, min(1, pt.y)))
    }

    /// Brush radius in normalized [0–1] image space, accounting for current zoom.
    /// A 40pt brush at zoom=1 with a 512pt-wide fit rect → radius = 20/512.
    private func brushRadiusNorm(for imageSize: CGSize) -> CGFloat {
        let fit = fitRect(imageSize: imageSize, stageSize: stageSize)
        guard fit.width > 0 else { return 0.02 }
        return (brushSize / 2) / (fit.width * zoomScale)
    }

    // MARK: - Crop Actions

    private func cropSaveToInspector() {
        guard let sel = cropSelection, let entry = viewModel.selectedImage,
              let cropped = viewModel.cropImage(entry.image, to: sel) else { return }
        viewModel.saveCroppedToInspector(cropped, parent: entry)
        cropSelection = nil
        viewModel.stageMode = .view
        showCropFeedback("Saved to Inspector")
    }

    private func cropExportToFile() {
        guard let sel = cropSelection, let entry = viewModel.selectedImage,
              let cropped = viewModel.cropImage(entry.image, to: sel) else { return }
        let panel = NSSavePanel()
        let base = (entry.sourceName as NSString).deletingPathExtension
        panel.nameFieldStringValue = "\(base)_crop.png"
        panel.allowedContentTypes = [.png]
        panel.begin { [weak viewModel] response in
            guard response == .OK, let url = panel.url else { return }
            if let tiff = cropped.tiffRepresentation,
               let bmp = NSBitmapImageRep(data: tiff),
               let png = bmp.representation(using: .png, properties: [:]) {
                try? png.write(to: url)
            }
            DispatchQueue.main.async {
                self.cropSelection = nil
                viewModel?.stageMode = .view
            }
        }
    }

    private func cropSendToGenerate() {
        guard let sel = cropSelection, let entry = viewModel.selectedImage,
              let cropped = viewModel.cropImage(entry.image, to: sel) else { return }
        cropSelection = nil
        viewModel.stageMode = .view
        viewModel.pendingCropForGenerate = cropped
    }

    private func showCropFeedback(_ msg: String) {
        cropFeedback = msg
        cropFeedbackTask?.cancel()
        cropFeedbackTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            cropFeedback = nil
        }
    }

    // MARK: - Actions

    private func openFilePanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { [viewModel] response in
            guard response == .OK, let url = panel.url else { return }
            viewModel.loadImage(url: url)
        }
    }

    private func importFilePanel() {
        let panel = NSOpenPanel()
        var types: [UTType] = [.png, .jpeg, .tiff, .image]
        if let webp = UTType(filenameExtension: "webp") { types.append(webp) }
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import Image"
        panel.begin { [viewModel] response in
            guard response == .OK, let url = panel.url else { return }
            viewModel.loadImage(url: url, source: .imported(sourceURL: url))
        }
    }

}

// MARK: - Right Panel Tab

private enum RightPanelTab: CaseIterable {
    case metadata, assist, actions

    var label: String {
        switch self {
        case .metadata: return "Metadata"
        case .assist:   return "Assist"
        case .actions:  return "Actions"
        }
    }

    var icon: String {
        switch self {
        case .metadata: return "doc.text"
        case .assist:   return "wand.and.stars"
        case .actions:  return "square.and.arrow.up"
        }
    }
}

// MARK: - Layout Pill Button Style

private struct LayoutPillButtonStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(isActive ? .white : Color(NSColor.secondaryLabelColor))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isActive ? Color.neuAccent : Color.clear)
                    .opacity(configuration.isPressed ? 0.75 : 1)
            )
    }
}

// MARK: - Collection Thumbnail Cell

private struct CollectionThumbnailCell: View {
    let entry: InspectedImage
    let isSelected: Bool
    let fixedSize: CGFloat?

    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Image(nsImage: entry.image)
                .resizable()
                .aspectRatio(contentMode: .fill)

            // Source indicator dot
            Circle()
                .fill(entry.source.dotColor)
                .frame(width: 6, height: 6)
                .padding(3)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(width: fixedSize, height: fixedSize)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(
                    isSelected ? Color.accentColor : Color(NSColor.separatorColor).opacity(0.6),
                    lineWidth: isSelected ? 2 : 0.5
                )
        )
        .scaleEffect(isHovered && !isSelected ? 1.03 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Filmstrip Cell

private struct FilmstripCell: View {
    let entry: InspectedImage
    let isSelected: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            Image(nsImage: entry.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 76, height: 76)
                .clipped()

            // Caption scrim + filename
            LinearGradient(
                colors: [.clear, .black.opacity(0.5)],
                startPoint: .center,
                endPoint: .bottom
            )
            .frame(height: 28)

            Text(entry.sourceName)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 4)
                .padding(.bottom, 3)
        }
        .frame(width: 76, height: 76)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(
                    isSelected ? Color.accentColor : Color(NSColor.separatorColor).opacity(0.5),
                    lineWidth: isSelected ? 2 : 0.5
                )
        )
    }
}

// MARK: - History Row View with Hover State

private struct HistoryRowView: View {
    let entry: InspectedImage
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    private var backgroundColor: Color {
        if isSelected {
            return Color.neuAccent.opacity(0.12)
        } else if isHovered {
            return Color.neuSurface.opacity(0.6)
        }
        return Color.clear
    }

    private var strokeColor: Color {
        if isSelected {
            return Color.neuAccent.opacity(0.3)
        } else if isHovered {
            return Color.neuShadowDark.opacity(0.1)
        }
        return Color.clear
    }

    private var scaleAmount: CGFloat {
        isHovered && !isSelected ? 1.02 : 1.0
    }

    private var accessibilityText: String {
        let metadataDesc = entry.metadata != nil ? entry.metadata!.format.rawValue + " metadata" : "no metadata"
        return "\(entry.sourceName), \(metadataDesc)"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: entry.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 48, height: 48)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.sourceName)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)
                    .truncationMode(.middle)

                metadataIndicator
            }

            Spacer(minLength: 0)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(strokeColor, lineWidth: 1)
        )
        .scaleEffect(scaleAmount)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            onSelect()
        }
        .contextMenu {
            Button("Delete") {
                onDelete()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var metadataIndicator: some View {
        HStack(spacing: 4) {
            if let meta = entry.metadata {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text(meta.format.rawValue)
                    .font(.caption2)
                    .foregroundColor(.neuTextSecondary)
            } else {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
                Text("No metadata")
                    .font(.caption2)
                    .foregroundColor(.neuTextSecondary)
            }
        }
    }
}

// MARK: - Crop Bar Button Style

private struct ConfirmationBarButtonStyle: ButtonStyle {
    var accent: Bool = false
    var destructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(destructive ? .red.opacity(0.85) : accent ? .white : .white.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(accent ? Color.accentColor.opacity(0.75) : Color.white.opacity(0.12))
                    .opacity(configuration.isPressed ? 0.7 : 1)
            )
    }
}

// MARK: - Crop Handle

private enum CropHandle: CaseIterable, Hashable {
    case topLeft, top, topRight
    case left, right
    case bottomLeft, bottom, bottomRight

    /// Anchor point in normalized [0,1] space for a given crop rect.
    func anchorPoint(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft:     return CGPoint(x: rect.minX, y: rect.minY)
        case .top:         return CGPoint(x: rect.midX, y: rect.minY)
        case .topRight:    return CGPoint(x: rect.maxX, y: rect.minY)
        case .left:        return CGPoint(x: rect.minX, y: rect.midY)
        case .right:       return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomLeft:  return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottom:      return CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    /// Adjust a crop rect by dragging this handle to `newNorm` (normalized point).
    func adjustedRect(_ rect: CGRect, newNorm: CGPoint) -> CGRect {
        var minX = rect.minX, minY = rect.minY
        var maxX = rect.maxX, maxY = rect.maxY
        switch self {
        case .topLeft:     minX = newNorm.x; minY = newNorm.y
        case .top:         minY = newNorm.y
        case .topRight:    maxX = newNorm.x; minY = newNorm.y
        case .left:        minX = newNorm.x
        case .right:       maxX = newNorm.x
        case .bottomLeft:  minX = newNorm.x; maxY = newNorm.y
        case .bottom:      maxY = newNorm.y
        case .bottomRight: maxX = newNorm.x; maxY = newNorm.y
        }
        // Ensure min < max
        let x = min(minX, maxX), w = abs(maxX - minX)
        let y = min(minY, maxY), h = abs(maxY - minY)
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

// MARK: - Scroll Wheel Handler

/// Transparent NSView overlay that separates trackpad two-finger scroll (pan) from
/// discrete mouse-wheel scroll (zoom).
///
/// - `onZoom(delta, locationInView)` — fired for discrete mouse-wheel events only
///   (hasPreciseScrollingDeltas == false). delta > 0 = zoom in.
/// - `onPan(translation)` — fired for precise trackpad two-finger scroll
///   (hasPreciseScrollingDeltas == true). Only forwarded when the caller indicates
///   the image is zoomed in; otherwise silently dropped at the NSView layer by
///   checking the `isZoomedIn` flag set by the caller.
private struct ScrollWheelHandler: NSViewRepresentable {
    let onZoom: (CGFloat, CGPoint) -> Void
    let onPan: (CGSize) -> Void

    func makeNSView(context: Context) -> ScrollWheelNSView {
        let v = ScrollWheelNSView()
        v.onZoom = onZoom
        v.onPan = onPan
        return v
    }

    func updateNSView(_ nsView: ScrollWheelNSView, context: Context) {
        nsView.onZoom = onZoom
        nsView.onPan = onPan
    }
}

final class ScrollWheelNSView: NSView {
    var onZoom: ((CGFloat, CGPoint) -> Void)?
    var onPan: ((CGSize) -> Void)?

    override var acceptsFirstResponder: Bool { false }

    override func scrollWheel(with event: NSEvent) {
        if event.hasPreciseScrollingDeltas {
            // Two-finger trackpad scroll → pan
            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY
            guard abs(dx) > 0.01 || abs(dy) > 0.01 else { super.scrollWheel(with: event); return }
            onPan?(CGSize(width: dx, height: dy))
        } else {
            // Discrete mouse-wheel → zoom
            let delta = event.deltaY * 3
            guard abs(delta) > 0.01 else { super.scrollWheel(with: event); return }
            let location = convert(event.locationInWindow, from: nil)
            onZoom?(delta, location)
        }
    }
}
