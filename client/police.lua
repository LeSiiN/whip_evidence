-- Client: police prompts (GSR test on a player, vehicle traces at the door, lab devices, evidence lockers)
-- canInteract = WhipEvidence.can(...): only ranks with the permission see the option (the server checks again)

local GSR_ID = 'gsr_test'
local gsrActive = false

-- aimBox costs a ray every frame: only active while on duty as police
local function setGsrPrompt(on)
    if on == gsrActive then return end
    gsrActive = on
    if not on then
        Whip.core:RemoveAction(GSR_ID)
        return
    end
    local function here() return WhipEvidence.street(GetEntityCoords(PlayerPedId())) end
    Whip.core:AddAction({
        id = GSR_ID, at = { aimBox = 'ped' },
        label = L('forensics'), icon = 'target', reach = 2.0,
        require = { job = Config.PoliceJobs, onDuty = true, item = WhipEvidence.Items.kit },
        canInteract = function(ctx) return ctx.player ~= nil end,
        options = {
            { id = 'gsr', label = L('gsr_test'), icon = 'target',
              canInteract = function(ctx) return ctx.player ~= nil and not ctx.player.isDead and WhipEvidence.can('evidence_gsr') end,
              onSelect = function(ctx) TriggerServerEvent('whip_evidence:gsrTest', ctx.player.serverId, here()) end },
            { id = 'swab', label = L('opt_swab'), icon = 'target',
              canInteract = function(ctx) return ctx.player ~= nil and WhipEvidence.can('evidence_collect') end,
              onSelect = function(ctx) TriggerServerEvent('whip_evidence:bloodSwab', ctx.player.serverId, here()) end },
        },
    })
end

AddStateBagChangeHandler('whipJob', ('player:%d'):format(GetPlayerServerId(PlayerId())), function(_, _, value)
    setGsrPrompt(WhipEvidence.isPoliceJob(value))
end)

---------------------------------------------------------------- Vehicle: doors open while it is examined

local openCars = {}

local function openDoors(car)
    for door = 0, 5 do SetVehicleDoorOpen(car, door, false, false) end
end

local function closeDoors(car)
    if DoesEntityExist(car) then
        for door = 0, 5 do SetVehicleDoorShut(car, door, false) end
    end
end

local function vehicleAction(event, car)
    if not NetworkGetEntityIsNetworked(car) then return end
    local net = NetworkGetNetworkIdFromEntity(car)
    openCars[net] = car
    openDoors(car)
    if event == 'whip_evidence:collectVehicle' then
        TriggerServerEvent(event, net, WhipEvidence.street(GetEntityCoords(PlayerPedId())))
    else
        TriggerServerEvent(event, net)
    end
    SetTimeout(20000, function()
        if openCars[net] then closeDoors(openCars[net]); openCars[net] = nil end
    end)
end

RegisterNetEvent('whip_evidence:client:vehicleDone', function(net)
    local car = openCars[net]
    openCars[net] = nil
    if car then closeDoors(car) end
end)

---------------------------------------------------------------- Release a crime scene (F1 wheel)

