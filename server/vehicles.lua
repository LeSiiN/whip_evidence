-- Traces inside vehicles. A car remembers who sat in it, who bled in it, shots fired from inside
-- (casings, GSR) and bullet holes. Police collects them at a front door, a cleaning cloth removes them.
WhipEvidence.Vehicles = {}

local traces = {}   -- [key] = { net, plate, prints = { [charId] = t }, blood = { [charId] = { t, data } },
                    --           casing = { [serial] = { t, n, data } }, bullet = { [serial] = { t, n, data } }, gsr = t }

local function entityOf(net)
    local ent = NetworkGetEntityFromNetworkId(net)
    if ent and ent ~= 0 and DoesEntityExist(ent) and GetEntityType(ent) == 2 then return ent end
    return nil
end

-- WHIP vehicles by vehicleId, everything else by plate
local function keyOf(ent)
    local v = exports.whip_core:GetVehicle({ entity = ent })
    if type(v) == 'table' and v.vehicleId then return 'v' .. v.vehicleId, v.plate end
    local plate = (GetVehicleNumberPlateText(ent) or ''):gsub('%s+', '')
    return 'p' .. plate, plate
end

local function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- What clients see while scanning (no names, no serials)
local function summary(tr)
    local casings, bullets = 0, 0
    for _, c in pairs(tr.casing) do casings = casings + c.n end
    for _, b in pairs(tr.bullet) do bullets = bullets + b.n end
    local s = { prints = next(tr.prints) ~= nil, blood = count(tr.blood), casing = casings, bullet = bullets, gsr = tr.gsr ~= nil }
    if not s.prints and s.blood == 0 and s.casing == 0 and s.bullet == 0 and not s.gsr then return nil end
    return s
end

-- Changed cars go out together every 500 ms (shots from inside a car change it every shot)
local pushQueue = {}
local function push(tr)
    pushQueue[tr] = true
end

CreateThread(function()
    while true do
        Wait(500)
        if next(pushQueue) then
            local q = pushQueue
            pushQueue = {}
            for tr in pairs(q) do
                TriggerClientEvent('whip_evidence:client:vehicleTraces', -1, tr.net, summary(tr))
            end
        end
    end
end)

local function traceOf(ent, create)
    local key, plate = keyOf(ent)
    local tr = traces[key]
    if not tr and create then
        tr = { prints = {}, blood = {}, casing = {}, bullet = {} }
        traces[key] = tr
    end
    if tr then
        tr.net, tr.plate, tr.key = NetworkGetNetworkIdFromEntity(ent), plate, key
    end
    return tr
end

-- kind: print | blood | casing | bullet | gsr
function WhipEvidence.Vehicles.addTrace(ent, kind, data, charId)
    local tr = traceOf(ent, true)
    local t = os.time()
    local before = summary(tr)
    if kind == 'print' then
        tr.prints[charId] = t
    elseif kind == 'blood' then
        tr.blood[charId] = { t = t, data = data }
    elseif kind == 'casing' or kind == 'bullet' then
        local list = tr[kind]
        local key = data.serial or 'Unknown'
        local entry = list[key] or { n = 0, data = data }
        entry.n, entry.t = math.min(entry.n + 1, 99), t
        list[key] = entry
    elseif kind == 'gsr' then
        tr.gsr = t
    end
    local after = summary(tr)
    if json.encode(before) ~= json.encode(after) then push(tr) end
end

-- For photos: what a car shows and its plate (nil without traces)
function WhipEvidence.Vehicles.photoInfo(ent)
    local tr = traceOf(ent, false)
    local s = tr and summary(tr)
    if not s then return nil end
    return s, tr.plate
end

