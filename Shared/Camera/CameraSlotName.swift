import Foundation

/// The rule for what a Fujifilm custom-slot name may hold, in one place.
///
/// Verified on an X-T50: **25 characters**, drawn from **printable ASCII** (`0x20` space through
/// `0x7E` tilde, with no gaps). Not `CharacterSet.alphanumerics`, which is the Unicode set and
/// would pass `é`, `Ω` and `日` through to the wire as UTF-16 while rejecting most of the
/// punctuation the camera does take.
///
/// Nothing here is camera-specific on purpose. A default slot name is generated when a recipe is
/// saved, which is long before any camera is attached, so the rule can't depend on a connected body.
/// `CameraModel.sanitizedSlotName` stays as the per-model guard at the wire, and is fed from here.
enum CameraSlotName {
    /// Characters the camera stores. Verified on X-T50.
    static let maxLength = 25

    /// What to call a recipe whose name survives sanitizing with nothing left.
    static let fallbackName = "Recipe"

    /// The allowed set as a `CharacterSet`, purely to satisfy `CameraModel.slotNameAllowedCharacters`'s
    /// existing type. Membership tests in this file use `isAllowed` instead — see its note.
    static let allowedCharacters = CharacterSet(charactersIn: " "..."~")

    /// Printable-ASCII test as a raw scalar comparison.
    ///
    /// Deliberately not `CharacterSet.contains`, which can bridge to `NSCharacterSet` and is far more
    /// than two range checks. It runs once per character on every keystroke in the editor's
    /// slot-name field, through ``filterForEntry(_:)`` and ``firstDisallowed(in:)``.
    @inline(__always)
    static func isAllowed(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value >= 0x20 && scalar.value <= 0x7E
    }

    // MARK: Canonical form

    /// The exact string the camera would store for `raw`.
    ///
    /// Pipeline order matters: fold diacritics → filter → collapse runs of spaces → truncate → trim.
    /// Filtering before truncating is what keeps `prefix` from spending its budget on characters that
    /// were about to be dropped; collapsing matters because stripping an em dash out of
    /// `"Classic Chrome — Jan 3"` otherwise leaves a double space where it used to be.
    ///
    /// Not for use on every keystroke — it trims, so it would eat a space the moment you typed one.
    /// The editor wants ``filterForEntry(_:)``.
    static func sanitize(_ raw: String) -> String {
        isCanonical(raw) ? raw : canonicalize(raw)
    }

    /// True when `raw` is already exactly what `canonicalize` would return, so `sanitize` can hand
    /// back the input and allocate nothing at all.
    ///
    /// This predicate has to be a genuine fixed point of `canonicalize`. A laxer version — say just
    /// "short enough and all-allowed" — would pass `" Foo "` through untouched, and the two paths
    /// would then disagree about the same string depending on which one ran.
    private static func isCanonical(_ raw: String) -> Bool {
        let bytes = raw.utf8
        // Every allowed character is one UTF-8 byte, so a byte count over the cap settles it without
        // walking the string; a multi-byte scalar fails the range check below anyway.
        guard !bytes.isEmpty, bytes.count <= maxLength else { return false }
        var lastWasSpace = true   // seeded true so a leading space is rejected by the same test
        for byte in bytes {
            guard byte >= 0x20, byte <= 0x7E else { return false }
            let isSpace = byte == 0x20
            if isSpace && lastWasSpace { return false }   // leading space, or a doubled one
            lastWasSpace = isSpace
        }
        return !lastWasSpace   // trailing space
    }

