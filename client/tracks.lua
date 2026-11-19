-- Client: leaves shoe prints and tyre tracks (reports stretches to the server) and draws them on the ground
-- (also the spot bleach leaves).
-- Shoes: mud, sand, snow (snowy weather: anywhere outside) and blood (after stepping in a stain).
-- Tyres: the same plus grass, and any ground while skidding or doing a burnout.

local TXD, SPOT = 'whip_ev_tracks', 'spot'
-- one picture per piece (one quad): four steps baked in (two variants each), both tyres of a car, a bike's tyre
local TEX = { 'trail_a', 'trail_b', 'trail_blood_a', 'trail_blood_b', 'tyres_car', 'tyre_bike', 'spot' }
local DRAW_RANGE = 25.0

-- How often: a stretch of steps every SHOE_GAP metres walked on soft ground, a stretch of track every
-- TYRE_GAP metres driven (and never closer in time than the *_MS). Blood: one stretch right after the stain.
local SHOE_GAP, SHOE_MS = 12.0, 5000
local TYRE_LEN, TYRE_GAP, TYRE_MS = 8.0, 25.0, 4000

-- Ground materials (hash -> surface)
local MAT = {}
for _, h in ipairs({ -1595148316, 510490462, 909950165, -1907520769, 509508168, 1288448767 }) do MAT[h] = 'sand' end
for _, h in ipairs({ -1942898710, 312396330, 1635937914, 1109728704, 223086562, 1584636462, -700658213,
    1144315879, 560985072, -1885547121 }) do MAT[h] = 'mud' end
for _, h in ipairs({ -1937569590, -878560889, 1619704960, 1550304810 }) do MAT[h] = 'snow' end
local GRASS = { [-461750719] = true, [1333033863] = true, [-1286696947] = true }
local SNOWY = { [`XMAS`] = true, [`SNOW`] = true, [`SNOWLIGHT`] = true, [`BLIZZARD`] = true }

-- Colour on the ground per surface (the texture is white)
local COLOUR = {
    mud   = { 45, 32, 22, 225 },
    sand  = { 88, 70, 48, 185 },
    snow  = { 115, 128, 148, 190 },
    grass = { 30, 40, 20, 170 },
    blood = { 120, 12, 10, 240 },
    skid  = { 20, 20, 20, 150 },
    cleaned = { 225, 228, 215, 95 },   -- bleached, wet-looking patch
}

local function snowy()
    return SNOWY[GetPrevWeatherTypeHashName()] or SNOWY[GetNextWeatherTypeHashName()]
end

-- What is under this point: ground position and surface (nil = leaves nothing)
local function surfaceAt(pos, ignore, tyres)
    local ray = StartExpensiveSynchronousShapeTestLosProbe(pos.x, pos.y, pos.z + 0.3, pos.x, pos.y, pos.z - 2.2, 1, ignore, 7)
    local _, hit, at, _, mat = GetShapeTestResultIncludingMaterial(ray)
    if not hit or hit == 0 or not at then return nil end
    local s = MAT[mat]
    if not s and tyres and GRASS[mat] then s = 'grass' end
    if not s and snowy() and GetInteriorFromEntity(ignore) == 0 and mat ~= 435688960 then s = 'snow' end
    return at, s
end

local function headingOf(from, to)
    return (math.deg(math.atan(to.y - from.y, to.x - from.x)) - 90.0) % 360.0
end

local function xyz(v) return { x = v.x + 0.0, y = v.y + 0.0, z = v.z + 0.0 } end

local function leaving()
    if Config.Tracks == false then return false end
    if Config.TrackPolice ~= true and WhipEvidence.isPoliceOnDuty() then return false end
    return true
end

---------------------------------------------------------------- Shoes

local NO_WHEELS = { type = -1, mod = -1, gauge = 0.0 }

