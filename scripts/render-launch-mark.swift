// Renders LaunchMark PNGs from the AppIcon.icon SVG layers (light and dark), cropped to the artwork.
// usage: swift scripts/render-launch-mark.swift FujiCookbook/AppIcon.icon/Assets FujiCookbook/Assets.xcassets/DarkslideLaunchMark.imageset
// Rerun after changing AppIcon.icon so the launch screen keeps matching the icon.
import AppKit

let args = CommandLine.arguments
let assets = URL(fileURLWithPath: args[1])
let out = URL(fileURLWithPath: args[2])

// Bottom to top, with the dark override colour from icon.json and the layer opacity.
let layers: [(file: String, dark: String?, opacity: CGFloat)] = [
    ("1_tank.svg", "#4A4A47", 1),
    ("2_card-1-frame.svg", "#4A4A47", 1),
    ("2_card-2-surface.svg", "#F2F2EF", 1),
    ("2_card-3-number.svg", "#3350F0", 1),
    ("2_card-4-data.svg", "#9E9D98", 1),
    ("2_card-5-lines.svg", "#3A3A38", 1),
    ("3_liquid-1-body.svg", "#3350F0", 0.62),
    ("3_liquid-2-surface.svg", "#3350F0", 1),
]

// Artwork bounds on the 1024 grid: tank x 152–872, tab top y 112, tank bottom y 880.
let crop = CGRect(x: 152, y: 112, width: 720, height: 768)
let pointSize = CGSize(width: 120, height: 128)

func svg(_ file: String, dark: String?) throws -> NSImage {
    var text = try String(contentsOf: assets.appendingPathComponent(file), encoding: .utf8)
    if let dark {
        text = text.replacingOccurrences(of: "fill=\"#[0-9A-Fa-f]{6}\"", with: "fill=\"\(dark)\"", options: .regularExpression)
    }
    guard let image = NSImage(data: Data(text.utf8)) else { throw NSError(domain: "svg", code: 1) }
    return image
}

for (suffix, isDark) in [("", false), ("-dark", true)] {
    for scale in [1, 2, 3] {
        let w = Int(pointSize.width) * scale, h = Int(pointSize.height) * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let k = CGFloat(w) / crop.width
        // Place the 1024 canvas so the crop rect fills the bitmap (AppKit's y axis points up).
        let dest = NSRect(x: -crop.minX * k, y: -(1024 - crop.maxY) * k, width: 1024 * k, height: 1024 * k)
        for layer in layers {
            let image = try svg(layer.file, dark: isDark ? layer.dark : nil)
            image.draw(in: dest, from: .zero, operation: .sourceOver, fraction: layer.opacity)
        }
        NSGraphicsContext.restoreGraphicsState()
        let name = "LaunchMark\(suffix)\(scale == 1 ? "" : "@\(scale)x").png"
        try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
        print(name, w, h)
    }
}