local function nearby()
    local pos = GetEntityCoords(PlayerPedId())
    local list = {}
    WhipEvidence.Ev.eachNear(pos, Config.ReleaseRadius, function(ev) list[#list + 1] = ev end)
    return list
end

local function numbers(list)
    table.sort(list, function(a, b) return (a.no or 0) < (b.no or 0) end)
    local out = {}
    for i = 1, math.min(#list, 10) do out[i] = '#' .. (list[i].no or '?') end
    if #list > 10 then out[#out + 1] = ('+%d'):format(#list - 10) end
    return table.concat(out, ' ')
end

-- Everything photographed: one question. Some without a photo: choose, and a second, louder question for "everything".
local function releaseScene()
    local list = nearby()
    if #list == 0 then return WhipEvidence.notify(L('nothing_to_clear'), 'info') end
    local missing = {}
    for _, ev in ipairs(list) do if not ev.photo then missing[#missing + 1] = ev end end
    local done = #list - #missing

    if #missing == 0 then
        local yes = Whip.core:Confirm({
            title = L('release_scene'),
            message = L('release_all_photo', #list, math.floor(Config.ReleaseRadius)),
            yes = L('release'), no = L('cancel'),
        })
        if yes then TriggerServerEvent('whip_evidence:release', 'photo') end
        return
    end

    local options = {}
    if done > 0 then options[#options + 1] = { value = 'photo', label = L('release_opt_photo', done) } end
    options[#options + 1] = { value = 'show', label = L('release_opt_show') }
    options[#options + 1] = { value = 'all', label = L('release_opt_all', #list) }
    local r = Whip.core:Input(L('release_missing', #missing, #list), {
        { label = L('no_photo_yet', numbers(missing)), type = 'select', options = options, default = options[1].value },
    })
    local choice = r and r[1]
    if choice == 'photo' then
        TriggerServerEvent('whip_evidence:release', 'photo')
    elseif choice == 'show' then
        local ids = {}
        for _, ev in ipairs(missing) do ids[#ids + 1] = ev.id end
        WhipEvidence.Scan.highlight(ids, 60)
        WhipEvidence.notify(L('release_blink', numbers(missing)), 'info')
    elseif choice == 'all' then
        local sure = Whip.core:Confirm({
            title = L('release_destroy_title', #missing),
            message = L('release_destroy_msg', numbers(missing)),
            yes = L('release_everything'), no = L('back'),
        })
        if sure then TriggerServerEvent('whip_evidence:release', 'all') end
    end
end

---------------------------------------------------------------- Register

Whip.register(function()
    gsrActive = false
    setGsrPrompt(WhipEvidence.isPoliceOnDuty())

    Whip.core:AddAction({
        id = 'release_scene', at = { radial = true }, icon = 'target',
        label = L('release_scene'),
        description = L('release_desc'),
        require = { job = Config.PoliceJobs, onDuty = true },
        canInteract = function()
            return WhipEvidence.can('evidence_release') and WhipEvidence.Ev.near(GetEntityCoords(PlayerPedId()), Config.ReleaseRadius)
        end,
        onSelect = function() CreateThread(releaseScene) end,
    })

    for _, part in ipairs({ 'door_dside_f', 'door_pside_f' }) do
        Whip.core:AddAction({
            id = 'veh_' .. part, at = { vehiclePart = part }, label = L('traces'),
            options = {
                { id = 'collect', label = L('collect_traces'), icon = 'target', press = true,
                  require = { job = Config.PoliceJobs, onDuty = true, item = WhipEvidence.Items.kit },
                  canInteract = function() return WhipEvidence.can('evidence_vehicle') end,
                  onSelect = function(ctx) vehicleAction('whip_evidence:collectVehicle', ctx.entity) end },
                { id = 'wipe', label = L('clean_interior'), icon = 'fail', press = true,
                  require = { item = WhipEvidence.Items.wipe },
                  onSelect = function(ctx) vehicleAction('whip_evidence:wipeVehicle', ctx.entity) end },
            },
        })
    end

    -- one device per lab; it analyses that lab's storage only
    for _, lab in ipairs(Config.Labs) do
        if lab.id and lab.device then
            local id = lab.id
            Whip.core:AddAction({
                id = 'lab:' .. id, at = { coords = WhipEvidence.vec(lab.device) },
                label = lab.label or id, icon = 'timer', reach = 2.0,
                require = { job = Config.PoliceJobs, onDuty = true },
                -- in the order they are used: unload, analyse, upload
                options = {
                    -- every bag from your evidence case into this lab's storage
                    { id = 'unload', label = L('unload_case'), icon = 'pickup', holdMs = 1000, press = true,
                      canInteract = function()
                          return WhipEvidence.can('evidence_lab') and Whip.core:HasItem(WhipEvidence.Items.case)
                      end,
                      onSelect = function() TriggerServerEvent('whip_evidence:labUnload', id) end },
                    { id = 'analyse', label = L('analyse'), icon = 'timer', holdMs = 1000, press = true,
                      canInteract = function() return WhipEvidence.can('evidence_lab') end,
                      onSelect = function() TriggerServerEvent('whip_evidence:analyse', id) end },
                    -- everything analysed in this lab's storage goes into a case's locker
                    { id = 'upload', label = L('upload_case'), icon = 'pickup', holdMs = 1000, press = true,
                      canInteract = function() return WhipEvidence.can('evidence_upload') end,
                      onSelect = function()
                          local r = Whip.core:Input(L('upload_case'), {
                              { label = L('case_id_mdt'), type = 'text', required = true },
                          })
                          local caseId = r and r[1] and tostring(r[1]):gsub('^%s*#?', ''):gsub('%s+$', '')
                          if caseId and caseId ~= '' then TriggerServerEvent('whip_evidence:labUpload', id, caseId) end
                      end },
                },
            })
        end
    end

    -- evidence lockers: type a case ID, its locker opens (every case at every locker)
    for _, locker in ipairs(Config.Lockers or {}) do
        if locker.id and locker.coords then
            Whip.core:AddAction({
                id = 'locker:' .. locker.id, at = { coords = WhipEvidence.vec(locker.coords) },
                label = locker.label or L('evidence_lockers'), icon = 'pickup', reach = 2.0, press = true,
                require = { job = Config.PoliceJobs, onDuty = true },
                canInteract = function() return WhipEvidence.can('evidence_locker') end,
                onSelect = function()
                    CreateThread(function()
                        local r = Whip.core:Input(L('open_locker'), {
                            { label = L('case_id'), type = 'text', required = true },
                        })
                        local caseId = r and r[1] and tostring(r[1]):gsub('^%s*#?', ''):gsub('%s+$', '')
                        if caseId and caseId ~= '' then TriggerServerEvent('whip_evidence:openLocker', caseId) end
                    end)
                end,
            })
        end
    end
end)
