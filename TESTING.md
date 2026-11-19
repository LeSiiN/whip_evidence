# In-Game Test-Checkliste

Dauer: ca. 30–45 min. Du brauchst: Admin-Rechte, einen zweiten Spieler (Zivi), einen Polizei-Job mit mindestens zwei Rängen.
Abhaken, was klappt. Was nicht klappt: Schritt-Nummer + F8/Server-Konsole notieren.

Dev-Tools: `/w` → **Forensics**.

## 0. Start
- [ ] 0.1 Server-Konsole beim Start: keine roten Fehler, Zeile `lab mrpd: container #…` erscheint.
- [ ] 0.2 Es wird kein Job angelegt. Fehlt ein Job aus „Police jobs“, steht er in der Konsole („does not exist (yet)“).
- [ ] 0.3 `/whip` → Settings → Forensics → „Lowest rank level“: 16 Einträge. Rang mit Level 1: scannen geht, einsammeln nicht („not allowed“). „Collect evidence“ auf 1 stellen → einsammeln geht (spätestens nach 10 s).
- [ ] 0.4 Lab-Monitor steht am Lab, zeigt den Win11-Desktop scharf und lesbar, Uhrzeit/Datum = echte Zeit.
- [ ] 0.5 `/w` → Forensics → „Fit the lab screen“ → Ecken oben links, oben rechts, unten links anklicken → mit Pfeilen/W/S/Mausrad feinjustieren → Enter speichert. Bild sitzt auf dem Glas, Taskleiste sichtbar, auch nach Neustart.
- [ ] 0.5b Fit-Tool mit Controller: RT/A wählt Ecke, B zurück. Feinjustieren: linker Stick bewegen, rechter Stick rein/raus, RT/LT Größe, X halten langsamer, A speichert, Y Ecken neu, B abbrechen.
- [ ] 0.6 Anderes Modell in `/whip` (Labs → Screen model) → nach Neustart neues Modell, Bild passt sich an.
- [ ] 0.7 `/whip` → Forensics → General → Language = Deutsch, Neustart → Prompts, Meldungen, Items, Minigames, Foto, Lab-Monitor auf Deutsch.

## 1. Spuren entstehen
- [ ] 1.1 Als Zivi ein paar Schüsse auf Wand und Auto → Hülsen am Boden, Projektil in der Wand.
- [ ] 1.2 Zivi wird angeschossen und läuft → Blutspur, wird nach ~20 s dünner, nach ~30 s Schluss. Unter 115 HP: blutet weiter bis Heilung.
- [ ] 1.3 Zivi sitzt ohne Handschuhe im Auto → Fingerabdruck im Auto (später beim Scan sichtbar).
- [ ] 1.4 Zivi sieht **kein** Overlay, nur die Boden-Prompts.

## 2. Scan (Polizei, im Dienst)
- [ ] 2.1 `/w` → Forensics → „Give me the test kit“.
- [ ] 2.2 Kamera benutzen → Overlay: nummerierte Marker, Legende, Karten.
- [ ] 2.3 Schussbahn: Linie von Hülse zu Projektil desselben Schusses.
- [ ] 2.4 Blutspur zeigt Pfeile in Laufrichtung.
- [ ] 2.5 **G** in der Kamera wechselt den Filter, **H** macht ein Foto.
- [ ] 2.6 Rang ohne `evidence_scan` → kein Overlay.
- [ ] 2.7 Resource neu starten, während die Kamera in der Hand ist → Overlay kommt nach ~1 s wieder.

## 3. Foto
- [ ] 3.1 H drücken → „Photo taken…“, dann „Photo saved.“ Kein Kick.
- [ ] 3.2 Foto-Item → „View photo“: scharfes Polaroid mit Markern, Liste und Stempel „NO CASE“.
- [ ] 3.3 Fotografierte Marker zeigen das Kamera-Abzeichen.
- [ ] 3.4 „Copy as text“ → Text im Clipboard (Strg+V im Chat/Notepad).
- [ ] 3.5 Einstellungen (Settings-Menü) → Layout von Scan und Foto ändern → wird übernommen.
- [ ] 3.6 Mit Controller: LB + Steuerkreuz links/rechts wechselt Filter / macht Foto (nur beim Scannen). Foto ansehen: A zoomt, LB/RB zoom, rechter Stick verschiebt, B zurück, Hinweise zeigen Pad-Tasten.

