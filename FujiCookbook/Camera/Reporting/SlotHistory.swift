import Foundation

/// What the push history in a compatibility report says each slot held before its last push: the
/// source of the free per-slot undo, with no file involved.
///
/// Clear Diagnostics reduces every push record to its drift baseline (`stripToDriftBaseline()`),
/// which drops the bytes and name this reads, so after a clear there is no undo. An exported
/// `CameraBackup` is the durable copy.
struct SlotHistory {
    let report: CameraCompatibilityReport?

    /// The name the last push to this slot replaced: the same push `lastPushPriorBytes` reads, but
    /// answered even when there are no bytes to put back.
    ///
    /// Without it an undo puts the settings back under the name the push left, so the slot holds
    /// its old settings while still calling itself "CT Colour", which reads as a failed restore.
    /// "" is a real answer: the slot had no name, and the undo writes the empty name back. Nil
    /// means there is no push, or the name wasn't read before it.
    func lastPushPriorName(forSlot slot: Int) -> String? {
        lastPush(forSlot: slot)?.nameBefore
    }

    /// What an undo writes as the slot's name: the name the push replaced, "" included. An
    /// unnamed bank shows as CUSTOM *n* in the camera's menu (zgrimz/fujifilm-ptp-reference
    /// `docs/03-encodings.md#0xd18d-bank-name`). Not the slot's current name, which after a push is
    /// the name the push wrote (falling back to that leaves a bank of factory defaults called
    /// "CT Mono"), and not `CameraSlotName.fallbackName`, which is "Recipe" and would claim there
    /// is one. Only a name that was never read falls back to "C*n*".
    func undoName(forSlot slot: Int) -> String {
        lastPushPriorName(forSlot: slot) ?? "C\(slot)"
    }

    /// What a slot held immediately before the last push to it, by property code. Nil when there is
    /// nothing to put back: no push, a push recorded as into an empty slot, or one that failed
    /// before it read the slot.
    func lastPushPriorBytes(forSlot slot: Int) -> [UInt16: Data]? {
        // Only records from earlier builds say `slotWasEmpty`; current pushes never set it true.
        // Absent bytes mean the push never read the slot, not that the slot was empty.
        guard let push = lastPush(forSlot: slot), push.slotWasEmpty != true,
              let before = push.slotBefore, !before.isEmpty else { return nil }
        let out = PTPHex.propertyBytes(before)
        return out.isEmpty ? nil : out
    }

    /// The most recent real push to this slot — not a restore, not a Clear-Diagnostics baseline.
    private func lastPush(forSlot slot: Int) -> CameraCompatibilityReport.PushRecord? {
        report?.pushes?.last {
            $0.slot == slot && $0.baselineOnly != true && $0.kind == nil
        }
    }
}
