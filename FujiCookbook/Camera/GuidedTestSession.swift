import Foundation

/// The guided **Camera Test**: what it has asked, what it has been told, and where it got to.
///
/// The Camera Test exists to bring back facts about bodies this app has never been run against, and
/// the two most valuable facts it asks for are ones no automated check can supply. A read-back
/// proves bytes round-tripped; it cannot prove they *mean* what the codec says — only a person
/// reading their camera's own IQ menu can catch a value decoded into the wrong setting. And nothing
/// during a push can see a write that verified and then quietly wasn't there after the camera was
/// switched off and on.
///
/// **The session and `GuidedTestFlow` are pure.** Every transition, verdict and comparison is a
/// function over values, so the whole protocol can be exercised in tests without a camera, a view,
/// or a main actor. `GuidedTestStore` and `GuidedRecoveryStore` at the end of this file are its
/// only file I/O, and `GuidedTestRunner` is the only part that talks to the camera services.
///
/// The session is saved to its own file after every change, and *projected* into the compatibility
/// report at step boundaries — not the other way round. The report is rebuilt from scratch on every
/// connect, including the silent recovery after a cable jostle and the power cycle the write pass
/// asks for by name, so a session that lived only in the report would be destroyed by the very
/// procedure it exists to document.
struct GuidedTestSession: Codable, Equatable {

    /// Bumped if a stored session's shape ever changes incompatibly. A session is far more
    /// disposable than a report — the worst case is one tester starting over — so there is no
    /// migration. Nothing reads it on load.
    static let currentVersion = 2

    var version = GuidedTestSession.currentVersion
    var id: String
    /// 1 = the read pass, 2 = the write pass. A continuous session (`plan` set) is 1 and covers both.
    var wave: Int
    var startedAt: Date
    var updatedAt: Date
    var step: GuidedTestStep
    var completedSteps: [GuidedTestStep] = []
    var outcome: Outcome = .inProgress

    // MARK: The body this session is about

    /// `usb` or `demo`. Decides which reconnect the flow offers after a power cycle.
    var transport: String?
    var cameraProductName: String?
    var identifiedModelID: String?
    var identification: String?
    var verification: String?
    var firmwareVersion: String?
    /// What `describesSameBody` matches on, so a session can refuse to resume against a different
    /// camera. Absent on a body that refuses `GetDeviceInfo`, which then matches by name alone.
    var serialHash: String?
    /// The capability seal the tester was shown, recorded verbatim — the identity question asks
    /// them to confirm what is on screen, so what was on screen is part of the answer.
    var badgeShown: String?
    /// Whether the connect this session adopted granted writes (`CameraFacts.canWrite`). The menu
    /// comparison is done unplugged, and the step after it leads to the write pass or past it: a
    /// listed body's registry entry can answer, but an `.untested` entry says nothing and an
    /// unlisted body has none, so the grant the connect decided is kept here. A routing fact only:
    /// `GuidedTestRunner.mutationBlockReason` asks the live camera before anything is written.
    /// Optional, so a session stored before it existed decodes and routes by its entry.
    var writeGranted: Bool?

    /// The model the saved body is encoded and judged by, with the cable in or out: its registry
    /// entry, or for an unlisted body the provisional model its connect built
    /// (`CameraModelRegistry.provisionalModel`), rebuilt from the product name so the placeholder
    /// id is stored nowhere. Nil for a body nothing names.
    var cameraModel: CameraModel? {
        if let model = identifiedModelID.flatMap(CameraModelRegistry.shared.model(withID:)) { return model }
        guard identification == "unlisted", let productName = cameraProductName else { return nil }
        return CameraModelRegistry.shared.provisionalModel(productName: productName)
    }

    // MARK: What the tester said

    var identity: IdentityCheck?
    var slotComparisons: [SlotComparison] = []
    var propertyReport: ProbeOutcome?
    /// Read-stage evidence survives later writes and the report reset on reconnect.
    var initialSlots: CameraCompatibilityReport.SlotSummary?
    var propertySweep: CameraCompatibilityReport.PropertySweep?
    var grainProbe: ProbeOutcome?
    var develop: DevelopCheck?
    /// The profile harvest, offered on the develop step of a body the app doesn't develop on. Its
    /// own field rather than a state of `develop`, because `develop` staying `.notWritable` is
    /// still true — nothing was developed — and the harvest is the separate fact that the camera
    /// was asked to describe a RAF. Optional, so a stored session from before it existed decodes.
    var profileHarvest: ProbeOutcome?
    var noCamera: NoCameraAnswers?
    var freeText: String?
    var writePass: WritePass?
    /// Absent in legacy two-part sessions. New sessions carry their selected coverage with them.
    var plan: TestPlan?
    var recoveryBaselineID: String?
    var selectedWriteSlot: Int?
    /// The tester checked this bank's X-M5 CUSTOM MODE SETTING. The app cannot detect it.
    /// Optional for sessions created before the bank-specific confirmation was introduced.
    var stillBankConfirmations: [StillBankConfirmation]?
    var grainConsentAt: Date?
    var kitchenRuns: [GuidedKitchenRun]?
    var kitchenCompletions: [GuidedKitchenCompletion]?
    var kitchenObservations: [String: Answer]?
    var reportSnapshot: DiagnosticsReportSnapshot?
    var shareEvents: [ShareEvent]?

    var isContinuous: Bool { plan != nil }

    enum OptionalCheck: String, Codable, CaseIterable, Identifiable {
        case secondSlotComparison, colour, mono, kelvin, extraRestarts
        case testKitchen, expandedKitchen, cameraReference, dynamicRange
        var id: String { rawValue }
    }

    struct TestPlan: Codable, Equatable {
        var version = 1
        var optionalChecks: Set<OptionalCheck> = []
        var setupModelID: String?
    }

    struct ShareEvent: Codable, Equatable {
        var at: Date
        var outcome: ReportShareOutcome
    }

    struct StillBankConfirmation: Codable, Equatable {
        var slot: Int
        var confirmedAt: Date
    }

    enum VerificationState: String, Codable, Equatable {
        case passed, issueFound, notTested, couldNotVerify
    }

    // MARK: Nested

    enum Outcome: String, Codable, Equatable {
        case inProgress, completed, sentEarly, abandoned
    }

    struct IdentityCheck: Codable, Equatable {
        var confirmed: Bool?
        var correction: String?
    }

    /// One slot, as the app displayed it, against what the camera's own menu shows.
    struct SlotComparison: Codable, Equatable, Identifiable {
        var slot: Int
        var name: String?
        var filmSimulation: String?
        /// Every row the app had on screen, snapshotted. Not a reference into `camera.slotReader.slots`: a
        /// push or a reconnect rewrites those, and this has to keep meaning what it meant when the
        /// person was looking at it.
        var rows: [Row] = []
        var fieldsAppCouldNotRead: [String] = []
        var unreadableCameraShows: [String: String]?
        /// The bank's ISO and image format as the tester read them off the camera. Neither is among
        /// the 23 bank properties, and both decide whether a Dynamic Range, D-Range Priority or
        /// Clarity refusal is a gate or a finding. Nil means not recorded, never base ISO or JPEG.
        var isoShown: String?
        var imageFormatShown: ImageFormatAnswer?
        /// Set when the tester said the whole slot matched. `verdict` derives the rest.
        var confirmedMatching = false
        var checkedAt: Date?

        var id: Int { slot }

        /// "C3". Derived rather than stored so the screen can render a comparison with the camera
        /// unplugged, which is the state the compare step actually runs in.
        var label: String { "C\(slot)" }

        /// The same fallback chain as `CameraSlot.displayName`, over the snapshot.
        var displayName: String { name ?? filmSimulation ?? "Occupied" }

        struct Row: Codable, Equatable, Identifiable {
            /// `RecipeField.rawValue`, so the row survives a display-name change.
            var field: String
            var label: String
            var appShowed: String
            var differs = false
            var cameraShows: String?
            var priorityControlled: Bool?

            var id: String { field }
            var isPriorityControlled: Bool {
                guard let recipeField = RecipeField(rawValue: field),
                      RecipeApplicability.fieldsUnderPriority.contains(recipeField) else { return false }
                return priorityControlled ?? appShowed.hasSuffix(RecipeSettingsFormatter.priorityNote)
            }
        }

