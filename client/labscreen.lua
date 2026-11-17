-- Client: the monitor at each lab (Config.Labs[].screen). A DUI page (html/lab.html) is drawn straight onto the
-- screen in the world (DrawTexturedPoly): sharp up close, works on any model. Model per lab: screenModel.
-- Where the picture sits on the model is fitted automatically; admins fine-tune it in /w -> Forensics.
-- The state comes from the server in GlobalState['whip_evidence:lab:<id>'].
-- Cost: one check per second; drawing only while you stand within 15 m of a screen.

local PAGE = ('nui://%s/html/lab.html'):format(WhipEvidence.Res)
local TXD, TEX = 'whip_evidence_lab', 'screen'
local W, H = 1280, 1024   -- the page uses the top part that matches the screen's shape (16:9 = 720 px, 5:4 = 1024 px)
local SPAWN, DRAW = 40.0, 15.0
local FITS = 'whip_evidence:screenfits'

local props = {}        -- [labId] = entity
local received = {}     -- [labId] = GetGameTimer() when its state last changed
local dui, up, waiting = nil, false, {}
local active = nil      -- lab drawn now
local editing = nil     -- the fit being adjusted (admin tool)
local hidden = false    -- clean screen
local lastPaint, lastPageH

local function send(msg)
    if up then SendDuiMessage(dui, json.encode(msg)) else waiting[#waiting + 1] = msg end
end

local function ensureDui()
    if dui then return end
    local ok, handle = pcall(CreateDui, PAGE, W, H)
    if not ok or not handle then return end
    dui = handle
    CreateRuntimeTextureFromDuiHandle(CreateRuntimeTxd(TXD), TEX, GetDuiHandle(dui))
    local mine = dui
    CreateThread(function()
        local untilAt = GetGameTimer() + 10000
        while dui == mine and not IsDuiAvailable(mine) and GetGameTimer() < untilAt do Wait(50) end
        if dui ~= mine then return end
        Wait(250)
        up = true
        for _, m in ipairs(waiting) do SendDuiMessage(dui, json.encode(m)) end
        waiting = {}
    end)
    send({ action = 'logo', src = Config.LabScreenLogo })
end

local function releaseDui()
    if dui then DestroyDui(dui) end
    dui, up, waiting, lastPaint, lastPageH = nil, false, {}, nil, nil
end

---------------------------------------------------------------- Where the picture sits

local modelOf = WhipEvidence.screenModel

-- A first guess from the model's size: the front face (-Y), a thin bezel, 16:9, at the top
-- (monitors have their stand below the screen)
local function autoFit(lab)
    local model = modelOf(lab)
    if not model or not IsModelInCdimage(joaat(model)) then
        return { x = 0.0, y = 0.0, z = 0.0, w = 0.9, h = 0.506, rot = 0.0, back = false }
    end
    local min, max = GetModelDimensions(joaat(model))
    local bezel = (max.x - min.x) * 0.035
    local w = (max.x - min.x) - 2 * bezel
    local h = w * 9 / 16
    local room = (max.z - min.z) - 2 * bezel
    if h > room then h = room; w = h * 16 / 9 end
    return { x = (min.x + max.x) / 2, y = min.y - 0.006, z = max.z - bezel - h / 2, w = w, h = h, rot = 0.0, back = false }
end

local function fitFor(lab)
    if editing and editing.lab == lab.id and editing.fit then return editing.fit end
    local saved = (GlobalState[FITS] or {})[lab.id]
    if type(saved) == 'table' and saved.model == (modelOf(lab) or 'none') then return saved end
    return autoFit(lab)
end

-- lab frame (position + heading of the screen) <-> world
local function toWorld(o, heading, x, y, z)
    local r = math.rad(heading)
    local c, s = math.cos(r), math.sin(r)
    return vector3(o.x + x * c - y * s, o.y + x * s + y * c, o.z + z)
end

local function toLocal(o, heading, p)
    local r = math.rad(heading)
    local c, s = math.cos(r), math.sin(r)
    local dx, dy = p.x - o.x, p.y - o.y
    return { x = dx * c + dy * s, y = -dx * s + dy * c, z = p.z - o.z }
end

local function cross(a, b) return vector3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x) end
local function dot3(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
local function norm(a) local l = #a; return l > 0 and a / l or vector3(0.0, 0.0, 1.0) end

-- The picture's corners in the world: top left, top right, bottom left (bottom right follows)
local function corners(lab, f)
    local o, hd = WhipEvidence.vec(lab.screen), (lab.screenHeading or 0.0) + 0.0
    if f.tl and f.tr and f.bl then   -- picked in game (fit tool)
        return toWorld(o, hd, f.tl.x, f.tl.y, f.tl.z), toWorld(o, hd, f.tr.x, f.tr.y, f.tr.z), toWorld(o, hd, f.bl.x, f.bl.y, f.bl.z)
    end
    -- the first guess from the model (or a fit from before 4.0): centre, size, turn
    local rot = math.rad(f.rot or 0.0)
    local side = (f.back and -1.0 or 1.0) * f.w / 2
    local dx, dy = math.cos(rot) * side, math.sin(rot) * side
    local top, bottom = f.z + f.h / 2, f.z - f.h / 2
    return toWorld(o, hd, f.x - dx, f.y - dy, top), toWorld(o, hd, f.x + dx, f.y + dy, top), toWorld(o, hd, f.x - dx, f.y - dy, bottom)
end

-- UVs as floats: a whole number would reach the native as the wrong value (one dark pixel stretched over the screen)
local function tri(a, b, c, ua, va, ub, vb, uc, vc)
    DrawTexturedPoly(a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z, 255, 255, 255, 255, TXD, TEX,
        ua + 0.0, va + 0.0, 1.0, ub + 0.0, vb + 0.0, 1.0, uc + 0.0, vc + 0.0, 1.0)
end

local function drawQuad(tl, tr, bl)
    local br = tr + bl - tl
    -- the page fits the screen's shape: as many page pixels high as the screen is (width 1280)
    local pageH = math.floor(math.max(360, math.min(H, W * #(bl - tl) / math.max(0.01, #(tr - tl)))) + 0.5)
    if pageH ~= lastPageH then
        lastPageH = pageH
        send({ action = 'size', h = pageH })
    end
    local v = pageH / H
    -- a polygon shows one side only: both windings, the model hides the back
    tri(tl, bl, br, 0, 0, 0, v, 1, v)
    tri(tl, br, tr, 0, 0, 1, v, 1, 0)
    tri(tl, br, bl, 0, 0, 1, v, 0, v)
    tri(tl, tr, br, 0, 0, 1, 0, 1, v)
end

local function drawScreen(lab)
    drawQuad(corners(lab, fitFor(lab)))
end

---------------------------------------------------------------- Props

local function spawnProp(lab)
    local model = modelOf(lab)
    if not model then props[lab.id] = false return end
    local hash = joaat(model)
    if not IsModelInCdimage(hash) or not Whip.core:LoadModel(hash) then
        print(('[whip_evidence] lab %s: screen model "%s" not found, drawing without it'):format(lab.id, model))
        props[lab.id] = false
        return
    end
    local p = WhipEvidence.vec(lab.screen)
    local ent = CreateObject(hash, p.x, p.y, p.z, false, false, false)
    SetEntityHeading(ent, (lab.screenHeading or 0.0) + 0.0)
    FreezeEntityPosition(ent, true)
    SetModelAsNoLongerNeeded(hash)
    props[lab.id] = ent
end

local function deleteProp(id)
    local ent = props[id]
    if ent and DoesEntityExist(ent) then DeleteObject(ent) end
    props[id] = nil
end

local function labById(id)
    for _, lab in ipairs(Config.Labs or {}) do
        if lab.id == id then return lab end
    end
end

---------------------------------------------------------------- Page

-- the lab's state for the page (time left counted from when it arrived)
local function paintFor(id)
    local st = GlobalState['whip_evidence:lab:' .. id]
    if type(st) ~= 'table' then return end
    local msg = { action = 'paint', state = st.state, label = st.label, pending = st.pending, analysed = st.analysed,
                  newGuns = st.newGuns, count = st.count, guns = st.guns, by = st.by, kinds = st.kinds,
                  summary = st.summary, results = st.results, finished = st.finished }
    if st.state == 'running' and st.ends and st.now then
        local since = GetGameTimer() - (received[id] or GetGameTimer())
        msg.leftMs = math.max(0, (st.ends - st.now) * 1000 - since)
        msg.totalMs = math.max(1000, (st.ends - (st.started or st.now)) * 1000)
    end
    local key = json.encode({ id, st.state, st.ends, st.pending, st.analysed, st.newGuns, st.finished, st.label })
    if key ~= lastPaint then
        lastPaint = key
        send(msg)
    end
end

local function drawLoop()
    CreateThread(function()
        while active do
            local lab = labById(active)
            if lab and up and not hidden then drawScreen(lab) end
            Wait(0)
        end
    end)
end

-- a lab's state changed: remember when (time left is counted from here) and repaint if it is on screen
for _, lab in ipairs(Config.Labs or {}) do
    if lab.id and lab.screen then
        AddStateBagChangeHandler('whip_evidence:lab:' .. lab.id, 'global', function()
            received[lab.id] = GetGameTimer()
            if active == lab.id then SetTimeout(0, function() paintFor(lab.id) end) end
        end)
    end
end

AddEventHandler('whip_core:ui:cleanScreen', function(e)
    hidden = type(e) == 'table' and e.on and e.world or false
end)

CreateThread(function()
    while true do
        local pos = GetEntityCoords(PlayerPedId())
        local nearest, nearestD
        for _, lab in ipairs(Config.Labs or {}) do
            if lab.id and lab.screen then
                local d = #(pos - WhipEvidence.vec(lab.screen))
                if d < SPAWN and props[lab.id] == nil then spawnProp(lab)
                elseif d > SPAWN + 20.0 and props[lab.id] ~= nil then deleteProp(lab.id) end
                if d < DRAW and (not nearestD or d < nearestD) then nearest, nearestD = lab.id, d end
            end
        end
        if editing then nearest = editing.lab end
        if nearest then
            ensureDui()
            if active ~= nearest then
                lastPaint = nil
                local was = active
                active = nearest
                if not was then drawLoop() end
            end
            paintFor(active)
            Wait(1000)
        else
            if active then
                active = nil
                SetTimeout(30000, function() if not active then releaseDui() end end)
            end
            Wait(next(props) and 1000 or 2500)
        end
    end
end)

---------------------------------------------------------------- Fit tool (admins, /w -> Forensics)

-- Aim at the corners of the monitor's picture area and click: top left, top right, bottom left.
-- Works for any monitor, tilted or not, any shape. Mouse: left click picks, right... is aiming, so
-- Backspace takes the last corner back, Esc (or Backspace with none) cancels.
local STEPS = { 'TOP LEFT', 'TOP RIGHT', 'BOTTOM LEFT' }

local function aimPoint()
    local from = GetFinalRenderedCamCoord()
    local rot = GetFinalRenderedCamRot(2)
    local rx, rz = math.rad(rot.x), math.rad(rot.z)
    local dir = vector3(-math.sin(rz) * math.abs(math.cos(rx)), math.cos(rz) * math.abs(math.cos(rx)), math.sin(rx))
    local ray = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z,
        from.x + dir.x * 10.0, from.y + dir.y * 10.0, from.z + dir.z * 10.0, 1 | 16, PlayerPedId(), 7)
    local _, hit, pos = GetShapeTestResult(ray)
    if hit == 1 or hit == true then return pos, from end
    return nil, from
end

local function dot(p, r, g, b)
    DrawMarker(28, p.x, p.y, p.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.012, 0.012, 0.012, r, g, b, 230,
        false, false, 2, false, nil, nil, false)
end

local function help(text)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, false, -1)
end

-- Step 2: fine-tuning. The keys come through the page (html/index.html, NUI focus), the game can't swallow them.
local fitKeys, fitDone = {}, nil

local function V(t) return vector3(t.x + 0.0, t.y + 0.0, t.z + 0.0) end
local function T(v) return { x = v.x, y = v.y, z = v.z } end

RegisterNUICallback('fitKeys', function(data, cb)
    fitKeys = type(data) == 'table' and type(data.held) == 'table' and data.held or {}
    cb('ok')
end)

-- bigger / smaller around the middle, keeps the shape
RegisterNUICallback('fitSize', function(data, cb)
    local f = editing and editing.fit
    if f and type(data) == 'table' then
        local k = data.slow and 1.004 or 1.02
        if data.dir ~= 1 then k = 1 / k end
        local tl, tr, bl = V(f.tl), V(f.tr), V(f.bl)
        local c = (tr + bl) / 2
        f.tl, f.tr, f.bl = T(c + (tl - c) * k), T(c + (tr - c) * k), T(c + (bl - c) * k)
    end
    cb('ok')
end)

RegisterNUICallback('fitDone', function(data, cb)
    local how = type(data) == 'table' and data.how
    fitDone = (how == 'save' or how == 'redo') and how or 'cancel'
    cb('ok')
end)

local function fineTune()
    fitKeys, fitDone = {}, nil
    SetNuiFocus(true, false)
    Whip.core:SetScreenOpen(true, 'fit')
    SendNUIMessage({ action = 'fit', open = true })
    while editing and editing.fit and fitDone == nil do
        local f = editing.fit
        local tl, tr, bl = V(f.tl), V(f.tr), V(f.bl)
        local right, down, out = norm(tr - tl), norm(bl - tl), V(editing.out)
        local step = (fitKeys.shift and 0.02 or 0.10) * GetFrameTime()   -- metres per second
        local d = vector3(0.0, 0.0, 0.0)
        if fitKeys.right then d = d + right * step end
        if fitKeys.left then d = d - right * step end
        if fitKeys.up then d = d - down * step end
        if fitKeys.down then d = d + down * step end
        if fitKeys.w then d = d - out * step * 0.5 end   -- into the monitor
        if fitKeys.s then d = d + out * step * 0.5 end   -- out of it
        if #d > 0 then f.tl, f.tr, f.bl = T(tl + d), T(tr + d), T(bl + d) end
        Wait(0)
    end
    SendNUIMessage({ action = 'fit', open = false })
    SetNuiFocus(false, false)
    Whip.core:SetScreenOpen(false, 'fit')
    return fitDone or 'cancel'
end

-- Step 1: aim at three corners. Returns true once they are picked (editing.fit), false when cancelled.
local function pickCorners(lab)
    local o, hd = WhipEvidence.vec(lab.screen), (lab.screenHeading or 0.0) + 0.0
    Whip.core:BlockControls('whip_evidence_fit', { groups = { 'combat' }, controls = { 177, 194, 200, 202, 322 } })
    local picked, done = {}, nil
    while editing and done == nil do
        local p, from = aimPoint()
        DrawRect(0.5, 0.5, 0.0025, 0.004, 255, 255, 255, 230)   -- crosshair
        if p then dot(p, 74, 222, 128) end
        for _, q in ipairs(picked) do dot(q, 250, 204, 21) end
        help(('Aim at the ~y~%s~s~ corner of the picture area and click (or E).~n~Backspace: back · Esc: cancel'):format(STEPS[#picked + 1]))
        if (IsDisabledControlJustPressed(0, 24) or IsDisabledControlJustPressed(0, 38)) and p then
            picked[#picked + 1] = p
            if #picked == 3 then
                -- in local coordinates, just in front of the glass (towards where you stand)
                local l, cam = {}, V(toLocal(o, hd, from))
                for i, q in ipairs(picked) do l[i] = V(toLocal(o, hd, q)) end
                local n = norm(cross(l[2] - l[1], l[3] - l[1]))
                if dot3(n, cam - l[1]) < 0 then n = n * -1.0 end
                editing.out = T(n)
                editing.fit = { tl = T(l[1] + n * 0.004), tr = T(l[2] + n * 0.004), bl = T(l[3] + n * 0.004) }
                done = true
            end
        elseif IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 194) then
            if #picked == 0 then done = false else picked[#picked] = nil end
        elseif IsDisabledControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 202) or IsDisabledControlJustPressed(0, 322) then
            done = false
        end
        Wait(0)
    end
    Whip.core:UnblockControls('whip_evidence_fit')
    return done == true
end

function WhipEvidence.fitScreen()
    if editing then return end
    local pos, lab, best = GetEntityCoords(PlayerPedId()), nil, DRAW
    for _, l in ipairs(Config.Labs or {}) do
        if l.id and l.screen then
            local d = #(pos - WhipEvidence.vec(l.screen))
            if d < best then lab, best = l, d end
        end
    end
    if not lab then
        WhipEvidence.notify(('No lab screen within %d m.'):format(math.floor(DRAW)), 'error')
        return
    end
    editing = { lab = lab.id }
    CreateThread(function()
        -- the /w menu has to be gone first (it holds mouse and keys)
        local untilAt = GetGameTimer() + 3000
        while IsNuiFocused() and GetGameTimer() < untilAt do Wait(50) end
        Wait(150)
        local result = 'cancel'
        while editing do
            if not pickCorners(lab) then break end
            result = fineTune()
            if result ~= 'redo' then break end
            editing.fit = nil
        end
        local fit = editing and editing.fit
        editing = nil
        if result == 'save' and fit then
            TriggerServerEvent('whip_evidence:screenFit', lab.id, { tl = fit.tl, tr = fit.tr, bl = fit.bl })
        else
            WhipEvidence.notify('Screen not changed.', 'info')
        end
    end)
end

AddEventHandler('onResourceStop', function(res)
    if res ~= WhipEvidence.Res then return end
    if editing and editing.fit then SetNuiFocus(false, false) end
    active, editing = nil, nil
    for id in pairs(props) do deleteProp(id) end
    releaseDui()
end)
