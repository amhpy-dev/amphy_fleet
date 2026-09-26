local currentReturn -- { org, garage } 
local blips = {}

local keybind = lib.addKeybind({
    name = "amphy_fleet_store",
    description = "Return fleet vehicle",
    defaultKey = "E",
    disabled = true,
    onPressed = function()
        local vehicle = cache.vehicle
        local state = vehicle and GetFleetState(vehicle)
        if not currentReturn or not state or state.org ~= currentReturn.org or cache.seat ~= -1 then return end
        StoreVehicle(vehicle)
    end,
})

local function updatePrompt()
    local state = cache.vehicle and GetFleetState(cache.vehicle)
    local active = currentReturn and state and state.org == currentReturn.org and cache.seat == -1

    keybind:disable(not active)
    if active then
        bridge.fw.showTextUI("[E] Return to Fleet", { icon = "square-parking", position = "left-center" })
    else
        local open, text = bridge.fw.isTextUIOpen()
        if open and text == "[E] Return to Fleet" then bridge.fw.hideTextUI() end
    end
end

lib.onCache("vehicle", function() SetTimeout(0, updatePrompt) end)
lib.onCache("seat", function() SetTimeout(0, updatePrompt) end)

local function refreshBlips()
    for _, blip in ipairs(blips) do RemoveBlip(blip) end
    table.wipe(blips)

    for orgName, org in pairs(Config.organizations) do
        if Access[orgName] then
            for _, garage in pairs(org.garages) do
                if garage.blip then
                    local blip = AddBlipForCoord(garage.coords.x, garage.coords.y, garage.coords.z)
                    SetBlipSprite(blip, garage.blip.sprite or 357)
                    SetBlipColour(blip, garage.blip.color or 0)
                    SetBlipScale(blip, garage.blip.scale or 0.7)
                    SetBlipAsShortRange(blip, true)
                    BeginTextCommandSetBlipName("STRING")
                    AddTextComponentSubstringPlayerName(("%s Fleet"):format(org.label))
                    EndTextCommandSetBlipName(blip)
                    blips[#blips + 1] = blip
                end
            end
        end
    end
end

AddEventHandler("amphy_fleet:client:accessChanged", refreshBlips)

for orgName, org in pairs(Config.organizations) do
    for garageId, garage in pairs(org.garages) do
        local id = ("amphy_fleet_%s_%s"):format(orgName, garageId)

        local options = {
            {
                name = id .. "_open",
                label = ("%s Fleet"):format(org.label),
                icon = "fa-solid fa-" .. (org.icon or "car"),
                distance = 2.5,
                canInteract = function() return HasAccess(orgName) end,
                onSelect = function() Menus.openGarage(orgName, garageId) end,
            },
            {
                name = id .. "_manage",
                label = "Fleet Management",
                icon = "fa-solid fa-gears",
                distance = 2.5,
                canInteract = function() return HasAccess(orgName) and Access[orgName].manage end,
                onSelect = function() Menus.openManagement(orgName, garageId) end,
            },
        }

        if garage.ped then
            exports["prp-bridge"]:AddPedInteraction(id, {
                model = garage.ped,
                coords = vec3(garage.coords.x, garage.coords.y, garage.coords.z - 1.0),
                heading = garage.heading or 0.0,
                radius = 50.0,
                options = options,
            })
        else
            bridge.target.addSphereZone({ name = id, coords = garage.coords, radius = garage.radius or 1.5, options = options })
        end

        for _, point in ipairs(garage.returns or {}) do
            lib.zones.sphere({
                coords = point.coords,
                radius = point.radius or 6.0,
                onEnter = function()
                    currentReturn = { org = orgName, garage = garageId }
                    updatePrompt()
                end,
                onExit = function()
                    currentReturn = nil
                    updatePrompt()
                end,
            })
        end
    end
end

-- On foot: target the vehicle while standing in a return zone.
bridge.target.addGlobalVehicle({
    {
        name = "amphy_fleet_store_vehicle",
        label = "Return to Fleet",
        icon = "fa-solid fa-square-parking",
        distance = 3.0,
        canInteract = function(entity)
            local state = currentReturn and GetFleetState(entity)
            return state ~= nil and state.org == currentReturn.org and not cache.vehicle
        end,
        onSelect = function(data) StoreVehicle(data.entity) end,
    },
})

AddEventHandler("onResourceStop", function(resource)
    if resource ~= GetCurrentResourceName() then return end
    local open, text = bridge.fw.isTextUIOpen()
    if open and text == "[E] Return to Fleet" then bridge.fw.hideTextUI() end
    bridge.target.removeGlobalVehicle("amphy_fleet_store_vehicle")
end)
