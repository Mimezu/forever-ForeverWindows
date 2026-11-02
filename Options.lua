local _, ns = ...

-- A small Legacy-style window listing every moved or resized window, with a
-- live outline preview on hover, open/close, and reset to Blizzard's layout.

local W, H = 344, 404
local ROWS, ROW_H = 8, 34
local GOLD, NOTE, DIM, GREEN = {1, 0.82, 0}, {0.80, 0.77, 0.70}, {0.5, 0.5, 0.5}, {0.55, 0.85, 0.45}

local LABELS = {
    CharacterFrame = "Character", WorldMapFrame = "World map", FriendsFrame = "Social",
    SocialUIFrame = "Social", GuildFrame = "Guild", CommunitiesFrame = "Guild & Communities",
    GuildControlUI = "Guild control", GuildRegistrarFrame = "Guild registrar", GuildBankFrame = "Guild bank",
    BankFrame = "Bank", MerchantFrame = "Vendor", TradeFrame = "Trade", LootFrame = "Loot",
    MailFrame = "Mailbox", OpenMailFrame = "Letter", AuctionFrame = "Auction house",
    AuctionHouseFrame = "Auction house", ClassTrainerFrame = "Trainer", CraftFrame = "Crafting",
    TradeSkillFrame = "Profession", ProfessionsFrame = "Professions", ProfessionsBookFrame = "Professions book",
    SpellBookFrame = "Spellbook", PlayerSpellsFrame = "Spells & talents", QuestLogFrame = "Quest log",
    QuestFrame = "Quest", GossipFrame = "NPC dialog", QuestLogPopupDetailFrame = "Quest details",
    InspectFrame = "Inspect", LFGParentFrame = "Group finder", DressUpFrame = "Dressing room", PetStableFrame = "Stable", StableFrame = "Stable",
    CollectionsJournal = "Collections", AchievementFrame = "Achievements", TalentFrame = "Talents",
    PlayerTalentFrame = "Talents", MacroFrame = "Macros", ItemTextFrame = "Book", PetitionFrame = "Petition",
    TabardFrame = "Tabard", TaxiFrame = "Flight map", FlightMapFrame = "Flight map", HelpFrame = "Help",
    SettingsPanel = "Options", InterfaceOptionsFrame = "Interface options", ChatConfigFrame = "Chat settings",
    CalendarFrame = "Calendar", PVEFrame = "Group finder", PVPUIFrame = "PvP", PVPFrame = "PvP",
    EncounterJournal = "Adventure guide", ContainerFrameCombinedBags = "Bags",
}
-- Windows only the game can open, and where.
local WHERE = {
    MerchantFrame = "at a vendor", MailFrame = "at a mailbox", OpenMailFrame = "at a mailbox",
    BankFrame = "at a banker", GuildBankFrame = "at a guild vault", AuctionFrame = "at an auctioneer",
    AuctionHouseFrame = "at an auctioneer", ClassTrainerFrame = "at a trainer", TaxiFrame = "at a flight master",
    FlightMapFrame = "at a flight master", TradeFrame = "when trading", LootFrame = "when looting",
    GossipFrame = "when talking to NPCs", QuestFrame = "when talking to NPCs", InspectFrame = "when inspecting",
    PetStableFrame = "at a stable master", StableFrame = "at a stable master", TabardFrame = "at a tabard vendor",
    GuildRegistrarFrame = "at a guild master", PetitionFrame = "with a charter", ItemTextFrame = "when reading",
    CraftFrame = "from your spellbook", TradeSkillFrame = "from your spellbook", ProfessionsFrame = "from your spellbook",
}
-- Open and Close never call Blizzard's panel code from addon code: its gamepad
-- focus manager listens to panel broadcasts, and an addon-made call leaves its
-- focus state tainted, which later blocks protected gamepad actions. Instead
-- the Open/Close button is an action button whose hardware click is handed to
-- Blizzard's own button (a micro button, or the window's close button), the
-- same delegation Gamepad Companion uses for Spells.
local OPEN_BUTTONS = {
    CharacterFrame = {"CharacterMicroButton"},
    -- Forever has no MiniMapWorldMapButton: the zone name above the minimap
    -- is the button that toggles the world map (MinimapZoneTextButtonMixin).
    WorldMapFrame = { function() return MinimapCluster and MinimapCluster.ZoneTextButton end },
    QuestLogFrame = {"QuestLogMicroButton"}, FriendsFrame = {"QuickJoinToastButton"},
    GuildFrame = {"GuildMicroButton"}, CommunitiesFrame = {"GuildMicroButton"},
    SpellBookFrame = {"SpellbookMicroButton"}, PlayerSpellsFrame = {"PlayerSpellsMicroButton", "SpellbookMicroButton"},
    ProfessionsBookFrame = {"ProfessionMicroButton"}, CollectionsJournal = {"CollectionsMicroButton"},
    -- Build 70338: on Forever these micro buttons open ProfessionsFrame and the
    -- vanilla-style group finder (LFGParentFrame).
    ProfessionsFrame = {"ProfessionMicroButton"}, LFGParentFrame = {"LFDMicroButton"},
    AchievementFrame = {"AchievementMicroButton"}, TalentFrame = {"TalentMicroButton"},
    PlayerTalentFrame = {"TalentMicroButton"}, CalendarFrame = {"GameTimeFrame"},
    PVEFrame = {"LFDMicroButton"}, EncounterJournal = {"EJMicroButton"}, HelpFrame = {"HelpMicroButton"},
    ContainerFrameCombinedBags = {"MainMenuBarBackpackButton"}, ContainerFrame1 = {"MainMenuBarBackpackButton"},
}
-- Blizzard slash commands, run by the engine's macro action.
local OPEN_MACROS = { MacroFrame = "/macro" }

