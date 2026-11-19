-- Labs: each lab is a WHIP container (storage) plus its own analysis device. Config.Labs holds any number.
-- While a lab analyses, its storage is locked: nobody can open it or take bags out.
-- On every start each lab is checked, and storages from older versions are emptied into the new ones.
-- Ballistics: put a gun into the storage too. The analysis test-fires it (a reference casing bag)
-- and marks every analysed casing/bullet in that lab that came from this gun.
WhipEvidence.Lab = {}

local labs = {}   -- [id] = { def, containerId, running = { ends, ids, guns, by } }

-- Storages older versions made. Their contents move into the nearest lab, then they are deleted.
local LEGACY_KEYS = { WhipEvidence.Res .. ':lab' }

local function busyName(def)
    return (def.label or def.id) .. L('lab_busy_suffix')
end

local function keyOf(id)
    return WhipEvidence.Res .. ':lab:' .. id
end

-- Bags and guns may go into a lab storage
local function allowedItems()
    local list = { [WhipEvidence.Items.bag] = true }
    for item in pairs(Config.Calibers) do list[item] = true end
    return list
end

-- One read of a storage: bags by id, guns, serials that already have a reference casing
local function contents(containerId, read)
    local stash = read({ kind = 'container', id = containerId })
    local c = { bags = {}, noId = 0, guns = {}, refs = {} }
    if type(stash) ~= 'table' then return c end
    for slot, it in pairs(stash.items or {}) do
        local meta = type(it.metadata) == 'table' and it.metadata or {}
        if it.item == WhipEvidence.Items.bag then
            if meta.kind == 'reference' and meta.weapon_serial then c.refs[meta.weapon_serial] = true end
            if meta.evidence_id then c.bags[meta.evidence_id] = { slot = tonumber(slot), meta = meta }
            else c.noId = c.noId + 1 end
        elseif Config.Calibers[it.item] and meta.serial then
            c.guns[#c.guns + 1] = { slot = tonumber(slot), item = it.item, serial = meta.serial }
        end
    end
    return c
end

-- What the device would do: bags waiting, guns without a reference casing, and counts for messages
local function status(containerId, read)
    local c = contents(containerId, read)
    local ids = {}
    for id in pairs(c.bags) do ids[#ids + 1] = id end
    local pending = WhipEvidence.Data.pendingSecrets(ids)
    local states = WhipEvidence.Data.bagStates(ids)
    local s = { total = #ids + c.noId, pending = {}, analysed = 0, nothing = c.noId, newGuns = {}, guns = #c.guns }
    for _, id in ipairs(ids) do
        if pending[id] then s.pending[#s.pending + 1] = id
        elseif states[id] and states[id].analysed then s.analysed = s.analysed + 1
        else s.nothing = s.nothing + 1 end
    end
    for _, g in ipairs(c.guns) do
        if not c.refs[g.serial] then s.newGuns[#s.newGuns + 1] = g end
    end
    return s
end

local function gunName(item)
    local def = Whip.core:GetItemDef(item)
    return (def and def.name) or item
end

---------------------------------------------------------------- Lab screen (client/labscreen.lua reads GlobalState)

-- One line per analysed bag for the screen: "#12 Casing · 9mm · ABC123"
local function resultLine(meta)
    local main = meta.weapon_serial or meta.fingerprint or meta.fiber or meta.cleaner or meta.shoe_profile or meta.tyre_profile
        or meta.blood_type or meta.paint or meta.gsr
    local parts = { meta.type or WhipEvidence.label(meta.kind) }
    if meta.ammo and meta.kind ~= 'reference' then parts[#parts + 1] = meta.ammo end
    if main and main ~= '???' then parts[#parts + 1] = main end
    local extra = meta.shoe_size or meta.tyre_width
    if extra and extra ~= '???' then parts[#parts + 1] = extra end
    if meta.age and meta.age ~= '???' then parts[#parts + 1] = meta.age end
    return { no = meta.marker, kind = meta.kind, text = table.concat(parts, ' · ') }
end

-- What the screen shows: idle (counts), running (progress), done (results for 10 minutes)
local function publish(id)
    local lab = labs[id]
    if not lab or not lab.containerId then return end
    local t = os.time()
    local st = { now = t, label = lab.def.label or id }
    if lab.running then
        local r = lab.running
        st.state, st.started, st.ends, st.count, st.guns, st.by, st.kinds = 'running', r.started, r.ends, #r.ids, #r.guns, r.byName, r.kinds
        st.items = r.list
    else
        local s = status(lab.containerId, function(addr) return Whip.core:StoreRead(addr) end)
        st.pending, st.analysed, st.total, st.newGuns = #s.pending, s.analysed, s.total, #s.newGuns
        local res = lab.result
        if res and t - res.at < 600 then
            st.state, st.finished, st.results, st.summary = 'done', res.at, res.lines, res.summary
        else
            st.state = 'idle'
        end
    end
    -- who is signed in at the device (lock screen without), and since when nobody is
    st.user, st.userLeft = lab.user, lab.userLeft
    -- just uploaded to a case: the screen plays it once, then shows the state below
    local up = lab.upload
    if up then st.upload = { at = up.at, case = up.case, n = up.n, left = up.left, by = up.by } end
    -- only when something changed (the clients count the time left themselves): no network traffic every 15 s
    st.now = nil
    local key = json.encode(st)
    if key == lab.published then return end
    lab.published = key
    st.now = t
    GlobalState['whip_evidence:lab:' .. id] = st
end

local function finish(id)
    local lab = labs[id]
    local job = lab and lab.running
    if not job then return end
    local addrOf = function(slot) return { kind = 'container', id = lab.containerId, slot = slot } end
    local c = contents(lab.containerId, function(addr) return Whip.core:StoreRead(addr) end)
    local who = Whip.core:GetPlayer({ charId = job.by })   -- the officer who started it, if still online
    local online = type(who) == 'table' and who.source

    -- 1. reveal the hidden values of the bags that are still there
    local stillThere = {}
    for _, bagId in ipairs(job.ids) do
        if c.bags[bagId] then stillThere[#stillThere + 1] = bagId end
    end
    local done = {}
    local labName = lab.def.label or id
    for bagId, secret in pairs(WhipEvidence.Data.pendingSecrets(stillThere)) do
        local addr = addrOf(c.bags[bagId].slot)
        secret.custody = WhipEvidence.custody(c.bags[bagId].meta.custody, L('custody_analysed', labName))
        if Whip.core:SetItemMetadata(addr, secret) then
            done[#done + 1] = bagId
            for k, v in pairs(secret) do c.bags[bagId].meta[k] = v end
            if online then Whip.core:LogActivity(who.source, 'evidence_analysed', { detail = lab.def.label or id, slotData = addr }) end
        end
    end
    WhipEvidence.Data.markAnalysed(done)
    local lines = {}
    for _, bagId in ipairs(done) do lines[#lines + 1] = resultLine(c.bags[bagId].meta) end

    -- 2. ballistics: a reference casing per new gun, then mark matching casings/bullets
    local guns = {}
    for _, g in ipairs(c.guns) do guns[g.serial] = g end
    local refs, noRoom = 0, 0
    for _, g in ipairs(job.guns) do
        local gun = guns[g.serial]
        if gun and not c.refs[g.serial] then
            local ok = Whip.core:StoreGive({ kind = 'container', id = lab.containerId }, WhipEvidence.Items.bag, 1, {
                evidence_id   = WhipEvidence.Data.newId(),
                kind          = 'reference',
                type          = L('kind_reference'),
                time          = os.date('%Y-%m-%d %H:%M:%S'),
                street        = lab.def.label or id,
                tested_on     = ('%s (%s)'):format(gunName(gun.item), gun.serial),
                ammo          = Config.Calibers[gun.item] or L('unknown'),
                weapon_serial = gun.serial,
                custody       = WhipEvidence.custody(nil, L('custody_testfired', labName)),
            }, 'test fired in ' .. labName)
            if ok then
                refs = refs + 1
                lines[#lines + 1] = { kind = 'reference', text = L('lab_line_reference', gunName(gun.item), gun.serial) }
            else
                noRoom = noRoom + 1
            end
        end
        -- the gun counts as analysed now: it can be uploaded to a case (MDT)
        if gun then Whip.core:SetItemMetadata(addrOf(gun.slot), { ballistics = L('ballistics_reference', labName) }) end
    end
    local matches = 0
    for _, bag in pairs(c.bags) do
        local m = bag.meta
        local gun = (m.kind == 'casing' or m.kind == 'bullet') and m.weapon_serial and guns[m.weapon_serial]
        if gun and m.ballistics == nil then
            if Whip.core:SetItemMetadata(addrOf(bag.slot), { ballistics = L('ballistics_match', gunName(gun.item)) }) then
                matches = matches + 1
                lines[#lines + 1] = { no = m.marker, kind = 'match', text = L('lab_line_match', m.type or '', m.marker or '', gunName(gun.item)) }
            end
        end
    end

    lab.running = nil
    Whip.core:UpdateContainer(lab.containerId, { locked = false, name = lab.def.label or id })
    local summary = L('lab_sum_bags', #done)
    if refs > 0 then summary = summary .. L('lab_sum_refs', refs) end
    if matches > 0 then summary = summary .. L('lab_sum_matches', matches) end
    lab.result = { at = os.time(), lines = lines, summary = summary }
    publish(id)

    if online then
        local text = L('lab_done_head', lab.def.label or id, #done)
        if refs > 0 then text = text .. L('lab_done_refs', refs) end
        if matches > 0 then text = text .. L('lab_done_matches', matches) end
        if noRoom > 0 then text = text .. L('lab_done_noroom', noRoom) end
        Whip.core:NotifyPlayer(who.source, text .. '.', matches > 0 and 'warning' or 'success', 8000)
    end
end

-- Chain of custody: every bag that goes into the analysis gets "In lab: <lab> · <officer>"
local function signLab(lab, ids, who)
    local want = {}
    for _, bagId in ipairs(ids) do want[bagId] = true end
    local c = contents(lab.containerId, function(addr) return exports.whip_core:StoreRead(addr) end)
    local what = L('custody_in_lab', lab.def.label or lab.def.id)
    for bagId, bag in pairs(c.bags) do
        if want[bagId] then
            exports.whip_core:SetItemMetadata({ kind = 'container', id = lab.containerId, slot = bag.slot },
                { custody = WhipEvidence.custody(bag.meta.custody, what, who) })
        end
    end
end

local function ensureLab(def)
    local stash = WhipEvidence.vec(def.stash)
    local container, why = Whip.core:EnsureContainer(keyOf(def.id), {
        name = def.label or def.id,
        x = stash.x, y = stash.y, z = stash.z,
        heading = (def.heading or 0) + 0.0,
        slots = def.slots or 10,
        maxWeight = (def.weight or 50) + 0.0,
        allowedItems = allowedItems(),
        requirements = { jobs = Config.PoliceJobs, onDuty = true },
    })
    if not container then return Whip.startProblem('lab %s: %s', def.id, tostring(why)) end

    -- check what WHIP really has under that key
    local real = Whip.core:GetContainer({ key = keyOf(def.id) })
    if type(real) ~= 'table' or real.containerId ~= container.containerId then
        return Whip.startProblem('lab %s: container check failed (key %s)', def.id, keyOf(def.id))
    end
    local off = #(vector3(real.x, real.y, real.z) - stash)
    if off > 1.0 then
        print(('[%s] lab %s: storage stands %.1f m from Config.Labs (moved in /whip?)'):format(WhipEvidence.Res, def.id, off))
    end

    local lab = labs[def.id] or {}
    lab.def, lab.containerId = def, real.containerId
    labs[def.id] = lab

    -- a restart during an analysis leaves it locked: open it again
    if not lab.running and (real.locked or real.name == busyName(def)) then
        Whip.core:UpdateContainer(lab.containerId, { locked = false, name = def.label or def.id })
    end
end

-- Empties a storage from an older version into the nearest lab, then deletes it
local function migrateLegacy()
    for _, key in ipairs(LEGACY_KEYS) do
        local old = Whip.core:GetContainer({ key = key })
        if type(old) == 'table' then
            local oldPos = vector3(old.x, old.y, old.z)
            local target, best
            for _, lab in pairs(labs) do
                local d = #(WhipEvidence.vec(lab.def.stash) - oldPos)
                if not best or d < best then target, best = lab, d end
            end
            local stash = Whip.core:StoreRead({ kind = 'container', id = old.containerId })
            local left = 0
            if target and type(stash) == 'table' then
                for slot in pairs(stash.items or {}) do
                    local ok = Whip.core:StoreMove(
                        { kind = 'container', id = old.containerId, slot = tonumber(slot) },
                        { kind = 'container', id = target.containerId },
                        { reason = 'lab storage moved to ' .. (target.def.label or target.def.id) })
                    if not ok then left = left + 1 end
                end
            end
            if left == 0 then
                Whip.core:DeleteContainer(old.containerId)
                print(('[%s] old lab storage "%s" emptied into "%s" and removed'):format(
                    WhipEvidence.Res, key, target and (target.def.label or target.def.id) or '-'))
            else
                Whip.startProblem('old lab storage "%s" (#%d) still holds %d item(s): no room in the new lab. Empty it in /whip -> Containers.',
                    key, old.containerId, left)
            end
        end
    end
end

-- One line per lab in the console, so you see at a glance what the device will find
local function report()
    for id, lab in pairs(labs) do
        local s = status(lab.containerId, function(addr) return Whip.core:StoreRead(addr) end)
        print(('[%s] lab %s: container #%d, %d bag(s): %d waiting, %d analysed, %d nothing to analyse, %d gun(s)'):format(
            WhipEvidence.Res, id, lab.containerId, s.total, #s.pending, s.analysed, s.nothing, s.guns))
    end
end

-- The screens: every 15 s (storage counts change when officers put bags in), and right after start / finish
CreateThread(function()
    while true do
        Wait(15000)
        for id in pairs(labs) do publish(id) end
    end
end)

WhipEvidence.Lab.publish = function(id) publish(id) end

-- Items went from the lab to a case: the screen shows the upload, then "Ready" once no analysed bag is left
function WhipEvidence.Lab.uploaded(id, caseId, moved, waiting, by)
    local lab = labs[id]
    if not lab or not lab.containerId then return end
    local s = status(lab.containerId, function(addr) return Whip.core:StoreRead(addr) end)
    if s.analysed == 0 then lab.result = nil end
    local mark = { at = os.time(), case = caseId, n = moved, left = waiting or 0, by = by }
    lab.upload = mark
    publish(id)
    SetTimeout(12000, function()
        if lab.upload ~= mark then return end
        lab.upload = nil
        publish(id)
    end)
end

-- Signed in at the monitor: the police officer on duty standing at the device (2.5 m). Every 2 s, cheap:
-- only labs with a screen, only players nearby. The screen locks when they leave.
local labelCache = {}   -- [source] = { label, at }
local function labelOf(src)
    local c = labelCache[src]
    if c and GetGameTimer() - c.at < 30000 then return c.label end
    local player = exports.whip_core:GetPlayer(src)
    local label = player and WhipEvidence.officerLabel(src, player) or nil
    labelCache[src] = { label = label, at = GetGameTimer() }
    return label
end
AddEventHandler('playerDropped', function() labelCache[source] = nil end)

CreateThread(function()
    while true do
        Wait(2000)
        local players
        for id, lab in pairs(labs) do
            if lab.def.screen and lab.def.device then
                players = players or GetPlayers()
                local at = WhipEvidence.vec(lab.def.device)
                local who, best
                for _, s in ipairs(players) do
                    local src = tonumber(s)
                    local ped = GetPlayerPed(src)
                    if ped and ped ~= 0 then
                        local d = #(GetEntityCoords(ped) - at)
                        if d <= 2.5 and (not best or d < best) and WhipEvidence.isPolice(src) then who, best = src, d end
                    end
                end
                local user = who and labelOf(who) or nil
                if user ~= lab.user then
                    if not user then lab.userLeft = os.time() end
                    lab.user = user
                    publish(id)
                end
            end
        end
    end
end)

-- Dev tools: finish every running analysis now. Returns how many.
function WhipEvidence.Lab.finishNow()
    local n = 0
    for id, lab in pairs(labs) do
        if lab.running then
            n = n + 1
            finish(id)
        end
    end
    return n
end

-- For the case upload at the device: the lab's storage, or nil while it analyses
function WhipEvidence.Lab.storage(id)
    local lab = labs[id]
    if not lab or not lab.containerId then return nil, L('unknown_lab') end
    if lab.running then return nil, L('lab_running_wait') end
    return lab.containerId, lab.def
end

function WhipEvidence.Lab.register()
    for _, def in ipairs(Config.Labs) do
        if def.id and def.stash and def.device then ensureLab(def) end
    end
    migrateLegacy()
    report()
    for id in pairs(labs) do publish(id) end

    -- Everything from the player's evidence cases into this lab's storage, in one go
    Whip.core:SecureEvent('whip_evidence:labUnload', {
        rateLimit = 2000,
        params = { { 'lab', 'key', 32 } },
        near = {
            at = function(_, _, id) return labs[id] and labs[id].def.device or nil end,
            range = 3.0,
        },
    }, function(source, player, id)
        if not WhipEvidence.can(source, 'evidence_lab') then return false, WhipEvidence.why(source, 'evidence_lab') end
        local containerId, why = WhipEvidence.Lab.storage(id)
        if not containerId then return false, why end
        if #WhipEvidence.Briefcase.all(source) == 0 then return false, L('no_evidence_case') end
        local done = exports.whip_core:Progress(source, WhipEvidence.bar('lab', {
            label = L('unloading_case'), duration = 1500, icon = 'pickup',
            disable = { move = true, combat = true, car = true },
            near = { coords = WhipEvidence.vec(labs[id].def.device), range = 3.0 },
        }))
        if not done or not exports.whip_core:IsSessionCurrent(source, player.session) then return false end
        local moved, full = WhipEvidence.Briefcase.unloadInto(source, containerId)
        if moved == 0 then return false, full and L('lab_full') or L('case_no_bags') end
        exports.whip_core:LogActivity(source, 'evidence_case_unloaded', { detail = ('%s: %d bag(s)'):format(id, moved) })
        publish(id)
        exports.whip_core:NotifyPlayer(source, L('lab_unloaded', moved,
            full and L('lab_unload_full') or ''), 'success')
    end)

    Whip.core:SecureEvent('whip_evidence:analyse', {
        rateLimit = 5000,
        params = { { 'lab', 'key', 32 } },
        near = {
            at = function(_, _, id) return labs[id] and labs[id].def.device or nil end,
            range = 3.0,
        },
    }, function(source, player, id)
        local lab = labs[id]
        if not lab then return false, L('lab_not_set_up') end
        if not WhipEvidence.isPolice(source) then return false, L('police_only_lab') end
        if not WhipEvidence.can(source, 'evidence_lab') then return false, WhipEvidence.why(source, 'evidence_lab') end
        if lab.running then
            return false, L('lab_running_left', math.max(1, math.ceil((lab.running.ends - os.time()) / 60)))
        end

        local s = status(lab.containerId, function(addr) return exports.whip_core:StoreRead(addr) end)
        if s.total == 0 and s.guns == 0 then return false, L('lab_empty') end
        if #s.pending == 0 and #s.newGuns == 0 then
            return false, L('lab_nothing_to_do', s.analysed, s.nothing)
        end

        local done = exports.whip_core:Progress(source, WhipEvidence.bar('lab', {
            label = L('starting_device'), duration = math.random(3000, 5000), icon = 'timer',
            disable = { move = true, combat = true, car = true },
            near = { coords = WhipEvidence.vec(lab.def.device), range = 3.0 },
        }))
        if not done then return false end
        if not exports.whip_core:IsSessionCurrent(source, player.session) then return false end
        if lab.running then return false, L('lab_running') end

        local lo = math.min(Config.LabMinMinutes, Config.LabMaxMinutes)
        local hi = math.max(Config.LabMinMinutes, Config.LabMaxMinutes)
        local minutes = math.random(lo, hi)
        local locked, why = exports.whip_core:UpdateContainer(lab.containerId, { locked = true, name = busyName(lab.def) })
        if not locked then return false, why end
        local token = WhipEvidence.Data.newId()
        local kinds, list = {}, {}
        local c = contents(lab.containerId, function(addr) return exports.whip_core:StoreRead(addr) end)
        for _, bagId in ipairs(s.pending) do
            local meta = c.bags[bagId] and c.bags[bagId].meta or {}
            local k = meta.kind or 'other'
            kinds[k] = (kinds[k] or 0) + 1
            if #list < 12 then list[#list + 1] = { k = k, n = meta.marker } end   -- the screen shows them one after another
        end
        lab.running = { started = os.time(), ends = os.time() + minutes * 60, ids = s.pending, guns = s.newGuns,
                        by = player.charId, byName = WhipEvidence.officerLabel(source, player), kinds = kinds, list = list, token = token }
        lab.result = nil
        signLab(lab, s.pending, WhipEvidence.officerLabel(source, player))
        publish(id)
        SetTimeout(math.max(1000, minutes * 60000), function()
            -- only this run (an admin may have finished it early and a new one started)
            if labs[id] and labs[id].running and labs[id].running.token == token then finish(id) end
        end)

        local what = L('lab_what_bags', #s.pending)
        if #s.newGuns > 0 then what = what .. L('lab_what_guns', #s.newGuns) end
        exports.whip_core:LogActivity(source, 'evidence_lab_started', { detail = (lab.def.label or id) .. ': ' .. what })
        exports.whip_core:NotifyPlayer(source, L('lab_started', what, minutes), 'success')
    end)
end
