import SwiftUI
import UIKit

/// The rolling history `CameraLog` keeps of every discover/open/keepalive/
/// suspend/recovery/close event (see `CameraLog.swift`), laid out like `CameraPropertyReportView`:
/// the report, then Copy and Share.
///
/// Unlike that screen, this one has to work **while disconnected** — a failed or flaky connect is
/// exactly the moment it's needed, and without it a report of "it says No camera detected" leaves
/// no artifact to look at afterward.
struct ConnectionLogView: View {
    @Environment(\.dismiss) private var dismiss

    private var entries: [AppLog.Entry] { AppLog.entries(in: .camera) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if entries.isEmpty {
                    Text("Nothing logged yet. Try Connect, or reproduce the issue, then come back here.")
                        .font(.subheadline)
                        .foregroundStyle(DSColor.textSecondary)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .themedCard(cornerRadius: 16)
                } else {
                    logCard
                    exportButtons
                }
            }
            .padding(18)
        }
        .background(DSColor.background.ignoresSafeArea())
        .navigationTitle("Connection Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                // Screen only: the on-disk log a bug report reads (`AppLog.currentLaunchText`) is
                // untouched, so clearing here cannot strip a connect sequence out of a report.
                Button("Clear") { AppLog.clear(.camera) }
                    .disabled(entries.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
        }
    }

    private var header: some View {
        Text("Every connect, disconnect, keepalive, and recovery event since the app launched — newest last. Copy or share this when reporting a connection problem.")
            .font(.subheadline)
            .foregroundStyle(DSColor.textSecondary)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .themedCard(cornerRadius: 16)
    }

    private var logCard: some View {
        VStack(spacing: 0) {
            ForEach(entries) { entry in
                if entry.id != entries.first?.id {
                    Rectangle().fill(DSColor.separator).frame(height: 1)
                }
                row(entry)
            }
        }
        .themedCard(cornerRadius: 16)
    }

    private func row(_ entry: AppLog.Entry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(Self.timeFormatter.string(from: entry.timestamp))
                .font(.caption2.monospaced())
                .foregroundStyle(DSColor.textSecondary)
            Text(entry.message)
                .font(.caption.monospaced())
                .foregroundStyle(entry.isError ? Theme.warning : DSColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    // MARK: Export

    private var exportButtons: some View {
        CopyShareButtons(copyTitle: "Copy Log", text: AppLog.reportText(in: .camera))
    }
}
