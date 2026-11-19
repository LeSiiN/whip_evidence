-- Gunshot residue on a person: a stat (0-100 %) that a shot fills and that fades over Config.GsrMinutes.
-- It shows as a ring on the player's own HUD (Config.GsrHud). Gone with water, swimming, rain or a cleaning item.
WhipEvidence.Gsr = {}

local STAT = 'evidence_gsr'
local ACT_CLEAN = 'whip_evidence:gsr_clean'
local washing = {}   -- [source] = { tag, aborted }

-- particles (Material Design "grain")
local ICON = 'M10,12A2,2 0 0,0 8,14A2,2 0 0,0 10,16A2,2 0 0,0 12,14A2,2 0 0,0 10,12M6,8A2,2 0 0,0 4,10A2,2 0 0,0 6,12A2,2 0 0,0 8,10A2,2 0 0,0 6,8'
    .. 'M6,16A2,2 0 0,0 4,18A2,2 0 0,0 6,20A2,2 0 0,0 8,18A2,2 0 0,0 6,16M18,8A2,2 0 0,0 20,6A2,2 0 0,0 18,4A2,2 0 0,0 16,6A2,2 0 0,0 18,8'
    .. 'M14,16A2,2 0 0,0 12,18A2,2 0 0,0 14,20A2,2 0 0,0 16,18A2,2 0 0,0 14,16M18,12A2,2 0 0,0 16,14A2,2 0 0,0 18,16A2,2 0 0,0 20,14A2,2 0 0,0 18,12'
    .. 'M14,8A2,2 0 0,0 12,10A2,2 0 0,0 14,12A2,2 0 0,0 16,10A2,2 0 0,0 14,8M10,4A2,2 0 0,0 8,6A2,2 0 0,0 10,8A2,2 0 0,0 12,6A2,2 0 0,0 10,4Z'

local function registerStat()
    local ok, why = Whip.core:RegisterStat(STAT, {
        type = 'custom', default = 0, min = 0, max = 100, persist = true,
        decay = -100 / math.max(1, (tonumber(Config.GsrMinutes) or 30) * 6), decayInterval = 10,   -- 100 % -> 0 in GsrMinutes
        hud = Config.GsrHud ~= false and {
            icon = ICON, color = '#f59e0b', order = 60, noCritical = true, showAboveZero = true, glide = true,
        } or nil,
    })
    if not ok then Whip.startProblem('GSR stat: %s', tostring(why)) end
end

Whip.onConfigChanged('GsrMinutes', function() if Whip.isReady() then registerStat() end end)
Whip.onConfigChanged('GsrHud', function() if Whip.isReady() then registerStat() end end)

function WhipEvidence.Gsr.level(source)
    local v = exports.whip_core:GetStat(source, STAT)   -- nil while not loaded
    return type(v) == 'number' and v or 0
end

function WhipEvidence.Gsr.has(source)
    return WhipEvidence.Gsr.level(source) > 0
end

function WhipEvidence.Gsr.mark(source)
    if WhipEvidence.Gsr.level(source) >= 97 then return end   -- full already (one write per decay tick at most)
    exports.whip_core:SetStat(source, STAT, 100, 'shot')
end

function WhipEvidence.Gsr.clear(source, reason)
    if not WhipEvidence.Gsr.has(source) then return false end
    exports.whip_core:SetStat(source, STAT, 0, reason or 'washed')
    return true
end

-- On load: GSR from before 4.0 was a player flag (its expiry time) -> into the stat
function WhipEvidence.Gsr.load(source)
    local v = Whip.core:GetPlayerFlag(source, WhipEvidence.GsrFlag)
    if v == nil or v == false then return end
    Whip.core:SetPlayerFlag(source, WhipEvidence.GsrFlag, false)
    if type(v) == 'number' and v > os.time() then
        local left = (v - os.time()) / math.max(60, Config.GsrMinutes * 60) * 100
        exports.whip_core:SetStat(source, STAT, math.min(100, left), 'from the old GSR flag')
    end
