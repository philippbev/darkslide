# Camera Compatibility Report

*Format note for `CameraCompatibilityReport` (`FujiCookbook/Camera/CameraCompatibilityReport.swift`).
`reportVersion` is **7**. Every version's changes are additive: reports written at earlier versions
still decode, and their fields and hardware observations keep their original meanings.*

An old `applied` result does not establish exact restoration, and an app capability gate is not a
body-wide hardware conclusion. What each body has shown is recorded once, in the protocol record's
[camera bodies](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/07-cameras.md) chapter; this document links to it rather than restating it.

> **Every field added from v2 on must be `Optional`.** The type has no `CodingKeys` and no
> `init(from:)`, and Swift's synthesized `Decodable` ignores a property's default value for a missing
> key — it throws `keyNotFound`. `CameraReportStore.loadLatest()` reads a file written by an earlier
> version of the app every time the diagnostics screen opens, so a non-optional `[Thing] = []` would
> make a user's stored report silently vanish the moment they updated the app. Pinned by
> `CompatibilityReportTests.testAV1ReportStillDecodes`.

## Why it exists

The app's Camera Test exists to bring back facts about Fujifilm bodies the maintainers don't have.
A description ("it said no camera detected") is not a fact anyone can act on; a JSON document with the
body's own `GetDeviceInfo`, every slot's raw bytes, and the PTP transactions that produced them is.
Two X-T5 reports diff. Every capture stage writes into this one document, and the human-readable
text (`textRendering`, what "Report a Problem" shows) is a rendering of it — never a separate account
that could drift.

## Lifecycle

- Created in `CameraConnector`'s connect the moment the session opens, for every body.
- `GetDeviceInfo` runs first. Then the slot read, which walks the banks, or the read-only sweep,
  which writes nothing: the sweep for a body nothing names, one the registry blocks, and one the
  registry doesn't vouch for whose selector didn't answer a bank number. The PTP trace is armed for
  exactly that sequence; for each push (the select and its read-back, the name, the property writes,
  the verification read-back); and for the Property Report and write probe. Not for the post-push
  re-read of every slot, whose result is already in `slots.reads`.
  Cap 1200 transactions (`PTPTraceRecorder.maxTransactions`); beyond that they are counted in
  `transactionsDropped`, not kept.
- Written to disk at every stage boundary: `<App Group>/Reports/camera-compatibility-latest.json`.
  A crash mid-session leaves the last complete stage behind.
- **Not** cleared by `disconnect()`. `CompatibilityReportRecorder.report` outlives the session, and
  `CameraReportStore.loadLatest()` outlives the launch.
- **A develop writes `develops[]`** at the end of every cook, clean or not, and the PTP trace is
  armed around it the way it is around a push. Every cook, not only the anomalies: RAW conversion is
  enabled on far more bodies than it is verified on (the X-T50 and the GFX100S), so a
  *successful* develop on any of the others is the evidence.
- **A push writes `pushes[]` twice.** Its entry is appended, and written to disk, as soon as the
  slot's bytes and name have been read and before anything is written — outcome `unknown`, with a
  message saying the push was cut off — and replaced in place by the finished record when the push
  returns. A push the cable or the app cuts off therefore keeps `slotBefore`, which is what Undo
  Last Push restores from. Nothing is added to a report once its session is over.
- **A connect that never reached a usable session writes `connectionFailures[]`** — appended to whatever
  report already exists, or to a minimal `beginUnreached()` one when there is nothing to append to.
  Appending rather than replacing is load-bearing: this file is overwritten per connect, so building
  a fresh one here would let a failed reconnect erase the successful session before it, at exactly
  the moment the user goes to send a report.
- **Reduced, not deleted, by Clear Diagnostics** — see `stripToDriftBaseline()` and "Reference
  bodies" below. Deleted only when there is no applied push to keep a baseline for. What survives is the
  camera identity and, per applied push, the slot, time, outcome, model, firmware and film simulation; develops, conversion
  checks, failed connects and Camera Test answers go with everything else. Clearing also empties the
  live trace (`CompatibilityReportRecorder.clear()`), so a camera still connected can't write the
  pre-clear transactions back at its next persist.
- The Camera Property Report (diagnostic mode) writes its per-slot sweep into the same document.
  There is only ever **one** sweep, so a second run replaces the first. It is carried across a
  reconnect by `adoptPropertySweep` — but only when this connect hasn't produced one of its own,
  because a fresh sweep describes the camera as it is now. Without that carry, the write pass's power
  cycle would destroy the very sweep its `guidedTests[]` record cites. Since v6 a continuous Camera
  Test also freezes its own copy (`guidedTests[].propertySweep`, beside `initialSlots`), so the
  top-level replacement doesn't take the test's evidence with it.
- **A guided Camera Test writes `guidedTests[]`** at each step boundary, upserted by session id, and
  is **carried across a reconnect** by `adoptGuidedTests` alongside the push history. That carry is
  not a nicety: the write pass asks the user to switch the camera off and on, which lands in
  `connect` and rebuilds this document — so without it the procedure would destroy the record of the
  push it exists to check. The session itself lives in its own file
  (`<App Group>/Reports/guided-test-session.json`, and `guided-test-history.json` for finished ones)
  and is the source of truth; what is here is a projection of it.

## Version 7 — the write decision

Version 7 records what the app decided about writing to the body and what that decision rests on:
`camera.writeAccess`, `slots.selectorRead`, `slots.walkResult`, `slots.registryDisagreements[]` and
`pushes[].firstWrite` (see the field table). The text rendering prints the decision as its `Writes`
line. Like every version's fields they are optional: a report from an earlier build has none of them,
and their absence means the build didn't record the decision, not that writing was refused.

## Version 6 — continuous Camera Test evidence

The continuous test has one saved session and one normal final report. Progress sharing does not
complete or archive that session. The human-readable result starts with coverage and observations;
the existing camera JSON remains the technical attachment. Completing navigation is not a passing
hardware result, and a sharing callback is not a delivery receipt.

New fields are optional. Reports written at earlier versions still decode, and absence of a new
field means **unknown**, not a successful check. In particular, do not reinterpret legacy
`completed`, `sentEarly`, `develop.state: ran`, or `stepsCompleted` as proof of successful operation,
verified rendering, or delivered mail. A record with `plan` uses the continuous flow; `wave` remains
for legacy compatibility and must not be used alone to classify a new record as reading-only.

