-- Client: each player's own layout for the police scan and the photo viewer.
-- Pause menu → Settings → Server Settings → tab "Forensics". Stored on the player's PC (KVP).
-- An admin can force a value for everyone from WHIP's settings page.
WhipEvidence.UI = {}

local ROWS = {
    { id = 'legend', type = 'toggle', default = true, label = 'ui_legend',
      help = 'ui_legend_help' },
    { id = 'legendSide', type = 'choice', default = 'right', label = 'ui_legend_side',
      options = { { value = 'right', label = 'ui_right' }, { value = 'left', label = 'ui_left' } } },
    { id = 'legendTop', type = 'slider', default = 8, min = 0, max = 60, step = 1, unit = '%', label = 'ui_legend_top' },
    { id = 'legendSize', type = 'slider', default = 20, min = 12, max = 32, step = 1, unit = '%', label = 'ui_legend_size' },
    { id = 'tagSize', type = 'slider', default = 100, min = 50, max = 200, step = 10, unit = '%', label = 'ui_tag_size' },
    { id = 'cardSize', type = 'slider', default = 100, min = 50, max = 200, step = 10, unit = '%', label = 'ui_card_size' },
    { id = 'trajectories', type = 'toggle', default = true, label = 'ui_trajectories' },
    { id = 'viewerSize', type = 'slider', default = 62, min = 35, max = 95, step = 1, unit = '%', label = 'ui_viewer_size',
      help = 'ui_viewer_size_help' },
    { id = 'viewerLog', type = 'choice', default = 'right', label = 'ui_viewer_log',
      options = { { value = 'right', label = 'ui_right' }, { value = 'left', label = 'ui_left' },
                  { value = 'bottom', label = 'ui_below' }, { value = 'hidden', label = 'ui_hidden' } } },
    { id = 'viewerStamp', type = 'toggle', default = true, label = 'ui_viewer_stamp' },
}

local function load(row)
    local raw = GetResourceKvpString('ui:' .. row.id)
    if raw then
        local ok, value = pcall(json.decode, raw)
        if ok and value ~= nil and type(value) == type(row.default) then return value end
    end
    return row.default
end

-- ROWS hold text keys (locales/), the menu gets the texts
local function options(list)
    if not list then return nil end
    local out = {}
    for i, o in ipairs(list) do out[i] = { value = o.value, label = L(o.label) } end
    return out
end

for _, row in ipairs(ROWS) do
    WhipEvidence.UI[row.id] = load(row)
    Whip.playerSetting({
        key = 'whip_evidence.' .. row.id, group = L('forensics'), type = row.type, default = row.default,
        label = L(row.label), help = row.help and L(row.help), options = options(row.options),
        min = row.min, max = row.max, step = row.step, unit = row.unit,
        get = function() return WhipEvidence.UI[row.id] end,
        set = function(value)
            WhipEvidence.UI[row.id] = value
            SetResourceKvp('ui:' .. row.id, json.encode(value))
            if WhipEvidence.Scan and WhipEvidence.Scan.layoutChanged then WhipEvidence.Scan.layoutChanged() end
        end,
    })
end

-- The value in force (a server-forced value wins over the player's choice)
function WhipEvidence.ui(id)
    local forced = exports.whip_core:GetPlayerSetting('whip_evidence.' .. id)
    if forced ~= nil then return forced end
    return WhipEvidence.UI[id]
end
