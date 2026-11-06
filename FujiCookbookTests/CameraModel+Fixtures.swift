import Foundation
@testable import FujiCookbook

extension CameraModel {
    /// A body with no Grain Effect control and no numeric ranges — the shape of the X-Trans I and
    /// II entries — for rules that must not assume every body has grain, or a range to clamp to.
    static func grainlessFixture(id: String = "FIXTURE-NOGRAIN") -> CameraModel {
        CameraModel(id: id, displayName: "FUJIFILM \(id)", sensorGeneration: .xTransI, processor: .exrProcessor,
                    supportsSlotProtocol: false, slotCount: 7, documentedSlotCount: nil,
                    supportedFields: [.filmSimulation, .whiteBalance, .dynamicRange, .highlightTone,
                                      .shadowTone, .color, .sharpness, .highISONR],
                    supportedFilmSimulations: [.provia, .velvia, .astia, .monochrome, .sepia],
                    supportedWhiteBalanceModes: [.auto, .daylight, .shade, .fluorescent1, .fluorescent2,
                                                 .fluorescent3, .incandescent, .kelvin, .underwater],
                    ranges: [:], hasMagentaGreenAxis: false, hasGrainSizeControl: false,
                    supportsSlotNaming: false, slotNameMaxLength: 0,
                    slotNameAllowedCharacters: CameraSlotName.allowedCharacters,
                    writeSupport: .blocked(reason: "A test fixture, never on a cable."),
                    verification: .inferred, supportsRawConversion: false, hasFilmSimulationDial: false)
    }
}
