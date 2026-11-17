-- Client: evidence data, collect prompts, reporting shots, blood, prints in cars and on weapons
WhipEvidence.Ev = {}

local Evidence = {}      -- [id] = view from the server
local Vehicles = {}      -- [netId] = trace summary (what a scan shows on a car)
local shown = {}         -- [id] = true while its prompt is up
local GROUP = 'whip_ev'
local dirty = false      -- list changed: re-check prompts

local function stamp(ev)
    local now = GetGameTimer()
    ev.bornAt = now - (ev.age or 0) * 1000
    ev.endsAt = now + (ev.left or 0) * 1000
end

function WhipEvidence.Ev.all() return Evidence end
function WhipEvidence.Ev.get(id) return Evidence[id] end
function WhipEvidence.Ev.vehicles() return Vehicles end

---------------------------------------------------------------- Grid: every lookup only reads the cells around you
-- (all loops ask "what is near me", never walk the whole server's list)

local CELL = 32.0
local grid = {}          -- [cellKey] = { [id] = ev }
local count, lasers = 0, {}   -- lasers: [id] = ev (drawn for everyone)

local function cellOf(x, y)
    return math.floor(x / CELL), math.floor(y / CELL)
end

local function key(cx, cy) return cx * 100000 + cy end

local function put(ev)
    local old = Evidence[ev.id]
    if old then
        local ocx, ocy = cellOf(old.coords.x, old.coords.y)
        local cell = grid[key(ocx, ocy)]
        if cell then cell[ev.id] = nil end
    else
        count = count + 1
    end
    Evidence[ev.id] = ev
    local cx, cy = cellOf(ev.coords.x, ev.coords.y)
    local k = key(cx, cy)
    grid[k] = grid[k] or {}
    grid[k][ev.id] = ev
    lasers[ev.id] = ev.laser and ev or nil
end

local function unput(id)
    local ev = Evidence[id]
    if not ev then return end
    Evidence[id] = nil
    count = count - 1
    lasers[id] = nil
    local cx, cy = cellOf(ev.coords.x, ev.coords.y)
    local k = key(cx, cy)
    local cell = grid[k]
    if cell then
        cell[id] = nil
        if not next(cell) then grid[k] = nil end
    end
end

-- fn(ev, dist) for every piece within range of pos
function WhipEvidence.Ev.eachNear(pos, range, fn)
    if count == 0 then return end
    local x0, y0 = cellOf(pos.x - range, pos.y - range)
    local x1, y1 = cellOf(pos.x + range, pos.y + range)
    for cx = x0, x1 do
        for cy = y0, y1 do
            local cell = grid[key(cx, cy)]
            if cell then
                for _, ev in pairs(cell) do
                    local d = #(ev.coords - pos)
                    if d <= range then fn(ev, d) end
                end
            end
        end
    end
end

function WhipEvidence.Ev.near(pos, range)
    local found = false
    WhipEvidence.Ev.eachNear(pos, range, function() found = true end)
    return found
end

function WhipEvidence.Ev.count() return count end
function WhipEvidence.Ev.lasers() return lasers end

---------------------------------------------------------------- Prompts (only while scanning, close up)

-- The prompt only shows up close; further away the scan markers show the evidence
local PROMPT_RANGE = 6.0

-- Police clean-up. Without a photo it asks first: once it is gone, nothing proves it was there.
local function clearAway(id)
    local ev = Evidence[id]
    if not ev then return end
    if ev.photo then return TriggerServerEvent('whip_evidence:clear', id, false) end
    local sure = Whip.core:Confirm({
        title = ('#%s %s has no photo'):format(ev.no or '?', WhipEvidence.label(ev.kind)),
        message = 'Once it is cleared away, nothing proves it was ever here. Take a photo with the camera first (marker gets a camera badge).',
        yes = 'Clear anyway', no = 'Keep it',
    })
    if sure then
        TriggerServerEvent('whip_evidence:clear', id, true)
    else
        WhipEvidence.Scan.highlight({ id }, 30)
    end
end
WhipEvidence.Ev.clearAway = clearAway

-- Civilians get no scan: only a prompt on the ground, close up, and only with the right item
-- (pliers for a bullet, a cleaning cloth for the rest). Removing it takes a skill check.
local CIV_RANGE = 3.0

local function wipeItem(kind)
    return kind == 'bullet' and WhipEvidence.Items.pliers or WhipEvidence.Items.wipe
end

local function civilianAction(ev)
    local item = wipeItem(ev.kind)
    return {
        id = 'ev:' .. ev.id, group = GROUP, at = { coords = ev.coords + vector3(0.0, 0.0, 0.15) },
        label = WhipEvidence.label(ev.kind),
        reach = Config.PickupDistance, seeFrom = CIV_RANGE, focusMode = 'near',
        options = {
            { id = 'destroy', icon = 'fail', require = { item = item }, press = true,
              label = ev.kind == 'bullet' and 'Pull out the bullet' or 'Wipe away',
              onSelect = function() TriggerServerEvent('whip_evidence:destroy', ev.id) end },
        },
    }
end

local function actionFor(ev)
    if not WhipEvidence.isPoliceOnDuty() then return civilianAction(ev) end
    local options
    if ev.phase == 'green' then
        options = {
            { id = 'fresh', label = 'Too fresh', icon = 'timer',
              onSelect = function(ctx) ctx.refuse('This evidence is still too fresh.') end },
        }
    else
        local police = { job = Config.PoliceJobs, onDuty = true }
        options = {
            { id = 'pickup', icon = 'pickup', require = police, press = true,
              canInteract = function() return WhipEvidence.can('evidence_collect') end,
              label = ev.fails > 0 and ('Collect (%d/%d failed)'):format(ev.fails, Config.MaxFails) or 'Collect',
              onSelect = function() TriggerServerEvent('whip_evidence:pickup', ev.id, WhipEvidence.street(ev.coords)) end },
        }
        if ev.kind == 'bullet' and ev.origin then
            options[#options + 1] = { id = 'laser', icon = 'target', require = police,
                canInteract = function() return WhipEvidence.can('evidence_laser') end,
                label = ev.laser and 'Remove laser pointer' or 'Place laser pointer',
                onSelect = function() TriggerServerEvent('whip_evidence:laser', ev.id) end }
        end
        -- hold to clear: 1 s, without a photo 2 s (and it still asks)
        options[#options + 1] = { id = 'clear', icon = 'fail', require = police, holdMs = ev.photo and 1000 or 2000,
            canInteract = function() return WhipEvidence.can('evidence_clear') end,
            label = ev.photo and 'Clear away' or 'Clear away (no photo!)',
            onSelect = function() CreateThread(function() clearAway(ev.id) end) end }
    end

    local tint = WhipEvidence.PhaseColor[ev.phase] or '#ffffff'
    return {
        id = 'ev:' .. ev.id, group = GROUP, at = { coords = ev.coords + vector3(0.0, 0.0, 0.15) },
        label = ev.no and ('#%d %s'):format(ev.no, WhipEvidence.label(ev.kind)) or ('Evidence: ' .. WhipEvidence.label(ev.kind)),
        reach = Config.PickupDistance, seeFrom = PROMPT_RANGE, focusMode = 'near',
        style = { tint = tint, labelTint = tint },
        options = options,
    }
end

local function show(ev)
    local id, why = Whip.core:AddAction(actionFor(ev))
    if id then shown[ev.id] = true else WhipEvidence.debug('prompt %s: %s', ev.id, tostring(why)) end
end

local function hide(id)
    if shown[id] then
        shown[id] = nil
        Whip.core:RemoveAction('ev:' .. id)
    end
end

local function hideAll()
    if next(shown) then
        shown = {}
        Whip.core:RemoveActionGroup(GROUP)
    end
end

-- Police: prompts while scanning (Config.NeedFlashlight). Civilians: only while carrying a cloth or pliers
-- (looked up every 3 s, not every loop).
local civTools, civToolsAt = false, -10000

local function promptMode()
    if WhipEvidence.isPoliceOnDuty() then
        if Config.NeedFlashlight and not WhipEvidence.Scan.active() then return nil end
        return 'police'
    end
    local now = GetGameTimer()
    if now - civToolsAt > 3000 then
        civToolsAt = now
        civTools = Whip.core:HasItem(WhipEvidence.Items.wipe) or Whip.core:HasItem(WhipEvidence.Items.pliers)
    end
    return civTools and 'civ' or nil
end

CreateThread(function()
    local lastPos, lastMode
    while true do
        local wait = 1000
        local mode = count > 0 and promptMode() or nil
        if mode ~= lastMode then
            hideAll()   -- police and civilians get different prompts
            lastMode, lastPos = mode, nil
        end
        if mode then
            wait = 250
            local pos = GetEntityCoords(PlayerPedId())
            if dirty or not lastPos or #(pos - lastPos) > 1.5 then
                lastPos, dirty = pos, false
                local range = mode == 'civ' and CIV_RANGE or math.min(Config.SeeDistance, PROMPT_RANGE)
                local near = {}
                WhipEvidence.Ev.eachNear(pos, range, function(ev)
                    near[ev.id] = true
                    if not shown[ev.id] then show(ev) end
                end)
                for id in pairs(shown) do
                    if not near[id] then hide(id) end
                end
            end
        end
        Wait(wait)
    end
end)

---------------------------------------------------------------- Data from the server

function WhipEvidence.Ev.reset(list, vehicles)
    hideAll()
    Evidence, Vehicles, grid, count, lasers = {}, {}, {}, 0, {}
    for _, ev in ipairs(list or {}) do
        stamp(ev)
        put(ev)
    end
    for _, v in ipairs(vehicles or {}) do Vehicles[v.net] = v.s end
    dirty = true
    WhipEvidence.Props.dirty()
end

RegisterNetEvent('whip_evidence:client:add', function(batch)
    for _, ev in ipairs(batch) do
        stamp(ev)
        put(ev)
    end
    dirty = true
    WhipEvidence.Props.dirty()
end)

RegisterNetEvent('whip_evidence:client:remove', function(ids)
    for _, id in ipairs(ids) do
        unput(id)
        hide(id)
        WhipEvidence.Props.remove(id)
    end
end)

RegisterNetEvent('whip_evidence:client:update', function(list)
    for _, patch in ipairs(list) do
        local ev = Evidence[patch.id]
        if ev then
            if patch.phase ~= nil then ev.phase = patch.phase end
            if patch.fails ~= nil then ev.fails = patch.fails end
            if patch.laser ~= nil then
                ev.laser = patch.laser
                lasers[ev.id] = ev.laser and ev or nil
            end
            if patch.photo ~= nil then ev.photo = patch.photo end
            if patch.left ~= nil then ev.endsAt = GetGameTimer() + patch.left * 1000 end
            if patch.age ~= nil then ev.bornAt = GetGameTimer() - patch.age * 1000 end
            if shown[ev.id] then show(ev) end
        end
    end
end)

RegisterNetEvent('whip_evidence:client:vehicleTraces', function(net, summary)
    Vehicles[net] = summary
end)

---------------------------------------------------------------- Shots

local shotCooldown = 0

local function drawnGun()
    if GetResourceState('whip_gunny') ~= 'started' then return nil end
    local ok, w = pcall(function() return exports.whip_gunny:GetDrawnWeapon() end)
    if ok and type(w) == 'table' and w.kind == 'gun' and not WhipEvidence.isIgnoredWeapon(w.item) then return w end
    return nil
end

local function xyz(v) return { x = v.x, y = v.y, z = v.z } end

AddEventHandler('CEventGunShot', function()
    local now = GetGameTimer()
    if now < shotCooldown then return end
    local ped = PlayerPedId()
    if not IsPedShooting(ped) or WhipEvidence.blocked() or not drawnGun() then return end
    shotCooldown = now + 600

    local from = GetEntityCoords(ped)
    local casing = WhipEvidence.ground(GetOffsetFromEntityInWorldCoords(ped, 0.0, 1.0, -1.0))
    local hit, impact = 'none', from
    local veh = { net = 0, c1 = 0, c2 = 0, gx = 0.0, gy = 0.0, gz = 0.0 }

    local hasHit, ip = GetPedLastWeaponImpactCoord(ped)
    if hasHit and not IsAnyPedNearPoint(ip.x, ip.y, ip.z, 1.5) then
        impact = ip
        if IsAnyVehicleNearPoint(ip.x, ip.y, ip.z, 2.5) then
            local car = GetClosestVehicle(ip.x, ip.y, ip.z, 3.0, 0, 70)
            if car ~= 0 and NetworkGetEntityIsNetworked(car) then
                hit = 'vehicle'
                local c1, c2 = GetVehicleColours(car)
                local g = WhipEvidence.ground(GetEntityCoords(car))
                veh = { net = NetworkGetNetworkIdFromEntity(car), c1 = c1, c2 = c2, gx = g.x, gy = g.y, gz = g.z }
            end
        else
            hit = 'world'
        end
    end

    TriggerServerEvent('whip_evidence:shot', xyz(casing), hit, xyz(impact), veh)
end)

---------------------------------------------------------------- Blood and fingerprints

-- dir: heading the person was walking (blood trail), -1 = none
local function drop(kind, coords, chance, dir)
    local pos = WhipEvidence.ground(WhipEvidence.vec(coords))
    local inCar = IsPedInAnyVehicle(PlayerPedId(), false)   -- the server puts it into the car
    if not inCar and (WhipEvidence.Ev.near(pos, Config.MinDistance) or WhipEvidence.inNoEvidenceZone(pos)) then return end
    TriggerServerEvent('whip_evidence:drop', kind, xyz(pos), tonumber(chance) or -1, dir and math.floor(dir % 360) or -1)
end

-- The server saw this player lose health (shot, fall, crash) or die
RegisterNetEvent('whip_evidence:client:bleed', function(death)
    if WhipEvidence.blocked() then return end
    drop('blood', GetEntityCoords(PlayerPedId()), death and 100 or -1)
end)

-- Bleeding: a drop every few metres while on foot, further apart towards the end (the bleeding slows down).
-- The server sends { left, total, critical } on a hit, false when it stops (healed, dead).
local trailState, trailRunning = nil, false
RegisterNetEvent('whip_evidence:client:trail', function(t)
    if type(t) ~= 'table' then
        trailState = nil
        return
    end
    trailState = { endsAt = GetGameTimer() + (tonumber(t.left) or 0), total = math.max(1, tonumber(t.total) or 1),
                   critical = t.critical == true }
    if trailRunning then return end
    trailRunning = true
    CreateThread(function()
        local last = GetEntityCoords(PlayerPedId())
        while trailState do
            Wait(1000)
            local st = trailState
            if not st then break end
            local left = st.endsAt - GetGameTimer()
            if left <= 0 and not st.critical then
                trailState = nil
                break
            end
            local spacing = Config.BloodTrailMeters
            if not st.critical then
                local done = 1 - left / st.total
                spacing = spacing * (done < 0.34 and 1 or done < 0.67 and 2 or 3.5)
            end
            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)
            if not IsPedInAnyVehicle(ped, false) and #(pos - last) >= spacing then
                -- the way the person walked: the scan shows it as an arrow on the drop
                local dir = GetHeadingFromVector_2d(pos.x - last.x, pos.y - last.y)
                last = pos
                if not WhipEvidence.blocked() then drop('blood', pos, 100, dir) end
            end
        end
        trailRunning = false
    end)
end)

