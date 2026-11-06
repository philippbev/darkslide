import Foundation
import CryptoKit

/// The **Camera Compatibility Report**: everything one connect attempt learned about a body, in one
/// versioned, self-contained JSON document.
///
/// It gives a tester with a body nobody here owns an artifact that *diffs* against another
/// tester's, rather than prose. Every capture stage — `GetDeviceInfo`, the slot reads, the property
/// sweep, the bounded PTP trace — writes into it, and the human-readable text (`textRendering`) is a
/// rendering of the same data, never a separate account. `reportVersion` is here from the first
/// build so a v1 report is still readable when the shape changes.
///
/// What it contains, deliberately: the tester's C1–C7 slot bytes (their recipes), the camera serial
/// *hashed under a key that never leaves the phone* (`SerialHash`), the iOS version and device
/// identifier. It is written to disk in the App Group container
/// and shared only by the user's own action — the consent posture of `DiagnosticsReportView`.
/// Format notes: `docs/camera-compatibility-report.md`.
struct CameraCompatibilityReport: Codable, Equatable {
    /// Version 7 adds the write decision and what it rests on: `camera.writeAccess`, the selector
    /// read, the walk result, registry disagreements and the staged first write. Version 6 added
    /// continuous test plans, recovery references, explicit verification states, conversion
    /// run/result linkage, share outcomes and per-phase/connection provenance. New fields remain
    /// optional so reports from earlier builds continue decoding without inventing evidence they
    /// did not collect.
    static let currentVersion = 7

    var reportVersion: Int = CameraCompatibilityReport.currentVersion
    var generatedAt: Date
    var updatedAt: Date
    var app: AppInfo
    var host: HostInfo
    var camera: CameraIdentity
    var deviceInfo: DeviceInfoRecord?
    var slots = SlotSummary()
    var propertySweep: PropertySweep?
    /// Property codes that answered `0x200A DeviceProp Not Supported` anywhere in the session.
    var unsupportedPropertyCodes: [String] = []
    var transactions: [PTPTransaction] = []
    var transactionsDropped: Int = 0
    /// The trace covers recorded operations on one connection, not every reconnect in a test.
    var traceStartedAt: Date?
    var traceScope: String?
    var connectionID: String?
    /// Free-form observations the capture code wants a reader to see ("GetDevicePropDesc refused
    /// wholesale", "slot select failed at C6"). Facts, not diagnoses.
    var notes: [String] = []

    /// What each push attempt did — the single most consequential event in the session, so it
    /// belongs in the diffable artifact rather than only in the log.
    ///
    /// **Optional, not defaulted, and so is every field added to this type from here on.** Swift's
    /// synthesized `Decodable` ignores a property's default value for a missing key and throws
    /// `keyNotFound`; `CameraReportStore.loadLatest()` reads files written by the *previous* build
    /// on connect and on the diagnostics screen. A non-optional `[PushRecord] = []` would make a
    /// tester's stored report vanish the moment they updated the app.
    var pushes: [PushRecord]?
    var pushesDropped: Int?

    /// What each in-camera develop did. *v3.*
    ///
    /// Structured, like `deviceInfo` and `slots` for the connect and `pushes[]` for a write, rather
    /// than prose in the on-device log: RAW conversion is enabled on more bodies than it has been
    /// driven on, so the Kitchen is the workflow with the *least* evidence and the most inference
    /// behind it.
    ///
    /// Optional, like every field added from v2 on. See `pushes`.
    var develops: [DevelopRecord]?
    var developsDropped: Int?

    /// Every profile harvest: an upload of one RAF, a read of `0xD185`, and nothing after. *v5.*
    ///
    /// The one piece of evidence that decides whether a body converts is a profile blob that
    /// `FujiRawConvProfile.resolveLayout` resolves or refuses — and `0xD185` only holds one after
    /// the host has uploaded a RAF. Every other path that uploads sits behind the
    /// `supportsRawConversion` gate the question is about, so without the harvest a body with
    /// conversion off could never produce this. Two GFX100S reports carry a `0x2002` from a plain
    /// sweep that settles nothing (2026-09-15).
    ///
    /// Optional, like every field added from v2 on. See `pushes`.
    var profileHarvests: [ProfileHarvestRecord]?
    var profileHarvestsDropped: Int?

    /// What each guided Camera Test observed. *v4.*
    ///
    /// Everything else in this document is what the *camera* said. This is the half only a person
    /// can supply: whether the app named the right body, whether a slot the app displayed matches
    /// what the camera's own IQ menu shows, whether a pushed recipe survived a power cycle, whether
    /// the photo looks like the recipe. Read-back verification proves bytes round-tripped; it cannot
    /// prove they *mean* what `FujiPresetCodec` says they mean, and the only instrument for that — a
    /// tester reading their camera's menu — needs somewhere to land other than free text.
    ///
    /// Keyed by `sessionID` and upserted: a test is projected here repeatedly as it progresses, so a
    /// session abandoned midway still leaves what it had. Optional, like every field added from v2
    /// on, **and so must be every field a later build adds to any type nested under it** — this
    /// array is what a future build would add a field to.
    var guidedTests: [GuidedTestRecord]?

    /// Connect attempts that ended without a usable session. *v3.*
    ///
    /// The rest of this document is created inside `connect` **once the session opens**, which
    /// means the single most common failure on a new body — the camera never appears at all — would
    /// otherwise produce no report to send, or point the user at one that is nearly empty. A
    /// failure is appended to whatever report already exists rather than replacing it, so a body
    /// that worked yesterday and fails today reports both facts.
    var connectionFailures: [ConnectionFailure]?

    /// Enough to see a pattern without turning the document into a log.
    static let maxConnectionFailures = 10

    /// A batch of seven, retried, and then some.
    static let maxPushRecords = 20

    /// A Test Kitchen grid is up to nine, and a tester will run more than one.
    static let maxDevelopRecords = 20
    /// Same cap as develops. A harvest is one exchange, and a tester runs it once per RAF.
    static let maxProfileHarvestRecords = 20

    /// A read pass and a write pass per body, plus room to restart. More than this and the tester
    /// is repeating themselves, which the newest records already say.
    static let maxGuidedTestRecords = 5

    struct PushRecord: Codable, Equatable {
        /// When the push *started*, not when it was recorded — a push ends by re-reading every
        /// slot, so stamping it afterwards would put it later than `slots.readAt` and make the slot
        /// section look like it predated a push it actually followed.
        var at: Date
        var slot: Int
        var modelID: String?
        /// Carried here as well as in `camera` because a push is dated: a body reporting a rejection
        /// on firmware 1.10 and not on 1.32 is the finding, and the two reports must be comparable.
        var firmwareVersion: String?
        var outcome: SlotOutcome
        var nameWritten: Bool
        var nameApplied: String?
        var nameOutcome: String?
        /// The slot's name *before* this push, so Undo Last Push can put it back. `slotBefore`
        /// carries D18E-D1A4 and stops there — `PresetProp` has no case for D18D — so without this
        /// an undo would restore every setting under whatever name the push left behind.
        var nameBefore: String?
        /// The write path's verdict on whether the slot held **no recipe** before the push: `false`
        /// when the push read the slot's film simulation, nil when it did not. The property path
        /// can't tell an empty slot from an occupied one, so the current build never records
        /// `true`; a `true` in a record from an earlier build still withholds Undo Last Push
        /// (`SlotHistory.lastPushPriorBytes`), which consults this rather than re-deriving
        /// emptiness from `slotBefore`.
        var slotWasEmpty: Bool?
        var clampedFields: [String] = []
        var errorMessage: String?
        var fields: [FieldRecord] = []
        /// Every property the destination slot held **before** this push, property code to hex.
        ///
        /// `push` already reads exactly this — it needs the slot's current bytes to build a patch
        /// that preserves fields the app doesn't edit — so recording it costs one dictionary and
        /// makes the one slot a push can damage recoverable from the report the tester sends.
        /// Recorded before the first content write (`beginPush`), so a push cut off part-way keeps
        /// it. Absent when the push failed before it got that far (slot select refused, or the read
        /// itself threw), which is also the case where nothing was written.
        var slotBefore: [String: String]?
        /// True on a record Clear Diagnostics reduced to its drift baseline: `slot`, `at`, `outcome`
        /// and the one `D192` field. Everything a later connect needs to notice the slot changed,
        /// and nothing a user would want erased. Optional, like every v2 field.
        var baselineOnly: Bool?
        /// What `0xD18C` reported *after* the push selected it. Equal to `slot` on a healthy push.
        ///
        /// A body that answers OK and stays put would otherwise produce a fully self-consistent,
        /// fully wrong-slot push reported as applied; the report carries the proof rather than the
        /// assertion.
        var selectorReadBack: Int?
        /// *v3.* `restore` when this write put a slot back from a saved copy, absent for an ordinary
        /// push. Two writes to one slot otherwise look alike in the record, and telling the accident
        /// from the repair is the first thing a reader needs.
        var kind: String?
        /// *v7.* How the staged first write ended, when this push staged one (`StagedWrite`): the
        /// first evidence a body gives about its bank path, kept apart from the rest of the push.
        var firstWrite: FirstWriteRecord?
    }

