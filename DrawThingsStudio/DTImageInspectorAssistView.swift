//
//  DTImageInspectorAssistView.swift
//  DrawThingsStudio
//
//  Assist tab of the Image Inspector right panel — LLM vision analysis and prompt assistance.
//

import AppKit
import SwiftUI

// MARK: - Message Model

private struct AssistMessage: Identifiable {
    let id = UUID()
    let role: Role
    let displayText: String
    let suggestedPrompt: String?

    enum Role { case user, assistant }

    init(role: Role, raw: String) {
        self.role = role
        if role == .assistant {
            let lines = raw.components(separatedBy: "\n")
            if let idx = lines.firstIndex(where: {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix("PROMPT:")
            }) {
                let promptLine = lines[idx].trimmingCharacters(in: .whitespaces)
                let extracted = String(promptLine.dropFirst("PROMPT:".count))
                    .trimmingCharacters(in: .whitespaces)
                let before = lines[..<idx].joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                self.displayText = before
                self.suggestedPrompt = extracted.isEmpty ? nil : extracted
            } else {
                self.displayText = raw
                self.suggestedPrompt = nil
            }
        } else {
            self.displayText = raw
            self.suggestedPrompt = nil
        }
    }
}

// MARK: - Main View

struct DTImageInspectorAssistView: View {
    let entry: InspectedImage?
    @ObservedObject var viewModel: ImageInspectorViewModel
    var showContextHeader: Bool = true

    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isInputFocused: Bool

