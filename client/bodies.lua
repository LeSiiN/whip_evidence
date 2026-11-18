-- Client: bodies (server/bodies.lua keeps them).
--  * reports the hits this player deals (wound type, body part) and their own cause of death
--  * keeps a pedestrian's body from despawning once it is a body
--  * prompts on a body for police on duty: examine, bullet, blood sample, GSR, release
--  * WhipEvidence.Bodies.* for the scan overlay (cards "L1", legend rows)
WhipEvidence.Bodies = {}

local Bodies, byNet = {}, {}   -- [id] = view from the server (+ at: when it arrived), [net] = id
local reported = {}            -- [net] = true: a pedestrian this player killed (kept once it is a body)
local GROUP = 'whip_evidence_bodies'
local PROMPT_RANGE = 25.0

---------------------------------------------------------------- Wounds and body parts

local function h(name) return GetHashKey(name) & 0xFFFFFFFF end

local SPECIAL = {
    [h('WEAPON_RUN_OVER_BY_CAR')] = 'vehicle', [h('WEAPON_RAMMED_BY_CAR')] = 'vehicle',
    [h('WEAPON_FALL')] = 'fall',
    [h('WEAPON_FIRE')] = 'burn', [h('WEAPON_MOLOTOV')] = 'burn', [h('WEAPON_PETROLCAN')] = 'burn', [h('WEAPON_FLARE')] = 'burn',
    [h('WEAPON_EXPLOSION')] = 'explosion',
}
for _, w in ipairs({ 'WEAPON_KNIFE', 'WEAPON_DAGGER', 'WEAPON_MACHETE', 'WEAPON_SWITCHBLADE', 'WEAPON_BATTLEAXE',
                     'WEAPON_HATCHET', 'WEAPON_STONE_HATCHET', 'WEAPON_BOTTLE' }) do
    SPECIAL[h(w)] = 'stab'
end

local GROUPS = {
    [0x18D5FA97] = 'gunshot', [0xC6E9A5C5] = 'gunshot', [0x39D5C192] = 'gunshot', [0x451B04BC] = 'gunshot',
    [0x33431399] = 'gunshot', [0xB7BBD827] = 'gunshot',               -- pistol, smg, rifle, mg, shotgun, sniper
    [0xA27A4F9F] = 'explosion', [0x5C4C5883] = 'explosion',           -- heavy, thrown
    [0xD49321D4] = 'blunt', [0xA00FC1E4] = 'blunt',                   -- melee, unarmed
}

local function woundOf(weapon)
    weapon = (tonumber(weapon) or 0) & 0xFFFFFFFF
    if weapon == 0 then return 'other' end
    if SPECIAL[weapon] then return SPECIAL[weapon] end
    return GROUPS[GetWeapontypeGroup(weapon) & 0xFFFFFFFF] or 'other'
end

local PART = {}
for _, b in ipairs({ 31086, 39317, 12844, 65068 }) do PART[b] = 'head' end
for _, b in ipairs({ 45509, 61163, 18905, 40269, 28252, 57005, 64729, 10706 }) do PART[b] = 'arms' end
for _, b in ipairs({ 58271, 63931, 14201, 2108, 51826, 36864, 52301, 20781, 65245, 35502 }) do PART[b] = 'legs' end

local function partOf(ped)
    local ok, bone = GetPedLastDamageBone(ped)
    return ok and PART[bone] or 'torso'
end

local function xyz(v) return { x = v.x, y = v.y, z = v.z } end

---------------------------------------------------------------- Hits this player deals

local lastHit, lastClean = {}, 0
local localHits = {}   -- [entity] = hits on a pedestrian only this game knows (not networked yet)

local function sendHit(net, h, fatal)
    TriggerServerEvent('whip_evidence:bodyHit', net, h.wound, h.part, fatal == true, h.armed == true, h.ground, h.male == true)
end

