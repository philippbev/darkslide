import Foundation

// Human-readable reports are kept separate from their Codable data and capture logic.
extension CameraCompatibilityReport {
    // MARK: Text rendering

    /// The same facts as the JSON, laid out for a person. This is what the tester reads before
    /// sending, and what lands in "Report a Problem".
    var textRendering: String {
        var lines: [String] = ["Darkslide — camera compatibility report v\(reportVersion)"]
        let f = ISO8601DateFormatter()
        lines.append("Collection  began \(f.string(from: generatedAt)) · updated \(f.string(from: updatedAt))  (app \(app.version) (\(app.build)) \(app.channel), iOS \(host.systemVersion), \(host.deviceIdentifier))")
        lines.append("")
        lines.append("Camera      \(camera.productName) via \(camera.transport)")
        lines.append("Identified  \(camera.identifiedModelID ?? camera.productName) (\(camera.identification))")
        if let verification = camera.verification {
            lines.append("Registry    write-support evidence: \(verification) — existing app metadata, not a verdict from this test")
        }
        if let fw = camera.firmwareVersion { lines.append("Firmware    \(fw)") }
        // What the app decided about writing, beside the registry's evidence it used to rest on.
        if let access = camera.writeAccess { lines.append("Writes      \(access)") }
        if let v = camera.usbVendorID, let p = camera.usbProductID { lines.append("USB         \(v):\(p)") }
        if let s = camera.serialHash { lines.append(Self.serialHashLine(s, scheme: camera.serialHashScheme)) }
        lines.append("")

        if let info = deviceInfo {
            if let error = info.error {
                lines.append("DeviceInfo  unavailable — \(error)")
            } else {
                lines.append("DeviceInfo  \(info.manufacturer ?? "") \(info.model ?? "") fw \(info.deviceVersion ?? "") · PTP \(info.standardVersion ?? 0) · ext \(info.vendorExtensionID ?? "") v\(info.vendorExtensionVersion ?? 0) \"\(info.vendorExtensionDesc ?? "")\" · \(info.rawLength ?? 0) bytes")
                func spell(_ r: CodeRecord) -> String { r.name.map { "\(r.code) \($0)" } ?? r.code }
                lines.append("  operations (\(info.operationsSupported.count)): "
                             + info.operationsSupported.map(spell).joined(separator: ", "))
                lines.append("  properties (\(info.devicePropertiesSupported.count)): "
                             + info.devicePropertiesSupported.map(spell).joined(separator: ", "))
                lines.append("  events (\(info.eventsSupported.count)): \(info.eventsSupported.joined(separator: ", "))")
                lines.append("  formats: capture \(info.captureFormats.joined(separator: ", ")) · image \(info.imageFormats.joined(separator: ", "))")
            }
            lines.append("")
        }

        var slotHead = "Slots       assumed \(slots.assumedSlotCount.map(String.init) ?? "—") · documented \(slots.documentedSlotCount.map(String.init) ?? "—") · probed \(slots.probedSlotCount.map(String.init) ?? "—")"
        if let selector = slots.selectorBeforeProbe { slotHead += " · selector before C\(selector)" }
        if let before = slots.selectorBeforeRead {
            slotHead += " · was on C\(before)"
            switch slots.selectorRestored {
            case true: slotHead += ", restored"
            case false: slotHead += ", NOT restored"
            case nil: slotHead += ", restore not attempted"
            }
        }
        if let selectorRead = slots.selectorRead { slotHead += " · selector \(selectorRead)" }
        if let walkResult = slots.walkResult { slotHead += " · walk \(walkResult)" }
        if let readAt = slots.readAt { slotHead += " · read \(f.string(from: readAt))" }
        lines.append(slotHead)
        for disagreement in slots.registryDisagreements ?? [] {
            lines.append("  ! registry disagrees on \(disagreement.field): registry \(disagreement.registry), body \(disagreement.observed)")
        }
        lines.append("  Latest camera state: these reads may follow writing or restoration. Original test reads are retained in each test when available.")
        for read in slots.reads {
            var head = "  C\(read.slot)  "
            if !read.selected { head += "select failed: \(read.selectError ?? "?")" }
            else {
                head += read.occupied == true ? "occupied" : "empty"
                if let name = read.name { head += " \"\(name)\"" }
                let ok = read.properties.filter { $0.value != nil }.count
                let failed = read.properties.filter { $0.error != nil }
                head += " · \(ok) properties read"
                if !failed.isEmpty { head += " · \(failed.count) failed: " + failed.map { "\($0.code) \($0.responseCode ?? $0.error ?? "")" }.joined(separator: ", ") }
            }
            lines.append(head)
            for p in read.properties where p.value != nil {
                lines.append("       \(p.code) \(p.name ?? "")  \(p.value ?? "")\(Self.reading(p.decoded))")
            }
            // `!` rather than an indented continuation: this is the line a reader is scanning for,
            // and it has to survive being read in a mail client's monospace-ish font.
            for d in read.divergences ?? [] {
                // A camera-only value (Custom white balance) is information, not a finding, so it
                // doesn't wear the marker a reader scans for.
                let why: String
                let marker: String
                switch d.kind {
                case "outOfRange":
                    (marker, why) = ("!", "outside \(d.expectedRange ?? "the expected range"), kept as read")
                case "cameraOnly":
                    (marker, why) = ("·", "a setting on the camera itself, not a recipe value; left unset")
                default:
                    (marker, why) = ("!", "not a value this app recognizes; left unread")
                }
                lines.append("     \(marker) \(d.code) \(d.name) = \(d.value) (\(d.decoded)) — " + why)
            }
        }
        if !unsupportedPropertyCodes.isEmpty {
            lines.append("  answered 0x200A: \(unsupportedPropertyCodes.joined(separator: ", "))")
        }
        lines.append("")

        if let sweep = propertySweep {
            lines.append("Sweep       \(sweep.readOnly ? "read-only" : "with slot select") · selector \(sweep.slot.map(String.init) ?? "—") · \(sweep.entries.count) properties"
                         + (sweep.capturedAt.map { " · captured \(f.string(from: $0))" } ?? " · capture time not recorded"))
            if let id = sweep.evidenceID { lines.append("  evidence ID: \(id)") }
            for e in sweep.entries {
                var line = "  \(e.code) \(e.name ?? "")"
                line += "  holds: " + (e.value.map { v in v + Self.reading(e.decoded) } ?? (e.valueResponseCode ?? e.valueError ?? "—"))
                if let d = e.descriptor {
                    var accepts = d.form
                    if let en = d.enumeration { accepts = "enum \(en)" }
                    if let lo = d.rangeMin, let hi = d.rangeMax, let st = d.rangeStep { accepts = "range \(lo)…\(hi) step \(st)" }
                    line += "  accepts: \(accepts) · \(d.dataType) · \(d.writable ? "rw" : "ro")"
                } else if let err = e.descriptorError {
                    line += "  descriptor: \(err)"
                }
                lines.append(line)
            }
            lines.append("")
        }

        if !notes.isEmpty {
            lines.append("Notes")
            for n in notes { lines.append("  · \(n)") }
            lines.append("")
        }

        // Directly after the notes, and ahead of the pushes, develops and trace. What a
        // person observed is both the scarcest thing in this document and the only thing that can
        // contradict the rest of it, so it should not be somewhere a reader scrolls to.
        for test in guidedTests ?? [] {
            lines += Self.render(guidedTest: test, formatter: f,
                                 sweepSlot: propertySweep?.slot)
            lines.append("")
        }

        if let pushes, !pushes.isEmpty {
            lines.append("Pushes      \(pushes.count)" + (pushesDropped.map { " (+\($0) not kept)" } ?? ""))
            for push in pushes {
                if push.baselineOnly == true {
                    let sim = push.fields.first?.wrote ?? "—"
                    lines.append("  C\(push.slot)  \(push.outcome.rawValue)  \(f.string(from: push.at))  (baseline only — film simulation \(sim); the rest was cleared)")
                    continue
                }
                var head = "  C\(push.slot)  \(push.kind ?? "push") \(push.outcome.rawValue)  \(f.string(from: push.at))  \(push.modelID ?? "—") fw \(push.firmwareVersion ?? "—")"
                // Only when it disagrees: on a healthy push this is noise, and on an unhealthy one
                // it is the single most important line in the report.
                if let got = push.selectorReadBack, got != push.slot { head += "  ! selector read back as C\(got)" }
                lines.append(head)
                if let error = push.errorMessage { lines.append("       error: \(error)") }
                if let first = push.firstWrite {
                    var line = "       first write: \(first.property) \(first.outcome)"
                    if let response = first.responseCode { line += " \(response)" }
                    if let read = first.read { line += " has=\(read)" }
                    if let restore = first.restore { line += " · \(restore)" }
                    lines.append(line)
                }
                if !push.clampedFields.isEmpty { lines.append("       clamped: \(push.clampedFields.joined(separator: ", "))") }
                lines.append("       name: " + (push.nameWritten ? "accepted \"\(push.nameApplied ?? "")\"" : "not confirmed")
                             + (push.nameOutcome.map { " [\($0)]" } ?? "")
                             + (push.nameBefore.map { " (was \"\($0)\")" } ?? ""))
                for field in push.fields {
                    var line = "       \(field.code ?? "     ") \(field.name)  \(field.outcome)"
                    if let response = field.responseCode { line += " \(response) \(FujiPTP.responseName(PTPHex.code(from: response) ?? 0) ?? "")" }
                    // `wrote` is on every field, so it always renders; `has=` only means something
                    // for a mismatch, where the read-back disagreed. Printing `has=—` on a written
                    // field would read as "the camera returned nothing", which is the opposite of
                    // what happened.
                    if let wrote = field.wrote { line += " wrote=\(wrote)" }
                    if let read = field.read { line += " has=\(read)" }
                    lines.append(line)
                }
                if let before = push.slotBefore, !before.isEmpty {
                    lines.append("       before: " + before.sorted { $0.key < $1.key }
                        .map { "\($0.key)=\($0.value)" }.joined(separator: " "))
                }
            }
            lines.append("")
        }

        if let connectionFailures, !connectionFailures.isEmpty {
            lines.append("Failed connects  \(connectionFailures.count)")
            for failure in connectionFailures {
                lines.append("  \(f.string(from: failure.at))  \(failure.stage): \(failure.reason)")
                if let name = failure.productName {
                    var line = "       device: \(name)"
                    if let v = failure.usbVendorID, let p = failure.usbProductID { line += " (\(v)/\(p))" }
                    if let id = failure.identification { line += " — \(id)" }
                    lines.append(line)
                }
                if let control = failure.controlAuthorization, let contents = failure.contentsAuthorization {
                    // Printed even when both are authorized: "the permissions were fine" is the
                    // half of the answer that sends the reader back to the cable.
                    lines.append("       permissions: control \(control), contents \(contents)")
                }
            }
            lines.append("")
        }

        if let profileHarvests, !profileHarvests.isEmpty {
            lines.append("Harvests    \(profileHarvests.count)" + (profileHarvestsDropped.map { " (+\($0) not kept)" } ?? ""))
            for h in profileHarvests {
                lines.append("  \(f.string(from: h.at))  \(h.modelID ?? "—") fw \(h.firmwareVersion ?? "—")  RAF \(h.rafBytes) bytes")
                lines.append("       D185 before the upload: \(h.profileBeforeUpload ?? "not read")")
                var upload = "       upload: \(h.uploadOutcome)"
                if let header = h.rafHeader { upload += " (the RAF's header \(header))" }
                if let created = h.uploadCreatedObject {
                    upload += created
                        ? " · appeared as an object" + (h.objectDeleted == true ? ", deleted" : ", NOT deleted")
                        : " · no object appeared"
                }
                lines.append(upload)
                // The profile line is the finding on a new body, exactly as it is for a develop.
                if let length = h.profileLength {
                    var profile = "       profile: \(length) bytes"
                    if let n = h.declaredParams { profile += ", \(n) params" }
                    profile += h.layoutBase.map { String(format: ", base 0x%X", $0) } ?? ", ! layout unresolved"
                    lines.append(profile)
                    if h.layoutBase == nil {
                        if let diagnostic = h.layoutDiagnostic { lines.append("       \(diagnostic)") }
                        if let head = h.profileHead { lines.append("       first bytes:\n" + head.split(separator: "\n").map { "         " + $0 }.joined(separator: "\n")) }
                    }
                } else if let refused = h.profileReadError {
                    lines.append("       profile: refused after the upload — \(refused)")
                }
                if let after = h.profileAfterDelete { lines.append("       D185 after the delete: \(after)") }
                if let reason = h.failureReason { lines.append("       reason: \(reason)") }
            }
            lines.append("")
        }
        if let develops, !develops.isEmpty {
            lines.append("Develops    \(develops.count)" + (developsDropped.map { " (+\($0) not kept)" } ?? ""))
            for cook in develops {
                var head = "  \(cook.succeeded ? "ok" : "failed")  \(f.string(from: cook.at))  \(cook.modelID ?? "—") fw \(cook.firmwareVersion ?? "—")"
                if let sim = cook.filmSimulation { head += "  \(sim)" }
                lines.append(head)
                // The profile line first, because on an unfamiliar body it is the whole finding: a
                // length the record hasn't seen, or a base that never resolved, explains every other
                // line under it.
                var profile = "       profile: "
                profile += cook.profileLength.map { "\($0) bytes" } ?? "not read"
                if let n = cook.declaredParams { profile += ", \(n) params" }
                profile += cook.layoutBase.map { String(format: ", base 0x%X", $0) } ?? ", ! layout unresolved"
                lines.append(profile)
                if let verification = cook.profileVerification {
                    lines.append("       recipe profile: \(verification)")
                } else if let verified = cook.profileVerified {
                    lines.append("       recipe profile: " + (verified ? "confirmed by the camera"
                                                                       : "! NOT confirmed — the JPEG may not match the recipe"))
                }
                for mismatch in cook.mismatches ?? [] { lines.append("         \(mismatch)") }
                if let dr = cook.dynamicRange { lines.append("       dynamic range: \(dr)") }
                if let clamped = cook.clampedFields, !clamped.isEmpty {
                    lines.append("       clamped: \(clamped.joined(separator: ", "))")
                }
                if let bytes = cook.outputBytes { lines.append("       output: \(bytes) bytes") }
                if let validation = cook.outputValidation { lines.append("       output validation: \(validation)") }
                if let cleanup = cook.cleanupOutcome { lines.append("       camera cleanup: \(cleanup)") }
                if let reason = cook.failureReason { lines.append("       failed: \(reason)") }
            }
            lines.append("")
        }

        lines.append("Trace       \(transactions.count) transactions · \(transactionsDropped) omitted by this connection's capture limit")
        if traceScope == "unavailable" {
            lines.append("  Original connection trace unavailable; no whole-test trace is implied.")
        } else {
            lines.append("  Scope: recorded operations on the latest connection, opened \(f.string(from: traceStartedAt ?? generatedAt)). Earlier connections and untraced operations are not included; zero omitted does not mean the whole test was captured.")
        }
        if let connectionID { lines.append("  Connection ID: \(connectionID)") }
        for t in transactions {
            var line = String(format: "  %3d  %@ %@ %@", t.sequence, t.operation, t.operationName ?? "",
                              t.parameters.joined(separator: " "))
            if let out = t.outData { line += " out=\(out)" } else if let out = t.outDataLength { line += " out=\(out)B" }
            if let inLen = t.inDataLength { line += " in=\(inLen)B" }
            if let data = t.inData, !data.isEmpty { line += " \(data)" }
            line += " → " + (t.response.map { r in r + (t.responseName.map { " \($0)" } ?? "") } ?? (t.error ?? "?"))
            line += " \(t.durationMs)ms"
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}


// MARK: - Guided test rendering

extension CameraCompatibilityReport {

    /// Run-local coverage comes from recorded operations and authored settings, never the model
    /// registry or the camera's current/default recipe. A setting supplied to a failed operation
    /// remains an attempted setting, not evidence that the camera supports it.
    static func coverageLines(for test: GuidedTestRecord) -> [String] {
        var lines = ["Coverage      this session's evidence only; completion does not certify every feature of this model"]
        let comparisons = (test.slotComparisons ?? []).filter { $0.checkedAt != nil }
        lines.append("  Read/menu comparison: \(comparisons.count) slots checked by the tester; \(comparisons.filter { $0.verdict == "matches" }.count) matched")
        let trials = test.writePass?.trials ?? []
        if trials.isEmpty { lines.append("  Slot writing: no recorded recipe trial") }
        for trial in trials {
            lines.append("  Slot write \(trial.recipeName ?? trial.recipe) → C\(trial.slot): \(trial.outcome?.rawValue ?? "not recorded")"
                         + (trial.persistence?.settingsState.map { "; restart settings \($0)" } ?? ""))
            if let settings = trial.recipeSettings {
                lines.append("    Authored settings: " + authoredFieldNames(settings).joined(separator: ", "))
            } else { lines.append("    Authored settings snapshot unavailable") }
        }
        let runs = test.kitchenRuns ?? []
        if runs.isEmpty { lines.append("  RAW develop: no run-associated conversion evidence") }
        for run in runs {
            let completion = test.kitchenCompletions?.first { $0.run.id == run.id }
            let cells = completion?.cells ?? []
            let verified = cells.filter { $0.succeeded && $0.profileVerified == true }.count
            let output = cells.filter(\.succeeded).count
            lines.append("  RAW develop \(run.caseID) [\(run.id.uuidString)]: \(output)/\(cells.count) outputs; \(verified) with verified profiles"
                         + (completion == nil ? "; attempt has no completion evidence" : "")
                         + (completion?.saveFailed == true ? "; local image save failed" : ""))
            for recipe in run.recipes {
                lines.append("    \(recipe.name), supplied settings: " + authoredFieldNames(recipe.settings).joined(separator: ", "))
            }
        }
        lines.append("  Slot-writing and RAW-develop evidence are separate; untouched settings and unrun cases remain untested.")
        return lines
    }

    private static func authoredFieldNames(_ s: RecipeSettings) -> [String] {
        var fields: [String] = []
        if s.filmSimulation != nil { fields.append("Film Simulation") }
        if s.monochromaticColorWC != nil { fields.append("Monochromatic WC") }
        if s.monochromaticColorMG != nil { fields.append("Monochromatic MG") }
        if s.grain != nil { fields.append("Grain Effect") }
        if s.colorChromeEffect != nil { fields.append("Color Chrome Effect") }
        if s.colorChromeFXBlue != nil { fields.append("Color Chrome FX Blue") }
        if let wb = s.whiteBalance {
            fields.append(wb.mode == .kelvin ? "White Balance (Kelvin)" : "White Balance")
        }
        if s.dynamicRange != nil { fields.append("Dynamic Range") }
        if s.dRangePriority != nil { fields.append("D-Range Priority") }
        if s.highlightTone != nil { fields.append("Highlight Tone") }
        if s.shadowTone != nil { fields.append("Shadow Tone") }
        if s.color != nil { fields.append("Color") }
        if s.sharpness != nil { fields.append("Sharpness") }
        if s.highISONR != nil { fields.append("High ISO NR") }
        if s.clarity != nil { fields.append("Clarity") }
        if s.exposureBias != nil { fields.append("Exposure Bias") }
        if s.noiseReduction != nil { fields.append("Noise Reduction") }
        return fields.isEmpty ? ["none recorded"] : fields
    }

    /// One guided test as a person reads it.
    ///
    /// `!` marks every line that contradicts something — a setting the camera shows differently, a
    /// recipe that didn't survive a power cycle, a photo that doesn't match. It is the only mark in
    /// this document that means "stop here", and it has to survive being read in a mail client.
    static func render(guidedTest test: GuidedTestRecord, formatter f: ISO8601DateFormatter,
                       sweepSlot: Int? = nil) -> [String] {
        var lines: [String] = []
        var head = test.plan == nil ? "Camera test  wave \(test.wave) (legacy)" : "Camera test  continuous"
        if let transport = test.transport { head += " · \(transport)" }
        head += " · started \(f.string(from: test.startedAt))"
        head += " · \(outcomePhrase(test))"
        lines.append(head)
        lines.append("  session ID    \(test.sessionID)")
        lines += coverageLines(for: test).map { "  " + $0 }
        for confirmation in test.stillBankConfirmations ?? [] {
            lines.append("  bank mode     tester confirmed C\(confirmation.slot) assigned to STILL at \(f.string(from: confirmation.confirmedAt)); not detected by the app")
        }

        if let original = test.initialSlots {
            lines.append("  initial read  \(original.reads.count) slots · "
                         + (original.readAt.map { f.string(from: $0) } ?? "capture time not recorded"))
            for slot in original.reads {
                let values = slot.properties.compactMap { property in
                    property.value.map { "\(property.code)=\($0)" }
                }
                lines.append("     C\(slot.slot) \(slot.selected ? "selected" : "selection failed")"
                             + (slot.name.map { " \"\($0)\"" } ?? "") + " · " + values.joined(separator: " "))
            }
        } else {
            lines.append("  initial read  original slot snapshot not retained by this test")
        }

        if let identity = test.identity {
            var line = "  identity      "
            switch identity.confirmed {
            case true?: line += "confirmed"
            case false?: line += "! WRONG BODY — tester says it is \(identity.correction ?? "something else")"
            case nil: line += "not answered"
            }
            let shown = identity.appShowedModelID ?? identity.appShowedProductName
            if let shown {
                line += " — shown as \(shown)"
                if let how = identity.identification { line += " (\(how))" }
            }
            if let badge = identity.badge { line += " \"\(badge)\"" }
            lines.append(line)
        }

        for comparison in test.slotComparisons ?? [] {
            lines += render(comparison: comparison, indent: "  ", formatter: f)
        }

        if let probe = test.propertyReport {
            var line = "  property      \(probeWord(probe))"
            if let slot = probe.slot, probe.state == "ran" { line += " on C\(slot)" }
            if let count = probe.count, probe.state == "ran" { line += " — \(count) properties" }
            if probe.readOnly == true { line += ", read-only (no slot select)" }
            if let detail = probe.detail { line += " — \(detail)" }
            if let captured = probe.capturedAt { line += " · captured \(f.string(from: captured))" }
            if let id = probe.evidenceID { line += " · evidence \(id)" }
            // A report holds one top-level sweep. When the test kept no sweep of its own, two read
            // passes, or a read pass and anything that reconnects, leave this record naming evidence
            // the reader cannot go and look at — so say so here rather than leaving a citation
            // pointing at a different slot's numbers.
            if probe.state == "ran", let retained = test.propertySweep {
                line += " · session sweep retained (\(retained.entries.count) attempted properties)"
            } else if probe.state == "ran", let slot = probe.slot, let sweep = sweepSlot {
                if sweep != slot { line += " · ! the Sweep below is C\(sweep), not this one" }
            } else if probe.state == "ran", sweepSlot == nil {
                line += " · ! not in this report (a later connect replaced it)"
            }
            lines.append(line)
        }
        if let sweep = test.propertySweep {
            lines.append("  session sweep retained values · "
                         + (sweep.capturedAt.map { f.string(from: $0) } ?? "capture time not recorded")
                         + (sweep.evidenceID.map { " · evidence \($0)" } ?? ""))
            for entry in sweep.entries {
                lines.append("     \(entry.code) \(entry.name ?? "") = \(entry.value ?? entry.valueResponseCode ?? entry.valueError ?? "unavailable")")
            }
        }
        if let probe = test.grainProbe {
            var line = "  grain probe   \(probeWord(probe))"
            if let slot = probe.slot, probe.state == "ran" { line += " on C\(slot)" }
            if let count = probe.count, probe.state == "ran" { line += " — \(count) candidates" }
            if let detail = probe.detail { line += " — \(detail)" }
            lines.append(line)
        }
        if let harvest = test.profileHarvest {
            var line = "  harvest       \(probeWord(harvest))"
            if let detail = harvest.detail { line += " — \(detail)" }
            lines.append(line)
        }
        if let develop = test.develop {
            var line = "  develop       \(develop.state == "ran" ? "ran" : develop.state)"
            switch develop.jpegMatchesRecipe {
            case "yes"?: line += " · the photo looks like the recipe"
            case "no"?: line += " · ! the photo does NOT look like the recipe"
            case "notChecked"?: line += " · not compared"
            default: break
            }
            if let detail = develop.detail { line += " — \(detail)" }
            lines.append(line)
        }

        if let none = test.noCamera {
            lines.append("  no camera     the app never saw it — everything below is the tester's own account")
            func row(_ label: String, _ value: String?) {
                guard let value, !value.isEmpty else { return }
                lines.append("     \(label.padding(toLength: max(label.count, 12), withPad: " ", startingAt: 0)) \(value)")
            }
            row("model", none.modelAsPrinted)
            row("firmware", none.firmwareFromMenu)
            row("USB mode", none.usbModeWording)
            row("cable", none.cable)
            if none.cameraPromptSeen != nil || none.filesPromptSeen != nil {
                row("prompts", "camera \(none.cameraPromptSeen ?? "—"), files & folders \(none.filesPromptSeen ?? "—")")
            }
            row("app said", none.appSaid)
        }

        if let write = test.writePass {
            var line = "  write pass    "
            var parts: [String] = []
            if let at = write.consentAt { parts.append("consented \(f.string(from: at))") }
            if let backup = write.backup {
                if backup.skipped == true {
                    parts.append("! backup SKIPPED")
                } else if backup.savedAt != nil {
                    parts.append("backup saved" + (backup.activity.map { " (\($0))" } ?? ""))
                }
            }
            if let dial = write.dialConfirmed { parts.append(dial ? "dial confirmed at C" : "! dial NOT confirmed") }
            if let autoUpdate = write.autoUpdateCustomSetting {
                parts.append("AUTO UPDATE CUSTOM SETTING " + autoUpdatePhrase(autoUpdate))
            }
            line += parts.isEmpty ? "started" : parts.joined(separator: " · ")
            lines.append(line)

            for (index, trial) in (write.trials ?? []).enumerated() {
                var trialHead = "     trial \(index + 1)  \"\(trial.recipeName ?? trial.recipe)\" → C\(trial.slot)"
                if let outcome = trial.outcome { trialHead += "  \(outcome.rawValue)" }
                if let at = trial.pushedAt { trialHead += "  \(f.string(from: at))" }
                switch trial.preparation {
                case "setForTest"?: trialHead += "  slot prepared (ISO 800+, JPEG)"
                case "leftUnchanged"?: trialHead += "  slot left as it was"
                default: break
                }
                lines.append(trialHead)
                if let persistence = trial.persistence {
                    if let state = persistence.evidenceState {
                        lines.append("        restart       \(state) · settings \(persistence.settingsState ?? "unrecorded") · name \(persistence.nameState ?? "unrecorded")")
                        lines.append("        evidence      restart confirmed: \(persistence.restartConfirmed.map { $0 ? "yes" : "no" } ?? "unrecorded") · fresh read: \(persistence.freshReadSucceeded.map { $0 ? "yes" : "no" } ?? "unrecorded") · connection changed: \(persistence.connectionChanged.map { $0 ? "yes" : "no" } ?? "unrecorded")")
                    } else if persistence.persisted {
                        lines.append("        power cycle   survived (legacy Boolean; detailed restart evidence not recorded)")
                    } else if persistence.differences?.isEmpty == false {
                        lines.append("        power cycle   ! did NOT survive — legacy evidence records the mismatches below")
                    } else {
                        lines.append("        power cycle   not confirmed (legacy Boolean; distinguish mismatch from missing evidence using the recorded differences)")
                    }
                    for d in persistence.differences ?? [] {
                        lines.append("        ! \(d.field): wrote \(d.wrote ?? "—"), holds \(d.holds ?? "nothing")")
                    }
                    if let readAt = persistence.readAt { lines.append("        read at       \(f.string(from: readAt))") }
                    if let connection = persistence.connectionStartedAt {
                        lines.append("        connection    read \(f.string(from: connection))"
                                     + (trial.connectionStartedAt.map { " · push \(f.string(from: $0))" } ?? " · push connection not recorded"))
                    }
                    if let id = persistence.connectionID { lines.append("        connection ID read \(id) · push \(trial.connectionID ?? "not recorded")") }
                    for (code, expected) in (persistence.expected ?? [:]).sorted(by: { $0.key < $1.key }) {
                        lines.append("        \(code) expected=\(expected) read=\(persistence.readback?[code] ?? "unavailable")")
                    }
                    if let name = persistence.nameReadBack { lines.append("        name read     \"\(name)\"") }
                    if persistence.nameHolds == false {
                        lines.append("        ! the slot name did not survive either")
                    }
                }
                if let menu = trial.menuComparison {
                    lines += render(comparison: menu, indent: "        ", formatter: f,
                                    label: "menu check")
                }
                switch trial.photoMatchesRecipe {
                case "yes"?: lines.append("        photo         looks like the recipe")
                case "no"?: lines.append("        photo         ! does NOT look like the recipe"
                                         + (trial.photoNote.map { " — \($0)" } ?? ""))
                case "notChecked"?: lines.append("        photo         not taken")
                default: break
                }
            }
            let restores = write.restores ?? []
            if !restores.isEmpty {
                lines.append("     restores      " + restores.map { "C\($0.slot) \($0.outcome?.rawValue ?? "—")" }
                    .joined(separator: ", "))
            }
            for restore in restores {
                guard let verification = restore.verification else { continue }
                lines.append("        C\(restore.slot) final state: \(verification.outcome.rawValue) · commands: \(verification.commandOutcome.rawValue) · checked \(f.string(from: verification.at))")
                lines.append("        fresh read: \(verification.freshReadSucceeded ? "yes" : "no")"
                             + (verification.readAt.map { " at \(f.string(from: $0))" } ?? "")
                             + " · \(verification.fields.filter(\.matches).count)/\(verification.fields.count) original properties match")
                lines.append("        name: \(verification.nameMatches.map { $0 ? "matches" : "differs" } ?? "not verified") · original name restorable: \(verification.originalNameRestorable ? "yes" : "no")")
                for field in verification.fields where !field.matches {
                    lines.append("        ! \(field.code): original=\(field.original) current=\(field.current ?? "unavailable")")
                }
                for reason in verification.reasons { lines.append("        \(reason)") }
            }
        }

        if let text = test.freeText, !text.isEmpty {
            lines.append("  tester note   \"\(text)\"")
        }
        if let steps = test.stepsCompleted, !steps.isEmpty {
            lines.append("  steps         \(steps.joined(separator: ", "))")
        }
        return lines
    }

    private static func render(comparison: SlotComparisonRecord, indent: String,
                               formatter f: ISO8601DateFormatter,
                               label: String? = nil) -> [String] {
        var lines: [String] = []
        let rows = comparison.rows ?? []
        let differing = rows.filter { $0.differs == true }
        var head = indent
        if let label {
            head += label.padding(toLength: max(label.count, 14), withPad: " ", startingAt: 0)
        } else {
            head += "C\(comparison.slot)"
            if let name = comparison.name { head += " \"\(name)\"" }
            head += "  "
        }
        switch comparison.verdict {
        case "matches"?: head += "matches the camera's menu"
        case "differs"?: head += "! Tester reported a difference from the camera's menu"
        case "unverified"?: head += "could not be fully verified against the camera's menu"
        default: head += "not checked"
        }
        // Only once somebody has actually looked. "not checked · 12 settings shown" reads as though
        // twelve settings were reviewed, which is the opposite of what it means — the rows are there
        // because the step seeded them, not because anyone read them.
        if !rows.isEmpty, comparison.checkedAt != nil { head += " · \(rows.count) settings shown" }
        if let unread = comparison.fieldsAppCouldNotRead, !unread.isEmpty {
            head += " · the app couldn't read: \(unread.joined(separator: ", "))"
        }
        // The timestamp is the only thing here that says how much work the verdict represents.
        // Three slots "matching" four seconds apart is a different claim from three read carefully,
        // and without this the two render identically. Stated, not judged — the reader can see the
        // gaps for themselves.
        if let at = comparison.checkedAt { head += " · checked \(f.string(from: at))" }
        // The two bank conditions the tester can read and the app can't. Only when noted: an absent
        // answer must not render as JPEG or base ISO.
        if let iso = comparison.isoShown { head += " · ISO \(iso)" }
        switch comparison.imageFormatShown {
        case "jpeg"?: head += " · JPEG"
        case "heif"?: head += " · HEIF"
        case "notChecked"?: head += " · format not checked"
        default: break
        }
        lines.append(head)
        for row in rows where row.priorityControlled == true {
            lines.append("\(indent)   \(row.field): \(row.displayedValue ?? "controlled by D-Range Priority") · stored value \(row.appShowed ?? "unavailable") is inactive")
        }
        for row in differing {
            lines.append("\(indent)   ! \(row.field): app showed \(row.displayedValue ?? row.appShowed ?? "nothing")"
                         + " — camera shows \(row.cameraShows.flatMap { $0.isEmpty ? nil : $0 } ?? "something else")")
        }
        return lines
    }

    private static func autoUpdatePhrase(_ answer: String) -> String {
        switch answer {
        case "enable": return "ENABLE"
        case "disable": return "DISABLE"
        case "notInMenu": return "not in this camera's menu"
        case "notChecked": return "not checked"
        default: return answer
        }
    }

    private static func probeWord(_ probe: ProbeRecord) -> String {
        switch probe.state {
        case "ran": return "ran"
        case "skipped": return "skipped by the tester"
        case "notWritable": return "not run — this body isn't written to"
        case "refused": return "refused — the camera was busy"
        case "failed": return "! failed"
        default: return "not run"
        }
    }

    private static func outcomePhrase(_ test: GuidedTestRecord) -> String {
        let step = test.outcomeStep ?? "an unnamed step"
        switch test.outcome {
        case "completed"?: return "completed"
        case "sentEarly"?: return "sent early, at \(step)"
        case "abandoned"?: return "stopped at \(step)"
        default: return "in progress at \(step)"
        }
    }
}
