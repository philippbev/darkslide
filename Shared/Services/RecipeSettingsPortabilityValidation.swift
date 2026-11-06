/// Numeric bounds a recipe file must meet to be imported or exported: finite and within `Int32`.
/// Checked only at the file boundary, so settings already in the library still decode, and unknown
/// fields pass through unchecked.
enum RecipeSettingsPortabilityValidation {
    /// The first unsafe known scalar, using its portable JSON field name, or nil when all fit.
    static func invalidField(in settings: RecipeSettings) -> String? {
        let s = settings
        // These are storage/arithmetic bounds, not a particular camera's ranges. Keep ordinary
        // out-of-camera-range values intact for the existing compatibility warnings/clamping.
        let numbers: [(String, Double?)] = [
            ("highlightTone", s.highlightTone), ("shadowTone", s.shadowTone),
            ("exposureBias", s.exposureBias), ("color", s.color.map(Double.init)),
            ("sharpness", s.sharpness.map(Double.init)), ("highISONR", s.highISONR.map(Double.init)),
            ("clarity", s.clarity.map(Double.init)), ("noiseReduction", s.noiseReduction.map(Double.init)),
            ("monochromaticColorWC", s.monochromaticColorWC.map(Double.init)),
            ("monochromaticColorMG", s.monochromaticColorMG.map(Double.init)),
            ("whiteBalance.shiftRed", s.whiteBalance.map { Double($0.shiftRed) }),
            ("whiteBalance.shiftBlue", s.whiteBalance.map { Double($0.shiftBlue) }),
            ("whiteBalance.kelvin", s.whiteBalance?.kelvin.map(Double.init))
        ]
        for (field, value) in numbers {
            if let value, !value.isFinite || value < Double(Int32.min) || value > Double(Int32.max) {
                return field
            }
        }
        return nil
    }
}
