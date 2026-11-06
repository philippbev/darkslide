# CloudKit schema maintenance

For the shipping container, launch a **Debug** build with the argument
`--initialize-cloudkit-schema` on a device signed into iCloud. This explicit maintenance mode
initializes Development from `SharedModelStore.modelTypes`, including `Recommendation`, using
an empty temporary store. It does not open the recipe library or change the sync preference.
The process prints `CLOUDKIT_SCHEMA_INITIALIZATION_SUCCEEDED` or a failure and exits.
The command is excluded from Release builds and rejects any container other than the one named
in `FujiCookbook/Support/CloudKitSchemaInitializer.swift`; a fork with its own container changes it
there ([rebranding a fork](rebranding-a-fork.md)).

After a successful run, review **Deploy Schema Changes** in CloudKit Console and deploy the
schema to Production. Initialization does not deploy it. Check both inline and `_ckAsset` fields;
ordinary sample records may not populate every storage variant. Remove the launch argument
before running the app normally.

Run it again, and deploy again, whenever a stored property of a model in
`SharedModelStore.modelTypes` is added or changed.
