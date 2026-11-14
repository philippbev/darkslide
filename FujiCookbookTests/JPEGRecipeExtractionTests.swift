import XCTest
@testable import FujiCookbook

/// Metadata-only envelopes exercise independent EXIF encodings and malformed boundaries.
/// These are synthetic parser cases, not claims about camera firmware or image pixels.
final class JPEGRecipeExtractionTests: XCTestCase {
    func testBothOuterByteOrdersKeepMakerNoteLittleEndian() throws {
        for big in [false, true] {
            let result = try decode(jpeg([
                .short(0x1003, big ? 0x502 : 0x501), .short(0x1401, 0),
                .short(0x1001, 0x82), .signed(0x1040, -24), .signed(0x1041, 8)
            ], bigEndian: big))
            XCTAssertEqual(result.settings.filmSimulation, big ? .acrosYe : .acrosR)
            XCTAssertNil(result.settings.color)
            XCTAssertEqual(result.settings.sharpness, -1)
            XCTAssertEqual(result.settings.shadowTone, 1.5)
            XCTAssertEqual(result.settings.highlightTone, -0.5)
        }
    }

    func testSignedByteOverridePreservesDeclaredRawInteger() throws {
        let result = try decode(jpeg([
            .short(0x1003, 0x501), .bytes(0x1049, [238]), .short(0x104B, 238)
        ]))
        XCTAssertEqual(result.settings.monochromaticColorWC, -18)
        XCTAssertEqual(result.settings.monochromaticColorMG, -18)
        XCTAssertEqual(result.raw.observations.first(where: { $0.tag == 0x1049 })?.values, [238])
    }

    func testEmptyMetadataDoesNotInventPriorityOff() throws {
        XCTAssertEqual(try decode(jpeg([])).settings, RecipeSettings())
    }

    func testMissingAndIncompleteWhiteBalanceNeverInventZeroShifts() throws {
        let missing = try decode(jpeg([.short(0x1002, 0)]), scale: .heuristic)
        XCTAssertNil(missing.settings.whiteBalance)
        XCTAssertFalse(missing.warnings.isEmpty)
        let shortPair = try decode(jpeg([.short(0x1002, 0), .signed(0x100A, 20)]), scale: .times20)
        XCTAssertNil(shortPair.settings.whiteBalance)
        XCTAssertNil(shortPair.raw.lists[0x100A])
    }

    func testWhiteBalancePolicyMustBeSelectedAndIsPreserved() throws {
        let data = jpeg([.short(0x1002, 0x100), .signed(0x100A, [60, -40])])
        XCTAssertNil(try decode(data).settings.whiteBalance)
        let selected = try decode(data, scale: .times20)
        XCTAssertEqual(selected.settings.whiteBalance,
                       WhiteBalance(mode: .daylight, shiftRed: 3, shiftBlue: -2, kelvin: nil))
        let inferred = try decode(data, scale: .heuristic)
        XCTAssertEqual(inferred.settings.whiteBalance, selected.settings.whiteBalance)
        XCTAssertTrue(inferred.warnings.contains(where: { $0.contains("inferred scale") }))
        let metadata = PhotoRecipeReader.metadataToPreserve(inferred.raw, warnings: inferred.warnings,
                                                           wbShiftScale: .heuristic)
        guard case .object(let object) = metadata["jpegRecipeMetadata"] else {
            return XCTFail("Missing preserved extraction evidence")
        }
        XCTAssertEqual(object["whiteBalanceShiftPolicy"], .string("heuristic"))
    }

    func testWhiteBalanceNeverTruncatesOrAcceptsOutOfRangePairs() throws {
        for pair in [[9, 180], [21, 0], [200, 0], [-181, 0]] {
            for policy in [PhotoRecipeReader.WBShiftScale.times20, .heuristic] {
                let result = try decode(jpeg([.short(0x1002, 0), .signed(0x100A, pair)]), scale: policy)
                XCTAssertNil(result.settings.whiteBalance, "\(pair) under \(policy)")
                XCTAssertEqual(result.raw.lists[0x100A], pair)
            }
        }
        let direct = try decode(jpeg([.short(0x1002, 0), .signed(0x100A, [-2, 5])]), scale: .direct)
        XCTAssertEqual(direct.settings.whiteBalance?.shiftRed, -2)
        XCTAssertEqual(direct.settings.whiteBalance?.shiftBlue, 5)
    }

