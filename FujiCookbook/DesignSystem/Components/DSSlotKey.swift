import SwiftUI

/// One custom slot of the camera as a square key: "C1" top left, the recipe's short name at the
/// bottom, an LED top right that is lit when the slot holds a setting. The chosen slot is the
/// active key.
struct DSSlotKey: View {
    let slot: String
    /// The name the camera shows for the slot; nil when it is empty.
    var name: String?
    var isOccupied: Bool
    var isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text(slot).dsKeyLabel()
                    Spacer(minLength: 0)
                    DSLED(isOn: isOccupied, color: isSelected ? .onSignal : .signal, size: 7)
                        .padding(.top, DSSpacing.xs)
                }
                Spacer(minLength: DSSpacing.xs)
                Text(name ?? "Empty")
                    .dsSmallMono()
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .opacity(name == nil ? 0.6 : 1)
            }
            .padding(DSSpacing.s + 2)
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(DSSlotKeyStyle(isActive: isSelected))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Slot \(slot), \(name ?? "empty")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The hardware key's look, sized by the square it is given rather than by a variant.
private struct DSSlotKeyStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: DSRadius.key, style: .continuous)
        let isDown = isActive || configuration.isPressed
        return configuration.label
            .foregroundStyle(isActive ? DSColor.onSignal : DSColor.textPrimary)
            .background(shape.fill(isActive ? DSColor.signal : DSColor.key))
            .overlay {
                if isDown { shape.stroke(DSColor.keyInset, lineWidth: 4).offset(y: 2).clipShape(shape) }
            }
            .background(shape.fill(DSColor.keyShadow).offset(y: isDown ? 0 : DSSize.keyShadowOffset))
            .contentShape(shape)
    }
}

/// The last tile of the slot grid: a dashed outline that opens the import, with the count of new
/// photos on the card.
struct DSSlotImportKey: View {
    let newCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: "square.and.arrow.down")
                    .font(DSFont.headline)
                Spacer(minLength: DSSpacing.xs)
                Text("Import").dsSmallMono().textCase(.uppercase)
                Text("\(newCount) new").dsSmallMono().textCase(.uppercase).foregroundStyle(DSColor.signalText)
            }
            .foregroundStyle(DSColor.textPrimary)
            .padding(DSSpacing.s + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .aspectRatio(1, contentMode: .fit)
            .overlay(RoundedRectangle(cornerRadius: DSRadius.key, style: .continuous)
                .strokeBorder(DSColor.textSecondary, style: StrokeStyle(lineWidth: DSLine.rule, dash: [4, 3])))
            .contentShape(RoundedRectangle(cornerRadius: DSRadius.key, style: .continuous))
        }
        .buttonStyle(DSPlainPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Import, \(newCount) new")
    }
}

/// The slot keys in four columns, 10 pt apart.
struct DSSlotGrid<Content: View>: View {
    @ViewBuilder var content: Content

    static var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: DSSize.slotKeySpacing), count: 4)
    }

    var body: some View {
        LazyVGrid(columns: Self.columns, spacing: DSSize.slotKeySpacing) { content }
            .padding(.bottom, DSSize.keyShadowOffset)
    }
}

#Preview("Slot keys") {
    DSSlotGrid {
        DSSlotKey(slot: "C1", name: "Kodachrome", isOccupied: true, isSelected: false) {}
        DSSlotKey(slot: "C2", name: "Tri-X", isOccupied: true, isSelected: false) {}
        DSSlotKey(slot: "C3", name: "Lua de Mel", isOccupied: true, isSelected: true) {}
        DSSlotKey(slot: "C4", name: nil, isOccupied: false, isSelected: false) {}
        DSSlotKey(slot: "C5", name: "Portra", isOccupied: true, isSelected: false) {}
        DSSlotKey(slot: "C6", name: nil, isOccupied: false, isSelected: false) {}
        DSSlotKey(slot: "C7", name: "Velvia 50", isOccupied: true, isSelected: false) {}
        DSSlotImportKey(newCount: 12) {}
    }
    .padding()
    .background(DSColor.background)
}
