fx_version "cerulean"
game "gta5"
lua54 "yes"

author "Amphy"
description "Departmental & gang shared fleet vehicles"
-- no `version` field on purpose: prp-bridge's import.lua would try to version-check this resource against its GitHub repo

dependencies {
    "ox_lib",
    "oxmysql",
    "prp-bridge",
}

shared_scripts {
    "@ox_lib/init.lua",
    "@prp-bridge/import.lua",
    "config.lua",
    "shared/constants.lua",
}

client_scripts {
    "integrations/fuel.lua",
    "client/main.lua",
    "client/menus.lua",
    "client/garages.lua",
}

server_scripts {
    "@oxmysql/lib/MySQL.lua",
    "integrations/keys.lua",
    "integrations/fuel.lua",
    "server/history.lua",
    "server/permissions.lua",
    "server/fleet.lua",
    "server/callbacks.lua",
    "integrations/impound.lua",
    "server/main.lua",
}
