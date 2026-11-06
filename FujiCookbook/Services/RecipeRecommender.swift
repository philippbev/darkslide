import Foundation

/// Errors surfaced while asking the model to pick recipes from the library.
enum RecipeRecommendError: LocalizedError {
    case notConfigured(AIProvider)
    case noModelSelected(AIProvider)
    case emptyRequest
    case emptyLibrary
    case requestFailed(provider: AIProvider, detail: String)
    case http(provider: AIProvider, status: Int, message: String, isAuthFailure: Bool)
    case refused
    case truncated
    case noPicks

    var errorDescription: String? {
        switch self {
        case .notConfigured(let provider):
            return "Recipe ideas aren't set up. Turn on AI features in Settings and add your \(provider.displayName) API key."
        case .noModelSelected(let provider):
            return "No model is chosen for ideas. Open Settings and pick one of \(provider.displayName)'s models."
        case .emptyRequest:
            return "Describe your shooting plans, or pick a few recipes to build around."
        case .emptyLibrary:
            return "Your library is empty. Add some recipes first — Ideas picks from what you already have."
        case .requestFailed(let provider, let detail):
            return "Couldn't reach \(provider.displayName): \(detail)"
        case .http(let provider, let status, let message, let isAuthFailure):
            // Whether a status means "bad key" is the provider's call, not a fixed 401.
            if isAuthFailure {
                return "Your \(provider.displayName) API key was rejected (\(status)). Check it in Settings."
            }
            if status == 429 {
                return "Rate limited by \(provider.displayName) (429). Try again in a moment."
            }
            return "\(provider.displayName) returned an error (\(status)): \(message)"
        case .refused:
            return "The model declined this request."
        case .truncated:
            return "The model ran out of room before it finished choosing. Try another model in Settings."
        case .noPicks:
            return "No recommendations came back. Try again, or pick a different model in Settings."
        }
    }
}

/// A full recommendation for one request.
struct RecommendationResult {
    var title: String
    var summary: String?
    var picks: [RecipePick]
    /// Situations the request calls for that the library can't cover, in the model's words.
    var gaps: [String]
}

/// Asks the selected AI provider to assemble a chapter of recipes **from the user's own library**
/// for their shooting plans — and, when the user has pinned recipes they already know they want, to
/// analyse what that pinned set covers and fill the remaining slots with recipes that cover what it
/// doesn't. Non-destructive: nothing changes in the library or chapters unless the user saves the
/// result as a chapter.
///
/// A forced `recommend_recipes` tool call whose `id` field is an enum of the library's actual recipe
/// UUIDs steers the model to existing recipes only (see ``AIClient``). How hard a constraint that
/// is varies by provider, so every returned id is validated against the library below regardless.
enum RecipeRecommender {
    private static let toolName = "recommend_recipes"

    /// A snapshot of one library recipe as shown to the model. Built on the main actor (Recipe is
    /// SwiftData-backed), then safe to carry into the request off the UI.
    struct LibraryEntry {
        let uuid: UUID
        let name: String
        let settingsSummary: String
        let notes: String?
        let tags: [String]

        @MainActor
        init(_ recipe: Recipe) {
            uuid = recipe.uuid
            name = recipe.name
            settingsSummary = RecipeSettingsFormatter.rows(for: recipe.settings)
                .map { "\($0.field.displayName): \($0.value)" }
                .joined(separator: "; ")
            // 300 is an allowance with no recorded reason.
            notes = recipe.notes.isEmpty ? nil : String(recipe.notes.prefix(300))
            tags = recipe.tags
        }
    }

