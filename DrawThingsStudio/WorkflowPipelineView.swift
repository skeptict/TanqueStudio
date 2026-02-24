//
//  WorkflowPipelineView.swift
//  DrawThingsStudio
//
//  Multi-step generation pipeline: each step can use a different model/config,
//  and passes its output image to the next step as an img2img source.
//  Inspired by ComfyUI's node-based chaining, adapted as a linear pipeline.
//

import SwiftUI

struct WorkflowPipelineView: View {
    @ObservedObject var viewModel: WorkflowPipelineViewModel
    @StateObject private var assetManager = DrawThingsAssetManager.shared

    var body: some View {
        HStack(spacing: 16) {
            stepListPanel
                .frame(minWidth: 220, idealWidth: 250, maxWidth: 300)

            if let selected = viewModel.selectedStep,
               let index = viewModel.steps.firstIndex(where: { $0.id == selected.id }) {
                PipelineStepEditorView(
                    step: $viewModel.steps[index],
                    stepIndex: index,
                    totalSteps: viewModel.steps.count,
                    availableModels: assetManager.allModels,
                    isLoadingModels: assetManager.isLoading || assetManager.isCloudLoading,
                    onRefreshModels: { Task { await assetManager.forceRefresh() } }
                )
                .frame(minWidth: 380)
            } else {
                pipelineEmptyState
                    .frame(minWidth: 380)
            }
        }
        .padding(20)
        .neuBackground()
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { viewModel.addStep() } label: {
                    Label("Add Step", systemImage: "plus")
                }
                .help("Add a new pipeline step")

                Button {
                    if let selected = viewModel.selectedStep {
                        viewModel.removeStep(selected)
                    }
                } label: {
                    Label("Remove Step", systemImage: "minus")
                }
                .disabled(viewModel.selectedStep == nil || viewModel.isRunning)
                .help("Remove selected step")

                Divider()

                if viewModel.isRunning {
                    Button { viewModel.cancelPipeline() } label: {
                        Label("Cancel", systemImage: "stop.fill")
                    }
                    .help("Cancel pipeline execution")
                } else {
                    Button { viewModel.runPipeline() } label: {
                        Label("Run Pipeline", systemImage: "play.fill")
                    }
                    .disabled(viewModel.steps.isEmpty || viewModel.steps.allSatisfy { $0.model.isEmpty })
                    .help("Run all pipeline steps sequentially")
                }
            }
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .task {
            await viewModel.checkConnection()
            await assetManager.fetchAssets()
            await assetManager.fetchCloudCatalogIfNeeded()
        }
    }

    // MARK: - Step List Panel

    private var stepListPanel: some View {
        VStack(spacing: 0) {
            HStack {
                NeuSectionHeader("Pipeline Steps", icon: "list.number")
                Spacer()
                NeuStatusBadge(
                    color: connectionColor,
                    text: viewModel.connectionStatus.displayText
                )
                .font(.caption2)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if viewModel.steps.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.stack.badge.plus")
                        .font(.system(size: 32))
                        .foregroundColor(.neuTextSecondary.opacity(0.4))
                    Text("No steps yet")
                        .font(.callout)
                        .foregroundColor(.neuTextSecondary)
                    Button("Add First Step") { viewModel.addStep() }
                        .buttonStyle(NeumorphicButtonStyle(isProminent: true))
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List(selection: $viewModel.selectedStepID) {
                    ForEach(viewModel.steps.indices, id: \.self) { index in
                        PipelineStepRowView(
                            step: viewModel.steps[index],
                            index: index,
                            isCurrentStep: viewModel.isRunning && viewModel.currentStepIndex == index
                        )
                        .tag(viewModel.steps[index].id)
                    }
                    .onMove { from, to in viewModel.moveSteps(from: from, to: to) }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }

            Divider()
                .padding(.horizontal, 12)

            Button { viewModel.addStep() } label: {
                HStack {
                    Image(systemName: "plus")
                    Text("Add Step")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(NeumorphicButtonStyle())
            .padding(12)
        }
        .neuCard(cornerRadius: 20)
    }

    private var connectionColor: Color {
        switch viewModel.connectionStatus {
        case .connected: return .green
        case .connecting: return .orange
        case .error: return .red
        case .disconnected: return .gray
        }
    }

    private var pipelineEmptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 52))
                .foregroundColor(.neuTextSecondary.opacity(0.3))
            Text("Multi-Model Pipeline")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.neuTextSecondary)
            VStack(spacing: 6) {
                Text("Chain multiple generation steps where each step")
                Text("can use a different model, and pass its output")
                Text("to the next step as an img2img source.")
            }
            .font(.callout)
            .foregroundColor(.neuTextSecondary.opacity(0.7))
            .multilineTextAlignment(.center)
            Button("Add First Step") { viewModel.addStep() }
                .buttonStyle(NeumorphicButtonStyle(isProminent: true))
                .padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .neuCard(cornerRadius: 24)
    }
}

// MARK: - Step Row

struct PipelineStepRowView: View {
    let step: PipelineStep
    let index: Int
    let isCurrentStep: Bool

