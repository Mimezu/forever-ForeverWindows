-- Run from the client root with Lua 5.1. Loads Core, Skin and Options with a
-- permissive UI mock and drives the options window: list, preview, open,
-- reset, undo, reset all, enable toggle.
local all = {}
local O = {}
O.__index = function(t, k)
    if O[k] then return O[k] end
    -- Any other widget method (capitalized) is a no-op; fields stay nil.
    local fields = { Left = true, Middle = true, Right = true, Text = true, BorderFrame = true, CloseButton = true, ClosePanelButton = true }
    if type(k) == "string" and k:find("^%u") and not fields[k] then return function() end end
end
local function New(kind, name, parent)
    local o = setmetatable({ kind = kind, name = name, parent = parent, scripts = {}, children = {},
        shown = true, w = 0, h = 0, scale = 1, left = 100, top = 800, enabled = true }, O)
    all[#all + 1] = o
    if parent then parent.children[#parent.children + 1] = o end
    if name then _G[name] = o end
    return o
end
function CreateFrame(kind, name, parent) return New(kind, name, parent) end
function O:CreateTexture() return New("Texture", nil, self) end
function O:CreateFontString() local f = New("FontString", nil, self); f.text = ""; return f end
local RealNew = New
New = function(kind, name, parent)
    local o = RealNew(kind, name, parent)
    if kind == "CheckButton" then o.Text = RealNew("FontString", nil, o) end
    return o
end
function O:CreateAnimationGroup() return New("AnimationGroup", nil, self) end
function O:CreateAnimation() return New("Animation", nil, self) end
function O:SetScript(k, v) self.scripts[k] = v end
function O:HookScript(k, v) local old = self.scripts[k]; self.scripts[k] = function(...) if old then old(...) end v(...) end end
function O:Fire(k, ...) if self.scripts[k] then return self.scripts[k](self, ...) end end
function O:Show() local was = self.shown; self.shown = true; if not was then self:Fire("OnShow") end end
function O:Hide() local was = self.shown; self.shown = false; if was then self:Fire("OnHide") end end
function O:SetShown(v) if v then self:Show() else self:Hide() end end
function O:IsShown() return self.shown end
function O:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function O:SetSize(w, h) self.w, self.h = w, h end
function O:GetSize() return self.w, self.h end
function O:SetHeight(h) self.h = h end
function O:GetHeight() return self.h end
function O:SetWidth(w) self.w = w end
function O:GetWidth() return self.w end
function O:SetText(t) self.text = t end
function O:GetText() return self.text end
function O:GetFontString() self.fs = self.fs or New("FontString", nil, self); return self.fs end
function O:SetEnabled(v) self.enabled = v and true or false end
function O:Enable() self.enabled = true end
function O:Disable() self.enabled = false end
function O:IsEnabled() return self.enabled end
function O:SetChecked(v) self.checked = v end
function O:GetChecked() return self.checked end
function O:IsMouseOver() return self.mouse end
function O:GetParent() return self.parent end
function O:GetScale() return self.scale end
function O:SetScale(v) self.scale = v end
function O:GetEffectiveScale() return self.scale * (self.parent and self.parent:GetEffectiveScale() or 1) end
function O:GetLeft() return self.left end
function O:GetTop() return self.top end
function O:IsForbidden() return false end
function O:IsObjectType(t) return t == "Frame" or t == self.kind end
function O:SetAttribute(k, v) self.attributes = self.attributes or {}; self.attributes[k] = v end
function O:GetAttribute(k) return self.attributes and self.attributes[k] end
function O:GetFrameLevel() return 1 end
function O:GetFrameStrata() return "MEDIUM" end
function O:IsMouseClickEnabled() return true end
function O:SetPoint(point, rel, relPoint, x, y)
    if point == "TOPLEFT" and rel == UIParent and relPoint == "TOPLEFT" then
        self.left = x; self.top = y + UIParent.h * UIParent:GetEffectiveScale() / self:GetEffectiveScale()
    elseif point == "TOPLEFT" and rel == UIParent and relPoint == "BOTTOMLEFT" then
        self.left, self.top = x, y
    end
end
function O:GetChildren() return unpack(self.children) end
C_Texture = { GetAtlasInfo = function() return { width = 64, height = 64, leftTexCoord = 0, rightTexCoord = 1,
    topTexCoord = 0, bottomTexCoord = 1, file = 1 } end }
NineSliceUtil = { ApplyLayoutByName = function() end }
UISpecialFrames = {}
local combat = false
function InCombatLockdown() return combat end
function IsControlKeyDown() return false end
function GetCursorPosition() return 0, 0 end
function issecurevariable() return true end
function GetMouseFoci() return {} end
function PlaySound() end
SOUNDKIT = {}
C_Timer = { After = function() end }
local tipped
GameTooltip = setmetatable({ SetText = function(_, t) tipped = t end }, { __index = function() return function() end end })
SlashCmdList = {}
UIParent = New("Frame", "UIParent"); UIParent.w, UIParent.h = 1920, 1080
function UIParent:GetWidth() return 1920 end
function UIParent:GetHeight() return 1080 end
local character = New("Frame", "CharacterFrame", UIParent); character.w, character.h = 400, 500
local mail = New("Frame", "MailFrame", UIParent); mail:Hide()
-- Blizzard's own buttons the Open/Close action hands its hardware click to.
local micro = New("Button", "CharacterMicroButton", UIParent)
character.CloseButton = New("Button", nil, character)
-- Any addon call into Blizzard's panel code is a failure: it taints the
-- gamepad focus manager (1.3.1 regression).
for _, fn in ipairs({ "ToggleCharacter", "HideUIPanel", "ShowUIPanel", "UpdateContainerFrameAnchors" }) do
    _G[fn] = function() error(fn .. " called from addon code") end
end
UIPanelWindows = { CharacterFrame = {}, MailFrame = {} }
function UpdateUIPanelPositions() error("UpdateUIPanelPositions called from addon code") end
ForeverWindowsDB = { windows = {
    CharacterFrame = { scale = 1.2, x = 0.3, y = -0.2 },
    MailFrame = { scale = 0.9, x = 0.5, y = -0.1, w = 300, h = 400 },
} }

local ns = {}
for _, file in ipairs({ "Core", "Skin", "Options" }) do
    assert(loadfile("Interface/AddOns/ForeverWindows/" .. file .. ".lua"))("ForeverWindows", ns)
end
local events
for _, f in ipairs(all) do if f.scripts.OnEvent and f.scripts.OnUpdate == nil and not f.name then events = events or f end end
events:Fire("OnEvent", "ADDON_LOADED", "ForeverWindows")
events:Fire("OnUpdate", 0.1)
local function near(a, b) assert(math.abs(a - b) < 0.01, tostring(a) .. " ~= " .. tostring(b)) end
near(character.scale, 1.2)

SlashCmdList.FOREVERWINDOWS("")
local win = ForeverWindowsOptions
assert(win and win:IsShown(), "/fwm opens the options window")
assert(UISpecialFrames[1] == "ForeverWindowsOptions", "Escape closes it")

-- Rows: find by their Reset/Open buttons.
local function Rows()
    local rows = {}
    for _, f in ipairs(all) do
        if f.entry ~= nil or (f.reset and f.open) then rows[#rows + 1] = f end
    end
    table.sort(rows, function(a, b) return (a.entry and a.entry.label or "~") < (b.entry and b.entry.label or "~") end)
    return rows
end
local rows = Rows()
assert(rows[1].entry.name == "CharacterFrame" and rows[2].entry.name == "MailFrame", "sorted by readable name")
assert(rows[1].name.text == "Character" and rows[2].name.text == "Mailbox")
assert(rows[1].detail.text:find("120%%") and rows[1].detail.text:find("open"), "scale and open state shown")
assert(rows[2].detail.text:find("at a mailbox"), "context windows say where they open")
local function Attr(b, k) return b.attributes and b.attributes[k] end
assert(rows[1].open.enabled and rows[1].open.label.text == "Close", "openable window")
assert(rows[1].open.kind == "Button" and not rows[1].open.scripts.OnClick, "action template keeps its own click handler")
assert(Attr(rows[1].open, "type") == "click" and Attr(rows[1].open, "clickbutton") == character.CloseButton,
    "Close hands the click to the window's own close button")
assert(not rows[2].open.enabled, "game-only window cannot be opened")
rows[2].open:Fire("OnEnter"); assert(tipped:find("mailbox"), "disabled Open explains why")

-- Hover preview: a closed window shows its saved rect, an open one its live rect.
rows[2].mouse = true; win:Fire("OnUpdate", 0.01)
local ghost, native
for _, f in ipairs(all) do if f.fade then if ghost then native = f else ghost = f end end end
assert(ghost and ghost:IsShown() and not native:IsShown(), "hover shows outline preview")
near(ghost.left, 0.5 * 1920); near(ghost.top, 0.9 * 1080); assert(ghost.w == 300 and ghost.h == 400)
rows[2].mouse = false; win:Fire("OnUpdate", 0.01)
assert(not ghost:IsShown(), "leaving the row hides the preview")
-- Hovering Reset: Blizzard's spot (seen just before the layout was applied)
-- in silver, the current layout dimmed behind it.
assert(ForeverWindowsDB.native.CharacterFrame, "Blizzard's spot is remembered")
rows[1].mouse = true; rows[1].reset.mouse = true; win:Fire("OnUpdate", 0.01)
assert(native:IsShown() and native.left == 100 and native.top == 800 and native.w == 400 and native.h == 500,
    "reset preview shows Blizzard's position and size")
assert(ghost:IsShown() and ghost.w == 480 and native.title.text == "Blizzard default")
rows[1].reset:Fire("OnEnter"); assert(tipped:find("silver"))
rows[2].mouse = true; rows[1].mouse = false; rows[1].reset.mouse = false
rows[2].reset.mouse = true; win:Fire("OnUpdate", 0.01)
assert(not native:IsShown() and ghost.title.text == "Mailbox", "unknown Blizzard spot falls back to your layout")
rows[2].reset:Fire("OnEnter"); assert(tipped:find("once the window has been opened"))
rows[2].mouse = false; rows[2].reset.mouse = false; win:Fire("OnUpdate", 0.01)

-- Open/close uses Blizzard's toggles.
character:Hide()
rows = Rows(); assert(rows[1].open.label.text == "Open")
assert(Attr(rows[1].open, "clickbutton") == micro, "Open hands the click to Blizzard's micro button")
character:Show(); events:Fire("OnUpdate", 0.1)
rows = Rows(); assert(Attr(rows[1].open, "clickbutton") == character.CloseButton)

-- Reset: forgets the layout, returns the open panel to Blizzard's layout, offers undo.
rows = Rows()
rows[1].reset:Fire("OnClick")
assert(ForeverWindowsDB.windows.CharacterFrame == nil, "reset forgets the layout")
near(character.scale, 1); near(character.left, 100); near(character.top, 800)
rows = Rows()
assert(rows[1].reset.text == "Undo" and rows[1].detail.text:find("Blizzard default"))
events:Fire("OnUpdate", 0.001); near(character.left, 100)
rows[1].reset:Fire("OnClick")
near(character.scale, 1.2); near(ForeverWindowsDB.windows.CharacterFrame.x, 0.3)
rows = Rows(); assert(rows[1].reset.text == "Reset", "undo restores the layout")

-- A closed window resets for next time.
rows[2].reset:Fire("OnClick")
rows = Rows(); assert(rows[2].detail.text:find("next time"), "closed window resets on next open")
rows[2].reset:Fire("OnClick")

-- Reset all needs a second click.
local resetAll
for _, f in ipairs(all) do if f.text == "Reset all" then resetAll = f end end
resetAll:Fire("OnClick"); assert(ForeverWindowsDB.windows.CharacterFrame and resetAll.text == "Confirm", "first click arms")
resetAll:Fire("OnClick"); assert(next(ForeverWindowsDB.windows) == nil, "second click resets every window")
rows = Rows(); assert(rows[1].reset.text == "Undo" and rows[2].reset.text == "Undo", "each stays undoable")
rows[1].reset:Fire("OnClick"); rows[2].reset:Fire("OnClick")
assert(ForeverWindowsDB.windows.CharacterFrame and ForeverWindowsDB.windows.MailFrame)

-- Combat disables Open; the enable box turns the addon off and on.
combat = true; events:Fire("OnEvent", "PLAYER_REGEN_DISABLED"); win:Fire("OnEvent", "PLAYER_REGEN_DISABLED")
rows = Rows(); assert(not rows[1].open.enabled, "no Open in combat")
combat = false; win:Fire("OnEvent", "PLAYER_REGEN_ENABLED")
local enable
for _, f in ipairs(all) do if f.kind == "CheckButton" then enable = f end end
enable.checked = false; enable:Fire("OnClick")
assert(ForeverWindowsDB.enabled == false and not ns.IsEnabled())
enable.checked = true; enable:Fire("OnClick")
assert(ForeverWindowsDB.enabled == true and ns.IsEnabled())

-- Empty state.
ForeverWindowsDB.windows = {}
SlashCmdList.FOREVERWINDOWS(""); SlashCmdList.FOREVERWINDOWS("")
for _, row in ipairs(Rows()) do assert(not row:IsShown()) end
win:Fire("OnHide"); assert(not ghost:IsShown() and not native:IsShown())
print("PASS: options list, labels, where-hints, hover preview, open/close, reset, undo, reset all, combat, enable, empty state")