    func testDefaultReadUsesDocumentedXT50ScaleIndependentlyOfMonochromeToning() throws {
        for bigEndian in [false, true] {
            let data = jpeg([
                .short(0x1003, 0x500), .short(0x1002, 0x100), .signed(0x100A, [180, -180]),
                .bytes(0x1049, [18]), .bytes(0x104B, [238])
            ], bigEndian: bigEndian, model: "X-T50")
            let reading = try PhotoRecipeReader.read(data, filename: "synthetic-xt50.jpg")

            XCTAssertEqual(reading.recipeStatus, .found)
            XCTAssertEqual(reading.camera.model, "X-T50")
            XCTAssertEqual(reading.settings.whiteBalance,
                           WhiteBalance(mode: .daylight, shiftRed: 9, shiftBlue: -9, kelvin: nil))
            XCTAssertEqual(reading.settings.monochromaticColorWC, 18)
            XCTAssertEqual(reading.settings.monochromaticColorMG, -18)
            XCTAssertEqual(reading.recordedWBShifts, [180, -180])
            XCTAssertTrue(reading.warnings.isEmpty, "\(reading.warnings)")

            let metadata = try extractionMetadata(reading)
            XCTAssertEqual(metadata["whiteBalanceShiftPolicy"], .string("automatic"))
            XCTAssertEqual(metadata["resolvedWhiteBalanceShiftScale"], .string("times20"))
            XCTAssertEqual(metadata["whiteBalanceShiftBasis"], .string("documented_model"))
            XCTAssertEqual(metadata["whiteBalanceShiftModel"], .string("X-T50"))
            guard case .string(let source) = metadata["whiteBalanceShiftSource"] else {
                return XCTFail("Missing documented scale source")
            }
            XCTAssertTrue(source.contains("docs/10-jpeg-recipes.md"))
            guard case .array(let observations) = metadata["tags"],
                  let wbObservation = observations.first(where: {
                      guard case .object(let entry) = $0 else { return false }
                      return entry["tag"] == .string("0x100A")
                  }), case .object(let wb) = wbObservation else {
                return XCTFail("Missing original WB observation")
            }
            XCTAssertEqual(wb["rawValues"], .array([.number(180), .number(-180)]))

            let encoded = try JSONEncoder().encode(reading.preservedMetadata)
            let restored = try JSONDecoder().decode([String: JSONValue].self, from: encoded)
            XCTAssertEqual(restored, reading.preservedMetadata)
        }
    }

    func testAutomaticScaleAcceptsExactModernModelsAndAliases() throws {
        let models = [
            ("X-T50", "X-T50"), ("FUJIFILM X-T50", "X-T50"), ("  fujifilm x-t50  ", "X-T50"),
            ("X-T20", "X-T20"), ("X-T3", "X-T3"), ("X-T30", "X-T30"), ("X-T5", "X-T5"),
            ("X-H2", "X-H2"), ("X100VI", "X100VI"), ("X-S20", "X-S20"),
            ("GFX50S", "GFX50S"), ("GFX100S", "GFX100S"), ("GFX100RF", "GFX100RF"),
            ("GFX 100S", "GFX100S"), ("FUJIFILM GFX 100S", "GFX100S"), ("X-T30II", "X-T30 II")
        ]
        for (model, canonicalID) in models {
            let reading = try PhotoRecipeReader.read(jpeg([
                .short(0x1002, 0x100), .signed(0x100A, [60, -40])
            ], model: model), filename: nil)
            XCTAssertEqual(reading.settings.whiteBalance?.shiftRed, 3, model)
            XCTAssertEqual(reading.settings.whiteBalance?.shiftBlue, -2, model)
            XCTAssertTrue(reading.warnings.isEmpty, "\(model): \(reading.warnings)")
            XCTAssertEqual(try extractionMetadata(reading)["whiteBalanceShiftModel"], .string(canonicalID))
        }
    }

