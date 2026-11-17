-- Jobs and rank permissions.
-- * A police job that does not exist yet is created (Config.Jobs).
-- * Every police job gets the evidence permissions (Config.Permissions) as its own permissions:
--   they show up as toggles on each role in /whip -> Jobs.
-- * On the first start each permission is switched on for every role at its level or higher.
--   After that the Job Manager decides; this file never changes a role again.
-- * A job another running resource declares cannot get them: then permissions stay off
--   (every on-duty officer may do everything) and the console says why.
WhipEvidence.Jobs = {}

local function permissionLabels()
    local list = {}
    for name, p in pairs(Config.Permissions or {}) do list[name] = p.label or name end
    return list
end

local function currentRoles(key)
    local roles = {}
    for _, r in ipairs(Whip.core:GetJobRoles(key) or {}) do roles[#roles + 1] = { name = r.name, level = r.level } end
    return roles
end

-- First start only: switch each permission on for the ranks at its level (KVP remembers it was done)
local function seed(key)
    local roles = Whip.core:GetJobRoles(key) or {}
    for name, p in pairs(Config.Permissions or {}) do
        local done = ('seed:%s:%s'):format(key, name)
        if not GetResourceKvpString(done) then
            for _, role in ipairs(roles) do
                if role.level < 100 and role.level >= (p.level or 1) then
                    local ok, why = Whip.core:UpdateJobRole(key, role.roleId, { permissions = { [name] = true } })
                    if not ok then print(('[%s] %s / %s: %s'):format(WhipEvidence.Res, key, role.name, tostring(why))) end
                end
            end
            SetResourceKvp(done, '1')
        end
    end
end

function WhipEvidence.Jobs.ensure()
    local usePerms = Config.UsePermissions ~= false and next(Config.Permissions or {}) ~= nil
    local allDeclared = usePerms
    for _, key in ipairs(Config.PoliceJobs) do
        local def = Config.Jobs[key] or {}
        local existed = Whip.core:GetJob(key) ~= nil
        if existed and not usePerms then goto continue end
        local data = { permissions = usePerms and permissionLabels() or nil }
        if existed then
            data.roles = currentRoles(key)   -- nothing added, nothing renamed
        else
            data.name, data.icon, data.roles = def.name or key, def.icon, def.roles
        end
        local job, why = Whip.core:EnsureJob(key, data)
        if not job then
            allDeclared = false
            if existed then
                print(('[%s] job "%s": cannot add the evidence permissions (%s). Every on-duty officer may do everything.')
                    :format(WhipEvidence.Res, key, tostring(why)))
            else
                Whip.startProblem('job %s: %s', key, tostring(why))
            end
        else
            if not existed then print(('[%s] created job "%s" (%s)'):format(WhipEvidence.Res, key, def.name or key)) end
            if usePerms then seed(key) end
        end
        ::continue::
    end
    GlobalState['whip_evidence:perms'] = allDeclared
end

-- May this player do it? Police job on duty, and (when permissions are in force) the rank has it.
function WhipEvidence.can(source, permission)
    local job = exports.whip_core:GetPlayerJob(source)
    if not job or not WhipEvidence.isPoliceJob(job.key) then return false end
    if not WhipEvidence.permsActive() then return true end
    return exports.whip_core:HasJobPermission(source, job.key, permission, { onDuty = true }) == true
end

-- Same check as an AddAction / item option requirement (client hint, server re-checks)
function WhipEvidence.req(permission, extra)
    local r = { job = Config.PoliceJobs, onDuty = true }
    if permission and WhipEvidence.permsActive() then r.jobPermission = permission end
    for k, v in pairs(extra or {}) do r[k] = v end
    return r
end

WhipEvidence.NOT_ALLOWED = 'Your rank is not allowed to do that.'
