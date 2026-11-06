# Supported cameras

The app keeps a list of camera models (`Shared/Camera/CameraModelRegistry.swift`) for two things:
what each body's menus offer, so a recipe can be encoded and judged for it, and how firmly its writes
have been confirmed. Whether the app writes to a connected body is decided from what the body answers
at connect, not from the list (`WriteDecision`, in `FujiCookbook/Camera/Session/WritePermission.swift`):
a body the list vouches for, identified by its exact product name or a known alias, writes on the
list's word; any other body writes once its slot selector has answered a bank number, every slot it
accepted has read back, and the selector has gone back where it was. A body is kept out by an entry
with a recorded failure of the bank path (a name that only resembles that entry's is kept out too),
by a slot read that doesn't pass, or, with no entry at all, by not naming itself over USB.

The first push to a body no push has yet been read back on is staged: one setting (film simulation,
or sharpness when the recipe leaves film simulation as it is) is written and read back before the
name and the rest. When neither differs from what the bank holds, the push runs unstaged. A refusal
other than "invalid value", a read-back that differs, or a lost response stops the push there, puts
that one setting back, and is reported; a clean push marks the body verified for the session, and
later pushes in the session run unstaged. The next connection starts unverified again. The X-T50,
X-M5 and GFX100S, whose writes were confirmed on hardware or by their owners, start verified and are
never staged when they are identified by name; a body only guessed to be one of them is staged like
any other. The staging is this
app's policy, not a protocol fact; the record's own method for a new body probes grain on a backed-up
bank ([*Methods*](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/08-methods.md#minimum-evidence-for-a-new-body)).

A body that isn't on the list at all is identified by what it reports over USB: `GetDeviceInfo` with
a product name, serial number and firmware version, and without all three it isn't written to. It is
walked and written like an untested entry, encoding with the newest generation's field knowledge; a
field the body lacks is refused by the body and reported by name. It gets no Kitchen, because RAW
conversion is decided per entry. The report such a connect produces is what gets the body listed.

| | Bodies |
|---|---|
| **Read and write recipes** | X-Trans V: X-T5, X-T50, X-H2, X-H2S, X100VI, X-S20, X-E5. X-Processor 5 with a 4th-generation sensor: X-T30 III, X-M5. Late X-Trans IV: X-T4, X100V, X-S10, X-E4, X-T30 II. GFX: GFX100S, GFX100, GFX 50S II, GFX100RF. |
| **Read and write recipes, untested** | GFX 50S, GFX 50R, GFX100 II, GFX100S II: no write to their banks is on record either way (for the GFX100 II the [record](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/07-cameras.md#summary) holds a selector descriptor, no write), so the app writes to them once their slots have answered at connect, and marks them "not yet tested". |
| **Develop RAW files (Kitchen)** | Every X-Trans IV and V body above, plus the X-Pro3, X-T3 and X-T30, the X-Trans III bodies (X-Pro2, X-T2, X100F, X-T20, X-E3, X-H1), and the GFX100S. |
| **Blocked on a recorded failure** | X-T20, X-T3, X-T30 and X-Pro3, each with a failure of the bank path in the record's camera bodies chapter ([X-T20](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/07-cameras.md#x-t20), [X-T3 and X-T30](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/07-cameras.md#x-t3-and-x-t30), [X-Pro3](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/07-cameras.md#x-pro3)). The X-Pro3's refusal tells the user about the published failure; the others say the body doesn't expose its slots through the bank protocol the app uses. |
| **Untested, bank protocol not expected** | X-Pro2, X-T2, X100F, X-E3, X-H1, and the X-Trans I and II bodies (X-Pro1, X-E1, X-M1, X100S, X-T1, X-E2, X-E2S, X-T10, X70, X100T): the record holds no observation of the bank protocol on them, for or against. (A published tool reaches an X100F's banks through the settings backup, a path the app doesn't implement.) The registry expects no bank protocol on them, and the connect asks anyway: a body whose selector answers a bank number is walked and written like the GFX bodies above, and one that answers `0x200A` is read without a single select. The X-Trans I and II bodies have no USB RAW conversion either; they are listed so a recipe can be judged against them. |

How firmly each body is known varies. The X-T50 is verified end to end on hardware, the GFX100S and
X-M5 by their owners' own write passes, and most of the rest by published or community reports. Six
write only because they share a processor and protocol with a tested body: the X-H2S, X-T4, X-E4,
X-T30 III, GFX100 and GFX 50S II. The app marks every body but the first three "not yet tested"
next to the camera until a push in the session has been read back. Before a push it shows a "Not
tested on this camera yet" note for the six, saying they share a processor and protocol with a
tested body, and for every body its slot read let write (the untested entries, a guess at a name,
and a body with no entry), saying that writing rests on its slots having answered. The
[Camera Compatibility Report](camera-compatibility-report.md) is how a body moves up.

## Sources for older bodies

The [Fujifilm PTP reference](https://github.com/zgrimz/fujifilm-ptp-reference) records menu facts
only for bodies with USB observations, so it leaves out the X-Trans I and II bodies and the X-E3's
menus, and holds only part of the X-H1's. For those, the registry takes what it knows straight from Fujifilm's
manuals:

| Body | Fujifilm manual | What the registry takes from it |
|---|---|---|
| X-Pro1 | [Owner's manual (PDF)](https://dl.fujifilm-x.com/support/manual/x/fujifilm_xpro1_manual_en.pdf) | Ten film simulations; seven banks |
| X-E1 | [Owner's manual (PDF)](https://dl.fujifilm-x.com/support/manual/x/fujifilm_xe1_manual_en.pdf) | Ten film simulations; seven banks |
| X-M1 | [Owner's manual (PDF)](https://dl.fujifilm-x.com/support/manual/x/fujifilm_xm1_manual_en.pdf) | Five film simulations; one bank; no Kelvin or Underwater white balance |
| X100S | [Owner's manual (PDF)](https://dl.fujifilm-x.com/support/manual/x/fujifilm_x100s_manual_en.pdf) | Ten film simulations; three banks |
| X-T1 | [Owner's manual (PDF)](https://dl.fujifilm-x.com/support/manual/x/fujifilm_xt1_manual_en.pdf) | Eleven film simulations, Classic Chrome from firmware 3.00; seven banks |
| X-E2 | [Owner's manual (PDF)](https://dl.fujifilm-x.com/support/manual/x/fujifilm_xe2_manual_en.pdf) | Eleven film simulations, Classic Chrome from firmware 3.00; seven banks |
| X-E2S | [Owner's manual (PDF)](https://fujifilm-dsc.com/en/manual/x-e2s/x-e2s_omw_en_s_f.pdf) | Eleven film simulations; seven banks |
| X-T10 | [Owner's manual](https://fujifilm-dsc.com/en/manual/x-t10/menu_shooting/index.html) | Eleven film simulations; seven banks |
| X70 | [Owner's manual (PDF)](https://fujifilm-dsc.com/en/manual/x70/X70_OMW_EN_S_F_02.pdf) | Eleven film simulations; seven banks |
| X100T | [Owner's manual (PDF)](https://fujifilm-dsc.com/en/manual/x100t/x100t_om-full_en_01.pdf) | Eleven film simulations; no bank count found |
| X-E3 | [Image quality settings](https://fujifilm-dsc.com/en/manual/x-e3/menu_shooting/image_quality_setting/index.html) | The X-Trans III fields and film list; Auto white balance without the White and Ambience priorities; seven banks |
| X-H1 | [Image quality settings](https://fujifilm-dsc.com/en/manual/x-h1/menu_shooting/image_quality_setting/index.html) | ETERNA and D-Range Priority on top of the X-Trans III set |

None of the X-Trans I and II manuals lists Grain Effect, Color Chrome, D-Range Priority, Clarity or
Monochromatic Color. Their white balance is Auto, the presets, Kelvin and Underwater, without the
White and Ambience priorities, except on the X-M1. The X-T1's and X-E2's Classic Chrome comes from
Fujifilm's firmware notes for version 3.00. The manuals print the tone and color controls without
their values, so the registry sets no range for these bodies and the Works With card says the range
isn't verified.

## Toning sources the record leaves out

The X-T4 and GFX100 have no USB observations in the protocol record, so it leaves out two of the
sources behind the registry's −18…+18 on both Monochromatic Color axes for them. For the X-T4 the
record holds a second report; for the GFX100 at firmware 4.00 the video below is the only source,
and it shows no end stop:

| Body | Source | What it shows |
|---|---|---|
| X-T4 | tomitom, [article on ACROS and Monochromatic Color](https://fujifilmxtomitom.com/acros-monochromecolor-fujifilm) (in Japanese), 2020-07-25 | States that both axes shift to ±18; gives no firmware. A second report beside the record's Fuji X Weekly one. |
| GFX100 | Fujifilm X Thailand, ["X-Tutorial : New! GFX100 "Firmware 4.0""](https://www.youtube.com/watch?v=DWjoV4Pl5HY&t=170s), video, 2021-06-30 | Firmware 3.02's menu has the warm–cool axis alone, shown at +9. Firmware 4.00's, beside it, reads WC +12 with MG +12 and MG −14 (2:51–2:58), on a grid drawn 18 steps either side of centre. No end stop is reached. |
