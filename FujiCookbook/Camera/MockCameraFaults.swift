import Foundation

/// Injectable failure modes for `MockCameraTransport`.
///
/// The write path's worst behavior only shows up when something goes wrong *partway* — a property
/// the body rejects, a cable pulled between the last write and the read-back, a slot that doesn't
/// exist, a product name that isn't in the registry. None of that is reachable from a working
/// X-T50, which is a verified body. Every field here exists to make one of them reproducible in
/// the Simulator and in tests.
///
/// Default-constructed this is a camera with no faults.
struct MockCameraFaults: Equatable {
    /// What the body calls itself, fed verbatim to `CameraModelRegistry.identify(productName:)`, so
    /// a test can connect as any registry body, or as one the registry does not recognize.
    var productName: String = "Demo Camera (no hardware)"

    /// What `GetDeviceInfo` reports as `deviceVersion` — the only route a firmware string takes on
    /// real hardware too. `nil` makes the body report an empty version, which the app shows as none.
    var firmwareVersion: String? = "1.00"

    /// Reject the Nth preset-property write (1-based) with `0x201C Invalid DeviceProp Value`.
    /// Slot-select and name writes are not counted, so this indexes a push's property writes,
    /// which is where a partial write happens.
    var rejectWriteAtIndex: Int?

    /// Property codes that answer `0x200A DeviceProp Not Supported` on read, the way a body that
    /// lacks a property does. The slot walk's `readPresetProps` and a push's
    /// `readAllPresetProperties` record one and carry on; the push plans no write for it.
    var unsupportedReadCodes: Set<UInt16> = []

    /// Exact PTP responses on value reads. In particular, the verified X-T50 refuses a
    /// diagnostic D183 read with 0x2002 even though writing that conversion trigger works.
    var readResponseCodes: [UInt16: UInt16] = [:]

    /// Property codes that answer `0x200A Device Prop Not Supported` on write.
    var unsupportedWriteCodes: Set<UInt16> = []
    /// Properties the camera refuses with `0x201C Invalid DeviceProp Value` — what a real X-T50
    /// says to `D18E` on a bank with SPORTS FINDER MODE on. Distinct from `unsupportedWriteCodes`
    /// (`0x200A`), which means the property doesn't exist on the body.
    var invalidValueWriteCodes: Set<UInt16> = []
    /// Exact PTP responses on value writes, for a refusal neither set above names. `0x2019 Device
    /// Busy` is the one it exists for: the record describes a body left answering it to everything
    /// by a conversion that never completed (zgrimz/fujifilm-ptp-reference `docs/01-transport.md`),
    /// and an X-M5 (fw 1.20, 2026-10-26) answered it to two develops in a session whose connect had
    /// a C1 select refused.
    var writeResponseCodes: [UInt16: UInt16] = [:]

    /// Property codes whose writes are answered **`0x2001 OK` and then discarded**.
    ///
    /// The behaviour this project's own notes describe — "a Fuji body answers OK to
    /// `SetDevicePropValue` and then keeps its old value when the value isn't in the property's
    /// enumerated set". It matters most for `0xD18C`: a select that is silently ignored sends the
    /// whole push to a slot the user didn't choose, and every read-back then agrees with itself.
    var silentlyIgnoredWriteCodes: Set<UInt16> = []
    /// Answer a `0xD18D` write whose data phase is one byte `0x2001 OK`, and keep the name.
    ///
    /// An X-T50 (fw 1.32) through ImageCaptureCore on iOS 27.0.1, 2026-10-19: a restore wrote the
    /// one-byte empty name `00`, then 20 bank settings, every write answered OK, and the bank still
    /// answered its old name. Over direct USB the same body takes `00` and `01 00 00` alike, and
    /// setting writes after either leave the name empty (zgrimz/fujifilm-ptp-reference
    /// `docs/03-encodings.md`). Which side drops the one byte isn't observed.
    var ignoresOneByteNameWrites: Bool = false
    /// Mutate the property, then lose its response. Tests distinguish an uncertain send from refusal.
    var lostWriteResponseCodes: Set<UInt16> = []
    var lostUploadResponse = false
    var lostDeleteResponse = false
    /// A Kelvin write resets both white balance shifts to zero, as Kelvin can on an X-S10 (see the
    /// restore order in `FujiPresetCodec`). Off by default: no other body is known to do it.
    var kelvinResetsShifts: Bool = false

    /// Conversion faults retain the camera's original object while altering transfer metadata/data.
    var conversionObjectFormat: UInt16 = 0x3801
    var conversionDownloadOverride: Data?
    var extraObjectsOnConversion: [Data] = []
    var deleteObjectResponse: UInt16?

    /// Pull the cable after this many preset-property writes. The writes that already landed stay
    /// landed, and every later operation — crucially the read-back — throws
    /// `disconnectedDuringOperation`, so the slot's outcome is `.unknown`: changed, but unconfirmed.
    var dropSessionAfterWrites: Int?