| v6 field | Meaning and limits |
|---|---|
| `guidedTests[].plan` | Saved plan version, selected optional checks and setup model ID. Omitted optional cases remain missing coverage. |
| `guidedTests[].selectedWriteSlot` / `recoveryBaselineID` | The selected slot and the session's local recovery-record identity. The ID is not a remotely retrievable backup. |
| `guidedTests[].stillBankConfirmations` | Optional X-M5 bank checks, each with `slot` and `confirmedAt`. These record the user's confirmation that the specific bank is assigned to STILL; they are not USB-detected state. Missing legacy data implies no confirmation. Both the grain probe and recipe write check their actual bank. |
| `guidedTests[].slotComparisons[].unreadableCameraShows` | The user's observations for settings the app could not decode; preserve the distinction from a successful app read. |
| `guidedTests[].writePass.trials[].id` / `recipeVersion` / `recipeSettings` | Stable trial identity and the supplied recipe's version and exact authored settings. A later trial cannot establish persistence of an earlier one. |
| `guidedTests[].writePass.trials[].refusalReason` | Recorded limitation/refusal associated with the trial, separate from the accepted fields. |
| `guidedTests[].writePass.trials[].persistence.evidenceState` | `passed`, `issueFound`, `notTested`, or `couldNotVerify`. Prefer this explicit evidence state to interpreting the legacy Boolean alone. |
| `...persistence.settingsState` / `nameState` | Independent evidence about recipe settings and slot-name persistence. A name-only failure must not be hidden by matching settings. |
| `...persistence.freshReadSucceeded` / `restartConfirmed` / `connectionChanged` | Fresh-read outcome, the user's restart confirmation, and observed connection change. USB reconnection alone does not prove use of the power switch. |
| `guidedTests[].kitchenRuns` | Stable run ID, case ID, start time, supplied recipe snapshots and resolution choice, captured before the camera operation. A run without completion evidence may have been interrupted. |
| `guidedTests[].kitchenCompletions` | Run-associated per-cell results, local saved-batch identity and save-failure status. Cells carry result/recipe IDs and a file index, never a selected file name or path. |
| `guidedTests[].kitchenObservations` | The user's observations associated with the relevant Kitchen case/run; a successful conversion is not automatically a positive visual observation. |
| `develops[].resultID` / `runID` / `caseID` / `recipeID` / `recipeSettings` | Link technical conversion evidence to the exact guided operation and supplied settings. Legacy and nonguided conversions may have no guided context. |
| `guidedTests[].shareEvents` | Timestamped local handoff observations: `ready`, `canceled`, `saved`, `shared`, `mailSent`, `failed`. `saved` is a Mail draft; `shared` can be a save to Files; `mailSent` is the composer's result, not proof of receipt. The in-app Mail composer (`ReportMailComposer`) is wired but not enabled (`preferAddressedMail: false`), so the app doesn't produce `saved` or `mailSent`; Mail is reached as a share-sheet destination and records `shared`. |
| `connectionID` / `traceStartedAt` / `traceScope` | Identity and opening time of the connection whose recorded operations populate the trace. `connection` describes one connection; `unavailable` means original connection diagnostics are absent. IDs distinguish reconnects within the same second. Legacy reports lack these fields. |
| `guidedTests[].initialSlots` | Frozen `SlotSummary` from the test's reading phase, including its `readAt` and raw values. Unlike top-level `slots`, it is not replaced by post-write or post-restoration reads. Missing means the original snapshot was not retained. |
| `guidedTests[].propertySweep` | The sweep retained by this test, independent of the mutable top-level sweep. Both can carry `capturedAt` and `evidenceID`; the probe summary carries the same reference. A later sweep on the same slot must not silently replace the evidence for an earlier check. |
| `guidedTests[].propertyReport.capturedAt` / `evidenceID` | When that reading was captured and its associated sweep identity. Counts represent answered properties, not a verdict that every attempted descriptor/value read succeeded. |
| `...slotComparisons[].rows[].priorityControlled` / `displayedValue` | Whether D-Range Priority made a stored value inactive, and the actual UI wording shown. `appShowed` preserves the underlying value; confirming a controlled value does not demonstrate independent DR or tone control. |
| `...writePass.trials[].connectionID` / `connectionStartedAt` | The connection used for the write. Persistence carries the corresponding read connection identity/time; reconnect provenance is independent of the user's power-switch confirmation. |
| `...persistence.readAt` / `expected` / `readback` / `nameReadBack` | Fresh read time, expected accepted property bytes, retained readback bytes, and the name read. Keep these with explicit evidence states; absence does not prove equality or a failed recipe. |
| `...writePass.restores[].verification` | Final restoration verification, separate from the legacy command `outcome`: verification/read times, final `outcome`, `commandOutcome`, fresh-read result, original/expected/current name and name match, original-name restorability, raw original/current fields with match results, and reasons. A refused no-op can coexist with a verified matching final state. |
| `...slotComparisons[].isoShown` / `imageFormatShown` | The bank's ISO (short text, as typed: `125`, `1600`, `Auto`) and image format (`jpeg` / `heif` / `notChecked`) as the tester read them off the camera's menu, on the read-pass comparison and on a trial's post-restart `menuComparison`. Neither is among the 23 bank properties, and both decide whether a Dynamic Range, D-Range Priority or Clarity refusal is a gate or a finding. Absent means not recorded, never base ISO or JPEG. |
| `...writePass.trials[].preparation` / `preparationConfirmedAt` | `setForTest` when the tester says they set the write slot's ISO to 800 or higher and its image format to JPEG before the push, `leftUnchanged` when they chose not to, and when they answered. The tester's statement, not USB-detected state. After `leftUnchanged`, a refused DR200 or D-Range Priority write is the expected ISO gate, not a finding about the encoding. Absent means the question wasn't asked (a session from before it existed). |
| `...writePass.autoUpdateCustomSetting` | `enable` / `disable` / `notInMenu` / `notChecked`: AUTO UPDATE CUSTOM SETTING as the tester read it at the recheck step. Camera-wide, so once per session. The record's persistence results are conditional on this state, so read each trial's `persistence` against it. Absent means not recorded. |

### Reading provenance and coverage

The report is assembled across operations and reconnects. `generatedAt` is the start of the latest
collection, not the start of the Camera Test. `guidedTests[].startedAt` identifies the test; each
retained phase has its own timestamp. Top-level `slots.readAt` dates the **latest camera state**,
which may be after restoration. Use `initialSlots` and the trial's `persistence` for the original
and restart readings rather than interpreting that latest slot snapshot as every phase at once.

