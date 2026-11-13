# Fuji Cookbook Fork

Persönlicher Fork von zgrimz/fuji-cookbook für Philipp (Fujifilm X100VI). Native SwiftUI-App für iPhone und iPad, Ziel zusätzlich macOS. Roadmap: `docs/fork/roadmap.md` (Kopie aus dem claude.ai-Projekt „fuji-cookbook fork“, dort ist die führende Version).

## Sprache
- Mit Philipp auf Deutsch kommunizieren. Code, Kommentare und Commit-Messages auf Englisch (wie im Upstream).

## Build & Test
- Xcode 26+, iOS-SDK 26 hinter Availability-Checks, Deployment Target iOS 17, Swift 5, keine Drittanbieter-Abhängigkeiten.
- Einmalig: `cp Config/Local.example.xcconfig Config/Local.xcconfig`, dort `DEVELOPMENT_TEAM` (vorerst leer) und `APP_IDENTIFIER_BASE = cloud.bevier.fujicookbook` setzen.
- Tests (keine Hardware nötig), Simulator an die lokal verfügbaren anpassen:
  `xcodebuild test -scheme FujiCookbook -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -collect-test-diagnostics never`
- Nach jeder Änderung bauen und die betroffenen Tests laufen lassen; vor einem Merge die ganze Suite.
- Kamera ohne Hardware: Simulator → Settings ▸ Diagnostics ▸ Show Diagnostic Tools ▸ Connect Demo Camera.

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
- Neue UI nur über zentrale Design-Tokens (Farben, Typografie, Abstände, Radien, Komponenten) – keine hartkodierten `Color(...)`/Font-Werte mehr in Views.
- Bestehende Views schrittweise migrieren, nicht in einem Rutsch.

## Git
- Ein Branch pro Feature (`feature/chapter-share`, `feature/usb-import`, …), PR gegen `main` des Forks.
- Commits mit `git commit -s` (DCO-Sign-off, wie im Upstream).
- Upstream als Remote `upstream` behalten und regelmäßig mergen.
