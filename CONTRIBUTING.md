# Contributing to Fuji Cookbook

Thanks for helping. Three kinds of contribution are especially useful:

- **Camera reports.** The app writes to more bodies than anyone here owns, so a report from a camera
  that hasn't been verified is often worth more than code. Connect your camera, scroll to the end
  of the Camera tab, and tap **Help improve camera support** to run the Camera Test. Attach the two
  files it produces to a
  [Camera report](https://github.com/zgrimz/fuji-cookbook/issues/new?template=camera_report.yml)
  issue, or email them to fujicookbook@grovehouse.xyz if you'd rather not post them publicly. A
  report replaces the camera's serial number with a hash keyed to your phone, which nobody else can
  reverse. Read it before posting anyway: it includes your custom-slot names, recipe settings and
  anything you typed into the test. If its serial hash line doesn't end in "(keyed to this phone)",
  it came from an older version of the app; update before posting it.
- **Bug reports**, using the issue template.
- **Pull requests.** For anything larger than a small fix, open an issue first so we can agree on the
  approach before you spend time on it.

## Setting up

Follow [Building from source](README.md#building-from-source) in the README. You don't need an
Apple developer account to build and test in the Simulator, and you don't need a camera: the Demo
Camera (**Settings ▸ Diagnostics ▸ Show Diagnostic Tools**) runs the real encoding and safe-write
code.

Two things must never be committed:

- `Config/Local.xcconfig`. It is git-ignored; keep it that way.
- A `DEVELOPMENT_TEAM` in `FujiCookbook.xcodeproj/project.pbxproj`. Xcode's Signing & Capabilities
  pane writes one there when you pick a team. Set your team in `Config/Local.xcconfig` instead. CI
  fails a pull request that adds one.

## Tests

Run the whole suite before opening a pull request (the command is in the README). Behaviour changes
need a test. Camera behaviour is tested against `MockCameraTransport`, and `MockCameraFaults` can
make the mock refuse, drop or misreport the way real bodies do.

## Changes that touch the camera

Changes to anything that writes to a camera — the push, Undo Last Push, the RAW-conversion profile,
or a body's entry in `CameraModelRegistry` — need more care than the rest of the app, because a
mistake changes someone's camera.

- Say which body and firmware you tested on, and how: on hardware, or against the Demo Camera only.
- Keep the safe-write discipline: read before writing, carry through what the app doesn't edit,
  read back what was written, and never invent a value the camera didn't give.
- Don't raise a body's verification level without evidence from that body.

## Code style

Match the code around your change; there's no formatter or linter to satisfy. Comments explain why,
in the present tense. Dated hardware evidence is welcome ("X-T50 fw 1.32, 2026-09-17"); the history
of how the code got here belongs in commit messages, not comments.

## Sign-off

Every commit needs a `Signed-off-by` line, certifying the
[Developer Certificate of Origin](https://developercertificate.org): that you wrote the change, or
otherwise have the right to submit it under this project's license. `git commit -s` adds the line.

By contributing, you agree that your contribution is licensed under the
[Apache License, Version 2.0](LICENSE), as section 5 of that license provides.

## Conduct

This project follows its [Code of Conduct](CODE_OF_CONDUCT.md).