    func testAutomaticScaleDoesNotGuessUnknownLegacyOrDemoModels() throws {
        for model in [nil, "", "FinePix S5Pro", "FUJIFILM FinePix X100", "DEMO", "Demo Camera",
                      "X-T50 II", "X-T500", "Unknown X-T50", "X-T5 TETHER", "GFX100S prototype",
                      "X-T30 IV", "UNKNOWN"] as [String?] {
            for pair in [[60, -40], [3, -2], [0, 0]] {
                let reading = try PhotoRecipeReader.read(jpeg([
                    .short(0x1002, 0x100), .signed(0x100A, pair)
                ], model: model), filename: nil)
                XCTAssertNil(reading.settings.whiteBalance, "\(model ?? "missing") / \(pair)")
                XCTAssertEqual(reading.recordedWBShifts, pair)
                XCTAssertTrue(reading.warnings.contains(where: { $0.contains("left unspecified") }))
                let metadata = try extractionMetadata(reading)
                XCTAssertEqual(metadata["whiteBalanceShiftPolicy"], .string("automatic"))
                XCTAssertEqual(metadata["resolvedWhiteBalanceShiftScale"], .string("unknown"))
                XCTAssertEqual(metadata["whiteBalanceShiftBasis"], .string("unresolved"))
            }
        }
    }

    func testEveryRegisteredModernCameraUsesTimes20IncludingZeroAndEndpoints() throws {
        // This is a product default for the registered modern range, not a hardware evidence test.
        for pair in [[60, -40], [0, 0], [180, -180]] {
            let raw = try decode(jpeg([.short(0x1002, 0x100), .signed(0x100A, pair)])).raw
            for model in CameraModelRegistry.shared.models {
                var warnings: [String] = []
                let settings = PhotoRecipeReader.decodeSettings(raw, warnings: &warnings,
                    wbShiftScale: .automatic, cameraModel: model.id)
                if model.id == CameraModelRegistry.demoModelID {
                    XCTAssertNil(settings.whiteBalance)
                } else if model.processor == .exrProcessor {
                    // The legacy gate in `automaticWBShiftMapping`: a body added to the registry is
                    // not opted into the ×20 default by that alone.
                    XCTAssertNil(settings.whiteBalance, model.id)
                    XCTAssertTrue(warnings.contains { $0.contains("couldn't be recovered") }, "\(model.id): \(warnings)")
                } else {
                    XCTAssertEqual(settings.whiteBalance,
                        WhiteBalance(mode: .daylight, shiftRed: pair[0] / 20, shiftBlue: pair[1] / 20, kelvin: nil),
                        "\(model.id): \(pair)")
                    XCTAssertTrue(warnings.isEmpty, "\(model.id): \(warnings)")
                }
            }
        }
    }

    func testAutomaticScalePreservesDistinctEvidenceBasisAndRawValuesThroughJSON() throws {
        for (model, basis) in [("X-T50", "documented_model"), ("X-T30", "documented_model"),
                               ("X-H2", "published_model"), ("X-T20", "modern_camera_default"),
                               ("X-T5", "modern_camera_default"), ("GFX100S", "modern_camera_default")] {
            let reading = try PhotoRecipeReader.read(jpeg([
                .short(0x1002, 0x100), .signed(0x100A, [60, -40])
            ], model: model), filename: nil)
            let metadata = try extractionMetadata(reading)
            XCTAssertEqual(metadata["whiteBalanceShiftPolicy"], .string("automatic"))
            XCTAssertEqual(metadata["resolvedWhiteBalanceShiftScale"], .string("times20"))
            XCTAssertEqual(metadata["whiteBalanceShiftBasis"], .string(basis), model)
            XCTAssertEqual(metadata["whiteBalanceShiftModel"], .string(model))
            guard case .string(let source) = metadata["whiteBalanceShiftSource"] else {
                return XCTFail("Missing scale source for \(model)")
            }
            // One section of the reference holds every body's evidence, whatever the basis.
            XCTAssertEqual(source,
                           "https://github.com/zgrimz/fujifilm-ptp-reference/blob/main/docs/10-jpeg-recipes.md#white-balance-scaling",
                           model)
            guard case .array(let observations) = metadata["tags"],
                  let wbObservation = observations.first(where: {
                      guard case .object(let entry) = $0 else { return false }
                      return entry["tag"] == .string("0x100A")
                  }), case .object(let wb) = wbObservation else {
                return XCTFail("Missing original WB observation for \(model)")
            }
            XCTAssertEqual(wb["rawValues"], .array([.number(60), .number(-40)]))
            let encoded = try JSONEncoder().encode(reading.preservedMetadata)
            XCTAssertEqual(try JSONDecoder().decode([String: JSONValue].self, from: encoded),
                           reading.preservedMetadata)
        }
    }

