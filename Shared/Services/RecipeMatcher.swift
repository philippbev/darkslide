import Foundation

/// One row of a photo-vs-recipe comparison. Rows don't map one-to-one onto `RecipeField` — White
/// Balance splits into a `mode` row and a `shift` row, because "Auto R+1 B−1 vs Daylight R+1 B−1"
/// and "Daylight R+1 B−1 vs Daylight R0 B0" are different kinds of disagreement and one collapsed
/// row can't say which.
struct FieldComparison: Identifiable {
    enum Verdict: Equatable {
        case same
        case different
        /// The photo has a value the recipe doesn't.
        case missingInRecipe
        /// The recipe has a value the decoder couldn't read from the photo — the parser's
        /// limitation, not the recipe's, so this is never scored against the recipe.
        case missingInPhoto
        /// Neither side has a value. Not counted as agreement: two unknowns aren't a match, and
        /// treating them as one would let a nearly-empty recipe score 100%.
        case notCompared
    }

    let id: String
    let label: String
    let photoValue: String?
    let recipeValue: String?
    let verdict: Verdict
    /// 0 when the row is shown but not scored: `filmSimulation`, which gates candidates instead,
    /// plus `exposureBias` and `noiseReduction`.
    let weight: Double
}

/// One candidate recipe scored against a photo's decoded settings.
struct RecipeMatch: Identifiable {
    let recipe: Recipe
    /// `recipe.uuid`, not `persistentModelID` — a new SwiftData object's persistent ID mutates on
    /// its first autosave, which would reshuffle a list keyed on it mid-display.
    var id: UUID { recipe.uuid }
    let score: Double
    let matchedWeight: Double
    let comparedWeight: Double
    let rows: [FieldComparison]
    var differences: [FieldComparison] { rows.filter { $0.verdict == .different || $0.verdict == .missingInRecipe } }
}

/// The outcome of comparing a photo against the whole library.
struct RecipeMatchResult {
    enum Tier: Equatable { case exact, close, closest, none }

    let tier: Tier
    let best: RecipeMatch?
    /// Other recipes tied with `best` on score, compared weight and the number of rows the photo
    /// couldn't supply (see `RecipeMatcher.tie`) — a genuine duplicate in the library, not a
    /// ranking artefact. Rendered explicitly rather than picked from arbitrarily, which is the
    /// worse failure mode.
    let tiedWithBest: [RecipeMatch]
    /// Up to two runners-up, for "also close" context.
    let runnersUp: [RecipeMatch]
    /// Recipes that would have scored well but were excluded by the film-simulation gate — so
    /// "nothing matched" can become "nothing uses this film simulation, but 2 recipes match
    /// everything else."
    let simulationNearMisses: [RecipeMatch]
}

/// Compares a photo's decoded `RecipeSettings` against the recipe library. Deliberately separate
/// from `DuplicateResolver`, which asks the binary question "does this exact recipe already exist"
/// for imports; this asks the fuzzy one, "which of my recipes does this photo look like."
enum RecipeMatcher {

    /// Below this compared weight, a recipe can only ever reach `.closest` — it stops a recipe that
    /// sets only, say, Sharpness from scoring a perfect 1.0 on a single weight-1 row and being
    /// announced as an exact match. A full modern-body recipe compares at roughly 25 weight.
    private static let minComparedWeightForRanking = 8.0
    private static let closeScoreThreshold = 0.85
    private static let closeMaxDifferences = 2
    private static let closeMaxDifferenceWeight = 3.0
    static let toneEpsilon = 0.05   // finest real step (−raw/16 at raw=±1) is 0.0625

    // MARK: - Per-field comparison

