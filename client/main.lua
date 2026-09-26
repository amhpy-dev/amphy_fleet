Access = {}

local ACCESS_TTL = 60000
local lastRefresh, refreshing = 0, false

function RefreshAccess()
    if refreshing then return end
    refreshing = true
    Access = lib.callback.await("amphy_fleet:getAccess", false) or {}
    lastRefresh = GetGameTimer()
    refreshing = false
    TriggerEvent("amphy_fleet:client:accessChanged")
end

---(covers gang changes).
function HasAccess(orgName)
    if not refreshing and GetGameTimer() - lastRefresh > ACCESS_TTL then
        CreateThread(RefreshAccess)
    end
    return Access[orgName] ~= nil
end

AddEventHandler("prp-bridge:client:playerLoad", RefreshAccess)
AddEventHandler("prp-bridge:client:jobChanged", RefreshAccess)
AddEventHandler("prp-bridge:client:playerUnload", function()
    Access = {}
    TriggerEvent("amphy_fleet:client:accessChanged")
end)

CreateThread(function()
    if bridge.fw.getIdentifier() then RefreshAccess() end
end)

---@return table? fleet statebag { id, org }
function GetFleetState(entity)
    return entity and entity ~= 0 and DoesEntityExist(entity) and Entity(entity).state.amphy_fleet or nil
end

function RetrieveVehicle(id, garageId)
    local ok, netId = lib.callback.await("amphy_fleet:retrieve", false, id, garageId)
    if not ok then return false end

    local vehicle = lib.waitFor(function()
        if NetworkDoesNetworkIdExist(netId) then
            local entity = NetToVeh(netId)
            if entity ~= 0 and DoesEntityExist(entity) then return entity end
        end
    end, nil, 10000)

    if vehicle and Config.warpIntoVehicle then
        TaskWarpPedIntoVehicle(cache.ped, vehicle, -1)
    end

    return true
end

local storing = false

function StoreVehicle(vehicle)
    if storing or not GetFleetState(vehicle) then return end
    storing = true

    local props = lib.getVehicleProperties(vehicle)
    local fuel = Fuel.get(vehicle)

    if cache.vehicle == vehicle then
        TaskLeaveVehicle(cache.ped, vehicle, 0)
        lib.waitFor(function()
            if not IsPedInVehicle(cache.ped, vehicle, false) then return true end
        end, nil, 3000)
    end

    lib.callback.await("amphy_fleet:store", false, VehToNet(vehicle), props, fuel)
    storing = false
end

exports("IsFleetVehicle", function(entity)
    return GetFleetState(entity) ~= nil
end)

exports("GetFleetVehicleId", function(entity)
    local state = GetFleetState(entity)
    return state and state.id
end)
