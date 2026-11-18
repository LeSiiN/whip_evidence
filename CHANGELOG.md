# Changelog

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