    /// **Do not** reach for `RecipeCompatibility.isSet` here. It treats an Off grain / Off chrome
    /// effect / Off D-Range Priority as "not set", which is correct for "will the camera ignore
    /// this write" and wrong for matching — an Off read off a photo is a real, meaningful value.
    static func compare(photo: RecipeSettings, recipe: RecipeSettings) -> [FieldComparison] {
        var rows: [FieldComparison] = []

        rows.append(enumRow(id: "filmSimulation", label: "Film Simulation",
                            photo: photo.filmSimulation, recipe: recipe.filmSimulation, weight: 0))

        rows.append(doubleRow(id: "highlightTone", label: "Highlight Tone",
                              photo: photo.highlightTone, recipe: recipe.highlightTone,
                              weight: 3, format: RecipeSettingsFormatter.tone))
        rows.append(doubleRow(id: "shadowTone", label: "Shadow Tone",
                              photo: photo.shadowTone, recipe: recipe.shadowTone,
                              weight: 3, format: RecipeSettingsFormatter.tone))
        rows.append(enumRow(id: "dynamicRange", label: "Dynamic Range",
                            photo: photo.dynamicRange, recipe: recipe.dynamicRange, weight: 3))

        rows.append(contentsOf: whiteBalanceRows(photo: photo.whiteBalance, recipe: recipe.whiteBalance))

        rows.append(intRow(id: "color", label: "Color", photo: photo.color, recipe: recipe.color, weight: 2))
        rows.append(monochromaticColorRow(photo: photo, recipe: recipe))
        rows.append(grainRow(photo: photo.grain, recipe: recipe.grain))
        rows.append(intRow(id: "clarity", label: "Clarity", photo: photo.clarity, recipe: recipe.clarity, weight: 2))

        rows.append(softOffEnumRow(id: "colorChromeEffect", label: "Color Chrome Effect",
                                   photo: photo.colorChromeEffect, recipe: recipe.colorChromeEffect,
                                   off: .off, weight: 1))
        rows.append(softOffEnumRow(id: "colorChromeFXBlue", label: "Color Chrome FX Blue",
                                   photo: photo.colorChromeFXBlue, recipe: recipe.colorChromeFXBlue,
                                   off: .off, weight: 1))
        rows.append(intRow(id: "sharpness", label: "Sharpness",
                           photo: photo.sharpness, recipe: recipe.sharpness, weight: 1))
        rows.append(intRow(id: "highISONR", label: "High ISO NR",
                           photo: photo.highISONR, recipe: recipe.highISONR, weight: 1))
        rows.append(softOffEnumRow(id: "dRangePriority", label: "D-Range Priority",
                                   photo: photo.dRangePriority, recipe: recipe.dRangePriority,
                                   off: .off, weight: 1))

        // Shown, never scored: exposureBias is what this frame used rather than what the recipe
        // prescribes (scoring it would make every photo differ from its own recipe), and the
        // decoder can never produce noiseReduction at all (see PhotoRecipeReader), so scoring it
        // would dock every recipe that happens to set it. A recipe holds it only beside a
        // highISONR — `RecipeSettings` folds a lone one into that field, which is scored.
        rows.append(doubleRow(id: "exposureBias", label: "Exposure Bias",
                              photo: photo.exposureBias, recipe: recipe.exposureBias, weight: 0,
                              format: { String(format: "%+.1f EV", $0) }))
        rows.append(intRow(id: "noiseReduction", label: "Noise Reduction",
                           photo: photo.noiseReduction, recipe: recipe.noiseReduction, weight: 0))

        return rows
    }

    // MARK: - Matching the library

