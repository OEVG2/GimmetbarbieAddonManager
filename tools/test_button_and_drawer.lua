--[[
    test_button_and_drawer.lua - the addon's own button moves freely around the
    screen, and the drawer is sized so every collected button (and its round
    border) sits inside the drawer's frame.

    Usage (from the repo root):
        lua tools/test_button_and_drawer.lua [path/to/addon.lua]
--]]

local Stub = dofile("tools/wow_stub.lua")
local ADDON_PATH = arg[1] or "GimmetbarbieAddonManager.lua"

local failures, checks = 0, 0
local function check(label, got, want)
    checks = checks + 1
    if got ~= want then
        failures = failures + 1
        print("  FAIL " .. label .. ": got " .. tostring(got) .. ", wanted " .. tostring(want))
    end
end
local function near(a, b) return a and b and math.abs(a - b) < 0.01 end

local function boot(saved)
    Stub.Reset()
    saved = saved or {}
    GetRealmName = function() return "Realm" end
    time = os.time
    date = function() return "12:00:00" end
    GameTooltip = Stub.CreateFrame("Frame", "GameTooltip")
    Minimap = Stub.CreateFrame("Frame", "Minimap")
    Minimap._w, Minimap._h = 140, 140
    Minimap:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 1700, 1050) -- centre 1770, 980
    ReloadUI = function() end
    geterrorhandler = function() return function() end end
    seterrorhandler = function() end
    GetNumAddOns = function() return 0 end
    GetAddOnInfo = function() return nil end
    IsAddOnLoaded = function() return nil end
    EnableAddOn = function() end
    DisableAddOn = function() end
    UIParent._w, UIParent._h = 1920, 1080
    UIParent._baseTop = 1080

    AM_ButtonPos, AM_MinimapPos = saved.buttonPos, saved.minimapPos
    AM_FramePos, AM_ErrorLog, AM_ReleasedButtons, AM_Profiles = nil, nil, nil, nil
    AM = nil
    dofile(ADDON_PATH)
    AM.releasedNames = {}
    AM.CreateDrawer()
    AM.CreateMinimapButton()
end

-- ---------------------------------------------------------------------------
print("button is free-floating")
boot({ minimapPos = 180 })
local b = AM.minimapButton
check("parented to UIParent, not Minimap", b._parent, UIParent)
-- first run keeps the old ring spot: angle 180 = left of minimap centre by radius 80
local cx, cy = b:GetCenter()
check("first run starts at old ring x", near(cx, 1770 - 80), true)
check("first run starts at old ring y", near(cy, 980), true)

-- grab the button 5px right of its centre and drag it to the bottom-left area
Stub.cursor.x, Stub.cursor.y = cx + 5, cy
Stub.ctrlDown = true
Stub.FireScript(b, "OnMouseDown", nil, "LeftButton")
Stub.cursor.x, Stub.cursor.y = 305, 205
Stub.FireScript(b, "OnUpdate", nil, 0.01)
Stub.FireScript(b, "OnMouseUp", nil, "LeftButton")
Stub.ctrlDown = false
cx, cy = b:GetCenter()
check("follows cursor, keeping grab offset (x)", near(cx, 300), true)
check("follows cursor (y)", near(cy, 205), true)
check("far from the minimap now", cx < 1000, true)

-- plain press doesn't move it
Stub.FireScript(b, "OnMouseDown", nil, "LeftButton")
Stub.cursor.x, Stub.cursor.y = 900, 900
Stub.FireScript(b, "OnUpdate", nil, 0.01)
Stub.FireScript(b, "OnMouseUp", nil, "LeftButton")
cx = b:GetCenter()
check("plain drag doesn't move it", near(cx, 300), true)

-- survives a reload
local saved = AM_ButtonPos
boot({ buttonPos = saved, minimapPos = 180 })
cx, cy = AM.minimapButton:GetCenter()
check("position restored after reload", near(cx, 300) and near(cy, 205), true)

-- reset puts it back by the minimap
Stub.RunSlash("ADDONMANAGER", "resetbutton")
cx = AM.minimapButton:GetCenter()
check("/am resetbutton returns it near the minimap", cx > 1600, true)

-- ---------------------------------------------------------------------------
print("drawer opens toward the middle of the screen")
local function drawerSide(bx, by)
    boot({ buttonPos = { x = bx, y = by } })
    AM.ToggleDrawer()
    local p = AM.drawer._points[1]
    return p and p.point
