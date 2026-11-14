# Fuji Cookbook Fork

Persönlicher Fork von zgrimz/fuji-cookbook für Philipp (Fujifilm X100VI). Native SwiftUI-App für iPhone und iPad; macOS ist on hold. Roadmap: `docs/fork/roadmap.md` (Kopie aus dem claude.ai-Projekt „fuji-cookbook fork“, dort ist die führende Version).

## Mobile first (verbindlich)
- iPhone und iPad haben Vorrang. macOS ist on hold.
- Die Mac-Catalyst-Basis bleibt im Code und darf nicht kaputtgehen: Änderungen müssen weiter für Catalyst kompilieren (`#if`/`isMacCatalystApp`-Zweige mitpflegen).
- Keine Mac-spezifischen Anpassungen und keine Mac-only-Features mehr, bis Philipp den Mac wieder aufnimmt.
- Neue Features werden auf dem iPhone gebaut und getestet: Simulator (iPhone 17 Pro) für die laufende Arbeit, das eigene iPhone für Gerätetests.

## Sprache
- Mit Philipp auf Deutsch kommunizieren. Code, Kommentare und Commit-Messages auf Englisch (wie im Upstream).

## Build & Test
- Xcode 26+, iOS-SDK 26 hinter Availability-Checks, Deployment Target iOS 17, Swift 5, keine Drittanbieter-Abhängigkeiten.
- Einmalig: `cp Config/Local.example.xcconfig Config/Local.xcconfig`, dort `DEVELOPMENT_TEAM` (Personal Team fürs eigene iPhone) und `APP_IDENTIFIER_BASE = cloud.bevier.fujicookbook` setzen.
- Tests (keine Hardware nötig), Simulator an die lokal verfügbaren anpassen:
  `xcodebuild test -scheme FujiCookbook -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -collect-test-diagnostics never`
- Nach jeder Änderung bauen und die betroffenen Tests laufen lassen; vor einem Merge die ganze Suite.
- Kamera ohne Hardware: Simulator → Settings ▸ Diagnostics ▸ Show Diagnostic Tools ▸ Connect Demo Camera.
- Mac (Mac Catalyst, ohne Apple-Team): `scripts/run-mac.sh` baut, signiert lokal mit `Config/LocalMac.entitlements` und startet. Dieser Build hat eine eigene Bibliothek (`SharedContainer`), kein iCloud, keine Share Extension und keinen USB-Kamerazugriff (`SharedContainer.isLocalMacBuild`). Location Track gibt es am Mac nicht (Tracks entstehen auf dem iPhone unterwegs). Mac-UI-Prüfung: Menüs per `osascript`/System Events, Fenster per `screencapture -l`.

## Niemals committen
- `Config/Local.xcconfig` (git-ignored)
- ein `DEVELOPMENT_TEAM` in `project.pbxproj` (Signing nur über `Local.xcconfig`, nicht über den Xcode-Signing-Pane)

## Struktur
- `Shared/` – Modelle (Recipe, Chapter, RecipeFile/PortableChapter), Import, Matching, KI-Scan; von App und ShareExtension genutzt
- `FujiCookbook/Camera/` – PTP-Protokoll, Session, Slots lesen/schreiben, RAW-Konvertierung, Diagnose
- `FujiCookbook/Features/` – UI: Library, Editor, Chapters, Camera, Kitchen, Recommender, ImportExport, Settings
- `FujiCookbook/Support/` – EXIF/MakerNote, RAF-Header, Rendering, Feature Flags
- `ShareExtension/` – KI-Scan aus Screenshots
- `docs/` – Protokoll, Rezeptformat, Kameras, CloudKit, Rebranding

## Regeln für Kamera-Code (aus CONTRIBUTING.md, verbindlich)
- Alles, was auf die Kamera schreibt (Push, Undo Last Push, RAW-Conversion-Profil, `CameraModelRegistry`), nur mit besonderer Sorgfalt ändern.
- Safe-Write-Disziplin: vor dem Schreiben lesen, Unbearbeitetes durchreichen, Geschriebenes zurücklesen, nie Werte erfinden.
- Verhalten gegen `MockCameraTransport` testen; `MockCameraFaults` für Fehlerfälle.
- Verifikationsstufe einer Kamera nie ohne Belege vom Gerät anheben.
- Neue Kamera-Funktionen (Foto-Import, Geotagging) lesen nur – Schreibzugriffe auf die Kamera vorher mit Philipp abstimmen.

## Stil
- Code um die Änderung herum matchen; kein Formatter/Linter.
- Kommentare erklären das Warum, im Präsens. Hardware-Belege datieren („X100VI fw 1.31, 2026-11-xx“).
- Jede Verhaltensänderung braucht einen Test.

## Design-System
- Spezifikation: `docs/fork/design-system.md` (v2.1: Hardware-Instrument + technisches Archiv, Signalfarbe Klein-Blau). Vor jeder UI-Arbeit lesen. Referenz-PNGs folgen in `docs/fork/design/`.
- Code: `FujiCookbook/DesignSystem/` – alles mit Präfix `DS`:
  - Tokens: `DSColor` (`DSColors.swift`), Simulationsfarben als Extension `FilmSimulation.dsStyle`/`dsCode`/`dsFill`/`dsText` (`DSSimulationColors.swift`), `DSFont` + Modifier `dsObjectNumber`/`dsFieldLabel`/`dsMetaMono`/`dsKeyLabel` (feste Größen skalieren über `@ScaledMetric`), `DSSpacing`, `DSRadius`, `DSLine`, `DSSize` (`DSMetrics.swift`).
  - Komponenten unter `Components/`: `DSHardwareKeyStyle` (`.dsPrimary`, `.dsSecondary`, `DSIconKey`, `DSTextKey`), `DSLED`, `DSSlotKey`, `DSKnob`, `DSHardwareSwitchStyle` (`.dsHardware`, `.dsHardwareSwitchOnly`), `DSDevicePanel`, `DSArchiveCard` + Teile, `DSDataFieldRow`, `DSRecipeRow`/`DSArchiveList`, `DSBarcode`, `DSContactSheetTile`/`DSContactSheetGrid`, `DSTag`, `DSFloatingActionBar`. Komponenten bekommen Daten nur als Parameter.
  - Vorschau: Settings ▸ Diagnostics ▸ Show Diagnostic Tools ▸ Design System, plus `#Preview` in jeder Komponenten-Datei.
- Neue UI nur über diese Tokens und Komponenten – keine hartkodierten `Color(...)`/Font-Werte mehr in Views.
- Bestehende Views nutzen noch `Theme` (`Shared/Support/Theme.swift`). Sie werden erst in Phase 5 schrittweise migriert, nicht in einem Rutsch; bis dahin beide Schichten nicht mischen. Ausnahme: `PhotoImportView` und `LocationTrackView` laufen schon auf DS.
- `AccentColor` und die globale Navigationsleisten-Schrift (Serif aus `Theme`) bleiben bis Phase 5; deshalb zeigt auch die Galerie noch einen Serif-Titel.

## Git
- Ein Branch pro Feature (`feature/chapter-share`, `feature/usb-import`, …), PR gegen `main` des Forks.
- Commits mit `git commit -s` (DCO-Sign-off, wie im Upstream).
- Upstream als Remote `upstream` behalten und regelmäßig mergen.
