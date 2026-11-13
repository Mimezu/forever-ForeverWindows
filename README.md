# Forever Windows - 1.4.0

Supported Blizzard windows are enabled by default. Left-drag their title bars to move; Ctrl + mouse wheel scales by 5%, from 50% to 200%. Account-wide positions and sizes persist across reloads.

Supported windows include Character, windowed Map, friends/guild, banks/bags, vendors, mail, auctions, professions, spellbook, quests, collections, talents, and settings. Discovery uses a window allowlist plus Blizzard's UIPanelWindows registry. Edit Mode systems, forbidden frames, cinematics and game-menu frames are excluded; this is not a general HUD mover. Movement and restoration pause during combat. Unusual window layouts may need individual adapters.

Saved layouts restore synchronously on opening. An OnShow post-hook handles direct openings; Blizzard's panel-open notification reapplies the layout after its panel manager finishes. No native method/script replacement, secure panel attribute changes, or close-time layout writes are used. Window-owned buttons handle title-bar input and share native focus/stacking. They ignore parent scale so their measured hit areas remain correct. Discovery runs on addon load, panel-open, bag, world and display events rather than a repeating scan.

The update loop stops when all managed windows are closed, during combat, and when disabled. Visibility hooks and game events wake it. Visible windows use a 10 Hz grip audit to follow native tab/focus/geometry changes; dragging updates each frame. Unchanged grip anchors and sizes are not rewritten, and stationary drags do not repeatedly save coordinates.

Dressing room (Ctrl-click) opens beside the auction house; it no longer closes it or the bags. While the auction house is open, the dressing room is shrunk to fit; its own scale returns when it opens alone.

## Commands

- `/fwm`: open the options window (moved windows, preview, open, reset).
- `/fwm help`: list commands.
- `/fwm enable`: enable all supported windows, including after reloads.
- `/fwm off`: stop and remain disabled after reloads; retain saved layouts.
- `/fwm test`: Character-only test for this session; your saved enable/off choice is unchanged.
- `/fwm gamepad`: pause or resume window moving while the gamepad UI is active (moving is on by default).
- `/fwm taint`: read-only check of Blizzard's gamepad state; prints which parts are tainted and by which addon, and saves the result (`ForeverWindowsDB.lastTaintCheck`) so it survives a `/reload`.
- `/fwm debug`: show version, mode, input counts, visible grip information, the last blocked action, and saved gamepad reports.
- `/fwm reset`: clear layouts and reload.

An addon-blocked/forbidden-action report suspends the addon and disables automatic startup until `/fwm enable` is used again.

## Saved settings

Layouts load through native SavedVariables (`ForeverWindowsDB`). The former `_SavedVariables.local` bridge is retired.

## Verification

Run `lua5.1 Interface/AddOns/ForeverWindows/tests/Behavior.lua` and `lua5.1 Interface/AddOns/ForeverWindows/tests/Options.lua` from the client root. Tests cover automatic startup, persistent enable/off, Character isolation, window-owned click-enabled grips, movement/scaling, synchronous restoration with no update tick, direct openings, load-on-demand discovery, combat, forbidden/Edit Mode/cycle exclusions, windowed map, read-only close paths, and suspension after blocked actions. Lua 5.1 syntax is also checked. These mocks do not replace live validation of every window's layout or the client's security rules.

The user-verified Character-only 1.1.3 version is preserved in `StorageInvestigation/foreverwindows-working-1.1.3`.

Version 1.2.1 adds an explicit classic MerchantFrame title-bar hit area, independent of inherited title-container dimensions. Regression covers merchant drag, Ctrl-wheel scaling and synchronous reopening with a zero-width inherited title container.

Version 1.2.2 keeps grips above the window and its focused tab content instead of using the title container alone. It checks only current mouse-focus ancestry during the existing grip refresh; unrelated and forbidden frames are excluded. Tests simulate a raised tab input layer and dragging without reopening. Live input routing still requires client verification.

