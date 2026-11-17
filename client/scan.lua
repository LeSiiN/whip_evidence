-- Client: scan mode. Aim a flashlight or hold the camera item:
--  * every piece of evidence in view gets a numbered marker tag (the number is the same for everyone)
--  * the one you aim at gets a card with details, cars with traces get a card (V1, V2, ...)
--  * police see shot trajectories: a line from a casing to the bullet of the same shot
--  * with the camera: a legend of everything in the picture, and a key that takes a photo (an item)
--  * a key cycles a filter (all, blood, casings, ...)
-- One DUI browser draws everything (atlas, painted only on change). Nothing runs per frame unless there is something to draw.
WhipEvidence.Scan = {}

local FLASHLIGHT = GetHashKey('WEAPON_FLASHLIGHT')
local MAX_MARKERS, CAR_CARDS, LEGEND_ROWS, MAX_LINES = 60, 3, 12, 40
local TAG_LIFT = 0.4          -- metres between evidence and the bottom of its tag
local cameraUp = false        -- told by the server while the WHIP camera item is in hand
local scanning = false
local worldHidden = false     -- WHIP's clean screen (filming) hides world UI
local markers, focus, cars, lines, lasers = {}, nil, {}, {}, {}
local picture = { ids = {}, cars = {} }   -- what a photo would show right now
local legendOn = false
-- the player's layout (client/settings.lua), read every 500 ms
local layout = { legend = true, side = 'right', top = 0.08, width = 0.2, tag = 1.0, card = 1.0, lines = true }

local function readLayout()
    layout.legend = WhipEvidence.ui('legend') ~= false
    layout.side = WhipEvidence.ui('legendSide') == 'left' and 'left' or 'right'
    layout.top = (tonumber(WhipEvidence.ui('legendTop')) or 8) / 100
    layout.width = (tonumber(WhipEvidence.ui('legendSize')) or 20) / 100
    layout.tag = (tonumber(WhipEvidence.ui('tagSize')) or 100) / 100
    layout.card = (tonumber(WhipEvidence.ui('cardSize')) or 100) / 100
    layout.lines = WhipEvidence.ui('trajectories') ~= false
end
local shooting = false        -- a screenshot is being taken: legend and card stay out of the picture
local highlight = {}          -- [id] = until (GetGameTimer): markers that blink (missing photos)
local lastSummary

-- phase keys are the old names; shown as blue = too fresh, green = ready, red = gone soon
local PHASE = {
    green  = { name = 'Too fresh', i = 0, color = 'blue' },
    yellow = { name = 'Ready',     i = 1, color = 'green' },
    red    = { name = 'Gone soon', i = 2, color = 'red' },
}

local FILTERS = {
    { key = 'all',              label = 'All' },
    { key = 'blood',            label = 'Blood' },
    { key = 'casing',           label = 'Casings' },
    { key = 'bullet',           label = 'Bullets' },
    { key = 'fingerprint',      label = 'Fingerprints' },
    { key = 'vehicle_fragment', label = 'Fragments' },
    { key = 'vehicles',         label = 'Vehicles' },
}
local filter = 1

local function passes(kind)
    local f = FILTERS[filter].key
    return f == 'all' or f == kind
end

---------------------------------------------------------------- DUI atlas (one browser for everything)

local PAGE = ('nui://%s/html/scan.html'):format(WhipEvidence.Res)
local TXD, TEX = 'whip_evidence_scan', 'atlas'
local W, H = 1024, 1024
local IDLE_MS = 60000
local dui, up, waiting, painted, lastUsed = nil, false, {}, {}, 0

local function release()
    if dui then DestroyDui(dui) end
    dui, up, waiting, painted = nil, false, {}, {}
end

local function checkIdle()
    if not dui then return end
    local left = lastUsed + IDLE_MS - GetGameTimer()
    if left > 0 then SetTimeout(left, checkIdle) else release() end
end

local function ensure()
    lastUsed = GetGameTimer()
    if dui then return end
    local ok, handle = pcall(CreateDui, PAGE, W, H)
    if not ok or not handle then return end
    dui = handle
    CreateRuntimeTextureFromDuiHandle(CreateRuntimeTxd(TXD), TEX, GetDuiHandle(dui))
    local mine = dui
    CreateThread(function()
        local untilAt = GetGameTimer() + 10000
        while dui == mine and not IsDuiAvailable(mine) and GetGameTimer() < untilAt do Wait(50) end
        if dui ~= mine then return end
        Wait(250)   -- a fresh page can miss its very first message
        up = true
        for _, m in ipairs(waiting) do SendDuiMessage(dui, json.encode(m)) end
        waiting = {}
    end)
    SetTimeout(IDLE_MS, checkIdle)