CreateThread(function()
    local from, lastSent, bloodAt, bloodId = nil, 0, nil, nil
    local lastShoes, shoesAt = nil, 0
    while true do
        local wait = 1000
        local ped = PlayerPedId()
        -- the server needs to know the shoes (for the code of the print); again now and then (restarts)
        local s = GetPedDrawableVariation(ped, 6)
        if s ~= lastShoes or GetGameTimer() - shoesAt > 30000 then
            lastShoes, shoesAt = s, GetGameTimer()
            TriggerServerEvent('whip_evidence:shoes', s)
        end
        if leaving() and not IsPedInAnyVehicle(ped, false) and not IsPedSwimming(ped) and not IsPedFalling(ped)
            and not IsPedRagdoll(ped) and GetEntitySpeed(ped) > 0.6 then
            wait = 300
            local p = GetEntityCoords(ped)
            local at, surface = surfaceAt(p, ped, false)
            -- stepped in blood: one bloody stretch right after it (fading), then nothing
            if not bloodAt then
                WhipEvidence.Ev.eachNear(p - vector3(0.0, 0.0, 0.95), 0.7, function(ev)
                    if ev.kind == 'blood' then bloodAt, bloodId = at or p, ev.id end
                end)
            end
            if at and bloodAt then
                if #(at - bloodAt) >= 3.0 then
                    TriggerServerEvent('whip_evidence:track', 'shoe', 'blood', xyz(at), headingOf(bloodAt, at), 0.0, 0, NO_WHEELS, bloodId)
                    lastSent, from, bloodAt = GetGameTimer(), nil, nil
                    -- no new bloody stretch from the same stain for a while
                    local stain = bloodId
                    SetTimeout(20000, function() if bloodId == stain then bloodId = nil end end)
                end
            elseif at and surface then
                if not from then
                    from = at
                elseif #(at - from) >= 3.0 and GetGameTimer() - lastSent > SHOE_MS then
                    -- a few steps, then a gap: SHOE_GAP metres before the next stretch
                    TriggerServerEvent('whip_evidence:track', 'shoe', surface, xyz(at), headingOf(from, at), 0.0, 0, NO_WHEELS, '-')
                    lastSent, from = GetGameTimer(), nil
                    wait = math.floor(SHOE_GAP / math.max(1.0, GetEntitySpeed(ped)) * 1000)
                end
            else
                from = nil
            end
        end
        Wait(math.min(wait, 6000))
    end
end)

---------------------------------------------------------------- Tyres

local function wheelsOf(car)
    local min, max = GetModelDimensions(GetEntityModel(car))
    return {
        type = GetVehicleWheelType(car), mod = GetVehicleMod(car, 23),
        gauge = math.max(0.0, math.min(3.0, (max.x - min.x) - 0.35)),
    }
end
WhipEvidence.wheelsOf = wheelsOf

-- A burnout, a handbrake slide at speed, or a full stop from high speed: tracks on any ground.
-- Needs two samples in a row (0.6 s), so normal braking leaves nothing.
local skidCount = 0
local function skidding(car, speed, before)
    if IsVehicleInBurnout(car) then return true end
    local hard = (IsControlPressed(0, 72) and before > 15.0 and before - speed > 3.5)
        or (IsControlPressed(0, 76) and before > 10.0 and before - speed > 1.5)
    skidCount = hard and skidCount + 1 or 0
    return skidCount >= 2
end

