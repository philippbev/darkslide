# Phase 3 – Testprotokoll (USB-Import + Geotagging Stufe A)

Gerätetest mit iPhone und X100VI. Ergebnis je Punkt eintragen: ✅ / ❌ / ⚠️ + Notiz. Bei ❌: Settings ▸ Diagnostics ▸ Bericht kopieren und mit dem Punkt-Nr. ablegen.

| | |
|---|---|
| Datum | 2026-11-15 |
| Build (Commit) | `19a9c82` (Branch `docs/phase-3-test-protocol`) |
| iPhone / iOS | iPhone Duo / iOS 27.2.1 |
| X100VI Firmware | 1.31 |
| Karte (Größe, Anzahl Fotos ca.) | 256 GB / 2.273 Fotos |
| Dateiformat-Einstellung der Kamera | RAW+JPEG |

## Vorbereitung
- [ ] Testordner in Dateien anlegen (z. B. „Darkslide Test“), Fotos-Mediathek: Album zum späteren Aufräumen merken.
- [x] Kamerauhr gegen iPhone prüfen: iPhone-Uhr fotografieren, Abweichung notieren: keine
- [ ] Mindestens ein Testtag mit **RAW+JPEG**, ein paar Bilder **nur RAW** und ein kurzes **Video** auf der Karte.

## A. Track aufzeichnen (unterwegs, vor dem Fotografieren)
Camera-Tab ▸ **Location Track** ▸ Start Recording.

| # | Schritt | Erwartet | Ergebnis |
|---|---|---|---|
| A1 | Erstes Start Recording | Dialog „Beim Verwenden der App“; danach „Recording“, Zeile im Camera-Tab heißt „Location Track (Recording)“ | — nicht getestet (Tracking bewusst ausgelassen) |
| A2 | Bildschirm sperren, 20–30 min gehen und fotografieren | Ortungsanzeige (Pfeil/blaue Pille) bleibt sichtbar; Aufzeichnung läuft weiter | — nicht getestet |
| A3 | App in den Hintergrund, andere Apps nutzen | Aufzeichnung läuft weiter | — nicht getestet |
| A4 | Stop Recording | Track in der Liste mit Dauer und Punktzahl, plausibel (grob 1 Punkt je 10 m) | — nicht getestet |
| A5 | Zweiten Track starten, App per App-Umschalter **beenden**, neu öffnen | Track ist geschlossen, endet am letzten Punkt; nichts geht verloren außer max. den letzten ~10 Punkten | — nicht getestet |
| A6 | Akku: Verbrauch für 30 min Aufzeichnung (Einstellungen ▸ Batterie) | notieren: ____ % | — nicht getestet |
| A7 | Ortung für Darkslide in Einstellungen auf „Nie“, Start Recording | Fehlertext „Location access is off …“ | — nicht getestet |

## B. Verbinden und Kartenmodus
| # | Schritt | Erwartet | Ergebnis |
|---|---|---|---|
| B1 | Kamera im Modus **USB RAW Conv./Backup Restore**, „Connect Camera (USB)“ verbinden, dann „Import Photos (USB)“ | Hinweis: erst im Camera-Tab trennen, Import braucht anderen USB-Modus | ⚠️ Hinweis kommt. Aber ein „Report a Problem“ (Herkunft Fuji Cookbook) wird noch angezeigt, obwohl `reportsEnabled = false` – Stelle noch offen |
| B2 | Trennen, Import Photos (USB) mit Kamera immer noch im RAW-Conv.-Modus | „The camera lists no photos …“ mit Anleitung zu **USB Card Reader** (oder klare andere Meldung) – Text notieren | ❌ Keine klare Meldung: Es bleibt bei „The photos appear as soon as the camera lists the first ones.“, kein Hinweis auf USB Card Reader |
| B3 | Kamera: Network/USB Setting ▸ Connection Mode ▸ **USB Card Reader**, Import Photos (USB) | Dialog Kamerazugriff (beim ersten Mal), dann „Reading the card …“ | ✅ Erst „The camera is indexing its card …“, danach funktioniert es |
| B4 | Ohne Kabel Import Photos (USB) | „No camera detected …“ | ✅ Fehlermeldung nach kurzer Zeit |
| B5 | Stimmt der Menüpfad im Hinweistext mit der X100VI überein? | genaue Bezeichnung auf der Kamera notieren: __________ | ✅ Menüpfad stimmt |

