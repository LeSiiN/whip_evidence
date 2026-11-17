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
        return false, c.blood and 'There is nothing on you to clean off.' or 'You have no gunshot residue.'
    end
    local done = exports.whip_core:Progress(source, {
        label = 'Cleaning yourself...', duration = math.max(1, tonumber(c.seconds) or 10) * 1000, icon = 'info',
        anim = { dict = 'missheist_agency3aig_23', clip = 'urinal_sink_loop', flag = 49 },
        disable = { combat = true }, canCancel = true,
    })
    if not done then return false end
    if not exports.whip_core:IsSessionCurrent(source, player.session) then return false end
    -- the item must still be there (it may have been dropped or given away meanwhile)
    local now = exports.whip_core:GetItemAt(addr)
    if not now or now.item ~= item then return false, 'The item is gone.' end
    if c.use == 'remove' then
        exports.whip_core:StoreTake(addr, 1, { reason = 'Cleaned off gunshot residue' })
    elseif c.use == 'wear' then
        WhipEvidence.wear(source, item)
    end
    WhipEvidence.Gsr.clear(source, 'item:' .. item)
    if c.blood then WhipEvidence.Body.clearBlood(source, 'item:' .. item) end
    exports.whip_core:LogActivity(source, 'evidence_gsr_washed', { detail = item })
    exports.whip_core:NotifyPlayer(source, blood and 'You cleaned yourself up.' or 'You cleaned off the gunshot residue.', 'success')
end

function WhipEvidence.Gsr.register()
    registerStat()

    Whip.core:RegisterContextAction(ACT_CLEAN, clean)
    for _, c in ipairs(Config.GsrCleaners or {}) do
        if type(c.item) == 'string' and c.item ~= '' then
            Whip.core:AddItemOption(c.item, { action = ACT_CLEAN, label = c.blood and 'Clean off residue and blood'
                or 'Clean off gunshot residue', anywhere = false })
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
            exports.whip_core:NotifyPlayer(source, 'The rain washed off the gunshot residue.', 'info')
            return
        end
        -- swimming: residue and blood
        local a = WhipEvidence.Gsr.clear(source, 'swimming')
        local b = WhipEvidence.Body.clearBlood(source, 'swimming')
        if a or b then exports.whip_core:NotifyPlayer(source, 'The water washed you clean.', 'info') end
    end)

    -- Police tests a player (target comes from the aimBox prompt)
    Whip.core:SecureEvent('whip_evidence:gsrTest', {
        rateLimit = 3000,
        params = { { 'target', 'player', { range = 3.0 } }, { 'street', 'string', 80, 'Unknown' } },
    }, function(source, player, target, street)
        if not WhipEvidence.isPolice(source) then return false, 'Only on-duty police can run this test.' end
        if not WhipEvidence.can(source, 'evidence_gsr') then return false, WhipEvidence.NOT_ALLOWED end
        if not exports.whip_core:HasItem(source, WhipEvidence.Items.kit) then return false, 'You need a forensics kit.' end
        if not WhipEvidence.hasEmptyBags(source) then return false, 'You have no empty evidence bags.' end
        if exports.whip_core:IsPlayerDead(target.source) then return false, 'The person must be conscious.' end

        local passed, res = WhipEvidence.minigame(source, 'gsr')
        if not passed then
            return false, res == 'busy' and 'Finish what you are doing first.' or nil
        end

        exports.whip_core:NotifyPlayer(target.source, 'You are being tested for gunshot residue.', 'info')
        local done = exports.whip_core:Progress(source, {
            label = 'Testing for gunshot residue...', duration = 3000, icon = 'target',
            anim = { dict = 'creatures@rottweiler@tricks@', clip = 'petting_franklin', flag = 0 },
            disable = { move = true, combat = true, car = true },
            near = { coords = GetEntityCoords(GetPlayerPed(target.source)), range = 3.5 },
        })
        if not done then return false end
        if not exports.whip_core:IsSessionCurrent(source, player.session) then return false end

        WhipEvidence.wear(source, WhipEvidence.Items.kit)
        local level = WhipEvidence.Gsr.level(target.source)
        local positive = level > 0
        local result = positive and 'positive' or 'negative'
        exports.whip_core:LogActivity(source, 'evidence_gsr_test', { detail = target.fullName .. ': ' .. result })
        exports.whip_core:LogActivity(target.source, 'evidence_gsr_tested', { detail = result })

        if not positive then
            exports.whip_core:NotifyPlayer(source, 'Result: NEGATIVE. No gunshot residue.', 'info')
            return
        end

        exports.whip_core:NotifyPlayer(source, level >= 50 and 'Result: POSITIVE. A lot of gunshot residue.'
            or 'Result: POSITIVE. Weak traces of gunshot residue.', 'warning')
        local officer = WhipEvidence.officerLabel(source, player)
        if not WhipEvidence.useEmptyBag(source) then return false, 'Positive, but you have no empty bag for the swab.' end
        WhipEvidence.giveBag(source, {
            evidence_id  = WhipEvidence.Data.newId(),
            kind         = 'gsr',
            type         = 'GSR test',
            time         = os.date('%Y-%m-%d %H:%M:%S'),
            street       = street,
            collected_by = officer,
            custody      = WhipEvidence.custody(nil, 'Collected', officer),
            tested_on    = target.fullName,
            gsr          = level >= 50 and 'POSITIVE (strong)' or 'POSITIVE (weak traces)',
        }, 'GSR test')
    end)

    -- Wash it off in water (the client only offers this in water)
    Whip.core:SecureEvent('whip_evidence:wash', {
        rateLimit = 3000,
    }, function(source, player)
        if not WhipEvidence.Gsr.has(source) and not WhipEvidence.Body.bloody(source) then
            return false, 'There is nothing on you to wash off.'
        end
        if washing[source] then return false end

        local tag = ('wash:%d:%d'):format(source, GetGameTimer())
        local w = { tag = tag, aborted = false }
        washing[source] = w
        local done = exports.whip_core:Progress(source, {
            label = 'Washing...', duration = Config.WashSeconds * 1000, icon = 'info', canCancel = true,
            disable = { move = false, combat = true }, tag = tag,
        })
        washing[source] = nil
        if not exports.whip_core:IsSessionCurrent(source, player.session) then return false end
        if not done then
            if w.aborted then return false, 'You left the water too early. Some residue is still there.' end
            return false
        end
        WhipEvidence.Gsr.clear(source, 'washed in water')
        WhipEvidence.Body.clearBlood(source, 'washed in water')
        exports.whip_core:LogActivity(source, 'evidence_gsr_washed', { detail = 'water' })
        exports.whip_core:NotifyPlayer(source, 'You washed yourself clean.', 'success')
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
