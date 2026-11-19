-- Client: leaves shoe prints and tyre tracks (reports stretches to the server) and draws them on the ground
-- (also the spot bleach leaves).
-- Shoes: mud, sand, snow (snowy weather: anywhere outside) and blood (after stepping in a stain).
-- Tyres: the same plus grass, and any ground while skidding or doing a burnout.

local TXD, SHOE_R, SHOE_L, TREAD, SPOT = 'whip_ev_tracks', 'shoe_r', 'shoe_l', 'tread', 'spot'
local DRAW_RANGE = 35.0

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
    mud   = { 58, 42, 30, 150 },
    sand  = { 96, 78, 55, 110 },
    snow  = { 130, 142, 160, 120 },
    grass = { 38, 52, 26, 110 },
    blood = { 82, 10, 8, 175 },
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
    CreateRuntimeTextureFromImage(txd, SHOE_R, 'html/img/tracks/shoe_r.png')
    CreateRuntimeTextureFromImage(txd, SHOE_L, 'html/img/tracks/shoe_l.png')
    CreateRuntimeTextureFromImage(txd, TREAD, 'html/img/tracks/tread.png')
    CreateRuntimeTextureFromImage(txd, SPOT, 'html/img/tracks/spot.png')
end

-- A flat quad on the ground: centre, forward and right half-vectors; both windings (seen from above either way)
local function quad(c, f, r, col, tex, z)
    local a = vector3(c.x - f.x - r.x, c.y - f.y - r.y, z)   -- back left
    local b = vector3(c.x + f.x - r.x, c.y + f.y - r.y, z)   -- front left
    local d = vector3(c.x + f.x + r.x, c.y + f.y + r.y, z)   -- front right
    local e = vector3(c.x - f.x + r.x, c.y - f.y + r.y, z)   -- back right
    local R, G, B, A = col[1], col[2], col[3], col[4]
    DrawTexturedPoly(a.x, a.y, a.z, b.x, b.y, b.z, d.x, d.y, d.z, R, G, B, A, TXD, tex, 0.0, 1.0, 1.0, 0.0, 0.0, 1.0, 1.0, 0.0, 1.0)
    DrawTexturedPoly(a.x, a.y, a.z, d.x, d.y, d.z, e.x, e.y, e.z, R, G, B, A, TXD, tex, 0.0, 1.0, 1.0, 1.0, 0.0, 1.0, 1.0, 1.0, 1.0)
    DrawTexturedPoly(a.x, a.y, a.z, d.x, d.y, d.z, b.x, b.y, b.z, R, G, B, A, TXD, tex, 0.0, 1.0, 1.0, 1.0, 0.0, 1.0, 0.0, 0.0, 1.0)
    DrawTexturedPoly(a.x, a.y, a.z, e.x, e.y, e.z, d.x, d.y, d.z, R, G, B, A, TXD, tex, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.0, 1.0)
end

-- Ground height under a point, looked up once per piece (slopes)
local function groundZ(x, y, z)
    local ok, gz = GetGroundZFor_3dCoord(x, y, z + 1.0, false)
    if ok and math.abs(gz - z) < 1.5 then return gz end
    return z
end

-- The same small differences every time for the same piece (no flicker, everyone sees the same)
local function rngOf(id)
    local x = 0
    for i = 1, #id do x = (x * 31 + id:byte(i)) % 2147483647 end
    return function()
        x = (x * 1103515245 + 12345) % 2147483648
        return x / 2147483648
    end
end

local function turned(v, deg)
    local r = math.rad(deg)
    local c, s = math.cos(r), math.sin(r)
    return vector3(v.x * c - v.y * s, v.x * s + v.y * c, 0.0)
end

