-- Client: helpers, sync, clipboard
WhipEvidence.Client = { gsr = false }

-- Arms without gloves (freemode ped, component 3)
local BARE_ARMS = {
    male = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 18, 26, 52, 53, 54, 55, 56, 57, 58, 59,
             60, 61, 62, 112, 113, 114, 118, 125, 132 },
    female = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 19, 59, 60, 61, 62, 63, 64, 65, 66, 67,
               68, 69, 70, 71, 129, 130, 131, 135, 142, 149, 153, 157, 161, 165 },
}
local bare = { male = {}, female = {} }
for sex, list in pairs(BARE_ARMS) do
    for _, n in ipairs(list) do bare[sex][n] = true end
end
local MALE, FEMALE = GetHashKey('mp_m_freemode_01'), GetHashKey('mp_f_freemode_01')

function WhipEvidence.wearingGloves()
    local ped = PlayerPedId()
    local model = GetEntityModel(ped)
    local set = (model == MALE and bare.male) or (model == FEMALE and bare.female)
    if not set then return false end
    return not set[GetPedDrawableVariation(ped, 3)]
end

function WhipEvidence.isPoliceOnDuty()
    return WhipEvidence.isPoliceJob(LocalPlayer.state.whipJob)
end

-- Client hint of the rank permission (the server checks again). Asked often (prompts, scan):
-- the answer is kept until the job, rank or duty changes, or 10 s pass.
local canCache, canJob, canAt = {}, nil, 0

local function resetCan() canCache = {} end
AddEventHandler('whip_core:job:listChanged', resetCan)
AddEventHandler('whip_core:job:clockedOn', resetCan)
AddEventHandler('whip_core:job:clockedOff', resetCan)

function WhipEvidence.can(permission)
    local job = LocalPlayer.state.whipJob
    if not WhipEvidence.isPoliceJob(job) then return false end
    if not WhipEvidence.permsActive() then return true end
    local now = GetGameTimer()
    if job ~= canJob or now - canAt > 10000 then
        canCache, canJob, canAt = {}, job, now
    end
    local v = canCache[permission]
    if v == nil then
        v = Whip.core:HasJobPermission(job, permission) == true
        canCache[permission] = v
    end
    return v
end

function WhipEvidence.notify(text, kind)
    exports.whip_core:Notify(text, kind or 'info', 5000)
end

function WhipEvidence.street(coords)
    local h1, h2 = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local main = GetStreetNameFromHashKey(h1)
    local cross = h2 ~= 0 and GetStreetNameFromHashKey(h2) or ''
    if cross ~= '' then return main .. ', ' .. cross end
    return main ~= '' and main or L('unknown')
end

-- Optional: no evidence while in FFA mode (lsl-ffa)
function WhipEvidence.blocked()
    if GetResourceState('lsl-ffa') ~= 'started' then return false end
    local ok, inFfa = pcall(function() return exports['lsl-ffa']:IsInFFA() end)
    return ok and inFfa == true
end

-- The floor under a spot: a ray from just above it straight down. Starting higher would land
-- on whatever is overhead (an awning, a balcony, a car roof), so it never starts more than 0.6 m up.
function WhipEvidence.ground(pos)
    local top = pos.z + 0.6
    local ray = StartExpensiveSynchronousShapeTestLosProbe(pos.x, pos.y, top, pos.x, pos.y, pos.z - 6.0, 1 | 16, PlayerPedId(), 0)
    local _, hit, at = GetShapeTestResult(ray)
    if hit == 1 and at then return vector3(pos.x, pos.y, at.z) end
    local found, z = GetGroundZFor_3dCoord(pos.x, pos.y, top, false)
    if found and z <= top then return vector3(pos.x, pos.y, z) end
    return pos
end

---------------------------------------------------------------- Sync

local function sync()
    local list, gsr, vehicles = Whip.core:Callback('whip_evidence:sync')
    if type(list) == 'table' then WhipEvidence.Ev.reset(list, vehicles) end
    WhipEvidence.Client.gsr = gsr == true
end

AddEventHandler('whip_core:player:loaded', function()
    CreateThread(sync)
end)

AddEventHandler('whip_core:player:logout', function()
    WhipEvidence.Ev.reset({})
    WhipEvidence.Client.gsr = false
end)


Whip.register(function()
    CreateThread(function()
        if exports.whip_core:IsPlayerLoaded() then sync() end
    end)
end)

---------------------------------------------------------------- Clipboard

RegisterNetEvent('whip_evidence:client:copy', function(text, what)
    if type(text) ~= 'string' then return end
    SendNUIMessage({ action = 'copy', text = text })
    -- long texts (a photo's list) only by name in the notification
    local short = text:find('\n') and '' or (': ' .. (#text > 60 and text:sub(1, 57) .. '...' or text))
    WhipEvidence.notify(L('copied', what or L('text'), short), 'success')
end)

-- The NUI page asks for its texts once (locales/, server language)
RegisterNUICallback('texts', function(_, cb)
    cb(WhipEvidence.texts())
end)