    var body: some View {
        HStack(spacing: 10) {
            // Step number / spinner
            ZStack {
                if isCurrentStep {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 26, height: 26)
                } else if step.resultImage != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .frame(width: 26, height: 26)
                } else {
                    Text("\(index + 1)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.neuTextSecondary)
                        .frame(width: 26, height: 26)
                        .background(
                            Circle()
                                .fill(Color.neuSurface)
                                .shadow(color: .neuShadowDark.opacity(0.15), radius: 2, x: 1, y: 1)
                        )
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(step.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if !step.model.isEmpty {
                    Text(step.model)
                        .font(.caption2)
                        .foregroundColor(.neuAccent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("No model set")
                        .font(.caption2)
                        .foregroundColor(.red.opacity(0.7))
                }
            }

            Spacer()

            // Chain indicator (not first step)
            if index > 0 && step.useOutputFromPreviousStep {
                Image(systemName: "arrow.up.to.line")
                    .font(.caption2)
                    .foregroundColor(.neuTextSecondary.opacity(0.5))
            }

            // Result thumbnail
            if let result = step.resultImage {
                Image(nsImage: result)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Step Editor

struct PipelineStepEditorView: View {
    @Binding var step: PipelineStep
    let stepIndex: Int
    let totalSteps: Int
    let availableModels: [DrawThingsModel]
    let isLoadingModels: Bool
    let onRefreshModels: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                // Step header
                HStack {
                    TextField("Step name", text: $step.name)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .textFieldStyle(.plain)
                    Spacer()
                    Text("Step \(stepIndex + 1) of \(totalSteps)")
                        .font(.caption)
                        .foregroundColor(.neuTextSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .neuInset(cornerRadius: 6)
                }

                Divider()

                // img2img chain toggle (only available for steps after first)
                if stepIndex > 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(isOn: $step.useOutputFromPreviousStep) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.up.to.line")
                                    .foregroundColor(.neuAccent)
                                Text("Use output from previous step")
                                    .font(.body)
                            }
                        }
                        .toggleStyle(.switch)

                        if step.useOutputFromPreviousStep {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Strength").font(.caption).foregroundColor(.neuTextSecondary)
                                HStack(spacing: 8) {
                                    Slider(value: $step.strength, in: 0...1, step: 0.05)
                                        .tint(Color.neuAccent)
                                    Text(String(format: "%.2f", step.strength))
                                        .font(.caption)
                                        .foregroundColor(.neuTextSecondary)
                                        .frame(width: 35)
                                }
                            }
                            .padding(.leading, 28)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(12)
                    .neuInset(cornerRadius: 12)
                }

                // Model
                VStack(alignment: .leading, spacing: 8) {
                    NeuSectionHeader("Model", icon: "cpu")
                    ModelSelectorView(
                        availableModels: availableModels,
                        selection: $step.model,
                        isLoading: isLoadingModels,
                        onRefresh: onRefreshModels
                    )
                }

                // Prompt
                VStack(alignment: .leading, spacing: 8) {
                    NeuSectionHeader("Prompt", icon: "text.quote")
                    TextEditor(text: $step.prompt)
                        .font(.body)
                        .frame(minHeight: 80, maxHeight: 140)
                        .padding(8)
                        .scrollContentBackground(.hidden)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.neuBackground.opacity(0.6))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.neuShadowDark.opacity(0.1), lineWidth: 0.5)
                        )
                }

                // Negative Prompt
                VStack(alignment: .leading, spacing: 8) {
                    NeuSectionHeader("Negative Prompt")
                    TextField("Things to avoid...", text: $step.negativePrompt)
                        .textFieldStyle(NeumorphicTextFieldStyle())
                }

                // Config grid
                VStack(alignment: .leading, spacing: 12) {
                    NeuSectionHeader("Generation Settings", icon: "gearshape")

                    // Sampler
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sampler").font(.caption).foregroundColor(.neuTextSecondary)
                        SimpleSearchableDropdown(
                            title: "Sampler",
                            items: DrawThingsSampler.builtIn.map { $0.name },
                            selection: $step.sampler,
                            placeholder: "Search samplers..."
                        )
                    }

                    // Dimensions
                    HStack(spacing: 12) {
                        pipelineConfigField("Width", value: $step.width)
                        pipelineConfigField("Height", value: $step.height)
                        pipelineConfigField("Steps", value: $step.steps)
                        Spacer()
                    }

                    // Guidance & Seed
                    HStack(spacing: 12) {
                        pipelineConfigFieldDouble("Guidance", value: $step.guidanceScale)
                        pipelineConfigField("Seed", value: $step.seed)
                        Spacer()
                    }
                }

                // LoRAs
                Divider()
                LoRAConfigurationView(
                    availableLoRAs: DrawThingsAssetManager.shared.loras,
                    selectedLoRAs: $step.loras
                )

                // Result image
                if let result = step.resultImage {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        NeuSectionHeader("Output", icon: "photo")
                        Image(nsImage: result)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .shadow(color: .neuShadowDark.opacity(0.15), radius: 6, x: 3, y: 3)
                            .frame(maxWidth: .infinity)
                            .contextMenu {
                                Button("Copy Image") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.writeObjects([result])
                                }
                            }
                    }
                } else if step.isRunning {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Generating…")
                            .font(.callout)
                            .foregroundColor(.neuTextSecondary)
                    }
                    .padding(.top, 8)
                }
            }
            .padding(20)
        }
        .neuCard(cornerRadius: 24)
    }

    private func pipelineConfigField(_ label: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundColor(.neuTextSecondary)
            TextField("", value: value, format: .number)
                .textFieldStyle(NeumorphicTextFieldStyle())
                .frame(width: 70)
        }
    }

    private func pipelineConfigFieldDouble(_ label: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundColor(.neuTextSecondary)
            TextField("", value: value, format: .number.precision(.fractionLength(1)))
                .textFieldStyle(NeumorphicTextFieldStyle())
                .frame(width: 70)
        }
    }
}
