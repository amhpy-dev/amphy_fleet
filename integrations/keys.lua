Keys = {}

function Keys.give(src, vehicle, plate)
    if not Config.integrations.keys or not src then return end
    local ok, err = pcall(bridge.vkeys.give, src, vehicle, plate)
    if not ok then lib.print.warn("keys.give failed:", err) end
end

function Keys.remove(src, vehicle, plate)
    if not Config.integrations.keys or not src then return end
    local ok, err = pcall(bridge.vkeys.remove, src, vehicle, plate)
    if not ok then lib.print.warn("keys.remove failed:", err) end
end