local function Label(name)
    if LABELS[name] then return LABELS[name] end
    local bag = name:match("^ContainerFrame(%d+)$")
    if bag then return "Bag " .. bag end
    return (name:gsub("Frame$", ""):gsub("(%l)(%u)", "%1 %2"))
end

local function Readable(button)
    if type(button) ~= "table" or type(button.IsForbidden) ~= "function" then return false end
    local ok, forbidden = pcall(button.IsForbidden, button)
    return ok and not forbidden and button:IsObjectType("Button")
end

-- Blizzard marks some buttons as not clickable through scripted input.
local function Delegable(button)
    if not Readable(button) then return false end
    local aspect = Enum and Enum.ForbiddenAspect and Enum.ForbiddenAspect.ScriptedInput
    if aspect and type(button.HasAccessConstraints) == "function" and type(button.HasAnyForbiddenAspects) == "function" then
        local okAccess, constrained = pcall(button.HasAccessConstraints, button)
        local okScript, forbidden = pcall(button.HasAnyForbiddenAspects, button, aspect)
        if not okAccess or not okScript then return false end
        if issecretvalue and (issecretvalue(constrained) or issecretvalue(forbidden)) then return false end
        return constrained == false and forbidden == false
    end
    return true
end

local function CloseButtonOf(f)
    for _, button in ipairs({ f.CloseButton, f.BorderFrame and f.BorderFrame.CloseButton,
        f.ClosePanelButton, _G[(f:GetName() or "") .. "CloseButton"] }) do
        if Delegable(button) and button:IsVisible() then return button end
    end
end

-- The action for the Open/Close button: "click", button / "macro", text, or
-- nil plus the reason it is unavailable.
local function Action(name)
    if InCombatLockdown() then return nil, "Not available in combat." end
    local f = ns.Frame(name)
    if f and f:IsVisible() then
        local close = CloseButtonOf(f)
        if close then return "click", close end
        return nil, "Close it with its own button or Escape."
    end
    if OPEN_MACROS[name] then return "macro", OPEN_MACROS[name] end
    local names = OPEN_BUTTONS[name] or (name:find("^ContainerFrame") and OPEN_BUTTONS.ContainerFrame1)
    for _, entry in ipairs(names or {}) do
        -- A global name, or a function for a button that only has a parentKey.
        local button
        if type(entry) == "function" then button = entry() else button = _G[entry] end
        if Delegable(button) then return "click", button end
    end
    if WHERE[name] then return nil, "Only the game opens this window, " .. WHERE[name] .. "." end
    return nil, names and "Blizzard's button for this window is unavailable right now."
        or "Open this window the usual way; hover the row to see where it sits."
end

local function Copy(t)
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    return c
end

