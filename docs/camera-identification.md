# Camera identification

*Code: `Shared/Camera/ModelIdentification.swift`,
`CameraModelRegistry.identify(productName:)`.*

## Why not the longest matching id

Resolving a product name by the longest entry id it contains hands a shipping camera the wrong
capabilities: the X-T30 III normalizes to a string that contains "X-T30 II", so that rule gives it
the X-T30 II's film list without REALA ACE, no Film Simulation dial reminder, and a verification
level it has never earned, with nothing on screen to say a guess has been made.

## The confidence axis

`identify(productName:)` returns a `ModelIdentification`; the connect adds one case it can't:

| Case | Meaning | May read | May write |
|---|---|---|---|
| `exact(model)` | the normalized name equals an entry id | yes | the entry decides: `.readWrite` writes, `.blocked` never, `.untested` once the slot read has answered |
| `alias(model, alias:)` | a known spelling variant: the alias table, or the spaceless form of an id ("X-T30II") | yes | as `exact` |
| `heuristic(model, matched:)` | the name *contains* an id at a word boundary ("X-T5 TETHER") | yes, behind a banner naming the guess | once the slot read has answered; never when the matched entry is `.blocked` |
| `unlisted(provisional:)` | nothing matched, and `GetDeviceInfo` named the body with a product name, serial and firmware (`CameraConnector`) | yes, on a provisional model with the newest generation's fields | once the slot read has answered |
| `unknown` | nothing matched and nothing named it | read-only sweep, report to send | never |

## The four fields

