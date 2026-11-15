# Darkslide (Fuji Cookbook Fork) – Roadmap

Stand: 15.11.2026 · Basis: [zgrimz/fuji-cookbook](https://github.com/zgrimz/fuji-cookbook) @ `923d86e` · Kamera: Fujifilm X100VI

## Ziel
Ein persönlicher Fork, der Fuji Cookbook zur All-in-One-App für den Fuji-Workflow ausbaut: Rezepte, Import, Geotagging, Teilen und KI-Anbindung – mit eigenem Design-System. **Neuer Name: Darkslide** (Leitmetapher Fotolabor, siehe Design-System v2.6).

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
| 0b | Repo-Pflege & Rebranding Stufe A | ✅ erledigt (PR #13, Merge `5d3c1d9`) | Repo → `philippbev/darkslide`, README und Meta-Dateien neu, Kontakt `hello@bevier.cloud`, Berichte/Feedback ausgeblendet, eigene Datenschutzerklärung. Briefing: `claude/briefing-repo-cleanup.md` |
| 1 | Design-System | ✅ erledigt | Tokens + Komponenten + Galerie in main (`feature/design-system-v2`, Merge `1a33819`); v1 ist ersetzt |
| 2 | Chapter-Export & Share | ✅ erledigt | Einzelnes Chapter als `.fujirecipe` teilen. Wird mit den Rolls zum Teilen einer Roll |
| 3 | USB-Import + Geotagging Stufe A | 🟡 gebaut, Gerätetest offen | Import von der Speicherkarte über PTP (neueste zuerst), Track-Aufzeichnung, Standort per Zeitstempel. Mit X100VI und iPhone durchtesten |
| 4 | macOS | ⏸ on hold | Catalyst-Basis vorhanden (`feature/macos` gemergt). Ruht bis nach Phase 5 |
| 5 | Design v2.6 ausrollen | offen | Screen für Screen: Recipes → Rezept-Detail → Camera → Light Table → AccentColor/Altlasten entfernen. Objektnummer fortlaufend nach `createdAt`, fest gespeichert. Dazu: vier Tabs und Umbenennung nach v2.4 |
| 6 | KI-Anbindung | offen | **Mobile first:** App Intents auf iOS (Kurzbefehle, Siri, Apples MCP-Integration). Lokaler MCP-Server der Mac-App ruht mit Phase 4 |
| 7 | Live-Standort per Bluetooth (Stufe B) | experimentell | Siehe Risiken |

## Nächste Schritte
1. ~~`feature/design-system-v2` in main mergen~~ – erledigt (`1a33819`).
2. ~~**App-Icon einbinden**~~ – erledigt mit PR #10 (`feature/darkslide-naming`), zusammen mit Anzeigename „Darkslide“, vier Tabs und den Laborbegriffen in der Oberfläche. Ergebnisse unten.
3. ~~**Phase 0b – Repo-Pflege & Rebranding Stufe A**~~ – erledigt mit PR #13.
4. Phase 3 auf dem iPhone mit der X100VI testen: Import-Modus der Kamera, Geschwindigkeit, Zuordnung der Standorte, RAF-Sidecars. Protokoll: `docs/fork/phase-3-testprotokoll.md`.
5. Rolls spezifizieren (Datenmodell, Migration der Chapters, Laden auf C1–C7, Teilen).
6. Phase 5 starten, ein Screen pro Branch, nach jedem Screen Freigabe.

## Entscheidungen 15.11.2026
- **Name:** Darkslide. Kein „Fuji“ im Namen. UI-Sprache Englisch.
- **Leitmetapher:** Fotolabor; Koch- und Buchbegriffe entfallen.
- **Tabs:** Recipes (`rectangle.stack`), Rolls (`film`), Darkroom (`camera.filters`), Camera (`camera.aperture`). Import-Screen heißt „Light Table“.
- **Rolls ersetzen Chapters:** immer genau sieben Plätze (C1–C7), als Ganzes auf die Kamera ladbar.
- **App-Icon:** Rezeptkarte im Entwicklertank mit durchscheinendem Klein-blauem Bad; Dumpling-Icon (v2.3) verworfen. Fertig in Icon Composer (`AppIcon.icon`).

## Entscheidungen 15.11.2026 (Nachmittag)
- **Repo-Pflege vor weiteren Phasen:** Das GitHub-Repo soll den aktuellen Stand zeigen – neuer Name `philippbev/darkslide`, eigenes README, keine Verweise mehr auf Support, Website, Spenden oder Issues des Originals.
- **Kontakt:** eigene Adresse `hello@bevier.cloud`.
- **Fehlerberichte und Feedback:** vorerst nicht sammeln, UI ausblenden (`FeatureFlags.reportsEnabled = false`), eigene Lösung in einer späteren Iteration.
- **Datenschutz:** eigene Erklärung in `docs/privacy-policy.md`, in der App auf die GitHub-Ansicht verlinkt; Philipp liest sie vor dem Merge.

## Ergebnisse Darkslide-Naming (15.11.2026, PR #10)
- **App-Icon:** `FujiCookbook/AppIcon.icon` liegt neben dem Asset-Katalog und gehört über die synchronisierte Gruppe automatisch zum App-Target. Das alte Set heißt jetzt `AppIconLegacy.appiconset`, bleibt erhalten und wird nicht mehr benutzt. Mac Catalyst erzeugt daraus ein `AppIcon.icns`.
- **Share Extension und Test-Target** brauchen kein eigenes Icon; die Extension zeigt das Icon der App.
- **Dunkles Icon:** erscheint unter iOS 26 nur mit Homescreen ▸ Customize ▸ Dark, nicht schon im Dunkelmodus. Geprüft im Simulator: Tank in `#4A4A47` bleibt auf Schwarz sichtbar.
- **Anzeigename:** „Darkslide“ in beiden Info.plists, den Berechtigungsdialogen und allen sichtbaren Texten, auch Berichtsköpfe, Export-Dateinamen („Darkslide Library“, „Darkslide Backup“), Pfade „Files → Darkslide“ und Share-Card-Wortmarke.
- **Herkunft:** Der About-Text nennt Darkslide einen unabhängigen Fork von Fuji Cookbook (Zachary Grimshaw, Apache 2.0), ohne Verbindung zu dessen Autoren oder Grove House Studio. Philipp hat mit den Erstellern des Originals nichts zu tun; Credits nach Apache 2.0 (`LICENSE`, `NOTICE`) bleiben.
- **Begriffe in der UI:** Chapter → Roll, Kitchen → Darkroom, Test Kitchen → **Test Strips**, Foto-Import → „Light Table“. Typen, Ordner, IDs, `.fujirecipe` und gespeicherte Daten unverändert (keine Migration); vorhandene Namen wie „New Chapter“ bleiben, neue heißen „New Roll“.
- **Ideas-Tab:** existiert im Code hinter `FeatureFlags.ideasEnabled = false` und bleibt aus.
- **Lokalisierung:** keine Strings-Dateien vorhanden.
- **Tests:** 1421 grün (iPhone 17 Pro), Catalyst baut.

**Nachtrag nach dem ersten Gerätetest (15.11.2026, `feature/darkslide-polish`):**
- **Ladescreen:** zeigte noch das alte grüne Icon mit „Fuji Cookbook“. Neu: Karte im Tank aus den `AppIcon.icon`-Ebenen (`DarkslideLaunchMark`, erzeugt mit `scripts/render-launch-mark.swift`) auf `#E8E7E3` bzw. `#0F0F0F` (`DarkslideLaunchBackground`). iOS behält einen einmal erzeugten Ladescreen auch über Neustarts, bis sich die `UILaunchScreen`-Einträge ändern – deshalb die neuen Asset-Namen. Bei künftigen Änderungen am Ladescreen wieder umbenennen.
- **Rolls auf dem iPad:** Die Auswahl war ein abgerundeter Rahmen auf der eckigen Archivkarte; jetzt eckig (`DSRadius.archive`).
- **Frame & Fit und Share Cards entfernt** (Philipp braucht sie nicht): Darkroom-Kachel, Menüpunkt „Share Card…“ im Rezept-Detail, `FrameAndFitView`, `FrameRenderer`, `ShareCard/` und 27 Tests. `pixelSize(of:)` lebt jetzt in `ImageDownsampler`. Damit entfallen auch `BrandMark`/`CardWordmark` aus Stufe C.
- **Gespeicherte Namen:** Bestehende Rolls heißen in den Daten noch „Chapter 1“ o. Ä. Umbenennen gehört in den Rolls-Branch (Migration), neue Rolls heißen „New Roll“.
- **Offen für Phase 5 (Rolls-Layout):** Die Rezeptnamen in der Roll-Karte sind noch mit „·“ getrennt, die Detailansicht nutzt noch Systemlisten mit runden Ecken.

**Noch auf das Original verweisend (Restliste):**
- **Stufe A, dringend:** Support-Adresse `fujicookbook@grovehouse.xyz` (`SupportContact.swift`) – Berichte und Feedback aus Darkslide landen sonst beim Autor des Originals. Datenschutz-URL `fujicookbook.grovehouse.xyz` (`SettingsView.swift`).
- **Stufe B:** Dokumenttyp `xyz.grovehouse.fujicookbook.recipe` und Beschreibung „Fuji Recipe“; CloudKit-Container `iCloud.xyz.grovehouse.fujicookbookapp`.
- **Stufe C:** Beispielfotos in „Lua de Mel“; Projekt-, Target-, Schema- und Ordnername `FujiCookbook`, `CFBundleName`, Bundle-ID in `Config/Base.xcconfig`, Entitlements, `scripts/run-mac.sh`; README, `docs/`, CONTRIBUTING, SECURITY, `.github`.
- **Bleibt:** `NOTICE`, `TRADEMARKS.md`, Quellenangaben in Kommentaren, Fixture eines alten Berichts in `SerialHashTests`.

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
- **Name Darkslide:** Im App Store gibt es eine Skateboard-App „DarkSlide“ (andere Kategorie); `darkslide.app` nutzt ein browserbasierter Foto-Editor. Für die persönliche App unkritisch, vor einer Veröffentlichung prüfen.

## Offen
- Rolls: Migration bestehender Chapters mit mehr als sieben Rezepten; Dateiendung beim Teilen (`.fujirecipe` umbenennen?)
- Suche als eigener Tab (iOS-26-Muster)?
- Layout der Screens Rolls und Darkroom
- Rebranding im Code: Anzeigename, sichtbare Texte, App-Icon und Ladescreen erledigt (PR #10, #11); Stufe A läuft mit Phase 0b. Rest nach Checkliste `docs/fork/rebranding.md`: Dokumenttyp und CloudKit-Container (B), Beispielfotos, Bundle-ID, Projekt-/Target-Namen, Doku (C)
- **Auf dem iPhone prüfen (Philipp):** neuer Ladescreen statt „Fuji Cookbook“ (hell und dunkel), dunkles Icon (Homescreen ▸ Customize ▸ Dark), eckige Roll-Auswahl auf dem iPad, Darkroom ohne Frame & Fit
- Aufräumen: `AppIconLegacy.appiconset` löschen, sobald das neue Icon auf dem Gerät bestätigt ist
- Aufräumen: Warnung `ImplicitStrongCapture` in `PhotoImportModel.swift:199` (bestand schon vor dem Darkslide-Naming)
- Eigene Lösung für Fehlerberichte und Feedback (nach Phase 0b, Zeitpunkt offen)
- Rolls-Migration: gespeicherte Namen wie „Chapter 1“ / „New Chapter“ mit umbenennen? (Entscheidung offen)
