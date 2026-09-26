Permissions = {}

local accessChecks = {} ---@type table<string, fun(src: number, ctx: table): boolean, string?>
local qualificationProvider ---@type fun(src: number, qualification: string, org: string): boolean

-- (/add_allowlist <id> swat).
qualificationProvider = function(src, qualification)
    local identifier = bridge.fw.getIdentifier(src)
    return identifier ~= nil and exports["prp-bridge"]:HasAllowlist(identifier, qualification) == true
end

function Permissions.isAdmin(src)
    return Config.adminBypass and bridge.fw.isAdmin(src)
end

---Membership with at least `grade`.
function Permissions.hasGrade(src, orgName, grade, duty)
    local org = Config.organizations[orgName]
    if not org then return false end

    if org.type == "gang" then
        return bridge.fw.hasGang(src, orgName, grade)
    end

    return bridge.fw.hasJob(src, orgName, grade, duty)
end

function Permissions.isMember(src, orgName)
    return Permissions.hasGrade(src, orgName, nil, false)
end

---@param action string key of org.permissions
function Permissions.can(src, orgName, action)
    if Permissions.isAdmin(src) then return true end

    local org = Config.organizations[orgName]
    local required = org and org.permissions[action]
    if required == nil then return false end

    return Permissions.hasGrade(src, orgName, required, false)
end

function Permissions.resolve(src, orgName)
    local org = Config.organizations[orgName]
    local perms = {}
    for action in pairs(org.permissions) do
        perms[action] = Permissions.can(src, orgName, action)
    end
    perms.admin = Permissions.isAdmin(src)
    return perms
end

function Permissions.gradeLabel(orgName, grade)
    local org = Config.organizations[orgName]
    return org and org.grades and org.grades[grade] or ("Grade %d"):format(grade or 0)
end

---Can this player check this vehicle out?
---@return boolean, string?
function Permissions.canRetrieve(src, vehicle)
    local orgName = vehicle.org
    local org = Config.organizations[orgName]
    if Permissions.isAdmin(src) then return true end

    if not Permissions.can(src, orgName, "retrieve") then
        return false, "You are not permitted to retrieve vehicles"
    end

    if org.type == "job" and org.requireDuty and not Permissions.hasGrade(src, orgName, nil, true) then
        return false, "You must be on duty"
    end

    local category = org.categories[vehicle.category] or {}
    local minGrade = math.max(vehicle.minGrade or 0, category.minGrade or 0)
    if minGrade > 0 and not Permissions.hasGrade(src, orgName, minGrade, false) then
        return false, ("Requires %s+"):format(Permissions.gradeLabel(orgName, minGrade))
    end

    local quals = {}
    for _, q in ipairs(category.qualifications or {}) do quals[#quals + 1] = q end
    for _, q in ipairs(vehicle.metadata.qualifications or {}) do quals[#quals + 1] = q end

    for _, qualification in ipairs(quals) do
        local ok, result = pcall(qualificationProvider, src, qualification, orgName)
        if not ok or not result then
            return false, ("Requires %s qualification"):format(qualification:upper())
        end
    end

    local ctx = { org = orgName, vehicle = vehicle }
    for name, check in pairs(accessChecks) do
        local ok, allowed, reason = pcall(check, src, ctx)
        if not ok then
            lib.print.error(("access check '%s' errored: %s"):format(name, allowed))
            return false, "Access check failed"
        end
        if not allowed then return false, reason or "Access denied" end
    end

    return true
end

-- Extension points for other resources.
exports("RegisterAccessCheck", function(name, fn)
    accessChecks[name] = fn
end)

exports("RemoveAccessCheck", function(name)
    accessChecks[name] = nil
end)

exports("RegisterQualificationProvider", function(fn)
    qualificationProvider = fn
end)