    static func match(photo: RecipeSettings, against recipes: [Recipe]) -> RecipeMatchResult {
        guard !recipes.isEmpty else {
            return RecipeMatchResult(tier: .none, best: nil, tiedWithBest: [], runnersUp: [], simulationNearMisses: [])
        }

        // The film-simulation gate: a recipe cannot be "close" on a different film simulation, so
        // it isn't a candidate at all. Two carve-outs keep the gate from lying: a photo whose film
        // simulation couldn't be decoded drops the gate entirely rather than filtering on a guess,
        // and a recipe with no film simulation set stays eligible (capped at `.closest` below,
        // since it can never claim to agree on the thing being gated).
        let gateOnSimulation = photo.filmSimulation != nil
        let candidates: [Recipe]
        let gatedOut: [Recipe]
        if gateOnSimulation {
            candidates = recipes.filter { $0.settings.filmSimulation == nil || $0.settings.filmSimulation == photo.filmSimulation }
            gatedOut = recipes.filter { $0.settings.filmSimulation != nil && $0.settings.filmSimulation != photo.filmSimulation }
        } else {
            candidates = recipes
            gatedOut = []
        }

        let scored = candidates.map { scoreMatch(photo: photo, recipe: $0) }
        let ranked = sortedByRank(scored)

        let simulationNearMisses = sortedByRank(gatedOut.map { scoreMatch(photo: photo, recipe: $0, excludingSimulationGate: true) })
            .filter { $0.score >= closeScoreThreshold }

        guard let best = ranked.first, best.comparedWeight > 0 else {
            return RecipeMatchResult(tier: .none, best: nil, tiedWithBest: [], runnersUp: [],
                                     simulationNearMisses: Array(simulationNearMisses.prefix(2)))
        }

        let tiedWithBest = ranked.dropFirst().prefix { tie(best, $0) }
        let runnersUp = ranked.dropFirst(1 + tiedWithBest.count).prefix(2)

        return RecipeMatchResult(tier: tier(for: best),
                                 best: best,
                                 tiedWithBest: Array(tiedWithBest),
                                 runnersUp: Array(runnersUp),
                                 simulationNearMisses: Array(simulationNearMisses.prefix(2)))
    }

    private static func scoreMatch(photo: RecipeSettings, recipe: Recipe, excludingSimulationGate: Bool = false) -> RecipeMatch {
        var rows = compare(photo: photo, recipe: recipe.settings)
        if excludingSimulationGate {
            rows.removeAll { $0.id == "filmSimulation" }
        }
        let comparedWeight = rows.reduce(0) { $0 + (isCounted($1.verdict) ? $1.weight : 0) }
        let matchedWeight = rows.reduce(0) { $0 + ($1.verdict == .same ? $1.weight : 0) }
        let score = comparedWeight > 0 ? matchedWeight / comparedWeight : 0
        // A recipe with no film simulation set can't claim to agree with the photo's — it stays a
        // candidate, but is capped so it can never read as exact or close.
        let capped = (recipe.settings.filmSimulation == nil && !excludingSimulationGate) ? min(score, closeScoreThreshold - 0.01) : score
        return RecipeMatch(recipe: recipe, score: capped, matchedWeight: matchedWeight,
                           comparedWeight: comparedWeight, rows: rows)
    }

    private static func isCounted(_ verdict: FieldComparison.Verdict) -> Bool {
        verdict == .same || verdict == .different || verdict == .missingInRecipe
    }

    private static func tier(for match: RecipeMatch) -> RecipeMatchResult.Tier {
        guard match.comparedWeight >= minComparedWeightForRanking else { return .closest }
        let differing = match.rows.filter { $0.verdict == .different || $0.verdict == .missingInRecipe }
        if differing.isEmpty { return .exact }
        if match.score >= closeScoreThreshold, differing.count <= closeMaxDifferences,
           differing.allSatisfy({ $0.weight < closeMaxDifferenceWeight }) {
            return .close
        }
        return match.score > 0 ? .closest : .none
    }

    /// Two matches are a genuine tie — not just close — when they agree through the score,
    /// how much was compared, and how much the decoder couldn't read. Anything looser risks
    /// presenting two meaningfully different recipes as interchangeable.
    private static func tie(_ a: RecipeMatch, _ b: RecipeMatch) -> Bool {
        a.score == b.score && a.comparedWeight == b.comparedWeight
            && missingInPhotoCount(a) == missingInPhotoCount(b)
    }

    private static func missingInPhotoCount(_ match: RecipeMatch) -> Int {
        match.rows.filter { $0.verdict == .missingInPhoto }.count
    }

