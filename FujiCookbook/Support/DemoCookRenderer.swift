import UIKit

/// A stand-in JPEG for the **Demo Camera**'s develop, so the Kitchen runs end to end with no
/// hardware.
///
/// There is no image processor to run, so it draws a gradient and labels chosen from the settings
/// `MockCameraTransport` decoded out of the patched profile: a different recipe gives a visibly
/// different result.
enum DemoCookRenderer {
    static func render(settings: RecipeSettings, filename: String) -> Data {
        let size = CGSize(width: 1200, height: 800)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let (top, bottom) = gradientColors(for: settings)
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors, locations: [0, 1]) {
                cg.drawLinearGradient(gradient,
                                      start: .zero,
                                      end: CGPoint(x: 0, y: size.height),
                                      options: [])
            }

            // A darkened band along the bottom so it reads as a photo, not a flat swatch.
            cg.setFillColor(UIColor.black.withAlphaComponent(0.18).cgColor)
            cg.fill(CGRect(x: 0, y: size.height - 220, width: size.width, height: 220))

            let simName = settings.filmSimulation?.displayName ?? "No Film Simulation"
            draw(simName, at: CGPoint(x: 48, y: size.height - 188),
                 font: .systemFont(ofSize: 56, weight: .bold), color: .white)
            draw(detailLine(settings), at: CGPoint(x: 48, y: size.height - 110),
                 font: .systemFont(ofSize: 30, weight: .medium), color: UIColor.white.withAlphaComponent(0.9))
            draw("Demo conversion · \(filename)", at: CGPoint(x: 48, y: 48),
                 font: .systemFont(ofSize: 26, weight: .semibold), color: UIColor.white.withAlphaComponent(0.85))
        }
        // 0.85 keeps the demo output clearly a JPEG without bloating the in-memory result.
        return image.jpegData(compressionQuality: 0.85) ?? Data()
    }

    private static func draw(_ text: String, at point: CGPoint, font: UIFont, color: UIColor) {
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.5)
        shadow.shadowBlurRadius = 6
        shadow.shadowOffset = CGSize(width: 0, height: 2)
        (text as NSString).draw(at: point, withAttributes: [
            .font: font, .foregroundColor: color, .shadow: shadow
        ])
    }

    private static func detailLine(_ s: RecipeSettings) -> String {
        var parts: [String] = []
        if let dr = s.dynamicRange { parts.append(dr.displayName) }
        if let wb = s.whiteBalance { parts.append("WB \(wb.mode.displayName)") }
        if let g = s.grain, g.strength != .off { parts.append("Grain \(g.strength.displayName)") }
        if let hl = s.highlightTone { parts.append("H \(RecipeSettingsFormatter.tone(hl))") }
        if let sh = s.shadowTone { parts.append("S \(RecipeSettingsFormatter.tone(sh))") }
        return parts.isEmpty ? "Neutral" : parts.joined(separator: "  ·  ")
    }

    /// Pick a gradient that loosely evokes the film simulation, so different recipes look different.
    private static func gradientColors(for s: RecipeSettings) -> (UIColor, UIColor) {
        if s.filmSimulation?.isMonochrome ?? false {
            return (UIColor(white: 0.78, alpha: 1), UIColor(white: 0.12, alpha: 1))
        }
        switch s.filmSimulation {
        case .velvia:        return (UIColor(red: 0.95, green: 0.45, blue: 0.35, alpha: 1), UIColor(red: 0.35, green: 0.08, blue: 0.20, alpha: 1))
        case .classicChrome: return (UIColor(red: 0.62, green: 0.66, blue: 0.66, alpha: 1), UIColor(red: 0.20, green: 0.26, blue: 0.30, alpha: 1))
        case .classicNeg:    return (UIColor(red: 0.70, green: 0.66, blue: 0.50, alpha: 1), UIColor(red: 0.22, green: 0.28, blue: 0.30, alpha: 1))
        case .eterna, .eternaBleachBypass:
            return (UIColor(red: 0.66, green: 0.68, blue: 0.70, alpha: 1), UIColor(red: 0.18, green: 0.22, blue: 0.26, alpha: 1))
        case .nostalgicNeg:  return (UIColor(red: 0.86, green: 0.66, blue: 0.42, alpha: 1), UIColor(red: 0.30, green: 0.16, blue: 0.12, alpha: 1))
        case .astia:         return (UIColor(red: 0.92, green: 0.74, blue: 0.70, alpha: 1), UIColor(red: 0.36, green: 0.22, blue: 0.28, alpha: 1))
        default:             return (UIColor(red: 0.55, green: 0.74, blue: 0.92, alpha: 1), UIColor(red: 0.12, green: 0.22, blue: 0.40, alpha: 1))
        }
    }
}