## C. Light Table: Listing und Geschwindigkeit
| # | Schritt | Erwartet | Ergebnis |
|---|---|---|---|
| C1 | Zeit von Tippen bis erste Kacheln sichtbar | wenige Sekunden (vorher ImageCaptureCore: ~2 min bei 2.000 Fotos) – messen: ____ s | ⚠️ 61 s (14:47:27 → 14:48:28), Indexierung der Kamera. Außerdem: Button heißt „Import Photos“, der Screen danach „Light Table“ – nicht gut kommuniziert |
| C2 | **Neueste zuerst:** oberster Tag = letzter Aufnahmetag, innerhalb des Tages richtige Reihenfolge | ✅ bestätigt die Annahme „höchste PTP-Handles = neueste“ | ❌ Oberster Tag stimmt, aber innerhalb eines Tages stehen die ältesten Fotos oben (Code sortiert absichtlich „in the order taken“) |
| C3 | Während „still being read“: schon auswählen/importieren möglich | ja, Hinweistext sichtbar | ✅ Auswählen/Importieren geht, Hinweistext nicht gesehen |
| C4 | Ans Ende scrollen ▸ „Load Older Photos“ | nächste ~300 Dateien kommen, Zeit: ____ s | ✅ sehr schnell |
| C5 | Vorschaubilder laden flüssig beim Scrollen | keine Hänger, Platzhalter werden ersetzt | ⚠️ Flüssig, aber nach „Load Older Photos“ springt die Liste hoch zu „Select Day“ (Tag 83) |
| C6 | Simulationscode auf Kacheln (z. B. CC, AC, CH) | passt zur Einstellung beim Fotografieren (Stichprobe 3 Bilder) | ✅ |
| C7 | RAW+JPEG-Paar erscheint als **eine** Kachel | ja | ✅ |
| C8 | Filter Dateien: RAW / JPEG/HEIF / RAW + JPEG/HEIF | Kacheln ohne passende Datei verschwinden; Auswahl wird mit gefiltert | ✅ Filter funktionieren (Frage zu RAW+JPEG in Fotos: siehe D2) |
| C9 | Choose Days ▸ einen Tag ▸ Show | nur dieser Tag | ✅ |
| C10 | „Select Day“ am Tageskopf, „All“, „None“ | korrekt | ✅ |
| C11 | Kabel während des Listings ziehen | bereits Gelistetes bleibt, Meldung zum Abbruch; kein Absturz | ✅ Meldung kommt, kein Absturz |

## D. Import in die Fotos-Mediathek
| # | Schritt | Erwartet | Ergebnis |
|---|---|---|---|
| D1 | Erster Import, Ziel Photo Library | Dialog „Fotos hinzufügen“ (nur Hinzufügen) | ✅ |
| D2 | 10 Fotos RAW+JPEG importieren, Zeit messen | ____ s gesamt, Fortschritt „Importing x of 10“ | ✅ sehr schnell. In Fotos ein Eintrag „RAW+JPEG“; der RAF liegt als zweite Ressource im selben Asset (so gewollt, siehe Befunde) |
| D3 | In Fotos: ein Eintrag pro Paar, Badge „RAW+JPEG“ | ja; Originaldateiname DSCFxxxx | ✅ DSCF7123 |
| D4 | EXIF in Fotos (Info-Panel): Kamera, Objektiv, Belichtung, Aufnahmezeit | unverändert wie von der Kamera | — nicht getestet |
| D5 | Nur-RAW-Bild importieren | erscheint als RAW-Foto | ✅ |
| D6 | Video importieren | erscheint als Video | — nicht getestet |
| D7 | Light Table erneut öffnen | importierte Fotos sind ausgeblendet („nur neue“); Umschalten zeigt sie als bereits importiert | ✅ |
| D8 | Import mittendrin abbrechen | Zusammenfassung „cancelled“; Bereits importierte zählen, Rest bleibt ausgewählt | ✅ |
| D9 | Fotozugriff in Einstellungen entziehen, importieren | Fehlertext „Photo library access is off …“ pro Frame | ✅ „0 photos copied … 6 couldn't be copied: DSCF7119.JPG: Photo library access is off …“ |

