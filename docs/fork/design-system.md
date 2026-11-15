# Darkslide – Design-System v2.6

Stand: 15.11.2026 (v2.1: Rückfragen aus Claude Code; v2.2: Entscheidungen zum Rollout der Rezepte-Liste; v2.3: App-Icon; v2.4: Name „Darkslide“, Leitmetapher Fotolabor, vier Tabs, Rolls statt Chapters, Dumpling-Icon verworfen; v2.5: neues App-Icon „Rezeptkarte im Entwicklertank“; **v2.6: App-Icon in Icon Composer fertig, acht Ebenen**). Quelle: Canvas „Fuji Cookbook – Design-Richtung“ (claude.ai), Artboards „Grundlagen v2“, „Rezepte“, „Rezept als Archivkarte“, „Kamera als Instrument“, „Import“; App-Icon: Figma-Datei „Darkslide – App Icon“ und `AppIcon.icon`. Ablage im Repo: `docs/fork/design-system.md`. Ersetzt v1 vollständig.

## Name, Leitmetapher und Struktur (v2.4)
**App-Name: Darkslide.** Der Darkslide ist der Schieber vor der Filmkassette – erst wenn er gezogen ist, kann belichtet werden. Der Name spielt bewusst auf die Dunkelkammer an. Kein „Fuji“ im Namen (Marke von Fujifilm). Fujifilm höchstens beschreibend im App-Store-Untertitel (z. B. „Film recipes for your X camera“). Oberflächensprache: **Englisch**.

**Leitmetapher: Fotolabor.** Jeder Begriff in der App muss in diese Welt passen. Die visuelle Sprache bleibt technisches Archiv + Hardware-Instrument; die Begriffe kommen aus dem Labor. Keine Koch- oder Buch-Begriffe mehr („Kitchen“, „Chapter“, „Cookbook“).

**Tabs (iPhone: Tab-Bar, iPad: Sidebar-adaptiv, Labels immer sichtbar):**

| Tab | SF Symbol | Aufgabe | Vorher |
|---|---|---|---|
| **Recipes** | `rectangle.stack` | Alle Rezepte als Archivkarten | Recipes |
| **Rolls** | `film` | Sätze von genau sieben Rezepten, als Ganzes auf C1–C7 ladbar | Chapters |
| **Darkroom** | `camera.filters` | Rezepte an RAW-Dateien testen, Rezepte aus Bildern auslesen | Kitchen |
| **Camera** | `camera.aperture` | Geräte-Panel, Slots C1–C7, Import | Camera |

Der Tab „Ideen“ aus früheren Fassungen existiert nicht. Offen: Suche als eigener Tab nach iOS-26-Muster.

**Import-Screen:** Titel **„Light Table“** (Leuchttisch mit Kontaktbogen).

**Rolls – Regel:** Eine Roll hat **immer genau sieben Plätze**, C1 bis C7, in fester Reihenfolge. Eine Roll lässt sich mit einem Tipp komplett auf die Kamera laden und als Ganzes teilen (Nachfolger des Chapter-Exports). Bestehende Chapters mit mehr als sieben Rezepten müssen bei der Umstellung aufgeteilt werden (Migration noch zu spezifizieren). In der UI heißt das Feld **ROLL** statt KAPITEL.

## Richtung
**iOS-Struktur mit mutigen Details aus Hardware-Instrument und technischem Archiv, Begriffe aus dem Fotolabor.**

- **iOS bleibt Basis:** NavigationStack, Sheets, Listen-Scrolling, Suche, System-Tab-Bar (ab iOS 26 Liquid Glass hinter Availability-Check, darunter Standard-TabView), Systemdialoge. Keine Nachbauten von Systemkomponenten.
- **Technisches Archiv:** Rezepte sind Archivobjekte mit Objektnummer (z. B. „034“), Datenblatt in Rasterfeldern, eckige Karten mit 1.5-pt-Linie in Textfarbe, Mono-Feldbeschriftungen in Versalien, Strichcode als Dekor.
- **Hardware-Instrument:** Kamera-Funktionen sind Bedienelemente: Tasten mit Radius 14 und Schlagschatten, Status-LEDs, Drehregler mit Skala, eckige Schalter, ein Geräte-Panel.
- **Signalfarbe Klein-Blau** – die einzige Akzentfarbe. Farbe sonst nur für Filmsimulationen.
- Hell und dunkel gleichwertig, folgt dem System.

