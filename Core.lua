local addonName, ns = ...
ns = ns or {}
local VERSION = "1.3.4"
ns.VERSION = VERSION
local states, ready, mode = {}, false, nil
local elapsedTotal, nextUpdate = 0, 0
local drag
local input = { presses = 0, drags = 0, moves = 0 }
local events, OnUpdate, Opened, UpdateDriver
local cachedStates = {}
local known = {}
for name in string.gmatch([[
CharacterFrame WorldMapFrame FriendsFrame SocialUIFrame GuildFrame CommunitiesFrame
GuildControlUI GuildRegistrarFrame GuildBankFrame BankFrame MerchantFrame TradeFrame
LootFrame MailFrame OpenMailFrame AuctionFrame AuctionHouseFrame ClassTrainerFrame
CraftFrame TradeSkillFrame ProfessionsFrame ProfessionsBookFrame SpellBookFrame
PlayerSpellsFrame QuestLogFrame QuestFrame GossipFrame QuestLogPopupDetailFrame
InspectFrame DressUpFrame PetStableFrame StableFrame CollectionsJournal AchievementFrame
TalentFrame PlayerTalentFrame MacroFrame ItemTextFrame PetitionFrame TabardFrame
TaxiFrame FlightMapFrame HelpFrame SettingsPanel InterfaceOptionsFrame ChatConfigFrame
CalendarFrame PVEFrame PVPUIFrame PVPFrame EncounterJournal ContainerFrameCombinedBags
]], "%S+") do known[name] = true end
for i = 1, 13 do known["ContainerFrame" .. i] = true end
local excluded = { EditModeManagerFrame = true, GameMenuFrame = true,
    CinematicFrame = true, MovieFrame = true, BarberShopFrame = true }

local function Accessible(frame)
    if type(frame) ~= "table" or type(frame.IsForbidden) ~= "function"
        or type(frame.IsObjectType) ~= "function" then return false end
    local ok, forbidden = pcall(frame.IsForbidden, frame)
    return ok and not forbidden and frame:IsObjectType("Frame")
end

-- Edit Mode systems as a set, rebuilt only when the registered list changes.
local systemSet, systemSource, systemCount = {}, nil, -1
local function EditModeSystems()
    local systems = EditModeManagerFrame and EditModeManagerFrame.registeredSystemFrames
    local count = 0
    if type(systems) == "table" then for _ in pairs(systems) do count = count + 1 end end
    if systems ~= systemSource or count ~= systemCount then
        systemSet, systemSource, systemCount = {}, systems, count
        if type(systems) == "table" then
            for _, system in pairs(systems) do systemSet[system] = true end
        end
    end
    return systemSet
end

local function Editable(frame)
    local current, depth = frame, 0
    local systems = EditModeSystems()
    while current and current ~= UIParent do
        -- A parent chain deeper than any real UI means a cycle.
        depth = depth + 1
        if depth > 64 or not Accessible(current) then return false end
        if current == EditModeManagerFrame or current.systemInfo or systems[current] then return false end
        current = current:GetParent()
    end
    return true
end

-- Windows move in the gamepad UI too. A live check (2026-09-26) found moved
-- windows plus gamepad popups leave Blizzard's gamepad state untainted; one
-- earlier SetPreferredGamepadInteractTarget block (build 70009) is still
-- unexplained. So a blocked action in the gamepad UI pauses gamepad moving for
-- that session only and records a full report. /fwm gamepad pauses it for good.
local sessionGamepadPause = false
local function GamepadUI()
    if not InputUtil or type(InputUtil.IsGamepadUIEnabled) ~= "function" then return false end
    local ok, enabled = pcall(InputUtil.IsGamepadUIEnabled)
    return ok and enabled == true
end
local function GamepadPaused()
    if not ForeverWindowsDB.gamepadPaused and not sessionGamepadPause then return false end
    return GamepadUI()
