//
//  ShowcaseView.swift
//  TanqueStudio
//
//  Page Layout, Phase 1a: Showcase, a 16:9 slideshow of a chapter's scenes
//  for sharing on the web. Each scene with a take is one slide; its 16:9
//  framing is stored on the scene (`showcaseCropJSON`), apart from any page
//  panel crop. Export writes images/NNN.jpg and a self-contained index.html.
//

import SwiftUI
import SwiftData
import AppKit

enum ChapterLayoutMode: String, CaseIterable, Identifiable {
    case pages, showcase
    var id: String { rawValue }
    var label: String { self == .pages ? "Pages" : "Showcase" }
}

/// Pages | Showcase switch, shown in both views' headers.
struct ChapterLayoutModePicker: View {
    @Binding var mode: ChapterLayoutMode

    var body: some View {
        TanqueSegmented(selection: $mode, options: ChapterLayoutMode.allCases.map { ($0, $0.label) })
    }
}

/// A segmented control drawn in TanqueDS colours. The system segmented
/// picker draws unselected labels dark on these dark panels.
struct TanqueSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                let (value, label) = options[i]
                let on = value == selection
                Button { selection = value } label: {
                    Text(label)
                        .font(TanqueDS.Font.bodySmall)
                        .foregroundStyle(on ? TanqueDS.Color.surface0 : TanqueDS.Color.textSecondary)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(on ? TanqueDS.Color.brass : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(TanqueDS.Color.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(TanqueDS.Color.surfaceBorder, lineWidth: 1))
        .fixedSize()
    }
}

// MARK: - Slides

struct ShowcaseSlide: Identifiable {
    let scene: StoryScene
    let take: PageTake
    let crop: PanelCrop
    var id: UUID { scene.id }

    /// Crop size in the take's pixels: what the export writes, never enlarged
    /// (capped at 1920 × 1080).
    var exportSize: (w: Int, h: Int) {
        let px = crop.pixelRect(in: take.pixelSize)
        let s = min(1, 1920 / max(1, px.width))
        return (Int((px.width * s).rounded()), Int((px.height * s).rounded()))
    }
}

@MainActor
enum Showcase {
    static let ratio = 16.0 / 9.0

    /// Scenes with a take, in scene order, with their 16:9 crops.
    static func slides(for chapter: StoryChapter, context: ModelContext) -> [ShowcaseSlide] {
        chapter.sortedScenes.compactMap { scene in
            guard let take = PageLayoutController.take(id: PageLayoutController.takeID(for: scene), context: context)
            else { return nil }
            return ShowcaseSlide(scene: scene, take: take, crop: crop(for: scene, take: take))
        }
    }

    /// The stored crop if it is still 16:9 for this take, else a centred fill.
    static func crop(for scene: StoryScene, take: PageTake) -> PanelCrop {
        if let stored = PanelCrop.decode(scene.showcaseCropJSON) {
            let px = stored.pixelRect(in: take.pixelSize)
            if px.height > 0, abs(Double(px.width / px.height) / ratio - 1) < 0.01 { return stored }
        }
        return PageCrop.fill(panelRatio: ratio, takeSize: take.pixelSize)
    }

