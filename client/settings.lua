-- Client: each player's own layout for the police scan and the photo viewer.
-- Pause menu → Settings → Server Settings → tab "Forensics". Stored on the player's PC (KVP).
-- An admin can force a value for everyone from WHIP's settings page.
WhipEvidence.UI = {}

local ROWS = {
    { id = 'legend', type = 'toggle', default = true, label = 'Camera: show legend',
      help = 'The list of everything in the picture while holding the camera.' },
    { id = 'legendSide', type = 'choice', default = 'right', label = 'Camera: legend side',
      options = { { value = 'right', label = 'Right' }, { value = 'left', label = 'Left' } } },
    { id = 'legendTop', type = 'slider', default = 8, min = 0, max = 60, step = 1, unit = '%', label = 'Camera: legend from the top' },
    { id = 'legendSize', type = 'slider', default = 20, min = 12, max = 32, step = 1, unit = '%', label = 'Camera: legend width' },
    { id = 'tagSize', type = 'slider', default = 100, min = 50, max = 200, step = 10, unit = '%', label = 'Scan: marker size' },
    { id = 'cardSize', type = 'slider', default = 100, min = 50, max = 200, step = 10, unit = '%', label = 'Scan: card size' },
    { id = 'trajectories', type = 'toggle', default = true, label = 'Scan: show shot trajectories' },
    { id = 'viewerSize', type = 'slider', default = 62, min = 35, max = 95, step = 1, unit = '%', label = 'Photo: picture size',
      help = 'Width of the photo in the viewer, share of the screen.' },
    { id = 'viewerLog', type = 'choice', default = 'right', label = 'Photo: evidence list',
      options = { { value = 'right', label = 'Right' }, { value = 'left', label = 'Left' },
                  { value = 'bottom', label = 'Below' }, { value = 'hidden', label = 'Hidden' } } },
    { id = 'viewerStamp', type = 'toggle', default = true, label = 'Photo: date stamp on the picture' },
}

local function load(row)
    local raw = GetResourceKvpString('ui:' .. row.id)
    if raw then
        local ok, value = pcall(json.decode, raw)
        if ok and value ~= nil and type(value) == type(row.default) then return value end
    end
    return row.default
end

for _, row in ipairs(ROWS) do
    WhipEvidence.UI[row.id] = load(row)
    Whip.playerSetting({
        key = 'whip_evidence.' .. row.id, group = 'Forensics', type = row.type, default = row.default,
        label = row.label, help = row.help, options = row.options,
        min = row.min, max = row.max, step = row.step, unit = row.unit,
        get = function() return WhipEvidence.UI[row.id] end,
        set = function(value)
            WhipEvidence.UI[row.id] = value
            SetResourceKvp('ui:' .. row.id, json.encode(value))
        end,
    })
end

-- The value in force (a server-forced value wins over the player's choice)
function WhipEvidence.ui(id)
    local forced = exports.whip_core:GetPlayerSetting('whip_evidence.' .. id)
    if forced ~= nil then return forced end
    return WhipEvidence.UI[id]
end
