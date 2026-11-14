import SwiftUI
import UniformTypeIdentifiers

/// Which card the photo import opens with.
enum PhotoImportRequest: String, Identifiable {
    case camera, demo

    var id: String { rawValue }

    @MainActor
    func makeSource() -> PhotoSource {
        switch self {
        case .camera: return CameraCardSource.camera()
        case .demo: return DemoPhotoSource()
        }
    }
}

/// Import photos from the camera's card: the card as a contact sheet by day, a destination, and
/// one button. The first screen built on the design system (`docs/fork/design-system.md`).
struct PhotoImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CameraServices.self) private var camera
    @State private var model: PhotoImportModel
    @State private var choosingFolder = false
    @State private var rememberedFolder = PhotoImportFolderBookmark.load()
    @State private var editingClock = false
    @State private var choosingDays = false
    @State private var dayRange = (from: Date.now, to: Date.now)

    init(source: PhotoSource) {
        _model = State(initialValue: PhotoImportModel(source: source))
    }

    var body: some View {
        content
            .background(DSColor.background.ignoresSafeArea())
            .tint(DSColor.signal)
            .navigationTitle("Import Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                // All or none of what is shown: the filters above narrow it to a day or two first.
                if model.phase == .ready, !model.visibleFrames.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        if PhotoImportHeader.selectsAll(selected: model.selectedFrames.count, shown: model.visibleFrames.count) {
                            Button("All") { model.selectAll() }
                                .accessibilityLabel("Select All Shown")
                        } else {
                            Button("None") { model.selectNone() }
                                .accessibilityLabel("Select None")
                        }
                    }
                }
            }
            .interactiveDismissDisabled(model.isImporting)
            .task { await model.open(recipeSessionActive: camera.session.isConnected) }
            .onDisappear { Task { await model.close() } }
            .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
                guard case .success(let url) = result else { return }
                PhotoImportFolderBookmark.save(url)
                rememberedFolder = url
                model.destination = .folder(url)
            }
            .sheet(isPresented: $editingClock, onDismiss: { CameraClockOffset.save(model.clockOffset) }) {
                NavigationStack { CameraClockOffsetView(offset: $model.clockOffset) }
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $choosingDays) { dayRangeSheet }
            .alert("Import Finished", isPresented: summaryIsPresented) {
                Button("OK") { model.acknowledgeSummary() }
            } message: {
                Text(summaryText)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .opening(let progress):
            VStack(spacing: DSSpacing.m) {
                if let progress, progress.percent > 0 {
                    ProgressView(value: Double(progress.percent), total: 100)
                        .frame(maxWidth: 280)
                } else {
                    ProgressView()
                }
                Text(Self.openingLabel(progress)).dsMetaMono()
                Text(progress?.note ?? (progress?.looksStuck == true
                     ? "No progress for a while. A full card can take a minute or two before the first photo appears. If nothing changes, unplug the camera, plug it in again and reopen this screen."
                     : "The photos appear as soon as the camera lists the first ones."))
                    .font(DSFont.subhead)
                    .foregroundStyle(DSColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            .padding(DSSpacing.screenMargin)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            failure(message)
        case .ready, .importing, .finished:
            sheet
        }
    }

    // MARK: Failure

    private func failure(_ message: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.l) {
                DSDevicePanel(title: model.sourceName, meta: "No Photos to Show") { EmptyView() }
                Text(message)
                    .font(DSFont.subhead)
                    .foregroundStyle(DSColor.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DSSpacing.l)
                    .dsArchiveFrame()
                Button("Try Again") {
                    Task { await model.open(recipeSessionActive: camera.session.isConnected) }
                }
                .buttonStyle(.dsSecondary)
            }
            .padding(DSSpacing.screenMargin)
        }
    }

    // MARK: Contact sheet

    private var sheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.xl) {
                DSDataFieldRow(fields: PhotoImportHeader.fields(sourceName: model.sourceName,
                                                                isListing: model.isListing,
                                                                loadedCount: model.frames.count,
                                                                hasOlder: model.canLoadMore,
                                                                fileChoice: model.fileChoice,
                                                                selected: model.selectedFrames.count,
                                                                shown: model.visibleFrames.count))
                    .padding(.horizontal, DSSpacing.screenMargin)
                if model.isListing || model.listingProblem != nil {
                    listingStatus
                        .padding(.horizontal, DSSpacing.screenMargin)
                }
                // Tracks are recorded on the phone and stay there, so the Mac has none to use.
                if !ProcessInfo.processInfo.isMacCatalystApp {
                    locationCard
                        .padding(.horizontal, DSSpacing.screenMargin)
                }
                filters
                    .disabled(model.isImporting)
                if model.visibleFrames.isEmpty {
                    Text(emptyText)
                        .font(DSFont.subhead)
                        .foregroundStyle(DSColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DSSpacing.l)
                        .dsArchiveFrame()
                        .padding(.horizontal, DSSpacing.screenMargin)
                }
                ForEach(model.days) { day in
                    VStack(alignment: .leading, spacing: DSSpacing.s) {
                        dayHeader(day)
                        DSContactSheetGrid {
                            ForEach(day.frames) { frame in tile(for: frame) }
                        }
                    }
                    .padding(.horizontal, DSSpacing.screenMargin)
                }
                if model.canLoadMore {
                    loadOlderFooter
                        .padding(.horizontal, DSSpacing.screenMargin)
                }
            }
            .padding(.vertical, DSSpacing.l)
        }
        .safeAreaInset(edge: .bottom) { actionBar }
    }

    // MARK: Older photos

    /// At the end of the sheet: reaching it reads the next portion of older photos.
    private var loadOlderFooter: some View {
        VStack(spacing: DSSpacing.s) {
            if model.isLoadingMore {
                ProgressView(value: Double(model.listingProgress?.percent ?? 0), total: 100)
                Text("Loading older photos").dsMetaMono()
            } else {
                Button("Load Older Photos") { model.loadOlder() }
                    .buttonStyle(.dsSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DSSpacing.s)
        .onAppear { model.loadOlder() }
    }

    // MARK: Listing in the background

    @ViewBuilder
    private var listingStatus: some View {
        if let problem = model.listingProblem {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                DSTag(text: "Card only partly read", systemImage: "exclamationmark.triangle")
                Text(problem).font(DSFont.subhead).foregroundStyle(DSColor.textSecondary)
            }
        } else {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                DSTag(text: Self.listingLabel(model.listingProgress), systemImage: "arrow.down.circle")
                Text("You can already import what is shown; the rest of the card is still being read.")
                    .font(DSFont.subhead)
                    .foregroundStyle(DSColor.textSecondary)
            }
        }
    }

    /// "Still reading the card   34%".
    static func listingLabel(_ progress: CatalogProgress?) -> String {
        guard let progress, progress.percent > 0 else { return "Still reading the card" }
        return "Still reading the card   \(progress.percent)%"
    }

    // MARK: Filters

    private var filters: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            filterRow("Files") {
                ForEach(ImportFileChoice.allCases) { choice in
                    DSTextKey(label: choice.label, isOn: model.fileChoice == choice) { model.setFileChoice(choice) }
                }
            }
            filterRow("Period") {
                DSTextKey(label: "All Dates", isOn: model.period == .all) { model.setPeriod(.all) }
                DSTextKey(label: "Today", isOn: model.period == .today) { model.setPeriod(.today) }
                DSTextKey(label: "7 Days", isOn: model.period == .lastWeek) { model.setPeriod(.lastWeek) }
                DSTextKey(label: Self.daysLabel(model.period) ?? "Choose Days…", isOn: Self.daysLabel(model.period) != nil) {
                    let bounds = model.dateBounds
                    if case .days(let from, let to) = model.period { dayRange = (from, to) }
                    else { dayRange = (bounds?.upperBound ?? .now, bounds?.upperBound ?? .now) }
                    choosingDays = true
                }
            }
            filterRow("Show") {
                DSTextKey(label: "New  \(model.newFrames.count)", isOn: model.showsOnlyNew) { model.setShowsOnlyNew(true) }
                DSTextKey(label: "All  \(model.eligibleFrames.count)", isOn: !model.showsOnlyNew) { model.setShowsOnlyNew(false) }
            }
        }
    }

    private func filterRow<Chips: View>(_ title: String, @ViewBuilder chips: () -> Chips) -> some View {
        DSKeyRow {
            Text(title).dsMetaMono().frame(minWidth: 52, alignment: .leading)
            chips()
        }
    }

    private var emptyText: String {
        if model.frames.allSatisfy({ model.isAlreadyImported($0) || $0.files(for: model.fileChoice).isEmpty }) {
            return "Everything on this card has been imported as \(model.fileChoice.label)."
        }
        return model.showsOnlyNew ? "Nothing new for these days and files." : "No photos for these days and files."
    }

    /// The day and its frame range on one line, the day's own select key under it on the right, so
    /// a long weekday and a four-digit range never crowd the key.
    private func dayHeader(_ day: ImportDay) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            DSContactSheetDayHeader(title: Self.heading(for: day.day),
                                    frameRange: PhotoImportHeader.frameRange(day.frames.map(\.frameNumber)))
            Button(model.isSelected(day) ? "Deselect Day" : "Select Day  \(day.frames.count)") { model.toggle(day) }
                .font(DSFont.subhead.weight(.semibold))
                .foregroundStyle(DSColor.signalText)
                .frame(minHeight: DSSize.touchTarget)
                .disabled(model.isImporting)
        }
        .padding(.horizontal, DSSpacing.xs)
    }

    private var dayRangeSheet: some View {
        NavigationStack {
            Form {
                let bounds = model.dateBounds ?? (Date.distantPast...Date.now)
                DatePicker("From", selection: $dayRange.from, in: bounds.lowerBound...max(bounds.upperBound, dayRange.to),
                           displayedComponents: .date)
                DatePicker("To", selection: $dayRange.to, in: min(bounds.lowerBound, dayRange.from)...max(bounds.upperBound, .now),
                           displayedComponents: .date)
            }
            .navigationTitle("Choose Days")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { choosingDays = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Show") {
                        model.setPeriod(.days(from: dayRange.from, to: dayRange.to))
                        choosingDays = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    /// "13 Nov", "12 Nov – 15 Nov" for a chosen period; nil for the others.
    static func daysLabel(_ period: ImportPeriod, calendar: Calendar = .current) -> String? {
        guard case .days(let from, let to) = period else { return nil }
        let style = Date.FormatStyle.dateTime.day().month(.abbreviated)
        let first = min(from, to), last = max(from, to)
        return calendar.isDate(first, inSameDayAs: last)
            ? first.formatted(style) : "\(first.formatted(style)) – \(last.formatted(style))"
    }

    /// "Reading the card", "Reading the card   42%   1,234 Files".
    static func openingLabel(_ progress: CatalogProgress?) -> String {
        guard let progress, progress.percent > 0 || progress.files > 0 else { return "Reading the card" }
        var parts = ["Reading the card", "\(progress.percent)%"]
        if progress.files > 0 { parts.append("\(progress.files.formatted()) Files") }
        return parts.joined(separator: "   ")
    }

    // MARK: Location

    private var locationCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            DSDevicePanel(title: "Location from Track", meta: locationMeta) {
                Toggle("Add Location", isOn: $model.addsLocation)
                    .toggleStyle(.dsHardwareSwitchOnly)
                    .disabled(model.matcher.isEmpty || model.isImporting)
            }
            if model.addsLocation {
                HStack(spacing: DSSpacing.s) {
                    Button { editingClock = true } label: {
                        DSTag(text: "Camera Clock  \(CameraClockOffset.label(model.clockOffset))", systemImage: "clock")
                    }
                    .buttonStyle(DSPlainPressStyle())
                    .disabled(model.isImporting)
                    if !model.framesFromTheFuture().isEmpty {
                        DSTag(text: "Clock Ahead?", systemImage: "exclamationmark.triangle")
                    }
                }
            }
        }
    }

    private var locationMeta: String {
        if model.matcher.isEmpty { return "No Track Recorded" }
        guard model.addsLocation else { return "Off" }
        let selected = model.selectedFrames
        let located = selected.filter { model.previewPosition(of: $0) != nil }.count
        return "\(located) of \(selected.count) Located"
    }

    private func tile(for frame: ImportFrame) -> some View {
        Button { model.toggle(frame) } label: {
            DSContactSheetTile(image: model.thumbnails[frame.id].map { Image(decorative: $0, scale: 1) },
                               frameNumber: frame.frameNumber,
                               simulation: model.simulations[frame.id],
                               format: frame.formatLabel,
                               isSelected: model.selection.contains(frame.id))
        }
        .buttonStyle(.plain)
        .disabled(model.isImporting)
        .onAppear { model.loadThumbnail(for: frame) }
    }

    /// "Today   November 13", "Yesterday   November 12", "Wednesday   November 11".
    static func heading(for day: Date?, calendar: Calendar = .current) -> String {
        guard let day else { return "No Date" }
        let date = day.formatted(.dateTime.month(.wide).day())
        if calendar.isDateInToday(day) { return "Today   \(date)" }
        if calendar.isDateInYesterday(day) { return "Yesterday   \(date)" }
        return "\(day.formatted(.dateTime.weekday(.wide)))   \(date)"
    }

    // MARK: Action bar

    private var actionBar: some View {
        DSFloatingActionBar {
            if case .importing(let done, let total) = model.phase {
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                HStack {
                    Text("Importing   \(done) of \(total)").dsMetaMono()
                    Spacer()
                }
                Button("Cancel") { model.cancelImport() }.buttonStyle(.dsSecondary)
            } else {
                destinationRow
                let count = model.selectedFrames.count
                Button(count == 0 ? "Select Photos to Import" : "Import \(count) Photo\(count == 1 ? "" : "s")") {
                    model.startImport()
                }
                .buttonStyle(.dsPrimary)
                .disabled(count == 0)
            }
        }
    }

    private var destinationRow: some View {
        HStack {
            Text("Destination").dsMetaMono()
            Spacer()
            Menu {
                Button { model.destination = .photoLibrary } label: {
                    Label("Photo Library", systemImage: "photo.on.rectangle")
                }
                if let rememberedFolder {
                    Button { model.destination = .folder(rememberedFolder) } label: {
                        Label(rememberedFolder.lastPathComponent, systemImage: "folder")
                    }
                }
                Button { choosingFolder = true } label: {
                    Label("Choose Folder…", systemImage: "folder.badge.plus")
                }
            } label: {
                HStack(spacing: DSSpacing.xs) {
                    Text(model.destination.label).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.semibold))
                }
                .font(DSFont.subhead)
                .foregroundStyle(DSColor.textPrimary)
                .frame(minHeight: DSSize.touchTarget)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Destination, \(model.destination.label)")
        }
    }

    // MARK: Summary

    private var summaryIsPresented: Binding<Bool> {
        Binding(get: { if case .finished = model.phase { return true } else { return false } },
                set: { if !$0 { model.acknowledgeSummary() } })
    }

    private var summaryText: String {
        guard case .finished(let summary) = model.phase else { return "" }
        return Self.text(for: summary, destination: model.destination)
    }

    static func text(for summary: PhotoImportModel.Summary, destination: PhotoImportDestination) -> String {
        var lines = ["\(summary.imported) photo\(summary.imported == 1 ? "" : "s") copied to \(destination.label). Nothing on the card was changed."]
        if let located = summary.located {
            lines.append(located == summary.imported
                         ? "Every one has its location."
                         : "\(located) of \(summary.imported) have their location. The rest were taken when no track was recording, or the camera clock is off.")
        }
        if summary.cancelled { lines.append("The import was cancelled before it finished.") }
        if !summary.failed.isEmpty {
            lines.append("\(summary.failed.count) couldn't be copied:")
            lines.append(contentsOf: summary.failed.prefix(5))
            if summary.failed.count > 5 { lines.append("and \(summary.failed.count - 5) more.") }
        }
        return lines.joined(separator: "\n")
    }
}

#Preview {
    NavigationStack { PhotoImportView(source: DemoPhotoSource()) }
        .environment(CameraServices())
}
