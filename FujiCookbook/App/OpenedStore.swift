/// The recipe store as it came up at launch, and how it came up.
struct OpenedStore<Store> {
    let store: Store
    let state: CloudStoreState

    /// Opens the store with CloudKit when the user asked for sync, and falls back to a local store
    /// when the CloudKit store can't be created.
    ///
    /// - Parameter open: Creates the store, with CloudKit when its argument is true.
    /// - Throws: The local store's error, when no store can be opened.
    static func open(wantsCloud: Bool, using open: (_ cloudKit: Bool) throws -> Store) throws -> OpenedStore {
        guard wantsCloud else { return OpenedStore(store: try open(false), state: .local) }
        do {
            return OpenedStore(store: try open(true), state: .cloudKit)
        } catch {
            let failure = CloudStoreFailure(error)
            AppLog.error(.data,
                         "iCloud (CloudKit) store unavailable — using local store: \(failure.boundedDescription)")
            return OpenedStore(store: try open(false), state: .fellBack(failure))
        }
    }
}
