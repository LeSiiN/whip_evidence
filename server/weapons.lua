-- Prints on weapons. Drawing a gunny weapon without gloves leaves your print on it (by serial).
-- Police dusts it from the weapon's right-click menu, a cleaning cloth wipes it.
WhipEvidence.Weapons = {}

local ACT_DUST = WhipEvidence.Res .. ':dust'
local ACT_WIPE = WhipEvidence.Res .. ':wipegun'
local ACT_FILE = WhipEvidence.Res .. ':fileserial'
local ACT_RESTORE = WhipEvidence.Res .. ':restoreserial'

local drawn = {}     -- [source] = { serial, at }   (from whip_gunny:weapon:drawn)
local written = {}   -- ["serial:charId"] = os.time() of the last DB write, saves writes

AddEventHandler('whip_gunny:weapon:drawn', function(e)
    if GetInvokingResource() ~= 'whip_gunny' or type(e) ~= 'table' or not e.source then return end
    if e.serial then drawn[e.source] = { serial = e.serial, at = os.time() } end
end)

AddEventHandler('whip_gunny:weapon:holstered', function(e)
    if GetInvokingResource() ~= 'whip_gunny' or type(e) ~= 'table' or not e.source then return end
    local d = drawn[e.source]
    if d and (not e.serial or d.serial == e.serial) then d.holstered = true end
end)

AddEventHandler('playerDropped', function()
    drawn[source] = nil
end)

local function weaponName(slotData)
    local def = exports.whip_core:GetItemDef(slotData.item)
    return (def and def.name) or slotData.item
end

