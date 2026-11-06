# Fuji recipe PTP protocol — as the app uses it

How Fuji Cookbook talks to a Fujifilm camera over USB, and what the app decides about each quirk.
The protocol itself — the codes, the value encodings, how a bank behaves, the conversion profile's
layout, what each body does — is recorded once, in the protocol reference below. This document says
what *this app* does with it and why, and links to the reference for every fact.

The rule for what lives where: a fact that is true for any app belongs in the reference; a decision
this app makes, a function it runs or a screen it shows belongs here.

## Protocol reference

The app-neutral, evidence-tagged record is the [Fujifilm PTP reference](https://github.com/zgrimz/fujifilm-ptp-reference),
published as its own repository. The chapter links below use its `main` branch.

| Chapter | Covers |
|--|--|
| [Transport and session](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/01-transport.md) | USB mode, PTP framing, response codes, `GetDeviceInfo`, descriptors, timing |
| [Property reference](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/02-properties.md) | Every vendor property code seen, with type, access and meaning |
| [Value encodings](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/03-encodings.md) | How each bank setting is encoded on the wire |
| [Custom-setting banks](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/04-custom-slots.md) | Bank counts, the write sequence, refusals, ISO gating, D-Range Priority, restoring |
| [In-camera RAW conversion](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/05-raw-conversion.md) | Upload, trigger, completion, dynamic range, white balance |
| [The `0xD185` conversion profile](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/06-conversion-profile.md) | Layout, field table, host-write form, parsing safely |
| [Camera bodies](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/07-cameras.md) | What is known per body and how firmly; bank counts, firmware additions and menu controls from Fujifilm's manuals |
| [Methods](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/08-methods.md) | Menu sweeps, write probes, render checks, capturing X RAW Studio |
| [Platform notes](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/09-platform-notes.md) | ImageCaptureCore on iOS, iPadOS and macOS; WebUSB and other host stacks |
| [Reading recipe settings from a JPEG](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/10-jpeg-recipes.md) | Reading a recipe back from a JPEG's MakerNote: bounded parsing, decoding, unknown and missing values |
| [Implementing a recipe client](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/11-client-implementation.md) | Operation ownership, snapshots, partial failures, session lifecycle |
| [Corrections to published sources](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/errata.md), [Open questions](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/open-questions.md) | Where published sources disagree with hardware; what is still unknown |
| [Captures](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/captures/README.md) | Decoded X RAW Studio transcripts: a bank save, a conversion, an editor walk and Monochromatic Color toning on an X-T50, and bank availability on an X-T3 and X-T30; how to reproduce the public analysis |
| [Evidence index](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/evidence/README.md) | Original-record availability, source conflicts, closure criteria and the sanitized X-T50 packages |
| [Public evidence report](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/evidence/report-schema.md) | A portable, sanitized format for observations, with explicit verification states |
| [Tools](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/tools/README.md) | `ptpcap.py` and `verify_capture.py` for USB captures, `bankprobe.py` for sweeps and write tests on a body, `jpeg_recipe.py`, and the offline checks |

Its [`SOURCES.md`](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/SOURCES.md) says what each published project
contributed and under which licence. These are protocol facts and captures used for the app's own
implementation, not linked or bundled dependencies, so the app reproduces no third-party license
text. [ThirdPartyNotices.md](../FujiCookbook/Resources/ThirdPartyNotices.md) (Settings ▸ About ▸
Acknowledgments) credits the reference, names the projects it builds on most directly, and links
`SOURCES.md` for the rest.

How firmly the app's write path is known to work on a listed body is the registry's call
(`CameraModel.verification`, [camera identification](camera-identification.md)): the X-T50 is verified end to end on the
maintainers' hardware; the GFX100S from its owner's reports, a slot write that survived a power cycle
and a develop whose overall tone closely matches the owner-attributed camera conversion (not pixel identity; see `camera-compatibility-report.md`); the X-M5
from its owner's report, a slot write that survived a power cycle and matched the camera's menu
(fw 1.30, 2026-10-31); the X-H2, X-T5, GFX100RF and other `.community` entries on published
records; and the `.inferred` entries on inference from those bodies. An `.untested` entry, and a body
with no entry at all, is decided by what it answers at connect (see "What `GetDeviceInfo` can and
can't tell the app"), and every grant but a hardware or owner report starts at the `unverified`
stage until a push has been read back (`WritePermission.Stage`).

## Mechanism

The recipe surface is a **hybrid**:

- **Read a slot:** select it with `0xD18C`, then `GetDevicePropValue` on the name (`0xD18D`) and each
  of the 23 bank properties (`0xD18E`–`0xD1A4`).
- **Write a slot:** select it, write the name, then `SetDevicePropValue` on the individual preset
  properties in a required order, with conditional rules.
- **Develop a RAF:** upload it, then read, patch and write back the `0xD185` **profile blob**, a binary
  table parsed by cell index, and trigger the conversion with `0xD183`.

Slots are numbered 1–*n* for C1–C*n*: 7 on an X-T50, and **6 on a GFX100S**, which refuses a select
of 7 with `0x200A`. The count is per body. The app starts from the registry's `slotCount` and stops
at the first slot that refuses a select (`slots.probedSlotCount` in the report).

The codes the app sends are `FujiPTP.Operation`, `FujiPTP.Prop` and `FujiPTP.PresetProp`; what each means,
and the evidence, is in the reference's *Transport and session* and *Property reference*. Two choices
are the app's: it polls `GetObjectHandles` for conversion completion where X RAW Studio polls the
`0xD212` event list (both work on the X-T50; the reference's
[*Completion*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/05-raw-conversion.md#completion)
section has the event's limits), and every sweep reads `0x500F` ExposureIndex, the standard PTP ISO
property, which an X-T50 answers `0x200A`. On iOS the containers go through ImageCaptureCore's
`requestSendPTPCommand` (`ImageCaptureTransport`), confirmed on the X-T50.

**`0xD18C` is a cursor for the host, not the bank the camera shoots with.** In the documented tests,
writing it did not switch the shooting bank. A read can answer whatever the last host left there — kept across reconnects
and the body's own bank changes on an X-T50, reset by a bank change on a GFX100RF
([*Custom-setting banks*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/04-custom-slots.md)). So every operation
here selects before it reads or writes, and everything that walks the banks (the connect scan, the
Property Report, the grain probe) puts the selector back where it found it once the walk has run
(`SlotSelector` for the connect scan; `CameraDiagnostics` for the other two). A connect scan that
fails part-way leaves the selector where it stopped. What a read of the body's current bank returns is that bank's **working copy**:
a setting changed in the shooting menu and not saved shows up in the block. That is the likely cause
of a film simulation found changed in a bank nobody pushed to (`detectFilmSimulationDrift`).

## What `GetDeviceInfo` can and can't tell the app

The advertised property list is **not a complete capability test**. An X-T20 and a GFX100S
advertise the same 168 properties; the X-T20 refused every tested bank-block read with
`0x200A` in a session whose USB mode was unrecorded, while the GFX100S answered `0xD18C`, `0xD18D`
and all 23 bank settings in USB RAW CONV. mode. Neither advertisement nor property count establishes
operation support. Probe the intended operation in a recorded mode and state; a read alone does not establish writability
([*Transport and session*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/01-transport.md#the-advertised-lists-are-not-complete)).

So the app never decides what a body can do from its advertised lists, and reports them only as
corroboration. It uses `GetDeviceInfo` for identity instead: a body with no registry entry is
written to only when `GetDeviceInfo` names it with a product name, serial and firmware, and is
otherwise refused (`WriteRefusal.noIdentity`). The connect's slot read begins with a value read of
`0xD18C`. A body the registry lists as writable, identified by its exact name or an alias, is walked
on the registry's word, whatever that read answered. A body nothing names takes the read-only sweep,
and so does a body the registry blocks on a recorded failure (the X-T20, X-T3, X-T30 and X-Pro3; see
the record's [*Camera bodies*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/07-cameras.md)):
the sweep reads `0xD18C` without writing it and records what the body answers. Every other body,
listed or not, is walked when the selector answered a bank number and swept when it answered
`0x200A` or failed. A walk grants writing only when every selected bank answered every property
(`0x200A` aside) and the selector went back where it was (`WriteDecision`). The registry's
`CameraModel.supportsSlotProtocol` records what it expects of each body; the sweep notes a body that
answers against that expectation. The walk proves the bank path, and the first push proves writing:
on a body whose permission is `unverified`, the push writes one setting and reads it back before the
rest (`StagedWrite`), stopping and putting that setting back on any answer but a clean read-back or
an "invalid value" refusal. A push whose candidates (film simulation, then sharpness) already match
the bank runs unstaged, restores are never staged, and the `verified` stage a clean push earns lasts
until the next connection. That staging is this app's policy. The record's method for a new body
([*Methods*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/08-methods.md#minimum-evidence-for-a-new-body))
probes grain on a backed-up bank and verifies every write by read-back
([*Verifying a write*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/04-custom-slots.md#verifying-a-write));
the app follows the order and the read-back rule, and stages film simulation or sharpness because
their read-back compares byte for byte.

The app also uses the DeviceInfo shape as a USB-mode heuristic.
`FujiPTP.DeviceInfo.looksLikeStorageOnlyMode` stops a connect whose list is a handful of properties
with nothing in the vendor control range: a GFX100S in storage mode advertised four
([*Recognizing the wrong USB mode*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/01-transport.md#recognizing-the-wrong-usb-mode)).

The camera's own menu is unavailable while it is connected in this mode, so the Camera Test's
menu comparisons happen with the cable out, from snapshots taken while it was in
(`GuidedTestFlow.seedComparisons`).

## Writing a slot

### The name is the bank's name

In the final controlled X-T50 tests, property writes took effect at once, survived a bank change,
power cycling and RESET THE CHANGES, with or without a name write. AUTO UPDATE CUSTOM SETTING was
not recorded, and earlier conflicting runs remain unresolved
([*Custom-setting banks*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/04-custom-slots.md#writing-a-bank)). The
name write (`0xD18D`) sets the bank's name; those tests do not establish it as a commit command.
The app writes it first because that is the captured X RAW Studio order. Published name-last writes
also work, without establishing a persistence benefit for either order (see "After a push" below).

`SlotWriter.performSlotWrite` does this:

1. **Select** with `SetDevicePropValue(0xD18C, slot)`, and read `0xD18C` back. The select decides
   where every later write lands, and a body that answers OK and stays put would produce a
   self-consistent push into the wrong slot, so the push stops (`CameraError.slotSelectIgnored`).
2. **Read the slot** after a short settle: every preset property and the name. That is the base the
   patch preserves and the recovery copy (`pushes[].slotBefore` and `nameBefore` in the report). A
   property that answers `0x200A` is absent, as it is in the connect walk, and the push goes on with
   the properties the body has: an X100V's banks answer that to `0xD18E`, `0xD18F`, `0xD1A3` and
   `0xD1A4` ([*Response codes*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/01-transport.md#response-codes)),
   four properties the plan only ever passes through, and the result names them. Any other failed
   read stops the push before anything is written.
3. **Require recoverable originals** for every planned property change and, on a body with naming on, a complete original name. Missing or malformed reads stop the operation before changing the bank contents, and so does a planned write to a property the body answered `0x200A` to; the refusal says which of the two it was.
4. **On a staged first push, write the staged property and read it back** (see "What `GetDeviceInfo` can and can't tell the app"). A stop there puts the property back and ends the push before the name is written.
5. **Write the name and preset properties** in the order below, the name first when the body has naming on. A valid refusal is distinguished from a lost or malformed response; an uncertain send stops further writes.
6. **Read the name and every written property back.** Acceptance, final state, and unavailable verification remain separate observations.

Every `.readWrite` entry has naming on (`supportsSlotNaming`), as a product rule: a push names the
bank it writes, and `testNoWritableBodyHasSlotNamingOff` keeps the two together. The `.untested`
entries have naming off, so one that its walk lets write is pushed without a name write, and the
push confirmation says the body keeps its default slot labels; nothing about persistence rides on it.

### Write order

```
D18E ImageSize          D19A WBShiftR (after D19C)
D18F ImageQuality       D19B WBShiftB (after D19C)
D190 DynamicRange       D19C ColorTemp (conditional; right after D199)
D191 DRangePriority     D19D HighlightTone (×10)
D192 FilmSimulation     D19E ShadowTone (×10)
D193 Mono WC (cond.)    D19F Color (×10; non-mono only)
D194 Mono MG (cond.)    D1A0 Sharpness (×10)
D195 GrainEffect        D1A1 High ISO NR (lookup)
D196 ColorChrome        D1A2 Clarity (×10)
D197 ColorChromeFxBlue  D1A3 Lens Modulation Optimizer (carried through)
D198 SmoothSkin         D1A4 ColorSpace (carried through)
D199 WhiteBalance
```

This is X RAW Studio's order, captured saving a bank on an X-T50
([*Captures*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/captures/x-rawstudio-bank-save-xt50.md)). The app makes one
deliberate break from it: `FujiPresetCodec.encode` writes `D191` **before** `D190`. With D-Range
Priority on, the camera refuses `D190`, so a recipe that turns the priority off and sets a dynamic
range has to clear the priority first. The order also keeps the film simulation ahead of every tone
and colour property, which a published report says matters on a GFX100RF
([*The sequence*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/04-custom-slots.md#the-sequence)).

The captured X RAW Studio save attempts all 23 bank properties and continues past four refusals.
Its combined save then copies the recipe to the live properties, starting with `D1A5`, live Image Size. `D1A5` isn't a bank
property, so the app excludes it from bank reads, writes and backups, and refuses a backup that holds
it with an explanation. The app differs from X RAW Studio in these ways:

- **Conditional writes are skipped rather than refused.** `D19C` only when white balance is Kelvin
  (`0x8007`). `D193`/`D194` only for a monochrome simulation with toning (`hasMonochromaticColor`,
  which excludes Sepia: the camera greys its toning out and refuses every write to either axis,
  `0` included, on the tested X-T50). The app writes an explicit zero to clear an axis's existing
  toning wherever the registry gives the body that axis (`CameraModel.hasMagentaGreenAxis`; the
  X-T3 and X-T30 lack MG, and the GFX100's entry describes firmware 4.00 and later, which has it, so
  a GFX100 on earlier firmware is sent the zero too). The X-T50 and X-H2 accept the zero;
  published sources report refusals on an X100VI and a GFX100RF
  ([*Polarity and use*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/03-encodings.md#polarity-and-use)). An unset (`nil`)
  axis is not written. A non-zero MG
  for one of those single-axis bodies is still attempted, with a compatibility warning. `D19F` only
  for a colour simulation. Under a monochrome simulation the app still writes Color Chrome Effect,
  Color Chrome FX Blue and both white balance shifts; the X-T50 accepted those four under ACROS and refused Color
  ([*Why a write is refused*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/04-custom-slots.md#why-a-write-is-refused)).
- **`D191` is written only when the push changes it.** The tested X-T50 refused every write at
  base ISO, including its held value. The app suppresses this no-op because a refusal of a recipe
  field would demote an otherwise clean push to `partiallyApplied`.
- **Housekeeping is passed through from the slot's own read:** `D18E`, `D18F`, `D198`, `D1A3`,
  `D1A4`. These are not recipe fields. A valid housekeeping refusal does not change the recipe-field
  outcome, but an uncertain send still makes the operation unconfirmed.
- **The app writes the bank only.** The captured combined X RAW Studio save also writes the live
  properties; the published SDK analysis identifies that copy as optional. In the tested X-T50 runs,
  a write to the active bank took effect immediately, and a write to another bank applied when that
  bank was selected. This is the basis for the app's bank-only policy.

### Why a write is refused, and what the app says

`0x201C Invalid DeviceProp Value` can result from an invalid encoding or a state restriction.
The code alone does not identify which condition caused a refusal. The full table of causes is in
[*Why a write is refused*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/04-custom-slots.md#why-a-write-is-refused).
The ones the app handles specifically:

| Refused | Cause | What the app does |
|--|--|--|
| `D18E` alone, on a slot where everything else writes | A bank setting that fixes Image Size: SPORTS FINDER MODE by correlation on the X-T50 (the refusing banks had it on; no on/off test on one bank), and DIGITAL TELE-CONV., which refused and then accepted the same bytes across an on/off comparison; the CH crop and HDR are untested | `SlotWriteResult.imageSizeFixedByBank` names the likely cause as a hint; the slot keeps its Image Size, and the push stays `applied` |
| `D190` DR200 or DR400 | Possible ISO gate; the exact 2×/4× thresholds were tested on the X-T50 | `SlotWriteResult.dynamicRangeRefusalHint` names the possible causes |
| `D191`, any value | Possible ISO gate; every tested value was refused at base ISO on the X-T50 | Not written unless the recipe changes it; `dRangePriorityRefusalHint` explains a refusal |
| `D190`, `D19D`, `D19E` | D-Range Priority is on in the bank | Not sent while the push leaves the priority on; see "Dynamic Range and D-Range Priority" |
| `D1A2` Clarity, every value | A possible HEIF gate; the X-T50 refused the tested values on a HEIF bank and accepted them on a JPEG bank | `clarityRefusalHint` names the possible format restriction; the push reports Clarity as refused |
| `D193`/`D194` written as `0` | Zero refusal is reported for the GFX100RF and X100VI without a detailed transaction trace; a refusal alone does not isolate this cause | `toningZeroRefusalHint` suggests that the bank kept its toning; fresh readback establishes what it holds |

ISO and file format are outside the 23 bank settings, while D-Range Priority is readable as `D191`.
The diagnostic hints suggest causes from the refusal pattern; they do not establish unobserved camera state.

### What read-back verification cannot catch

Both write paths verify the same way: send, read back, compare. That catches a camera that accepts
a write and doesn't keep it. It can't tell whether what was sent is what the recipe asked for.

**An unchanged value cannot show that a write caused the final state.** For an accepted write whose
fresh readback matches the sent bytes, the app marks `.written`, even if the bank already held that
value. The app keeps a refusal `.rejected` and a missing readback `.unverified`; it does not
promote those outcomes to `.written`. The rules that follow:

1. **Report the value, not just the status.** The push results show what the slot's film simulation
   and dynamic range read back as (`SlotWriteResult.filmSimulationReadBack` and
   `dynamicRangeReadBack`, shown by `PushResultsView`).
2. **A recipe field the recipe leaves unset is written as a default, not inherited.** Film
   simulation (PROVIA), dynamic range (Auto), grain (Off), D-Range Priority (Off) and both Color
   Chrome effects (Off) are `FujiPresetCodec.defaultedFields`. A recipe describes a whole look;
   inheriting the bank's values would make one recipe produce two looks on two banks, each reported
   as "Written and verified". Two recipe fields still pass through: High ISO NR when the recipe sets
   none, and film simulation when the body doesn't offer the recipe's (the bank keeps its own, and
   `RecipeCompatibility` warns).
3. **An unanswered read is not a licence to write.** If an occupied slot didn't report one of those
   properties, its default is skipped, because the bank may hold anything.
   `defaultsNotWrittenForSilentRead` puts that on the results screen, since a default that was never
   sent leaves no other row. Housekeeping that the slot didn't report is not written at all.
4. **Missing reads never prove an empty slot.** Live writes require recoverable originals. Synthetic
   demo fixtures may use `FujiPresetCodec.seedValues`; hardware reads do not authorize those seeds.
5. **A probe must check what the camera did, not what it stored.** `probeConversionDynamicRange`
   develops each candidate and reads the rendered JPEG's MakerNote, which distinguished the tested
   `−1` candidate from DR Auto (see "Dynamic range in a develop"). A profile read-back alone would
   have passed it.

### After a push: the red dot

The final controlled X-T50 tests left red dots on written items in EDIT/SAVE CUSTOM SETTING
(not in the Q menu), with SAVE THE CHANGES and RESET THE CHANGES offered. Those USB writes
survived RESET and power cycling; the tested name-write timings did not clear the dots, while
opening the item or power cycling did. AUTO UPDATE CUSTOM SETTING was not recorded, and earlier
conflicting persistence/RESET runs remain unexplained
([*Writing a bank*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/04-custom-slots.md#writing-a-bank)). The push
results explain the observed behavior in a note (`annotateCameraFlag`), and the Camera Test's
power-cycle step tells the tester to expect it. RESET is not a verified rollback for these USB writes;
Undo Last Push attempts restoration from the saved pre-push state and verifies the result.

### Restoring a slot

A restore (`SlotWriter.restore`, behind Undo Last Push and Restore a Slot) is a push:
the same `performSlotWrite`, with the same select, name write and read-back. It is encoded by
`FujiPresetCodec.encodeRestore` from saved bytes rather than from a recipe, is never staged, and
does not move the permission to `verified`.

Backup import validates the whole file before offering a restore: version 1, unique slot indices
C1–C7, recognized custom-slot property codes, and exactly two bytes of hexadecimal data per
property. An occupied slot must contain saved settings. Unfamiliar values of a recognized property
remain raw bytes; an invalid property or slot rejects the file instead of silently dropping part of
it. The restore boundary checks the properties and the connected camera's slot count again before
selecting a bank or writing its name.

- **Conditional writes are decided from the saved bytes, after the dormant values the slot still
  exposes.** `D193`/`D194` only when the saved `D192` is a monochrome simulation with toning, and
  `D19C` only when the saved `D199` is `0x8007`; for a saved monochrome simulation, `D19F` is
  skipped only when the current bytes already match. A push over the slot may have changed a value
  the backup hides — a Kelvin recipe over an Auto bank rewrites `D19C`, a toned ACROS recipe over a
  colour bank rewrites `D193`/`D194`, a colour recipe over an ACROS bank rewrites `D19F` — so when
  the slot's current read (`current`) still exposes such a value and it differs from the saved
  bytes, the saved value is written first, while the camera accepts it, and the simulation or white
  balance that hides it after; `RestoreFidelity.restoredWhileActive` names them for the log and the
  confirmation screen. Without a current read, or where the slot no longer exposes the value, the
  rules stand: the app does not stage a temporary simulation or white balance, and the final
  baseline comparison retains the mismatch. Measured on the X-T50 (fw 1.32, 2026-10-19): a Kelvin
  push over an Auto bank storing 5300 K, then Undo, wrote `D19C` 5300 first (accepted, 135 ms),
  `D199` Auto later (300 ms), and the final read matched all 23 original bytes.
- **Grain Off preserves remembered size where evidenced.** On the X-T50 and GFX100S, saved `6`
  is reconstructed with `2 → 1`, and saved `7` with `5 → 1`. Each sequence is one logical field;
  failure of its preparation stops that sequence. Final restore verification checks the original raw
  bytes. Other bodies retain the semantic Off fallback and explicitly report incomplete fidelity if
  the remembered size differs.
- **White balance restores in dependency order:** mode, Kelvin, red shift, blue shift. This prevents
  a Kelvin write that resets shifts from undoing the saved shift values.
- **D-Range Priority is ordered by direction.** Restoring a bank whose priority was Off turns it off
  before writing Dynamic Range and the tones. Restoring Priority On over an Off bank writes the saved
  Dynamic Range and tones first and turns the priority on last. An already-On bank gets no invented
  temporary Off. Command results are recorded separately from the final original-versus-current
  verification.
- **An unnamed slot gets its empty name back.** `undoName(forSlot:)` and a restore from a backup
  write the recorded name, "" included: the app packs an empty name as `01 00 00`, the count and
  the NUL that an unnamed X-T50 bank answers for `D18D`, and the camera then labels the bank
  CUSTOM *n* with a blank name. Over direct USB the X-T50 takes that form and the one-byte empty
  string `00` alike; through ImageCaptureCore the one-byte form was answered OK and left the old
  name (fw 1.32, iOS 27.0.1, 2026-10-19; the reference's
  [bank name notes](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/03-encodings.md#0xd18d-bank-name)).
  `completePresetName` reads `01 00 00` as a complete empty name, so the final comparison verifies
  it. A push never writes an empty name (`sanitizedSlotName` substitutes "Recipe"), and only a name
  that was never read before the push falls back to "C*n*".

## Value encodings

Every encoding the app uses lives in `FujiEncoding`; the values themselves, with the evidence for
each, are in [*Value encodings*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/03-encodings.md). What the app does
with the ones that need care:

- **Grain has asymmetric read and write sets.** `grainToFlat` writes `1` for Off, `flatToGrain`
  decodes `1`, `6` and `7` all as Off, and `SlotWriteVerification.readBackMatches` compares grain by
  decoded meaning for recipe pushes: writing `1` and reading `6` or `7` is success. Restore additionally checks exact saved bytes. The in-app `D195`
  write probe is how the write set was established, and it has run on an X-T50 and a GFX100S.
- **The effects are 1-indexed on the wire.** `effectToValue` already emits the wire value. Published
  code that stores them 0-indexed in its UI adds one when writing; don't "fix" the app's to match
  ([*Color Chrome, Color Chrome FX Blue, Smooth Skin*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/03-encodings.md#0xd196--0xd197--0xd198-color-chrome-color-chrome-fx-blue-smooth-skin)).
- **Custom white balance 1–3 (`0x8008`–`0x800A`) is recognised, never authored.** A custom white
  balance is a measurement the user made on one camera, so no recipe carries it and the editor
  doesn't offer it. `FujiPresetCodec.decode` records it as a `DecodeDivergence.Kind.cameraOnly`
  and `DecodedProfile.cameraOnlyFields`, so the slot row shows "Custom 1 — set on the camera, not
  part of a recipe" and the Camera Test's menu comparison "Custom 1 (set on the camera)" instead of
  a value the app couldn't read; the recipe imported from
  that slot has no white balance, and a push of it writes Auto, like any recipe without one.
- **A slot keeps its last Kelvin while white balance is something else, and it is inert.** The
  camera shows it greyed out and uses it for nothing. The app never sees it either: `encode` writes
  `D19C` only for a Kelvin recipe, `decode` reads it only when `D199` is Kelvin, and a restore replays
  it only when the saved slot was Kelvin. It isn't a push advisory: the push did nothing the recipe
  didn't state.
- **A white balance shift belongs to its mode.** Each mode keeps its own shift within the bank, and
  `D19A`/`D19B` report the active mode's, so the app writes the shifts after the mode and reads a
  shift as that mode's.
- **DR Auto is `0xFFFF`.** `FujiEncoding.drAutoSlotValue` writes it and `decode` maps it to Auto;
  `0` was refused on the tested X-T50; the conflicting X-H2 interpretation remains in the reference's errata. Treating `0xFFFF` as unknown would turn a supported DR AUTO bank into a
  recipe with no dynamic range.
- **`GetDevicePropDesc` is often refused for bank settings**, including the tested X-T50 and
  GFX100S blocks, with codes that differ by body. This is not universal: the GFX100 II tether-mode
  dump supplies a selector descriptor. The app uses the reference's menu-swept value sets and
  records descriptor refusals without treating them as evidence that value access is unavailable.
- **`D183` refuses a diagnostic read on an X-T50** (`0x2002` for value and descriptor before a RAF
  upload), where the GFX100S and X-T20 answer a descriptor. `D183` is the conversion trigger, so the
  refusal says nothing about the slot values or about conversion. The guided Camera Test's read
  checkpoint (`GuidedTestRunner.propertyReadFailure`) accepts `0x2002` from `D183` and `D185`
  without failing a clean slot read.

## Dynamic Range and D-Range Priority

Dynamic Range and D-Range Priority interact. On the tested X-T50, both are gated by state the 23 bank properties
don't carry: `D190` DR200 and DR400 need the bank's own ISO at exactly 2× and 4× base; `D191` refuses
every write at base ISO; with the priority on, the camera drives `D190`, `D19D` and `D19E` and refuses
writes to exactly those three; and the ISO can't be read on an X-T50. The measurements are in
[*ISO gating*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/04-custom-slots.md#iso-gating) and
[*The D-Range Priority interlock*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/04-custom-slots.md#the-d-range-priority-interlock).

What the app does about it:

- `FujiPresetCodec.encode` writes `D191` before `D190`, and only when the recipe changes it.
- While the push leaves the priority on, it doesn't send `D190`, `D19D` or `D19E`. The editor greys
  those three rows, and `RecipeCompatibility` says so before and after the push. A recipe that leaves
  the priority unset turns it off, as a default (the push's advisories say so); one that holds both a
  priority and a dynamic range keeps the priority and skips `D190`.
- **The withholding is contingent on the `D191` write landing.** If `D191` comes back refused, the
  bank kept whatever priority it had, so `FujiPresetCodec.dRangePriorityWithheld` keeps the three
  writes and the push sends them anyway: they land if the bank's priority was off, and are refused
  as three named rows if it wasn't. The case is real on the GFX100S
  ([*Camera bodies*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/07-cameras.md#gfx100s)).
- Because the ISO isn't readable on every body, a refusal may be the only signal.
  `SlotWriteResult.dynamicRangeRefusalHint` and `dRangePriorityRefusalHint` name the possible causes
  instead of showing a bare response code. `CameraDiagnostics.dynamicRangeProbeCandidates` is
  the `D190` write probe's list, with a DR100 control between candidates and Auto last. Every sweep
  reads `0x500F`, so a body that answers it could be warned about before a push instead of after.
- **`D191` is read and packed unsigned.** Auto is `0x8000`; read signed it arrives as −32768 and
  misses the table, and `decode` files an unknown value as a divergence rather than as Off.
- **The stored value and the menu can disagree at base ISO.** A bank can store Auto while the camera
  shows OFF and greys the item out. The Camera Test's slot comparison records such a bank as
  `! D-Range Priority: app showed Auto — camera shows OFF`; both values are right, so read a lone
  D-Range Priority mismatch against the bank's ISO before treating it as a decode error. Such a bank
  refused attempts to clear its priority through the tested `D191` path at base ISO. The record
  does not establish that ISO is the only gate or that every USB path behaves the same way.
- **`D191` is not evidence for profile cell 7.** `D191` is a slot property; cell 7 is the conversion
  profile, which published sources encode differently
  ([*D-Range Priority, cell 7*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/06-conversion-profile.md#d-range-priority-cell-7--unknown)).
  `FujiRawConvProfile.Field` has no case for
  cell 7, so nothing writes it. `FujiMakerNote` reads MakerNote tag `0x1445` DRangePriorityFixed as
  `1: Weak, 2: Strong`, which is consistent with `D191` rather than a confirmation of it.

## Bodies with a Film Simulation dial

The manuals for bodies with a Film Simulation dial describe its override unless it is set to **C**.
The tested X-T50 accepted `D192` writes in either position while the dial determined the shooting simulation
([*Bodies with a Film Simulation dial*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/04-custom-slots.md#bodies-with-a-film-simulation-dial)).
`CameraModel.hasFilmSimulationDial` is set for the X-T50, X-E5, X-T30 III and X-M5, and drives a
reminder in the push flow.

## Housekeeping seeds

`FujiPresetCodec.seedValues` supports synthetic empty-bank fixtures. A missing `D192` response is
not evidence of an erased bank, so the live write path does not use missing reads to authorize
seeding. Every property that a write may change must first have a complete two-byte original, and
on a body with naming on the original name must be valid. The preflight also covers the contingent writes that would be
sent if the camera refused D-Range Priority.

The synthetic housekeeping values come from the X-T50 and must not be generalized to other bodies:
`D18E = 7` (L 3:2), `D18F = 4` (FINE + RAW), `D198 = 1` (Smooth Skin), `D1A1 = 0x4000` (High ISO NR),
`D1A3 = 1` (Lens Modulation Optimizer), and `D1A4 = 1` (sRGB). `D1A5` is a live property and is excluded entirely.

## RAW conversion (Kitchen)

The in-camera RAW-to-JPEG path, distinct from the slot read and write above: upload a RAF, patch the
`0xD185` profile, trigger, and fetch the JPEG the camera's own processor produced. It drives the
app's Kitchen (`FujiRawConvProfile`, `RawConversionService.cook`, `ImageCaptureTransport`). The
camera must be in **USB RAW Conv./Backup Restore** mode. The flow and its evidence are in
[*In-camera RAW conversion*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/05-raw-conversion.md) and
[*The `0xD185` conversion profile*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/06-conversion-profile.md).

### Sequence

1. **Upload:** `SendObjectInfo (0x900C)` with params `[0, 0, 0]` and an ObjectInfo named
   `FUP_FILE.dat`, as X RAW Studio and the published implementations all do
   ([*The sequence*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/05-raw-conversion.md#the-sequence)); then `SendObject2 (0x900D)`
   with the bytes. Before either, the file's own header is read (`RAFHeader`: the magic, the camera
   ID at bytes 20–27, the model name at 28–59): a file without the magic is refused without an
   upload (`not_a_raf`; the camera accepts any bytes and then answers `0x2002` to the `0xD185`
   read), a file whose model name the registry places on another body is refused the same way
   (`raf_from_different_body`), and the demo camera and a name the registry can't place decide
   nothing. A `0x2002` from the upload itself is reported as an unexplained General Error
   (`upload_general_error`): an upload refusal alone doesn't establish a cause
   ([*Prerequisites*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/05-raw-conversion.md#prerequisites)).
2. **Read** `0xD185`: 625 bytes and `numParams = 29` on the X-T50, describing the RAF's as-shot
   settings. A `0x2002` here, after an accepted upload of a file whose header doesn't name the
   connected body, is where the published foreign-RAF failure lands (same section), so it is
   reported with that as a known cause (`raf_from_different_body`); for the body's own file it is
   reported as the camera's error.
3. **Patch** only the cells the recipe sets. The base carries as-shot values and sentinels, and
   writing defaults into unset cells corrupts the conversion. Monochromatic Color's two axes go
   into their own cells
   ([*Monochromatic Color, cells 23 and 26*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/06-conversion-profile.md#monochromatic-color-cells-23-and-26))
   by the push's rule, `FujiPresetCodec.toningValuesToWrite`, so both paths encode the same requested
   toning. Bank acceptance and rendered output still require separate verification.
4. **Write** using the app's `FujiRawConvProfile.hostWriteForm`: zero-extended to 629
   bytes with `numParams` set to 29. The padding goes after the table, so no field moves. Applied to
   the X-Pro3's captured 621-byte read, it reproduces X RAW Studio's captured 629-byte write byte for
   byte. Other observed host writes use nonzero tail cells, including an X-T50 first write;
   this is an app policy, not a universal X RAW Studio fill rule.
5. **Verify:** re-read `0xD185` and compare every explicitly requested cell, including values that
   equal the as-shot base. Missing or malformed readback is unavailable verification, never a match.
6. **Trigger:** `SetDevicePropValue(0xD183, n)`, where 1 = full resolution and 0 = a reduced-size
   preview. A write of 2 is refused `0x201C` on the X-T50; other bodies' trigger semantics and
   output dimensions aren't verified.
7. **Fetch safely:** require exactly one new handle and complete `GetObjectInfo (0x1008)` identifying
   a JPEG. Download it with `GetObject (0x1009)`, check its declared byte count and fully decode the
   image. Ambiguous or invalid output is retained on the camera.
8. **Preserve before cleanup:** write and synchronize a recovery JPEG under Documents/Recovered
   Develops before `DeleteObject (0x100B)`. Cleanup failure remains separate from conversion success.
   The recovery file is removed only after the app's library save succeeds; otherwise it remains
   accessible in Files and through the result's recovery share action.

Cook, batch, matrix, and the conversion probe each hold the operation gate for their whole run.
Session changes invalidate subsequent writes, output retrieval and deletion. An unconfirmed upload,
profile write, trigger or cleanup stops automatic work on the remaining batch items, even when a
JPEG was safely saved before its cleanup reply was lost.

Object lists used for conversion or cleanup must be complete: the response envelope must be valid and belong to the ImageCaptureCore request callback, and the handle count must match the payload. Missing or truncated lists, duplicate or
zero handles, and the all-objects sentinel are rejected. A valid zero-count list is empty. An
invalid list never supplies a candidate for cleanup; it is not treated as an empty baseline that
could make an existing object appear new.

**Upload once, develop many.** The conversion buffer survives a conversion, so another version of
the same photo can reuse the upload and run steps 3–8, including durable saving and cleanup. `cookMatrix` relies on this: a 3 × 3 Test Kitchen grid is three
uploads, not nine. Every version is patched from the profile read at step 2, so patches never stack.

### Profile harvest

A readable, parseable `0xD185` after upload is one prerequisite for this app's conversion path,
not proof of a complete conversion. Normal develops require `supportsRawConversion` in the registry
and a body identified by its exact name or an alias (`CameraSession.canConvert`).
`RawConversionService.harvestConversionProfile` lets the Camera Test inspect the upload/profile
part of that path on a body the app does not yet develop on; it needs the same identification, but
not `supportsRawConversion`:

1. Read `0xD185` (expect `0x2002`) and `GetObjectHandles`, as the "before".
2. Upload, exactly as above, but without the header refusal: the harvest is a probe, so it sends
   a file whose header names another body and records that verdict in `rafHeader`, beside the
   camera's answer in `uploadOutcome`. An upload `0x2002` is filed as `upload_general_error`; a
   `0x2002` on the profile read that follows, for a file whose header names another body, is filed
   as `raf_from_different_body`, the published cause. General Error alone does not diagnose the file
   or the failed phase.
3. `GetObjectHandles` again, to find the object the upload created.
4. Read `0xD185`. Its length, `numParams`, `resolveLayout`'s verdict and diagnostic, and the first 64
   bytes go into `profileHarvests[]` in the report.
5. Clean up: delete the new object only when it is the one new handle and its complete ObjectInfo
   identifies the uploaded RAF as `FUP_FILE.dat`; ambiguous objects are retained. Read `0xD185` once
   more after the delete to learn whether the buffer went with it.
6. **Stop.** `ProfileHarvestTests.testTheHarvestNeverDevelops` asserts the trace holds no `0xD185`
   write, no `0xD183` and no `GetObject`.

The outcomes guide the next test. A resolved layout is a candidate for a controlled end-to-end
conversion before changing the registry. A refused upload needs its operation, response, RAF
provenance and mode checked. An accepted upload followed by a refused profile read leaves the
workflow unresolved; it does not alone prove that the body lacks conversion support.

A GFX100S harvest is the evidence behind its `supportsRawConversion`
([*Camera bodies*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/07-cameras.md#gfx100s)). A harvest
proves only that a body takes a RAF and describes it; the profile write, the trigger and `GetObject`
are shown by a develop. The shared JPEG pair supports a close overall-tone match, not exact pixels or every recipe setting
(`camera-compatibility-report.md`).

### Profile layout

The inspected profiles share table base `0x1FD`; lengths, counts and field availability differ by
body and transfer direction. The field table, with the evidence for each cell, is in
[*The `0xD185` conversion profile*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/06-conversion-profile.md).
`FujiRawConvProfile.Field` follows the record's cell numbering, from base `0x1FD`. Cell 4 is Image
Quality, not Exposure Bias, and cell 11 is the white balance source, not Smooth Skin, where some
published tables differ ([*Corrections to published sources*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/errata.md)). Cell 7 (D-Range
Priority) has no case and is never written.

`FujiRawConvProfile.resolveLayout` tries `0x1FD` first, then the tail-derived base
(`length − 4·numParams`) and one cell either side of it, and validates each semantically: cell 6 must
be exactly 100, 200 or 400 and cell 8 a known film simulation. Those are two narrow domains in
adjacent cells, which a 4-byte shift can't satisfy together, and the 1-indexed effect cells break
ties. If nothing decodes plausibly, the develop aborts before writing a byte, and the error says what
each candidate decoded to. Bounds are checked per cell, so short tables are fine (the X-H1's 601-byte,
23-param read stops after Color Space). The app records the IOPCode and never branches on it, because
no general decoder for processor generation is established.

Demo blobs cover the three shapes seen: `demoBaseProfile()` (the X-T50's 625/29),
`demoShortBaseProfile()` (the X-H1's 601/23) and `demoGFXBaseProfile()` (the GFX100S's 621/28).
`RawConvLayoutTests` checks that every read shape lands on the same base.

To capture a real blob, use the Property Report (Show Diagnostic Tools → Camera Property Report →
"RAW Conv. Profile (D185)") once a RAF has been uploaded in the session; the observed X-T50
pre-upload reads answered `0x2002`. The report prints the resolved layout, the IOPCode and a full hex dump.

### White balance

Cell 11 selects the white balance source: `1` uses the RAF's as-shot balance and `2` uses the mode
in cell 12, with the Kelvin value in cell 15 for `0x8007`. The app uses the slot protocol's mode enum
here. A recipe that sets no white balance leaves cells 11 and 12 alone.

### Verify the profile write before triggering

An OK response to `SetDevicePropValue(0xD185)` alone does not establish which settings the next
conversion will use. A stale profile could still produce a valid JPEG. On an X-T50 the **same profile
bytes** produced a heavy green cast on one develop and a correct render on later ones. The cause
wasn't isolated; the trigger arriving before the profile took effect is one hypothesis. A warm–cool
value written into the magenta–green cell is another way to get green
([*Monochromatic Color, cells 23 and 26*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/06-conversion-profile.md#monochromatic-color-cells-23-and-26)).

So `develop` re-reads `0xD185` after writing it and compares the patched cells. On a mismatch it
rewrites once and checks again. It **never refuses the develop**: a mismatch that survives the retry
is reported in the result and the diagnostics, because a field the camera silently normalises would
otherwise block renders that are fine. Missing, malformed or failed readback is explicitly
`unavailable`, with a visible warning and no verified-success claim. An empty patch plan is
`not_tested`. Verification covers all requested cells, including a matrix recipe that resets a
previous version back to the original as-shot value.

The re-read establishes returned profile bytes, not how the camera rendered them. The JPEG's
MakerNote supplies separate evidence of reported settings, such as `BWAdjustment` and
`BWMagentaGreen`; image appearance or processing effects require intact pixels and a suitable
comparison. A result's Share… button hands over the camera's file with its metadata intact. Each result also
carries **Diagnostics (D185 profile)**, `FujiRawConvProfile.fieldReport`: every cell of the camera's
read, base and patched, with the cells `FujiRawConvProfile.Field` has no case for marked `unnamed`,
because a cell the patch never touches still reaches the conversion with the camera's value.

### Dynamic range in a develop

**Raising DR above the frame's own renders green** on the X-T50: the write is accepted and the JPEG's
EXIF reports the higher DR, but the render has a heavy green cast. Lowering DR rendered clean in the
tested X-T50 conversions.

So `FujiRawConvProfile.resolveDynamicRange` caps the recipe's DR at the RAF's as-shot DR, read from
cell 6 of the base profile, and `develop` puts "Dynamic Range" in `clampedFields`, which makes it a
reportable anomaly. The user sees "Adjusted before developing: Dynamic Range" in the scannable list,
and a plain-language note naming both DRs and the green cast it avoids.

**No working conversion-profile DR Auto encoding is established here.** `RawConversionService.probeConversionDynamicRange`
writes 100, 200 and 400 into cell 6 as controls, then −1; reads each back; develops a preview for each
accepted candidate; and reads the JPEG's MakerNote to see what the camera rendered. On an X-T50 the
−1 was stored, while the tested output matched the DR100 control's Fujifilm tags and was closest
to it in the reported pixel comparison (not exact pixel equality). That case does not establish a
universal fallback, and a profile readback alone would miss the difference from requested Auto. Run the probe from Show Diagnostic Tools → Kitchen → Develop, with one RAF
picked. Its four previews go to Recent Results as comparison previews, each carrying its candidate
and the probe report, to open together in the Comparison viewer.

**The app approximates DR Auto as `min(200, as-shot)`** (`FujiRawConvProfile.autoCeiling`), with its own note.
The camera's own DR Auto never chose above DR200 on three high-contrast X-T50 frames, and the as-shot
value is no stand-in for Auto: a frame's EXIF can carry the previous recipe's manual DR400. On X RAW
Studio's capture file, `min(200, as-shot)` reproduces the DR200 X RAW Studio wrote. This policy
has not been shown to reproduce Auto's scene-dependent choice across photos.

### Net behaviour

The Kitchen applies a recipe's full look, white balance shifts and white balance mode (any mode in
the Fuji enum, including a Kelvin temperature) to a RAF. A recipe that sets no white balance develops
with the photo's as-shot white balance. Dynamic Range is capped at the RAF's as-shot DR, and DR Auto
resolves to `min(200, as-shot)`.

The supported captures and hardware runs establish useful profile layouts, but do not prove that
one host-write padding policy works on every body. The first-generation X-T30 capture has nonzero
host padding; the current zero-extension policy needs a targeted hardware comparison there. Develops are verified end to end
on the X-T50 and the GFX100S; check the first developed JPEG from any other body by eye.

### Where the app differs from X RAW Studio

Seventeen bank/profile values matched in the captured X-T50 conversion. This does not distinguish
direct copying from independent serialization. The app encodes from the recipe; compared with that
observed profile, it differs in three places:

- **Grain Off in cell 9.** The captured X RAW Studio write uses `7`, matching the bank's read-side value; the app writes `1`, the
  `D195` write value. Whether the converter treats `1` as Off in the profile is untested on an X-T50
  (a published report has it working on an X-E5; [*Parameter table*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/06-conversion-profile.md#parameter-table)).
  The app's verification compares grain by decoded meaning, so it
  would pass either way. Developing one RAF with grain Off and reading `GrainEffectRoughness` in the
  output settles it.
- **Cell 15 with a non-Kelvin white balance.** The captured cell 15 matches the bank's Kelvin even
  with white balance on Auto; the app writes cell 15 only for a Kelvin recipe, so otherwise it keeps
  the RAF's as-shot value. Its effect in that mode remains untested.
- **Cell 7 (D-Range Priority)** isn't written.

## JPEG recipe extraction

`ExifParser` bounds every TIFF read to its declared APP1 region and every MakerNote read to the
MakerNote's declared extent. Duplicate EXIF blocks or pointers are rejected; duplicate recipe tags,
wrong component counts and malformed values remain unusable observations rather than settings.
Monochrome WC/MG use the documented signed-byte interpretation even when TIFF declares an unsigned
value.

Extraction preserves missing and ambiguous information. Missing D-Range Priority is unknown, legacy
Wide1 is not relabeled DR200, nonintegral Clarity is not truncated, and FilmMode without the necessary
Saturation evidence remains a candidate. Active D-Range Priority's rendered DR and tone tags are
observations, not independent recipe intent. White balance requires a complete pair of shifts. The
reader defaults to the ×20 JPEG mapping for the modern X-series and GFX models in the app's registry,
using exact names and recognized aliases. This is an application default, not a claim of per-model
hardware verification: X-T50 and X-T30 captures establish the scale, an X-H2 isolation report agrees,
and ExifTool's newer-camera note supports the inference for other registered models. Unknown models,
legacy FinePix names and heuristic identity matches stay unresolved; invalid or fractional shifts are
withheld without rounding, clamping or falling back to direct units. The normal UI has no scale picker.
Explicit policies remain available internally for parser tests. Filtered numeric observations,
warnings, selected and resolved scale policies, and the automatic mapping's source survive Save as
New Recipe under `unsupportedFields.jpegRecipeMetadata`. The basis distinguishes `documented_model`,
`published_model` and `modern_camera_default`; these observations do not enter the camera encoder.

## Open questions

Where the app's behaviour rests on something not yet measured. The full list, with what would settle
each, is in [*Open questions*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/open-questions.md).

- **First-generation X-T30 host padding.** Compare the current zero-extended profile with the
  captured host's nonzero padding on that body before changing the write form.
- **Conversion Grain Off.** Compare profile values `1` and `7` against the rendered JPEG's grain
  metadata and appearance. Bank restore reconstruction does not settle conversion-profile behavior.
- **Expanded monochrome toning range on other bodies.** The app allows ±18 on the bodies whose
  entries have evidence past ±9 (`rangesToningEighteen` and its whole-step variant), the X-T50's
  measured endpoints among it. Confirm the range on bodies still using the app's conservative ±9
  bounds before widening those bounds.
- **Slot value sets on other bodies.** The reference separates tested settings and values on the
  X-T50, owner-reported GFX100S observations, published X-H2 and X-S10 tests, and narrower reports
  for other models. Neither a processor label nor one successful field validates an entire value table.
- **The app's conversion sequence on the X-Trans III bodies.** The Kitchen is on for the X-Pro2,
  X-T2, X100F, X-T20, X-E3 and X-H1 on that evidence: Fujifilm supports USB conversion with X RAW Studio on the
  X-T20 from firmware 2.00 and on the X-Pro2, X-T2, X-E3 and X-H1; X100F conversions have been published
  ([*Camera bodies*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/07-cameras.md#summary)), in the X-H1's 601-byte profile shape the layout
  already resolves; and the X-T20
  advertises every conversion operation and answers a writable `0xD183` descriptor. None of that
  reproduces this app's upload/profile/trigger/retrieval path, so the first develop on each body is
  a tester's, with `resolveLayout` as the guard.
- **The app's sequence on other GFX bodies.** Fujifilm lists manufacturer-supported X RAW Studio
  conversion separately from this app's hardware coverage. The Kitchen is on for the GFX100S alone. The GFX100 and
  GFX 50S II write on its report, but neither has been harvested; the GFX100RF writes on a published
  record and has never been sent a RAF.
- **The DR thresholds** on bodies whose base ISO isn't 125. On the X-T50 they are exactly 2× and 4×.
- **Whether any body encodes D-Range Priority or DR Auto differently.** The X-H2 DR Auto report
  conflicts with the stored-Auto evidence on the tested X-T50 and other bodies. A refusal is one
  possible outcome of an unsupported value; acceptance, normalization and unchanged readback must
  also remain distinct. A successful response alone does not establish the interpretation.
- **The X-Pro3.** A published report found every bank operation failing at firmware 2.00, without
  the response codes. A read-only sweep of `0xD18C`, with mode and firmware recorded, is an initial
  diagnostic; selector changes and property-specific reads/writes are separate capabilities.

## Capturing X RAW Studio

To record Fujifilm's own software talking to a camera, see
[*Capturing Fujifilm's own software*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/08-methods.md#capturing-fujifilms-own-software)
and the reference's `tools/ptpcap.py` decoder. It supports classic pcap and pcapng and reassembles
containers split across packets. Missing packets can still leave large transfers incomplete;
`--recover` may resume at later packet boundaries, with explicit heuristic-recovery diagnostics.
Only complete metadata regions can support metadata conclusions, and recovered EXIF does not
establish intact pixels. See the reference's capture reproduction guide for the exact inputs and limits.
