import Foundation

/// The address every shared report and feedback message is sent to. Nothing offers to send there
/// while `FeatureFlags.reportsEnabled` is false.
enum SupportContact {
    static let address = "hello@bevier.cloud"
}
