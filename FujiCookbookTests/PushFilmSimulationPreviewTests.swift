import XCTest
@testable import FujiCookbook

/// The push screen says what a slot's film simulation will be before the user confirms. The
/// halves that need pinning are the ones where the push does not write the recipe's simulation.
/// For a recipe with none, `FujiPresetCodec.encode` writes PROVIA / Standard wherever the slot's
/// read answered D192 and nothing where it did not. For a recipe naming a simulation the body
/// lacks, it carries the slot's own D192 through instead of substituting one. The preview has to
/// say the same thing the push then does. "PROVIA / Standard" is spelled out because it is the
/// phrase the push-time warning uses; the two rows sit on one screen.
@MainActor
final class PushFilmSimulationPreviewTests: XCTestCase {

    private typealias P = FujiPTP.PresetProp

    /// A slot whose read answered D192 with a value the codec knows.
    private func occupied(_ simulation: FilmSimulation) -> CameraSlot {
        CameraSlot(index: 1, label: "C1", name: "Sunny 16", isOccupied: true,
                   settings: RecipeSettings(filmSimulation: simulation),
                   rawProperties: [P.filmSimulation.rawValue:
                                    FujiEncoding.packU16(FujiEncoding.filmSimToByte[simulation]!)],
                   unsupportedFields: [:])
    }

    /// A slot whose read answered D192 with a value the codec has no entry for: occupied, with no
    /// film simulation the app can name.
    private var unreadable: CameraSlot {
        CameraSlot(index: 1, label: "C1", name: nil, isOccupied: true, settings: RecipeSettings(),
                   rawProperties: [P.filmSimulation.rawValue: FujiEncoding.packU16(0xFFFF)],
                   unsupportedFields: [:])
    }

    /// A slot whose read had no D192 at all, which is what the reader calls empty.
    private var empty: CameraSlot {
        CameraSlot(index: 1, label: "C1", name: nil, isOccupied: false, settings: nil,
                   rawProperties: [:], unsupportedFields: [:])
    }

    /// The registry body the unsupported cases run on. It lacks Nostalgic Neg., which the X-Trans V
    /// bodies have; `testTheXT4LacksNostalgicNegWhichAnotherBodyHas` pins that pairing.
    private func xT4() throws -> CameraModel {
        try XCTUnwrap(CameraModelRegistry.shared.model(withID: "X-T4"))
    }

    /// The Demo Camera has every simulation the recipes here name, so the predictions that do not
    /// depend on the body use it.
    private func preview(_ slot: CameraSlot, _ settings: RecipeSettings,
                         model: CameraModel = CameraModelRegistry.shared.demoModel) -> String {
        PushView.filmSimulationPreview(slot: slot, settings: settings, model: model)
    }

    // MARK: A recipe with a film simulation the body has writes it, whatever the slot holds

    func testASimulationReplacesTheOneTheSlotHolds() {
        XCTAssertEqual(preview(occupied(.velvia), RecipeSettings(filmSimulation: .classicChrome)),
                       "\(FilmSimulation.velvia.displayName) → \(FilmSimulation.classicChrome.displayName)")
    }

    func testASimulationFillsAnEmptySlot() {
        XCTAssertEqual(preview(empty, RecipeSettings(filmSimulation: .classicChrome)),
                       "empty → \(FilmSimulation.classicChrome.displayName)")
    }

    func testASimulationReplacesOneTheAppCouldNotRead() {
        XCTAssertEqual(preview(unreadable, RecipeSettings(filmSimulation: .classicChrome)),
                       "unreadable → \(FilmSimulation.classicChrome.displayName)")
    }

    // MARK: A recipe with none

    /// The slot does not keep the simulation it answered with: the codec writes PROVIA over it.
    func testNoSimulationWritesProviaOverAnOccupiedSlot() {
        XCTAssertEqual(preview(occupied(.velvia), RecipeSettings()),
                       "\(FilmSimulation.velvia.displayName) → PROVIA / Standard")
    }

    /// `emitDefault` writes a default only where the read answered for the property, and the
    /// reader calls a slot empty exactly when it did not, so nothing is written here.
    func testNoSimulationLeavesAnEmptySlotUnwritten() {
        XCTAssertEqual(preview(empty, RecipeSettings()), "empty → not written")
    }

    /// A value the codec could not decode is still an answer, so the default is written over it.
    func testNoSimulationWritesProviaOverAnUnreadableSlot() {
        XCTAssertEqual(preview(unreadable, RecipeSettings()), "unreadable → PROVIA / Standard")
    }

    // MARK: A recipe with a film simulation the body lacks

    /// The pair the cases below rely on: a registry body without a simulation another registry
    /// body has, so the recipe is one the app lets a user author and then push to this body.
    func testTheXT4LacksNostalgicNegWhichAnotherBodyHas() throws {
        XCTAssertFalse(try xT4().supports(filmSimulation: .nostalgicNeg))
        XCTAssertTrue(CameraModelRegistry.shared.models.contains { $0.supports(filmSimulation: .nostalgicNeg) })
    }

    /// The codec substitutes nothing for a simulation the body has not got: it carries the slot's
    /// own D192 through, so the slot keeps the simulation it answered with.
    func testAnUnsupportedSimulationLeavesAnOccupiedSlotUnchanged() throws {
        let body = try xT4()
        XCTAssertEqual(preview(occupied(.classicChrome), RecipeSettings(filmSimulation: .nostalgicNeg), model: body),
                       "\(FilmSimulation.classicChrome.displayName) → unchanged")
    }

    /// Carrying D192 through needs a D192 to carry, and a slot the reader calls empty had none.
    func testAnUnsupportedSimulationLeavesAnEmptySlotUnwritten() throws {
        let body = try xT4()
        XCTAssertEqual(preview(empty, RecipeSettings(filmSimulation: .nostalgicNeg), model: body),
                       "empty → not written")
    }

    /// Bytes the app could not name are carried through all the same, and stay unnamed.
    func testAnUnsupportedSimulationLeavesAnUnreadableSlotUnchanged() throws {
        let body = try xT4()
        XCTAssertEqual(preview(unreadable, RecipeSettings(filmSimulation: .nostalgicNeg), model: body),
                       "unreadable → unchanged")
    }

    // MARK: Against the codec

    /// The preview promises a D192 write exactly when `encode` makes one, pinned against the
    /// codec's own output so the two cannot drift apart: a recipe with a simulation the body has,
    /// one with none, and one whose simulation the body lacks, on each slot state.
    func testThePreviewPromisesAWriteExactlyWhenTheCodecMakesOne() throws {
        let demo = CameraModelRegistry.shared.demoModel
        let cases: [(model: CameraModel, settings: RecipeSettings)] = [
            (demo, RecipeSettings(filmSimulation: .classicChrome)),
            (demo, RecipeSettings()),
            (try xT4(), RecipeSettings(filmSimulation: .nostalgicNeg)),
        ]
        for (model, settings) in cases {
            for slot in [occupied(.velvia), unreadable, empty] {
                let written = FujiPresetCodec.encode(settings, model: model, slot: .holds(slot.rawProperties))
                    .contains { $0.code == P.filmSimulation.rawValue }
                let promised = !preview(slot, settings, model: model).hasSuffix("→ not written")
                XCTAssertEqual(promised, written,
                               "\(model.id) \(settings.filmSimulation?.rawValue ?? "none") occupied=\(slot.isOccupied)")
            }
        }
    }
}
