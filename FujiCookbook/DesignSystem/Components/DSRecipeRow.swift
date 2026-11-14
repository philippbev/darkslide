import SwiftUI

/// One recipe in an archive list: a 52 pt column in the simulation's color with its code above
/// and the archive number below, the name and a mono meta line, and the camera slot it sits in.
struct DSRecipeRow: View {
    let simulation: FilmSimulation?
    /// "034".
    let objectNumber: String
    let name: String
    /// "CLASSIC CHROME   GRAIN WEAK": parts separated by space alone.
    let meta: String
    /// "C1" when the recipe is in a camera slot.
    var slot: String?
    /// Whether that slot holds the recipe as written right now.
    var slotIsLoaded = true
    /// A star after the name.
    var isFavorite = false
    /// A warning mark after the name, with what VoiceOver reads for it.
    var warning: String?

    var body: some View {
        HStack(spacing: 0) {
            simulationColumn
            DSRule(vertical: true)
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                HStack(spacing: DSSpacing.s) {
                    Text(name)
                        .font(DSFont.headline)
                        .foregroundStyle(DSColor.textPrimary)
                        .lineLimit(1)
                    if isFavorite {
                        Image(systemName: "star.fill")
                            .font(DSFont.metaMono)
                            .foregroundStyle(DSColor.textSecondary)
                            .accessibilityLabel("Favorite")
                    }
                    if let warning {
                        Image(systemName: "exclamationmark.triangle")
                            .font(DSFont.metaMono)
                            .foregroundStyle(DSColor.textSecondary)
                            .accessibilityLabel(warning)
                    }
                }
                Text(meta).dsMetaMono().lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DSSpacing.m)
            .padding(.vertical, DSSpacing.m)
            if let slot {
                DSSlotBadge(slot: slot, isLoaded: slotIsLoaded)
                    .padding(.trailing, DSSpacing.m)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private var simulationColumn: some View {
        VStack {
            Text(simulation?.dsCode ?? DSNoSimulation.code)
                .dsSmallMono(size: 11, weight: .bold)
            Spacer(minLength: DSSpacing.xs)
            Text(objectNumber)
                .dsSmallMono(size: 11, weight: .medium)
        }
        .foregroundStyle(simulation?.dsText ?? DSNoSimulation.text)
        .padding(.vertical, DSSpacing.s)
        .frame(width: DSSize.simulationColumn)
        .frame(maxHeight: .infinity)
        .background(simulation?.dsFill ?? DSNoSimulation.fill)
        .accessibilityHidden(true)
    }
}

/// The slot a recipe sits in, as a small key: an LED and "C1".
struct DSSlotBadge: View {
    let slot: String
    var isLoaded = true

    var body: some View {
        HStack(spacing: DSSpacing.xs + 2) {
            DSLED(isOn: isLoaded, size: 6)
            Text(slot).dsSmallMono(size: 13, weight: .bold)
        }
        .foregroundStyle(DSColor.textPrimary)
        .padding(.horizontal, DSSpacing.s)
        .padding(.vertical, DSSpacing.xs + 2)
        .background {
            let shape = RoundedRectangle(cornerRadius: DSRadius.switchTrack, style: .continuous)
            shape.fill(DSColor.keyShadow).offset(y: 2)
            shape.fill(DSColor.key)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Slot \(slot)")
    }
}

/// Rows in one archive frame, a 1.5 pt rule between each two.
struct DSArchiveList<Item: Identifiable, Row: View>: View {
    let items: [Item]
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { DSRule() }
                row(item)
            }
        }
        .dsArchiveFrame()
    }
}

#Preview("Recipe rows") {
    struct Item: Identifiable {
        let id: String
        let simulation: FilmSimulation?
        let slot: String?
    }
    let items = [Item(id: "Kodachrome 64", simulation: .classicChrome, slot: "C1"),
                 Item(id: "Lua de Mel", simulation: .classicNeg, slot: nil),
                 Item(id: "Tri-X 400 with a deliberately long name", simulation: .acrosYe, slot: "C4"),
                 Item(id: "Untitled", simulation: nil, slot: nil)]
    return DSArchiveList(items: items) { item in
        DSRecipeRow(simulation: item.simulation, objectNumber: "034", name: item.id,
                    meta: "\(item.simulation?.displayName ?? "None")   Grain Weak", slot: item.slot,
                    isFavorite: item.id == "Lua de Mel")
    }
    .padding()
    .background(DSColor.background)
}
