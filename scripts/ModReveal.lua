-- Mod Reveal (Fennell)
-- Lists every mod and DLC this game runs with its version, author and file, plus the mods that are installed
-- but not used, and what changed since the last time this savegame (or server) was played.
-- Left Alt + I opens the list (ModRevealDisplay.lua). On every load the list is also written to
-- modSettings/FS25_ModReveal/ModList.txt and ModList.csv, on players' games and on a dedicated server.
-- Console: modReveal (list), modRevealExport (write the files), modRevealChanges (what changed), modRevealShow (open).
--
-- Mod items come from g_modManager. Only modName, title, version, author and modDir are known fields
-- (used by other mods); the rest is read from each active mod's own modDesc.xml, and every field is optional.

ModReveal = {}
ModReveal.MOD_NAME = g_currentModName
ModReveal.MOD_DIR = g_currentModDirectory
ModReveal.FOLDER_NAME = "FS25_ModReveal"
ModReveal.NOTIFY_DELAY = 8000
ModReveal.USAGE_DELAY = 20000

ModReveal.mods = {}           -- active mods (no DLC), each an entry (see newEntry)
ModReveal.dlcs = {}           -- active DLCs
ModReveal.unused = nil        -- installed but not active; nil when the game doesn't tell
ModReveal.changes = {}        -- entries with .change set, plus removed ones
ModReveal.isFirstVisit = false
ModReveal.summary = {}
ModReveal.notifyTimer = nil
ModReveal.lastExportPath = nil

local function log(fmt, ...)
    print(string.format("[ModReveal] " .. fmt, ...))
end
ModReveal.log = log

local function text(name, ...)
    local value = g_i18n:getText(name, ModReveal.MOD_NAME)
    if select("#", ...) > 0 then
        return string.format(value, ...)
    end
    return value
end
ModReveal.text = text

-- string or nil, whitespace collapsed
local function clean(value)
    if value == nil then
        return nil
    end
    value = tostring(value):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    if value == "" then
        return nil
    end
    return value
end
ModReveal.clean = clean

-- -------------------------------------------------------------------------------------------------------
-- Versions
-- -------------------------------------------------------------------------------------------------------