-- The parts of one piece, worked out once: { centre, forward, right, z, strength 0-1, texture }
local function partsOf(ev)
    local look = ev.look or {}
    local h = math.rad((ev.heading or 0.0) + 90.0)
    local fwd = vector3(math.cos(h), math.sin(h), 0.0)
    local right = vector3(fwd.y, -fwd.x, 0.0)
    local c, parts = ev.coords, {}
    local rnd = rngOf(tostring(ev.id))
    if ev.kind == 'cleaned' then
        parts[1] = { c, fwd * 0.6, right * 0.6, groundZ(c.x, c.y, c.z) + 0.015, 1.0, SPOT }
    elseif ev.kind == 'shoeprint' then
        -- four steps behind the end of the stretch, left and right, toes a little outwards, never quite even.
        -- Blood: strongest at the stain (the oldest step), almost gone at the last one.
        local blood = look.s == 'blood'
        for i = 0, 3 do
            local leftFoot = i % 2 == 1
            local side = (leftFoot and -0.09 or 0.09) + (rnd() - 0.5) * 0.03
            local at = c - fwd * (i * 0.68 + 0.15 + (rnd() - 0.5) * 0.08) + right * side
            local angle = (leftFoot and 6.0 or -6.0) + (rnd() - 0.5) * 8.0
            local f, r = turned(fwd, angle), turned(right, angle)
            local strength = blood and (0.25 + 0.75 * (i / 3)) or (0.6 + rnd() * 0.4)
            parts[#parts + 1] = { at, f * 0.14, r * 0.055, groundZ(at.x, at.y, c.z) + 0.02, strength, leftFoot and SHOE_L or SHOE_R }
        end
    else
        local len = look.l or 6.0
        local n = math.max(1, math.floor(len / 2 + 0.5))   -- pieces of about 2 m (fewer polygons)
        local seg = len / n
        local sides = look.b and { 0.0 } or { -(look.w or 1.6) / 2, (look.w or 1.6) / 2 }
        local half = look.b and 0.07 or 0.12
        for _, side in ipairs(sides) do
            for i = 0, n - 1 do
                local at = c + fwd * (-len / 2 + seg * (i + 0.5)) + right * side
                -- fainter at both ends of the stretch
                local edge = math.min(i + 1, n - i) / math.max(1, math.ceil(n / 2))
                parts[#parts + 1] = { at, fwd * (seg / 2), right * half, groundZ(at.x, at.y, c.z) + 0.02,
                    0.55 + 0.45 * edge * (0.8 + rnd() * 0.2), TREAD }
            end
        end
    end
    return parts
end

local near = {}   -- pieces to draw, refreshed twice a second
CreateThread(function()
    while true do
        local n = 0
        if WhipEvidence.Ev.count() > 0 then
            local pos = GetEntityCoords(PlayerPedId())
            WhipEvidence.Ev.eachNear(pos, DRAW_RANGE, function(ev)
                if ev.kind == 'shoeprint' or ev.kind == 'tyre_track' or ev.kind == 'cleaned' then
                    n = n + 1
                    near[n] = ev
                end
            end)
        end
        for i = #near, n + 1, -1 do near[i] = nil end
        Wait(500)
    end
end)

local col = { 0, 0, 0, 0 }
-- drawn every frame only while a print or track is within DRAW_RANGE (otherwise it checks twice a second)
CreateThread(function()
    while true do
        local wait = 500
        if near[1] then
            wait = 0
            loadTextures()
            local now = GetGameTimer()
            for i = 1, #near do
                local ev = near[i]
                if WhipEvidence.Ev.get(ev.id) == ev then
                    ev.parts = ev.parts or partsOf(ev)
                    local base = COLOUR[(ev.look or {}).s] or COLOUR.mud
                    -- fades as it gets older
                    local total = math.max(1, (ev.endsAt or now) - (ev.bornAt or now))
                    local left = math.max(0.0, math.min(1.0, ((ev.endsAt or now) - now) / total))
                    local alpha = base[4] * (0.35 + 0.65 * left)
                    col[1], col[2], col[3] = base[1], base[2], base[3]
                    for _, p in ipairs(ev.parts) do
                        col[4] = math.floor(alpha * p[5])
                        quad(p[1], p[2], p[3], col, p[6], p[4])
                    end
                end
            end
        end
        Wait(wait)
    end
end)
