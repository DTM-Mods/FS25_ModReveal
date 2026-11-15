-- Mod Reveal (Fennell)
-- The mod list window: drawn straight onto the screen (drawFilledRect + renderText) while open.
-- Left Alt + I (default) opens it. While open it has its own input context, so keys don't drive the vehicle or
-- the player: Esc closes (clears the search first), Left / Right change the tab, Up / Down select a mod (hold to
-- run), typing searches by name, author or file. Mouse: click tabs, rows, SORT and SAVE LIST; the wheel scrolls.
-- Gamepad: the menu stick / d-pad selects and changes tabs, LB / RB change tabs, the menu "extra" buttons sort and
-- save, B closes. Those buttons share their actions with Q / E / X / C on the keyboard, so an action that arrives in
-- the same frame as a typed letter is dropped (see state.pending).
-- Layout is in 1920 x 1080 reference pixels, top-left origin (same scheme as Monthly Expense Sheet).

ModRevealDisplay = {}
ModRevealDisplay.INPUT_CONTEXT = "MOD_REVEAL"
ModRevealDisplay.ROWS = 17
ModRevealDisplay.ROW_H = 29
ModRevealDisplay.REPEAT_DELAY = 350
ModRevealDisplay.REPEAT_INTERVAL = 45
ModRevealDisplay.STATUS_TIME = 6000

local MOD_NAME = g_currentModName

-- DTM brand colours
local COLOR = {
    backdrop = {0, 0, 0, 0.55},
    panel = {0.063, 0.16, 0.118, 0.97},          -- night field, a bit darker
    header = {0.851, 0.643, 0.255, 1},           -- field gold
    headerText = {0.078, 0.2, 0.149, 1},         -- night field
    tab = {0.122, 0.302, 0.227, 1},              -- field green
    rowHeader = {0.122, 0.302, 0.227, 1},
    rowStripe = {0.086, 0.21, 0.157, 1},
    rowSelected = {0.18, 0.42, 0.31, 1},         -- crop green
    detailsPanel = {0.086, 0.21, 0.157, 1},
    text = {0.957, 0.945, 0.91, 1},              -- cream
    textDim = {0.498, 0.643, 0.541, 1},          -- sage
    straw = {0.914, 0.78, 0.478, 1},
    warn = {0.93, 0.55, 0.2, 1},
    bad = {0.86, 0.33, 0.27, 1},
    good = {0.55, 0.78, 0.36, 1},
    keyBox = {0.957, 0.945, 0.91, 1}
}

-- chip colours by kind
local CHIP = {
    MAP = COLOR.header,
    SCRIPT = COLOR.textDim,
    DLC = COLOR.straw,
    NOMP = COLOR.bad,
    FOLDER = COLOR.warn,
    DUP = COLOR.bad,
    NEW = COLOR.good,
    UPDATED = COLOR.good,
    OLDER = COLOR.warn,
    CHANGED = COLOR.straw,
    REMOVED = COLOR.bad,
    IDLE = COLOR.warn
}

local TAB_ACTIVE, TAB_DLC, TAB_UNUSED, TAB_CHANGES = 1, 2, 3, 4
local SORTS = {"name", "ingame", "author", "file", "load"}

local function text(name, ...)
    local value = g_i18n:getText(name, MOD_NAME)
    if select("#", ...) > 0 then
        return string.format(value, ...)
    end
    return value
end

-- reference pixels -> screen
local function sx(px) return px / 1920 end
local function sy(py) return 1 - py / 1080 end
local function sh(px) return px / 1080 end

local function rect(x, y, w, h, color)
    drawFilledRect(sx(x), sy(y + h), sx(w), sh(h), color[1], color[2], color[3], color[4])
end

local function textWidth(size, value, bold)
    setTextBold(bold == true)
    return getTextWidth(sh(size), value) * 1920
end

local function label(x, y, size, value, color, bold, alignment)
    setTextBold(bold == true)
    setTextAlignment(alignment or RenderText.ALIGN_LEFT)
    setTextColor(color[1], color[2], color[3], color[4])
    -- y = top of the text line
    renderText(sx(x), sy(y + size * 0.85), sh(size), value)
end

local function resetText()
    setTextBold(false)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(1, 1, 1, 1)
end

local function isInside(posX, posY, x, y, w, h)
    return posX >= sx(x) and posX <= sx(x + w) and posY <= sy(y) and posY >= sy(y + h)
end

local function dropLastChar(value)
    return (value:gsub("[^\128-\191][\128-\191]*$", ""))
end

-- cut to maxWidth reference pixels with "...", cached (it runs every frame)
local fitCache = {}
local fitCacheSize = 0
local function fit(value, size, maxWidth, bold)
    value = tostring(value or "")
    local key = value .. "\0" .. size .. "\0" .. maxWidth .. (bold and "b" or "")
    local cached = fitCache[key]
    if cached ~= nil then
        return cached
    end
    local result = value
    if textWidth(size, value, bold) > maxWidth then
        result = value
        while result ~= "" and textWidth(size, result .. "...", bold) > maxWidth do
            result = dropLastChar(result)
        end
        result = result .. "..."
    end
    if fitCacheSize > 3000 then
        fitCache, fitCacheSize = {}, 0
    end
    fitCache[key] = result
    fitCacheSize = fitCacheSize + 1
    return result