    /// *v7.* The staged first write of a push to a body no push had been read back on.
    struct FirstWriteRecord: Codable, Equatable {
        /// The property staged, as hex.
        var property: String
        /// `written`, `invalid-value`, `refused`, `mismatched` or `unknown` (`FirstWriteOutcome`).
        var outcome: String
        /// The camera's response on a refusal.
        var responseCode: String?
        /// What the read-back answered on a mismatch, as hex.
        var read: String?
        /// How the property was put back after a stop: `unchanged`, `restored`, `restore-refused
        /// <code>`, `restore-mismatch` or `restore-unknown`. Absent when the push went on.
        var restore: String?
    }

    /// One develop, as much of it as can be said without naming the user's photo. *v3.*
    ///
    /// Deliberately narrower than `ConversionResult`, which carries `sourceFilename`, an
    /// `errorMessage` that interpolates it, and a byte-level `diagnostics` dump. None of those can
    /// enter this document: it has no field for a photo or a file name and must not grow one. What
    /// is here is the body's own behaviour — the profile it produced, whether the app could read it,
    /// whether it took the patch back, and how Dynamic Range resolved.
    struct DevelopRecord: Codable, Equatable {
        var resultID: UUID?
        var runID: UUID?
        var caseID: String?
        var recipeID: String?
        var recipeSettings: RecipeSettings?
        var at: Date
        var modelID: String?
        /// As on `PushRecord`, and for the same reason: conversion behaviour is a per-firmware fact.
        var firmwareVersion: String?
        var succeeded: Bool
        /// The recipe's film simulation. A recipe *name* is the user's; the simulation is one of a
        /// closed set of Fujifilm's own, and it is what a "this doesn't look right" report turns on.
        var filmSimulation: String?
        /// A length the record hasn't seen (zgrimz/fujifilm-ptp-reference
        /// `docs/06-conversion-profile.md#lengths-seen`) is a finding by itself.
        var profileLength: Int?
        var declaredParams: Int?
        /// Nil when `resolveLayout` refused the blob — the abort that stops an unfamiliar body
        /// before a byte is written, and the single most actionable thing a new body can report here.
        var layoutBase: Int?
        /// Whether the camera read the patched profile back as written. `false` means the JPEG may
        /// not reflect the recipe at all, which is indistinguishable from a recipe that looks bad.
        var profileVerified: Bool?
        var profileVerification: String?
        var outputValidation: String?
        var cleanupOutcome: String?
        var mismatches: [String]?
        /// `applied` / `untouched` / `cappedToAsShot(400->200)` / `autoResolved(200, asShot 400)`.
        var dynamicRange: String?
        var fullResolution: Bool?
        var clampedFields: [String]?
        /// Size of the produced JPEG — how you tell "developed nothing" from "developed the wrong
        /// thing". Not the image, and nothing derived from its content.
        var outputBytes: Int?
        /// The coarse label, never the user-facing message: `raf_from_different_body`,
        /// `conversion_profile_mismatch`, `raw_conversion_unsupported`, or a `diagnosticReason`.
        var failureReason: String?
    }

    /// One profile harvest. *v5.* The first half of a develop, recorded step by step so a refusal
    /// says *where* it happened — the upload, or the read after it — which are two different
    /// findings about a body.
    struct ProfileHarvestRecord: Codable, Equatable {
        var at: Date
        var modelID: String?
        var firmwareVersion: String?
        /// Size only. No filename — the report has no field for one, on purpose.
        var rafBytes: Int
        /// What `0xD185` answered before anything was sent: a response code, or a length if it
        /// already held something. The before half of the contrast the record exists to show.
        var profileBeforeUpload: String?
        /// `accepted`, or the response the camera gave. `0x2002 General Error` is usually a RAF it
        /// didn't shoot; `rafHeader` says whether the file's own header agrees. Compared whole
        /// (`== "accepted"`) by the runner and the summary, so nothing is ever appended to it.
        var uploadOutcome: String
        /// What the RAF's own header says about the file, from `RAFHeader`: `names this body`, or
        /// `names X-T5, not this GFX100`. Absent when the file has no readable header. Beside
        /// `uploadOutcome` rather than inside it, so the camera's answer stays comparable.
        var rafHeader: String?
        /// Whether the upload showed up in `GetObjectHandles`. Nil when the handles couldn't be read
        /// on both sides of it. The RAF goes into a conversion buffer under a fixed name; whether
        /// that buffer is a visible card object is what this measures.
        var uploadCreatedObject: Bool?
        /// When it did appear: whether `DeleteObject` took it back. Best effort, recorded either way.
        var objectDeleted: Bool?
        var profileLength: Int?
        var declaredParams: Int?
        /// Nil when `resolveLayout` refused the blob — on a new body, the whole finding.
        var layoutBase: Int?
        var layoutDiagnostic: String?
        /// The first 64 bytes, hex. Camera settings, not a photograph, and the only way to reason
        /// about a layout that didn't resolve from a report alone.
        var profileHead: String?
        /// The response when `0xD185` refused *after* a good upload — the finding that says the
        /// property is not there, and the `0xD183` descriptor was a red herring.
        var profileReadError: String?
        /// What `0xD185` answered after the uploaded object was deleted, when there was one.
        var profileAfterDelete: String?
        /// `raf_from_different_body`, `conversion_profile_mismatch`, `profile_empty`, or a
        /// `diagnosticReason`.
        var failureReason: String?
    }

    /// One connect attempt that ended without a usable session. *v3.*
    struct ConnectionFailure: Codable, Equatable {
        var at: Date
        /// `discovery` — no device was ever enumerated (cable, USB mode, or a permission).
        /// `open` — a device was found and the PTP session wouldn't open.
        /// `usb-mode` — the session opened, and `GetDeviceInfo` showed a storage USB mode.
        var stage: String
        /// A `CameraError`'s own description, or the error passed through `AppLog.bounded`, so no
        /// file path or URL can ride in on it.
        var reason: String
        /// Known at the `open` and `usb-mode` stages; at `discovery` there is no device to name.
        var productName: String?
        var usbVendorID: String?
        var usbProductID: String?
        var identification: String?
        /// The two ImageCaptureCore grants at the moment of failure, as words. This is the field
        /// that separates "wrong cable or wrong USB mode" from "the permission never took" — the
        /// distinction a tester cannot make for themselves and the app could never report.
        var controlAuthorization: String?
        var contentsAuthorization: String?
    }