    func testExplicitWhiteBalancePolicyOverridesDocumentedModel() throws {
        let data = jpeg([.short(0x1002, 0x100), .signed(0x100A, [3, -2])], model: "X-T50")
        for policy in PhotoRecipeReader.WBShiftScale.allCases where policy != .automatic {
            let reading = try PhotoRecipeReader.read(data, filename: nil, wbShiftScale: policy)
            if policy == .direct || policy == .heuristic {
                XCTAssertEqual(reading.settings.whiteBalance?.shiftRed, 3)
                XCTAssertEqual(reading.settings.whiteBalance?.shiftBlue, -2)
            } else {
                XCTAssertNil(reading.settings.whiteBalance, "\(policy)")
            }
            let metadata = try extractionMetadata(reading)
            XCTAssertEqual(metadata["whiteBalanceShiftPolicy"], .string(policy.rawValue))
            XCTAssertEqual(metadata["whiteBalanceShiftBasis"], .string("explicit_policy"))
        }

        let unknown = try PhotoRecipeReader.read(jpeg([
            .short(0x1002, 0x100), .signed(0x100A, [60, -40])
        ], model: "Undocumented body"), filename: nil, wbShiftScale: .times20)
        XCTAssertEqual(unknown.settings.whiteBalance?.shiftRed, 3)
        XCTAssertEqual(unknown.settings.whiteBalance?.shiftBlue, -2)
    }

    func testAutomaticScaleDoesNotRoundClampOrFallBackToDirectForInvalidModernPairs() throws {
        for model in ["X-T50", "X-T30", "X-H2", "X-T20", "GFX100RF"] {
            for pair in [[3, -2], [9, 180], [21, 0], [200, 0], [-181, 0], [60, 3]] {
                let reading = try PhotoRecipeReader.read(jpeg([
                    .short(0x1002, 0x100), .signed(0x100A, pair)
                ], model: model), filename: nil)
                XCTAssertNil(reading.settings.whiteBalance, "\(model): \(pair)")
                XCTAssertEqual(reading.recordedWBShifts, pair)
                XCTAssertTrue(reading.warnings.contains(where: { $0.contains("whole steps") }))
                XCTAssertEqual(try extractionMetadata(reading)["resolvedWhiteBalanceShiftScale"], .string("times20"))
            }
        }
    }

    func testAutomaticScaleStillRequiresACompleteValidWhiteBalance() throws {
        for tags in [
            [Tag.short(0x1002, 0x100)],
            [.short(0x1002, 0x100), .signed(0x100A, 60)],
            [.short(0x1002, 0xFF0), .signed(0x100A, [0, 0])],
            [.short(0x1002, 0xF02), .signed(0x100A, [0, 0])]
        ] {
            let reading = try PhotoRecipeReader.read(jpeg(tags, model: "X-T50"), filename: nil)
            XCTAssertNil(reading.settings.whiteBalance)
            XCTAssertFalse(reading.warnings.isEmpty)
        }
        let zero = try PhotoRecipeReader.read(jpeg([
            .short(0x1002, 0x100), .signed(0x100A, [0, 0])
        ], model: "X-T50"), filename: nil)
        XCTAssertEqual(zero.settings.whiteBalance,
                       WhiteBalance(mode: .daylight, shiftRed: 0, shiftBlue: 0, kelvin: nil))
    }

