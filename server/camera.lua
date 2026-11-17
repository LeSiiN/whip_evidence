-- Scan mode with WHIP's camera item: when someone uses it, watch whether it is still in their
-- hand (held props tag 'camera') and tell their client, so the evidence overlay can show.

local CAMERA_ITEM = 'camera'   -- WHIP's own camera item
local watching = {}   -- [source] = true

local function watch(source)
    if watching[source] then return end
    watching[source] = true
    TriggerClientEvent('whip_evidence:client:camera', source, true)
    CreateThread(function()
        while watching[source] do
            Wait(1000)
            if not Whip.isReady() or not exports.whip_core:IsPlayerLoaded(source)
                or exports.whip_core:GetHeldPropsTag(source) ~= 'camera' then
                break
            end
        end
        watching[source] = nil
        TriggerClientEvent('whip_evidence:client:camera', source, false)
    end)
end

AddEventHandler('whip_core:item:used', function(e)
    if GetInvokingResource() ~= 'whip_core' or type(e) ~= 'table' then return end
    if e.item == CAMERA_ITEM and e.source then
        -- the camera goes into the hand right after the use
        SetTimeout(500, function() watch(e.source) end)
    end
end)

AddEventHandler('playerDropped', function()
    watching[source] = nil
end)

-- After a restart: whoever already has the camera in hand gets the scan back
Whip.register(function()
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        if src and exports.whip_core:IsPlayerLoaded(src) and exports.whip_core:GetHeldPropsTag(src) == 'camera' then
            watch(src)
        end
    end
end)
