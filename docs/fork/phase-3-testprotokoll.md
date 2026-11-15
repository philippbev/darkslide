# Phase 3 – Testprotokoll (USB-Import + Geotagging Stufe A)

Gerätetest mit iPhone und X100VI. Ergebnis je Punkt eintragen: ✅ / ❌ / ⚠️ + Notiz. Bei ❌: Settings ▸ Diagnostics ▸ Bericht kopieren und mit dem Punkt-Nr. ablegen.

| | |
|---|---|
| Datum | |
| Build (Commit) | |
| iPhone / iOS | |
| X100VI Firmware | |
| Karte (Größe, Anzahl Fotos ca.) | |
| Dateiformat-Einstellung der Kamera | RAW+JPEG / RAW+HEIF / JPEG / … |

## Vorbereitung
- [ ] Testordner in Dateien anlegen (z. B. „Darkslide Test“), Fotos-Mediathek: Album zum späteren Aufräumen merken.
- [ ] Kamerauhr gegen iPhone prüfen: iPhone-Uhr fotografieren, Abweichung notieren: ______
- [ ] Mindestens ein Testtag mit **RAW+JPEG**, ein paar Bilder **nur RAW** und ein kurzes **Video** auf der Karte.

## A. Track aufzeichnen (unterwegs, vor dem Fotografieren)
Camera-Tab ▸ **Location Track** ▸ Start Recording.

| # | Schritt | Erwartet | Ergebnis |
|---|---|---|---|
| A1 | Erstes Start Recording | Dialog „Beim Verwenden der App“; danach „Recording“, Zeile im Camera-Tab heißt „Location Track (Recording)“ | |
| A2 | Bildschirm sperren, 20–30 min gehen und fotografieren | Ortungsanzeige (Pfeil/blaue Pille) bleibt sichtbar; Aufzeichnung läuft weiter | |
| A3 | App in den Hintergrund, andere Apps nutzen | Aufzeichnung läuft weiter | |
| A4 | Stop Recording | Track in der Liste mit Dauer und Punktzahl, plausibel (grob 1 Punkt je 10 m) | |
| A5 | Zweiten Track starten, App per App-Umschalter **beenden**, neu öffnen | Track ist geschlossen, endet am letzten Punkt; nichts geht verloren außer max. den letzten ~10 Punkten | |
| A6 | Akku: Verbrauch für 30 min Aufzeichnung (Einstellungen ▸ Batterie) | notieren: ____ % | |
| A7 | Ortung für Darkslide in Einstellungen auf „Nie“, Start Recording | Fehlertext „Location access is off …“ | |

## B. Verbinden und Kartenmodus
| # | Schritt | Erwartet | Ergebnis |
|---|---|---|---|
| B1 | Kamera im Modus **USB RAW Conv./Backup Restore**, „Connect Camera (USB)“ verbinden, dann „Import Photos (USB)“ | Hinweis: erst im Camera-Tab trennen, Import braucht anderen USB-Modus | |
| B2 | Trennen, Import Photos (USB) mit Kamera immer noch im RAW-Conv.-Modus | „The camera lists no photos …“ mit Anleitung zu **USB Card Reader** (oder klare andere Meldung) – Text notieren | |
| B3 | Kamera: Network/USB Setting ▸ Connection Mode ▸ **USB Card Reader**, Import Photos (USB) | Dialog Kamerazugriff (beim ersten Mal), dann „Reading the card …“ | |
| B4 | Ohne Kabel Import Photos (USB) | „No camera detected …“ | |
| B5 | Stimmt der Menüpfad im Hinweistext mit der X100VI überein? | genaue Bezeichnung auf der Kamera notieren: __________ | |

## C. Light Table: Listing und Geschwindigkeit
| # | Schritt | Erwartet | Ergebnis |
|---|---|---|---|
| C1 | Zeit von Tippen bis erste Kacheln sichtbar | wenige Sekunden (vorher ImageCaptureCore: ~2 min bei 2.000 Fotos) – messen: ____ s | |
| C2 | **Neueste zuerst:** oberster Tag = letzter Aufnahmetag, innerhalb des Tages richtige Reihenfolge | ✅ bestätigt die Annahme „höchste PTP-Handles = neueste“ | |
| C3 | Während „still being read“: schon auswählen/importieren möglich | ja, Hinweistext sichtbar | |
| C4 | Ans Ende scrollen ▸ „Load Older Photos“ | nächste ~300 Dateien kommen, Zeit: ____ s | |
| C5 | Vorschaubilder laden flüssig beim Scrollen | keine Hänger, Platzhalter werden ersetzt | |
| C6 | Simulationscode auf Kacheln (z. B. CC, AC, CH) | passt zur Einstellung beim Fotografieren (Stichprobe 3 Bilder) | |
| C7 | RAW+JPEG-Paar erscheint als **eine** Kachel | ja | |
| C8 | Filter Dateien: RAW / JPEG/HEIF / RAW + JPEG/HEIF | Kacheln ohne passende Datei verschwinden; Auswahl wird mit gefiltert | |
| C9 | Choose Days ▸ einen Tag ▸ Show | nur dieser Tag | |
| C10 | „Select Day“ am Tageskopf, „All“, „None“ | korrekt | |
| C11 | Kabel während des Listings ziehen | bereits Gelistetes bleibt, Meldung zum Abbruch; kein Absturz | |

