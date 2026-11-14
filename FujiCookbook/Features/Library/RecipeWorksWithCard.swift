import SwiftUI

/// "Works With": which cameras run this recipe as written, which need a change, and which can't,
/// from `RecipeCameraFit`. The body of a `DSArchiveSection` on the recipe's detail. The user's own cameras come first; every other body sits in a collapsed
/// list grouped by verdict. Nothing here is about USB: a read-only body can still run a recipe its
/// menus express.
struct RecipeWorksWithCard: View {
    let settings: RecipeSettings
    /// `Recipe.hasPreservedUnsupportedFields`: the byte-count flag, so no JSON decode per card.
    let hasPreservedFields: Bool

    @Environment(OwnedCameras.self) private var ownedCameras
    @State private var showingAllCameras = false
    @State private var showingMyCameras = false

    var body: some View {
        // Computed once per body pass: `fits` runs the analysis for every registry body.
        let owned = ownedCameras.models.map { RecipeCameraFit(settings, on: $0) }
        let all = RecipeCameraFit.fits(settings, across: ownedCameras.selectable)
        let caveats = RecipeCameraFit.caveats(for: settings, hasPreservedFields: hasPreservedFields)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(caveats, id: \.self) { caveat in
                Label(caveat.text, systemImage: "info.circle")
                    .font(DSFont.subhead)
                    .foregroundStyle(DSColor.textSecondary)
            }
            if owned.isEmpty {
                noOwnedCameras
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(owned) { row($0) }
                }
            }
            DSSeparator()
            DisclosureGroup(isExpanded: $showingAllCameras) {
                allCameras(all).padding(.top, DSSpacing.s)
            } label: {
                Text("All cameras   \(all.count)")
                    .font(DSFont.headline)
                    .foregroundStyle(DSColor.textPrimary)
            }
            .tint(DSColor.textSecondary)
            Text("Checks the recipe's settings against each camera's controls on current firmware. It doesn't promise an identical look, and pushing over USB is a separate question.")
                .font(DSFont.subhead)
                .foregroundStyle(DSColor.textSecondary)
        }
        .sheet(isPresented: $showingMyCameras) {
            NavigationStack { OwnedCamerasView() }
        }
    }

    private var noOwnedCameras: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pick your cameras to see them here first.")
                .font(DSFont.subhead)
                .foregroundStyle(DSColor.textSecondary)
            Button("Manage My Cameras") { showingMyCameras = true }
                .font(DSFont.subhead.weight(.semibold))
                .foregroundStyle(DSColor.signalText)
        }
    }

    private func allCameras(_ fits: [RecipeCameraFit]) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            ForEach(fits.groupedByVerdict(), id: \.verdict) { group in
                VStack(alignment: .leading, spacing: DSSpacing.s) {
                    Text("\(group.verdict.title)   \(group.fits.count)")
                        .dsMetaMono()
                    ForEach(group.fits) { row($0) }
                }
            }
        }
    }

    private func row(_ fit: RecipeCameraFit) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DSSpacing.s) {
            Image(systemName: fit.verdict.symbol)
                .foregroundStyle(fit.verdict.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(fit.model.id)
                    .font(DSFont.valueMono)
                    .foregroundStyle(DSColor.textPrimary)
                if !fit.changes.isEmpty {
                    Text(fit.changes.map(\.text).joined(separator: "   "))
                        .font(DSFont.subhead)
                        .foregroundStyle(DSColor.textSecondary)
                }
                if !fit.unverifiedRanges.isEmpty {
                    Text(Self.unverifiedText(for: fit))
                        .font(DSFont.subhead)
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Self.spokenLabel(for: fit))
    }

    /// "X-T3, not available. No Classic Neg." — the id, the verdict, each change, then any range the
    /// registry can't vouch for. No full stop of its own at the end: a film simulation's name may
    /// already carry one.
    static func spokenLabel(for fit: RecipeCameraFit) -> String {
        var parts = ["\(fit.model.id), \(fit.verdict.title.lowercased())"]
        if !fit.changes.isEmpty { parts.append(fit.changes.map(\.spokenText).joined(separator: "; ")) }
        if !fit.unverifiedRanges.isEmpty { parts.append(unverifiedText(for: fit)) }
        return parts.joined(separator: ". ")
    }

    /// "Highlight Tone, Color: range not verified" — the body has the controls; the registry holds
    /// no limits for them, so the check made no claim either way.
    static func unverifiedText(for fit: RecipeCameraFit) -> String {
        fit.unverifiedRanges.map(\.displayName).joined(separator: ", ") + ": range not verified"
    }
}

extension RecipeCameraFit.Verdict {
    var title: String {
        switch self {
        case .worksAsWritten: return "Works as written"
        case .worksWithChanges: return "Works with changes"
        case .notAvailable: return "Not available"
        }
    }

    var symbol: String {
        switch self {
        case .worksAsWritten: return "checkmark.circle.fill"
        case .worksWithChanges: return "exclamationmark.circle.fill"
        case .notAvailable: return "xmark.circle.fill"
        }
    }

    /// The symbol's shape tells the verdicts apart; the design system keeps color for the signal
    /// and the film simulations, so a body that can't run the recipe is merely quieter.
    var color: Color {
        switch self {
        case .worksAsWritten, .worksWithChanges: return DSColor.textPrimary
        case .notAvailable: return DSColor.textSecondary
        }
    }
}

extension RecipeCameraFit.Change {
    /// Short, for a row: "No Clarity", "Highlight Tone +1.5 → +2".
    var text: String {
        switch self {
        case .filmSimulationMissing(let sim): return "No \(sim.displayName)"
        case .fieldMissing(let field): return "No \(field.displayName)"
        case .clamped(let subject, let from, let to): return "\(subject) \(from) → \(to)"
        case .magentaGreenAxisMissing: return "Warm–cool axis only"
        case .grainSizeFixed: return "Grain size not adjustable"
        case .whiteBalanceModeMissing(let mode): return "No \(mode.displayName)"
        }
    }

    /// The same for VoiceOver, with the arrow said in words.
    var spokenText: String {
        if case .clamped(let subject, let from, let to) = self {
            return "\(subject) \(from) clamped to \(to)"
        }
        return text
    }
}

extension RecipeCameraFit.Caveat {
    var text: String {
        switch self {
        case .noFilmSimulation: return "No film simulation set, so this checks the other settings only."
        case .preservedFields: return "Some imported settings couldn't be checked."
        }
    }
}
