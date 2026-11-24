import SwiftUI
import AppKit
import CoreImage
import UniformTypeIdentifiers

// MARK: - Film Finish (Labs)
//
// A test bench for the halation and .cube LUT filters: drop or open an image,
// open a LUT, move the sliders, hold Before to compare, export a PNG. Not yet
// wired to the gallery or the Focus Room; that comes after the filters are
// judged on real renders.

struct FilmFinishLabView: View {
    @State private var sourceURL: URL?
    @State private var sourceCG: CGImage?
    @State private var previewInput: CIImage?
    @State private var preview: NSImage?

    @State private var halationOn = true
    @State private var halation = HalationSettings.default
    @State private var tintColor = Color(.sRGB, red: 1.0, green: 0.55, blue: 0.3)
    @State private var haloOnly = false

    @State private var lut: CubeLUT?
    @State private var lutName: String?
    @State private var lutStrength: Float = 1

    @State private var showBefore = false
    @State private var message: String?
    @State private var renderTask: Task<Void, Never>?

    private var finish: FilmFinish {
        FilmFinish(halation: halationOn ? halation : nil, lut: lut, lutStrength: lutStrength)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            canvas
            controls.frame(width: 300)
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 24)
        .onChange(of: finish) { _, _ in rerender() }
        .onChange(of: haloOnly) { _, _ in rerender() }
        .onChange(of: tintColor) { _, c in halation.tint = Self.linearRGB(c) }
    }

    // MARK: Canvas

    private var canvas: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(DashboardDS.surf1)
            if let shown = showBefore ? sourceCG.map({ NSImage(cgImage: $0, size: .zero) }) : preview {
                Image(nsImage: shown).resizable().interpolation(.high).aspectRatio(contentMode: .fit).padding(12)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled").font(.system(size: 32))
                    Text("Drop an image here, or Open Image…").font(TanqueDS.Font.mono(11.5))
                }
                .foregroundStyle(DashboardDS.muted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The only drop API that works reliably on macOS Tahoe (see Open Brain).
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            if url.pathExtension.lowercased() == "cube" { loadLUT(url) } else { loadImage(url) }
            return true
        }
    }

    // MARK: Controls

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Button("Open Image…") { pick([.png, .jpeg, .tiff, .heic]) { loadImage($0) } }
                    Button("Export PNG…", action: export).disabled(sourceCG == nil)
                }

                section("Halation", isOn: $halationOn) {
                    slider("Threshold", $halation.threshold, 0.05...1.5)
                    slider("Softness", $halation.softness, 0...1)
                    slider("Radius", $halation.radius, 0.001...0.05, format: "%.3f")
                    slider("Strength", $halation.strength, 0...2)
                    slider("Core protection", $halation.coreProtection, 0...1)
                    ColorPicker("Tint", selection: $tintColor, supportsOpacity: false)
                    Picker("Blend", selection: $halation.blend) {
                        ForEach(HalationSettings.Blend.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Show halation only", isOn: $haloOnly)
                    Button("Reset halation") {
                        halation = .default
                        tintColor = Color(.sRGB, red: 1.0, green: 0.55, blue: 0.3)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("LUT").font(TanqueDS.Font.monoSemiBold(12))
                    HStack {
                        Button("Open .cube…") {
                            pick([UTType(filenameExtension: "cube") ?? .data]) { loadLUT($0) }
                        }
                        if lut != nil { Button("Clear") { lut = nil; lutName = nil } }
                    }
                    Text(lutName ?? "None").font(TanqueDS.Font.mono(11)).foregroundStyle(DashboardDS.muted2)
                    if lut != nil { slider("Strength", $lutStrength, 0...1) }
                }

                Button {} label: { Text("Hold to see Before").frame(maxWidth: .infinity) }
                    .simultaneousGesture(DragGesture(minimumDistance: 0)
                        .onChanged { _ in showBefore = true }
                        .onEnded { _ in showBefore = false })
                    .disabled(sourceCG == nil)

                if let message {
                    Text(message).font(TanqueDS.Font.mono(11)).foregroundStyle(DashboardDS.brass)
                        .textSelection(.enabled)
                }
            }
            .font(TanqueDS.Font.mono(11))
            .foregroundStyle(DashboardDS.text)
        }
    }

    private func section<Content: View>(_ title: String, isOn: Binding<Bool>,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: isOn) { Text(title).font(TanqueDS.Font.monoSemiBold(12)) }
            if isOn.wrappedValue { content() }
        }
    }

    private func slider(_ label: String, _ value: Binding<Float>, _ range: ClosedRange<Float>,
                        format: String = "%.2f") -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack { Text(label); Spacer(); Text(String(format: format, value.wrappedValue)).monospacedDigit() }
            Slider(value: value, in: range)
        }
    }

    // MARK: Actions

    private func pick(_ types: [UTType], then: (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { then(url) }
    }

    private func loadImage(_ url: URL) {
        guard let cg = FilmFinishRenderer.loadCGImage(url) else { message = "Couldn't open \(url.lastPathComponent)."; return }
        sourceURL = url
        sourceCG = cg
        previewInput = FilmFinishRenderer.previewSource(cg)
        message = nil
        rerender()
    }

    private func loadLUT(_ url: URL) {
        do {
            let parsed = try CubeLUT(contentsOf: url)
            lut = parsed
            lutName = "\(parsed.title ?? url.deletingPathExtension().lastPathComponent) · \(parsed.size)³"
            message = nil
        } catch {
            message = "\(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func rerender() {
        guard let input = previewInput else { return }
        renderTask?.cancel()
        let finish = self.finish
        let haloOnly = self.haloOnly && halationOn
        nonisolated(unsafe) let source = input
        renderTask = Task {
            let cg = await Task.detached(priority: .userInitiated) { () -> CGImage? in
                let out = haloOnly ? HalationFilter.haloLayer(finish.halation ?? .default, for: source)
                                   : finish.apply(to: source)
                return FilmFinishRenderer.context.createCGImage(out, from: out.extent, format: .RGBA8,
                                                                colorSpace: FilmFinishRenderer.sRGB)
            }.value
            guard !Task.isCancelled, let cg else { return }
            preview = NSImage(cgImage: cg, size: .zero)
        }
    }

    private func export() {
        guard let sourceCG, let sourceURL else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = sourceURL.deletingPathExtension().lastPathComponent + "-finished.png"
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        let finish = self.finish
        nonisolated(unsafe) let cg = sourceCG
        Task {
            let ok = await Task.detached(priority: .userInitiated) { () -> Bool in
                guard let out = FilmFinishRenderer.render(finish, cgImage: cg) else { return false }
                return FilmFinishRenderer.writePNG(out, to: dest, metadataFrom: sourceURL)
            }.value
            message = ok ? "Saved \(dest.lastPathComponent) (\(cg.width)×\(cg.height))." : "Export failed."
        }
    }

    /// SwiftUI colour → linear-light RGB for the halation tint.
    private static func linearRGB(_ color: Color) -> SIMD3<Float> {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        func lin(_ c: CGFloat) -> Float {
            let v = Float(c)
            return v <= 0.04045 ? v / 12.92 : powf((v + 0.055) / 1.055, 2.4)
        }
        return SIMD3(lin(ns.redComponent), lin(ns.greenComponent), lin(ns.blueComponent))
    }
}
