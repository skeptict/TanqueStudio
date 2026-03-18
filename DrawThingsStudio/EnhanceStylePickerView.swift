//
//  EnhanceStylePickerView.swift
//  DrawThingsStudio
//
//  Reusable popover content for selecting a prompt enhancement style,
//  and LLMActionLabel for consistent spinner/icon button labels.
//

import SwiftUI

/// Reusable button label that shows a spinner when active or an icon otherwise.
struct LLMActionLabel: View {
    let isActive: Bool
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            if isActive {
                ProgressView().scaleEffect(0.6).frame(width: 14, height: 14)
            } else {
                Image(systemName: icon)
            }
            Text(text)
        }
        .font(.caption)
    }
}

struct EnhanceStylePickerView: View {
    let onSelect: (CustomPromptStyle) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Enhance Style")
                .font(.headline)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(PromptStyleManager.shared.styles) { style in
                        Button {
                            onSelect(style)
                        } label: {
                            HStack {
                                Image(systemName: style.icon).frame(width: 22)
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
            .frame(maxHeight: 260)
        }
        .padding()
        .frame(width: 220)
    }
}