The trace covers recorded operations on the latest connection. `transactionsDropped` counts only
entries omitted by that connection's bounded recorder; zero does **not** establish a complete
whole-test trace. Earlier push, develop and guided-session records can survive reconnects without
their original transactions. The readable report states this explicitly. `camera.verification`
is pre-existing registry evidence about write support, not a compatibility verdict awarded by the
current run.

Each session's readable coverage lists menu comparisons, slot-write trials and RAW-develop runs
separately. Authored/supplied setting names come from retained recipe snapshots, including explicit
Off/zero settings; they are not inferred from current camera defaults or the model registry. The
operation outcome, persistence result and conversion profile evidence determine how to interpret
that list. A successful CT Colour develop is evidence for that conversion path, not a CT Colour
slot write. Completion of the selected test does not certify untouched settings or unrun cases.

Guided report snapshots include only timestamp-filtered camera/Kitchen log entries from the
current app launch's bounded buffer, between test start and capture. Full ISO timestamps avoid
confusing activity across midnight. The section discloses that events are associated by time and
not individually identified to a camera, and that earlier buffered or previous-launch activity
may be absent. Existing frozen snapshots retain their original log context. Standalone support
reports keep their broader diagnostic behavior.

The legacy `persisted` Boolean remains for decoding existing reports. No accepted recipe fields
means settings persistence was not tested; a failed fresh read means it could not be verified.
Partial writes can still produce evidence about accepted fields. Refused fields remain refused,
and neither case is a vacuous passing persistence check.

The session stores a **frozen report snapshot** with its capture time, diagnostic text, camera JSON
and summary. A later share/retry uses that snapshot instead of whichever camera most recently
connected. At export, the session's current note is projected into that session's JSON and shown once
in the readable note section; its duplicate is omitted from the technical text. Other sessions'
notes and the frozen camera evidence stay unchanged. Snapshot contents describe capture-time evidence, so a
handoff occurring afterward is recorded locally and cannot appear retroactively inside its own
already-shared attachment.

**Share Test Results** hands the share sheet two files: `fuji-cookbook-test-results-<model>-<yyyyMMdd-HHmm>.txt`
(the readable results — summary, the user's note, technical evidence) and
`fuji-cookbook-camera-report-<model>-<yyyyMMdd-HHmm>.json` (this document). Clear Diagnostics'
export-before-clear writes one `fuji-cookbook-recovery-<sessionID>.json` per recovery record, each
loadable by Restore a Slot.

Recovery records are stored separately under `<App Group>/Reports/camera-test-recovery/`. Their
original backup is immutable, bound to the physical body and session, and retained separately from
bounded diagnostic/session history. Per-slot disposition records distinguish restored, kept,
originally empty, and unresolved changes. Restoring multiple trials uses the original baseline,
not the previous trial's `slotBefore`. Clear Diagnostics explicitly describes deletion of these
records and permits backup export first; deleting them leaves recovery unavailable. A backup
already exported elsewhere is separate.

No photos, selected file names, file paths, automatic upload or new report server are introduced.
A successful Develop establishes only that case; omitted Test Kitchen or DR cases remain untested.

## What it contains — and what it deliberately doesn't

The tester's **custom-slot contents** (seven banks on most bodies, six on a PSAM-dial GFX, four on the X-S10/X-S20/X-M5 — their recipes, as raw property bytes), a **hashed** camera
serial, the iOS version and hardware identifier — and, since v4, **the answers a tester typed into a
guided Camera Test**: whether the app named the right body, which settings they marked as differing
from the camera's own menu and what the camera showed instead, the bank's ISO and image format as
they read them off that menu, whether they prepared the write slot, the AUTO UPDATE CUSTOM SETTING
state, whether a developed photo or a pushed recipe looked right, and any note they wrote. The user reads it on screen and sends it by their own
action, as part of the app's only reporting channel of any kind. It leaves as the JSON attached to
Report a Problem or the Camera Test results, beside a text report that carries its readable
rendering (`textRendering`). Those screens (`DiagnosticsReportView`) show the JSON verbatim, the
same bytes that leave, under a collapsed **Camera Data (JSON)** section with its own Copy button;
the rendering is no substitute, because it leaves out a few encoded fields. The serial itself never
appears: `camera.serialHash` is an HMAC of the serial under a key that never leaves the phone,
truncated, enough to tell two reports of one body from one phone apart. Photos and file names are
not in it and have no field to land in.

`develops[]` holds no photo and no file name, and this is enforced by shape rather than by care:
`CookEvidence` is a separate, narrower type from `ConversionResult`, which carries `sourceFilename`,
an `errorMessage` that interpolates it, and a byte-level `diagnostics` dump — none of which have a
field to land in here. `CookRecordTests.testTheRafFilenameNeverReachesTheReport` pins it.

**The hash's exact shape, and what it does and doesn't buy** (`SerialHash.swift`): HMAC-SHA256 over
the UTF-8 of the serial, keyed with a random 256-bit secret generated on the phone the first time a
camera connects, truncated to the first **8 bytes** and rendered as 16 lowercase hex characters.
`camera.serialHashScheme` is `hmac-sha256` beside it, and the text rendering adds "(keyed to this
phone)".

The key is a Keychain item of its own (account `camera.serialHashKey`), stored `ThisDeviceOnly`:
never synced, never restored to another phone, and never in a report, a log or an export. Fujifilm
serials are short enough to enumerate, so the key is the whole protection: without it a guessed serial
can't be checked against a hash, which is what makes a report safe to post in a public issue. The cost
is that the hash is stable for one body **on one phone**; two phones give the same body different
hashes, so two testers' reports can't be matched by hash. Every comparison the app makes stays on one
phone — carrying push history, guided tests, the sweep, harvests and develops forward from the last
report about the same body, the drift check against Clear Diagnostics' baseline, Camera Test resume,
recovery matching — so none of them needs more. The value is still **pseudonymous, not anonymous**:
every report one phone makes about one body carries it. The launch cleanup of retired AI keys leaves it alone; erasing
it would make every camera the app has met look like a stranger. When the Keychain can't produce the
key, the report records no hash, with a `notes[]` line saying why, rather than a weaker one, and the
body is matched by name and USB identity like one that refuses `GetDeviceInfo`.

