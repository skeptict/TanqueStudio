//
//  ImageLightboxView.swift
//  DrawThingsStudio
//
//  Full-window image preview overlay with dim background.
//  Double-click any thumbnail to open; click outside or press Escape to dismiss.
//  Arrow keys (or chevron buttons) navigate through an optional browse list.
//

import SwiftUI
import AppKit
import Combine

// MARK: - Key Event Monitor

/// Ties NSEvent monitor lifetime to ARC — deinit always removes the monitor,
/// even if the enclosing SwiftUI struct is released during a dismiss animation.
private final class KeyEventMonitor: ObservableObject {
    var monitor: Any?
    deinit {
        if let m = monitor { NSEvent.removeMonitor(m) }
    }
}

// MARK: - Lightbox Overlay

struct LightboxOverlay: View {
    /// The binding drives both display and navigation — writing a new value navigates.
    @Binding var image: NSImage?
    /// Ordered list of images to navigate through. Identity comparison (===) locates current.
    var browseList: [NSImage] = []

    @StateObject private var keyEventMonitor = KeyEventMonitor()

    private var currentIndex: Int {
        guard let img = image else { return -1 }
        return browseList.firstIndex(where: { $0 === img }) ?? -1
    }
    private var hasPrev: Bool { currentIndex > 0 }
    private var hasNext: Bool { currentIndex >= 0 && currentIndex < browseList.count - 1 }
    private var hasNav: Bool { !browseList.isEmpty }

    var body: some View {
        ZStack {
            // Dimmed background — tap to dismiss
            Color.black.opacity(0.82)
                .ignoresSafeArea()
                .onTapGesture { image = nil }

            // Centered image
            if let img = image {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(.horizontal, hasNav ? 80 : 40)
                    .padding(.vertical, 40)
                    .shadow(color: .black.opacity(0.55), radius: 30, x: 0, y: 10)
                    .allowsHitTesting(false)
            }

            // Navigation chevrons
            if hasNav {
                HStack {
                    navButton(systemName: "chevron.left.circle.fill", enabled: hasPrev) { navigatePrev() }
                    Spacer()
                    navButton(systemName: "chevron.right.circle.fill", enabled: hasNext) { navigateNext() }
                }
                .padding(.horizontal, 16)
            }

            // Close button (top-right)
            VStack {
                HStack {
                    Spacer()
                    Button(action: { image = nil }) {
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
        .onAppear {
            // Capture the binding — idx is computed fresh on each keypress so navigation
            // always reflects the current position, not the position at install time.
            let imageBinding = $image
            let list = browseList
            keyEventMonitor.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                switch event.keyCode {
                case 53:   // Escape
                    imageBinding.wrappedValue = nil
                    return nil
                case 123:  // Left arrow
                    if let current = imageBinding.wrappedValue,
                       let idx = list.firstIndex(where: { $0 === current }),
                       idx > 0 {
                        imageBinding.wrappedValue = list[idx - 1]
                    }
                    return nil
                case 124:  // Right arrow
                    if let current = imageBinding.wrappedValue,
                       let idx = list.firstIndex(where: { $0 === current }),
                       idx < list.count - 1 {
                        imageBinding.wrappedValue = list[idx + 1]
                    }
                    return nil
                default:
                    return event
                }
            }
        }
    }

    private func navigatePrev() {
        let idx = currentIndex
        if idx > 0 { image = browseList[idx - 1] }
    }

    private func navigateNext() {
        let idx = currentIndex
        if idx >= 0 && idx < browseList.count - 1 { image = browseList[idx + 1] }
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
}

// MARK: - View Extension

extension View {
    /// Overlays a full-window lightbox when `image` is non-nil.
    /// Provide `browseList` to enable arrow-key / chevron navigation.
    func lightbox(image: Binding<NSImage?>, browseList: [NSImage] = []) -> some View {
        ZStack {
            self
            if image.wrappedValue != nil {
                LightboxOverlay(image: image, browseList: browseList)
                    .transition(.opacity)
                    .zIndex(999)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: image.wrappedValue != nil)
    }
}