    @State private var messages: [AssistMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var availableModels: [LLMModel] = []
    @State private var selectedModelName: String =
        UserDefaults.standard.string(forKey: "assist.selectedModel") ?? ""
    @State private var lastEntryID: UUID? = nil
    @State private var sendTapCount = 0

    private var hasPrompt: Bool {
        guard let p = entry?.metadata?.prompt else { return false }
        return !p.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var placeholder: String {
        hasPrompt ? "Ask about this image or prompt…" : "Ask about this image…"
    }

    // MARK: Body

    var body: some View {
        if let entry {
            VStack(spacing: 0) {
                if showContextHeader {
                    contextHeader(entry)
                    Divider()
                }
                chipScrollView
                Divider()

                if messages.isEmpty && !isLoading {
                    emptyConversationState
                } else {
                    conversationScrollView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                Divider()
                modelSelectorRow
                Divider()
                inputRow
            }
            .onAppear { loadModels(); syncEntry(entry) }
            .onChange(of: entry.id) { _, _ in syncEntry(entry) }
        } else {
            noSelectionState
        }
    }

    // MARK: - Context Header

    private func contextHeader(_ entry: InspectedImage) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Thumbnail
            Image(nsImage: entry.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            // Filename + context info
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.sourceName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(contextInfoString(entry))
                    .font(.system(size: 11))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            // Context badge
            contextBadge
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var contextBadge: some View {
        Text(hasPrompt ? "Prompt + vision" : "Vision only")
            .font(.system(size: 10))
            .foregroundColor(hasPrompt ? Color(hex: "#185FA5") : Color(NSColor.secondaryLabelColor))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(hasPrompt ? Color(hex: "#E6F1FB") : Color(NSColor.tertiarySystemFill))
            )
            .fixedSize()
    }

    private func contextInfoString(_ entry: InspectedImage) -> String {
        var parts: [String] = []
        switch entry.source {
        case .drawThings:  parts.append("Draw Things")
        case .civitai:     parts.append("Civitai")
        case .imported:    parts.append("Imported")
        case .unknown:     break
        }
        if let meta = entry.metadata {
            if let w = meta.width, let h = meta.height { parts.append("\(w)×\(h)") }
            if let sampler = meta.sampler { parts.append(sampler) }
            if let steps = meta.steps { parts.append("\(steps) steps") }
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Suggestion Chips

    private var chipScrollView: some View {
        ChipFlowLayout(spacing: 8) {
            ForEach(visionChips, id: \.self) { label in
                chipButton(label, colors: visionChipColors)
            }
            if hasPrompt {
                ForEach(enhanceChips, id: \.self) { label in
                    chipButton(label, colors: enhanceChipColors)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func chipButton(_ label: String, colors: ChipColors) -> some View {
        Button(label) {
            inputText = label
            Task { await sendMessage() }
        }
        .font(.system(size: 12))
        .foregroundColor(colors.text)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colors.bg)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(colors.border, lineWidth: 0.75)
                )
        )
        .buttonStyle(.plain)
    }

    private let visionChips = [
        "Describe this image",
        "How would I recreate this?",
        "Suggest a prompt for this style",
        "What model might have made this?"
    ]

    private let enhanceChips = [
        "Enhance this prompt",
        "Create a variation",
        "Change the style"
    ]

    // MARK: - Chip Colors

    private struct ChipColors { let bg: Color; let text: Color; let border: Color }

    private var visionChipColors: ChipColors {
        colorScheme == .dark
            ? ChipColors(bg: Color(hex: "#042C53"), text: Color(hex: "#B5D4F4"), border: Color(hex: "#185FA5"))
            : ChipColors(bg: Color(hex: "#E6F1FB"), text: Color(hex: "#185FA5"), border: Color(hex: "#85B7EB"))
    }

    private var enhanceChipColors: ChipColors {
        colorScheme == .dark
            ? ChipColors(bg: Color(hex: "#04342C"), text: Color(hex: "#9FE1CB"), border: Color(hex: "#0F6E56"))
            : ChipColors(bg: Color(hex: "#E1F5EE"), text: Color(hex: "#0F6E56"), border: Color(hex: "#5DCAA5"))
    }

    // MARK: - Conversation

    private var conversationScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(messages) { msg in
                        messageTurn(msg)
                    }
                    if isLoading {
                        typingIndicator
                    }
                    Color.clear.frame(height: 1).id("assistBottom")
                }
                .padding(12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: messages.count) { _, _ in
                withAnimation { proxy.scrollTo("assistBottom", anchor: .bottom) }
            }
            .onChange(of: isLoading) { _, _ in
                withAnimation { proxy.scrollTo("assistBottom", anchor: .bottom) }
            }
        }
    }

    @ViewBuilder
    private func messageTurn(_ msg: AssistMessage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(msg.role == .user ? "YOU" : "ASSISTANT")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color(NSColor.tertiaryLabelColor))
                .kerning(0.3)

            messageBubble(msg)

            if msg.role == .assistant, let prompt = msg.suggestedPrompt {
                promptResultCard(prompt)
            }
        }
    }

    @ViewBuilder
    private func messageBubble(_ msg: AssistMessage) -> some View {
        let text = msg.displayText.isEmpty && msg.role == .assistant
            ? "(No text)"
            : msg.displayText

        Text(text)
            .font(.system(size: 12))
            .lineSpacing(12 * 0.6)
            .foregroundColor(Color(NSColor.labelColor))
            .textSelection(.enabled)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        msg.role == .user
                            ? Color(.systemBlue).opacity(0.12)
                            : Color(NSColor.secondarySystemFill)
                    )
            )
    }

    private func promptResultCard(_ prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SUGGESTED PROMPT")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color(NSColor.tertiaryLabelColor))
                .kerning(0.3)

            Text(prompt)
                .font(.system(size: 11.5))
                .lineSpacing(11.5 * 0.6)
                .foregroundColor(Color(NSColor.labelColor))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                // Primary: Use in Draw Things
                Button("Use in Draw Things") {
                    viewModel.pendingAssistPrompt = prompt
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.accentColor))
                .buttonStyle(.plain)

                // Copy
                Button("Copy") {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(prompt, forType: .string)
                }
                .font(.system(size: 11))
                .foregroundColor(Color(NSColor.labelColor))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(NSColor.secondarySystemFill))
                )
                .buttonStyle(.plain)

                // Refine
                Button("Refine further") {
                    inputText = "Refine this: \(prompt)"
                    isInputFocused = true
                }
                .font(.system(size: 11))
                .foregroundColor(Color(NSColor.labelColor))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(NSColor.secondarySystemFill))
                )
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(NSColor.secondarySystemFill))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5)
                )
        )
    }

    private var typingIndicator: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text("Thinking…")
                .font(.system(size: 11))
                .foregroundColor(Color(NSColor.secondaryLabelColor))
        }
        .padding(.leading, 4)
    }

    // MARK: - Empty / No-selection States

    private var emptyConversationState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "wand.and.stars")
                .font(.system(size: 28))
                .foregroundColor(Color(NSColor.tertiaryLabelColor))
                .symbolEffect(.pulse, options: .repeating)
            Text("Ask about this image")
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
            Text("Vision analysis always available. Prompt enhancement available when metadata is present.")
                .font(.system(size: 12))
                .foregroundColor(Color(NSColor.tertiaryLabelColor))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noSelectionState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "photo.badge.arrow.down")
                .font(.system(size: 28))
                .foregroundColor(Color(NSColor.tertiaryLabelColor))
            Text("No image selected")
                .font(.system(size: 13))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Model Selector

    private var modelSelectorRow: some View {
        HStack(spacing: 8) {
            Text("MODEL")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color(NSColor.tertiaryLabelColor))
                .kerning(0.3)

            if availableModels.isEmpty {
                Text("No models available")
                    .font(.system(size: 11))
                    .foregroundColor(Color(NSColor.secondaryLabelColor))
                Spacer()
            } else {
                Picker("", selection: $selectedModelName) {
                    ForEach(availableModels, id: \.name) { model in
                        Text(model.name).tag(model.name)
                    }
                }
                .labelsHidden()
                .font(.system(size: 11))
                .frame(maxWidth: .infinity)
                .onChange(of: selectedModelName) { _, name in
                    UserDefaults.standard.set(name, forKey: "assist.selectedModel")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Input Area

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ZStack(alignment: .topLeading) {
                if inputText.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 12))
                        .foregroundColor(Color(NSColor.placeholderTextColor))
                        .padding(.top, 5)
                        .padding(.leading, 4)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $inputText)
                    .font(.system(size: 12))
                    .focused($isInputFocused)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 36, maxHeight: 48)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(NSColor.secondarySystemFill))
            )

            Button {
                sendTapCount += 1
                Task { await sendMessage() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 26))
                    .foregroundColor(canSend ? Color.accentColor : Color(NSColor.tertiaryLabelColor))
                    .symbolEffect(.bounce, value: sendTapCount)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }

    // MARK: - LLM Request

    @MainActor
    private func sendMessage() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let entry else { return }

        inputText = ""
        messages.append(AssistMessage(role: .user, raw: text))
        isLoading = true

        let client = AppSettings.shared.createLLMClient()
        let model = resolvedModel

        guard let imageData = jpegData(from: entry.image) else {
            messages.append(AssistMessage(role: .assistant, raw: "Failed to encode image for vision analysis."))
            isLoading = false
            return
        }

        let systemPrompt = buildSystemPrompt(for: entry)

        do {
            let response = try await client.describeImage(
                imageData,
                systemPrompt: systemPrompt,
                userMessage: text,
                model: model
            )
            messages.append(AssistMessage(role: .assistant, raw: response))
        } catch {
            messages.append(AssistMessage(role: .assistant, raw: "Error: \(error.localizedDescription)"))
        }

        isLoading = false
    }

    private func buildSystemPrompt(for entry: InspectedImage) -> String {
        if hasPrompt, let prompt = entry.metadata?.prompt {
            return """
            You are a helpful assistant for an AI image generation app. The user is showing you an \
            image along with its original generation prompt: "\(prompt)". You can analyze the image \
            and work with the existing prompt to enhance or vary it. When outputting an enhanced or \
            new prompt, place it on its own line preceded by "PROMPT:" so it can be detected.
            """
        } else {
            return """
            You are a helpful assistant for an AI image generation app. Analyze the image visually. \
            When suggesting prompts, format them as generation-ready text for Stable Diffusion or \
            Flux models. If you suggest a prompt, place it on its own line preceded by "PROMPT:" \
            so it can be detected.
            """
        }
    }

    private var resolvedModel: String {
        if !selectedModelName.isEmpty,
           availableModels.contains(where: { $0.name == selectedModelName }) {
            return selectedModelName
        }
        return availableModels.first?.name ?? selectedModelName
    }

    // MARK: - Model Loading

    private func loadModels() {
        Task { @MainActor in
            let client = AppSettings.shared.createLLMClient()
            if let models = try? await client.listModels(), !models.isEmpty {
                availableModels = models
                // Restore persisted selection or default to first
                if !selectedModelName.isEmpty,
                   models.contains(where: { $0.name == selectedModelName }) {
                    // keep current selection
                } else {
                    selectedModelName = models.first?.name ?? ""
                    UserDefaults.standard.set(selectedModelName, forKey: "assist.selectedModel")
                }
            }
        }
    }

    // MARK: - Entry Sync

    private func syncEntry(_ entry: InspectedImage) {
        if entry.id != lastEntryID {
            messages = []
            lastEntryID = entry.id
        }
    }

    // MARK: - Image Encoding

    private func jpegData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
            // Fallback: try CGImage path
            if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                let rep = NSBitmapImageRep(cgImage: cg)
                return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
            }
            return nil
        }
        return jpeg
    }
}

// MARK: - Flow Layout for Chips

private struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(maxWidth: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.maxHeight).reduce(0, +) + CGFloat(max(rows.count - 1, 0)) * spacing
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for subview in row.subviews {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.maxHeight + spacing
        }
    }

    private struct Row {
        var subviews: [LayoutSubview] = []
        var maxHeight: CGFloat = 0
    }

    private func computeRows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        var currentWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let needed = currentWidth > 0 ? currentWidth + spacing + size.width : size.width
            if currentWidth > 0 && needed > maxWidth {
                rows.append(current)
                current = Row()
                currentWidth = 0
            }
            current.subviews.append(subview)
            current.maxHeight = max(current.maxHeight, size.height)
            currentWidth = currentWidth > 0 ? currentWidth + spacing + size.width : size.width
        }
        if !current.subviews.isEmpty { rows.append(current) }
        return rows
    }
}

// MARK: - Hex Color Utility

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
