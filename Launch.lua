local _, ns = ...

-- Ways to the options window: a key (Bindings.xml) set from our own window,
-- a minimap button, and a page in Blizzard's Settings (Esc > Options > AddOns).

local ACTION = "FOREVERWINDOWS_TOGGLE"
local TITLE = "Forever Windows"
local GOLD = {1, 0.82, 0}

BINDING_CATEGORY_FOREVERWINDOWS = TITLE
BINDING_HEADER_FOREVERWINDOWS = TITLE
BINDING_NAME_FOREVERWINDOWS_TOGGLE = "Toggle window"
function ForeverWindows_ToggleOptions() if ns.ToggleOptions then ns.ToggleOptions() end end

local function Say(text) print("Forever Windows: " .. text) end

-- Keys ----------------------------------------------------------------------

local K = {}
ns.Keys = K
K.ACTION = ACTION

function K.Bound(action)
    local key = GetBindingKey and GetBindingKey(action or ACTION)
    if not key then return nil end
    return GetBindingText and GetBindingText(key) or key
end

-- key nil clears. Out of combat only; the client refuses bindings there.
function K.Bind(key, action)
    action = action or ACTION
    if InCombatLockdown() or not SetBinding then Say("keys can't be changed in combat."); return false end
    local before = key and GetBindingAction and GetBindingAction(key)
    for _, old in ipairs({ GetBindingKey(action) }) do SetBinding(old) end
    if key then
        SetBinding(key, action)
        if before and before ~= "" and before ~= action then
            Say((GetBindingText and GetBindingText(key) or key) .. " no longer does \""
                .. (_G["BINDING_NAME_" .. before] or before) .. "\".")
        end
    end
    if SaveBindings then SaveBindings(GetCurrentBindingSet and GetCurrentBindingSet() or 1) end
    return true
end

local MODIFIERS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
    LALT = true, RALT = true, LMETA = true, RMETA = true }
-- Enter and Backspace stay the chat's; left and right click stay clicks.
local NEVER = { ENTER = true, BACKSPACE = true, BUTTON1 = true, BUTTON2 = true }
local BUTTONS = { LeftButton = "BUTTON1", RightButton = "BUTTON2", MiddleButton = "BUTTON3" }

function K.Combo(key)
    local mods = ""
    if IsAltKeyDown and IsAltKeyDown() then mods = mods .. "ALT-" end
    if IsControlKeyDown and IsControlKeyDown() then mods = mods .. "CTRL-" end
    if IsShiftKeyDown and IsShiftKeyDown() then mods = mods .. "SHIFT-" end
    if IsMetaKeyDown and IsMetaKeyDown() then mods = mods .. "META-" end
    return mods .. key
end

local setters, listening = {}, nil
local function RefreshSetters() for _, s in ipairs(setters) do s:Refresh() end end
K.Refresh = RefreshSetters

