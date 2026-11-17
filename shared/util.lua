-- Shared helpers (client and server)
WhipEvidence = {}

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
}

WhipEvidence.GsrFlag = RES .. ':gsr'
WhipEvidence.PhotoChunk = 10000   -- characters per part when a photo travels (small parts, no kicks)

WhipEvidence.PhaseColor = {
    green  = '#3cdc50',
    yellow = '#ffa500',
    red    = '#c0392b',
}

function WhipEvidence.debug(fmt, ...)
    if not Config.Debug then return end
    local ok, text = pcall(string.format, fmt, ...)
    print(('[%s] %s'):format(RES, ok and text or tostring(fmt)))
end

-- Rank permissions are in force when Config.UsePermissions is on and every police job declared them
-- (the server sets this after start; see server/jobs.lua)
function WhipEvidence.permsActive()
    return GlobalState['whip_evidence:perms'] == true
end

function WhipEvidence.isPoliceJob(key)
    if not key then return false end
    for _, job in ipairs(Config.PoliceJobs) do
        if job == key then return true end
    end
    return false
end

function WhipEvidence.isIgnoredWeapon(item)
    for _, name in ipairs(Config.IgnoreWeapons) do
        if name == item then return true end
    end
    return false
end

function WhipEvidence.label(kind)
    local p = Config.Props[kind]
    return p and p.label or kind
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
