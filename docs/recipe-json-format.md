# Fuji Cookbook — Recipe Import/Export JSON Format

The field names below are the exact JSON keys. The models use Swift's default coding
keys, so JSON keys are the camelCase property names exactly as shown.

Exported files use the `.fujirecipe` extension and are plain, pretty-printed JSON. The
same format is used for three kinds of export — a single recipe, a combined multi-recipe
file, and a full backup — and the importer accepts all of them. The app names each export after
its recipe or collection and the local date, such as `Fuji Cookbook Backup 2026-10-15.fujirecipe`;
the importer ignores the file name.

## 1. File envelope

Every file is a single JSON object with a versioned header plus **either** one recipe
or many. A full backup additionally carries chapters. All shapes are accepted by the importer.

| Field | Type | Required | Notes |
|---|---|---|---|
| `schema` | string | ✅ | Must be exactly `"fuji-recipe"`. Anything else → rejected. |
| `version` | integer | ✅ | Currently `1`. A higher number requests an app update. Values at or below `1` retain the existing decoding behavior; no field transformations are currently applied. |
| `recipe` | object | one of these | A single `PortableRecipe` (see §2). |
| `recipes` | array | one of these | An array of `PortableRecipe` objects — **this is bulk import**. |
| `chapters` | array | optional | An array of `PortableChapter` objects (see §6). Present only in a **full backup** of a library that has chapters. Additive — older app versions ignore it. |

If both `recipe` and `recipes` are present, `recipes` wins. The file must contain
**at least one** recipe or it errors as empty.

**Single:**
```json
{ "schema": "fuji-recipe", "version": 1, "recipe": { /* … */ } }
```

**Bulk:**
```json
{ "schema": "fuji-recipe", "version": 1, "recipes": [ { /* … */ }, { /* … */ } ] }
```

**Full backup:**
```json
{ "schema": "fuji-recipe", "version": 1, "recipes": [ /* … */ ], "chapters": [ /* … */ ] }
```

## 2. The recipe object (`PortableRecipe`)

| Field | Type | Required | Notes |
|---|---|---|---|
| `name` | string | ✅ | Display name. Duplicate detection matches it trimmed and case-insensitively, or matches identical settings under any name (§7). |
| `settings` | object | ✅ | The camera parameters — see §3. |
| `uuid` | string (UUID) | optional | Stable recipe identity. Written only in **full backups** (§6), where chapters re-link to their recipes by uuid; single/combined exports omit it. Optional on import — a fresh id is minted regardless, so this never collides with existing inventory. |
| `cameraName` | string | optional | Camera-slot name (limited character set). Additive and backward-compatible. Every export writes it: the recipe's own slot name, or the one generated from `name`. A file without it imports with a generated slot name. |
| `cameraNameIsCustom` | boolean | optional | Whether `cameraName` is the author's own choice rather than the name generated from `name`. Every export writes it. When absent, a present `cameraName` counts as custom, as in files written before the key existed. On **overwrite**, only a custom name replaces the local slot name. |
| `credit` | string | optional | Who the recipe is by, carried with the file so attribution survives sharing. Trimmed on export (`Recipe.displayCredit`); omitted when empty or whitespace-only. Additive and backward-compatible. |
| `authoredForModel` | string | optional | Camera profile the recipe was built for (e.g. an X-T5 id), shown as "Camera Profile": the editor shows that body's fields and ranges. Not a compatibility verdict. Preserved verbatim when unrecognized. |
| `notes` | string | optional | Free text. Omitted when empty. |
| `tags` | array of strings | optional | Organizational tags. Omitted when empty. |
| `unsupportedFields` | object | optional | Pass-through bag for fields this app version doesn't model — preserved verbatim and re-exported. See §5. |
| `photos` | array | optional | Embedded sample photos (`PortablePhoto`, see §4). Present only when the user exports *with* photos; recipe-only exports omit the key. Additive — older app versions ignore it. |

## 3. The `settings` object (`RecipeSettings`)

**Every field is optional.** Omit a field entirely, or give it `null`, to mean "not set / not part
of this recipe." Enum values are stable strings in upper case with underscores, as listed below
(`ACROS_Ye` and `MONOCHROME_Ye` keep their lower-case `e`), not camera byte codes. An enum value this
version doesn't list reads as not set, and the rest of the recipe imports; a value of the wrong JSON
type, such as a number where a string belongs or `1.5` for an integer, rejects the file (§7).

### Scalar fields

