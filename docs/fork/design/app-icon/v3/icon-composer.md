# Darkslide App-Icon v3 (K1 „Lichtnetz“) – Icon Composer

Alle SVGs: 1024 × 1024 px, nur Flächen, keine Maske (die setzt das System). Alle Formen sitzen bereits an der richtigen Stelle, also nichts verschieben oder skalieren.

## 1. Neues Dokument
- File › New, Plattform **iOS**.
- **Hintergrund (Fill):** Solid `#1F3BD6`. Unter Dark überschreiben mit `#16278F`.

## 2. Gruppen und Ebenen
In der Seitenleiste steht oben, was vorne liegt. Zuerst hinzugefügt = hinten.

| Gruppe (oben → unten) | Ebenen (oben → unten) | Liquid Glass |
|---|---|---|
| **3 Card** (vorne) | `3_card-5-lines`, `3_card-4-data`, `3_card-3-number`, `3_card-2-surface`, `3_card-1-frame` | Translucency aus, Specular an, Shadow **aus** |
| **2 Shadow** | `2_shadow` | Glass aus, Translucency aus, Shadow aus |
| **1 Background** (hinten) | `1_background-light` | Glass aus, Translucency aus, Shadow aus |

Der Schatten ist bewusst eine eigene, flache Ebene. Die Shadow-Funktion von Icon Composer bleibt deshalb überall aus, sonst ist der Schatten doppelt. Wenn die Karte zu flach wirkt: bei Gruppe 3 Shadow „Neutral“ mit höchstens 25 % testen.

Bei Fill aller Ebenen „Automatic“ lassen (die Farbe kommt aus der SVG).

## 3. Farben je Erscheinung

| Ebene | Default (aus SVG) | Dark (Override) |
|---|---|---|
| Hintergrund (Fill) | `#1F3BD6` | `#16278F` |
| `1_background-light` | `#4762F2` | `#2A45C9` |
| `2_shadow` | `#1830BC` | `#0F1D72` |
| `3_card-1-frame` | `#121212` | `#121212` (bleibt) |
| `3_card-2-surface` | `#F7F7F4` | `#F2F2EF` |
| `3_card-3-number` | `#1F3BD6` | `#3350F0` |
| `3_card-4-data` | `#5A5954` | `#9E9D98` |
| `3_card-5-lines` | `#121212` | `#3A3A38` |

**Mono (Clear/Tinted):** automatisch lassen. Danach prüfen, ob das Lichtnetz in Tinted noch als feines Muster lesbar ist. Wenn es zu laut wird: bei `1_background-light` in Mono die Opacity auf etwa 50 % senken.

## 4. Prüfen in der Vorschau
- Das Loch in der Lasche ist durchsichtig: Man sieht Lichtnetz und einen Teil vom Schatten, keinen farbigen Punkt.
- Kein Element läuft in die Maskenecken.
- 29 pt: Karte, Nummernfeld und Strichcode sind noch erkennbar.

## 5. Speichern
Als `AppIcon.icon` speichern und die bisherige Datei ersetzen (`docs/fork/design/app-icon/AppIcon.icon` und `FujiCookbook/AppIcon.icon`). Name und Build-Setting bleiben `AppIcon`, in Xcode muss nichts umgestellt werden.
