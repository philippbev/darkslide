import Foundation

/// Live progress through a batch of camera operations: a `pushBatch`, a `cookBatch` or a
/// `cookMatrix`. Published so the UI can show a determinate bar; `nil` when no batch is in flight.
struct BatchProgress: Equatable {
    var completed: Int
    var total: Int
    var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }
}