    static func caption(_ scene: StoryScene) -> (narrator: String, dialogue: String) {
        ((scene.narratorText ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
         (scene.dialogueText ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

// MARK: - View

struct ShowcaseView: View {
    @Bindable var chapter: StoryChapter
    @Bindable var project: StoryProject
    @Binding var mode: ChapterLayoutMode

    @Environment(\.modelContext) private var modelContext
    @State private var selectedID: UUID?
    @State private var reframing: ShowcaseSlide?
    @State private var exporter = ShowcaseExportController()
    /// Bumped after a reframe so slides re-read their crops.
    @State private var revision = 0

    var body: some View {
        let slides = Showcase.slides(for: chapter, context: modelContext)
        let _ = revision
        let selected = slides.first { $0.id == selectedID } ?? slides.first
        HStack(spacing: 0) {
            slideList(slides, selected: selected)
                .frame(width: 190)
            Rectangle().fill(TanqueDS.Color.surfaceBorder).frame(width: 1)
            VStack(spacing: 0) {
                header(slides)
                Rectangle().fill(TanqueDS.Color.surfaceBorder).frame(height: 1)
                stage(selected)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Rectangle().fill(TanqueDS.Color.surfaceBorder).frame(width: 1)
            inspector(selected, slides: slides)
                .frame(width: 270)
        }
        .background(TanqueDS.Color.surface0)
        .sheet(item: $reframing) { slide in
            if let image = PageImageCache.shared.image(id: slide.take.id, path: slide.take.filePath, maxPixels: 2000) {
                ReframeSheet(title: "Reframe Slide · \(slide.scene.title)", image: image,
                             takeSize: slide.take.pixelSize, panelRatio: Showcase.ratio,
                             initial: slide.crop) { crop in
                    slide.scene.showcaseCropJSON = crop.json
                    chapter.project?.modifiedAt = Date()
                    revision += 1
                }
            }
        }
    }

    private func header(_ slides: [ShowcaseSlide]) -> some View {
        HStack(spacing: TanqueDS.Spacing.md) {
            ChapterLayoutModePicker(mode: $mode)
            Text("\(slides.count) slide\(slides.count == 1 ? "" : "s") · 16:9")
                .font(TanqueDS.Font.body)
                .foregroundStyle(TanqueDS.Color.textSecondary)
            Spacer()
            Button {
                exporter.export(slides, title: chapter.title.isEmpty ? project.name : chapter.title)
            } label: {
                Label("Export Showcase…", systemImage: "square.and.arrow.up")
                    .font(TanqueDS.Font.bodySmall)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(TanqueDS.Color.brass)
            .disabled(slides.isEmpty || exporter.isExporting)
        }
        .padding(.horizontal, TanqueDS.Spacing.lg)
        .padding(.vertical, TanqueDS.Spacing.sm + 2)
        .background(TanqueDS.Color.surface1)
    }

    private func slideList(_ slides: [ShowcaseSlide], selected: ShowcaseSlide?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Slides").tanqueSectionLabel()
                .padding(.horizontal, TanqueDS.Spacing.md)
                .padding(.vertical, TanqueDS.Spacing.sm)
            List(selection: Binding(get: { selected?.id }, set: { selectedID = $0 })) {
                ForEach(Array(slides.enumerated()), id: \.element.id) { i, slide in
                    VStack(alignment: .leading, spacing: 3) {
                        SlideImage(slide: slide, maxPixels: 400)
                            .aspectRatio(Showcase.ratio, contentMode: .fit)
                        Text("\(i + 1) · \(slide.scene.title)")
                            .font(TanqueDS.Font.bodySmall)
                            .foregroundStyle(TanqueDS.Color.textPrimary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 3)
                    .accessibilityElement(children: .combine)
                    .accessibilityAction { selectedID = slide.id }
                    .tag(slide.id)
                    .listRowBackground(slide.id == selected?.id ? TanqueDS.Color.surface3 : TanqueDS.Color.surface1)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .background(TanqueDS.Color.surface1)
    }

    @ViewBuilder
    private func stage(_ slide: ShowcaseSlide?) -> some View {
        if let slide {
            VStack(spacing: 14) {
                SlideImage(slide: slide, maxPixels: 2000)
                    .aspectRatio(Showcase.ratio, contentMode: .fit)
                    .background(Color.black)
                    .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(TanqueDS.Color.surfaceBorder))
                    .onTapGesture(count: 2) { reframing = slide }
                    .accessibilityAction(named: "Reframe") { reframing = slide }
                let caption = Showcase.caption(slide.scene)
                if !caption.narrator.isEmpty {
                    Text(caption.narrator)
                        .font(TanqueDS.Font.body.italic())
                        .foregroundStyle(TanqueDS.Color.textSecondary)
                        .multilineTextAlignment(.center)
                }
                if !caption.dialogue.isEmpty {
                    Text(caption.dialogue)
                        .font(TanqueDS.Font.body)
                        .foregroundStyle(TanqueDS.Color.textPrimary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(30)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "play.rectangle")
                    .font(.system(size: 40))
                    .foregroundStyle(TanqueDS.Color.textMuted)
                Text("No slides yet")
                    .font(TanqueDS.Font.bodyMedium)
                    .foregroundStyle(TanqueDS.Color.textPrimary)
                Text("Every scene in this chapter with an image becomes a slide.")
                    .font(TanqueDS.Font.bodySmall)
                    .foregroundStyle(TanqueDS.Color.textSecondary)
            }
        }
    }

    private func inspector(_ slide: ShowcaseSlide?, slides: [ShowcaseSlide]) -> some View {
        VStack(alignment: .leading, spacing: TanqueDS.Spacing.md) {
            Text("Slide").tanqueSectionLabel()
            if let slide {
                Text(slide.scene.title)
                    .font(TanqueDS.Font.bodyMedium)
                    .foregroundStyle(TanqueDS.Color.textPrimary)
                HStack {
                    Button("Reframe…") { reframing = slide }
                    Button("Reset") {
                        slide.scene.showcaseCropJSON = nil
                        revision += 1
                    }
                    .disabled(slide.scene.showcaseCropJSON == nil)
                }
                let px = slide.crop.pixelRect(in: slide.take.pixelSize)
                let out = slide.exportSize
                infoRow("Take", "\(Int(slide.take.pixelSize.width)) × \(Int(slide.take.pixelSize.height)) px")
                infoRow("16:9 crop", "\(Int(px.width.rounded())) × \(Int(px.height.rounded())) px")
                infoRow("Exports at", "\(out.w) × \(out.h) px")
                if out.w < 1280 {
                    Text("Smaller than 1280 wide. Showcase never enlarges, so this slide will look soft on a big screen. A wider render would help.")
                        .font(TanqueDS.Font.bodySmall)
                        .foregroundStyle(TanqueDS.Color.brass)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Captions come from the scene's narrator and dialogue text.")
                    .font(TanqueDS.Font.bodySmall)
                    .foregroundStyle(TanqueDS.Color.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if exporter.isExporting {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(exporter.progress)
                        .font(TanqueDS.Font.bodySmall)
                        .foregroundStyle(TanqueDS.Color.textSecondary)
                }
            }
            if let summary = exporter.summary {
                Text(summary)
                    .font(TanqueDS.Font.bodySmall)
                    .foregroundStyle(TanqueDS.Color.brass)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(TanqueDS.Spacing.md)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(TanqueDS.Color.surface1)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(TanqueDS.Font.bodySmall)
                .foregroundStyle(TanqueDS.Color.textSecondary)
            Spacer()
            Text(value)
                .font(TanqueDS.Font.bodySmall)
                .foregroundStyle(TanqueDS.Color.textPrimary)
        }
    }
}

/// A slide's take shown through its 16:9 crop.
private struct SlideImage: View {
    let slide: ShowcaseSlide
    let maxPixels: Int

    var body: some View {
        GeometryReader { geo in
            if let image = PageImageCache.shared.image(id: slide.take.id, path: slide.take.filePath, maxPixels: maxPixels) {
                let c = slide.crop
                let fullW = geo.size.width / CGFloat(c.w)
                let fullH = geo.size.height / CGFloat(c.h)
                Image(nsImage: image)
                    .resizable()
                    .frame(width: fullW, height: fullH)
                    .offset(x: -CGFloat(c.x) * fullW, y: -CGFloat(c.y) * fullH)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                    .clipped()
            } else {
                TanqueDS.Color.surface2
            }
        }
    }
}

// MARK: - Export

@MainActor
@Observable
final class ShowcaseExportController {
    var isExporting = false
    var progress = ""
    var summary: String?

    func export(_ slides: [ShowcaseSlide], title: String) {
        guard !isExporting, !slides.isEmpty else { return }
        summary = nil
        let items = slides.enumerated().map { i, s in
            let size = s.exportSize
            let canvas = ComposedCanvas(
                name: String(format: "%03d", i + 1), size: CGSize(width: size.w, height: size.h), scale: 1,
                pdfPointsPerUnit: 1, borderWidth: 0,
                panels: [ComposedPanel(rect: CGRect(x: 0, y: 0, width: size.w, height: size.h),
                                       imagePath: s.take.filePath, crop: s.crop, name: "")],
                foldX: nil)
            let caption = Showcase.caption(s.scene)
            return (canvas: canvas, slide: ShowcaseHTML.Slide(
                src: "images/\(canvas.name).jpg", title: s.scene.title,
                narrator: caption.narrator, dialogue: caption.dialogue))
        }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Choose a folder for the showcase (index.html and an images folder go inside)"
        panel.begin { [weak self] response in
            guard response == .OK, let folder = panel.url else { return }
            Task { @MainActor in self?.run(items, title: title, folder: folder) }
        }
    }

    private func run(_ items: [(canvas: ComposedCanvas, slide: ShowcaseHTML.Slide)], title: String, folder: URL) {
        isExporting = true
        let small = items.filter { $0.canvas.pixelSize.w < 1280 }.count
        let read: PageCompositor.Reader = { path in
            await MainActor.run { try? ImageFolderAccess.readData(at: URL(fileURLWithPath: path)) }
        }
        let report: @Sendable (String) -> Void = { [weak self] text in
            guard let owner = self else { return }
            Task { @MainActor in owner.progress = text }
        }
        Task { [weak self] in
            let accessed = folder.startAccessingSecurityScopedResource()
            defer { if accessed { folder.stopAccessingSecurityScopedResource() } }
            let error = await Task.detached(priority: .userInitiated) { () -> String? in
                let images = folder.appendingPathComponent("images", isDirectory: true)
                do {
                    try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
                    for (i, item) in items.enumerated() {
                        report("\(i + 1) of \(items.count)")
                        guard let bitmap = await PageCompositor.bitmap(item.canvas, read: read),
                              let jpeg = PageCompositor.jpeg(bitmap, quality: 0.9) else {
                            return "Could not compose slide \(i + 1)."
                        }
                        try jpeg.write(to: images.appendingPathComponent("\(item.canvas.name).jpg"))
                    }
                    let html = ShowcaseHTML.page(title: title, slides: items.map(\.slide))
                    try Data(html.utf8).write(to: folder.appendingPathComponent("index.html"))
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }.value
            guard let self else { return }
            isExporting = false
            progress = ""
            if let error {
                summary = "Showcase export failed: \(error)"
            } else {
                summary = "Wrote \(items.count) slides and index.html to \(folder.lastPathComponent)."
                    + (small > 0 ? " \(small) slide\(small == 1 ? " is" : "s are") under 1280 wide (not enlarged)." : "")
            }
        }
    }
}

// MARK: - HTML

nonisolated enum ShowcaseHTML {
    struct Slide: Codable, Sendable {
        let src: String
        let title: String
        let narrator: String
        let dialogue: String
    }

    /// A self-contained slideshow: arrow keys, Home/End, click or swipe.
    static func page(title: String, slides: [Slide]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = (try? encoder.encode(slides)).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
        // Keep the JSON from closing the <script> element.
        let safe = data.replacingOccurrences(of: "</", with: "<\\/")
        let escapedTitle = title
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escapedTitle)</title>
        <style>
          html, body { margin: 0; height: 100%; background: #0d0d0f; color: #ece8e1;
            font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif; }
          body { display: flex; flex-direction: column; overflow: hidden; }
          #stage { flex: 1; display: flex; align-items: center; justify-content: center; min-height: 0; padding: 2vh 2vw 0; }
          #frame { position: relative; width: min(96vw, calc((100vh - 9rem) * 16 / 9)); aspect-ratio: 16 / 9; background: #000; }
          #frame img { width: 100%; height: 100%; object-fit: contain; display: block; }
          #captions { min-height: 6rem; padding: 0.8rem 6vw 0.4rem; text-align: center; }
          #narrator { font-style: italic; color: #b9b2a6; margin: 0 0 0.35rem; }
          #dialogue { margin: 0; font-size: 1.1rem; }
          #bar { display: flex; justify-content: space-between; align-items: center; padding: 0.4rem 1rem 0.8rem; color: #8a847a; font-size: 0.85rem; }
          button { background: none; border: 1px solid #3a3733; color: #ece8e1; border-radius: 4px; padding: 0.3rem 0.8rem; cursor: pointer; }
          button:disabled { opacity: 0.3; cursor: default; }
          .hit { position: absolute; top: 0; bottom: 0; width: 35%; cursor: pointer; }
          #prevHit { left: 0; } #nextHit { right: 0; }
        </style>
        </head>
        <body>
        <div id="stage"><div id="frame">
          <img id="slide" alt="">
          <div class="hit" id="prevHit" aria-hidden="true"></div>
          <div class="hit" id="nextHit" aria-hidden="true"></div>
        </div></div>
        <div id="captions"><p id="narrator"></p><p id="dialogue"></p></div>
        <div id="bar">
          <button id="prev" aria-label="Previous slide">&larr;</button>
          <span id="count" aria-live="polite"></span>
          <button id="next" aria-label="Next slide">&rarr;</button>
        </div>
        <script id="data" type="application/json">\(safe)</script>
        <script>
          const slides = JSON.parse(document.getElementById('data').textContent);
          let i = Math.max(0, Math.min(slides.length - 1, (parseInt(location.hash.slice(1), 10) || 1) - 1));
          const $ = id => document.getElementById(id);
          function show(n) {
            if (!slides.length) { $('count').textContent = 'No slides'; return; }
            i = Math.max(0, Math.min(slides.length - 1, n));
            const s = slides[i];
            $('slide').src = s.src;
            $('slide').alt = s.title;
            $('narrator').textContent = s.narrator;
            $('dialogue').textContent = s.dialogue;
            $('count').textContent = (i + 1) + ' / ' + slides.length;
            $('prev').disabled = i === 0;
            $('next').disabled = i === slides.length - 1;
            history.replaceState(null, '', '#' + (i + 1));
            if (slides[i + 1]) { new Image().src = slides[i + 1].src; }
          }
          document.addEventListener('keydown', e => {
            if (e.key === 'ArrowRight' || e.key === 'PageDown' || e.key === ' ') { show(i + 1); e.preventDefault(); }
            else if (e.key === 'ArrowLeft' || e.key === 'PageUp') { show(i - 1); e.preventDefault(); }
            else if (e.key === 'Home') { show(0); }
            else if (e.key === 'End') { show(slides.length - 1); }
          });
          $('prev').onclick = () => show(i - 1);
          $('next').onclick = () => show(i + 1);
          $('prevHit').onclick = () => show(i - 1);
          $('nextHit').onclick = () => show(i + 1);
          let x0 = null;
          $('stage').addEventListener('touchstart', e => { x0 = e.touches[0].clientX; }, { passive: true });
          $('stage').addEventListener('touchend', e => {
            if (x0 === null) return;
            const dx = e.changedTouches[0].clientX - x0;
            if (Math.abs(dx) > 40) show(dx < 0 ? i + 1 : i - 1);
            x0 = null;
          });
          show(i);
        </script>
        </body>
        </html>
        """
    }
}
