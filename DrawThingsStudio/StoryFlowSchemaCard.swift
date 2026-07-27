import SwiftUI

// MARK: - Schema-driven step card (260723 Phase 2)
//
// The generic form §8.5 calls for: one view that renders any `StoryFlowItemSchema`
// entry, so adding an instruction is a table row rather than a new view.
//
// It edits a `.passthrough` step in place. Passthrough already carries the value
// losslessly (`itemType` + `rawValueJSON`) and already round-trips through both the
// project format and the pipeline export — the only thing that was missing was a
// form, which is exactly what this is.

// MARK: - Reading and writing a passthrough step's value

/// Get/set helpers over a passthrough step's `rawValueJSON`.
///
/// Three encodings are stacked here and it is worth being explicit, because getting
/// a layer wrong is silent:
///   1. the step stores `rawValueJSON`, a JSON encoding of `StoryFlowItemValue`;
///   2. for object-valued instructions that value is a **`.string`** whose contents
///      are themselves JSON — the editor writes `dataset.jsonValue = JSON.stringify(…)`
///      and we match it (spec §8.3.1);
///   3. so an object field lives inside JSON inside a JSON string.
enum StoryFlowPassthroughValue {

    static func value(of step: WorkflowStep) -> StoryFlowItemValue? {
        guard let raw = step.parameters["rawValueJSON"],
              let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(StoryFlowItemValue.self, from: data)
    }

    static func set(_ value: StoryFlowItemValue, on step: inout WorkflowStep) {
        guard let data = try? JSONEncoder().encode(value),
              let json = String(data: data, encoding: .utf8) else { return }
        step.parameters["rawValueJSON"] = json
    }

    // MARK: Scalars

    static func text(of step: WorkflowStep) -> String {
        if case .string(let s)? = value(of: step) { return s }
        return ""
    }

    static func setText(_ text: String, on step: inout WorkflowStep) {
        set(.string(text), on: &step)
    }

    static func number(of step: WorkflowStep) -> Double {
        switch value(of: step) {
        case .int(let i)?:    return Double(i)
        case .double(let d)?: return d
        default:              return 0
        }
    }

    static func setNumber(_ number: Double, isInteger: Bool, on step: inout WorkflowStep) {
        set(isInteger ? .int(Int(number)) : .double(number), on: &step)
    }

    // MARK: Object fields

    static func object(of step: WorkflowStep) -> [String: Any] {
        guard case .string(let json)? = value(of: step),
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return dict
    }

    static func setObject(_ dict: [String: Any], on step: inout WorkflowStep) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return }
        set(.string(json), on: &step)
    }

    static func setObjectField(_ key: String, to newValue: Any, on step: inout WorkflowStep) {
        var dict = object(of: step)
        dict[key] = newValue
        setObject(dict, on: &step)
    }
}

// MARK: - The card

struct StoryFlowSchemaCard: View {
    let schema: StoryFlowItemSchema
    @Binding var step: WorkflowStep
    let allVariables: [WorkflowVariable]
    let onDelete: () -> Void
    let onChange: () -> Void

    var body: some View {
        StoryFlowCardChrome(title: schema.itemType,
                            accent: schema.accent,
                            onDelete: onDelete) {
            switch schema.shape {
            case .flag:
                // Nothing to edit — the instruction's presence *is* the setting.
                Text(schema.summary)
                    .font(TanqueDS.Font.mono(10.5))
                    .foregroundStyle(DashboardDS.muted)
                    .fixedSize(horizontal: false, vertical: true)

            case .string(_, let placeholder, let prefix, let multiline):
                stringField(placeholder: placeholder, prefix: prefix, multiline: multiline)

            case .number(_, let isInteger):
                numberField(isInteger: isInteger)

            case .object(let fields):
                objectFields(fields)
            }
        }
    }

    // MARK: Fields