Regeln: Werte nur durch Abstand trennen, **kein „·“ als Trenner**. Keine Verläufe, Texturen oder dekorative Unschärfe. **Ausnahme:** Systemmaterial bzw. Liquid Glass für schwebende Leisten (Tab-Bar, FloatingActionBar) und das App-Icon (Icon Composer) ist erlaubt, sonst nirgends. **Keine Anspielungen auf Leica** (Skalen, Typo, Rot). Touch-Ziele ≥ 44 pt, Kontrast Text ≥ 4.5:1 (große Zahlen ≥ 3:1).

## Farben (semantische Tokens)

| Token | Hell | Dunkel | Verwendung |
|---|---|---|---|
| `background` (Gehäuse) | `#E8E7E3` | `#0F0F0F` | Screen-Grund |
| `surface` (Karte) | `#F7F7F4` | `#1A1A19` | Archivkarten, Listen |
| `panel` | `#DAD9D4` | `#232322` | Geräte-Panel, Suchfeld, aktiver Tab-Hintergrund |
| `key` (Taste) | `#F7F7F4` | `#2A2A29` | Fläche inaktiver Tasten |
| `keyShadow` | `#000` @ 18 % | `#000` @ 60 % | Schlagschatten unter Tasten (y 2–3, kein Blur) |
| `separator` | `#C6C5BF` | `#363634` | feine Linien in Datenblättern (1 pt) |
| `rule` | = `textPrimary` | = `textPrimary` | Archiv-Rahmen und Tabellenlinien (1.5 pt) |
| `textPrimary` | `#121212` | `#F2F2EF` | Text |
| `textSecondary` | `#5A5954` | `#9E9D98` | Feldlabels, Metazeilen |
| `signal` | `#1F3BD6` | `#3350F0` | aktive Taste, Primär-Button, Schalter an, LED |
| `onSignal` | `#FFFFFF` | `#FFFFFF` | Text/Icons auf `signal` |
| `signalText` | `#1F3BD6` | `#7D93FF` | Signal als Text: Objektnummern, Zähler, aktiver Tab |
| `knob` | `#1E1E1E` | `#E8E7E3` | Drehregler-Körper |
| `knobMark` | `#7D93FF` | `#1F3BD6` | Zeiger auf dem Regler |
| `ledOff` | `#BDBCB6` | `#4A4A47` | LED aus |
| `ledOK` | `#3FD07A` | `#3FD07A` | Verbindung steht |
| `danger` | Systemrot | Systemrot | nur zerstörende Aktionen (Löschen), über `role: .destructive`; nie als Deko |
| `chromeGlass` | `background` @ 88 % + Material | dito | schwebende Leisten < iOS 26 |

`AccentColor` im Asset-Katalog wird **erst in Phase 5** auf `signal` gesetzt (sonst färbt es sofort alle alten Views um). Umsetzung als Color Sets (Any/Dark) oder Helper `Color(light:dark:)` über `UIColor { traits in … }`.

## Farben der Filmsimulationen
Jede Simulation hat eine feste Farbe mit Kürzel. Verwendung: Farbfläche/Spalte an Rezepten, Kürzel-Badge im Import. Text darauf in der angegebenen Farbe.

| Simulation | Kürzel | Fläche | Text |
|---|---|---|---|
| Provia | PRV | `#8FB8E8` | `#121212` |
| Velvia | VLV | `#D61F69` | `#FFFFFF` |
| Astia | AST | `#F4B6C8` | `#121212` |
| Classic Chrome | CC | `#7E9488` | `#121212` |
| Classic Neg | CN | `#E3A82B` | `#121212` |
| Nostalgic Neg | NN | `#E8743B` | `#121212` |
| Reala Ace | RA | `#3FA06A` | `#121212` |
| Eterna | ETR | `#2E6B5C` | `#FFFFFF` |
| Pro Neg Std | PNS | `#B9B3A6` | `#121212` |
| Pro Neg Hi | PNH | `#C98F84` | `#121212` |
| Eterna Bleach Bypass | EBB | `#8E9A92` | `#121212` |
| Acros (inkl. Ye/R/G-Filter) | ACR | hell `#121212`, dunkel `#F2F2EF` | hell `#FFFFFF`, dunkel `#121212` |
| Monochrom (inkl. Ye/R/G-Filter) | MON | wie ACR | wie ACR |
| Sepia | SEP | `#8A5A3C` | `#FFFFFF` |