end

-- Paints one cell (0-5, 'legend' or 'photo'), only when its content changed
local function paint(cell, data)
    data.action, data.cell = 'paint', cell
    local text = json.encode(data)
    if painted[cell] == text then return end
    painted[cell] = text
    if up then SendDuiMessage(dui, text) else waiting[#waiting + 1] = data end
end

-- UVs (see the layout in html/scan.html)
local function uv(x, y, w, h)
    return x / W, y / H, (x + w) / W, (y + h) / H
end
local function cardUv(cell)
    return uv((cell % 2) * 256 + 8, math.floor(cell / 2) * 128 + 8, 240, 112)
end
local LEGEND_UV = { uv(512, 0, 512, 640) }
local BADGE_UV  = { uv(512 + 6 * 64, 640, 64, 64) }   -- camera badge: already photographed
local ARROW_UV  = { uv(512 + 7 * 64, 640, 64, 64) }   -- blood trail: the way the person walked

-- GTA heading (0 = north, 90 = west) as a compass word
local COMPASS = { 'N', 'NW', 'W', 'SW', 'S', 'SE', 'E', 'NE' }
local function compass(h)
    return COMPASS[math.floor(((h % 360) + 22.5) / 45) % 8 + 1]
end
local TAG_UV, RING_UV, DIGIT_UV = {}, {}, {}
for i = 0, 2 do
    TAG_UV[i] = { uv(512 + i * 64, 704, 64, 80) }
    RING_UV[i] = { uv(512 + (i + 3) * 64, 640, 64, 64) }
end
for d = 0, 9 do DIGIT_UV[d] = { uv(512 + d * 32, 784, 32, 64) } end

---------------------------------------------------------------- Keys

local function keyLabel(command, fallback)
    local ok, label = pcall(GetControlInstructionalButton, 0, joaat(command) | 0x80000000, true)
    if ok and type(label) == 'string' and label:sub(1, 2) == 't_' then return label:sub(3) end
    return fallback
end

local function hint()
    local text = ('[%s] Filter: %s'):format(keyLabel('whip_evidence_filter', Config.ScanKeys.Filter), FILTERS[filter].label)
    if cameraUp then text = text .. ('   [%s] Photo'):format(keyLabel('whip_evidence_photo', Config.ScanKeys.Photo)) end
    return text
end

-- WHIP's camera viewfinder holds the game input (IsGameInputFree() is false while it is up),
-- so with the camera in hand only the pause menu stops the keys. Typing never reaches key mappings.
local function keysAllowed()
    if cameraUp then return not IsPauseMenuActive() end
    return Whip.core:IsGameInputFree()
end

-- A key can arrive twice (key mapping and the camera fallback below): only once per 300 ms
local lastPress = {}
local function once(what)
    local now = GetGameTimer()
    if lastPress[what] and now - lastPress[what] < 300 then return false end
    lastPress[what] = now
    return true
end

local function nextFilter()
    if not scanning or not keysAllowed() or not once('filter') then return end
    filter = filter % #FILTERS + 1
    PlaySoundFrontend(-1, 'NAV_LEFT_RIGHT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
end

local function flash()
    CreateThread(function()
        local untilAt = GetGameTimer() + 180
        while GetGameTimer() < untilAt do
            local a = math.floor(220 * (untilAt - GetGameTimer()) / 180)
            DrawRect(0.5, 0.5, 1.0, 1.0, 255, 255, 255, a)
            Wait(0)
        end
    end)
end

-- A real photo: WHIP's TakeScreenshot (the markers are in it, the legend and card are not).
-- The server makes the item, then asks for the picture (whip_evidence:client:photoUpload).
local snapping, pendingPicture = false, nil

local function takePhoto()
    if not cameraUp or not scanning or not keysAllowed() or not once('photo') or snapping then return end
    if not WhipEvidence.can('evidence_photo') then return WhipEvidence.notify('Your rank does not take crime scene photos.', 'info') end
    if #picture.ids == 0 and #picture.cars == 0 then
        return WhipEvidence.notify('There is no evidence in the picture.', 'info')
    end
    snapping = true
    local ids, carNets = picture.ids, picture.cars
    local street = WhipEvidence.street(GetEntityCoords(PlayerPedId()))
    CreateThread(function()
        PlaySoundFrontend(-1, 'Camera_Shoot', 'Phone_Soundset_Franklin', true)
        shooting = true
        Wait(0)
        Wait(0)
        local shot = { format = Config.Photo.Format == 'jpg' and 'jpg' or 'webp', quality = Config.Photo.Quality }
        if (Config.Photo.Width or 0) > 0 then shot.width = Config.Photo.Width end   -- 0: full screen, sharpest
        local image = Whip.core:TakeScreenshot(shot)
        shooting = false
        flash()
        pendingPicture = type(image) == 'string' and image or nil
        if not pendingPicture then WhipEvidence.notify('The camera could not take a picture. The photo still lists everything.', 'warning') end
        TriggerServerEvent('whip_evidence:photo', ids, carNets, street, pendingPicture ~= nil)
        snapping = false
    end)
end

-- The picture goes in small parts with a short pause: one big event gets you kicked
RegisterNetEvent('whip_evidence:client:photoUpload', function(photoId)
    local image = pendingPicture
    pendingPicture = nil
    if not image then return end
    CreateThread(function()
        local size = WhipEvidence.PhotoChunk
        local parts = math.ceil(#image / size)
        TriggerServerEvent('whip_evidence:photoBegin', photoId, parts, #image)
        Wait(200)
        for i = 1, parts do
            TriggerServerEvent('whip_evidence:photoPart', photoId, i, image:sub((i - 1) * size + 1, i * size))
            Wait(80)   -- about 125 KB/s: never floods the connection
        end
    end)
end)

-- Blink these markers for a while (e.g. evidence that still needs a photo)
function WhipEvidence.Scan.highlight(ids, seconds)
    local untilAt = GetGameTimer() + (seconds or 30) * 1000
    for _, id in ipairs(ids) do highlight[id] = untilAt end
end

RegisterCommand('whip_evidence_filter', nextFilter, false)
RegisterKeyMapping('whip_evidence_filter', 'Evidence scan: next filter', 'keyboard', Config.ScanKeys.Filter)
RegisterCommand('whip_evidence_photo', takePhoto, false)
RegisterKeyMapping('whip_evidence_photo', 'Evidence scan: take a photo (camera)', 'keyboard', Config.ScanKeys.Photo)

-- Fallback while the viewfinder is up: read G and H as game controls too (they still report while
-- disabled). Only while the binding is still G / H, so a player who rebinds gets just their key.
local KEY_CONTROLS = { G = { 47, 58 }, H = { 74, 304 } }
local bound = { filter = nil, photo = nil, checkedAt = 0 }

local function pressed(key)
    local list = KEY_CONTROLS[key]
    if not list then return false end
    for i = 1, #list do
        if IsDisabledControlJustPressed(0, list[i]) or IsControlJustPressed(0, list[i]) then return true end
    end
    return false
end

local function cameraKeys()
    local now = GetGameTimer()
    if now - bound.checkedAt > 2000 then
        bound.checkedAt = now
        bound.filter = keyLabel('whip_evidence_filter', Config.ScanKeys.Filter)
        bound.photo = keyLabel('whip_evidence_photo', Config.ScanKeys.Photo)
    end
    if pressed(bound.filter) then nextFilter() end
    if pressed(bound.photo) then takePhoto() end
end

---------------------------------------------------------------- What to show

RegisterNetEvent('whip_evidence:client:camera', function(on)
    cameraUp = on == true
end)

AddEventHandler('whip_core:player:logout', function()
    cameraUp = false
end)

AddEventHandler('whip_core:ui:cleanScreen', function(e)
    worldHidden = type(e) == 'table' and e.on == true and e.world == true
end)

function WhipEvidence.Scan.active()
    return scanning
end

-- Only on-duty police with the scan permission get the scan (markers, cards, legend, trajectories, photos)
local function detect()
    if not WhipEvidence.can('evidence_scan') then return false end
    if cameraUp then return true end
    local ped = PlayerPedId()
    if GetSelectedPedWeapon(ped) == FLASHLIGHT and IsPlayerFreeAiming(PlayerId()) then return true end
    return IsPedUsingScenario(ped, 'WORLD_HUMAN_PAPARAZZI')
end

local function minutes(ms)
    local m = math.floor(ms / 60000)
    if m < 1 then return '<1 min' end
    return ('%d min'):format(m)
end

local function metres(d)
    return ('%d m'):format(math.floor(d + 0.5))
end

-- Card for the aimed-at evidence. Police on duty see everything, others only type and state.
local function evidenceCard(ev, dist, police)
    local st = PHASE[ev.phase] or PHASE.yellow
    local chips = { { text = st.name, color = st.color } }
    if police then
        local now = GetGameTimer()
        chips[#chips + 1] = { text = minutes(now - (ev.bornAt or now)) .. ' old' }
        chips[#chips + 1] = { text = minutes(math.max(0, (ev.endsAt or now) - now)) .. ' left' }
        if ev.fails and ev.fails > 0 then chips[#chips + 1] = { text = ('%d/%d failed'):format(ev.fails, Config.MaxFails), color = 'red' } end
        if ev.laser then chips[#chips + 1] = { text = 'Laser', color = 'red' } end
        chips[#chips + 1] = ev.photo and { text = 'Photographed', color = 'green' } or { text = 'No photo', color = 'yellow' }
        if ev.dir then chips[#chips + 1] = { text = 'Trail heading ' .. compass(ev.dir), color = 'red' } end
    end
    return { no = ev.no and tostring(ev.no) or nil, title = WhipEvidence.label(ev.kind), color = st.color, dist = metres(dist), chips = chips }
end

-- Short line for the legend
local function evidenceInfo(ev, police)
    local st = PHASE[ev.phase] or PHASE.yellow
    if not police then return st.name end
    local now = GetGameTimer()
    local text = ('%s · %s old'):format(st.name, minutes(now - (ev.bornAt or now)))
    if ev.laser then text = text .. ' · Laser' end
    if ev.dir then text = text .. ' · trail ' .. compass(ev.dir) end
    return text
end

local function carParts(s, police)
    local parts = {}
    if s.blood > 0 then parts[#parts + 1] = { text = 'Blood', color = 'red' } end
    if s.casing > 0 then parts[#parts + 1] = { text = ('%d casing%s'):format(s.casing, s.casing > 1 and 's' or '') } end
    if s.bullet > 0 then parts[#parts + 1] = { text = ('%d bullet hole%s'):format(s.bullet, s.bullet > 1 and 's' or '') } end
    if s.gsr then parts[#parts + 1] = { text = 'GSR', color = 'yellow' } end
    if s.prints and police then parts[#parts + 1] = { text = 'Possible prints' } end
    return parts
end

local function onScreen(pos)
    local on, x, y = GetScreenCoordFromWorldCoord(pos.x, pos.y, pos.z)
    return on, x, y
end

-- Rebuilt every 500 ms: markers, focus card, car cards, trajectories, legend, summary, lasers
-- Lasers are drawn for everyone (a real beam); usually there are none, then this costs nothing
local function collectLasers(pos)
    local list = {}
    for _, ev in pairs(WhipEvidence.Ev.lasers()) do
        if ev.origin and #(ev.coords - pos) < 60.0 then
            list[#list + 1] = { from = ev.origin + vector3(0.0, 0.0, 0.5), to = ev.coords }
        end
    end
    return list
end

-- Everything a marker needs per frame, worked out here once (no strings or maths per frame)
local function markerGeometry(m, aspect)
    local w = math.max(0.011, math.min(0.024, 0.024 - m.dist * 0.0005)) * layout.tag
    local h = w * (80 / 64) * aspect
    m.w, m.h = w, h
    local text = tostring(m.no)
    local n = #text
    local scale = n == 1 and 0.95 or (n == 2 and 0.72 or 0.55)
    local dw = w * 0.5 * scale
    m.dw, m.dh = dw, dw * 2 * aspect
    local step = dw * 0.78
    m.digits = {}
    for i = 1, n do
        local d = tonumber(text:sub(i, i))
        if d then m.digits[#m.digits + 1] = { dx = (i - (n + 1) / 2) * step, uv = DIGIT_UV[d] } end
    end
    m.line = m.dist < 18.0
    m.bw = w * 0.55
    m.ring = math.max(0.014, 0.03 - m.dist * 0.0006)
    local dir = m.ev.dir
    if dir then
        -- a point 0.6 m ahead on the ground: the arrow turns to face it on screen
        local r = math.rad(dir)
        m.tip = m.pos + vector3(-math.sin(r) * 0.6, math.cos(r) * 0.6, 0.03)
        m.aw = math.max(0.012, 0.026 - m.dist * 0.0006) * layout.tag
    else
        m.tip = nil
    end
end

local lastLayout = 0

local function rebuild()
    if scanning and GetGameTimer() - lastLayout > 3000 then
        lastLayout = GetGameTimer()
        readLayout()
    end
    local pos = GetEntityCoords(PlayerPedId())
    if not scanning then
        lasers = collectLasers(pos)
        return
    end
    local police = WhipEvidence.isPoliceOnDuty()
    local aspect = GetAspectRatio(false)
    local found = {}
    WhipEvidence.Ev.eachNear(pos, Config.SeeDistance, function(ev, dist)
        if passes(ev.kind) then found[#found + 1] = { ev = ev, dist = dist } end
    end)
    local laserList = collectLasers(pos)
    table.sort(found, function(a, b) return a.dist < b.dist end)

    local counts = { green = 0, yellow = 0, red = 0 }
    local photographed = 0
    local list, inPicture, shots = {}, {}, {}
    local best, bestScore
    for i, f in ipairs(found) do
        local ev = f.ev
        counts[ev.phase] = (counts[ev.phase] or 0) + 1
        if ev.photo then photographed = photographed + 1 end
        if i <= MAX_MARKERS then
            local m = { id = ev.id, ev = ev, pos = ev.coords, dist = f.dist, no = ev.no or 0, phase = (PHASE[ev.phase] or PHASE.yellow).i,
                        photo = ev.photo == true }
            markerGeometry(m, aspect)
            list[#list + 1] = m
            local on, sx, sy = onScreen(ev.coords + vector3(0.0, 0.0, TAG_LIFT))
            if on then
                inPicture[#inPicture + 1] = m
                local dx, dy = sx - 0.5, (sy - 0.5) / aspect
                local score = dx * dx + dy * dy
                if score < 0.006 and (not bestScore or score < bestScore) then best, bestScore = m, score end
            end
        end
        if police and ev.shot and (ev.kind == 'casing' or ev.kind == 'bullet') then
            shots[ev.shot] = shots[ev.shot] or {}
            shots[ev.shot][ev.kind] = ev.coords
        end
    end

    -- the aimed-at one gets a card (cell 0)
    if best then
        paint(0, evidenceCard(best.ev, best.dist, police))
        focus = { m = best }
    else
        focus = nil
    end

    -- shot trajectories (police): casing -> bullet of the same shot
    local lineList = {}
    for _, s in pairs(shots) do
        if s.casing and s.bullet and #lineList < MAX_LINES then lineList[#lineList + 1] = { from = s.casing, to = s.bullet } end
    end

    -- cars with traces (cells 1-3), named V1, V2, ...
    local carList, carRows, carNets = {}, {}, {}
    if scanning and passes('vehicles') then
        for net, s in pairs(WhipEvidence.Ev.vehicles()) do
            if #carList >= CAR_CARDS then break end
            if NetworkDoesNetworkIdExist(net) then
                local ent = NetworkGetEntityFromNetworkId(net)
                if DoesEntityExist(ent) then
                    local cpos = GetEntityCoords(ent)
                    local dist = #(cpos - pos)
                    local parts = dist <= Config.SeeDistance and carParts(s, police) or {}
                    if #parts > 0 then
                        local tag = 'V' .. (#carList + 1)
                        local cell = 1 + #carList
                        paint(cell, { no = tag, car = true, title = 'Vehicle', dist = metres(dist), chips = parts })
                        carList[#carList + 1] = { cell = cell, ent = ent, dist = dist }
                        if onScreen(cpos + vector3(0.0, 0.0, 1.0)) then
                            local texts = {}
                            for _, p in ipairs(parts) do texts[#texts + 1] = p.text end
                            carRows[#carRows + 1] = { no = tag, car = true, title = 'Vehicle', info = table.concat(texts, ', '), dist = metres(dist) }
                            carNets[#carNets + 1] = net
                        end
                    end
                end
            end
        end
    end

    markers, cars, lines, lasers = list, carList, lineList, laserList

    -- what a photo would show
    local ids = {}
    for _, m in ipairs(inPicture) do ids[#ids + 1] = m.id end
    picture = { ids = ids, cars = carNets }

    if not scanning then return end

    -- camera: legend of everything in the picture (sorted by marker number)
    legendOn = cameraUp and layout.legend
    if legendOn then
        table.sort(inPicture, function(a, b) return a.no < b.no end)
        local rows = {}
        for _, m in ipairs(inPicture) do
            if #rows >= LEGEND_ROWS then break end
            rows[#rows + 1] = { no = tostring(m.no), title = WhipEvidence.label(m.ev.kind), info = evidenceInfo(m.ev, police),
                                color = m.ev.phase, dist = metres(m.dist), photo = m.photo }
        end
        for _, r in ipairs(carRows) do
            if #rows >= LEGEND_ROWS then break end
            rows[#rows + 1] = r
        end
        local total = #inPicture + #carRows
        paint('legend', {
            label = 'CRIME SCENE', street = WhipEvidence.street(pos),
            sub = ('%02d:%02d · %d in the picture · %d/%d photographed'):format(GetClockHours(), GetClockMinutes(), total, photographed, #found),
            rows = rows, more = total > #rows and (total - #rows) or nil, hint = hint(),
        })
        if lastSummary then
            lastSummary = nil
            Whip.core:HideText()
        end
        return
    end

    local summary = ('Evidence nearby: %d | %d ready · %d too fresh · %d gone soon | %d/%d photographed')
        :format(#found, counts.yellow, counts.green, counts.red, photographed, #found)
    if #carList > 0 then summary = summary .. (' | %d vehicle(s) with traces'):format(#carList) end
    summary = summary .. ' | ' .. hint()
    if summary ~= lastSummary then
        lastSummary = summary
        Whip.core:ShowText(summary, { icon = 'target' })
    end
end

local function stopScan()
    scanning, legendOn = false, false
    markers, focus, cars, lines = {}, nil, {}, {}
    picture = { ids = {}, cars = {} }
    if lastSummary then
        lastSummary = nil
        Whip.core:HideText()
    end
end

---------------------------------------------------------------- Drawing (every frame, only while needed)

-- natives as locals: the draw loop runs every frame
local DrawSpriteUv, DrawLine = DrawSpriteUv, DrawLine
local GetScreenCoordFromWorldCoord = GetScreenCoordFromWorldCoord

local function sprite(x, y, w, h, t)
    DrawSpriteUv(TXD, TEX, x, y, w, h, t[1], t[2], t[3], t[4], 0.0, 255, 255, 255, 255)
end

local function cardSprite(x, y, w, h, cell)
    local u1, v1, u2, v2 = cardUv(cell)
    DrawSpriteUv(TXD, TEX, x, y, w, h, u1, v1, u2, v2, 0.0, 255, 255, 255, 255)
end

local function cardSize(dist, aspect)
    local w = math.max(0.07, math.min(0.13, 0.135 - dist * 0.003)) * layout.card
    return w, w * (112 / 240) * aspect
end

-- one marker: yellow tag, coloured stripe (age), digits, badge. Geometry from markerGeometry.
local function drawMarker(m, x, y, aspect)
    local cy = y - m.h / 2
    sprite(x, cy, m.w, m.h, TAG_UV[m.phase])
    local dy, digits = cy - m.h * 0.11, m.digits
    for i = 1, #digits do
        local d = digits[i]
        sprite(x + d.dx, dy, m.dw, m.dh, d.uv)
    end
    local top = cy - m.h / 2
    if m.photo then sprite(x + m.w * 0.45, top + m.bw * aspect * 0.15, m.bw, m.bw * aspect, BADGE_UV) end
    return top
end

local function trailArrow(m, aspect)
    local p, t = m.pos, m.tip
    local on, gx, gy = GetScreenCoordFromWorldCoord(p.x, p.y, p.z + 0.03)
    if not on then return end
    local on2, tx, ty = GetScreenCoordFromWorldCoord(t.x, t.y, t.z)
    if not on2 then return end
    local angle = math.deg(math.atan((tx - gx) * aspect, -(ty - gy)))
    local u = ARROW_UV
    DrawSpriteUv(TXD, TEX, gx, gy, m.aw, m.aw * aspect, u[1], u[2], u[3], u[4], angle, 255, 255, 255, 235)
end

local function groundRing(p, size, uvs, aspect)
    local on, gx, gy = GetScreenCoordFromWorldCoord(p.x, p.y, p.z + 0.02)
    if on then sprite(gx, gy, size, size * aspect, uvs) end
end

local function drawFrame(aspect)
    if shooting then HideHudAndRadarThisFrame() end
    if up and not worldHidden then
        local focused = not shooting and focus and focus.m
        local now = GetGameTimer()
        for i = 1, #markers do
            local m = markers[i]
            local p = m.pos
            local on, x, y = GetScreenCoordFromWorldCoord(p.x, p.y, p.z + TAG_LIFT)
            if on then
                if m.line then DrawLine(p.x, p.y, p.z + 0.03, p.x, p.y, p.z + TAG_LIFT, 255, 255, 255, 120) end
                local top = drawMarker(m, x, y, aspect)
                if m.tip then trailArrow(m, aspect) end
                local hl = highlight[m.id]
                if hl then
                    if hl < now then
                        highlight[m.id] = nil
                    else
                        groundRing(p, (0.03 + 0.012 * math.sin(now / 120)) * math.max(0.5, 1.0 - m.dist / 40), RING_UV[2], aspect)
                    end
                end
                if m == focused then
                    groundRing(p, m.ring, RING_UV[m.phase], aspect)
                    local cw, ch = cardSize(m.dist, aspect)
                    cardSprite(x, top - 0.006 - ch / 2, cw, ch, 0)
                end
            end
        end
        for i = 1, #cars do
            local c = cars[i]
            if DoesEntityExist(c.ent) then
                local p = GetEntityCoords(c.ent)
                local on, x, y = GetScreenCoordFromWorldCoord(p.x, p.y, p.z + 1.3)
                if on then
                    local cw, ch = cardSize(c.dist, aspect)
                    cardSprite(x, y - ch / 2, cw, ch, c.cell)
                end
            end
        end
        if layout.lines then
            for i = 1, #lines do
                local l = lines[i]
                DrawLine(l.from.x, l.from.y, l.from.z + 0.03, l.to.x, l.to.y, l.to.z, 250, 204, 21, 210)
            end
        end
        if legendOn and not shooting then
            local w = layout.width
            local h = w * (640 / 512) * aspect
            local x = layout.side == 'left' and (0.012 + w / 2) or (1.0 - 0.012 - w / 2)
            sprite(x, layout.top + h / 2, w, h, LEGEND_UV)
        end
    end
    for i = 1, #lasers do
        local l = lasers[i]
        DrawLine(l.from.x, l.from.y, l.from.z, l.to.x, l.to.y, l.to.z, 255, 0, 0, 200)
    end
end

-- draws for 500 ms, then everything is looked up again
local function drawFor500ms()
    local untilAt = GetGameTimer() + 500
    local aspect = GetAspectRatio(false)
    repeat
        local t = WhipCost and WhipCost.start()
        drawFrame(aspect)
        if cameraUp and scanning then cameraKeys() end
        if t then WhipCost.stop('evidence: scan overlay', t) end
        Wait(0)
    until GetGameTimer() >= untilAt
end

-- Idle cost: civilians and officers off duty only check for lasers (a table that is almost always empty)
-- and sleep 1.5 s. On duty, without flashlight or camera: one cheap check every 500 ms.
CreateThread(function()
    while true do
        local police = WhipEvidence.isPoliceOnDuty()
        local hasData = WhipEvidence.Ev.count() > 0 or next(WhipEvidence.Ev.vehicles()) ~= nil
        local active = police and hasData and detect()
        if active then
            if not scanning then readLayout() end
            scanning = true
            ensure()
        elseif scanning then
            stopScan()
        end
        if hasData then rebuild() elseif #lasers > 0 then lasers = {} end
        if #markers > 0 or #cars > 0 or #lasers > 0 or legendOn then
            drawFor500ms()
        else
            Wait(active and 250 or (police and 500 or 1500))
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= WhipEvidence.Res then return end
    stopScan()
    release()
end)
