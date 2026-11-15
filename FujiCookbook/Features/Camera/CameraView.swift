import SwiftUI
import SwiftData

/// The camera workspace as an instrument: the device panel, the custom slots as keys, the chosen
/// slot's archive card with three knobs, and a floating bar that loads a recipe into that slot or
/// undoes the last load. Disconnected, the panel shows the camera last read and the ways to connect.
struct CameraView: View {
    @Environment(CameraServices.self) private var camera
    @Environment(AppRouter.self) private var router
    @Query(Recipe.listFetch(sortBy: [SortDescriptor(\Recipe.name)])) private var recipes: [Recipe]

    /// Gates the Demo Camera and the property report — see `DiagnosticMode`.
    @AppStorage(DiagnosticMode.key) private var diagnosticMode = false
    /// The camera last read and its slots as read then, for the panel while nothing is connected.
    @AppStorage(CameraSlotSnapshot.storageKey) private var slotSnapshotsJSON = ""
    @AppStorage(RememberedCamera.displayNameKey) private var rememberedCameraName = ""

    @State private var showingGuide = false
    @State private var showingImport = false
    @State private var showingPropertyReport = false
    @State private var showingConnectionLog = false
    @State private var showingBackupShare = false
    @State private var showingBackupPicker = false
    @State private var restoreTarget: RestoreRequest?
    @State private var backupError: String?
    @State private var pendingBackup: CameraBackup?
    /// The slot the card shows and the bar loads into; nil until the user picks one, which means
    /// the first slot that holds a setting (`CameraInstrument.selection`).
    @State private var chosenSlot: Int?
    /// "Load Recipe into C3": the recipe picker first, then the push with that slot filled in.
    /// The push opens only once the picker is gone, from its `onDismiss`.
    @State private var showingRecipePicker = false
    @State private var pickedPush: PushRequest?
    @State private var push: PushRequest?
    /// What to open the Camera Test with, or nil when it isn't showing.
    ///
    /// Carried as one value rather than two `@State` flags beside an `isPresented` sheet: one value
    /// avoids a stale-parameter race, where the sheet builds with the previous wave.
    @State private var cameraTest: CameraTestRequest?
    @State private var recoveryTest: GuidedRecoveryRecord?
    /// Which card the photo import opens with, or nil when it isn't showing.
    @State private var photoImport: PhotoImportRequest?
    @State private var showingLocationTrack = false
    /// What the Camera Test row shows, read from the store when the tab appears and whenever a test
    /// sheet closes. Held in state because nothing on this screen observes those files: the flow
    /// writes them from inside a sheet, and a body that read them directly would only notice when
    /// something else redrew it — and would decode the history on every camera status change.
    @State private var testRecords = CameraTestRecords()

    private struct CameraTestRecords {
        /// The live session the tester has actually started. Opening the test saves a session at
        /// its intro, and reading the intro is not starting: until Begin, the row stays the
        /// invitation rather than claiming a test is in progress.
        var live: GuidedTestSession?
        var latest: GuidedTestSession?
        var recoveries: [GuidedRecoveryRecord] = []

        static func load() -> CameraTestRecords {
            let live = GuidedTestStore.load().flatMap { session in
                session.isLive && (session.step != .intro || !session.completedSteps.isEmpty) ? session : nil
            }
            return CameraTestRecords(live: live, latest: GuidedTestStore.loadHistory().last,
                                     recoveries: GuidedRecoveryStore.unresolvedRecords())
        }
    }

    private struct CameraTestRequest: Identifiable {
        let id = UUID()
        /// Where to open, when something specific sent the tester there — a failed connect goes
        /// straight to the questions about what happened.
        var entry: GuidedTestStep?
        var wave = 1
        var sessionID: String?
    }

    /// One recipe into one slot, handed to `PushView` as a pre-filled assignment, so the push keeps
    /// its own confirmation, compatibility warnings and read-back.
    private struct PushRequest: Identifiable {
        let slot: Int
        let recipe: UUID
        var id: String { "\(slot)-\(recipe)" }
    }

    /// A recognized body the app selects no slot on (`ConnectedCamera.slotsUnreachable`). Not "we
    /// won't write to it": there is nothing there to read either, so the screen explains the camera
    /// instead of offering it slots and then failing to fill them.
    private var hasNoSlots: Bool { camera.session.connected?.slotsUnreachable ?? false }

    private var cardState: CameraCardState? {
        CameraCardState(isConnected: camera.session.isConnected, isRecovering: camera.connector.isRecovering)
    }

    /// Slots, keys and the bar are for a recognized body with slots.
    private var showsSlots: Bool {
        camera.session.isConnected && camera.session.connected?.isUnsupported != true && !hasNoSlots
    }

    private var slots: [CameraSlot] { camera.slotReader.slots }

