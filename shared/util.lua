-- Shared helpers (client and server)
WhipEvidence = WhipEvidence or {}   -- shared/locale.lua already added L()

local RES = GetCurrentResourceName()
WhipEvidence.Res = RES

-- Item keys come from the folder name (WHIP wants the resource prefix)
WhipEvidence.Items = {
    bag    = RES .. '_bag',     -- evidence bag (filled)
    empty  = RES .. '_empty_bag', -- empty evidence bag (used up when Config.NeedEmptyBag is on)
    case   = RES .. '_case',    -- evidence case (30 compartments)
    photo  = RES .. '_photo',   -- crime scene photo
    kit    = RES .. '_kit',     -- forensics kit
    laser  = RES .. '_laser',   -- laser pointer
    pliers = RES .. '_pliers',  -- pliers
    wipe   = RES .. '_wipe',    -- cleaning cloth
    bleach = RES .. '_bleach',  -- bleach (cleans blood and prints around you, leaves a cleaned spot)
    file   = RES .. '_file',    -- metal file (files a weapon's serial off)
}

WhipEvidence.GsrFlag = RES .. ':gsr'
WhipEvidence.PhotoChunk = 10000   -- characters per part when a photo travels (small parts, no kicks)

WhipEvidence.PhaseColor = {
    green  = '#60a5fa',   -- too fresh (blue; the key names are the old phase names)
    yellow = '#3cdc50',   -- ready (green)
    red    = '#c0392b',   -- gone soon
}

function WhipEvidence.debug(fmt, ...)
    if not Config.Debug then return end
    local ok, text = pcall(string.format, fmt, ...)
    print(('[%s] %s'):format(RES, ok and text or tostring(fmt)))
end

-- Rank permissions: the lowest rank level in Config.Permissions (server/jobs.lua checks, the client hints)
WhipEvidence.PERMISSIONS = {
    { 'evidence_scan', 'Scan (flashlight, camera)' }, { 'evidence_photo', 'Crime scene photos' },
    { 'evidence_collect', 'Collect evidence' }, { 'evidence_gsr', 'GSR tests' },
    { 'evidence_vehicle', 'Collect vehicle traces' }, { 'evidence_laser', 'Laser pointer' },
    { 'evidence_sign', 'Sign for evidence' }, { 'evidence_clear', 'Clear away single traces' },
    { 'evidence_upload', 'Upload to a case (MDT)' }, { 'evidence_locker', 'Open case lockers' },
    { 'evidence_body', 'Examine bodies' }, { 'evidence_dust', 'Dust weapons for prints' },
    { 'evidence_release', 'Release crime scenes' }, { 'evidence_lab', 'Run lab analyses' },
    { 'evidence_locker_take', 'Take items out of case lockers' }, { 'evidence_case_close', 'Close cases' },
}

function WhipEvidence.permsActive()
    return Config.UsePermissions ~= false
end

-- may a rank of this level do it?
function WhipEvidence.levelAllows(level, permission)
    if not WhipEvidence.permsActive() then return true end
    local need = tonumber((Config.Permissions or {})[permission]) or 1
    return (tonumber(level) or 0) >= need
end

function WhipEvidence.isPoliceJob(key)
    if not key then return false end
    for _, job in ipairs(Config.PoliceJobs) do
        if job == key then return true end
    end
    return false
end

-- A Progress bar's options with the animation and prop of Config.Animations[key] (prop left out with Config.HandProps = false)
function WhipEvidence.bar(key, opts)
    local a = (Config.Animations or {})[key]
    if a then
        opts.anim = opts.anim or a.anim
        if a.prop and Config.HandProps ~= false then opts.prop = a.prop end
    end
    return opts
end

function WhipEvidence.isIgnoredWeapon(item)
    for _, name in ipairs(Config.IgnoreWeapons) do
        if name == item then return true end
    end
    return false
end

-- Name of an evidence type in the server's language (locales: kind_<type>), else the config label
function WhipEvidence.label(kind)
    local text = L('kind_' .. tostring(kind))
    if text ~= 'kind_' .. tostring(kind) then return text end
    local p = Config.Props[kind]
    return p and p.label or kind
end

-- How old something looks on the scan and photos (Config.AgeShown): "12 min old", "fresh", ... or nil (not shown)
function WhipEvidence.ageWords(seconds)
    local mode = Config.AgeShown or 'rough'
    if mode == 'off' then return nil end
    local m = math.floor(math.max(0, seconds or 0) / 60)
    if mode == 'exact' then return L('chip_old', m < 1 and '<1 min' or ('%d min'):format(m)) end
    if m < 5 then return L('age_fresh') end
    if m < 20 then return L('age_while') end
    if m < 45 then return L('age_older') end
    return L('age_old')
end

function WhipEvidence.vec(t)
    if type(t) == 'vector3' then return t end
    return vector3(t.x + 0.0, t.y + 0.0, t.z + 0.0)
end

function WhipEvidence.inNoEvidenceZone(coords)
    for _, zone in ipairs(Config.NoEvidenceZones) do
        if zone.coords and #(coords - WhipEvidence.vec(zone.coords)) <= (zone.radius or 0) then
            return true
        end
    end
    return false
end

-- The ring skill check from Config.SkillCheck, clamped so WHIP always accepts it
function WhipEvidence.skillCheck()
    local s = Config.SkillCheck or {}
    local pieces = math.max(1, math.floor(tonumber(s.pieces) or 4))
    local widest = math.min(math.max(1, math.floor(tonumber(s.widest) or 2)), pieces)
    local narrowest = math.min(math.max(1, math.floor(tonumber(s.narrowest) or 2)), widest)
    return { level = {
        pieces = pieces, widest = widest, narrowest = narrowest,
        parts = math.max(1, math.floor(tonumber(s.parts) or 3)),
        msPerPart = math.max(200, math.floor(tonumber(s.msPerPart) or 1000)),
    } }
end

-- The prop of a lab's screen, or nil for 'none' (a monitor already in the map)
function WhipEvidence.screenModel(lab)
    local m = type(lab) == 'table' and lab.screenModel
    if m == nil or m == '' then return 'prop_monitor_w_large' end   -- labs saved before screenModel existed
    if type(m) ~= 'string' or m == 'none' then return nil end
    return m
end
