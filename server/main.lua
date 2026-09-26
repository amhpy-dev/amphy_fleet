local ready = false

local function installSchema()
    local sql = LoadResourceFile(GetCurrentResourceName(), "sql/install.sql")
    if not sql then return lib.print.error("sql/install.sql missing") end

    sql = sql:gsub("%-%-[^\n]*", "")
    for statement in sql:gmatch("[^;]+") do
        if statement:find("%S") then MySQL.query.await(statement) end
    end
end

local function reconcile()
    local found, relinked = {}, 0

    for _, entity in ipairs(GetAllVehicles()) do
        local state = Entity(entity).state.amphy_fleet
        if state and state.id then
            local vehicle = Fleet.get(state.id)
            local valid = vehicle and vehicle.status == "in_use" and not found[vehicle.id]
                and NormalizePlate(GetVehicleNumberPlateText(entity)) == vehicle.plate

            if valid then
                found[vehicle.id] = true
                relinked += 1
                Fleet.track(vehicle.id, entity)
            else
                DeleteEntity(entity) -- stale copy or duplicate of an already-linked vehicle
            end
        end
    end

    local lost = {}
    for id, vehicle in pairs(Fleet.all()) do
        if vehicle.status == "in_use" and not found[id] then lost[#lost + 1] = id end
    end

    for _, id in ipairs(lost) do
        Fleet.markLost(id, "Not found after restart")
    end

    return relinked, #lost
end

local function sweep()
    local now = os.time()
    local ids = {}
    for id in pairs(Fleet.entities) do ids[#ids + 1] = id end

    for _, id in ipairs(ids) do
        local entity = Fleet.entities[id]
        local vehicle = Fleet.get(id)

        if not entity or not vehicle then
            Fleet.untrack(id)
        elseif not DoesEntityExist(entity) then
            Fleet.markLost(id, "Vehicle no longer exists")
        elseif not Fleet.isOccupied(entity) then
            if GetEntityHealth(entity) <= 0 or GetVehicleEngineHealth(entity) <= -3999.0 then
                Fleet.setStatus(id, "maintenance", nil, { action = "destroyed", note = "Recovered wrecked" })
            elseif vehicle.holder and not bridge.fw.getSrcFromIdentifier(vehicle.holder) then
                Fleet.offlineSince[id] = Fleet.offlineSince[id] or now
                if now - Fleet.offlineSince[id] >= Config.recovery.abandonedMinutes * 60 then
                    Fleet.setStatus(id, Config.recovery.abandonedStatus, nil, { action = "abandoned", note = "Holder offline" })
                end
            else
                Fleet.offlineSince[id] = nil
            end
        end
    end
end

CreateThread(function()
    installSchema()
    local count = Fleet.load()
    local relinked, lost = reconcile()
    History.prune()
    ready = true

    lib.print.info(("loaded %d fleet vehicles (%d relinked, %d lost)"):format(count, relinked, lost))

    while true do
        Wait(Config.recovery.sweepInterval * 60000)
        local ok, err = pcall(sweep)
        if not ok then lib.print.error("sweep failed:", err) end
    end
end)

-- Our own despawns untrack first, so anything reaching here was removed externally.
AddEventHandler("entityRemoved", function(entity)
    if not ready then return end
    local id = Fleet.idFromEntity(entity)
    if not id then return end

    Fleet.untrack(id)
    CreateThread(function()
        Fleet.markLost(id, "Vehicle was deleted")
    end)
end)

local function stampOffline(src)
    local identifier = bridge.fw.getIdentifier(src)
    if not identifier then return end

    for id in pairs(Fleet.entities) do
        local vehicle = Fleet.get(id)
        if vehicle and vehicle.holder == identifier then
            Fleet.offlineSince[id] = Fleet.offlineSince[id] or os.time()
        end
    end
end

AddEventHandler("playerDropped", function()
    pcall(stampOffline, source)
end)

AddEventHandler("prp-bridge:server:playerUnload", function(src)
    pcall(stampOffline, src)
end)

bridge.fw.registerCommand(Config.adminCommand, "Open fleet management for any organisation", nil, "group.admin", function(src)
    if src <= 0 then return end
    local orgs = {}
    for name, org in pairs(Config.organizations) do
        orgs[#orgs + 1] = { name = name, label = org.label, icon = org.icon, type = org.type }
    end
    table.sort(orgs, function(a, b) return a.label < b.label end)
    TriggerClientEvent("amphy_fleet:client:admin", src, orgs)
end)

---------------------------------------------------------------------------
-- Exports (impound, MDT, mechanic and admin integrations)
-- Vehicles can be referenced by fleet id, plate or entity handle.
---------------------------------------------------------------------------

local function public(value)
    local vehicle = Fleet.resolve(value)
    return vehicle and Fleet.public(vehicle, true) or nil
end

exports("IsFleetVehicle", function(value)
    return Fleet.resolve(value) ~= nil
end)

exports("GetFleetVehicle", public)
exports("GetFleetVehicleByPlate", public)

exports("GetFleetVehicleState", function(value)
    local vehicle = Fleet.resolve(value)
    if not vehicle then return nil end
    local entity = Fleet.entities[vehicle.id]

    return {
        status = vehicle.status,
        holder = vehicle.holder,
        holderName = vehicle.holderName,
        lastHolder = vehicle.lastHolder,
        lastHolderName = vehicle.lastHolderName,
        checkedOutAt = vehicle.checkedOutAt,
        returnedAt = vehicle.returnedAt,
        garage = vehicle.garage,
        entity = entity,
        netId = entity and DoesEntityExist(entity) and NetworkGetNetworkIdFromEntity(entity) or nil,
    }
end)

---@param opts { note?: string, actorName?: string, force?: boolean, keepEntity?: boolean }?
exports("SetFleetVehicleState", function(value, status, opts)
    local vehicle = Fleet.resolve(value)
    if not vehicle then return false, "not_fleet_vehicle" end
    opts = opts or {}
    return Fleet.setStatus(vehicle.id, status, opts.actorName and { name = opts.actorName }, opts)
end)

exports("GetFleetVehicleHistory", function(value, limit)
    local vehicle = Fleet.resolve(value)
    return vehicle and History.get(vehicle.id, limit) or nil
end)

exports("GetOrganizationFleet", function(orgName)
    local list = {}
    for _, vehicle in pairs(Fleet.all()) do
        if vehicle.org == orgName then list[#list + 1] = Fleet.public(vehicle, true) end
    end
    return list
end)

exports("AddFleetVehicle", function(data, actorName)
    return Fleet.add(data, actorName and { name = actorName })
end)

exports("RemoveFleetVehicle", function(value, actorName)
    local vehicle = Fleet.resolve(value)
    if not vehicle then return false, "not_fleet_vehicle" end
    return Fleet.remove(vehicle.id, actorName and { name = actorName })
end)

---changes: label, callsign, category, garage, minGrade, metadata, engine, body, fuel, dirt
exports("UpdateFleetVehicle", function(value, changes, actorName)
    local vehicle = Fleet.resolve(value)
    if not vehicle then return false, "not_fleet_vehicle" end
    return Fleet.update(vehicle.id, changes, actorName and { name = actorName })
end)