## D. Import in die Fotos-Mediathek
| # | Schritt | Erwartet | Ergebnis |
|---|---|---|---|
| D1 | Erster Import, Ziel Photo Library | Dialog „Fotos hinzufügen“ (nur Hinzufügen) | |
| D2 | 10 Fotos RAW+JPEG importieren, Zeit messen | ____ s gesamt, Fortschritt „Importing x of 10“ | |
| D3 | In Fotos: ein Eintrag pro Paar, Badge „RAW+JPEG“ | ja; Originaldateiname DSCFxxxx | |
| D4 | EXIF in Fotos (Info-Panel): Kamera, Objektiv, Belichtung, Aufnahmezeit | unverändert wie von der Kamera | |
| D5 | Nur-RAW-Bild importieren | erscheint als RAW-Foto | |
| D6 | Video importieren | erscheint als Video | |
| D7 | Light Table erneut öffnen | importierte Fotos sind ausgeblendet („nur neue“); Umschalten zeigt sie als bereits importiert | |
| D8 | Import mittendrin abbrechen | Zusammenfassung „cancelled“; Bereits importierte zählen, Rest bleibt ausgewählt | |
| D9 | Fotozugriff in Einstellungen entziehen, importieren | Fehlertext „Photo library access is off …“ pro Frame | |

## E. Import in einen Ordner (Dateien)
| # | Schritt | Erwartet | Ergebnis |
|---|---|---|---|
| E1 | Destination ▸ Choose Folder… ▸ Testordner | Ziel zeigt Ordnernamen | |
| E2 | 5 RAW+JPEG importieren | je `DSCFxxxx.RAF` + `.JPG`, Originalgröße, Bytes identisch zur Karte | |
| E3 | App neu starten, Light Table öffnen | Zielordner ist noch gewählt | |
| E4 | Dieselben Fotos erneut importieren („nur neue“ aus) | keine Duplikate (gleiche Größe = übersprungen) | |
| E5 | iCloud-Drive-Ordner als Ziel | funktioniert | |
| E6 | (optional) USB-Stick/SSD am iPhone als Ziel, danach abziehen und Light Table öffnen | Import klappt; ohne Stick verständliche Meldung | |

## F. Geotagging
Voraussetzung: Track aus A, Fotos während der Aufzeichnung.

| # | Schritt | Erwartet | Ergebnis |
|---|---|---|---|
| F1 | Light Table öffnen | Panel „Location from Track“, „Add Location“ ist an | |
| F2 | Camera Clock zeigt In Sync bzw. gemessene Abweichung aus der Vorbereitung eintragen | Tag „Camera Clock …“ korrekt | |
| F3 | Import in **Fotos** | Zusammenfassung nennt Anzahl verorteter Fotos; Karte in Fotos zeigt Bilder auf der gelaufenen Strecke | |
| F4 | Genauigkeit: 3 Bilder an markanten Orten prüfen | Abweichung ≤ ca. 30 m – notieren | |
| F5 | Import in **Ordner**: JPEG/HEIF | GPS steckt im JPEG selbst (Fotos-App/Dateien-Info oder am Mac `exiftool`/Vorschau ▸ Informationen) | |
| F6 | Ordner: RAF | Datei `DSCFxxxx.xmp` daneben; RAF unverändert | |
| F7 | XMP am Mac in Lightroom/Bridge (oder `exiftool DSCFxxxx.xmp`) | Position wird gelesen | |
| F8 | JPEG-Bildqualität nach Geotag | Dateigröße nahezu gleich, keine Neukompression (Stichprobe) | |
| F9 | Foto **außerhalb** jeder Aufzeichnung (> 5 min Abstand) | wird nicht verortet (lieber keine Position als eine falsche) | |
| F10 | Kamerauhr absichtlich +1 h stellen, Fotos machen, Light Table | Tag „Clock Ahead?“ erscheint; mit Offset „Ahead 1 h“ werden die Fotos richtig verortet | |
| F11 | Ohne aufgezeichnete Tracks | „Add Location“ aus und nicht schaltbar | |
| F12 | Zeitzone: schreibt die X100VI `OffsetTimeOriginal` (fw ≥ ?) | im EXIF eines JPEG prüfen, notieren | |

## G. Rückweg zu Rezepten
| # | Schritt | Erwartet | Ergebnis |
|---|---|---|---|
| G1 | Light Table schließen, Kamera zurück auf USB RAW Conv./Backup Restore, Connect Camera | Rezepte/Slots lesen wie gewohnt | |
| G2 | Auf der Karte hat sich nichts geändert (Anzahl Bilder, Dateien in der Kamera-Wiedergabe) | ja | |

## Offene Fragen für dieses Protokoll
- Grenzwerte beim Zuordnen: Interpolation bei bis zu 10 min Lücke, sonst nächster Punkt bis 5 min. Passt das im Alltag?
- Batchgrößen: erste Portion 200 Dateien, danach 300. Reicht das, oder anpassen nach C1/C4?
- Bonus (nicht Teil des Tests): Rezept aus den MakerNotes lesen und Fotos zuordnen.

## Ergebnis
- Gesamt: ____ ✅ / ____ ❌ / ____ ⚠️
- Gefundene Fehler (Punkt → Kurzbeschreibung):
- Hardware-Belege für den Code (datiert, „X100VI fw x.xx, 2026-11-xx“): C2 (Handle-Reihenfolge), C1/C4 (Zeiten), F12 (Zeitzone)
