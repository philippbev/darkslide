import Foundation
@testable import FujiCookbook

/// The fault profiles the tests drive the Demo Camera with. `gfx100WithoutKitchen` stays in the
/// app, which offers it as a second demo.
///
/// Camera facts in these tests are from zgrimz/fujifilm-ptp-reference:
/// `docs/03-encodings.md#0xd199-white-balance-mode`.
extension MockCameraFaults {
    /// A body that identifies as the X-T30 III — real, shipping, and named one letter past the
    /// X-T30 II.
    static let xT30III = MockCameraFaults(productName: "FUJIFILM X-T30 III", firmwareVersion: nil)

    /// The X-M5: writable on its owner's report (fw 1.30, 2026-10-31), and the one whose mode dial
    /// has four C positions where the registry's walk assumes seven. Four selectable banks, so the
    /// connect walk lands exactly on `documentedSlotCount` and files the refusal at C5 as the
    /// manual confirmed rather than as a finding.
    static let xM5 = MockCameraFaults(productName: "FUJIFILM X-M5", firmwareVersion: nil,
                                      maxSelectableSlot: 4)

    /// A body stuck answering `0x2019 Device Busy`. An X-M5 (fw 1.20) failed two develops with
    /// `0x2019` (zgrimz/fujifilm-ptp-reference `docs/07-cameras.md#x-m5`), but which command answered
    /// isn't recorded; this fixture models the answer on every slot select and on the RAF upload,
    /// so the connect walk stops at C1, a push at its select and a develop at its upload.
    static let busyXM5 = MockCameraFaults(productName: "FUJIFILM X-M5", firmwareVersion: "1.20",
                                          writeResponseCodes: [FujiPTP.Prop.slotSelector: FujiPTP.responseDeviceBusy],
                                          rejectsUpload: FujiPTP.responseDeviceBusy)

    /// A body whose product name matches nothing in the registry, and whose `GetDeviceInfo` carries
    /// no firmware version, so nothing names it: `ModelIdentification.unknown`, the read-only sweep,
    /// and no write.
    static let unknownBody = MockCameraFaults(productName: "FUJIFILM X-T99", firmwareVersion: nil)

    /// A body whose product name matches nothing in the registry and that names itself over
    /// `GetDeviceInfo` with product name, serial and firmware: `ModelIdentification.unlisted`, walked
    /// on a provisional model and granted or refused by what it answers.
    static let unlistedBody = MockCameraFaults(productName: "FUJIFILM X-T99", firmwareVersion: "1.00")

    /// A **recognized** body with no record of its bank path either way (`.untested`): its slots
    /// answer, so the walk grants it, unverified, and its first push is staged. A different state
    /// from a recorded failure (`noSlotProtocolBody`) and from nothing naming the body
    /// (`unknownBody`). Each needs its own fixture.
    ///
    /// The unreported GFX bodies are what sits at that level. Named rather than spelled inline so
    /// the next promotion moves one line instead of five call sites; the name is older than the
    /// state it now stands for.
    static let readOnlyWithSlots = MockCameraFaults(productName: "FUJIFILM GFX100 II", firmwareVersion: nil)

    /// A **recognized** body with no USB slot protocol: `0xD18C`/`0xD18D` answer `0x200A` on read
    /// and are absent from `GetDeviceInfo`, as in an X-T20 owner's log (zgrimz/fujifilm-ptp-reference
    /// `docs/07-cameras.md#x-t20`, `evidence/xt20-undated-172851`). That log holds no writes; the
    /// write refusal is modelled, not observed.
    ///
    /// `unsupportedWriteCodes` is belt and braces rather than the point: the app must never send a
    /// `0xD18C` write to this body at all. If it regresses and does, the refusal here throws and the
    /// session lands on `.failed`, which is the assertion that catches it.
    static let noSlotProtocolBody = MockCameraFaults(
        productName: "FUJIFILM X-T20", firmwareVersion: "2.01",
        unsupportedReadCodes: [FujiPTP.Prop.slotSelector, FujiPTP.Prop.presetName],
        unsupportedWriteCodes: [FujiPTP.Prop.slotSelector])

    /// The X100V of the record's capture: on every bank, 19 of the 23 properties read and `0xD18E`,
    /// `0xD18F`, `0xD1A3` and `0xD1A4` answer `0x200A` to a read and to X RAW Studio's write
    /// (zgrimz/fujifilm-ptp-reference `docs/01-transport.md#response-codes`; firmware and USB mode
    /// unknown there). The write refusal is belt and braces: the app plans no write for a property
    /// the body lacks, and if it regresses and does, the row reads `rejected (0x200A)`.
    static let x100V = MockCameraFaults(
        productName: "FUJIFILM X100V", firmwareVersion: nil,
        unsupportedReadCodes: x100VAbsentProperties, unsupportedWriteCodes: x100VAbsentProperties)

    /// The four bank properties the record's X100V lacks.
    static let x100VAbsentProperties: Set<UInt16> = [
        FujiPTP.PresetProp.imageSize.rawValue, FujiPTP.PresetProp.imageQuality.rawValue,
        FujiPTP.PresetProp.lensModulationOptimizer.rawValue, FujiPTP.PresetProp.colorSpace.rawValue,
    ]

    /// The cable comes out after four properties have been written and before the read-back.
    static let dropMidPush = MockCameraFaults(dropSessionAfterWrites: 4)

    /// A body with five custom slots rather than the assumed seven.
    static let fiveSlots = MockCameraFaults(maxSelectableSlot: 5)

    /// A camera nobody has ever programmed: seven slots, all empty. The read pass has nothing to
    /// compare, and the write pass's undo has nothing to put back — no clearing operation is
    /// characterized (zgrimz/fujifilm-ptp-reference `docs/04-custom-slots.md#how-many-banks`), so
    /// programming a slot is the one thing the Camera Test can do and not take back.
    static let emptyCamera = MockCameraFaults(startsWithEmptySlots: true)

    /// A body that takes a push, verifies it, and has forgotten it by the next time it is switched
    /// on. The guided write pass's power-cycle step is the only thing that catches this.
    static let forgetsWritesOnPowerCycle = MockCameraFaults(revertsWritesOnReopen: true)

    /// A body reporting a white balance mode outside `FujiEncoding.valueToWBMode` — the case that
    /// must surface as a missing value rather than a confidently wrong "Auto". Not `0x8009`: that is
    /// Custom 2, which the app knows (`FujiEncoding.customWhiteBalanceLabel`).
    static let divergentWhiteBalance = MockCameraFaults(
        rawReadValues: [FujiPTP.PresetProp.whiteBalance.rawValue: FujiEncoding.packU16(0x8099)])

    /// A body that answers OK to a slot select and stays where it was. Every subsequent read and
    /// write in a push then addresses the wrong slot *consistently*, so the read-back verifies and
    /// the app reports success for a slot it never touched.
    static let selectorIgnoresWrites = MockCameraFaults(
        silentlyIgnoredWriteCodes: [FujiPTP.Prop.slotSelector])

    /// A body that answers OK, with nothing, when asked for a slot's film simulation. The slot is
    /// occupied and holds a real one; the read just doesn't say so.
    static let silentFilmSimulationRead = MockCameraFaults(
        emptyReadCodes: [FujiPTP.PresetProp.filmSimulation.rawValue])
}