The record asks a client to keep four things about a body apart
([*Implementing a recipe client*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/11-client-implementation.md#keep-session-and-device-identity-explicit)),
and `ConnectedCamera` carries them as four fields:

| Field | Type | Who sets it |
|---|---|---|
| Identity | `identification: ModelIdentification` | `CameraModelRegistry.identify`, then `CameraConnector` for `unlisted` |
| Published capability | `model: CameraModel?`, read from the identification (`writeSupport`, `supportsSlotProtocol`, fields, ranges); nil for `unknown` | the registry; a provisional model for an unlisted body |
| Observed capability | `observed: ObservedCapabilities` — what the selector answered, how the walk ended, whether the selector went back, and how a staged first write ended | `SlotReader.refresh`, filed by the connector; the first push for `firstWrite` |
| Permission | `writeAccess: WriteAccess` — `.undecided`, `.granted(WritePermission)` or `.refused(WriteRefusal)` | `WriteDecision.decide`, called by the connector before and after the walk |

Only `WriteDecision` produces a `WritePermission`, and the slot writer and the write probe take one
as a parameter, so nothing writes without it; the one other way to get one is
`WritePermission.verified()`, which re-stages an existing permission after a push has been read
back. A trusted `.readWrite` entry is granted at identification, on the registry's word. Every
other body is granted only by its walk, in the record's order for a new body: the selector read
answered a bank number, every selected bank read back, the selector was restored and read back.
`.undecided` lasts from connect to the end of that walk, during which no push is offered.

A permission carries a stage (`WritePermission.Stage`). A trusted entry at `.hardware` or
`.ownerReport` starts `verified`; every other grant starts `unverified`, and its first push is
staged: one setting is written and read back before the rest (`StagedWrite`; see
[supported cameras](supported-cameras.md)). A push read back clean moves the stage to `verified` for
the rest of the connection.

Normalization: uppercase, the make stripped, whitespace collapsed. Hyphens are kept, so "X-T30 III"
and "X-T30 II" stay distinct. Two rules keep the guess tier honest:

- **Word boundary.** "X-T30 II" inside "X-T30 III" is followed by a letter, so it doesn't count.
- **Generation suffix.** "X-T30" inside "X-T30 III" *is* at a boundary, but the next token is a
  roman numeral, and Fujifilm uses those to mean a newer body. An id followed by `II`, `III`,
  `IV`, `V`… is a different camera, not that camera with a suffix.

`model(matchingProductName:)` exists on the registry (`CameraModelRegistry.swift:53`) for the
identification tests only; no production code calls it. The read-only best-guess consumers go
through `identify` too: a photo's EXIF seeding `authoredForModel` takes
`identify(productName:).model?.id` (`PhotoRecipeReader.swift:169`), which accepts a heuristic match
because nothing is written from it. Anything that decides what may be written goes through
`identify` as well, and `WriteDecision.decide` (`WritePermission.swift`) is the one place that
combines confidence, the registry's word and what the body answered; its answer travels on
`ConnectedCamera.writeAccess`. Anything that persists or compares a model id reads
`registryModel?.id`, which is nil for an unlisted body: its provisional model's id is a placeholder
two different cameras would share.

## The processor axis

Film simulations follow the processor, not the sensor. `CameraModel.processor` carries it, and the
registry keys each generation's film list off it (`sims(for:)`): the EXR processors → the X-Trans II
list, X-Processor Pro → the X-Trans III list, X-Processor 4 → the late gen-IV list, X-Processor 5 →
REALA ACE and Nostalgic Neg. Bodies that differ from their processor's list pass their own: the X-T3
and X-T30 (no Classic Neg or Bleach Bypass), the X-Pro3 and X100V (no Bleach Bypass), the X-H1
(ETERNA on an X-Processor Pro body), the X-Trans I bodies, the X100S and the X-M1 (before Classic
Chrome), and the GFX line, where Nostalgic Neg reached the X-Processor 4 bodies by firmware and
Classic Neg reached the X-Processor Pro ones.

**Most other capabilities are per body, not per processor.** Grain *size* is a registry flag,
`CameraModel.hasGrainSizeControl`: the X-Processor Pro bodies and the X-T3 and X-T30 have strength
only, and the X-Trans I and II bodies have no grain at all. Tone steps are per body too: whole steps
on the X-Trans III bodies, the X-T3, X-T30, X-Pro3, X100V, GFX 50S and GFX 50R, half steps from the
X-T4 on.
Monochromatic Color's magenta–green axis is `CameraModel.hasMagentaGreenAxis`: Fujifilm's manuals
give it to the X-Processor 4 bodies from the X-Pro3 on, and to the GFX100 from firmware 4.00, and
only the X-T3 and X-T30 have the warm–cool axis alone. White-balance modes are per body as well
(`CameraModel.supportedWhiteBalanceModes`): the Auto White and Ambience priorities exist from the
X-T4 on and on the GFX100S and later GFX bodies, not on the X-Pro3, X100V or GFX100, and the X-M1
has no Kelvin or Underwater; a recipe's mode the body lacks is a change on the Works With card and a
warning before a push. What hangs off `sensorGeneration` is mostly description, not capability: it
groups the My Cameras list, and it is one of the conditions for reading a JPEG's automatic
white-balance shift (`PhotoRecipeReader`).

The X-Trans I and II entries (X-Pro1, X-E1, X-M1; X100S, X-T1, X-E2, X-E2S, X-T10, X70, X100T) carry
no numeric ranges: their manuals print the controls without values, so the registry claims no
limit, the editor falls back to its Generic ranges on those profiles, and the Works With card says
"range not verified" where it would have checked one. They are `.untested` with no Kitchen: the
registry expects no bank protocol on them, and the connect asks anyway, so one whose selector answers
a bank number is walked and may be written like any other `.untested` entry. The X-E3 and X-H1 join
the X-Trans III group, with the Kitchen that group has.

The **X-T30 III** and **X-M5** (X-Trans 4 sensor, X-Processor 5, Film Simulation dial) are writable:
the X-T30 III at `verification: .inferred`, held to the same standard as the other `.inferred`
entries, and the X-M5 at `.ownerReport` after its owner's full write pass through the app (fw 1.30,
2026-10-31). The **GFX line** is eight bodies on `sensorGeneration: .gfx`: the GFX100S is writable
and `verification: .ownerReport` after its owner's full write pass (the record's
[camera bodies](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/07-cameras.md#gfx100s)
chapter); the GFX100 and GFX 50S II write on sharing that body's entry; the GFX100RF writes on a
published record (`.community`); and the other four are `.untested`, written once their walk
answers. The GFX100S is also the one body whose `slotCount` is a measurement rather than the
registry's assumption of seven ([*Custom-setting banks*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/04-custom-slots.md#how-many-banks)).

### GFX names, and what they exercise in the matcher

The GFX line is the first place all three of the matcher's edge cases show up at once, so its ids
are worth stating: `GFX50S`, `GFX50R`, `GFX50S II`, `GFX100`, `GFX100S`, `GFX100 II`, `GFX100S II`,
`GFX100RF`.

- **Fujifilm's marketing spells them with a space and the camera doesn't.** A GFX100S reports
  `GFX100S`, no space, so that is the id; `GFX 100S` resolves through the derived spaceless alias.
  Spacing therefore can't decide identity in either direction, and neither belongs in the alias
  table.
- **The `II` suffix is load-bearing.** `GFX100S II` contains `GFX100S`, and `GFX100 II` contains
  `GFX100` — the same shape as "X-T30 III" against "X-T30 II" above. The `generationSuffixes`
  guard is what stops it, and there are tests pinning both pairs.
- **Two ids can be prefixes of a third.** `GFX100` is a prefix of `GFX100S`, which is a prefix of
  `GFX100S II`. Exact match runs before the boundary search, so each resolves to itself.
- **The older X names nest the same way.** `X-T1` is a prefix of `X-T10`, `X-E2` of `X-E2S`, and
  `X100S`, `X100T`, `X100F` and `X100V` share a stem. A digit or letter after an id is not a
  boundary, so each resolves to its own entry, and a name whose entry is missing never falls back
  to the shorter id. Tests pin all three pairs.

## What the tester sees

The write access, its stage and the identification combine into these
(`ConnectedCamera.capabilityBadge`). The caveat reads the permission's stage: it shows until a push in
the session has been read back on the body, and comes back with the next connection.

| State | Card badge | Push screen |
|---|---|---|
| Trusted, a write read back on hardware or by an owner (`.hardware`, `.ownerReport`: X-T50, GFX100S, X-M5) | "Read & Write" | offered |
| Trusted on a published or community report (`.community`: X100VI, X-T5…) | "Read & Write · not yet tested", then "Read & Write" once a push here has been read back | offered |
| Trusted, writable on shared architecture alone (`.inferred`: X-H2S, X-T4, X-T30 III…) | "Read & Write · not yet tested", clearing the same way | offered, under a "Not tested on this camera yet" note (`VerificationLevel.pushCaveat`) |
| Granted by the walk: an `.untested` entry (GFX100 II, X-H1…), a guess, or an unlisted body whose slots answered | "Read & Write · not yet tested", clearing the same way | offered, under a "Not tested on this camera yet" note that says writing rests on the slots having answered (`WritePermission.Grounds.pushCaveat`); a guess keeps its banner |
| Still being read (any body the walk decides, until it ends) | "Reading slots…" | not offered: "The camera's slots are still being read." |
| Blocked on a recorded failure (X-T3, X-T30, X-T20, X-Pro3) | "Read-only · no USB slots" | the entry's own reason; the Camera tab explains the body instead of offering slots |
| Refused by the walk: the selector answered `0x200A` | "Read-only · no USB slots" | "answers that it has no custom-slot selector over USB"; an unlisted body shows the unsupported-camera card |
| Refused by the walk for any other reason: the selector read failed, a select was ignored, no bank accepted a select, the selector didn't go back | "Read-only" ("Read-only · matched by name" for a guess) | the refusal, naming what happened |
| Unknown: no entry and nothing named the body | "Unrecognized model — writes blocked" | not reachable; the Camera tab's unsupported-camera card points to the Camera Test instead, whose report carries the same camera data |

A trusted identification — exact or alias — also adds the body to Settings ▸ My Cameras, which the
Works With card and the Library's camera filter put first. A guess does not, nor does an unlisted
body or the Demo Camera.

## Reporting

The confidence tiers reach the maintainers only through reports the user sends by hand.
"Unrecognized" means *no match at all* in the log line and the compatibility report, and confidence
rides as its own field: the report records it with its detail (`heuristic(X-T5)`, `unlisted`), and
a heuristic or unlisted connect leaves a note in it saying the slot read decides writing.
