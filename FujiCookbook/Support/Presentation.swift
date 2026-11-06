import SwiftUI

extension Binding where Value == Bool {
    /// True while `source` holds a value; writing false clears it. One optional then both drives
    /// an alert, sheet or dialog and carries what it shows, and dismissing the presentation is
    /// what empties it.
    init<Wrapped>(isPresent source: Binding<Wrapped?>) {
        self.init(get: { source.wrappedValue != nil },
                  set: { if !$0 { source.wrappedValue = nil } })
    }
}

/// A value with an identity fixed when it is wrapped, for `.sheet(item:)` and friends.
///
/// The id belongs to the presentation, not to the value, so a sheet stays up while its payload's own
/// identity moves: SwiftData flips a new model's `persistentModelID` from temporary to permanent on
/// its first autosave, which keyed by that id would dismiss an editor mid-edit. Wrap once and store
/// the result; one built inside a getter gets a new id on every read and presents again each time.
struct Identified<Value>: Identifiable {
    let id = UUID()
    let value: Value
}
