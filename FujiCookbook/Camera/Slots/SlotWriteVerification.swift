import Foundation

/// Pure rules for judging a slot write: whether a read-back confirms what was written, what the
/// slot's headline outcome is, and how a property is named in the per-field table.
enum SlotWriteVerification {

    /// Whether a read-back satisfies verification for what was written. Byte equality for
    /// everything except D195 grain, whose read and write value sets differ (`FujiEncoding.flatToGrain`).
    /// There the two sides are compared by decoded meaning, or every Off-grain push reports a false
    /// mismatch.
    ///
    /// The guided test's power-cycle check asks the same question of the same bytes a day later,
    /// and a second comparison written to its own rules would disagree with the push about grain —
    /// reporting every Off-grain recipe as lost. So there is one.
    static func readBackMatches(_ code: UInt16, wrote: Data, read: Data?) -> Bool {
        guard wrote.count == 2, read?.count == 2 else { return false }
        if read == wrote { return true }
        if code == FujiPTP.PresetProp.grain.rawValue,
           let wroteGrain = FujiEncoding.decodeInt16(wrote).flatMap(FujiEncoding.flatToGrain),
           let readGrain = (read.flatMap(FujiEncoding.decodeInt16)).flatMap(FujiEncoding.flatToGrain) {
            return wroteGrain == readGrain
        }
        return false
    }

    /// Derive what the camera holds from what actually happened to each recipe field.
    ///
    /// Housekeeping properties are excluded by the caller: they're passed through rather than
    /// authored, and some bodies refuse them routinely, so letting one demote every push to
    /// "partially applied" would bury the signal this enum exists to carry.
    static func outcome(for recipeFields: [FieldResult], nameWritten: Bool,
                        nameOutcome: FieldOutcome? = nil) -> SlotOutcome {
        if nameOutcome == .outcomeUnknown || nameOutcome == .unverified
            || recipeFields.contains(where: { $0.outcome == .outcomeUnknown || $0.outcome == .unverified }) { return .unknown }
        guard !recipeFields.isEmpty else { return nameWritten ? .partiallyApplied : .notWritten }
        // Nothing reached the camera at all — the one case where "unchanged" is true. A written
        // name counts as reaching it: the bank's name changed, even if nothing else did.
        let touched = recipeFields.contains { $0.outcome != .notAttempted && !$0.isRejectedOutright }
        if !touched && !nameWritten { return .notWritten }
        let nameVerified = nameOutcome == nil || nameOutcome == .written
        return recipeFields.allSatisfy { $0.outcome == .written } && nameVerified ? .applied : .partiallyApplied
    }

    /// Whether a preset property maps to a user-facing recipe field (vs. a housekeeping property
    /// like image size/quality or Lens Modulation Optimizer that we pass through but don't surface).
    static func isRecipeField(_ code: UInt16) -> Bool {
        FujiPTP.PresetProp(rawValue: code)?.recipeField != nil
    }

    /// Unambiguous name for a preset property, for the per-field outcome table.
    ///
    /// `PresetProp.debugName` rather than `RecipeField.displayName`, which collapses D199/D19A/D19B/
    /// D19C onto "White Balance" and D193/D194 onto "Monochromatic Color" — fine for a clamp message
    /// about a recipe field, useless in a report meant to say which property a body refused.
    static func propertyName(for code: UInt16) -> String {
        FujiPTP.PresetProp(rawValue: code)?.debugName ?? String(format: "property 0x%04X", code)
    }
}