end
-- Read-only: which pieces of Blizzard's gamepad state are tainted, and by whom.
-- Addon taint lands in list entries (Blizzard's own table.insert/remove running
-- under an addon's taint) as often as in plain fields, so both are checked.
-- Returns the tainted values plus one summary line.
local WATCHED_EVENTS = {
    "UIParentPanelManager.ShowUIPanel", "UIParentPanelManager.HideUIPanel",
    "UIParentPanelManager.ForcePanelHide", "ContainerFrame.OpenBag", "ContainerFrame.CloseBag",
    "MenuProxy.OnShow", "MenuProxy.OnClose", "Gamepad.PreferredGamepadInteractTargetChanged",
    "PLAYER_SOFT_INTERACT_CHANGED", "PLAYER_SOFT_ENEMY_CHANGED", "PLAYER_TARGET_CHANGED",
    "PLAYER_EQUIPMENT_CHANGED",
}
local function Describe(value)
    if type(value) == "table" then
        for _, method in ipairs({ "GetDebugName", "GetName" }) do
            local ok, name = pcall(function() return value[method](value) end)
            if ok and type(name) == "string" and name ~= "" then return name end
        end
        return "table"
    end
    return tostring(value)
end
local function GamepadTaintReport()
    local lines, checked, failed, failure = {}, 0, 0, nil
    if type(issecurevariable) ~= "function" then return lines end
    local function check(label, owner, key)
        if type(owner) ~= "table" then return end
        local ok, secure, by = pcall(issecurevariable, owner, key)
        if not ok then failed, failure = failed + 1, failure or secure; return end
        checked = checked + 1
        if not secure then lines[#lines + 1] = label .. ": tainted by " .. tostring(by) end
    end
    local function fields(prefix, owner, keys)
        for _, key in ipairs(keys) do check(prefix .. "." .. key, owner, key) end
    end
    local function entries(label, list)
        if type(list) ~= "table" then return end
        for index = 1, #list do check(label .. "[" .. index .. "]", list, index) end
    end
    local function keyed(label, map)
        if type(map) ~= "table" then return end
        for key in pairs(map) do check(label .. "[" .. Describe(key) .. "]", map, key) end
    end
    local manager = GamepadMode and GamepadMode.FrameControlsManager
    fields("frames", manager, { "isUIFocused", "focusedFrame", "fallThroughCatcherActive", "shownFrames",
        "topSuspendedFrame", "prevFrame", "nextFrame", "isPopupFrame" })
    if type(manager) == "table" then
        entries("frames.shownFrames", manager.shownFrames)
        keyed("frames.isPopupFrame", manager.isPopupFrame)
    end
    local popups = GamepadMode and GamepadMode.PopupHandler
    if type(popups) == "table" then entries("popups.visible", popups.visiblePopups) end
    local nav = SmartNavigation
    fields("nav", nav, { "currentButton", "activeInfo", "bindingActive", "enabled", "isCursorSuspended",
        "rightStickScrolling", "activePanels" })
    if type(nav) == "table" and type(nav.activePanels) == "table" then
        for index = 1, #nav.activePanels do
            local label = "nav.activePanels[" .. index .. "]"
            check(label, nav.activePanels, index)
            local info = nav.activePanels[index]
            if type(info) == "table" then
                fields(label .. " " .. Describe(info.frame), info, { "frame", "buttonGroups", "lastButton", "focusedKey" })
            end
        end
    end
    -- A panel hook installed under taint stays tainted for the whole session.
    if type(nav) == "table" then keyed("nav.hookedFrames", nav.hookedFrames) end
    local bindings = GamepadSharedUtility and GamepadSharedUtility.InputBindingManager
    check("bindings.stack", bindings, "bindingSetStack")
    check("bindings.coreActive", bindings, "currentCoreBindingActive")
    check("bindings.assumeCore", bindings, "assumeCoreBindingsUsable")
    if type(bindings) == "table" then
        entries("bindings.stack", bindings.bindingSetStack)
        keyed("bindings.active", bindings.activeBindings)
    end
    local sticks = _G.inputBindingAxisListener
    if type(sticks) == "table" then
        for _, side in ipairs({ "left", "right" }) do
            fields("sticks." .. side, sticks[side], { "func", "waitForCentering", "isCentered" })
        end
    end
    -- Blizzard's broadcast bookkeeping, written each time one of these fires.
    local executing = EventRegistry and EventRegistry.executingEvents
    if type(executing) == "table" then
        for _, event in ipairs(WATCHED_EVENTS) do check("events." .. event, executing, event) end
    end
    if failed > 0 then
        lines[#lines + 1] = failed .. " values could not be checked (" .. tostring(failure) .. ")"
    end
    lines[#lines + 1] = #lines == 0 and ("all " .. checked .. " checked values are clean")
        or (#lines .. " of " .. checked .. " checked values are tainted")
    return lines
end

-- Automatic snapshots while the gamepad UI is on, so a report exists even when
-- the session is reloaded right away: the first blocked action of each addon
-- per session, and the first Lua error inside Blizzard's gamepad navigation.
local reportedAddons, reportedError = {}, false
local function SaveGamepadReport(report)
    report.time = date and date("%Y-%m-%d %H:%M:%S") or nil
    report.version = VERSION
    report.taint = GamepadTaintReport()
    local reports = type(ForeverWindowsDB.gamepadReports) == "table" and ForeverWindowsDB.gamepadReports or {}
    reports[#reports + 1] = report
    while #reports > 5 do table.remove(reports, 1) end
    ForeverWindowsDB.gamepadReports = reports
end
local function WatchGamepadErrors()
    if not EventRegistry or type(EventRegistry.RegisterCallback) ~= "function" then return end
    EventRegistry:RegisterCallback("BugGrabber.BugGrabbed", function(_, id)
        if reportedError or type(ForeverWindowsDB) ~= "table" or not GamepadUI() then return end
        local grabber = _G.BugGrabber
        local ok, err = pcall(function() return grabber:GetErrorByID(id) end)
        local message = ok and type(err) == "table" and err.message
        if type(message) ~= "string" or not (message:find("SmartNavigation", 1, true)
            or message:find("FrameControlsManager", 1, true) or message:find("InputBindingManager", 1, true)) then return end
        reportedError = true
        SaveGamepadReport({ error = message:sub(1, 300) })
    end, "ForeverWindows.GamepadErrors")
end

local function Available(state)
    local f = state.frame
    -- Cheap visibility first: most tracked windows are closed on any tick.
    return mode and not InCombatLockdown() and not GamepadPaused() and Accessible(f) and f:IsVisible()
        and Editable(f) and not (f == WorldMapFrame and f.IsMaximized and f:IsMaximized())
end

local function Geometry(frame)
    local left, top = frame:GetLeft(), frame:GetTop()
    if not left or not top then return end
    local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return left * ratio, top * ratio, frame:GetWidth() * ratio, frame:GetHeight() * ratio
end

local function Valid(d)
    if type(d) ~= "table" then return end
    for _, key in ipairs({ "x", "y", "scale" }) do
        local v = d[key]
        if type(v) ~= "number" or v ~= v or math.abs(v) > 10000 then return end
    end
    return d
end
local function Saved(state) return Valid(ForeverWindowsDB.windows[state.name]) end

local function Save(state)
    local left, top, width, height = Geometry(state.frame)
    if not left then return end
    -- Updated in place: dragging saves on every cursor movement.
    local d = ForeverWindowsDB.windows[state.name]
    if type(d) ~= "table" then d = {}; ForeverWindowsDB.windows[state.name] = d end
    d.scale, d.x, d.y = state.frame:GetScale(), left / UIParent:GetWidth(), top / UIParent:GetHeight() - 1
    -- Size lets the options window preview a layout while the window is closed.
    d.w, d.h = width, height
    state.driftFails = nil
end

-- Keeps a whole window on screen.
local function Clamp(left, top, width, height)
    left = math.max(0, math.min(left, math.max(0, UIParent:GetWidth() - width)))
    top = math.min(UIParent:GetHeight(), math.max(math.min(height, UIParent:GetHeight()), top))
    return left, top
end

local function MoveTo(state, left, top)
    if not Available(state) then return end
    local frame = state.frame
    local oldLeft, oldTop, width, height = Geometry(frame)
    if not oldLeft then return end
    left, top = Clamp(left, top, width, height)
    if math.abs(oldLeft - left) < 0.25 and math.abs(oldTop - top) < 0.25 then return end
    local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", left / ratio,
        (top - UIParent:GetHeight()) / ratio)
    local actualLeft, actualTop = Geometry(frame)
    state.lastMove = string.format("requested %.1f,%.1f; actual %.1f,%.1f", left, top, actualLeft or -1, actualTop or -1)
end

-- Just before a moved window is put back, it sits where Blizzard placed it.
-- Remember that spot (per window, kept across resets) so the options window
-- can preview what a reset would give. Blizzard's own anchor point is kept:
-- a TOP-anchored panel stays centered when its size changes.
local function Capture(state, d)
    local frame = state.frame
    local left, top, width, height = Geometry(frame)
    if not left then return end
    local uiWidth, uiHeight = UIParent:GetWidth(), UIParent:GetHeight()
    local wantLeft, wantTop = Clamp(d.x * uiWidth, (1 + d.y) * uiHeight, width, height)
    if math.abs(left - wantLeft) <= 0.5 and math.abs(top - wantTop) <= 0.5 then return end
    local scale = frame:GetScale()
    if not scale or scale <= 0 then return end
    -- A scale that is not the saved one was set by Blizzard (scale to fit).
    local native = math.abs(scale - math.max(0.5, math.min(2, d.scale))) > 0.001 and scale or (state.nativeScale or 1)
    local nativeWidth, nativeHeight = width / scale * native, height / scale * native
    local ok, point = pcall(frame.GetPoint, frame, 1)
    point = ok and type(point) == "string" and point or "TOPLEFT"
    if point:find("RIGHT") then left = left + width - nativeWidth
    elseif not point:find("LEFT") then left = left + (width - nativeWidth) / 2 end
    if point:find("BOTTOM") then top = top - height + nativeHeight
    elseif not point:find("TOP") then top = top - (height - nativeHeight) / 2 end
    ForeverWindowsDB.native[state.name] = { x = left / uiWidth, y = top / uiHeight - 1,
        w = nativeWidth, h = nativeHeight, scale = native }
end

local function Restore(state)
    local d = Saved(state)
    if not d or not Available(state) then return end
    Capture(state, d)
    local scale = math.max(0.5, math.min(2, d.scale))
    if math.abs(state.frame:GetScale() - scale) > 0.001 then state.frame:SetScale(scale) end
    MoveTo(state, d.x * UIParent:GetWidth(), (1 + d.y) * UIParent:GetHeight())
end

-- Blizzard's panel manager re-anchors every open panel when a tab changes a
-- panel's width or another panel opens or closes, and announces nothing
-- afterwards. A moved window that no longer sits at its saved layout drifted.
local function Drifted(state)
    local d = Saved(state)
    if not d then return false end
    local frame = state.frame
    if math.abs(frame:GetScale() - math.max(0.5, math.min(2, d.scale))) > 0.001 then return true end
    local left, top, width, height = Geometry(frame)
    if not left then return false end
    local wantLeft, wantTop = Clamp(d.x * UIParent:GetWidth(), (1 + d.y) * UIParent:GetHeight(), width, height)
    return math.abs(left - wantLeft) > 0.5 or math.abs(top - wantTop) > 0.5
end

-- Puts drifted windows back. Called every frame while windows are open, so a
-- native re-anchor made during input is undone before the frame is drawn.
-- A window that will not stay put (another addon anchoring it every frame)
-- is left alone after three tries until it is next opened or dragged.
local function Reapply(skip)
    for _, state in pairs(states) do
        if state.visible and state ~= skip and (state.driftFails or 0) < 3 and Drifted(state) then
            Restore(state)
            if not mode then return end
            if Drifted(state) then state.driftFails = (state.driftFails or 0) + 1
            else state.driftFails = nil end
            if state.grip then state.gripLeft = nil end
        end
    end
end

-- Options window refresh; set by Options.lua.
local function Changed()
    if ns.OnLayoutsChanged then ns.OnLayoutsChanged() end
end

local function Cursor()
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    return x / scale, y / scale
end

local function FinishDrag()
    -- Last valid coordinates are saved during dragging. No Blizzard methods
    -- run on mouse-up, close, combat entry or addon suspension.
    local dragged = drag and drag.lastX
    drag = nil
    if dragged then Changed() end
end

local function MakeGrip(state)
    -- Share the window's focus/raise hierarchy so interacting with its contents
    -- cannot leave the title grip behind as a separate top-level window.
    local grip = CreateFrame("Button", nil, state.frame)
    state.grip = grip
    grip:Hide()
    grip:EnableMouse(true)
    grip:SetMouseClickEnabled(true)
    grip:SetPropagateMouseClicks(false)
    grip:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
    grip:SetToplevel(false)
    grip:SetIgnoreParentScale(true)
    grip:SetScale(UIParent:GetEffectiveScale())
    grip:EnableMouseWheel(true)
    grip:RegisterForDrag("LeftButton")
    local function BeginDrag(_, button)
        if button ~= "LeftButton" or not Available(state) then return end
        if drag and drag.state == state then return end
        local left, top = Geometry(state.frame)
        if not left then return end
        local x, y = Cursor()
        state.restoreAt = nil
        drag = { state = state, x = x, y = y, left = left, top = top }
    end
    grip:SetScript("OnMouseDown", function(self, button)
        input.presses = input.presses + 1
        state.presses = (state.presses or 0) + 1
        BeginDrag(self, button)
    end)
    grip:SetScript("OnDragStart", function(self, button)
        input.drags = input.drags + 1
        state.drags = (state.drags or 0) + 1
        BeginDrag(self, button)
    end)
    grip:SetScript("OnDragStop", FinishDrag)
    grip:SetScript("OnHide", function()
        if drag and drag.state == state then FinishDrag() end
    end)
    grip:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then FinishDrag() end
    end)
    grip:SetScript("OnMouseWheel", function(_, delta)
        if drag or delta == 0 or not IsControlKeyDown() or not Available(state) then return end
        local left, top = Geometry(state.frame)
        if not left then return end
        state.restoreAt = nil
        local old = state.frame:GetScale()
        local scale = math.max(0.5, math.min(2, math.floor((old + (delta > 0 and 0.05 or -0.05)) * 100 + 0.5) / 100))
        if scale ~= old then state.frame:SetScale(scale) end
        MoveTo(state, left, top)
        Save(state)
        Changed()
    end)
end

local function Discover()
    local candidates = {}
    if mode == "test" then candidates.CharacterFrame = true
    else
        for name in pairs(known) do candidates[name] = true end
        for name, info in pairs(UIPanelWindows or {}) do
            if type(info) == "table" and info.area ~= "full" then candidates[name] = true end
        end
    end
    for name in pairs(candidates) do
        local f = _G[name]
        if not states[name] and not excluded[name] and Accessible(f) and Editable(f)
            and (known[name] or (issecurevariable and issecurevariable(_G, name))) then
            local parent, nested, seen = f:GetParent(), false, {}
            while parent and parent ~= UIParent do
                if seen[parent] or not Accessible(parent) then nested = true; break end
                seen[parent] = true
                if candidates[parent:GetName()] then nested = true; break end
                parent = parent:GetParent()
            end
            if not nested then
                local state = cachedStates[name]
                if not state or state.frame ~= f then
                    -- Scale before this addon ever changes it; reset returns to it.
                    state = { name = name, frame = f, nativeScale = f:GetScale() }
                    cachedStates[name] = state
                end
                states[name] = state
                if not state.showHooked then
                    state.showHooked = true
                    f:HookScript("OnShow", function()
                        if ready and mode and states[name] == state then Opened(state) end
                    end)
                    f:HookScript("OnHide", function()
                        if states[name] ~= state then return end
                        state.visible, state.restoreAt = false, nil
                        if state.grip then state.grip:Hide() end
                        if drag and drag.state == state then FinishDrag() end
                        UpdateDriver()
                        Changed()
                    end)
                end
            end
        end
    end
end

local function HideGrip(state)
    if state.grip then state.grip:Hide() end
end

local function InputLevel(frame, title, grip)
    local level = math.max(frame:GetFrameLevel(), (title or frame):GetFrameLevel()) + 1
    -- Bags include an unnamed title-wide click router. It is a sibling of the
    -- title container, so the title's level alone is not sufficient.
    if frame.GetChildren then
        for _, child in ipairs({frame:GetChildren()}) do
            if child ~= grip and Accessible(child) and child:IsVisible() then
                level = math.max(level, child:GetFrameLevel() + 1)
            end
        end
    end
    -- Tab content can be raised independently of the title. Inspect only the
    -- current mouse-focus chain, never enumerate the whole UI or modify it.
    if GetMouseFoci then
        for _, focus in ipairs(GetMouseFoci()) do
            local current, seen = focus, {}
            if focus ~= grip and Accessible(focus) then
                while current and current ~= UIParent and Accessible(current) and not seen[current] do
                    if current == frame then
                        level = math.max(level, focus:GetFrameLevel() + 1)
                        break
                    end
                    seen[current] = true
                    current = current:GetParent()
                end
            end
        end
    end
    -- Retain the input level once the grip becomes the mouse focus itself.
    return math.max(level, grip:GetFrameLevel())
end

local function UpdateGrip(state)
    local f = state.frame
    local title = f.TitleContainer or (f.BorderFrame and f.BorderFrame.TitleContainer)
        or (f.Border and f.Border.TitleContainer)
    if title and not Accessible(title) then HideGrip(state); return end
    -- The classic merchant supplies its own MerchantNameText rather than
    -- relying on the inherited title container's geometry.
    local merchant = state.name == "MerchantFrame"
    local anchor = merchant and f or (title or f)
    local left, top, width, height = Geometry(anchor)
    if not left then HideGrip(state); return end
    local ratio = anchor:GetEffectiveScale() / UIParent:GetEffectiveScale()
    if merchant then
        local close = f.CloseButton or MerchantFrameCloseButton
        local rightInset = Accessible(close) and close:IsVisible() and 28 or 0
        left, width, height = left + 60 * ratio, width - (60 + rightInset) * ratio, 24 * ratio
    elseif title then width = width - (state.name == "WorldMapFrame" and 55 or 8) * ratio
    else left, top, width, height = left + 60 * ratio, top - 3 * ratio, width - 125 * ratio, 24 * ratio end
    if width <= 0 or height <= 0 then HideGrip(state); return end
    if not state.grip then MakeGrip(state) end
    local g = state.grip
    local uiScale = UIParent:GetEffectiveScale()
    if math.abs(g:GetScale() - uiScale) > 0.001 then g:SetScale(uiScale) end
    -- Since build 70338 a frame's strata can be a secret value.
    local strata = (title or f):GetFrameStrata()
    if (issecretvalue and issecretvalue(strata)) or type(strata) ~= "string" then strata = "HIGH" end
    if g:GetFrameStrata() ~= strata then g:SetFrameStrata(strata) end
    local level = InputLevel(f, title, g)
    if g:GetFrameLevel() ~= level then g:SetFrameLevel(level) end
    if not g:IsMouseClickEnabled() then g:SetMouseClickEnabled(true) end
    if state.gripLeft ~= left or state.gripTop ~= top then
        g:ClearAllPoints()
        g:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
        state.gripLeft, state.gripTop = left, top
    end
    if g:GetWidth() ~= width or g:GetHeight() ~= height then g:SetSize(width, height) end
    if not g:IsVisible() then g:Show() end
end

UpdateDriver = function()
    if not events then return end
    local needed = false
    if ready and mode and not InCombatLockdown() and not GamepadPaused() then
        for _, state in pairs(states) do
            if Accessible(state.frame) and state.frame:IsVisible() then needed = true; break end
        end
    end
    events:SetScript("OnUpdate", needed and OnUpdate or nil)
end

Opened = function(state)
    -- A maximized map still needs a slow visibility/geometry audit so its grip
    -- returns when native code minimizes it without another OnShow.
    UpdateDriver()
    if not Available(state) then return end
    state.restoreAt, state.driftFails = nil, nil
    Restore(state)
    if not mode then return end
    state.visible = true
    UpdateGrip(state)
    Changed()
end

local function Suspend()
    mode = nil
    if events then events:SetScript("OnUpdate", nil) end
    FinishDrag()
    for _, state in pairs(states) do
        if state.grip then state.grip:Hide() end
        state.visible, state.restoreAt = nil, nil
    end
    states = {}
end

-- Entering the gamepad UI hides grips; leaving it lets the next tick restore
-- any open window. A window already moved stays put until it is reopened.
local function InputModeChanged()
    if not ready or not mode then return end
    if GamepadPaused() then
        FinishDrag()
        for _, state in pairs(states) do
            HideGrip(state)
            state.visible, state.restoreAt = false, nil
        end
    elseif not InCombatLockdown() then
        Discover()
        nextUpdate = 0
    end
    UpdateDriver()
end

-- Blizzard broadcasts this synchronously after its panel layout and Show have
-- finished, before the next render. Restore here rather than on a later tick.
-- Opening or closing a panel re-anchors the other open panels too, so every
-- moved window is put back here, not only the one that opened.
local panelOwner = {}
if EventRegistry then
    EventRegistry:RegisterCallback("UIParentPanelManager.ShowUIPanel", function(_, frame)
        if not ready or not mode or InCombatLockdown() then return end
        Discover()
        local opened
        for _, state in pairs(states) do
            if state.frame == frame and Available(state) then
                Opened(state)
                opened = state
                break
            end
        end
        if mode then Reapply(opened) end
    end, panelOwner)
    EventRegistry:RegisterCallback("UIParentPanelManager.HideUIPanel", function()
        if not ready or not mode or InCombatLockdown() then return end
        Reapply()
    end, panelOwner)
end

events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("UI_SCALE_CHANGED")
events:RegisterEvent("DISPLAY_SIZE_CHANGED")
events:RegisterEvent("ADDON_ACTION_BLOCKED")
events:RegisterEvent("ADDON_ACTION_FORBIDDEN")
events:RegisterEvent("INPUT_DEVICE_INTERFACE_TRANSITION")
events:SetScript("OnEvent", function(_, event, name, action)
    if event == "INPUT_DEVICE_INTERFACE_TRANSITION" then
        -- Read the new style after the client's own transition handlers ran.
        if C_Timer and C_Timer.After then C_Timer.After(0, InputModeChanged) else InputModeChanged() end
        return
    end
    if event == "ADDON_LOADED" and name == addonName then
        ForeverWindowsDB = type(ForeverWindowsDB) == "table" and ForeverWindowsDB or {}
        ForeverWindowsDB.windows = type(ForeverWindowsDB.windows) == "table" and ForeverWindowsDB.windows or {}
        ForeverWindowsDB.native = type(ForeverWindowsDB.native) == "table" and ForeverWindowsDB.native or {}
        ForeverWindowsDB.gamepad = nil -- 1.2.6 opt-in flag; moving in the gamepad UI is now the default.
        ready = true
        WatchGamepadErrors()
        if ForeverWindowsDB.enabled ~= false then
            mode = "all"
            Discover()
            UpdateDriver()
        end
    elseif ready and mode and event == "BAG_UPDATE_DELAYED" then
        -- Looting fires this constantly. Only a newly created bag frame needs discovery.
        if InCombatLockdown() then return end
        for name in pairs(known) do
            if not states[name] and name:find("^Container") and _G[name] then
                Discover()
                nextUpdate = 0
                UpdateDriver()
                return
            end
        end
    elseif ready and mode and (event == "ADDON_LOADED" or event == "PLAYER_LOGIN"
        or event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED"
        or event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED") then
        if not InCombatLockdown() then Discover() end
        nextUpdate = 0
        UpdateDriver()
    elseif event == "PLAYER_REGEN_DISABLED" then
        FinishDrag()
        for _, state in pairs(states) do
            HideGrip(state)
            state.visible = false
        end
        UpdateDriver()
    elseif ready and name ~= addonName and (event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN") then
        -- Another addon's block in the gamepad UI: one snapshot per addon and session.
        local blamed = tostring(name)
        if GamepadUI() and not reportedAddons[blamed] then
            reportedAddons[blamed] = true
            SaveGamepadReport({ addon = blamed, event = event, action = tostring(action),
                stack = debugstack and debugstack(2, 12, 12) or nil })
        end
    elseif ready and name == addonName and (event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN") then
        -- Keep both ends of the stack: the origin is what identifies the cause.
        local gamepad = GamepadUI()
        ForeverWindowsDB.lastBlockedAction = { action = tostring(action), event = event,
            stack = debugstack and debugstack(2, 30, 30) or "unavailable", version = VERSION,
            gamepad = gamepad, taint = GamepadTaintReport(), time = date and date("%Y-%m-%d %H:%M:%S") }
        if gamepad and not sessionGamepadPause then
            -- Keyboard/mouse mode keeps working; gamepad moving resumes next session.
            sessionGamepadPause = true
            InputModeChanged()
            print("Forever Windows paused window moving in the gamepad UI for this session after a blocked action ("
                .. tostring(action) .. "). Please send /fwm debug.")
        elseif not gamepad then
            Suspend()
            ForeverWindowsDB.enabled = false
            print("Forever Windows suspended after blocked action: " .. tostring(action) .. ". /fwm debug for details.")
        end
    end
end)
OnUpdate = function(_, elapsed)
    if not ready or not mode then return end
    elapsedTotal = elapsedTotal + elapsed
    Reapply(drag and drag.state)
    if not mode then return end
    if drag then
        local activeDrag = drag
        if not Available(activeDrag.state) then FinishDrag()
        else
            local x, y = Cursor()
            if x ~= activeDrag.lastX or y ~= activeDrag.lastY then
                activeDrag.lastX, activeDrag.lastY = x, y
                input.moves = input.moves + 1
                MoveTo(activeDrag.state, activeDrag.left + x - activeDrag.x, activeDrag.top + y - activeDrag.y)
                if not mode then return end
                Save(activeDrag.state)
            end
        end
    end
    if not drag and elapsedTotal < nextUpdate then return end
    nextUpdate = elapsedTotal + 0.1
    for _, state in pairs(states) do
        local available = Available(state)
        if available then
            if not state.visible then state.restoreAt = elapsedTotal end
            if state.restoreAt and elapsedTotal >= state.restoreAt and not drag then
                state.restoreAt = nil
                Restore(state)
                if not mode then return end
            end
            UpdateGrip(state)
        else
            state.restoreAt = nil
            if state.grip then state.grip:Hide() end
        end
        state.visible = available
    end
    UpdateDriver()
end

-- Options window API ------------------------------------------------------

ns.GamepadUI = GamepadUI
function ns.IsEnabled() return mode ~= nil end
function ns.Layout(name)
    local d = Saved({ name = name })
    if d then return math.max(0.5, math.min(2, d.scale)) end
end
function ns.Layouts()
    local list = {}
    for name in pairs(ForeverWindowsDB.windows) do
        if type(name) == "string" and Saved({ name = name }) then list[#list + 1] = name end
    end
    return list
end
-- A window this addon tracks, when its frame exists and is safe to read.
local function Frame(name)
    local state = states[name] or cachedStates[name]
    local f = state and state.frame
    if Accessible(f) then return f, state end
end
ns.Frame = Frame
function ns.IsOpen(name)
    local f = Frame(name)
    return f and f:IsVisible() and true or false
end
-- Where a window is now, in UIParent units: left, top, width, height.
function ns.LiveRect(name)
    local f = Frame(name)
    if not f or not f:IsVisible() then return end
    return Geometry(f)
end
-- Where a saved layout puts a window, even while it is closed.
-- Pass a layout table (an undone reset) instead of the saved one if needed.
function ns.SavedRect(name, layout)
    local d = Valid(layout or ForeverWindowsDB.windows[name])
    if not d then return end
    local scale = math.max(0.5, math.min(2, d.scale))
    local width, height = d.w, d.h
    local f = Frame(name)
    if f and (f:GetWidth() or 0) > 0 then
        local ratio = f:GetEffectiveScale() / f:GetScale() * scale / UIParent:GetEffectiveScale()
        width, height = f:GetWidth() * ratio, f:GetHeight() * ratio
    end
    if type(width) ~= "number" or type(height) ~= "number" or width <= 0 or height <= 0 then
        width, height = 384 * scale, 512 * scale
    end
    local left, top = Clamp(d.x * UIParent:GetWidth(), (1 + d.y) * UIParent:GetHeight(), width, height)
    return left, top, width, height
end
-- Where Blizzard puts a window, as last seen; an open window without a
-- layout is already there. Returns left, top, width, height, scale.
function ns.NativeRect(name)
    local f = Frame(name)
    if f and f:IsVisible() and not Saved({ name = name }) then
        local left, top, width, height = Geometry(f)
        if left then return left, top, width, height, f:GetScale() end
    end
    local n = Valid(ForeverWindowsDB.native[name])
    if not n or type(n.w) ~= "number" or type(n.h) ~= "number" or n.w <= 0 or n.h <= 0 then return end
    local left, top = Clamp(n.x * UIParent:GetWidth(), (1 + n.y) * UIParent:GetHeight(), n.w, n.h)
    return left, top, n.w, n.h, n.scale
end
-- Forget a layout. An open window goes to Blizzard's last seen spot at once
-- when it is known; otherwise it opens there next time. Returns true when live.
-- Never call Blizzard's panel code (UpdateUIPanelPositions, HideUIPanel...)
-- from here: its gamepad focus manager listens to those panel broadcasts and
-- would store addon-tainted focus state, which later blocks protected
-- gamepad actions (seen in 1.3.1: SetPreferredGamepadInteractTarget).
function ns.Reset(name)
    local native = Valid(ForeverWindowsDB.native[name])
    ForeverWindowsDB.windows[name] = nil
    local f, state = Frame(name)
    if drag and drag.state == state then FinishDrag() end
    if not f or not f:IsShown() or InCombatLockdown() or not Editable(f) then return false end
    local scale = native and native.scale or state.nativeScale
    if type(scale) ~= "number" or scale <= 0 then return false end
    if math.abs(f:GetScale() - scale) > 0.001 then f:SetScale(scale) end
    if state.grip then state.gripLeft = nil end
    if not native then return false end
    local _, _, width, height = Geometry(f)
    if not width then return false end
    local left, top = Clamp(native.x * UIParent:GetWidth(), (1 + native.y) * UIParent:GetHeight(), width, height)
    local ratio = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", left / ratio, (top - UIParent:GetHeight()) / ratio)
    return true
end
-- Put back a layout removed with Reset.
function ns.Undo(name, d)
    if type(d) ~= "table" then return end
    ForeverWindowsDB.windows[name] = d
    local _, state = Frame(name)
    if state and states[name] == state and Available(state) then
        state.driftFails = nil
        Restore(state)
        state.gripLeft = nil
    end
end

local function SetEnabled(enabled)
    Suspend()
    ForeverWindowsDB.enabled = enabled
    if enabled then
        mode = "all"
        Discover()
        UpdateDriver()
        nextUpdate = 0
    end
    Changed()
end
ns.SetEnabled = SetEnabled

SLASH_FOREVERWINDOWS1, SLASH_FOREVERWINDOWS2 = "/fwm", "/foreverwindows"
SlashCmdList.FOREVERWINDOWS = function(message)
    if not ready then return end
    local command = string.lower((message or ""):match("^%s*(.-)%s*$"))
    if command == "" or command == "options" or command == "config" then
        if ns.ToggleOptions then ns.ToggleOptions()
        else print("Forever Windows " .. VERSION .. ": options window unavailable. /fwm help lists commands.") end
    elseif command == "test" or command == "enable" then
        Suspend()
        mode = command == "test" and "test" or "all"
        -- Test mode is session-only; it must not turn the addon off for future logins.
        if command == "enable" then ForeverWindowsDB.enabled = true end
        Discover()
        UpdateDriver()
        nextUpdate = 0
        print("Forever Windows " .. VERSION .. ": " .. (mode == "test" and "Character-only test for this session" or "all supported windows enabled") .. ". /fwm off stops it.")
        Changed()
    elseif command == "off" then
        Suspend()
        ForeverWindowsDB.enabled = false
        print("Forever Windows inactive. Saved layouts retained.")
        Changed()
    elseif command == "gamepad" then
        ForeverWindowsDB.gamepadPaused = not ForeverWindowsDB.gamepadPaused or nil
        sessionGamepadPause = false
        InputModeChanged()
        print("Forever Windows: gamepad UI " .. (ForeverWindowsDB.gamepadPaused
            and "window moving paused. Windows open at native positions there; /fwm gamepad resumes."
            or "windows move and scale as in keyboard mode (default)."))
    elseif command == "taint" then
        local lines = GamepadTaintReport()
        if #lines == 0 then print("Forever Windows: taint check unavailable on this client."); return end
        -- Saved too, so the result survives the /reload that fixes the session.
        ForeverWindowsDB.lastTaintCheck = { time = date and date("%Y-%m-%d %H:%M:%S") or nil,
            gamepad = GamepadUI(), version = VERSION, taint = lines }
        for _, line in ipairs(lines) do print("Forever Windows gamepad state - " .. line) end
    elseif command == "vendor" then
        if not mode then print("Enable windows first with /fwm enable."); return end
        Discover()
        local state = states.MerchantFrame
        if not state or not Available(state) then print("Open a vendor first."); return end
        UpdateGrip(state)
        local g = state.grip
        if not g or not g:IsVisible() then print("Vendor grip has no usable title geometry."); return end
        if not state.marker then
            state.marker = g:CreateTexture(nil, "OVERLAY")
            state.marker:SetAllPoints(g)
            state.marker:SetColorTexture(0, 1, 0, 0.4)
        end
        state.marked = not state.marked
        state.marker:SetShown(state.marked)
        print("Vendor drag area " .. (state.marked and "highlighted green. Try dragging it, then /fwm debug." or "hidden."))
    elseif command == "debug" then
        print("Forever Windows " .. VERSION .. ": " .. (mode or "inactive")
            .. (GamepadPaused() and (sessionGamepadPause and " (gamepad UI paused this session after a blocked action)"
                or " (gamepad UI paused; /fwm gamepad resumes)") or ""))
        print("Title input: presses=" .. input.presses .. ", drag starts=" .. input.drags .. ", movement ticks=" .. input.moves .. ", dragging=" .. tostring(drag ~= nil))
        for name, state in pairs(states) do
            local g = state.grip
            if g and g:IsVisible() then
                print(name .. " grip: clicks=" .. tostring(g:IsMouseClickEnabled()) .. ", strata=" .. g:GetFrameStrata() .. ", level=" .. g:GetFrameLevel())
                print("  presses=" .. (state.presses or 0) .. ", drags=" .. (state.drags or 0) .. "; " .. (state.lastMove or "no move requested"))
            end
        end
        local d = ForeverWindowsDB.lastBlockedAction
        if d then
            print((d.version or "older build") .. ": " .. d.event .. " " .. d.action .. (d.time and (" at " .. d.time) or "")
                .. (d.gamepad and " (gamepad UI)" or ""))
            for _, line in ipairs(type(d.taint) == "table" and d.taint or {}) do print("  " .. line) end
            print(d.stack)
        else print("No blocked-action report saved.") end
        for _, r in ipairs(type(ForeverWindowsDB.gamepadReports) == "table" and ForeverWindowsDB.gamepadReports or {}) do
            print("Gamepad report" .. (r.time and (" at " .. r.time) or "") .. ": "
                .. (r.addon and (r.addon .. " " .. tostring(r.event) .. " " .. tostring(r.action)) or tostring(r.error)))
            for _, line in ipairs(type(r.taint) == "table" and r.taint or {}) do print("  " .. line) end
        end
    elseif command == "reset" then
        Suspend()
        ForeverWindowsDB.windows = {}
        ReloadUI()
    else
        print("Forever Windows " .. VERSION .. ": " .. (mode or "inactive") .. ". /fwm: options window; /fwm enable: all windows; /fwm off: stop; /fwm test: Character only; /fwm gamepad: pause/resume moving in gamepad UI; /fwm taint: gamepad taint check; /fwm debug: report.")
    end
end
