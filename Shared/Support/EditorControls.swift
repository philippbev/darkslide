import SwiftUI

/// The design system's parameter control: the value in the accent color over a slider that shows
/// where it sits in the range.
private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: NumericRange
    let format: (Double) -> String

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(DSColor.signalText)
            }
            Slider(value: $value,
                   in: range.min...range.max,
                   step: range.step == 0 ? 1 : range.step)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityValue(format(value))
    }
}

/// Slider row for an integer parameter, constrained to a camera range.
struct IntSliderRow: View {
    let title: String
    @Binding var value: Int
    let range: NumericRange

    var body: some View {
        SliderRow(title: title,
                  value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }),
                  range: range,
                  format: { RecipeSettingsFormatter.signed(Int($0.rounded())) })
    }
}

/// The optional sibling of `SliderRow`, for a parameter a recipe may simply not set.
///
/// `nil` and a value are different instructions to a camera push and a RAF develop alike: an unset
/// field leaves the slot's own setting (or the RAF's as-shot value) alone, where a value overwrites it, so
/// the form has to be able to say "not set" rather than showing a zero it made up. Setting one is
/// a deliberate tap, and the ✕ puts it back to absent.
private struct OptionalSliderRow: View {
    let title: String
    @Binding var value: Double?
    let range: NumericRange
    let format: (Double) -> String

    var body: some View {
        if let current = value {
            VStack(spacing: 8) {
                HStack {
                    Text(title)
                    Spacer(minLength: 12)
                    Text(format(current))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(DSColor.signalText)
                    Button { value = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Clear \(title)")
                }
                Slider(value: Binding(get: { current }, set: { value = range.clamp($0) }),
                       in: range.min...range.max,
                       step: range.step == 0 ? 1 : range.step)
                    .accessibilityLabel(title)
                    .accessibilityValue(format(current))
            }
            .padding(.vertical, 2)
        } else {
            HStack {
                Text(title)
                Spacer(minLength: 12)
                Text("Not set")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Set") { value = defaultValue }
                    .buttonStyle(.borderless)
                    .font(.subheadline.weight(.medium))
                    .padding(.leading, 8)
            }
            .padding(.vertical, 2)
        }
    }

    /// Zero when the range includes it, otherwise the bottom of the range — so "Set" never lands
    /// on a value the camera doesn't offer.
    private var defaultValue: Double {
        (range.min...range.max).contains(0) ? 0 : range.min
    }
}

/// `IntSliderRow` for an integer parameter the recipe may not set.
struct OptionalIntSliderRow: View {
    let title: String
    @Binding var value: Int?
    let range: NumericRange

    var body: some View {
        OptionalSliderRow(title: title,
                          value: Binding(get: { value.map(Double.init) },
                                         set: { value = $0.map { Int($0.rounded()) } }),
                          range: range,
                          format: { RecipeSettingsFormatter.signed(Int($0.rounded())) })
    }
}

/// Slider row for a half-step parameter (highlight/shadow tone on modern bodies) the recipe may
/// not set.
struct OptionalDoubleSliderRow: View {
    let title: String
    @Binding var value: Double?
    let range: NumericRange

    var body: some View {
        OptionalSliderRow(title: title, value: $value, range: range,
                          format: RecipeSettingsFormatter.tone)
    }
}
