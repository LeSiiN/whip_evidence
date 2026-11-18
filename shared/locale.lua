-- Texts in the server's language (Config.Locale, files in locales/). Missing texts fall back to English.
-- L('key', ...) works like string.format: L('collected', 'Casing') -> "Casing collected."
Locales = Locales or {}
WhipEvidence = WhipEvidence or {}

function WhipEvidence.L(key, ...)
    local t = Locales[Config.Locale or 'en'] or Locales.en or {}
    local s = t[key] or (Locales.en and Locales.en[key]) or key
    if select('#', ...) > 0 then
        local ok, out = pcall(string.format, s, ...)
        if ok then return out end
    end
    return s
end

-- all texts of the current language (for the NUI pages; English fills the gaps)
function WhipEvidence.texts()
    local out = {}
    for k, v in pairs(Locales.en or {}) do out[k] = v end
    for k, v in pairs(Locales[Config.Locale or 'en'] or {}) do out[k] = v end
    return out
end

L = WhipEvidence.L