end

local function lower(value)
    value = tostring(value or "")
    if utf8ToLower ~= nil then
        local ok, result = pcall(utf8ToLower, value)
        if ok and type(result) == "string" then
            return result
        end
    end
    return value:lower()
end

-- state ------------------------------------------------------------------------------------------------

local state = {
    isOpen = false,
    tab = TAB_ACTIVE,
    selected = 1,
    scroll = 0,
    search = "",
    sort = 1,
    openedAt = 0,
    axisDir = 0,
    axisTime = 0,
    nextRepeat = 0,
    status = nil,
    statusTimer = 0,
    list = nil,           -- filtered + sorted entries of the tab, rebuilt when something changes
    listKey = nil,
    frame = 0,            -- counted in update
    lateFrame = nil,      -- the last frame drawn from the FSBaseMission.draw hook
    hudWasVisible = nil   -- the game HUD was visible when the window opened (it is hidden while open)
}

-- The game HUD (F1 help box, player list, field info ...) draws over the window, so it is hidden while
-- the window is open, and shown again on close only if it was visible before.
local function setHudHidden(hidden)
    local hud = g_currentMission ~= nil and g_currentMission.hud or nil
    if hud == nil or hud.setIsVisible == nil then
        return
    end
    if hidden then
        local ok, visible = pcall(function() return hud.getIsVisible == nil or hud:getIsVisible() end)
        state.hudWasVisible = ok and visible
        if state.hudWasVisible then
            pcall(hud.setIsVisible, hud, false)
        end
    elseif state.hudWasVisible then
        state.hudWasVisible = nil
        pcall(hud.setIsVisible, hud, true)
    end
end

function ModRevealDisplay.load()
    state.isOpen = false
    state.list = nil
    state.listKey = nil
    fitCache, fitCacheSize = {}, 0
end

function ModRevealDisplay.delete()
    if state.isOpen then
        ModRevealDisplay.close()
    end
end

-- log lines that should appear once per session only
local loggedOnce = {}
local function logOnce(key, fmt, ...)
    if not loggedOnce[key] then
        loggedOnce[key] = true
        ModReveal.log(fmt, ...)
    end
end

function ModRevealDisplay.registerToggleAction(contextName)
    if g_inputBinding == nil or InputAction == nil or InputAction.MR_TOGGLE == nil then
        logOnce("noAction", "Key binding MR_TOGGLE is unknown to the game; Left Alt + I still works through the keyboard watch.")
        return
    end
    local _, eventId = g_inputBinding:registerActionEvent(InputAction.MR_TOGGLE, ModRevealDisplay, ModRevealDisplay.onToggleAction, false, true, false, true)
    if eventId ~= nil then
        -- listed in the F1 help box, at the bottom
        g_inputBinding:setActionEventTextVisibility(eventId, true)
        if GS_PRIO_VERY_LOW ~= nil and g_inputBinding.setActionEventTextPriority ~= nil then
            g_inputBinding:setActionEventTextPriority(eventId, GS_PRIO_VERY_LOW)
        end
    end
    logOnce("register_" .. tostring(contextName), "Key binding MR_TOGGLE registered for %s: %s", contextName ~= nil and tostring(contextName) or "on foot",
        eventId ~= nil and "yes" or "NO (another action may own the key)")
end

function ModRevealDisplay.onToggleAction()
    ModRevealDisplay.toggle("key binding")
end

function ModRevealDisplay.getTabList(tab)
    if tab == TAB_ACTIVE then
        return ModReveal.mods
    elseif tab == TAB_DLC then
        return ModReveal.dlcs
    elseif tab == TAB_UNUSED then
        return ModReveal.unused or {}
    end
    return ModReveal.changes
end