    /// Picks recipes from `library` for a chapter, every anchor included. Every pick is a library
    /// recipe, at most once. Throws `RecipeRecommendError`.
    ///
    /// - Parameters:
    ///   - prompt: The shooting brief. May be empty when `anchors` carry the request on their own.
    ///   - library: Every recipe the model may choose from.
    ///   - anchors: Recipes the user pinned, in their order. The model must return all of them.
    ///   - slotTarget: How many slots the finished set should fill. Raised to the anchor count and
    ///     capped at `Chapter.maxSlots`; anchors are never dropped, even past that cap.
    ///   - excluded: Recipes withheld from this round — picks the user rejected while refining.
    ///     Anchors always win over this list.
    static func recommend(prompt: String,
                          library: [LibraryEntry],
                          anchors: [UUID] = [],
                          slotTarget: Int = Chapter.maxSlots,
                          excluded: Set<UUID> = [],
                          provider: AIProvider,
                          apiKey: String,
                          modelID: String) async throws -> RecommendationResult {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw RecipeRecommendError.notConfigured(provider) }
        let model = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw RecipeRecommendError.noModelSelected(provider) }
        guard !library.isEmpty else { throw RecipeRecommendError.emptyLibrary }

        let brief = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        // Keep only anchors that are really in the library, in the user's order and without repeats.
        let libraryUUIDs = Set(library.map(\.uuid))
        var anchorList: [UUID] = []
        for uuid in anchors where libraryUUIDs.contains(uuid) && !anchorList.contains(uuid) {
            anchorList.append(uuid)
        }
        let anchorSet = Set(anchorList)
        guard !brief.isEmpty || !anchorSet.isEmpty else { throw RecipeRecommendError.emptyRequest }

        // A rejected pick is withheld by dropping it from the catalog *and* the schema's id enum, so
        // it can't come back. Pinning always wins — an anchor is never withheld.
        let offered = library.filter { anchorSet.contains($0.uuid) || !excluded.contains($0.uuid) }
        guard !offered.isEmpty else { throw RecipeRecommendError.emptyLibrary }

        let target = min(max(slotTarget, anchorList.count, 1), Chapter.maxSlots)

        let input: [String: Any]
        do {
            input = try await AIClient.forcedToolInput(
                request(brief: brief, library: offered, anchors: anchorList,
                        target: target, modelID: model),
                provider: provider, apiKey: key)
        } catch let error as AIClient.CallError {
            switch error {
            case .transport(let detail):
                throw RecipeRecommendError.requestFailed(provider: provider, detail: detail)
            case .http(let status, let message, let isAuthFailure):
                throw RecipeRecommendError.http(provider: provider, status: status, message: message,
                                                isAuthFailure: isAuthFailure)
            case .refused: throw RecipeRecommendError.refused
            case .truncated: throw RecipeRecommendError.truncated
            case .noToolCall: throw RecipeRecommendError.noPicks
            }
        }

        // Validate every pick against what was offered and drop duplicates — belt and braces on top
        // of the schema's enum constraint.
        let offeredUUIDs = Set(offered.map(\.uuid))
        var picks: [RecipePick] = []
        var seen = Set<UUID>()
        for raw in (input["picks"] as? [[String: Any]]) ?? [] {
            guard let idString = raw["id"] as? String,
                  let uuid = UUID(uuidString: idString),
                  offeredUUIDs.contains(uuid),
                  !seen.contains(uuid) else { continue }
            seen.insert(uuid)
            picks.append(RecipePick(recipeUUID: uuid,
                                    reason: trimmedOrNil(raw["reason"]),
                                    role: trimmedOrNil(raw["role"]),
                                    isAnchor: anchorSet.contains(uuid)))
        }

        // The schema can ask for the pinned recipes but can't enforce them, so restore any the
        // model dropped. They go on the end: without a pick we have no ranking for them.
        for uuid in anchorList where !seen.contains(uuid) {
            picks.append(RecipePick(recipeUUID: uuid, isAnchor: true))
        }
        // Trim to the requested size from the tail, sacrificing unpinned picks first.
        while picks.count > target,
              let index = picks.lastIndex(where: { !$0.isAnchor }) {
            picks.remove(at: index)
        }
        picks = Array(picks.prefix(max(target, anchorList.count)))
        guard !picks.isEmpty else { throw RecipeRecommendError.noPicks }

        let title = ((input["title"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = trimmedOrNil(input["summary"])
        let gaps = ((input["gaps"] as? [Any]) ?? []).compactMap(trimmedOrNil)
        return RecommendationResult(title: title.isEmpty ? "Recipe Ideas" : title,
                                    summary: summary,
                                    picks: picks,
                                    gaps: gaps)
    }

    private static func trimmedOrNil(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }

    // MARK: Request construction

    private static func request(brief: String, library: [LibraryEntry], anchors: [UUID],
                                target: Int, modelID: String) -> AIToolRequest {
        // 2048 tokens and 120 s are allowances with no recorded reason.
        AIToolRequest(
            modelID: modelID,
            maxTokens: 2048,
            systemPrompt: systemPrompt,
            userText: userMessage(brief: brief, library: library, anchors: anchors, target: target),
            image: nil,
            tool: recommendationTool(library: library, anchors: anchors, target: target),
            timeout: 120)
    }

    private static func userMessage(brief: String, library: [LibraryEntry], anchors: [UUID],
                                    target: Int) -> String {
        var sections: [String] = []

        if brief.isEmpty {
            sections.append("My shooting plans: not specified — build the most broadly useful bank "
                            + "around the recipes I've already chosen, covering the widest range of "
                            + "everyday shooting situations.")
        } else {
            sections.append("My shooting plans: \(brief)")
        }

        sections.append("Chapter size: \(target) slots (C1–C\(target)). Return exactly \(target) "
                        + "picks unless the library genuinely has nothing worth the last slot.")

        if !anchors.isEmpty {
            let byUUID = Dictionary(library.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
            let lines = anchors.compactMap { uuid -> String? in
                guard let entry = byUUID[uuid] else { return nil }
                return "- id: \(entry.uuid.uuidString) — \(entry.name)"
            }.joined(separator: "\n")
            let remaining = max(target - anchors.count, 0)
            sections.append("""
            LOCKED — recipes I have already decided to carry. Every one of these must appear in your \
            picks; you may reorder them but you may not drop or substitute any:
            \(lines)

            That leaves \(remaining) slot\(remaining == 1 ? "" : "s") for you to fill.
            """)
        }

        sections.append("My recipe library:\n\(catalog(for: library, anchors: Set(anchors)))")
        return sections.joined(separator: "\n\n")
    }

    /// One line per recipe, so the model judges by the actual stored settings — not by what a
    /// similarly-named community recipe usually looks like.
    private static func catalog(for library: [LibraryEntry], anchors: Set<UUID>) -> String {
        library.map { entry in
            let marker = anchors.contains(entry.uuid) ? " [LOCKED]" : ""
            var line = "- id: \(entry.uuid.uuidString)\(marker)\n  name: \(entry.name)\n  settings: \(entry.settingsSummary)"
            if let notes = entry.notes { line += "\n  notes: \(notes)" }
            if !entry.tags.isEmpty { line += "\n  tags: \(entry.tags.joined(separator: ", "))" }
            return line
        }.joined(separator: "\n")
    }

    private static let systemPrompt = """
    You are an expert on Fujifilm X-series film-simulation "recipes". The user describes their \
    shooting plans (destination, season, weather, subjects, the vibe they want) and provides their \
    personal recipe library. Call the recommend_recipes tool to assemble a chapter — a bank of \
    custom slots C1–C7 — from the recipes IN THAT LIBRARY.

    Some requests arrive with LOCKED recipes: recipes the user has already committed to carrying. \
    When they do, the job is not to pick a set from scratch — it is to COMPLETE the set:
    - Include every locked recipe. Never drop, substitute or duplicate one, even if you'd have \
    chosen differently. They are the user's decision, not a suggestion.
    - Work out what the locked recipes already cover between them, judging by their stored \
    settings, and — just as important — what they leave uncovered.
    - Spend every remaining slot on a recipe that covers something the locked set does NOT. A pick \
    that duplicates a locked recipe's base simulation and rendering is a wasted slot.
    - If the locked set already covers a situation well, don't reinforce it; move to the next \
    uncovered situation.

    Rules that always apply:
    - Pick recipes ONLY by the exact id values in the library list. Never invent recipes or \
    settings, and never recommend recipes the user doesn't have.
    - Judge each recipe by its actual stored settings (film simulation, white balance and shifts, \
    tone curve, color, grain, dynamic range). Never justify a pick by the fame or community \
    reputation of a recipe's name or the film stock it imitates — a recipe is only what its \
    stored settings say it is.
    - First break the plans into distinct shooting situations — a trip is not one scene. Typical \
    axes: bright outdoor daylight, overcast or flat light, golden hour, indoor window light, \
    indoor artificial or night, black & white, plus subject-specific needs (people, landscape, \
    street, food).
    - Pick a SET that covers those situations as far as the library allows. Two recipes sharing a \
    base simulation and near-identical settings cover one situation — keep the stronger and spend \
    the slot elsewhere. Fill fewer slots than asked only when nothing left in the library genuinely \
    fits; never pad with weak matches, and never pick the same recipe twice. Order the picks most \
    broadly useful first (position 1 maps to C1, the slot they'd leave the camera on) — locked \
    recipes take their place in that ranking like any other.

    Matching settings to light:
    - Harsh midday sun: forgiving low-contrast bases (Eterna, Classic Chrome), negative Highlight \
    and Shadow tone, DR400 to hold the sky. Under bright open sky, Color Chrome FX Blue deepens \
    blue gradation.
    - Overcast, flat, or rainy: bases that stay lively without dramatic light — Classic Negative, \
    Reala Ace, PRO Neg. Hi. Positive tone values and higher Color add life; DR100–200 is fine \
    since highlights aren't at risk.
    - Golden hour: warm bases (Nostalgic Neg., Classic Negative) and warm WB shifts (+Red/−Blue).
    - Indoor artificial light or night: AUTO white balance only. A fixed Daylight or ~5500K WB \
    goes ugly yellow under tungsten and LED — never pick one for an indoor/night situation; if \
    the library has no Auto-WB option for a shoot that needs it, report that in gaps.

    Matching settings to subject:
    - Landscape/nature: Velvia for saturated vistas and foliage; Provia or Reala Ace for a \
    natural palette; Classic Chrome when Velvia is too intense.
    - People: skin rendering comes first — Astia and the PRO Neg. pair keep skin transitions \
    smooth; Velvia oversaturates skin; negative Clarity softens skin like a diffusion filter.
    - Street/travel/everyday: versatile all-rounders (Classic Chrome, Reala Ace, Provia); \
    Auto-WB recipes survive walking from daylight into a cafe.
    - Black & white: Acros for shadow richness and tonal structure (+Ye moderately darkens sky, \
    +R is dramatic, +G flatters skin); Monochrome renders flatter and softer. Don't force a B&W \
    pick unless the library or the stated intent supports one.

    Output fields:
    - role is the one situation this recipe is in the set to handle: at most four words, Title \
    Case, e.g. "Overcast & Rain", "Night & Interiors", "Portraits In Shade". Two picks should not \
    share a role — if they would, one of them is redundant.
    - reason is read by a photographer deciding which custom slot to turn to: one concrete \
    sentence, second person, saying what the recipe will DO to the image in that light and when \
    to switch to it — not that it's "great for travel". For a LOCKED recipe, use the sentence to \
    tell them what it covers here and what it leaves to the others. For a recipe you added, say \
    what it gives them that the rest of the set does not.
    - Set title to a short name for the set and summary to 1–2 sentences on how the set covers the \
    plans; when there are locked recipes, summary should say what they already covered and what \
    you added around them. In summary, also note anything you inferred rather than were told \
    (e.g. likely weather from season and place).
    - Use gaps for situations these plans call for that the library simply cannot cover — one \
    short phrase each, naming the situation and what's missing (e.g. "Night interiors — no \
    Auto-WB recipe in your library"). Leave gaps empty when the set genuinely covers the plans; \
    never list a gap you actually filled.
    """

    /// The tool the model is forced to call. Returned as a vendor-neutral ``AITool``: the nested
    /// `picks.items.properties.id` enum below is the only thing keeping picks inside the user's own
    /// library, and each ``AIWireFormat`` has to carry it down intact.
    private static func recommendationTool(library: [LibraryEntry], anchors: [UUID],
                                           target: Int) -> AITool {
        AITool(
            name: toolName,
            description: anchors.isEmpty
                ? "Record which of the user's own library recipes to recommend for their shooting plans."
                : "Record the completed chapter: every locked recipe plus the library recipes you chose to cover what the locked ones don't.",
            properties: [
                "title": ["type": "string", "description": "Short name for this set, e.g. \"Kyoto in Autumn\"."],
                "summary": ["type": "string", "description": "1–2 sentences on how the set covers the plans — with locked recipes, what they covered and what you added around them — noting anything inferred rather than stated."],
                "picks": [
                    "type": "array",
                    "minItems": max(anchors.count, 1),
                    "maxItems": target,
                    "description": anchors.isEmpty
                        ? "The recommended library recipes, most broadly useful first (maps to slots C1–C\(target)). No duplicates."
                        : "The complete chapter, most broadly useful first (maps to slots C1–C\(target)): all \(anchors.count) locked recipe(s) plus your additions. No duplicates.",
                    "items": [
                        "type": "object",
                        "properties": [
                            "id": ["type": "string",
                                   "enum": library.map(\.uuid.uuidString),
                                   "description": "The id of a recipe from the user's library."],
                            "role": ["type": "string",
                                     "description": "The one situation this recipe covers in the set — at most four words, Title Case. Unique across picks."],
                            "reason": ["type": "string",
                                       "description": "One concrete second-person sentence: what this recipe does to the image in this shoot's light, and when to switch to it. For an added recipe, what it gives that the rest of the set doesn't."],
                        ],
                        "required": ["id", "role", "reason"],
                    ],
                ],
                "gaps": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": "Situations these plans call for that the library cannot cover — one short phrase each. Empty when the set covers the plans.",
                ],
            ],
            required: ["title", "picks"])
    }
}
