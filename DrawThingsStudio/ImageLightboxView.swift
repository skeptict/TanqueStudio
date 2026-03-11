//
//  ImageLightboxView.swift
//  DrawThingsStudio
//
//  Full-window image preview overlay with dim background.
//  Double-click any thumbnail to open; click outside or press Escape to dismiss.
//

import SwiftUI
import AppKit

// MARK: - Lightbox Overlay

struct LightboxOverlay: View {
    let image: NSImage
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Dimmed background — tap to dismiss
            Color.black.opacity(0.82)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            // Centered image — taps pass through to background
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(40)
                .shadow(color: .black.opacity(0.55), radius: 30, x: 0, y: 10)
                .allowsHitTesting(false)

            // Close button
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 26))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.white.opacity(0.9), Color.white.opacity(0.15))
            }
            .buttonStyle(.plain)
            .padding(20)
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
    }
}

// MARK: - View Extension

extension View {
    /// Overlays a full-window lightbox when `image` is non-nil.
    /// Use `@State private var lightboxImage: NSImage?` in the parent view and
    /// set it on double-click to show the lightbox.
    func lightbox(image: Binding<NSImage?>) -> some View {
        ZStack {
            self
            if let img = image.wrappedValue {
                LightboxOverlay(image: img) { image.wrappedValue = nil }
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.15), value: image.wrappedValue != nil)
                    .zIndex(999)
            }
        }
    }
}
