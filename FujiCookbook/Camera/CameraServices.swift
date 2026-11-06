import Foundation
import Observation

/// The camera services for one app run, wired together once and put into the SwiftUI environment.
/// Views and the guided test runner reach the service they need through it: the session for state,
/// the connector to connect and disconnect, the reader and writer for slots, the diagnostics, the
/// Kitchen's conversion service, and the recorder for the compatibility report.
///
/// `@Observable` only because `.environment(_:)` needs an observable object; every property is a
/// `let`, and the state views watch lives on the services.
@MainActor
@Observable
final class CameraServices {
    let session: CameraSession
    let reports: CompatibilityReportRecorder
    let gate: CameraOperationGate
    let slotReader: SlotReader
    let slotWriter: SlotWriter
    let diagnostics: CameraDiagnostics
    let conversion: RawConversionService
    let connector: CameraConnector

    /// `discovery` finds the camera a hardware connect opens. It is a closure so the app's
    /// ImageCaptureCore browser is created on the first hardware connect rather than at launch.
    init(discovery: @escaping @MainActor () -> CameraDiscovery = { CameraDeviceBrowser.shared }) {
        let session = CameraSession()
        let reports = CompatibilityReportRecorder()
        let gate = CameraOperationGate()
        let slotReader = SlotReader(session: session, reports: reports, gate: gate)
        let slotWriter = SlotWriter(session: session, reports: reports, gate: gate, slotReader: slotReader)
        let conversion = RawConversionService(session: session, reports: reports, gate: gate)
        self.session = session
        self.reports = reports
        self.gate = gate
        self.slotReader = slotReader
        self.slotWriter = slotWriter
        self.diagnostics = CameraDiagnostics(session: session, reports: reports, gate: gate)
        self.conversion = conversion
        self.connector = CameraConnector(session: session, reports: reports, gate: gate, slotReader: slotReader,
                                         slotWriter: slotWriter, conversion: conversion, discovery: discovery)
    }
}
