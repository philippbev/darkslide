# Fuji Cookbook Fork – Design-System v0.1

Stand: 13.11.2026. Quelle: Canvas „Fuji Cookbook – Design-Richtung“ (claude.ai). Ablage im Repo: `docs/fork/design-system.md`.

## Richtung
**iOS-nativ mit Details aus dem Fotolabor.** Hell und dunkel gleichwertig, folgt dem System.

1. **System zuerst:** SF Pro, native `List`/`Form`/Sheets/NavigationStack, iOS-26-Tab-Leiste (Liquid Glass, ab iOS 26 hinter Availability-Check; iOS 17–25 Standard-TabView). Keine eigenen Nachbauten von Systemkomponenten.
2. **Labor-Details:** Mono-Labels in Versalien wie der Aufdruck am Filmrand; Einstellungswerte in Mono; Teststreifen statt Beispielfoto; Import als Kontaktbogen mit Bildnummern.
3. **Hell und dunkel:** warmes „Papier“ hell, „Dunkelkammer“ dunkel. Ein einziger Akzent: **Safelight** (Orange, angelehnt an das Labor-Rotlicht).

Regeln: Werte nur durch Abstand trennen, **kein „·“ als Trenner**. Keine Texturen, Verläufe oder Filmkorn-Overlays. Touch-Ziele ≥ 44 pt. Kontrast Text ≥ 4.5:1.

## Farben (semantische Tokens)

| Token | Hell | Dunkel | Verwendung |
|---|---|---|---|
| `background` | `#F4F2ED` | `#111110` | Screen-Grund |
| `surface` | `#FFFFFF` | `#1C1B19` | Karten, gruppierte Listen |
| `surfaceSecondary` | `#EAE7E0` | `#262522` | Chips, Suchfeld, runde Icon-Buttons, Sekundär-Button |
| `separator` | `#DDD9D0` | `#2E2D2A` | Trennlinien, Ränder |
| `textPrimary` | `#1B1A18` | `#F3F0EA` | Text |
| `textSecondary` | `#625E56` | `#A6A096` | Sekundärtext, Labels |
| `accent` (Safelight) | `#C2410C` | `#FF7A45` | Primär-Button, Toggle an, Auswahl |
| `onAccent` | `#FFFFFF` | `#1B1A18` | Text/Icons auf `accent` |
| `accentText` | `#A8360A` | `#FF9B70` | Akzent als Text/Outline (Slot-Badge, aktiver Tab) |
| `accentSoft` | `#F6E3D8` | `#3A2117` | Hinterlegte Hinweise („Läuft auf X100VI …“) |
| `success` | `#2F8F4E` | `#5BC27A` | Verbindungsstatus |
| `chromeGlass` | `#FFFFFF` @ 78 % | `#1C1B19` @ 78 % | Fallback-Hintergrund für schwebende Leisten < iOS 26 (mit Material) |

Umsetzung: Color Sets im Asset-Katalog (Any/Dark) **oder** `Color(light:dark:)`-Helper über `UIColor { traits in … }`. `AccentColor` im Asset-Katalog auf Safelight setzen, damit native Controls (Toggle, Links) automatisch passen.

## Typografie
SF Pro über Dynamic-Type-Styles (skaliert mit Systemgröße). Mono = SF Mono (`.monospaced()` bzw. `design: .monospaced`).

| Token | SwiftUI | Größe/Gewicht (Default) |
|---|---|---|
| `largeTitle` | `.largeTitle.bold()` | 34 Bold |
| `title` | `.title2.weight(.semibold)` | 22 Semibold |
| `headline` | `.headline` | 17 Semibold |
| `body` | `.body` | 17 Regular |
| `subhead` | `.subheadline` | 15 Regular |
| `footnote` | `.footnote` | 13 Regular |
| `labelMono` | `.system(.caption2, design: .monospaced).weight(.medium)` + `.textCase(.uppercase)` + `.tracking(1.1)` | 11, Versalien, Sperrung 0.1 em |
| `valueMono` | `.system(.subheadline, design: .monospaced)` | 15 |

Mono-Labels: Kontext über dem Titel („CLASSIC CHROME   SLOT C1“), Abschnittsüberschriften („FARBE“, „HEUTE   13. NOVEMBER“), Metazeilen in Listen. Werte (z. B. „+2“, „R+2  B−5“, „DR200“) immer `valueMono`, echtes Minuszeichen `−`.

## Abstände & Radien
- Raster 4 pt. Skala: `xs 4`, `s 8`, `m 12`, `l 16`, `xl 20`, `xxl 24`, `xxxl 32`.
- Seitenrand 16, Kartenabstand 12–16, Abschnittsabstand 20–24, Zeilenhöhe Einstellungen 46.
- Radien: `badge 8`, `image 12`, `card 16`, `sheet 22`, `capsule` (Buttons, Chips, runde Icon-Buttons).

