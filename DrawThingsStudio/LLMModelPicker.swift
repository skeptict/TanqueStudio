import SwiftUI

// MARK: - LLM Model Picker
//
// The MODEL row shared by Assist and Compose: a menu of the models the configured
// LLM server reports, falling back to a text field when it reports none. Both hosts
// bind it to `AppSettings.llmModelName`, so a pick in either place is a pick in both.
// Only a pick changes it: a model the server doesn't list is kept and flagged, never
// swapped for the server's first one.

struct LLMModelPicker: View {
    @Binding var modelName: String

    @State private var availableModels: [String] = []
    @State private var isFetching = false
    @State private var fetchHint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("MODEL")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                RefreshButton(isFetching: isFetching) {
                    fetchModels()
                }
            }
            if availableModels.isEmpty {
                TextField("llama3, mistral…", text: $modelName)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            } else {
                Picker("", selection: $modelName) {
                    ForEach(Self.menuEntries(serverModels: availableModels, saved: modelName), id: \.self) { name in
                        Text(availableModels.contains(name) ? name : "\(name) (not on server)").tag(name)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)
            }
            if let fetchHint, !isFetching {
                Text(fetchHint)
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            if availableModels.isEmpty && !isFetching {
                fetchModels()
            }
        }
    }

    /// The menu's entries: the server's models, with the saved choice first when the
    /// server doesn't list it, so the Picker always has a tag for its selection.
    static func menuEntries(serverModels: [String], saved: String) -> [String] {
        guard !saved.isEmpty, !serverModels.contains(saved) else { return serverModels }
        return [saved] + serverModels
    }

    private func fetchModels() {
        guard !isFetching else { return }
        isFetching = true
        let baseURL = AppSettings.shared.llmEffectiveBaseURL
        let provider = AppSettings.shared.llmProvider
        let apiKey = AppSettings.shared.llmAPIKey
        Task { @MainActor in
            defer { isFetching = false }
            do {
                let models = try await LLMService.fetchModels(
                    baseURL: baseURL, provider: provider, apiKey: apiKey
                )
                availableModels = models
                if models.isEmpty {
                    fetchHint = "No \(provider.displayName) models found — pull one (e.g. `ollama pull llama3`), then refresh."
                } else if modelName.isEmpty {
                    fetchHint = nil
                    modelName = models[0]
                } else if !models.contains(modelName) {
                    // Keep the saved choice. Replacing it here used to discard the user's
                    // model the moment Assist opened against a different provider, and
                    // nothing said so. A request with it will fail visibly instead.
                    fetchHint = "\(modelName) isn't on this \(provider.displayName) server. Pick one of its models above."
                } else {
                    fetchHint = nil
                }
            } catch {
                availableModels = []
                fetchHint = "Couldn't reach \(provider.displayName) at \(baseURL). Make sure it's running and the host is correct in Settings, then refresh."
            }
        }
    }
}

// MARK: - Refresh Button

/// The spin is driven by a `TimelineView`, which sets the angle each frame rather than
/// animating it. It used to be a `repeatForever` animation, and that leaked: started inside
/// `withAnimation` it caught the Compose sheet's own sizing and slid the whole sheet back
/// and forth; scoped with `.animation(_:value:)` it still caught the icon's own move when
/// the Assist section expanded, and the icon drifted. Nothing here is an animation now.
private struct RefreshButton: View {
    let isFetching: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            TimelineView(.animation(paused: !isFetching)) { context in
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 9))
                    .rotationEffect(.degrees(isFetching ? angle(at: context.date) : 0))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tertiary)
        .disabled(isFetching)
    }

    /// One turn per second.
    private func angle(at date: Date) -> Double {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360
    }
}
