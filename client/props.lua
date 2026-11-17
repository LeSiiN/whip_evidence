-- Client: evidence props. Each client spawns local props (never networked, no collision) only within
-- Config.RenderDistance and deletes them when it walks away. Nothing is ever attached to vehicles.
WhipEvidence.Props = {}

local spawned = {}       -- [id] = entity
local MAX_PER_PASS = 12  -- spread big batches over several passes, no hitch

function WhipEvidence.Props.remove(id)
    local ent = spawned[id]
    if ent then
        spawned[id] = nil
        if DoesEntityExist(ent) then DeleteEntity(ent) end
    end
end

function WhipEvidence.Props.clear()
    for id in pairs(spawned) do WhipEvidence.Props.remove(id) end
end

local function spawn(ev)
    local p = Config.Props[ev.kind]
    if not p then return end
    local hash = Whip.core:LoadModel(p.model)
    if not hash then return end
    -- removed or already spawned while the model loaded
    if spawned[ev.id] or not WhipEvidence.Ev.get(ev.id) then
        SetModelAsNoLongerNeeded(hash)
        return
    end
    local c = ev.coords
    -- CreateObject (not NoOffset): the z offsets in Config.Props are made for it
    local obj = CreateObject(hash, c.x, c.y, c.z + (p.z or 0.0), false, false, false)
    SetModelAsNoLongerNeeded(hash)
    if not obj or obj == 0 then return end
    SetEntityRotation(obj, p.rotX + 0.0, p.rotY + 0.0, (ev.heading or 0.0) + 0.0, 2, true)
    FreezeEntityPosition(obj, true)
    SetEntityCollision(obj, false, false)
    SetEntityInvincible(obj, true)
    SetEntityVisible(obj, true, false)
    ResetEntityAlpha(obj)
    SetEntityLodDist(obj, math.floor(Config.RenderDistance) + 10)
    spawned[ev.id] = obj
end

-- Streamer: only looks again after moving 4 m or when the list changed
local dirty = true
function WhipEvidence.Props.dirty() dirty = true end

CreateThread(function()
    local lastPos
    while true do
        if WhipEvidence.Ev.count() == 0 and not next(spawned) then
            Wait(2000)
        else
            local pos = GetEntityCoords(PlayerPedId())
            if dirty or not lastPos or #(pos - lastPos) > 4.0 then
                lastPos, dirty = pos, false
                local hide = Config.RenderDistance + 10.0
                local made = 0
                -- only the cells around the player
                WhipEvidence.Ev.eachNear(pos, Config.RenderDistance, function(ev)
                    if not spawned[ev.id] then
                        if made < MAX_PER_PASS then
                            spawn(ev)
                            made = made + 1
                        else
                            dirty = true   -- the rest next pass
                        end
                    end
                end)
                -- spawned props are few: check each one
                for id, ent in pairs(spawned) do
                    local ev = WhipEvidence.Ev.get(id)
                    if not ev or #(ev.coords - pos) > hide then WhipEvidence.Props.remove(id) end
                end
            end
            Wait(1000)
        end
    end
end)

-- Our props go before anything else unloads
AddEventHandler('onResourceStop', function(res)
    if res == WhipEvidence.Res then WhipEvidence.Props.clear() end
end)
