-- Client: page in /w (developer mode only). The server checks every action itself.
-- Levels: top (clean up, test tools), cases (every case locker), one case (open, close, delete).

local level, caseList, picked = 'top', {}, nil

local function loadCases()
    CreateThread(function()
        caseList = Whip.core:Callback('whip_evidence:adminCases') or {}
        Whip.core:RefreshDevPage('evidence')
    end)
end

RegisterNetEvent('whip_evidence:client:adminCasesChanged', loadCases)

local function caseById(id)
    for _, c in ipairs(caseList) do
        if c.id == id then return c end
    end
end

local function topRows()
    return { rows = {
        { sep = 'Evidence' },
        { id = 'wipe10', label = 'Remove evidence within 10 m', icon = 'target' },
        { id = 'wipe25', label = 'Remove evidence within 25 m', icon = 'target' },
        { id = 'wipe50', label = 'Remove evidence within 50 m', icon = 'target' },
        { id = 'clear', label = 'Remove ALL evidence', icon = 'warning', desc = 'For the whole server.' },
        { sep = 'Testing' },
        { id = 'kit', label = 'Give me the test kit', icon = 'pickup',
          desc = 'Forensics kit, empty bags, laser pointers, pliers, cloths, bleach, file, camera, flashlight.' },
        { id = 'bags', label = 'Give me every evidence bag', icon = 'pickup',
          desc = 'Each kind once, not analysed (ground, person, weapon, vehicle, body, shoe and tyre prints, fibres, bleach). Your own fingerprint, blood and shoes.' },
        { id = 'spawn', label = 'Place test evidence around me', icon = 'target',
          desc = 'One of each type, with your own fingerprint and blood. Casing and bullet share a shot (trajectory).' },
        { id = 'ready', label = 'Make evidence within 25 m ready', icon = 'timer', desc = 'Only needed when "too fresh" is turned on.' },
        { id = 'finishLabs', label = 'Finish running lab analyses now', icon = 'timer' },
        { id = 'reveal', label = 'Analyse the bags in my pockets', icon = 'timer', desc = 'Lab values at once, no lab needed.' },
        { sep = 'Bodies' },
        { id = 'body:ped', label = 'Place a test pedestrian', icon = 'target', desc = 'Stands 4 m in front of you. Kill it, then examine the body.' },
        { id = 'body:armed', label = 'Place an armed test pedestrian', icon = 'target', desc = 'Holds a pistol: GSR on the hands.' },
        { id = 'body:clone', label = 'Place a stand-in for me', icon = 'target',
          desc = 'Your model, your blood and your GSR: tests a player\'s body alone (no respawn hold).' },
        { id = 'body:clear', label = 'Remove all bodies', icon = 'warning', desc = 'Pedestrian bodies are taken away.' },
        { sep = 'Labs' },
        { id = 'fitScreen', label = 'Fit the lab screen', icon = 'target', close = true,
          desc = 'Stand at a lab: click 3 corners of the monitor (top left, top right, bottom left), then fine-tune.' },
        { sep = 'Cases' },
        { id = 'cases', label = 'Case lockers', kind = 'open', desc = 'Every case: open, close, reopen, delete.' },
    } }
end

local function caseRows()
    local rows = {}
    if #caseList == 0 then rows[1] = { kind = 'note', label = 'No case lockers yet.' } end
    for _, c in ipairs(caseList) do
        local state = c.closed and 'closed' or 'open'
        rows[#rows + 1] = {
            id = 'case:' .. c.id, kind = 'open',
            label = ('Case %s  ·  %d item(s)  ·  %s'):format(c.id, c.items, state),
            desc = c.taken > 0 and ('%d item(s) taken out right now.'):format(c.taken) or nil,
        }
    end
    return { title = 'Case lockers', back = 'Forensics', rows = rows }
end

local function oneCaseRows(c)
    return { title = 'Case ' .. c.id, back = 'Case lockers', rows = {
        { id = 'open', label = 'Open its locker (from here)', icon = 'pickup', close = true },
        c.closed and { id = 'reopen', label = 'Reopen the case', icon = 'check' }
            or { id = 'close', label = 'Close the case (look only)', icon = 'warning' },
        { id = 'delete', label = 'Delete case and its items', icon = 'warning', desc = 'Everything in the locker is gone for good.' },
    } }
end

Whip.register(function()
    Whip.core:RegisterDevPage('evidence', {
        label = 'Forensics',
        desc = 'Clean up evidence, test tools, case lockers.',
        rows = function()
            if level == 'cases' then return caseRows() end
            if level == 'case' then
                local c = caseById(picked)
                if c then return oneCaseRows(c) end
                level = 'cases'
                return caseRows()
            end
            return topRows()
        end,
        onBack = function()
            level = level == 'case' and 'cases' or 'top'
        end,
        onSelect = function(rowId)
            if level == 'top' then
                if rowId == 'clear' then
                    TriggerServerEvent('whip_evidence:admin', 'clear', 1)
                elseif rowId == 'cases' then
                    level = 'cases'
                    loadCases()
                elseif rowId == 'fitScreen' then
                    WhipEvidence.fitScreen()
                elseif rowId:sub(1, 5) == 'body:' then
                    TriggerServerEvent('whip_evidence:adminBody', rowId:sub(6))
                elseif rowId:sub(1, 4) == 'wipe' then
                    local radius = tonumber(rowId:match('%d+'))
                    if radius then TriggerServerEvent('whip_evidence:admin', 'wipe', radius) end
                else
                    TriggerServerEvent('whip_evidence:adminTest', rowId)
                end
            elseif level == 'cases' then
                local id = tostring(rowId):match('^case:(.+)$')
                if id then level, picked = 'case', id end
            elseif level == 'case' and picked then
                local id = picked
                if rowId == 'delete' then
                    CreateThread(function()
                        local sure = Whip.core:Confirm({
                            title = ('Delete case %s?'):format(id),
                            message = 'The case and everything in its locker are gone for good.',
                            yes = 'Delete', no = 'Cancel',
                        })
                        if sure then
                            level = 'cases'
                            TriggerServerEvent('whip_evidence:adminCase', 'delete', id)
                        end
                    end)
                else
                    TriggerServerEvent('whip_evidence:adminCase', rowId, id)
                end
            end
        end,
    })
end)
