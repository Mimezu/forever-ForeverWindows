-- Run from the client root with Lua 5.1.
local all, combat, control, down, cx, cy = {}, false, false, false, 300, 650
local F = {}; F.__index = F
function CreateFrame(kind, name, parent)
    local f = setmetatable({ kind=kind, name=name, parent=parent, scripts={}, children={}, scale=1,
        left=100, top=800, width=400, height=500, writes=0, level=1 }, F)
    all[#all+1]=f
    if parent then parent.children[#parent.children+1]=f end
    if name then _G[name]=f end
    return f
end
function F:GetChildren() return unpack(self.children) end
function F:SetPropagateMouseClicks(v) self.propagateClicks=v end
function F:GetName() assert(not self.forbidden); return self.name end
function F:GetParent() assert(not self.forbidden); return self.parent end
function F:IsForbidden() return self.forbidden end
function F:IsObjectType(t) assert(not self.forbidden); return t=='Frame' end
function F:IsShown() return not self.hidden end
function F:IsVisible() return not self.hidden and (not self.parent or self.parent:IsVisible()) end
function F:GetScale() return self.scale end
function F:GetEffectiveScale() return self.scale*(not self.ignoreParentScale and self.parent and self.parent:GetEffectiveScale() or 1) end
function F:GetLeft() return self.title and self.parent:GetLeft()+58 or self.left end
function F:GetTop() return self.title and self.parent:GetTop()-1 or self.top end
function F:GetWidth() return self.title and self.parent:GetWidth()-82 or self.width end
function F:GetHeight() return self.title and 20 or self.height end
function F:GetFrameLevel() return self.level end
function F:GetFrameStrata() return 'MEDIUM' end
function F:SetScale(v) self.writes=self.writes+1; self.scale=v end
function F:ClearAllPoints() self.writes=self.writes+1 end
function F:SetPoint(point, relative, relativePoint, x,y)
    assert(relative==UIParent, 'no anchor dependency on Blizzard windows')
    self.writes=self.writes+1
    self.left=x
    self.top=y+(relativePoint=='TOPLEFT' and UIParent.height*UIParent:GetEffectiveScale()/self:GetEffectiveScale() or 0)
end
function F:SetSize(w,h) self.width,self.height=w,h end
function F:SetFrameLevel(v) self.level=v end
function F:SetFrameStrata() end
function F:Show() local hidden=self.hidden; self.hidden=false; if hidden and self.showHook then self.showHook(self) end end
function F:Hide()
    local shown = not self.hidden
    self.hidden=true
    if shown then
        if self.hideHook then self.hideHook(self) end
        self:Fire('OnHide')
    end
end
function F:EnableMouse() end
function F:SetMouseClickEnabled(v) self.clickEnabled=v end
function F:IsMouseClickEnabled() return self.clickEnabled end
function F:RegisterForClicks(...) self.clicks={...} end
function F:SetToplevel(v) self.toplevel=v end
function F:SetIgnoreParentScale(v) self.ignoreParentScale=v end
function F:EnableMouseWheel() end
function F:RegisterEvent() end
function F:RegisterForDrag(button) assert(button=='LeftButton'); self.dragButton=button end
function F:SetScript(k,v) self.scripts[k]=v end
function F:Fire(k,...) if self.scripts[k] then self.scripts[k](self,...) end end
-- Any legacy invasive operation is a hard test failure.
for _, method in ipairs({'SetMovable','StartMoving','StopMovingOrSizing','SetUserPlaced','SetClampedToScreen'}) do
    F[method]=function() error('forbidden legacy operation: '..method) end
end
function F:HookScript(event,fn)
    assert(event=='OnShow' or event=='OnHide','only visibility hooks permitted')
    local key = event=='OnShow' and 'showHook' or 'hideHook'
    assert(not self[key],'no duplicate hook'); self[key]=fn
end
function hooksecurefunc() error('native hooks must not be installed') end
function InCombatLockdown() return combat end
function IsControlKeyDown() return control end
function IsMouseButtonDown() return down end
function GetCursorPosition() return cx*UIParent:GetEffectiveScale(),cy*UIParent:GetEffectiveScale() end
function issecurevariable(_,name) return name~='ThirdPartyWindow' end
function ReloadUI() end
local mouseFoci={}
function GetMouseFoci() return mouseFoci end
SlashCmdList={}
EventRegistry={callbacks={}}
function EventRegistry:RegisterCallback(event,fn,owner) self.callbacks[event]={fn=fn,owner=owner} end
local function openPanel(frame)
    -- Native panel manager finishes its own positioning before broadcasting.
    frame.left,frame.top,frame.scale=18,800,1
    frame:Show()
    local callback=EventRegistry.callbacks['UIParentPanelManager.ShowUIPanel']
    if callback then callback.fn(callback.owner,frame) end
end
UIParent=CreateFrame('Frame','UIParent'); UIParent.width,UIParent.height,UIParent.scale=1920,1080,0.8
local function window(name)
    local f=CreateFrame('Frame',name,UIParent)
    f.TitleContainer=CreateFrame('Frame',nil,f); f.TitleContainer.title=true; f.TitleContainer.level=510
    return f
end
local character=window('CharacterFrame')
local bags=window('ContainerFrameCombinedBags')
local map=window('WorldMapFrame')
function map:IsMaximized() return self.maximized end
local blocked=window('ForbiddenWindow'); blocked.forbidden=true
local hud=window('EditSystem')
EditModeManagerFrame={registeredSystemFrames={hud}}
local third=window('ThirdPartyWindow')
local cyclic=window('CyclicWindow'); cyclic.parent=cyclic
UIPanelWindows={ForbiddenWindow={},EditSystem={},ThirdPartyWindow={},CyclicWindow={}}
ForeverWindowsDB={windows={CharacterFrame={scale=1.25,x=0.2,y=-0.1}}}
local nativeCount=#all
local ns={}
assert(loadfile('Interface/AddOns/ForeverWindows/Core.lua'))('ForeverWindows',ns)
local events=all[#all]
events:Fire('OnEvent','ADDON_LOADED','ForeverWindows')
local function tick(n) for i=1,n or 1 do events:Fire('OnUpdate',0.1) end end
local function near(a,b) assert(math.abs(a-b)<0.001,tostring(a)..' ~= '..tostring(b)) end
local function overlays()
    local result={}
    for _,f in ipairs(all) do if f.scripts.OnMouseWheel and f:IsVisible() then result[#result+1]=f end end
    return result
end
tick(2)
assert(events.scripts.OnUpdate and #overlays()==3,'all supported windows enabled by default')
near(character.scale,1.25); near(character.left*1.25,384)
SlashCmdList.FOREVERWINDOWS('off')
assert(ForeverWindowsDB.enabled==false,'off persists across reloads')
local inactiveWrites=character.writes
openPanel(character); tick(10)
assert(character.writes==inactiveWrites and #overlays()==0,'inactive opening callback does nothing')
SlashCmdList.FOREVERWINDOWS('test'); tick(2)
assert(#overlays()==1 and bags.writes==0,'Character-only isolation')
local grip=overlays()[1]
assert(grip.kind=='Button' and grip.clickEnabled and not grip.toplevel,'grip receives clicks within the window focus hierarchy')
assert(grip.clicks[1]=='LeftButtonDown' and grip.clicks[2]=='LeftButtonUp','both click edges registered')
character.TitleContainer.forbidden=true; tick(2)
assert(#overlays()==0,'inaccessible title must hide its stale overlay')
character.TitleContainer.forbidden=false; tick(2)
assert(overlays()[1]==grip,'title recovery reuses overlay')
assert(grip.parent==character and grip.ignoreParentScale and #character.TitleContainer.children==0,'grip follows owning window without inheriting its scale')
near(character.scale,1.25); near(character.left*1.25,384)
local stable=character.writes; tick(100); assert(character.writes==stable,'no repeated layout enforcement')
local gripWrites = grip.writes
tick(100)
assert(grip.writes == gripWrites, 'unchanged grip must not rewrite anchors')
down=false; grip:Fire('OnMouseDown','LeftButton'); grip:Fire('OnDragStart','LeftButton'); cx,cy=cx+100,cy-50; tick()
down=false; grip:Fire('OnMouseUp','LeftButton')
near(character.left*character.scale,484)
local stopped=character.writes
cx=cx+10; tick(); assert(character.writes==stopped,'mouse release must end drag')
grip:Fire('OnDragStart','LeftButton'); grip:Fire('OnDragStop'); cx=cx+10; tick()
assert(character.writes==stopped,'drag stop must end drag without physical button polling')
-- A tab raises an input layer independently from its title container.
-- Model top-level input ownership after clicking window contents. A root
-- sibling loses click routing even if its numerical frame level is higher.
local function inputRoot(frame)
    while frame.parent and frame.parent~=UIParent do frame=frame.parent end
    return frame
end
assert(inputRoot(grip)==inputRoot(character),'internal click focus and grip must share window root')
local tabLayer=CreateFrame('Frame',nil,character); tabLayer.level=800
mouseFoci={tabLayer}; tick()
assert(grip.level>tabLayer.level,'grip stays above focused content after tab switch')
mouseFoci={grip}; tick()
assert(grip.level>tabLayer.level,'grip keeps recovered stacking once it owns focus')
local beforeDrag=character.left
cx=cx+20; grip:Fire('OnMouseDown','LeftButton'); cx=cx+30; tick(); grip:Fire('OnMouseUp','LeftButton')
near(character.left*character.scale,beforeDrag*character.scale+30)
-- Put the tested layout back to the earlier coordinates for the remaining checks.
grip:Fire('OnMouseDown','LeftButton'); cx=cx-30; tick(); grip:Fire('OnMouseUp','LeftButton')
local foreign=CreateFrame('Frame',nil,UIParent); foreign.level=9000
mouseFoci={foreign,blocked}; tick()
assert(grip.level<foreign.level,'unrelated and forbidden input layers are ignored')
mouseFoci={}
local savedX=ForeverWindowsDB.windows.CharacterFrame.x
control=false; grip:Fire('OnMouseWheel',1); near(character.scale,1.25)
control=true; grip:Fire('OnMouseWheel',1); near(character.scale,1.30); tick(); near(grip:GetEffectiveScale(),UIParent:GetEffectiveScale())
near(character.left*character.scale,484)
for i=1,50 do grip:Fire('OnMouseWheel',1) end; near(character.scale,2)
for i=1,50 do grip:Fire('OnMouseWheel',-1) end; near(character.scale,0.5)
-- Close during a drag: no native methods or writes, and grip disappears.
down=true; grip:Fire('OnMouseDown','LeftButton')
character:Hide(); stable=character.writes; tick(100)
assert(character.writes==stable and #overlays()==0,'closing must not write to the window')
down=false; character.left=0; character.scale=1; character:Show(); tick(2)
near(character.scale,0.5)
near(character.left*character.scale,savedX*UIParent.width)
-- Reopening restores synchronously, with no tick/render in between.
character:Hide(); tick()
openPanel(character)
near(character.scale,0.5)
near(character.left*character.scale,savedX*UIParent.width)
stable=character.writes; tick(10)
assert(character.writes==stable,'opening event must not schedule a second restore')
-- Blizzard's panel manager re-anchors open panels (a tab changing a panel's
-- width, another panel opening or closing) and announces nothing afterwards.
local savedLeft,savedTop=character.left,character.top
character.left,character.top=18,800
events:Fire('OnUpdate',0.001)
near(character.left,savedLeft); near(character.top,savedTop)
character.left=18
local hideCallback=EventRegistry.callbacks['UIParentPanelManager.HideUIPanel']
hideCallback.fn(hideCallback.owner)
near(character.left,savedLeft)
character.scale=1; events:Fire('OnUpdate',0.001); near(character.scale,0.5)
stable=character.writes; for i=1,50 do events:Fire('OnUpdate',0.001) end
assert(character.writes==stable,'a window at its layout is never rewritten')
-- Another addon anchoring the window every frame: give up after three tries.
character.SetPoint=function(self) self.writes=self.writes+1 end
character.left=18; for i=1,20 do events:Fire('OnUpdate',0.001) end
assert(character.writes-stable<=6,'drift correction must not fight forever')
character.SetPoint=nil
character:Hide(); openPanel(character)
near(character.left,savedLeft)
combat=true; events:Fire('OnEvent','PLAYER_REGEN_DISABLED'); stable=character.writes; tick(10)
assert(#overlays()==0 and character.writes==stable,'combat is read-only')
assert(events.scripts.OnUpdate == nil, 'combat must detach polling')
combat=false; events:Fire('OnEvent','PLAYER_REGEN_ENABLED'); tick(2)
SlashCmdList.FOREVERWINDOWS('enable'); tick(2)
assert(#overlays()==3,'only Character, bag and map overlays, not forbidden/EditMode/third-party/cycle')
assert(#bags.TitleContainer.children==0 and #map.TitleContainer.children==0)
local bagRouter=CreateFrame('Button',nil,bags); bagRouter.level=1200
mouseFoci={}; tick(2)
local bagGrip
for _,g in ipairs(overlays()) do if g.parent==bags then bagGrip=g end end
assert(bagGrip and bagGrip.level>bagRouter.level,'bag grip is above native title click router before hovering')
assert(bagGrip.propagateClicks==false,'title clicks cannot pass through to bag menu')
local bagLeft=bags.left
bagGrip:Fire('OnMouseDown','LeftButton'); cx=cx+20; tick(); bagGrip:Fire('OnMouseUp','LeftButton')
near(bags.left,bagLeft+20)
assert(ForeverWindowsDB.enabled==true,'enable persists across reloads')
-- Windows the user never moved keep following Blizzard.
local mapWrites=map.writes; map.left=5; tick(3); events:Fire('OnUpdate',0.001)
assert(map.writes==mapWrites and map.left==5,'unmoved windows are never re-anchored')
-- Options window: preview, reset to Blizzard's place, undo.
local layouts=ns.Layouts(); table.sort(layouts)
assert(#layouts>=1 and layouts[1]=='CharacterFrame','options list moved windows')
local rl,rt,rw,rh=ns.SavedRect('CharacterFrame')
near(rl,ForeverWindowsDB.windows.CharacterFrame.x*UIParent.width); near(rw,400*character.scale)
local before={}; for k,v in pairs(ForeverWindowsDB.windows.CharacterFrame) do before[k]=v end
-- Reset must never call Blizzard's panel code (it taints gamepad focus state).
function UpdateUIPanelPositions() error('UpdateUIPanelPositions called from addon code') end
UIPanelWindows.CharacterFrame={}
local seen=ForeverWindowsDB.native.CharacterFrame
assert(seen and math.abs(seen.x*UIParent.width-18)<0.01 and seen.scale==1,'Blizzard spot recorded before restoring')
assert(ns.Reset('CharacterFrame')==true,'open panel goes to Blizzard spot at once')
assert(ForeverWindowsDB.windows.CharacterFrame==nil)
near(character.scale,1); near(character.left,18)
tick(5); events:Fire('OnUpdate',0.001); near(character.left,18)
ns.Undo('CharacterFrame',before)
near(character.scale,before.scale); near(character.left*character.scale,before.x*UIParent.width)
combat=true; assert(ns.Reset('CharacterFrame')==false,'combat reset only forgets the layout'); combat=false
assert(character.writes>0 and ForeverWindowsDB.windows.CharacterFrame==nil)
ns.Undo('CharacterFrame',before)
ForeverWindowsDB.native.CharacterFrame=nil
assert(ns.Reset('CharacterFrame')==false,'unknown Blizzard spot: back to native scale, spot on next open')
near(character.scale,1)
ForeverWindowsDB.native.CharacterFrame=seen
ns.Undo('CharacterFrame',before)
UIPanelWindows.CharacterFrame=nil; UpdateUIPanelPositions=nil
-- Direct-Show windows restore without waiting for either notification or tick.
ForeverWindowsDB.windows.ContainerFrameCombinedBags={scale=1.1,x=.3,y=-.2}
bags:Hide(); bags.left=0; bags.scale=1; bags:Show()
near(bags.scale,1.1); near(bags.left*bags.scale,.3*UIParent.width)
-- Load-on-demand windows are discovered before their first Show.
local guild=window('GuildFrame'); guild:Hide()
ForeverWindowsDB.windows.GuildFrame={scale=.9,x=.25,y=-.1}
events:Fire('OnEvent','ADDON_LOADED','Blizzard_GuildUI')
guild:Show(); near(guild.scale,.9); near(guild.left*guild.scale,.25*UIParent.width)
guild:Hide(); tick(2)
map.maximized=true; tick(2); assert(#overlays()==2)
map.maximized=false; tick(2); assert(#overlays()==3)
for _,f in ipairs({character,bags,map}) do
    f:Hide(); f.left=0
end
local total=character.writes+bags.writes+map.writes
tick(100)
assert(#overlays()==0 and total==character.writes+bags.writes+map.writes,'all close paths read-only')
assert(events.scripts.OnUpdate==nil,'no polling with all windows closed')
character:Show(); tick(2)
events:Fire('OnEvent','ADDON_ACTION_BLOCKED','ForeverWindows','ExampleBlockedFunction')
assert(ForeverWindowsDB.lastBlockedAction.action=='ExampleBlockedFunction')
assert(#overlays()==0,'blocked action suspends overlays')
assert(events.scripts.OnUpdate == nil, 'suspension must detach per-frame work')
stable=character.writes; tick(100); assert(character.writes==stable,'suspended addon must stay idle')
-- Merchant's inherited title can have unusable geometry: use its own top bar.
local merchant=window('MerchantFrame'); merchant:Hide()
merchant.width=336
merchant.TitleContainer.GetWidth=function() return 0 end
SlashCmdList.FOREVERWINDOWS('enable'); tick(2)
merchant:Show()
local merchantGrip
for _,g in ipairs(overlays()) do if math.abs(g.width-276)<.001 then merchantGrip=g end end
assert(merchantGrip,'merchant has explicit usable title hit area despite zero-width inherited title')
near(merchantGrip.left+merchantGrip.width,merchant.left+merchant.width)
merchant.CloseButton=CreateFrame('Button',nil,merchant)
tick(); near(merchantGrip.width,248)
merchant.CloseButton:Hide(); tick(); near(merchantGrip.width,276)
local mx=merchant.left
merchantGrip:Fire('OnMouseDown','LeftButton'); cx=cx+80; tick(); merchantGrip:Fire('OnMouseUp','LeftButton')
near(merchant.left,mx+80)
control=true; merchantGrip:Fire('OnMouseWheel',1); near(merchant.scale,1.05)
local merchantSaved=ForeverWindowsDB.windows.MerchantFrame.x
merchant:Hide(); openPanel(merchant)
near(merchant.scale,1.05); near(merchant.left*merchant.scale,merchantSaved*UIParent.width)
merchant:Hide(); tick(2)
local frameCount=#all
for i=1,5 do
    SlashCmdList.FOREVERWINDOWS('test'); tick(2)
    assert(#overlays()==1 and overlays()[1]==grip,'reactivation reuses original grip')
    SlashCmdList.FOREVERWINDOWS('off')
    assert(events.scripts.OnUpdate==nil and #overlays()==0,'off detaches work and hides overlays')
end
assert(#all==frameCount,'repeated toggles must not leak frames')
-- Gamepad UI: windows move by default; /fwm gamepad pauses; a blocked action
-- there pauses gamepad moving for the session only.
local gamepadUI=false
InputUtil={IsGamepadUIEnabled=function() return gamepadUI end}
local globalSecure=issecurevariable
issecurevariable=function(t,k)
    if t==_G then return globalSecure(t,k) end
    return k~="focusedFrame", k=="focusedFrame" and "SomeAddon" or nil
end
GamepadMode={FrameControlsManager={}}
SlashCmdList.FOREVERWINDOWS('enable'); tick(2)
assert(#overlays()==1,'keyboard UI keeps grips')
gamepadUI=true; events:Fire('OnEvent','INPUT_DEVICE_INTERFACE_TRANSITION',1,0); tick(2)
assert(#overlays()==1,'gamepad UI keeps grips by default')
character:Hide(); character.left,character.scale=0,1
openPanel(character)
near(character.scale,0.5); near(character.left*character.scale,ForeverWindowsDB.windows.CharacterFrame.x*UIParent.width)
SlashCmdList.FOREVERWINDOWS('gamepad'); tick(2)
assert(ForeverWindowsDB.gamepadPaused==true and #overlays()==0 and events.scripts.OnUpdate==nil,'/fwm gamepad pauses the gamepad UI')
character:Hide(); character.left,character.scale=0,1
stable=character.writes; openPanel(character); tick(10)
assert(character.writes==stable,'paused gamepad UI openings are read-only')
gamepadUI=false; events:Fire('OnEvent','INPUT_DEVICE_INTERFACE_TRANSITION',0,1); tick(2)
assert(#overlays()==1 and character.writes>stable,'keyboard UI still restores while gamepad is paused')
SlashCmdList.FOREVERWINDOWS('gamepad'); gamepadUI=true
events:Fire('OnEvent','INPUT_DEVICE_INTERFACE_TRANSITION',1,0); tick(2)
assert(ForeverWindowsDB.gamepadPaused==nil and #overlays()==1,'/fwm gamepad resumes')
events:Fire('OnEvent','ADDON_ACTION_FORBIDDEN','ForeverWindows','SetPreferredGamepadInteractTarget()')
local report=ForeverWindowsDB.lastBlockedAction
assert(report.gamepad==true and ForeverWindowsDB.enabled==true,'gamepad block keeps the addon enabled')
assert(#overlays()==0 and ForeverWindowsDB.gamepadPaused==nil,'gamepad block pauses this session only')
local sawTaint
for _,line in ipairs(report.taint) do if line=='frames.focusedFrame: tainted by SomeAddon' then sawTaint=true end end
assert(sawTaint,'report names tainted gamepad state and its owner')
-- 1.3.3: list entries are checked, a summary counts them, /fwm taint is saved,
-- and other addons' blocks and gamepad navigation errors are saved once.
local listed=CreateFrame('Frame','ListedWindow')
GamepadMode.FrameControlsManager.shownFrames={character,listed}
issecurevariable=function(t,k)
    if t==_G then return globalSecure(t,k) end
    if t==GamepadMode.FrameControlsManager.shownFrames and k==2 then return false,'FrameGambit' end
    return k~="focusedFrame", k=="focusedFrame" and "SomeAddon" or nil
end
SlashCmdList.FOREVERWINDOWS('taint')
local sawEntry, summary
for _,line in ipairs(ForeverWindowsDB.lastTaintCheck.taint) do
    if line=='frames.shownFrames[2]: tainted by FrameGambit' then sawEntry=true end
    if line:find('checked values',1,true) then summary=line end
end
assert(sawEntry,'taint check reads list entries')
assert(summary and summary:match('^2 of %d+ checked values are tainted$'),'summary counts tainted values')
events:Fire('OnEvent','ADDON_ACTION_FORBIDDEN','FrameGambit','SetPreferredGamepadInteractTarget()')
events:Fire('OnEvent','ADDON_ACTION_FORBIDDEN','FrameGambit','SetPreferredGamepadInteractTarget()')
local reports=ForeverWindowsDB.gamepadReports
assert(#reports==1 and reports[1].addon=='FrameGambit' and reports[1].action=='SetPreferredGamepadInteractTarget()','first block of another addon in the gamepad UI is saved once')
assert(ForeverWindowsDB.enabled==true and ForeverWindowsDB.lastBlockedAction==report,"another addon's block changes nothing else")
BugGrabber={GetErrorByID=function() return {message='SmartNavigation.lua:832: calling Hide on bad self'} end}
EventRegistry.callbacks['BugGrabber.BugGrabbed'].fn(nil,'table: 1')
EventRegistry.callbacks['BugGrabber.BugGrabbed'].fn(nil,'table: 2')
assert(#reports==2 and reports[2].error:find('SmartNavigation',1,true),'first gamepad navigation error is saved once')
BugGrabber=nil; GamepadMode.FrameControlsManager.shownFrames=nil
gamepadUI=false; events:Fire('OnEvent','INPUT_DEVICE_INTERFACE_TRANSITION',0,1); tick(2)
assert(#overlays()==1,'keyboard UI unaffected by the session pause')
gamepadUI=false; InputUtil=nil; issecurevariable=globalSecure; GamepadMode=nil
SlashCmdList.FOREVERWINDOWS('enable')
SlashCmdList.FOREVERWINDOWS('test')
assert(ForeverWindowsDB.enabled==true,'session-only test mode must not disable future logins')
SlashCmdList.FOREVERWINDOWS('off')
assert(next(character.scripts)==nil and character.SetPoint==F.SetPoint,'native scripts and methods unchanged')
print('PASS: panel-manager drift correction, unmoved windows untouched, reset/undo, automatic startup, direct-Show and lazy-window instant restore, persistent enable/off, inactive behavior, Character isolation, window-owned grips, drag/scale/persistence, no idle or close writes, combat, forbidden/EditMode/cycle exclusions, map mode, auto-suspension, gamepad UI default, pause/resume and session-only block pause')