    struct FieldRecord: Codable, Equatable {
        /// Absent for a field rejected pre-flight, which never had a property code.
        var code: String?
        var name: String
        var isRecipeField: Bool
        /// `written` / `rejected` / `notAttempted` / `mismatched` / `unverified` / `outcome_unknown`.
        var outcome: String
        /// The camera's own response, when it gave one — the most useful fact about a new body.
        var responseCode: String?
        /// Hex, for every field the push wrote a value to.
        var wrote: String?
        /// Hex, for `mismatched` only: what the camera read back instead.
        var read: String?
    }

    // MARK: Guided test (v4)

    /// One run of the in-app Camera Test.
    ///
    /// A field added to this type or any type below in a later build must be `Optional`, or a
    /// stored report written by the build before it stops decoding. See the note on `pushes`.
    struct GuidedTestRecord: Codable, Equatable {
        var sessionID: String
        var plan: GuidedTestSession.TestPlan?
        var recoveryBaselineID: String?
        var selectedWriteSlot: Int?
        var stillBankConfirmations: [GuidedTestSession.StillBankConfirmation]?
        var kitchenRuns: [GuidedKitchenRun]?
        var kitchenCompletions: [GuidedKitchenCompletion]?
        var kitchenObservations: [String: GuidedTestSession.Answer]?
        var shareEvents: [GuidedTestSession.ShareEvent]?
        /// 1 = the read pass, 2 = the write pass.
        var wave: Int
        var startedAt: Date
        var updatedAt: Date?
        /// `usb` or `demo`. A demo run exercises the format and is never evidence about a body.
        var transport: String?
        /// `inProgress` / `completed` / `sentEarly` / `abandoned`.
        var outcome: String?
        /// Where it stopped, for anything but `completed`.
        var outcomeStep: String?
        var stepsCompleted: [String]?
        var identity: IdentityRecord?
        var slotComparisons: [SlotComparisonRecord]?
        var propertyReport: ProbeRecord?
        var grainProbe: ProbeRecord?
        /// *v5.* The full record is `profileHarvests[]` on the report; this is whether the step
        /// ran, was skipped, or was refused, in the tester's own session.
        var profileHarvest: ProbeRecord?
        var develop: DevelopCheckRecord?
        var noCamera: NoCameraRecord?
        var freeText: String?
        var writePass: WritePassRecord?
        /// Frozen read-phase evidence; top-level slots/sweep may describe a later camera state.
        var initialSlots: SlotSummary?
        var propertySweep: PropertySweep?
    }

    /// Did the app name the right camera? The one question whose wrong answer invalidates every
    /// other line in the report — a body resolved to the wrong entry reads and writes a field set
    /// that isn't its own.
    struct IdentityRecord: Codable, Equatable {
        var appShowedProductName: String?
        var appShowedModelID: String?
        /// `ModelIdentification.reportLabel` as it stood when the tester was asked.
        var identification: String?
        /// The capability seal the tester was looking at, verbatim.
        var badge: String?
        var confirmed: Bool?
        /// What the tester says it actually is, when they said it isn't that.
        var correction: String?
    }

    /// One slot the tester compared against the camera's own IQ menu, setting by setting.
    ///
    /// `rows` is a snapshot of what the app *displayed at the time*, not a reference into
    /// `slots.reads` — a push, a reconnect or a pull-to-refresh rewrites that section, and this
    /// record has to keep meaning what it meant when the person was looking at the screen.
    struct SlotComparisonRecord: Codable, Equatable {
        var unreadableCameraShows: [String: String]?
        var slot: Int
        var name: String?
        var filmSimulation: String?
        /// `matches` / `differs` / `unverified` / `notChecked`. Derived from the rows, never typed.
        var verdict: String?
        var checkedAt: Date?
        var rows: [ComparisonRow]?
        /// Fields the decode left unset, so the tester was asked to read them off the camera.
        var fieldsAppCouldNotRead: [String]?
        /// *v6.* The bank's ISO and image format (`jpeg` / `heif` / `notChecked`) as the tester read
        /// them off the camera's menu. Absent means not recorded, never base ISO or JPEG.
        var isoShown: String?
        var imageFormatShown: String?
    }

    struct ComparisonRow: Codable, Equatable {
        var field: String
        /// What the app had on screen for this field.
        var appShowed: String?
        var differs: Bool?
        /// What the camera's menu showed instead. Free text: the tester is copying their screen.
        var cameraShows: String?
        /// D-Range Priority can make the stored value inactive. Preserve both the value and UI copy.
        var priorityControlled: Bool?
        var displayedValue: String?
    }

    /// A diagnostic the flow ran on the tester's behalf.
    struct ProbeRecord: Codable, Equatable {
        /// `ran` / `skipped` / `notWritable` / `refused` / `failed` / `notRun`.
        var state: String
        var slot: Int?
        /// How many properties answered, for a sweep; how many candidates, for a write probe.
        var count: Int?
        /// True when the sweep ran without selecting a slot — a weaker diagnostic.
        var readOnly: Bool?
        var detail: String?
        var capturedAt: Date?
        var evidenceID: String?
    }

    struct DevelopCheckRecord: Codable, Equatable {
        var state: String
        /// `yes` / `no` / `notChecked` — whether the developed JPEG looks like the recipe. The only
        /// test that goes all the way through the conversion path, and it needs eyes.
        var jpegMatchesRecipe: String?
        var detail: String?
    }

    /// The camera never appeared. Everything here is typed by the tester, because there is no
    /// session to ask — the machine half is in `connectionFailures[]`, and on its own it cannot
    /// distinguish a charge-only cable from the wrong USB mode.
    struct NoCameraRecord: Codable, Equatable {
        var modelAsPrinted: String?
        var firmwareFromMenu: String?
        var usbModeWording: String?
        var cable: String?
        var cameraPromptSeen: String?
        var filesPromptSeen: String?
        var appSaid: String?
    }

    struct WritePassRecord: Codable, Equatable {
        var consentAt: Date?
        var backup: BackupRecord?
        /// Nil on a body with no Film Simulation dial — there is nothing to confirm.
        var dialConfirmed: Bool?
        var trials: [PushTrialRecord]?
        var restores: [RestoreRecord]?
        /// *v6.* `enable` / `disable` / `notInMenu` / `notChecked`: AUTO UPDATE CUSTOM SETTING as the
        /// tester read it. Every trial's persistence result is read against it.
        var autoUpdateCustomSetting: String?
    }

    struct BackupRecord: Codable, Equatable {
        var savedAt: Date?
        /// Where the share sheet sent it, when it said. Not a file path — an activity type.
        var activity: String?
        var skipped: Bool?
    }

    /// One test recipe pushed to one slot, and what happened to it afterwards.
    struct PushTrialRecord: Codable, Equatable {
        var id: String?
        var recipeVersion: Int?
        var recipeSettings: RecipeSettings?
        var refusalReason: String?
        /// The canonical recipe's id, or `custom`.
        var recipe: String
        var slot: Int
        var recipeName: String?
        var pushedAt: Date?
        var outcome: SlotOutcome?
        var persistence: PersistenceRecord?
        var menuComparison: SlotComparisonRecord?
        /// `yes` / `no` / `notChecked`.
        var photoMatchesRecipe: String?
        var photoNote: String?
        var connectionStartedAt: Date?
        var connectionID: String?
        /// *v6.* `setForTest` / `leftUnchanged`: whether the tester set the slot's ISO to 800 or
        /// higher and its image format to JPEG before the push, and when they answered. Their
        /// statement, not USB-detected state.
        var preparation: String?
        var preparationConfirmedAt: Date?
    }

