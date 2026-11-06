import SwiftUI
import UIKit

/// **Send Feedback** — the other half of Help & Feedback: what you want to say, and nothing else.
///
/// `DiagnosticsReportView` exists for a bug and carries everything that makes one findable: both
/// launches' logs, the camera compatibility report, your settings. That is the right payload for a
/// problem and the wrong one for "the Kitchen is slow on my phone" — so this screen carries only the
/// note and the four lines that say which build it was written on.
///
/// **The dependency list is the disclosure.** There is no `CameraServices`, no
/// `modelContext`, no `AppLog` call and no `CameraReportStore` read anywhere in this file, and
/// `SupportMail.feedback(text:)` leaves `extraFiles` empty. A reviewer can confirm the promise by
/// reading this file rather than by trusting the copy. Keep it that way: if this screen ever needs
/// a log, it has stopped being this screen.
struct SendFeedbackView: View {
    @State private var note = ""

    private var trimmedNote: String { note.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isEmpty: Bool { trimmedNote.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                noteEditor
                // Dimmed as well as disabled: the button draws its own fill and text colours, which
                // `.disabled` leaves unchanged.
                ShareReportButton(title: "Share Feedback",
                                  report: { SupportMail.feedback(text: feedbackText) })
                    .disabled(isEmpty)
                    .opacity(isEmpty ? 0.45 : 1)
                metadataCard
                copyButton
            }
            .padding(18)
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("Send Feedback")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        Text([
            "Write what you want to tell us — what's working, what isn't, what you'd change. Fuji Cookbook attaches nothing else: no logs, no camera report, no settings. Only the four lines below, so a reply knows which build you're on.",
            "If something went wrong, use Report a Problem instead — it carries the detail that makes a bug findable.",
            "Nothing is sent unless you send it.",
        ].joined(separator: "\n\n"))
            .font(.subheadline)
            .foregroundStyle(Theme.ink2)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .themedCard(cornerRadius: 16)
    }

    /// `TextEditor` has no placeholder API, so the prompt is an overlay that clears itself.
    private var noteEditor: some View {
        TextEditor(text: $note)
            .font(.subheadline)
            .foregroundStyle(Theme.ink)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 180)
            .padding(10)
            .overlay(alignment: .topLeading) {
                if note.isEmpty {
                    Text("What's working, what isn't, what you'd change.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink3)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
            }
            .themedCard(cornerRadius: 16)
            .accessibilityLabel("Your feedback")
    }

    /// The four lines, shown verbatim. "Attaches nothing else" is only a claim the reader can check
    /// if they can see the whole of what it does attach.
    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sent with your note")
                .font(.caption)
                .foregroundStyle(Theme.ink3)
            Text(metadataLines.joined(separator: "\n"))
                .font(.caption.monospaced())
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard(cornerRadius: 16)
    }

    private var copyButton: some View {
        CopyButton(title: "Copy Feedback Text", text: feedbackText)
            .buttonStyle(.outline)
            .disabled(isEmpty)
    }

    // MARK: The file

    private var metadataLines: [String] { AppIdentity.reportLines }

    private var feedbackText: String {
        (["Fuji Cookbook — feedback", ""] + metadataLines + ["", trimmedNote]).joined(separator: "\n")
    }
}