Filter-Varianten teilen Kürzel und Farbe ihrer Basis; der Filter erscheint als Wert im Datenblatt. Kommt ein weiterer Enum-Fall dazu: Farbe mit ≥ 4.5:1 für den Text wählen, nicht nahe an `signal`, und hier nachtragen.

Umsetzung: Kürzel und Farben als Extension am bestehenden `FilmSimulation` (`Shared/Models/RecipeEnums.swift`) in der DS-Schicht. Das alte `swatchColor` bleibt bis Phase 5 und wird dann entfernt.

## Typografie
SF Pro und SF Mono über Dynamic Type.

| Token | SwiftUI | Default |
|---|---|---|
| `objectNumber` | `.system(size: 64, weight: .heavy)` + `.monospacedDigit()`, Tracking −0.04 em, `signalText` | 64 Heavy (Liste 26, Kopfzeile 52) |
| `largeTitle` | `.largeTitle.weight(.heavy)`, Tracking −0.03 em | 34 Heavy |
| `title` | `.title.weight(.heavy)` | 28–30 Heavy |
| `headline` | `.headline.weight(.bold)` | 17 Bold |
| `body` | `.body` | 17 |
| `subhead` | `.subheadline` | 15 |
| `fieldLabel` | `.system(size: 9–10, weight: .regular, design: .monospaced)`, Versalien, Tracking 0.1 em, `textSecondary` | Feldbeschriftung |
| `metaMono` | `.system(.caption2, design: .monospaced)`, Versalien, Tracking 0.08 em | Metazeilen, Abschnittsköpfe |
| `valueMono` | `.system(.subheadline, design: .monospaced).weight(.medium)` | 15, Werte („+2“, „R+2  B−5“, „DR200“), echtes Minus `−` |
| `keyLabel` | `.system(size: 17–18, weight: .bold, design: .monospaced)` | Slot-Tasten „C1“ |

Feste Größen (`objectNumber`, `fieldLabel`, `keyLabel`) skalieren über `Font.system(size:weight:design:)` mit `relativeTo:` bzw. `UIFontMetrics`, damit sie mit Dynamic Type mitwachsen. `fieldLabel` nur für kurze Labels über einem Wert.

## Raster, Radien, Linien
- Raster 4 pt: `4 8 12 16 20 24 32`. Seitenrand 16, Abstand zwischen Blöcken 14–16.
- Radien: **Archiv 0** (eckig), Schalter 8 (Knopf 6), **Tasten 14**, Panel 18, Regler und LEDs rund. iOS-Elemente behalten Systemradien.
- Linien: Archivrahmen und Feldtrenner 1.5 pt `rule`; innere Datenblattlinien 1 pt `separator`.

## Komponenten
Alle Komponenten und Dateien tragen das Präfix **DS** (z. B. `DSHardwareKey`, `DSLED`, Dateien `DSColors.swift`, `DSSimulationColors.swift`). Komponenten bekommen Daten nur als Parameter (Objektnummer, Slot-Belegung, Zähler wie „5/7“); woher die Werte kommen, wird beim Ausrollen in Phase 5 entschieden.


