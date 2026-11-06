import Foundation

/// Whether the connected body may be written to, as the camera services decided it.
///
/// Four questions about a body are kept apart (zgrimz/fujifilm-ptp-reference
/// `docs/11-client-implementation.md#keep-session-and-device-identity-explicit`): what it is
/// (`ModelIdentification`), what the registry publishes about it (`CameraModel`), what it answered
/// at connect (`ObservedCapabilities`), and what the app will do with it. This is the last one.
/// Views read it; writers take the `WritePermission` inside `.granted` as a parameter, so nothing
/// writes without a value that only `WriteDecision` produces.
enum WriteAccess: Equatable {
    /// Connected, and the slot read that decides hasn't finished.
    case undecided
    case granted(WritePermission)
    case refused(WriteRefusal)

    /// For the compatibility report: `undecided`, `granted(<grounds>, <stage>)` or
    /// `refused(<reason>)`, so two testers' reports of one body compare.
    var reportLabel: String {
        switch self {
        case .undecided: return "undecided"
        case .granted(let permission): return "granted(\(permission.grounds.reportLabel), \(permission.stage.reportLabel))"
        case .refused(let refusal): return "refused(\(refusal.reportLabel))"
        }
    }
}

/// Permission to write recipes to the connected body, for this session.
///
/// Carries what it rests on and which body it names, so a report can say both.
struct WritePermission: Equatable {
    enum Stage: Equatable {
        /// No push to this body has been read back on this body yet.
        case unverified
        /// A push has, or the registry entry rests on a hardware or owner report.
        case verified

        var reportLabel: String {
            switch self {
            case .unverified: return "unverified"
            case .verified: return "verified"
            }
        }
    }

    /// What the permission rests on.
    enum Grounds: Equatable {
        /// An `exact` or `alias` registry match whose entry is `.readWrite`, at the level the
        /// registry records for it.
        case trustedEntry(VerificationLevel)
        /// The connect's slot read: the selector answered a bank number, every selected bank read
        /// back, and the selector went back where it was (`WriteDecision`).
        case walk

        var reportLabel: String {
            switch self {
            case .trustedEntry(let level): return "trusted-entry(\(level.reportLabel))"
            case .walk: return "walk"
            }
        }

        /// What the push screen says before a write on these grounds. A trusted entry says what its
        /// level says (`VerificationLevel.pushCaveat`). A walk grant always says something, and
        /// never what the entry's level says: an `.untested` entry is `.inferred` by default, and an
        /// X-Trans II body shares no processor with a tested one.
        var pushCaveat: String? {
            switch self {
            case .trustedEntry(let level):
                return level.pushCaveat
            case .walk:
                return "Writing is on because this camera's custom slots answered when it connected, not because anyone has reported a write to it. Fuji Cookbook records exactly what the slot held before it writes, and tells you exactly what landed."
            }
        }

        /// What the Camera Test tells a tester about the evidence their report adds to, on these
        /// grounds; the walk counterpart of `VerificationLevel.testerNote`.
        var testerNote: String? {
            switch self {
            case .trustedEntry(let level):
                return level.testerNote
            case .walk:
                return "This camera hasn't been tested — writing is on because its custom slots answered when it connected. Fuji Cookbook records exactly what the slot held before it writes, and tells you exactly what landed."
            }
        }
    }

    let stage: Stage
    let grounds: Grounds
    /// The firmware the body reported when the permission was granted; nil when neither the
    /// transport nor `GetDeviceInfo` gave one.
    let firmwareVersion: String?
    /// The body's serial as `SerialHash` records it; nil without `GetDeviceInfo` or without this
    /// phone's hashing key.
    let serialHash: String?

    fileprivate init(stage: Stage, grounds: Grounds, firmwareVersion: String?, serialHash: String?) {
        self.stage = stage
        self.grounds = grounds
        self.firmwareVersion = firmwareVersion
        self.serialHash = serialHash
    }

    /// The same permission, verified: a push has been read back on this body
    /// (`StagedWrite.provesBankPath`). Only `CameraSession.markWriteVerified` calls it.
    func verified() -> WritePermission {
        WritePermission(stage: .verified, grounds: grounds, firmwareVersion: firmwareVersion, serialHash: serialHash)
    }
}

/// Why the connected body is refused writes: one case per gate, phrased in one place.
enum WriteRefusal: Equatable {
    /// The registry entry refuses, in its own words.
    case blockedByRecord(reason: String)
    /// No registry entry, and no `GetDeviceInfo` naming the body with product name, serial and
    /// firmware.
    case noIdentity
    /// The selector read answered `0x200A`: no bank block in this context.
    case noBankBlock
    /// The selector read failed for another reason, which says nothing about the block.
    case selectorUnreadable(detail: String)
    /// The walk threw, or a selected bank didn't answer every property.
    case walkFailed(detail: String)
    /// A select answered OK and the selector read back as another bank.
    case selectIgnored(bank: Int)
    /// No bank accepted a select.
    case noBanks
    /// The selector did not go back to the bank the walk found it on.
    case selectorNotRestored