| Field | Type | Values | Notes |
|---|---|---|---|
| `filmSimulation` | string enum | see list | Base simulation. |
| `highlightTone` | number | menu value | Whole steps, or half steps on bodies that have them. |
| `shadowTone` | number | menu value | Whole steps, or half steps on bodies that have them. |
| `color` | integer | menu value | Saturation. **Not** applicable to monochrome sims. |
| `sharpness` | integer | menu value | |
| `highISONR` | integer | menu value | High ISO noise reduction. |
| `clarity` | integer | menu value | |
| `exposureBias` | number | EV | A shooting suggestion. A push never writes it. |
| `noiseReduction` | integer | menu value | The older name for High ISO NR: bodies up to the X-T3 call the setting Noise Reduction ([X-T3 manual](https://fujifilm-dsc.com/en/manual/x-t3/menu_shooting/image_quality_setting/index.html)). A file carrying it without `highISONR` imports with the value as `highISONR`; one carrying both keeps both, and only such a recipe exports the key. The camera setting is High ISO NR (`0xD1A1` in the [Fujifilm PTP reference](https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/02-properties.md)); a push never writes this one. |
| `monochromaticColorWC` | integer | menu value, warm–cool | ACROS/Monochrome sims on bodies with toning. Explicit zero means neutral. |
| `monochromaticColorMG` | integer | menu value, magenta–green | ACROS/Monochrome sims on every body with toning except the X-T3, X-T30 and a GFX100 before firmware 4.00. Explicit zero means neutral. |

Numeric values are the camera menu's own numbers: a Highlight of −1.5 is `-1.5`. The valid range
and step differ by body, so the format sets none; a file may hold any number within the bounds in
§7. Before a push or a develop, the app rounds each tone, Color, Sharpness, High ISO NR, Clarity
and Monochromatic Color value to the connected body's step and clamps it to that body's range, and
the push screen says which values it changed. A value goes through unchanged on a body whose range
the app doesn't know.

### `filmSimulation` allowed values
```
PROVIA, VELVIA, ASTIA, CLASSIC_CHROME, PRO_NEG_HI, PRO_NEG_STD,
CLASSIC_NEG, NOSTALGIC_NEG, ETERNA, ETERNA_BLEACH_BYPASS, REALA_ACE,
ACROS, ACROS_Ye, ACROS_R, ACROS_G,
MONOCHROME, MONOCHROME_Ye, MONOCHROME_R, MONOCHROME_G, SEPIA
```
`ACROS*` and `MONOCHROME*` use `monochromaticColor*` on bodies that support toning, not `color`.
`SEPIA` supports neither saturation nor adjustable monochrome toning. An omitted toning axis is
not set; an explicit zero requests neutral toning on that axis. Camera writes apply that zero only
where the body has the axis.

### `dynamicRange` / `dRangePriority`
- `dynamicRange`: `DR_AUTO`, `DR100`, `DR200`, `DR400`
- `dRangePriority`: `OFF`, `AUTO`, `WEAK`, `STRONG`

### `colorChromeEffect` / `colorChromeFXBlue`
Each: `OFF`, `WEAK`, `STRONG`

### `grain` (nested object)
| Field | Type | Required | Values |
|---|---|---|---|
| `strength` | string | to set grain | `OFF`, `WEAK`, `STRONG`. Missing, null or a value this version doesn't list means no grain setting. |
| `size` | string | optional | `SMALL`, `LARGE` (omit on older bodies with strength-only grain). A value this version doesn't list reads as absent; the strength still applies. |

```json
"grain": { "strength": "STRONG", "size": "LARGE" }
```

### `whiteBalance` (nested object)
| Field | Type | Required | Notes |
|---|---|---|---|
| `mode` | string | to set white balance | See list below. Missing or null means no white-balance setting. |
| `shiftRed` | integer | optional on import | Red–Cyan shift; defaults to `0`. Exports include it. |
| `shiftBlue` | integer | optional on import | Blue–Amber shift; defaults to `0`. Exports include it. |
| `kelvin` | integer | optional | Only meaningful when `mode` is `KELVIN` |

`mode` values:
```
AUTO, AUTO_WHITE_PRIORITY, AUTO_AMBIENCE_PRIORITY, DAYLIGHT, SHADE,
FLUORESCENT_1, FLUORESCENT_2, FLUORESCENT_3, INCANDESCENT, UNDERWATER,
KELVIN
```

`AUTO_WHITE_PRIORITY` and `AUTO_AMBIENCE_PRIORITY` exist only on bodies whose manuals list them
(the X-T4, X-S10, X-E4, X-T30 II and every X-Processor 5 body, and the GFX bodies but the GFX100
and the GFX 50S and 50R); `UNDERWATER` and `KELVIN` on every body
but the X-M1. The app keeps the mode on other bodies, shows it as a change on the Works With card and
warns before a push.

`CUSTOM_1`, `CUSTOM_2` and `CUSTOM_3` were accepted by earlier versions. A custom white balance is a
measurement stored on one camera, not a recipe parameter, so a file carrying one now imports with no
white balance; the rest of the recipe is unaffected. Any `mode` this version doesn't list is treated
the same way.

```json
"whiteBalance": { "mode": "KELVIN", "shiftRed": -1, "shiftBlue": 2, "kelvin": 5500 }
```

## 4. `photos` (embedded sample photos, `PortablePhoto`)

An optional array of sample photos carried inside a recipe. Each entry is a small object:

| Field | Type | Required | Notes |
|---|---|---|---|
| `data` | string | ✅ | Base64-encoded image bytes. Exports contain the image stored on-device: normally the compressed, resized JPEG, though a photo stored by an older version can be a PNG or a larger JPEG and is exported as it is. |

```json
"photos": [ { "data": "/9j/4AAQSkZJRgABAQ…" } ]
```

Photos are only written when the user chooses **Export with photos** (they make the file larger).
On import, valid images are prepared at a maximum long edge of 1,280 pixels, with a 240-pixel
thumbnail. A valid JPEG already within the stored size keeps its original bytes, avoiding another
lossy compression pass when restoring a backup. Other decodable images are normalized to JPEG.

Invalid Base64 or undecodable image data is skipped, with a warning on that recipe in the import
review. The photo-count and byte limits in §7 still reject the file as a whole; they never silently
truncate a photo list.

On **overwrite**, the photo payload determines what happens to existing samples:

| Incoming `photos` | Result |
|---|---|
| Key omitted | Keep existing photos. |
| `[]` | Clear existing photos. |
| Nonempty, all entries invalid | Keep existing photos and show a warning. |
| One or more valid entries | Replace with the valid photos, in their original order; warn about skipped entries. |

## 5. `unsupportedFields` (pass-through)

A free-form object mapping a key to any JSON value (string, number, bool, object,
array, null). Use it to carry parameters a future/other camera has that this app
version doesn't model — they're preserved and re-exported rather than dropped. Values
keep their meaning, not their formatting: numbers are held as double-precision floating
point, so an integer beyond 2⁵³ loses precision.

```json
"unsupportedFields": { "someNewToggle": "ON", "futureValue": 3 }
```

## 6. `chapters` (full backups, `PortableChapter`)

A full backup includes a top-level `chapters` array alongside `recipes`. Each chapter
groups recipes by their stable `uuid`:

| Field | Type | Required | Notes |
|---|---|---|---|
| `name` | string | ✅ | Chapter display name. |
| `recipeUUIDs` | array of strings (UUID) | ✅ | Ordered recipe identities this chapter groups, matching the `uuid` of recipes in the same file. |

```json
"chapters": [ { "name": "Travel 2025", "recipeUUIDs": ["…uuid-a…", "…uuid-b…"] } ]
```

On restore, the importer remaps these references to the recipes as they're imported
(`RecipeImporter.applyBatch`), rebuilding the chapters. A recipe the user skips maps to the
library recipe it matched. References that don't resolve to an imported or matched recipe are
dropped, and so is a chapter left with none. A chapter whose name and set of recipes match one
already in the library is not added again. A chapter holds at most seven recipes
(`Chapter.maxSlots`), one per camera slot; a longer list keeps its first seven.

## 7. Validation behavior (important for bulk)

File validation and photo preparation finish **before the import review or any library changes**.
The following reject the entire file:

- Invalid JSON, a `schema` other than `"fuji-recipe"`, or a version newer than the app supports.
- No recipes, a missing required field (such as `name` or `settings`), or a field type that cannot
  be decoded. The nested grain and white-balance defaults described in §3 still apply.
- A decoded numeric setting that is not finite or is outside −2,147,483,648…2,147,483,647, including
  numeric white-balance fields. These are representation and arithmetic bounds, not camera ranges.
- Any resource limit below being exceeded.

Two things are dropped without rejecting the file: an enum value this version doesn't list, which
reads as not set (§3), and chapter references beyond what a chapter holds (§6).

| Resource | Limit per imported file |
|---|---|
| Complete JSON input, including Base64 text | 256 MiB |
| Recipes | 10,000 |
| Chapters | 10,000 |
| Supplied photos per recipe, including invalid entries | 5 |
| Each image after Base64 decoding, measured as image file bytes | 32 MiB |
| All prepared images and thumbnails combined | 256 MiB |

One MiB is 1,048,576 bytes. Reads enforce the input limit as bytes arrive, including files that grow
or have no reliable size metadata. A limit error identifies what to reduce; the importer does not
silently drop recipes, whole chapters or excess photos.

Exports check the same known-setting numeric bounds and resource limits. Unsafe numeric settings
are rejected before JSON encoding, with a message identifying the recipe and field; the stored
recipe is left unchanged. Photo budgets use the images import would normalize and the thumbnails
it would regenerate, rather than assuming the stored thumbnail sizes will match.

Counts, numeric settings and photo budgets are checked before JSON encoding. The complete encoded
JSON size is checked afterwards, before a file is written. Like import, this runs off the UI thread
with progress and cancellation. If a backup exceeds a resource budget,
export without sample photos or split it into smaller recipe groups.

Import does not clamp or round settings to a camera's supported range. Ordinary out-of-camera-range
values remain available for the existing compatibility warnings and adjustments when using a
camera. Unrecognized `authoredForModel` identifiers and the `unsupportedFields` bag are preserved;
numbers in that bag are not constrained by the known-setting bounds above.

Preparation runs off the UI thread with progress and cancellation. Prepared images are staged in
temporary files until review finishes. Invalid image contents are the recoverable exception to
file rejection: they are skipped with the warnings and overwrite rules in §4.

After preparation, each recipe is reviewed individually for duplicates, where you choose **skip**,
**overwrite**, or **keep both** per recipe. A recipe matches when its name does, trimmed and
case-insensitively, or when its settings are identical under any name. **Overwrite** replaces the
local recipe's name and settings. A `notes`, `tags` or `credit` the file leaves out keeps the local
value; `authoredForModel` and `unsupportedFields` are taken from the file, so leaving them out
clears them. Photos follow §4, and the slot name follows `cameraNameIsCustom` (§2).

## 8. Examples

### Bulk recipes

```json
{
  "schema": "fuji-recipe",
  "version": 1,
  "recipes": [
    {
      "name": "Classic Chrome Everyday",
      "authoredForModel": "X-T5",
      "notes": "Good for overcast street.",
      "tags": ["street", "daily"],
      "settings": {
        "filmSimulation": "CLASSIC_CHROME",
        "dynamicRange": "DR400",
        "whiteBalance": { "mode": "DAYLIGHT", "shiftRed": -1, "shiftBlue": -2 },
        "highlightTone": -1.0,
        "shadowTone": 1.0,
        "color": 1,
        "sharpness": -1,
        "highISONR": -2,
        "clarity": 0,
        "grain": { "strength": "WEAK", "size": "SMALL" },
        "colorChromeEffect": "STRONG",
        "colorChromeFXBlue": "WEAK"
      }
    },
    {
      "name": "ACROS Night",
      "settings": {
        "filmSimulation": "ACROS_R",
        "dynamicRange": "DR200",
        "whiteBalance": { "mode": "AUTO", "shiftRed": 0, "shiftBlue": 0 },
        "monochromaticColorWC": 2,
        "highlightTone": 2.0,
        "shadowTone": 2.0,
        "sharpness": 0,
        "highISONR": -4,
        "clarity": 2,
        "grain": { "strength": "STRONG", "size": "LARGE" }
      }
    }
  ]
}
```

### Full backup (recipes + chapters)

```json
{
  "schema": "fuji-recipe",
  "version": 1,
  "recipes": [
    {
      "name": "Classic Chrome Everyday",
      "uuid": "11111111-1111-1111-1111-111111111111",
      "cameraName": "C-CHROME",
      "settings": { "filmSimulation": "CLASSIC_CHROME", "dynamicRange": "DR400" }
    },
    {
      "name": "ACROS Night",
      "uuid": "22222222-2222-2222-2222-222222222222",
      "settings": { "filmSimulation": "ACROS_R", "dynamicRange": "DR200" }
    }
  ],
  "chapters": [
    {
      "name": "Everyday",
      "recipeUUIDs": [
        "11111111-1111-1111-1111-111111111111",
        "22222222-2222-2222-2222-222222222222"
      ]
    }
  ]
}
```

## Source of truth

This format is defined in:
- `Shared/Models/RecipeFile.swift` — envelope, schema constants, `PortableRecipe`, `PortablePhoto`, `PortableChapter`
- `Shared/Models/RecipeSettings.swift` — settings payload
- `Shared/Models/RecipeEnums.swift` — enum string values
- `Shared/Models/JSONValue.swift` — `unsupportedFields` value type
- `Shared/Services/RecipePortability.swift` — encode/decode, validation, and schema migration
- `Shared/Services/RecipeImportPreparation.swift` — import resource limits and photo preparation
- `Shared/Services/RecipeSettingsPortabilityValidation.swift` — numeric bounds
- `Shared/Services/RecipeExportValidation.swift` — export checks
- `Shared/Services/RecipeImporter.swift` — duplicate resolution, overwrite and chapter restore
- `Shared/Support/PhotoProcessing.swift` — photo size and thumbnail
- `FujiCookbook/Services/RecipeExporter.swift` — `.fujirecipe` file writing (single / combined / backup)