**HardwareKey** (`ButtonStyle`) – Radius 14, Fläche `key`, Schatten `0 2–3 0 keyShadow`. Aktiv/gedrückt: Fläche `signal`, Text `onSignal`, Schatten nach innen (`inset 0 2 0 schwarz 18 %`). Varianten: Icon-Taste 44×44, Text-Taste (Höhe 38–44, Mono-Label), Primär (Höhe 52, `signal`, `headline`), Sekundär (`key`).
**LED** – Kreis 6–10 pt. An: `signal` (bzw. `ledOK`), optional Glow 8 pt mit 70 %. Aus: `ledOff`.
**SlotKey** – quadratisch, 4 Spalten, Abstand 10. Oben links „C1“ (`keyLabel`), unten Kurzname 10 pt, oben rechts LED (an = Slot belegt). Ausgewählt = aktiver HardwareKey. Letzte Kachel: gestrichelter Rahmen „Import  N neu“.
**Knob** (nur Anzeige, später evtl. Eingabe) – 76 pt Feld, 11 Skalenstriche (2×6 pt, `textSecondary`) von −135° bis +135°, Körper 54 pt `knob`, Zeiger 4×14 `knobMark`. Darunter `fieldLabel` + `valueMono`. Bereiche: Farbe/Ton −4…+4 linear; Stufen (Korn, DR) gleichmäßig verteilt.
**HardwareSwitch** – 56×32, Radius 8, Spur an = `textPrimary` (hell dunkel, im Dunkelmodus hell), aus = `ledOff`; Knopf 26×26 Radius 6: an = `signal` rechts, aus = weiß links. Basiert auf `Toggle` mit eigenem `ToggleStyle`.
**DevicePanel** – Radius 18, Fläche `panel`, feine Lichtkante oben. Inhalt: Kameraname (20 Heavy), Mono-Zeile „FW 1.31   USB   RAW CONV.-MODUS“, rechts LEDs mit Mono-Label (LINK, R/W).
**ArchiveCard** – eckig, Rahmen 1.5 `rule`, Fläche `surface`. Aufbau Rezept-Detail: Kopf (Objektnummer links | Seitenfelder SLOT/ROLL/ERSTELLT rechts) → Titel + Beschreibung → Simulationsfläche (Höhe 64, Name 22 Heavy, Kürzel rechts) → Datenblatt 2-spaltig (`fieldLabel` + `valueMono`) → Fuß (Strichcode + „X100VI  WIE GESCHRIEBEN“).
**DataFieldRow** – Reihe gleich breiter Felder mit `fieldLabel` über `valueMono`, getrennt durch 1.5-pt-Linien (z. B. ARCHIV 024 | KAMERA 5/7; QUELLE | MODUS | AUSWAHL).
**RecipeRow** – Grid: Simulationsspalte 52 pt (Kürzel oben, Nummer unten) | Name (`headline`, 1 Zeile) + `metaMono` | Slot-Badge (kleine HardwareKey-Optik mit LED + „C1“). Zeilen getrennt durch 1.5 pt, gesamte Liste in einem Archivrahmen.
**Barcode** – rein dekorativ, aus der Rezept-ID deterministisch erzeugte Strichbreiten 1–3 pt, Höhe 24–28, `accessibilityHidden(true)`.
**ContactSheet** (Import) – 3 Spalten, Abstand 3 auf `textPrimary`-Grund im Archivrahmen. Kachel: Bildnummer unten links (Mono 10 auf Schwarz), Simulations-Kürzel oben links (Farbe der Simulation), Auswahlkästchen oben rechts (20 pt, Radius 5, weißer Rand, an = `signal` mit weißem Haken). Abgewählt = 40 % Deckkraft. Tageskopf `metaMono` mit Bildbereich rechts („0142–0150“).
**Tag** – eckig, Rahmen 1.5, `metaMono` 11 Bold (z. B. Roll STREET).
**FloatingActionBar** – unten, Material/Glass, Trennlinie oben, Mono-Statuszeile (z. B. „ZIEL C3   SCHREIBEN  ZURÜCKLESEN  PRÜFEN“) + Primär-Taste.

