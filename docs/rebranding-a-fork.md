# Rebranding a fork

The Apache license covers the code, documentation and sample recipe data. The Fuji Cookbook name,
its artwork and the Lua de Mel sample photos have separate terms in [TRADEMARKS.md](../TRADEMARKS.md),
including permission to retain them in source forks used for development and contributions. If you
distribute a fork as an app, change:

- `APP_IDENTIFIER_BASE` and `DEVELOPMENT_TEAM` in `Config/Base.xcconfig`;
- the display name (`CFBundleDisplayName` in `FujiCookbook/Info.plist`),
  and the name everywhere else it reaches users: the camera and photo-library permission prompts in
  `FujiCookbook/Info.plist`, and the user-facing strings in the Swift sources that say
  "Fuji Cookbook", which include export and report file names (search the sources for the name);
- the app icon and the `LaunchMark` image in `FujiCookbook/Assets.xcassets`;
- the share cards' sign-off, the mark and the name that `BrandMark` and `CardWordmark` draw in
  `FujiCookbook/Features/Library/ShareCard/ShareCardTypography.swift`;
- the sample photos in `FujiCookbook/Resources/Lua de Mel.fujirecipe`, the recipe a new library
  starts with: delete the file's `photos` key, or put in photos of your own;
- the support address in `FujiCookbook/Support/SupportContact.swift`, and the privacy-policy URL in
  `FujiCookbook/Features/Settings/SettingsView.swift`;
- the exported `.fujirecipe` document type, `xyz.grovehouse.fujicookbook.recipe`, in
  `FujiCookbook/Info.plist` and `FujiCookbook/Support/UIKitBridges.swift`, so two apps don't both
  claim it;
- the CloudKit container identifier in `FujiCookbook/Support/CloudKitSchemaInitializer.swift`, which
  is written out rather than derived from `APP_IDENTIFIER_BASE`, if the fork syncs through iCloud
  (see [cloudkit-schema.md](cloudkit-schema.md)).

The App Group, iCloud container, Keychain group and bundle identifiers derive from
`APP_IDENTIFIER_BASE`, so they need no change of their own.

A few tests pin the support address, the document type and the bundled recipe: `SupportMailTests`,
`ReportSharingTests`, `RecipeUTITests` and `StarterRecipeTests` (which checks the recipe's credit
and its five photos). Update them alongside, and update the tests that match on the app's name in
report and feedback text.
