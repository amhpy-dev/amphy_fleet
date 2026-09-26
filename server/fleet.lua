Fleet = {}

local vehicles = {}     ---@type table<number, table>
local byPlate = {}      ---@type table<string, number>
local locks = {}        ---@type table<number, true> vehicles mid-checkout/return
local entityToId = {}   ---@type table<number, number>
Fleet.entities = {}     ---@type table<number, number> fleet id -> spawned entity
Fleet.offlineSince = {} ---@type table<number, number> fleet id -> os.time() holder went offline

local NULL = setmetatable({}, { __tostring = function() return "NULL" end })
Fleet.NULL = NULL

local COLUMNS = {
    label = "label", callsign = "callsign", category = "category", garage = "garage", status = "status",
    minGrade = "min_grade", holder = "current_holder", holderName = "current_holder_name",
    lastHolder = "last_holder", lastHolderName = "last_holder_name",
    checkedOutAt = "checked_out_at", returnedAt = "returned_at",
    fuel = "fuel", engine = "engine_health", body = "body_health", dirt = "dirt_level",
    properties = "properties", metadata = "metadata",
}
local TIME_COLUMNS = { checkedOutAt = true, returnedAt = true }
local JSON_COLUMNS = { properties = true, metadata = true }

local SELECT = [[
    SELECT id, org_type, org_name, model, label, plate, callsign, category, garage, status, min_grade,
        current_holder, current_holder_name, last_holder, last_holder_name,
        UNIX_TIMESTAMP(checked_out_at) AS checked_out_at, UNIX_TIMESTAMP(returned_at) AS returned_at,
        fuel, engine_health, body_health, dirt_level, properties, metadata, UNIX_TIMESTAMP(created_at) AS created_at
    FROM fleet_vehicles
]]

local function decode(value)
    if type(value) ~= "string" or value == "" then return {} end
    local ok, result = pcall(json.decode, value)
    return ok and type(result) == "table" and result or {}
end

local function fromRow(row)
    return {
        id = row.id,
        orgType = row.org_type,
        org = row.org_name,
        model = row.model,
        label = row.label,
        plate = row.plate,
        callsign = row.callsign,
        category = row.category,
        garage = row.garage,
        status = row.status,
        minGrade = row.min_grade,
        holder = row.current_holder,
        holderName = row.current_holder_name,
        lastHolder = row.last_holder,
        lastHolderName = row.last_holder_name,
        checkedOutAt = tonumber(row.checked_out_at),
        returnedAt = tonumber(row.returned_at),
        fuel = row.fuel,
        engine = row.engine_health,
        body = row.body_health,
        dirt = row.dirt_level,
        properties = decode(row.properties),
        metadata = decode(row.metadata),
        createdAt = tonumber(row.created_at),
    }
end

local function clamp(value, min, max, fallback)
    value = tonumber(value)
    if not value or value ~= value then return fallback end
    return math.min(max, math.max(min, value))
end

---@param actor { identifier?: string, name?: string }?
local function log(vehicle, action, actor, data)
    History.add(vehicle.id, action, actor, data)
    TriggerEvent("amphy_fleet:server:vehicleChanged", Fleet.public(vehicle, true), action, actor, data)
end
Fleet.log = log