-- One keycap button: click listens for the next key (Esc cancels, modifiers
-- combine), right-click clears. skinned: Forever's Legacy button art.
function K.Setter(parent, width, skinned)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 96, 22)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetMotionScriptsWhileDisabled(true)
    if skinned and ns.Skin then ns.Skin.Button(b) end
    local catcher = CreateFrame("Frame", nil, b)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:Hide()
    b.catcher = catcher

    function b:Refresh()
        local text = self.listening and "Press a key" or K.Bound() or "Not set"
        self:SetText(text)
        local fs = self:GetFontString()
        if fs then
            if self.listening or K.Bound() then fs:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
            else fs:SetTextColor(0.5, 0.5, 0.5) end
        end
    end
    function b:Stop()
        if not self.listening then return end
        self.listening = false
        if listening == self then listening = nil end
        catcher:EnableKeyboard(false); catcher:EnableMouse(false)
        catcher:SetScript("OnKeyDown", nil); catcher:SetScript("OnMouseDown", nil)
        catcher:Hide()
        self:Refresh()
    end
    local function Take(key)
        if MODIFIERS[key] then return end
        b:Stop()
        if key == "ESCAPE" or NEVER[key] then return end
        K.Bind(K.Combo(key))
        RefreshSetters()
    end
    function b:Listen()
        if InCombatLockdown() then Say("keys can't be changed in combat."); return end
        if listening and listening ~= self then listening:Stop() end
        listening, self.listening = self, true
        catcher:Show()
        catcher:EnableKeyboard(true)
        if catcher.SetPropagateKeyboardInput then catcher:SetPropagateKeyboardInput(false) end
        catcher:EnableMouse(true)
        catcher:SetScript("OnKeyDown", function(_, key) Take(key) end)
        catcher:SetScript("OnMouseDown", function(_, button)
            local key = BUTTONS[button] or tostring(button):upper()
            if NEVER[key] then b:Stop() else Take(key) end
        end)
        self:Refresh()
    end
    b:SetScript("OnClick", function(self, button)
        if self.listening then self:Stop(); return end
        if button == "RightButton" then
            if K.Bind(nil) then RefreshSetters() end
        else
            self:Listen()
        end
    end)
    b:HookScript("OnHide", function(self) self:Stop() end)
    b:HookScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(BINDING_NAME_FOREVERWINDOWS_TOGGLE, 1, 1, 1)
        GameTooltip:AddLine(InCombatLockdown() and "Not in combat" or "Click: set  ·  Right-click: clear", 0.8, 0.77, 0.7)
        GameTooltip:Show()
    end)
    b:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    setters[#setters + 1] = b
    b:Refresh()
    return b
end

-- Minimap button ------------------------------------------------------------

local M = {}
ns.Minimap = M
local button
local checks = {}

local function DB()
    local d = type(ForeverWindowsDB.minimap) == "table" and ForeverWindowsDB.minimap or {}
    ForeverWindowsDB.minimap = d
    return d
end

local function Place()
    if not button or not Minimap then return end
    local angle = math.rad(tonumber(DB().angle) or 200)
    local radius = (Minimap:GetWidth() or 140) / 2 + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end
M.Place = Place

local function Drag()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    DB().angle = math.floor(math.deg(math.atan2(cy / scale - my, cx / scale - mx)) + 0.5) % 360
    Place()
end

function M.Shown() return type(ForeverWindowsDB) ~= "table" or not (type(ForeverWindowsDB.minimap) == "table" and ForeverWindowsDB.minimap.hide) end

function M.Create()
    if button or not Minimap then return button end
    button = CreateFrame("Button", "ForeverWindowsMinimapButton", Minimap)
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel((Minimap:GetFrameLevel() or 0) + 8)
    local back = button:CreateTexture(nil, "BACKGROUND")
    back:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    back:SetSize(20, 20); back:SetPoint("CENTER")
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\Spell_Arcane_Blink")
    icon:SetSize(20, 20); icon:SetPoint("CENTER")
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    if button.CreateMaskTexture then
        local mask = button:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(icon)
        icon:AddMaskTexture(mask)
    end
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(54, 54); border:SetPoint("TOPLEFT")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnClick", function() ns.ToggleOptions() end)
    button:SetScript("OnDragStart", function(self)
        if GameTooltip then GameTooltip:Hide() end
        self:SetScript("OnUpdate", Drag)
    end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil); Place() end)
    button:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(TITLE, 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    if Minimap.HookScript then Minimap:HookScript("OnSizeChanged", Place) end
    Place()
    button:SetShown(M.Shown())
    return button
end

-- A "Minimap icon" checkbox bound to the saved toggle.
function M.Check(parent)
    local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    c:SetSize(26, 26)
    local label = c.Text or c.text
    if label then label:SetFontObject("GameFontHighlight"); label:SetText("Minimap icon") end
    c:SetScript("OnClick", function(self) M.SetShown(self:GetChecked() == true) end)
    c:SetChecked(M.Shown())
    checks[#checks + 1] = c
    return c
end

function M.SetShown(shown)
    DB().hide = not shown or nil
    if shown then M.Create() end
    if button then button:SetShown(shown) end
    for _, c in ipairs(checks) do c:SetChecked(shown) end
end

-- Blizzard Settings page ---------------------------------------------------

local function SettingsPage()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
    local panel = CreateFrame("Frame")
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(TITLE)
    -- Open hands its hardware click to Settings' own Close button (addon
    -- calls into Blizzard's panel code taint the gamepad focus manager, see
    -- Options.lua), then shows our window.
    local open = CreateFrame("Button", nil, panel, "InsecureActionButtonTemplate")
    open:SetSize(120, 24)
    open:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    open:RegisterForClicks("LeftButtonUp")
    open:SetAttribute("useOnKeyDown", false)
    local label = open:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER")
    label:SetText("Open")
    open.label = label
    if ns.Skin then ns.Skin.Button(open) end
    local function Arm()
        if InCombatLockdown() then return end
        local close = ns.CloseButtonOf and SettingsPanel and ns.CloseButtonOf(SettingsPanel)
        open:SetAttribute("type", close and "click" or nil)
        open:SetAttribute("clickbutton", close)
    end
    open:SetScript("PreClick", Arm)
    open:SetScript("PostClick", function() if ns.ShowOptions then ns.ShowOptions() end end)
    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    hint:SetPoint("LEFT", open, "RIGHT", 12, 0)
    hint:SetText("/fwm")
    local check = M.Check(panel)
    check:SetPoint("TOPLEFT", open, "BOTTOMLEFT", -4, -14)
    local keyLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    keyLabel:SetPoint("TOPLEFT", check, "BOTTOMLEFT", 4, -14)
    keyLabel:SetText("Window key")
    local key = K.Setter(panel, 120, true)
    key:SetPoint("LEFT", keyLabel, "LEFT", 110, 0)
    panel:SetScript("OnShow", function() Arm(); RefreshSetters(); check:SetChecked(M.Shown()) end)
    local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, panel, TITLE)
    if ok and category then pcall(Settings.RegisterAddOnCategory, category) end
    M.panel = panel
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("UPDATE_BINDINGS")
loader:SetScript("OnEvent", function(_, event)
    if event == "UPDATE_BINDINGS" then RefreshSetters(); return end
    if type(ForeverWindowsDB) ~= "table" then return end
    if M.Shown() then M.Create() end
    SettingsPage()
end)
