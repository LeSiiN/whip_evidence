-- The forensic minigames as WHIP skill check games (whip_core keeps the token, the timing and the answer).
-- Server: WhipEvidence.minigame(source, what) plays the game set for "what" in Config.Minigames
-- (or WHIP's ring). Client: html/games.js draws them, client/games.lua runs them.
WhipEvidence.Games = WhipEvidence.Games or {}

local GAMES = {
    dust     = { label = 'Dust for prints',  desc = 'Brush the powder over the surface, then lift the print with tape.' },
    tweezers = { label = 'Tweezers',         desc = 'Grab the casing at its rim and carry it into the bag.' },
    swab     = { label = 'Swab',             desc = 'Rub the swab round the stain until it is soaked.' },
    pull     = { label = 'Pull it out',      desc = 'Keep steady pull in the green zone. Too hard and it breaks.' },
    shards   = { label = 'Pick up shards',   desc = 'Find and pick up every fragment before time runs out.' },
    gsrswab  = { label = 'GSR swab',         desc = 'Swab the marked spots, right hand first, then the left.' },
}

-- the time on screen is shorter than timeoutMs; minMs: no game is honestly done faster
local LEVELS = {
    easy   = { minMs = 1500, timeoutMs = 30000 },
    medium = { minMs = 1500, timeoutMs = 30000 },
    hard   = { minMs = 1500, timeoutMs = 30000 },
}

WhipEvidence.Games.ids = {}
for name, g in pairs(GAMES) do
    local id = 'whip_evidence.' .. name
    WhipEvidence.Games.ids[name] = id
    if IsDuplicityVersion() then
        Whip.skillCheckGame(id, { label = g.label, desc = g.desc, levels = LEVELS })
    else
        Whip.skillCheckGame(id, {
            run = function(difficulty, token) return WhipEvidence.Games.play(name, difficulty, token) end,
            cancel = function(token) WhipEvidence.Games.cancel(token) end,
        })
    end
end

if IsDuplicityVersion() then
    -- what -> game: fingerprint, casing, blood, bullet, vehicle_fragment, gsr, wipe (civilians), dust (weapons)
    function WhipEvidence.minigame(source, what)
        local name = (Config.Minigames or {})[what]
        local id = name and WhipEvidence.Games.ids[name]
        if id then
            local level = Config.MinigameLevel
            if level ~= 'medium' and level ~= 'hard' then level = 'easy' end
            local passed, why = exports.whip_core:SkillCheck(source, level, { game = id })
            if why ~= 'unavailable' then return passed, why end
        end
        return exports.whip_core:SkillCheck(source, WhipEvidence.skillCheck())
    end
end