-- -1 / 0 / 1; numbers compared part by part ("1.10.0.0" > "1.9.0.0"), anything else as text
function ModReveal.compareVersions(a, b)
    a, b = tostring(a or ""), tostring(b or "")
    if a == b then
        return 0
    end
    local partsA, partsB = {}, {}
    for part in a:gmatch("%d+") do
        table.insert(partsA, tonumber(part))
    end
    for part in b:gmatch("%d+") do
        table.insert(partsB, tonumber(part))
    end
    for i = 1, math.max(#partsA, #partsB) do
        local x, y = partsA[i] or 0, partsB[i] or 0
        if x ~= y then
            return x < y and -1 or 1
        end
    end
    return a < b and -1 or 1
end

-- -------------------------------------------------------------------------------------------------------
-- Collecting
-- -------------------------------------------------------------------------------------------------------

function ModReveal.getActiveModItems()
    if g_modManager == nil or type(g_modManager.getActiveMods) ~= "function" then
        return {}
    end
    local ok, items = pcall(g_modManager.getActiveMods, g_modManager)
    if ok and type(items) == "table" then
        return items
    end
    return {}
end

-- every installed mod and DLC, or nil when the mod manager has no such list
function ModReveal.getInstalledModItems()
    if g_modManager == nil then
        return nil
    end
    if type(g_modManager.getMods) == "function" then
        local ok, items = pcall(g_modManager.getMods, g_modManager)
        if ok and type(items) == "table" and #items > 0 then
            return items
        end
    end
    if type(g_modManager.mods) == "table" and #g_modManager.mods > 0 then
        return g_modManager.mods
    end
    return nil
end

function ModReveal.isDLCItem(item)
    if item.isDLC == true then
        return true
    end
    return type(item.modName) == "string" and item.modName:sub(1, 5) == "pdlc_"
end

function ModReveal.newEntry(item, isActive)
    local entry = {
        modName = clean(item.modName) or "?",
        title = clean(item.title),
        version = clean(item.version),
        author = clean(item.author),
        isDLC = ModReveal.isDLCItem(item),
        isActive = isActive,
        hash = type(item.fileHash) == "string" and item.fileHash ~= "" and item.fileHash or nil,
        modDir = type(item.modDir) == "string" and item.modDir or nil,
        isFolder = nil,                     -- true / false, nil = unknown
        isMultiplayer = nil,
        descVersion = nil,
        numScripts = 0,
        numSpecializations = 0,
        numStoreItems = 0,
        isMap = false,
        dependencies = {},
        description = nil,
        change = nil,                       -- "NEW", "UPDATED", "OLDER", "CHANGED" (same version, other file)
        oldVersion = nil,
        isDuplicate = false,
        usage = nil,                        -- filled by computeUsage (after the savegame's vehicles are loaded)
        inGame = 0,
        ownInGame = 0,
        isCurrentMap = false,
        isIdle = false
    }
    if type(item.isMultiplayerSupported) == "boolean" then
        entry.isMultiplayer = item.isMultiplayerSupported
    end
    if type(item.isDirectory) == "boolean" then
        entry.isFolder = item.isDirectory
    end
    if type(item.description) == "string" then
        entry.description = clean(item.description:gsub("<[^>]*>", " "))
    end
    if item.hasScripts == true then
        entry.numScripts = 1
    end
    entry.title = entry.title or entry.modName
    return entry
end

local function countXML(xml, pattern)
    local count = 0
    while count < 10000 and hasXMLProperty(xml, string.format(pattern, count)) do
        count = count + 1
    end
    return count
end

-- fills in what the mod item doesn't say, from the mod's own modDesc.xml
function ModReveal.readModDesc(entry, item)
    local path = nil
    if type(item.modFile) == "string" and item.modFile:lower():find("moddesc%.xml$") then
        path = item.modFile
    elseif entry.modDir ~= nil then
        path = entry.modDir .. "modDesc.xml"
    end
    if path == nil or not fileExists(path) then
        return
    end

    local xml = loadXMLFile("ModRevealModDesc", path)
    if xml == nil or xml == 0 then
        return
    end

    local ok, err = pcall(function()
        entry.descVersion = getXMLInt(xml, "modDesc#descVersion")
        local isMultiplayer = getXMLBool(xml, "modDesc.multiplayer#supported")
        if entry.isMultiplayer == nil then
            entry.isMultiplayer = isMultiplayer == true
        end
        entry.numScripts = math.max(entry.numScripts > 0 and 1 or 0, countXML(xml, "modDesc.extraSourceFiles.sourceFile(%d)"))
        entry.numSpecializations = countXML(xml, "modDesc.specializations.specialization(%d)")
        entry.numStoreItems = countXML(xml, "modDesc.storeItems.storeItem(%d)")
        entry.isMap = hasXMLProperty(xml, "modDesc.maps.map(0)")
        for i = 0, 99 do
            local key = string.format("modDesc.dependencies.dependency(%d)", i)
            if not hasXMLProperty(xml, key) then
                break
            end
            local dependency = clean(getXMLString(xml, key))
            if dependency ~= nil then
                table.insert(entry.dependencies, dependency)
            end
        end
        entry.version = entry.version or clean(getXMLString(xml, "modDesc.version"))
        entry.author = entry.author or clean(getXMLString(xml, "modDesc.author"))
    end)
    delete(xml)
    if not ok then
        log("Could not read %s: %s", path, tostring(err))
    end
end

-- zip or folder: a zip mod's folder is <mods>/<name>/ inside the zip, so look for <mods>/<name>.zip
function ModReveal.findZip(entry)
    if entry.modDir == nil then
        return nil
    end
    local base = entry.modDir:gsub("/+$", "")
    local ok, exists = pcall(fileExists, base .. ".zip")
    if not ok then
        return nil
    end
    return exists == true
end

function ModReveal.getFileName(entry)
    if entry.isDLC then
        return entry.modName
    end
    if entry.isFolder == true then
        return entry.modName .. "/"
    end
    return entry.modName .. ".zip"
end

function ModReveal.getSortTitle(entry)
    local title = entry.title or entry.modName
    if utf8ToLower ~= nil then
        local ok, lower = pcall(utf8ToLower, title)
        if ok and type(lower) == "string" then
            return lower
        end
    end
    return title:lower()
end

function ModReveal.collect()
    local mods, dlcs = {}, {}
    local activeNames = {}
    local zipsFound, zipsChecked = 0, 0

    for index, item in ipairs(ModReveal.getActiveModItems()) do
        local entry = ModReveal.newEntry(item, true)
        entry.loadIndex = index
        local ok, err = pcall(ModReveal.readModDesc, entry, item)
        if not ok then
            log("Could not read modDesc of %s: %s", entry.modName, tostring(err))
        end
        if entry.isDLC then
            table.insert(dlcs, entry)
        else
            if entry.isFolder == nil then
                zipsChecked = zipsChecked + 1
                entry.zipFound = ModReveal.findZip(entry)
                if entry.zipFound then
                    zipsFound = zipsFound + 1
                end
            end
            table.insert(mods, entry)
        end
        activeNames[entry.modName] = true
    end

    -- folder = no zip next to it; only trusted when the zip check worked for at least one mod
    for _, entry in ipairs(mods) do
        if entry.isFolder == nil and zipsFound > 0 and entry.zipFound ~= nil then
            entry.isFolder = not entry.zipFound
        end
        entry.zipFound = nil
        entry.fileName = ModReveal.getFileName(entry)
    end
    for _, entry in ipairs(dlcs) do
        entry.fileName = ModReveal.getFileName(entry)
    end

    -- two active mods with the same title are often the same mod twice (old and new zip)
    local byTitle = {}
    for _, entry in ipairs(mods) do
        local key = ModReveal.getSortTitle(entry)
        byTitle[key] = byTitle[key] or {}
        table.insert(byTitle[key], entry)
    end
    for _, list in pairs(byTitle) do
        if #list > 1 then
            for _, entry in ipairs(list) do
                entry.isDuplicate = true
            end
        end
    end

    local unused = nil
    local installed = ModReveal.getInstalledModItems()
    if installed ~= nil then
        unused = {}
        for _, item in ipairs(installed) do
            if type(item) == "table" and item.modName ~= nil and not activeNames[item.modName] then
                local entry = ModReveal.newEntry(item, false)
                entry.fileName = ModReveal.getFileName(entry)
                table.insert(unused, entry)
            end
        end
    end

    local function byName(a, b)
        local ta, tb = ModReveal.getSortTitle(a), ModReveal.getSortTitle(b)
        if ta ~= tb then
            return ta < tb
        end
        return a.modName < b.modName
    end
    table.sort(mods, byName)
    table.sort(dlcs, byName)
    if unused ~= nil then
        table.sort(unused, byName)
    end

    ModReveal.mods, ModReveal.dlcs, ModReveal.unused = mods, dlcs, unused
    ModReveal.updateSummary()
end

function ModReveal.updateSummary()
    local s = {mods = #ModReveal.mods, dlcs = #ModReveal.dlcs, maps = 0, scripts = 0, notMultiplayer = 0,
               folders = 0, duplicates = 0, storeItems = 0, idle = 0, unused = ModReveal.unused and #ModReveal.unused or nil}
    for _, entry in ipairs(ModReveal.mods) do
        if entry.isIdle then s.idle = s.idle + 1 end
        if entry.isMap then s.maps = s.maps + 1 end
        if entry.numScripts > 0 then s.scripts = s.scripts + 1 end
        if entry.isMultiplayer == false then s.notMultiplayer = s.notMultiplayer + 1 end
        if entry.isFolder == true then s.folders = s.folders + 1 end
        if entry.isDuplicate then s.duplicates = s.duplicates + 1 end
        s.storeItems = s.storeItems + entry.numStoreItems
    end
    local changes = {new = 0, updated = 0, removed = 0}
    for _, entry in ipairs(ModReveal.changes) do
        if entry.change == "NEW" then
            changes.new = changes.new + 1
        elseif entry.change == "REMOVED" then
            changes.removed = changes.removed + 1
        else
            changes.updated = changes.updated + 1
        end
    end
    s.changes = changes
    ModReveal.summary = s
end

-- -------------------------------------------------------------------------------------------------------
-- What changed since last time (per savegame, or per server for a multiplayer player)
-- -------------------------------------------------------------------------------------------------------

function ModReveal.getSettingsDir()
    return getUserProfileAppPath() .. "modSettings/" .. ModReveal.FOLDER_NAME .. "/"
end

function ModReveal.getSetupKey()
    local mission = g_currentMission
    local missionInfo = mission ~= nil and mission.missionInfo or {}
    local dynamicInfo = mission ~= nil and mission.missionDynamicInfo or {}
    local key
    if g_server == nil then
        -- a player in multiplayer: the server, as well as we can name it
        key = "server_" .. tostring(clean(dynamicInfo.serverName) or clean(missionInfo.mapId) or "unknown")
    else
        key = "savegame" .. tostring(missionInfo.savegameIndex or 0)
    end
    return (key:gsub("[^%w_%-]", "_"):sub(1, 80))
end

function ModReveal.getAllActive()
    local all = {}
    for _, entry in ipairs(ModReveal.mods) do
        table.insert(all, entry)
    end
    for _, entry in ipairs(ModReveal.dlcs) do
        table.insert(all, entry)
    end
    return all
end

function ModReveal.loadLastSeen(path)
    if not fileExists(path) then
        return nil
    end
    local xml = loadXMLFile("ModRevealLastSeen", path)
    if xml == nil or xml == 0 then
        return nil
    end
    local seen = {}
    for i = 0, 9999 do
        local key = string.format("modReveal.mod(%d)", i)
        if not hasXMLProperty(xml, key) then
            break
        end
        local name = getXMLString(xml, key .. "#name")
        if name ~= nil then
            seen[name] = {
                modName = name,
                title = getXMLString(xml, key .. "#title") or name,
                version = getXMLString(xml, key .. "#version"),
                hash = getXMLString(xml, key .. "#hash"),
                author = getXMLString(xml, key .. "#author"),
                fileName = getXMLString(xml, key .. "#file"),
                isDLC = getXMLBool(xml, key .. "#dlc") == true,
                order = i
            }
        end
    end
    delete(xml)
    return seen
end

function ModReveal.saveLastSeen(path)
    local xml = createXMLFile("ModRevealLastSeen", path, "modReveal")
    if xml == nil or xml == 0 then
        log("Could not write %s", path)
        return
    end
    for i, entry in ipairs(ModReveal.getAllActive()) do
        local key = string.format("modReveal.mod(%d)", i - 1)
        setXMLString(xml, key .. "#name", entry.modName)
        setXMLString(xml, key .. "#title", entry.title)
        setXMLString(xml, key .. "#version", entry.version or "")
        if entry.hash ~= nil then
            setXMLString(xml, key .. "#hash", entry.hash)
        end
        if entry.author ~= nil then
            setXMLString(xml, key .. "#author", entry.author)
        end
        setXMLString(xml, key .. "#file", entry.fileName or entry.modName)
        if entry.isDLC then
            setXMLBool(xml, key .. "#dlc", true)
        end
    end
    saveXMLFile(xml)
    delete(xml)
end

function ModReveal.updateChanges()
    ModReveal.changes = {}
    ModReveal.isFirstVisit = false

    local dir = ModReveal.getSettingsDir()
    createFolder(dir)
    local path = dir .. "lastSeen_" .. ModReveal.getSetupKey() .. ".xml"
    local seen = ModReveal.loadLastSeen(path)

    if seen == nil then
        ModReveal.isFirstVisit = true
    else
        local active = {}
        for _, entry in ipairs(ModReveal.getAllActive()) do
            active[entry.modName] = true
            local old = seen[entry.modName]
            if old == nil then
                entry.change = "NEW"
            elseif (old.version or "") ~= (entry.version or "") then
                entry.change = ModReveal.compareVersions(entry.version, old.version) < 0 and "OLDER" or "UPDATED"
                entry.oldVersion = old.version
            elseif old.hash ~= nil and entry.hash ~= nil and old.hash ~= entry.hash then
                entry.change = "CHANGED"
            end
            if entry.change ~= nil then
                table.insert(ModReveal.changes, entry)
            end
        end
        local removed = {}
        for name, old in pairs(seen) do
            if not active[name] then
                table.insert(removed, {
                    modName = name, title = old.title, version = old.version, author = old.author, hash = old.hash,
                    isDLC = old.isDLC, isActive = false, change = "REMOVED", fileName = old.fileName or (old.isDLC and name or (name .. ".zip")),
                    numScripts = 0, numSpecializations = 0, numStoreItems = 0, dependencies = {}, isMap = false,
                    inGame = 0, ownInGame = 0, isCurrentMap = false, isIdle = false
                })
            end
        end
        table.sort(removed, function(a, b) return ModReveal.getSortTitle(a) < ModReveal.getSortTitle(b) end)
        local rank = {NEW = 1, UPDATED = 2, OLDER = 3, CHANGED = 4}
        table.sort(ModReveal.changes, function(a, b)
            if rank[a.change] ~= rank[b.change] then
                return rank[a.change] < rank[b.change]
            end
            return ModReveal.getSortTitle(a) < ModReveal.getSortTitle(b)
        end)
        for _, entry in ipairs(removed) do
            table.insert(ModReveal.changes, entry)
        end
    end

    ModReveal.saveLastSeen(path)
    ModReveal.updateSummary()
end

-- -------------------------------------------------------------------------------------------------------
-- In use: what each mod adds to the shop and how much of it is in this savegame. Vehicles (pallets too),
-- placeables and hand tools all carry .customEnvironment = the mod they came from, store items too.
-- -------------------------------------------------------------------------------------------------------

ModReveal.MAX_SHOP_NAMES = 8

local function newUsage()
    return {storeItems = 0, shopNames = {}, vehicles = 0, ownVehicles = 0, placeables = 0, ownPlaceables = 0, handTools = 0, ownHandTools = 0}
end

local function ownerOf(object)
    if object ~= nil and type(object.getOwnerFarmId) == "function" then
        local ok, farmId = pcall(object.getOwnerFarmId, object)
        if ok then
            return farmId
        end
    end
    return nil
end

function ModReveal.computeUsage()
    local usage = {}
    local function get(name)
        if type(name) ~= "string" or name == "" then
            return nil
        end
        local u = usage[name]
        if u == nil then
            u = newUsage()
            usage[name] = u
        end
        return u
    end

    local mission = g_currentMission
    local myFarmId = nil
    if g_dedicatedServer == nil and mission ~= nil and type(mission.getFarmId) == "function" then
        local ok, farmId = pcall(mission.getFarmId, mission)
        myFarmId = ok and farmId or nil
    end
    local function count(list, field, ownField, iter)
        if type(list) ~= "table" then
            return
        end
        for _, object in iter(list) do
            local u = type(object) == "table" and get(object.customEnvironment) or nil
            if u ~= nil then
                u[field] = u[field] + 1
                if myFarmId ~= nil and myFarmId ~= 0 and ownerOf(object) == myFarmId then
                    u[ownField] = u[ownField] + 1
                end
            end
        end
    end

    if g_storeManager ~= nil and type(g_storeManager.getItems) == "function" then
        local ok, items = pcall(g_storeManager.getItems, g_storeManager)
        if ok and type(items) == "table" then
            for _, item in pairs(items) do
                local u = type(item) == "table" and get(item.customEnvironment) or nil
                if u ~= nil then
                    u.storeItems = u.storeItems + 1
                    if item.showInStore ~= false and #u.shopNames < ModReveal.MAX_SHOP_NAMES and clean(item.name) ~= nil then
                        table.insert(u.shopNames, clean(item.name))
                    end
                end
            end
        end
    end
    if mission ~= nil then
        if mission.vehicleSystem ~= nil then
            count(mission.vehicleSystem.vehicles, "vehicles", "ownVehicles", pairs)
        end
        if mission.placeableSystem ~= nil then
            count(mission.placeableSystem.placeables, "placeables", "ownPlaceables", pairs)
        end
        if mission.handToolSystem ~= nil then
            count(mission.handToolSystem.handTools, "handTools", "ownHandTools", pairs)
        end
    end

    local mapEnvironment = mission ~= nil and mission.missionInfo ~= nil and mission.missionInfo.customEnvironment or nil
    for _, list in ipairs({ModReveal.mods, ModReveal.dlcs}) do
        for _, entry in ipairs(list) do
            local u = usage[entry.modName] or newUsage()
            entry.usage = u
            entry.inGame = u.vehicles + u.placeables + u.handTools
            entry.ownInGame = u.ownVehicles + u.ownPlaceables + u.ownHandTools
            entry.isCurrentMap = mapEnvironment ~= nil and mapEnvironment == entry.modName
            -- "idle": it only brings shop items and none of them is in this savegame
            entry.isIdle = entry.isActive and not entry.isDLC and not entry.isCurrentMap and entry.numScripts == 0
                and entry.numSpecializations == 0 and u.storeItems > 0 and entry.inGame == 0
        end
    end
    ModReveal.myFarmId = myFarmId
    ModReveal.usageReady = true
    ModReveal.updateSummary()
end

-- short text for the list column and the files: "9 (4 yours)", "map", "-"
function ModReveal.getInGameText(entry)
    if entry.isCurrentMap then
        return text("mr_inGameMap")
    end
    if entry.usage == nil or (entry.usage.storeItems == 0 and entry.inGame == 0) then
        return "-"
    end
    if ModReveal.myFarmId ~= nil and entry.ownInGame > 0 then
        return text("mr_inGameYours", entry.inGame, entry.ownInGame)
    end
    return tostring(entry.inGame)
end

-- -------------------------------------------------------------------------------------------------------
-- Text descriptions shared by the list, the log and the files
-- -------------------------------------------------------------------------------------------------------

function ModReveal.getKindText(entry)
    local parts = {}
    if entry.isDLC then
        table.insert(parts, "DLC")
    end
    if entry.isMap then
        table.insert(parts, "Map")
    end
    if entry.numScripts > 0 then
        table.insert(parts, "Script")
    end
    if entry.numStoreItems > 0 then
        table.insert(parts, string.format("%d store items", entry.numStoreItems))
    end
    return table.concat(parts, ", ")
end

function ModReveal.getChangeText(entry)
    if entry.change == "NEW" then
        return text("mr_changeNew")
    elseif entry.change == "UPDATED" then
        return text("mr_changeUpdated", tostring(entry.oldVersion or "?"), tostring(entry.version or "?"))
    elseif entry.change == "OLDER" then
        return text("mr_changeOlder", tostring(entry.oldVersion or "?"), tostring(entry.version or "?"))
    elseif entry.change == "CHANGED" then
        return text("mr_changeChanged")
    elseif entry.change == "REMOVED" then
        return text("mr_changeRemoved")
    end
    return nil
end

function ModReveal.getModeText()
    local mission = g_currentMission
    local isMultiplayer = mission ~= nil and mission.missionDynamicInfo ~= nil and mission.missionDynamicInfo.isMultiplayer
    if g_dedicatedServer ~= nil then
        return text("mr_modeDedicated")
    elseif isMultiplayer and g_server ~= nil then
        return text("mr_modeHost")
    elseif isMultiplayer then
        return text("mr_modeClient")
    end
    return text("mr_modeSingle")
end

function ModReveal.getMapTitle()
    local missionInfo = g_currentMission ~= nil and g_currentMission.missionInfo or nil
    return missionInfo ~= nil and clean(missionInfo.mapTitle) or "?"
end

function ModReveal.getGameVersion()
    return clean(g_gameVersionDisplay) or clean(g_gameVersion) or "?"
end

function ModReveal.getDate()
    if getDate ~= nil then
        local ok, value = pcall(getDate, "%Y-%m-%d %H:%M")
        if ok and type(value) == "string" then
            return value
        end
    end
    return ""
end

-- -------------------------------------------------------------------------------------------------------
-- Export: modSettings/FS25_ModReveal/ModList.txt (readable, paste into Discord) and ModList.csv (spreadsheet)
-- -------------------------------------------------------------------------------------------------------

local function pad(value, width)
    value = tostring(value or "")
    local length = utf8Strlen ~= nil and utf8Strlen(value) or #value
    if length >= width then
        return value .. " "
    end
    return value .. string.rep(" ", width - length)
end

local function csv(value)
    value = tostring(value or "")
    if value:find('[,"\n;]') then
        value = '"' .. value:gsub('"', '""') .. '"'
    end
    return value
end

local function writeFile(path, content)
    local file = createFile(path, FileAccess.WRITE)
    if file == nil or file == 0 then
        return false
    end
    fileWrite(file, content)
    delete(file)
    return true
end

function ModReveal.buildText()
    local s = ModReveal.summary
    local lines = {}
    local function add(fmt, ...)
        table.insert(lines, select("#", ...) > 0 and string.format(fmt, ...) or fmt)
    end

    add("Mod Reveal - mod list")
    add("Written: %s", ModReveal.getDate())
    add("Game: Farming Simulator 25 %s | %s | Map: %s", ModReveal.getGameVersion(), ModReveal.getModeText(), ModReveal.getMapTitle())
    add("Active: %d mods, %d DLC | script mods: %d | maps: %d | store items: %d", s.mods, s.dlcs, s.scripts, s.maps, s.storeItems)
    if s.notMultiplayer > 0 or s.folders > 0 or s.duplicates > 0 then
        add("Watch out: %d not for multiplayer | %d unzipped folders | %d possible duplicates", s.notMultiplayer, s.folders, s.duplicates)
    end
    if ModReveal.usageReady then
        add("In game = vehicles, pallets, buildings and hand tools from that mod in this savegame%s.",
            ModReveal.myFarmId ~= nil and " (and how many are yours)" or "")
        add("Nothing in game: %d mods only add shop items and none of them is in this savegame (candidates to remove).", s.idle)
    end
    add("")

    local function table_(title, list, withChange)
        add("== %s (%d) ==", title, #list)
        if #list == 0 then
            add("(none)")
            add("")
            return
        end
        local widths = {title = 10, version = 7, author = 6, file = 4}
        for _, entry in ipairs(list) do
            local function width(value)
                value = tostring(value or "")
                return math.min(60, utf8Strlen ~= nil and utf8Strlen(value) or #value)
            end
            widths.title = math.max(widths.title, width(entry.title))
            widths.version = math.max(widths.version, width(entry.version))
            widths.author = math.max(widths.author, width(entry.author))
            widths.file = math.max(widths.file, width(entry.fileName))
        end
        add("%s%s%s%s%s", pad("Mod", widths.title + 1), pad("Version", widths.version + 1), pad("Author", widths.author + 1),
            pad("File", widths.file + 1), withChange and "Change" or "Notes")
        for _, entry in ipairs(list) do
            local notes = {}
            if withChange then
                table.insert(notes, ModReveal.getChangeText(entry) or "")
            else
                local kind = ModReveal.getKindText(entry)
                if kind ~= "" then table.insert(notes, kind) end
                if entry.isActive and entry.isMultiplayer == false and not entry.isDLC then table.insert(notes, "NOT FOR MULTIPLAYER") end
                if entry.isFolder == true then table.insert(notes, "FOLDER (not zipped)") end
                if entry.isDuplicate then table.insert(notes, "POSSIBLE DUPLICATE") end
                if entry.change ~= nil then table.insert(notes, ModReveal.getChangeText(entry)) end
                if ModReveal.usageReady and entry.isActive then
                    if entry.isIdle then
                        table.insert(notes, "NOTHING IN GAME")
                    elseif ModReveal.getInGameText(entry) ~= "-" then
                        table.insert(notes, "In game: " .. ModReveal.getInGameText(entry))
                    end
                end
            end
            add("%s%s%s%s%s", pad(entry.title, widths.title + 1), pad(entry.version or "-", widths.version + 1),
                pad(entry.author or "-", widths.author + 1), pad(entry.fileName, widths.file + 1), table.concat(notes, " | "))
        end
        add("")
    end

    if not ModReveal.isFirstVisit then
        table_("Changed since last time", ModReveal.changes, true)
    end
    table_("Active mods", ModReveal.mods, false)
    table_("Active DLC", ModReveal.dlcs, false)
    if ModReveal.unused ~= nil then
        table_("Installed but not used here", ModReveal.unused, false)
    end
    return table.concat(lines, "\r\n")
end

function ModReveal.buildCSV()
    local lines = {"status,mod name,title,version,author,file,type,multiplayer,hash,change,shop items,in game,yours,nothing in game"}
    local function add(status, entry)
        local multiplayer = entry.isMultiplayer == nil and "" or (entry.isMultiplayer and "yes" or "no")
        local usage = ModReveal.usageReady and entry.usage or nil
        table.insert(lines, table.concat({csv(status), csv(entry.modName), csv(entry.title), csv(entry.version), csv(entry.author),
            csv(entry.fileName), csv(ModReveal.getKindText(entry)), csv(multiplayer), csv(entry.hash), csv(entry.change or ""),
            csv(usage and usage.storeItems or ""), csv(usage and entry.inGame or ""), csv(usage and ModReveal.myFarmId and entry.ownInGame or ""),
            csv(usage and (entry.isIdle and "yes" or "no") or "")}, ","))
    end
    for _, entry in ipairs(ModReveal.mods) do add("active", entry) end
    for _, entry in ipairs(ModReveal.dlcs) do add("active", entry) end
    for _, entry in ipairs(ModReveal.unused or {}) do add("not used", entry) end
    for _, entry in ipairs(ModReveal.changes) do
        if entry.change == "REMOVED" then add("removed", entry) end
    end
    return table.concat(lines, "\r\n")
end

-- Changes.txt: the changes of this load, tab separated, for scripts (the DTM server posts them to Discord).
-- "load" is the same for every write during one load, so a reader can tell a new start from a re-save.
function ModReveal.writeChangesFile()
    local function field(value)
        return (tostring(value or ""):gsub("[\t\r\n]", " "))
    end
    local s = ModReveal.summary
    local lines = {
        "modRevealChanges\t1",
        "load\t" .. field(ModReveal.loadStamp),
        "setup\t" .. field(ModReveal.getSetupKey()),
        "map\t" .. field(ModReveal.getMapTitle()),
        "game\t" .. field(ModReveal.getGameVersion()),
        "mods\t" .. tostring(s.mods or 0) .. "\t" .. tostring(s.dlcs or 0),
        "firstVisit\t" .. (ModReveal.isFirstVisit and "yes" or "no")
    }
    for _, entry in ipairs(ModReveal.changes) do
        local old = (entry.change == "NEW") and "" or (entry.oldVersion or entry.version)
        local new = (entry.change == "REMOVED") and "" or entry.version
        table.insert(lines, table.concat({"change", field(entry.change), field(entry.title), field(entry.fileName), field(old), field(new),
            entry.isDLC and "dlc" or "mod"}, "\t"))
    end
    local dir = ModReveal.getSettingsDir()
    createFolder(dir)
    if not writeFile(dir .. "Changes.txt", table.concat(lines, "\r\n") .. "\r\n") then
        log("Could not write %sChanges.txt", dir)
    end
end

function ModReveal.export()
    if ModReveal.usageReady then
        pcall(ModReveal.computeUsage)
    end
    local dir = ModReveal.getSettingsDir()
    createFolder(dir)
    local okText = writeFile(dir .. "ModList.txt", ModReveal.buildText())
    local okCSV = writeFile(dir .. "ModList.csv", ModReveal.buildCSV())
    if okText and okCSV then
        ModReveal.lastExportPath = dir .. "ModList.txt"
        return true, dir
    end
    log("Could not write the mod list to %s", dir)
    return false, dir
end

-- -------------------------------------------------------------------------------------------------------
-- Log and console
-- -------------------------------------------------------------------------------------------------------

function ModReveal.logSummary()
    local s = ModReveal.summary
    log("%d mods and %d DLC active (script mods: %d, maps: %d), %s installed but not used. Game %s, %s.",
        s.mods, s.dlcs, s.scripts, s.maps, s.unused ~= nil and tostring(s.unused) or "?", ModReveal.getGameVersion(), ModReveal.getModeText())
    if s.notMultiplayer > 0 or s.folders > 0 or s.duplicates > 0 then
        for _, entry in ipairs(ModReveal.mods) do
            if entry.isMultiplayer == false then log("  not for multiplayer: %s (%s)", entry.title, entry.fileName) end
            if entry.isFolder == true then log("  unzipped folder: %s", entry.fileName) end
            if entry.isDuplicate then log("  possible duplicate: %s (%s)", entry.title, entry.fileName) end
        end
    end
    if ModReveal.isFirstVisit then
        log("First visit here: the list is saved, changes show from the next load on.")
    elseif #ModReveal.changes == 0 then
        log("No mod changes since last time.")
    else
        log("Changed since last time:")
        for _, entry in ipairs(ModReveal.changes) do
            log("  %-8s %s (%s) %s", entry.change, entry.title, entry.fileName, ModReveal.getChangeText(entry) or "")
        end
    end
end

function ModReveal:consoleList()
    local lines = {}
    local function add(list, label)
        table.insert(lines, string.format("%s (%d):", label, #list))
        for _, entry in ipairs(list) do
            table.insert(lines, string.format("  %-45s %-14s %-28s %s", entry.title, entry.version or "-", entry.author or "-", entry.fileName))
        end
    end
    add(ModReveal.mods, "Active mods")
    add(ModReveal.dlcs, "Active DLC")
    if ModReveal.unused ~= nil then
        add(ModReveal.unused, "Installed but not used")
    end
    for _, line in ipairs(lines) do
        print(line)
    end
    return string.format("%d mods, %d DLC", #ModReveal.mods, #ModReveal.dlcs)
end

function ModReveal:consoleExport()
    local ok, dir = ModReveal.export()
    if ok then
        return "Mod list written to " .. dir .. "ModList.txt and ModList.csv"
    end
    return "Could not write the mod list to " .. dir
end

function ModReveal:consoleShow()
    if g_dedicatedServer ~= nil then
        return "Not on a dedicated server: use modReveal or modRevealExport."
    end
    ModRevealDisplay.open("console")
    return "Mod Reveal window opened (close the console with ~ to use it)."
end

function ModReveal:consoleChanges()
    if ModReveal.isFirstVisit then
        return "First visit here: changes show from the next load on."
    end
    if #ModReveal.changes == 0 then
        return "No mod changes since last time."
    end
    for _, entry in ipairs(ModReveal.changes) do
        print(string.format("  %-8s %-45s %s", entry.change, entry.title, ModReveal.getChangeText(entry) or ""))
    end
    return string.format("%d changes", #ModReveal.changes)
end

-- -------------------------------------------------------------------------------------------------------
-- Mod listener
-- -------------------------------------------------------------------------------------------------------

function ModReveal:loadMap(filename)
    ModReveal.usageReady = false
    ModReveal.myFarmId = nil
    ModReveal.loadStamp = ModReveal.getDate()
    if ModReveal.loadStamp == "" then
        ModReveal.loadStamp = "unknown"
    end
    local ok, err = pcall(function()
        ModReveal.collect()
        ModReveal.updateChanges()
        ModReveal.writeChangesFile()
        ModReveal.export()
        ModReveal.logSummary()
    end)
    if not ok then
        log("Error while reading the mod list: %s", tostring(err))
    end

    addConsoleCommand("modReveal", "Lists every active mod with its version, author and file", "consoleList", ModReveal)
    addConsoleCommand("modRevealExport", "Writes the mod list to modSettings/FS25_ModReveal", "consoleExport", ModReveal)
    addConsoleCommand("modRevealChanges", "Lists the mods that changed since the last load", "consoleChanges", ModReveal)
    addConsoleCommand("modRevealShow", "Opens the Mod Reveal window (same as Left Alt + I)", "consoleShow", ModReveal)

    if g_dedicatedServer == nil and not ModReveal.isFirstVisit and #ModReveal.changes > 0 then
        ModReveal.notifyTimer = ModReveal.NOTIFY_DELAY
    end
    -- the savegame's vehicles and buildings are loaded after loadMap: count them a little later, then write the files again
    ModReveal.usageTimer = ModReveal.USAGE_DELAY
    ModRevealDisplay.load()
end

function ModReveal:deleteMap()
    ModRevealDisplay.delete()
    removeConsoleCommand("modReveal")
    removeConsoleCommand("modRevealExport")
    removeConsoleCommand("modRevealChanges")
    removeConsoleCommand("modRevealShow")
    ModReveal.notifyTimer = nil
    ModReveal.usageTimer = nil
end

function ModReveal.notifyChanges()
    local c = ModReveal.summary.changes
    local message = text("mr_notifyChanges", c.updated, c.new, c.removed)
    if g_currentMission ~= nil and g_currentMission.addIngameNotification ~= nil then
        pcall(g_currentMission.addIngameNotification, g_currentMission, FSBaseMission.INGAME_NOTIFICATION_INFO, message)
    end
end

function ModReveal:update(dt)
    if ModReveal.notifyTimer ~= nil then
        ModReveal.notifyTimer = ModReveal.notifyTimer - dt
        if ModReveal.notifyTimer <= 0 then
            ModReveal.notifyTimer = nil
            ModReveal.notifyChanges()
        end
    end
    if ModReveal.usageTimer ~= nil then
        ModReveal.usageTimer = ModReveal.usageTimer - dt
        if ModReveal.usageTimer <= 0 then
            ModReveal.usageTimer = nil
            local ok, err = pcall(function()
                ModReveal.computeUsage()
                ModReveal.export()
            end)
            if ok then
                log("Counted what each mod has in this savegame: %d mods add shop items but have nothing in it.", ModReveal.summary.idle or 0)
            else
                log("Could not count what is in the savegame: %s", tostring(err))
            end
        end
    end
    ModRevealDisplay.update(dt)
end

function ModReveal:draw()
    ModRevealDisplay.drawFromListener()
end

function ModReveal:mouseEvent(posX, posY, isDown, isUp, button)
    ModRevealDisplay.mouseEvent(posX, posY, isDown, isUp, button)
end

function ModReveal:keyEvent(unicode, sym, modifier, isDown)
    ModRevealDisplay.keyEvent(unicode, sym, modifier, isDown)
end

-- Left Alt + I, on foot and in vehicles. Hooked once (savegames re-source the scripts) and dispatched to the current table.
if PlayerInputComponent ~= nil and not PlayerInputComponent.modRevealHooked then
    PlayerInputComponent.modRevealHooked = true
    PlayerInputComponent.registerGlobalPlayerActionEvents = Utils.appendedFunction(PlayerInputComponent.registerGlobalPlayerActionEvents, function(component, contextName)
        if ModRevealDisplay ~= nil then
            ModRevealDisplay.registerToggleAction(contextName)
        end
    end)
end

-- The window is drawn after the whole mission (HUD and other mods' overlays included), so nothing
-- draws over it. Hooked once and dispatched to the current table.
if FSBaseMission ~= nil and FSBaseMission.draw ~= nil and not FSBaseMission.modRevealDrawHooked then
    FSBaseMission.modRevealDrawHooked = true
    FSBaseMission.draw = Utils.appendedFunction(FSBaseMission.draw, function()
        if ModRevealDisplay ~= nil and ModRevealDisplay.drawLate ~= nil then
            ModRevealDisplay.drawLate()
        end
    end)
end

addModEventListener(ModReveal)