    private var selectedSlot: CameraSlot? {
        CameraInstrument.selection(chosenSlot, in: slots).flatMap { index in slots.first { $0.index == index } }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                let inLibrary = CameraInstrument.libraryRecipes(for: slots, in: recipes)
                VStack(alignment: .leading, spacing: DSSpacing.block) {
                    Text("Camera")
                        .dsLargeTitle()
                        .accessibilityAddTraits(.isHeader)
                    // While reconnecting the panel says so. Recovery's own attempts would otherwise
                    // flash "Connecting…", a failure with Connection Help, and slot reads above it.
                    if cardState != .reconnecting { transientStatus }
                    if camera.session.isConnected {
                        connectedPanel
                        if let banner = camera.session.connected.flatMap({ $0.identification.guessBanner(productName: $0.productName) }) {
                            CameraNotice(title: banner, systemImage: "questionmark.diamond.fill") { EmptyView() }
                        }
                        if camera.session.connected?.isUnsupported == true {
                            unrecognizedCard
                            cameraTestSection
                        } else if hasNoSlots {
                            // The slot keys are hidden rather than emptied: "No slots read yet."
                            // is untrue here and implies a pull-to-refresh would help.
                            noSlotProtocolCard
                            cameraTestSection
                        } else {
                            // What was read before the drop, until the reconnect reads it again.
                            Group {
                                slotKeys(inLibrary: inLibrary)
                                if let slot = selectedSlot { slotCard(slot, libraryRecipe: inLibrary[slot.index]) }
                            }
                            .opacity(cardState == .reconnecting ? 0.45 : 1)
                        }
                        driftCard
                        divergenceCard
                        if camera.session.model != nil, !camera.slotWriter.canPush, !hasNoSlots {
                            Text(camera.slotWriter.pushBlockReason ?? "Push is disabled for this camera because its parameter encodings haven't been verified on hardware yet. Reading recipes is always safe.")
                                .font(DSFont.subhead)
                                .foregroundStyle(DSColor.textSecondary)
                        }
                        backupRow
                        if camera.session.model != nil, ReportSurfaces.current.showsReportPrompts { reportProblemRow }
                    } else {
                        offlinePanel
                        connectCard
                    }
                    helpButton
                    if !testLeadsThePage { cameraTestSection }
                    // Reachable whether or not the camera is connected — unlike the property report,
                    // this is exactly what's needed right after a failed or flaky connect attempt.
                    if diagnosticMode { connectionLogButton }
                    if camera.session.isConnected, diagnosticMode { propertyReportButton }
                }
                .padding(DSSpacing.screenMargin)
            }
            .background(DSColor.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { if showsSlots { actionBar } }
            .tint(DSColor.signal)
            .navigationBarTitleDisplayMode(.inline)
            .settingsToolbarItem()
            .toolbar {
                // The title lives in the scroll view; an empty principal item keeps the bar from
                // repeating it inline.
                ToolbarItem(placement: .principal) {
                    Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
                }
                if camera.session.isConnected {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Disconnect") { Task { await camera.connector.disconnect() } }
                    }
                }
            }
            .sheet(isPresented: $showingGuide) {
                ConnectionGuideView()
            }
            .sheet(item: $cameraTest, onDismiss: refreshTestRecords) { request in
                GuidedTestView(entry: request.entry, wave: request.wave, sessionID: request.sessionID)
            }
            .sheet(item: $recoveryTest, onDismiss: refreshTestRecords) { record in
                GuidedRecoveryView(record: record)
            }
            .onAppear(perform: refreshTestRecords)
            .sheet(isPresented: $showingImport) { NavigationStack { CameraImportView() } }
            .sheet(isPresented: $showingLocationTrack) { NavigationStack { LocationTrackView() } }
            // The menu bar's Import Photos: taken over here, so it opens like the row above.
            .onChange(of: router.photoImport, initial: true) { _, request in
                guard let request else { return }
                photoImport = request
                router.photoImport = nil
            }
            .sheet(item: $photoImport) { request in
                NavigationStack { PhotoImportView(source: request.makeSource()) }
            }
            .sheet(isPresented: $showingRecipePicker, onDismiss: {
                push = pickedPush
                pickedPush = nil
            }) {
                RecipePickerSheet(title: "Load into \(selectedSlot?.label ?? "Slot")",
                                  choices: recipes.map(RecipeChoice.init),
                                  mode: .single) { picked in
                    guard case .library(let uuid)? = picked.first, let slot = selectedSlot else { return }
                    pickedPush = PushRequest(slot: slot.index, recipe: uuid)
                }
            }
            .sheet(item: $push) { request in
                NavigationStack { PushView(preselectedRecipe: nil, preassignedSlots: [request.slot: request.recipe]) }
            }
            .sheet(item: $restoreTarget) { target in
                RestoreView(slot: target.slot, slotName: target.name,
                            saved: target.saved, source: target.source)
            }
            .sheet(isPresented: $showingBackupPicker) {
                ContentPicker(contentTypes: [.json], allowsMultiple: false) { urls in
                    showingBackupPicker = false
                    guard let url = urls.first else { return }
                    loadBackup(from: url)
                }
            }
            .sheet(item: $pendingBackup) { backup in
                NavigationStack { backupSlotPicker(backup) }
            }
            .alert("Couldn't Read That Backup",
                   isPresented: Binding(isPresent: $backupError)) {
                Button("OK", role: .cancel) { backupError = nil }
            } message: { Text(backupError ?? "") }
            .sheet(isPresented: $showingPropertyReport) { NavigationStack { CameraPropertyReportView() } }
            .sheet(isPresented: $showingConnectionLog) { NavigationStack { ConnectionLogView() } }
            // `requestRefresh()`, not `refresh()`: `connect` reports `.connected` before it
            // awaits its own slot read, so this is pullable while that read is still walking slots.
            .refreshable { if camera.session.isConnected { await camera.slotReader.requestRefresh() } }
        }
    }

    // MARK: Transient status (connecting / working / failed)

    @ViewBuilder
    private var transientStatus: some View {
        switch camera.session.status {
        // Ahead of the status, which a cancel has already set to disconnected: the connect can
        // still be inside a session open, and the Connect rows wait for it.
        case _ where camera.connector.connectProgress == .cancelling:
            statusPanel {
                HStack(spacing: DSSpacing.s) {
                    ProgressView()
                    Text("Cancelling…")
                }
            }
        case .connecting:
            statusPanel {
                HStack(spacing: DSSpacing.s) {
                    ProgressView()
                    Text("Connecting…")
                    // Only a connect the user started; recovery's reconnects also pass through
                    // `.connecting`, and Disconnect ends those.
                    if camera.connector.connectProgress == .running {
                        Spacer()
                        Button("Cancel") { Task { await camera.connector.cancelConnect() } }
                            .buttonStyle(.dsTextKey(isActive: false))
                    }
                }
            }
        case .working(let message):
            statusPanel {
                HStack(spacing: DSSpacing.s) {
                    ProgressView()
                    Text(message)
                }
            }
        case .failed(let message):
            CameraNotice(title: message, systemImage: "exclamationmark.triangle.fill") {
                HStack(spacing: DSSpacing.s) {
                    Button("Connection Help") { showingGuide = true }
                    // A camera that never appears is the most common failure and the one
                    // the app can say least about by itself — it has the two permission states
                    // and the stage that failed, and nothing that separates a charge-only cable
                    // from the wrong USB mode. That part has to be asked.
                    if ReportSurfaces.current.showsCameraTest {
                        Button("Tell Us What Happened") {
                            cameraTest = CameraTestRequest(entry: .noCamera)
                        }
                    }
                }
                .buttonStyle(.dsTextKey(isActive: false))
            }
        case .connected, .disconnected:
            EmptyView()
        }
    }

    private func statusPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .font(DSFont.subhead)
            .foregroundStyle(DSColor.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DSSpacing.l)
            .background(DSColor.panel, in: RoundedRectangle(cornerRadius: DSRadius.panel, style: .continuous))
    }

    // MARK: Device panel

    /// The camera held: its name, a mono line of firmware, transport and slot range, and two LEDs.
    /// While a dropped session recovers, LINK goes dark and the line says "Reconnecting", so the
    /// camera last seen never reads as connected.
    @ViewBuilder
    private var connectedPanel: some View {
        if let connected = camera.session.connected, let state = cardState {
            let showsRange = connected.model != nil && !hasNoSlots
            VStack(alignment: .leading, spacing: DSSpacing.s) {
                DSDevicePanel(title: connected.model?.displayName ?? connected.productName,
                              meta: CameraInstrument.panelMeta(firmware: connected.firmwareVersion,
                                                               isDemo: connected.isDemo,
                                                               isReconnecting: state == .reconnecting,
                                                               slotCount: showsRange ? camera.slotReader.effectiveSlotCount : 0)) {
                    DSPanelLEDs(indicators: CameraInstrument.panelLEDs(isLive: state == .live,
                                                                       canWrite: camera.slotWriter.canPush))
                }
                // One source for the seal, shared with the test's identity step — which asks the
                // tester to confirm it, and records what they were shown.
                Label(connected.capabilityBadge.text, systemImage: connected.capabilityBadge.symbol)
                    .dsMetaMono()
                    .padding(.horizontal, DSSpacing.xs)
            }
            .animation(.easeInOut(duration: 0.25), value: state)
            .accessibilityElement(children: .combine)
        }
    }

    /// Nothing connected: the camera last read, dark, with the day of that read.
    private var offlinePanel: some View {
        let snapshot = CameraSlotSnapshot.all(from: slotSnapshotsJSON)[rememberedCameraName]
        let field = LibraryCameraField(snapshot: snapshot, connectedCameraName: nil)
        let meta = ["Offline", snapshot.map { _ in field.value }, field.asOf]
            .compactMap { $0 }.joined(separator: "   ")
        return DSDevicePanel(title: rememberedCameraName.isEmpty ? "No Camera" : rememberedCameraName, meta: meta) {
            DSPanelLEDs(indicators: CameraInstrument.panelLEDs(isLive: false, canWrite: false))
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Slots

    /// C1–C7 as keys, the chosen one active, and the import key last.
    private func slotKeys(inLibrary: [Int: Recipe]) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            Text("Custom Slots").dsMetaMono(DSColor.textPrimary).accessibilityAddTraits(.isHeader)
            if slots.isEmpty {
                Text("No slots read yet.")
                    .font(DSFont.subhead)
                    .foregroundStyle(DSColor.textSecondary)
            } else {
                let selected = CameraInstrument.selection(chosenSlot, in: slots)
                let canImport = actionsAvailable && slots.contains { $0.isOccupied }
                DSSlotGrid {
                    ForEach(slots) { slot in
                        DSSlotKey(slot: slot.label,
                                  name: slot.isOccupied ? slot.displayName : nil,
                                  isOccupied: slot.isOccupied,
                                  isSelected: slot.index == selected) {
                            chosenSlot = slot.index
                        }
                        // The free undo, also on the key: the bytes this slot held before the app
                        // last wrote to it.
                        .contextMenu {
                            if let request = undoRequest(for: slot) {
                                Button { restoreTarget = request } label: {
                                    Label("Undo Last Push to \(slot.label)", systemImage: "arrow.uturn.backward")
                                }
                            }
                        }
                    }
                    DSSlotImportKey(newCount: CameraInstrument.newSlotCount(slots, inLibrary: inLibrary)) {
                        showingImport = true
                    }
                    .disabled(!canImport)
                    .opacity(canImport ? 1 : 0.45)
                }
            }
        }
    }

    /// The chosen slot as an archive card: its label as the number, the setting's name, the film
    /// simulation band, COLOR / GRAIN / DYNAMIC as knobs, the rest as a data sheet, and whether the
    /// library holds it.
    private func slotCard(_ slot: CameraSlot, libraryRecipe: Recipe?) -> some View {
        DSArchiveCard {
            DSArchiveHeader(objectNumber: slot.label,
                            fields: CameraInstrument.sideFields(isOccupied: slot.isOccupied, libraryRecipe: libraryRecipe))
            DSRule()
            if slot.isOccupied, let settings = slot.settings {
                DSArchiveTitle(title: slot.resolvedName ?? "Unnamed")
                DSSimulationBand(simulation: settings.filmSimulation)
                HStack(alignment: .top) {
                    ForEach(CameraInstrument.knobs(for: settings), id: \.label) { knob in
                        DSKnob(label: knob.label, value: knob.value, position: knob.position)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, DSSpacing.l)
                .padding(.horizontal, DSSpacing.s)
                DSRule()
                DSDataSheet(fields: CameraInstrument.dataSheetFields(for: settings))
                slotNotes(slot)
                DSRule()
                DSArchiveFooter(barcodeSeed: "\(camera.session.connected?.productName ?? "")-\(slot.label)",
                                text: CameraInstrument.footer(isOccupied: true, libraryRecipe: libraryRecipe))
            } else {
                DSArchiveTitle(title: slot.isOccupied ? slot.displayName : "Empty",
                               description: slot.isOccupied
                               ? "The camera holds a setting here that this app couldn't read."
                               : "This slot holds no setting. Load a recipe into it below.")
            }
        }
    }

    /// What the card can't show as a field: values the app couldn't read, and settings only the
    /// camera holds. Said as information, so an import doesn't look like it lost something.
    @ViewBuilder
    private func slotNotes(_ slot: CameraSlot) -> some View {
        if !slot.unsupportedFields.isEmpty || !slot.cameraOnlyFields.isEmpty {
            DSSeparator()
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                if !slot.unsupportedFields.isEmpty {
                    Label("\(slot.unsupportedFields.count) setting\(slot.unsupportedFields.count == 1 ? "" : "s") this app couldn't read",
                          systemImage: "exclamationmark.triangle.fill")
                }
                ForEach(slot.cameraOnlyFields.sorted(by: { $0.key < $1.key }), id: \.key) { field, label in
                    Label("\(field): \(label), set on the camera, not part of a recipe", systemImage: "camera")
                }
            }
            .font(DSFont.subhead)
            .foregroundStyle(DSColor.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DSSpacing.m)
        }
    }

    // MARK: Action bar

    /// "Load Recipe into C3" and the undo of the last push to that slot. The undo is an icon key so
    /// the primary key keeps its whole label at every text size.
    private var actionBar: some View {
        let slot = selectedSlot
        let canLoad = actionsAvailable && camera.slotWriter.canPush && slot != nil
        let undo = slot.flatMap(undoRequest(for:))
        return DSFloatingActionBar(status: CameraInstrument.actionStatus(slotLabel: slot?.label,
                                                                         canWrite: camera.slotWriter.canPush,
                                                                         isBusy: !actionsAvailable)) {
            HStack(spacing: DSSpacing.m) {
                DSIconKey(systemImage: "arrow.uturn.backward",
                          label: "Undo Last Push to \(slot?.label ?? "Slot")") {
                    restoreTarget = undo
                }
                .disabled(undo == nil || !actionsAvailable)
                Button { showingRecipePicker = true } label: {
                    Label("Load Recipe into \(slot?.label ?? "Slot")", systemImage: "arrow.up.to.line")
                        .lineLimit(1)
                }
                .buttonStyle(.dsPrimary)
                .disabled(!canLoad)
            }
        }
    }

    /// The bytes this slot held before the app last wrote to it, when there are any and the app may
    /// write. The name is the one the push *replaced*, never the slot's current one; `undoName`
    /// holds the rule.
    private func undoRequest(for slot: CameraSlot) -> RestoreRequest? {
        guard camera.slotWriter.canPush,
              let saved = camera.reports.history.lastPushPriorBytes(forSlot: slot.index) else { return nil }
        return RestoreRequest(slot: slot.index, name: camera.reports.history.undoName(forSlot: slot.index),
                              saved: saved, source: .lastPush)
    }

    // MARK: Notices

    /// The unrecognized-body path's whole purpose: turn "not supported" into an artifact that gets
    /// the body supported. The report is on disk already; this card says what it holds and leaves
    /// sending it to the Camera Test, whose results screen shows the report, as readable text and as
    /// the attached JSON, before anything is shared (`DiagnosticsReportView`).
    @ViewBuilder
    private var unrecognizedCard: some View {
        if let report = camera.reports.report {
            CameraNotice(title: "This camera isn't supported yet", systemImage: "questionmark.diamond") {
                Text(ReportSurfaces.current.showsCameraTest
                     ? "Darkslide read everything \(report.camera.productName) would show it and changed nothing. Sharing a report is what gets this camera supported. It contains what the camera says about itself and the recipe settings it currently holds — nothing leaves the phone until you share it."
                     : "Darkslide read everything \(report.camera.productName) would show it and changed nothing.")
                // No share button here: the Camera Test below leads to the fuller report — the same
                // camera data plus the logs and the answers only a person can give — and two
                // buttons offering different halves of one thing would make the weaker one look
                // like the quicker route.
            }
        }
    }

    /// A recognized body whose firmware has no custom-slot protocol.
    ///
    /// The registry already records that these bodies have no working slot select
    /// (`CameraModelRegistry`, which cites the record), so sending one would only show the tester
    /// "Couldn't select custom slot C1 on the camera": an error, for a fact known before the cable
    /// went in. The connection is fine; the camera doesn't have the feature. So this says that
    /// plainly, in the body's own words (`writeSupport.blockReason`), and points at the Camera Test,
    /// whose report is what confirms or overturns the bodies the registry holds on inference
    /// (`GuidedTestView`).
    @ViewBuilder
    private var noSlotProtocolCard: some View {
        if camera.reports.report != nil, let model = camera.session.model {
            // No model name in the title: the panel directly above already names the body, and
            // `blockReason` opens with it too — three in a row read as a stutter.
            CameraNotice(title: "No custom slots over USB", systemImage: "lock.fill") {
                Text("\(model.writeSupport.blockReason ?? "This camera's firmware doesn't expose custom slots over USB.") Darkslide read everything it would show and changed nothing — it didn't even ask the camera to select a slot.")
                if ReportSurfaces.current.showsCameraTest {
                    Text("Sharing a report is what gets this camera's support confirmed. It holds what the camera says about itself and which settings it answered for — nothing leaves the phone until you share it. The Camera Test walks you through producing one.")
                }
            }
        }
    }

    /// A slot that changed since the app last wrote it. Distinct from `divergenceCard`, which is
    /// about values the app can't read: this is a value it wrote, verified, and later found
    /// replaced. The app didn't do it, and says so — on a dial body, the dial is the usual answer.
    @ViewBuilder
    private var driftCard: some View {
        let drift = camera.slotReader.filmSimulationDrift
        if !drift.isEmpty {
            let dial = camera.session.model?.hasFilmSimulationDial ?? false
            CameraNotice(title: drift.count == 1 ? "A slot changed since you last wrote it"
                                                 : "\(drift.count) slots changed since you last wrote them",
                         systemImage: "arrow.triangle.2.circlepath") {
                ForEach(drift) { Text($0.summary + ".") }
                Text(dial
                     ? "Darkslide didn't do this. On the \(camera.session.model?.displayName ?? "camera"), the Film Simulation dial can change a custom slot's film simulation — check that it's on “C”. Push the recipe again to restore it."
                     : ReportSurfaces.current.showsReportPrompts
                        ? "Darkslide didn't do this. Push the recipe again to restore it, and if it keeps happening, send a report."
                        : "Darkslide didn't do this. Push the recipe again to restore it.")
                if ReportSurfaces.current.showsReportPrompts {
                    NavigationLink { DiagnosticsReportView() } label: {
                        Label("Report a Problem", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.dsTextKey(isActive: false))
                }
            }
        }
    }

    /// Slots whose contents the codec could not fully read.
    private var divergentSlots: [CameraSlot] { slots.filter { !$0.unsupportedFields.isEmpty } }

    /// Tells the user when a slot holds values the codec doesn't recognize, and offers a report.
    ///
    /// A body whose encodings differ from ours produces recipes that look plausible, so without
    /// this card the misread goes unnoticed and unreported. It renders for recognized and guessed
    /// bodies alike: a *recognized* body reading wrongly is the case nothing else on this screen
    /// covers.
    @ViewBuilder
    private var divergenceCard: some View {
        if !divergentSlots.isEmpty {
            let count = divergentSlots.reduce(0) { $0 + $1.unsupportedFields.count }
            let names = divergentSlots.map(\.label).joined(separator: ", ")
            CameraNotice(title: "Some settings didn't read cleanly", systemImage: "exclamationmark.triangle.fill") {
                Text("Darkslide read \(count) value\(count == 1 ? "" : "s") on \(names) that it doesn't recognize on this camera. It left \(count == 1 ? "that setting" : "those settings") blank rather than guessing, so what you see may be incomplete\(ReportSurfaces.current.showsReportPrompts ? " — and that's exactly the kind of fact that gets this camera properly supported" : "").")
                if ReportSurfaces.current.showsReportPrompts {
                    NavigationLink { DiagnosticsReportView() } label: {
                        Label("Report a Problem", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.dsPrimary)
                }
            }
        }
    }

    // MARK: Backup

    /// One pending restore: which slot, from where, and the bytes.
    struct RestoreRequest: Identifiable {
        let slot: Int
        let name: String
        let saved: [UInt16: Data]
        let source: RestoreView.Source
        var id: Int { slot }
    }

    /// Save every slot, and put one back.
    ///
    /// The save half is free — `SlotReader.refresh()` already read these bytes — and it is the only thing
    /// here that carries no risk at all, which is why it leads. The restore half is a push in every
    /// respect but its values, so it is offered **one slot at a time**: that keeps the exposure
    /// identical to the push it undoes, and it matches how damage actually happens.
    ///
    /// A quiet section below the slot card: Undo Last Push already covers a slot's latest push, so
    /// this is the fullest way back, not the only one.
    @ViewBuilder
    private var backupRow: some View {
        if camera.session.model != nil, slots.contains(where: { $0.isOccupied }) {
            DSArchiveSection(title: "Backup") {
                Text("Save every slot's exact settings to a file you keep, so you can put any slot back later.")
                    .font(DSFont.subhead)
                    .foregroundStyle(DSColor.textSecondary)
                // Side by side, stacked when the largest text sizes leave no room for both.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: DSSpacing.s) { backupButtons }
                    VStack(alignment: .leading, spacing: DSSpacing.s) { backupButtons }
                }
                .buttonStyle(.dsTextKey(isActive: false))
            }
            .sheet(isPresented: $showingBackupShare) {
                if let backup = camera.slotReader.slotBackup {
                    ShareBundle.backupShareSheet(backup)
                }
            }
        }
    }

    @ViewBuilder
    private var backupButtons: some View {
        Button { showingBackupShare = true } label: {
            Label("Save Backup", systemImage: "square.and.arrow.up")
        }
        .disabled(camera.slotReader.slotBackup == nil)
        if camera.slotWriter.canPush {
            Button { showingBackupPicker = true } label: {
                Label("Restore a Slot…", systemImage: "arrow.uturn.backward")
            }
        }
    }

    /// Which slot to put back. One at a time, deliberately — see `backupRow`.
    @ViewBuilder
    private func backupSlotPicker(_ backup: CameraBackup) -> some View {
        List {
            Section {
                ForEach(backup.slots.sorted { $0.index < $1.index }, id: \.index) { slot in
                    Button {
                        guard let saved = backup.properties(forSlot: slot.index) else { return }
                        pendingBackup = nil
                        restoreTarget = RestoreRequest(slot: slot.index,
                                                       name: slot.name ?? "C\(slot.index)",
                                                       saved: saved,
                                                       source: .backup(name: backup.suggestedFilename))
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("C\(slot.index)").font(DSFont.subhead.weight(.semibold))
                                Text(slot.occupied ? (slot.name ?? slot.summary ?? "Occupied")
                                                   : "Empty when this backup was taken")
                                    .font(DSFont.subhead).foregroundStyle(DSColor.textSecondary)
                            }
                            Spacer()
                            if slot.occupied { Image(systemName: "chevron.right").font(DSFont.subhead) }
                        }
                    }
                    .disabled(!slot.occupied || backup.properties(forSlot: slot.index) == nil)
                }
            } footer: {
                Text("A slot that was empty can't be put back. " + CameraBackup.slotCannotBeEmptied)
            }
        }
        .navigationTitle("Restore Which Slot?")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { pendingBackup = nil } }
        }
    }

    /// Read a picked backup, refuse it if it belongs to another body, then ask which slot.
    ///
    /// The body check is not pedantry: a backup is raw property bytes, and writing one camera's
    /// bytes into another is the one mistake this feature makes newly possible.
    private func loadBackup(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let backup = try CameraBackup.decode(try Data(contentsOf: url))
            if let connected = camera.session.connected,
               !backup.camera.isFromBody(productName: connected.productName,
                                         registryModelID: connected.registryModel?.id) {
                backupError = CameraBackupError.differentBody(
                    backup: backup.camera.modelID ?? backup.camera.productName,
                    connected: connected.registryModel?.id ?? connected.productName).errorDescription
                return
            }
            pendingBackup = backup
        } catch {
            backupError = error.localizedDescription
        }
    }

    // MARK: Camera Test

    /// The route for people who want to help: one quiet row at the end of the page.
    ///
    /// Offered for every connected body, verified or not: every other report route here is worded
    /// for a failure, and a clean session on an unverified body is the one that promotes it. The
    /// README and CONTRIBUTING send contributors to it by its title. For a body with no match or no
    /// slots it follows the card that explains that (`testLeadsThePage`).
    ///
    /// Disconnected, it starts nothing new but keeps what's already begun: a live test (menu
    /// comparisons require unplugging), saved results and unresolved recovery records.
    ///
    /// The camera report alone can't stand in for the test: whether the app's reading matches the
    /// camera's own menu, and whether a pushed recipe survives a power cycle, take a person to answer.
    @ViewBuilder
    private var cameraTestSection: some View {
        // With the Camera Test hidden, only recovery stays: it puts back slots a past test changed.
        let showsTest = ReportSurfaces.current.showsCameraTest
        let session = showsTest ? testRecords.live : nil
        let latest = showsTest ? testRecords.latest : nil
        let recoveries = testRecords.recoveries
        if session != nil || (showsTest && camera.session.isConnected) || latest != nil || !recoveries.isEmpty {
            VStack(alignment: .leading, spacing: DSSpacing.s) {
                if let session {
                    cameraTestRow(title: "Camera Test in progress",
                                  subtitle: "\(GuidedTestFlow.positionLabel(of: session.step, in: session)). Pick up where you left off.",
                                  systemImage: "arrow.right.circle") {
                        cameraTest = CameraTestRequest(wave: session.wave)
                    }
                } else if showsTest, camera.session.isConnected {
                    cameraTestRow(title: "Help improve camera support",
                                  subtitle: "A guided Camera Test shows how your \(testedCameraName) works with Darkslide.",
                                  systemImage: "checklist") {
                        cameraTest = CameraTestRequest()
                    }
                } else if let latest {
                    cameraTestRow(title: "Your Camera Test results",
                                  subtitle: "Review or share your last test.",
                                  systemImage: "checklist") {
                        cameraTest = CameraTestRequest(wave: latest.wave, sessionID: latest.id)
                    }
                }
                if let latest, session != nil || camera.session.isConnected {
                    Button("Review Saved Test Results") {
                        cameraTest = CameraTestRequest(wave: latest.wave, sessionID: latest.id)
                    }
                    .buttonStyle(.dsTextKey(isActive: false))
                }
                ForEach(recoveries) { record in
                    Button {
                        recoveryTest = record
                    } label: {
                        Label("Review \(record.backup.camera.productName) settings", systemImage: "arrow.uturn.backward.circle")
                    }
                    .buttonStyle(.dsTextKey(isActive: false))
                }
            }
        }
    }

    /// A body with no match or no slots has nothing else to do here, so the test follows the card
    /// that explains it instead of waiting at the end of the page.
    private var testLeadsThePage: Bool {
        camera.session.isConnected && (camera.session.model == nil || hasNoSlots)
    }

    /// "your X-S20", in the invitation. The demo's display name is written for a model list.
    private var testedCameraName: String {
        guard let connected = camera.session.connected else { return "camera" }
        if connected.isDemo { return "demo camera" }
        return connected.model?.displayName ?? connected.productName
    }

    /// The quiet row: a framed place to go, not a task to do.
    private func cameraTestRow(title: String, subtitle: String, systemImage: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.m) {
                Image(systemName: systemImage)
                    .font(DSFont.headline)
                    .foregroundStyle(DSColor.signalText)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(DSFont.headline)
                        .foregroundStyle(DSColor.textPrimary)
                    Text(subtitle)
                        .font(DSFont.subhead)
                        .foregroundStyle(DSColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(DSFont.subhead.weight(.semibold))
                    .foregroundStyle(DSColor.textSecondary)
            }
            .padding(DSSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .dsArchiveFrame()
        }
        .buttonStyle(DSPlainPressStyle())
    }

    private func refreshTestRecords() {
        testRecords = .load()
    }

    /// The always-there route for a *recognized* body.
    ///
    /// `unrecognizedCard` only appears when nothing matched, and `divergenceCard` only when the
    /// decode noticed something. The case neither covers is the dangerous one: a body the app is
    /// confident about, reading and pushing without complaint, getting it wrong. Not gated on
    /// Diagnostic Mode — a tester will not find that toggle.
    private var reportProblemRow: some View {
        NavigationLink { DiagnosticsReportView() } label: {
            HStack(spacing: DSSpacing.s) {
                Text("Recipes look wrong, or a push didn't take?")
                    .foregroundStyle(DSColor.textSecondary)
                Spacer(minLength: 0)
                Text("Report a Problem")
                    .fontWeight(.semibold)
                    .foregroundStyle(DSColor.signalText)
                Image(systemName: "chevron.right")
                    .foregroundStyle(DSColor.signalText)
            }
            .font(DSFont.subhead)
        }
        .buttonStyle(DSPlainPressStyle())
    }

    private var actionsAvailable: Bool {
        Self.actionsAvailable(status: camera.session.status, cardState: cardState)
    }

    /// Whether Import and Push may open: a live session with nothing running.
    ///
    /// `connected` stays set while a dropped session recovers, so the panel can show the camera as
    /// reconnecting, but the transport is down for the whole recovery. That includes a failed
    /// attempt's `.failed` while the next one waits, which `isBusy` alone doesn't cover.
    nonisolated static func actionsAvailable(status: CameraSession.Status, cardState: CameraCardState?) -> Bool {
        cardState == .live && !status.isBusy
    }

    // MARK: Disconnected

    private var connectCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            Text("Connect").dsMetaMono(DSColor.textPrimary).accessibilityAddTraits(.isHeader)
            // One connect at a time: the rows wait out the one under way, whose progress shows above.
            VStack(spacing: 0) {
                if SharedContainer.isLocalMacBuild {
                    // See `SharedContainer.isLocalMacBuild`: no USB camera in this build.
                    Text("This Mac build is signed to run locally, so it can't reach a camera over USB. Recipes, rolls and the Darkroom work; the Demo Camera and Demo Card are under the diagnostic tools.")
                        .font(DSFont.subhead)
                        .foregroundStyle(DSColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DSSpacing.m)
                } else {
                    connectRow(title: "Connect Camera (USB)", systemImage: "cable.connector") {
                        Task { await camera.connector.connectHardware() }
                    }
                    DSSeparator()
                    connectRow(title: "Import Photos (USB)", systemImage: "photo.on.rectangle.angled") {
                        photoImport = .camera
                    }
                }
                // Recorded on the walk, so on the phone that goes along: not on the Mac.
                if !ProcessInfo.processInfo.isMacCatalystApp {
                    DSSeparator()
                    connectRow(title: LocationRecorder.shared.isRecording ? "Location Track (Recording)" : "Location Track",
                               systemImage: "location") {
                        showingLocationTrack = true
                    }
                }
                if diagnosticMode {
                    DSSeparator()
                    connectRow(title: "Import Photos from Demo Card", systemImage: "play.circle") {
                        photoImport = .demo
                    }
                    DSSeparator()
                    connectRow(title: "Connect Demo Camera", systemImage: "play.circle") {
                        Task { await camera.connector.connectDemo() }
                    }
                    DSSeparator()
                    // The demo model converts, so the develop step's profile harvest never shows
                    // on it. This one presents as a GFX100 — read, write, no Kitchen — which is the
                    // only way to walk that step without owning such a body.
                    connectRow(title: "Connect Demo as GFX100 (no Darkroom)", systemImage: "play.circle") {
                        Task { await camera.connector.connectDemo(using: MockCameraTransport(faults: .gfx100WithoutKitchen)) }
                    }
                }
            }
            .disabled(camera.connector.isConnecting)
            .opacity(camera.connector.isConnecting ? 0.45 : 1)
            .dsArchiveFrame()
            Text(diagnosticMode
                 ? "No Fuji body handy? “Connect Demo Camera” runs the full read/import/push workflow with a simulated camera. For real hardware, connect by USB in “USB RAW Conv./Backup Restore” mode — see Connection Help. Importing photos needs “USB Card Reader” mode instead."
                 : "Connect your camera by USB in “USB RAW Conv./Backup Restore” mode — see Connection Help. Importing photos needs “USB Card Reader” mode instead.")
                .font(DSFont.subhead)
                .foregroundStyle(DSColor.textSecondary)
        }
    }

    private func connectRow(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.m) {
                Image(systemName: systemImage)
                    .foregroundStyle(DSColor.signalText)
                    .frame(width: 24)
                Text(title)
                    .font(DSFont.headline)
                    .foregroundStyle(DSColor.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(DSFont.subhead.weight(.semibold))
                    .foregroundStyle(DSColor.textSecondary)
            }
            .padding(DSSpacing.m)
            .contentShape(Rectangle())
        }
        .buttonStyle(DSPlainPressStyle())
    }

    /// Diagnostics: what the camera says it holds and will accept, per property. Lives here rather
    /// than in Settings because it needs the live session (see `CameraPropertyReportView`).
    private var propertyReportButton: some View {
        Button { showingPropertyReport = true } label: {
            Label("Camera Property Report", systemImage: "list.bullet.rectangle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.dsSecondary)
    }

    /// Diagnostics: the connect/disconnect/keepalive/recovery event history (`CameraLog`). Shown
    /// outside the `isConnected` gate on purpose — see the call site.
    private var connectionLogButton: some View {
        Button { showingConnectionLog = true } label: {
            Label("Connection Log", systemImage: "text.alignleft")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.dsSecondary)
    }

    private var helpButton: some View {
        Button { showingGuide = true } label: {
            Label("Connection Help & Requirements", systemImage: "questionmark.circle")
                .font(DSFont.subhead.weight(.semibold))
                .foregroundStyle(DSColor.signalText)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, DSSpacing.s)
        }
        .buttonStyle(DSPlainPressStyle())
    }
}

/// A notice on the Camera tab: a framed title with its symbol, and text or keys under it. The
/// symbol's shape carries the kind of notice; color stays with the signal.
private struct CameraNotice<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            Label(title, systemImage: systemImage)
                .font(DSFont.headline)
                .foregroundStyle(DSColor.textPrimary)
            content
                .font(DSFont.subhead)
                .foregroundStyle(DSColor.textSecondary)
        }
        .padding(DSSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsArchiveFrame()
    }
}