    private static func sortedByRank(_ matches: [RecipeMatch]) -> [RecipeMatch] {
        matches.sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            if a.comparedWeight != b.comparedWeight { return a.comparedWeight > b.comparedWeight }
            let aMissing = missingInPhotoCount(a), bMissing = missingInPhotoCount(b)
            if aMissing != bMissing { return aMissing < bMissing }
            if a.recipe.updatedAt != b.recipe.updatedAt { return a.recipe.updatedAt > b.recipe.updatedAt }
            if a.recipe.name != b.recipe.name { return a.recipe.name < b.recipe.name }
            return a.recipe.uuid.uuidString < b.recipe.uuid.uuidString
        }
    }

    // MARK: - Row builders

    private static func enumRow<T: RecipeOption>(id: String, label: String, photo: T?, recipe: T?, weight: Double) -> FieldComparison {
        row(id: id, label: label, photo: photo?.displayName, recipe: recipe?.displayName,
            same: photo != nil && recipe != nil && photo == recipe,
            photoIsNil: photo == nil, recipeIsNil: recipe == nil, weight: weight)
    }

    /// Like `enumRow`, but a recipe with no value here reads as agreeing when the photo's value is
    /// the "off" case. AI scans and recipe files leave the chrome effects and D-Range Priority nil
    /// when they don't mention them, while a photo always yields a real value — without this, every
    /// such recipe loses these rows to a modelling artefact rather than a real difference. The
    /// editor saves Off for these fields, so a recipe saved there never depends on it.
    private static func softOffEnumRow<T: RecipeOption & Equatable>(id: String, label: String, photo: T?, recipe: T?, off: T, weight: Double) -> FieldComparison {
        if recipe == nil, photo == off {
            return FieldComparison(id: id, label: label, photoValue: photo?.displayName,
                                   recipeValue: nil, verdict: .same, weight: weight)
        }
        return enumRow(id: id, label: label, photo: photo, recipe: recipe, weight: weight)
    }

    private static func intRow(id: String, label: String, photo: Int?, recipe: Int?, weight: Double) -> FieldComparison {
        row(id: id, label: label, photo: photo.map(RecipeSettingsFormatter.signed),
            recipe: recipe.map(RecipeSettingsFormatter.signed),
            same: photo != nil && recipe != nil && photo == recipe,
            photoIsNil: photo == nil, recipeIsNil: recipe == nil, weight: weight)
    }

    private static func doubleRow(id: String, label: String, photo: Double?, recipe: Double?, weight: Double, format: (Double) -> String) -> FieldComparison {
        let same = photo != nil && recipe != nil && abs(photo! - recipe!) < toneEpsilon
        return row(id: id, label: label, photo: photo.map(format), recipe: recipe.map(format),
                  same: same, photoIsNil: photo == nil, recipeIsNil: recipe == nil, weight: weight)
    }

    private static func grainRow(photo: GrainEffect?, recipe: GrainEffect?) -> FieldComparison {
        let weight = 2.0
        // The soft-Off equivalence of `softOffEnumRow`, for grain: AI scans and recipe files leave
        // grain nil when they don't mention it, while a photo always records its strength.
        if recipe == nil, let photo, photo.strength == .off {
            return FieldComparison(id: "grain", label: "Grain Effect", photoValue: grainText(photo),
                                   recipeValue: nil, verdict: .same, weight: weight)
        }
        guard let photo, let recipe else {
            return row(id: "grain", label: "Grain Effect",
                      photo: photo.map(grainText), recipe: recipe.map(grainText),
                      same: false, photoIsNil: photo == nil, recipeIsNil: recipe == nil, weight: weight)
        }
        // Both Off agree regardless of a remembered size. Otherwise, if either side's size is nil
        // — a body with only a strength control, no size — compare strength alone: a forced
        // mismatch on a field that body doesn't have would be a model artefact, not a real one.
        let same: Bool
        if photo.strength == .off && recipe.strength == .off {
            same = true
        } else if photo.size == nil || recipe.size == nil {
            same = photo.strength == recipe.strength
        } else {
            same = photo.strength == recipe.strength && photo.size == recipe.size
        }
        return row(id: "grain", label: "Grain Effect", photo: grainText(photo), recipe: grainText(recipe),
                  same: same, photoIsNil: false, recipeIsNil: false, weight: weight)
    }

    private static func grainText(_ grain: GrainEffect) -> String {
        if grain.strength == .off { return "Off" }
        if let size = grain.size { return "\(grain.strength.displayName), \(size.displayName)" }
        return grain.strength.displayName
    }

    private static func monochromaticColorRow(photo: RecipeSettings, recipe: RecipeSettings) -> FieldComparison {
        let weight = 2.0
        let photoSet = photo.monochromaticColorWC != nil || photo.monochromaticColorMG != nil
        let recipeSet = recipe.monochromaticColorWC != nil || recipe.monochromaticColorMG != nil
        let same = photoSet && recipeSet
            && (photo.monochromaticColorWC ?? 0) == (recipe.monochromaticColorWC ?? 0)
            && (photo.monochromaticColorMG ?? 0) == (recipe.monochromaticColorMG ?? 0)
        return row(id: "monochromaticColor", label: "Monochromatic Color",
                  photo: photoSet ? monochromaticText(photo) : nil,
                  recipe: recipeSet ? monochromaticText(recipe) : nil,
                  same: same, photoIsNil: !photoSet, recipeIsNil: !recipeSet, weight: weight)
    }

    private static func monochromaticText(_ settings: RecipeSettings) -> String {
        var parts: [String] = []
        if let wc = settings.monochromaticColorWC { parts.append("WC \(RecipeSettingsFormatter.signed(wc))") }
        if let mg = settings.monochromaticColorMG { parts.append("MG \(RecipeSettingsFormatter.signed(mg))") }
        return parts.joined(separator: ", ")
    }

    private static func whiteBalanceRows(photo: WhiteBalance?, recipe: WhiteBalance?) -> [FieldComparison] {
        let modeText: (WhiteBalance) -> String = { wb in
            wb.mode.usesKelvin ? (wb.kelvin.map { "\($0)K" } ?? wb.mode.displayName) : wb.mode.displayName
        }
        let modeSame = photo != nil && recipe != nil
            && photo!.mode == recipe!.mode
            && (!photo!.mode.usesKelvin || photo!.kelvin == recipe!.kelvin)
        let modeRow = row(id: "whiteBalance.mode", label: "White Balance",
                          photo: photo.map(modeText), recipe: recipe.map(modeText),
                          same: modeSame, photoIsNil: photo == nil, recipeIsNil: recipe == nil, weight: 3)

        let shiftText: (WhiteBalance) -> String = { "R\(RecipeSettingsFormatter.signed($0.shiftRed)) B\(RecipeSettingsFormatter.signed($0.shiftBlue))" }
        let shiftSame = photo != nil && recipe != nil
            && photo!.shiftRed == recipe!.shiftRed && photo!.shiftBlue == recipe!.shiftBlue
        let shiftRow = row(id: "whiteBalance.shift", label: "WB Shift",
                           photo: photo.map(shiftText), recipe: recipe.map(shiftText),
                           same: shiftSame, photoIsNil: photo == nil, recipeIsNil: recipe == nil, weight: 2)

        return [modeRow, shiftRow]
    }

    private static func row(id: String, label: String, photo: String?, recipe: String?, same: Bool,
                            photoIsNil: Bool, recipeIsNil: Bool, weight: Double) -> FieldComparison {
        let verdict: FieldComparison.Verdict
        switch (photoIsNil, recipeIsNil) {
        case (true, true): verdict = .notCompared
        case (false, true): verdict = .missingInRecipe
        case (true, false): verdict = .missingInPhoto
        case (false, false): verdict = same ? .same : .different
        }
        return FieldComparison(id: id, label: label, photoValue: photo, recipeValue: recipe,
                               verdict: verdict, weight: weight)
    }
}
