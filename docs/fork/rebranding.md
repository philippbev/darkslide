# Rebranding-Liste

Stand: 13.11.2026 · Quelle: [`docs/rebranding-a-fork.md`](../rebranding-a-fork.md) und [`TRADEMARKS.md`](../../TRADEMARKS.md), gegen den Stand `923d86e` geprüft.

## Wann was nötig ist

`TRADEMARKS.md` erlaubt, die App aus dem Quellcode für sich selbst zu bauen und zu benutzen, und Name, Artwork und Fotos in Forks zu behalten, die der Entwicklung dienen. Die Pflicht zum Umbenennen beginnt mit dem Verteilen als App. TestFlight zählt dazu.

Daraus ergeben sich drei Stufen:

- **A – jetzt, auch für den rein privaten Fork sinnvoll:** Stellen, an denen der Fork sonst mit dem Original kollidiert oder dessen Autor behelligt.
- **B – vor dem ersten Gerätetest:** nur, wenn die Original-App auf demselben Gerät installiert ist oder iCloud-Sync an bleibt.
- **C – vor jeder Verteilung (TestFlight, App Store, Weitergabe eines Builds):** Name, Artwork, Fotos.

## Stufe A – jetzt

| Erledigt | Was | Wo | Warum schon jetzt |
|---|---|---|---|
| ✅ | `APP_IDENTIFIER_BASE`, `DEVELOPMENT_TEAM` | `Config/Local.xcconfig` (nicht `Base.xcconfig`, solange nichts verteilt wird) | Bundle-IDs, App Group, iCloud-Container und Keychain-Gruppe leiten sich daraus ab |
| ☐ | Support-Adresse `fujicookbook@grovehouse.xyz` | `FujiCookbook/Support/SupportContact.swift:5` | Problem- und Feedback-Berichte aus dem Fork gingen sonst an den Upstream-Autor, mit Fehlern aus Code, den er nicht kennt |
| ☐ | Datenschutz-URL `https://fujicookbook.grovehouse.xyz/app-privacy/` | `FujiCookbook/Features/Settings/SettingsView.swift:101` | Beschreibt die Original-App; neue Funktionen (Standort-Track, Foto-Import) deckt sie nicht ab |

Tests, die mitziehen müssen: `SupportMailTests`, `ReportSharingTests`.

## Stufe B – vor dem Gerätetest

| Erledigt | Was | Wo | Bedingung |
|---|---|---|---|
| ☐ | Exportierter Dokumenttyp `xyz.grovehouse.fujicookbook.recipe` | `FujiCookbook/Info.plist:109` und `:132`, `FujiCookbook/Support/UIKitBridges.swift:14` | Original-App auf demselben Gerät: zwei Apps dürfen denselben Typ nicht beide exportieren |
| ☐ | CloudKit-Container `iCloud.xyz.grovehouse.fujicookbookapp` | `FujiCookbook/Support/CloudKitSchemaInitializer.swift:25` | Nur wenn der Fork über iCloud synchronisiert. Laut Roadmap bleibt Sync in Dev-Builds aus; dann entfällt der Punkt. Der Code läuft ohnehin nur in Debug mit `--initialize-cloudkit-schema` |

Test, der mitzieht: `RecipeUTITests`.

Offen dabei: Soll der Fork `.fujirecipe`-Dateien des Originals weiter öffnen können? Dann den Typ des Originals zusätzlich als *importierten* Typ deklarieren, statt ihn nur zu ersetzen.

## Stufe C – vor einer Verteilung

| Erledigt | Was | Wo |
|---|---|---|
| ☐ | Anzeigename `CFBundleDisplayName` | `FujiCookbook/Info.plist:20`, `ShareExtension/Info.plist:21` |
| ☐ | Name in den Berechtigungsdialogen (Kamera, Fotos hinzufügen) | `FujiCookbook/Info.plist:77`, `:81` |
| ☐ | Name in den Swift-Quellen: 68 Treffer für „Fuji Cookbook“ in 28 Dateien, darunter Export- und Berichts-Dateinamen | `FujiCookbook/`, `Shared/`, `ShareExtension/` |
| ☐ | App-Icon und `LaunchMark` | `FujiCookbook/Assets.xcassets` |
| ☐ | Signatur, Marke und Name der Share Cards (`BrandMark`, `CardWordmark`) | `FujiCookbook/Features/Library/ShareCard/ShareCardTypography.swift` |
| ☐ | Die fünf Beispielfotos: `photos`-Schlüssel löschen oder eigene Fotos einsetzen | `FujiCookbook/Resources/Lua de Mel.fujirecipe` |
| ☐ | `APP_IDENTIFIER_BASE` und `DEVELOPMENT_TEAM` dauerhaft | `Config/Base.xcconfig` |
| ☐ | Wortmarke und Screenshots der Doku | `docs/images/` |

Tests, die mitziehen müssen: `StarterRecipeTests` (prüft Credit und die fünf Fotos) sowie die sechs Testdateien, die den App-Namen in Berichts- und Feedback-Texten abgleichen.

## Bleibt unverändert

- `LICENSE` und `NOTICE`: Apache 2.0 verlangt, beide zu erhalten. Eigene Änderungen kommen in `NOTICE` dazu, nichts wird entfernt.
- Der Herkunftshinweis „based on Fuji Cookbook“ mit Link aufs Original ist ausdrücklich erwünscht.
- Die Verweise auf `zgrimz/fujifilm-ptp-reference` in `PhotoRecipeReader.swift` sind Quellenangaben und bleiben.

## Hängt an offenen Entscheidungen

- **Name des Forks** blockiert Stufe C komplett und die Wahl der neuen Dokumenttyp-Kennung in Stufe B.
- **Support-Adresse und Datenschutz-URL** für Stufe A: eigene Adresse, oder beides im Fork vorerst ausblenden.
