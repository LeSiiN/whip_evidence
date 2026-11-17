-- Client: viewing a crime scene photo item (html/index.html shows it as a polaroid with the evidence log)

local open = false
local incoming = nil   -- { id, parts, list }: the picture arriving in parts
local waiting = nil    -- a picture that was complete before the viewer was up

local function close(tellPage)
    if not open then return end
    open = false
    incoming, waiting = nil, nil
    SetNuiFocus(false, false)
    Whip.core:SetScreenOpen(false, 'photo')
    if tellPage then SendNUIMessage({ action = 'photoClose' }) end
end

-- The picture comes after the meta, in parts (whip_evidence:client:viewPhotoPart)

RegisterNetEvent('whip_evidence:client:viewPhotoPart', function(photoId, index, data)
    local inc = incoming
    if not inc or inc.id ~= photoId or index ~= #inc.list + 1 or type(data) ~= 'string' then return end
    inc.list[index] = data
    if index < inc.parts then
        if index % 10 == 0 then SendNUIMessage({ action = 'photoLoading', done = index, total = inc.parts }) end
        return
    end
    incoming = nil
    local image = table.concat(inc.list)
    if open then SendNUIMessage({ action = 'photoImage', image = image }) else waiting = image end
end)

RegisterNetEvent('whip_evidence:client:viewPhoto', function(data, parts)
    if type(data) ~= 'table' then return end
    parts = tonumber(parts) or 0
    incoming = parts > 0 and { id = data.photo_id, parts = parts, list = {} } or nil
    waiting = nil
    CreateThread(function()
        -- "View photo" comes from the inventory: close it first, then take the screen
        if Whip.core:IsInventoryOpen() then
            Whip.core:CloseInventory()
            Wait(150)
        end
        open = true
        SetNuiFocus(true, true)
        Whip.core:SetScreenOpen(true, 'photo')
        SendNUIMessage({ action = 'photo', data = data, loading = parts > 0, ui = {
            size = tonumber(WhipEvidence.ui('viewerSize')) or 62,
            log = WhipEvidence.ui('viewerLog') or 'right',
            stamp = WhipEvidence.ui('viewerStamp') ~= false,
        } })
        if waiting then
            SendNUIMessage({ action = 'photoImage', image = waiting })
            waiting = nil
        end
    end)
end)

RegisterNUICallback('photoClose', function(_, cb)
    close(false)
    cb('ok')
end)

AddEventHandler('whip_core:player:logout', function()
    close(true)
end)

AddEventHandler('onResourceStop', function(res)
    if res == WhipEvidence.Res then close(true) end
end)