## Screens (Referenz-PNGs folgen in `docs/fork/design/`; bis dahin gilt der Text)
1. **Recipes** – Toolbar mit Systemknöpfen (unter iOS 26 Glas, „+“ darf Glas-Knopf mit blauem Symbol sein), Large Title + DataFieldRow (ARCHIV | KAMERA), eine horizontal scrollende Reihe Text-Tasten mit LED: zuerst die Filter (Alle, Favoriten, Kameras, Filmsimulationen), dann nach einem Trenner die Rolls; genau eine Taste aktiv. RecipeRow-Liste. **Suche bleibt unten** (Daumenbereich, iOS-26-Muster). System-Tab-Bar mit den vier Tabs aus v2.4.
2. **Rezept-Detail** – ArchiveCard wie oben, Tags, FloatingActionBar „Auf Kamera laden“ + Teilen.
3. **Camera** – Large Title, DevicePanel, SlotKey-Raster C1–C7 + Import-Kachel, Archivkarte des gewählten Slots mit drei Knobs (FARBE, KORN, DYNAMIK), FloatingActionBar „Rezept in C3 laden“ + „Rückgängig“.
4. **Light Table (Import)** – DataFieldRow (QUELLE | MODUS | AUSWAHL n/m), Panel „Standort aus Aufzeichnung“ mit HardwareSwitch, ContactSheet nach Tagen, FloatingActionBar mit Ziel + „N Bilder importieren“, oben „ALLE/KEINE“.
5. **Rolls** und **Darkroom** – Layout noch zu entwerfen.

## App-Icon (v2.6, fertig)
**Konzept:** Die Rezeptkarte der App (Archivkarte mit Nummernfeld, Datenzeilen und Strichcode) steckt in einem Entwicklertank und wird im Klein-blauen Bad „entwickelt“ – so wie die App Rezepte auf die Kamera bringt. Eine runde Lasche mit Loch oben an der Karte. Die Flüssigkeit ist durchscheinend: Der eingetauchte Teil der Karte bleibt sichtbar.

