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

// MARK: - Lightbox Overlay

struct LightboxOverlay: View {
    let image: NSImage
    let onDismiss: () -> Void
    var onPrevious: (() -> Void)? = nil
    var onNext: (() -> Void)? = nil

    @State private var eventMonitor: Any?
    private var hasNav: Bool { onPrevious != nil || onNext != nil }

    var body: some View {
        ZStack {
            // Dimmed background — tap to dismiss
            Color.black.opacity(0.82)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            // Centered image — taps pass through to background
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(.horizontal, hasNav ? 80 : 40)
                .padding(.vertical, 40)
                .shadow(color: .black.opacity(0.55), radius: 30, x: 0, y: 10)
                .allowsHitTesting(false)

            // Navigation chevrons
            if hasNav {
                HStack {
                    navButton(systemName: "chevron.left.circle.fill", action: onPrevious)
                    Spacer()
                    navButton(systemName: "chevron.right.circle.fill", action: onNext)
                }
                .padding(.horizontal, 16)
            }

            // Close button (top-right)
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
        .onAppear {
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                switch event.keyCode {
                case 53: onDismiss(); return nil          // Escape
                case 123: onPrevious?(); return nil       // Left arrow
                case 124: onNext?(); return nil           // Right arrow
                default: return event
                }
            }
        }
        .onDisappear {
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
        }
    }

    @ViewBuilder
    private func navButton(systemName: String, action: (() -> Void)?) -> some View {
        if let action {
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
            if let img = image.wrappedValue {
                let idx = browseList.isEmpty ? -1 : browseList.firstIndex(where: { $0 === img }) ?? -1
                let hasPrev = idx > 0
                let hasNext = idx >= 0 && idx < browseList.count - 1
                LightboxOverlay(
                    image: img,
                    onDismiss: { image.wrappedValue = nil },
                    onPrevious: hasPrev ? { image.wrappedValue = browseList[idx - 1] } : nil,
                    onNext:     hasNext ? { image.wrappedValue = browseList[idx + 1] } : nil
                )
                .transition(.opacity)
                .zIndex(999)
            }
        }
        // Drive the appear/disappear transition from the ZStack level so that
        // both insertion and removal animate correctly. A modifier on the child
        // alone only animates internal state changes, not the branch removal.
        .animation(.easeInOut(duration: 0.15), value: image.wrappedValue != nil)
    }
}