        /// `matches` / `differs` / `unverified` / `notChecked`, derived and never typed — a tester can't be asked
        /// to summarise their own answers, and a summary that disagreed with the rows would be the
        /// one thing in this record nobody could check.
        var verdict: String {
            if rows.contains(where: { $0.differs }) { return "differs" }
            if !fieldsAppCouldNotRead.isEmpty { return "unverified" }
            return confirmedMatching ? "matches" : "notChecked"
        }
    }

    /// What became of one of the diagnostics the flow runs on the tester's behalf.
    struct ProbeOutcome: Codable, Equatable {
        enum State: String, Codable, Equatable {
            /// It ran and produced something.
            case ran
            /// The tester skipped it. Retained for older sessions and optional checks.
            case skipped
            /// This body can't do what the step needs (be written to, develop, take a RAF), so it
            /// is not offered.
            case notWritable
            /// Another camera operation was in flight. Retryable, and not a fact about the body.
            case refused
            case failed
            case notRun
        }

        var state: State
        var slot: Int?
        var count: Int?
        var readOnly: Bool?
        var detail: String?
        var capturedAt: Date? = CameraCompatibilityReport.timestamp()
        var evidenceID: String? = UUID().uuidString
    }

    struct DevelopCheck: Codable, Equatable {
        var state: ProbeOutcome.State
        var jpegMatchesRecipe: Answer?
        var detail: String?
    }

    /// The three-way answer every "did it look right?" question takes. "Didn't check" is a first
    /// class answer: a tester who guesses is worse than one who says they didn't look.
    enum Answer: String, Codable, Equatable {
        case yes, no, notChecked
    }

    /// What the tester did to the write slot before the push.
    ///
    /// Dynamic Range and D-Range Priority are refused below an ISO threshold and Clarity on a HEIF
    /// bank, and none of that state is among the 23 readable properties, so the flow asks for the
    /// slot to be prepared and records whether it was. Either answer is valid: after
    /// `leftUnchanged`, the refusals that follow are the expected gate rather than findings.
    enum SlotPreparation: String, Codable, Equatable {
        case setForTest, leftUnchanged
    }

    /// The bank's image format as the tester read it off the camera. Not among the 23 bank
    /// properties, and the one bank state that locks Clarity.
    enum ImageFormatAnswer: String, Codable, Equatable {
        case jpeg, heif, notChecked
    }

    /// AUTO UPDATE CUSTOM SETTING as the tester read it. Camera-wide, and the variable the protocol
    /// record names as unrecorded behind every persistence measurement so far.
    enum AutoUpdateAnswer: String, Codable, Equatable {
        case enable, disable, notInMenu, notChecked
    }

    /// The failed-detect branch. Everything here is typed by the tester because there is no session
    /// to ask — `connectionFailures[]` has the machine half, and on its own it can't tell a
    /// charge-only cable from the wrong USB mode.
    struct NoCameraAnswers: Codable, Equatable {
        var modelAsPrinted: String?
        var firmwareFromMenu: String?
        var usbModeWording: String?
        var cable: String?
        var cameraPromptSeen: Answer?
        var filesPromptSeen: Answer?
        var appSaid: String?
    }

    // MARK: Wave 2

    struct WritePass: Codable, Equatable {
        var consentAt: Date?
        var backup: BackupStep?
        /// Nil on a body with no Film Simulation dial — there is nothing to confirm.
        var dialConfirmed: Bool?
        var trials: [PushTrial] = []
        /// Index into `trials` of the one being worked on.
        var currentTrial: Int?
        var restores: [RestoreOutcome] = []
        /// Asked once, at the recheck step; what every trial's `persistence` is read against.
        var autoUpdateCustomSetting: AutoUpdateAnswer?

        var trial: PushTrial? {
            guard let currentTrial, trials.indices.contains(currentTrial) else { return nil }
            return trials[currentTrial]
        }

        /// The trial only once a slot has actually been chosen.
        ///
        /// A trial is created at the recipe step with `slot: 0`, and the hub lets a tester tap
        /// straight into the push step without passing through the chooser, where the trial alone
        /// would offer "Write to C0".
        var trialWithASlot: PushTrial? {
            guard let trial, trial.slot > 0 else { return nil }
            return trial
        }

        /// The trial the full restart check belongs to: the first whose write the camera accepted,
        /// or, while none has been pushed yet, the first still waiting to be, so the summary lists
        /// the check as planned. An attempt the camera refused is neither: it wrote nothing, so
        /// there is nothing to check after a restart, and it doesn't use the check up.
        var restartCheckTrial: Int? {
            trials.firstIndex(where: \.hasAcceptedWrite) ?? trials.firstIndex(where: { $0.outcome == nil })
        }

        /// The trials after the one that carries the restart check: the additional recipes whose
        /// restart checks are the optional extra.
        var extraTrials: ArraySlice<PushTrial> {
            guard let first = restartCheckTrial else { return [] }
            return trials[(first + 1)...]
        }
    }

    struct BackupStep: Codable, Equatable {
        var savedAt: Date?
        var activity: String?
        var skipped = false
    }

    /// One test recipe pushed to one slot, and everything asked about it afterwards.
    struct PushTrial: Codable, Equatable {
        /// Optional so a report/session written before stable trial IDs still decodes.
        var id: String?
        /// `GuidedTestRecipes.TestRecipe.id`, or `custom`.
        var recipe: String
        var recipeName: String
        var slot: Int
        var pushedAt: Date?
        var outcome: SlotOutcome?
        /// What the camera accepted from the push, hex by property code — the fields whose outcome
        /// was `written` or `unverified`. A refused or mismatched property is left out: the push
        /// record carries that finding, and the power-cycle check that reads this map is asking a
        /// different question, whether what landed is still there.
        ///
        /// Copied out of the push record at the time rather than read back later: the power cycle
        /// this is compared against recreates the report, and `adoptGuidedTests` is best-effort
        /// where this is not.
        var wrote: [String: String] = [:]
        var nameApplied: String?
        var persistence: Persistence?
        var menuComparison: SlotComparison?
        var photoMatchesRecipe: Answer?
        var photoNote: String?
        var recipeVersion: Int?
        var recipeSettings: RecipeSettings?
        var refusalReason: String?
        /// The connection that accepted this trial, retained across view recreation and relaunch.
        var connectionStartedAt: Date?
        var connectionID: String?
        /// How the tester prepared the slot before the push, and when they said so. Absent in
        /// sessions from before the question existed.
        var preparation: SlotPreparation?
        var preparationConfirmedAt: Date?

        var hasAcceptedRecipeFields: Bool {
            wrote.contains { key, value in
                guard let code = PTPHex.code(from: key), Data(hexString: value) != nil else { return false }
                return FujiPTP.PresetProp(rawValue: code)?.recipeField != nil
            }
        }

        var hasAcceptedWrite: Bool { hasAcceptedRecipeFields || nameApplied != nil }
    }

    struct Persistence: Codable, Equatable {
        var persisted: Bool
        var checkedAt: Date?
        var differences: [Difference] = []
        var nameHolds: Bool?
        var evidenceState: VerificationState?
        var settingsState: VerificationState?
        var nameState: VerificationState?
        var freshReadSucceeded: Bool?
        var restartConfirmed: Bool?
        var connectionChanged: Bool?
        var readAt: Date?
        var expected: [String: String]?
        var readback: [String: String]?
        var nameReadBack: String?
        var connectionStartedAt: Date?
        var connectionID: String?

        struct Difference: Codable, Equatable {
            var field: String
            var code: String
            var wrote: String
            var holds: String?
        }
    }

    struct RestoreOutcome: Codable, Equatable {
        var slot: Int
        var outcome: RestoreDisposition?
        var verification: RestoreVerification?
    }

    // MARK: Lifecycle

    static func begin(wave: Int, step: GuidedTestStep) -> GuidedTestSession {
        let now = CameraCompatibilityReport.timestamp()
        return GuidedTestSession(id: UUID().uuidString, wave: wave, startedAt: now,
                                 updatedAt: now, step: step)
    }

