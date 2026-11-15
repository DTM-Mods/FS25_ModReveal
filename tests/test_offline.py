"""Offline test of FS25_ModReveal: runs both scripts in lupa (Lua 5.4/5.5, stricter than the game's 5.1) with
stubbed engine functions, through two loads: a first visit and one where mods were updated, added and removed.
Usage: python tests/test_offline.py        (needs: pip install lupa)"""
import os
import re
import shutil
import sys
import tempfile
import xml.etree.ElementTree as ET

from lupa import LuaRuntime

PROJ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HERE = tempfile.mkdtemp(prefix="modreveal_test_")
MOD_DESCS = {
    "FS25_ModA": '<modDesc descVersion="114"><author>Alice</author><version>1.2.0.0</version><multiplayer supported="true"/>'
                 '<extraSourceFiles><sourceFile filename="a.lua"/><sourceFile filename="b.lua"/></extraSourceFiles>'
                 '<storeItems><storeItem xmlFilename="x.xml"/></storeItems>'
                 '<dependencies><dependency>FS25_MapB</dependency></dependencies></modDesc>',
    "FS25_MapB": '<modDesc descVersion="110"><author>Bob</author><version>2.0</version><multiplayer supported="false"/>'
                 '<maps><map id="x"/></maps></modDesc>',
    "FS25_Folder": '<modDesc descVersion="110"><author>Carl</author><version>0.1</version></modDesc>',
}
for name, content in MOD_DESCS.items():
    os.makedirs(os.path.join(HERE, "fakemods", name))
    open(os.path.join(HERE, "fakemods", name, "modDesc.xml"), "w", encoding="utf-8").write(content)
for name in ("FS25_ModA", "FS25_MapB"):
    open(os.path.join(HERE, "fakemods", name + ".zip"), "wb").close()
os.makedirs(os.path.join(HERE, "profile"))
lua = LuaRuntime(unpack_returned_tuples=True)
G = lua.globals()
xmls, files, nxt = {}, {}, [1]


def parsekey(k):
    attr = None
    if '#' in k:
        k, attr = k.split('#', 1)
    parts = []
    for p in k.split('.'):
        m = re.match(r'(\w+)\((\d+)\)$', p)
        parts.append((m.group(1), int(m.group(2))) if m else (p, 0))
    return parts, attr


def find(root, k):
    parts, attr = parsekey(k)
    if parts[0][0] != root.tag:
        return None, attr
    node = root
    for tag, idx in parts[1:]:
        ch = [c for c in node if c.tag == tag]
        if idx >= len(ch):
            return None, attr
        node = ch[idx]
    return node, attr


def loadXMLFile(name, path, root=None):
    try:
        t = ET.parse(path).getroot()
    except Exception:
        return 0
    i = nxt[0]; nxt[0] += 1
    xmls[i] = (t, path)
    return i


def createXMLFile(name, path, root):
    i = nxt[0]; nxt[0] += 1
    xmls[i] = (ET.Element(root), path)
    return i


def getS(x, k):
    n, a = find(xmls[x][0], k)
    if n is None:
        return None
    if a:
        return n.get(a)
    return (n.text or '').strip() or None


def has(x, k):
    n, a = find(xmls[x][0], k)
    return n is not None and (a is None or n.get(a) is not None)


def setS(x, k, v):
    assert isinstance(v, str), (k, v)
    root = xmls[x][0]
    parts, attr = parsekey(k)
    node = root
    for tag, idx in parts[1:]:
        ch = [c for c in node if c.tag == tag]
        while len(ch) <= idx:
            ch.append(ET.SubElement(node, tag))
        node = ch[idx]
    node.set(attr, v)


def save(x):
    ET.ElementTree(xmls[x][0]).write(xmls[x][1], encoding='utf-8')


def createFile(p, mode):
    i = nxt[0]; nxt[0] += 1
    files[i] = [p, []]
    return i


def fileWrite(f, s):
    files[f][1].append(s)


def delete(i):
    if i in files:
        open(files[i][0], 'w', encoding='utf-8', newline='').write(''.join(files[i][1]))
        del files[i]
    xmls.pop(i, None)