end
check("top-right button -> drawer below-left", drawerSide(1800, 1000), "TOPRIGHT")
check("bottom-left button -> drawer above-right", drawerSide(100, 100), "BOTTOMLEFT")
check("top-left button -> drawer below-right", drawerSide(100, 1000), "TOPLEFT")

-- ---------------------------------------------------------------------------
print("drawer fits its buttons")
local function fitCase(label, specs)
    boot({ buttonPos = { x = 1800, y = 1000 } })
    AM.ToggleDrawer() -- anchors and shows it
    AM.collectedList = {}
    for i, sp in ipairs(specs) do
        local btn = Stub.CreateFrame("Button", "Fake" .. label .. i, AM.drawer)
        btn._w, btn._h = sp[1], sp[1]
        local scale = sp[2] or 1
        btn.GetScale = function() return scale end
        table.insert(AM.collectedList, btn)
    end
    AM.LayoutDrawer()
    local dl, dt = AM.drawer:GetLeft(), AM.drawer:GetTop()
    local dr, db = dl + AM.drawer:GetWidth(), dt - AM.drawer:GetHeight()
    local BORDER = 4 -- silver tooltip edge
    local worst = 999
    for _, btn in ipairs(AM.collectedList) do
        -- The stub ignores scale when resolving geometry, so work out the drawn
        -- rect from the anchor offset (which is in the button's own scale).
        local p = btn._points[1]
        local s = btn:GetScale()
        assert(p.point == "CENTER" and p.relPoint == "TOPLEFT" and p.relativeTo == AM.drawer)
        local ccx, ccy = dl + p.x * s, dt + p.y * s
        local half = btn._w * s / 2
        worst = math.min(worst, (ccx - half) - dl, dr - (ccx + half), dt - (ccy + half), (ccy - half) - db)
    end
    check(label .. ": every button clear of the border", worst >= BORDER + 2, true)
    return worst
end
fitCase("21 mixed 31-33px (like the screenshot)", (function()
    local t = {}
    for i = 1, 21 do t[i] = { 31 + math.mod(i, 3) } end
    return t
end)())
fitCase("one scaled-up button", { { 31 }, { 31, 1.3 }, { 28 } })
fitCase("small 24px buttons", { { 24 }, { 24 }, { 24 }, { 24 } })

-- no overlap between neighbours
boot({ buttonPos = { x = 1800, y = 1000 } })
AM.collectedList = {}
for i = 1, 3 do
    local btn = Stub.CreateFrame("Button", "Nb" .. i, AM.drawer)
    btn._w, btn._h = 33, 33
    table.insert(AM.collectedList, btn)
end
AM.LayoutDrawer()
local gap = AM.collectedList[2]._points[1].x - AM.collectedList[1]._points[1].x
check("neighbours don't overlap", gap >= 33, true)

-- ---------------------------------------------------------------------------
print("button matches the minimap's scale")
boot({ buttonPos = { x = 500, y = 400 } })
b = AM.minimapButton
-- the shared stub ignores scale, so give the button a real one and a scaled minimap
local bscale = 1
b.SetScale = function(_, v) bscale = v end
b.GetScale = function() return bscale end
Minimap.GetEffectiveScale = function() return 1.25 end
AM.UpdateMinimapButtonPos()
check("button scale copies minimap scale", near(bscale, 1.25), true)
local pt = b._points[1]
check("anchor offset divided by scale (x)", near(pt.x * bscale, 500), true)
check("anchor offset divided by scale (y)", near(pt.y * bscale, 400), true)
-- GetCenter answers in scaled units; the addon converts back to screen units
local ux, uy = AM.MinimapButtonCenter()
check("centre reported in screen units", near(ux, 500 / 1.25 * 1.25) and near(uy, 400), true)
-- minimap scale changes later (another addon): next 5s sweep picks it up
Minimap.GetEffectiveScale = function() return 1.5 end
AM.ScanMinimapButtons = function() end
AM.UpdateDrawerAutoClose = function() end
for _, f in ipairs(Stub.allFrames) do
    if f._events and f._events.ADDON_LOADED then
        f.initialScanDone = true
        f.rescanTimer = 0
        Stub.FireScript(f, "OnUpdate", nil, 5.1)
    end
end
check("later minimap rescale is picked up", near(bscale, 1.5), true)
check("and the button stays put on screen", near(b._points[1].x * bscale, 500), true)

print("")
if failures == 0 then
    print("all " .. checks .. " checks passed")
else
    print(failures .. " of " .. checks .. " checks FAILED")
    os.exit(1)
end
