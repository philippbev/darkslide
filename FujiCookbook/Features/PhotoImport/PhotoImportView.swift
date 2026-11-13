import SwiftUI
import UniformTypeIdentifiers

/// Which card the photo import opens with.
enum PhotoImportRequest: String, Identifiable {
    case camera, demo

    var id: String { rawValue }

    @MainActor
    func makeSource() -> PhotoSource {
        switch self {
        case .camera: return CameraPhotoSource()
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

    init(source: PhotoSource) {
        _model = State(initialValue: PhotoImportModel(source: source))
    }

    var body: some View {
        content
            .background(DSColor.background.ignoresSafeArea())
            .tint(DSColor.accent)
            .navigationTitle("Import Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                if model.phase == .ready, !model.visibleFrames.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        let allSelected = model.selectedFrames.count == model.visibleFrames.count
                        Button(allSelected ? "Select None" : "Select All") {
                            if allSelected { model.selectNone() } else { model.selectAll() }
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
            .alert("Import Finished", isPresented: summaryIsPresented) {
                Button("OK") { model.acknowledgeSummary() }
            } message: {
                Text(summaryText)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .opening:
            VStack(spacing: DSSpacing.m) {
                ProgressView()
                Text("Reading the card").dsLabelMono()
            }
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
                DSStatusCard(systemImage: "camera", title: model.sourceName, meta: "No Photos to Show") { EmptyView() }
                Text(message)
                    .font(DSFont.subhead)
                    .foregroundStyle(DSColor.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DSSpacing.l)
                    .dsCard()
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
                DSStatusCard(systemImage: "camera", title: model.sourceName, meta: cardMeta) { DSStatusDot() }
                    .padding(.horizontal, DSSpacing.screenMargin)
                // Tracks are recorded on the phone and stay there, so the Mac has none to use.
                if !ProcessInfo.processInfo.isMacCatalystApp {
                    locationCard
                        .padding(.horizontal, DSSpacing.screenMargin)
                }
                DSChipRow {
                    DSChip(label: "New  \(model.newFrames.count)", isSelected: model.showsOnlyNew) {
                        model.setShowsOnlyNew(true)
                    }
                    DSChip(label: "All  \(model.frames.count)", isSelected: !model.showsOnlyNew) {
                        model.setShowsOnlyNew(false)
                    }
                }
                .disabled(model.isImporting)
                if model.visibleFrames.isEmpty {
                    Text("Everything on this card has been imported.")
                        .font(DSFont.subhead)
                        .foregroundStyle(DSColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DSSpacing.l)
                        .dsCard()
                        .padding(.horizontal, DSSpacing.screenMargin)
                }
                ForEach(model.days) { day in
                    VStack(alignment: .leading, spacing: DSSpacing.s) {
                        Text(Self.heading(for: day.day))
                            .dsLabelMono()
                            .padding(.horizontal, DSSpacing.xs)
                            .accessibilityAddTraits(.isHeader)
                        LazyVGrid(columns: DSContactSheet.columns, spacing: DSContactSheet.spacing) {
                            ForEach(day.frames) { frame in tile(for: frame) }
                        }
                    }
                    .padding(.horizontal, DSSpacing.screenMargin)
                }
            }
            .padding(.vertical, DSSpacing.l)
        }
        .safeAreaInset(edge: .bottom) { actionBar }
    }

    // MARK: Location

    private var locationCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            DSStatusCard(systemImage: "location", title: "Location", meta: locationMeta, iconTint: .accent) {
                Toggle("Add Location", isOn: $model.addsLocation)
                    .labelsHidden()
                    .disabled(model.matcher.isEmpty || model.isImporting)
            }
            if model.addsLocation {
                HStack(spacing: DSSpacing.s) {
                    Button { editingClock = true } label: {
                        DSHintPill(text: "Camera Clock  \(CameraClockOffset.label(model.clockOffset))", systemImage: "clock")
                    }
                    .buttonStyle(DSPlainPressStyle())
                    .disabled(model.isImporting)
                    if !model.framesFromTheFuture().isEmpty {
                        DSHintPill(text: "Clock Ahead?", systemImage: "exclamationmark.triangle")
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

    private var cardMeta: String {
        let count = model.frames.count
        return "USB   Card Reader   \(count) Photo\(count == 1 ? "" : "s")"
    }

    private func tile(for frame: ImportFrame) -> some View {
        Button { model.toggle(frame) } label: {
            DSContactSheetTile(image: model.thumbnails[frame.id].map { Image(decorative: $0, scale: 1) },
                               frameNumber: frame.frameNumber,
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
        DSActionBar {
            if case .importing(let done, let total) = model.phase {
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                HStack {
                    Text("Importing   \(done) of \(total)").dsLabelMono()
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
            Text("Destination").dsLabelMono()
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
