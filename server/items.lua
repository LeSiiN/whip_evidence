-- Items: evidence bag, crime scene photo, forensics kit, laser pointer, pliers, cleaning cloth
WhipEvidence.ItemDefs = {}

local I = WhipEvidence.Items
local ACT_COPY     = WhipEvidence.Res .. ':copy'
local ACT_SIGN     = WhipEvidence.Res .. ':sign'
local CUSTODY_SEP, CUSTODY_KEEP = ' → ', 6

-- Empty bags: only used up when Config.NeedEmptyBag is on
function WhipEvidence.hasEmptyBags(source, n)
    if not Config.NeedEmptyBag then return true end
    return (exports.whip_core:GetItemCount(source, I.empty) or 0) >= (n or 1)
end

function WhipEvidence.useEmptyBag(source)
    if not Config.NeedEmptyBag then return true end
    return exports.whip_core:RemoveItem(source, I.empty, 1, nil, 'Evidence bagged') == true
end

-- A bag could not be given after all: the empty one goes back
function WhipEvidence.returnEmptyBag(source)
    if Config.NeedEmptyBag then exports.whip_core:AddItem(source, I.empty, 1, nil, 'Evidence bag returned') end
end

-- Chain of custody: "11/16 14:02 Collected · Sgt | Smith → 11/16 14:20 In lab: Police Lab · ..."
-- Keeps the first entry (who collected it) and the newest ones.
function WhipEvidence.custody(old, what, who)
    local list = {}
    if type(old) == 'string' and old ~= '' then
        local from = 1
        while true do
            local a, b = old:find(CUSTODY_SEP, from, true)
            list[#list + 1] = old:sub(from, (a or 0) - 1)
            if not a then break end
            from = b + 1
        end
    end
    list[#list + 1] = ('%s %s%s'):format(os.date('%m/%d %H:%M'), what, who and (' · ' .. who) or '')
    while #list > CUSTODY_KEEP do table.remove(list, 2) end
    return table.concat(list, CUSTODY_SEP)
end

-- Wear: durability drops per use by the item setting "wear" (/whip -> Economy -> Items)
function WhipEvidence.wear(source, item)
    local setting = exports.whip_core:GetItemSetting(item, 'wear')
    local wear = tonumber(setting) or 0
    if wear <= 0 then return end
    local found = exports.whip_core:FindItem(source, item)
    if not found then return end
    local left = (tonumber(found.metadata and found.metadata.durability) or 100) - wear
    if left <= 0 then
        exports.whip_core:StoreTake(found.addr, 1, { reason = 'worn out' })
        local def = exports.whip_core:GetItemDef(item)
        exports.whip_core:NotifyPlayer(source, ((def and def.name) or item) .. ' is worn out.', 'warning')
    else
        exports.whip_core:SetItemMetadata(found.addr, { durability = math.floor(left * 10 + 0.5) / 10 })
    end
end

-- Activity log entry that also lands in the bag's own item history (chain of custody)
function WhipEvidence.logBag(source, event, detail, bagId)
    local addr
    for _, found in ipairs(exports.whip_core:FindAllItems(source, WhipEvidence.Items.bag) or {}) do
        if found.metadata and found.metadata.evidence_id == bagId then addr = found.addr break end
    end
    exports.whip_core:LogActivity(source, event, { detail = detail, slotData = addr })
end

local function wearSetting(default)
    return { { key = 'wear', type = 'number', default = default, min = 0, max = 100, step = 0.5, unit = '%',
               label = 'Wear per use', help = '0 = lasts forever' } }
end

local function newTool()
    return { durability = 100 }
end

-- Values the lab reveals, in the order "Copy data" looks for them
local COPY_FIELDS = {
    { 'weapon_serial', 'Serial number' },
    { 'fingerprint', 'Fingerprint' },
    { 'blood_type', 'Blood type' },
    { 'paint', 'Paint' },
}

function WhipEvidence.ItemDefs.register()
    Whip.core:RegisterItem(I.bag, {
        name = 'Evidence Bag', desc = 'A sealed evidence bag holding one piece of evidence.',
        weight = 0.005, type = 'evidence', stack = false, usable = false,
        prop = 'prop_paper_bag_small',
        -- picture per type: html/img/items/bag_casing.webp, bag_bullet.webp, ... (no type = empty bag picture)
        images = { { image = 'html/img/items/bag_{kind}.webp' } },
        metaFields = {
            { key = 'case',          label = 'Case' },
            { key = 'type',          label = 'Type' },
            { key = 'time',          label = 'Time' },
            { key = 'street',        label = 'Street' },
            { key = 'ammo',          label = 'Ammunition' },
            { key = 'weapon_serial', label = 'Serial number' },
            { key = 'fingerprint',   label = 'Fingerprint' },
            { key = 'blood_type',    label = 'Blood type' },
            { key = 'paint',         label = 'Paint' },
            { key = 'gsr',           label = 'GSR' },
            { key = 'ballistics',    label = 'Ballistics' },
            { key = 'tested_on',     label = 'Tested on' },
            { key = 'marker',        label = 'Marker' },
            { key = 'age',           label = 'Age at collection' },
            { key = 'photographed',  label = 'Photographed' },
            { key = 'collected_by',  label = 'Collected by' },
            { key = 'custody',       label = 'Chain of custody' },
        },
        contextOptions = {
            { action = ACT_COPY, label = 'Copy data', order = 1, anywhere = true },
            { action = ACT_SIGN, label = 'Sign for evidence', order = 3, anywhere = true,
              require = WhipEvidence.req('evidence_sign') },
        },
    })

    WhipEvidence.Photo.registerItem(ACT_SIGN)

    Whip.core:RegisterItem(I.kit, {
        name = 'Forensics Kit', desc = 'Everything needed to collect evidence and run GSR tests.',
        weight = 3.0, type = 'tool', stack = false, usable = false,
        metaFields = { { key = 'durability', label = 'Condition (%)', value = '100' } },
        settings = wearSetting(2.5),
    })

    Whip.core:RegisterItem(I.pliers, {
        name = 'Pliers', desc = 'Sturdy pliers. Essential when it counts.',
        weight = 0.75, type = 'tool', stack = false, usable = false,
        metaFields = { { key = 'durability', label = 'Condition (%)', value = '100' } },
        settings = wearSetting(1.0),
    })

    Whip.core:RegisterItem(I.empty, {
        name = 'Empty Evidence Bag', desc = 'A clean, sealable evidence bag.',
        weight = 0.005, type = 'tool', stack = true, maxStack = 50, usable = false,
    })

    Whip.core:RegisterItem(I.laser, {
        name = 'Laser Pointer', desc = 'Shows the path of a bullet from its hole.',
        weight = 0.5, type = 'tool', stack = true, maxStack = 10, usable = false,
    })

    Whip.core:RegisterItem(I.wipe, {
        name = 'Cleaning Cloth', desc = 'Wipes away fingerprints, blood and other traces.',
        weight = 0.05, type = 'tool', stack = true, maxStack = 20, usable = false,
    })

    Whip.core:RegisterItemDefaultMetadata(I.kit, newTool)
    Whip.core:RegisterItemDefaultMetadata(I.pliers, newTool)

    -- Right-click "Copy data": the first analysed value goes to the clipboard
    Whip.core:RegisterContextAction(ACT_COPY, function(source, player, slotData)
        local m = slotData.metadata or {}
        for _, field in ipairs(COPY_FIELDS) do
            local value = m[field[1]]
            if value and value ~= '???' then
                TriggerClientEvent('whip_evidence:client:copy', source, tostring(value), field[2])
                return
            end
        end
        return false, 'Nothing on this bag has been analysed yet.'
    end)

    -- Right-click "Sign for evidence": the officer who takes it over signs the chain of custody
    Whip.core:RegisterContextAction(ACT_SIGN, function(source, player, slotData, addr)
        if not WhipEvidence.can(source, 'evidence_sign') then return false, 'Only on-duty police with the right rank can sign for evidence.' end
        local who = WhipEvidence.officerLabel(source, player)
        local old = slotData.metadata and slotData.metadata.custody
        if type(old) == 'string' and old:sub(-#who) == who then return false, 'You are already the last one who signed.' end
        local ok, why = exports.whip_core:SetItemMetadata(addr, { custody = WhipEvidence.custody(old, 'Received', who) })
        if not ok then return false, why end
        exports.whip_core:LogActivity(source, 'evidence_signed', { detail = who, slotData = addr })
        exports.whip_core:NotifyPlayer(source, 'You signed for this evidence.', 'success')
    end)

end