function ModRevealDisplay.getTabs()
    local tabs = {
        {id = TAB_ACTIVE, label = text("mr_tabActive", #ModReveal.mods)},
        {id = TAB_DLC, label = text("mr_tabDLC", #ModReveal.dlcs)}
    }
    if ModReveal.unused ~= nil then
        table.insert(tabs, {id = TAB_UNUSED, label = text("mr_tabUnused", #ModReveal.unused)})
    end
    table.insert(tabs, {id = TAB_CHANGES, label = text("mr_tabChanges", #ModReveal.changes)})
    return tabs
end

local function matches(entry, search)
    if search == "" then
        return true
    end
    for _, value in ipairs({entry.title, entry.modName, entry.author, entry.version}) do
        if value ~= nil and lower(value):find(search, 1, true) then
            return true
        end
    end
    return false
end

function ModRevealDisplay.getList()
    local key = state.tab .. "|" .. state.sort .. "|" .. state.search
    if state.list ~= nil and state.listKey == key then
        return state.list
    end

    local search = lower(state.search)
    local list = {}
    for _, entry in ipairs(ModRevealDisplay.getTabList(state.tab)) do
        if matches(entry, search) then
            table.insert(list, entry)
        end
    end

    local sort = SORTS[state.sort]
    if state.tab ~= TAB_CHANGES and sort ~= "name" then
        local function value(entry)
            if sort == "ingame" then
                -- nothing in game first, then the least used; mods without shop items or objects last
                if entry.usage == nil or (entry.usage.storeItems == 0 and (entry.inGame or 0) == 0) or entry.isCurrentMap then
                    return 1000000
                end
                return entry.inGame or 0
            elseif sort == "author" then
                return lower(entry.author or "~")
            elseif sort == "file" then
                return lower(entry.fileName or entry.modName)
            end
            return entry.loadIndex or 0
        end
        table.sort(list, function(a, b)
            local va, vb = value(a), value(b)
            if va ~= vb then
                return va < vb
            end
            return ModReveal.getSortTitle(a) < ModReveal.getSortTitle(b)
        end)
    end

    state.list, state.listKey = list, key
    state.selected = math.max(1, math.min(state.selected, #list))
    ModRevealDisplay.keepSelectionVisible()
    return list
end

-- open / close + input -------------------------------------------------------------------------------

-- the key binding and the keyboard watch can both see one press: only the first one in 250 ms counts
function ModRevealDisplay.toggle(source)
    local now = g_time or 0
    if state.lastToggle ~= nil and now - state.lastToggle < 250 then
        return
    end
    state.lastToggle = now
    if state.isOpen then
        ModRevealDisplay.close()
    else
        ModRevealDisplay.open(source)
    end
end

function ModRevealDisplay.isOpen()
    return state.isOpen
end

function ModRevealDisplay.getTab()
    return state.tab, state.search
end

function ModRevealDisplay.getOpenGuiName()
    if g_gui == nil or not g_gui:getIsGuiVisible() then
        return nil
    end
    return tostring(g_gui.currentGuiName or "a menu")
end

function ModRevealDisplay.open(source)
    if state.isOpen then
        return
    end
    local guiName = ModRevealDisplay.getOpenGuiName()
    if guiName ~= nil then
        ModReveal.log("Not opened (%s): %s is open.", tostring(source or "?"), guiName)
        return
    end
    logOnce("opened_" .. tostring(source), "Window opened by %s.", tostring(source or "?"))
    state.isOpen = true
    state.openedAt = g_time or 0
    state.axisDir = 0
    state.list = nil
    -- opens on the changes when there are fresh ones, else where it was left
    if ModReveal.notifyTimer ~= nil or (state.firstOpen == nil and #ModReveal.changes > 0 and not ModReveal.isFirstVisit) then
        state.tab = TAB_CHANGES
        state.selected, state.scroll = 1, 0
    end
    state.firstOpen = false
    state.pending = nil
    if g_dedicatedServer == nil then
        pcall(ModReveal.computeUsage)
        state.list = nil
    end

    g_inputBinding:setContext(ModRevealDisplay.INPUT_CONTEXT, true, false)
    local function register(action, callback, triggerAlways)
        if action ~= nil then
            local _, eventId = g_inputBinding:registerActionEvent(action, ModRevealDisplay, callback, false, true, triggerAlways == true, true)
            if eventId ~= nil then
                g_inputBinding:setActionEventTextVisibility(eventId, false)
            end
        end
    end
    register(InputAction.MENU_BACK, ModRevealDisplay.onBack)
    register(InputAction.MR_TOGGLE, ModRevealDisplay.onToggleAction)
    register(InputAction.MENU_AXIS_UP_DOWN, ModRevealDisplay.onAxisUpDown, true)
    register(InputAction.MENU_AXIS_LEFT_RIGHT, function(_, _, value)
        if value ~= nil and math.abs(value) > 0.5 then
            ModRevealDisplay.changeTab(value > 0 and 1 or -1)
        end
    end)
    -- gamepad buttons (the keyboard keys of these actions are letters: see ModRevealDisplay.queue)
    register(InputAction.MENU_PAGE_PREV, function() ModRevealDisplay.queue(function() ModRevealDisplay.changeTab(-1) end) end)
    register(InputAction.MENU_PAGE_NEXT, function() ModRevealDisplay.queue(function() ModRevealDisplay.changeTab(1) end) end)
    register(InputAction.MENU_EXTRA_1, function() ModRevealDisplay.queue(ModRevealDisplay.cycleSort) end)
    register(InputAction.MENU_EXTRA_2, function() ModRevealDisplay.queue(ModRevealDisplay.export) end)

    g_inputBinding:setShowMouseCursor(true)
    setHudHidden(true)
end

function ModRevealDisplay.close()
    if not state.isOpen then
        return
    end
    state.isOpen = false
    g_inputBinding:revertContext(true)
    g_inputBinding:setShowMouseCursor(false)
    setHudHidden(false)
end

-- Drawn from the FSBaseMission.draw hook (ModReveal.lua), after the HUD and other mods' overlays, so
-- nothing draws over the window. The mod listener's draw is the fallback if that hook never runs.
function ModRevealDisplay.drawLate()
    state.lateFrame = state.frame
    ModRevealDisplay.draw()
end

function ModRevealDisplay.drawFromListener()
    if state.lateFrame ~= nil and state.frame - state.lateFrame <= 2 then
        return
    end
    ModRevealDisplay.draw()
end

function ModRevealDisplay.isHudHidden()
    return state.hudWasVisible == true
end

-- runs fn in the next update unless a letter was typed in the same frame (then the key was meant for the search)
function ModRevealDisplay.queue(fn)
    state.pending = fn
    state.pendingAt = g_time or 0
end

function ModRevealDisplay.onBack()
    if state.search ~= "" then
        ModRevealDisplay.setSearch("")
    else
        ModRevealDisplay.close()
    end
end

-- Up / Down: one step on press, then repeats while held (the event fires every frame with triggerAlways)
function ModRevealDisplay.onAxisUpDown(_, _, value)
    local dir = 0
    if value ~= nil and math.abs(value) > 0.5 then
        dir = value > 0 and -1 or 1
    end
    local now = g_time or 0
    if dir ~= 0 and (dir ~= state.axisDir or now - state.axisTime > 150) then
        ModRevealDisplay.changeSelection(dir)
        state.nextRepeat = now + ModRevealDisplay.REPEAT_DELAY
    end
    state.axisDir = dir
    state.axisTime = now
end

function ModRevealDisplay.changeTab(direction)
    local tabs = ModRevealDisplay.getTabs()
    local index = 1
    for i, tab in ipairs(tabs) do
        if tab.id == state.tab then
            index = i
        end
    end
    index = ((index - 1 + direction) % #tabs) + 1
    ModRevealDisplay.setTab(tabs[index].id)
end

function ModRevealDisplay.setTab(tab)
    if state.tab ~= tab then
        state.tab = tab
        state.selected, state.scroll = 1, 0
        state.list = nil
    end
end

function ModRevealDisplay.setSearch(value)
    state.search = value
    state.selected, state.scroll = 1, 0
    state.list = nil
end

function ModRevealDisplay.cycleSort()
    state.sort = state.sort % #SORTS + 1
    state.selected, state.scroll = 1, 0
    state.list = nil
end

function ModRevealDisplay.keepSelectionVisible()
    local rows = ModRevealDisplay.ROWS
    local count = state.list ~= nil and #state.list or 0
    if state.selected > state.scroll + rows then
        state.scroll = state.selected - rows
    elseif state.selected <= state.scroll then
        state.scroll = state.selected - 1
    end
    state.scroll = math.max(0, math.min(state.scroll, math.max(0, count - rows)))
end

function ModRevealDisplay.changeSelection(direction)
    local list = ModRevealDisplay.getList()
    if #list == 0 then
        return
    end
    state.selected = math.max(1, math.min(#list, state.selected + direction))
    ModRevealDisplay.keepSelectionVisible()
end

function ModRevealDisplay.export()
    local ok, dir = ModReveal.export()
    if ok then
        state.status = text("mr_saved", dir .. "ModList.txt")
    else
        state.status = text("mr_saveFailed", dir)
    end
    state.statusTimer = ModRevealDisplay.STATUS_TIME
end

function ModRevealDisplay.update(dt)
    state.frame = state.frame + 1
    if state.statusTimer > 0 then
        state.statusTimer = state.statusTimer - dt
        if state.statusTimer <= 0 then
            state.status = nil
        end
    end
    if not state.isOpen then
        state.pending = nil
        return
    end
    if g_gui:getIsGuiVisible() then
        ModRevealDisplay.close()
        return
    end
    if state.pending ~= nil then
        local fn = state.pending
        state.pending = nil
        if state.typedAt ~= state.pendingAt then
            fn()
        end
    end

    local now = g_time or 0
    if state.axisDir ~= 0 then
        if now - state.axisTime > 150 then
            state.axisDir = 0              -- no event for a while: released
        elseif now >= state.nextRepeat then
            ModRevealDisplay.changeSelection(state.axisDir)
            state.nextRepeat = now + ModRevealDisplay.REPEAT_INTERVAL
        end
    end
end

-- typing searches; keys with Alt / Ctrl held are left alone (Left Alt + I is the toggle)
local function hasModifier(modifier, name)
    return modifier ~= nil and bitAND ~= nil and Input[name] ~= nil and bitAND(modifier, Input[name]) ~= 0
end

-- Left Alt + I straight from the keyboard, in case the key binding never reaches us (taken by another action,
-- dropped from the player's bindings). Not with Ctrl or Shift held: Ctrl + Left Alt + I is AutoDrive's fleet key.
function ModRevealDisplay.watchToggleKey(sym, modifier, isDown)
    if sym ~= Input.KEY_i then
        return false
    end
    if not isDown then
        state.toggleKeyDown = false
        return false
    end
    if state.toggleKeyDown or not hasModifier(modifier, "MOD_LALT") or hasModifier(modifier, "MOD_LCTRL")
        or hasModifier(modifier, "MOD_RCTRL") or hasModifier(modifier, "MOD_LSHIFT") or hasModifier(modifier, "MOD_RSHIFT") then
        return false
    end
    state.toggleKeyDown = true
    if not state.isOpen and ModRevealDisplay.getOpenGuiName() ~= nil then
        return false                       -- typing in chat or a menu
    end
    ModRevealDisplay.toggle("keyboard watch")
    return true
end

function ModRevealDisplay.keyEvent(unicode, sym, modifier, isDown)
    if g_dedicatedServer ~= nil or Input == nil then
        return
    end
    if ModRevealDisplay.watchToggleKey(sym, modifier, isDown) then
        return
    end
    if not state.isOpen or not isDown then
        return
    end
    if modifier ~= nil and modifier ~= 0 and bitAND ~= nil and Input.MOD_LALT ~= nil then
        local held = bitAND(modifier, Input.MOD_LALT) + bitAND(modifier, Input.MOD_RALT or 0)
            + bitAND(modifier, Input.MOD_LCTRL or 0) + bitAND(modifier, Input.MOD_RCTRL or 0)
        if held ~= 0 then
            return
        end
    end
    if sym == Input.KEY_backspace then
        if state.search ~= "" then
            ModRevealDisplay.setSearch(dropLastChar(state.search))
        end
        return
    end
    if unicode ~= nil and unicode >= 32 and unicode ~= 127 and #state.search < 40 then
        local char = nil
        if unicodeToUtf8 ~= nil then
            local ok, value = pcall(unicodeToUtf8, unicode)
            char = ok and type(value) == "string" and value or nil
        end
        if char == nil and unicode < 128 then
            char = string.char(unicode)
        end
        if char ~= nil and char ~= "" then
            state.typedAt = g_time or 0
            if state.pending ~= nil and state.pendingAt == state.typedAt then
                state.pending = nil
            end
            ModRevealDisplay.setSearch(state.search .. char)
        end
    end
end

-- clickable areas, filled while drawing
local hitAreas = {}

function ModRevealDisplay.mouseEvent(posX, posY, isDown, isUp, button)
    if not state.isOpen then
        return
    end
    if isDown and (button == Input.MOUSE_BUTTON_WHEEL_UP or button == Input.MOUSE_BUTTON_WHEEL_DOWN) then
        ModRevealDisplay.changeSelection(button == Input.MOUSE_BUTTON_WHEEL_UP and -3 or 3)
        return
    end
    if isDown and button == Input.MOUSE_BUTTON_LEFT then
        for _, area in ipairs(hitAreas) do
            if isInside(posX, posY, area.x, area.y, area.w, area.h) then
                area.onClick()
                return
            end
        end
    end
end

-- drawing ----------------------------------------------------------------------------------------------

local PANEL_X, PANEL_Y, PANEL_W, PANEL_H = 140, 60, 1640, 960
local LEFT_X = PANEL_X + 25
local INNER_W = PANEL_W - 50

-- columns: x offset from LEFT_X and width
local COL = {
    num = {0, 48},
    title = {60, 420},
    chips = {490, 240},
    ingame = {740, 130},
    version = {880, 180},
    author = {1070, 185},
    file = {1265, 315}
}

local function addHit(x, y, w, h, onClick)
    table.insert(hitAreas, {x = x, y = y, w = w, h = h, onClick = onClick})
end

function ModRevealDisplay.draw()
    if not state.isOpen then
        return
    end
    hitAreas = {}

    rect(0, 0, 1920, 1080, COLOR.backdrop)
    rect(PANEL_X, PANEL_Y, PANEL_W, PANEL_H, COLOR.panel)

    -- header
    rect(PANEL_X, PANEL_Y, PANEL_W, 60, COLOR.header)
    label(LEFT_X, PANEL_Y + 14, 30, text("mr_title"), COLOR.headerText, true)
    local info = string.format("%s   |   %s   |   FS25 %s", ModReveal.getMapTitle(), ModReveal.getModeText(), ModReveal.getGameVersion())
    label(PANEL_X + PANEL_W - 25, PANEL_Y + 19, 20, fit(info, 20, 1000, true), COLOR.headerText, true, RenderText.ALIGN_RIGHT)

    ModRevealDisplay.drawTabs(PANEL_Y + 78)
    ModRevealDisplay.drawSummary(PANEL_Y + 132)

    local list = ModRevealDisplay.getList()
    ModRevealDisplay.drawList(list, PANEL_Y + 170)
    ModRevealDisplay.drawDetails(list[state.selected], PANEL_Y + 706)
    ModRevealDisplay.drawKeyHints(PANEL_Y + PANEL_H - 50)

    resetText()
end

function ModRevealDisplay.drawTabs(y)
    local x = LEFT_X
    for _, tab in ipairs(ModRevealDisplay.getTabs()) do
        local isSelected = tab.id == state.tab
        local w = textWidth(20, tab.label, true) + 36
        rect(x, y, w, 38, isSelected and COLOR.header or COLOR.tab)
        label(x + w / 2, y + 9, 20, tab.label, isSelected and COLOR.headerText or COLOR.text, true, RenderText.ALIGN_CENTER)
        local id = tab.id
        addHit(x, y, w, 38, function() ModRevealDisplay.setTab(id) end)
        x = x + w + 10
    end

    -- buttons and search, from the right
    local right = LEFT_X + INNER_W
    local saveLabel = text("mr_buttonSave")
    local saveW = textWidth(18, saveLabel, true) + 30
    rect(right - saveW, y, saveW, 38, COLOR.straw)
    label(right - saveW / 2, y + 10, 18, saveLabel, COLOR.headerText, true, RenderText.ALIGN_CENTER)
    addHit(right - saveW, y, saveW, 38, ModRevealDisplay.export)
    right = right - saveW - 10

    if state.tab ~= TAB_CHANGES then
        local sortLabel = text("mr_buttonSort", text("mr_sort_" .. SORTS[state.sort]))
        local sortW = textWidth(18, sortLabel, true) + 30
        rect(right - sortW, y, sortW, 38, COLOR.tab)
        label(right - sortW / 2, y + 10, 18, sortLabel, COLOR.text, true, RenderText.ALIGN_CENTER)
        addHit(right - sortW, y, sortW, 38, ModRevealDisplay.cycleSort)
        right = right - sortW - 10
    end

    local searchW = 330
    rect(right - searchW, y, searchW, 38, COLOR.rowStripe)
    rect(right - searchW, y + 36, searchW, 2, state.search ~= "" and COLOR.header or COLOR.textDim)
    if state.search == "" then
        label(right - searchW + 12, y + 10, 18, text("mr_searchHint"), COLOR.textDim, false)
    else
        local cursor = (math.floor((g_time or 0) / 500) % 2 == 0) and "_" or ""
        local shown = state.search
        while shown ~= "" and textWidth(18, shown .. "_", true) > searchW - 24 do
            shown = shown:gsub("^[^\128-\191][\128-\191]*", "")
        end
        label(right - searchW + 12, y + 10, 18, shown .. cursor, COLOR.text, true)
    end
end

function ModRevealDisplay.drawSummary(y)
    local s = ModReveal.summary
    local parts = {
        text("mr_sumActive", s.mods or 0, s.dlcs or 0),
        text("mr_sumScripts", s.scripts or 0),
        text("mr_sumMaps", s.maps or 0),
        text("mr_sumStoreItems", s.storeItems or 0)
    }
    local line = table.concat(parts, "   |   ")
    label(LEFT_X, y, 18, line, COLOR.textDim, false)

    -- warnings on the right, in colour
    local warnings = {}
    if (s.notMultiplayer or 0) > 0 then table.insert(warnings, {text("mr_sumNoMP", s.notMultiplayer), COLOR.bad}) end
    if (s.folders or 0) > 0 then table.insert(warnings, {text("mr_sumFolders", s.folders), COLOR.warn}) end
    if (s.duplicates or 0) > 0 then table.insert(warnings, {text("mr_sumDuplicates", s.duplicates), COLOR.bad}) end
    if ModReveal.usageReady and (s.idle or 0) > 0 then
        table.insert(warnings, {text("mr_sumIdle", s.idle), COLOR.warn, function()
            ModRevealDisplay.setTab(TAB_ACTIVE)
            state.sort = 2               -- IN GAME
            state.selected, state.scroll = 1, 0
            state.list = nil
        end})
    end
    local x = LEFT_X + INNER_W
    for i = #warnings, 1, -1 do
        local w = textWidth(18, warnings[i][1], true)
        label(x, y, 18, warnings[i][1], warnings[i][2], true, RenderText.ALIGN_RIGHT)
        if warnings[i][3] ~= nil then
            addHit(x - w - 5, y - 4, w + 10, 28, warnings[i][3])
        end
        x = x - w - 30
    end
end

-- small coloured tags; returns the width used
local function chip(x, y, value, color)
    local w = textWidth(14, value, true) + 14
    rect(x, y, w, 21, color)
    label(x + 7, y + 3, 14, value, COLOR.headerText, true)
    return w
end

function ModRevealDisplay.getChips(entry)
    local chips = {}
    if state.tab == TAB_CHANGES or entry.change ~= nil then
        if entry.change ~= nil then
            table.insert(chips, {text("mr_chip_" .. entry.change), CHIP[entry.change]})
        end
    end
    if entry.isDLC and state.tab ~= TAB_DLC then table.insert(chips, {text("mr_chip_DLC"), CHIP.DLC}) end
    if entry.isMap then table.insert(chips, {text("mr_chip_MAP"), CHIP.MAP}) end
    if entry.numScripts > 0 then table.insert(chips, {text("mr_chip_SCRIPT"), CHIP.SCRIPT}) end
    if entry.isActive and entry.isMultiplayer == false and not entry.isDLC then table.insert(chips, {text("mr_chip_NOMP"), CHIP.NOMP}) end
    if entry.isFolder == true then table.insert(chips, {text("mr_chip_FOLDER"), CHIP.FOLDER}) end
    if entry.isDuplicate then table.insert(chips, {text("mr_chip_DUP"), CHIP.DUP}) end
    if ModReveal.usageReady and entry.isIdle then table.insert(chips, 1, {text("mr_chip_IDLE"), CHIP.IDLE}) end
    return chips
end

function ModRevealDisplay.drawList(list, y)
    local rowW = INNER_W + 20
    rect(LEFT_X - 10, y - 5, rowW, 34, COLOR.rowHeader)
    label(LEFT_X + COL.num[1] + COL.num[2], y + 2, 17, "#", COLOR.textDim, true, RenderText.ALIGN_RIGHT)
    label(LEFT_X + COL.title[1], y + 2, 17, text("mr_colMod"), COLOR.textDim, true)
    label(LEFT_X + COL.chips[1], y + 2, 17, text("mr_colInfo"), COLOR.textDim, true)
    label(LEFT_X + COL.ingame[1], y + 2, 17, text("mr_colInGame"), COLOR.textDim, true)
    label(LEFT_X + COL.version[1], y + 2, 17, text("mr_colVersion"), COLOR.textDim, true)
    label(LEFT_X + COL.author[1], y + 2, 17, text("mr_colAuthor"), COLOR.textDim, true)
    label(LEFT_X + COL.file[1], y + 2, 17, text("mr_colFile"), COLOR.textDim, true)
    y = y + 40

    if #list == 0 then
        local key = "mr_empty"
        if state.search ~= "" then
            key = "mr_noMatch"
        elseif state.tab == TAB_CHANGES then
            key = ModReveal.isFirstVisit and "mr_firstVisit" or "mr_noChanges"
        end
        label(LEFT_X, y + 6, 20, text(key), COLOR.textDim, false)
        return
    end

    local rows, rowH = ModRevealDisplay.ROWS, ModRevealDisplay.ROW_H
    local listY = y
    for i = state.scroll + 1, math.min(#list, state.scroll + rows) do
        local entry = list[i]
        local isSelected = i == state.selected
        if isSelected then
            rect(LEFT_X - 10, y - 4, rowW, rowH - 1, COLOR.rowSelected)
        elseif i % 2 == 0 then
            rect(LEFT_X - 10, y - 4, rowW, rowH - 1, COLOR.rowStripe)
        end

        label(LEFT_X + COL.num[1] + COL.num[2], y, 17, tostring(i), COLOR.textDim, false, RenderText.ALIGN_RIGHT)
        label(LEFT_X + COL.title[1], y, 18, fit(entry.title, 18, COL.title[2] - 10, isSelected), COLOR.text, isSelected)

        local chipX = LEFT_X + COL.chips[1]
        for _, c in ipairs(ModRevealDisplay.getChips(entry)) do
            if chipX + textWidth(14, c[1], true) + 14 > LEFT_X + COL.chips[1] + COL.chips[2] then
                break
            end
            chipX = chipX + chip(chipX, y - 1, c[1], c[2]) + 5
        end

        if ModReveal.usageReady and entry.isActive then
            local inGame = ModReveal.getInGameText(entry)
            local inGameColor = entry.isIdle and COLOR.warn or ((entry.inGame or 0) > 0 and COLOR.text or COLOR.textDim)
            label(LEFT_X + COL.ingame[1], y, 17, fit(inGame, 17, COL.ingame[2] - 10, false), inGameColor, entry.isIdle)
        end

        local version = entry.version or "-"
        if entry.change == "UPDATED" or entry.change == "OLDER" then
            version = tostring(entry.oldVersion or "?") .. " > " .. tostring(entry.version or "?")
        end
        local versionColor = (entry.change == "UPDATED" and COLOR.good) or (entry.change == "OLDER" and COLOR.warn) or COLOR.straw
        label(LEFT_X + COL.version[1], y, 18, fit(version, 18, COL.version[2] - 10, false), versionColor, false)
        label(LEFT_X + COL.author[1], y, 18, fit(entry.author or "-", 18, COL.author[2] - 10, false), COLOR.textDim, false)
        label(LEFT_X + COL.file[1], y, 17, fit(entry.fileName, 17, COL.file[2] - 10, false), COLOR.textDim, false)

        local index = i
        addHit(LEFT_X - 10, y - 4, rowW, rowH - 1, function() state.selected = index end)
        y = y + rowH
    end

    -- scroll bar when not everything fits
    if #list > rows then
        local barH = rows * rowH - 4
        local thumbH = math.max(30, barH * rows / #list)
        local thumbY = listY - 4 + (barH - thumbH) * state.scroll / (#list - rows)
        rect(LEFT_X + INNER_W + 4, listY - 4, 4, barH, COLOR.rowStripe)
        rect(LEFT_X + INNER_W + 4, thumbY, 4, thumbH, COLOR.header)
    end
end

function ModRevealDisplay.drawDetails(entry, y)
    local x, w, h = LEFT_X - 10, INNER_W + 20, 190
    rect(x, y, w, h, COLOR.detailsPanel)
    rect(x, y, 4, h, COLOR.header)
    if entry == nil then
        return
    end
    x = x + 22
    local maxW = w - 44

    local title = entry.title
    if entry.title ~= entry.modName then
        title = title .. "   (" .. entry.modName .. ")"
    end
    label(x, y + 12, 22, fit(title, 22, maxW, true), COLOR.header, true)

    local line1 = {
        text("mr_detVersion", entry.version or "-"),
        text("mr_detAuthor", entry.author or "-"),
        text("mr_detFile", entry.fileName or "-")
    }
    if entry.hash ~= nil then
        table.insert(line1, text("mr_detHash", entry.hash))
    end
    label(x, y + 44, 18, fit(table.concat(line1, "     "), 18, maxW, false), COLOR.text, false)

    local line2 = {}
    local kind = {}
    if entry.isDLC then table.insert(kind, text("mr_kindDLC")) end
    if entry.isMap then table.insert(kind, text("mr_kindMap")) end
    if entry.numScripts > 0 then table.insert(kind, text("mr_kindScript", entry.numScripts)) end
    if entry.numSpecializations > 0 then table.insert(kind, text("mr_kindSpecs", entry.numSpecializations)) end
    if entry.numStoreItems > 0 then table.insert(kind, text("mr_kindStore", entry.numStoreItems)) end
    if #kind > 0 then
        table.insert(line2, table.concat(kind, ", "))
    end
    if entry.isMultiplayer ~= nil then
        table.insert(line2, text(entry.isMultiplayer and "mr_detMPYes" or "mr_detMPNo"))
    end
    if entry.descVersion ~= nil then
        table.insert(line2, text("mr_detDescVersion", entry.descVersion))
    end
    if entry.isActive == false and entry.change == nil then
        table.insert(line2, text("mr_detNotUsed"))
    end
    local change = ModReveal.getChangeText(entry)
    if change ~= nil then
        table.insert(line2, change)
    end
    label(x, y + 70, 18, fit(table.concat(line2, "     "), 18, maxW, false), COLOR.textDim, false)

    local usageLine, usageColor = ModRevealDisplay.getUsageLine(entry)
    if usageLine ~= nil then
        label(x, y + 96, 18, fit(usageLine, 18, maxW, false), usageColor, false)
    end

    local line3 = {}
    if #entry.dependencies > 0 then
        table.insert(line3, text("mr_detNeeds", table.concat(entry.dependencies, ", ")))
    end
    if entry.isFolder == true then
        table.insert(line3, text("mr_detFolderWarn"))
    end
    if entry.isDuplicate then
        table.insert(line3, text("mr_detDuplicateWarn"))
    end
    if entry.isActive and entry.isMultiplayer == false and not entry.isDLC then
        table.insert(line3, text("mr_detNoMPWarn"))
    end
    if #line3 > 0 then
        label(x, y + 122, 18, fit(table.concat(line3, "     "), 18, maxW, false), COLOR.warn, false)
    end

    if entry.description ~= nil then
        label(x, y + 152, 16, fit(entry.description, 16, maxW, false), COLOR.textDim, false)
    end
end

-- "In this game: 5 vehicles (2 yours), 1 building     Shop: 12 items: A, B, C, ..."
function ModRevealDisplay.getUsageLine(entry)
    if not entry.isActive then
        return nil
    end
    if not ModReveal.usageReady or entry.usage == nil then
        return text("mr_useCounting"), COLOR.textDim
    end
    if entry.isCurrentMap then
        return text("mr_useCurrentMap"), COLOR.good
    end
    local u = entry.usage
    local parts = {}
    local mine = ModReveal.myFarmId ~= nil
    local function add(count, own, key)
        if count > 0 then
            local value = text(key, count)
            if mine and own > 0 then
                value = value .. " " .. text("mr_useYours", own)
            end
            table.insert(parts, value)
        end
    end
    add(u.vehicles, u.ownVehicles, "mr_useVehicles")
    add(u.placeables, u.ownPlaceables, "mr_usePlaceables")
    add(u.handTools, u.ownHandTools, "mr_useHandTools")

    local line, color
    if #parts > 0 then
        line, color = text("mr_useInGame", table.concat(parts, ", ")), COLOR.good
    elseif u.storeItems > 0 then
        line, color = text(entry.isIdle and "mr_useNothingIdle" or "mr_useNothing"), entry.isIdle and COLOR.warn or COLOR.textDim
    else
        line, color = text("mr_useNoItems"), COLOR.textDim
    end
    if u.storeItems > 0 then
        local names = table.concat(u.shopNames, ", ")
        if u.storeItems > #u.shopNames then
            names = names .. ", ..."
        end
        line = line .. "     " .. text("mr_useShop", u.storeItems, names)
    end
    return line, color
end

function ModRevealDisplay.drawKeyHints(y)
    local x = LEFT_X
    local hints = {
        {"ESC", text("mr_keyClose")},
        {text("mr_keyLeftRight"), text("mr_keyTab")},
        {text("mr_keyUpDown"), text("mr_keySelect")},
        {"A-Z", text("mr_keySearch")}
    }
    for _, hint in ipairs(hints) do
        local keyWidth = textWidth(17, hint[1], true)
        rect(x, y, keyWidth + 20, 30, COLOR.keyBox)
        label(x + 10, y + 6, 17, hint[1], COLOR.headerText, true)
        x = x + keyWidth + 30
        label(x, y + 6, 17, hint[2], COLOR.text, false)
        x = x + textWidth(17, hint[2], false) + 35
    end

    if state.status ~= nil then
        label(LEFT_X + INNER_W, y + 6, 17, fit(state.status, 17, LEFT_X + INNER_W - x - 20, false), COLOR.straw, false, RenderText.ALIGN_RIGHT)
    end
end
