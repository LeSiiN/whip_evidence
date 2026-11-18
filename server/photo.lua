-- Crime scene photos: with the camera in hand, a key takes a real screenshot (WHIP's TakeScreenshot,
-- with the markers in it). The photo is an item that lists every marked piece of evidence and car in it;
-- the picture itself goes into the database (whip_evidence_photos), the item only holds its id.
-- Pictures travel in small parts (WhipEvidence.PhotoChunk) with a short pause between them: one big
-- event gets players kicked ("packet overflow").
WhipEvidence.Photo = {}

local pending = {}   -- [source] = { id, charId, at }: the picture we wait for after a photo was made
local MAX_BYTES = 4000 * 1024   -- hard cap (Config.Photo.MaxKB decides below it)
local CHUNK = WhipEvidence.PhotoChunk
local MAX_PARTS = math.ceil(MAX_BYTES / CHUNK)
local PICTURE = '^data:image/[jw][pe][eb]?[gp];base64,[%w%+/=]+$'

local I = WhipEvidence.Items
local ACT_VIEW = WhipEvidence.Res .. ':photoview'
local ACT_TEXT = WhipEvidence.Res .. ':phototext'
local MAX_ENTRIES, MAX_CARS = 60, 6

-- "3× Casing" (works in every language)
local function count(n, word)
    return ('%d× %s'):format(n, word)
end