    @ViewBuilder
    private func stringField(placeholder: String, prefix: String?, multiline: Bool) -> some View {
        HStack(alignment: .top, spacing: 4) {
            if let prefix {
                // The editor shows these as a fixed, non-editable lead-in (`~Pictures/`,
                // `find object: `) rather than as part of the value. Matching that keeps
                // users from typing the prefix in and doubling it.
                Text(prefix)
                    .font(TanqueDS.Font.mono(10.5))
                    .foregroundStyle(DashboardDS.muted)
                    .padding(.top, 5)
            }

            if multiline {
                // Prompt-bearing fields take variable references, so they get the same
                // picker the first-class prompt step uses.
                StoryFlowVariableField(
                    placeholder: placeholder,
                    variableTypes: [.prompt, .wildcard],
                    allVariables: allVariables,
                    text: textBinding,
                    onChange: onChange
                )
            } else {
                TextField(placeholder, text: textBinding)
                    .storyFlowFieldChrome()
                    .onSubmit { onChange() }
            }
        }
    }

    private func numberField(isInteger: Bool) -> some View {
        HStack(spacing: 6) {
            TextField("0", value: numberBinding, format: .number.grouping(.never))
                .multilineTextAlignment(.trailing)
                .frame(width: 60)
                .storyFlowFieldChrome()
                .onSubmit { onChange() }
            Text(schema.summary)
                .font(TanqueDS.Font.mono(10.5))
                .foregroundStyle(DashboardDS.muted)
                .lineLimit(1)
        }
    }

    /// Object fields wrap rather than sitting on one line — `moodboardWeights` has six
    /// and `inpaintTools` four, which no card is wide enough for in a row.
    private func objectFields(_ fields: [StoryFlowObjectField]) -> some View {
        FlowingFields {
            ForEach(fields, id: \.key) { field in
                objectField(field)
            }
        }
    }

