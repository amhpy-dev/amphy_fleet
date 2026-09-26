Config = {}

Config.debug = false

-- Admins (bridge.fw.isAdmin) bypass every fleet permission check.
Config.adminBypass = true
Config.adminCommand = "fleetadmin"

-- Max vehicles one character may have checked out per organisation (0 = unlimited).
Config.maxCheckedOut = 1

-- Retrieve a vehicle stored at another garage of the same org (per-garage `remote = true` also works).
Config.remoteRetrieval = false

-- true: returning at any garage of the org stores it there. false: must return to its own garage.
Config.storeAtAnyGarage = true

-- Put the player in the driver seat after retrieval.
Config.warpIntoVehicle = true

-- How close (metres) the player must be to the garage interaction point to retrieve.
Config.interactDistance = 10.0

Config.historyLimit = 25
Config.historyRetentionDays = 90

-- Vehicles returned below these values go straight to maintenance.
Config.autoMaintenance = { engine = 300.0, body = 300.0 }

Config.recovery = {
    -- in_use vehicles whose entity no longer exists (server restart, deleted, cleaned up)
    lostStatus = "missing",
    -- holder offline this long and vehicle unoccupied -> vehicle is stored automatically
    abandonedMinutes = 30,
    abandonedStatus = "available",
    -- how often tracked vehicles are checked (minutes)
    sweepInterval = 3,
}

Config.integrations = {
    keys = true, -- bridge.vkeys
    fuel = true, -- bridge.vfuel
}

-- Qualifications (divisions) are checked through prp-bridge allowlists by default:
--   /add_allowlist <id> swat
-- Other resources can replace this with exports.amphy_fleet:RegisterQualificationProvider(fn)

--[[
    Organisations
    type         "job" | "gang"
    requireDuty  job orgs only, required to retrieve
    platePrefix  up to 4 chars, used for generated plates
    grades       optional grade -> label map for display ("Minimum Rank: Officer")
    models       optional whitelist of models non-admin managers may add
    permissions  action -> minimum grade
        retrieve   check vehicles out (still subject to vehicle/category rank)
        store      return vehicles (holders can always return their own)
        history    view vehicle history
        status     out of service / maintenance / impound release
        manage     management menu, deployed list, recall deployed vehicles
        edit       rename / callsign / category
        ranks      change minimum rank
        transfer   move between garages
        missing    mark missing / recovered
        add, remove
    categories   id -> { label, icon, iconColor?, minGrade?, qualifications? }
    garages      id -> { label, coords, radius?, ped?, heading?, remote?, blip?, spawns = { vec4 }, returns = { { coords, radius } } }
]]
Config.organizations = {
    police = {
        type = "job",
        label = "LSPD",
        icon = "shield-halved",
        requireDuty = true,
        platePrefix = "LSPD",
        grades = { [0] = "Cadet", [1] = "Officer", [2] = "Senior Officer", [3] = "Sergeant", [4] = "Lieutenant", [5] = "Captain", [6] = "Chief" },
        models = { "police", "police2", "police3", "police4", "policeb", "fbi", "fbi2", "riot", "sheriff2" },
        permissions = {
            retrieve = 0, store = 0, history = 0,
            status = 2, manage = 3, edit = 3, ranks = 4, transfer = 3, missing = 3,
            add = 4, remove = 5,
        },
        categories = {
            patrol     = { label = "Patrol Vehicles",     icon = "car-side",      iconColor = "#4dabf7" },
            supervisor = { label = "Supervisor Vehicles", icon = "user-tie",      iconColor = "#fab005", minGrade = 3 },
            cid        = { label = "CID Vehicles",        icon = "user-secret",   iconColor = "#be4bdb", minGrade = 2, qualifications = { "cid" } },
            tactical   = { label = "Tactical Vehicles",   icon = "shield-halved", iconColor = "#fa5252", minGrade = 2, qualifications = { "swat" } },
        },
        garages = {
            mrpd = {
                label = "Mission Row",
                coords = vec3(454.6, -1017.4, 28.4),
                ped = "s_m_y_cop_01",
                heading = 90.0,
                blip = { sprite = 357, color = 38, scale = 0.7 },
                spawns = {
                    vec4(438.4, -1018.3, 27.7, 90.0),
                    vec4(441.0, -1024.2, 28.3, 90.0),
                    vec4(445.3, -1025.5, 28.6, 90.0),
                },
                returns = {
                    { coords = vec3(452.0, -1021.0, 28.4), radius = 6.0 },
                },
            },
            sandy = {
                label = "Sandy Shores",
                coords = vec3(1868.5, 3688.2, 33.7),
                ped = "s_m_y_sheriff_01",
                heading = 210.0,
                spawns = { vec4(1866.3, 3695.4, 33.6, 210.0) },
                returns = { { coords = vec3(1860.5, 3690.0, 33.7), radius = 6.0 } },
            },
        },
    },

    ballas = {
        type = "gang",
        label = "Ballas",
        icon = "users",
        platePrefix = "BLS",
        grades = { [0] = "Recruit", [1] = "Enforcer", [2] = "Shot Caller", [3] = "Boss" },
        models = { "baller", "buccaneer2", "chino2", "faction2", "voodoo" },
        permissions = {
            retrieve = 0, store = 0, history = 1,
            status = 2, manage = 2, edit = 2, ranks = 3, transfer = 2, missing = 2,
            add = 3, remove = 3,
        },
        categories = {
            street = { label = "Street Cars", icon = "car", iconColor = "#be4bdb" },
            boss   = { label = "Boss Cars",   icon = "crown", iconColor = "#fab005", minGrade = 3 },
        },
        garages = {
            grove = {
                label = "Grove Street",
                coords = vec3(-45.2, -1446.8, 32.4),
                spawns = { vec4(-52.2, -1442.4, 31.8, 5.0) },
                returns = { { coords = vec3(-55.0, -1447.0, 32.0), radius = 6.0 } },
            },
        },
    },
}
