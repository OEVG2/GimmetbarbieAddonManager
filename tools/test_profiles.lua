--[[
    test_profiles.lua - profile slots save and restore which addons are
    enabled, plus the minimap button's click/drag bindings.

    Usage (from the repo root):
        lua tools/test_profiles.lua [path/to/addon.lua]
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

-- A fake installed-addon list: { name, enabled }. Order is the client's index order.
local installed
local reloads

local function boot(addonSpec, savedProfiles)
    Stub.Reset()
    installed = {}
    for i, a in ipairs(addonSpec) do installed[i] = { name = a[1], enabled = a[2] } end
    reloads = 0

    GetRealmName = function() return "Realm" end
    time = os.time
    date = function() return "12:00:00" end
    GameTooltip = Stub.CreateFrame("Frame", "GameTooltip")
    Minimap = Stub.CreateFrame("Frame", "Minimap")
    Minimap._w, Minimap._h = 140, 140
    Minimap:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 1000, 900)
    ReloadUI = function() reloads = reloads + 1 end
    geterrorhandler = function() return function() end end
    seterrorhandler = function() end
    GetNumAddOns = function() return table.getn(installed) end
    GetAddOnInfo = function(i)
        local a = installed[i]
        return a.name, a.name, "", a.enabled, (not a.enabled) and "DISABLED" or nil
    end
    IsAddOnLoaded = function() return nil end
    EnableAddOn = function(i) installed[i].enabled = true end
    DisableAddOn = function(i) installed[i].enabled = false end

    -- Frame API the main window uses that the shared stub doesn't model.
    local mt = getmetatable(Stub.CreateFrame("Frame"))
    for _, m in ipairs({ "LockHighlight", "UnlockHighlight", "SetAutoFocus", "ClearFocus",
        "SetMultiLine", "SetMaxLetters", "SetScrollChild", "UpdateScrollChildRect",
        "SetVerticalScroll", "SetFrameLevel", "SetHeight", "SetWidth", "GetWidth",
        "SetNumeric", "HighlightText", "SetTextInsets", "EnableKeyboard" }) do
        if not mt.__index[m] then mt.__index[m] = function() end end
    end
    mt.__index.LockHighlight = function(self) self._locked = true end
    mt.__index.UnlockHighlight = function(self) self._locked = false end

    AM_Profiles = savedProfiles
    AM_MinimapPos, AM_FramePos, AM_ErrorLog, AM_ReleasedButtons = nil, nil, nil, nil
    AM = nil
    dofile(ADDON_PATH)
    AM.releasedNames = {}
    AM.CreateDrawer()
    AM.CreateMinimapButton()
end

local function isEnabled(name)
    for _, a in ipairs(installed) do if a.name == name then return a.enabled end end
end

local function clickProfile(slot, mods)
    mods = mods or {}
    Stub.shiftDown, Stub.ctrlDown = mods.shift or false, mods.ctrl or false
    Stub.FireScript(AM.mainFrame.profileButtons[slot], "OnClick", nil, "LeftButton")
    Stub.shiftDown, Stub.ctrlDown = false, false
end

local SPEC = {
    { "GimmetbarbieAddonManager", true },
    { "BigWigs", true }, { "Questie", true }, { "aux", true }, { "pfQuest", false },
}

-- ---------------------------------------------------------------------------
print("profile save / load")
boot(SPEC, nil)
AM.ToggleMainFrame() -- builds the list and the window
local f = AM.mainFrame
check("4 profile buttons exist", f.profileButtons[4] ~= nil and f.profileButtons[5] == nil, true)
check("empty slot shows grey", f.profileButtons[1]:GetText(), "|cFF7777771|r")

clickProfile(1, { shift = true }) -- save "everything on" as slot 1
check("slot 1 saved", AM_Profiles[1] ~= nil and AM_Profiles[1].states.BigWigs, true)
check("slot 1 matches now (green)", f.profileButtons[1]:GetText(), "|cFF00FF7F1|r")
check("slot 1 highlighted", f.profileButtons[1]._locked, true)

-- build a raid setup by hand: questie + aux off, bigwigs on
for _, row in ipairs(AM.addons) do
    if row.name == "Questie" or row.name == "aux" then AM.ToggleAddonRow(row) end
end
check("slot 1 no longer matches (white)", f.profileButtons[1]:GetText(), "|cFFFFFFFF1|r")
clickProfile(2, { shift = true })
AM_Profiles[2].name = "Raid"
check("raid saved with Questie off", AM_Profiles[2].states.Questie, false)

-- back to slot 1 via click: everything the profile knows gets re-enabled
clickProfile(1)
check("Questie re-enabled by slot 1", isEnabled("Questie"), true)
check("aux re-enabled by slot 1", isEnabled("aux"), true)
check("pfQuest left disabled (was off when saved)", isEnabled("pfQuest"), false)
check("pending reload flagged", AM.pendingReload, true)
check("plain click doesn't reload", reloads, 0)
check("banner tells you to reload", f.banner:GetText(), "Reload needed to apply")

-- ctrl+click loads and reloads
clickProfile(2, { ctrl = true })
check("ctrl+click reloads", reloads, 1)
check("Questie off after raid profile", isEnabled("Questie"), false)

-- re-saving keeps the name
clickProfile(2, { shift = true })
check("re-save keeps name", AM_Profiles[2].name, "Raid")

-- ---------------------------------------------------------------------------
print("reload carries profiles; new addons and the manager itself are safe")
local saved = AM_Profiles
local spec2 = {}
for _, a in ipairs(installed) do table.insert(spec2, { a.name, a.enabled }) end
table.insert(spec2, { "NewAddon", true })         -- installed after the profiles were saved
saved[3] = { states = { GimmetbarbieAddonManager = false, BigWigs = false } }
boot(spec2, saved)
AM.ToggleMainFrame()
check("raid slot still matches after reload", AM.mainFrame.profileButtons[2]:GetText(), "|cFF00FF7F2|r")
clickProfile(1)
check("NewAddon untouched by an older profile", isEnabled("NewAddon"), true)
clickProfile(3)
check("profile can't disable the manager itself", isEnabled("GimmetbarbieAddonManager"), true)
check("profile 3 disables BigWigs", isEnabled("BigWigs"), false)

clickProfile(4) -- empty slot: nothing happens
check("empty slot load is a no-op", isEnabled("BigWigs"), false)

-- ---------------------------------------------------------------------------
print("slash commands")
boot(SPEC, nil)
Stub.RunSlash("ADDONMANAGER", "profile save 3")
check("/am profile save 3", AM_Profiles[3] ~= nil and AM_Profiles[3].states ~= nil, true)
Stub.RunSlash("ADDONMANAGER", "profile name 3 Raid Night")
check("/am profile name keeps case and spaces", AM_Profiles[3].name, "Raid Night")
DisableAddOn(2) -- BigWigs off, so loading slot 3 has something to change
AM.BuildAddonList()
Stub.RunSlash("ADDONMANAGER", "profile 3")
check("/am profile 3 loads", isEnabled("BigWigs"), true)
Stub.RunSlash("ADDONMANAGER", "profile clear 3")
check("/am profile clear 3", AM_Profiles[3], nil)
Stub.chat = {}
Stub.RunSlash("ADDONMANAGER", "profile")
check("/am profile lists slots", table.getn(Stub.chat), 1 + 4)

-- ---------------------------------------------------------------------------
print("minimap button clicks")
boot(SPEC, nil)
local opened = {}
AM.ToggleDrawer = function() opened.drawer = (opened.drawer or 0) + 1 end
AM.ToggleMainFrame = function() opened.list = (opened.list or 0) + 1 end
local mb = AM.minimapButton
Stub.FireScript(mb, "OnClick", nil, "LeftButton")
check("left-click opens drawer", opened.drawer, 1)
Stub.FireScript(mb, "OnClick", nil, "RightButton")
check("right-click opens addon list", opened.list, 1)

Stub.FireScript(mb, "OnMouseDown", nil, "LeftButton")
check("plain left press doesn't drag", mb.dragging, nil)
Stub.FireScript(mb, "OnMouseUp", nil, "LeftButton")

Stub.ctrlDown = true
Stub.FireScript(mb, "OnMouseDown", nil, "LeftButton")
check("ctrl+left press drags", mb.dragging, true)
Stub.FireScript(mb, "OnMouseUp", nil, "LeftButton")
Stub.FireScript(mb, "OnClick", nil, "LeftButton")
Stub.ctrlDown = false
check("click ending a ctrl-drag doesn't open drawer", opened.drawer, 1)
Stub.FireScript(mb, "OnClick", nil, "LeftButton")
check("next plain click opens drawer again", opened.drawer, 2)

print("")
if failures == 0 then
    print("all " .. checks .. " checks passed")
else
    print(failures .. " of " .. checks .. " checks FAILED")
    os.exit(1)
end