local function dust(source, player, slotData, addr)
    local serial = slotData.metadata and slotData.metadata.serial
    if not serial then return false, L('no_serial') end
    if not WhipEvidence.can(source, 'evidence_dust') then return false, WhipEvidence.why(source, 'evidence_dust') end
    if not exports.whip_core:HasItem(source, WhipEvidence.Items.kit) then return false, L('need_kit') end
    if not WhipEvidence.hasEmptyBags(source) then return false, L('no_empty_bags') end

    local passed, res = WhipEvidence.minigame(source, 'dust')
    if not passed then
        if res == 'busy' then return false, L('busy') end
        if res == 'cancelled' or res == 'not started' then return false end
        return false, L('powder_smeared')
    end
    if not exports.whip_core:IsSessionCurrent(source, player.session) then return false end

    local done = exports.whip_core:Progress(source, WhipEvidence.bar('dust', {
        label = L('dusting'), duration = 6000, icon = 'target',
        disable = { move = true, combat = true, car = true },
    }))
    if not done then return false end
    if not exports.whip_core:IsSessionCurrent(source, player.session) then return false end

    WhipEvidence.wear(source, WhipEvidence.Items.kit)
    local charIds = WhipEvidence.Data.weaponPrints(serial)
    if #charIds == 0 then return false, L('no_prints') end

    local name = weaponName(slotData)
    local queries = {}
    for _, charId in ipairs(charIds) do
        -- a negative id is a glove fibre (-(fibre + 1)), not a person
        local traits = charId > 0 and WhipEvidence.Data.traits(charId)
        if charId < 0 and WhipEvidence.useEmptyBag(source) then
            local officer = WhipEvidence.officerLabel(source, player)
            local meta = {
                evidence_id = WhipEvidence.Data.newId(), kind = 'fiber', type = L('type_fiber_weapon'),
                time = os.date('%Y-%m-%d %H:%M:%S'), street = '-', collected_by = officer,
                tested_on = ('%s (%s)'):format(name, serial),
                custody = WhipEvidence.custody(nil, L('custody_collected'), officer),
            }
            local secret = WhipEvidence.Evidence.secretFor('fiber', { fiber = -charId - 1 }, meta)
            if WhipEvidence.giveBag(source, meta, 'Weapon fibres ' .. serial) then
                queries[#queries + 1] = WhipEvidence.Data.bagQuery(meta.evidence_id, 'fiber', secret)
            else
                WhipEvidence.returnEmptyBag(source)
            end
        end
        if traits then
            local meta = {
                evidence_id  = WhipEvidence.Data.newId(),
                kind         = 'fingerprint',
                type         = L('type_fp_weapon'),
                time         = os.date('%Y-%m-%d %H:%M:%S'),
                street       = '-',
                collected_by = WhipEvidence.officerLabel(source, player),
                tested_on    = ('%s (%s)'):format(name, serial),
                fingerprint  = '???',
            }
            meta.custody = WhipEvidence.custody(nil, L('custody_collected'), meta.collected_by)
            if WhipEvidence.useEmptyBag(source) then
                if WhipEvidence.giveBag(source, meta, 'Weapon prints ' .. serial) then
                    queries[#queries + 1] = WhipEvidence.Data.bagQuery(meta.evidence_id, 'fingerprint', { fingerprint = traits.fingerprint })
                else
                    WhipEvidence.returnEmptyBag(source)
                end
            end
        end
    end
    WhipEvidence.Data.saveBags(queries)
    exports.whip_core:LogActivity(source, 'evidence_weapon_dusted', { detail = ('%s: %d'):format(serial, #queries), slotData = addr })
    exports.whip_core:NotifyPlayer(source, L('prints_lifted', #queries), 'success')
end

local function wipe(source, player, slotData, addr)
    local serial = slotData.metadata and slotData.metadata.serial
    if not serial then return false end
    if not exports.whip_core:HasItem(source, WhipEvidence.Items.wipe) then return false, L('need_cloth') end
    local done = exports.whip_core:Progress(source, WhipEvidence.bar('wipe_weapon', {
        label = L('wiping_weapon'), duration = 4000, icon = 'fail',
        disable = { move = true, combat = true, car = true },
    }))
    if not done then return false end
    if not exports.whip_core:IsSessionCurrent(source, player.session) then return false end
    WhipEvidence.Data.wipeWeapon(serial)
    for key in pairs(written) do
        if key:sub(1, #serial + 1) == serial .. ':' then written[key] = nil end
    end
    exports.whip_core:LogActivity(source, 'evidence_weapon_wiped', { slotData = addr })
    exports.whip_core:NotifyPlayer(source, L('weapon_wiped'), 'success')
end

---------------------------------------------------------------- Filing the serial off, and getting it back

-- The slot still holds this weapon with this serial (after a progress bar)
local function stillThere(addr, item, serial)
    local store = exports.whip_core:StoreRead(addr)
    local it = store and store.items and store.items[addr.slot]
    return it and it.item == item and (it.metadata or {}).serial == serial
end

-- "AB3K9X2M7QPL" -> "##3####M####": a few characters survive. It stays unique (whip_gunny knows a weapon by it).
local function filedOf(serial)
    for _ = 1, 8 do
        local keep = {}
        while #serial > 3 and (function() local n = 0 for _ in pairs(keep) do n = n + 1 end return n end)() < 2 do
            keep[math.random(1, #serial)] = true
        end
        local out = {}
        for i = 1, #serial do out[i] = keep[i] and serial:sub(i, i) or '#' end
        local filed = table.concat(out)
        if not WhipEvidence.Data.filedOriginal(filed) then return filed end
    end
    return nil
end

local function fileSerial(source, player, slotData, addr)
    local m = slotData.metadata or {}
    local serial = m.serial
    if not serial then return false, L('no_serial') end
    if m.serial_filed or serial:find('#', 1, true) then return false, L('serial_already_filed') end
    if not exports.whip_core:HasItem(source, WhipEvidence.Items.file) then return false, L('need_file') end
    local d = drawn[source]
    if d and d.serial == serial and not d.holstered then return false, L('holster_first') end
    local done = exports.whip_core:Progress(source, WhipEvidence.bar('file_serial', {
        label = L('filing_serial'), duration = 9000, icon = 'fail',
        disable = { move = true, combat = true, car = true },
    }))
    if not done or not exports.whip_core:IsSessionCurrent(source, player.session) then return false end
    if not stillThere(addr, slotData.item, serial) then return false, L('weapon_moved') end
    local filed = filedOf(serial)
    if not filed or not WhipEvidence.Data.fileSerial(filed, serial) then return false, L('try_again') end
    local ok, why = exports.whip_core:SetItemMetadata(addr, { serial = filed, serial_filed = 'yes' })
    if not ok then return false, why end
    for key in pairs(written) do
        if key:sub(1, #serial + 1) == serial .. ':' then written[key] = nil end
    end
    WhipEvidence.wear(source, WhipEvidence.Items.file)
    exports.whip_core:LogActivity(source, 'evidence_serial_filed', { detail = serial .. ' -> ' .. filed, slotData = addr })
    exports.whip_core:NotifyPlayer(source, L('serial_filed', filed), 'success')
end

local function nearLab(source)
    local pos = GetEntityCoords(GetPlayerPed(source))
    for _, lab in ipairs(Config.Labs or {}) do
        if lab.device and #(pos - WhipEvidence.vec(lab.device)) <= 3.5 then return true end
    end
    return false
end

-- Police at a lab device: acid brings part of a filed serial back (each character with SerialRestoreChance,
-- sometimes nothing at all). Once per weapon: the result is on the weapon.
local function restoreSerial(source, player, slotData, addr)
    local m = slotData.metadata or {}
    if not m.serial_filed then return false, L('serial_not_filed') end
    if m.serial_restored then return false, L('serial_restored_already', m.serial_restored) end
    if not WhipEvidence.can(source, 'evidence_dust') then return false, WhipEvidence.why(source, 'evidence_dust') end
    if not exports.whip_core:HasItem(source, WhipEvidence.Items.kit) then return false, L('need_kit') end
    if not nearLab(source) then return false, L('need_lab_device') end
    local done = exports.whip_core:Progress(source, WhipEvidence.bar('restore_serial', {
        label = L('restoring_serial'), duration = 10000, icon = 'target',
        disable = { move = true, combat = true, car = true },
    }))
    if not done or not exports.whip_core:IsSessionCurrent(source, player.session) then return false end
    if not stillThere(addr, slotData.item, m.serial) then return false, L('weapon_moved') end
    local original = WhipEvidence.Data.filedOriginal(m.serial) or ''
    local lost = original == '' or WhipEvidence.roll(Config.SerialLostChance or 15)
    local out = {}
    for i = 1, #m.serial do
        local c = m.serial:sub(i, i)
        if c ~= '#' then
            out[i] = c
        elseif not lost and WhipEvidence.roll(Config.SerialRestoreChance or 60) then
            out[i] = original:sub(i, i)
        else
            out[i] = '?'
        end
    end
    local result = table.concat(out)
    local ok, why = exports.whip_core:SetItemMetadata(addr, { serial_restored = lost and L('serial_destroyed') or result })
    if not ok then return false, why end
    WhipEvidence.wear(source, WhipEvidence.Items.kit)
    -- the result as a lab report in a bag (for the case); the weapon card cannot show it
    if WhipEvidence.useEmptyBag(source) then
        local officer = WhipEvidence.officerLabel(source, player)
        local meta = {
            evidence_id = WhipEvidence.Data.newId(), kind = 'serial', type = L('type_serial_report'),
            time = os.date('%Y-%m-%d %H:%M:%S'), street = '-', collected_by = officer,
            tested_on = ('%s (%s)'):format(weaponName(slotData), m.serial),
            weapon_serial = lost and L('serial_destroyed') or result,
            custody = WhipEvidence.custody(nil, L('custody_analysed', L('lab')), officer),
        }
        if not WhipEvidence.giveBag(source, meta, 'Serial report ' .. m.serial) then WhipEvidence.returnEmptyBag(source) end
    end
    exports.whip_core:LogActivity(source, 'evidence_serial_restored', { detail = m.serial .. ' -> ' .. (lost and 'lost' or result), slotData = addr })
    exports.whip_core:NotifyPlayer(source, lost and L('serial_lost') or L('serial_restored', result), lost and 'warning' or 'success')
end

function WhipEvidence.Weapons.register()
    -- The client drew a weapon: a print, or with gloves = true maybe fibres. The serial comes from whip_gunny.
    Whip.core:SecureEvent('whip_evidence:touchWeapon', {
        rateLimit = 2000, burst = 2, sheet = 'light',
        params = { { 'gloves', 'bool', false } },
    }, function(source, player, gloves)
        local d = drawn[source]
        if not d or os.time() - d.at > 15 then return false end
        local id = player.charId
        if gloves then
            local fiber = WhipEvidence.Body.fiber(source)
            if not fiber or not WhipEvidence.roll(Config.FiberChance or 60) then return end
            id = -(fiber + 1)   -- stored like a print, with a negative id
        end
        local key = d.serial .. ':' .. id
        local now = os.time()
        if written[key] and now - written[key] < 600 then return end   -- one DB write per 10 min is enough
        written[key] = now
        WhipEvidence.Data.touchWeapon(d.serial, id)
    end)

    Whip.core:RegisterContextAction(ACT_DUST, dust)
    Whip.core:RegisterContextAction(ACT_WIPE, wipe)
    Whip.core:RegisterContextAction(ACT_FILE, fileSerial)
    Whip.core:RegisterContextAction(ACT_RESTORE, restoreSerial)

    local hasSerial = { serial = { empty = false } }
    local function addOptions(item)
        Whip.core:AddItemOption(item, { action = ACT_DUST, label = L('opt_dust'), anywhere = true, when = hasSerial,
            require = WhipEvidence.req('evidence_dust'), whyNot = L('no_serial') })
        Whip.core:AddItemOption(item, { action = ACT_WIPE, label = L('opt_wipe_prints'), when = hasSerial,
            require = { item = WhipEvidence.Items.wipe } })
    end
    -- only guns have a serial worth filing off
    local function addSerialOptions(item)
        Whip.core:AddItemOption(item, { action = ACT_FILE, label = L('opt_file_serial'), when = hasSerial,
            require = { item = WhipEvidence.Items.file } })
        Whip.core:AddItemOption(item, { action = ACT_RESTORE, label = L('opt_restore_serial'), anywhere = true,
            when = { serial_filed = { empty = false } }, require = WhipEvidence.req('evidence_dust') })
    end
    for item in pairs(Config.Calibers) do addSerialOptions(item) end
    for item in pairs(Config.Calibers) do addOptions(item) end
    for _, item in ipairs(Config.MeleeWeapons) do addOptions(item) end
end