    static func beginContinuous(step: GuidedTestStep = .intro) -> GuidedTestSession {
        var session = begin(wave: 1, step: step)
        session.plan = TestPlan()
        return session
    }

    /// Move to `step`, marking the one being left as done.
    mutating func advance(to next: GuidedTestStep) {
        if !completedSteps.contains(step) { completedSteps.append(step) }
        step = next
        updatedAt = CameraCompatibilityReport.timestamp()
    }

    mutating func touch() { updatedAt = CameraCompatibilityReport.timestamp() }

    func hasConfirmedStillBank(_ slot: Int) -> Bool {
        stillBankConfirmations?.contains(where: { $0.slot == slot }) == true
    }

    mutating func setStillBankConfirmation(_ slot: Int, confirmed: Bool) {
        guard slot > 0 else { return }
        var confirmations = stillBankConfirmations ?? []
        confirmations.removeAll { $0.slot == slot }
        if confirmed {
            confirmations.append(.init(slot: slot, confirmedAt: CameraCompatibilityReport.timestamp()))
        }
        stillBankConfirmations = confirmations.isEmpty ? nil : confirmations.sorted { $0.slot < $1.slot }
        touch()
    }

    /// Record what the connected camera is, so a later resume can refuse a different body.
    ///
    /// Nothing is recorded when nothing is attached. This runs at every step boundary, and the
    /// flow asks the tester to unplug twice by name — so copying an empty `CameraFacts` over the
    /// top would erase the body the session is about at exactly the moment they did as they were
    /// told, and a resume would then have nothing to match against.
    mutating func adopt(camera: CameraFacts) {
        guard camera.isConnected else { touch(); return }
        // A resumed continuous test remains about its original body. A newly connected camera
        // must not rewrite the identity that operation-time checks are supposed to protect.
        if isContinuous, cameraProductName != nil,
           !GuidedTestFlow.describesSameBody(stored: self, facts: camera) { touch(); return }
        transport = camera.transport
        cameraProductName = camera.productName
        identifiedModelID = camera.modelID
        identification = camera.identification
        verification = camera.verification
        firmwareVersion = camera.firmwareVersion
        serialHash = camera.serialHash
        badgeShown = camera.badge
        writeGranted = camera.canWrite
        touch()
    }

    var isLive: Bool { outcome == .inProgress }
}

// MARK: - Steps

/// Every screen the guided test can be on, in main-line order per wave.
///
/// `String`-backed and stable: these are written into a stored session *and* into the shared report,
/// so renaming a case renames it in a tester's half-finished run.
enum GuidedTestStep: String, Codable, Hashable, CaseIterable {
    // Wave 1 — the read pass
    case intro, connect, noCamera, confirmIdentity, readSlots, compareSlots
    case propertyReport, grainProbe, develop
    // Wave 2 — the write pass
    case writeIntro, backup, dialCheck, chooseRecipe, chooseSlot, push
    case powerCycle, recheckSlot, photoCheck, moreTrials, restoreOffer
    // Both
    case review, send

    /// The hub's label for this step.
    var title: String {
        switch self {
        case .intro: return "What this does"
        case .connect: return "Connect your camera"
        case .noCamera: return "What happened"
        case .confirmIdentity: return "Confirm your camera"
        case .readSlots: return "Read your slots"
        case .compareSlots: return "Check two slots against the camera"
        case .propertyReport: return "Read camera settings"
        case .grainProbe: return "Check grain settings"
        case .develop: return "Develop a RAW file"
        case .writeIntro: return "Before writing"
        case .backup: return "Back up your slots"
        case .dialCheck: return "Set the dial to C"
        case .chooseRecipe: return "Choose a test recipe"
        case .chooseSlot: return "Choose a slot"
        case .push: return "Write it to the camera"
        case .powerCycle: return "Switch the camera off and on"
        case .recheckSlot: return "Check the slot again"
        case .photoCheck: return "Take one photo"
        case .moreTrials: return "Another recipe?"
        case .restoreOffer: return "Put your slots back"
        case .review: return "Review"
        case .send: return "Send the report"
        }
    }

    /// The hub's label for this step in a particular session. The continuous test compares one
    /// slot unless the tester selected a second; the legacy two-wave flow asked for two.
    func title(in session: GuidedTestSession) -> String {
        guard self == .compareSlots, session.isContinuous,
              session.plan?.optionalChecks.contains(.secondSlotComparison) != true else { return title }
        return "Check one slot against the camera"
    }

    /// Whether the tester has been asked to break the connection on purpose at this step.
    ///
    /// In `USB RAW Conv./Backup Restore` the camera hands its screen to the host, so reading the
    /// camera's own IQ menu and taking a photo can only be done with the cable out — and the power
    /// cycle is the point of its step. Choosing a slot asks for the menu as well: the write slot's
    /// ISO and image format are set there before the push. `GuidedTestView` arms
    /// `CameraConnector.expectRemoval` from this, which waits longer for the camera and stops
    /// counting the drop against the "your cable is bad" throttle.
    ///
    /// Coarser than the gate card's own rule on purpose: `GuidedCompareStep` suppresses its warning
    /// only once there is something to compare, whereas this is flat per step. The difference is
    /// harmless — this only widens timings and quiets a log line, so being armed a little early
    /// costs nothing.
    var expectsUnplug: Bool {
        switch self {
        case .compareSlots, .chooseSlot, .powerCycle, .recheckSlot, .photoCheck: return true
        default: return false
        }
    }
}

// MARK: - The camera, as a value

/// Everything the flow's decisions depend on, snapshotted off the camera services.
///
/// A value rather than `CameraServices` itself so every transition below is testable without a
/// camera, a main actor, or a connect.
struct CameraFacts: Equatable {
    var isConnected = false
    /// The app can name this body and work with it: a registry match, or an unlisted body its slot
    /// read granted. A body nothing names, or an unlisted one its read refused, has no slots to
    /// read or compare and gets the read-only sweep instead (`ConnectedCamera.isUnsupported`).
    var isRecognized = false
    var hasSlotProtocol = false
    var canWrite = false
    var canConvert = false
    /// Whether a RAF may be sent to this body to read its conversion profile — a trusted
    /// identification and an upload-capable transport, and nothing about `canConvert`.
    var canHarvestProfile = false
    var hasOccupiedSlots = false
    var hasFilmSimulationDial = false
    var transport: String?
    var productName: String?
    var modelID: String?
    var identification: String?
    var verification: String?
    var firmwareVersion: String?
    var serialHash: String?
    var badge: String?

    var isDemo: Bool { transport == "demo" }
}

// MARK: - Flow

/// The guided test's rules, as pure functions.
enum GuidedTestFlow {

    /// Recipe choices belong to the test's saved body, including while the tester has unplugged
    /// to check the menu or take a photo. These are presentation choices, never write permission;
    /// the runner still requires the same live camera and all mutation prerequisites.
    static func writeRecipes(session: GuidedTestSession) -> [GuidedTestRecipes.TestRecipe] {
        guard let model = session.cameraModel else { return [] }
        let all = GuidedTestRecipes.canonical(for: model)
        let first = all.first(where: { $0.id == "priority" }) ?? all.first
        let selected = session.plan?.optionalChecks ?? []
        let ids = [first?.id, selected.contains(.colour) ? "colour" : nil,
                   selected.contains(.mono) ? "mono" : nil, selected.contains(.kelvin) ? "kelvin" : nil].compactMap { $0 }
        return ids.reduce(into: []) { result, id in
            if !result.contains(where: { $0.id == id }), let recipe = all.first(where: { $0.id == id }) {
                result.append(recipe)
            }
        }
    }

    static func remainingWriteRecipes(session: GuidedTestSession) -> [GuidedTestRecipes.TestRecipe] {
        let attempted = Set((session.writePass?.trials ?? []).filter { $0.pushedAt != nil }.map(\.recipe))
        let selected = Set((session.plan?.optionalChecks ?? []).map(\.rawValue))
        return writeRecipes(session: session).filter { selected.contains($0.id) && !attempted.contains($0.id) }
    }

    static func suggestedWriteRecipe(session: GuidedTestSession) -> GuidedTestRecipes.TestRecipe? {
        let attempted = Set((session.writePass?.trials ?? []).filter { $0.pushedAt != nil }.map(\.recipe))
        if !attempted.isEmpty, let next = remainingWriteRecipes(session: session).first { return next }
        let recipes = writeRecipes(session: session)
        return recipes.first { !attempted.contains($0.id) }
    }