- [ ] 3.7 Auf ein geparktes Auto schießen → Fragmente am Boden, Auto bekommt blauen Marker „V1“, Karte „Fragmente am Tatort · Noch kein Foto“. Vier Autos mit Spuren → V1–V4, alle mit Marker.
- [ ] 3.8 Foto von der Seite → Foto-Liste „V1 Kennzeichen nicht lesbar (gelb) · Modell, Farbe“, Karte „Foto ohne Kennzeichen“. Foto von vorne/hinten unter 12 m → Kennzeichen steht drin, Karte „Fotografiert“.
- [ ] 3.9 Tatort freigeben mit Auto ohne Kennzeichen-Foto → Nachfrage „1 Fahrzeug(e) ohne Foto: V1 (…)“. „Zurück“ bricht ab, „Trotzdem freigeben“ geht weiter.
- [ ] 3.10 Spuren am Auto einsammeln → Marker bleibt, solange Fragmente-Spur da ist; Nummer und Foto bleiben.

## 4. Einsammeln
- [ ] 4.1 Frische Spur ist sofort grün und einsammelbar (kein Warten).
- [ ] 4.2 Einsammeln → Minigame je Typ (Pinzette, Tupfer, Ziehen …) → Beutel landet im Beweiskoffer.
- [ ] 4.3 Minigame 3× verkacken → „The evidence is ruined.“
- [ ] 4.4 Beutel-Infos: Marker `#n`, „Photographed: Yes/No“, Werte `???`, Chain of custody „Collected“.
- [ ] 4.5 Beweiskoffer: 30 Fächer, Bild sichtbar, öffnen per Doppelklick.
- [ ] 4.6 Koffer voll (oder `BagsIntoCase` aus) → Beutel geht in die Taschen.
- [ ] 4.7 Laserpointer in Projektil setzen und wieder entfernen.
- [ ] 4.8 Auto an der Fahrertür untersuchen (leer, steht still) → Beutel pro Spur, Türen öffnen/schließen sich.
- [ ] 4.9 Waffe im Rechtsklickmenü → „Dust for prints“ → Minigame → Fingerabdruck-Beutel.
- [ ] 4.10 GSR-Test auf den Zivi (nach Schuss) → POSITIVE (strong) + Beutel. Zivi im Wasser waschen → danach NEGATIVE.
- [ ] 4.11 Zivi schießt → GSR-Ring im HUD (orange), wird langsam leerer. Nach ~15 min Test → „weak traces“.
- [ ] 4.12 Rechtsklick Wasserflasche / Putztuch → „Clean off gunshot residue“ → Ring weg, Flasche weg bzw. Tuch abgenutzt.
- [ ] 4.13 Schwimmen (~15 s) oder Regen zu Fuß draußen (~60 s) → Ring weg. Im Auto bei Regen → bleibt.
- [ ] 4.14 Zivi wird angeschossen → roter Blut-Ring. Spieler 2 stand daneben → hat auch einen.
- [ ] 4.15 Polizei: auf Zivi zielen → „Swab clothes for blood“ → Beutel pro Person; im Labor Blutgruppe.
- [ ] 4.16 Zivi zieht sich um / wäscht sich im Wasser → Blut-Ring weg.
- [ ] 4.17 Handschuhe an → grauer Handschuh-Ring. Schießen → wird weniger. Handschuhe aus → Ring weg, wieder an → gleicher Stand.