    /// Did the recipe survive the camera being switched off and on?
    ///
    /// The failure this exists for reports success, reads back correctly, and is quietly gone after
    /// a power cycle. Nothing the app does during a push can see it.
    struct PersistenceRecord: Codable, Equatable {
        var evidenceState: String?
        var settingsState: String?
        var nameState: String?
        var freshReadSucceeded: Bool?
        var restartConfirmed: Bool?
        var connectionChanged: Bool?
        var persisted: Bool
        var checkedAt: Date?
        var differences: [PersistenceDifference]?
        var nameHolds: Bool?
        var readAt: Date?
        var expected: [String: String]?
        var readback: [String: String]?
        var nameReadBack: String?
        var connectionStartedAt: Date?
        var connectionID: String?
    }

    struct PersistenceDifference: Codable, Equatable {
        var field: String
        var code: String?
        var wrote: String?
        var holds: String?
    }

    struct RestoreRecord: Codable, Equatable {
        var slot: Int
        var outcome: RestoreDisposition?
        var verification: RestoreVerification?
    }

    // MARK: Sections

    struct AppInfo: Codable, Equatable {
        var version: String
        var build: String
        var channel: String

        static var current: AppInfo {
            AppInfo(version: AppIdentity.version, build: AppIdentity.build,
                    channel: BuildChannel.current.rawValue)
        }
    }

    struct HostInfo: Codable, Equatable {
        var systemVersion: String
        var deviceIdentifier: String

        /// `systemVersion` is stored bare (`26.1`); the `"iOS "` belongs to the rendering, not the
        /// wire format. `deviceIdentifier` is `iPhone16,1` rather than "iPhone".
        @MainActor
        static var current: HostInfo {
            HostInfo(systemVersion: AppIdentity.systemVersion,
                     deviceIdentifier: AppIdentity.deviceIdentifier)
        }
    }

    struct CameraIdentity: Codable, Equatable {
        var productName: String
        /// `"usb"` or `"demo"`.
        var transport: String
        var usbVendorID: String?
        var usbProductID: String?
        /// The registry entry the product name resolved to, if any.
        var identifiedModelID: String?
        /// How the product name resolved: `exact`, `alias(<name>)`, `heuristic(<id>)`, `unlisted`
        /// or `unknown` (`ModelIdentification.reportLabel`). `unlisted` is a body no entry matches
        /// that named itself over `GetDeviceInfo`.
        var identification: String
        /// From `GetDeviceInfo` when the transport has none of its own.
        var firmwareVersion: String?
        /// The serial as `SerialHash` records it — never the serial itself. Stable for one body on
        /// one phone, which is enough to tell two reports of one body apart; two phones give the
        /// same body different hashes.
        var serialHash: String?
        /// `hmac-sha256` (`SerialHash.keyedScheme`) beside a keyed hash. Absent beside a hash
        /// stored by an earlier build, which is unkeyed and reversible: that one stays on the
        /// device, where it still matches its camera, and `forSharing` leaves it out of everything
        /// that leaves. Optional, like every v2 field.
        var serialHashScheme: String?
        /// `hardware` / `owner-report` / `community` / `inferred` — how firmly the write path was
        /// known when this report was captured. Optional, like every v2 field, so a v1 file still
        /// decodes.
        var verification: String?
        /// *v7.* What the app decided about writing to this body (`WriteAccess.reportLabel`):
        /// `undecided`, `granted(<grounds>, <stage>)` or `refused(<reason>)`. Updated when the
        /// decision changes: after the slot read, and when a push verifies the body.
        var writeAccess: String?
    }

    struct CodeRecord: Codable, Equatable {
        var code: String
        var name: String?
    }

    struct DeviceInfoRecord: Codable, Equatable {
        /// Set when `GetDeviceInfo` failed or was refused; the other fields are then absent.
        var error: String?
        var standardVersion: Int?
        var vendorExtensionID: String?
        var vendorExtensionVersion: Int?
        var vendorExtensionDesc: String?
        var functionalMode: Int?
        var manufacturer: String?
        var model: String?
        var deviceVersion: String?
        var operationsSupported: [CodeRecord] = []
        var eventsSupported: [String] = []
        var devicePropertiesSupported: [CodeRecord] = []
        var captureFormats: [String] = []
        var imageFormats: [String] = []
        var rawLength: Int?
    }

    struct SlotSummary: Codable, Equatable {
        /// What the registry says this model has — the walk's ceiling. Nil for an unrecognized body.
        var assumedSlotCount: Int?
        /// What Fujifilm's manual says this model has (v5, 2026-09-16). Nil where the registry has
        /// no manual entry or the body is unrecognized. Read next to `probedSlotCount`: equal is the
        /// prediction confirmed, probed lower is a finding, probed higher is the USB protocol
        /// exposing banks the menu does not — and the notes say which.
        var documentedSlotCount: Int?
        /// How many slots actually accepted a select, when probing ran. Nil when the body took the
        /// read-only sweep: selecting a slot is a write, and a body the registry blocks, one with no
        /// identity, or one whose selector didn't answer is never written to.
        var probedSlotCount: Int?
        /// The selector's value before anything touched it.
        var selectorBeforeProbe: Int?
        /// The selector's value when the slot walk began (v5). `0xD18C` is a host-side cursor, not
        /// the bank the camera shoots with, and the walk selects every bank in turn; the record's
        /// method puts the selector back when a read is done (zgrimz/fujifilm-ptp-reference
        /// `docs/04-custom-slots.md#reading-a-bank`). The walk does; `selectorRestored` says whether
        /// the write took.
        var selectorBeforeRead: Int?
        /// `true` when the post-walk restore wrote `selectorBeforeRead` and read it back; `false`
        /// when the write was refused or read back as something else; nil when there was nothing
        /// to restore (the pre-walk read failed, or the walk never ran).
        var selectorRestored: Bool?
        /// *v7.* What the selector answered to the read that opens the walk (`SelectorRead.reportLabel`):
        /// a bank, `unsupported (0x200A)`, or a failure. `selectorBeforeRead` carries the bank as a
        /// number; this says why there is none when there is none.
        var selectorRead: String?
        /// *v7.* How the slot read ended (`WalkEvidence.reportLabel`): swept read-only, finished with
        /// every bank read or not, stopped at an ignored select, or failed.
        var walkResult: String?
        /// *v7.* Where the body's answers disagree with its registry entry: the slot protocol the
        /// entry expects against what the selector answered, and the assumed and documented bank
        /// counts against the count probed. Absent for an unlisted body, which has no entry.
        var registryDisagreements: [DisagreementRecord]?
        var reads: [SlotRead] = []
        /// When these reads were taken.
        ///
        /// Not decoration. `SlotWriter.push` ends with `SlotReader.refresh()`, which rewrites
        /// `reads` — so on a report that carries a push, this section is the camera **after** it,
        /// while `transactions` and `pushes[].slotBefore` are from before. Without a timestamp the
        /// two silently contradict each other and the reader has no way to tell which is which.
        var readAt: Date?
    }

    /// *v7.* One disagreement between the registry's entry and what the body answered.
    struct DisagreementRecord: Codable, Equatable {
        /// `slot protocol`, `assumed slot count` or `documented slot count`.
        var field: String
        var registry: String
        var observed: String
    }

    struct SlotRead: Codable, Equatable {
        var slot: Int
        var selected: Bool
        var selectError: String?
        var name: String?
        var occupied: Bool?
        var properties: [PropertyRead] = []
        /// Values this slot returned that `FujiPresetCodec` could not account for. Optional, not
        /// defaulted — see the note on `pushes`.
        var divergences: [DivergenceRecord]?
    }

