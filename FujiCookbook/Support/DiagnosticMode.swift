import Foundation

/// **Diagnostic mode** — an off-by-default switch (Settings ▸ Diagnostics) that reveals the
/// protocol-verification surfaces: the Demo Camera, the Camera Property Report and its write probe,
/// and the raw D185 profile dumps on developed photos.
///
/// These exist to check reverse-engineered encodings against real hardware (`FujiEncoding`,
/// `docs/fuji-recipe-ptp-protocol.md`), not to cook recipes — so the everyday app hides them. Nothing
/// behind the switch changes stored recipes; it only adds entry points.
enum DiagnosticMode {
    /// UserDefaults key. Views gate on it with `@AppStorage(DiagnosticMode.key)`, so flipping the
    /// Settings toggle updates every surface immediately.
    static let key = "diagnostics.enabled"
}