    static func mainLine(session: GuidedTestSession) -> [GuidedTestStep] {
        guard session.isContinuous else { return mainLine(wave: session.wave) }
        return [.intro, .connect, .confirmIdentity, .readSlots, .compareSlots,
                .writeIntro, .backup, .dialCheck, .grainProbe, .chooseRecipe, .chooseSlot,
                .push, .powerCycle, .recheckSlot, .photoCheck, .moreTrials, .develop,
                .restoreOffer, .review]
    }

    static func next(after step: GuidedTestStep, session: GuidedTestSession,
                     facts: CameraFacts) -> GuidedTestStep {
        guard session.isContinuous else { return next(after: step, facts: facts) }
        // Menu comparisons deliberately happen unplugged. Stored, trusted capabilities decide
        // which screen comes next; live identity/readiness still exclusively govern mutations.
        let trusted = session.identification == "exact" || session.identification?.hasPrefix("alias(") == true
        let storedModel = trusted ? session.identifiedModelID.flatMap(CameraModelRegistry.shared.model(withID:)) : nil
        // What the connect decided outranks the entry: an `.untested` entry or an unlisted body is
        // granted by its slot read, which no entry records. The entry answers for a session stored
        // before the grant was.
        let canWrite = facts.isConnected ? facts.canWrite : session.writeGranted ?? (storedModel?.allowsWrite == true)
        let hasDial = facts.isConnected ? facts.hasFilmSimulationDial : storedModel?.hasFilmSimulationDial == true
        switch step {
        case .noCamera: return .review
        case .connect: return facts.isRecognized ? .confirmIdentity : .propertyReport
        case .confirmIdentity:
            return session.identity?.confirmed == true ? .readSlots : .review
        case .readSlots:
            guard session.propertyReport?.state == .ran else { return .review }
            return facts.hasOccupiedSlots ? .compareSlots : canWrite ? .writeIntro : .develop
        case .compareSlots:
            guard readCheckpointBlockReason(session: session, hasOccupiedSlots: true) == nil else { return .review }
            // A dial that can't be set to C pauses the writing branch, not the whole test: the
            // non-mutating Develop check still runs, and `mutationBlockReason` keeps writes closed.
            if hasDial, session.writePass?.dialConfirmed == false { return .develop }
            return canWrite ? .writeIntro : .develop
        case .propertyReport: return .review
        case .backup: return hasDial && session.writePass?.dialConfirmed != true ? .dialCheck : .grainProbe
        case .dialCheck: return session.writePass?.dialConfirmed == true ? .grainProbe : .develop
        case .grainProbe:
            switch session.grainProbe?.state {
            case .ran: return canWrite ? .chooseRecipe : .develop
            case .failed: return .restoreOffer
            case .notWritable: return canWrite ? .grainProbe : .develop
            default: return .grainProbe
            }
        case .push:
            guard let pass = session.writePass, pass.trial?.hasAcceptedWrite == true else { return .moreTrials }
            // A later recipe's immediate read-back does not establish persistence. The first
            // accepted trial always gets the full check; later ones do so only when explicitly
            // selected. An attempt the camera refused wrote nothing and doesn't use the check up.
            let isFirst = pass.currentTrial == pass.restartCheckTrial
            return isFirst || session.plan?.optionalChecks.contains(.extraRestarts) == true
                ? .powerCycle : .moreTrials
        case .moreTrials: return remainingWriteRecipes(session: session).isEmpty ? .develop : .chooseRecipe
        case .develop: return .restoreOffer
        case .review, .send: return .send
        default:
            let line = mainLine(session: session)
            guard let index = line.firstIndex(of: step), index + 1 < line.count else { return .review }
            return line[index + 1]
        }
    }

    /// Older continuous sessions may have skipped grain and already reached a writing screen.
    /// Bring them to the prerequisite (or recovery after a write) instead of a permanent refusal.
    static func writePrerequisiteStep(for step: GuidedTestStep, session: GuidedTestSession) -> GuidedTestStep {
        guard session.isLive, session.isContinuous, session.grainProbe?.state != .ran,
              [.chooseRecipe, .chooseSlot, .push].contains(step) else { return step }
        if session.grainProbe?.state == .failed || session.writePass?.trials.contains(where: { $0.pushedAt != nil || $0.hasAcceptedWrite }) == true {
            return .restoreOffer
        }
        return .grainProbe
    }

    /// Read evidence is checked again immediately before a mutation, not merely when the
    /// navigation offers writing. Unsupported values and a real mismatch are not a passing read.
    static func readCheckpointBlockReason(session: GuidedTestSession,
                                          hasOccupiedSlots: Bool) -> String? {
        guard session.identity?.confirmed == true else { return "Confirm the camera's identity before writing." }
        guard session.propertyReport?.state == .ran,
              !hasOccupiedSlots || (session.propertyReport?.count ?? 0) > 0 else {
            return "Complete the camera reading successfully before writing."
        }
        if session.slotComparisons.contains(where: { $0.verdict == "differs" }) {
            return "A menu comparison differs. Share the reading results before writing."
        }
        if session.slotComparisons.contains(where: { !$0.fieldsAppCouldNotRead.isEmpty }) {
            return "Some slot settings could not be understood. Share the reading results before writing."
        }
        if hasOccupiedSlots && !session.slotComparisons.contains(where: {
            $0.checkedAt != nil && $0.verdict == "matches"
        }) {
            return "Compare one existing slot with the camera's menu before writing."
        }
        return nil
    }

    /// The steps a wave walks, in order. Steps that don't apply to a body are still listed — the hub
    /// shows them as skipped, which is more honest than a checklist that silently changes length.
    static func mainLine(wave: Int) -> [GuidedTestStep] {
        wave == 1
            ? [.intro, .connect, .confirmIdentity, .readSlots, .compareSlots,
               .propertyReport, .grainProbe, .develop, .review, .send]
            : [.writeIntro, .backup, .dialCheck, .chooseRecipe, .chooseSlot, .push,
               .powerCycle, .recheckSlot, .photoCheck, .moreTrials, .restoreOffer, .review, .send]
    }

    /// Where `step` sits in its wave's main line, one-based, and how many steps that wave has.
    ///
    /// Nil for the steps that are branches rather than stages — `.noCamera` is reached from a
    /// failed connect and has no place in a count of ten.
    static func position(of step: GuidedTestStep, wave: Int) -> (index: Int, total: Int)? {
        let line = mainLine(wave: wave)
        guard let offset = line.firstIndex(of: step) else { return nil }
        return (offset + 1, line.count)
    }

    /// "Part One · 4 of 10", or just "Part One" off the main line. The flow's only statement of
    /// where the tester is: the checklist that would otherwise say so is behind a Back chevron.
    static func positionLabel(of step: GuidedTestStep, wave: Int) -> String {
        let part = wave == 1 ? "Part One" : "Part Two"
        guard let position = position(of: step, wave: wave) else { return part }
        return "\(part) · \(position.index) of \(position.total)"
    }

    /// A continuous session's stages, in order. Coarser than its steps on purpose: which steps a
    /// session reaches depends on the camera, and a count that changed mid-test would read as lost
    /// progress.
    static let continuousStages: [(name: String, steps: [GuidedTestStep])] = [
        ("Prepare", [.intro, .connect, .noCamera]),
        ("Read", [.confirmIdentity, .readSlots, .compareSlots, .propertyReport]),
        ("Write", [.writeIntro, .backup, .dialCheck, .grainProbe, .chooseRecipe, .chooseSlot, .push]),
        ("Check", [.powerCycle, .recheckSlot, .photoCheck, .moreTrials]),
        ("Develop", [.develop]),
        ("Finish", [.restoreOffer, .review, .send])]

    /// "Read · 2 of 6" for a continuous session, or the wave label for a stored two-part one. Shared
    /// by the step screens' bar and the Camera tab's resume row, which must name the same place.
    static func positionLabel(of step: GuidedTestStep, in session: GuidedTestSession) -> String {
        guard session.isContinuous,
              let index = continuousStages.firstIndex(where: { $0.steps.contains(step) }) else {
            return positionLabel(of: step, wave: session.wave)
        }
        return "\(continuousStages[index].name) · \(index + 1) of \(continuousStages.count)"
    }