G.loadXMLFile = loadXMLFile
G.createXMLFile = createXMLFile
G.getXMLString = getS
G.getXMLInt = lambda x, k: (int(getS(x, k)) if getS(x, k) else None)
G.getXMLBool = lambda x, k: (None if getS(x, k) is None else getS(x, k).lower() == 'true')
G.hasXMLProperty = has
G.setXMLString = setS
G.setXMLBool = lambda x, k, v: setS(x, k, 'true' if v else 'false')
G.saveXMLFile = save
G.delete = delete
G.createFile = createFile
G.fileWrite = fileWrite
G.fileExists = lambda p: os.path.exists(p)
G.createFolder = lambda p: os.makedirs(p, exist_ok=True)
G.getUserProfileAppPath = lambda: HERE.replace('\\', '/') + '/profile/'
tr = {e.get('name'): e.get('text') for e in ET.parse(os.path.join(PROJ, 'translations/l10n_en.xml')).getroot().iter('text')}
G.TR = lua.table_from(tr)
drawn = []
G.renderText = lambda x, y, s, t: drawn.append(t)

lua.execute('''
g_currentModName = "FS25_ModReveal"; g_currentModDirectory = "x/"
g_i18n = {getText = function(self, n) local v = TR[n]; if v == nil then error("missing text "..n) end; return v end}
Utils = {appendedFunction = function(a, b) return function(...) if a then a(...) end; b(...) end end}
PlayerInputComponent = {registerGlobalPlayerActionEvents = function() end}
InputAction = {MR_TOGGLE = "MR_TOGGLE", MENU_BACK = "MENU_BACK", MENU_AXIS_UP_DOWN = "UD", MENU_AXIS_LEFT_RIGHT = "LR", MENU_PAGE_PREV = "MENU_PAGE_PREV", MENU_PAGE_NEXT = "MENU_PAGE_NEXT", MENU_EXTRA_1 = "MENU_EXTRA_1", MENU_EXTRA_2 = "MENU_EXTRA_2"}
Input = {MOD_LALT = 1, MOD_RALT = 2, MOD_LCTRL = 4, MOD_RCTRL = 8, MOD_LSHIFT = 16, MOD_RSHIFT = 32, KEY_i = 105, KEY_backspace = 8, MOUSE_BUTTON_LEFT = 1, MOUSE_BUTTON_WHEEL_UP = 4, MOUSE_BUTTON_WHEEL_DOWN = 5}
function bitAND(a, b) return a & b end
FileAccess = {WRITE = 2}; RenderText = {ALIGN_LEFT = 0, ALIGN_CENTER = 1, ALIGN_RIGHT = 2}
FSBaseMission = {INGAME_NOTIFICATION_INFO = 3, draw = function() end}
events = {}
g_inputBinding = {setContext = function() end, revertContext = function() end, setShowMouseCursor = function() end,
  registerActionEvent = function(self, a, t, cb, ...) events[a] = cb; return true, 1 end, setActionEventTextVisibility = function() end}
g_gui = {getIsGuiVisible = function() return false end}
listeners = {}; function addModEventListener(l) table.insert(listeners, l) end
consoleCmds = {}; function addConsoleCommand(n, d, f, t) consoleCmds[n] = function() return t[f](t) end end
function removeConsoleCommand() end
function setTextBold() end; function setTextAlignment() end; function setTextColor() end
function drawFilledRect() end
function getTextWidth(s, t) return s * #t * 0.28 end
function utf8Strlen(s) return utf8.len(s) end
g_time = 0
''')

MODS = HERE.replace('\\', '/') + '/fakemods/'


def item(name, title, ver, extra=''):
    return f'{{modName="{name}", title="{title}", version="{ver}", author="X", modDir="{MODS}{name}/", fileHash="h{ver}"{extra}}}'