Version 1.2.3 puts each input grip inside its owning window instead of making it a separate top-level window. This addresses drag input loss after interacting with window contents; numerical frame-level adjustments alone were insufficient in the live client. Tests check shared input ancestry and independent scale, but the native focus behavior still requires live verification.

Bag title bars also contain an unnamed native button routing clicks to the portrait menu. The grip sits above visible direct children and disables click propagation; the portrait remains outside its title hit area. Tests cover routing-layer order and bag dragging.

Version 1.2.4 extends the vendor title grip to the top-right edge when the native close button is hidden (gamepad UI). When the close button is visible, its 28-pixel area remains reserved. `/fwm vendor` toggles the diagnostic green highlight; `/fwm debug` reports per-window drag input and requested/actual positions.

Version 1.2.5 is a performance pass. The 10 Hz audit checks visibility before walking parents, Edit Mode systems are a cached set, drags update the saved layout in place, panel-open discovery runs once, and bag updates rescan only when a new bag frame exists. `/fwm test` no longer turns the addon off for future logins. The old 1.0.2 sources in `archive/` were removed (kept in the StorageInvestigation backup).

Version 1.2.6 pauses window moving while Blizzard's gamepad UI is active (build 1.60.1.70009). On 2026-09-25 the addon suspended itself with `ADDON_ACTION_FORBIDDEN: SetPreferredGamepadInteractTarget()` raised from a gamepad popup. Blizzard's gamepad frame manager sorts every open window by its on-screen centre (`FrameLessThanCmp` -> `GetScaledCenter`) whenever a window, chat or popup shows. A window positioned by this addon taints that sort and the protected interact-target update that follows. In the gamepad UI, grips are hidden and windows open at their native positions. Switching back to keyboard/mouse restores open windows. A window moved before switching keeps its position until it is reopened. `/fwm gamepad` opts back in at your own risk. After updating, run `/fwm enable` once: the blocked action left `enabled = false` saved.

Version 1.2.7 moves windows in the gamepad UI by default again. The 1.2.6 explanation (addon-set window positions taint Blizzard's gamepad sort) did not hold up in a live test on 2026-09-26. A moved Character window plus a gamepad delete-item popup left every checked piece of gamepad state clean, and the taint log recorded nothing from this addon. The one earlier `SetPreferredGamepadInteractTarget()` block is still unexplained; its saved stack was cut off before the origin. If a blocked action happens in the gamepad UI now, moving pauses there for that session only. Keyboard/mouse mode keeps working and the addon stays enabled. The report keeps both ends of the stack, a timestamp and a `/fwm taint` snapshot; see `/fwm debug`. Blocked actions in keyboard/mouse mode still suspend the addon as before.

Version 1.3.0 keeps moved windows where you put them. Blizzard's panel manager (`FramePositionDelegate:UpdateUIPanelPositions`) re-anchors every open panel when a tab changes a panel's width (for example Social -> Raid calls `FriendsFrame_UpdateUIPanelWidth`) and whenever another panel opens or closes, and it announces nothing afterwards. Moved windows now go back to their saved layout synchronously on Blizzard's open/close notifications, and a per-frame check (read-only unless a moved window drifted) catches tab re-anchors before the frame is drawn. Windows you never moved still follow Blizzard. A window that another addon re-anchors every frame is left alone after three tries until it is reopened or dragged. Blizzard may still close a panel when its slot rules think there is no room; that decision is secure code and is not changed.

`/fwm` opens a small Legacy-style options window listing every moved or resized window, sorted by name, with its scale and whether it is open. Hovering a row draws a gold outline where that window sits (live rect when open, saved rect when closed). Open/Close uses Blizzard's own toggles; windows only the game can open (vendor, mailbox, bank...) say where they open, and Open is disabled in combat (since 1.3.2 it also works in the gamepad UI, because the click is handed to Blizzard's own button; see below). Reset forgets the layout: an open panel returns to Blizzard's position and scale immediately (via `UpdateUIPanelPositions`, or `UpdateContainerFrameAnchors` for bags); otherwise it opens there next time. Every reset can be undone until logout. Reset all needs a second click. The footer checkbox is the same as `/fwm enable` / `/fwm off`. Layouts now also store the window size so closed windows preview at the right size; older layouts use the live frame size when the window exists.

