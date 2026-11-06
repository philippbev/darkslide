import XCTest
@testable import FujiCookbook

/// The hints a refused field earns on the push results screen, from `SlotWriteResult` alone. Each
/// names a cause the app cannot see over USB, so a tester checks one menu instead of filing a bug.
///
/// Camera facts in these tests are from zgrimz/fujifilm-ptp-reference:
/// `docs/04-custom-slots.md#why-a-write-is-refused`, and `docs/07-cameras.md#gfx100rf`.
final class RefusalHintTests: XCTestCase {
    private func result(rejecting prop: FujiPTP.PresetProp, wrote: Data) -> SlotWriteResult {
        SlotWriteResult(slot: 3, outcome: .partiallyApplied, nameWritten: true, nameApplied: "Hint",
                        clampedFields: [],
                        fields: [FieldResult(code: prop.rawValue, field: prop.debugName, isRecipeField: true,
                                             outcome: .rejected(code: FujiPTP.responseInvalidDevicePropValue),
                                             wrote: wrote)],
                        errorMessage: nil)
    }

    /// Clarity is refused for every value while the bank's image format is HEIF (X-T50 fw 1.32,
    /// 2026-10-15; GFX100RF, published). The hint names the format, which the app can't read.
    func testARefusedClarityNamesTheHEIFBank() {
        let r = result(rejecting: .clarity, wrote: FujiEncoding.packI16(20))
        XCTAssertEqual(r.clarityRefusalHint?.contains("HEIF"), true)
        XCTAssertNil(r.toningZeroRefusalHint)
        XCTAssertNil(r.dynamicRangeRefusalHint)
    }

    /// A GFX100RF refusing a toning of exactly 0 is a published report of conflicting provenance
    /// (zgrimz/fujifilm-ptp-reference `docs/errata.md#a-zero-on-the-monochromatic-color-axes`); the
    /// hint covers it. A refused tint is a different
    /// question — a colour simulation, or Sepia — and gets no hint.
    func testAToningZeroRefusalIsHintedOnlyForAZeroWrite() {
        XCTAssertNotNil(result(rejecting: .monochromaticWC, wrote: FujiEncoding.packI16(0)).toningZeroRefusalHint)
        XCTAssertNotNil(result(rejecting: .monochromaticMG, wrote: FujiEncoding.packI16(0)).toningZeroRefusalHint)
        XCTAssertNil(result(rejecting: .monochromaticWC, wrote: FujiEncoding.packI16(30)).toningZeroRefusalHint)
        XCTAssertNil(result(rejecting: .monochromaticWC, wrote: FujiEncoding.packI16(0)).clarityRefusalHint)
    }
}
