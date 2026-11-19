# Changelog

## 4.2.4

### New
- **Exact hit spots**: the findings sheet puts every hit where it landed (from the bone that was hit: head, neck, chest, belly, pelvis, left/right shoulder, upper arm, forearm, hand, thigh, lower leg, foot). Hover shows wound and spot. For an MDT: `report.details.marks[].s` (missing when the bone is not known).

## 4.2.0

### New
- **Shoe prints**: walking through mud, sand or snow (in snowy weather anywhere outside) leaves prints, and after stepping in blood a few bloody ones. The lab tells the sole pattern ("SP-3F2A", the same shoes always give the same code) and the shoe size; a bloody print also the blood type. Police take a shoe print from a person to compare ("Take a shoe print").
- **Tyre tracks**: driving over mud, sand, snow or grass, and skidding or a burnout on any ground. The lab tells the tread pattern (same car and rims = same code) and the tyre width. Police take a tyre print at a front door (bikes: at the handlebar) to compare.
- Drawn on the ground (no props), they fade with age and stay 20 minutes (`TrackMinutes`). At most 12 per player at once; police on duty leave none (`TrackPolice`). Scan filter "Prints & tracks", lab visuals for both, settings group in `/whip`.
- **Glove fibres**: gloves that stop a print leave fibres instead (in cars and on weapons, `FiberChance`). The lab gives a code ("FA-3F2A", the same gloves always give the same one). Police take fibres from a person's gloves to compare ("Take glove fibres").
- **Burnt-out cars**: a car with traces that burns loses what was inside (prints, blood, casings, GSR). Bullet holes, pieces on the ground, the number and the plate stay. The card and photos say "Burnt out".
- **Bleach** (new item): cleans blood, prints and bloody shoe prints within 2.5 m at once (no minigame), but leaves a "cleaned spot" (60 min). A swab of it: the lab finds bleach.
- **Filing a serial off** (new item: metal file): right-click a holstered gun. A few characters stay ("##3####M####"), prints on the weapon move along. Police at a lab device: "Restore serial (acid)" brings part of it back ("AB3?9X?M7Q?L", `SerialRestoreChance`) or nothing (`SerialLostChance`), once per weapon, as a lab report bag.
- Dev tools: test pieces and "Give me every evidence bag" include shoe and tyre prints, fibres and a cleaned spot; the test kit has bleach and a file.
- Prints and tracks on the ground cost much less: one picture per piece (four steps, or both tyres of a car, baked into one texture), one side of the polygon, corners and colour worked out twice a second, pieces off screen skipped, drawn within 25 m. Timed in `/whipcost` ("evidence: prints and tracks"). `/evidence_trackfaces` switches the drawn side if a GPU shows the other one.
- Scan markers are painted whole on the page (tag, number and photo badge in one picture): one sprite per marker per frame instead of three to five.
- Lighter: the player's job is kept instead of read from the state bag in every loop, the layout settings are asked of whip_core once a minute instead of every 10 s, evidence prompts go up within 3.5 m instead of 6 m (whip_core scores every prompt that is up, every frame), marker stems only within 12 m.
- **Clean view in the camera**: K (controller: LB + D-pad up) hides the big card of the trace you aim at. Markers (also V1, L1), legend and text line stay. Again K or putting the camera away brings it back.
- **Lab time by age**: each bag takes its own time by how old it was when collected (fresh ~1 min, older ~1.5, old ~2.5; samples from people, cars and weapons 1 min; a gun to test-fire 1 min), a little random, all added up and kept between `LabMinMinutes` and `LabMaxMinutes` (now 2 and 15). The monitor's bag list uses the real times.
- **Partly readable** (`LabPartial`, off by default): traces over 30 min old when collected sometimes come back with some characters as "?" (fingerprint, serial, sole and tread pattern, fibre; blood type without +/-), marked "partly readable" (`LabPartialChance`).
- **Age without a clock**: `AgeShown` (scan card, legend, photos) and `LabAge` (the lab's age at collection), each 'exact', 'rough' (default) or 'off'. Rough: "fresh", "a while ago", "older", "old" on the scene; "Under 15 min", "Under 1 h", "Over 1 h" in the lab. The "time left" chip only shows with exact ages. Shoe prints, tyre tracks and cleaned spots are always rough in the lab. Settings in `/whip`.
- **Post-mortem report**: examining a body gives a report item (cause of death, findings, the whole report for an MDT) that goes into a case like any bag. For an MDT: `entry.report`, `entry.body` on bags taken from a body, `entry.bodies` on photos, event `whip_evidence:bodyExamined(report)` and export `GetBodyReport(bodyId)` (behind `ApiResources`; reports are saved, so this also works after the body is gone, `BodyReportDays` = 30).
- **New findings sheet**: a body picture with every hit where it landed (from the bone that was hit: head, neck, chest, belly, pelvis, shoulder, upper arm, forearm, hand, thigh, lower leg, foot, left/right; hover shows what it is). Marks: bullet still inside, went through, stab, other; the fatal one circled. Cause of death on top, hits / bullets / time of death as tiles.
- **New minigames**: "Plaster cast" for shoe prints and tyre tracks (pour plaster over the whole print without spilling or pouring too thick, then lift the cast when it is set) and "Glove fibres" for fibres from a person (pick only the fibres in the glove's colour, not lint or hairs). Choosable per job in `/whip` like the others.

## 4.1.0

### Changed
- **Jobs are only listened to**: `Config.PoliceJobs` names jobs from your job scripts; nothing is created or changed (no more conflicts with the script that owns the job).
- **Rank permissions by level**: "Lowest rank level" per action in `/whip` → Settings → Forensics, the same for every police job (no more toggles in the Job Manager).

### New
- **More immersion**: every bar has a fitting animation, many with a prop in the hand (notepad, clipboard, sponge, torch), taken from WHIP's emotes and listed in `Config.Animations` (`Config.HandProps = false`: no props). Collecting ends with sealing and labelling the bag. New short bars for lab unload/upload and opening a locker. A sealed bag makes a sound. A tested or swabbed person holds their hands out.
- **Vehicles at a scene**: every vehicle with traces gets a blue marker "V1", "V2", ... (card when aimed at, no limit). A photo lists number, plate, model and colour; the plate only counts from the front or back within 12 m. The card shows "No photo yet" / "Photo without plate" / "Photographed". Releasing a scene asks when vehicles have no photo of their plate (and logs them).
- **Fragments name their car**: the car hit pieces came from is involved too ("Fragments at the scene"), even with nothing inside.
- **Bodies**: players and pedestrians killed by a player can be examined (time of death, wounds, body parts), bullets taken out for the lab, blood sample and GSR test on the hands. Card "L1" in the scan, respawn held while police examine, pedestrian bodies don't despawn. Dev tools: test pedestrians and a stand-in with your blood.
- Findings sheet per body (cause of death, wounds per body part, shot distance, bullets in the body or through, defence wounds, weapon in hand, moved after death), copy as text, controller.
- Every body gets its own purple marker ("L1", "L2", ...) like evidence, the card shows for the one you aim at. Bodies are listed on crime scene photos. Every pedestrian works, also ones only your game knows. The prompt sits on the chest.
- **Evidence locker case list**: the locker shows the cases instead of asking for an ID: 15 latest changed first (more with a button), closed ones greyed (look only), with evidence count, items taken out and last change. The search field also opens an ID not in the list. Mouse, keyboard and controller. "Upload to a case" at the lab uses the same list (open cases only; a new MDT case ID is typed in the search field).
- Fix: the evidence locker did not open after typing the case ID (no message) since whip_core's early panel drawing (2026-11-18): each press of the locker prompt now has a fresh id, so nothing early is drawn and declined.
- A refused action says why: "Your rank is level 10, this needs level 20". The evidence locker prompt shows for every officer on duty (the rank is checked when opening).
- Fix: shots at police, emergency and parked NPC cars made no fragments or bullet holes (the car was not found). The car hit is now found by a ray through the impact; a car only one game knew is networked first.
- Fix: blood, casings and fragments landed on top of awnings, balconies or roofs above the spot. The floor is now found straight below.
- Settings group "Bodies" in `/whip`, rank level for "Examine bodies".
- **Lab monitor**: locked with clock and status when nobody is at the device; an officer stepping up signs in ("Welcome, name") and is shown in the taskbar; screensaver after 2 minutes. Start and finish play a sound at the monitor, the notification also shows on the lock screen. While running: each bag in turn (done / running % / about when), who started it, progress under the taskbar icon, a badge with the results. The current bag shows what the instrument sees: DNA peaks (blood), fingerprint points, striations lining up (casings, bullets), lead/barium/antimony (GSR), paint layers (vehicle fragments). Everything moves in steps once a second with the analysis (smooth motion shimmers on a monitor in the world).
- Upload to a case at the lab: the monitor shows the transfer (bags → case folder, item by item), then "uploaded" with a sound; once no analysed bag is left in the lab it goes back to "Ready".
- Dev tool "Give me every evidence bag": each kind once, not analysed (ground, person, weapon, vehicle, body), with your own fingerprint and blood.

## 4.0.0

### New
- **Crime scene photos**: a real screenshot with the camera (key H), shown as a polaroid with every marker listed. "Copy as text" for reports.
- **Numbered markers**, legend, scan filter (key G), shot trajectories, camera badge on photographed traces.
- **Chain of custody** on every bag and photo, "Sign for evidence".
- **Six forensic minigames** (dust, tweezers, swab, pull, shards, GSR swab), mouse and controller. Other resources can use them.
- **Civilians** remove traces with pliers / cleaning cloth and a minigame. The scan overlay is police only.
- **Rank permissions**: 15 toggles per rank in `/whip` → Jobs.
- **Case lockers + MDT exports**: upload analysed evidence to a case, it moves into that case's locker. Open it at any evidence locker.
- **Evidence case**: 30 compartments, new bags go in first, unload at the lab in one go.
- **Lab monitor**: Windows-style screen at each lab showing progress and results. Any prop per lab (`screenModel`), sharp picture drawn straight onto it, fit tool in `/w`, real clock. Your own logo possible.
- **Lab results**: age of a trace at collection. **Blood trails** show the walking direction.
- **GSR on the HUD**: a ring that fades over time. Cleaning items (water bottle, cloth, configurable), swimming and rain wash it off. The test tells strong or weak traces.
- **Blood on clothes**: own blood when hurt, others' when close by or carrying them. HUD ring, police can swab clothes, washing or new clothes remove it.
- **Blood trail** lasts a while after a hit (longer for heavy hits), thins out, stops when healed; critical injuries keep bleeding.
- **Glove wear**: HUD ring, worn gloves let more prints through.
- **Less garbage while scanning**: the overlay reuses its tables (about 45 KB → 2 KB per rebuild), prompts check rank permissions once instead of every frame and don't flicker on and off at the edge of their range.
- **Controller support** everywhere: scan filter and photo on WHIP's pad buttons, photo viewer, minigames and the lab screen fit tool.
- README with screenshot slots, where to get the items, GPL-3.0 `LICENSE`. Default evidence locker at Mission Row.
- **MDT guide** in the README: step-by-step integration with examples and a checklist.
- Item pictures for everything, a bag colour per evidence type.
- Update notices: whip_core tells you when a new release is on GitHub (`whip_updates`).
- **Languages**: English and German (`Config.Locale`), every text players see. Add your own in `locales/`.
- Player settings for the scan and photo layout. Admin dev tools and case management in `/w` → Forensics.

### Changed
- **Performance**: much lower resmon (spatial grid, painted overlay, idle back-off, chunked transfers). Lab screens only send changes, vehicle traces and glove wear are batched, the lab monitor works out its corners once.
- Prompts: hold to confirm risky actions (clear away, lab device), press for the rest.
- The default lab is now called "Police Lab".
- No more waiting before collecting (`Aging.Fresh = 0`, can be turned back on). Marker colours: green = ready, red = gone soon (blue = too fresh). Laser pointer and clearing away work on fresh evidence too.
- Lab device options in the order you use them: unload, analyse, upload.

### Removed
- "Set incident ID": the case ID now comes from the MDT upload.

### Fixed
- Kicked for "latent event packet overflow" when sending photos.
- G/H didn't work while looking through the camera.
- Photo badge and blood trail direction were lost after a restart. The last seconds before a stop are now saved too.
- A bag could exist twice if moving it out of the evidence case failed (upload to a case, unloading at the lab).
- The same evidence could be uploaded twice if the MDT sent it twice.
- Handing over the evidence case could sign the bags twice after a `whip_core` restart (same for the lab monitor).
- An empty bag was lost when dusting a weapon with full pockets.
- The scan didn't come back after a restart while the camera was already in hand.

### Upgrading from 3.x
Just replace both folders and restart. New tables are created on start, evidence on the ground and bags stay.
Check `/whip` → Jobs: the new permissions are on from their level up.
