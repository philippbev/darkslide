# Recipe comparison

*Code: `Shared/Services/SettingsDiff.swift` (the engine), `Shared/Services/RecipeApplicability.swift`
(which controls apply), `FujiCookbook/Features/Library/RecipeCompareView.swift` (the screen). Tests:
`SettingsDiffTests`, `RecipeApplicabilityTests`.*

**Compare Settings…** in a recipe's ⋯ menu compares that recipe with a second one picked from the
library, setting by setting. It is named for the settings because the Kitchen's own Compare is about
developed images.

`SettingsDiff` is pure and synchronous: no view, no SwiftData, no camera. The screen computes the
rows once when a side changes and keeps them in `@State`; switching between **Differences** and
**All Settings** filters them rather than recomputing.

## Rows

A comparison has 19 rows in five groups: Base, Tone, Color, Detail and Exposure. Rows are not
fields. Three fields carry two independent controls, and each gets two rows so a comparison can say
which one disagrees:

| Field | Rows | Why two |
|---|---|---|
| Monochromatic Color | warm–cool, magenta–green | The axes apply independently: the X-T3 and X-T30 have the warm–cool axis alone (`CameraModel.hasMagentaGreenAxis`). |
| White Balance | mode, shift | "Auto R+1 B−1 against Daylight R+1 B−1" and "Daylight R+1 B−1 against Daylight R0 B0" are different disagreements. |
| Grain | strength, size | Size is absent on bodies without a size control and meaningless when the strength is Off. |

Rows render in `DiffRowID` declaration order: by group, then in the order the app lists fields
everywhere else.

Two rows agree when:

- **Tones and exposure bias** are within `RecipeMatcher.toneEpsilon`, so one value arriving at
  different precisions from the editor, a camera slot, a file or the scanner doesn't read as a
  difference.
- **White balance mode** is the same mode, and the same Kelvin when the mode uses one. Two Daylight
  recipes with different remembered temperatures agree, because the camera never reads the
  temperature in that mode.
- **White balance shift** has the same red and blue values.
- Every other row holds the same value.

## Three kinds of nothing

Each side of each row is one of three presences, because the camera treats them differently:

| Presence | Shown as | Means |
|---|---|---|
| `set` | the value | The recipe states a value. |
| `unset` | "Not set" | The recipe declines to state one. A push leaves the slot's own value for an unset field without a default, and a develop leaves the RAF's as-shot value. |
| `notApplicable` | an em dash, with the reason beneath the row | The control doesn't apply on this side (see below). |

Whether a side is set is a plain nil check. An Off the user chose is a value, so a recipe with grain
Off and one with no grain setting differ. That is the opposite of `RecipeCompatibility.isSet`,
which reads Off as absent because it answers whether the camera will ignore a write.

## Statuses

| Status | When | Shown |
|---|---|---|
| `same` | Both set, and they agree | All Settings only |
| `differs` | Both set, and they disagree | Both modes |
| `setOnlyInA`, `setOnlyInB` | One side set, the other unset | Both modes |
| `applicabilityDiffers` | The control applies on one side only | Both modes |
| `neitherSet` | Both unset | Never |
| `neitherApplicable` | The control applies on neither side | Never |

The glyph beside each row carries the status by shape as well as colour, and each row's
accessibility label reads the row, both values and the reason a control doesn't apply.

## Which controls apply

Each side is read against the body its recipe was authored for (`Recipe.authoredForModel`), or
against every field when the recipe names none. The rules are `RecipeApplicability`'s, the same
ones the editor, the read-only settings table, the push warnings and the share card use, and the
body gate runs before any rule that depends on the settings. The reasons a control doesn't apply,
and the note the screen shows for each:

| Reason | Note |
|---|---|
| `monochrome` | Doesn't apply on a monochrome film simulation (Color) |
| `notMonochrome` | Only applies on a monochrome film simulation (Monochromatic Color) |
| `fixedToning` | This film simulation is already toned (Monochromatic Color on Sepia) |
| `noMagentaGreenAxis` | *Recipe* is authored for a body without a magenta–green axis |
| `grainOff` | Only applies when Grain Effect is on (Grain Size) |
| `noGrainSizeControl` | *Recipe* is authored for a body with grain strength only |
| `underPriority` | The camera drives this while D-Range Priority is on (Dynamic Range, Highlight and Shadow Tone) |
| `bodyLacksField` | *Recipe* is authored for a body without this control |

The notes that depend on the body name the recipe, because the two sides of a comparison can be
authored for different bodies.

## The summary line

The line above the rows reads, for example, "3 of 15 differ · 4 don't apply to both"
(`DiffSummary`). The count of rows compared is the rows that differ plus the rows that agree, never
the total row count. The second count is the rows that apply on one side or neither. Rows set on
neither side are left out of both counts. When nothing differs the line turns the accent colour, and
VoiceOver reads it as the recipes agreeing on every setting that applies to both.

## What isn't built

`DiffSide.Origin` has cases for a camera slot, an incoming file and a photo besides a library
recipe, but no screen builds those sides yet: the import review, the push screen and photo matching
(`RecipeMatcher`, which has its own row model) don't use this comparison. The only comparison in
the app is recipe against recipe.
