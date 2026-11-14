import SwiftUI

/// Where a dial's pointer stands. A display for now; input may come later.
enum DSKnobScale {
    static let tickCount = 11
    static let minAngle: Double = -135
    static let maxAngle: Double = 135

    /// The pointer's angle in degrees for a position from 0 (left stop) to 1 (right stop). Values
    /// outside are held at the stops.
    static func angle(for position: Double) -> Double {
        minAngle + (maxAngle - minAngle) * min(max(position, 0), 1)
    }

    /// A value on a linear range, such as color or tone from −4 to +4.
    static func position(of value: Double, in range: ClosedRange<Double>) -> Double {
        guard range.upperBound > range.lowerBound else { return 0.5 }
        return (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    /// One of a few steps, such as grain Off / Weak / Strong, spread evenly over the scale.
    static func position(ofStep index: Int, count: Int) -> Double {
        guard count > 1 else { return 0.5 }
        return Double(index) / Double(count - 1)
    }

    /// The tick angles from stop to stop.
    static var tickAngles: [Double] {
        (0..<tickCount).map { angle(for: Double($0) / Double(tickCount - 1)) }
    }
}

/// A dial with a scale, showing one setting: 11 ticks from −135° to +135°, the body, a pointer, and
/// the setting's label and value underneath.
struct DSKnob: View {
    let label: String
    /// "+2", "WEAK", "DR200".
    let value: String
    /// 0 is the left stop, 1 the right; see `DSKnobScale`.
    let position: Double

    var body: some View {
        VStack(spacing: DSSpacing.s) {
            ZStack {
                ForEach(Array(DSKnobScale.tickAngles.enumerated()), id: \.offset) { _, angle in
                    Capsule()
                        .fill(DSColor.textSecondary)
                        .frame(width: 2, height: 6)
                        .offset(y: -(DSSize.knobField / 2 - 3))
                        .rotationEffect(.degrees(angle))
                }
                Circle()
                    .fill(DSColor.knob)
                    .frame(width: DSSize.knobBody, height: DSSize.knobBody)
                Capsule()
                    .fill(DSColor.knobMark)
                    .frame(width: 4, height: 14)
                    .offset(y: -(DSSize.knobBody / 2 - 7 - 4))
                    .rotationEffect(.degrees(DSKnobScale.angle(for: position)))
            }
            .frame(width: DSSize.knobField, height: DSSize.knobField)
            .accessibilityHidden(true)
            VStack(spacing: 2) {
                Text(label).dsFieldLabel()
                Text(value)
                    .font(DSFont.valueMono)
                    .foregroundStyle(DSColor.textPrimary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

#Preview("Knobs") {
    HStack(spacing: DSSpacing.l) {
        DSKnob(label: "Color", value: DSValueFormat.signed(2), position: DSKnobScale.position(of: 2, in: -4...4))
        DSKnob(label: "Grain", value: "Weak", position: DSKnobScale.position(ofStep: 1, count: 3))
        DSKnob(label: "Dynamic", value: "DR400", position: DSKnobScale.position(ofStep: 3, count: 4))
    }
    .padding()
    .background(DSColor.background)
}