---@return boolean
function Fleet.save(id, changes, expectStatus)
    local sets, params = {}, {}

    for key, value in pairs(changes) do
        local column = COLUMNS[key]
        if not column then error(("Fleet.save: unknown field '%s'"):format(key)) end

        if value == NULL then
            sets[#sets + 1] = ("`%s` = NULL"):format(column)
        elseif TIME_COLUMNS[key] then
            sets[#sets + 1] = ("`%s` = FROM_UNIXTIME(?)"):format(column)
            params[#params + 1] = value
        else
            sets[#sets + 1] = ("`%s` = ?"):format(column)
            params[#params + 1] = JSON_COLUMNS[key] and json.encode(value) or value
        end
    end

    local query = ("UPDATE fleet_vehicles SET %s WHERE id = ?"):format(table.concat(sets, ", "))
    params[#params + 1] = id

    if expectStatus then
        query = query .. " AND status = ?"
        params[#params + 1] = expectStatus
    end

    local affected = MySQL.update.await(query, params)
    if not affected or affected < 1 then return false end

    local vehicle = vehicles[id]
    if vehicle then
        for key, value in pairs(changes) do
            vehicle[key] = value ~= NULL and value or nil
        end
    end

    return true
end

function Fleet.load()
    table.wipe(vehicles)
    table.wipe(byPlate)

    local rows = MySQL.query.await(SELECT) or {}
    for i = 1, #rows do
        local vehicle = fromRow(rows[i])
        vehicles[vehicle.id] = vehicle
        byPlate[vehicle.plate] = vehicle.id
    end

    return #rows
end

function Fleet.get(id)
    return vehicles[tonumber(id)]
end

function Fleet.getByPlate(plate)
    local id = byPlate[NormalizePlate(plate) or ""]
    return id and vehicles[id]
end

---Accepts a fleet id, plate or entity handle.
function Fleet.resolve(value)
    if type(value) == "string" then return Fleet.getByPlate(value) end
    if type(value) == "number" then
        return vehicles[value] or (entityToId[value] and vehicles[entityToId[value]])
    end
end

function Fleet.all()
    return vehicles
end

function Fleet.getGarage(orgName, garageId)
    local org = Config.organizations[orgName]
    return org and org.garages[garageId]
end

function Fleet.public(vehicle, full)
    local entity = Fleet.entities[vehicle.id]
    local copy = {
        id = vehicle.id, org = vehicle.org, orgType = vehicle.orgType, model = vehicle.model,
        label = vehicle.label, plate = vehicle.plate, callsign = vehicle.callsign,
        category = vehicle.category, garage = vehicle.garage, status = vehicle.status,
        minGrade = vehicle.minGrade, holderName = vehicle.holderName, lastHolderName = vehicle.lastHolderName,
        checkedOutAt = vehicle.checkedOutAt, returnedAt = vehicle.returnedAt,
        fuel = vehicle.fuel, engine = vehicle.engine, body = vehicle.body, dirt = vehicle.dirt,
        netId = entity and DoesEntityExist(entity) and NetworkGetNetworkIdFromEntity(entity) or nil,
    }

    if full then
        copy.holder = vehicle.holder
        copy.lastHolder = vehicle.lastHolder
        copy.properties = vehicle.properties
        copy.metadata = vehicle.metadata
        copy.entity = entity
    end

    return copy
end

function Fleet.actor(src)
    local identifier = bridge.fw.getIdentifier(src)
    return {
        source = src,
        identifier = identifier,
        name = identifier and bridge.fw.getCharacterName(identifier) or GetPlayerName(src),
    }
end

---------------------------------------------------------------------------
-- Entities
---------------------------------------------------------------------------

function Fleet.track(id, entity)
    Fleet.entities[id] = entity
    entityToId[entity] = id
    Fleet.offlineSince[id] = nil
end

function Fleet.untrack(id)
    local entity = Fleet.entities[id]
    if entity then entityToId[entity] = nil end
    Fleet.entities[id] = nil
    Fleet.offlineSince[id] = nil
end

function Fleet.idFromEntity(entity)
    return entityToId[entity]
end

function Fleet.despawn(id)
    local entity = Fleet.entities[id]
    Fleet.untrack(id)
    if entity and DoesEntityExist(entity) then DeleteEntity(entity) end
end

function Fleet.isOccupied(entity)
    for seat = -1, 6 do
        if GetPedInVehicleSeat(entity, seat) ~= 0 then return true end
    end
    return false
end

function Fleet.readCondition(entity, fallback)
    return {
        engine = clamp(GetVehicleEngineHealth(entity), 0, 1000, fallback.engine),
        body = clamp(GetVehicleBodyHealth(entity), 0, 1000, fallback.body),
        dirt = clamp(GetVehicleDirtLevel(entity), 0, 15, fallback.dirt),
    }
end

local function findSpawn(garage)
    local world = GetAllVehicles()
    for _, spawn in ipairs(garage.spawns) do
        local point, blocked = spawn.xyz, false
        for i = 1, #world do
            if #(GetEntityCoords(world[i]) - point) < 3.0 then
                blocked = true
                break
            end
        end
        if not blocked then return spawn end
    end
end

local function findReturnGarage(orgName, coords)
    for garageId, garage in pairs(Config.organizations[orgName].garages) do
        for _, point in ipairs(garage.returns or {}) do
            if #(coords - point.coords) <= (point.radius or 6.0) then return garageId end
        end
    end
end

local function countHeld(identifier, orgName)
    local count = 0
    for _, vehicle in pairs(vehicles) do
        if vehicle.holder == identifier and vehicle.org == orgName and vehicle.status == "in_use" then
            count += 1
        end
    end
    return count
end

---------------------------------------------------------------------------
-- Checkout / return
---------------------------------------------------------------------------

---@return boolean ok
---@return string|number result error message, or netId on success
function Fleet.checkout(src, id, garageId)
    local vehicle = vehicles[id]
    if not vehicle then return false, "Vehicle not found" end

    local org = Config.organizations[vehicle.org]
    local garage = org.garages[garageId]
    if not garage then return false, "Invalid garage" end

    if #(GetEntityCoords(GetPlayerPed(src)) - garage.coords) > Config.interactDistance then
        return false, "You are too far from the garage"
    end

    if vehicle.status ~= "available" then return false, "This vehicle is not available" end
    if locks[id] then return false, "This vehicle is already being retrieved" end

    if vehicle.garage ~= garageId and not (garage.remote or Config.remoteRetrieval) then
        local home = org.garages[vehicle.garage]
        return false, ("This vehicle is stored at %s"):format(home and home.label or vehicle.garage)
    end

    local allowed, reason = Permissions.canRetrieve(src, vehicle)
    if not allowed then return false, reason end

    local actor = Fleet.actor(src)
    if not actor.identifier then return false, "Character not loaded" end

    if Config.maxCheckedOut > 0 and countHeld(actor.identifier, vehicle.org) >= Config.maxCheckedOut then
        return false, "You already have a fleet vehicle checked out"
    end

    local spawn = findSpawn(garage)
    if not spawn then return false, "All parking spots are blocked" end

    -- above is synchronous
    locks[id] = true

    local claimed = Fleet.save(id, {
        status = "in_use",
        holder = actor.identifier,
        holderName = actor.name,
        checkedOutAt = os.time(),
    }, "available")

    if not claimed then
        locks[id] = nil
        return false, "This vehicle is no longer available"
    end

    local ok, entity = pcall(exports["prp-bridge"].SpawnTemporaryVehicle, exports["prp-bridge"], {
        model = vehicle.model,
        coords = spawn.xyz,
        heading = spawn.w,
        plate = vehicle.plate,
    })

    if not ok or not entity or not DoesEntityExist(entity) then
        Fleet.save(id, { status = "available", holder = NULL, holderName = NULL }, "in_use")
        locks[id] = nil
        lib.print.error(("failed to spawn fleet vehicle %d (%s): %s"):format(id, vehicle.model, ok and "no entity" or entity))
        return false, "Failed to spawn the vehicle"
    end

    Fleet.track(id, entity)
    SetEntityOrphanMode(entity, 2)

    local props = lib.table.deepclone(vehicle.properties)
    props.plate = vehicle.plate
    props.fuelLevel = vehicle.fuel
    props.engineHealth = vehicle.engine
    props.bodyHealth = vehicle.body
    props.dirtLevel = vehicle.dirt

    local state = Entity(entity).state
    state:set("amphy_fleet", { id = id, org = vehicle.org }, true)
    state:set("setVehicleProperties", props, true) -- applied by ox_lib on the owning client

    Fuel.set(src, entity, vehicle.fuel)
    Keys.give(src, entity, vehicle.plate)

    locks[id] = nil
    log(vehicle, "checked_out", actor, { garage = garage.label })

    return true, NetworkGetNetworkIdFromEntity(entity)
end

local function sanitizeProps(vehicle, props)
    if type(props) ~= "table" then return vehicle.properties end
    if props.model and props.model ~= joaat(vehicle.model) then return vehicle.properties end

    props.plate = vehicle.plate
    local encoded = json.encode(props)
    if #encoded > 32768 then return vehicle.properties end

    return props
end

---@return boolean, string?
function Fleet.store(src, netId, props, fuel)
    local entity = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false, "Vehicle not found" end

    local id = entityToId[entity]
    local vehicle = id and vehicles[id]
    if not vehicle then return false, "This is not a fleet vehicle" end
    if vehicle.status ~= "in_use" then return false, "This vehicle is not checked out" end

    if NormalizePlate(GetVehicleNumberPlateText(entity)) ~= vehicle.plate then
        return false, "The plate does not match fleet records"
    end

    local actor = Fleet.actor(src)
    if actor.identifier ~= vehicle.holder and not Permissions.can(src, vehicle.org, "store") then
        return false, "You are not permitted to return this vehicle"
    end

    local coords = GetEntityCoords(entity)
    if #(GetEntityCoords(GetPlayerPed(src)) - coords) > 10.0 then return false, "You are too far from the vehicle" end

    local garageId = findReturnGarage(vehicle.org, coords)
    if not garageId then return false, "Not at a fleet return point" end

    local org = Config.organizations[vehicle.org]
    if not Config.storeAtAnyGarage and garageId ~= vehicle.garage then
        local home = org.garages[vehicle.garage]
        return false, ("This vehicle belongs to %s"):format(home and home.label or vehicle.garage)
    end

    if locks[id] then return false, "This vehicle is busy" end
    locks[id] = true

    local condition = Fleet.readCondition(entity, vehicle)
    local limits = Config.autoMaintenance
    local status = (condition.engine < limits.engine or condition.body < limits.body) and "maintenance" or "available"
    local holder, holderName = vehicle.holder, vehicle.holderName

    local saved = Fleet.save(id, {
        status = status,
        holder = NULL,
        holderName = NULL,
        lastHolder = holder,
        lastHolderName = holderName,
        returnedAt = os.time(),
        garage = garageId,
        fuel = clamp(fuel, 0, 100, vehicle.fuel),
        engine = condition.engine,
        body = condition.body,
        dirt = condition.dirt,
        properties = sanitizeProps(vehicle, props),
    }, "in_use")

    locks[id] = nil
    if not saved then return false, "Failed to return the vehicle" end

    Keys.remove(holder and bridge.fw.getSrcFromIdentifier(holder), entity, vehicle.plate)
    Fleet.despawn(id)

    log(vehicle, "returned", actor, {
        garage = org.garages[garageId].label,
        engine = math.floor(condition.engine),
        body = math.floor(condition.body),
        fuel = math.floor(vehicle.fuel),
        holder = holder ~= actor.identifier and holderName or nil,
    })

    if status == "maintenance" then
        log(vehicle, "maintenance", nil, { note = "Returned damaged" })
    end

    return true, status
end

---------------------------------------------------------------------------
-- Status
---------------------------------------------------------------------------

local function transitionAction(from, to)
    if to == "missing" then return "missing" end
    if to == "impounded" then return "impounded" end
    if to == "maintenance" then return "maintenance" end
    if to == "out_of_service" then return "out_of_service" end
    if from == "missing" then return "recovered" end
    if from == "impounded" then return "released" end
    if from == "maintenance" then return "maintenance_end" end
    if from == "out_of_service" then return "in_service" end
    if from == "in_use" then return "recalled" end
    return "status"
end

---@param opts { note?: string, force?: boolean, keepEntity?: boolean, action?: string }?
---@return boolean, string?
function Fleet.setStatus(id, status, actor, opts)
    opts = opts or {}
    local vehicle = vehicles[id]
    if not vehicle then return false, "Vehicle not found" end
    if not Status[status] or status == "in_use" then return false, "Invalid status" end

    local from = vehicle.status
    if from == status then return false, ("Vehicle is already %s"):format(Status[status].label:lower()) end
    if locks[id] then return false, "This vehicle is busy" end

    local changes = { status = status }
    local entity = Fleet.entities[id]
    local exists = entity and DoesEntityExist(entity)

    if from == "in_use" then
        if exists and not opts.keepEntity then
            if not opts.force and Fleet.isOccupied(entity) then return false, "The vehicle is occupied" end
            local condition = Fleet.readCondition(entity, vehicle)
            changes.engine, changes.body, changes.dirt = condition.engine, condition.body, condition.dirt
        end

        changes.holder = NULL
        changes.holderName = NULL
        changes.lastHolder = vehicle.holder or NULL
        changes.lastHolderName = vehicle.holderName or NULL
        changes.returnedAt = os.time()
    end

    locks[id] = true
    local saved = Fleet.save(id, changes, from)
    locks[id] = nil
    if not saved then return false, "Failed to update the vehicle" end

    if from == "in_use" then
        if opts.keepEntity then Fleet.untrack(id) else Fleet.despawn(id) end
    end

    log(vehicle, opts.action or transitionAction(from, status), actor, { note = opts.note, from = Status[from].label })
    return true
end

---Entity vanished while checked out?
function Fleet.markLost(id, reason)
    local vehicle = vehicles[id]
    Fleet.untrack(id)
    if not vehicle or vehicle.status ~= "in_use" then return end

    Fleet.setStatus(id, Config.recovery.lostStatus, nil, { keepEntity = true, action = "lost", note = reason })
end

---------------------------------------------------------------------------
-- Edit / add / remove
---------------------------------------------------------------------------

local EDITS = {
    label = function(vehicle, value)
        value = type(value) == "string" and value:gsub("^%s+", ""):gsub("%s+$", "") or ""
        if #value < 1 or #value > 64 then return nil, "Name must be 1-64 characters" end
        return value, "renamed", { from = vehicle.label, to = value }
    end,
    callsign = function(vehicle, value)
        value = type(value) == "string" and value:gsub("%s", ""):upper() or ""
        if #value > 16 then return nil, "Callsign must be at most 16 characters" end
        return value == "" and NULL or value, "callsign", { from = vehicle.callsign or "None", to = value ~= "" and value or "None" }
    end,
    category = function(vehicle, value, org)
        if not org.categories[value] then return nil, "Invalid category" end
        return value, "category", { from = org.categories[vehicle.category] and org.categories[vehicle.category].label or vehicle.category, to = org.categories[value].label }
    end,
    garage = function(vehicle, value, org)
        if not org.garages[value] then return nil, "Invalid garage" end
        if vehicle.status == "in_use" then return nil, "Vehicle is checked out" end
        return value, "transferred", { from = org.garages[vehicle.garage] and org.garages[vehicle.garage].label or vehicle.garage, to = org.garages[value].label }
    end,
    minGrade = function(vehicle, value)
        value = math.tointeger(tonumber(value))
        if not value or value < 0 or value > 255 then return nil, "Invalid rank" end
        return value, "restrictions", { from = Permissions.gradeLabel(vehicle.org, vehicle.minGrade), to = Permissions.gradeLabel(vehicle.org, value) }
    end,
    metadata = function(_, value)
        if type(value) ~= "table" then return nil, "Metadata must be a table" end
        return value, "restrictions", nil
    end,
}

-- API-only
local CONDITION = { engine = { 0, 1000 }, body = { 0, 1000 }, fuel = { 0, 100 }, dirt = { 0, 15 } }

---@return boolean, string?
function Fleet.update(id, changes, actor)
    local vehicle = vehicles[id]
    if not vehicle then return false, "Vehicle not found" end
    local org = Config.organizations[vehicle.org]

    local apply, logs = {}, {}
    for field, value in pairs(changes) do
        if EDITS[field] then
            local result, action, data = EDITS[field](vehicle, value, org)
            if result == nil then return false, action end
            apply[field] = result
            logs[#logs + 1] = { action, data }
        elseif CONDITION[field] then
            apply[field] = clamp(value, CONDITION[field][1], CONDITION[field][2], vehicle[field])
        else
            return false, ("Unknown field '%s'"):format(field)
        end
    end

    if not next(apply) then return false, "Nothing to change" end
    if not Fleet.save(id, apply) then return false, "Failed to update the vehicle" end

    for _, entry in ipairs(logs) do log(vehicle, entry[1], actor, entry[2]) end
    if apply.engine or apply.body then
        log(vehicle, "repaired", actor, { engine = math.floor(vehicle.engine), body = math.floor(vehicle.body) })
    end

    return true
end

local function plateTaken(plate)
    if byPlate[plate] then return true end
    if MySQL.scalar.await("SELECT 1 FROM fleet_vehicles WHERE plate = ? LIMIT 1", { plate }) then return true end
    return bridge.fw.getOwnedVehicleByPlate(plate) ~= nil
end

local function generatePlate(prefix)
    prefix = (prefix or ""):upper():gsub("[^%w]", ""):sub(1, 4)
    local digits = 8 - #prefix
    for _ = 1, 50 do
        local plate = prefix .. tostring(math.random(10 ^ (digits - 1), 10 ^ digits - 1))
        if not plateTaken(plate) then return plate end
    end
end

---@param data { org: string, model: string, category: string, garage: string, label?: string, plate?: string, callsign?: string, minGrade?: number, metadata?: table }
---@return number?, string?
function Fleet.add(data, actor)
    local org = Config.organizations[data.org]
    if not org then return nil, "Invalid organisation" end

    local model = type(data.model) == "string" and data.model:lower() or ""
    if not model:match("^[%w_]+$") or #model > 50 then return nil, "Invalid model" end
    if not org.categories[data.category] then return nil, "Invalid category" end
    if not org.garages[data.garage] then return nil, "Invalid garage" end

    local plate = NormalizePlate(data.plate)
    if plate then
        if #plate > 8 or not plate:match("^[%w ]+$") then return nil, "Plates are max 8 letters/numbers" end
        if plateTaken(plate) then return nil, "That plate is already in use" end
    else
        plate = generatePlate(org.platePrefix)
        if not plate then return nil, "Could not generate a unique plate" end
    end

    local label = type(data.label) == "string" and data.label ~= "" and data.label:sub(1, 64) or nil
    if not label then
        local info = exports["prp-bridge"]:GetVehicleData(model)
        label = info and info.label or model:upper()
    end

    local callsign = type(data.callsign) == "string" and data.callsign:gsub("%s", ""):upper():sub(1, 16) or nil
    if callsign == "" then callsign = nil end
    local minGrade = math.tointeger(tonumber(data.minGrade)) or 0
    local metadata = type(data.metadata) == "table" and data.metadata or {}

    local id = MySQL.insert.await([[
        INSERT INTO fleet_vehicles (org_type, org_name, model, label, plate, callsign, category, garage, min_grade, metadata)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], { org.type, data.org, model, label, plate, callsign, data.category, data.garage, minGrade, json.encode(metadata) })

    if not id then return nil, "Database error" end

    local row = MySQL.single.await(SELECT .. " WHERE id = ?", { id })
    local vehicle = fromRow(row)
    vehicles[id] = vehicle
    byPlate[plate] = id

    log(vehicle, "created", actor, { model = model, plate = plate, garage = org.garages[data.garage].label })
    return id
end

---@return boolean, string?
function Fleet.remove(id, actor)
    local vehicle = vehicles[id]
    if not vehicle then return false, "Vehicle not found" end
    if vehicle.status == "in_use" then return false, "Vehicle is checked out" end
    if locks[id] then return false, "This vehicle is busy" end

    local affected = MySQL.update.await("DELETE FROM fleet_vehicles WHERE id = ? AND status <> 'in_use'", { id })
    if not affected or affected < 1 then return false, "Failed to remove the vehicle" end

    vehicles[id] = nil
    byPlate[vehicle.plate] = nil
    log(vehicle, "removed", actor, { plate = vehicle.plate, model = vehicle.model })

    return true
end

---------------------------------------------------------------------------
-- Menu view model
---------------------------------------------------------------------------

---Everything the client needs
function Fleet.buildView(src, orgName, garageId)
    local org = Config.organizations[orgName]
    if not org then return nil, "Invalid organisation" end
    if not Permissions.isMember(src, orgName) and not Permissions.isAdmin(src) then
        return nil, "You are not a member of this organisation"
    end

    local garage = garageId and org.garages[garageId]
    local list, counts = {}, {}

    for _, vehicle in pairs(vehicles) do
        if vehicle.org == orgName then
            local entry = Fleet.public(vehicle)
            local category = org.categories[vehicle.category] or {}
            local home = org.garages[vehicle.garage]
            local effectiveGrade = math.max(vehicle.minGrade or 0, category.minGrade or 0)

            entry.garageLabel = home and home.label or vehicle.garage
            entry.categoryLabel = category.label or vehicle.category
            entry.minGradeLabel = Permissions.gradeLabel(orgName, effectiveGrade)
            entry.atGarage = vehicle.garage == garageId

            if vehicle.status ~= "available" then
                entry.reason = vehicle.status == "in_use" and ("Checked out by %s"):format(vehicle.holderName or "Unknown") or Status[vehicle.status].label
            elseif not garage then
                entry.reason = "Not at a garage"
            elseif not entry.atGarage and not (garage.remote or Config.remoteRetrieval) then
                entry.reason = ("Stored at %s"):format(entry.garageLabel)
            else
                entry.canRetrieve, entry.reason = Permissions.canRetrieve(src, vehicle)
            end

            local count = counts[vehicle.category] or { total = 0, available = 0 }
            count.total += 1
            if vehicle.status == "available" and (entry.atGarage or not garage) then count.available += 1 end
            counts[vehicle.category] = count

            list[#list + 1] = entry
        end
    end

    table.sort(list, function(a, b)
        if a.category ~= b.category then return a.category < b.category end
        return (a.callsign or a.plate) < (b.callsign or b.plate)
    end)

    local categories = {}
    for id, category in pairs(org.categories) do
        local count = counts[id] or { total = 0, available = 0 }
        categories[#categories + 1] = {
            id = id, label = category.label, icon = category.icon, iconColor = category.iconColor,
            total = count.total, available = count.available,
            minGradeLabel = category.minGrade and Permissions.gradeLabel(orgName, category.minGrade) or nil,
        }
    end
    table.sort(categories, function(a, b) return a.label < b.label end)

    local garages = {}
    for id, g in pairs(org.garages) do garages[#garages + 1] = { value = id, label = g.label } end
    table.sort(garages, function(a, b) return a.label < b.label end)

    local grades = {}
    for grade, label in pairs(org.grades or { [0] = "Any" }) do grades[#grades + 1] = { value = grade, label = label } end
    table.sort(grades, function(a, b) return a.value < b.value end)

    return {
        org = { name = orgName, label = org.label, icon = org.icon, type = org.type },
        garage = garage and { id = garageId, label = garage.label } or nil,
        perms = Permissions.resolve(src, orgName),
        vehicles = list,
        categories = categories,
        garages = garages,
        grades = grades,
        models = org.models,
        now = os.time(),
    }
end
