# whip_evidence

Forensics for WHIP: evidence at crime scenes, real crime scene photos, minigames, labs with a monitor,
ballistics, gunshot residue, vehicle and weapon traces, an evidence case and case lockers for your MDT.

Version 4.0.0 · Changes: `CHANGELOG.md` · In-game test: `TESTING.md`

## Requires

- `whip_core` (1.0+), `oxmysql`
- [whip_evidence_assets](https://github.com/LeSiiN/whip_evidence_assets) (props, ships with this)
- `whip_gunny` (shots, weapon prints)

## Install

1. Put `whip_evidence` and `whip_evidence_assets` in `resources/`. Don't rename `whip_evidence` (the folder name sets the item names).
2. In `server.cfg`, after `whip_core`:
   ```
   ensure whip_evidence_assets
   ensure whip_evidence
   ```
3. Start the server. Tables, items and missing police jobs are made automatically.
4. In game, `/whip` → Settings → Forensics: set the lab, its monitor and the evidence locker with "here".

Restart only `whip_evidence`. Leave `whip_evidence_assets` running (unloading props in use crashes the game).

## Jobs and ranks

Jobs in `Config.PoliceJobs` (`police`, `bcso`, `sahp`) that don't exist yet are created from `Config.Jobs`.
Existing jobs keep their name and ranks.

Each permission below shows up as a toggle on every rank in `/whip` → Jobs. On the first start it is switched on
from its `level` up. After that you decide. `Config.UsePermissions = false`: every on-duty officer may do everything.

| Permission | Allows | From level |
|---|---|---|
| `evidence_scan` | Scan with flashlight / camera | 1 |
| `evidence_photo` | Crime scene photos | 1 |
| `evidence_collect` | Collect evidence | 20 |
| `evidence_gsr` | GSR tests | 20 |
| `evidence_vehicle` | Collect vehicle traces | 20 |
| `evidence_laser` | Laser pointer | 20 |
| `evidence_sign` | Sign for evidence | 20 |
| `evidence_clear` | Clear away single traces | 20 |
| `evidence_upload` | Upload evidence to a case (MDT) | 20 |
| `evidence_locker` | Open case lockers | 20 |
| `evidence_dust` | Dust weapons for prints | 40 |
| `evidence_release` | Release crime scenes | 40 |
| `evidence_lab` | Run lab analyses | 40 |
| `evidence_locker_take` | Take items out of case lockers (without: look only) | 40 |
| `evidence_case_close` | Close cases | 60 |

If another resource owns one of these jobs, the permissions can't be added: the console says so and every on-duty officer may do everything.

## Items

| Item | Use |
|---|---|
| `whip_evidence_kit` | Forensics kit: collect, GSR test, vehicle traces, dust weapons (wears out) |
| `whip_evidence_case` | Evidence case: 30 compartments, new bags go in first |
| `whip_evidence_bag` | Evidence bag (picture and colour per evidence type) |
| `whip_evidence_empty_bag` | Empty bag, only used with `Config.NeedEmptyBag = true` |
| `whip_evidence_photo` | Crime scene photo (camera, key H) |
| `whip_evidence_laser` | Laser pointer for bullet holes |
| `whip_evidence_pliers` | Pliers: civilians pull bullets out (wears out) |
| `whip_evidence_wipe` | Cleaning cloth: wipe evidence, car interiors and weapons |

Pictures: `html/img/items/`. Wear: `/whip` → Economy → Items → "Wear per use".

## A case, step by step

1. **Scan.** On-duty police aim a flashlight (`gunny_torch`) or hold the `camera`. Every trace gets a numbered marker
   (same number for everyone). Colour: green = too fresh, orange = ready, red = gone soon.
   Trajectories link a casing to its bullet. Blood trails show which way the person walked.
   **G** changes the filter, the camera shows a legend.
2. **Photo.** **H** with the camera takes a real screenshot. The photo item lists every marker in it.
   Right-click → "View photo" (polaroid, click to zoom) or "Copy as text". Photographed markers get a camera badge.
3. **Collect.** "Collect" → minigame → the bag goes into your evidence case. Three fails ruin the trace.
   Vehicles: at a front door. Weapons: right-click → "Dust for prints". People: aim → "GSR test".
4. **Lab.** At the lab device: "Unload evidence case", then "Analyse evidence" (5–10 min, storage locked).
   A gun in the storage gets test-fired: a reference casing and "Ballistic match" on matching casings.
   The lab also tells how old a trace was when it was collected. The monitor shows progress and results.
5. **Case.** Upload analysed items to a case in your MDT (or at the lab device: "Upload to a case").
   They move into that case's locker. Open it at any evidence locker by typing the case ID.
6. **Clean up.** "Clear away" on a marker, or F1 → "Release crime scene". Unphotographed traces need a confirmation.

Every bag and photo has a **chain of custody**: collected, received, in lab, analysed, uploaded, taken out, returned.
Right-click → "Sign for evidence" when you take it over.

## Civilians

No scan. With a cleaning cloth (bullets: pliers) they can remove a trace right next to them after a minigame,
clean a car's interior or wipe a weapon.

**GSR** (gunshot residue): every shot fills it, it fades over `Config.GsrMinutes` and shows as a ring on your own HUD.
Gone by: washing in water (F1), swimming, standing in the rain on foot, or right-clicking a cleaning item
(`Config.GsrCleaners`: water bottle, cleaning cloth, ... each with time and "used up / wears out / stays").
The test says "strong" or "weak traces".

**Blood on clothes**: your own when you get hurt, someone else's when you stand next to them as they are hit
or carry / escort them while they are badly hurt. A red ring on your HUD. Police: aim at a person → "Swab clothes for blood"
(one bag per person whose blood it is, the lab tells the blood type). Gone by water, swimming, new clothes,
a cleaning item with `blood = true`, or after `Config.BloodOnMinutes`.

**Gloves** wear out with every shot and every print they catch (a ring on your HUD, red when nearly torn).
The more worn, the more prints get through: from `GloveLeakChance` (new) up to `GloveTornLeak` (torn).
Each pair keeps its own wear; another pair starts fresh.

## Where traces come from

- **Shots**: casings, bullets, vehicle fragments, GSR. Shots from inside a car stay in the car.
- **Blood**: when you lose health and where you die. A hit leaves a trail for a while (`BloodTrailSeconds`, longer for heavy hits), thinning out towards the end; critically hurt players keep bleeding until healed.
- **Fingerprints**: sitting in a car or drawing a weapon without gloves.
- Evidence ages and disappears; rain speeds it up. It survives restarts.

## Settings

- Admins: `/whip` → Settings → Forensics (overrides `config/config.lua`).
- Officers: pause menu → Settings → Server Settings → Forensics (legend, marker and card size, photo viewer).
- Keys: Settings → Key Bindings → FiveM.
- Lab monitor: pick any prop per lab (`screenModel`, `none` = a monitor already in the map). To put the picture exactly on the screen: `/w` → Forensics → "Fit the lab screen", then aim at the top left, top right and bottom left corner of the monitor's glass and click each (tilted monitors and any shape work). Then fine-tune: arrows move, W/S into/out of the monitor, mouse wheel size, R picks the corners again, Enter saves. Logo: your PNG at `html/img/screen/logo.png`. Clock and date are the player's real time.

## Admins

`/w` → Forensics: remove evidence, test kit, place test evidence, make it ready, finish lab analyses,
analyse your bags, fit the lab screen, manage case lockers (open, close, reopen, delete). Console: `clearevidence`.

## For other scripts

### MDT

whip_evidence keeps the **things** (bags, photos, guns, lab, lockers). Your MDT keeps the **cases** (IDs, reports, people).
The only link between them is the **case ID**. Everything below runs on the **server**: call the exports from your MDT's
server code, never straight from its NUI.

**How it fits together**

1. Officer collects evidence → lab analyses it → in the officer's pockets / evidence case it is now `analysed = true`.
2. MDT case page → "Add evidence" → your server calls `GetUploadable(source)` → your NUI shows the list.
3. Officer ticks items → your server calls `Upload(source, refs, caseId)` → for every `ok` result, save `entry` in your DB.
   The items now sit in that case's locker in game (`Case: <id>` on the item, chain of custody updated).
4. In game, officers open the locker at an evidence locker by typing the case ID (or your MDT calls `OpenCaseLocker`).
5. `whip_evidence:caseChanged` tells your MDT when something changed → refresh with `GetCase(caseId)`.
6. Closing the case in your MDT → `CloseCase(caseId, source)` (the locker becomes look only).

**Rules worth knowing**

- Case ID: text, letters / digits / `_` / `-`, max 32 characters, a leading `#` is ignored. Numeric IDs: pass `tostring(id)`.
- Only analysed items upload. One item belongs to one case for good; uploading it again to the same case is fine.
- `GetUploadable` returns nothing for players who are not on-duty police. `Upload` also checks `evidence_upload`,
  `CloseCase`/`ReopenCase` check `evidence_case_close` when you pass `source` (leave it out to skip the rank check).
- Lock the exports to your MDT: `Config.ApiResources = { 'your-mdt' }`. Others get `false, 'Not allowed'` / `nil` / `{}`.
- Start order: `ensure whip_evidence` before your MDT.

**1. At MDT start: how to check a case ID** (needed for "Upload to a case" at the lab device)

```lua
local function hookEvidence()
    exports.whip_evidence:SetCaseCheck(function(caseId, source)
        return MySQL.scalar.await('SELECT 1 FROM mdt_cases WHERE id = ?', { caseId }) ~= nil
    end)
end
CreateThread(function()
    while GetResourceState('whip_evidence') ~= 'started' do Wait(500) end
    hookEvidence()
end)
-- whip_evidence restarted: it forgot the check
AddEventHandler('onResourceStart', function(res) if res == 'whip_evidence' then SetTimeout(1000, hookEvidence) end end)
```

**2. "Add evidence" list**

```lua
-- your MDT server, called by your NUI with the open case
local function listEvidence(source, caseId)
    local out = {}
    for _, e in ipairs(exports.whip_evidence:GetUploadable(source)) do
        out[#out + 1] = {
            ref = e.ref, kind = e.kind, label = e.type, time = e.time, street = e.street,
            analysed = e.analysed,
            otherCase = e.case and e.case ~= caseId and e.case or nil,     -- already belongs elsewhere
            canAdd = e.analysed and (not e.case or e.case == caseId),
            results = e.results,                                           -- bags only
        }
    end
    return out
end
```

Show not-yet-analysed items greyed out ("Lab first") instead of hiding them: officers then know why.

**3. Upload and save**

```lua
local function addEvidence(source, caseId, refs)
    local results, err = exports.whip_evidence:Upload(source, refs, caseId)
    if not results then return { error = err } end              -- e.g. 'This case is closed.'
    for _, r in ipairs(results) do
        if r.ok then
            MySQL.insert.await([[INSERT INTO mdt_case_evidence (case_id, ref, kind, data) VALUES (?, ?, ?, ?)
                ON DUPLICATE KEY UPDATE data = VALUES(data)]], { caseId, r.ref, r.entry.kind, json.encode(r.entry) })
        end
    end
    return { results = results }                                 -- show r.why next to every failed item
end
```

Suggested table: `mdt_case_evidence (case_id VARCHAR(32), ref VARCHAR(80), kind VARCHAR(20), data LONGTEXT, PRIMARY KEY (case_id, ref))`.
The `entry` is a snapshot for reports; the real item lives in the locker.

**4. Stay in sync**

```lua
AddEventHandler('whip_evidence:caseChanged', function(caseId, why)
    -- why: 'uploaded', 'taken', 'returned', 'closed', 'reopened', 'deleted'
    local case = exports.whip_evidence:GetCase(caseId)          -- nil after 'deleted'
    -- case.items = entries in the locker, case.taken[ref] = { by, at, what } = who has it outside the locker
end)
```

**5. Photos**

`entry.entries` lists the markers in the picture (`n` number, `t` type, `d` metres, `s` state, `a` age in minutes),
`entry.cars` the vehicles. The picture itself: `GetPhotoImage(entry.photo_id)` → a `data:image/...;base64,...` text
(up to a few MB). Load it only when an officer opens the photo, and keep your own copy if the MDT should still show it
after `Config.Photo.KeepDays` (photos in a case locker are never deleted).

**Entry fields**

| Field | All | Bag | Photo | Weapon |
|---|---|---|---|---|
| `ref` (`bag:<id>`, `photo:<id>`, `gun:<serial>`), `item`, `kind`, `type`, `case`, `analysed`, `custody` | ✓ | | | |
| `time`, `street`, `collected_by`, `marker` (scene number), `photographed`, `tested_on` | | ✓ | | |
| `results` = `{ ammo, weapon_serial, fingerprint, blood_type, paint, gsr, ballistics, age }` | | ✓ | | |
| `photo_id`, `time`, `street`, `scene`, `taken_by`, `entries`, `cars` | | | ✓ | |
| `serial`, `caliber`, `ballistics` | | | | ✓ |

`custody` is one text: `"11/16 14:02 Collected · Sgt | Smith → 11/16 14:20 In lab: Police Lab · ..."`
(split on `" → "`; first entry and the newest five are kept). `kind` for bags: `casing`, `bullet`, `blood`,
`fingerprint`, `vehicle_fragment`, `gsr`, `reference`.

**All exports**

```lua
exports.whip_evidence:GetUploadable(source)             -- { entry, ... } (pockets + evidence cases)
exports.whip_evidence:Upload(source, refs, caseId)      -- { { ref, ok, why?, entry? } } or false, why
exports.whip_evidence:GetCase(caseId)                   -- { id, created, closed, closedBy, items, taken } or nil
exports.whip_evidence:CloseCase(caseId, source?)        -- true or false, why
exports.whip_evidence:ReopenCase(caseId, source?)       -- true or false, why
exports.whip_evidence:OpenCaseLocker(source, caseId)    -- only works at an evidence locker
exports.whip_evidence:GetPhotoImage(photoId)            -- data URL or nil
exports.whip_evidence:SetCaseCheck(function(caseId, source) return exists end)
AddEventHandler('whip_evidence:caseChanged', function(caseId, why) end)
```

**Checklist for building it (people or AI)**

- [ ] `Config.ApiResources` set, whip_evidence starts first, `SetCaseCheck` hooked (also after a whip_evidence restart).
- [ ] Case page: "Add evidence" list from `GetUploadable`, not-analysed items shown but disabled.
- [ ] Upload: save every `ok` entry, show every `why`.
- [ ] Case page shows saved entries (type, results, custody) and refreshes on `caseChanged`.
- [ ] Photos load on demand with `GetPhotoImage`.
- [ ] Closing / reopening a case calls `CloseCase` / `ReopenCase` with the officer's `source`.
- [ ] Never pass a case ID or refs from NUI without checking that this officer may edit that case in your MDT.

### Evidence

```lua
-- Client
TriggerEvent('whip_evidence:client:CreateFingerDrop', coords, 80)   -- chance optional
TriggerEvent('whip_evidence:client:CreateBloodDrop', coords)

-- Server
exports.whip_evidence:CreateEvidence('fingerprint', coords, { source = src })

-- Minigames in your own scripts
exports.whip_core:SkillCheck(source, 'easy', { game = 'whip_evidence.dust' })
```