## E. Import in einen Ordner (Dateien)
| # | Schritt | Erwartet | Ergebnis |
|---|---|---|---|
| E1 | Destination ▸ Choose Folder… ▸ Testordner | Ziel zeigt Ordnernamen | ✅ |
| E2 | 5 RAW+JPEG importieren | je `DSCFxxxx.RAF` + `.JPG`, Originalgröße, Bytes identisch zur Karte | ⚠️ RAF und JPG liegen im Ordner, die Zusammenfassung sagt aber „1 photo“ (zählt Frames, nicht Dateien) |
| E3 | App neu starten, Light Table öffnen | Zielordner ist noch gewählt | ✅ Nach Neustart wieder „Photo Library“ – Philipp findet das gut so |
| E4 | Dieselben Fotos erneut importieren („nur neue“ aus) | keine Duplikate (gleiche Größe = übersprungen) | ✅ |
| E5 | iCloud-Drive-Ordner als Ziel | funktioniert | ✅ |
| E6 | (optional) USB-Stick/SSD am iPhone als Ziel, danach abziehen und Light Table öffnen | Import klappt; ohne Stick verständliche Meldung | — nicht getestet |

## F. Geotagging
Voraussetzung: Track aus A, Fotos während der Aufzeichnung.

| # | Schritt | Erwartet | Ergebnis |
|---|---|---|---|
| F1 | Light Table öffnen | Panel „Location from Track“, „Add Location“ ist an | — nicht getestet |
| F2 | Camera Clock zeigt In Sync bzw. gemessene Abweichung aus der Vorbereitung eintragen | Tag „Camera Clock …“ korrekt | — nicht getestet |
| F3 | Import in **Fotos** | Zusammenfassung nennt Anzahl verorteter Fotos; Karte in Fotos zeigt Bilder auf der gelaufenen Strecke | — nicht getestet |
| F4 | Genauigkeit: 3 Bilder an markanten Orten prüfen | Abweichung ≤ ca. 30 m – notieren | — nicht getestet |
| F5 | Import in **Ordner**: JPEG/HEIF | GPS steckt im JPEG selbst (Fotos-App/Dateien-Info oder am Mac `exiftool`/Vorschau ▸ Informationen) | — nicht getestet |
| F6 | Ordner: RAF | Datei `DSCFxxxx.xmp` daneben; RAF unverändert | — nicht getestet |
| F7 | XMP am Mac in Lightroom/Bridge (oder `exiftool DSCFxxxx.xmp`) | Position wird gelesen | — nicht getestet |
| F8 | JPEG-Bildqualität nach Geotag | Dateigröße nahezu gleich, keine Neukompression (Stichprobe) | — nicht getestet |
| F9 | Foto **außerhalb** jeder Aufzeichnung (> 5 min Abstand) | wird nicht verortet (lieber keine Position als eine falsche) | — nicht getestet |
| F10 | Kamerauhr absichtlich +1 h stellen, Fotos machen, Light Table | Tag „Clock Ahead?“ erscheint; mit Offset „Ahead 1 h“ werden die Fotos richtig verortet | — nicht getestet |
| F11 | Ohne aufgezeichnete Tracks | „Add Location“ aus und nicht schaltbar | — nicht getestet |
| F12 | Zeitzone: schreibt die X100VI `OffsetTimeOriginal` (fw ≥ ?) | im EXIF eines JPEG prüfen, notieren | — nicht getestet |