    func testAutomaticScaleUsesMakerNoteModelOnlyWhenExifModelIsAbsent() throws {
        for modelTag in [UInt16(0x1447), UInt16(0x1448)] {
            let tags: [Tag] = [.short(0x1002, 0x100), .signed(0x100A, [60, -40]),
                               .text(modelTag, "X-T50")]
            let fallback = try PhotoRecipeReader.read(jpeg(tags), filename: nil)
            XCTAssertEqual(fallback.settings.whiteBalance?.shiftRed, 3)
            XCTAssertEqual(fallback.settings.whiteBalance?.shiftBlue, -2)

            let differentExifModel = try PhotoRecipeReader.read(jpeg(tags, model: "X-T5"), filename: nil)
            XCTAssertEqual(differentExifModel.settings.whiteBalance?.shiftRed, 3)
            XCTAssertEqual(try extractionMetadata(differentExifModel)["whiteBalanceShiftModel"], .string("X-T5"))
            XCTAssertEqual(try extractionMetadata(differentExifModel)["whiteBalanceShiftBasis"], .string("modern_camera_default"))

            let unknownExifModel = try PhotoRecipeReader.read(jpeg(tags, model: "Undocumented body"), filename: nil)
            XCTAssertNil(unknownExifModel.settings.whiteBalance)
        }
    }