function WhipEvidence.Vehicles.summaries()
    local out = {}
    for _, tr in pairs(traces) do
        local s = summary(tr)
        if s and tr.net then out[#out + 1] = { net = tr.net, s = s } end
    end
    return out
end

function WhipEvidence.Vehicles.tick()
    if not next(traces) then return end
    local cutoff = os.time() - Config.VehicleTraceMinutes * 60
    for key, tr in pairs(traces) do
        local before = json.encode(summary(tr))
        for id, t in pairs(tr.prints) do if t < cutoff then tr.prints[id] = nil end end
        for id, b in pairs(tr.blood) do if b.t < cutoff then tr.blood[id] = nil end end
        for id, c in pairs(tr.casing) do if c.t < cutoff then tr.casing[id] = nil end end
        for id, b in pairs(tr.bullet) do if b.t < cutoff then tr.bullet[id] = nil end end
        if tr.gsr and tr.gsr < cutoff then tr.gsr = nil end
        local s = summary(tr)
        if json.encode(s) ~= before then push(tr) end
        if not s then traces[key] = nil end
    end
end

local function vehicleNear(range)
    return {
        at = function(_, _, net)
            local ent = entityOf(net)
            return ent and GetEntityCoords(ent) or nil
        end,
        range = range,
    }
end

local function isEmpty(ent)
    for seat = -1, 6 do
        local ped = GetPedInVehicleSeat(ent, seat)
        if ped and ped ~= 0 then return false end
    end
    return true
end

local function examine(source, ent, label)
    local done = exports.whip_core:Progress(source, {
        label = label, duration = 15000, icon = 'car',
        anim = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 1 },
        disable = { move = true, combat = true, car = true },
        near = { coords = GetEntityCoords(ent), range = 6.0 },
    })
    return done
end

