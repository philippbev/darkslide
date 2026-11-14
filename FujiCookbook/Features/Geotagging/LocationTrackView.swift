import SwiftUI

/// Record a track while taking pictures, see the tracks kept, and say how far the camera's clock is
/// off. An import uses every track here to place the photos.
struct LocationTrackView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(DiagnosticMode.key) private var diagnosticMode = false
    @State private var recorder = LocationRecorder.shared
    @State private var tracks: [LocationTrack] = []
    @State private var clockOffset = CameraClockOffset.load()
    @State private var editingClock = false

    private let store = LocationTrackStore.standard

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.xl) {
                recordingCard
                if let error = recorder.lastError {
                    DSTag(text: "Location unavailable", systemImage: "exclamationmark.triangle")
                    Text(error).font(DSFont.subhead).foregroundStyle(DSColor.textSecondary)
                }
                clockCard
                trackList
                Text("Tracks stay on this device. Importing photos from the camera adds the position recorded at the time each one was taken: into JPEG and HEIF files, and as an XMP sidecar beside a RAF. Nothing on the camera's card is changed.")
                    .font(DSFont.subhead)
                    .foregroundStyle(DSColor.textSecondary)
            }
            .padding(DSSpacing.screenMargin)
        }
        .background(DSColor.background.ignoresSafeArea())
        .tint(DSColor.signal)
        .navigationTitle("Location Track")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } }
        }
        .safeAreaInset(edge: .bottom) {
            DSFloatingActionBar {
                if recorder.isRecording {
                    Button("Stop Recording") { recorder.stop(); reload() }.buttonStyle(.dsSecondary)
                } else {
                    Button("Start Recording") { recorder.start() }.buttonStyle(.dsPrimary)
                }
            }
        }
        .sheet(isPresented: $editingClock, onDismiss: { CameraClockOffset.save(clockOffset) }) {
            NavigationStack { CameraClockOffsetView(offset: $clockOffset) }
                .presentationDetents([.medium])
        }
        .onAppear(perform: reload)
        .onChange(of: recorder.isRecording) { reload() }
    }

    private var recordingCard: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            DSDevicePanel(title: recorder.isRecording ? "Recording" : "Not Recording",
                          meta: recordingMeta(now: context.date)) {
                if recorder.isRecording { DSLEDIndicator(label: "Rec", isOn: true, color: .signal) }
            }
        }
    }

    private func recordingMeta(now: Date) -> String {
        guard let track = recorder.current else { return "Start before you go out" }
        let points = track.points.count
        return "\(Self.duration(now.timeIntervalSince(track.startedAt)))   \(points) Point\(points == 1 ? "" : "s")"
    }

    private var clockCard: some View {
        Button { editingClock = true } label: {
            DSDevicePanel(title: "Camera Clock", meta: CameraClockOffset.label(clockOffset)) {
                Image(systemName: "chevron.right").foregroundStyle(DSColor.textSecondary)
            }
        }
        .buttonStyle(DSPlainPressStyle())
    }

    @ViewBuilder
    private var trackList: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            Text("Tracks").dsMetaMono().padding(.horizontal, DSSpacing.xs).accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                if tracks.isEmpty {
                    Text("No tracks yet.")
                        .font(DSFont.subhead)
                        .foregroundStyle(DSColor.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: DSSize.touchTarget, alignment: .leading)
                        .padding(.horizontal, DSSpacing.l)
                }
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    if index > 0 { DSSeparator().padding(.leading, DSSpacing.l) }
                    trackRow(track)
                }
                if diagnosticMode {
                    if !tracks.isEmpty { DSSeparator() }
                    Button("Add Demo Tracks for the Demo Card") {
                        LocationTrack.demoTracks().forEach { try? store.save($0) }
                        reload()
                    }
                    .font(DSFont.subhead)
                    .frame(maxWidth: .infinity, minHeight: DSSize.touchTarget, alignment: .leading)
                    .padding(.horizontal, DSSpacing.l)
                }
            }
            .dsArchiveFrame()
        }
    }

    private func trackRow(_ track: LocationTrack) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text(track.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(DSFont.subhead)
                    .foregroundStyle(DSColor.textPrimary)
                Text("\(Self.duration(track.duration))   \(track.points.count) Points").dsMetaMono()
            }
            Spacer()
            if track.endedAt != nil {
                Button(role: .destructive) {
                    store.delete(track.id)
                    reload()
                } label: {
                    Image(systemName: "trash").frame(width: DSSize.touchTarget, height: DSSize.touchTarget)
                }
                .accessibilityLabel("Delete track")
            }
        }
        .padding(.leading, DSSpacing.l)
        .padding(.trailing, DSSpacing.xs)
        .frame(minHeight: DSSize.touchTarget + DSSpacing.m)
    }

    /// The track being recorded is shown in the card above, live; the list holds the finished ones.
    private func reload() { tracks = store.all().filter { $0.id != recorder.current?.id } }

    /// "2 h 14 min", "12 min", "40 s".
    static func duration(_ interval: TimeInterval) -> String {
        let seconds = max(Int(interval), 0)
        if seconds < 60 { return "\(seconds) s" }
        let minutes = seconds / 60
        return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }
}