Version 1.3.1: hovering Reset shows where Blizzard would put the window, as a silver outline with its size and scale, while your current layout stays dimmed in gold behind it. Hovering Undo shows your layout again. The addon records Blizzard's spot (`ForeverWindowsDB.native`, which is kept across resets) each time it puts a moved window back. That happens right after Blizzard placed it: on opening, a tab change, or another window opening. The record keeps Blizzard's anchor point and any scale-to-fit, and it reflects the slot Blizzard used at that moment. A window that hasn't been opened since updating has no record yet; its Reset tooltip says so.

Version 1.3.2 fixes a gamepad taint that 1.3.0 introduced. On 2026-09-27 the saved report showed `SetPreferredGamepadInteractTarget()` forbidden, with `frames.focusedFrame`, `frames.fallThroughCatcherActive` and `bindings.coreActive` "tainted by ForeverWindows". The options window's Open/Close/Reset buttons called `ToggleCharacter`/`HideUIPanel`/`UpdateUIPanelPositions` directly. Blizzard's gamepad `FrameControlsManager` listens to the ShowUIPanel/HideUIPanel broadcasts those calls make, so it stored its focus state under this addon's taint, even when the buttons were used in keyboard mode. That state later blocked spell binding and other gamepad actions, and the interrupted focus code closed other windows (for example Gamepad Companion's). Now:
- Open/Close is an `InsecureActionButtonTemplate` button. Its hardware click goes to Blizzard's own button: a micro button (or the minimap map button, the backpack button, or the calendar clock) to open, or the window's own close button to close. `/macro` runs as a macro action. This is the same pattern Gamepad Companion uses for Spells. The addon has no OnClick of its own on it. Buttons flagged with scripted-input restrictions are not used.
- Reset puts an open window back to the recorded Blizzard spot with its own `SetPoint`/`SetScale`, which is what the addon always does. With no record yet, it only resets the scale, and the window opens in Blizzard's spot next time.
- Tests fail if any Blizzard panel function is called from addon code.

Version 1.3.4 (build 70338): a window's strata can now be a secret value, so the grip falls back to HIGH when it can't read it. Open buttons for Professions (the Professions micro button now opens ProfessionsFrame on Forever) and the vanilla-style Group finder (LFGParentFrame, opened by the group finder micro button).

A session that already has this taint needs `/reload`.

Version 1.3.3 makes `/fwm taint` see where this taint really lands. Earlier checks only read the fields that hold Blizzard's lists (which never change), so a tainted session could still read "clean". Blizzard's own `table.insert`/`table.remove` calls running under an addon's taint write the list entries. The check now also reads the entries: open windows, popups, gamepad cursor panels and their button data, the binding stack and active bindings, the two stick listeners, and the bookkeeping of the panel, bag, menu and soft-target broadcasts. It also lists panel hooks that were installed under taint (these stay tainted until `/reload`). It prints only the tainted values plus a summary line, and saves the result.

The addon also saves a snapshot on its own while the gamepad UI is on (`ForeverWindowsDB.gamepadReports`, last 5): once per session for each other addon that has an action blocked, and once for the first Lua error inside Blizzard's gamepad navigation (via BugGrabber). This was added for the 2026-09-27 report of A no longer jumping and B no longer closing windows. There, `SmartNavigation` Show/Hide was refused after Frame Gambit's Cinematic Mode had called `CloseAllWindows()`. Nothing else changes for other addons' blocks.

Version 1.3.6 drops window names that do not exist on Forever (checked against the 70532 Blizzard UI source: GuildFrame, AuctionFrame, CraftFrame, TradeSkillFrame, SpellBookFrame, QuestLogFrame, StableFrame, TalentFrame, PlayerTalentFrame, InterfaceOptionsFrame, PVPFrame, EncounterJournal) from the discovery list and their label, location and Open-button rows. Windows that exist are unchanged.