    /// Where the flow goes after `step`, given what this camera can do.
    ///
    /// Skipping is a decision made here and recorded, never a step quietly not shown: a body that
    /// can't be written to produces a *report* saying the grain probe was not applicable, which is
    /// itself a fact about that body.
    static func next(after step: GuidedTestStep, facts: CameraFacts) -> GuidedTestStep {
        switch step {
        case .intro:
            return .connect
        case .connect:
            // An unrecognized body, or one without the slot protocol, has no slots to read or
            // compare, and its read-only sweep is the whole of what it can contribute.
            guard facts.isRecognized, facts.hasSlotProtocol else { return .propertyReport }
            return .confirmIdentity
        case .noCamera:
            return .review
        case .confirmIdentity:
            return facts.hasSlotProtocol ? .readSlots : .propertyReport
        case .readSlots:
            return facts.hasOccupiedSlots ? .compareSlots : .propertyReport
        case .compareSlots:
            return .propertyReport
        case .propertyReport:
            return .grainProbe
        case .grainProbe:
            return .develop
        case .develop:
            return .review

        case .writeIntro:
            return .backup
        case .backup:
            return facts.hasFilmSimulationDial ? .dialCheck : .chooseRecipe
        case .dialCheck:
            return .chooseRecipe
        case .chooseRecipe:
            return .chooseSlot
        case .chooseSlot:
            return .push
        case .push:
            return .powerCycle
        case .powerCycle:
            return .recheckSlot
        case .recheckSlot:
            return .photoCheck
        case .photoCheck:
            return .moreTrials
        case .moreTrials:
            return .restoreOffer
        case .restoreOffer:
            return .review

        case .review:
            return .send
        case .send:
            return .send
        }
    }

    /// Where a connect attempt lands. A failure is not a dead end — it is the branch that asks what
    /// the app cannot answer for itself.
    static func stepAfterConnect(status: CameraSession.Status, facts: CameraFacts) -> GuidedTestStep {
        if case .failed = status { return .noCamera }
        guard facts.isConnected else { return .connect }
        return next(after: .connect, facts: facts)
    }

    /// Whether the grain probe can be offered at all on this body. `probeWriteValues` refuses a body
    /// the app doesn't write to, so asking for consent first would be asking about something that
    /// cannot happen.
    static func grainProbeState(facts: CameraFacts) -> GuidedTestSession.ProbeOutcome? {
        guard !facts.canWrite else { return nil }
        return GuidedTestSession.ProbeOutcome(
            state: .notWritable,
            detail: "Writing isn't enabled for this camera, so the grain check is unavailable.")
    }

    /// Likewise for the develop step: nothing to run on a body whose RAW conversion is off.
    static func developState(facts: CameraFacts) -> GuidedTestSession.DevelopCheck? {
        guard !facts.canConvert else { return nil }
        return GuidedTestSession.DevelopCheck(
            state: .notWritable,
            detail: "RAW conversion isn't enabled for this body.")
    }

    /// Whether the develop step should offer the profile harvest instead of the Kitchen.
    ///
    /// Only where it matters: a body the app doesn't develop on, and that can be sent a RAF. On a
    /// body that already converts, a develop *is* a harvest with more evidence attached, so there
    /// is nothing to offer. On a guessed body there is no trusted target to send a file to.
    static func offersProfileHarvest(facts: CameraFacts) -> Bool {
        !facts.canConvert && facts.canHarvestProfile
    }

    /// One check the intro screen promises the Camera Test will make on a body.
    enum CoverageCheck: Equatable {
        case reading, saving, developing, rawSettings
    }

    struct Coverage: Equatable {
        var checks: [CoverageCheck]
        /// The sentence under the checklist, where one is needed.
        var note: String?
    }

    /// What this body can actually be checked for. A body the registry blocks never reaches the
    /// writing steps, a body with no record either way reaches them only if its slots answer at
    /// connect, a body the Kitchen is off for sends one RAF instead of developing it, and an
    /// unlisted body is developed on nowhere, since the Kitchen and the profile harvest both key on
    /// a registry match (`CameraSession.canConvert`, `RawConversionService.canHarvestProfile`), so
    /// the promise on the first screen must not be wider than the checklist that follows.
    static func coverage(for model: CameraModel?, unlisted: Bool) -> Coverage {
        guard let model else {
            return Coverage(checks: [.reading, .saving, .developing],
                            note: "Some checks only run where your camera supports them.")
        }
        let develop: [CoverageCheck] = unlisted ? [] : [model.supportsRawConversion ? .developing : .rawSettings]
        switch model.writeSupport {
        case .blocked:
            return Coverage(checks: [.reading] + develop,
                            note: "This app doesn't write recipes to this camera, so the writing checks are skipped.")
        case .untested:
            return Coverage(checks: [.reading, .saving] + develop,
                            note: "Whether this camera takes recipes is decided when it is connected and its slots are read; the writing checks run if it does.")
        case .readWrite:
            return Coverage(checks: [.reading, .saving] + develop, note: nil)
        }
    }

    // MARK: Resuming

    enum ResumeDecision: Equatable {
        /// Nothing stored, or what is stored is finished.
        case fresh
        /// A live session for this body (or for no body yet).
        case offerResume(GuidedTestStep)
        /// A live session, but the camera plugged in now is a different one.
        case differentBody(stored: String?)
    }

    static func resumeDecision(stored: GuidedTestSession?, facts: CameraFacts) -> ResumeDecision {
        guard let stored, stored.isLive else { return .fresh }
        // Nothing connected, or the session never got as far as identifying a body: offer it back.
        // Judging "same camera" needs both sides, and refusing to resume because nothing is plugged
        // in would strand a tester who is mid-way through a power cycle.
        guard facts.isConnected, stored.cameraProductName != nil else {
            return .offerResume(stored.step)
        }
        if describesSameBody(stored: stored, facts: facts) { return .offerResume(stored.step) }
        return .differentBody(stored: stored.cameraProductName)
    }

    /// The same asymmetry `CameraCompatibilityReport.describesSameBody` errs on: a false negative
    /// costs a tester one restart, a false positive files one camera's answers under another.
    static func describesSameBody(stored: GuidedTestSession, facts: CameraFacts) -> Bool {
        guard stored.cameraProductName == facts.productName else { return false }
        if stored.isContinuous, stored.serialHash != nil || facts.serialHash != nil {
            return SerialHash.same(stored.serialHash, facts.serialHash)
        }
        if let mine = stored.serialHash, let theirs = facts.serialHash { return SerialHash.same(mine, theirs) }
        return true
    }

    // MARK: Observations

    /// The rows to put in front of a tester for one slot, and the fields the app admits it could
    /// not read. Pure so the comparison screen's content is testable without SwiftUI.
    static func comparison(for slot: CameraSlot, model: CameraModel?) -> GuidedTestSession.SlotComparison {
        var rows = (slot.settings.map { RecipeSettingsFormatter.rows(for: $0, model: model) } ?? [])
            .map { row in GuidedTestSession.SlotComparison.Row(field: row.field.rawValue,
                                                        label: row.field.displayName,
                                                        appShowed: row.value,
                                                        priorityControlled: slot.settings.map { settings in
                                                            RecipeApplicability.fieldsUnderPriority.contains(row.field)
                                                                && RecipeApplicability.priorityOverrides(settings, on: model)
                                                        }) }
        // A Custom white balance has no row above, because `RecipeSettings` has nowhere to put a
        // measurement made on one camera — and the tester's camera menu will show it. Say what the
        // slot holds where the white balance row would be, so the comparison can match.
        if slot.settings?.whiteBalance == nil,
           let label = slot.cameraOnlyFields[RecipeField.whiteBalance.displayName] {
            let row = GuidedTestSession.SlotComparison.Row(field: RecipeField.whiteBalance.rawValue,
                                                           label: RecipeField.whiteBalance.displayName,
                                                           appShowed: "\(label) (set on the camera)")
            let at = rows.firstIndex { $0.field == RecipeField.highlightTone.rawValue } ?? rows.endIndex
            rows.insert(row, at: at)
        }
        return GuidedTestSession.SlotComparison(
            slot: slot.index,
            name: slot.resolvedName,
            filmSimulation: slot.settings?.filmSimulation?.displayName,
            rows: rows,
            fieldsAppCouldNotRead: slot.unsupportedFields.keys.sorted())
    }

