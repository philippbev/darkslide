import XCTest
@testable import FujiCookbook

/// How a develop resolves dynamic range against the frame it is developing.
///
/// `FujiEncoding.drToPercent` has no value for DR Auto, and no working DR Auto encoding for a
/// develop is established (zgrimz/fujifilm-ptp-reference `docs/05-raw-conversion.md#dynamic-range`).
/// So a recipe's Auto resolves to the frame's own DR *deliberately*: the value is chosen rather than
/// inherited from the RAF, and can be explained.
///
/// Camera facts in these tests are from zgrimz/fujifilm-ptp-reference:
/// `docs/06-conversion-profile.md#table-length`, `docs/03-encodings.md#0xd190-dynamic-range`, and
/// `docs/04-custom-slots.md#the-d-range-priority-interlock`.
final class RawConvDynamicRangeTests: XCTestCase {

    private let model = CameraModelRegistry.shared.demoModel

    /// A demo profile whose dynamic-range cell reads `percent`, standing in for a RAF shot at that
    /// DR. Written through the same offset arithmetic `patch` uses, so a layout change breaks this
    /// helper rather than silently relocating what it asserts on.
    private func base(shotAt percent: Int) throws -> (blob: Data, layout: FujiRawConvProfile.Layout) {
        var blob = FujiRawConvProfile.demoBaseProfile()
        let layout = try XCTUnwrap(FujiRawConvProfile.resolveLayout(blob))
        let offset = layout.base + FujiRawConvProfile.Field.dynamicRange.rawValue * FujiRawConvProfile.fieldSize
        withUnsafeBytes(of: Int32(percent).littleEndian) { blob.replaceSubrange(offset..<(offset + 4), with: $0) }
        return (blob, layout)
    }

    private func resolve(_ dr: DynamicRange?, shotAt shot: Int) throws -> FujiRawConvProfile.DynamicRangeResolution {
        let (blob, layout) = try base(shotAt: shot)
        return FujiRawConvProfile.resolveDynamicRange(RecipeSettings(dynamicRange: dr),
                                                      base: blob, layout: layout)
    }

    /// What `patch` actually leaves in the cell, decoded back out — the thing the camera renders from.
    private func patched(_ dr: DynamicRange?, shotAt shot: Int) throws -> DynamicRange? {
        let (blob, layout) = try base(shotAt: shot)
        let out = FujiRawConvProfile.patch(base: blob, with: RecipeSettings(dynamicRange: dr),
                                           model: model, layout: layout)
        return FujiRawConvProfile.decode(out, layout: layout).dynamicRange
    }

    // MARK: DR Auto

    func testAutoIsCappedAtTheCeilingTheCamerasOwnAutoObeys() throws {
        // A frame's as-shot DR400 may be a manual setting the camera was left on rather than an
        // Auto decision, so a DR-Auto develop doesn't inherit it. The ceiling is measured: frames shot
        // at DR AUTO on an X-T50 at ISO 640+ resolved no higher than DR200, and a −1 in cell 6 is
        // stored but develops at DR100 (zgrimz/fujifilm-ptp-reference
        // `docs/05-raw-conversion.md#dynamic-range`, `docs/06-conversion-profile.md#dynamic-range-cell-6`).
        // See `FujiRawConvProfile.autoCeiling`.
        XCTAssertEqual(try resolve(.auto, shotAt: 400), .autoResolved(picked: 200, asShot: 400))
        XCTAssertEqual(try patched(.auto, shotAt: 400), .dr200)
    }

    func testAutoNeverExceedsWhatTheFrameWasShotAt() throws {
        // Below the ceiling the frame still wins: Auto can't conjure headroom that was never captured.
        XCTAssertEqual(try resolve(.auto, shotAt: 100), .autoResolved(picked: 100, asShot: 100))
        XCTAssertEqual(try patched(.auto, shotAt: 100), .dr100)

        XCTAssertEqual(try resolve(.auto, shotAt: 200), .autoResolved(picked: 200, asShot: 200))
        XCTAssertEqual(try patched(.auto, shotAt: 200), .dr200)
    }

    // MARK: A named DR

    func testANamedDynamicRangeIsAppliedWhenTheFrameCanCarryIt() throws {
        XCTAssertEqual(try resolve(.dr200, shotAt: 400), .applied(200))
        XCTAssertEqual(try patched(.dr200, shotAt: 400), .dr200,
                       "the fix for a too-flat DR400 develop is a recipe that names DR200 — it must land")
        XCTAssertEqual(try resolve(.dr400, shotAt: 400), .applied(400),
                       "a recipe that names DR400 still gets it — only Auto is capped")
    }

    func testANamedDynamicRangeIsCappedToTheFrameItCannotExceed() throws {
        // A DR higher than the frame was shot at turned the X-T50's conversion green in the tested
        // cases; the cause was not isolated (zgrimz/fujifilm-ptp-reference
        // `docs/05-raw-conversion.md#dynamic-range`).
        XCTAssertEqual(try resolve(.dr400, shotAt: 200), .cappedToAsShot(recipe: 400, asShot: 200))
        XCTAssertEqual(try patched(.dr400, shotAt: 200), .dr200)
        XCTAssertEqual(try resolve(.dr400, shotAt: 100), .cappedToAsShot(recipe: 400, asShot: 100))
    }

