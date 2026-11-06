import SwiftUI

/// The app's credits and its own license, rendered from the copy bundled inside the app.
///
/// This screen is where the app's attribution lives. Apache-2.0 §4 asks that the license and
/// NOTICE travel with every copy, and the copy that counts is the one on the user's phone, not a
/// file in the repository. The Fujifilm PTP reference, which the camera code and the photo reader
/// are built on, asks implementations to consider crediting it alongside the upstream sources it
/// relies on: this screen credits the reference, names the projects it builds on most directly,
/// and leaves the rest to the reference's SOURCES.md. The app uses facts from those projects, not
/// code, so no third-party license text is owed.
///
/// The text is `Resources/ThirdPartyNotices.md` from the bundle, so a new credit is an edit to that
/// file, not to Swift. `NoticeMarkdown` renders headings, paragraphs, fenced code and rules.
struct AcknowledgmentsView: View {
    private let blocks: [NoticeMarkdown.Block]

    init() {
        blocks = NoticeMarkdown.parse(NoticeMarkdown.bundledNotices())
    }

    var body: some View {
        Group {
            if blocks.isEmpty {
                // Reaching this means the resource didn't make it into the bundle — a packaging
                // failure, not a user error, and one that silently un-does the compliance this
                // screen exists for. Say so loudly rather than showing an empty page.
                ContentUnavailableView("Notices Unavailable",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text("The third-party notices couldn't be read from the app bundle. This is a packaging error — please report it."))
            } else {
                notices
            }
        }
        .navigationTitle("Acknowledgments")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var notices: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    view(for: block)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            // Legal text people may want to quote or search — selection costs nothing here.
            .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func view(for block: NoticeMarkdown.Block) -> some View {
        switch block {
        case .heading(let level, let text):
            // The file's one `#` heading is the screen's own title; rendering it again would just
            // repeat the navigation bar.
            if level > 1 {
                Text(NoticeMarkdown.inline(text))
                    .font(level == 2 ? .title3.weight(.semibold) : .headline)
                    .padding(.top, level == 2 ? 10 : 2)
            }

        case .paragraph(let text):
            Text(NoticeMarkdown.inline(text))
                .font(.subheadline)
                .foregroundStyle(.secondary)

        case .code(let text):
            // License blocks are reproduced verbatim, so this is monospaced and never reflowed —
            // the source file's own hard wraps are the line breaks you see. Long lines soft-wrap on
            // narrow devices rather than scrolling sideways inside a scroll view.
            Text(text)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))

        case .rule:
            Divider().padding(.vertical, 2)
        }
    }
}

/// Just enough markdown to render the notices file faithfully: headings, fenced license blocks,
/// horizontal rules, and paragraphs whose inline markup (`code`, **bold**, <autolinks>) SwiftUI's
/// own parser handles.
///
/// A general markdown renderer would be far more than this screen needs. What it does need is to
/// never drop text: an unterminated fence still emits its contents, and a paragraph that fails
/// inline parsing falls back to being shown as plain text.
enum NoticeMarkdown {
    enum Block {
        case heading(level: Int, text: String)
        case paragraph(String)
        case code(String)
        case rule
    }

    static let resourceName = "ThirdPartyNotices"

    /// The notices as shipped, or an empty string when the resource is missing or unreadable. Both are
    /// packaging errors, and `AcknowledgmentsView` shows them as one.
    static func bundledNotices() -> String {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }

    static func parse(_ source: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var code: [String] = []
        var inCode = false

        // Soft-wrapped source lines are joined back into one paragraph so the text re-wraps to the
        // device width instead of keeping the file's 100-column breaks.
        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph.removeAll()
        }

        for line in source.components(separatedBy: .newlines) {
            if line.hasPrefix("```") {
                if inCode {
                    blocks.append(.code(code.joined(separator: "\n")))
                    code.removeAll()
                } else {
                    flushParagraph()
                }
                inCode.toggle()
                continue
            }
            if inCode {
                code.append(line)
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushParagraph()
            } else if trimmed == "---" {
                flushParagraph()
                blocks.append(.rule)
            } else if trimmed.hasPrefix("#") {
                flushParagraph()
                let level = trimmed.prefix { $0 == "#" }.count
                let text = String(trimmed.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                blocks.append(.heading(level: level, text: text))
            } else {
                paragraph.append(trimmed)
            }
        }

        flushParagraph()
        // A fence the file never closed would otherwise swallow every license after it.
        if inCode, !code.isEmpty { blocks.append(.code(code.joined(separator: "\n"))) }
        return blocks
    }

    /// Inline-only parsing: block structure is already handled above, and `.full` would try to turn
    /// a heading or paragraph that opens with "1." into an ordered list.
    static func inline(_ markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible)
        return (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
    }
}

#Preview {
    NavigationStack { AcknowledgmentsView() }
}