## 5. Aufräumen
- [ ] 5.1 Nicht fotografierte Spur „Clear away“ → Rückfrage, rot hervorgehoben, Halten zum Bestätigen.
- [ ] 5.2 Fotografierte Spur → ohne Rückfrage weg.
- [ ] 5.3 F1-Rad → Tatort freigeben: „nur fotografierte“ vs. „alles“ (Rückfrage).
- [ ] 5.4 Zivi mit Zange (Projektil) / Putztuch (Rest) → Minigame → Spur weg. Ohne Item: Hinweis.
- [ ] 5.5 Zivi putzt Auto-Innenraum mit Putztuch → Abdrücke/Blut weg, Einschusslöcher bleiben.

Tipp: `/w` → Forensics → „Give me every evidence bag“ gibt jede Beweisart einmal unanalysiert in die Taschen (16 Beutel), ohne Minigames.

## 6. Labor
- [ ] 6.1 Am Lab-Gerät „Unload evidence case“ → alle Beutel im Lager, Koffer leer.
- [ ] 6.2 Waffe dazulegen → „Analyse“ → Bildschirm zeigt Fortschritt, Lager ist gesperrt.
- [ ] 6.3 „Finish running lab analyses now“ → Bildschirm zeigt Ergebnisse, Lager offen.
- [ ] 6.4 Beutel: Werte sichtbar, „Age at collection“, Custody „In lab“ → „Analysed“.
- [ ] 6.5 Referenzhülse für die Waffe im Lager, passende Hülsen haben „Ballistic match“.
- [ ] 6.6 Rechtsklick „Copy data“ → Seriennummer o. ä. im Clipboard.
- [ ] 6.7 Niemand am Gerät → Sperrbildschirm mit Uhr, Datum und Status. Ans Gerät treten (≤ 2,5 m) → „Willkommen, Name“, dann Desktop, Name unten rechts. Weggehen → wieder gesperrt (bis 2 s).
- [ ] 6.8 2 Minuten niemand am Gerät → Bildschirmschoner (schwarz, Logo + Uhr wandert). Fertige Analyse weckt ihn.
- [ ] 6.9 Analyse starten → Ton am Monitor (15 m, 3D). Liste: Beutel nacheinander „fertig“ / „läuft · %“ / „in ca. X Min“, „gestartet von …“, Balken unter dem Taskleisten-Icon.
- [ ] 6.10 Bild rechts passt zum Beutel: Blut DNA-Kurven, Fingerabdruck Punkte, Hülse/Projektil Riefen, Schmauch Balken Pb/Ba/Sb, Fahrzeugteile Lackschichten.
- [ ] 6.10b Monitor flimmert/zittert nicht (auch Sperrbildschirm und Bildschirmschoner: Logo springt alle 10 s, gleitet nicht).
- [ ] 6.12 Nach der Analyse am Gerät „Upload to a case“ → Monitor: Beutel → Ordner mit Fall-ID, „Beweis X von Y“, dann grüner Haken „… in Fall … hochgeladen“ + Ton. Danach „Bereit“, wenn nichts Ausgewertetes mehr im Lager liegt (sonst wieder die Ergebnisse).
- [ ] 6.11 Fertig → Ton, Hinweis unten rechts (auch auf dem Sperrbildschirm), rotes Abzeichen mit Anzahl am Icon. Nach dem Joinen kein Ton für alte Ergebnisse.