    func testARecipeWithNoDynamicRangeLeavesTheCellAlone() throws {
        XCTAssertEqual(try resolve(nil, shotAt: 400), .untouched)
        let (blob, layout) = try base(shotAt: 400)
        let out = FujiRawConvProfile.patch(base: blob, with: RecipeSettings(), model: model, layout: layout)
        XCTAssertEqual(out, blob, "an empty recipe patches nothing at all")
    }

    // MARK: The probe seam

    func testProbeWritingPutsTheRawValueInTheCellUntouched() throws {
        // The point of `probeWriting` is that it does NOT encode: the probe has to be able to put a
        // value the encoder would never produce into cell 6, which is how we find out whether the
        // camera accepts the DR-Auto sentinel there at all.
        let (blob, layout) = try base(shotAt: 400)
        for raw in [FujiEncoding.drAutoSlotValue, 0, 100, 200, 400] {
            let out = FujiRawConvProfile.probeWriting(base: blob, layout: layout,
                                                      field: .dynamicRange, rawValue: raw)
            XCTAssertEqual(FujiRawConvProfile.rawCell(out, .dynamicRange, layout), raw)
            XCTAssertEqual(out.count, blob.count, "a probe write must not resize the blob")
        }
    }

    func testProbeWritingRespectsAShortParameterTable() throws {
        // The X-H1-shaped 23-cell blob. Cell 6 is addressable there; cell 27 is not, and a write
        // past the table would corrupt whatever follows it.
        let blob = FujiRawConvProfile.demoShortBaseProfile()
        let layout = try XCTUnwrap(FujiRawConvProfile.resolveLayout(blob))
        let out = FujiRawConvProfile.probeWriting(base: blob, layout: layout,
                                                  field: .dynamicRange, rawValue: 200)
        XCTAssertEqual(FujiRawConvProfile.rawCell(out, .dynamicRange, layout), 200)

        let past = FujiRawConvProfile.probeWriting(base: blob, layout: layout,
                                                   field: .clarity, rawValue: 30)
        XCTAssertEqual(past, blob, "a cell beyond the table is not writable and must change nothing")
    }

    // MARK: What the user is told

    func testTheHeadroomCapIsBothScannableAndExplained() {
        // The DR cap goes to both channels on purpose, and they are not interchangeable.
        // `clampedFields` is the scannable "what changed" list and is what makes a capped develop
        // show up in the shared problem report; `notes` carries the reason. Neither alone is enough:
        // the list without the note leaves "Dynamic Range" unexplained, and the note without the
        // list means a green-cast-avoiding cap never reaches the log.
        var capped = ConversionResult(sourceFilename: "DSCF4072.RAF", success: true,
                                      clampedFields: ["Dynamic Range"])
        capped.notes = ["Dynamic Range: developed at DR200, not the recipe's DR400."]
        XCTAssertTrue(capped.isReportableAnomaly,
                      "a capped dynamic range is a develop that doesn't match its recipe")
    }

    func testADisclosureIsNotAnAnomaly() {
        // DR Auto is the default in `RecipeSettings.neutral`, so routing its disclosure through
        // `clampedFields` or `warnings` would mark a large share of all develops as anomalies in the
        // shared problem report — and mislabel an explanation as something having gone wrong.
        var result = ConversionResult(sourceFilename: "DSCF4072.RAF", success: true,
                                      clampedFields: [])
        result.notes = ["Dynamic Range: kept this shot's DR400."]
        XCTAssertFalse(result.isReportableAnomaly,
                       "a note explains a render; it does not flag one")
    }

    func testAPushRaisesNothingForDynamicRange() {
        // DR Auto briefly raised a `.notWritten` advisory here, on the belief that it had no wire
        // value. `0xD190 = 0xFFFF` is DR Auto (X-T50 fw 1.32), so the push writes it and there is
        // nothing to warn about.
        for dr in DynamicRange.allCases {
            let issues = RecipeCompatibility.analyze(RecipeSettings(dynamicRange: dr), for: model)
            XCTAssertFalse(issues.contains { $0.field == .dynamicRange },
                           "\(dr.displayName) is writable to a slot")
        }
    }

    /// Inverted on 2026-09-17, when `0xD191` turned out to be D-Range Priority. The push writes it
    /// now, so the warning is the other way round: the camera drives Dynamic Range while D-Range
    /// Priority is on, and refuses every write to D190 until it is off.
    func testAPushSaysDynamicRangeYieldsToDRangePriority() {
        let both = RecipeSettings(dynamicRange: .dr400, dRangePriority: .strong)
        let issues = RecipeCompatibility.analyze(both, for: model)
        XCTAssertTrue(issues.contains { $0.field == .dynamicRange && $0.kind == .notWritten },
                      "the dynamic range is the one that won't be written")
        XCTAssertFalse(issues.contains { $0.field == .dRangePriority },
                       "and D-Range Priority itself is no longer the unwritable one")

        // A priority with no dynamic range beside it contradicts nothing.
        let alone = RecipeCompatibility.analyze(RecipeSettings(dRangePriority: .strong), for: model)
        XCTAssertFalse(alone.contains { $0.kind == .notWritten })

        let off = RecipeCompatibility.analyze(RecipeSettings(dynamicRange: .dr400, dRangePriority: .off),
                                              for: model)
        XCTAssertFalse(off.contains { $0.field == .dynamicRange },
                       "Off asks for nothing, so the dynamic range goes as written")
    }
}