end

function WhipEvidence.Gsr.forget(source)
    washing[source] = nil
end

local function cleanerFor(item)
    for _, c in ipairs(Config.GsrCleaners or {}) do
        if c.item == item then return c end
    end
end

-- Right-click a cleaning item (Config.GsrCleaners): wipe hands and clothes
local function clean(source, player, slotData, addr)
    local held = exports.whip_core:GetItemAt(addr)
    local item = held and held.item
    local c = item and cleanerFor(item)
    if not c then return false end
    local gsr, blood = WhipEvidence.Gsr.has(source), c.blood == true and WhipEvidence.Body.bloody(source)
    if not gsr and not blood then
        return false, c.blood and L('nothing_to_clean') or L('no_gsr')
    end
    local done = exports.whip_core:Progress(source, WhipEvidence.bar('clean_self', {
        label = L('cleaning_self'), duration = math.max(1, tonumber(c.seconds) or 10) * 1000, icon = 'info',
        disable = { combat = true }, canCancel = true,
    }))
    if not done then return false end
    if not exports.whip_core:IsSessionCurrent(source, player.session) then return false end
    -- the item must still be there (it may have been dropped or given away meanwhile)
    local now = exports.whip_core:GetItemAt(addr)
    if not now or now.item ~= item then return false, L('item_gone') end
    if c.use == 'remove' then
        exports.whip_core:StoreTake(addr, 1, { reason = 'Cleaned off gunshot residue' })
    elseif c.use == 'wear' then
        WhipEvidence.wear(source, item)
    end
    WhipEvidence.Gsr.clear(source, 'item:' .. item)
    if c.blood then WhipEvidence.Body.clearBlood(source, 'item:' .. item) end
    exports.whip_core:LogActivity(source, 'evidence_gsr_washed', { detail = item })
    exports.whip_core:NotifyPlayer(source, blood and L('cleaned_self') or L('cleaned_gsr'), 'success')
end

