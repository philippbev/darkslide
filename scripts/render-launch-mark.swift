// Renders the launch screen mark from AppIcon.icon (light and dark), cropped to the artwork.
// usage: swift scripts/render-launch-mark.swift FujiCookbook/AppIcon.icon FujiCookbook/Assets.xcassets/DarkslideLaunchCard.imageset
// Rerun after changing AppIcon.icon so the launch screen keeps matching the icon.
//
// Layer order and colours come from icon.json, so the script needs no edits when the icon changes.
// A static launch screen is flat: Liquid Glass does not exist there. Layers filled with the icon's own
// background colour (the "Lichtnetz" in v3) would be invisible, so they are left out and the mark is
// just the card and its shadow. The background colour lives in DarkslideLaunchBath.
import AppKit

let args = CommandLine.arguments
let icon = URL(fileURLWithPath: args[1])
let out = URL(fileURLWithPath: args[2])

// One launch point per 6 icon pixels keeps the mark at the size the v2.6 launch screen had.
let pixelsPerPoint: CGFloat = 6

struct Layer { let file: String; let light: String?; let dark: String?; let opacity: CGFloat }

func hex(_ value: Any?) -> String? {
    guard let solid = (value as? [String: Any])?["solid"] as? String, solid.hasPrefix("srgb:") else { return nil }
    let c = solid.dropFirst(5).split(separator: ",").compactMap { Double($0) }
    guard c.count >= 3 else { return nil }
    return String(format: "#%02X%02X%02X", Int((c[0] * 255).rounded()), Int((c[1] * 255).rounded()), Int((c[2] * 255).rounded()))
}

// Returns (default, dark) fills; nil means "keep the colour from the SVG".
func fills(_ node: [String: Any]) -> (String?, String?) {
    if let fill = hex(node["fill"]) { return (fill, fill) }
    var light: String?, dark: String?
    for spec in node["fill-specializations"] as? [[String: Any]] ?? [] {
        if spec["appearance"] as? String == "dark" { dark = hex(spec["value"]) }
        else if spec["appearance"] == nil { light = hex(spec["value"]) }
    }
    return (light, dark ?? light)
}

let json = try JSONSerialization.jsonObject(with: Data(contentsOf: icon.appendingPathComponent("icon.json"))) as! [String: Any]
let (backgroundLight, backgroundDark) = fills(json)
print("background:", backgroundLight ?? "-", backgroundDark ?? "-")

// icon.json lists front to back; drawing needs back to front.
var layers: [Layer] = []
for group in (json["groups"] as? [[String: Any]] ?? []).reversed() {
    for layer in (group["layers"] as? [[String: Any]] ?? []).reversed() where layer["hidden"] as? Bool != true {
        let (light, dark) = fills(layer)
        if light != nil, light == backgroundLight, dark == backgroundDark { continue }
        layers.append(Layer(file: layer["image-name"] as! String, light: light, dark: dark,
                            opacity: CGFloat(layer["opacity"] as? Double ?? 1)))
    }
}

func svg(_ file: String, fill: String?) throws -> NSImage {
    var text = try String(contentsOf: icon.appendingPathComponent("Assets").appendingPathComponent(file), encoding: .utf8)
    if let fill {
        text = text.replacingOccurrences(of: "fill=\"#[0-9A-Fa-f]{6}\"", with: "fill=\"\(fill)\"", options: .regularExpression)
    }
    guard let image = NSImage(data: Data(text.utf8)) else { throw NSError(domain: "svg", code: 1) }
    return image
}

// origin is the crop's top-left on the 1024 grid; AppKit's y axis points up.
func render(size: CGSize, origin: CGPoint, scale: CGFloat, dark: Bool) throws -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let dest = NSRect(x: -origin.x * scale, y: size.height - (1024 - origin.y) * scale,
                      width: 1024 * scale, height: 1024 * scale)
    for layer in layers {
        let image = try svg(layer.file, fill: dark ? layer.dark : layer.light)
        image.draw(in: dest, from: .zero, operation: .sourceOver, fraction: layer.opacity)
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// Find the artwork bounds on the 1024 grid (bitmap rows run top-down), then round out to whole points.
let full = try render(size: CGSize(width: 1024, height: 1024), origin: .zero, scale: 1, dark: false)
var minX = 1024, minY = 1024, maxX = -1, maxY = -1
for y in 0..<1024 { for x in 0..<1024 where full.colorAt(x: x, y: y)!.alphaComponent > 0.01 {
    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
} }
let p = Int(pixelsPerPoint) * 2  // even point sizes
let x0 = minX / p * p, y0 = minY / p * p
let x1 = (maxX / p + 1) * p, y1 = (maxY / p + 1) * p
let points = CGSize(width: CGFloat(x1 - x0) / pixelsPerPoint, height: CGFloat(y1 - y0) / pixelsPerPoint)
print("layers:", layers.map(\.file).joined(separator: ", "))
print("crop:", x0, y0, x1, y1, "points:", points)

for (suffix, dark) in [("", false), ("-dark", true)] {
    for scale in [1, 2, 3] {
        let size = CGSize(width: points.width * CGFloat(scale), height: points.height * CGFloat(scale))
        let rep = try render(size: size, origin: CGPoint(x: x0, y: y0), scale: CGFloat(scale) / pixelsPerPoint, dark: dark)
        let name = "LaunchMark\(suffix)\(scale == 1 ? "" : "@\(scale)x").png"
        try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
        print(name, Int(size.width), Int(size.height))
    }
}
