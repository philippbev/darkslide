import SwiftUI

/// One frame of the import's contact sheet: the picture, its number bottom left, the simulation's
/// code top left in its color, and a selection box top right. A frame that isn't selected is dimmed.
struct DSContactSheetTile: View {
    /// Nil while the thumbnail loads.
    var image: Image?
    let frameNumber: String
    /// The simulation the photo was taken with, when known.
    var simulation: FilmSimulation?
    /// The files behind the frame, such as "RAF+JPG", when the sheet mixes formats.
    var format: String?
    let isSelected: Bool

    var body: some View {
        DSColor.panel
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image { image.resizable().scaledToFill() }
            }
            .clipped()
            .opacity(isSelected ? 1 : 0.4)
            .overlay(alignment: .bottomLeading) { DSFrameLabel(text: frameNumber) }
            .overlay(alignment: .bottomTrailing) {
                if let format { DSFrameLabel(text: format) }
            }
            .overlay(alignment: .topLeading) {
                if let simulation {
                    Text(simulation.dsCode)
                        .dsSmallMono(size: 9, weight: .bold)
                        .foregroundStyle(simulation.dsText)
                        .padding(.horizontal, DSSpacing.xs)
                        .padding(.vertical, 2)
                        .background(simulation.dsFill)
                        .padding(DSSpacing.xs)
                }
            }
            .overlay(alignment: .topTrailing) { DSCheckbox(isOn: isSelected).padding(DSSpacing.xs + 2) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(["Frame \(frameNumber)", format, simulation?.displayName]
                .compactMap { $0 }.joined(separator: ", "))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A frame number or format: mono 10 in white on black, as printed on the film's edge.
private struct DSFrameLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .dsSmallMono(size: 10)
            .foregroundStyle(DSColor.filmEdgeText)
            .padding(.horizontal, DSSpacing.xs)
            .padding(.vertical, 1)
            .background(DSColor.filmEdge)
    }
}

/// The contact sheet's selection box: 20 pt, white edge, signal blue with a white tick when on.
struct DSCheckbox: View {
    let isOn: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DSRadius.checkbox, style: .continuous)
        ZStack {
            shape.fill(isOn ? DSColor.signal : DSColor.keyInset)
            shape.strokeBorder(DSColor.onSignal, lineWidth: DSLine.rule)
            if isOn {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DSColor.onSignal)
            }
        }
        .frame(width: DSSize.checkbox, height: DSSize.checkbox)
        .accessibilityHidden(true)
    }
}

/// The contact sheet: three columns 3 pt apart on the text color, in an archive frame.
struct DSContactSheetGrid<Content: View>: View {
    @ViewBuilder var content: Content

    static var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: DSSize.contactSheetSpacing), count: 3)
    }

    var body: some View {
        LazyVGrid(columns: Self.columns, spacing: DSSize.contactSheetSpacing) { content }
            .padding(DSSize.contactSheetSpacing)
            .background(DSColor.textPrimary)
            .overlay(Rectangle().strokeBorder(DSColor.rule, lineWidth: DSLine.rule))
    }
}

/// A day of the contact sheet: its name on the left, the frame range on the right ("0142–0150"),
/// and an optional control such as "Select Day".
struct DSContactSheetDayHeader<Accessory: View>: View {
    let title: String
    var frameRange: String?
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: DSSpacing.m) {
            Text(title).dsMetaMono(DSColor.textPrimary).accessibilityAddTraits(.isHeader)
            Spacer(minLength: DSSpacing.s)
            if let frameRange { Text(frameRange).dsMetaMono() }
            accessory
        }
    }
}

extension DSContactSheetDayHeader where Accessory == EmptyView {
    init(title: String, frameRange: String? = nil) {
        self.init(title: title, frameRange: frameRange) { EmptyView() }
    }
}

#Preview("Contact sheet") {
    VStack(alignment: .leading, spacing: DSSpacing.s) {
        DSContactSheetDayHeader(title: "Today   November 14", frameRange: "0142–0150")
        DSContactSheetGrid {
            ForEach(0..<6) { index in
                DSContactSheetTile(frameNumber: String(format: "%04d", 142 + index),
                                   simulation: [.classicChrome, .velvia, .acros][index % 3],
                                   format: index == 2 ? "RAF+JPG" : nil,
                                   isSelected: index != 4)
            }
        }
    }
    .padding()
    .background(DSColor.background)
}