    private func extractionMetadata(_ reading: PhotoRecipeReading) throws -> [String: JSONValue] {
        let value = try XCTUnwrap(reading.preservedMetadata["jpegRecipeMetadata"])
        guard case .object(let metadata) = value else {
            throw NSError(domain: "JPEGRecipeExtractionTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Expected preserved metadata object"])
        }
        return metadata
    }

    func testKelvinWithoutTemperatureAndCustomWBRemainObservations() throws {
        for mode in [0xFF0, 0xF02] {
            let result = try decode(jpeg([.short(0x1002, mode), .signed(0x100A, [0, 0])]), scale: .direct)
            XCTAssertNil(result.settings.whiteBalance)
            XCTAssertEqual(result.raw.ints[0x1002], mode)
        }
    }

    func testLegacyUnknownAndIncompleteDynamicRangeStayUnspecified() throws {
        for tags in [[Tag.short(0x1402, 0x200)], [.short(0x1402, 999), .short(0x1403, 200)],
                     [.short(0x1402, 1)], [.short(0x1402, 1), .short(0x1403, 800)]] {
            XCTAssertNil(try decode(jpeg(tags)).settings.dynamicRange)
        }
        XCTAssertEqual(try decode(jpeg([.short(0x1402, 1), .short(0x1403, 400)])).settings.dynamicRange, .dr400)
        XCTAssertEqual(try decode(jpeg([.short(0x1402, 0), .short(0x1403, 400)])).settings.dynamicRange, .auto)
    }

    func testPriorityRequiresKnownModeAndFixedStrength() throws {
        for tags in [[Tag.short(0x1443, 1)], [.short(0x1443, 2), .short(0x1445, 1)]] {
            XCTAssertNil(try decode(jpeg(tags)).settings.dRangePriority)
        }
        let result = try decode(jpeg([
            .short(0x1443, 0), .short(0x1444, 3), .short(0x1402, 1), .short(0x1403, 400),
            .signed(0x1040, -32), .signed(0x1041, -16)
        ]))
        XCTAssertEqual(result.settings.dRangePriority, .auto)
        XCTAssertNil(result.settings.dynamicRange)
        XCTAssertNil(result.settings.shadowTone)
        XCTAssertNil(result.settings.highlightTone)
        XCTAssertEqual(result.raw.ints[0x1444], 3)
        XCTAssertEqual(result.raw.ints[0x1403], 400)
    }

    func testUnknownClarityAndUncertainFilmModeStayUnspecified() throws {
        XCTAssertNil(try decode(jpeg([.signed(0x100F, 1500)])).settings.clarity)
        XCTAssertNil(try decode(jpeg([.signed(0x100F, 6000)])).settings.clarity)
        XCTAssertEqual(try decode(jpeg([.signed(0x100F, -3000)])).settings.clarity, -3)
        XCTAssertNil(try decode(jpeg([.short(0x1401, 0)])).settings.filmSimulation)
        XCTAssertNil(try decode(jpeg([.short(0x1401, 0), .short(0x1003, 0xFFFF)])).settings.filmSimulation)
        XCTAssertEqual(try decode(jpeg([.short(0x1401, 0), .short(0x1003, 0)])).settings.filmSimulation, .provia)
    }

    func testGrainSeparatesMissingInactiveAndContradictorySizes() throws {
        XCTAssertEqual(try decode(jpeg([.signed(0x1047, 0), .short(0x104C, 32)])).settings.grain, .off)
        XCTAssertEqual(try decode(jpeg([.signed(0x1047, 64)])).settings.grain,
                       GrainEffect(strength: .strong, size: nil))
        XCTAssertNil(try decode(jpeg([.signed(0x1047, 64), .short(0x104C, 0)])).settings.grain)
    }

    func testDuplicateWrongTypeAndWrongCountNeverBecomeSettings() throws {
        for tags in [[Tag.short(0x1001, 3), .short(0x1001, 5)],
                     [Tag(tag: 0x1001, type: 2, count: 2, value: Data([3, 0]))],
                     [Tag(tag: 0x1001, type: 3, count: 2, value: Data([3, 0, 5, 0]))]] {
            let result = try decode(jpeg(tags))
            XCTAssertNil(result.settings.sharpness)
            XCTAssertFalse(result.raw.issues.isEmpty)
        }
        let wrongPair = Tag(tag: 0x100A, type: 4, count: 2, value: Data([20, 0, 0, 0, 40, 0, 0, 0]))
        XCTAssertNil(try decode(jpeg([.short(0x1002, 0), wrongPair]), scale: .times20).settings.whiteBalance)
    }

    func testMakerNoteValueCannotEscapeDeclaredMakerNoteOrAPP1() throws {
        var data = jpeg([.short(0x1002, 0), .signed(0x100A, [20, 40])])
        let noteStart = 12 + 44
        let appendedOffset = data.count
        data.append(Tag.signed(0, [60, -40]).value)
        put32(UInt32(appendedOffset - noteStart), into: &data, at: noteStart + 14 + 12 + 8)
        let result = try decode(data, scale: .times20)
        XCTAssertNil(result.settings.whiteBalance)
        XCTAssertNil(result.raw.lists[0x100A])
        XCTAssertEqual(result.raw.observations.first(where: { $0.tag == 0x100A })?.status, "malformed")

        // Truncate only the MakerNote declaration; the bytes still exist inside APP1.
        var shortNote = jpeg([.short(0x1002, 0), .signed(0x100A, [20, 40])])
        put32(42, into: &shortNote, at: 12 + 26 + 2 + 4)
        XCTAssertNil(try decode(shortNote, scale: .times20).settings.whiteBalance)
    }

    func testIFDCannotEscapeAPP1EvenWhenJPEGHasMoreBytes() throws {
        var data = jpeg([])
        let outsideOffset = data.count
        data.append(Data(repeating: 0, count: 80))
        put32(UInt32(outsideOffset - 12), into: &data, at: 16)
        XCTAssertThrowsError(try decode(data))
    }

    func testDuplicateAPP1AndCyclicOrMalformedPointersAreRejected() throws {
        let data = jpeg([])
        var duplicate = Data(data.dropLast(2))
        duplicate.append(data.dropFirst(2))
        XCTAssertThrowsError(try ExifParser.exifBlock(inJPEG: duplicate))
        var cyclic = data
        put32(8, into: &cyclic, at: 12 + 8 + 2 + 8)
        XCTAssertThrowsError(try decode(cyclic))
        var wrongType = data
        put16(3, into: &wrongType, at: 12 + 8 + 2 + 2)
        XCTAssertThrowsError(try decode(wrongType))
    }

    func testDuplicateDirectoryPointersAndShortMakerHeaderAreRejected() throws {
        var bytes = Data(repeating: 0, count: 64)
        put16(2, into: &bytes, at: 8)
        for at in [10, 22] {
            put16(0x8769, into: &bytes, at: at)
            put16(4, into: &bytes, at: at + 2)
            put32(1, into: &bytes, at: at + 4)
            put32(38, into: &bytes, at: at + 8)
        }
        let duplicate = TIFFBlock(view: ByteView(bytes), base: 0, end: bytes.count, ifd0Offset: 8)
        XCTAssertThrowsError(try ExifParser.makerNoteRange(in: duplicate))

        var shortHeader = jpeg([])
        put32(8, into: &shortHeader, at: 12 + 26 + 2 + 4)
        XCTAssertThrowsError(try decode(shortHeader))

        var hugeDirectory = jpeg([])
        put16(4097, into: &hugeDirectory, at: 12 + 44 + 12)
        XCTAssertThrowsError(try decode(hugeDirectory))
    }

    func testEveryTruncationBoundaryIsHandledWithoutCrashing() {
        let data = jpeg([.short(0x1003, 0x501), .signed(0x100A, [60, -40])])
        for end in 0..<data.count {
            // An intact APP1 may still yield useful metadata without image scans/EOI.
            _ = try? decode(Data(data.prefix(end)))
        }
    }

    func testPreservedMetadataExcludesSerialsAndUnknownPayloads() throws {
        let result = try decode(jpeg([
            .text(0x0010, "PRIVATE-SERIAL"), .text(0x7FFE, "PRIVATE-OWNER"), .signed(0x1048, 12345)
        ]))
        let preserved = PhotoRecipeReader.metadataToPreserve(result.raw, warnings: result.warnings, wbShiftScale: .unknown)
        let encoded = String(decoding: try JSONEncoder().encode(preserved), as: UTF8.self)
        XCTAssertFalse(encoded.contains("PRIVATE"))
        XCTAssertFalse(encoded.contains("0x0010"))
        XCTAssertTrue(encoded.contains("12345"))
        XCTAssertTrue(encoded.contains("0x7FFE"))
        XCTAssertNil(result.settings.colorChromeEffect)
    }

    private func decode(_ data: Data, scale: PhotoRecipeReader.WBShiftScale = .unknown) throws
        -> (raw: FujiMakerNote.Raw, settings: RecipeSettings, warnings: [String]) {
        let block = try ExifParser.exifBlock(inJPEG: data)
        let raw = try FujiMakerNote.parse(block.view, range: ExifParser.makerNoteRange(in: block))
        var warnings: [String] = []
        let settings = PhotoRecipeReader.decodeSettings(raw, warnings: &warnings, wbShiftScale: scale)
        return (raw, settings, warnings)
    }

    private struct Tag {
        var tag: UInt16
        var type: UInt16
        var count: UInt32
        var value: Data
        static func short(_ tag: UInt16, _ value: Int) -> Tag {
            Tag(tag: tag, type: 3, count: 1, value: Data([UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: value >> 8)]))
        }
        static func signed(_ tag: UInt16, _ value: Int) -> Tag { signed(tag, [value]) }
        static func signed(_ tag: UInt16, _ values: [Int]) -> Tag {
            Tag(tag: tag, type: 9, count: UInt32(values.count), value: Data(values.flatMap { value in
                (0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }
            }))
        }
        static func bytes(_ tag: UInt16, _ value: [UInt8]) -> Tag {
            Tag(tag: tag, type: 1, count: UInt32(value.count), value: Data(value))
        }
        static func text(_ tag: UInt16, _ value: String) -> Tag {
            let bytes = Data(value.utf8) + Data([0])
            return Tag(tag: tag, type: 2, count: UInt32(bytes.count), value: bytes)
        }
    }

    private func jpeg(_ tags: [Tag], bigEndian: Bool = false, model: String? = nil) -> Data {
        var note = Data("FUJIFILM".utf8) + Data([12, 0, 0, 0])
        note.append(Data(repeating: 0, count: 2 + tags.count * 12 + 4))
        put16(UInt16(tags.count), into: &note, at: 12)
        for (index, tag) in tags.enumerated() {
            let at = 14 + index * 12
            put16(tag.tag, into: &note, at: at)
            put16(tag.type, into: &note, at: at + 2)
            put32(tag.count, into: &note, at: at + 4)
            if tag.value.count <= 4 {
                note.replaceSubrange((at + 8)..<(at + 8 + tag.value.count), with: tag.value)
            } else {
                put32(UInt32(note.count), into: &note, at: at + 8)
                note.append(tag.value)
            }
        }
        var tiff = Data(repeating: 0, count: 44)
        tiff[0] = bigEndian ? 0x4D : 0x49; tiff[1] = tiff[0]
        put16(42, into: &tiff, at: 2, bigEndian: bigEndian)
        put32(8, into: &tiff, at: 4, bigEndian: bigEndian)
        put16(1, into: &tiff, at: 8, bigEndian: bigEndian)
        put16(0x8769, into: &tiff, at: 10, bigEndian: bigEndian)
        put16(4, into: &tiff, at: 12, bigEndian: bigEndian)
        put32(1, into: &tiff, at: 14, bigEndian: bigEndian)
        put32(26, into: &tiff, at: 18, bigEndian: bigEndian)
        put16(1, into: &tiff, at: 26, bigEndian: bigEndian)
        put16(0x927C, into: &tiff, at: 28, bigEndian: bigEndian)
        put16(7, into: &tiff, at: 30, bigEndian: bigEndian)
        put32(UInt32(note.count), into: &tiff, at: 32, bigEndian: bigEndian)
        put32(44, into: &tiff, at: 36, bigEndian: bigEndian)
        tiff.append(note)
        if let model {
            // Append a replacement IFD0 so old malformed-boundary tests retain their offsets.
            let root = tiff.count
            tiff.append(Data(repeating: 0, count: 2 + 3 * 12 + 4))
            put32(UInt32(root), into: &tiff, at: 4, bigEndian: bigEndian)
            put16(3, into: &tiff, at: root, bigEndian: bigEndian)
            for (index, tag) in [Tag.text(0x010F, "FUJIFILM"), .text(0x0110, model)].enumerated() {
                let at = root + 2 + index * 12
                put16(tag.tag, into: &tiff, at: at, bigEndian: bigEndian)
                put16(tag.type, into: &tiff, at: at + 2, bigEndian: bigEndian)
                put32(tag.count, into: &tiff, at: at + 4, bigEndian: bigEndian)
                if tag.value.count <= 4 {
                    tiff.replaceSubrange((at + 8)..<(at + 8 + tag.value.count), with: tag.value)
                } else {
                    put32(UInt32(tiff.count), into: &tiff, at: at + 8, bigEndian: bigEndian)
                    tiff.append(tag.value)
                }
            }
            let exifPointer = root + 2 + 2 * 12
            put16(0x8769, into: &tiff, at: exifPointer, bigEndian: bigEndian)
            put16(4, into: &tiff, at: exifPointer + 2, bigEndian: bigEndian)
            put32(1, into: &tiff, at: exifPointer + 4, bigEndian: bigEndian)
            put32(26, into: &tiff, at: exifPointer + 8, bigEndian: bigEndian)
        }
        let payload = Data([0x45, 0x78, 0x69, 0x66, 0, 0]) + tiff
        let length = payload.count + 2
        return Data([0xFF, 0xD8, 0xFF, 0xE1, UInt8(length >> 8), UInt8(length & 255)]) + payload + Data([0xFF, 0xD9])
    }

    private func put16(_ value: UInt16, into data: inout Data, at offset: Int, bigEndian: Bool = false) {
        for index in 0..<2 { data[offset + index] = UInt8(truncatingIfNeeded: value >> (8 * (bigEndian ? 1 - index : index))) }
    }

    private func put32(_ value: UInt32, into data: inout Data, at offset: Int, bigEndian: Bool = false) {
        for index in 0..<4 { data[offset + index] = UInt8(truncatingIfNeeded: value >> (8 * (bigEndian ? 3 - index : index))) }
    }
}

/// The import's simulation code comes from a preview's MakerNote, read like any camera JPEG.
extension JPEGRecipeExtractionTests {
    func testAPreviewWithAMakerNoteNamesItsSimulation() {
        XCTAssertEqual(PreviewSimulation.read(jpeg([.short(0x1401, 0), .short(0x1003, 0)]), name: "DSCF0001.JPG"), .provia)
    }

    func testAPreviewWithoutOneNamesNothing() {
        XCTAssertNil(PreviewSimulation.read(Data([0xFF, 0xD8, 0xFF, 0xD9]), name: "DSCF0001.JPG"))
        XCTAssertNil(PreviewSimulation.read(Data(), name: "DSCF0001.JPG"))
    }
}
