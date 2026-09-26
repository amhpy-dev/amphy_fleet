Status = {
    available      = { label = "Available",      icon = "circle-check",       color = "#40c057" },
    in_use         = { label = "In Use",         icon = "road",               color = "#fd7e14" },
    out_of_service = { label = "Out of Service", icon = "ban",                color = "#868e96" },
    maintenance    = { label = "Maintenance",    icon = "screwdriver-wrench", color = "#fab005" },
    impounded      = { label = "Impounded",      icon = "lock",               color = "#e64980" },
    missing        = { label = "Missing",        icon = "circle-question",    color = "#fa5252" },
}

HistoryActions = {
    created         = { label = "Added to fleet",           icon = "plus",               color = "#40c057" },
    checked_out     = { label = "Checked out",              icon = "right-from-bracket", color = "#4dabf7" },
    returned        = { label = "Returned",                 icon = "right-to-bracket",   color = "#40c057" },
    recalled        = { label = "Recalled",                 icon = "rotate-left",        color = "#fab005" },
    transferred     = { label = "Transferred",              icon = "right-left",         color = "#4dabf7" },
    impounded       = { label = "Impounded",                icon = "lock",               color = "#e64980" },
    released        = { label = "Released from impound",    icon = "lock-open",          color = "#40c057" },
    missing         = { label = "Marked missing",           icon = "circle-question",    color = "#fa5252" },
    recovered       = { label = "Recovered",                icon = "magnifying-glass",   color = "#40c057" },
    maintenance     = { label = "Sent to maintenance",      icon = "screwdriver-wrench", color = "#fab005" },
    maintenance_end = { label = "Removed from maintenance", icon = "wrench",             color = "#40c057" },
    out_of_service  = { label = "Marked out of service",    icon = "ban",                color = "#868e96" },
    in_service      = { label = "Returned to service",      icon = "circle-check",       color = "#40c057" },
    renamed         = { label = "Renamed",                  icon = "pen",                color = "#adb5bd" },
    callsign        = { label = "Callsign changed",         icon = "hashtag",            color = "#adb5bd" },
    category        = { label = "Category changed",         icon = "layer-group",        color = "#adb5bd" },
    restrictions    = { label = "Restrictions changed",     icon = "user-lock",          color = "#adb5bd" },
    lost            = { label = "Vehicle lost",             icon = "triangle-exclamation", color = "#fa5252" },
    abandoned       = { label = "Stored (abandoned)",       icon = "person-walking-arrow-right", color = "#fab005" },
    destroyed       = { label = "Destroyed",                icon = "fire",               color = "#fa5252" },
    removed         = { label = "Removed from fleet",       icon = "trash",              color = "#fa5252" },
    status          = { label = "Status changed",           icon = "arrows-rotate",      color = "#adb5bd" },
    repaired        = { label = "Repaired",                 icon = "wrench",             color = "#40c057" },
}

---Trimmed, upper-case plate for comparisons.
---@param plate string?
---@return string?
function NormalizePlate(plate)
    if type(plate) ~= "string" then return nil end
    plate = plate:gsub("^%s+", ""):gsub("%s+$", ""):upper()
    return plate ~= "" and plate or nil
end