    /// One `DecodeDivergence`, flattened for JSON.
    struct DivergenceRecord: Codable, Equatable {
        var code: String        // "0xD199"
        var name: String        // "White Balance"
        var field: String?      // the recipe field it belongs to, when it has one
        var value: String       // "0x8009"
        var decoded: Int        // 32777
        /// `unrecognized` — no entry in our table, and the field was left unset — or `outOfRange`,
        /// or `cameraOnly`: a value the app knows that no recipe carries (Custom white balance).
        var kind: String
        /// `"-4…4"`. Only for `outOfRange`.
        var expectedRange: String?
    }

    struct PropertyRead: Codable, Equatable {
        var code: String
        var name: String?
        /// Hex bytes as read. Absent when the read failed or the camera answered with nothing.
        var value: String?
        /// The value as a signed 16-bit integer, when it is two bytes.
        var decoded: Int?
        var error: String?
        var responseCode: String?
    }

    struct DescriptorRecord: Codable, Equatable {
        var dataType: String
        var writable: Bool
        var factoryDefault: Int?
        var current: Int?
        /// `"none"`, `"range"` or `"enumeration"`.
        var form: String
        var enumeration: [Int]?
        var rangeMin: Int?
        var rangeMax: Int?
        var rangeStep: Int?
    }

    struct PropertyProbeRecord: Codable, Equatable {
        var code: String
        var name: String?
        var value: String?
        var decoded: Int?
        var valueError: String?
        var valueResponseCode: String?
        var descriptor: DescriptorRecord?
        var descriptorError: String?
    }

    struct PropertySweep: Codable, Equatable {
        /// The slot the camera had selected while the sweep ran, if it could be read.
        var slot: Int?
        /// True when nothing was written, not even a slot select — the unrecognized-body path.
        var readOnly: Bool
        var entries: [PropertyProbeRecord] = []
        var capturedAt: Date?
        var evidenceID: String?
    }

    // MARK: Building

    @MainActor
    static func begin(productName: String, transport: String, usb: USBIdentity?,
                      modelID: String?, identification: String, firmwareVersion: String?,
                      verification: String?, assumedSlotCount: Int?,
                      documentedSlotCount: Int? = nil) -> CameraCompatibilityReport {
        let now = Self.timestamp()
        var report = CameraCompatibilityReport(
            generatedAt: now, updatedAt: now, app: .current, host: .current,
            camera: CameraIdentity(productName: productName, transport: transport,
                                   usbVendorID: usb.map { String(format: "0x%04X", $0.vendorID) },
                                   usbProductID: usb.map { String(format: "0x%04X", $0.productID) },
                                   identifiedModelID: modelID, identification: identification,
                                   firmwareVersion: firmwareVersion, serialHash: nil,
                                   verification: verification))
        report.traceStartedAt = now
        report.traceScope = "connection"
        report.connectionID = UUID().uuidString
        report.slots.assumedSlotCount = assumedSlotCount
        report.slots.documentedSlotCount = documentedSlotCount
        return report
    }

    /// `serialKey` is this phone's key unless a test says otherwise; nil records no serial hash.
    mutating func record(deviceInfo info: FujiPTP.DeviceInfo, rawLength: Int,
                         serialKey: SymmetricKey? = SerialHash.deviceKey) {
        func codes(_ list: [UInt16]) -> [String] { list.map(PTPHex.code) }
        deviceInfo = DeviceInfoRecord(
            error: nil,
            standardVersion: Int(info.standardVersion),
            vendorExtensionID: String(format: "0x%08X", info.vendorExtensionID),
            vendorExtensionVersion: Int(info.vendorExtensionVersion),
            vendorExtensionDesc: info.vendorExtensionDesc,
            functionalMode: Int(info.functionalMode),
            manufacturer: info.manufacturer,
            model: info.model,
            deviceVersion: info.deviceVersion,
            operationsSupported: info.operationsSupported.map {
                CodeRecord(code: PTPHex.code($0), name: FujiPTP.operationName($0)) },
            eventsSupported: codes(info.eventsSupported),
            devicePropertiesSupported: info.devicePropertiesSupported.map {
                CodeRecord(code: PTPHex.code($0), name: FujiPTP.propertyName($0)) },
            captureFormats: codes(info.captureFormats),
            imageFormats: codes(info.imageFormats),
            rawLength: rawLength)
        if camera.firmwareVersion == nil, !info.deviceVersion.isEmpty {
            camera.firmwareVersion = info.deviceVersion
        }
        if !info.serialNumber.isEmpty {
            if let serialKey {
                camera.serialHash = SerialHash.recordConnected(serial: info.serialNumber, key: serialKey)
                camera.serialHashScheme = SerialHash.keyedScheme
            } else {
                camera.serialHash = nil
                camera.serialHashScheme = nil
                note("serial hash omitted: this phone's hashing key is unavailable, and an unkeyed hash would expose the serial")
            }
        }
        touch()
    }

    mutating func recordDeviceInfoFailure(_ message: String) {
        deviceInfo = DeviceInfoRecord(error: message)
        touch()
    }

    mutating func noteUnsupported(code: UInt16) {
        let spelled = PTPHex.code(code)
        if !unsupportedPropertyCodes.contains(spelled) { unsupportedPropertyCodes.append(spelled) }
    }

    mutating func note(_ text: String) {
        notes.append(text)
        touch()
    }

    /// `note`, for a finding that restates a standing fact about the camera rather than recording
    /// an event.
    ///
    /// The slot walk runs on connect *and* at the end of every push, restore and pull-to-refresh,
    /// and everything else it produces is *replaced* each time — only `notes` is append-only. So a
    /// body that refuses C7 would collect that line once per walk, and the report would tell its
    /// reader the same thing several times with no way to know whether it happened that often.
    ///
    /// Deliberately not applied to `note` wholesale: a write probe re-run with the same candidates
    /// produces the same summary twice, and there the repetition is the record of two probes.
    mutating func noteOnce(_ text: String) {
        guard !notes.contains(text) else { return }
        note(text)
    }

    mutating func touch() { updatedAt = Self.timestamp() }