    /// For the compatibility report: the case, and the bank where one is named.
    var reportLabel: String {
        switch self {
        case .blockedByRecord: return "blocked-by-record"
        case .noIdentity: return "no-identity"
        case .noBankBlock: return "no-bank-block"
        case .selectorUnreadable: return "selector-unreadable"
        case .walkFailed: return "walk-failed"
        case .selectIgnored(let bank): return "select-ignored(C\(bank))"
        case .noBanks: return "no-banks"
        case .selectorNotRestored: return "selector-not-restored"
        }
    }

    /// The sentence shown wherever the refused write would have been offered.
    func reason(productName: String) -> String {
        switch self {
        case .blockedByRecord(let reason):
            return reason
        case .noIdentity:
            return "“\(productName)” isn't a recognized model and didn't identify itself over USB with a product name, serial number and firmware version, so Fuji Cookbook can't be sure which camera it is talking to and won't write recipes to it."
        case .noBankBlock:
            return "“\(productName)” answers that it has no custom-slot selector over USB (0x200A), so its slots can't be reached this way. Nothing was written."
        case .selectorUnreadable(let detail):
            return "“\(productName)” didn't say which custom slot is selected (\(detail)), so Fuji Cookbook can't tell whether its slots are reachable and won't write to it. Reconnect and try again."
        case .walkFailed(let detail):
            return "Reading “\(productName)”'s custom slots stopped early (\(detail)), so Fuji Cookbook won't write to it. Reconnect to read them again."
        case .selectIgnored(let bank):
            return "“\(productName)” said OK to selecting slot C\(bank) and stayed where it was, so a write could land in the wrong slot. Fuji Cookbook won't write to it."
        case .noBanks:
            return "“\(productName)” accepted no slot select, so there is no slot to write to."
        case .selectorNotRestored:
            return "After its slots were read, “\(productName)” didn't go back to the slot it was on, so its slot selector can't be trusted and Fuji Cookbook won't write to it."
        }
    }
}

/// The one place that decides `WriteAccess`.
///
/// A function of the identification, what the registry publishes and what the body answered, so
/// the rule is tested without a camera, and the only producer of a `WritePermission`.
enum WriteDecision {
    static func decide(identification: ModelIdentification, observed: ObservedCapabilities,
                       firmwareVersion: String?, serialHash: String?) -> WriteAccess {
        switch identification {
        case .unknown:
            return .refused(.noIdentity)
        case .exact(let model), .alias(let model, _):
            switch model.writeSupport {
            case .blocked(let reason):
                return .refused(.blockedByRecord(reason: reason))
            case .readWrite:
                return .granted(WritePermission(stage: stage(for: model.verification),
                                                grounds: .trustedEntry(model.verification),
                                                firmwareVersion: firmwareVersion,
                                                serialHash: serialHash))
            case .untested:
                return decideFromWalk(observed, firmwareVersion: firmwareVersion, serialHash: serialHash)
            }
        case .heuristic(let model, _), .unlisted(let model):
            // A guess is a different camera until shown otherwise, and an unlisted body has no
            // entry at all; both are decided by what they answered. A guess at a `.blocked` entry
            // keeps the block: a name that contains the X-Pro3's is most likely an X-Pro3.
            if case .blocked(let reason) = model.writeSupport {
                return .refused(.blockedByRecord(reason: reason))
            }
            return decideFromWalk(observed, firmwareVersion: firmwareVersion, serialHash: serialHash)
        }
    }

    /// The record's order for a new body: the selector read, every bank selected and read back,
    /// the selector restored (zgrimz/fujifilm-ptp-reference
    /// `docs/08-methods.md#minimum-evidence-for-a-new-body`, `docs/04-custom-slots.md#verifying-a-write`).
    /// Each step passes to the next or refuses, and an outcome that isn't known refuses.
    private static func decideFromWalk(_ observed: ObservedCapabilities, firmwareVersion: String?,
                                       serialHash: String?) -> WriteAccess {
        guard let read = observed.slotRead else { return .undecided }
        switch read.selector {
        case .notRead: return .refused(.selectorUnreadable(detail: "the selector was not read"))
        case .unsupported: return .refused(.noBankBlock)
        case .failed(let detail): return .refused(.selectorUnreadable(detail: detail))
        case .value: break
        }
        switch read.walk {
        case .notWalked, .sweptReadOnly:
            return .refused(.walkFailed(detail: "the slot read did not run"))
        case .failed(let detail):
            return .refused(.walkFailed(detail: detail))
        case .stopped(let bank):
            return .refused(.selectIgnored(bank: bank))
        case .finished(let banks, let allRead):
            guard banks >= 1 else { return .refused(.noBanks) }
            guard allRead else { return .refused(.walkFailed(detail: "a selected bank did not answer every property")) }
            guard read.selectorRestored == true else { return .refused(.selectorNotRestored) }
            return .granted(WritePermission(stage: .unverified, grounds: .walk,
                                            firmwareVersion: firmwareVersion, serialHash: serialHash))
        }
    }

    /// A body somebody has written to through this app and reported on starts verified; one known
    /// from published records or shared architecture does not.
    private static func stage(for verification: VerificationLevel) -> WritePermission.Stage {
        switch verification {
        case .hardware, .ownerReport: return .verified
        case .community, .inferred: return .unverified
        }
    }
}
