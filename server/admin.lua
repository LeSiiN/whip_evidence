-- Dev tools for /w -> Forensics (whip.devtools + developer mode). Test helpers and case administration.
WhipEvidence.Admin = {}

local KINDS = { 'casing', 'bullet', 'blood', 'fingerprint', 'vehicle_fragment' }

-- One piece of each type around the admin, with the admin's own fingerprint / blood
local function spawnAll(source, player)
    local ped = GetPlayerPed(source)
    local pos, heading = GetEntityCoords(ped), GetEntityHeading(ped)
    local traits = WhipEvidence.Data.traits(player.charId) or {}
    local data = {
        casing = { serial = 'TEST-' .. player.charId, caliber = '9mm' },
        bullet = { serial = 'TEST-' .. player.charId, caliber = '9mm' },
        blood = { blood = traits.blood or 'O+' },
        fingerprint = { fingerprint = traits.fingerprint or 'TEST' },
        vehicle_fragment = { colour = 'Test Red' },
    }
    local shot, made = WhipEvidence.Data.newId(), 0
    for i, kind in ipairs(KINDS) do
        local a = math.rad(heading + 90 + (i - 1) * 45)
        local at = pos + vector3(math.cos(a) * 2.2, math.sin(a) * 2.2, -0.95)
        local opts = { coords = at, data = data[kind] }
        if kind == 'casing' or kind == 'bullet' then opts.shot = shot end
        if kind == 'bullet' then opts.origin = pos end
        if WhipEvidence.Evidence.create(kind, opts) then made = made + 1 end
    end
    return made
end

