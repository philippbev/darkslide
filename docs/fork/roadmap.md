# Fuji Cookbook Fork – Roadmap

Stand: 14.11.2026 · Basis: [zgrimz/fuji-cookbook](https://github.com/zgrimz/fuji-cookbook) @ `923d86e` · Kamera: Fujifilm X100VI

## Ziel
Ein persönlicher Fork, der Fuji Cookbook zur All-in-One-App für den Fuji-Workflow ausbaut: Rezepte, Import, Geotagging, Teilen und KI-Anbindung – mit eigenem Design-System.

## Leitlinie: Mobile first
**iPhone (und iPad) haben Vorrang.** Der Mac ist vorerst **on hold**: Die bestehende Catalyst-Basis bleibt im Code und darf nicht kaputtgehen, wird aber nicht weiterentwickelt (keine Mac-spezifischen Anpassungen, keine Mac-only-Features). Neue Features werden auf dem iPhone gebaut und getestet.

## Zusammenarbeit
- **Code, Builds, Tests, Git:** lokale Claude-Code-Session in der Claude-Desktop-App (Ordner = Fork).
- **Planung, Konzepte, Design-System, Entscheidungen:** claude.ai-Projekt „fuji-cookbook fork“. Spezifikationen landen zusätzlich in `docs/fork/` und werden dort sofort committet.
- **Philipp:** Entscheidungen, Gerätetests mit iPhone und X100VI.

## Status

| # | Phase | Status | Notizen |
|---|---|---|---|
| 0 | Fork & Setup | ✅ erledigt | `CLAUDE.md`, Roadmap, Rebranding-Checkliste (`docs/fork/rebranding.md`), Signing fürs eigene iPhone |
| 1 | Design-System | 🟡 v2.1 gebaut, nicht gemergt | Tokens + Komponenten + Galerie auf `feature/design-system-v2` (Klein-Blau, Instrument + Archiv). v1 liegt noch in main und wird ersetzt |
| 2 | Chapter-Export & Share | ✅ erledigt | Einzelnes Chapter als `.fujirecipe` teilen |
| 3 | USB-Import + Geotagging Stufe A | 🟡 gebaut, Gerätetest offen | Import von der Speicherkarte über PTP (neueste zuerst), Track-Aufzeichnung, Standort per Zeitstempel. Mit X100VI und iPhone durchtesten |
| 4 | macOS | ⏸ on hold | Catalyst-Basis vorhanden (`feature/macos` gemergt). Ruht bis nach Phase 5 |
| 5 | Design v2.1 ausrollen | ⏭ als Nächstes | Screen für Screen: Rezepte → Rezept-Detail → Kamera → Import → AccentColor/Altlasten entfernen. Objektnummer fortlaufend nach `createdAt`, fest gespeichert |
| 6 | KI-Anbindung | offen | **Mobile first:** App Intents auf iOS (Kurzbefehle, Siri, Apples MCP-Integration). Lokaler MCP-Server der Mac-App ruht mit Phase 4 |
| 7 | Live-Standort per Bluetooth (Stufe B) | experimentell | Siehe Risiken |

## Nächste Schritte
1. `feature/design-system-v2` prüfen (Galerie: Einstellungen ▸ Diagnostics ▸ Design System) und in main mergen.
2. Phase 3 auf dem iPhone mit der X100VI testen: Import-Modus der Kamera, Geschwindigkeit, Zuordnung der Standorte, RAF-Sidecars.
3. Phase 5 starten, ein Screen pro Branch, nach jedem Screen Freigabe.

## Phase 3 – Details und offene Prüfpunkte
- Rezept-Funktionen brauchen *USB RAW CONV./BACKUP RESTORE*, Import den Kartenmodus. App erkennt den Modus und leitet an.
- Ziele: Fotos-Mediathek und Dateien (Mac-Ordner ruht).
- Geotagging: JPEG/HEIF direkt, RAF per XMP-Sidecar; Kamerazeit abgleichen bzw. warnen.
- Bonus offen: Rezept aus den MakerNotes lesen und Fotos dem Rezept zuordnen.

## Risiken
- **Garantie:** Fujifilm sagt, nicht lizenzierte Software an der Kamera hebt die Garantie auf.
- **Bluetooth (Stufe B):** Protokoll durch Open-Source-Projekte (z. B. furble) bekannt; Firmware 1.30 der X100VI hat Pairing und Sicherheit geändert – Machbarkeit am Gerät testen. Kamera evtl. nur mit einer App koppelbar.
- **MCP bei Apple:** Integration in App Intents ist angekündigt; Umfang auf iOS noch unklar.
- **Lizenz/Marke:** Code Apache 2.0; Name, Artwork und Beispielfotos laut `TRADEMARKS.md` separat.

## Offen
- Name des Forks / Branding (Checkliste vorhanden)
- Tab-Reihenfolge im neuen Design (vorerst bleiben die fünf Tabs)
