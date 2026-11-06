import Foundation

/// The chapter editor's working copy: the name and slot order as plain values, written to the
/// `Chapter` only on Save.
struct ChapterDraft: Equatable {
    var name: String
    /// Ordered recipe identities. Position `i` maps to camera slot `C{i+1}`.
    var recipeUUIDs: [UUID]

    /// The name and slots as the editor opened them; ``hasChanges`` compares against these. A copy
    /// of the values, not the `Chapter`, so ``hasChanges`` counts only edits made in the form,
    /// whatever writes to the `Chapter` while the editor is open; and not a `ChapterDraft`, because
    /// a struct can't contain itself.
    private let opened: Opened

    init(from chapter: Chapter) {
        self.init(opening: Opened(name: chapter.name, recipeUUIDs: chapter.recipeUUIDs))
    }

    private init(opening opened: Opened) {
        self.opened = opened
        name = opened.name
        recipeUUIDs = opened.recipeUUIDs
    }

    /// What `init(from:)` reads from a chapter.
    private struct Opened: Equatable {
        let name: String
        let recipeUUIDs: [UUID]
    }

    /// Whether the name or the slots differ from how the editor opened. Undoing an edit by hand
    /// clears it, so the editor asks before discarding only when there is something to lose.
    var hasChanges: Bool { self != ChapterDraft(opening: opened) }
}