def run_setup(items_lua, title):
    lua.execute('''
    g_modManager = {getActiveMods = function() return ACTIVE end, getMods = function() return ALL end}
    notified = nil
    g_currentMission = {missionInfo = {mapTitle = "Riverbend Springs", savegameIndex = 3, mapId = "MapUS"},
       missionDynamicInfo = {isMultiplayer = true}, addIngameNotification = function(self, t, m) notified = m end,
       getFarmId = function() return 1 end,
       hud = {visible = true, setIsVisible = function(self, v) self.visible = v end, getIsVisible = function(self) return self.visible end}}
    g_server = {}
    -- what is in the savegame: two Mod A vehicles (one ours), a hand tool of Mod A; Brand new only has a shop item
    local function obj(env, farm) return {customEnvironment = env, getOwnerFarmId = function() return farm end} end
    g_storeManager = {getItems = function() return {
        {customEnvironment = "FS25_ModA", name = "Tractor A", showInStore = true},
        {customEnvironment = "FS25_ModA", name = "Trailer A", showInStore = true},
        {customEnvironment = "FS25_New", name = "Silo", showInStore = true},
        {name = "Base game thing"}} end}
    g_currentMission.vehicleSystem = {vehicles = {obj("FS25_ModA", 1), obj("FS25_ModA", 2), obj(nil, 1)}}
    g_currentMission.placeableSystem = {placeables = {obj(nil, 0)}}
    g_currentMission.handToolSystem = {handTools = {obj("FS25_ModA", 1)}}
    ''' + items_lua)
    for p in ('scripts/ModRevealDisplay.lua', 'scripts/ModReveal.lua'):
        lua.execute(open(os.path.join(PROJ, p), encoding='utf-8').read())
    lua.execute('''
    local l = listeners[#listeners]
    l:loadMap("x")
    for i = 1, 60 do g_time = g_time + 400; l:update(400) end
    print("notified:", notified)
    PlayerInputComponent.registerGlobalPlayerActionEvents({})
    -- keyboard watch: Left Alt + I opens, and the key binding firing for the same press must not close it again
    l:keyEvent(0, Input.KEY_i, Input.MOD_LALT, true); events.MR_TOGGLE()
    assert(ModRevealDisplay.isOpen(), 'Left Alt + I did not open the window')
    assert(not g_currentMission.hud.visible, 'the game HUD was not hidden while the window is open')
    l:draw()
    -- drawn after the whole mission (HUD and other overlays); then the listener's draw stands back
    local drawCalls = 0
    local realDraw = ModRevealDisplay.draw
    ModRevealDisplay.draw = function() drawCalls = drawCalls + 1; realDraw() end
    FSBaseMission.draw(g_currentMission); l:update(16); l:draw()
    assert(drawCalls == 1, 'drawn ' .. drawCalls .. ' times in one frame (late draw + listener draw)')
    ModRevealDisplay.draw = realDraw
    l:keyEvent(0, Input.KEY_i, Input.MOD_LALT, false)
    l:keyEvent(0, Input.KEY_i, Input.MOD_LALT + Input.MOD_LCTRL, true)   -- Ctrl+Alt+I (AutoDrive): ignored
    l:keyEvent(0, Input.KEY_i, 0, false)
    assert(ModRevealDisplay.isOpen(), 'Ctrl + Alt + I closed the window')
    g_time = g_time + 1000; l:keyEvent(0, Input.KEY_i, Input.MOD_LALT, true); l:keyEvent(0, Input.KEY_i, Input.MOD_LALT, false)
    assert(not ModRevealDisplay.isOpen(), 'Left Alt + I did not close the window')
    assert(g_currentMission.hud.visible, 'the game HUD was not shown again on close')
    -- a HUD the player had hidden stays hidden
    g_currentMission.hud.visible = false
    g_time = g_time + 1000; consoleCmds.modRevealShow(); events.MENU_BACK()
    assert(not ModRevealDisplay.isOpen() and not g_currentMission.hud.visible, 'a hidden HUD was shown on close')
    g_currentMission.hud.visible = true
    g_time = g_time + 1000; print(consoleCmds.modRevealShow()); assert(ModRevealDisplay.isOpen(), 'modRevealShow did not open')
    -- gamepad RB changes the tab; the same action from typing "e" (same frame as the typed letter) must not
    local tab0 = ModRevealDisplay.getTab()
    g_time = g_time + 16; events.MENU_PAGE_NEXT(); l:update(16)
    assert(ModRevealDisplay.getTab() ~= tab0, 'RB did not change the tab')
    local tab1 = ModRevealDisplay.getTab()
    g_time = g_time + 16; events.MENU_PAGE_NEXT(); l:keyEvent(101, 101, 0, true); l:update(16)
    local tab2, search = ModRevealDisplay.getTab()
    assert(tab2 == tab1 and search == "e", 'typing e also changed the tab')
    events.MENU_BACK(); events.MENU_EXTRA_1(); g_time = g_time + 16; l:update(16); l:draw()
    for tab = 1, 5 do
      for i = 1, 3 do l:draw(); events.UD(nil, nil, -1); g_time = g_time + 16; l:update(16) end
      for i = 1, 40 do events.UD(nil, nil, -1); g_time = g_time + 16; l:update(16) end
      events.UD(nil, nil, 0)
      l:mouseEvent(0.5, 0.5, true, false, 5); l:mouseEvent(0.5, 0.5, true, false, 1); l:draw()
      events.LR(nil, nil, 1)
    end
    l:keyEvent(109, 109, 0, true); l:keyEvent(97, 97, 0, true); l:draw()
    l:keyEvent(0, 8, 0, true); l:keyEvent(0, 8, 0, true); l:keyEvent(0, 8, 0, true)
    l:keyEvent(122, 122, 0, true); l:draw()
    events.MENU_BACK(); l:draw()
    for i = 1, 4 do ModRevealDisplay.cycleSort(); l:draw() end
    ModRevealDisplay.export(); l:draw()
    events.MENU_BACK()
    print(consoleCmds.modReveal()); print(consoleCmds.modRevealChanges()); print(consoleCmds.modRevealExport())
    l:deleteMap()
    ''')
    print('==', title, 'texts drawn', len(drawn))


