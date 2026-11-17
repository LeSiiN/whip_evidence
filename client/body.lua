-- Client: traces on yourself. Reports which gloves you wear and when you change clothes (the server keeps
-- the rings on the HUD: blood on you, glove condition). Worn gloves let more prints through.

WhipEvidence.Client.bloody = false
local loaded = false
local lastGlove, lastClothes

-- Do the gloves stop this print? Worn gloves leak more (GloveLeakChance new -> GloveTornLeak torn).
function WhipEvidence.glovesStopPrint()
    if not WhipEvidence.wearingGloves() then return false end
    TriggerServerEvent('whip_evidence:gloveTouch')
    local stat = Whip.core:GetStat('evidence_gloves')
    local cond = (type(stat) == 'number' and stat > 0) and (stat - 1) or 100
    local new, torn = Config.GloveLeakChance or 5, Config.GloveTornLeak or 60
    local leak = new + (torn - new) * (1 - cond / 100)
    return math.random(1, 100) > leak
end

AddEventHandler('whip_core:player:loaded', function() loaded = true end)
AddEventHandler('whip_core:player:logout', function()
    loaded, lastGlove, lastClothes = false, nil, nil
    WhipEvidence.Client.bloody = false
end)

CreateThread(function()
    Wait(2000)
    if next(Whip.core:GetPlayer() or {}) then loaded = true end   -- resource restarted while playing
    while true do
        Wait(2000)
        if loaded then
            local ped = PlayerPedId()
            local glove = WhipEvidence.wearingGloves() and GetPedDrawableVariation(ped, 3) or -1
            if glove ~= lastGlove then
                lastGlove = glove
                TriggerServerEvent('whip_evidence:gloves', glove)
            end
            local clothes = ('%d:%d:%d:%d'):format(GetPedDrawableVariation(ped, 11), GetPedTextureVariation(ped, 11),
                GetPedDrawableVariation(ped, 8), GetPedDrawableVariation(ped, 4))
            if lastClothes and clothes ~= lastClothes and WhipEvidence.Client.bloody then
                TriggerServerEvent('whip_evidence:changedClothes')
            end
            lastClothes = clothes
        end
    end
end)

Whip.register(function()
    lastGlove = nil   -- a whip_core restart: tell the server again
    Whip.core:OnStatChanged('evidence_bloody', function(value)
        WhipEvidence.Client.bloody = (tonumber(value) or 0) > 0
    end, nil, { now = true })
end)