## 7. Fall-Spinde (braucht das MDT oder den Test-Schnipsel unten)
- [ ] 7.0 Am Spind „Evidence Lockers“ → Liste der Fälle (neueste Änderung oben, abgeschlossene grau unten). Klick öffnet den Spind. Über 15 Fälle: „Mehr anzeigen“. Suche filtert; eine ID, die nicht in der Liste ist, lässt sich mit Enter trotzdem öffnen. Controller: Steuerkreuz, A, X, B.
- [ ] 7.0b Am Lab-Gerät „In Fall hochladen“ → dieselbe Liste (ohne abgeschlossene Fälle). Fall anklicken → hochgeladen. Neue Case-ID ins Suchfeld → „diesen Fall verwenden“ → Enter.
- [ ] 7.1 Lab-Gerät → „Upload to a case“ → Fall-ID → analysierte Sachen wandern in den Fall-Spind.
- [ ] 7.2 Nicht analysierte bleiben im Lab (Meldung zählt sie).
- [ ] 7.3 Am Spind (Config.Lockers) Fall-ID eingeben → Spind öffnet.
- [ ] 7.4 Rausnehmen → Custody „Taken from case locker“. Zurücklegen geht nur für denselben Fall.
- [ ] 7.5 Rang ohne `evidence_locker_take` → nur ansehen.
- [ ] 7.6 Während der Spind offen ist, Rang ändern oder ausstempeln → Spind schließt.
- [ ] 7.7 `/w` → Forensics → Case lockers → Fall schließen → nur noch ansehen. Wieder öffnen, löschen.

Test-Schnipsel ohne MDT (eigene kleine Resource, Server-Datei, nach whip_evidence starten):
```lua
CreateThread(function()
    Wait(2000)
    exports.whip_evidence:SetCaseCheck(function(caseId, source) return true end)   -- jede Fall-ID gilt
end)
```

## 7b. Leichen (alleine testbar)
Vorbereitung: `/w` → Forensics → „Give me the test kit“, Polizei im Dienst, eine Waffe.
- [ ] 7b.1 „Place a test pedestrian“ → Passant steht 4 m vor dir und bleibt stehen.
- [ ] 7b.2 Zweimal anschießen, dann erschießen → Blutlache am Boden. Taschenlampe drauf: Karte „L1 Leiche · Noch nicht untersucht“.
- [ ] 7b.3 Prompt „Leiche L1“ sitzt auf der Brust der Leiche (auch nach Wegtragen). „Leiche untersuchen“ (kniend, 6 s) → Befund-Fenster öffnet sich: Todesursache, Verletzungen je Körperstelle, Schussdistanz, Projektile, Geschlecht. „Als Text kopieren“ geht, Esc/B schließt. „Befund ansehen“ öffnet es wieder.
- [ ] 7b.3b Kamera auf die Leiche, Foto (H) → im Foto steht „L1 Leiche“ in der Liste, Karte zeigt „Fotografiert“.
- [ ] 7b.3c Einen normalen Passanten auf der Straße erschießen (nicht gespawnt) → wird genauso zur Leiche.
- [ ] 7b.4 „Projektil entnehmen“ → Herausziehen-Minigame → Beutel „Projektil (aus Leiche)“. Im Labor: Seriennummer deiner Waffe.
- [ ] 7b.5 „Blutprobe nehmen“ und „Schmauchtest an den Händen“ → unbewaffneter Passant: negativ. Optionen verschwinden danach.
- [ ] 7b.6 „Place an armed test pedestrian“ → erschießen → Schmauchtest positiv, Beutel kommt.
- [ ] 7b.7 „Place a stand-in for me“ → erschießen → Blutprobe im Labor = deine Blutgruppe.
- [ ] 7b.8 Mit dem Messer / Auto töten → Wunde „Stich/Schnitt“ bzw. „Von Fahrzeug erfasst“.
- [ ] 7b.9 Weggehen (über 300 m) und zurück → Leiche liegt noch da. „Leiche freigeben“ (halten) → Leiche weg.
- [ ] 7b.10 Vier Leichen nebeneinander → jede hat einen lila Marker „L1“–„L4“, die Karte nur bei der angezielten. Foto → alle vier in der Liste. Filter (G) „Leichen“ zeigt nur Leichen; Kamera-Legende listet sie.
- [ ] 7b.11 (Zweiter Spieler) Spieler 2 stirbt → Leiche „L…“. Untersuchen → Spieler 2 kann nicht respawnen und bekommt eine Meldung; nach „Leiche freigeben“ oder 10 Min wieder.