/// Set how far the camera's clock is off, in hours and minutes.
struct CameraClockOffsetView: View {
    @Binding var offset: TimeInterval
    @Environment(\.dismiss) private var dismiss

    private var totalMinutes: Binding<Int> {
        Binding(get: { Int((offset / 60).rounded()) }, set: { offset = TimeInterval($0 * 60) })
    }

    var body: some View {
        Form {
            Section {
                Stepper(value: Binding(get: { totalMinutes.wrappedValue / 60 },
                                       set: { totalMinutes.wrappedValue = $0 * 60 + totalMinutes.wrappedValue % 60 }),
                        in: -14...14) {
                    LabeledContent("Hours", value: DSValueFormat.signed(totalMinutes.wrappedValue / 60))
                }
                Stepper(value: totalMinutes, in: -14 * 60 - 59...14 * 60 + 59) {
                    LabeledContent("Minutes", value: DSValueFormat.signed(totalMinutes.wrappedValue % 60))
                }
            } header: {
                Text(CameraClockOffset.label(offset))
            } footer: {
                Text("Positive when the camera's clock is ahead of the iPhone's. A camera left on home time while travelling is off by whole hours. To check, photograph the iPhone's clock and compare the time the photo shows.")
            }
            Section {
                Button("Reset to In Sync") { offset = 0 }.disabled(offset == 0)
            }
        }
        .navigationTitle("Camera Clock")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}

extension LocationTrack {
    /// Two walks on Pico in the Azores, at the times the demo card's photos are dated: yesterday
    /// afternoon and this morning. Only for the diagnostic tools.
    static func demoTracks(now: Date = .now, calendar: Calendar = .current) -> [LocationTrack] {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        func walk(from start: Date, minutes: Int, origin: (Double, Double)) -> LocationTrack {
            let points = (0...(minutes * 2)).map { step -> GeoPoint in
                let t = Double(step)
                return GeoPoint(timestamp: start.addingTimeInterval(t * 30),
                                latitude: origin.0 + t * 0.00018,
                                longitude: origin.1 + sin(t / 9) * 0.0012 + t * 0.0001,
                                altitude: 40 + t * 0.8, horizontalAccuracy: 8)
            }
            return LocationTrack(startedAt: start, endedAt: points.last?.timestamp, points: points)
        }
        return [walk(from: yesterday.addingTimeInterval(14.75 * 3600), minutes: 60, origin: (38.5262, -28.5305)),
                walk(from: today.addingTimeInterval(8.75 * 3600), minutes: 90, origin: (38.4636, -28.3256))]
    }
}