function WhipEvidence.Gsr.register()
    registerStat()

    Whip.core:RegisterContextAction(ACT_CLEAN, clean)
    for _, c in ipairs(Config.GsrCleaners or {}) do
        if type(c.item) == 'string' and c.item ~= '' then
            Whip.core:AddItemOption(c.item, { action = ACT_CLEAN, label = c.blood and L('opt_clean_both')
                or L('opt_clean_gsr'), anywhere = false })
        end
    end

    -- Outside in the rain long enough, or swimming (the client counts, the server checks what it can)
    Whip.core:SecureEvent('whip_evidence:gsrWeather', {
        rateLimit = 5000, sheet = 'light',
        params = { { 'how', 'enum', { 'rain', 'swim' } } },
    }, function(source, player, how)
        if how == 'rain' then
            if not WhipEvidence.Gsr.has(source) or not WhipEvidence.Evidence.isRaining() then return end
            if GetVehiclePedIsIn(GetPlayerPed(source), false) ~= 0 then return false end
            WhipEvidence.Gsr.clear(source, 'rain')
            exports.whip_core:NotifyPlayer(source, L('rain_washed'), 'info')
            return
        end
        -- swimming: residue and blood
        local a = WhipEvidence.Gsr.clear(source, 'swimming')
        local b = WhipEvidence.Body.clearBlood(source, 'swimming')
        if a or b then exports.whip_core:NotifyPlayer(source, L('water_washed'), 'info') end
    end)

    -- Police tests a player (target comes from the aimBox prompt)
    Whip.core:SecureEvent('whip_evidence:gsrTest', {
        rateLimit = 3000,
        params = { { 'target', 'player', { range = 3.0 } }, { 'street', 'string', 80, 'Unknown' } },
    }, function(source, player, target, street)
        if not WhipEvidence.isPolice(source) then return false, L('police_only_test') end
        if not WhipEvidence.can(source, 'evidence_gsr') then return false, WhipEvidence.why(source, 'evidence_gsr') end
        if not exports.whip_core:HasItem(source, WhipEvidence.Items.kit) then return false, L('need_kit') end
        if not WhipEvidence.hasEmptyBags(source) then return false, L('no_empty_bags') end
        if exports.whip_core:IsPlayerDead(target.source) then return false, L('must_be_conscious') end

        local passed, res = WhipEvidence.minigame(source, 'gsr')
        if not passed then
            return false, res == 'busy' and L('busy') or nil
        end

        exports.whip_core:NotifyPlayer(target.source, L('being_tested'), 'info')
        TriggerClientEvent('whip_evidence:client:handsOut', target.source, 3000)
        local done = exports.whip_core:Progress(source, WhipEvidence.bar('swab_person', {
            label = L('testing_gsr'), duration = 3000, icon = 'target',
            disable = { move = true, combat = true, car = true },
            near = { coords = GetEntityCoords(GetPlayerPed(target.source)), range = 3.5 },
        }))
        if not done then return false end
        if not exports.whip_core:IsSessionCurrent(source, player.session) then return false end

        WhipEvidence.wear(source, WhipEvidence.Items.kit)
        local level = WhipEvidence.Gsr.level(target.source)
        local positive = level > 0
        local result = positive and 'positive' or 'negative'
        exports.whip_core:LogActivity(source, 'evidence_gsr_test', { detail = target.fullName .. ': ' .. result })
        exports.whip_core:LogActivity(target.source, 'evidence_gsr_tested', { detail = result })

        if not positive then
            exports.whip_core:NotifyPlayer(source, L('gsr_negative'), 'info')
            return
        end

        exports.whip_core:NotifyPlayer(source, level >= 50 and L('gsr_positive_strong')
            or L('gsr_positive_weak'), 'warning')
        local officer = WhipEvidence.officerLabel(source, player)
        if not WhipEvidence.useEmptyBag(source) then return false, L('gsr_no_bag') end
        WhipEvidence.giveBag(source, {
            evidence_id  = WhipEvidence.Data.newId(),
            kind         = 'gsr',
            type         = L('gsr_test'),
            time         = os.date('%Y-%m-%d %H:%M:%S'),
            street       = street,
            collected_by = officer,
            custody      = WhipEvidence.custody(nil, L('custody_collected'), officer),
            tested_on    = target.fullName,
            gsr          = level >= 50 and L('gsr_strong') or L('gsr_weak'),
        }, L('gsr_test'))
    end)

    -- Wash it off in water (the client only offers this in water)
    Whip.core:SecureEvent('whip_evidence:wash', {
        rateLimit = 3000,
    }, function(source, player)
        if not WhipEvidence.Gsr.has(source) and not WhipEvidence.Body.bloody(source) then
            return false, L('nothing_to_wash')
        end
        if washing[source] then return false end

        local tag = ('wash:%d:%d'):format(source, GetGameTimer())
        local w = { tag = tag, aborted = false }
        washing[source] = w
        local done = exports.whip_core:Progress(source, WhipEvidence.bar('clean_self', {
            label = L('washing'), duration = Config.WashSeconds * 1000, icon = 'info', canCancel = true,
            disable = { move = false, combat = true }, tag = tag,
        }))
        washing[source] = nil
        if not exports.whip_core:IsSessionCurrent(source, player.session) then return false end
        if not done then
            if w.aborted then return false, L('wash_aborted') end
            return false
        end
        WhipEvidence.Gsr.clear(source, 'washed in water')
        WhipEvidence.Body.clearBlood(source, 'washed in water')
        exports.whip_core:LogActivity(source, 'evidence_gsr_washed', { detail = 'water' })
        exports.whip_core:NotifyPlayer(source, L('washed_clean'), 'success')
    end)

    -- The client reports: out of the water, stop washing
    Whip.core:SecureEvent('whip_evidence:washAbort', {
        rateLimit = 500, burst = 3, sheet = 'light',
    }, function(source)
        local w = washing[source]
        if not w then return end
        w.aborted = true
        exports.whip_core:ReleaseTag(w.tag)
    end)
end
