import SwiftUI

/// A decorative barcode: bars and gaps 1 to 3 pt wide, derived from a seed (a recipe's id), so a
/// recipe always shows the same code. It encodes nothing and is hidden from VoiceOver.
struct DSBarcode: View {
    let seed: String
    var height: CGFloat = DSSize.barcodeHeight

    var body: some View {
        Canvas { context, size in
            let widths = Self.widths(for: seed)
            var x: CGFloat = 0
            var index = 0
            // The pattern repeats until the width is filled; even entries are bars, odd are gaps.
            while x < size.width, !widths.isEmpty {
                let width = CGFloat(widths[index % widths.count])
                if index % 2 == 0 {
                    context.fill(Path(CGRect(x: x, y: 0, width: min(width, size.width - x), height: size.height)),
                                 with: .color(DSColor.textPrimary))
                }
                x += width
                index += 1
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    static let elementCount = 48

    /// The widths in points, alternating bar and gap, the same for the same seed on every launch
    /// and device. FNV-1a over the seed's bytes feeds a xorshift generator; Swift's own hashing is
    /// seeded per launch and would change the code each time.
    static func widths(for seed: String) -> [Int] {
        var state: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in seed.utf8 {
            state ^= UInt64(byte)
            state &*= 0x0000_0100_0000_01B3
        }
        if state == 0 { state = 0x9E37_79B9_7F4A_7C15 }
        return (0..<elementCount).map { _ in
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return Int(state % 3) + 1
        }
    }
}

#Preview("Barcode") {
    VStack(spacing: DSSpacing.m) {
        DSBarcode(seed: "1B6F0C2E-0000-4000-8000-000000000034")
        DSBarcode(seed: "another recipe")
    }
    .padding()
    .background(DSColor.surface)
}