    /// `Date()` truncated to the whole second.
    ///
    /// Every date in this type is encoded as ISO 8601, which has no sub-second component — so an
    /// untruncated `Date` decodes to a *different* value than the one that was written, and the
    /// document stops being equal to itself across a save/load. Truncating at the source is what
    /// makes "the JSON and the text are one account" true of timestamps too, and it costs nothing:
    /// nothing here is timed more finely than a second.
    static func timestamp() -> Date { Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)) }

    /// Whether two reports are about the same physical camera.
    ///
    /// The product name and the USB vendor and product ids must match, always. A serial hash that
    /// agrees while the name disagrees is a contradiction — one of the two is wrong — and the safe
    /// reading of a contradiction is "not the same camera". Where both carry a hash it has to agree
    /// as well, which is what separates two bodies of the same model. This decides only whether to
    /// carry history forward (`CompatibilityReportRecorder.carryHistoryForward`), so the cost of a
    /// false negative is a lost diagnostic line and the cost of a false positive is attributing one
    /// camera's refusals to another — the asymmetry is why this errs strict.
    func describesSameBody(as other: CameraCompatibilityReport) -> Bool {
        guard camera.productName == other.camera.productName,
              camera.usbVendorID == other.camera.usbVendorID,
              camera.usbProductID == other.camera.usbProductID else { return false }
        if let mine = camera.serialHash, let theirs = other.camera.serialHash { return SerialHash.same(mine, theirs) }
        return true
    }

    /// Reduce this report to what the drift check needs and nothing else.
    ///
    /// The report is where the app remembers what it last wrote to each slot, and Clear Diagnostics
    /// is the button a careful person presses right after sharing a report — deleting the report
    /// outright would disable the check at exactly that moment. What survives is the camera identity
    /// (so `describesSameBody` still matches) and, per applied push, the slot, the time, the model
    /// and firmware, and the film simulation bytes written. Slot contents, raw bytes, names, trace,
    /// device info, tester answers, and the develop, conversion-check and failed-connection records
    /// all go.
    mutating func stripToDriftBaseline() {
        deviceInfo = nil
        slots = SlotSummary()
        propertySweep = nil
        unsupportedPropertyCodes = []
        transactions = []
        transactionsDropped = 0
        traceStartedAt = nil
        traceScope = "unavailable"
        connectionID = nil
        notes = []
        // The tester's own answers go with everything else they can ask to erase. Nothing here is
        // needed to notice a slot changing later, which is the one thing this keeps.
        guidedTests = nil
        // Develops, conversion checks and failed connects (with the iOS permission states at the
        // time) are evidence about what happened, not the baseline.
        develops = nil
        developsDropped = nil
        profileHarvests = nil
        profileHarvestsDropped = nil
        connectionFailures = nil
        let d192 = PTPHex.code(FujiPTP.PresetProp.filmSimulation.rawValue)
        let kept: [PushRecord] = (pushes ?? []).compactMap { push in
            guard push.outcome == .applied,
                  let sim = push.fields.first(where: { $0.code == d192 }) else { return nil }
            var minimal = PushRecord(at: push.at, slot: push.slot, modelID: push.modelID,
                                     firmwareVersion: push.firmwareVersion, outcome: push.outcome,
                                     nameWritten: false, nameApplied: nil)
            minimal.fields = [FieldRecord(code: sim.code, name: sim.name, isRecipeField: true,
                                          outcome: sim.outcome, wrote: sim.wrote)]
            minimal.baselineOnly = true
            return minimal
        }
        pushes = kept.isEmpty ? nil : kept
        pushesDropped = nil
        touch()
    }

    /// Adopt an earlier report's push history.
    ///
    /// A report is created fresh on every connect and the file holds only the newest, so without
    /// this a tester who pushes, unplugs and plugs back in loses the record of what the camera
    /// refused — which is the most valuable thing an untested body produces. The slot *reads* are
    /// deliberately not carried over: those describe the camera as it is now, and a stale copy
    /// would be worse than none.
    mutating func adoptPushHistory(from previous: CameraCompatibilityReport) {
        guard let earlier = previous.pushes, !earlier.isEmpty else { return }
        var combined = earlier + (pushes ?? [])
        var dropped = (previous.pushesDropped ?? 0) + (pushesDropped ?? 0)
        if combined.count > Self.maxPushRecords {
            dropped += combined.count - Self.maxPushRecords
            combined.removeFirst(combined.count - Self.maxPushRecords)
        }
        pushes = combined
        pushesDropped = dropped == 0 ? nil : dropped
    }

    /// As `adoptPushHistory`, and for the same reason: the harvest lives in the develop step of a
    /// pass that asks the tester to unplug twice afterwards, and each reconnect begins a report.
    mutating func adoptProfileHarvests(from previous: CameraCompatibilityReport) {
        guard let earlier = previous.profileHarvests, !earlier.isEmpty else { return }
        var combined = earlier + (profileHarvests ?? [])
        var dropped = (previous.profileHarvestsDropped ?? 0) + (profileHarvestsDropped ?? 0)
        if combined.count > Self.maxProfileHarvestRecords {
            dropped += combined.count - Self.maxProfileHarvestRecords
            combined.removeFirst(combined.count - Self.maxProfileHarvestRecords)
        }
        profileHarvests = combined
        profileHarvestsDropped = dropped == 0 ? nil : dropped
    }

    /// As `adoptProfileHarvests`, for the record a harvest exists to make possible. A tester who
    /// develops, unplugs and reconnects to share the report would otherwise lose which field was
    /// clamped, whether the profile verified and the output size to the reconnect's fresh report.
    /// `CookRecordTests` covers it.
    mutating func adoptDevelops(from previous: CameraCompatibilityReport) {
        guard let earlier = previous.develops, !earlier.isEmpty else { return }
        var combined = earlier + (develops ?? [])
        var dropped = (previous.developsDropped ?? 0) + (developsDropped ?? 0)
        if combined.count > Self.maxDevelopRecords {
            dropped += combined.count - Self.maxDevelopRecords
            combined.removeFirst(combined.count - Self.maxDevelopRecords)
        }
        develops = combined
        developsDropped = dropped == 0 ? nil : dropped
    }

    static func propertyRead(code: UInt16, value: Data?, error: Error?) -> PropertyRead {
        var read = PropertyRead(code: PTPHex.code(code), name: FujiPTP.propertyName(code))
        if let value {
            read.value = PTPHex.bytes(value)
            if value.count == 2 { read.decoded = FujiEncoding.decodeInt16(value) }
        }
        if let error {
            if case CameraError.ptpError(let code) = error {
                read.responseCode = PTPHex.code(code)
                read.error = FujiPTP.responseName(code) ?? "PTP error"
            } else {
                read.error = error.cameraLogDescription
            }
        }
        return read
    }

    /// How a two-byte value reads, in the form that is actually useful.
    ///
    /// `decoded` is a signed 16-bit int, which is right for tones and shifts and actively misleading
    /// for the properties Fuji stores as bit patterns: an Auto-White-Priority white balance is
    /// `0x8020`, and printing it as `-32736` next to raw bytes of `2080` (little-endian) gives a
    /// reader two numbers, neither of which is the one to look up. A hugely negative signed reading
    /// is the tell — no tone, shift or temperature comes near it.
    static func reading(_ decoded: Int?) -> String {
        guard let decoded else { return "" }
        guard decoded <= -1000 else { return " (\(decoded))" }
        return String(format: " (u16 0x%04X)", UInt16(truncatingIfNeeded: decoded))
    }

    static func divergenceRecord(_ d: DecodeDivergence) -> DivergenceRecord {
        var record = DivergenceRecord(code: PTPHex.code(d.code), name: d.property,
                                      field: d.field?.displayName,
                                      value: PTPHex.code(UInt16(truncatingIfNeeded: d.value)),
                                      decoded: d.value, kind: "unrecognized")
        switch d.kind {
        case .outOfRange(let min, let max):
            record.kind = "outOfRange"
            record.expectedRange = "\(DecodeDivergence.trim(min))…\(DecodeDivergence.trim(max))"
        case .cameraOnly:
            record.kind = "cameraOnly"
        case .unrecognized:
            break
        }
        return record
    }

    /// Append a push outcome, oldest dropped once the cap is reached. Bounded for the same reason
    /// the PTP trace is: this file is read on screen and mailed, and a tester pushing all seven
    /// slots repeatedly should not turn it into something nobody opens.
    mutating func record(push result: SlotWriteResult, at: Date, modelID: String?,
                         firmwareVersion: String?, slotBefore: [UInt16: Data]?,
                         nameBefore: String? = nil, slotWasEmpty: Bool? = nil,
                         selectorReadBack: Int? = nil, kind: String? = nil) {
        var record = PushRecord(at: at, slot: result.slot, modelID: modelID,
                                firmwareVersion: firmwareVersion,
                                outcome: result.outcome,
                                nameWritten: result.nameWritten, nameApplied: result.nameApplied,
                                clampedFields: result.clampedFields, errorMessage: result.errorMessage)
        record.selectorReadBack = selectorReadBack
        record.nameOutcome = result.nameOutcome.map(Self.name(for:))
        record.firstWrite = result.firstWrite.map(Self.firstWriteRecord)
        record.nameBefore = nameBefore
        record.slotWasEmpty = slotWasEmpty
        record.kind = kind
        record.slotBefore = slotBefore.map { before in
            Dictionary(uniqueKeysWithValues: before.map { (PTPHex.code($0.key), PTPHex.bytes($0.value)) })
        }
        record.fields = result.fields.map { field in
            var out = FieldRecord(code: field.code == 0 ? nil : PTPHex.code(field.code),
                                  name: field.field, isRecipeField: field.isRecipeField,
                                  outcome: Self.name(for: field.outcome))
            // For every outcome, not only a mismatch: "what did D192 get" is the question a
            // film-simulation complaint asks.
            out.wrote = field.wrote.map(PTPHex.bytes)
            switch field.outcome {
            case .rejected(let code):
                out.responseCode = code.map(PTPHex.code)
            case .mismatched(let wrote, let read):
                out.wrote = PTPHex.bytes(wrote)
                out.read = read.map(PTPHex.bytes)
            default: break
            }
            return out
        }
        // A push's entry is appended before its first write (`beginPush`) and finished here, in
        // place, so a push that was cut off keeps the one record of what the slot held.
        if let index = pushes?.firstIndex(where: { $0.at == at && $0.slot == result.slot }) {
            pushes?[index] = record
            touch()
            return
        }
        var existing = pushes ?? []
        existing.append(record)
        if existing.count > Self.maxPushRecords {
            pushesDropped = (pushesDropped ?? 0) + (existing.count - Self.maxPushRecords)
            existing.removeFirst(existing.count - Self.maxPushRecords)
        }
        pushes = existing
        touch()
    }

    static func firstWriteRecord(_ outcome: FirstWriteOutcome) -> FirstWriteRecord {
        func restore(_ restore: FirstWriteOutcome.Restore) -> String {
            switch restore {
            case .unchanged: return "unchanged"
            case .restored: return "restored"
            case .restoreRefused(let code): return "restore-refused \(PTPHex.code(code))"
            case .restoreMismatch: return "restore-mismatch"
            case .restoreUnknown: return "restore-unknown"
            }
        }
        switch outcome {
        case .written(let property):
            return FirstWriteRecord(property: PTPHex.code(property), outcome: "written")
        case .invalidValue(let property, let code):
            return FirstWriteRecord(property: PTPHex.code(property), outcome: "invalid-value", responseCode: PTPHex.code(code))
        case .refused(let property, let code, let put):
            return FirstWriteRecord(property: PTPHex.code(property), outcome: "refused", responseCode: PTPHex.code(code),
                                    restore: restore(put))
        case .mismatched(let property, let read, let put):
            return FirstWriteRecord(property: PTPHex.code(property), outcome: "mismatched",
                                    read: read.map(PTPHex.bytes), restore: restore(put))
        case .unknown(let property, let put):
            return FirstWriteRecord(property: PTPHex.code(property), outcome: "unknown", restore: restore(put))
        }
    }

    /// File what the connect's slot read established, beside the fields the walk writes as it goes,
    /// and where the body's answers disagree with its registry entry. `model` is the registry's
    /// entry; nil for an unlisted body, which has nothing to disagree with.
    mutating func record(slotRead: WalkResult, registryModel model: CameraModel?) {
        slots.selectorRead = slotRead.selector.reportLabel
        slots.walkResult = slotRead.walk.reportLabel
        guard let model else { return }
        var disagreements: [DisagreementRecord] = []
        switch slotRead.selector {
        case .value(let bank) where !model.supportsSlotProtocol:
            disagreements.append(DisagreementRecord(field: "slot protocol", registry: "none expected",
                                                    observed: "the selector answered C\(bank)"))
        case .unsupported where model.supportsSlotProtocol:
            disagreements.append(DisagreementRecord(field: "slot protocol", registry: "expected",
                                                    observed: "the selector answered 0x200A"))
        default:
            break
        }
        if case .finished(let banks, _) = slotRead.walk {
            if banks != model.slotCount {
                disagreements.append(DisagreementRecord(field: "assumed slot count", registry: "\(model.slotCount)",
                                                        observed: "\(banks) accepted a select"))
            }
            if let documented = model.documentedSlotCount, banks != documented {
                disagreements.append(DisagreementRecord(field: "documented slot count", registry: "\(documented)",
                                                        observed: "\(banks) accepted a select"))
            }
        }
        slots.registryDisagreements = disagreements.isEmpty ? nil : disagreements
        touch()
    }

    /// How a push's record reads while the push is still running, and for good if it never
    /// returns: cut off by a pulled cable or a quit app, with the slot possibly part-written.
    static let interruptedPushMessage = "This push was cut off before the app recorded how it ended — the camera was disconnected or the app quit mid-push. The slot may hold a mix of the old and new settings."

    /// Append a push's entry before its first write, with the recovery copy already in it and the
    /// outcome `unknown`: if the push never returns, this entry is its record, and the copy is what
    /// Undo Last Push restores from. `record(push:at:…)` with the same `at` and slot replaces it
    /// when the push does return.
    mutating func beginPush(at: Date, slot: Int, modelID: String?, firmwareVersion: String?,
                            slotBefore: [UInt16: Data]?, nameBefore: String?, slotWasEmpty: Bool?,
                            selectorReadBack: Int?, kind: String? = nil) {
        let placeholder = SlotWriteResult(slot: slot, outcome: .unknown, nameWritten: false, nameApplied: nil,
                                          clampedFields: [], fields: [],
                                          errorMessage: Self.interruptedPushMessage)
        record(push: placeholder, at: at, modelID: modelID, firmwareVersion: firmwareVersion,
               slotBefore: slotBefore, nameBefore: nameBefore, slotWasEmpty: slotWasEmpty,
               selectorReadBack: selectorReadBack, kind: kind)
    }

    /// Record one develop. Mirrors `record(push:)`, including the drop accounting — a Test Kitchen
    /// grid is up to nine cooks and a tester will run more than one grid.
    mutating func record(develop evidence: CookEvidence, at: Date, modelID: String?,
                         firmwareVersion: String?, succeeded: Bool,
                         clampedFields: [String], filmSimulation: String?,
                         resultID: UUID? = nil, context: CookRecordContext? = nil) {
        var record = DevelopRecord(at: at, modelID: modelID, firmwareVersion: firmwareVersion,
                                   succeeded: succeeded, filmSimulation: filmSimulation)
        record.resultID = resultID
        record.runID = context?.runID
        record.caseID = context?.caseID
        record.recipeID = context?.recipeID
        record.recipeSettings = context?.settings
        record.profileLength = evidence.profileLength
        record.declaredParams = evidence.declaredParams
        record.layoutBase = evidence.layoutBase
        record.profileVerified = evidence.profileVerified
        record.profileVerification = evidence.profileVerification
        record.outputValidation = evidence.outputValidation
        record.cleanupOutcome = evidence.cleanupOutcome
        record.mismatches = evidence.mismatches.isEmpty ? nil : evidence.mismatches
        record.dynamicRange = evidence.dynamicRange
        record.fullResolution = evidence.fullResolution
        record.clampedFields = clampedFields.isEmpty ? nil : clampedFields
        record.outputBytes = evidence.outputBytes
        record.failureReason = evidence.failureReason

        var existing = develops ?? []
        existing.append(record)
        if existing.count > Self.maxDevelopRecords {
            developsDropped = (developsDropped ?? 0) + (existing.count - Self.maxDevelopRecords)
            existing.removeFirst(existing.count - Self.maxDevelopRecords)
        }
        develops = existing
        touch()
    }

    mutating func record(harvest record: ProfileHarvestRecord) {
        var existing = profileHarvests ?? []
        existing.append(record)
        if existing.count > Self.maxProfileHarvestRecords {
            profileHarvestsDropped = (profileHarvestsDropped ?? 0) + (existing.count - Self.maxProfileHarvestRecords)
            existing.removeFirst(existing.count - Self.maxProfileHarvestRecords)
        }
        profileHarvests = existing
        touch()
    }

    /// Add or replace a guided test, keyed by its session id.
    ///
    /// Upsert rather than append: a test is projected here every time it reaches a step boundary, so
    /// appending would fill the section with a dozen snapshots of one session. Replacing in place
    /// also makes the projection idempotent, which is what lets the caller re-project freely without
    /// tracking whether it already has.
    mutating func record(guidedTest record: GuidedTestRecord) {
        var existing = guidedTests ?? []
        if let index = existing.firstIndex(where: { $0.sessionID == record.sessionID }) {
            existing[index] = record
        } else {
            existing.append(record)
            if existing.count > Self.maxGuidedTestRecords {
                existing.removeFirst(existing.count - Self.maxGuidedTestRecords)
            }
        }
        guidedTests = existing
        touch()
    }

    /// Adopt an earlier report's guided tests, the way `adoptPushHistory` adopts its pushes.
    ///
    /// Load-bearing for the write pass specifically: its power-cycle step *requires* the camera to
    /// be switched off and on, which recreates this report from scratch, and the record of what was
    /// pushed before the power cycle is the thing the step exists to compare against. Without this
    /// the evidence would be destroyed by the procedure that produces it.
    mutating func adoptGuidedTests(from previous: CameraCompatibilityReport) {
        guard let earlier = previous.guidedTests, !earlier.isEmpty else { return }
        var combined = earlier
        for record in guidedTests ?? [] {
            if let index = combined.firstIndex(where: { $0.sessionID == record.sessionID }) {
                combined[index] = record
            } else {
                combined.append(record)
            }
        }
        if combined.count > Self.maxGuidedTestRecords {
            combined.removeFirst(combined.count - Self.maxGuidedTestRecords)
        }
        guidedTests = combined
    }

    /// Adopt an earlier report's property sweep when this connect hasn't produced one.
    ///
    /// The sweep is the bulkiest evidence a read pass collects and there is only ever one, so a
    /// reconnect — including the power cycle the *write* pass asks for by name — would otherwise
    /// destroy it, and a tester who did Part One and then Part Two would arrive with a
    /// `guidedTests[]` record saying "ran on C1 — 26 properties" and no sweep anywhere in the
    /// report to look at.
    ///
    /// A sweep this connect *did* run always wins: it describes the camera as it is now. What this
    /// rescues is the case where nothing has replaced it.
    mutating func adoptPropertySweep(from previous: CameraCompatibilityReport) {
        guard propertySweep == nil, let earlier = previous.propertySweep else { return }
        propertySweep = earlier
    }

    mutating func record(connectionFailure stage: String, reason: String, productName: String? = nil,
                         usb: USBIdentity? = nil, identification: String? = nil,
                         authorization: (control: String, contents: String)? = nil) {
        var record = ConnectionFailure(at: Self.timestamp(), stage: stage, reason: reason,
                                       productName: productName)
        record.usbVendorID = usb.map { String(format: "0x%04X", $0.vendorID) }
        record.usbProductID = usb.map { String(format: "0x%04X", $0.productID) }
        record.identification = identification
        record.controlAuthorization = authorization?.control
        record.contentsAuthorization = authorization?.contents

        var existing = connectionFailures ?? []
        existing.append(record)
        if existing.count > Self.maxConnectionFailures {
            existing.removeFirst(existing.count - Self.maxConnectionFailures)
        }
        connectionFailures = existing
        touch()
    }

    /// A report for a camera that was never reached — identity unknown, nothing read, nothing
    /// written. Used only when there is no existing report to append the failure to, so a first-ever
    /// connect that fails still produces something with the app, iOS and device lines on it.
    @MainActor
    static func beginUnreached() -> CameraCompatibilityReport {
        let now = Self.timestamp()
        var report = CameraCompatibilityReport(
            generatedAt: now, updatedAt: now, app: .current, host: .current,
            camera: CameraIdentity(productName: "(no camera reached)", transport: "usb",
                                   usbVendorID: nil, usbProductID: nil,
                                   identifiedModelID: nil, identification: "unknown",
                                   firmwareVersion: nil, serialHash: nil, verification: nil))
        report.traceScope = "unavailable"
        return report
    }

    private static func name(for outcome: FieldOutcome) -> String {
        switch outcome {
        case .written: return "written"
        case .rejected: return "rejected"
        case .notAttempted: return "notAttempted"
        case .mismatched: return "mismatched"
        case .unverified: return "unverified"
        case .outcomeUnknown: return "outcome_unknown"
        }
    }

    static func descriptorRecord(_ d: FujiPTP.PropertyDescriptor) -> DescriptorRecord {
        var record = DescriptorRecord(dataType: d.dataTypeName, writable: d.isWritable,
                                      factoryDefault: d.factoryDefault, current: d.current, form: "none")
        switch d.form {
        case .none: break
        case .range(let min, let max, let step):
            record.form = "range"; record.rangeMin = min; record.rangeMax = max; record.rangeStep = step
        case .enumeration(let values):
            record.form = "enumeration"; record.enumeration = values
        }
        return record
    }

    // MARK: Serialization

    /// Shared with `GuidedTestStore`, whose files sit beside the report and read the same way.
    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    var json: Data { (try? Self.encoder.encode(self)) ?? Data() }

    static func decode(_ data: Data) throws -> CameraCompatibilityReport {
        try decoder.decode(CameraCompatibilityReport.self, from: data)
    }

    /// This report as it may leave the device: without a serial hash that carries no scheme.
    ///
    /// Such a hash was stored by a build that hashed serials unkeyed, and anyone can reverse it. It
    /// stays in the stored file, where the next connect of its camera still recognizes it and
    /// replaces it with a keyed one; it goes no further. Applied by `DiagnosticsReportSnapshot.Export`,
    /// which everything that shows, copies or shares a report reads.
    var forSharing: CameraCompatibilityReport {
        guard camera.serialHash != nil, camera.serialHashScheme == nil else { return self }
        var copy = self
        copy.camera.serialHash = nil
        return copy
    }

    /// `text` without any rendering of a serial hash that carries no scheme — the text half of
    /// `forSharing`, for renderings already frozen into a saved snapshot by an earlier build.
    static func withoutUnkeyedSerialHashLines(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let kept = lines.filter { line in
            // A keyed hash renders with its scheme after it; an unkeyed one, in this build and
            // every earlier one, renders as the bare hash.
            !(line.hasPrefix(serialHashLabel) && !line.dropFirst(serialHashLabel.count).contains(" "))
        }
        return kept.count == lines.count ? text : kept.joined(separator: "\n")
    }

    private static let serialHashLabel = "Serial      hash "

    static func serialHashLine(_ hash: String, scheme: String?) -> String {
        scheme == nil ? serialHashLabel + hash : serialHashLabel + hash + " (keyed to this phone)"
    }

    /// `fuji-cookbook-camera-report-X-T50-20260904-1112.json` — model or product name, then when.
    var suggestedFilename: String {
        let subject = (camera.identifiedModelID ?? camera.productName)
            .replacingOccurrences(of: "FUJIFILM", with: "")
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "-")
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyyMMdd-HHmm"
        return "fuji-cookbook-camera-report-\(subject.isEmpty ? "camera" : subject)-\(f.string(from: generatedAt)).json"
    }

}

/// USB vendor/product ids as the transport enumerated them.
struct USBIdentity: Equatable, Codable, Sendable {
    let vendorID: Int
    let productID: Int
}
