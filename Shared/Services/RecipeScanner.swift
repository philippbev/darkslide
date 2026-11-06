import Foundation

/// Errors surfaced while scanning a screenshot into a recipe. Non-destructive: nothing enters the
/// library unless extraction succeeds and the user saves the reviewed result.
enum RecipeScanError: LocalizedError {
    case notConfigured(AIProvider)
    case noModelSelected(AIProvider)
    case imageUnreadable
    case requestFailed(provider: AIProvider, detail: String)
    case http(provider: AIProvider, status: Int, message: String, isAuthFailure: Bool)
    case refused
    case truncated
    case noRecipeFound

    var errorDescription: String? {
        switch self {
        case .notConfigured(let provider):
            return "AI scanning isn't set up. Turn on AI features in Settings and add your \(provider.displayName) API key."
        case .noModelSelected(let provider):
            return "No model is chosen for scanning. Open Settings and pick one of \(provider.displayName)'s models."
        case .imageUnreadable:
            return "That image couldn't be read."
        case .requestFailed(let provider, let detail):
            return "Couldn't reach \(provider.displayName): \(detail)"
        case .http(let provider, let status, let message, let isAuthFailure):
            // Whether a status means "bad key" is the provider's call, not a fixed 401. Reading
            // an auth failure as a malformed request would send the user hunting through their
            // screenshot instead of through Settings.
            if isAuthFailure {
                return "Your \(provider.displayName) API key was rejected (\(status)). Check it in Settings."
            }
            if status == 429 {
                return "Rate limited by \(provider.displayName) (429). Try again in a moment."
            }
            return "\(provider.displayName) returned an error (\(status)): \(message)"
        case .refused:
            return "The model declined to read this image."
        case .truncated:
            return "The model ran out of room before it finished reading the screenshot. Try another model in Settings."
        case .noRecipeFound:
            return "No recipe settings could be read from that screenshot."
        }
    }
}

extension RecipeScanError {
    /// Coarse, non-identifying label for log lines.
    ///
    /// A rejected key, a rate limit, and a model that ran out of room are three unrelated product
    /// problems — one is the user's setup, one is the vendor, one is our model choice — and a log
    /// line reading only "failed" tells nobody which. Provider messages are dropped: they're vendor
    /// prose, and can quote the request.
    var diagnosticReason: String {
        switch self {
        case .notConfigured: return "not_configured"
        case .noModelSelected: return "no_model_selected"
        case .imageUnreadable: return "image_unreadable"
        case .requestFailed: return "request_failed"
        case .http(_, let status, _, let isAuthFailure):
            if isAuthFailure { return "auth_failed" }
            if status == 429 { return "rate_limited" }
            return "http_\(status)"
        case .refused: return "refused"
        case .truncated: return "truncated"
        case .noRecipeFound: return "no_recipe_found"
        }
    }
}

/// Extracts a Fujifilm recipe from a screenshot, using whichever AI provider the user selected.
///
/// A forced `extract_recipe` tool call (see ``AIClient``) makes the model return structured JSON
/// constrained to this app's stable enum raw values.
enum RecipeScanner {
    private static let toolName = "extract_recipe"

    /// Scan `imageData` (any UIImage-decodable bytes) into a portable recipe for review.
    ///
    /// `timeout` is a parameter rather than a constant because the two callers wait in very
    /// different places. In the app the scan runs behind a dismissable overlay, so a slow model is
    /// merely slow; in the Share Extension it holds a modal sheet over whatever app the user was
    /// actually using, where a full minute is an eternity. The extension passes a shorter one and
    /// offers the inbox as a fallback.
    static func scan(imageData: Data, provider: AIProvider, apiKey: String,
                     modelID: String, timeout: TimeInterval = 60) async throws -> PortableRecipe {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw RecipeScanError.notConfigured(provider) }
        let model = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw RecipeScanError.noModelSelected(provider) }

        // Resize + re-encode to JPEG before upload: cuts tokens, stays within vision limits, and
        // guarantees the declared media type matches. Recipe-screenshot text stays legible at this size.
        // `uploadJPEG` rather than `process` so nothing ever holds the full-resolution bitmap —
        // this runs inside the Share Extension, where a 40MP share would otherwise be fatal.
        guard let upload = PhotoProcessing.uploadJPEG(imageData) else {
            throw RecipeScanError.imageUnreadable
        }

        let input: [String: Any]
        do {
            input = try await AIClient.forcedToolInput(
                request(base64Image: upload.base64EncodedString(), modelID: model, timeout: timeout),
                provider: provider, apiKey: key)
        } catch let error as AIClient.CallError {
            switch error {
            case .transport(let detail):
                throw RecipeScanError.requestFailed(provider: provider, detail: detail)
            case .http(let status, let message, let isAuthFailure):
                throw RecipeScanError.http(provider: provider, status: status, message: message,
                                           isAuthFailure: isAuthFailure)
            case .refused: throw RecipeScanError.refused
            case .truncated: throw RecipeScanError.truncated
            case .noToolCall: throw RecipeScanError.noRecipeFound
            }
        }

        let inputData = try JSONSerialization.data(withJSONObject: input)
        guard let scanned = try? JSONDecoder().decode(AIRecipePayload.self, from: inputData) else {
            throw RecipeScanError.noRecipeFound
        }
        return scanned.toPortable(fallbackName: "Scanned Recipe")
    }

    // MARK: Request construction

    private static func request(base64Image: String, modelID: String,
                                timeout: TimeInterval) -> AIToolRequest {
        AIToolRequest(
            modelID: modelID,
            maxTokens: 1024,
            systemPrompt: systemPrompt,
            userText: "Extract the Fujifilm film-simulation recipe shown in this screenshot.",
            image: AIImage(base64: base64Image, mediaType: "image/jpeg"),
            tool: AITool(
                name: toolName,
                description: "Record the Fujifilm recipe settings read from the screenshot.",
                properties: AIRecipeSchema.recipeProperties(),
                // Empty: the model omits anything the screenshot doesn't show.
                required: []),
            timeout: timeout)
    }

    private static let systemPrompt = """
    You read Fujifilm film-simulation "recipe" screenshots (often from social media, blogs, or apps) \
    and extract the camera settings. Call the extract_recipe tool with the values you can see.

    Rules:
    - Use ONLY the exact enum values allowed by the schema (they are uppercase tokens, not the \
    human-readable labels). Map labels to tokens, e.g. "Classic Chrome" -> CLASSIC_CHROME, \
    "DR400" -> DR400, "Weak" -> WEAK.
    - Only include a field if it is clearly shown. Omit anything not present; do not guess.
    - White-balance shift like "R:+3, B:-5" means whiteBalanceShiftRed=3 and whiteBalanceShiftBlue=-5.
    - If a value lists alternatives like "Auto (or Daylight)", choose the first option.
    - Put the recipe title (e.g. "Portra 400") in name. Put any extra free-text tips into notes.
    - Credit only whoever the screenshot shows *made* the recipe — a byline on the recipe, or a \
    poster whose own caption claims it ("I made this"). A handle, watermark, or username alone is \
    not authorship; a repost looks identical. Set credit and creditBasis together, or omit both.
    """
}
