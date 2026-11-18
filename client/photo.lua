-- Client: viewing a crime scene photo item (html/index.html shows it as a polaroid with the evidence log)

local open = false

-- Controller (Whip.padScreen): A zoom, B back, LB/RB zoom out/in, D-pad up/down scroll the list, right stick moves the zoomed picture
local screen = Whip.padScreen({
    buttons = { 'a', 'b', 'up', 'down', 'lb', 'rb' },
    stick = false,
    onButton = function(cmd, down, rep)
        if down then SendNUIMessage({ action = 'photoPad', cmd = cmd }) end
    end,
    onFrame = function()
        local dx, dy = GetDisabledControlNormal(0, 1), GetDisabledControlNormal(0, 2)
        if math.abs(dx) > 0.08 or math.abs(dy) > 0.08 then
            SendNUIMessage({ action = 'photoStick', dx = dx, dy = dy })
        end
    end,
})
local incoming = nil   -- { id, parts, list }: the picture arriving in parts
local waiting = nil    -- a picture that was complete before the viewer was up

local function close(tellPage)
    if not open then return end
    open = false
    incoming, waiting = nil, nil
    screen:close()
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
        Whip.core:SetScreenOpen(true, 'photo')
        local pad = screen:open()
        SendNUIMessage({ action = 'photo', data = data, loading = parts > 0, pad = pad == true, ui = {
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
