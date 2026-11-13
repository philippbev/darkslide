# Fuji Cookbook Fork – Roadmap

Stand: 13.11.2026 · Basis: [zgrimz/fuji-cookbook](https://github.com/zgrimz/fuji-cookbook) @ `923d86e` (6.11.2026) · Kamera: Fujifilm X100VI

## Ziel
Ein persönlicher Fork, der Fuji Cookbook zur All-in-One-App für den Fuji-Workflow ausbaut: Rezepte (schon sehr gut), plus Import, Geotagging, macOS, Teilen und KI-Anbindung – mit eigenem Design-System.

## Zusammenarbeit
- **Code, Builds, Tests, Git:** lokale Claude-Code-Session in der Claude-Desktop-App (Umgebung = Mac, Ordner = Fork). Keine Cloud-Umgebung – dort gibt es kein Xcode.
- **Planung, Konzepte, Design-System, Entscheidungen:** claude.ai-Projekt „fuji-cookbook fork“. Ergebnisse landen als Docs dort.
- **Philipp:** Entscheidungen, Gerätetests mit der X100VI, Signing/Capabilities in Xcode.

## Phasen

| # | Phase | Aufwand | Kernpunkte |
|---|---|---|---|
| 0 | Fork & Setup | klein | Fork, `Local.xcconfig`, `CLAUDE.md`, Build + Tests grün, Rebranding-Liste aus `docs/rebranding-a-fork.md` |
| 1 | Design-Tokens (Fundament) | mittel | Zentrale Farben, Typografie, Abstände, Radien, Komponenten. Heute keine Token-Schicht – Farben/Fonts in ~50 Dateien direkt gesetzt; nur `CardPalette` für Share Cards |
| 2 | Chapter-Export & Share | klein | `PortableChapter` existiert bereits (nur im Full Backup). Einzelnes Chapter + Rezepte als `.fujirecipe`, Share-Sheet, Import stellt das Chapter wieder her |
| 3 | USB-Import + Geotagging Stufe A | groß | Siehe unten |
| 4 | macOS | mittel | Mac Catalyst zuerst (33 Dateien importieren UIKit; ImageCaptureCore läuft auch auf dem Mac). Danach Sidebar, Menüs, Drag & Drop |
| 5 | Neues Design ausrollen | mittel–groß | Views schrittweise auf Tokens umstellen |
| 6 | MCP & App Intents | mittel | Lokaler MCP-Server in der Mac-App (Rezepte suchen/anlegen, Chapters, ggf. Push). Parallel App Intents für Kurzbefehle/Siri und Apples MCP-Integration |
| 7 | Live-Standort per Bluetooth (Stufe B) | experimentell | Siehe Risiken |

## Phase 3 im Detail – USB-Import
- Grundlage vorhanden: PTP über ImageCaptureCore, Objekt-Enumeration (`ObjectEnumerationTests`). Kein Download von Fotos bisher.
- **Offene Frage zuerst klären:** Rezept-Funktionen brauchen den Modus *USB RAW CONV./BACKUP RESTORE*; Import vermutlich *USB-Kartenleser*/PTP. App soll den nötigen Modus erkennen und anleiten.
- Funktionen: Thumbnails, „nur neue“, Auswahl nach Datum/Session, JPEG/HEIF/RAF.
- Ziele: Fotos-Mediathek, Ordner in Dateien, am Mac frei wählbarer Ordner (z. B. T7).
- Bonus: Rezept aus den MakerNotes lesen (`FujiMakerNote`, `PhotoRecipeReader` vorhanden) und Fotos dem passenden Rezept zuordnen.

## Phase 3 im Detail – Geotagging Stufe A
- App zeichnet während einer Fototour den Standort auf (Track).
- Beim Import GPS per Zeitstempel-Abgleich schreiben: JPEG/HEIF direkt, RAF per XMP-Sidecar (RAW nicht verändern).
- Voraussetzung: Kamerazeit stimmt – App gleicht sie ab / warnt bei Abweichung.

## Risiken & offene Punkte
- **Garantie:** Fujifilm sagt, nicht lizenzierte Software an der Kamera hebt die Garantie auf (siehe README des Originals).
- **Bluetooth (Stufe B):** Protokoll ist durch Open-Source-Projekte (z. B. furble) bekannt; Firmware 1.30 der X100VI hat Pairing und Sicherheit geändert – Machbarkeit mit aktueller Firmware muss am Gerät getestet werden. Kamera ist evtl. nur mit einer App koppelbar (ersetzt dann die XApp).
- **MCP bei Apple:** Integration in App Intents ist angekündigt/in Arbeit; lokaler MCP-Server am Mac ist davon unabhängig.
- **Lizenz/Marke:** Code Apache 2.0; Name, Artwork und Beispielfotos laut `TRADEMARKS.md` separat – bei Verteilung umbenennen.

## Entscheidungen
- Erst Prototyp im Simulator, ohne Apple Team ID. `APP_IDENTIFIER_BASE = cloud.bevier.fujicookbook` als Platzhalter.
- Für Gerätetests später: kostenlose Apple ID als Personal Team reicht; iCloud-Sync in Dev-Builds dann abschalten.

## Offen
- GitHub-Account für den Fork
- Name des Forks / Branding
- Design-Richtung (Bezug zur Marke „Philipp Bevier“?)