-- "12 traces: 5 casings, 3 blood, 2 bullets · 1 vehicle"
local function sceneText(entries, cars, bodies)
    local counts, order = {}, {}
    for _, e in ipairs(entries) do
        if not counts[e.t] then counts[e.t] = 0; order[#order + 1] = e.t end
        counts[e.t] = counts[e.t] + 1
    end
    local parts = {}
    for _, t in ipairs(order) do parts[#parts + 1] = count(counts[t], t) end
    local text = L('scene_traces', #entries)
    if #parts > 0 then text = text .. ': ' .. table.concat(parts, ', ') end
    if #cars > 0 then text = text .. L('scene_vehicles', #cars) end
    if bodies and #bodies > 0 then text = text .. L('scene_bodies', #bodies) end
    return text
end

-- What a car shows on the photo: "Blood, 2 casings, GSR"
local function carText(s)
    local parts = {}
    if s.blood > 0 then parts[#parts + 1] = WhipEvidence.label('blood') end
    if s.casing > 0 then parts[#parts + 1] = count(s.casing, WhipEvidence.label('casing')) end
    if s.bullet > 0 then parts[#parts + 1] = L('car_bullet_holes', s.bullet) end
    if s.gsr then parts[#parts + 1] = 'GSR' end
    if s.prints then parts[#parts + 1] = L('possible_prints') end
    return table.concat(parts, ', ')
end

-- Text for the clipboard (MDT reports)
local function photoText(m)
    local lines = {
        L('photo_text_head', m.photo_id or '?', m.case or '-'),
        L('photo_text_sub', m.street or '?', m.time or '?', m.taken_by or '?'),
    }
    for _, e in ipairs(type(m.entries) == 'table' and m.entries or {}) do
        local line = ('#%s %s'):format(e.n or '?', e.t or '?')
        if e.s then line = line .. L('photo_text_age', e.s, e.a or 0) end
        lines[#lines + 1] = line .. (' · %d m'):format(e.d or 0)
    end
    for _, c in ipairs(type(m.cars) == 'table' and m.cars or {}) do
        lines[#lines + 1] = L('photo_text_car', c.p or '?', c.t or '')
    end
    for _, b in ipairs(type(m.bodies) == 'table' and m.bodies or {}) do
        lines[#lines + 1] = ('%s %s · %s · %d m'):format(b.n or '?', b.t or '?', b.i or '', b.d or 0)
    end
    return table.concat(lines, '\n')
end

function WhipEvidence.Photo.registerItem(actSign)
    Whip.core:RegisterItem(I.photo, {
        name = L('item_photo'), desc = L('item_photo_desc'),
        weight = 0.01, type = 'evidence', stack = false, usable = false,
        metaFields = {
            { key = 'case',     label = L('f_case') },
            { key = 'street',   label = L('f_street') },
            { key = 'time',     label = L('f_time') },
            { key = 'scene',    label = L('f_scene') },
            { key = 'taken_by', label = L('f_taken_by') },
            { key = 'custody',  label = L('f_custody') },
        },
        contextOptions = {
            { action = ACT_VIEW, label = L('opt_view'), order = 1, anywhere = true },
            { action = ACT_TEXT, label = L('opt_text'), order = 2, anywhere = true },
            { action = actSign, label = L('opt_sign'), order = 4, anywhere = true,
              require = WhipEvidence.req('evidence_sign') },
        },
    })

    -- Meta first (the viewer opens at once), then the picture in parts
    Whip.core:RegisterContextAction(ACT_VIEW, function(source, player, slotData)
        local m = slotData.metadata or {}
        local image = WhipEvidence.Data.loadPhoto(m.photo_id)
        image = type(image) == 'string' and image or nil
        local parts = image and math.ceil(#image / CHUNK) or 0
        TriggerClientEvent('whip_evidence:client:viewPhoto', source, {
            photo_id = m.photo_id, case = m.case, street = m.street, time = m.time, scene = m.scene,
            taken_by = m.taken_by, entries = m.entries, cars = m.cars, bodies = m.bodies, custody = m.custody,
        }, parts)
        if not image then return end
        CreateThread(function()
            for i = 1, parts do
                if GetPlayerPing(source) == 0 then return end
                TriggerClientEvent('whip_evidence:client:viewPhotoPart', source, m.photo_id, i, image:sub((i - 1) * CHUNK + 1, i * CHUNK))
                Wait(50)   -- about 200 KB/s: never floods the connection
            end
        end)
    end)

    Whip.core:RegisterContextAction(ACT_TEXT, function(source, player, slotData)
        TriggerClientEvent('whip_evidence:client:copy', source, photoText(slotData.metadata or {}), L('photo'))
    end)
end

function WhipEvidence.Photo.register()
    Whip.core:SecureEvent('whip_evidence:photo', {
        rateLimit = 3000,
        params = {
            { 'ids', 'list', { 'id', 'key', 16 }, MAX_ENTRIES },
            { 'cars', 'list', { 'net', 'int', 1, 2147483647 }, MAX_CARS },
            { 'street', 'string', 80, 'Unknown' },
            { 'picture', 'bool', false },   -- the client has a screenshot to send
            { 'bodies', 'list', { 'id', 'key', 16 }, MAX_CARS },
        },
    }, function(source, player, ids, cars, street, picture, bodies)
        if not WhipEvidence.can(source, 'evidence_photo') then return false, L('photo_not_allowed') end
        if exports.whip_core:GetHeldPropsTag(source) ~= 'camera' then return false, L('need_camera') end
        local pos = GetEntityCoords(GetPlayerPed(source))
        local range = Config.SeeDistance + 10.0
        local now = os.time()

        local entries, shown = {}, {}
        for _, id in ipairs(ids) do
            local ev = WhipEvidence.Evidence.get(id)
            local dist = ev and #(ev.coords - pos)
            if dist and dist <= range then
                shown[#shown + 1] = id
                entries[#entries + 1] = {
                    n = ev.no, t = WhipEvidence.label(ev.kind), d = math.floor(dist + 0.5),
                    s = WhipEvidence.Evidence.phaseName(ev.phase), a = math.floor((now - ev.created) / 60),
                }
            end
        end
        table.sort(entries, function(a, b) return (a.n or 0) < (b.n or 0) end)

        local carList = {}
        for _, net in ipairs(cars) do
            local ent = NetworkGetEntityFromNetworkId(net)
            if ent and ent ~= 0 and DoesEntityExist(ent) and #(GetEntityCoords(ent) - pos) <= range then
                local s, plate = WhipEvidence.Vehicles.photoInfo(ent)
                if s then carList[#carList + 1] = { p = plate or '?', t = carText(s) } end
            end
        end
        local bodyRows, bodiesShown = WhipEvidence.Bodies.photoRows(bodies or {}, pos, range)
        if #entries == 0 and #carList == 0 and #bodyRows == 0 then return false, L('photo_nothing') end

        local takenBy = WhipEvidence.officerLabel(source, player)
        local meta = {
            photo_id = WhipEvidence.Data.newId(),
            street   = street,
            time     = os.date('%Y-%m-%d %H:%M:%S'),
            scene    = sceneText(entries, carList, bodyRows),
            taken_by = takenBy,
            entries  = entries,
            cars     = carList,
            bodies   = #bodyRows > 0 and bodyRows or nil,
        }
        meta.custody = WhipEvidence.custody(nil, L('custody_taken'), takenBy)
        if not exports.whip_core:IsSessionCurrent(source, player.session) then return false end
        local ok, why = exports.whip_core:AddItem(source, I.photo, 1, meta, 'Crime scene photo')
        if not ok then return false, why end
        WhipEvidence.Evidence.markPhotographed(shown, meta.photo_id)
        WhipEvidence.Bodies.markPhotographed(bodiesShown, meta.photo_id)
        if picture then
            pending[source] = { id = meta.photo_id, charId = player.charId, at = os.time() }
            TriggerClientEvent('whip_evidence:client:photoUpload', source, meta.photo_id)
        end
        exports.whip_core:LogActivity(source, 'evidence_photo', { detail = street .. ': ' .. meta.scene })
        exports.whip_core:NotifyPlayer(source, L('photo_taken', meta.scene), 'success')
    end)

    -- The screenshot itself, in parts, right after the photo item was made.
    -- Only the picture we asked for, within two minutes, in order, a JPG/WebP data URL.
    Whip.core:SecureEvent('whip_evidence:photoBegin', {
        rateLimit = 1000,
        params = { { 'photo', 'key', 16 }, { 'parts', 'int', 1, MAX_PARTS }, { 'bytes', 'int', 1, MAX_BYTES } },
    }, function(source, player, photoId, parts, bytes)
        local want = pending[source]
        if not want or want.id ~= photoId or want.charId ~= player.charId then return false end
        if bytes > (Config.Photo.MaxKB or 2500) * 1024 or parts ~= math.ceil(bytes / CHUNK) then
            pending[source] = nil
            return false, L('photo_too_big')
        end
        want.parts, want.bytes, want.list = parts, bytes, {}
    end)

    Whip.core:SecureEvent('whip_evidence:photoPart', {
        rateLimit = 30, burst = 6,
        params = { { 'photo', 'key', 16 }, { 'index', 'int', 1, MAX_PARTS }, { 'data', 'string', CHUNK, '' } },
    }, function(source, player, photoId, index, data)
        local want = pending[source]
        if not want or not want.list or want.id ~= photoId or want.charId ~= player.charId then return false end
        if index ~= #want.list + 1 or os.time() - want.at > 120 then
            pending[source] = nil
            return false
        end
        want.list[index] = data
        if index < want.parts then return end
        pending[source] = nil
        local image = table.concat(want.list)
        if #image ~= want.bytes or not image:find(PICTURE) then return false end
        WhipEvidence.Data.savePhoto(photoId, player.charId, image)
        exports.whip_core:NotifyPlayer(source, L('photo_saved'), 'success', 2500)
    end)
end

AddEventHandler('playerDropped', function()
    pending[source] = nil
end)