-- Bags in the admin's pockets: lab values revealed at once
local function revealMine(source)
    local found = exports.whip_core:FindAllItems(source, WhipEvidence.Items.bag) or {}
    local byId, ids = {}, {}
    for _, f in ipairs(found) do
        local id = f.metadata and f.metadata.evidence_id
        if id then byId[id] = f; ids[#ids + 1] = id end
    end
    local done = {}
    for id, secret in pairs(WhipEvidence.Data.pendingSecrets(ids)) do
        if exports.whip_core:SetItemMetadata(byId[id].addr, secret) then done[#done + 1] = id end
    end
    WhipEvidence.Data.markAnalysed(done)
    return #done
end

-- Every kind of evidence bag once, not analysed yet (tests the lab, lockers and MDT without the minigames).
-- Your own fingerprint and blood, gun serial TEST-<charId>. Straight into the pockets.
local function giveAllBags(source, player)
    local officer = WhipEvidence.officerLabel(source, player)
    local traits = WhipEvidence.Data.traits(player.charId) or {}
    local me = ('%s %s'):format(player.firstName or '', player.lastName or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if me == '' then me = officer end
    local gun = { serial = 'TEST-' .. player.charId, caliber = '9mm' }
    local fp, blood = { fingerprint = traits.fingerprint or 'TEST' }, { blood = traits.blood or 'O+' }
    local car = L('vehicle_plate', 'TEST 123')
    local list = {
        -- kind, label, data for the lab (nil = nothing to analyse), extra fields, age at collection (s)
        { 'casing', WhipEvidence.label('casing'), gun, { marker = '#1' }, 600 },
        { 'bullet', WhipEvidence.label('bullet'), gun, { marker = '#2' }, 600 },
        { 'blood', WhipEvidence.label('blood'), blood, { marker = '#3' }, 1500 },
        { 'fingerprint', WhipEvidence.label('fingerprint'), fp, { marker = '#4' }, 3600 },
        { 'vehicle_fragment', WhipEvidence.label('vehicle_fragment'), { colour = 'Test Red' }, { marker = '#5' }, 300 },
        { 'blood', L('type_blood_clothing'), blood, { tested_on = me } },
        { 'gsr', L('gsr_test'), nil, { tested_on = me, gsr = L('gsr_strong') } },
        { 'fingerprint', L('type_fp_weapon'), fp, { tested_on = ('Pistol (%s)'):format(gun.serial), street = '-' } },
        { 'fingerprint', L('type_fp_vehicle'), fp, { tested_on = car } },
        { 'blood', L('type_blood_vehicle'), blood, { tested_on = car } },
        { 'casing', L('type_casing_vehicle', 2), gun, { tested_on = car } },
        { 'bullet', L('type_bullet_vehicle', 1), gun, { tested_on = car } },
        { 'gsr', L('type_gsr_vehicle'), nil, { tested_on = car, gsr = 'POSITIVE' } },
        { 'bullet', L('type_bullet_body'), gun, { tested_on = 'L1', marker = 'L1' } },
        { 'blood', L('type_blood_body'), blood, { tested_on = 'L1', marker = 'L1' } },
        { 'gsr', L('gsr_test'), nil, { tested_on = 'L1', gsr = L('gsr_weak') } },
    }
    local queries, made = {}, 0
    for _, e in ipairs(list) do
        local meta = {
            evidence_id = WhipEvidence.Data.newId(), kind = e[1], type = e[2],
            time = os.date('%Y-%m-%d %H:%M:%S'), street = 'Test', collected_by = officer,
            photographed = e[5] and L('no') or nil,
        }
        for k, v in pairs(e[4]) do meta[k] = v end
        meta.custody = WhipEvidence.custody(nil, L('custody_collected'), officer)
        local secret = e[3] and WhipEvidence.Evidence.secretFor(e[1], e[3], meta, e[5]) or nil
        if exports.whip_core:AddItem(source, WhipEvidence.Items.bag, 1, meta, 'Forensics test bags') then
            made = made + 1
            if secret and next(secret) then queries[#queries + 1] = WhipEvidence.Data.bagQuery(meta.evidence_id, e[1], secret) end
        end
    end
    WhipEvidence.Data.saveBags(queries)
    return made, #list
end

local function giveKit(source)
    local I = WhipEvidence.Items
    local list = {
        { I.kit, 1 }, { I.case, 1 }, { I.empty, 10 }, { I.laser, 2 }, { I.pliers, 1 }, { I.wipe, 3 },
        { 'camera', 1 }, { 'gunny_torch', 1 },
    }
    local n = 0
    for _, it in ipairs(list) do
        if exports.whip_core:GetItemDef(it[1]) and exports.whip_core:AddItem(source, it[1], it[2], nil, 'Forensics test kit') then n = n + 1 end
    end
    return n
end

-- Lab screens: where exactly the picture sits on the model, fitted in game (KVP, per lab)
local FITS = 'whip_evidence:screenfits'
local CORNER = { { 'x', 'number', -10, 10 }, { 'y', 'number', -10, 10 }, { 'z', 'number', -10, 10 } }


local function loadFits()
    local fits = {}
    for _, lab in ipairs(Config.Labs or {}) do
        local raw = lab.id and GetResourceKvpString('screenfit:' .. lab.id)
        local ok, fit = pcall(json.decode, raw or '')
        if ok and type(fit) == 'table' then fits[lab.id] = fit end
    end
    GlobalState[FITS] = fits
end

function WhipEvidence.Admin.register()
    loadFits()

    Whip.core:SecureEvent('whip_evidence:screenFit', {
        ace = 'whip.devtools', rateLimit = 1000,
        -- the picture's corners (top left, top right, bottom left), metres from the lab's screen position
        params = { { 'lab', 'string', 32 }, { 'fit', 'record', {
            { 'tl', 'record', CORNER }, { 'tr', 'record', CORNER }, { 'bl', 'record', CORNER },
        } } },
    }, function(source, player, labId, fit)
        local lab
        for _, l in ipairs(Config.Labs or {}) do
            if l.id == labId then lab = l end
        end
        if not lab then return false, 'Unknown lab.' end
        fit.model = WhipEvidence.screenModel(lab) or 'none'
        SetResourceKvp('screenfit:' .. lab.id, json.encode(fit))
        local fits = GlobalState[FITS] or {}
        fits[lab.id] = fit
        GlobalState[FITS] = fits
        exports.whip_core:LogActivity(source, 'evidence_admin_test', { detail = 'screen fitted: ' .. lab.id })
        exports.whip_core:NotifyPlayer(source, ('Screen of %s saved.'):format(lab.label or lab.id), 'success')
    end)

    Whip.core:SecureEvent('whip_evidence:adminTest', {
        ace = 'whip.devtools', rateLimit = 1000,
        params = { { 'action', 'enum', { 'spawn', 'ready', 'finishLabs', 'reveal', 'kit', 'bags' } } },
    }, function(source, player, action)
        local text
        if action == 'spawn' then
            text = ('%d piece(s) of test evidence placed around you.'):format(spawnAll(source, player))
        elseif action == 'ready' then
            text = ('%d piece(s) within 25 m are ready to collect now.'):format(
                WhipEvidence.Evidence.makeReady(GetEntityCoords(GetPlayerPed(source)), 25.0))
        elseif action == 'finishLabs' then
            text = ('%d running analysis/analyses finished.'):format(WhipEvidence.Lab.finishNow())
        elseif action == 'bags' then
            local made, all = giveAllBags(source, player)
            text = ('%d of %d evidence bag(s) given (not analysed).'):format(made, all)
            if made < all then text = text .. ' Pockets full?' end
        elseif action == 'reveal' then
            text = ('%d bag(s) in your pockets analysed.'):format(revealMine(source))
        else
            text = ('%d test item(s) given.'):format(giveKit(source))
        end
        exports.whip_core:LogActivity(source, 'evidence_admin_test', { detail = action })
        exports.whip_core:NotifyPlayer(source, text, 'success')
    end)

    -- Test bodies: a pedestrian 4 m in front (armed: holds a pistol, GSR on the hands);
    -- "stand-in": your model, bleeds your blood and carries your GSR (tests a player's body alone)
    Whip.core:SecureEvent('whip_evidence:adminBody', {
        ace = 'whip.devtools', rateLimit = 1000,
        params = { { 'action', 'enum', { 'ped', 'armed', 'clone', 'clear' } } },
    }, function(source, player, action)
        if action == 'clear' then
            local n = WhipEvidence.Bodies.clearAll()
            exports.whip_core:NotifyPlayer(source, ('%d body/bodies removed.'):format(n), 'success')
            return
        end
        local me = GetPlayerPed(source)
        local h = GetEntityHeading(me)
        local r = math.rad(h)
        local pos = GetEntityCoords(me) + vector3(-math.sin(r) * 4.0, math.cos(r) * 4.0, 0.0)
        local model = action == 'clone' and GetEntityModel(me) or joaat('a_m_y_business_01')
        local ped = CreatePed(4, model, pos.x, pos.y, pos.z - 0.9, (h + 180.0) % 360.0, true, true)
        local untilAt = GetGameTimer() + 3000
        while not DoesEntityExist(ped) and GetGameTimer() < untilAt do Wait(50) end
        if not exports.whip_core:IsSessionCurrent(source, player.session) then
            if DoesEntityExist(ped) then DeleteEntity(ped) end
            return
        end
        if not DoesEntityExist(ped) then
            return false, 'The pedestrian could not be made (entity lockdown?).'
        end
        if action == 'armed' then GiveWeaponToPed(ped, joaat('WEAPON_PISTOL'), 30, false, true) end
        local net = NetworkGetNetworkIdFromEntity(ped)
        if action == 'clone' then WhipEvidence.Bodies.markClone(net, source, player.charId) end
        TriggerClientEvent('whip_evidence:client:testPed', source, net)
        exports.whip_core:NotifyPlayer(source, 'Test pedestrian placed in front of you. Kill it, then examine the body.', 'success')
    end)

    Whip.core:SecureCallback('whip_evidence:adminCases', { ace = 'whip.devtools', rateLimit = 500 }, function()
        return WhipEvidence.Cases.list()
    end)

    Whip.core:SecureEvent('whip_evidence:adminCase', {
        ace = 'whip.devtools', rateLimit = 1000,
        params = { { 'action', 'enum', { 'open', 'close', 'reopen', 'delete' } }, { 'case', 'string', 32 } },
    }, function(source, player, action, caseId)
        local ok, why
        if action == 'open' then
            ok, why = WhipEvidence.Cases.adminOpen(source, caseId)
        elseif action == 'delete' then
            ok, why = WhipEvidence.Cases.delete(caseId, source)
            if ok then why = ('Case %s deleted (%d item(s) gone).'):format(caseId, why) end
        else
            ok, why = WhipEvidence.Cases.setClosed(caseId, action == 'close')
            if ok then why = ('Case %s %s.'):format(caseId, action == 'close' and 'closed' or 'reopened') end
        end
        if not ok then return false, why end
        if why then exports.whip_core:NotifyPlayer(source, why, 'success') end
        TriggerClientEvent('whip_evidence:client:adminCasesChanged', source)
    end)
end