## 7c. Animationen und Props
- [ ] 7c.1 Einsammeln: knien, dann stehend „Beutel verschließen und beschriften“ mit Notizblock, kurzer Ton.
- [ ] 7c.2 Waffe einstauben: Arbeiten wie an einer Werkbank (/e mechanic4). Waffe/Innenraum putzen (Zivi): Schwamm. Fahrzeugspuren: Taschenlampe.
- [ ] 7c.3 Tatort freigeben: Klemmbrett. Leiche untersuchen: kniend (Medic). Lab starten/ausladen/hochladen und Spind öffnen: Tippen.
- [ ] 7c.4 Schmauchtest / Abstrich an Spieler 2: Spieler 2 hält kurz die Hände nach vorne.
- [ ] 7c.5 Props sitzen richtig in der Hand (sonst: Emote-Name nennen, das besser passt). `/whip` → „Props in the hand“ aus → nur Animationen.

## 7d. Schuh- und Reifenspuren (alleine testbar, Polizei-Job aus oder `TrackPolice` an)
- [ ] 7d.1 Über Sand (Strand) oder Matsch laufen → etwa alle 12 m vier Abdrücke (links/rechts, Zehen leicht nach außen, nicht ganz gleichmäßig, Ballen und Ferse kräftiger). Auf Asphalt nichts.
- [ ] 7d.2 Durch eine Blutlache laufen → eine Strecke rote Abdrücke direkt danach, zur Lache hin kräftig, dann fast weg.
- [ ] 7d.3 Mit dem Auto über Wiese/Sand/Matsch fahren → etwa 8 m Reifenspur, dann ~25 m nichts. Motorrad eine Spur. Auf Asphalt nur bei Burnout, Handbremse bei Tempo oder Vollbremsung aus hohem Tempo; normales Bremsen nichts.
- [ ] 7d.4 Spuren werden mit der Zeit blasser und sind nach 20 Min weg. Mehr als 12 eigene → die ältesten verschwinden.
- [ ] 7d.5 Scan: Marker und Karte wie bei anderen Spuren, Filter „Spuren“. Einsammeln → Beutel „Schuhabdruck“ / „Reifenspur“ mit Untergrund, Profil „???“.
- [ ] 7d.5b Minigame „Gipsabguss“: Gips über den ganzen Abdruck gießen (Maus halten, bewegen). Außerhalb des Rahmens → „Daneben“, zu lange → Fehler; auf einer Stelle stehen bleiben → „Blasen“. Dann Balken: im Grünen klicken → fertig, zu früh „Noch weich“, zu spät „klebt fest“.
- [ ] 7d.6 Labor: Bild „Sohlenprofil“ / „Reifenprofil“; danach „SP-xxxx · ca. 43 (EU)“ bzw. „RP-xxxx · 225 mm · Auto“. Blutiger Abdruck zeigt auch die Blutgruppe.
- [ ] 7d.7 Vergleich: Polizei → Spieler „Schuhabdruck nehmen“ → gleiches SP-Profil wie seine Spuren. An der Vordertür (Motorrad: am Lenker) „Reifenabdruck nehmen“ → gleiches RP-Profil wie die Spur des Autos. Andere Schuhe/Felgen → anderer Code.
- [ ] 7d.8 Wetter auf XMAS → überall draußen Abdrücke im Schnee.