-- One bag per trace. Returns the number of bags.
local function collect(source, player, tr, street)
    local stamp = {
        time         = os.date('%Y-%m-%d %H:%M:%S'),
        street       = street,
        collected_by = WhipEvidence.officerLabel(source, player),
        tested_on    = L('vehicle_plate', tr.plate or '?'),
    }
    local queries, made, lost = {}, 0, 0

    local function give(kind, typeLabel, data, extra)
        local meta = {}
        for k, v in pairs(stamp) do meta[k] = v end
        meta.evidence_id, meta.kind, meta.type = WhipEvidence.Data.newId(), kind, typeLabel
        for k, v in pairs(extra or {}) do meta[k] = v end
        meta.custody = WhipEvidence.custody(nil, L('custody_collected'), stamp.collected_by)
        local secret = WhipEvidence.Evidence.secretFor(kind, data, meta)
        if not WhipEvidence.useEmptyBag(source) then
            lost = lost + 1
            return
        end
        if not WhipEvidence.giveBag(source, meta, 'Vehicle traces ' .. (tr.plate or '?')) then
            WhipEvidence.returnEmptyBag(source)
            lost = lost + 1
        else
            if next(secret) then queries[#queries + 1] = WhipEvidence.Data.bagQuery(meta.evidence_id, kind, secret) end
            made = made + 1
        end
    end

    for charId in pairs(tr.prints) do
        local traits = WhipEvidence.Data.traits(charId)
        if traits then give('fingerprint', L('type_fp_vehicle'), { fingerprint = traits.fingerprint }) end
    end
    for _, b in pairs(tr.blood) do give('blood', L('type_blood_vehicle'), b.data) end
    for _, c in pairs(tr.casing) do give('casing', L('type_casing_vehicle', c.n), c.data) end
    for _, b in pairs(tr.bullet) do give('bullet', L('type_bullet_vehicle', b.n), b.data) end
    if tr.gsr then give('gsr', L('type_gsr_vehicle'), {}, { gsr = 'POSITIVE' }) end

    WhipEvidence.Data.saveBags(queries)
    return made, lost
end

function WhipEvidence.Vehicles.register()
    -- The client sat in the car long enough (without gloves)
    Whip.core:SecureEvent('whip_evidence:touchVehicle', {
        rateLimit = 10000, burst = 2, sheet = 'light',
        params = { { 'net', 'id', 1, 2147483647 } },
        near = { at = vehicleNear(6.0).at, range = 6.0, message = false },
    }, function(source, player, net)
        local ent = entityOf(net)
        if not ent or GetVehiclePedIsIn(GetPlayerPed(source), false) ~= ent then return false end
        WhipEvidence.Vehicles.addTrace(ent, 'print', nil, player.charId)
    end)

    -- Police collects every trace at a front door
    Whip.core:SecureEvent('whip_evidence:collectVehicle', {
        rateLimit = 5000,
        params = { { 'net', 'id', 1, 2147483647 }, { 'street', 'string', 80, 'Unknown' } },
        near = vehicleNear(5.0),
    }, function(source, player, net, street)
        local ent = entityOf(net)
        if not ent then return false, L('vehicle_not_found') end
        if not WhipEvidence.isPolice(source) then return false, L('police_only_collect') end
        if not WhipEvidence.can(source, 'evidence_vehicle') then return false, L('not_allowed') end
        if not exports.whip_core:HasItem(source, WhipEvidence.Items.kit) then return false, L('need_kit') end
        if not WhipEvidence.hasEmptyBags(source) then return false, L('no_empty_bags') end
        if not isEmpty(ent) then return false, L('vehicle_not_empty') end
        if #(GetEntityVelocity(ent)) > 0.5 then return false, L('vehicle_moving') end

        local done = examine(source, ent, L('examining'))
        TriggerClientEvent('whip_evidence:client:vehicleDone', source, net)
        if not done then return false end
        if not exports.whip_core:IsSessionCurrent(source, player.session) then return false end
        ent = entityOf(net)
        if not ent then return false, L('vehicle_not_found') end

        WhipEvidence.wear(source, WhipEvidence.Items.kit)
        local tr = traceOf(ent, false)
        if not tr or not summary(tr) then return false, L('no_traces') end
        traces[tr.key] = nil
        TriggerClientEvent('whip_evidence:client:vehicleTraces', -1, tr.net, nil)

        local made, lost = collect(source, player, tr, street)
        exports.whip_core:LogActivity(source, 'evidence_vehicle_traces', { detail = ('%s: %d'):format(tr.plate or '?', made) })
        if lost > 0 then
            exports.whip_core:NotifyPlayer(source, L('traces_lost', made, lost), 'warning')
        else
            exports.whip_core:NotifyPlayer(source, L('traces_collected', made), 'success')
        end
    end)

    -- Anyone with a cleaning cloth: clean the inside (prints, blood, GSR, casings). Bullet holes stay.
    Whip.core:SecureEvent('whip_evidence:wipeVehicle', {
        rateLimit = 5000,
        params = { { 'net', 'id', 1, 2147483647 } },
        near = vehicleNear(5.0),
    }, function(source, player, net)
        local ent = entityOf(net)
        if not ent then return false, L('vehicle_not_found') end
        if not exports.whip_core:HasItem(source, WhipEvidence.Items.wipe) then return false, L('need_cloth') end

        local done = exports.whip_core:Progress(source, {
            label = L('cleaning_interior'), duration = 8000, icon = 'car',
            anim = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 1 },
            disable = { move = true, combat = true, car = true },
            near = { coords = GetEntityCoords(ent), range = 6.0 },
        })
        TriggerClientEvent('whip_evidence:client:vehicleDone', source, net)
        if not done then return false end
        if not exports.whip_core:IsSessionCurrent(source, player.session) then return false end
        ent = entityOf(net)
        if not ent then return false end

        local tr = traceOf(ent, false)
        if not tr or (not next(tr.prints) and not next(tr.blood) and not next(tr.casing) and not tr.gsr) then
            return false, L('nothing_to_clean_car')
        end
        tr.prints, tr.blood, tr.casing, tr.gsr = {}, {}, {}, nil
        push(tr)
        if not summary(tr) then traces[tr.key] = nil end
        exports.whip_core:LogActivity(source, 'evidence_vehicle_cleaned')
        exports.whip_core:NotifyPlayer(source, L('interior_clean'), 'success')
    end)
end
