import SwiftUI

/// Spacing on a 4 pt grid.
enum DSSpacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32

    /// Distance from the screen's edge to its content.
    static let screenMargin = l
    /// Between blocks on a screen.
    static let block = l

    static let scale: [(name: String, value: CGFloat)] = [
        ("xs", xs), ("s", s), ("m", m), ("l", l), ("xl", xl), ("xxl", xxl), ("xxxl", xxxl)
    ]
}

/// Corner radii. The archive is square; the instrument is rounded. Dials and LEDs are circles and
/// need none; iOS elements keep their system radii.
enum DSRadius {
    static let archive: CGFloat = 0
    /// The contact sheet's selection box.
    static let checkbox: CGFloat = 5
    static let switchKnob: CGFloat = 6
    static let switchTrack: CGFloat = 8
    static let key: CGFloat = 14
    static let panel: CGFloat = 18

    static let scale: [(name: String, value: CGFloat)] = [
        ("archive", archive), ("checkbox", checkbox), ("switchKnob", switchKnob),
        ("switchTrack", switchTrack), ("key", key), ("panel", panel)
    ]
}

/// Line widths.
enum DSLine {
    /// Archive frames and the lines between fields, in `rule`.
    static let rule: CGFloat = 1.5
    /// Lines inside a data sheet, in `separator`.
    static let hairline: CGFloat = 1
}

/// Fixed sizes the components share.
enum DSSize {
    /// The smallest touch target.
    static let touchTarget: CGFloat = 44
    static let iconKey: CGFloat = 44
    static let textKeyHeight: CGFloat = 40
    static let primaryKeyHeight: CGFloat = 52
    /// The hard shadow under a key, straight down.
    static let keyShadowOffset: CGFloat = 3
    static let switchSize = CGSize(width: 56, height: 32)
    static let switchKnob: CGFloat = 26
    static let knobField: CGFloat = 76
    static let knobBody: CGFloat = 54
    static let simulationColumn: CGFloat = 52
    static let simulationBandHeight: CGFloat = 64
    static let barcodeHeight: CGFloat = 26
    static let checkbox: CGFloat = 20
    static let contactSheetSpacing: CGFloat = 3
    static let slotKeySpacing: CGFloat = 10
}

extension View {
    /// The square archive frame: `surface` inside a 1.5 pt `rule` border.
    func dsArchiveFrame() -> some View {
        background(DSColor.surface)
            .overlay(Rectangle().strokeBorder(DSColor.rule, lineWidth: DSLine.rule))
    }
}

/// A 1 pt line inside a data sheet.
struct DSSeparator: View {
    var body: some View {
        Rectangle().fill(DSColor.separator).frame(height: DSLine.hairline)
    }
}

/// A 1.5 pt line in the text color, between archive fields or rows. Horizontal unless `vertical`.
struct DSRule: View {
    var vertical = false

    var body: some View {
        Rectangle()
            .fill(DSColor.rule)
            .frame(width: vertical ? DSLine.rule : nil, height: vertical ? nil : DSLine.rule)
    }
}