## G. Rückweg zu Rezepten
| # | Schritt | Erwartet | Ergebnis |
|---|---|---|---|
| G1 | Light Table schließen, Kamera zurück auf USB RAW Conv./Backup Restore, Connect Camera | Rezepte/Slots lesen wie gewohnt | ✅ |
| G2 | Auf der Karte hat sich nichts geändert (Anzahl Bilder, Dateien in der Kamera-Wiedergabe) | ja | ✅ |

## Offene Fragen für dieses Protokoll
- Grenzwerte beim Zuordnen: Interpolation bei bis zu 10 min Lücke, sonst nächster Punkt bis 5 min. Passt das im Alltag?
- Batchgrößen: erste Portion 200 Dateien, danach 300. Reicht das, oder anpassen nach C1/C4?
- Bonus (nicht Teil des Tests): Rezept aus den MakerNotes lesen und Fotos zuordnen.

## Ergebnis
- Gesamt (Lauf 1, ohne A und F): 24 ✅ / 2 ❌ / 4 ⚠️, 3 nicht getestet (D4, D6, E6). A (Tracking) und F (Geotagging) bewusst ausgelassen, folgen in einem zweiten Lauf.
- Gefundene Fehler (Punkt → Kurzbeschreibung):
  - B1 → „Report a Problem“ wird trotz `reportsEnabled = false` angezeigt; genaue Stelle noch offen (Screenshot nötig).
  - B2 → Im RAW-Conv.-Modus wartet der Screen ohne klare Meldung, statt `noPhotos` mit Card-Reader-Hinweis zu zeigen.
  - C2 → Innerhalb eines Tages älteste zuerst; gewünscht: neueste zuerst wie bei den Tagen.
  - C5 → Nach „Load Older Photos“ springt die Scrollposition nach oben.
  - C1 → Benennung: „Import Photos (USB)“ öffnet „Light Table“; erste Kacheln erst nach ~1 min.
  - E2 → Zusammenfassung zählt Frames („1 photo“), nicht Dateien; besser „1 photo (2 files)“.
- Behoben in PR #16 (`0b920cd`), am iPhone nachgeprüft 2026-11-15: B1 (Build war älter als `reportsEnabled`, mit aktuellem Build weg), B2 (Meldung mit Card-Reader-Hinweis kommt), C2 (neuestes Foto oben), C5 (springt nicht mehr), C1 (Zeile heißt jetzt „Light Table (USB)“, mit Untertitel). Ebenfalls in PR #16, noch nicht am Gerät nachgeprüft: E2 („1 photo (2 files)“).
- Aus der Nachprüfung dazugekommen und in PR #16 umgesetzt, am iPhone bestätigt: Bildschirm bleibt an, während die Karte gelesen oder importiert wird; Kontext-Texte unter „Connect Camera (USB)“ und „Location Track“ (als ungetestet markiert); Kamera im Card-Reader-Modus zeigt LINK an, R/W aus, „USB Card Reader   Photos Only“.
- Offen: zweiter Lauf für A (Tracking) und F (Geotagging), dazu D4, D6, E6.
- Kein Fehler: D2/C8 – ein RAW+JPEG-Paar landet in Fotos als ein Asset mit JPEG als Foto und RAF als `alternatePhoto` (Badge „RAW+JPEG“). In Fotos ▸ Bearbeiten ▸ ⋯ ▸ „RAW als Original verwenden“ bzw. Export „Unbearbeitetes Original“ liefert beide Dateien.
- Hardware-Belege für den Code: X100VI fw 1.31, 2026-11-15, 2.273 Dateien: erste Kacheln nach 61 s (Indexierung der Kamera beim ersten Verbinden), „Load Older“ fast sofort. Tagesreihenfolge (neuester Tag oben) stimmt; ob das an den Handles oder an der Datumssortierung liegt, zeigt der Lauf nicht eindeutig. F12 offen.
