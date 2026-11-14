import SwiftUI

/// Per-slot result after a push, led by a plain-language statement of what the camera now holds.
///
/// The headline is `SlotWriteResult.outcome`: what reached the camera, not whether the write threw.
/// A slot can be renamed and half-written by a write that fails, or lack a film simulation after one
/// that succeeds. Every property in the encode set is accounted for, including the ones never
/// attempted.
struct PushResultsView: View {
    let results: [SlotWriteResult]
    @Environment(\.dismiss) private var dismiss
    @State private var didCopy = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(results) { result in
                    Section("Slot C\(result.slot)") {
                        statusRow(result)
                        Text(result.plainLanguageState)
                            .font(.callout)
                            .foregroundStyle(.primary)

                        if result.nameOutcome == .written, let name = result.nameApplied {
                            Label("Named “\(name)”", systemImage: "textformat")
                                .font(.caption).foregroundStyle(.secondary)
                        } else if let nameOutcome = result.nameOutcome {
                            Label("Slot name: \(describe(nameOutcome))", systemImage: "textformat")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        // The value, not just the status: a passthrough writes the slot's own D192
                        // back and verifies against itself, so "Written and verified" alone could
                        // sit over a film simulation the recipe never asked for.
                        if let sim = result.filmSimulationReadBack {
                            Label("Film simulation now: \(sim.displayName)", systemImage: "camera.filters")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let dr = result.dynamicRangeReadBack {
                            Label("Dynamic range now: \(dr.displayName)", systemImage: "circle.lefthalf.filled")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(result.advisories, id: \.self) { advisory in
                            Label(advisory, systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(DSColor.caution)
                        }
                        // Something the camera said about the bank, not the recipe — an info line,
                        // because nothing went wrong. See `SlotWriteResult.imageSizeFixedByBank`.
                        ForEach(result.notes, id: \.self) { note in
                            Label(note, systemImage: "info.circle")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if !result.clampedFields.isEmpty {
                            Label("Clamped: \(result.clampedFields.joined(separator: ", "))",
                                  systemImage: "arrow.down.right.and.arrow.up.left")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if !result.unsupportedOnModel.isEmpty {
                            outcomeLabel("Not supported on this model", result.unsupportedOnModel,
                                         "minus.circle", Color.secondary)
                        }

                        // Each failure kind gets its own line: one shared label would tell a tester
                        // whose cable came out that their camera lacked thirteen features.
                        if !result.rejected.isEmpty {
                            outcomeLabel("Refused by the camera", result.rejected,
                                         "minus.circle", DSColor.caution)
                            // A refusal with a likely cause gets it named here: the slot's ISO or
                            // D-Range Priority for Dynamic Range, a HEIF bank for Clarity, a body
                            // that refuses a toning of 0. These are suggestions from the refusal
                            // pattern, not observed state (zgrimz/fujifilm-ptp-reference
                            // `docs/04-custom-slots.md#why-a-write-is-refused`); naming one sends a
                            // tester to check a menu instead of filing a bug.
                            ForEach([result.dynamicRangeRefusalHint,
                                     result.dRangePriorityRefusalHint,
                                     result.clarityRefusalHint,
                                     result.toningZeroRefusalHint].compactMap { $0 }, id: \.self) { hint in
                                Text(hint)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 20)
                            }
                        }
                        if !result.notAttempted.isEmpty {
                            outcomeLabel("Never attempted", result.notAttempted,
                                         "circle.dashed", Color.secondary)
                        }
                        let uncertain = result.fields.filter { $0.outcome == .outcomeUnknown || $0.outcome == .unverified }
                        if !uncertain.isEmpty {
                            outcomeLabel("Could not confirm", uncertain, "questionmark.circle", DSColor.caution)
                        }
                        if let error = result.errorMessage {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption).foregroundStyle(DSColor.caution)
                        }

                        // Raw wrote-vs-read values for every field that failed verification —
                        // without these a mismatch is unactionable (is it the encoding, or did the
                        // camera clamp the value because of some other setting?).
                        ForEach(result.mismatches, id: \.code) { mismatch in
                            Label(mismatch.detail, systemImage: "curlybraces")
                                .font(.caption2.monospaced()).foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .navigationTitle("Push Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Per-label text selection can't select the set, so without these the evidence for
                // a failed or partial push dead-ends on this screen.
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        UIPasteboard.general.string = report
                        didCopy = true
                    } label: {
                        Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(item: report) { Label("Share", systemImage: "square.and.arrow.up") }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    @ViewBuilder
    private func outcomeLabel(_ title: String, _ fields: [FieldResult],
                              _ symbol: String, _ tint: Color) -> some View {
        Label("\(title): \(fields.map(\.field).joined(separator: ", "))", systemImage: symbol)
            .font(.caption).foregroundStyle(tint)
    }

    @ViewBuilder
    private func statusRow(_ result: SlotWriteResult) -> some View {
        switch result.outcome {
        case .applied:
            Label("Written and verified", systemImage: "checkmark.circle.fill").foregroundStyle(DSColor.ledOK)
        case .partiallyApplied:
            Label("Partly written", systemImage: "exclamationmark.circle.fill").foregroundStyle(DSColor.caution)
        case .unknown:
            Label("Could not verify", systemImage: "questionmark.circle.fill").foregroundStyle(DSColor.caution)
        case .notWritten:
            Label("Not written", systemImage: "xmark.circle.fill").foregroundStyle(DSColor.caution)
        }
    }

    /// The full per-field table, not a summary — this is the artifact that makes a partial write
    /// diagnosable on a body nobody has tested.
    private var report: String {
        var lines = ["Fuji Cookbook — push results"]
        for result in results {
            lines.append("")
            lines.append("Slot C\(result.slot): \(result.outcome)")
            lines.append("  \(result.plainLanguageState)")
            if let sim = result.filmSimulationReadBack { lines.append("  film simulation now: \(sim.displayName)") }
            if let dr = result.dynamicRangeReadBack { lines.append("  dynamic range now: \(dr.displayName)") }
            for advisory in result.advisories { lines.append("  note: \(advisory)") }
            for note in result.notes { lines.append("  bank: \(note)") }
            if let name = result.nameApplied {
                lines.append("  name: “\(name)” (\(result.nameOutcome.map(describe) ?? "not confirmed"))")
            }
            if !result.clampedFields.isEmpty { lines.append("  clamped: \(result.clampedFields.joined(separator: ", "))") }
            if let error = result.errorMessage { lines.append("  error: \(error)") }
            lines.append("  fields:")
            for field in result.fields {
                let code = field.code == 0 ? "     " : PTPHex.propertyLabel(field.code)
                lines.append("    \(code)  \(field.field.padding(toLength: max(field.field.count, 22), withPad: " ", startingAt: 0))  \(describe(field.outcome))")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func describe(_ outcome: FieldOutcome) -> String {
        switch outcome {
        case .written: return "written"
        case .unverified: return "written, unverified"
        case .outcomeUnknown: return "sent, response unavailable"
        case .notAttempted: return "never attempted"
        case .rejected(let code):
            guard let code else { return "unsupported on this model" }
            return "refused \(PTPHex.code(code)) \(FujiPTP.responseName(code) ?? "")"
        case .mismatched(let wrote, let read):
            func hex(_ d: Data?) -> String { d.map { "0x" + PTPHex.bytes($0) } ?? "nothing" }
            return "wrote \(hex(wrote)), camera has \(hex(read))"
        }
    }
}
