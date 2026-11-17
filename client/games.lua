-- Client: runs a forensic minigame (shared/games.lua registers them, html/games.js draws them).
-- Mouse on the page; a controller moves the cursor with the right stick and grabs with A (Whip.padScreen).

local active = nil   -- { token, result }
local screen = Whip.padScreen({
    buttons = { 'a', 'b' },
    releases = { a = true },
    stick = false,
    onButton = function(cmd, down)
        if cmd == 'b' and down then
            if active then active.result = { passed = false, why = 'cancelled' } end
            return
        end
        SendNUIMessage({ action = 'gameButton', cmd = cmd, down = down })
    end,
    onFrame = function()
        -- right stick moves the cursor on the page
        local dx, dy = GetDisabledControlNormal(0, 1), GetDisabledControlNormal(0, 2)
        if math.abs(dx) > 0.08 or math.abs(dy) > 0.08 then
            SendNUIMessage({ action = 'gameStick', dx = dx, dy = dy })
        end
    end,
})

local function close()
    screen:close()
    Whip.core:SetScreenOpen(false, 'game')
    SendNUIMessage({ action = 'gameClose' })
end

function WhipEvidence.Games.play(name, difficulty, token)
    if active then return false, 'busy' end
    active = { token = token }
    Whip.core:SetScreenOpen(true, 'game')
    local pad = screen:open()
    SendNUIMessage({ action = 'game', game = name, difficulty = difficulty, token = token, pad = pad })
    local untilAt = GetGameTimer() + 29000   -- the level's timeoutMs is 30 s
    while not active.result and GetGameTimer() < untilAt do Wait(50) end
    local result = active.result or { passed = false, why = 'timeout' }
    active = nil
    close()
    return result.passed == true, result.passed and nil or (result.why or 'failed')
end

function WhipEvidence.Games.cancel(token)
    if active and (token == nil or active.token == token) then
        active.result = { passed = false, why = 'cancelled' }
    end
end

-- the page says how it went
RegisterNUICallback('gameDone', function(data, cb)
    cb('ok')
    if active and type(data) == 'table' and data.token == active.token then
        local why = data.why
        if why ~= 'failed' and why ~= 'cancelled' and why ~= 'timeout' then why = 'failed' end
        active.result = { passed = data.passed == true, why = why }
    end
end)

AddEventHandler('whip_core:player:logout', function() WhipEvidence.Games.cancel() end)
AddEventHandler('onResourceStop', function(res)
    if res == WhipEvidence.Res and active then close() end
end)