-- Outline previews -----------------------------------------------------------

-- Gold: your layout. Silver: where Blizzard puts the window.
local SILVER = {0.78, 0.86, 1}
local ghosts = {}
local function Ghost(key, color)
    if ghosts[key] then return ghosts[key] end
    local g = CreateFrame("Frame", nil, UIParent)
    ghosts[key] = g
    g:SetFrameStrata("DIALOG")
    g:EnableMouse(false)
    g:Hide()
    local fill = g:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(); fill:SetColorTexture(color[1], color[2], color[3], 0.10)
    g.fill = fill
    local function Edge(a, b, horizontal)
        local t = g:CreateTexture(nil, "BORDER")
        t:SetColorTexture(color[1], color[2], color[3], 0.9)
        t:SetPoint(a); t:SetPoint(b)
        if horizontal then t:SetHeight(2) else t:SetWidth(2) end
    end
    Edge("TOPLEFT", "TOPRIGHT", true); Edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
    Edge("TOPLEFT", "BOTTOMLEFT"); Edge("TOPRIGHT", "BOTTOMRIGHT")
    local plate = g:CreateTexture(nil, "ARTWORK")
    plate:SetColorTexture(0, 0, 0, 0.72)
    g.title = g:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    g.title:SetPoint("CENTER", 0, 8)
    g.title:SetTextColor(color[1], color[2], color[3])
    g.detail = g:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    g.detail:SetPoint("TOP", g.title, "BOTTOM", 0, -4)
    g.detail:SetTextColor(NOTE[1], NOTE[2], NOTE[3])
    plate:SetPoint("TOPLEFT", g.title, "TOPLEFT", -14, 8)
    plate:SetPoint("BOTTOMRIGHT", g.detail, "BOTTOMRIGHT", 14, -8)
    g.plate = plate
    local fade = g:CreateAnimationGroup()
    local alpha = fade:CreateAnimation("Alpha")
    alpha:SetFromAlpha(0); alpha:SetToAlpha(1); alpha:SetDuration(0.12)
    g.fade = fade
    return g
end

local function Place(key, color, left, top, width, height, title, detail, dim)
    local g = Ghost(key, color)
    if not left then g:Hide(); return end
    g:ClearAllPoints()
    g:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    g:SetSize(width, height)
    g.title:SetText(title); g.detail:SetText(detail)
    -- The label plate only when it fits inside the outline.
    local fits = width > 150 and height > 70
    g.title:SetShown(fits and title ~= nil); g.detail:SetShown(fits and title ~= nil); g.plate:SetShown(fits and title ~= nil)
    g.fill:SetAlpha(dim and 0.4 or 1)
    g:SetAlpha(dim and 0.55 or 1)
    if not g:IsShown() then g:Show(); if not dim then g.fade:Play() end end
end

local function HideGhost()
    for _, g in pairs(ghosts) do g:Hide() end
end

local function Percent(scale) return math.floor((scale or 1) * 100 + 0.5) .. "% scale" end

-- part: nil (row), "reset" (Reset or Undo button).
local function ShowGhost(entry, part)
    local name, open = entry.name, ns.IsOpen(entry.name)
    local current = open and "open now" or "opens here"
    if part == "reset" and entry.undo then
        -- Undo: where your layout puts it back.
        local l, t, w, h = ns.SavedRect(name, entry.undo)
        Place("mine", GOLD, l, t, w, h, entry.label, Percent(entry.undo.scale) .. "  ·  undo puts it here")
        Place("native", SILVER, nil)
        return
    end
    if part == "reset" then
        -- Reset: Blizzard's spot in silver, your current layout dimmed behind it.
        local l, t, w, h, scale = ns.NativeRect(name)
        Place("native", SILVER, l, t, w, h, "Blizzard default", Percent(scale) .. "  ·  reset puts it here")
        local ml, mt, mw, mh = ns.SavedRect(name)
        if open then ml, mt, mw, mh = ns.LiveRect(name) end
        Place("mine", GOLD, ml, mt, mw, mh, l and nil or entry.label, l and nil or "Blizzard's spot not seen yet", l ~= nil)
        return
    end
    local l, t, w, h
    if open then l, t, w, h = ns.LiveRect(name)
    elseif not entry.undo then l, t, w, h = ns.SavedRect(name) end
    local detail = entry.undo and "Blizzard default" or Percent(entry.scale)
    Place("mine", entry.undo and SILVER or GOLD, l, t, w, h, entry.label, detail .. "  ·  " .. current)
    Place("native", SILVER, nil)
