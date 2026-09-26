Menus = {}

local view         -- last view from the server
local nav = {}     -- { list = spec, vehicleId = id } so menus can be rebuilt after a change

local function ago(ts)
    if not ts then return "Never" end
    local diff = math.max(0, (view.now or 0) - ts)
    if diff < 60 then return "just now" end
    if diff < 3600 then return ("%d min ago"):format(diff // 60) end
    if diff < 86400 then return ("%d hr ago"):format(diff // 3600) end
    return ("%d days ago"):format(diff // 86400)
end

local function pct(value, max)
    return math.floor(math.max(0, math.min(100, (value or 0) / max * 100)))
end

local function colorScheme(percent)
    return percent >= 60 and "green" or percent >= 30 and "yellow" or "red"
end

local function title(v)
    return ("%s — %s"):format(v.callsign or v.plate, v.label)
end

local function findVehicle(id)
    for _, v in ipairs(view.vehicles) do
        if v.id == id then return v end
    end
end

local function statusLine(v)
    if v.status == "in_use" then
        return ("In use by %s · %s"):format(v.holderName or "Unknown", ago(v.checkedOutAt))
    end
    if v.status == "available" then
        return v.atGarage and ("Available · %s"):format(v.garageLabel) or ("Available · Stored at %s"):format(v.garageLabel)
    end
    return ("%s · %s"):format(Status[v.status].label, v.garageLabel)
end

local function vehicleMetadata(v)
    local meta = { { label = "Plate", value = v.plate }, { label = "Garage", value = v.garageLabel } }

    if v.status == "in_use" then
        meta[#meta + 1] = { label = "Checked Out By", value = v.holderName or "Unknown" }
        meta[#meta + 1] = { label = "Checked Out", value = ago(v.checkedOutAt) }
    else
        meta[#meta + 1] = { label = "Last Used", value = v.lastHolderName or "Never" }
        meta[#meta + 1] = { label = "Returned", value = ago(v.returnedAt) }
    end

    local fuel, engine = math.floor(v.fuel or 0), pct(v.engine, 1000)
    meta[#meta + 1] = { label = "Fuel", value = fuel .. "%", progress = fuel, colorScheme = colorScheme(fuel) }
    meta[#meta + 1] = { label = "Engine", value = engine .. "%", progress = engine, colorScheme = colorScheme(engine) }
    return meta
end

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------

local function fetch(orgName, garageId)
    view = lib.callback.await("amphy_fleet:getView", false, orgName, garageId)
    return view ~= nil
end

local register

---Refetch
local function refresh(menuId)
    if not fetch(view.org.name, view.garage and view.garage.id) then return end
    register()
    lib.showContext(menuId)
end

---------------------------------------------------------------------------
-- Vehicle lists
---------------------------------------------------------------------------

local function registerList(spec)
    local options = {}

    for _, v in ipairs(view.vehicles) do
        if spec.filter(v) then
            local status = Status[v.status]
            options[#options + 1] = {
                title = title(v),
                description = statusLine(v),
                icon = status.icon,
                iconColor = v.canRetrieve and status.color or (v.status == "available" and "#868e96" or status.color),
                metadata = vehicleMetadata(v),
                arrow = true,
                onSelect = function()
                    nav.vehicleId = v.id
                    Menus.registerVehicle(v.id)
                    lib.showContext("amphy_fleet:vehicle")
                end,
            }
        end
    end

    if #options == 0 then
        options[1] = { title = "No vehicles", description = spec.empty or "Nothing to show here", icon = "circle-info", disabled = true }
    end

    lib.registerContext({ id = "amphy_fleet:list", title = spec.title, menu = spec.parent, options = options })
end

local function openList(spec)
    nav.list = spec
    registerList(spec)
    lib.showContext("amphy_fleet:list")
end

---------------------------------------------------------------------------
-- Vehicle details / management
---------------------------------------------------------------------------

local function input(heading, rows)
    return lib.inputDialog(heading, rows, { allowCancel = true })
end

local function update(v, field, value)
    if lib.callback.await("amphy_fleet:update", false, v.id, field, value) then
        refresh("amphy_fleet:vehicle")
    end
end

local function setStatus(v, status, confirm)
    if confirm then
        local answer = lib.alertDialog({ header = confirm.header, content = confirm.content, centered = true, cancel = true })
        if answer ~= "confirm" then return lib.showContext("amphy_fleet:vehicle") end
    end

    if lib.callback.await("amphy_fleet:setStatus", false, v.id, status) then
        refresh("amphy_fleet:vehicle")
    end
end

local function openHistory(v)
    local rows = lib.callback.await("amphy_fleet:history", false, v.id)
    if not rows then return end

    local options = {}
    for _, row in ipairs(rows) do
        local action = HistoryActions[row.action] or HistoryActions.status
        local meta = {}
        for key, value in pairs(row.data) do
            meta[#meta + 1] = { label = key:gsub("^%l", string.upper), value = tostring(value) }
        end

        options[#options + 1] = {
            title = row.time,
            description = ("%s by %s"):format(action.label, row.actor_name or "System"),
            icon = action.icon,
            iconColor = action.color,
            metadata = #meta > 0 and meta or nil,
            readOnly = true,
        }
    end

    if #options == 0 then
        options[1] = { title = "No history yet", icon = "circle-info", readOnly = true }
    end

    lib.registerContext({ id = "amphy_fleet:history", title = ("History — %s"):format(v.callsign or v.plate), menu = "amphy_fleet:vehicle", options = options })
    lib.showContext("amphy_fleet:history")
end

local function selectOptions(list)
    local out = {}
    for _, entry in ipairs(list) do out[#out + 1] = { value = entry.value, label = entry.label } end
    return out
end

local function categoryOptions()
    local out = {}
    for _, c in ipairs(view.categories) do out[#out + 1] = { value = c.id, label = c.label } end
    return out
end

function Menus.registerVehicleManage(id)
    local v = findVehicle(id)
    if not v then return end
    local p = view.perms
    local inUse = v.status == "in_use"
    local options = {}

    if p.edit then
        options[#options + 1] = { title = "Rename Vehicle", description = v.label, icon = "pen", onSelect = function()
            local r = input("Rename Vehicle", { { type = "input", label = "Name", default = v.label, required = true, max = 64 } })
            if r then update(v, "label", r[1]) else lib.showContext("amphy_fleet:vmanage") end
        end }
        options[#options + 1] = { title = "Change Callsign", description = v.callsign or "None", icon = "hashtag", onSelect = function()
            local r = input("Change Callsign", { { type = "input", label = "Callsign", default = v.callsign, max = 16 } })
            if r then update(v, "callsign", r[1] or "") else lib.showContext("amphy_fleet:vmanage") end
        end }
        options[#options + 1] = { title = "Change Category", description = v.categoryLabel, icon = "layer-group", onSelect = function()
            local r = input("Change Category", { { type = "select", label = "Category", options = categoryOptions(), default = v.category, required = true } })
            if r then update(v, "category", r[1]) else lib.showContext("amphy_fleet:vmanage") end
        end }
    end

    if p.ranks then
        options[#options + 1] = { title = "Change Minimum Rank", description = v.minGradeLabel, icon = "user-lock", onSelect = function()
            local r = input("Minimum Rank", { { type = "select", label = "Rank", options = selectOptions(view.grades), default = v.minGrade, required = true } })
            if r then update(v, "minGrade", r[1]) else lib.showContext("amphy_fleet:vmanage") end
        end }
    end

    if p.transfer then
        options[#options + 1] = {
            title = "Transfer Garage", description = inUse and "Vehicle is checked out" or v.garageLabel,
            icon = "right-left", disabled = inUse,
            onSelect = function()
                local r = input("Transfer Garage", { { type = "select", label = "Garage", options = view.garages, default = v.garage, required = true } })
                if r then update(v, "garage", r[1]) else lib.showContext("amphy_fleet:vmanage") end
            end,
        }
    end

    if p.status then
        if v.status == "maintenance" then
            options[#options + 1] = { title = "Complete Maintenance", icon = "wrench", iconColor = "#40c057", onSelect = function() setStatus(v, "available") end }
        elseif v.status == "available" or v.status == "out_of_service" then
            options[#options + 1] = { title = "Send to Maintenance", icon = "screwdriver-wrench", iconColor = "#fab005", onSelect = function() setStatus(v, "maintenance") end }
        end
        if v.status == "impounded" then
            options[#options + 1] = { title = "Release from Impound", icon = "lock-open", iconColor = "#40c057", onSelect = function() setStatus(v, "available") end }
        end
    end

    if p.missing then
        if v.status == "missing" then
            options[#options + 1] = { title = "Mark Recovered", icon = "magnifying-glass", iconColor = "#40c057", onSelect = function() setStatus(v, "available") end }
        elseif v.status ~= "impounded" then
            options[#options + 1] = { title = "Mark Missing", icon = "circle-question", iconColor = "#fa5252", onSelect = function()
                setStatus(v, "missing", { header = "Mark Missing", content = ("Mark **%s** as missing?"):format(title(v)) })
            end }
        end
    end

    if p.manage and inUse then
        options[#options + 1] = {
            title = "Recall Vehicle", description = ("Force return from %s"):format(v.holderName or "Unknown"),
            icon = "rotate-left", iconColor = "#fab005",
            onSelect = function()
                setStatus(v, "available", { header = "Recall Vehicle", content = ("Despawn **%s** and return it to %s?"):format(title(v), v.garageLabel) })
            end,
        }
    end

    if p.remove then
        options[#options + 1] = {
            title = "Remove From Fleet", description = inUse and "Vehicle is checked out" or "Permanently delete this vehicle",
            icon = "trash", iconColor = "#fa5252", disabled = inUse,
            onSelect = function()
                local answer = lib.alertDialog({
                    header = "Remove From Fleet",
                    content = ("Permanently remove **%s** (%s)? This cannot be undone."):format(title(v), v.plate),
                    centered = true, cancel = true,
                })
                if answer ~= "confirm" then return lib.showContext("amphy_fleet:vmanage") end
                if lib.callback.await("amphy_fleet:remove", false, v.id) then
                    nav.vehicleId = nil
                    refresh(nav.list and "amphy_fleet:list" or "amphy_fleet:main")
                end
            end,
        }
    end

    lib.registerContext({ id = "amphy_fleet:vmanage", title = ("Manage — %s"):format(v.callsign or v.plate), menu = "amphy_fleet:vehicle", options = options })
    return #options > 0
end

function Menus.registerVehicle(id)
    local v = findVehicle(id)
    if not v then return end
    local p = view.perms
    local status = Status[v.status]
    local engine, body, fuel = pct(v.engine, 1000), pct(v.body, 1000), math.floor(v.fuel or 0)

    local options = {
        {
            title = ("Status: %s"):format(status.label),
            description = statusLine(v),
            icon = status.icon, iconColor = status.color, readOnly = true,
        },
        {
            title = "Vehicle Information",
            icon = "circle-info", readOnly = true,
            metadata = {
                { label = "Plate", value = v.plate },
                { label = "Model", value = v.model },
                { label = "Category", value = v.categoryLabel },
                { label = "Garage", value = v.garageLabel },
                { label = "Minimum Rank", value = v.minGradeLabel },
                { label = "Last Driver", value = v.lastHolderName or "Never" },
                { label = "Last Returned", value = ago(v.returnedAt) },
            },
        },
        {
            title = "Condition",
            description = ("Engine %d%% · Body %d%% · Fuel %d%%"):format(engine, body, fuel),
            icon = "gauge-high", iconColor = colorScheme(math.min(engine, body)) == "green" and "#40c057" or "#fab005",
            progress = math.min(engine, body), colorScheme = colorScheme(math.min(engine, body)),
            readOnly = true,
            metadata = {
                { label = "Engine", value = ("%d / 1000"):format(v.engine or 0), progress = engine, colorScheme = colorScheme(engine) },
                { label = "Body", value = ("%d / 1000"):format(v.body or 0), progress = body, colorScheme = colorScheme(body) },
                { label = "Fuel", value = fuel .. "%", progress = fuel, colorScheme = colorScheme(fuel) },
            },
        },
        {
            title = "Retrieve Vehicle",
            description = v.canRetrieve and ("Spawn at %s"):format(view.garage and view.garage.label or "") or v.reason,
            icon = "car-on", iconColor = v.canRetrieve and "#40c057" or "#868e96",
            disabled = not v.canRetrieve,
            onSelect = function()
                RetrieveVehicle(v.id, view.garage.id)
            end,
        },
    }

    if p.history then
        options[#options + 1] = { title = "Vehicle History", icon = "scroll", arrow = true, onSelect = function() openHistory(v) end }
    end

    if p.status and (v.status == "available" or v.status == "out_of_service") then
        local oos = v.status == "out_of_service"
        options[#options + 1] = {
            title = oos and "Return to Service" or "Mark Out of Service",
            icon = oos and "circle-check" or "ban", iconColor = oos and "#40c057" or "#868e96",
            onSelect = function() setStatus(v, oos and "available" or "out_of_service") end,
        }
    end

    if Menus.registerVehicleManage(id) then
        options[#options + 1] = { title = "Manage Vehicle", icon = "gear", menu = "amphy_fleet:vmanage", arrow = true }
    end

    lib.registerContext({ id = "amphy_fleet:vehicle", title = title(v), menu = nav.list and "amphy_fleet:list" or "amphy_fleet:main", options = options })
end

---------------------------------------------------------------------------
-- Management
---------------------------------------------------------------------------

local function addVehicle()
    local modelRow = view.models and not view.perms.admin
        and { type = "select", label = "Model", options = (function()
            local o = {}
            for _, m in ipairs(view.models) do o[#o + 1] = { value = m, label = m } end
            return o
        end)(), required = true }
        or { type = "input", label = "Model", placeholder = "police3", required = true }

    local r = input("Add Fleet Vehicle", {
        modelRow,
        { type = "input", label = "Display Name", placeholder = "Leave blank for default" },
        { type = "select", label = "Category", options = categoryOptions(), required = true },
        { type = "select", label = "Garage", options = view.garages, default = view.garage and view.garage.id, required = true },
        { type = "input", label = "Callsign", placeholder = "PD311", max = 16 },
        { type = "input", label = "Plate", placeholder = "Leave blank to generate", max = 8 },
        { type = "select", label = "Minimum Rank", options = selectOptions(view.grades), default = view.grades[1] and view.grades[1].value },
    })
    if not r then return lib.showContext("amphy_fleet:manage") end

    local model = tostring(r[1]):lower()
    if not IsModelInCdimage(joaat(model)) or not IsModelAVehicle(joaat(model)) then
        lib.notify({ type = "error", title = "Fleet", description = ("'%s' is not a valid vehicle model"):format(model) })
        return lib.showContext("amphy_fleet:manage")
    end

    local ok = lib.callback.await("amphy_fleet:add", false, view.org.name, {
        model = model, label = r[2], category = r[3], garage = r[4], callsign = r[5], plate = r[6], minGrade = r[7],
    })
    if ok then refresh("amphy_fleet:manage") else lib.showContext("amphy_fleet:manage") end
end

local function registerManage()
    local counts = { in_use = 0, maintenance = 0, out_of_service = 0, missing = 0, impounded = 0 }
    for _, v in ipairs(view.vehicles) do
        if counts[v.status] then counts[v.status] += 1 end
    end

    local function listOption(label, icon, color, statuses, count)
        return {
            title = label, icon = icon, iconColor = color, arrow = true,
            description = ("%d vehicle%s"):format(count, count == 1 and "" or "s"),
            onSelect = function()
                openList({
                    title = label, parent = "amphy_fleet:manage",
                    filter = function(v) return statuses[v.status] == true end,
                })
            end,
        }
    end

    local options = {}
    if view.perms.add then
        options[#options + 1] = { title = "Add Vehicle", description = "Register a new fleet vehicle", icon = "plus", iconColor = "#40c057", onSelect = addVehicle }
    end

    options[#options + 1] = {
        title = "Manage Vehicles", icon = "list", arrow = true,
        description = ("%d vehicles in fleet"):format(#view.vehicles),
        onSelect = function()
            openList({ title = "All Vehicles", parent = "amphy_fleet:manage", filter = function() return true end })
        end,
    }
    options[#options + 1] = listOption("Deployed Vehicles", "road", Status.in_use.color, { in_use = true }, counts.in_use)
    options[#options + 1] = listOption("Maintenance", "screwdriver-wrench", Status.maintenance.color, { maintenance = true, out_of_service = true }, counts.maintenance + counts.out_of_service)
    options[#options + 1] = listOption("Missing Vehicles", "circle-question", Status.missing.color, { missing = true }, counts.missing)
    options[#options + 1] = listOption("Impounded", "lock", Status.impounded.color, { impounded = true }, counts.impounded)

    lib.registerContext({
        id = "amphy_fleet:manage",
        title = ("%s Fleet Management"):format(view.org.label),
        menu = view.garage and "amphy_fleet:main" or nil,
        options = options,
    })
end

---------------------------------------------------------------------------
-- Main
---------------------------------------------------------------------------

local function registerMain()
    local options = {}
    local total, available, deployed, down = #view.vehicles, 0, 0, 0

    for _, v in ipairs(view.vehicles) do
        if v.status == "available" then available += 1
        elseif v.status == "in_use" then deployed += 1
        else down += 1 end
    end

    options[#options + 1] = {
        title = "Fleet Status",
        description = ("%d available · %d deployed · %d unavailable"):format(available, deployed, down),
        icon = "chart-simple", readOnly = true,
        progress = total > 0 and math.floor(available / total * 100) or 0, colorScheme = "green",
    }

    for _, c in ipairs(view.categories) do
        if c.total > 0 then
            options[#options + 1] = {
                title = c.label,
                description = ("%d of %d available here%s"):format(c.available, c.total, c.minGradeLabel and (" · %s+"):format(c.minGradeLabel) or ""),
                icon = c.icon or "car", iconColor = c.iconColor,
                progress = math.floor(c.available / c.total * 100), colorScheme = c.available > 0 and "green" or "red",
                arrow = true,
                onSelect = function()
                    openList({
                        title = c.label, parent = "amphy_fleet:main",
                        filter = function(v) return v.category == c.id end,
                    })
                end,
            }
        end
    end

    options[#options + 1] = {
        title = "Out of Service", icon = "wrench", iconColor = "#868e96", arrow = true,
        description = ("%d vehicle%s unavailable"):format(down, down == 1 and "" or "s"),
        onSelect = function()
            openList({ title = "Out of Service", parent = "amphy_fleet:main", filter = function(v) return v.status ~= "available" and v.status ~= "in_use" end })
        end,
    }

    options[#options + 1] = {
        title = "Currently Deployed", icon = "clipboard-list", iconColor = Status.in_use.color, arrow = true,
        description = ("%d vehicle%s on the road"):format(deployed, deployed == 1 and "" or "s"),
        onSelect = function()
            openList({ title = "Currently Deployed", parent = "amphy_fleet:main", filter = function(v) return v.status == "in_use" end })
        end,
    }

    if view.perms.manage then
        registerManage()
        options[#options + 1] = { title = "Fleet Management", icon = "gears", iconColor = "#fab005", menu = "amphy_fleet:manage", arrow = true }
    end

    lib.registerContext({
        id = "amphy_fleet:main",
        title = view.garage and ("%s Fleet — %s"):format(view.org.label, view.garage.label) or ("%s Fleet"):format(view.org.label),
        options = options,
    })
end

register = function()
    if view.garage then registerMain() else registerManage() end
    if nav.list then registerList(nav.list) end
    if nav.vehicleId and findVehicle(nav.vehicleId) then Menus.registerVehicle(nav.vehicleId) end
end

---------------------------------------------------------------------------
-- Entry points
---------------------------------------------------------------------------

function Menus.openGarage(orgName, garageId)
    nav = {}
    if not fetch(orgName, garageId) then return end
    registerMain()
    lib.showContext("amphy_fleet:main")
end

function Menus.openManagement(orgName, garageId)
    nav = {}
    if not fetch(orgName, garageId) then return end
    if not view.perms.manage then
        return lib.notify({ type = "error", title = "Fleet", description = "You are not permitted to manage this fleet" })
    end
    if view.garage then registerMain() end
    registerManage()
    lib.showContext("amphy_fleet:manage")
end

RegisterNetEvent("amphy_fleet:client:admin", function(orgs)
    local options = {}
    for _, org in ipairs(orgs) do
        options[#options + 1] = {
            title = org.label, description = org.type == "gang" and "Gang fleet" or "Department fleet",
            icon = org.icon or "car", arrow = true,
            onSelect = function() Menus.openManagement(org.name) end,
        }
    end
    lib.registerContext({ id = "amphy_fleet:admin", title = "Fleet Admin", options = options })
    lib.showContext("amphy_fleet:admin")
end)
