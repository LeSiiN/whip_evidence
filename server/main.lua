-- Start, player events, blood, tick, admin

local bleedCooldown = {}   -- [source] = GetGameTimer() when they may bleed again
local trail = {}           -- [source] = { untilAt, total, critical } while they bleed

-- Blood trail: a hit makes you bleed for a while (heavier hits longer), the client drops blood while you walk
-- and the drops get further apart towards the end. Critically hurt: it goes on until healed.
local function sendTrail(source)
    local t = trail[source]
    if not t then
        TriggerClientEvent('whip_evidence:client:trail', source, false)
        return
    end
    TriggerClientEvent('whip_evidence:client:trail', source,
        { left = math.max(0, t.untilAt - GetGameTimer()), total = t.total, critical = t.critical })
end

local function critical(health)
    local c = tonumber(Config.BloodCriticalHealth) or 0
    return c > 100 and health ~= nil and health > 100 and health <= c
end

-- A hit that made them bleed
local function startTrail(source, loss, health)
    if not Config.BloodTrail or not health or health <= 100 then return end
    local base = tonumber(Config.BloodTrailSeconds) or 30
    local secs = math.max(8, math.min(base * 2, base * loss / 30))   -- a normal hit (30 health) = base
    local now = GetGameTimer()
    local untilAt = now + secs * 1000
    local t = trail[source]
    if t and t.untilAt > untilAt then untilAt = t.untilAt end
    trail[source] = { untilAt = untilAt, total = untilAt - now, critical = critical(health) }
    sendTrail(source)
end

-- Health changed: dead or healed stops the bleeding; critical keeps it going
local function updateTrail(source, health, old)
    local t, now = trail[source], GetGameTimer()
    if t and not t.critical and t.untilAt <= now then trail[source], t = nil, nil end   -- ran out on its own
    if not t then
        if Config.BloodTrail and critical(health) then   -- e.g. after a restart
            trail[source] = { untilAt = now, total = 1, critical = true }
            sendTrail(source)
        end
        return
    end
    if not Config.BloodTrail or health == nil or health <= 100 or (old and health > old) then
        trail[source] = nil
        sendTrail(source)
        return
    end
    local c = critical(health)
    if c ~= t.critical then
        t.critical = c
        if not c then   -- no longer critical: runs out normally from now
            t.untilAt = math.max(t.untilAt, now + 10000)
            t.total = t.untilAt - now
        end
        sendTrail(source)
    end
end

local function onHealth(e)
    if e.value then updateTrail(e.source, e.value, e.old) end
    if not Config.Bleeding or not e.old or not e.value then return end
    if e.old - e.value < Config.BleedMinDamage then return end
    -- every hit, fall or crash comes in as 'combat (reported): ...' (the client reports its ped)
    local reason = tostring(e.reason or '')
    if not reason:find('^combat') and not reason:find('^killed') then return end
    local now = GetGameTimer()
    if (bleedCooldown[e.source] or 0) > now then return end
    bleedCooldown[e.source] = now + 3000
    TriggerClientEvent('whip_evidence:client:bleed', e.source, false)
    startTrail(e.source, e.old - e.value, e.value)
    WhipEvidence.Body.onHurt(e.source, e.old - e.value)
end

Whip.register(function()
    WhipEvidence.Data.setup()
    WhipEvidence.Evidence.restore()
    WhipEvidence.Jobs.ensure()
    WhipEvidence.ItemDefs.register()
    WhipEvidence.Briefcase.register()
    WhipEvidence.Evidence.register()
    WhipEvidence.Gsr.register()
    WhipEvidence.Body.register()
    WhipEvidence.Bodies.register()
    WhipEvidence.Vehicles.register()
    WhipEvidence.Tracks.register()
    WhipEvidence.Weapons.register()
    WhipEvidence.Lab.register()
    WhipEvidence.Photo.register()
    WhipEvidence.Cases.register()
    WhipEvidence.Admin.register()

    -- now = true: also once for everyone already online (a restart keeps their trail)
    Whip.core:OnStatChanged('health', onHealth, nil, { table = true, now = true })

    -- Admin tools from /w (developer mode only)
    Whip.core:SecureEvent('whip_evidence:admin', {
        ace = 'whip.devtools', rateLimit = 1000,
        params = { { 'action', 'enum', { 'clear', 'wipe' } }, { 'radius', 'number', 1, 500, 10 } },
    }, function(source, player, action, radius)
        local n
        if action == 'clear' then
            n = WhipEvidence.Evidence.clearAll()
        else
            n = WhipEvidence.Evidence.clearNear(GetEntityCoords(GetPlayerPed(source)), radius)
        end
        exports.whip_core:LogActivity(source, 'evidence_admin_clear', { detail = ('%s: %d'):format(action, n) })
        exports.whip_core:NotifyPlayer(source, ('%d piece(s) of evidence removed.'):format(n), 'success')
    end)

    -- After a resource restart: players who are already online
    local players = Whip.core:GetPlayers({ light = true })
    if type(players) == 'table' then
        for src in pairs(players) do WhipEvidence.Gsr.load(src) end
    end
end)

AddEventHandler('whip_core:player:loaded', function(e)
    if GetInvokingResource() ~= 'whip_core' or type(e) ~= 'table' then return end
    WhipEvidence.Gsr.load(e.source)
    trail[e.source] = nil
    updateTrail(e.source, exports.whip_core:GetStat(e.source, 'health'))
    WhipEvidence.Data.traits(e.charId)   -- creates fingerprint/blood type for new characters
end)

AddEventHandler('whip_core:player:logout', function(e)
    if GetInvokingResource() ~= 'whip_core' or type(e) ~= 'table' then return end
    WhipEvidence.Gsr.forget(e.source)
    WhipEvidence.Body.forget(e.source)
    WhipEvidence.Data.forget(e.charId)
    bleedCooldown[e.source] = nil
    trail[e.source] = nil
end)

-- Blood where someone dies
AddEventHandler('whip_core:player:died', function(e)
    if GetInvokingResource() ~= 'whip_core' or type(e) ~= 'table' then return end
    updateTrail(e.source, 0)
    if Config.BloodOnDeath then TriggerClientEvent('whip_evidence:client:bleed', e.source, true) end
end)

AddEventHandler('playerDropped', function()
    WhipEvidence.Body.forget(source)
    trail[source] = nil
    bleedCooldown[source] = nil
end)

-- Tick: aging, rain, vehicle traces. Does nothing while there is nothing to do.
CreateThread(function()
    while true do
        Wait(10000)
        if Whip.isReady() then
            local raining = WhipEvidence.Evidence.isRaining()
            WhipEvidence.Evidence.tick(raining)
            WhipEvidence.Vehicles.tick()
        end
    end
end)

-- Console or developer mode: remove all evidence
Whip.command('clearevidence', { dev = true }, function(source)
    local n = WhipEvidence.Evidence.clearAll()
    if source > 0 then Whip.core:NotifyPlayer(source, ('%d piece(s) of evidence removed.'):format(n), 'success')
    else print(('[%s] %d piece(s) of evidence removed.'):format(WhipEvidence.Res, n)) end
end)

Whip.sayStarted()
