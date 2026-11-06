import XCTest
import SwiftData
@testable import FujiCookbook

/// A develop must reach the compatibility report, not only the log.
///
/// The Kitchen used to be the one camera workflow that left nothing structured behind: the connect
/// wrote `deviceInfo` and `slots`, a push wrote `pushes[]`, and a cook wrote prose into
/// `AppLog(.kitchen)` and nothing else. That was backwards — RAW conversion is enabled on every
/// X-Trans IV and V body and has been driven on exactly one of them, so it is the workflow with the
/// least evidence and the most inference behind it.
///
/// Camera facts in these tests are from zgrimz/fujifilm-ptp-reference: `docs/05-raw-conversion.md#output`.
@MainActor
final class CookRecordTests: XCTestCase {

    override func setUp() {
        super.setUp()
        CameraReportStore.deleteLatest()
    }

    private func connected() async -> CameraServices {
        var faults = MockCameraFaults()
        faults.isInstant = true
        let manager = CameraServices()
        await manager.connector.connectDemo(using: MockCameraTransport(faults: faults))
        return manager
    }

    private var recipe: RecipeSettings {
        var settings = RecipeSettings.neutral
        settings.filmSimulation = .classicChrome
        return settings
    }

    func testACleanCookLandsInTheReport() async {
        let manager = await connected()
        let result = await manager.conversion.cook(raf: RAFFixture.raf(),
                                        filename: "DSCF0001.RAF", settings: recipe)
        XCTAssertTrue(result.success, "the mock renders a JPEG")

        let cook = manager.reports.report?.develops?.first
        XCTAssertEqual(manager.reports.report?.develops?.count, 1,
                       "every cook, not only the anomalies — a clean develop on a body nobody owns is the evidence")
        XCTAssertEqual(cook?.filmSimulation, "Classic Chrome")
        XCTAssertEqual(cook?.modelID, CameraModelRegistry.demoModelID)
        XCTAssertNotNil(cook?.profileLength, "the D185 length is the finding on an unfamiliar body")
        XCTAssertNotNil(cook?.layoutBase, "and the base it resolved to")
        XCTAssertEqual(cook?.succeeded, true)
        XCTAssertNil(cook?.failureReason)
        XCTAssertNotNil(cook?.outputBytes)
    }

    /// The report must never learn the user's file name, on any path. `ConversionResult` carries it
    /// three ways over — `sourceFilename`, an `errorMessage` that interpolates it, and `diagnostics`
    /// — which is exactly why `CookEvidence` exists as a separate, narrower type.
    func testTheRafFilenameNeverReachesTheReport() async {
        let manager = await connected()
        _ = await manager.conversion.cook(raf: RAFFixture.raf(),
                               filename: "a-very-distinctive-name.RAF", settings: recipe)

        let json = String(decoding: manager.reports.report?.json ?? Data(), as: UTF8.self)
        XCTAssertFalse(json.contains("a-very-distinctive-name"),
                       "no field for a photo or a file name, and it must not grow one")
        XCTAssertFalse(manager.reports.report?.textRendering.contains("a-very-distinctive-name") ?? true)
    }

    /// `cookMatrix` develops directly rather than through `cook`, so it records for itself. Without
    /// this the Test Kitchen — where a tester exercises an unfamiliar body hardest — would be the
    /// one Kitchen path still writing nothing into the report.
    func testATestKitchenGridRecordsEveryCell() async {
        let manager = await connected()
        var mono = RecipeSettings.neutral
        mono.filmSimulation = .acros
        let recipes: [(settings: RecipeSettings, displayName: String, filmSimulation: String?)] = [
            (recipe, "Sunny 16", "Classic Chrome"),
            (mono, "ACROS Street", "ACROS"),
        ]
        _ = await manager.conversion.cookMatrix(rafs: [.inMemory(RAFFixture.raf(), filename: "DSCF0001.RAF")],
                                     recipes: recipes)

        XCTAssertEqual(manager.reports.report?.develops?.count, 2, "one record per cell")
        XCTAssertEqual(manager.reports.report?.develops?.map(\.filmSimulation),
                       ["Classic Chrome", "ACROS"])
        XCTAssertEqual(manager.reports.report?.develops?.allSatisfy { $0.fullResolution == false }, true,
                       "grid cells are downscaled previews, and the record says so")
    }

    func testABatchOfCooksAccumulates() async {
        let manager = await connected()
        for _ in 0..<3 {
            _ = await manager.conversion.cook(raf: RAFFixture.raf(),
                                   filename: "DSCF0001.RAF", settings: recipe)
        }
        XCTAssertEqual(manager.reports.report?.develops?.count, 3)
        XCTAssertTrue(manager.reports.report!.textRendering.contains("Develops    3"))
    }

    /// A develop is not only a record in memory; it has to survive the reconnect between running it
    /// and sharing it, because a connect begins a new report and carries the earlier records
    /// forward. Mirrors the harvest's own test in `ProfileHarvestTests`.
    func testADevelopSurvivesTheReconnectBetweenRunningItAndSharingIt() async {
        var faults = MockCameraFaults()
        faults.isInstant = true
        let transport = MockCameraTransport(faults: faults)
        let manager = CameraServices()
        await manager.connector.connectDemo(using: transport)
        let result = await manager.conversion.cook(raf: RAFFixture.raf(),
                                        filename: "DSCF0001.RAF", settings: recipe)
        XCTAssertTrue(result.success)
        XCTAssertEqual(CameraReportStore.loadLatest()?.develops?.count, 1,
                       "in the file the tester sends, not only in memory")

        await manager.connector.disconnect()
        await manager.connector.connectDemo(using: transport)
        XCTAssertEqual(manager.reports.report?.develops?.count, 1,
                       "the same body picks its develop back up across the unplug")
        XCTAssertEqual(manager.reports.report?.develops?.first?.filmSimulation, "Classic Chrome",
                       "and it is the same record, not an empty stand-in")
    }