CreateThread(function()
    local from, last, surf, lastSent, lastSpeed, sentAt = nil, nil, nil, 0, 0.0, nil
    -- sends the stretch from `from` to `last` (at least 3 m); then TYRE_GAP metres pass before the next one
    local function flush(car)
        if not from or not last then return end
        local len = #(last - from)
        if len >= 3.0 and GetGameTimer() - lastSent > TYRE_MS and NetworkGetEntityIsNetworked(car) then
            TriggerServerEvent('whip_evidence:track', 'tyre', surf, xyz((from + last) / 2), headingOf(from, last), len,
                NetworkGetNetworkIdFromEntity(car), wheelsOf(car), '-')
            lastSent, sentAt = GetGameTimer(), last
        end
    end
    while true do
        local wait = 1000
        local ped = PlayerPedId()
        local car = GetVehiclePedIsIn(ped, false)
        local s, at
        if car ~= 0 and leaving() and GetPedInVehicleSeat(car, -1) == ped then
            local class = GetVehicleClass(car)
            -- cars, bikes, quads (no boats, aircraft, trains)
            if class ~= 14 and class ~= 15 and class ~= 16 and class ~= 21 then
                wait = 300
                local speed = GetEntitySpeed(car)
                if IsVehicleOnAllWheels(car) and speed > 2.0 then
                    at, s = surfaceAt(GetEntityCoords(car), car, true)
                    if at and not s and skidding(car, speed, lastSpeed) then s = 'skid' end
                end
                lastSpeed = speed
            end
        else
            lastSpeed = 0.0
        end
        if at and sentAt and #(at - sentAt) < TYRE_GAP and s ~= 'skid' then
            from, last = nil, nil   -- the gap after a stretch (a skid always counts)
        elseif at and s then
            if from and s ~= surf then
                flush(car)
                from = nil
            end
            if not from then from = at end
            surf, last = s, at
            if #(last - from) >= TYRE_LEN then
                flush(car)
                from, last = nil, nil
            end
        else
            if car ~= 0 then flush(car) end
            from, last = nil, nil
        end
        Wait(wait)
    end
end)

---------------------------------------------------------------- Drawing

local loaded = false
local function loadTextures()
    if loaded then return end
    loaded = true
    local txd = CreateRuntimeTxd(TXD)
    for _, name in ipairs(TEX) do CreateRuntimeTextureFromImage(txd, name, ('html/img/tracks/%s.png'):format(name)) end
end

-- Which side of a polygon GTA shows is not documented: both are drawn by default. `/evidence_trackfaces`
-- switches between both / only one / only the other, so the cheaper single side can be tested in game.
local FACES = GetResourceKvpString('trackfaces') or 'b'   -- 'b' is the side GTA shows from above
RegisterCommand('evidence_trackfaces', function()
    FACES = FACES == 'both' and 'a' or (FACES == 'a' and 'b' or 'both')
    SetResourceKvp('trackfaces', FACES)
    print(('[whip_evidence] prints and tracks drawn with side: %s'):format(FACES))
end, false)

local DrawTexturedPoly = DrawTexturedPoly
-- One flat quad, corners worked out once (p = { ax, ay, bx, by, dx, dy, ex, ey, z, strength, texture })
local function quad(p, R, G, B, A)
    local z, tex = p[9], p[11]
    if FACES ~= 'b' then
        DrawTexturedPoly(p[1], p[2], z, p[3], p[4], z, p[5], p[6], z, R, G, B, A, TXD, tex, 0.0, 1.0, 1.0, 0.0, 0.0, 1.0, 1.0, 0.0, 1.0)
        DrawTexturedPoly(p[1], p[2], z, p[5], p[6], z, p[7], p[8], z, R, G, B, A, TXD, tex, 0.0, 1.0, 1.0, 1.0, 0.0, 1.0, 1.0, 1.0, 1.0)
    end
    if FACES ~= 'a' then
        DrawTexturedPoly(p[1], p[2], z, p[5], p[6], z, p[3], p[4], z, R, G, B, A, TXD, tex, 0.0, 1.0, 1.0, 1.0, 0.0, 1.0, 0.0, 0.0, 1.0)
        DrawTexturedPoly(p[1], p[2], z, p[7], p[8], z, p[5], p[6], z, R, G, B, A, TXD, tex, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.0, 1.0)
    end
end

-- centre c, half-vectors f (forward) and r (right) -> the flat corner list
local function corners(c, f, r, z, strength, tex)
    return { c.x - f.x - r.x, c.y - f.y - r.y,   -- back left
             c.x + f.x - r.x, c.y + f.y - r.y,   -- front left
             c.x + f.x + r.x, c.y + f.y + r.y,   -- front right
             c.x - f.x + r.x, c.y - f.y + r.y,   -- back right
             z, strength, tex }
end

