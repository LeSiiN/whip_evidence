-- Client: gunshot residue on yourself. The amount is the stat 'evidence_gsr' (a ring on the HUD).
-- Wash it off in water (F1 wheel); swimming or standing in the rain long enough washes it off by itself.

local function watchWater()
    local untilAt = GetGameTimer() + Config.WashSeconds * 1000 + 1500
    while GetGameTimer() < untilAt do
        Wait(250)
        if not IsEntityInWater(PlayerPedId()) then
            TriggerServerEvent('whip_evidence:washAbort')
            return
        end
    end
end

-- Rain (on foot, outside) and swimming: counted here, checked by the server. Sleeps while you have no GSR.
CreateThread(function()
    local rain, swim = 0, 0
    while true do
        if not WhipEvidence.Client.gsr and not WhipEvidence.Client.bloody then
            rain, swim = 0, 0
            Wait(3000)
        else
            Wait(2000)
            local ped = PlayerPedId()
            local outside = not IsPedInAnyVehicle(ped, false) and GetInteriorFromEntity(ped) == 0
            rain = (WhipEvidence.Client.gsr and outside and GetRainLevel() > 0.2) and rain + 2 or 0
            swim = IsPedSwimming(ped) and swim + 2 or 0
            if rain >= (Config.GsrRainSeconds or 60) then
                rain = 0
                TriggerServerEvent('whip_evidence:gsrWeather', 'rain')
            elseif swim >= (Config.WashSeconds or 15) then
                swim = 0
                TriggerServerEvent('whip_evidence:gsrWeather', 'swim')
            end
        end
    end
end)

Whip.register(function()
    Whip.core:OnStatChanged('evidence_gsr', function(value)
        WhipEvidence.Client.gsr = (tonumber(value) or 0) > 0
    end, nil, { now = true })

    Whip.core:AddAction({
        id = 'wash', at = { radial = true }, icon = 'info',
        label = L('wash_self'),
        description = L('wash_self_desc'),
        canInteract = function()
            return (WhipEvidence.Client.gsr or WhipEvidence.Client.bloody) and IsEntityInWater(PlayerPedId())
        end,
        onSelect = function()
            TriggerServerEvent('whip_evidence:wash')
            watchWater()
        end,
    })
end)
