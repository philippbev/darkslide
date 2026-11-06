#if DEBUG
import CloudKit
import CoreData
import Foundation
import SwiftData

/// Creates the CloudKit Development schema from the shipping SwiftData model, then exits.
///
/// Runs only on a Debug launch with `--initialize-cloudkit-schema`, against an empty temporary
/// store, never the user's App Group store. Deploying the schema to Production is a separate step
/// (`docs/cloudkit-schema.md`).
enum CloudKitSchemaInitializer {
    static func runAndExit() -> Never {
        do {
            try initialize()
            print("CLOUDKIT_SCHEMA_INITIALIZATION_SUCCEEDED")
            exit(EXIT_SUCCESS)
        } catch {
            print("CLOUDKIT_SCHEMA_INITIALIZATION_FAILED: \(error)")
            exit(EXIT_FAILURE)
        }
    }

    private static func initialize() throws {
        let identifier = "iCloud.xyz.grovehouse.fujicookbookapp"
        guard CKContainer.default().containerIdentifier == identifier else {
            throw NSError(domain: "CloudKitSchemaInitializer", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Unexpected CloudKit container"])
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CloudKitSchema-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try autoreleasepool {
            guard let model = NSManagedObjectModel.makeManagedObjectModel(for: SharedModelStore.modelTypes) else {
                throw NSError(domain: "CloudKitSchemaInitializer", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "Could not generate the managed object model"])
            }
            print("Initializing \(identifier) from entities: \(model.entities.compactMap(\.name).sorted())")
            let description = NSPersistentStoreDescription(url: directory.appendingPathComponent("Schema.sqlite"))
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: identifier)
            description.shouldAddStoreAsynchronously = false
            let container = NSPersistentCloudKitContainer(name: "FujiCookbookSchema", managedObjectModel: model)
            container.persistentStoreDescriptions = [description]
            var loadError: Error?
            container.loadPersistentStores { _, error in loadError = error }
            if let loadError { throw loadError }
            defer {
                for store in container.persistentStoreCoordinator.persistentStores {
                    try? container.persistentStoreCoordinator.remove(store)
                }
            }
            try container.initializeCloudKitSchema()
        }
    }
}
#endif
