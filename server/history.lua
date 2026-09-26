History = {}

---@param vehicleId number
---@param action string key of HistoryActions
---@param actor { identifier?: string, name?: string }?  nil = system
---@param data table?
function History.add(vehicleId, action, actor, data)
    MySQL.insert("INSERT INTO fleet_vehicle_history (vehicle_id, action, actor_identifier, actor_name, data) VALUES (?, ?, ?, ?, ?)", {
        vehicleId,
        action,
        actor and actor.identifier or nil,
        actor and actor.name or "System",
        data and next(data) and json.encode(data) or nil,
    })
end

---@return table[]
function History.get(vehicleId, limit)
    local rows = MySQL.query.await([[
        SELECT action, actor_name, data, UNIX_TIMESTAMP(created_at) AS ts
        FROM fleet_vehicle_history
        WHERE vehicle_id = ?
        ORDER BY id DESC
        LIMIT ?
    ]], { vehicleId, limit or Config.historyLimit }) or {}

    local now = os.time()
    for i = 1, #rows do
        local row = rows[i]
        row.data = row.data and json.decode(row.data) or {}
        row.time = now - row.ts < 86400 and os.date("%H:%M", row.ts) or os.date("%d/%m %H:%M", row.ts)
    end

    return rows
end

function History.prune()
    if not Config.historyRetentionDays or Config.historyRetentionDays <= 0 then return end
    MySQL.update("DELETE FROM fleet_vehicle_history WHERE created_at < (NOW() - INTERVAL ? DAY)", { Config.historyRetentionDays })
end
