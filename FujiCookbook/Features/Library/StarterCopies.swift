import Foundation

/// Which copies of a starter recipe, or of the starter roll, a library keeps when it holds more than
/// one. Two devices that each seeded a new library hold two copies with the same `StarterLibrary`
/// uuid once iCloud sync meets them.
///
/// The rules read only what sync carries to every device — creation dates and whether a copy was
/// edited — so two devices deciding at the same time delete the same copies rather than one each.
/// Two installs in the same instant would tie; that doesn't happen.
///
/// An edited copy is never deleted. Edited copies past the first keep their contents and get new
/// identities: they are the user's own now, and two recipes (or rolls) must not share a uuid.
enum StarterCopies {
    struct Copy<ID: Hashable> {
        let id: ID
        let createdAt: Date
        /// Whether the user has changed this copy since it was added.
        let isEdited: Bool
    }

    struct Resolution<ID: Hashable>: Equatable {
        /// Untouched copies that another copy makes redundant.
        var delete: [ID] = []
        /// Edited copies that need an identity of their own.
        var rekey: [ID] = []

        var isEmpty: Bool { delete.isEmpty && rekey.isEmpty }
    }

    /// With at least one edited copy, every untouched copy goes and every edited copy but the oldest
    /// is re-keyed. With none edited, the oldest copy stays and the rest go.
    static func resolve<ID: Hashable>(_ copies: [Copy<ID>]) -> Resolution<ID> {
        guard copies.count > 1 else { return Resolution() }
        let oldestFirst = copies.sorted { $0.createdAt < $1.createdAt }
        let edited = oldestFirst.filter(\.isEdited)
        let untouched = oldestFirst.filter { !$0.isEdited }
        guard !edited.isEmpty else { return Resolution(delete: untouched.dropFirst().map(\.id)) }
        return Resolution(delete: untouched.map(\.id), rekey: edited.dropFirst().map(\.id))
    }
}