    /// A comparison for every occupied slot, built *while the camera is still attached*.
    ///
    /// The compare step asks the tester to read their camera's own IQ menu, and a camera in
    /// `USB RAW Conv./Backup Restore` has handed its display to the host — so the menu is reachable
    /// only with the cable out, and `disconnect()` empties `slots`. Everything that screen shows has
    /// to be snapshotted before that happens, or the tester unplugs to do the one step nothing else
    /// can do and finds an empty list.
    ///
    /// Existing entries are left exactly as they are: someone who compares C1, plugs back in and
    /// comes back must not have their answers rebuilt from a fresh read.
    static func seedComparisons(into existing: [GuidedTestSession.SlotComparison],
                                slots: [CameraSlot],
                                model: CameraModel?) -> [GuidedTestSession.SlotComparison] {
        var result = existing
        for slot in slots where slot.isOccupied {
            guard !result.contains(where: { $0.slot == slot.index }) else { continue }
            result.append(comparison(for: slot, model: model))
        }
        return result.sorted { $0.slot < $1.slot }
    }

    /// Whether a develop happened since the flow handed off to the Kitchen.
    ///
    /// By timestamp, never by count: `develops` is capped at twenty and rebuilt on every connect, so
    /// a count taken before and after can fall as easily as rise.
    static func developed(since: Date, in report: CameraCompatibilityReport?) -> Bool {
        (report?.develops ?? []).contains { $0.at >= since }
    }

    /// Which slot the write pass should land on unless the tester moves it.
    ///
    /// An empty slot first: none of the tester's work is then at stake. But "empty" here is the
    /// app's word, and it means "`0xD192` did not answer" — which on a GFX100S never happens, since
    /// every bank answers all 23 bank properties whether or not anyone has ever programmed it. There,
    /// every untouched bank reads as occupied, and a first-slot default lands on C1, the bank most
    /// likely to hold the owner's own recipe.
    ///
    /// So: an unnamed bank next. On a body like that, "nobody has used this" presents as a slot
    /// with no name rather than as an empty one — and the highest-numbered such bank is the least
    /// likely to be someone's first, most-used preset. `isOccupied` is part of the test because
    /// `resolvedName` is nil for an empty slot too, and without it this is just a slower route back
    /// to the same answer.
    static func defaultWriteSlot(in slots: [CameraSlot]) -> Int? {
        if let empty = slots.first(where: { !$0.isOccupied }) { return empty.index }
        if let unnamed = slots.filter({ $0.isOccupied && $0.resolvedName == nil })
            .max(by: { $0.index < $1.index }) {
            return unnamed.index
        }
        return slots.max(by: { $0.index < $1.index })?.index
    }

    static func suggestedWriteSlot(in slots: [CameraSlot], session: GuidedTestSession) -> Int? {
        if let selected = session.selectedWriteSlot, slots.contains(where: { $0.index == selected }) { return selected }
        // Reusing a confirmed X-M5 bank avoids another menu visit, but does not sacrifice an
        // available empty bank just because the grain check used an occupied one.
        if session.identifiedModelID == "X-M5", let grainSlot = session.grainProbe?.slot,
           session.hasConfirmedStillBank(grainSlot),
           let slot = slots.first(where: { $0.index == grainSlot }),
           !slot.isOccupied || !slots.contains(where: { !$0.isOccupied }) {
            return grainSlot
        }
        return defaultWriteSlot(in: slots)
    }

    static func connectionChanged(for trial: GuidedTestSession.PushTrial, currentID: String?,
                                  currentStartedAt: Date?, observedDisconnect: Bool) -> Bool? {
        if observedDisconnect { return true }
        if let before = trial.connectionID, let currentID { return before != currentID }
        if let before = trial.connectionStartedAt, let currentStartedAt,
           before != currentStartedAt { return true }
        // Matching second-resolution timestamps cannot rule out a reconnect. Legacy records
        // without connection IDs remain unknown unless an actual transition was observed.
        return nil
    }

    /// Did the pushed recipe survive the power cycle?
    ///
    /// Compares what the push intended for each property against what the slot holds now, using the
    /// push path's own rule — which compares D195 grain by decoded *meaning*, because the X-T50
    /// normalizes a write of Off into a different read value. A byte comparison here would report
    /// every Off-grain recipe as lost.
    static func persistence(trial: GuidedTestSession.PushTrial, slot: CameraSlot?,
                            nameApplied: String?, freshReadSucceeded: Bool = true,
                            restartConfirmed: Bool = true,
                            connectionChanged: Bool? = nil, readAt: Date? = nil,
                            connectionStartedAt: Date? = nil, connectionID: String? = nil) -> GuidedTestSession.Persistence {
        typealias State = GuidedTestSession.VerificationState
        var result = GuidedTestSession.Persistence(
            persisted: false, checkedAt: CameraCompatibilityReport.timestamp(),
            evidenceState: .notTested, settingsState: .notTested, nameState: .notTested,
            freshReadSucceeded: freshReadSucceeded, restartConfirmed: restartConfirmed,
            connectionChanged: connectionChanged)
        // Keep the successful readings too. A zero-difference verdict alone cannot be audited
        // after a reconnect replaces the slot reader's current slots.
        result.expected = trial.wrote
        result.connectionStartedAt = connectionStartedAt
        result.connectionID = connectionID
        if freshReadSucceeded, let slot {
            result.readAt = readAt ?? result.checkedAt
            result.readback = Dictionary(uniqueKeysWithValues: slot.rawProperties.map {
                (PTPHex.code($0.key), PTPHex.bytes($0.value))
            })
            result.nameReadBack = slot.resolvedName
        }
        guard freshReadSucceeded else {
            result.evidenceState = .couldNotVerify
            result.settingsState = .couldNotVerify
            if nameApplied != nil { result.nameState = .couldNotVerify }
            return result
        }
        guard restartConfirmed else { return result }
        var differences: [GuidedTestSession.Persistence.Difference] = []
        guard let slot else {
            result.evidenceState = .couldNotVerify
            result.settingsState = .couldNotVerify
            if nameApplied != nil { result.nameState = .couldNotVerify }
            return result
        }
        var acceptedRecipeFields = 0
        var unreadableEvidence = false
        for (codeText, wroteHex) in trial.wrote.sorted(by: { $0.key < $1.key }) {
            guard let code = PTPHex.code(from: codeText),
                  let wrote = Data(hexString: wroteHex) else { unreadableEvidence = true; continue }
            // Housekeeping properties are passed through rather than authored — a body refusing one
            // says nothing about whether the recipe survived.
            guard let prop = FujiPTP.PresetProp(rawValue: code), prop.recipeField != nil else { continue }
            acceptedRecipeFields += 1
            let holds = slot.rawProperties[code]
            if holds == nil { unreadableEvidence = true }
            guard !SlotWriteVerification.readBackMatches(code, wrote: wrote, read: holds) else { continue }
            differences.append(.init(field: prop.debugName, code: codeText, wrote: wroteHex,
                                     holds: holds.map(PTPHex.bytes)))
        }
        var nameHolds: Bool?
        if let nameApplied { nameHolds = slot.resolvedName == nameApplied }
        let settingsState: State = differences.contains(where: { $0.holds != nil }) ? .issueFound
            : unreadableEvidence ? .couldNotVerify
            : acceptedRecipeFields == 0 ? .notTested : .passed
        result.differences = differences
        result.nameHolds = nameHolds
        result.settingsState = settingsState
        result.nameState = nameHolds.map { $0 ? .passed : .issueFound } ?? .notTested
        result.evidenceState = nameHolds == false || settingsState == .issueFound ? .issueFound
            : settingsState
        result.persisted = settingsState == .passed && nameHolds != false
        return result
    }
}

// MARK: - Projection into the report

extension CameraCompatibilityReport.GuidedTestRecord {

