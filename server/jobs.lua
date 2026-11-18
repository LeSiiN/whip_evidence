-- Jobs and rank permissions.
-- * The police jobs (Config.PoliceJobs) come from other scripts or /whip -> Jobs: this file only listens
--   to them, it never creates or changes a job (a job belongs to the script that declares it).
-- * Rank permissions are rank levels (Config.Permissions, /whip -> Settings -> Forensics):
--   "collect evidence from level 20" means every rank of level 20 or higher, in every police job.
WhipEvidence.Jobs = {}

-- On start: say in the console which listed jobs don't exist (yet). A job script may create them later.
function WhipEvidence.Jobs.ensure()
    for _, key in ipairs(Config.PoliceJobs) do
        if not Whip.core:GetJob(key) then
            print(('[%s] police job "%s" does not exist (yet): create it in your job script or /whip -> Jobs.')
                :format(WhipEvidence.Res, key))
        end
    end
end

-- May this player do it? Police job on duty, and (when permissions are on) a rank level high enough.
function WhipEvidence.can(source, permission)
    local job = exports.whip_core:GetPlayerJob(source)
    if not job or not WhipEvidence.isPoliceJob(job.key) then return false end
    return WhipEvidence.levelAllows(job.roleLevel, permission)
end

-- AddAction / item option requirement: the police job on duty (the rank level is checked by the server)
function WhipEvidence.req(_, extra)
    local r = { job = Config.PoliceJobs, onDuty = true }
    for k, v in pairs(extra or {}) do r[k] = v end
    return r
end

-- (kept for other code; the texts come from L('not_allowed'))
WhipEvidence.NOT_ALLOWED = 'Your rank is not allowed to do that.'
