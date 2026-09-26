local function notify(src, kind, message)
    bridge.fw.notify(src, kind, message, "Fleet")
end

---Validates the vehicle id and the permission for it.
local function authorize(src, id, action)
    local vehicle = Fleet.get(id)
    if not vehicle then return nil, "Vehicle not found" end
    if not Permissions.can(src, vehicle.org, action) then return nil, "You are not permitted to do that" end
    return vehicle
end

---Which permission a player needs to move a vehicle between two statuses.
local function statusPermission(vehicle, to)
    local from = vehicle.status
    if to == "in_use" or to == "impounded" then return nil end

    if from == "in_use" then
        if to == "available" then return "manage" end -- recall
        if to == "missing" then
            local entity = Fleet.entities[vehicle.id]
            if entity and DoesEntityExist(entity) then return nil, "Vehicle is still out - recall it instead" end
            return "missing"
        end
        return nil
    end

    if to == "missing" or from == "missing" then return "missing" end
    return "status"
end

lib.callback.register("amphy_fleet:getAccess", function(src)
    local access = {}
    for orgName, org in pairs(Config.organizations) do
        if Permissions.isMember(src, orgName) or Permissions.isAdmin(src) then
            access[orgName] = { label = org.label, manage = Permissions.can(src, orgName, "manage") }
        end
    end
    return access
end)

lib.callback.register("amphy_fleet:getView", function(src, orgName, garageId)
    if type(orgName) ~= "string" then return nil end
    if garageId ~= nil and type(garageId) ~= "string" then return nil end

    local view, err = Fleet.buildView(src, orgName, garageId)
    if not view then notify(src, "error", err) end
    return view
end)

lib.callback.register("amphy_fleet:retrieve", function(src, id, garageId)
    if type(garageId) ~= "string" then return false end

    local ok, result = Fleet.checkout(src, tonumber(id), garageId)
    if not ok then
        notify(src, "error", result)
        return false
    end

    local vehicle = Fleet.get(id)
    notify(src, "success", ("%s checked out"):format(vehicle.callsign or vehicle.plate))
    return true, result
end)

lib.callback.register("amphy_fleet:store", function(src, netId, props, fuel)
    local ok, result = Fleet.store(src, netId, props, fuel)
    if not ok then
        notify(src, "error", result)
        return false
    end

    notify(src, result == "maintenance" and "warning" or "success",
        result == "maintenance" and "Vehicle returned - sent to maintenance due to damage" or "Vehicle returned to the fleet")
    return true
end)

lib.callback.register("amphy_fleet:history", function(src, id)
    local vehicle, err = authorize(src, tonumber(id), "history")
    if not vehicle then
        notify(src, "error", err)
        return nil
    end
    return History.get(vehicle.id)
end)

lib.callback.register("amphy_fleet:setStatus", function(src, id, status)
    local vehicle = Fleet.get(tonumber(id))
    if not vehicle or type(status) ~= "string" then return false end

    local permission, reason = statusPermission(vehicle, status)
    if not permission then
        notify(src, "error", reason or "That status change is not allowed")
        return false
    end

    if not Permissions.can(src, vehicle.org, permission) then
        notify(src, "error", "You are not permitted to do that")
        return false
    end

    local ok, err = Fleet.setStatus(vehicle.id, status, Fleet.actor(src))
    notify(src, ok and "success" or "error", ok and ("Marked %s"):format(Status[status].label:lower()) or err)
    return ok
end)

local FIELD_PERMISSION = { label = "edit", callsign = "edit", category = "edit", minGrade = "ranks", garage = "transfer" }

lib.callback.register("amphy_fleet:update", function(src, id, field, value)
    local permission = FIELD_PERMISSION[field]
    if not permission then return false end

    local vehicle, err = authorize(src, tonumber(id), permission)
    if not vehicle then
        notify(src, "error", err)
        return false
    end

    local ok, updateErr = Fleet.update(vehicle.id, { [field] = value }, Fleet.actor(src))
    notify(src, ok and "success" or "error", ok and "Vehicle updated" or updateErr)
    return ok
end)

lib.callback.register("amphy_fleet:add", function(src, orgName, data)
    if type(orgName) ~= "string" or type(data) ~= "table" then return false end
    local org = Config.organizations[orgName]
    if not org then return false end

    if not Permissions.can(src, orgName, "add") then
        notify(src, "error", "You are not permitted to add vehicles")
        return false
    end

    -- Non-admin managers are limited to the org's model whitelist.
    if org.models and not Permissions.isAdmin(src) and not lib.table.contains(org.models, data.model) then
        notify(src, "error", "That model is not allowed for this fleet")
        return false
    end

    local id, err = Fleet.add({
        org = orgName,
        model = data.model,
        label = data.label,
        category = data.category,
        garage = data.garage,
        callsign = data.callsign,
        plate = data.plate,
        minGrade = data.minGrade,
    }, Fleet.actor(src))

    if not id then
        notify(src, "error", err)
        return false
    end

    local vehicle = Fleet.get(id)
    notify(src, "success", ("Added %s (%s)"):format(vehicle.label, vehicle.plate))
    return true
end)

lib.callback.register("amphy_fleet:remove", function(src, id)
    local vehicle, err = authorize(src, tonumber(id), "remove")
    if not vehicle then
        notify(src, "error", err)
        return false
    end

    local ok, removeErr = Fleet.remove(vehicle.id, Fleet.actor(src))
    notify(src, ok and "success" or "error", ok and "Vehicle removed from the fleet" or removeErr)
    return ok
end)