## 7e. Gegenspiel (Fasern, Feuer, Bleiche, Seriennummer)
- [ ] 7e.1 Mit Handschuhen ins Auto setzen (1–2 Min) → Scan „Mögliche Abdrücke“; Polizei sammelt → Beutel „Handschuhfasern (Fahrzeug)“ statt Fingerabdruck (60 %). Labor: „FA-xxxx“.
- [ ] 7e.2 Mit Handschuhen Waffe ziehen → einstauben → Beutel „Handschuhfasern (Waffe)“.
- [ ] 7e.3 Spieler 2 trägt Handschuhe → „Handschuhfasern nehmen“ → Minigame (nur Fasern in Handschuhfarbe anklicken; Fussel/Haar = Fehler) → gleicher FA-Code. Ohne Handschuhe: „trägt keine Handschuhe“.
- [ ] 7e.4 Auto mit Spuren anzünden (Molotov) und brennen lassen → Karte „Ausgebrannt“, Blut/Abdrücke/Hülsen innen weg, Einschusslöcher und Kennzeichen bleiben.
- [ ] 7e.5 Bleiche benutzen neben Blut/Fingerabdruck → alles im Umkreis von 2,5 m weg, eine helle „gereinigte Stelle“ bleibt. Einsammeln → Labor: „Bleiche (Natriumhypochlorit)“. Ohne Spuren in der Nähe: „nichts zu reinigen“.
- [ ] 7e.6 Waffe weggesteckt → Rechtsklick „Seriennummer wegfeilen“ (Feile) → Seriennummer z. B. „##3####M####“. Gezogen: „Steck die Waffe zuerst weg“. Danach schießen → Hülse zeigt im Labor die gefeilte Nummer.
- [ ] 7e.7 Polizei am Laborgerät: Rechtsklick „Seriennummer wiederherstellen“ → Beutel „Seriennummer (Laborbericht)“ mit z. B. „AB3?9X?M7Q?L“ (oder „Zerstört“). Zweites Mal: „Schon wiederhergestellt“. Weg vom Gerät: „Nur an einem Laborgerät“.

## 7e2. Kamera: saubere Ansicht
- [ ] 7e2.1 Kamera hoch, auf eine Spur / V1 / L1 zielen → große Karte da. K → nur die große Karte weg; Marker, Legende und Textzeile bleiben (Hinweis „[K] Karte zeigen“). K → Karte wieder da. Kamera weg und wieder hoch → Karte da.
- [ ] 7e2.2 Controller: LB + Steuerkreuz hoch macht dasselbe.

## 7f. Alter ohne Uhr
- [ ] 7f.1 Standard (grob): Scan-Karte zeigt „frisch“ / „vor einer Weile“ / „älter“ / „alt“, kein „noch X Min“. Legende genauso. Foto-Liste und Text auch.
- [ ] 7f.2 Labor (grob): „Alter bei Sicherung: Unter 15 Min / Unter 1 Std / Über 1 Std“.
- [ ] 7f.3 `/whip`: Alter auf „Exact“ → wieder Minuten und „noch X Min“; „Not shown“ → keine Altersangabe. Labor „Not told“ → neue Beutel ohne Altersfeld.

## 8. Neustart und Kanten
- [ ] 8.1 Spur fotografieren, Resource neu starten → Spur, Nummer, Foto-Abzeichen und Blutrichtung sind noch da.
- [ ] 8.2 Beweiskoffer an Spieler 2 geben → Custody „Received (evidence case)“ bei allen Beuteln, **nur einmal**.
- [ ] 8.3 `whip_core` neu starten → Prompts, Koffer, Lab-Bildschirm funktionieren wie vorher, nichts doppelt.
- [ ] 8.4 Regen → Spuren altern schneller, GSR ist weg.
- [ ] 8.5 Minigames mit Gamepad durchspielen.
- [ ] 8.6 Performance (F8 `resmon 1`, Spalte whip_evidence; Feinmessung im Dev-Modus mit `/whipcost`, Server-Konsole `whipcost 30`):

| Situation | Ziel (CPU ms) |
|---|---|
| Zivi, keine Spuren in der Nähe | 0.00 |
| Polizei im Dienst, 30+ Spuren in der Nähe, ohne Lampe/Kamera | ≤ 0.01 |
| Taschenlampe auf 30+ Spuren | ≤ 0.12 |
| Kamera mit Legende auf 30+ Spuren | ≤ 0.15 |
| Am Lab-Monitor (unter 15 m) | ≤ 0.03 |
| Minigame offen | ≤ 0.03 |
| Server (`whipcost 30`), Schießerei mit 2–3 Spielern | ≤ 0.2 ms pro Tick |