**A hash with no `serialHashScheme` is unkeyed**, from a build before the key: SHA-256 over the
UTF-8 of `"fuji-cookbook-serial:" + serial`, same truncation. That salt is compiled into every copy of
the app, so anyone holding such a hash can recover the serial by enumeration; treat one in a report
already received as you would the serial. Stored copies are still on testers' phones (the latest
report and its Clear Diagnostics baseline, Camera Test sessions, recovery copies), so
`SerialHash.legacy` survives for one purpose. When a body connects, its legacy hash is computed in
memory, and `SerialHash.same` recognizes a stored record carrying it as that body; the record is then
rewritten with the keyed hash, except a recovery copy, whose backup is never rewritten and keeps
matching this way. An unkeyed hash never leaves the device: `DiagnosticsReportSnapshot.Export` drops it
from the JSON (`forSharing`) and drops its line from the text, including text frozen into a Camera Test
saved before the upgrade. A camera backup records `camera.serialHashScheme` the same way, and every
backup export, the recovery copies Clear Diagnostics offers included, drops a hash without one
(`CameraBackup.forSharing`); the recovery record on the phone keeps it to find its camera.

## Fields

| Field | What it is for |
|---|---|
| `reportVersion` | Shape version, bumped when fields are added or a field changes meaning. Every change so far is additive. |
| `generatedAt`, `updatedAt` | When the session opened; when the last stage wrote. ISO 8601. |
| `app` | `version`, `build`, `channel` (`debug` / `local` / `testflight` / `app_store`). |
| `host` | `systemVersion`, `deviceIdentifier` (`iPhone16,1`). |
| `camera.productName` | What ImageCaptureCore called the device — the string identification runs on. |
| `camera.transport` | `usb` or `demo`. Demo reports are for exercising the format, never evidence. |
| `camera.usbVendorID` / `usbProductID` | From enumeration. The identity that doesn't depend on the name string. |
| `camera.identifiedModelID` / `identification` | The registry entry and how the name resolved to it: `exact`, `alias(<name>)`, `heuristic(<id>)` — a word-boundary guess — `unlisted` — no entry, named by `GetDeviceInfo` — or `unknown`. See `docs/camera-identification.md`. |
| `camera.firmwareVersion` | From `GetDeviceInfo.deviceVersion`; the transport has no other source. |
| `camera.serialHash` | See above. |
| `camera.serialHashScheme` | `hmac-sha256` beside a keyed hash. Absent beside an unkeyed one, which only an earlier build's report carries; see above. |
| `camera.writeAccess` | *v7.* What the app decided about writing to this body: `undecided` (the slot read hasn't finished), `granted(trusted-entry(<verification>), <stage>)` for a body the registry vouches for, `granted(walk, <stage>)` for one granted by what it answered, or `refused(<reason>)`: `blocked-by-record`, `no-identity`, `no-bank-block`, `selector-unreadable`, `walk-failed`, `select-ignored(C<n>)`, `no-banks`, `selector-not-restored`. A trusted entry at `hardware` or `owner-report` starts `verified`; every other grant starts `unverified` and moves to `verified` when a push is read back on the body (`StagedWrite`). The text rendering prints this as its `Writes` line. See `docs/camera-identification.md`. |
| `deviceInfo` | The parsed DeviceInfo dataset: PTP version, vendor extension, `operationsSupported` and `devicePropertiesSupported` as `{code, name}` with names for every code the app knows, events and formats as codes, `rawLength`. `error` set instead when the body refused it. Advertisement is diagnostic context; actual selector/name reads and operations establish the tested slot path, since unadvertised properties can answer. |
| `slots.readAt` | *v2.* When these reads were taken. **Load-bearing:** `push` ends by calling `SlotReader.refresh()`, so on a report carrying a push this section is the camera *after* it while `transactions` and `pushes[].slotBefore` are from before. `readAt` at or after the last `pushes[].at` means you are looking at the post-push state. |
| `slots.assumedSlotCount` | What the registry says, or the provisional model's seven for an unlisted body. Nil for a body with no identity. Usually 7, which is an assumption rather than a measurement; the GFX100S carries 6, a measurement ([*How many banks*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/04-custom-slots.md#how-many-banks)). A report where `probedSlotCount` is lower than this is the assumption being corrected, not a fault. |
| `slots.probedSlotCount` | How many consecutive slots accepted a select. The scan stops at the first refusal; that operational boundary does not by itself establish the cause or the menu bank count. Nil when the body took the read-only sweep — selecting a slot is a write. |
| `slots.selectorBeforeProbe` | The selector's value on arrival (the sweep reads it; the slot read overwrites it). `0xD18C` is a host-side cursor, not the bank the camera shoots with ([*Custom-setting banks*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/04-custom-slots.md)). |
| `slots.selectorBeforeRead` / `selectorRestored` | *v5.* The selector's value when the slot read began, and whether the read put it back: `true` written and read back, `false` refused or read back as something else, nil when there was nothing to restore. |
| `slots.selectorRead` | *v7.* What the selector answered to the read that opens the slot read: `C<n>`, `unsupported (0x200A)` — no bank block in this context — `failed: <detail>`, or `not read`. |
| `slots.walkResult` | *v7.* How the slot read ended: `swept read-only`, `finished: <n> banks, all read` (or `a bank did not answer every property`), `stopped: select of C<n> answered OK and did not take`, `failed: <detail>`, or `not walked`. |
| `slots.documentedSlotCount` | *v5.* What Fujifilm's manual says the body has, where the registry has a manual entry; rendered as "documented N". Read beside `probedSlotCount`. |
| `slots.registryDisagreements[]` | *v7.* Where the body's answers disagree with its registry entry, as `field`, `registry`, `observed`: the slot protocol the entry expects against what the selector answered; the assumed and documented bank counts against the count probed. Absent when nothing disagrees, and for an unlisted body, which has no entry. These are what promote or correct an entry. |
| `slots.reads[]` | Per slot: `selected` (+ `selectError`), `name`, `occupied`, and `properties[]` — every preset property with `value` (hex), `decoded` (int16 when two bytes), or `error` + `responseCode`. |
| `propertySweep` | The read-only sweep (`readOnly: true`, nothing written: a body with no identity, one the registry blocks, or one whose selector didn't answer) or the diagnostic Property Report (`readOnly: false`, one slot select). Per property, in `propertySweep.entries[]`: value, and the `GetDevicePropDesc` descriptor — data type, writability, default, current, and the accepted `enumeration` or `range` — or the refusal. |
| `unsupportedPropertyCodes` | Every code that answered `0x200A DeviceProp Not Supported` anywhere in the session. |
| `transactions[]` | The bounded PTP trace for recorded operations on the latest connection: `sequence`, `operation`, `operationName`, `parameters`, `outDataLength`, `outData` (first 16 bytes, hex, only when small: a select or a property value, never an upload), `inDataLength`, `inData` (first 64 bytes, hex; never for object transfers), `response`, `responseName` or transport `error`, `durationMs`. The current cap is 1200 entries; `transactionsDropped` counts additional recorded entries from this connection only, not earlier connections or untraced operations. |
| `notes[]` | Recorded observations and app-generated interpretations (for example a slot-refusal note). Interpretations require evidence beyond the refusal code. Since v2 this includes `drift:` lines — a slot whose film simulation no longer matches what the last applied push wrote to it, found on connect by comparing `pushes[].fields[D192].wrote` against the fresh `slots.reads`. The stored comparison does not identify what caused the change; the dial is one possible influence on a dial body. Also `C<n>: D18E refused 0x201C with the recipe written — the bank has a setting that fixes Image Size …`, written when a push matched the app heuristic `SlotWriteResult.imageSizeFixedByBank`; the label is an app heuristic, not proof of the cause. Also `C<n>: … withheld` — properties `FujiPresetCodec.unwritableProperties` does not send to this body. A recurring observation or hint — a refused slot select, a withheld property, the D18E bank-lock hint — appears once however many slot walks found it (`noteOnce`). An **event** — a write probe's summary, a drift line — appears each time it happened. |
| `camera.verification` | *v2.* `hardware` / `owner-report` / `community` / `inferred` — how firmly this body's **write** path was known when the report was captured. Only the X-T50 is `hardware` — the body the maintainers can re-test on demand — besides the Demo Camera, whose reports are never evidence. The GFX100S (2026-09-15) and the X-M5 (2026-10-31) are `owner-report`, each after its owner's full write pass. `community` also includes published records with raw values, such as X-H2/X-T5 and GFX100RF reports; it does not mean that no upstream write was tested. `inferred` records the registry’s compatibility inference. These app labels are distinct from the reference’s evidence tags, and a report retains the classification at collection time. |
| `slots.reads[].divergences[]` | *v2.* Values the slot returned that `FujiPresetCodec` could not account for: `code`, `name`, `field`, `value` (hex), `decoded`, `kind`, `expectedRange`. `kind` is `unrecognized` — no entry in the app's table, and **the recipe field was left unset rather than guessed** — `outOfRange`, meaning it decoded but fell outside the model's own range and was *kept anyway*, or `cameraOnly`, a value only the camera can author (a Custom white balance), recognized and left out of the recipe. Absent when nothing diverged. |
| `pushes[].firstWrite` | *v7.* The staged first write of a push to a body no push had been read back on (`StagedWrite`): `property` (hex), `outcome` (`written`, `invalid-value`, `refused`, `mismatched`, `unknown`), the camera's `responseCode` on a refusal, what the read-back answered (`read`) on a mismatch, and how the property was put back after a stop (`restore`: `unchanged`, `restored`, `restore-refused <code>`, `restore-mismatch`, `restore-unknown`). Absent on an unstaged push. |
| `pushes[]` | *v2.* What each push did, capped at 20 (`pushesDropped` counts the rest). Per push: `at`, `slot`, `modelID`, `firmwareVersion`, `outcome` (`SlotOutcome`), `nameWritten`/`nameApplied`/`nameOutcome`, `clampedFields`, `errorMessage`, and `fields[]` — every property with `isRecipeField`, `outcome` (`written` / `rejected` / `notAttempted` / `mismatched` / `unverified` / `outcome_unknown`), the camera's `responseCode` where it gave one, and `wrote`/`read` hex for a mismatch. **Carried forward across a reconnect to the same body** (`adoptPushHistory`), because the file holds only the newest report, and a user who pushed, unplugged and plugged back in would otherwise lose the record of what the camera refused. Appended before the first write and finished in place when the push returns, so a push that is cut off keeps its `slotBefore` (see *Lifecycle*). |
| `pushes[].nameBefore` | *v4.* The slot's name before this push. `slotBefore` covers the bank settings D18E–D1A4; historical snapshots could also contain live D1A5 — `FujiPTP.PresetProp` has no case for D18D — so without this, Undo Last Push would put every setting back under the name the push left behind. `undoName(forSlot:)` is the one rule for every undo: the recorded name, or "C*n*" for a slot that had none, as an app fallback rather than exact restoration of an absent name. Rendered on the push's `name:` line as `(was "…")`. |
| `pushes[].slotWasEmpty` | *v4.* A historical app classification retained for decoding and undo decisions. It does not prove an erased camera bank: missing or failed reads cannot establish emptiness. Current hardware writes require readable originals and do not seed missing settings. No tested USB clear-bank operation is established here; menu ERASE is a separate capability, so legacy empty-bank records do not authorize reconstructing that state. |
| `pushes[].fields[].wrote` | *v2.* The bytes the push intended for that property, hex, **for every outcome**. "What did D192 get" is the question a film-simulation complaint asks, and `written` alone carries no value to answer it. This is also what the reconnect drift check compares against (see `notes[]` entries prefixed `drift:`). |
| `pushes[].selectorReadBack` | *v2.* What `0xD18C` reported **after** the push selected it. Equal to `slot` on a healthy push; the text rendering stays quiet unless it disagrees, in which case that line is the most important one in the report. The select decides where every other write lands, so a body answering OK and staying put would produce a fully self-consistent, fully wrong-slot push. |
| `develops[]` | *v3.* What each in-camera develop did, capped at 20 (`developsDropped` counts the rest). Per cook: `at`, `modelID`, `firmwareVersion`, `succeeded`, `filmSimulation`, `profileLength` (a length the record's [*Lengths seen*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/06-conversion-profile.md#lengths-seen) doesn't list is a finding on its own), `declaredParams`, `layoutBase` (absent when `resolveLayout` refused the blob, which is the abort that stops an unfamiliar body before a byte is written), `profileVerified` + `mismatches`, `profileVerification`, `dynamicRange`, `fullResolution`, `clampedFields`, `outputBytes`, `outputValidation`, `cleanupOutcome` (`retained` when the output stayed on the camera), and a coarse `failureReason`. Carried across a reconnect (`adoptDevelops`). |
| `profileHarvests[]` | *v5.* The first half of a develop on a body the app does **not** develop on — one RAF uploaded, `0xD185` read, nothing after — capped at 20. Per harvest: `at`, `modelID`, `firmwareVersion`, `rafBytes` (no filename, ever), `profileBeforeUpload` (the refusal a plain sweep also sees), `uploadOutcome` (`accepted` or the code, nothing else; an upload `0x2002` is filed as `upload_general_error`, with no cause), `rafHeader` (what the file's own header says: `names this body`, or `names X-T5, not this GFX100`; absent when the file has no readable header), `uploadCreatedObject` / `objectDeleted` / `profileAfterDelete` (whether handle enumeration found a new object, whether it was deleted, and what the profile read answered after), `profileLength`, `declaredParams`, `layoutBase` (absent = `resolveLayout` refused it, the whole finding), `layoutDiagnostic`, `profileHead` (first 64 bytes, hex), `profileReadError` (refused *after* a good upload — a different finding), `failureReason`, and `profileHarvestsDropped` beyond the cap. A harvest does not by itself verify a complete conversion. Carried across a reconnect like `pushes[]`. |
| `develops[].dynamicRange` | *v3.* How the app resolved requested DR against the as-shot profile: `applied`, `untouched`, `cappedToAsShot(400->200)`, `autoResolved(200, asShot 400)`. The cap is an app precaution based on higher-DR green casts in tested X-T50 cases. The field records an adjustment, not a universal rendering rule or proof of the output’s DR. |
| `connectionFailures[]` | *v3.* Connect attempts that never reached a session, capped at 10. Per attempt: `at`, `stage` (`discovery` / `open`), a `reason` already passed through `AppLog.bounded`, the device identity when there was one, and — the reason the section exists — `controlAuthorization` / `contentsAuthorization`, the two ImageCaptureCore grants as words. That pair is what separates "wrong cable or wrong USB mode" from "the permission never took" (see `CameraDeviceBrowser.ensureAuthorized()`), a distinction a user can't make for themselves. Everything else in this document is created inside `connect` *once the session opens*, so without this section the most common connection failure would leave no report at all. |
| `pushes[].kind` | *v3.* `restore` when the write put a slot back from a saved copy, absent for an ordinary push. Two writes to one slot otherwise look alike in the record, and telling the accident from the repair is the first thing a reader needs. |
| `pushes[].slotBefore` | *v2.* Every property the destination slot held immediately before this push, property code to hex. `push` already reads it — it needs the slot's current bytes to build a patch that preserves fields the app doesn't edit — so recording it is nearly free and makes the one slot a push can damage recoverable from the report the user sends. Recorded before the first write, so a push cut off part-way keeps it; absent when the push failed before that read, which is also when nothing was written. |
| `guidedTests[]` | *v4; extended in v6.* What each guided Camera Test observed, capped at 5 and keyed by `sessionID`. Legacy records use `wave` (1 reading, 2 writing); v6 continuous records carry `plan`. `transport`, `outcome` (`inProgress` / `completed` / `sentEarly` / `abandoned`), `outcomeStep`, and `stepsCompleted` retain their original meanings. Finished navigation is not a passing check and `sentEarly` is not proof of delivery. See the v6 table above. |
| `guidedTests[].identity` | *v4.* What the app showed the user — product name, resolved model, confidence, the capability seal verbatim — and whether they confirmed it. A body resolved to the wrong registry entry reads and writes a field set that isn't its own and says nothing about having guessed; **this is the only field that catches it**, and a `confirmed: false` invalidates every other line in the report. |
| `guidedTests[].slotComparisons[]` | *v4.* **The user's comparison against the camera's own menu.** Per slot: `verdict` (`matches` / `differs` / `unverified` when the app couldn't read a field / `notChecked`, derived from the rows and never typed), `checkedAt`, `fieldsAppCouldNotRead`, and `rows[]` — every setting the app *displayed*, snapshotted, with `differs` and the free-text `cameraShows`. A snapshot rather than a reference into `slots.reads` because a push or a reconnect rewrites that section, and this has to keep meaning what it meant when the person was looking at the screen. Read-back verification proves bytes round-tripped; it cannot prove they mean what `FujiPresetCodec` says, so a `differs` row is the most actionable thing a new body can produce. Since v6 the comparison also carries `isoShown` and `imageFormatShown`, the two bank conditions the tester can read and the app can't; see the v6 table. `checkedAt` is rendered into the text block as well as the JSON, because it is the only thing separating a careful read-through from three slots confirmed four seconds apart — a `matches` costs one tap, and without the timestamp the two are the same line. |
| `guidedTests[].propertyReport` → `propertySweep` | *v4 legacy.* The record stored only `slot`, `count` and `readOnly`, referring to the single top-level sweep, which later work could replace. Legacy rendering warns when that sweep is missing or belongs to a different slot. New v6 sessions retain their own `propertySweep` with capture time and evidence identity; missing legacy timestamps/identity must not be invented. |
| `guidedTests[].propertyReport` / `.grainProbe` | *v4.* `state` is `ran` / `skipped` / `notWritable` / `refused` / `failed` / `notRun`. The distinctions matter: `skipped` is a user declining (legacy only — since v6 the check is required before any recipe write, and declining leaves the step in place), `notWritable` is a body this app doesn't write to (so the probe was never offered), and `refused` is another camera operation having been in flight — retryable, and not a fact about the body. `readOnly: true` on the sweep means it ran without selecting a slot, which is a strictly weaker diagnostic. |
| `guidedTests[].develop` / `.profileHarvest` | *v4, v5.* Whether the Camera Test's develop and harvest steps ran, were skipped or were refused, in the tester's own session; the develop's `jpegMatchesRecipe` (`yes` / `no` / `notChecked`) is the tester's look at the JPEG. The full records are `develops[]` and `profileHarvests[]`. |
| `guidedTests[].freeText` / `updatedAt` | *v4.* The tester's own note, and when the record last changed. |
| `guidedTests[].noCamera` | *v4.* The failed-detect branch, all typed by the user: model as printed, firmware from the camera's own menu, the exact USB-mode wording, the cable, which permission prompts appeared, and what the app said. `connectionFailures[]` has the machine half; on its own it cannot separate a charge-only cable from the wrong USB mode. |
| `guidedTests[].writePass` | *v4.* `consentAt`, the `backup` (saved when and through which activity; `skipped: true` appears only in legacy records — since v6 the original is an automatic recovery copy that cannot be skipped, and `recoveryBaselineID` names it), `dialConfirmed` on a dial body, `trials[]` and `restores[]`. Since v6 also `autoUpdateCustomSetting`, and each trial's `preparation`; see the v6 table. |
| `guidedTests[].writePass.trials[].persistence` | *v4.* **Whether the recipe was still there after the camera was switched off and on.** `persisted`, and per lost setting a `differences[]` entry with `wrote` and `holds`. The failure this exists for reports success, reads back correctly, and is quietly gone on the next power-up — nothing the app does during a push can see it. Compared with the push path's own `readBackMatches`, so D195 grain is judged by decoded meaning rather than bytes; a byte comparison would report every Off-grain recipe as lost. |
| `guidedTests[].writePass.trials[].photoMatchesRecipe` | *v4.* `yes` / `no` / `notChecked`. The user's observation of the photo, separate from storage verification. A plausible-looking photo does not prove every recipe parameter was used correctly. |

## Reading one

`textRendering` is the quickest way. Four things to know before you read numbers off it:

- **A Property Report needs Show Diagnostic Tools.** The button only exists with it enabled, and the
  problem report's header says which (`Diagnostics off`). On legacy (pre-v6) reports, someone who couldn't
  find the button may have run the guided Camera Test instead, whose slot comparison ended at
  `compareSlots` when they unplugged to check the menu — `guidedTests[].outcome: sentEarly` there
  means its own property step never ran either. A v6 continuous test runs the sweep automatically on
  the read step, before the comparison, and Share Progress doesn't set `sentEarly`.
- **Date the `propertySweep` before you trust it — the header does not.** `app.build` names the
  build that *exported* the report, not the one that captured its sweep. There is only ever one
  sweep and a reconnect carries it forward (see Lifecycle), so a report can carry a sweep from an
  earlier session and an earlier app version while looking current, and a session that never ran
  the Property Report can look as though it had. Read `propertySweep.capturedAt` where it is
  present. Otherwise check whether the sweep reads `0x500F` (older sweeps don't) and whether `0xD191`
  is named "D-Range Priority" (older sweeps say "Unknown D191"), and look for the
  `Property report: C<n> — N of M values read` line **inside the launch you care about** — the log is
  split by launch and the section headers matter.

- **Every date is truncated to the whole second** at the source, so the JSON decodes back to exactly
  what was written and the document is equal to itself across a save/load.
- **`value` is raw byte order; `decoded` is signed 16-bit.** For the properties Fuji stores as bit
  patterns those are both misleading — an Auto-White-Priority white balance is `0x8020`, which shows
  as bytes `2080` and decoded `-32736`. The text rendering therefore prints `(u16 0x8020)` instead of
  the signed reading whenever it is `<= -1000`; no tone, shift or colour temperature comes near that,
  so ordinary negatives are untouched.

In the JSON, the order to look at for a new body:

0. **`guidedTests[]`, if there is one.** It is what a person saw, and it is the only section that can
   *contradict* the rest of the document. `identity.confirmed: false` means every other line is about
   the wrong body. A `slotComparisons[].rows[].differs` usually means the app read a value and
   misunderstood it — which nothing below can detect, because every automatic check agrees with the
   misreading. **The one known exception is D-Range Priority**, where the app and the camera can
   both be right: a bank can store a priority the menu shows as OFF at base ISO, so a bank holding
   Auto shows as a mismatch ([*The D-Range Priority interlock*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/04-custom-slots.md#the-d-range-priority-interlock)).
   Check the bank's ISO before filing that one as a decode bug: the comparison's `isoShown` holds it
   when the tester noted it, and nothing else in the report can on a body that doesn't answer
   `0x500F`. See [Dynamic Range and D-Range Priority](fuji-recipe-ptp-protocol.md#dynamic-range-and-d-range-priority).
   A legacy `writePass.trials[].persistence.persisted: false` does not distinguish a changed value
   from failed or missing verification. Prefer the v6 evidence states and retained readbacks.
1. **`propertySweep.entries[]` — did `0xD18C` *answer*?** Not "is it in
   `deviceInfo.devicePropertiesSupported`": a body can omit it from its advertised list and answer
   it, and two bodies advertising the same count can answer differently
   ([*The advertised lists are not complete*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/01-transport.md#the-advertised-lists-are-not-complete)).
   The advertised list is corroboration — check it second, and when the two disagree, say so in the
   entry's comment, because a disagreement is a finding about Fujifilm's firmware rather than a
   thing to resolve. A sweep where `0xD18C` is genuinely refused **and** the advertised list omits
   it is the whole finding; either one alone is not.
2. **`slots.reads[].divergences`** — values this body returned that the app's tables don't contain. Ahead
   of `unsupportedPropertyCodes` deliberately: a missing property is loud (the app says the field
   wasn't read), a divergence is not. An `unrecognized` divergence means the returned value is outside the app's
   table. Preserve it for investigation; it may reflect a new enum, inactive value, state or
   parsing issue rather than a different encoding.
3. `unsupportedPropertyCodes` — which tested properties did not answer. The current bank settings
   are 23 codes, `0xD18E`–`0xD1A4`; historical sweeps also included live Image Size `0xD1A5`.
4. `slots.probedSlotCount` against `assumedSlotCount` and `documentedSlotCount`. Lower is the
   registry's assumption being corrected. And if a sweep ran **without** selecting a slot
   (`propertySweep.readOnly: true`), remember what it read: whatever bank the selector was left on,
   which may be one the app cannot select.
5. `propertySweep.entries[].descriptor` — the values it will accept, against `FujiEncoding`'s assumptions.
6. `pushes[].fields` — when the report came with a push complaint. `rejected` with a `responseCode`
   is the body refusing a value; `mismatched` is the more dangerous case, where it accepted the
   write and kept something else. `slotBefore` on the same record is what the slot held first, if
   the slot needs putting back.

   `0xD190` and `0xD191` refusals can be gated by the bank's ISO
   ([*ISO gating*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/04-custom-slots.md#iso-gating)). The ISO is not among the 23 bank
   settings, so neither refusal is predictable from the report: read `slotBefore` for the D191 the
   bank had, then the trial's `preparation` and its `menuComparison.isoShown` for the ISO, and ask
   the user only when neither was recorded. Identical bytes refused on one bank and accepted on
   another point at the bank's ISO first, but don't prove it. Every sweep reads `0x500F`
   ExposureIndex, the standard PTP property for the ISO, so look for it in `propertySweep.entries[]`
   before asking; on a body that answers it `0x200A`, such as the X-T50, the refusal is the only
   signal.
7. `profileHarvests[]` — on any body the app doesn't develop on, and **before** `develops[]`,
   because there won't be one. Three readings: `layoutBase` present is the evidence to enable
   conversion for that body; `profileLength` present and `layoutBase` absent is a new profile
   shape, and `profileHead` is what to look at; `uploadOutcome: accepted` with `profileReadError`
   set is a body that took the file and refused to describe it — the `0xD183` descriptor was a red
   herring there. The app files an upload `0x2002` as `upload_general_error` with no cause. It
   files a `0x2002` on the profile read after an accepted upload as `raf_from_different_body`
   when the file's header doesn't name the body: the published cause, not a diagnosis the code
   establishes, so preserve the operation and inputs.
8. `develops[]` — when the complaint is about a developed JPEG. `layoutBase` absent is the whole
   finding; `profileVerified: false` means the camera never confirmed the recipe, which is
   indistinguishable from a recipe that just looks bad; `dynamicRange` explains most of the rest.
9. `connectionFailures[]` — when the complaint is that nothing connected. Read the two
   authorization words before anything else.
10. `transactions` — only when something above doesn't add up.

## Reference bodies

A new body's report is read against the bodies the record knows best: the
[X-T50](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/07-cameras.md#x-t50), the maintainers' body, and the owner-reported
[GFX100S](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/07-cameras.md#gfx100s) and [X-T20](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/07-cameras.md#x-t20). Their
`GetDeviceInfo` datasets, how their banks read and take a write, what their conversion profiles look
like, and the dated observations behind each are recorded there, with the evidence; this document
does not restate them. Read a report the way the order above sets out: which tested codes answer,
whether `0xD18C` answers rather than whether it is advertised, and what the descriptors say where
the X-T50 refuses `GetDevicePropDesc`.

Two app behaviours rest on what the X-T50 has shown:

- **`D18E` refused with `0x201C` on a slot whose every other property writes is reported as a hint,
  not a refusal.** Image Size is forced per bank by settings the 23 properties don't carry
  ([*Why a write is refused*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/04-custom-slots.md#why-a-write-is-refused)), so the push
  says the bank likely has a setting that fixes Image Size (`SlotWriteResult.imageSizeFixedByBank`).
  Image Size isn't a recipe field, the slot keeps what it had, and the push reports `applied`.
- **A slot's film simulation can change with the app disconnected**, through the bank's working copy
  ([*Custom-setting banks*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/04-custom-slots.md)). The drift check
  (`notes[] drift:`) can name it only while the report remembers what the app last wrote, which is
  why Clear Diagnostics strips the report to a baseline rather than deleting it —
  `stripToDriftBaseline()`: camera identity plus, per applied push, `slot`, `at`, `outcome`,
  `modelID`, `firmwareVersion` and the one `D192` field, marked `baselineOnly`. Slot contents,
  names, raw bytes, trace and device info go.

## Loading one into the mock

`MockCameraFaults` is the seam: `unsupportedReadCodes` from `unsupportedPropertyCodes`,
`maxSelectableSlot` from `probedSlotCount`, `productName` and `firmwareVersion` from `camera`, and —
since v2 — **`rawReadValues` from `slots.reads[].divergences`**, which is the only way to make the
mock answer a value the app's own encoder could not have produced. The test fixture
`.divergentWhiteBalance` (`FujiCookbookTests/MockCameraFaults+Fixtures.swift`) is a worked example.
Nothing loads a captured report into the mock automatically; the faults are set by hand in a test.

## Why there is no separate backup file

A push makes no backup file of its own. Most `.readWrite` bodies write on inference, so a push may
write encodings nobody has confirmed on that body — and what that costs is
the recipe the user already had in that slot. That is a real risk, but a separate file is the wrong
answer to it:

- The bytes are **already here**. `slots.reads[].properties[].value` is every slot's raw hex.
- Only the pushed slot is at risk. A push selects one slot and writes into it; the other banks are
  untouched, and are in `slots.reads[]` of this same document.
- What a file would add is **lifetime**, since this document is overwritten on the next connect.
  `pushes[]` gets that instead: `slotBefore` captures the slot that actually changed, and
  `adoptPushHistory` carries push records across reconnects. Same recovery data, no new artifact,
  nothing new to disclose.
- A separate file would cost a new store, a retention policy, a Clear Diagnostics branch, a second
  attachment, and its own paragraph in the privacy policy — five places to be wrong about the user's
  own creative work.

`SlotWriter.restore` writes one slot back. **Undo Last Push** restores from
`pushes[].slotBefore`, which needs no file at all because the bytes are already here. **Restore a
Slot** loads a `CameraBackup` file (`CameraBackup.swift`) the user exported, the durable case: it
lives where the user put it, for as long as they want it. The Camera Test's write pass also keeps a
recovery record of the original slot (see "Version 6" above), which its restore step uses and which
Clear Diagnostics offers to export as `fuji-cookbook-recovery-<sessionID>.json` files that Restore a
Slot can load.

Three things a reader of this document should know about restores:

- **Exact restoration needs a raw comparison.** Grain Off reads back as values the camera won't take
  as a write ([*Restoring a bank*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/04-custom-slots.md#restoring-a-bank)), so
  `encodeRestore` uses size-then-Off sequences on the X-T50 and GFX100S; the raw readback must match before claiming exact restoration. Other bodies use
  the semantic fallback and report its fidelity limits. A name fallback or an unresolved field
  likewise prevents claiming a lossless bank restore.
- **A restore uses the bank writer.** Same `performSlotWrite`, same select, name-first ordering and
  read-back. It carries the same risk on an unverified body, which is why it is offered one slot at
  a time — the same blast radius as the push it undoes.
- **Clear Diagnostics takes the undo away.** `stripToDriftBaseline()` drops `slotBefore`, and
  clearing deletes the recovery records, so the button a careful person presses right after sharing
  a report also removes their rollback point. The confirmation says so and offers to export the
  originals first; an exported file is the answer that survives it. Clearing also strips the
  *in-memory* report (`CompatibilityReportRecorder.clear()`), because
  `DiagnosticsReportView` prefers the live copy over the file, and stripping only the file would leave
  a connected session able to render everything the button promised to erase.