    func testGuidedCookJoinsExactRecipeRunAndSavedImage() async throws {
        let manager = await connected()
        let supplied = GuidedKitchenRecipe(id: "colour", name: "CT Colour", settings: recipe)
        let run = GuidedKitchenRun(caseID: "develop", recipes: [supplied], fullResolution: true)
        let results = await manager.conversion.cookBatch([
            CookItem(raf: .inMemory(RAFFixture.raf(), filename: "private-filename.RAF"),
                     settings: supplied.settings)
        ], recordContext: run.recordContexts.first)
        let result = try XCTUnwrap(results.first)
        let record = try XCTUnwrap(manager.reports.report?.develops?.last)
        XCTAssertEqual(record.resultID, result.id)
        XCTAssertEqual(record.runID, run.id)
        XCTAssertEqual(record.caseID, "develop")
        XCTAssertEqual(record.recipeID, supplied.id)
        XCTAssertEqual(record.recipeSettings, supplied.settings)

        let container = try ModelContainer(for: CookedPhoto.self, CookedVersion.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let batchID = try await CookStore.persistChecked(CookStore.comparisons(from: results, recipe: supplied.resolved),
                                                        fullResolution: true, into: container.mainContext)
        let reopened = ModelContext(container)
        let photos = try reopened.fetch(FetchDescriptor<CookedPhoto>())
        XCTAssertEqual(photos.first?.batchID, batchID)
        XCTAssertEqual(photos.first?.sortedVersions.first?.uuid, result.id,
                       "the report's result ID addresses the saved image after reopening")

        let completion = GuidedKitchenCompletion(run: run,
            cells: [.init(result: result, recipeID: supplied.id, fileIndex: 0)],
            savedBatchID: batchID, saveFailed: false)
        let data = try JSONEncoder().encode(completion)
        XCTAssertEqual(try JSONDecoder().decode(GuidedKitchenCompletion.self, from: data), completion)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("private-filename"))
        XCTAssertFalse(String(decoding: manager.reports.report?.json ?? Data(), as: UTF8.self).contains("private-filename"))
    }

    func testFailedGuidedComparisonKeepsEachPlannedCellAndDoesNotClaimAPhoto() async throws {
        var faults = MockCameraFaults()
        faults.isInstant = true
        faults.readResponseCodes = [FujiPTP.Prop.rawConvProfile: 0x2002]
        let manager = CameraServices()
        await manager.connector.connectDemo(using: MockCameraTransport(faults: faults))
        var mono = recipe
        mono.filmSimulation = .acros
        let supplied = [GuidedKitchenRecipe(id: "colour", name: "CT Colour", settings: recipe),
                        GuidedKitchenRecipe(id: "mono", name: "CT Mono", settings: mono)]
        let run = GuidedKitchenRun(caseID: "testKitchen", recipes: supplied, fullResolution: false)
        let comparisons = await manager.conversion.cookMatrix(
            rafs: [.inMemory(RAFFixture.raf(), filename: "private-wrong-body.RAF")],
            recipes: supplied.map { ($0.settings, $0.name, $0.settings.filmSimulation?.displayName) },
            recordContexts: run.recordContexts)
        let versions = try XCTUnwrap(comparisons.first?.versions)
        XCTAssertEqual(versions.count, 2)
        XCTAssertTrue(versions.allSatisfy { !$0.result.success && $0.result.recoveryFileURL == nil })
        let records = try XCTUnwrap(manager.reports.report?.develops)
        XCTAssertEqual(records.map(\.resultID), versions.map { Optional($0.result.id) })
        XCTAssertEqual(records.map(\.recipeID), ["colour", "mono"])
        XCTAssertTrue(records.allSatisfy { $0.failureReason == "raf_from_different_body" && $0.runID == run.id })
        let completion = GuidedKitchenCompletion(run: run,
            cells: versions.enumerated().map { .init(result: $0.element.result, recipeID: supplied[$0.offset].id, fileIndex: 0) },
            savedBatchID: nil, saveFailed: false)
        XCTAssertFalse(completion.hasSuccessfulOutput)
        XCTAssertTrue(completion.hasFailures)
    }

    func testSuppliedDevelopWorksWithNoProgrammedCameraRecipes() async throws {
        var faults = MockCameraFaults.emptyCamera
        faults.isInstant = true
        let manager = CameraServices()
        await manager.connector.connectDemo(using: MockCameraTransport(faults: faults))
        XCTAssertTrue(manager.occupiedSlots.isEmpty)
        let model = try XCTUnwrap(manager.session.model)
        let testRecipe = try XCTUnwrap(GuidedTestRecipes.recipe(id: "colour", for: model))
        let supplied = GuidedKitchenRecipe(id: testRecipe.id, name: testRecipe.name, settings: testRecipe.settings)
        let run = GuidedKitchenRun(caseID: "develop", recipes: [supplied], fullResolution: true)
        let result = await manager.conversion.cook(raf: RAFFixture.raf(), filename: "own-camera.RAF",
                                        settings: supplied.settings,
                                        recordContext: run.recordContexts.first)
        XCTAssertTrue(result.success)
        XCTAssertTrue(manager.occupiedSlots.isEmpty, "developing with the supplied recipe never fills a camera slot")
    }
}