-- Ground height under a point, looked up once per piece (slopes)
local function groundZ(x, y, z)
    local ok, gz = GetGroundZFor_3dCoord(x, y, z + 1.0, false)
    if ok and math.abs(gz - z) < 1.5 then return gz end
    return z
end

-- The parts of one piece, worked out once: one quad each (corners, z, strength, texture)
local function partsOf(ev)
    local look = ev.look or {}
    local h = math.rad((ev.heading or 0.0) + 90.0)
    local fwd = vector3(math.cos(h), math.sin(h), 0.0)
    local right = vector3(fwd.y, -fwd.x, 0.0)
    local c = ev.coords
    if ev.kind == 'cleaned' then
        return { corners(c, fwd * 0.6, right * 0.6, groundZ(c.x, c.y, c.z) + 0.015, 1.0, SPOT) }
    end
    if ev.kind == 'shoeprint' then
        -- four steps behind the end of the stretch, in one picture (two variants; blood fades towards the end)
        local id = tostring(ev.id)
        local variant = (id:byte(#id) or 0) % 2 == 0 and 'a' or 'b'
        local tex = (look.s == 'blood' and 'trail_blood_' or 'trail_') .. variant
        local mid = c - fwd * 1.175
        return { corners(mid, fwd * 1.3, right * 0.2, groundZ(mid.x, mid.y, c.z) + 0.02, 1.0, tex) }
    end
    -- tyre track: both tyres of a car in one picture (or a bike's one), faint at both ends
    local len = look.l or 6.0
    local half = look.b and 0.07 or ((look.w or 1.6) + 0.24) / 2
    return { corners(c, fwd * (len / 2), right * half, groundZ(c.x, c.y, c.z) + 0.02, 1.0, look.b and 'tyre_bike' or 'tyres_car') }
end

local near = {}   -- pieces to draw (in range, with their colour), refreshed twice a second
local SIZE = { shoeprint = 2.6, tyre_track = 7.5, cleaned = 0.9 }   -- radius for "is it on screen"
CreateThread(function()
    while true do
        local n = 0
        if WhipEvidence.Ev.count() > 0 then
            local pos = GetEntityCoords(PlayerPedId())
            local now = GetGameTimer()
            WhipEvidence.Ev.eachNear(pos, DRAW_RANGE, function(ev)
                if SIZE[ev.kind] then
                    n = n + 1
                    near[n] = ev
                    ev.parts = ev.parts or partsOf(ev)
                    -- colour and how faded (it changes slowly: worked out here, not every frame)
                    local base = COLOUR[(ev.look or {}).s] or COLOUR.mud
                    local total = math.max(1, (ev.endsAt or now) - (ev.bornAt or now))
                    local left = math.max(0.0, math.min(1.0, ((ev.endsAt or now) - now) / total))
                    ev.rgb, ev.alpha = base, base[4] * (0.35 + 0.65 * left)
                end
            end)
        end
        for i = #near, n + 1, -1 do near[i] = nil end
        Wait(500)
    end
end)

-- drawn every frame only while a print or track is within DRAW_RANGE (otherwise it checks twice a second);
-- a piece off screen costs one check, nothing is drawn for it
local IsSphereVisible, floor, Get = IsSphereVisible, math.floor, WhipEvidence.Ev.get
CreateThread(function()
    while true do
        local wait = 500
        if near[1] then
            wait = 0
            loadTextures()
            local t = WhipCost and WhipCost.start()
            for i = 1, #near do
                local ev = near[i]
                local c = ev.coords
                if ev.parts and Get(ev.id) == ev and IsSphereVisible(c.x, c.y, c.z, SIZE[ev.kind]) then
                    local rgb, alpha = ev.rgb, ev.alpha
                    for j = 1, #ev.parts do
                        local p = ev.parts[j]
                        quad(p, rgb[1], rgb[2], rgb[3], floor(alpha * p[10]))
                    end
                end
            end
            if t then WhipCost.stop('evidence: prints and tracks', t) end
        end
        Wait(wait)
    end
end)