end

-- Window --------------------------------------------------------------------

local frame, Refresh
local undo, pending = {}, {}
local offset, armed = 0, false

local function Create()
    local skin = ns.Skin
    frame = CreateFrame("Frame", "ForeverWindowsOptions", UIParent)
    frame:Hide()
    frame:SetSize(W, H)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN")
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    if UISpecialFrames then table.insert(UISpecialFrames, "ForeverWindowsOptions") end
    local heading = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    heading:SetText("Forever Windows")
    skin.Frame(frame, heading)

    local function Text(parent, text, template, color)
        local label = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlight")
        label:SetJustifyH("LEFT")
        label:SetText(text)
        if color then label:SetTextColor(color[1], color[2], color[3]) end
        return label
    end
    local function Line(parent, alpha)
        local line = parent:CreateTexture(nil, "BORDER")
        line:SetColorTexture(0.68, 0.50, 0.26, alpha)
        return line
    end
    local function Button(parent, text, width, onClick)
        local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        button:SetSize(width, 22)
        button:SetText(text)
        button:SetScript("OnClick", onClick)
        button:SetMotionScriptsWhileDisabled(true)
        skin.Button(button)
        return button
    end
    local function Tip(owner, text)
        owner:SetScript("OnEnter", function(self)
            local value = type(text) == "function" and text(self) or text
            if not value or not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(value, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        owner:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    end

    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", 22, -44)
    content:SetPoint("BOTTOMRIGHT", -16, 48)
    local status = Text(content, "", "GameFontHighlightSmall", NOTE)
    status:SetPoint("TOPLEFT", 2, 0)
    local version = Text(content, "v" .. ns.VERSION, "GameFontDisableSmall")
    version:SetPoint("TOPRIGHT", -2, 0)

    -- The list card.
    local list = CreateFrame("Frame", nil, content)
    list:SetPoint("TOPLEFT", 0, -20)
    list:SetPoint("TOPRIGHT", 0, -20)
    list:SetHeight(ROWS * ROW_H + 10)
    local wash = list:CreateTexture(nil, "BACKGROUND", nil, -2)
    wash:SetAllPoints(); wash:SetColorTexture(0.25, 0.17, 0.085, 0.16)
    local top = Line(list, 0.55); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(1)
    local bottom = Line(list, 0.3); bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT"); bottom:SetHeight(1)
    local leftEdge = Line(list, 0.3); leftEdge:SetPoint("TOPLEFT"); leftEdge:SetPoint("BOTTOMLEFT"); leftEdge:SetWidth(1)
    local rightEdge = Line(list, 0.3); rightEdge:SetPoint("TOPRIGHT"); rightEdge:SetPoint("BOTTOMRIGHT"); rightEdge:SetWidth(1)

    local empty = CreateFrame("Frame", nil, list)
    empty:SetAllPoints()
    local emptyTitle = Text(empty, "No moved windows yet", "GameFontNormal")
    emptyTitle:SetPoint("CENTER", 0, 18); emptyTitle:SetJustifyH("CENTER")
    local emptyNote = Text(empty, "Drag a window's title bar to move it.\nCtrl + mouse wheel over the title scales it.",
        "GameFontHighlightSmall", NOTE)
    emptyNote:SetPoint("TOP", emptyTitle, "BOTTOM", 0, -8); emptyNote:SetJustifyH("CENTER")
    emptyNote:SetSpacing(3)

    local thumb = list:CreateTexture(nil, "ARTWORK")
    thumb:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.5)
    thumb:SetWidth(2)

    local rows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Frame", nil, list)
        row:SetPoint("TOPLEFT", 6, -5 - (i - 1) * ROW_H)
        row:SetPoint("RIGHT", list, "RIGHT", -8, 0)
        row:SetHeight(ROW_H)
        row.hover = row:CreateTexture(nil, "BACKGROUND")
        row.hover:SetAllPoints(); row.hover:SetColorTexture(1, 0.72, 0.2, 0.12)
        row.hover:Hide()
        if i < ROWS then
            local rule = Line(row, 0.14)
            rule:SetPoint("BOTTOMLEFT", 6, 0); rule:SetPoint("BOTTOMRIGHT", -6, 0); rule:SetHeight(1)
        end
        row.name = Text(row, "", "GameFontHighlight")
        row.name:SetPoint("TOPLEFT", 8, -4); row.name:SetPoint("RIGHT", row, "RIGHT", -130, 0)
        row.name:SetWordWrap(false)
        row.detail = Text(row, "", "GameFontHighlightSmall", NOTE)
        row.detail:SetPoint("TOPLEFT", 8, -19); row.detail:SetPoint("RIGHT", row, "RIGHT", -130, 0)
        row.detail:SetWordWrap(false)
        row.reset = Button(row, "Reset", 58, function(self)
            local entry = self:GetParent().entry
            if not entry then return end
            if entry.undo then
                ns.Undo(entry.name, entry.undo)
                undo[entry.name], pending[entry.name] = nil, nil
            else
                undo[entry.name] = Copy(ForeverWindowsDB.windows[entry.name])
                pending[entry.name] = not ns.Reset(entry.name) or nil
            end
            Refresh()
        end)
        row.reset:SetPoint("RIGHT", -4, 0)
        Tip(row.reset, function(self)
            local entry = self:GetParent().entry
            if not entry then return end
            if entry.undo then return "Put " .. entry.label .. " back where you had it." end
            if not ns.NativeRect(entry.name) then
                return "Forget this position and size. " .. entry.label .. " opens where Blizzard puts it.|n|n"
                    .. "|cffa0a0a0Blizzard's spot shows here once the window has been opened.|r"
            end
            return "Forget this position and size. " .. entry.label .. " opens where Blizzard puts it (silver outline)."
        end)
        -- An action button: no OnClick of ours, the template's own handler
        -- passes the hardware click to Blizzard's button.
        local open = CreateFrame("Button", nil, row, "InsecureActionButtonTemplate")
        open:SetSize(58, 22)
        open:RegisterForClicks("LeftButtonUp")
        open:SetAttribute("useOnKeyDown", false)
        open:SetMotionScriptsWhileDisabled(true)
        open.label = open:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        open.label:SetPoint("CENTER", 0, 0)
        skin.Button(open)
        open:SetScript("PostClick", function() if Refresh then Refresh() end end)
        open:SetPoint("RIGHT", row.reset, "LEFT", -4, 0)
        Tip(open, function(self)
            local entry = self:GetParent().entry
            return entry and select(2, Action(entry.name))
        end)
        row.open = open
        rows[i] = row
    end

    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        offset = offset - delta
        Refresh()
    end)

    -- Footer.
    local enable = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    enable:SetSize(26, 26)
    enable:SetPoint("BOTTOMLEFT", 20, 14)
    local enableLabel = enable.Text or enable.text
    enableLabel:SetFontObject("GameFontHighlight")
    enableLabel:SetText("Move & scale windows")
    enable:SetScript("OnClick", function(self) ns.SetEnabled(self:GetChecked() == true) end)
    Tip(enable, "Off: windows open where Blizzard puts them. Saved positions are kept.")

    local resetAll = Button(frame, "Reset all", 86, function()
        if not armed then
            armed = true
            Refresh()
            if C_Timer then C_Timer.After(4, function() if armed then armed = false; Refresh() end end) end
            return
        end
        armed = false
        for _, name in ipairs(ns.Layouts()) do
            undo[name] = Copy(ForeverWindowsDB.windows[name])
            pending[name] = not ns.Reset(name) or nil
        end
        Refresh()
    end)
    resetAll:SetPoint("BOTTOMRIGHT", -18, 16)
    Tip(resetAll, "Every window goes back to Blizzard's position and size. Each can still be undone until you log out.")

    Refresh = function()
        if not frame:IsShown() then return end
        local entries, seen = {}, {}
        for _, name in ipairs(ns.Layouts()) do
            undo[name], pending[name] = nil, nil
            entries[#entries + 1] = { name = name, label = Label(name), scale = ns.Layout(name) }
            seen[name] = true
        end
        for name, d in pairs(undo) do
            if not seen[name] then entries[#entries + 1] = { name = name, label = Label(name), undo = d } end
        end
        table.sort(entries, function(a, b)
            if a.label ~= b.label then return a.label < b.label end
            return a.name < b.name
        end)
        local maxOffset = math.max(0, #entries - ROWS)
        offset = math.max(0, math.min(offset, maxOffset))
        empty:SetShown(#entries == 0)
        for i, row in ipairs(rows) do
            local entry = entries[i + offset]
            row.entry = entry
            row:SetShown(entry ~= nil)
            if entry then
                local open = ns.IsOpen(entry.name)
                row.name:SetText(entry.label)
                local detail
                if entry.undo then
                    detail = pending[entry.name] and "Blizzard default next time it opens" or "Blizzard default"
                    row.name:SetTextColor(DIM[1], DIM[2], DIM[3])
                else
                    detail = math.floor(entry.scale * 100 + 0.5) .. "%"
                    row.name:SetTextColor(1, 1, 1)
                end
                if open then detail = detail .. "  ·  |cff8cd973open|r"
                elseif WHERE[entry.name] and not entry.undo then detail = detail .. "  ·  opens " .. WHERE[entry.name] end
                row.detail:SetText(detail)
                row.reset:SetText(entry.undo and "Undo" or "Reset")
                local kind, target = Action(entry.name)
                -- Insecure action buttons accept attributes in combat, but
                -- nothing is changed then: the button is simply disabled.
                if not InCombatLockdown() then
                    row.open:SetAttribute("type", kind)
                    row.open:SetAttribute("clickbutton", kind == "click" and target or nil)
                    row.open:SetAttribute("macrotext", kind == "macro" and target or nil)
                end
                row.open.label:SetText(open and "Close" or "Open")
                row.open:SetEnabled(kind ~= nil)
                if kind then row.open.label:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
                else row.open.label:SetTextColor(DIM[1], DIM[2], DIM[3]) end
            end
        end
        if maxOffset > 0 then
            local track = list:GetHeight() - 12
            local size = math.max(24, track * ROWS / #entries)
            thumb:ClearAllPoints()
            thumb:SetPoint("TOPRIGHT", -3, -6 - (track - size) * offset / maxOffset)
            thumb:SetHeight(size)
            thumb:Show()
        else
            thumb:Hide()
        end
        local count = #ns.Layouts()
        if not ns.IsEnabled() then
            status:SetText("|cffff6040Off|r  ·  windows open where Blizzard puts them")
        elseif count == 0 then
            status:SetText("Positions and sizes you set")
        else
            status:SetText("Hover a window to see where it sits")
        end
        enable:SetChecked(ns.IsEnabled())
        resetAll:SetEnabled(count > 0)
        resetAll:SetText(armed and "Confirm" or "Reset all")
        if count > 0 then
            resetAll:GetFontString():SetTextColor(armed and 1 or GOLD[1], armed and 0.38 or GOLD[2], armed and 0.25 or GOLD[3])
        end
    end

    -- Hover drives the outline preview; this runs only while the window is open.
    local hovered, hoveredPart
    frame:SetScript("OnUpdate", function()
        local over
        for _, row in ipairs(rows) do
            if row:IsShown() and row:IsMouseOver() then over = row; break end
        end
        local entry = over and over.entry
        local part = over and over.reset:IsMouseOver() and "reset" or nil
        for _, row in ipairs(rows) do row.hover:SetShown(row == over) end
        if entry ~= hovered or part ~= hoveredPart then
            hovered, hoveredPart = entry, part
            if entry then ShowGhost(entry, part) else HideGhost() end
        end
    end)
    frame:SetScript("OnShow", function()
        offset, armed, hovered, hoveredPart = 0, false, nil, nil
        if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN) end
        Refresh()
    end)
    frame:SetScript("OnHide", function()
        armed, hovered, hoveredPart = false, nil, nil
        HideGhost()
        if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE) end
    end)
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:SetScript("OnEvent", function() Refresh() end)
end

ns.OnLayoutsChanged = function()
    -- Rows get fresh entries, so the preview follows a window opening or closing.
    if frame and frame:IsShown() then Refresh() end
end

function ns.ToggleOptions()
    if not frame then Create() end
    frame:SetShown(not frame:IsShown())
end
