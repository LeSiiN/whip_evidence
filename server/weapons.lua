-- Prints on weapons. Drawing a gunny weapon without gloves leaves your print on it (by serial).
-- Police dusts it from the weapon's right-click menu, a cleaning cloth wipes it.
WhipEvidence.Weapons = {}

local ACT_DUST = WhipEvidence.Res .. ':dust'
local ACT_WIPE = WhipEvidence.Res .. ':wipegun'

local drawn = {}     -- [source] = { serial, at }   (from whip_gunny:weapon:drawn)
local written = {}   -- ["serial:charId"] = os.time() of the last DB write, saves writes

AddEventHandler('whip_gunny:weapon:drawn', function(e)
    if GetInvokingResource() ~= 'whip_gunny' or type(e) ~= 'table' or not e.source then return end
    if e.serial then drawn[e.source] = { serial = e.serial, at = os.time() } end
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
        local traits = WhipEvidence.Data.traits(charId)
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

function WhipEvidence.Weapons.register()
    -- The client drew a weapon without gloves: the serial comes from whip_gunny, not from the client
    Whip.core:SecureEvent('whip_evidence:touchWeapon', {
        rateLimit = 2000, burst = 2, sheet = 'light',
    }, function(source, player)
        local d = drawn[source]
        if not d or os.time() - d.at > 15 then return false end
        local key = d.serial .. ':' .. player.charId
        local now = os.time()
        if written[key] and now - written[key] < 600 then return end   -- one DB write per 10 min is enough
        written[key] = now
        WhipEvidence.Data.touchWeapon(d.serial, player.charId)
    end)

    Whip.core:RegisterContextAction(ACT_DUST, dust)
    Whip.core:RegisterContextAction(ACT_WIPE, wipe)

    local hasSerial = { serial = { empty = false } }
    local function addOptions(item)
        Whip.core:AddItemOption(item, { action = ACT_DUST, label = L('opt_dust'), anywhere = true, when = hasSerial,
            require = WhipEvidence.req('evidence_dust'), whyNot = L('no_serial') })
        Whip.core:AddItemOption(item, { action = ACT_WIPE, label = L('opt_wipe_prints'), when = hasSerial,
            require = { item = WhipEvidence.Items.wipe } })
    end
    for item in pairs(Config.Calibers) do addOptions(item) end
    for _, item in ipairs(Config.MeleeWeapons) do addOptions(item) end
end
