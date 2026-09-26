Fuel = {}

if IsDuplicityVersion() then
    function Fuel.set(src, vehicle, amount)
        if not Config.integrations.fuel then return end
        local ok, err = pcall(bridge.vfuel.set, src, vehicle, amount)
        if not ok then lib.print.warn("fuel.set failed:", err) end
    end
else
    ---@return number?
    function Fuel.get(vehicle)
        if not Config.integrations.fuel then return GetVehicleFuelLevel(vehicle) end
        local ok, value = pcall(bridge.vfuel.get, vehicle)
        return ok and tonumber(value) or GetVehicleFuelLevel(vehicle)
    end
end
