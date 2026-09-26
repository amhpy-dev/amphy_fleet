-- Hooks for impound / tow scripts.
--
--   exports.amphy_fleet:ImpoundFleetVehicle(plate, reason, officerName)
--   exports.amphy_fleet:ReleaseFleetVehicle(plate, garageId?, officerName)
--
local function actorFor(name)
    return name and { name = name } or nil
end

exports("ImpoundFleetVehicle", function(plate, reason, officerName)
    local vehicle = Fleet.getByPlate(plate)
    if not vehicle then return false, "not_fleet_vehicle" end
    return Fleet.setStatus(vehicle.id, "impounded", actorFor(officerName), { note = reason })
end)

exports("ReleaseFleetVehicle", function(plate, garageId, officerName)
    local vehicle = Fleet.getByPlate(plate)
    if not vehicle then return false, "not_fleet_vehicle" end
    if vehicle.status ~= "impounded" then return false, "not_impounded" end

    if garageId and Fleet.getGarage(vehicle.org, garageId) then
        Fleet.save(vehicle.id, { garage = garageId })
    end

    return Fleet.setStatus(vehicle.id, "available", actorFor(officerName))
end)
