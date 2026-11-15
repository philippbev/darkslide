# Darkslide

[![CI](https://github.com/philippbev/darkslide/actions/workflows/ci.yml/badge.svg)](https://github.com/philippbev/darkslide/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/philippbev/darkslide)](LICENSE)

A personal app for a Fujifilm workflow built around the X100VI: film-simulation recipes, the
camera's custom slots, and importing photos from the memory card, on iPhone and iPad. The Mac
(Mac Catalyst) build still compiles but is on hold.

Darkslide is not on the App Store. You can only build it from source.

## Features

- **Recipes.** Collect film-simulation recipes: type one in, import a
  [`.fujirecipe`](docs/recipe-json-format.md) file, read one out of a SOOC JPEG, or pull what's
  already in the camera's custom slots.
- **Rolls.** Sets of recipes for the camera's custom slots, C1–C7: push a roll and each recipe
  goes to its matching slot.
- **Darkroom with Test Strips.** Pick up to three recipes and your own RAF files. The camera does
  the developing over USB, so you compare the JPEGs it would have made, side by side or with a
  slider.
- **Camera.** Push a recipe to the custom slots you choose. Nothing changes on the camera until you
  confirm, every write is read back, and **Undo Last Push** puts back what was there.
- **Light Table.** Import photos from the camera's memory card over USB, and geotag them from a
  location track the iPhone recorded while you were shooting.
- **Optional AI scanning.** Off by default. With your own Anthropic or OpenAI API key, share a
  recipe screenshot to the app and it reads the settings into a new recipe for you to review.

## Before you connect a camera

The camera protocol is reverse-engineered, not published by Fujifilm, so you use the app at your
own risk, as the [license](LICENSE) says. Fujifilm has said that connecting software it hasn't
licensed to a camera voids the camera's limited warranty.

## Privacy

Darkslide has no account and no server, and sends nothing on its own: no analytics, crash
reporting or tracking. The details are in the [privacy policy](docs/privacy-policy.md).

## Building from source

### Requirements

- Xcode 26 or later; the code uses the iOS 26 SDK behind availability checks.
- No third-party dependencies, and no Apple developer account for the Simulator.

### Steps

```sh
git clone https://github.com/philippbev/darkslide.git
cd darkslide
cp Config/Local.example.xcconfig Config/Local.xcconfig
open FujiCookbook.xcodeproj
```

The Xcode project, scheme and folders still carry the original name `FujiCookbook`. Run the
**FujiCookbook** scheme on any iOS Simulator. For a camera there, turn on **Settings ▸ Diagnostics
▸ Show Diagnostic Tools** and use **Connect Demo Camera**, which runs the real encoding and
safe-write code in memory.

### Configuration

Signing and identifiers live in [`Config/Base.xcconfig`](Config/Base.xcconfig); the git-ignored
`Config/Local.xcconfig` overrides it. For a device build, set `DEVELOPMENT_TEAM` there, and
`APP_IDENTIFIER_BASE` to a bundle-id prefix you own. A free Personal Team can't provision iCloud;
`Config/Local.example.xcconfig` shows how to build without it. Don't set the team in Xcode's
Signing & Capabilities pane, which writes it into the project file.

### Tests

The tests need no hardware. Boot a Simulator, then:

```sh
xcodebuild test -scheme FujiCookbook -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -collect-test-diagnostics never
```

Keep `-collect-test-diagnostics never`, or a failing run spends ten minutes on diagnostics before
it reports. Leave code signing on: with `CODE_SIGNING_ALLOWED=NO` the test host has no App Group
entitlement and crashes at launch, before any test runs.

## Project structure

SwiftUI and SwiftData, in three targets: the app in `FujiCookbook/`, the Share Extension in
`ShareExtension/`, and `FujiCookbookTests/`. `Shared/` is compiled into both the app and the
extension, `Config/` holds signing settings, and `docs/` holds the reference docs, indexed in
[docs/README.md](docs/README.md). Plans and specifications for this fork are in
[`docs/fork/`](docs/fork/) (German).

## Status

See the [roadmap](docs/fork/roadmap.md).

## Contributing

This is a personal project. Issues are welcome; please talk to me before opening a pull request.
See [CONTRIBUTING.md](CONTRIBUTING.md).

## Credits & license

Darkslide is an independent fork of [Fuji Cookbook](https://github.com/zgrimz/fuji-cookbook) by
Zachary Grimshaw, released under the Apache License 2.0. It is not affiliated with Fuji Cookbook's
authors or with Grove House Studio. Fuji Cookbook's camera support is built on the
[Fujifilm PTP reference](https://github.com/zgrimz/fujifilm-ptp-reference)
([CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)); the app's own credits are under
**Settings ▸ About ▸ Acknowledgments**.

The source code is licensed under the [Apache License, Version 2.0](LICENSE). Keep the
[NOTICE](NOTICE) file with any distribution. The original app's name, icon, artwork and sample
photos are not covered by the license; see [TRADEMARKS.md](TRADEMARKS.md).

> FUJIFILM is a trademark of FUJIFILM Corporation. Darkslide is not affiliated with, endorsed by,
> or sponsored by FUJIFILM Corporation. Camera model names are trademarks of their respective
> owners.