    /// Flatten a session into the shape the shared report carries.
    ///
    /// Strings and plain values only: this lands in a document a stranger reads months later, so
    /// nothing here may depend on an app type's `Codable` shape staying still.
    init(session: GuidedTestSession) {
        self.init(sessionID: session.id, wave: session.wave, startedAt: session.startedAt)
        updatedAt = session.updatedAt
        transport = session.transport
        outcome = session.outcome.rawValue
        outcomeStep = session.outcome == .completed ? nil : session.step.rawValue
        stepsCompleted = session.completedSteps.isEmpty ? nil : session.completedSteps.map(\.rawValue)
        plan = session.plan
        recoveryBaselineID = session.recoveryBaselineID
        selectedWriteSlot = session.selectedWriteSlot
        stillBankConfirmations = session.stillBankConfirmations
        kitchenRuns = session.kitchenRuns
        kitchenCompletions = session.kitchenCompletions
        kitchenObservations = session.kitchenObservations
        shareEvents = session.shareEvents
        initialSlots = session.initialSlots
        propertySweep = session.propertySweep

        if let identity = session.identity {
            self.identity = .init(appShowedProductName: session.cameraProductName,
                                  appShowedModelID: session.identifiedModelID,
                                  identification: session.identification,
                                  badge: session.badgeShown,
                                  confirmed: identity.confirmed,
                                  correction: identity.correction)
        }
        let comparisons = session.slotComparisons.filter { $0.checkedAt != nil }
        slotComparisons = comparisons.isEmpty ? nil : comparisons.map(Self.record(comparison:))
        propertyReport = session.propertyReport.map(Self.record(probe:))
        grainProbe = session.grainProbe.map(Self.record(probe:))
        profileHarvest = session.profileHarvest.map(Self.record(probe:))
        develop = session.develop.map {
            .init(state: $0.state.rawValue, jpegMatchesRecipe: $0.jpegMatchesRecipe?.rawValue,
                  detail: $0.detail)
        }
        noCamera = session.noCamera.map {
            .init(modelAsPrinted: $0.modelAsPrinted, firmwareFromMenu: $0.firmwareFromMenu,
                  usbModeWording: $0.usbModeWording, cable: $0.cable,
                  cameraPromptSeen: $0.cameraPromptSeen?.rawValue,
                  filesPromptSeen: $0.filesPromptSeen?.rawValue, appSaid: $0.appSaid)
        }
        // Capped, because this is free text in a document the tester reads before sending and a
        // pasted novel would bury everything under it.
        freeText = session.freeText
            .map { String($0.prefix(Self.maxFreeTextCharacters)) }
            .flatMap { $0.isEmpty ? nil : $0 }
        writePass = session.writePass.map(Self.record(writePass:))
    }

    static let maxFreeTextCharacters = 2000

    private static func record(comparison: GuidedTestSession.SlotComparison)
        -> CameraCompatibilityReport.SlotComparisonRecord {
        var record = CameraCompatibilityReport.SlotComparisonRecord(slot: comparison.slot)
        record.name = comparison.name
        record.filmSimulation = comparison.filmSimulation
        record.verdict = comparison.verdict
        record.checkedAt = comparison.checkedAt
        record.rows = comparison.rows.isEmpty ? nil : comparison.rows.map {
            .init(field: $0.label, appShowed: $0.appShowed, differs: $0.differs,
                  cameraShows: $0.cameraShows, priorityControlled: $0.isPriorityControlled,
                  displayedValue: $0.isPriorityControlled ? "Controlled by D-Range Priority" : $0.appShowed)
        }
        record.fieldsAppCouldNotRead = comparison.fieldsAppCouldNotRead.isEmpty
            ? nil : comparison.fieldsAppCouldNotRead
        record.unreadableCameraShows = comparison.unreadableCameraShows
        record.isoShown = comparison.isoShown
        record.imageFormatShown = comparison.imageFormatShown?.rawValue
        return record
    }

    private static func record(probe: GuidedTestSession.ProbeOutcome)
        -> CameraCompatibilityReport.ProbeRecord {
        .init(state: probe.state.rawValue, slot: probe.slot, count: probe.count,
              readOnly: probe.readOnly, detail: probe.detail,
              capturedAt: probe.capturedAt, evidenceID: probe.evidenceID)
    }

    private static func record(writePass pass: GuidedTestSession.WritePass)
        -> CameraCompatibilityReport.WritePassRecord {
        var record = CameraCompatibilityReport.WritePassRecord()
        record.consentAt = pass.consentAt
        record.backup = pass.backup.map {
            .init(savedAt: $0.savedAt, activity: $0.activity, skipped: $0.skipped ? true : nil)
        }
        record.dialConfirmed = pass.dialConfirmed
        record.autoUpdateCustomSetting = pass.autoUpdateCustomSetting?.rawValue
        record.trials = pass.trials.isEmpty ? nil : pass.trials.map { trial in
            var out = CameraCompatibilityReport.PushTrialRecord(recipe: trial.recipe, slot: trial.slot)
            out.recipeName = trial.recipeName
            out.pushedAt = trial.pushedAt
            out.outcome = trial.outcome
            out.id = trial.id
            out.recipeVersion = trial.recipeVersion
            out.recipeSettings = trial.recipeSettings
            out.refusalReason = trial.refusalReason
            out.connectionStartedAt = trial.connectionStartedAt
            out.connectionID = trial.connectionID
            out.preparation = trial.preparation?.rawValue
            out.preparationConfirmedAt = trial.preparationConfirmedAt
            out.persistence = trial.persistence.map { p in
                var result = CameraCompatibilityReport.PersistenceRecord(persisted: p.persisted, checkedAt: p.checkedAt,
                      differences: p.differences.isEmpty ? nil : p.differences.map {
                          .init(field: $0.field, code: $0.code, wrote: $0.wrote, holds: $0.holds)
                      },
                      nameHolds: p.nameHolds)
                result.evidenceState = p.evidenceState?.rawValue
                result.settingsState = p.settingsState?.rawValue
                result.nameState = p.nameState?.rawValue
                result.freshReadSucceeded = p.freshReadSucceeded
                result.restartConfirmed = p.restartConfirmed
                result.connectionChanged = p.connectionChanged
                result.readAt = p.readAt
                result.expected = p.expected
                result.readback = p.readback
                result.nameReadBack = p.nameReadBack
                result.connectionStartedAt = p.connectionStartedAt
                result.connectionID = p.connectionID
                return result
            }
            out.menuComparison = trial.menuComparison.map(Self.record(comparison:))
            out.photoMatchesRecipe = trial.photoMatchesRecipe?.rawValue
            out.photoNote = trial.photoNote
            return out
        }
        record.restores = pass.restores.isEmpty ? nil : pass.restores.map {
            .init(slot: $0.slot, outcome: $0.outcome, verification: $0.verification)
        }
        return record
    }
}

// MARK: - Storage

/// Where an in-progress guided test lives between launches.
///
/// Next to the compatibility report, in the App Group, and for the same reason: the write pass asks
/// the tester to switch their camera off and on, and an iOS relaunch during that is ordinary. A
/// session that lived in view state would lose everything the person had already typed.
///
/// One file — a second concurrent test is not a thing a person does — and `history` keeps the
/// ended ones, finished or abandoned.
enum GuidedTestStore {

    static var directoryURL: URL? { CameraReportStore.directoryURL }
    static var latestURL: URL? { directoryURL?.appendingPathComponent("guided-test-session.json") }
    static var historyURL: URL? { directoryURL?.appendingPathComponent("guided-test-history.json") }

    /// Sessions this device has ended, newest last. Bounded: readers look up the newest one, or one
    /// by session ID.
    static let maxHistory = 10