**Dateien:**
- **Endprodukt:** `docs/fork/design/app-icon/AppIcon.icon` (Icon Composer, iOS Only). Eingebunden als `FujiCookbook/AppIcon.icon` im App-Target (PR #10).
- **Quelle der Form:** Figma „Darkslide – App Icon“ (`https://www.figma.com/design/qkORPBcI3u7AgiUcpxgns0`), Seite „App Icon“: Komponente „Darkslide App Icon“ mit Variablen-Sammlung „Darkslide Icon“ (Modi Default/Dark/Mono, iOS-Code-Syntax `DSIcon.*`), Fläche „Preview“ (Maske, Größen 360–29 pt), Fläche „Icon Composer Export“ (acht SVG-Ebenen).
- Skizzen und verworfene Varianten (A–I): Design-Fläche „Darkslide – App-Icon Skizzen“ (claude.ai). Das Dumpling-Icon aus v2.3 ist verworfen; die Datei „Fuji Cookbook – App Icon“ ist nur noch Archiv.

**Geometrie (Raster 1024 px, ohne Maske – die Maske setzt das System):**
- Tank: U-Form, außen x 152–872, y 460–880, Radius 64; Wand 28 px, innen Radius 40, oben offen.
- Karte: x 272–752, y 190–810 (480 × 620), eckig, Rahmen 20 px. Lasche: Kreis Mittelpunkt (512, 190), außen r 78, innen r 58, Loch r 26 (ausgestanzt).
- Karteninhalt: Nummernfeld 124 × 86 in Signal oben links (x 324, y 242); Trennlinie 12 px bei y 360; drei Datenzeilen zweispaltig (Höhe 20, Radius 4) ab y 400 im 48er-Abstand; Strichcode 11 Balken, Höhe 80, ab y 678.
- Flüssigkeit: innen im Tank, Oberkante y 590, mit 16 px kräftiger Oberflächenlinie.

**Ebenen in Icon Composer** – je Farbe eine Ebene, damit Dark pro Ebene umgefärbt werden kann. In der Seitenleiste steht oben, was vorne liegt.

| Gruppe | Ebenen (oben → unten) | Liquid Glass |
|---|---|---|
| **3 Liquid** (vorne) | `3_liquid-2-surface`, `3_liquid-1-body` (Opacity 62 % in allen Erscheinungen) | Translucency an, 40 %; Shadow neutral 50 % |
| **2 Card** | `2_card-5-lines`, `2_card-4-data`, `2_card-3-number`, `2_card-2-surface`, `2_card-1-frame` | Translucency aus; Shadow neutral 50 % |
| **1 Tank** (hinten) | `1_tank` | Translucency aus; Shadow neutral 50 % |

Ebenen-Farben kommen in Default aus den SVGs (Fill „Automatic“). Hintergrund ist keine Ebene, sondern die Füllung des Icons.

**Farben je Erscheinung:**

| Element | Default (SVG) | Dark (Override) |
|---|---|---|
| Hintergrund | `#E8E7E3` | `#0F0F0F` |
| Tank, Kartenrahmen | `#121212` | **`#4A4A47`** (heller als `ink`, damit der Tank auf Schwarz sichtbar bleibt) |
| Linie + Strichcode (`card-5-lines`) | `#121212` | `#3A3A38` |
| Kartenfläche | `#F7F7F4` | `#F2F2EF` |
| Nummernfeld, Flüssigkeit | `#1F3BD6` | `#3350F0` |
| Datenzeilen | `#5A5954` | `#9E9D98` |

**Mono** (Clear/Tinted): automatische Ableitung von Icon Composer, keine eigenen Werte. Der Hintergrund ist in Mono nicht editierbar.

Hinweis: Die Figma-Variable `icon/ink` steht in Dark noch auf `#3A3A38` für alle Strukturen; maßgeblich für Tank und Rahmen ist `#4A4A47` aus `AppIcon.icon`.

**Einbinden in Xcode:** `AppIcon.icon` aus `docs/fork/design/app-icon/` in den App-Ordner kopieren (neben den Asset-Katalog, nicht hinein), im Project Navigator dem App-Target zuordnen; unter Target › General › App Icons muss das Feld „App Icon“ `AppIcon` lauten. Die `.icon`-Datei ersetzt das bisherige Icon aus dem Asset-Katalog; Bilder für iOS < 26 erzeugt Xcode beim Build.

**Regeln:** Kein Text, keine Fujifilm-Marke, kein Kameramotiv, kein Rot. Kernform in allen Erscheinungen gleich, nur Farben wechseln. Die Datenzeilen bleiben auch in kleinen Größen.

## Daten hinter der Oberfläche
- **Feld KAMERA / Slot-Badges:** zeigen den zuletzt ausgelesenen Stand der Kamera (z. B. „5/7“, „C1“). Ohne Verbindung: LED aus, Zusatz „STAND tt.mm.“. Nie ausgelesen: „—“, keine Badges.
- **Archivnummer:** fortlaufend nach `createdAt`, fest gespeichert, gelöschte Nummern werden nicht neu vergeben. Im **Backup** enthalten und bei Wiederherstellung beibehalten (bei Kollision nächste freie). In **geteilten `.fujirecipe`-Dateien nicht enthalten** – Import vergibt die nächste freie Nummer. iCloud-Duplikat: das Rezept mit dem älteren `createdAt` behält die Nummer, das andere bekommt die nächste freie.
- **Übergang:** Bis zum Ende von Phase 5 ist ein gemischter Zustand (alte Tab-Leiste, alte Screens mit neuem Blau in Systemknöpfen) akzeptiert.

## Umsetzungsregeln für Phase 1
- Tokens zentral: `FujiCookbook/DesignSystem/` (`DSColors.swift`, `DSSimulationColors.swift`, `DSTypography.swift`, `DSMetrics.swift`, `Components/…`). v2 **ersetzt** v1 vollständig; v1-Typen werden entfernt. Nach `Shared/` nur, was die ShareExtension braucht.
- Komponenten als `ButtonStyle`, `ToggleStyle`, `ViewModifier` und kleine Views; keine hartkodierten Farben/Fonts in Views.
- Simulationsfarben an das bestehende Filmsimulations-Enum hängen (eine Quelle der Wahrheit).
- **Phase 1 = Fundament + Komponenten + Galerie-Screen** (unter Settings ▸ Diagnostics), hell und dunkel, plus SwiftUI-Previews. Views, die schon v1 nutzen (`PhotoImportView`, `LocationTrackView`), nur so weit anpassen, dass sie mit v2 kompilieren – neue Tokens und Komponenten, kein neues Layout. Alle anderen Views erst in Phase 5.
- Share Cards samt `CardPalette` sind entfernt (PR #11).