## Komponenten

**Primär-Button** – Kapsel, Höhe 50, `accent`/`onAccent`, `headline`. Ein Primär-Button pro Screen, unten in schwebender Leiste.
**Sekundär-Button** – Kapsel, `surfaceSecondary`/`textPrimary`.
**Runder Icon-Button** – 44×44, Kapsel, `surfaceSecondary`; Primäraktion (z. B. „+“) in `accent`.
**Chip (Kapitel-Filter)** – Kapsel, Höhe 36, `subhead` Medium. Aus: `surfaceSecondary`/`textPrimary`. An: invertiert (`textPrimary` als Grund, `background` als Text). Horizontal scrollend.
**Slot-Badge** – „C1“…„C7“, `valueMono` 13 Medium, Rand 1.5 `accent`, Text `accentText`, Radius 8.
**Hinweis-Pill** – Höhe 32, Kapsel, `accentSoft`/`accentText`, Icon + `footnote` Semibold.
**Teststreifen** – fünf gleich breite Farbfelder (Tiefen → Lichter), ohne Abstand, Radius `image`. Größen: 56×56 in Listen, volle Breite × 120 im Detail mit Mono-Beschriftung „TIEFEN  MITTELTÖNE  LICHTER“. Farben vorerst pro Filmsimulation aus einer festen Tabelle; Berechnung aus den Einstellungen ist ein späterer Schritt.
**Rezept-Zeile** – Teststreifen 56 + Name (`headline`, eine Zeile) + Metazeile (`labelMono`, z. B. „CLASSIC CHROME   KORN SCHWACH“) + optional Slot-Badge rechts. In gruppierter Karte (`surface`, Radius 16), Trennlinie `separator`.
**Einstellungs-Gruppe** – Mono-Überschrift über einer Karte; Zeilen: Label `subhead`/`textSecondary` links, Wert `valueMono` rechts, Höhe 46.
**Status-Karte** – `surface`, Radius 16, Icon in 44er-Kachel (`surfaceSecondary` bzw. `accentSoft`), Titel + Mono-Metazeile, rechts Status-Punkt (`success`) oder Toggle.
**Kontaktbogen-Kachel** (Import) – quadratisch, 3 Spalten, Abstand 4, Radius 8. Bildnummer unten links (Mono 10, weiß), Format-Badge oben links („RAF+JPG“, Mono 9 auf schwarz 45 %), Auswahlkreis oben rechts (22, weißer Rand, an = `accent` mit Haken). Nicht ausgewählt = 45 % Deckkraft. Tagesüberschrift als `labelMono`.
**Schwebende Aktionsleiste** – unten, Material/Glass, obere Trennlinie, Innenabstand 16, enthält Primär-Button (+ ggf. Zusatzzeile wie „Ziel  Fotos-Mediathek“).
**Tab-Leiste** – Rezepte, Kapitel, Kamera, Küche. iOS 26: System-Tab-Bar (Liquid Glass). Aktiver Tab in `accentText` über `AccentColor`.

## Screens (Referenz)
1. **Rezepte** – Kopfzeile mit Einstellungen + „Neues Rezept“, Mono-Kontext „X100VI   24 REZEPTE   5 IN DER KAMERA“, Large Title, Suche, Kapitel-Chips, gruppierte Rezept-Liste.
2. **Rezept-Detail** – Teststreifen groß, Mono-Kontext (Filmsimulation + Slot), Titel, Kurzbeschreibung, Pills (Kompatibilität, Kapitel), Einstellungs-Gruppen FARBE / TON / DETAIL, Aktionsleiste „Auf Kamera übertragen“ + Teilen.
3. **Import** (neu, im Kamera-Tab) – Status-Karte Kamera (Modus!), Status-Karte Standort mit Toggle, Kontaktbogen nach Tagen, Aktionsleiste mit Ziel und „N Fotos importieren“. Oben „Alle/Keine“.

## Umsetzungsregeln für Phase 1
- Tokens zentral anlegen, z. B. `FujiCookbook/DesignSystem/` (`Colors.swift`, `Typography.swift`, `Spacing.swift`, `Components/…`). Ggf. nach `Shared/`, falls die ShareExtension sie braucht.
- Komponenten als wiederverwendbare Views/`ButtonStyle`s/`ViewModifier`s.
- **Phase 1 = nur Fundament + Komponenten + eine Vorschau-Galerie** (SwiftUI-Previews oder ein Debug-Screen „Design System“ unter Diagnostics). Bestehende Views erst in Phase 5 migrieren.
- `CardPalette` der Share Cards vorerst unverändert lassen.
- Keine hartkodierten Farben/Fonts in neuen Views.