-- A pedestrian that only exists in this game (no server copy): make it networked once it dies,
-- then send the hits it took. Afterwards it is a body like any other.
local function networkAndSend(victim, hits, last)
    CreateThread(function()
        SetEntityAsMissionEntity(victim, true, true)
        NetworkRegisterEntityAsNetworked(victim)
        local untilAt = GetGameTimer() + 2000
        while DoesEntityExist(victim) and not NetworkGetEntityIsNetworked(victim) and GetGameTimer() < untilAt do Wait(50) end
        if not DoesEntityExist(victim) or not NetworkGetEntityIsNetworked(victim) then return end
        local net = NetworkGetNetworkIdFromEntity(victim)
        SetNetworkIdCanMigrate(net, true)
        Wait(250)   -- the server has to know it first
        reported[net] = true
        for i = math.max(1, #hits - 6), #hits do sendHit(net, hits[i], false) end
        sendHit(net, last, true)
    end)
end

AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' or Config.Bodies == false then return end
    local victim, attacker = args[1], args[2]
    local me = PlayerPedId()
    if victim == me or not victim or not DoesEntityExist(victim) or not IsEntityAPed(victim) then return end
    if attacker ~= me then
        local car = GetVehiclePedIsIn(me, false)
        if car == 0 or attacker ~= car then return end   -- run over: the car is the attacker
    end
    if WhipEvidence.blocked() then return end
    local fatal = args[6] == 1 or IsPedDeadOrDying(victim, true)
    local now = GetGameTimer()
    if now - lastClean > 60000 then lastHit, localHits, lastClean = {}, {}, now end
    if not fatal and lastHit[victim] and now - lastHit[victim] < 150 then return end   -- shotgun pellets: one hit
    lastHit[victim] = now
    local hit = { wound = woundOf(args[7]), part = partOf(victim), armed = IsPedArmed(victim, 4 | 2) == true,
                  male = IsPedMale(victim) == true, ground = xyz(WhipEvidence.ground(GetEntityCoords(victim))) }

    if not NetworkGetEntityIsNetworked(victim) then
        if IsPedAPlayer(victim) then return end
        local list = localHits[victim] or {}
        localHits[victim] = list
        if not fatal then
            list[#list + 1] = hit
            return
        end
        localHits[victim] = nil
        networkAndSend(victim, list, hit)
        return
    end

    local net = NetworkGetNetworkIdFromEntity(victim)
    if byNet[net] then return end   -- already a body: shooting a corpse adds nothing
    if fatal and not IsPedAPlayer(victim) then reported[net] = true end
    sendHit(net, hit, fatal)
end)

-- Own death: the cause as this game saw it (the server uses it only when nobody reported a hit)
AddEventHandler('whip_core:player:died', function(e)
    if Config.Bodies == false or (type(e) == 'table' and (e.reconnected or e.respawnRefused)) then return end
    local ped = PlayerPedId()
    TriggerServerEvent('whip_evidence:myDeath', woundOf(GetPedCauseOfDeath(ped)), partOf(ped))
end)

-- A pedestrian this player killed is a body now: keep it from despawning (needs control of it)
local function keep(net)
    CreateThread(function()
        local untilAt = GetGameTimer() + 3000
        while GetGameTimer() < untilAt do
            if NetworkDoesNetworkIdExist(net) then
                local ped = NetworkGetEntityFromNetworkId(net)
                if ped ~= 0 and DoesEntityExist(ped) then
                    if NetworkHasControlOfEntity(ped) then
                        SetEntityAsMissionEntity(ped, true, true)
                        return
                    end
                    NetworkRequestControlOfEntity(ped)
                end
            end
            Wait(100)
        end
    end)
end

---------------------------------------------------------------- Bodies from the server

local dirty = true

local function put(v)
    local old = Bodies[v.id]
    v.at = GetGameTimer()
    Bodies[v.id] = v
    byNet[v.net] = v.id
    if not old and reported[v.net] then
        reported[v.net] = nil
        keep(v.net)
    end
    dirty = true
end

RegisterNetEvent('whip_evidence:client:body', function(v)
    if type(v) == 'table' and v.id then put(v) end
end)

local hide
RegisterNetEvent('whip_evidence:client:bodyGone', function(id)
    local b = Bodies[id]
    if not b then return end
    Bodies[id] = nil
    if byNet[b.net] == id then byNet[b.net] = nil end
    hide(id)
end)

local function sync()
    local list = Whip.core:Callback('whip_evidence:bodies')
    Bodies, byNet = {}, {}
    for _, v in ipairs(type(list) == 'table' and list or {}) do put(v) end
end

AddEventHandler('whip_core:player:loaded', function() CreateThread(sync) end)
Whip.register(function()
    CreateThread(function()
        if exports.whip_core:IsPlayerLoaded() then sync() end
    end)
end)

-- Dev tools: the test pedestrian stands still and doesn't run off
RegisterNetEvent('whip_evidence:client:testPed', function(net)
    CreateThread(function()
        local untilAt = GetGameTimer() + 5000
        while GetGameTimer() < untilAt do
            if NetworkDoesNetworkIdExist(net) then
                local ped = NetworkGetEntityFromNetworkId(net)
                if ped ~= 0 and DoesEntityExist(ped) then
                    NetworkRequestControlOfEntity(ped)
                    if NetworkHasControlOfEntity(ped) then
                        SetBlockingOfNonTemporaryEvents(ped, true)
                        SetPedFleeAttributes(ped, 0, false)
                        SetPedKeepTask(ped, true)
                        TaskStandStill(ped, -1)
                        return
                    end
                end
            end
            Wait(100)
        end
    end)
end)

---------------------------------------------------------------- Texts for the scan overlay

local function minutesText(seconds)
    local m = math.floor(math.max(0, seconds) / 60)
    if m < 5 then return L('age_under5') end
    if m < 10 then return L('age_5_10') end
    if m < 60 then
        local lo = math.floor(m / 10) * 10
        return L('age_min', lo, lo + 10)
    end
    local hr = math.floor(m / 60)
    return L('age_hours', hr, hr + 1)
end

local function age(b) return b.age + (GetGameTimer() - b.at) / 1000 end

function WhipEvidence.Bodies.all() return Bodies end

function WhipEvidence.Bodies.label(b) return L('body_label', b.no) end

-- chips on the card
function WhipEvidence.Bodies.chips(b)
    if not b.examined then return { { text = L('body_not_examined'), color = 'yellow' } } end
    local chips = { { text = L('body_died', minutesText(age(b))) } }
    local f = b.details and b.details.fatal
    if f then chips[#chips + 1] = { text = L('body_fatal_short', L('wound_' .. f.w), L('part_' .. f.p)), color = 'red' } end
    for _, w in ipairs(b.wounds or {}) do
        chips[#chips + 1] = { text = L('wound_' .. w.w) .. (w.n > 1 and (' ×' .. w.n) or ''), color = w.w == 'gunshot' and 'red' or nil }
    end
    if (b.bullets or 0) > 0 then chips[#chips + 1] = { text = L('body_bullets_in', b.bullets), color = 'red' } end
    local parts = {}
    for _, p in ipairs(b.parts or {}) do parts[#parts + 1] = L('part_' .. p) end
    if #parts > 0 then chips[#chips + 1] = { text = table.concat(parts, ', ') } end
    if b.blood then chips[#chips + 1] = { text = L('chip_blood_taken'), color = 'green' } end
    if b.gsr then chips[#chips + 1] = { text = L('chip_gsr_taken'), color = 'green' } end
    if b.photo then chips[#chips + 1] = { text = L('chip_photo'), color = 'green' } end
    if b.held then chips[#chips + 1] = { text = L('chip_held'), color = 'blue' } end
    return chips
end

-- one line in the legend
function WhipEvidence.Bodies.info(b)
    if not b.examined then return L('body_not_examined') end
    local w = {}
    for _, x in ipairs(b.wounds or {}) do w[#w + 1] = L('wound_' .. x.w) .. (x.n > 1 and (' ×' .. x.n) or '') end
    return table.concat(w, ', ') .. ' · ' .. minutesText(age(b))
end

-- The prompt sits just above the chest of the body, wherever it lies (a ragdoll's origin is not where it looks)
local CHEST = 24818   -- SKEL_Spine3
local function chestOf(b)
    if NetworkDoesNetworkIdExist(b.net) then
        local ped = NetworkGetEntityFromNetworkId(b.net)
        if ped ~= 0 and DoesEntityExist(ped) then
            local p = GetPedBoneCoords(ped, CHEST, 0.0, 0.0, 0.0)
            return vector3(p.x, p.y, p.z + 0.35)
        end
    end
    local c = b.coords
    return vector3(c.x + 0.0, c.y + 0.0, c.z + 0.35)
end

WhipEvidence.Bodies.chest = chestOf   -- the scan marker sits here too

-- where the body is now (it can be carried), and its entity if streamed in
function WhipEvidence.Bodies.where(b)
    if NetworkDoesNetworkIdExist(b.net) then
        local ent = NetworkGetEntityFromNetworkId(b.net)
        if ent ~= 0 and DoesEntityExist(ent) then return GetEntityCoords(ent), ent end
    end
    local c = b.coords
    return vector3(c.x + 0.0, c.y + 0.0, c.z + 0.0), nil
end

---------------------------------------------------------------- Findings sheet (html/index.html)

local function woundList(list)
    local w = {}
    for _, x in ipairs(list or {}) do w[#w + 1] = L('wound_' .. x.w) .. (x.n > 1 and (' ×' .. x.n) or '') end
    return table.concat(w, ', ')
end

-- rows { k, v, c? } and the same as text for the clipboard
local function reportOf(b)
    local d = b.details or {}
    local rows = {}
    local function row(k, v, c) rows[#rows + 1] = { k = k, v = v, c = c } end
    if d.fatal then row(L('rep_fatal'), L('rep_fatal_v', L('wound_' .. d.fatal.w), L('part_' .. d.fatal.p)), 'red') end
    row(L('rep_wounds'), ('%s  (%s)'):format(woundList(b.wounds), L('rep_hits', d.hits or 0)))
    for _, p in ipairs(d.byPart or {}) do row('   ' .. L('part_' .. p.p), woundList(p.w)) end
    if d.ranges and #d.ranges > 0 then
        local r = {}
        for _, x in ipairs(d.ranges) do r[#r + 1] = L('range_' .. x) end
        row(L('rep_range'), table.concat(r, ', '))
    end
    if (d.through or 0) > 0 or (b.bullets or 0) > 0 then
        row(L('rep_bullets'), L('rep_bullets_v', b.bullets or 0, d.through or 0), (b.bullets or 0) > 0 and 'red' or nil)
    end
    if d.defense then row(L('rep_defense'), L('rep_defense_v'), 'yellow') end
    if d.armed then row(L('rep_armed'), L('rep_armed_v'), 'yellow') end
    if d.moved then row(L('rep_moved'), L('rep_moved_v', d.moved), 'yellow') end
    local secured = {}
    if b.photo then secured[#secured + 1] = L('chip_photo') end
    if b.blood then secured[#secured + 1] = L('chip_blood_taken') end
    if b.gsr then secured[#secured + 1] = L('chip_gsr_taken') end
    row(L('rep_secured'), #secured > 0 and table.concat(secured, ', ') or L('rep_nothing_yet'))
    local sub = L('body_died', minutesText(age(b)))
    if d.sex then sub = sub .. ' · ' .. L('sex_' .. d.sex) end
    sub = sub .. ' · ' .. L(b.kind == 'player' and 'rep_kind_player' or 'rep_kind_ped')
    local title = L('rep_title', b.no)
    local lines = { title, sub }
    for _, r in ipairs(rows) do lines[#lines + 1] = (r.k:gsub('^%s+', '- ')) .. ': ' .. r.v end
    return title, sub, rows, table.concat(lines, '\n')
end

local reportId = nil
local reportPad = Whip.padScreen({
    buttons = { 'a', 'b' },
    onButton = function(cmd, down)
        if down then SendNUIMessage({ action = 'bodyReportPad', cmd = cmd }) end
    end,
})

local function closeReport(tellPage)
    if not reportId then return end
    reportId = nil
    reportPad:close()
    Whip.core:SetScreenOpen(false, 'bodyReport')
    if tellPage then SendNUIMessage({ action = 'bodyReport', open = false }) end
end

function WhipEvidence.Bodies.openReport(id)
    local b = Bodies[id]
    if not b or not b.examined then return end
    if reportId then closeReport(true) end
    reportId = id
    local title, sub, rows, text = reportOf(b)
    Whip.core:SetScreenOpen(true, 'bodyReport')
    local pad = reportPad:open()
    SendNUIMessage({ action = 'bodyReport', open = true, pad = pad == true, kicker = L('rep_kicker'),
        title = title, sub = sub, rows = rows, text = text,
        copy = L('rep_copy'), close = pad and L('rep_close_pad') or L('rep_close'), copied = L('rep_copied') })
end

RegisterNUICallback('bodyReportClose', function(_, cb)
    closeReport(false)
    cb('ok')
end)

-- right after "Examine the body" (the server sent the new findings first)
RegisterNetEvent('whip_evidence:client:bodyReport', function(id)
    CreateThread(function()
        local untilAt = GetGameTimer() + 2000
        while GetGameTimer() < untilAt and not (Bodies[id] and Bodies[id].examined) do Wait(50) end
        WhipEvidence.Bodies.openReport(id)
    end)
end)

---------------------------------------------------------------- Prompts (police on duty, close by)

local shown = {}   -- [id] = state key the prompt was built with

local function here() return WhipEvidence.street(GetEntityCoords(PlayerPedId())) end


local function actionFor(b)
    local id = b.id
    local function send(event) return function() TriggerServerEvent(event, id, here()) end end
    local options = {}
    if not b.examined then
        options[#options + 1] = { id = 'examine', label = L('body_examine'), icon = 'target', onSelect = send('whip_evidence:bodyExamine') }
    else
        options[#options + 1] = { id = 'report', label = L('body_report'), icon = 'info',
            onSelect = function() WhipEvidence.Bodies.openReport(id) end }
        if (b.bullets or 0) > 0 then
            options[#options + 1] = { id = 'bullet', label = L('body_take_bullet', b.bullets), icon = 'pickup', onSelect = send('whip_evidence:bodyBullet') }
        end
    end
    if not b.blood then
        options[#options + 1] = { id = 'blood', label = L('body_take_blood'), icon = 'pickup', onSelect = send('whip_evidence:bodyBlood') }
    end
    if not b.gsr then
        options[#options + 1] = { id = 'gsr', label = L('body_test_gsr'), icon = 'target', onSelect = send('whip_evidence:bodyGsr') }
    end
    options[#options + 1] = { id = 'release', label = L('body_release'), icon = 'check', holdMs = 1500,
        onSelect = send('whip_evidence:bodyRelease') }
    return {
        id = 'body:' .. id, group = GROUP,
        at = { coords = chestOf(b), follow = function()
            local p = chestOf(Bodies[id] or b)
            return p.x, p.y, p.z
        end },
        label = L('body_label', b.no), icon = 'target', reach = 2.0, seeFrom = 8.0,
        require = { job = Config.PoliceJobs, onDuty = true, item = WhipEvidence.Items.kit },
        style = { tint = '#a78bfa', labelTint = '#a78bfa' },
        options = options,
    }
end

local function stateOf(b)
    return ('%s|%s|%s|%s|%s'):format(b.examined, b.blood, b.gsr, b.held, b.bullets or 0)
end

hide = function(id)
    if shown[id] then
        shown[id] = nil
        Whip.core:RemoveAction('body:' .. id)
    end
end

local function hideAll()
    if next(shown) then
        shown = {}
        Whip.core:RemoveActionGroup(GROUP)
    end
end

CreateThread(function()
    local allowedBefore = false
    while true do
        local wait = 1500
        local allowed = next(Bodies) ~= nil and WhipEvidence.isPoliceOnDuty() and WhipEvidence.can('evidence_body')
        if allowed ~= allowedBefore then
            hideAll()
            allowedBefore, dirty = allowed, true
        end
        if allowed then
            wait = 500
            local pos = GetEntityCoords(PlayerPedId())
            for id, b in pairs(Bodies) do
                local bpos = WhipEvidence.Bodies.where(b)
                local near = #(bpos - pos) <= PROMPT_RANGE
                if near then
                    local state = stateOf(b)
                    if shown[id] ~= state then
                        local ok = Whip.core:AddAction(actionFor(b))
                        shown[id] = ok and state or nil
                    end
                elseif shown[id] then
                    hide(id)
                end
            end
            dirty = false
        end
        Wait(wait)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == WhipEvidence.Res then closeReport(true) end
end)

AddEventHandler('whip_core:player:logout', function()
    closeReport(true)
    hideAll()
    Bodies, byNet, reported = {}, {}, {}
end)