AddEventHandler('whip_core:player:logout', function()
    trailState = nil
end)

-- For other scripts: TriggerEvent('whip_evidence:client:CreateFingerDrop', coords, chance?)
AddEventHandler('whip_evidence:client:CreateFingerDrop', function(coords, chance)
    if not coords or WhipEvidence.blocked() then return end
    if WhipEvidence.glovesStopPrint() then return end
    drop('fingerprint', coords, chance)
end)

-- For other scripts: TriggerEvent('whip_evidence:client:CreateBloodDrop', coords, chance?)
AddEventHandler('whip_evidence:client:CreateBloodDrop', function(coords, chance)
    if not coords or WhipEvidence.blocked() then return end
    drop('blood', coords, chance)
end)

---------------------------------------------------------------- Prints in vehicles and on weapons

local pendingCar = {}

AddEventHandler('whip_core:vehicle:entered', function(e)
    if type(e) ~= 'table' or not e.entity or pendingCar[e.entity] then return end
    local car = e.entity
    pendingCar[car] = true
    CreateThread(function()
        local lo, hi = math.min(Config.PrintDelayMin, Config.PrintDelayMax), math.max(Config.PrintDelayMin, Config.PrintDelayMax)
        Wait(math.random(lo, hi) * 1000)
        pendingCar[car] = nil
        if GetVehiclePedIsIn(PlayerPedId(), false) ~= car or WhipEvidence.blocked() then return end
        if WhipEvidence.glovesStopPrint() then return end
        if not NetworkGetEntityIsNetworked(car) then return end
        TriggerServerEvent('whip_evidence:touchVehicle', NetworkGetNetworkIdFromEntity(car))
    end)
end)

-- Drawing a weapon: the server knows which one (serial) from whip_gunny, we only say "no gloves"
AddEventHandler('whip_gunny:weapon:drawn', function(w)
    if type(w) ~= 'table' or not w.serial then return end
    if WhipEvidence.glovesStopPrint() then return end
    TriggerServerEvent('whip_evidence:touchWeapon')
end)