    /// Highest slot this body will select; a select past it answers `0x200A DeviceProp Not
    /// Supported`, as a GFX100S does for `0xD18C = 7` (fw 2.13, 2026-09-15) and an X-M5 for C5
    /// (fw 1.30, 2026-10-31). Gives a test a body with fewer banks than the registry's `slotCount`.
    var maxSelectableSlot: Int?

    /// Answer `GetDeviceInfo` with `0x2005 Operation Not Supported`, the way a body that refuses
    /// it would. The report must still be produced — with the refusal recorded — and the connect
    /// must still succeed, since it goes ahead without DeviceInfo.
    var refusesDeviceInfo: Bool = false

    /// Property codes answered **`0x2001 OK` with no data phase** — the read succeeds and yields
    /// no bytes.
    ///
    /// Distinct from `unsupportedReadCodes` (`0x200A`, which throws) in the one way that matters:
    /// `readProperty` returns nil *without* throwing, so the property goes missing from the read
    /// and nothing anywhere reports a failure — the silence `FujiPresetCodec.Slot` exists to
    /// handle. Nothing else here can produce a nil-without-throw.
    var emptyReadCodes: Set<UInt16> = []

    /// Raw bytes to answer for a property code, whatever the slot actually holds.
    ///
    /// The seam for a body whose *encodings* diverge from `FujiEncoding` — an unlisted white
    /// balance mode, a film simulation byte the app has never seen, a tone stored ×100 instead of
    /// ×10. Everything the mock stores came out of the app's own `FujiPresetCodec.encode`, so
    /// without this (or a one-shot `MockCameraTransport.queueRead`) the mock only returns values
    /// the decoder already understands, and its divergence handling is unfalsifiable.
    var rawReadValues: [UInt16: Data] = [:]

    /// Forget every slot write when the session is next opened.
    ///
    /// The failure the guided write pass's power-cycle step exists for: a push that is answered OK,
    /// reads back correctly, and is quietly gone once the camera has been switched off and on.
    /// Nothing during the push can see it — the read-back happens while the value is still there —
    /// so it is invisible to every other fault here.
    var revertsWritesOnReopen: Bool = false

    /// Start with **every** slot unprogrammed, the way a camera belongs to someone who has never
    /// made a recipe on it.
    ///
    /// The demo camera ships with C1 and C2 filled, so every path that asks "is there a slot worth
    /// reading?" is otherwise answered yes here — the read pass's comparison step, the slot both
    /// probes pick, the undo the write pass offers at the end. An empty body answers no to all
    /// three.
    var startsWithEmptySlots: Bool = false

    /// Refuse the RAF upload with this response code. A RAF the body didn't shoot is refused later,
    /// at the `0xD185` read after the upload (zgrimz/fujifilm-ptp-reference
    /// `docs/05-raw-conversion.md#prerequisites`); model that with `readResponseCodes`.
    var rejectsUpload: UInt16?

    /// Answer `0x2002` to a read of `0xD185` until a RAF has been uploaded — what the GFX100S
    /// showed twice, and the reason a property sweep can never settle the Kitchen question. Off
    /// by default, so a cook test has a profile from the start.
    var profileNeedsUpload: Bool = false

    /// Make the upload appear in `GetObjectHandles`, so the harvest's "did the upload create a
    /// visible object, and can it be deleted?" branch has something to find.
    var uploadCreatesObject: Bool = false

    /// Skip the mock's simulated USB latency. Tests shouldn't pay 250ms to open a session.
    var isInstant: Bool = false

    /// Connect as a body on the cable rather than as the Demo Camera: `ConnectedCamera.isDemo` is
    /// false and the report says "usb", so the connect does what it does with real hardware —
    /// remembering the body for the Chapter screen included. For tests of exactly that; the app's
    /// demos never set it.
    var presentsAsHardware: Bool = false
}

extension MockCameraFaults {
    /// A recognized body the app reads and writes but does not develop on, whose `0xD185` refuses
    /// until a RAF has been sent. The one demo body on which the Camera Test's develop step offers
    /// the profile harvest — and so the only way to see that step without owning a camera the
    /// Kitchen is off for.
    ///
    /// The GFX100: in the GFX100S's registry group, writable on that body's report, with the
    /// Kitchen off because the only profile blob read is the GFX100S's. Its name resolves as an
    /// *alias* rather than an exact match ("FUJIFILM GFX 100" normalizes to "GFX 100" against the
    /// id "GFX100", which the derived-spaceless branch catches) — and an alias is trusted, which is
    /// all the harvest gate asks for. No firmware: no GFX100 has ever reported one here, and a
    /// made-up version number in a fixture reads like evidence.
    static let gfx100WithoutKitchen = MockCameraFaults(
        productName: "FUJIFILM GFX 100", firmwareVersion: nil, profileNeedsUpload: true)
}
