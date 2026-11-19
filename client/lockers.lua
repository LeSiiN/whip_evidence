-- Client: the evidence locker's case list (html/index.html #cases). A click on a case opens its locker;
-- the search field also takes a case ID that is not in the list. All from this resource's own case lockers.
WhipEvidence.Lockers = {}

local open = false
local PAGE = 15
local mode, labId = 'locker', nil   -- what a pick does: open the locker, or upload the lab's evidence to the case

local screen = Whip.padScreen({
    buttons = { 'a', 'b', 'x', 'up', 'down' },
    onButton = function(cmd, down)
        if down then SendNUIMessage({ action = 'casesPad', cmd = cmd }) end
    end,
})

local function close(tellPage)
    if not open then return end
    open = false
    screen:close()
    Whip.core:SetScreenOpen(false, 'cases')
    if tellPage then SendNUIMessage({ action = 'cases', open = false }) end
end

-- the locker is asked for once this list is gone (a screen still up would make the game decline the locker)
local function openCase(caseId)
    caseId = tostring(caseId or ''):gsub('^%s*#?', ''):gsub('%s+$', '')
    if caseId == '' then return end
    CreateThread(function()
        Wait(200)
        local untilAt = GetGameTimer() + 2000
        while Whip.core:IsAnyScreenOpen() and GetGameTimer() < untilAt do Wait(100) end
        TriggerServerEvent('whip_evidence:openLocker', caseId)
    end)
end

-- opts: nil = evidence locker; { upload = labId } = upload that lab's analysed evidence to the picked case
function WhipEvidence.Lockers.pick(opts)
    if open then return end
    mode, labId = (opts and opts.upload) and 'upload' or 'locker', opts and opts.upload or nil
    local r = Whip.core:Callback('whip_evidence:lockerCases', mode, labId or '')
    if type(r) ~= 'table' then return end
    if r.error then return WhipEvidence.notify(r.error, 'error') end
    open = true
    Whip.core:SetScreenOpen(true, 'cases')
    local pad = screen:open()
    SendNUIMessage({
        action = 'cases', open = true, pad = pad == true, page = PAGE, now = r.now, cases = r.cases or {},
        texts = {
            kicker = mode == 'upload' and L('upload_kicker') or L('lockers_kicker'),
            title = mode == 'upload' and L('upload_title') or L('lockers_title'),
            search = mode == 'upload' and L('upload_search') or L('lockers_search'),
            more = L('lockers_more'), empty = mode == 'upload' and L('upload_empty') or L('lockers_empty'),
            typed = mode == 'upload' and L('upload_typed') or L('lockers_open_typed'),
            items = L('lockers_items'), taken = L('lockers_taken'), closed = L('lockers_closed'),
            close = pad and L('rep_close_pad') or L('rep_close'),
            hint = pad and L('lockers_hint_pad') or L('lockers_hint'),
            ago_now = L('ago_now'), ago_min = L('ago_min'), ago_hours = L('ago_hours'), ago_days = L('ago_days'),
        },
    })
end

RegisterNUICallback('casesPick', function(data, cb)
    cb('ok')
    close(false)
    local id = type(data) == 'table' and tostring(data.id or ''):gsub('^%s*#?', ''):gsub('%s+$', '') or ''
    if mode == 'upload' then
        if id ~= '' and labId then TriggerServerEvent('whip_evidence:labUpload', labId, id) end
        return
    end
    openCase(id)
end)

RegisterNUICallback('casesClose', function(_, cb)
    cb('ok')
    close(false)
end)

-- typing in the search field: the pad leaves the keys to it
RegisterNUICallback('casesTyping', function(data, cb)
    cb('ok')
    if open then screen:typing(type(data) == 'table' and data.on == true) end
end)

AddEventHandler('onResourceStop', function(res)
    if res == WhipEvidence.Res then close(true) end
end)
AddEventHandler('whip_core:player:logout', function() close(true) end)