    @ViewBuilder
    private func objectField(_ field: StoryFlowObjectField) -> some View {
        switch field.kind {
        case .number(_, let range, let step, let isInteger):
            labelled(field.label) {
                // No thousands separator: these are pixel dimensions and frame counts,
                // and "1,920" reads as two values.
                TextField("0", value: objectNumberBinding(field.key, range: range, isInteger: isInteger),
                          format: .number.grouping(.never))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 52)
                    .storyFlowFieldChrome()
                    .onSubmit { onChange() }
                    .help(rangeHelp(range: range, step: step))
            }

        case .toggle:
            labelled(field.label) {
                Toggle("", isOn: objectToggleBinding(field.key))
                    .labelsHidden()
                    .toggleStyle(.dashboardCheckbox)
            }

        case .text:
            labelled(field.label) {
                TextField("", text: objectTextBinding(field.key))
                    .frame(minWidth: 70)
                    .storyFlowFieldChrome()
                    .onSubmit { onChange() }
            }

        case .picklist(_, let options):
            labelled(field.label) {
                Picker("", selection: objectTextBinding(field.key)) {
                    ForEach(options, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 110)
                .font(TanqueDS.Font.mono(11))
            }

        case .cardList:
            // One card per line, matching the editor's textarea. Deliberately NOT typed
            // here: sweep's numeric coercion belongs at export, not in the form (§8.3.3).
            VStack(alignment: .leading, spacing: 3) {
                Text(field.label)
                    .font(TanqueDS.Font.mono(10))
                    .foregroundStyle(DashboardDS.muted)
                CardListEditor(
                    text: cardListText(field.key),
                    onCommit: { setCards(field.key, from: $0) }
                )
                    .font(TanqueDS.Font.mono(11))
                    .scrollContentBackground(.hidden)
                    .background(DashboardDS.bg, in: RoundedRectangle(cornerRadius: 5))
                    // Capped rather than growing: a real wildcard can hold twenty cards,
                    // and four of those in one workflow would push every other step off
                    // screen. It scrolls internally instead.
                    .frame(height: 76)
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(DashboardDS.border, lineWidth: 1))
                    .help("One card per line")
            }
            .frame(minWidth: 180)
        }
    }

    private func labelled<Content: View>(_ label: String,
                                         @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(TanqueDS.Font.mono(10))
                .foregroundStyle(DashboardDS.muted)
            content()
        }
    }

    private func rangeHelp(range: ClosedRange<Double>?, step: Double) -> String {
        guard let range else { return "Step \(step.clean)" }
        return "\(range.lowerBound.clean)–\(range.upperBound.clean), step \(step.clean)"
    }

    // MARK: Bindings

    private var textBinding: Binding<String> {
        Binding(
            get: { StoryFlowPassthroughValue.text(of: step) },
            set: { StoryFlowPassthroughValue.setText($0, on: &step) }
        )
    }

    private var numberBinding: Binding<Double> {
        Binding(
            get: { StoryFlowPassthroughValue.number(of: step) },
            set: { newValue in
                guard case .number(_, let isInteger) = schema.shape else { return }
                StoryFlowPassthroughValue.setNumber(newValue, isInteger: isInteger, on: &step)
                onChange()
            }
        )
    }

    private func objectNumberBinding(_ key: String,
                                     range: ClosedRange<Double>?,
                                     isInteger: Bool) -> Binding<Double> {
        Binding(
            get: { (StoryFlowPassthroughValue.object(of: step)[key] as? NSNumber)?.doubleValue ?? 0 },
            set: { newValue in
                // Clamp to the editor's own range so a typed value can't leave the form
                // in a state the editor would immediately reject.
                let clamped = range.map { min(max(newValue, $0.lowerBound), $0.upperBound) } ?? newValue
                let stored: Any = isInteger ? Int(clamped) : clamped
                StoryFlowPassthroughValue.setObjectField(key, to: stored, on: &step)
                onChange()
            }
        )
    }

    private func objectToggleBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { StoryFlowPassthroughValue.object(of: step)[key] as? Bool ?? false },
            set: {
                StoryFlowPassthroughValue.setObjectField(key, to: $0, on: &step)
                onChange()
            }
        )
    }

    private func objectTextBinding(_ key: String) -> Binding<String> {
        Binding(
            get: { StoryFlowPassthroughValue.object(of: step)[key] as? String ?? "" },
            set: {
                StoryFlowPassthroughValue.setObjectField(key, to: $0, on: &step)
                onChange()
            }
        )
    }

    /// The card list as editable text, one per line.
    private func cardListText(_ key: String) -> String {
        let cards = StoryFlowPassthroughValue.object(of: step)[key] as? [Any] ?? []
        return cards.map { "\($0)" }.joined(separator: "\n")
    }

    private func setCards(_ key: String, from text: String) {
        let cards = text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        StoryFlowPassthroughValue.setObjectField(key, to: cards, on: &step)
        onChange()
    }
}

/// Card list editor that keeps its own text while you type.
///
/// **Do not bind a `TextEditor` straight to the parsed model here.** The parse
/// trims each line and drops empty ones, so re-deriving the displayed text from
/// the model on every keystroke deletes the space you just typed at the end of
/// `red ` before you can type `car`, and swallows the newline that would start a
/// new card. Multi-word cards and new lines both become impossible to type —
/// which is most of what a wildcard is for.
///
/// So the text lives here while the field has focus, and is parsed back into
/// cards when focus leaves. Typing stays literal; normalisation happens once.
private struct CardListEditor: View {
    let text: String
    let onCommit: (String) -> Void

    @State private var draft: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextEditor(text: $draft)
            .focused($isFocused)
            .onAppear { draft = text }
            // Re-seed when the model changes underneath us (a different step
            // scrolled into this view), but never while the user is typing.
            .onChange(of: text) { _, newValue in
                if !isFocused { draft = newValue }
            }
            .onChange(of: isFocused) { _, focused in
                if !focused { onCommit(draft) }
            }
    }
}

// MARK: - Wrapping field row

/// Lays fields out left to right and wraps. `moodboardWeights` has six fields and
/// `inpaintTools` four; a single `HStack` would either clip them or force the card
/// wider than the column.
private struct FlowingFields: Layout {
    var spacing: CGFloat = 10
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

private extension Double {
    /// Trims a trailing `.0` so ranges read as "1–8" rather than "1.0–8.0".
    var clean: String {
        self == rounded() ? String(Int(self)) : String(format: "%g", self)
    }
}
