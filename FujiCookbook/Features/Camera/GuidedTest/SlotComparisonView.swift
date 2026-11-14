import SwiftUI

/// Keep the original USB reading in the report while showing what a tester can actually compare.
/// The suffix fallback covers snapshots saved before explicit applicability metadata was added.
struct GuidedComparisonRowPresentation {
    let row: GuidedTestSession.SlotComparison.Row

    var priorityControlled: Bool { row.isPriorityControlled }

    var value: String { priorityControlled ? "Controlled by D-Range Priority" : row.appShowed }
}

/// One slot, setting by setting, against the camera's own IQ menu.
///
/// Read-back verification proves bytes round-tripped. It cannot prove they *mean* what the codec
/// says — if a body stores Classic Chrome as a number this app reads as something else, the app
/// shows the wrong film simulation with total confidence and every automatic check agrees with it.
/// A person reading their camera's menu is the only instrument that catches it.
///
/// Only explicit difference controls change the tester's answers. Tapping a value must not turn
/// it into a finding or make a manual observation look like an automatically detected mismatch.
struct SlotComparisonView: View {
    @Binding var comparison: GuidedTestSession.SlotComparison
    let slotLabel: String
    let slotName: String

    @Environment(\.dismiss) private var dismiss

    private var differingCount: Int { comparison.rows.filter(\.differs).count }
    private var hasPriorityControlledRows: Bool {
        comparison.rows.contains { GuidedComparisonRowPresentation(row: $0).priorityControlled }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    instructions
                    if hasPriorityControlledRows {
                        GuidedNoticeCard(title: "D-Range Priority is on",
                            systemImage: "slider.horizontal.3",
                            message: "Compare D-Range Priority and the other active settings. Skip Dynamic Range, Highlight Tone and Shadow Tone; the camera is controlling them.")
                    }
                    rows
                    conditions
                    if !comparison.fieldsAppCouldNotRead.isEmpty { unreadable }
                }
                .padding(18)
            }
            footer
        }
        .background(DSColor.background.ignoresSafeArea())
        .navigationTitle("\(slotLabel) · \(slotName)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var instructions: some View {
        GuidedNoticeCard(
            title: "On the camera",
            systemImage: "camera",
            message: "Unplug the USB cable. On the camera, open \(slotLabel) in the Image Quality (IQ) menu and compare each setting below. If a value differs, choose Report a difference below it. If everything matches, leave the rows unchanged and confirm at the bottom. Differences are recorded from your answers. The bank's ISO and image format are in the same list; note them below the settings.")
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(Array(comparison.rows.enumerated()), id: \.element.field) { index, row in
                let presentation = GuidedComparisonRowPresentation(row: row)
                VStack(spacing: 0) {
                    rowContent(row, presentation: presentation)

                    if !presentation.priorityControlled || row.differs {
                        Button { setDifference(index, differs: !row.differs) } label: {
                            Text(row.differs ? "Clear difference" : "Report a difference")
                                .font(.caption.weight(.medium))
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(DSColor.signalText)
                        .padding(.horizontal, 14)
                        .accessibilityLabel("\(row.differs ? "Clear difference" : "Report a difference") for \(row.label)")
                    }

                    if row.differs {
                        // Optional on purpose. "It's different" is already the finding; what the
                        // camera actually shows turns it from a bug report into a decoding table.
                        GuidedTextField(label: "What does the camera show? (optional)",
                                        placeholder: "e.g. Weak, Small",
                                        text: cameraShowsBinding(index))
                            .padding(.horizontal, 14)
                            .padding(.bottom, 12)
                    }
                }
                if index < comparison.rows.count - 1 {
                    Rectangle().fill(DSColor.separator).frame(height: 1).padding(.leading, 14)
                }
            }
        }
        .themedCard(cornerRadius: 16)
    }

    private func rowContent(_ row: GuidedTestSession.SlotComparison.Row,
                            presentation: GuidedComparisonRowPresentation) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            // No empty checkbox: it can be mistaken for a control to confirm a matching value.
            if row.differs || presentation.priorityControlled {
                Image(systemName: row.differs ? "exclamationmark.circle.fill" : "lock")
                    .font(.subheadline)
                    .foregroundStyle(row.differs ? DSColor.caution : DSColor.textSecondary.opacity(0.6))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(row.label).font(.subheadline).foregroundStyle(DSColor.textSecondary)
                if row.differs {
                    Text(presentation.priorityControlled ? "You marked this as different earlier" : "You marked this as different")
                        .font(.caption).foregroundStyle(DSColor.caution)
                }
            }
            Spacer(minLength: 12)
            Text(presentation.value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(presentation.priorityControlled ? DSColor.textSecondary : DSColor.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    /// The two bank conditions a tester can read and the app can't. Neither is among the 23 bank
    /// properties, and both decide whether a Dynamic Range, D-Range Priority or Clarity refusal is a
    /// gate or a finding. Optional: an unanswered field stays nil, never JPEG or base ISO.
    private var conditions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Also note for \(slotLabel)", systemImage: "info.circle")
                .font(.subheadline.weight(.semibold)).foregroundStyle(DSColor.textPrimary)
            Text("The app can't read a bank's ISO or image format, and both decide whether the camera accepts Dynamic Range, D-Range Priority and Clarity.")
                .font(.caption).foregroundStyle(DSColor.textSecondary)
            GuidedTextField(label: "ISO (optional)", placeholder: "e.g. 125, 1600 or Auto", text: isoBinding)
            VStack(alignment: .leading, spacing: 6) {
                Text("Image format").font(.caption.weight(.semibold)).foregroundStyle(DSColor.textSecondary)
                GuidedChoiceRow<GuidedTestSession.ImageFormatAnswer>(
                    choices: [.init(value: .jpeg, label: "JPEG"), .init(value: .heif, label: "HEIF"),
                              .init(value: .notChecked, label: "Didn't check")],
                    selection: $comparison.imageFormatShown)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard(cornerRadius: 16)
    }

    /// Short, like the setting it copies: a bank's ISO is a number or "Auto".
    private static let maxISOCharacters = 16

    private var isoBinding: Binding<String> {
        Binding(get: { comparison.isoShown ?? "" },
                set: { typed in
                    let kept = String(typed.prefix(Self.maxISOCharacters))
                    comparison.isoShown = kept.isEmpty ? nil : kept
                })
    }

    private var unreadable: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("The app couldn't identify these values", systemImage: "questionmark.circle")
                .font(.subheadline.weight(.semibold)).foregroundStyle(DSColor.caution)
            Text("If you can, enter what the camera shows. The app can't confirm these values yet.")
                .font(.caption).foregroundStyle(DSColor.textSecondary)
            ForEach(comparison.fieldsAppCouldNotRead, id: \.self) { field in
                GuidedTextField(label: "\(field) — camera shows (optional)",
                                placeholder: "Value shown in the camera's menu",
                                text: unreadableBinding(field))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard(cornerRadius: 16)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if !comparison.fieldsAppCouldNotRead.isEmpty {
                GuidedPrimaryButton(title: "Save Observations", systemImage: "checkmark") {
                    comparison.confirmedMatching = false
                    comparison.checkedAt = CameraCompatibilityReport.timestamp()
                    dismiss()
                }
            } else if differingCount == 0 {
                GuidedPrimaryButton(title: hasPriorityControlledRows ? "Active Settings Match" : "Everything Matches", systemImage: "checkmark") {
                    comparison.confirmedMatching = true
                    comparison.checkedAt = CameraCompatibilityReport.timestamp()
                    dismiss()
                }
            } else {
                GuidedPrimaryButton(title: "Save — \(guidedSettingsDiffer(differingCount))",
                                    systemImage: "checkmark") {
                    comparison.confirmedMatching = false
                    comparison.checkedAt = CameraCompatibilityReport.timestamp()
                    dismiss()
                }
            }
            GuidedSecondaryButton(title: "Check Later") { dismiss() }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(DSColor.background)
    }

    private func setDifference(_ index: Int, differs: Bool) {
        comparison.rows[index].differs = differs
        if !differs { comparison.rows[index].cameraShows = nil }
    }

    private func cameraShowsBinding(_ index: Int) -> Binding<String> {
        Binding(get: { comparison.rows[index].cameraShows ?? "" },
                set: { comparison.rows[index].cameraShows = $0.isEmpty ? nil : $0 })
    }

    private func unreadableBinding(_ field: String) -> Binding<String> {
        Binding(get: { comparison.unreadableCameraShows?[field] ?? "" },
                set: { value in
                    var observations = comparison.unreadableCameraShows ?? [:]
                    observations[field] = value.isEmpty ? nil : value
                    comparison.unreadableCameraShows = observations.isEmpty ? nil : observations
                })
    }
}
