-- Evidence case: an item with 30 compartments (WHIP panel item: its contents live in its metadata.slots
-- and travel with it). New bags go into the case first (Config.BagsIntoCase), the pockets only when it is full.
-- Handing the case over signs every bag in it ("Received"); at a lab it unloads in one go.
WhipEvidence.Briefcase = {}

local I = WhipEvidence.Items
local SLOTS = 30
local ACT_OPEN = WhipEvidence.Res .. ':opencase'

-- metadata.slots as { [n] = { item, amount, metadata } } (JSON can turn the keys into strings)
local function slotsOf(meta)
    local out = {}
    local raw = type(meta) == 'table' and type(meta.slots) == 'table' and meta.slots or {}
    for k, v in pairs(raw) do
        local n = tonumber(k)
        if n and type(v) == 'table' and v.item then out[n] = v end
    end
    return out
end
WhipEvidence.Briefcase.slotsOf = slotsOf

function WhipEvidence.Briefcase.all(source)
    return exports.whip_core:FindAllItems(source, I.case) or {}
end

-- Puts a bag into the first case with room. true when it went in.
function WhipEvidence.Briefcase.put(source, meta)
    for _, f in ipairs(WhipEvidence.Briefcase.all(source)) do
        local slots = slotsOf(f.metadata)
        for n = 1, SLOTS do
            if not slots[n] then
                slots[n] = { item = I.bag, amount = 1, metadata = meta }
                if exports.whip_core:SetItemMetadata(f.addr, { slots = slots }) then return true end
                break
            end
        end
    end
    return false
end

-- Every new bag goes through here: case first, else the pockets. Returns 'case', the AddItem answer, or false.
function WhipEvidence.giveBag(source, meta, reason)
    TriggerClientEvent('whip_evidence:client:bagged', source)   -- a short sound: the bag is sealed
    if Config.BagsIntoCase ~= false and WhipEvidence.Briefcase.put(source, meta) then return 'case' end
    return exports.whip_core:AddItem(source, I.bag, 1, meta, reason)
end

-- The id of a bag or photo in a compartment
local function idOf(s)
    local m = type(s) == 'table' and type(s.metadata) == 'table' and s.metadata or {}
    return m.evidence_id or m.photo_id
end
WhipEvidence.Briefcase.idOf = idOf

-- Takes compartments out of a case BEFORE they go somewhere else (so nothing can exist twice).
-- expect: { [n] = id }; only compartments that still hold that bag/photo come out.
-- Returns { [n] = entry } of what came out, or nil.
function WhipEvidence.Briefcase.take(caseAddr, expect)
    local it = exports.whip_core:GetItemAt(caseAddr)
    if not it or it.item ~= I.case then return nil end
    local slots, out = slotsOf(it.metadata), {}
    for n, id in pairs(expect) do
        if slots[n] and idOf(slots[n]) == id then out[n], slots[n] = slots[n], nil end
    end
    if not next(out) then return nil end
    if not exports.whip_core:SetItemMetadata(caseAddr, { slots = slots }) then return nil end
    return out
end

-- Taken out but could not be placed: back into the case (same compartment or the first free one), else the pockets
function WhipEvidence.Briefcase.putBack(source, caseAddr, entries)
    local left = {}
    local it = exports.whip_core:GetItemAt(caseAddr)
    if it and it.item == I.case then
        local slots = slotsOf(it.metadata)
        for n, e in pairs(entries) do
            local at = not slots[n] and n or nil
            if not at then
                for k = 1, SLOTS do if not slots[k] then at = k; break end end
            end
            if at then slots[at] = e else left[#left + 1] = e end
        end
        if not exports.whip_core:SetItemMetadata(caseAddr, { slots = slots }) then
            left = {}
            for _, e in pairs(entries) do left[#left + 1] = e end
        end
    else
        for _, e in pairs(entries) do left[#left + 1] = e end
    end
    for _, e in ipairs(left) do
        if not exports.whip_core:AddItem(source, e.item, e.amount or 1, e.metadata, 'Back from evidence case') then
            exports.whip_core:LogActivity(source, 'evidence_lost', { detail = 'no room for ' .. tostring(idOf(e)) })
        end
    end
end

-- The case changed hands: every bag and photo in it gets "Received · <new holder>"
local function signContents(source)
    local player = exports.whip_core:GetPlayer(source)
    if not player then return end
    local who = WhipEvidence.isPolice(source) and WhipEvidence.officerLabel(source, player)
        or ('%s %s'):format(player.firstName or '', player.lastName or '')
    for _, f in ipairs(WhipEvidence.Briefcase.all(source)) do
        local slots, changed = slotsOf(f.metadata), false
        for _, s in pairs(slots) do
            local m = type(s.metadata) == 'table' and s.metadata or nil
            local old = m and m.custody
            if m and (s.item == I.bag or s.item == I.photo) and not (type(old) == 'string' and old:sub(-#who) == who) then
                m.custody = WhipEvidence.custody(old, L('custody_received_case'), who)
                changed = true
            end
        end
        if changed then exports.whip_core:SetItemMetadata(f.addr, { slots = slots }) end
    end
end

function WhipEvidence.Briefcase.register()
    Whip.core:RegisterItem(I.case, {
        name = L('item_case'), desc = L('item_case_desc', SLOTS),
        weight = 2.0, type = 'tool', stack = false, usable = false,
        prop = 'prop_ld_case_01',
        defaultAction = ACT_OPEN,
        contextOptions = { { action = ACT_OPEN, label = L('opt_open'), order = 1 } },
    })
    local ok, why = Whip.core:RegisterPanelItem(I.case, {
        slots = SLOTS, label = L('item_case'), action = ACT_OPEN,
        allowedItems = { I.bag, I.photo, I.empty },
    })
    if not ok then Whip.startProblem('evidence case: %s', tostring(why)) end
end

-- given, picked up or taken from a boot: the new holder signs for what is inside
-- (at file level: Whip.register runs again after a whip_core restart)
AddEventHandler('whip_core:item:added', function(e)
    if GetInvokingResource() ~= 'whip_core' then return end
    if type(e) ~= 'table' or e.item ~= I.case or e.by then return end   -- e.by: a resource moved it (our own moves)
    local src = tonumber(e.source)
    if src then CreateThread(function() signContents(src) end) end
end)

-- At a lab device: every bag from the player's cases into the lab storage (guns stay with the player)
function WhipEvidence.Briefcase.unloadInto(source, containerId)
    local moved, full = 0, false
    for _, f in ipairs(WhipEvidence.Briefcase.all(source)) do
        local expect = {}
        for n, s in pairs(slotsOf(f.metadata)) do
            if s.item == I.bag and idOf(s) then expect[n] = idOf(s) end
        end
        local out = next(expect) and WhipEvidence.Briefcase.take(f.addr, expect)
        if out then
            local back = {}
            for n, s in pairs(out) do
                if not full and exports.whip_core:StoreGive({ kind = 'container', id = containerId }, I.bag, 1, s.metadata, 'Unloaded from evidence case') then
                    moved = moved + 1
                else
                    full, back[n] = true, s
                end
            end
            if next(back) then WhipEvidence.Briefcase.putBack(source, f.addr, back) end
        end
        if full then break end
    end
    return moved, full
end