    /// `raw` with its diacritics folded away, so `é` reaches the camera as `e` instead of being
    /// dropped.
    ///
    /// POSIX rather than `.current`: diacritic folding is locale-sensitive, and a Turkish locale
    /// folds a dotless i differently, which would make a recipe's slot name depend on the phone's
    /// region setting.
    static func foldingDiacritics(_ raw: String) -> String {
        raw.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func canonicalize(_ raw: String) -> String {
        let folded = foldingDiacritics(raw)
        var result = ""
        result.reserveCapacity(Swift.min(folded.utf8.count, maxLength))
        // A space is only committed once a keeper follows it, which drops leading and trailing runs
        // without a second pass.
        var pendingSpace = false
        for scalar in folded.unicodeScalars {
            guard isAllowed(scalar) else { continue }
            if scalar == " " {
                pendingSpace = !result.isEmpty
                continue
            }
            if pendingSpace {
                result.append(" ")
                pendingSpace = false
            }
            result.unicodeScalars.append(scalar)
        }
        return result.count > maxLength ? truncated(result) : result
    }

    /// Cut to `maxLength`, keeping a trailing " (2)"-style counter if the name carries one.
    ///
    /// `RecipeImporter` disambiguates a name collision by appending " (2)" to the recipe name. A
    /// plain truncation throws that suffix away — "A Very Long Recipe Name That Overflows" and its
    /// "(2)" copy both cut down to "A Very Long Recipe Name T", so the two recipes reach the camera
    /// under one identical label, which is the exact outcome the suffix existed to prevent.
    ///
    /// Deciding this from the string alone, rather than from what else is in the library, is what
    /// keeps a recipe generating the same slot name on every synced device.
    private static func truncated(_ value: String) -> String {
        // `counter.count < maxLength` is load-bearing, not defensive: without it a counter wider
        // than the whole budget makes the `prefix` below negative, which traps.
        guard let counter = trailingCounter(in: value),
              counter.count < maxLength else { return plainTruncated(value) }
        let base = trimmingTrailingSpaces(String(value.dropLast(counter.count)
                                                      .prefix(maxLength - counter.count)))
        // A counter so wide it leaves nothing to label is worse than no counter at all.
        guard !base.isEmpty else { return plainTruncated(value) }
        return base + counter
    }

    private static func plainTruncated(_ value: String) -> String {
        // The cut can land just after a space; a trailing blank would go to the camera verbatim.
        trimmingTrailingSpaces(String(value.prefix(maxLength)))
    }

    /// The trailing " (12)" of a name, or nil. Requires the leading space, so a name that simply
    /// ends in a parenthesis — "Shot Wide (open)" — isn't mistaken for a disambiguated one.
    private static func trailingCounter(in value: String) -> String? {
        guard value.hasSuffix(")") else { return nil }
        var digits = 0
        var index = value.index(before: value.endIndex)   // the ")"
        while index > value.startIndex {
            index = value.index(before: index)
            let character = value[index]
            if character.isNumber {
                digits += 1
                continue
            }
            guard character == "(", digits > 0 else { return nil }
            guard index > value.startIndex,
                  value[value.index(before: index)] == " " else { return nil }
            return String(value[value.index(before: index)...])
        }
        return nil
    }

    private static func trimmingTrailingSpaces(_ value: String) -> String {
        var trimmed = value
        while trimmed.hasSuffix(" ") { trimmed.removeLast() }
        return trimmed
    }

    // MARK: Live entry

    /// The filter for a text field the user is actively typing in: drops disallowed characters and
    /// enforces the length cap, and **nothing else**.
    ///
    /// Spacing is left alone on purpose. `sanitize` trims and collapses, so running it per keystroke
    /// would delete the space in "Kodak " the instant it was typed and make it impossible to type a
    /// two-word name. Whitespace gets its canonical treatment once, on save.
    static func filterForEntry(_ raw: String) -> String {
        let folded = foldingDiacritics(raw)
        var result = ""
        result.reserveCapacity(Swift.min(folded.utf8.count, maxLength))
        for scalar in folded.unicodeScalars where isAllowed(scalar) {
            if result.count == maxLength { break }
            result.unicodeScalars.append(scalar)
        }
        return result
    }

    /// The first character the camera would refuse, for a message that can name it.
    ///
    /// Reported as the user typed it, before folding — telling someone their `é` was rejected is
    /// more use than reporting the `e` it became.
    static func firstDisallowed(in raw: String) -> Character? {
        raw.first { character in
            character.unicodeScalars.contains { !isAllowed($0) }
        }
    }

    // MARK: Generation

    /// The default slot name for a recipe called `name`, guaranteed non-empty: a push names the bank
    /// it writes, and this is the name it uses when the user hasn't typed one.
    ///
    /// Folding rescues `café`, but not `ß`, `ø`, `đ`, or any CJK, so a library named entirely in
    /// Japanese would otherwise collapse to one shared fallback. `fallback` is the recipe's film
    /// simulation, which at least distinguishes those recipes from each other.
    static func generate(from name: String, fallback: String? = nil) -> String {
        let generated = sanitize(name)
        if !generated.isEmpty { return generated }
        if let fallback {
            let sanitizedFallback = sanitize(fallback)
            if !sanitizedFallback.isEmpty { return sanitizedFallback }
        }
        return fallbackName
    }
}