items1 = ('ACTIVE = {' + ','.join([item('FS25_ModA', 'Mod A', '1.2.0.0'), item('FS25_MapB', 'Map B', '2.0'),
                                    item('FS25_Folder', 'Mod A', '0.1'),
                                    '{modName="pdlc_test", title="Test DLC", version="1.0", isDLC=true}']) + '}\n'
          'ALL = {ACTIVE[1], ACTIVE[2], ACTIVE[3], ACTIVE[4], {modName="FS25_Unused", title="Unused thing", version="9"}}')
run_setup(items1, 'first visit')
items2 = ('ACTIVE = {' + ','.join([item('FS25_ModA', 'Mod A', '1.3.0.0'), item('FS25_MapB', 'Map B', '1.9'),
                                    item('FS25_New', 'Brand new', '1.0')]) + '}\nALL = nil')
drawn.clear()
run_setup(items2, 'second visit')
out = os.path.join(HERE, 'profile/modSettings/FS25_ModReveal/')
text = open(out + 'ModList.txt', encoding='utf-8').read()
csv = open(out + 'ModList.csv', encoding='utf-8').read()
print(text)
print(csv)
for needle in ('Updated 1.2.0.0 > 1.3.0.0', 'Older version 2.0 > 1.9', 'FS25_Folder/', 'FOLDER (not zipped)',
               'NOT FOR MULTIPLAYER', 'New since last time', 'In game: 3 (2 yours)', 'NOTHING IN GAME',
               'Nothing in game: 1 mods'):
    assert needle in text, needle
changes = open(out + 'Changes.txt', encoding='utf-8').read()
print(changes)
assert 'change\tUPDATED\tMod A\tFS25_ModA.zip\t1.2.0.0\t1.3.0.0\tmod' in changes, changes
assert 'change\tREMOVED\tTest DLC\tpdlc_test\t1.0\t\tdlc' in changes, changes
assert 'change\tNEW\tBrand new\tFS25_New/\t\t1.0\tmod' in changes, changes
assert 'firstVisit\tno' in changes
assert ',FS25_ModA.zip,' in csv and ',2,3,2,no' in csv, csv
assert any(t.startswith('In this savegame: vehicles / pallets: 2 (1 yours), hand tools: 1 (1 yours)') for t in drawn), \
    [t for t in drawn if 'savegame' in t][:5]
assert 'removed,FS25_Folder,Mod A,0.1,X,FS25_Folder/' in csv
assert lua.eval('notified') is not None and '2 updated, 1 new, 2 removed' in lua.eval('notified')
assert any('1.2.0.0 > 1.3.0.0' == t for t in drawn), 'version change not drawn'
shutil.rmtree(HERE, ignore_errors=True)
print('ALL OK')