    @discardableResult
    static func save(_ session: GuidedTestSession) -> URL? {
        guard let dir = directoryURL, let url = latestURL else { return nil }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try CameraCompatibilityReport.encoder.encode(session).write(to: url, options: .atomic)
            return url
        } catch {
            AppLog.error(.camera, "Camera test: could not save the session — \(AppLog.bounded(error))")
            return nil
        }
    }

    static func load() -> GuidedTestSession? {
        guard let url = latestURL, let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try CameraCompatibilityReport.decoder.decode(GuidedTestSession.self, from: data)
        } catch {
            AppLog.error(.camera, "Camera test: the saved session could not be decoded — \(AppLog.bounded(error))")
            return nil
        }
    }

    static func loadHistory() -> [GuidedTestSession] {
        guard let url = historyURL, let data = try? Data(contentsOf: url) else { return [] }
        do {
            return try CameraCompatibilityReport.decoder.decode([GuidedTestSession].self, from: data)
        } catch {
            AppLog.error(.camera, "Camera test: the saved history could not be decoded — \(AppLog.bounded(error))")
            return []
        }
    }

    enum RestartError: LocalizedError {
        case archiveFailed, saveFailed

        var errorDescription: String? {
            switch self {
            case .archiveFailed: return "The previous results could not be saved. Your current test is still available."
            case .saveFailed: return "The new test could not be saved. Your previous results and backups are still available."
            }
        }
    }

    /// Restart navigation without treating outstanding camera changes as resolved. Recovery
    /// remains separate and still blocks a new write baseline for the same camera.
    @MainActor
    static func startOver(replacing current: GuidedTestSession?, facts: CameraFacts) throws -> GuidedTestSession {
        var previous = [GuidedTestSession]()
        if let live = load(), live.id != current?.id { previous.append(live) }
        if let current { previous.append(current) }
        for var record in previous {
            if record.reportSnapshot == nil {
                record.reportSnapshot = .forSession(record, report: CameraReportStore.loadLatest())
            }
            if record.isLive {
                record.outcome = .abandoned
                record.touch()
                if let snapshot = record.reportSnapshot {
                    record.reportSnapshot = .refreshing(session: record, reportSnapshot: snapshot)
                }
            }
            // Keep the live session file until the new session is saved successfully.
            guard archive(record, at: historyURL, clearingLive: false) else { throw RestartError.archiveFailed }
        }
        var fresh = GuidedTestSession.beginContinuous()
        fresh.adopt(camera: facts)
        guard save(fresh) != nil else { throw RestartError.saveFailed }
        return fresh
    }

    /// File a finished session and clear the live one. Called when a test ends, however it ended.
    @discardableResult
    static func archive(_ session: GuidedTestSession) -> Bool {
        archive(session, at: historyURL)
    }

    /// The explicit destination also makes write failure testable without filling a device's disk.
    @discardableResult
    static func archive(_ session: GuidedTestSession, at url: URL?, clearingLive: Bool = true) -> Bool {
        guard let url else { return false }
        var history = loadHistory().filter { $0.id != session.id }
        history.append(session)
        if history.count > maxHistory { history.removeFirst(history.count - maxHistory) }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try CameraCompatibilityReport.encoder.encode(history).write(to: url, options: .atomic)
            if clearingLive, load()?.id == session.id { delete() }
            return true
        } catch {
            AppLog.error(.camera, "Camera test: archive failed; the live session was kept — \(AppLog.bounded(error))")
            return false
        }
    }

    /// Forget the live session. `archive` calls this once the session is filed, and `deleteAll`
    /// for Clear Diagnostics.
    static func delete() {
        guard let url = latestURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Everything, including what the tester answered in tests they finished. Clear Diagnostics
    /// promises to erase what a report draws on, and a projected guided test is exactly that.
    static func deleteAll() {
        delete()
        guard let url = historyURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

/// Recovery is operational data, not a rolling diagnostic. Its original backup is immutable;
/// only touched-slot dispositions change. No history limit or Start Over removes these files.
struct GuidedRecoveryRecord: Codable, Equatable, Identifiable {
    let sessionID: String
    let backup: CameraBackup
    let transport: String?
    var touchedSlots: [Int] = []
    var dispositions: [String: RestoreDisposition] = [:]
    var id: String { sessionID }

    var unresolvedSlots: [Int] {
        touchedSlots.filter { dispositions[String($0)]?.isSettled != true }
    }

    /// Missing serial data remains uncertainty. If either side supplies a serial, both must agree.
    /// Name-only matches are allowed only when neither side exposed a serial, never called proof.
    func matches(_ facts: CameraFacts) -> Bool {
        guard backup.camera.productName == facts.productName, transport == facts.transport else { return false }
        if backup.camera.serialHash != nil || facts.serialHash != nil {
            // The backup is never rewritten, so one taken before serials were keyed keeps its
            // legacy hash for good; `same` recognizes it whenever its camera is connected.
            return SerialHash.same(backup.camera.serialHash, facts.serialHash)
        }
        return true
    }

    /// What Settings exports before Clear Diagnostics erases this record: the original backup, which
    /// Restore a Slot reads back, `forSharing`. The record itself keeps an unkeyed hash, for `matches`.
    var exportFile: (fileName: String, data: Data) {
        ("fuji-cookbook-recovery-\(sessionID).json", backup.forSharing.json)
    }
}

enum GuidedRecoveryStore {
    static var directoryURL: URL? {
        CameraReportStore.directoryURL?.appendingPathComponent("camera-test-recovery", isDirectory: true)
    }

    private static func url(sessionID: String) -> URL? {
        // A session ID is internal, but a decoded file must not be able to escape its directory.
        guard !sessionID.isEmpty, sessionID.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return nil }
        return directoryURL?.appendingPathComponent("\(sessionID).json")
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func load(sessionID: String) -> GuidedRecoveryRecord? {
        guard let url = url(sessionID: sessionID), let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let record = try? decoder.decode(GuidedRecoveryRecord.self, from: data),
              record.sessionID == sessionID else { return nil }
        return record
    }

    static func allRecords() -> [GuidedRecoveryRecord] {
        guard let directoryURL,
              let urls = try? FileManager.default.contentsOfDirectory(at: directoryURL,
                                                                      includingPropertiesForKeys: nil) else { return [] }
        return urls.filter { $0.pathExtension == "json" }.compactMap {
            load(sessionID: $0.deletingPathExtension().lastPathComponent)
        }.sorted { $0.backup.capturedAt < $1.backup.capturedAt }
    }

    static func unresolvedRecords() -> [GuidedRecoveryRecord] {
        allRecords().filter { !$0.unresolvedSlots.isEmpty }
    }

    @discardableResult
    static func create(_ record: GuidedRecoveryRecord) -> Bool {
        guard let url = url(sessionID: record.sessionID) else { return false }
        // Refuse replacement, including a corrupt file: a fresh camera read cannot reconstruct an
        // original after mutation. Keeping the old evidence is safer than silently replacing it.
        if FileManager.default.fileExists(atPath: url.path) {
            guard let stored = load(sessionID: record.sessionID) else { return false }
            return stored.backup == record.backup && stored.transport == record.transport
        }
        return write(record)
    }

    private static func write(_ record: GuidedRecoveryRecord) -> Bool {
        guard let directoryURL, let url = url(sessionID: record.sessionID) else { return false }
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try encoder.encode(record).write(to: url, options: .atomic)
            // Verify the exact durable representation before a camera operation is permitted.
            return load(sessionID: record.sessionID) == record
        } catch {
            AppLog.error(.camera, "Camera test: recovery could not be saved — \(AppLog.bounded(error))")
            return false
        }
    }

    @discardableResult
    static func markTouched(sessionID: String, slot: Int) -> Bool {
        guard var record = load(sessionID: sessionID), record.backup.slots.contains(where: { $0.index == slot }) else { return false }
        if !record.touchedSlots.contains(slot) { record.touchedSlots.append(slot); record.touchedSlots.sort() }
        record.dispositions[String(slot)] = .pending
        return write(record)
    }

    @discardableResult
    static func recordDisposition(sessionID: String, slot: Int, outcome: RestoreDisposition) -> Bool {
        guard var record = load(sessionID: sessionID), record.touchedSlots.contains(slot) else { return false }
        record.dispositions[String(slot)] = outcome
        return write(record)
    }

    /// Use only after an explicit deletion choice that describes loss of recovery data.
    @discardableResult
    static func deleteAll() -> Bool {
        guard let directoryURL else { return false }
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return true }
        do {
            try FileManager.default.removeItem(at: directoryURL)
            return true
        } catch {
            AppLog.error(.camera, "Camera test: recovery data could not be deleted — \(AppLog.bounded(error))")
            return false
        }
    }
}
