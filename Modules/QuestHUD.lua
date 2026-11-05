local _, FC = ...
local HUD={status="Blizzard tracker in use."}
FC.QuestHUD=HUD
local Route,Guide,UI=FC.QuestRoute,FC.QuestGuide,FC.UI
local GOLD,TEXT,DIM,GREEN={1,.82,.43},{1,.94,.83},{.82,.77,.66},{.70,.85,.55}
local hud,panel,hiddenNative,nextRefresh,message,messageUntil=nil,nil,nil,0,nil,0
local folded={route={},nearby={}}

local function read(fn,...)
    local status,result=FC.SafeRead(fn,...)
    if status=="ready" then return result,true end
end

local function inGameRule(key)
    local rule=Enum and Enum.GameRule and Enum.GameRule[key]
    return rule and read(C_GameRules and C_GameRules.IsGameRuleActive,rule)==true
end

local function enabledReplacement()
    return FC.IsEnabled("quests") and FC.Store.root.settings.questReplacement==true
end

local function notify(ok,reason)
    if not ok and reason then message,messageUntil=reason,GetTime()+5 end
end

local function setReplacement(enabled)
    if not FC.Store.CanWrite() then return false,"Saved data is read-only." end
    FC.Store.root.settings.questReplacement=enabled
    nextRefresh=0
    return true
end

local function atlas(texture,name)
    if read(C_Texture and C_Texture.GetAtlasInfo,name) then texture:SetAtlas(name); return true end
end

local function font(parent,size,color)
    local native=size=="title" and ObjectiveTrackerHeaderFont or ObjectiveTrackerLineFont
    local fs=parent:CreateFontString(nil,"OVERLAY",size=="title" and "GameFontNormal" or "GameFontHighlightSmall")
    if native and size~="small" then fs:SetFontObject(native) end
    fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP")
    fs:SetTextColor(unpack(color))
    return fs
end

local function button(parent,text,action)
    local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate")
    b:SetSize(80,21); b:SetText(text)
    b:SetScript("OnClick",function(self)
        local status,err=pcall(action,self)
        if not status then FC.RecordDiagnostic("Quest Helper action",err); notify(false,"Action unavailable.") end
        nextRefresh=0
    end)
    return b
end

local function showParty()
    UI.Open("party")
end

local function setView(view)
    Route.SetView(view)
    if hud then hud.resetScroll=true end
    if panel then panel.resetScroll=true end
end

local function makeView(parent,isHUD)
    local f=CreateFrame("Frame",isHUD and "ForeverCompanionQuestHUD" or nil,parent,"BackdropTemplate")
    f:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8",edgeFile="Interface/Tooltips/UI-Tooltip-Border",edgeSize=12,
        insets={left=3,right=3,top=3,bottom=3}})
    f:SetBackdropColor(.073,.055,.035,.86)
    f:SetBackdropBorderColor(.56,.43,.25,.94)
    f:SetClampedToScreen(isHUD)
    local header=f:CreateTexture(nil,"BACKGROUND",nil,1)
    header:SetPoint("TOPLEFT",4,-4); header:SetPoint("TOPRIGHT",-4,-4); header:SetHeight(30)
    if not atlas(header,"ui-questtracker-primary-objective-header") then header:SetColorTexture(.25,.16,.08,.9) end
    f.title=font(f,"title",GOLD)
    f.title:SetPoint("TOPLEFT",12,-11); f.title:SetText(isHUD and "Objectives" or "Quest Route")
    if isHUD then
        f.restore=button(f,"Blizzard",function() notify(setReplacement(false)); FC.Refresh("quests") end)
        f.restore:SetSize(65,20); f.restore:SetPoint("TOPRIGHT",-35,-8)
        f.restore:SetScript("OnEnter",function(self)
            GameTooltip:SetOwner(self,"ANCHOR_LEFT"); GameTooltip:SetText("Use Blizzard Tracker"); GameTooltip:Show()
        end)
        f.restore:SetScript("OnLeave",function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
        f.collapse=button(f,"-",function(self)
            f.collapsed=not f.collapsed
            self:SetText(f.collapsed and "+" or "-")
        end)
        f.collapse:SetSize(23,20); f.collapse:SetPoint("TOPRIGHT",-9,-8)
    end
    f.route=button(f,"Route",function() setView("route") end)
    f.nearby=button(f,"Nearby",function() setView("nearby") end)
    f.route:SetPoint("TOPLEFT",10,-37); f.nearby:SetPoint("LEFT",f.route,"RIGHT",5,0)
    f.context=font(f,"small",DIM); f.context:SetPoint("TOPLEFT",12,-64)
    f.context:SetWordWrap(false)
    f.scroll=CreateFrame("ScrollFrame",nil,f,"UIPanelScrollFrameTemplate")
    f.scroll:SetPoint("TOPLEFT",8,-84); f.scroll:SetPoint("BOTTOMRIGHT",-26,46)
    f.scroll:EnableMouseWheel(true)
    f.list=CreateFrame("Frame",nil,f.scroll); f.list:SetSize(1,1); f.scroll:SetScrollChild(f.list)
    f.pool={}
    f.footer=font(f,"small",DIM)
    f.footer:SetPoint("BOTTOMLEFT",12,9)
    f.footer:SetWordWrap(false)
    f.party=button(f,"Adventure Together",showParty)
    f.party:SetSize(133,18); f.party:SetPoint("BOTTOMLEFT",9,24)
    f.summary=font(f,"small",GREEN); f.summary:SetPoint("LEFT",f.party,"RIGHT",6,0)
    f.summary:SetWordWrap(false)
    f:Hide()
    return f
end

local function rowWidget(view,index)
    local row=view.pool[index]
    if row then return row end
    row=CreateFrame("Frame",nil,view.list)
    row.bg=row:CreateTexture(nil,"BACKGROUND"); row.bg:SetAllPoints()
    row.line=row:CreateTexture(nil,"BORDER"); row.line:SetPoint("BOTTOMLEFT"); row.line:SetPoint("BOTTOMRIGHT"); row.line:SetHeight(1)
    row.line:SetColorTexture(.43,.33,.20,.58)
    row.main=CreateFrame("Button",nil,row); row.main:SetPoint("TOPLEFT",5,-4); row.main:SetHeight(19)
    row.main:SetPoint("TOPRIGHT",-5,-4)
    row.main:SetHighlightTexture("Interface/QuestFrame/UI-QuestTitleHighlight","ADD")
    row.label=font(row.main,"line",TEXT); row.label:SetPoint("TOPLEFT"); row.label:SetPoint("TOPRIGHT")
    row.body=font(row,"small",DIM); row.body:SetPoint("TOPLEFT",16,-24)
    row.main:SetScript("OnClick",function()
        local ok,err=pcall(function() if row.data.action then row.data.action() end end)
        if not ok then FC.RecordDiagnostic("Quest Helper row",err) end
        nextRefresh=0
    end)
    row.side=button(row,"Track",function() if row.data.sideAction then row.data.sideAction() end end)
    row.side:SetSize(48,19); row.side:SetPoint("TOPRIGHT",-4,-4)
    view.pool[index]=row
    return row
end

local function layout(view,rows)
    local width=math.max(180,view:GetWidth()-34)
    local signature={width}
    for i,d in ipairs(rows) do
        signature[#signature+1]=table.concat({d.kind,d.title,d.body or "",d.side or "",d.active and "1" or "0",
            d.action and "1" or "0",d.sideAction and "1" or "0"},"\001")
        if view.pool[i] then view.pool[i].data=d end
    end
    signature=table.concat(signature,"\002")
    if view.signature==signature and not view.resetScroll then return end
    view.signature=signature
    local scroll=view.resetScroll and 0 or view.scroll:GetVerticalScroll()
    view.resetScroll=false
    local y=0
    view.list:SetWidth(width)
    for i,d in ipairs(rows) do
        local row=rowWidget(view,i)
        row.data=d
        row:ClearAllPoints(); row:SetPoint("TOPLEFT",0,-y); row:SetWidth(width)
        row.bg:SetColorTexture(.40,.24,.08,d.active and .48 or (d.kind=="heading" and .30 or 0))
        row.line:SetShown(d.kind=="heading" or d.active==true)
        row.side:SetShown(d.side~=nil); row.side:SetText(d.side or "")
        row.main:SetEnabled(d.action~=nil)
        row.main:SetPoint("TOPRIGHT",d.side and -58 or -5,-4)
        row.label:SetText(d.title)
        local color=d.kind=="hint" and DIM or GOLD
        row.label:SetTextColor(unpack(color))
        local titleHeight=math.max(14,row.label:GetStringHeight())
        row.main:SetHeight(titleHeight+2)
        row.body:SetPoint("TOPLEFT",d.kind=="hint" and 5 or 16,-(titleHeight+8))
        row.body:SetWidth(width-21)
        row.body:SetText(d.body or ""); row.body:SetShown(d.body~=nil)
        local height=math.max(d.side and 27 or 24,titleHeight+(d.body and row.body:GetStringHeight()+13 or 9))
        row:SetHeight(height)
        row:Show(); y=y+height+2
    end
    for i=#rows+1,#view.pool do view.pool[i]:Hide() end
    view.list:SetHeight(math.max(1,y))
    view.scroll:UpdateScrollChildRect()
    view.scroll:SetVerticalScroll(math.min(scroll,view.scroll:GetVerticalScrollRange()))
end

local function estimate(row)
    return row.distance and ("  ·  "..((row.point and row.point.approximate) and "~" or "")..math.floor(row.distance+.5).." yd") or ""
end

local function heading(rows,group,defaultOpen,side,callback)
    local state=folded[Route.view]
    local open=state[group.key]
    if open==nil then open=defaultOpen end
    rows[#rows+1]={kind="heading",title=(open and "-  " or "+  ")..group.label.."  ("..#group.rows..")",
        side=side,sideAction=callback,action=function() state[group.key]=not open end}
    return open
end

local function sessionNow()
    local s=FC.IsEnabled("party") and FC.Adventure.sharing and FC.Adventure.shared
    if not s or s.phase=="syncing" then return end
    local status,party=FC.API.Party()
    if status=="ready" and FC.API.SameGroup(s.context,party) then return s,party end
end

local function routeRows(party)
    local out={}
    local state=({waiting="Waiting for reliable quest progress or locations.",finished="Area objectives complete. Pick another section to continue.",
        ["no-distance"]="Distance unavailable. Choose a quest to focus it."})[Route.state]
    if state then out[#out+1]={kind="hint",title=state} end
    if not FC.Quests.membershipComplete then
        out[#out+1]={kind="hint",title="Quest log may be incomplete.",body="Expand any collapsed quest log sections."}
    end
    for i,group in ipairs(Route.sections) do
        local key=group.key
        local active=key==Route.area
        local trackable=key~="turnin" and key~="instance" and key~="unknown"
        local action
        if trackable then action=function()
            if Route.area==key then Route.Stop(); Guide.Stop()
            else Route.Track(key); Guide.Resume(); folded.route[key]=true end
        end end
        if heading(out,group,active or i==1 or key=="turnin",trackable and (active and "Stop" or "Track") or nil,action) then
            for _,row in ipairs(group.rows) do
                local record,id=row.record,row.id
                local target=active and Route.target==id and Route.state=="tracking"
                local body={}
                if not record.observed then body[#body+1]="Quest progress unavailable."
                elseif record.status=="C" then body[#body+1]="Ready for turn-in"
                elseif record.status=="F" then body[#body+1]="Failed"
                else
                    if target then body[#body+1]="Tracking"..estimate(row) end
                    for _,objective in ipairs(record.objectives) do
                        if target or not objective.finished then
                            body[#body+1]=(objective.finished and "Done: " or "- ")..objective.text
                            if not target and #body>=2 then break end
                        end
                    end
                end
                if not target and row.distance then body[#body+1]=estimate(row):gsub("^  ·  ","") end
                if party then
                    local summary=FC.Quests.GroupSummary(id,party)
                    if summary then body[#body+1]="Party: "..summary.text end
                end
                local side,sideAction
                if record.status=="C" and row.point then
                    local point=row.point
                    side,sideAction="Map",function() notify(Guide.ShowPoint(point)) end
                elseif trackable and record.observed and record.status=="A" and not target then
                    side,sideAction="Focus",function() Route.Track(key,id); Guide.Resume() end
                end
                out[#out+1]={kind="quest",title=(target and "> " or (record.status=="C" and "? " or ""))..record.title,
                    body=#body>0 and table.concat(body,"\n") or nil,active=target,side=side,sideAction=sideAction,
                    action=function() notify(Guide.ShowDetails(id)) end}
            end
        end
    end
    if #Route.sections==0 and FC.Quests.membershipComplete then
        out[#out+1]={kind="hint",title="No active quests.",body="Open Nearby to find quests you can pick up."}
    end
    return out
end

local function pickupRows()
    local out={{kind="hint",title="Quest pickups",body=Route.nearbyStatus or "Reading nearby offers…"}}
    for i,stop in ipairs(Route.nearby) do
        if heading(out,stop,i<=3) then
            for _,row in ipairs(stop.rows) do
                local point=row.point
                local body=(row.confirmed and "Confirmed offer" or "Likely available")..estimate(row)
                if row.workLabel then body=body.."\n"..(row.bundle and "Quest bundle: " or "Adds to: ")..row.workLabel end
                out[#out+1]={kind="quest",title="! "..row.title,body=body,action=point and function() notify(Guide.ShowPoint(point)) end or nil}
            end
        end
    end
    return out
end

local function paint(view,rows,summary,footer,context)
    local collapsed=view.collapsed
    if view==hud then
        local height=math.min(470,math.max(255,UIParent:GetHeight()-255))
        view:SetHeight(collapsed and 38 or height)
    end
    view.route:SetShown(not collapsed); view.nearby:SetShown(not collapsed)
    view.context:SetShown(not collapsed); view.scroll:SetShown(not collapsed)
    view.party:SetShown(not collapsed and FC.IsEnabled("party"))
    view.summary:SetShown(not collapsed and summary~=nil)
    view.footer:SetShown(not collapsed)
    if collapsed then return end
    view.route:SetEnabled(Route.view~="route"); view.nearby:SetEnabled(Route.view~="nearby")
    view.context:SetWidth(view:GetWidth()-24); view.footer:SetWidth(view:GetWidth()-24)
    view.summary:SetWidth(view:GetWidth()-158)
    view.context:SetText(context); view.footer:SetText(footer); view.summary:SetText(summary or "")
    layout(view,rows)
end

local function repaint()
    local showHUD=hud and hud:IsShown()
    local showPanel=panel and panel:IsVisible()
    if not showHUD and not showPanel then return end
    local session,party=sessionNow()
    local rows=Route.view=="route" and routeRows(party) or pickupRows()
    local summary
    if session then
        local mine=session.members[party.selfName]
        local ready=0
        for _,task in ipairs(session.tasks) do if mine and mine[task.id]==true then ready=ready+1 end end
        summary=(session.title or "Shared adventure").." · "..ready.."/"..#session.tasks.." ready (you)"
    end
    local count,limit=FC.Quests.count,read(C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept)
    local context=Route.mapLabel or "Current area"
    if count then context=context.."  ·  "..count..(FC.Number(limit,1,1000) and "/"..limit or "").." in quest log" end
    local footer=(GetTime()<messageUntil and message) or (FC.IsCombat() and "Quest and map updates resume after combat.") or Guide.Status()
        or (Route.view=="nearby" and "Select a pickup to show it on the map." or "Select an area to track its nearest quest.")
    if showHUD then paint(hud,rows,summary,footer,context) end
    if showPanel then paint(panel,rows,summary,footer,context) end
end

local function protectedActivity(native)
    local combat=FC.IsCombat()
    if combat then return "Combat in progress." end
    if inGameRule("ObjectiveTrackerDisabled") then return "The game disabled the tracker here." end
    local instance,known=read(IsInInstance)
    if not known or instance then return "Blizzard tracker in use for this instance." end
    if EditModeManagerFrame and read(EditModeManagerFrame.IsEditModeActive,EditModeManagerFrame)==true then
        return "Blizzard tracker in use in Edit Mode."
    end
    if InputUtil and read(InputUtil.IsGamepadUIEnabled)==true then return "Blizzard tracker in use for controller navigation." end
    if not native or type(native.ForEachModule)~="function" or type(native.Update)~="function" then
        return "The Blizzard tracker is not ready."
    end
    local protected,checked=read(native.IsProtected,native)
    if not checked or protected then return "The client has protected the Blizzard tracker." end
    if not FC.Quests.membershipComplete then return "Quest log incomplete. Expand collapsed quest log sections." end
    for _,record in pairs(FC.Quests.records) do
        if record.specialItem~=false or record.specialAction or record.isTask or (record.autoComplete and record.status=="C") then
            return "Blizzard tracker in use for a quest item or special quest action."
        end
    end
    local popups=read(GetNumAutoQuestPopUps)
    if FC.Number(popups,1,1000) then return "Blizzard tracker in use for a quest pop-up." end
    local unsupported=false
    local status=FC.SafeRead(native.ForEachModule,native,function(module)
        if module~=QuestObjectiveTracker and module~=CampaignQuestObjectiveTracker then
            local has,ok=read(module.HasContents,module)
            local truncated=read(module.IsTruncated,module)
            if not ok or has or truncated then unsupported=true end
        end
    end)
    if status~="ready" or unsupported then return "Blizzard tracker in use for other objectives." end
end

local function restoreNative()
    if not hiddenNative then return true end
    if FC.IsCombat() then return false end
    local native=hiddenNative
    if not inGameRule("ObjectiveTrackerDisabled") then
        local status=FC.SafeRead(native.Update,native,false)
        if status~="ready" then status=FC.SafeRead(native.Show,native) end
        if status~="ready" then return false end
    end
    hiddenNative=nil
    return true
end

local function alignHUD(native)
    if read(native.IsShown,native)~=true then return end
    local right,top=read(native.GetRight,native),read(native.GetTop,native)
    local scale,parentScale=read(native.GetEffectiveScale,native),read(UIParent.GetEffectiveScale,UIParent)
    if type(right)~="number" or type(top)~="number" or type(scale)~="number" or type(parentScale)~="number"
        or parentScale<=0 then return end
    local x=right*scale/parentScale-UIParent:GetWidth()
    local y=top*scale/parentScale-UIParent:GetHeight()
    if x==x and y==y and x<=0 and x>=-UIParent:GetWidth() and y<=0 and y>=-UIParent:GetHeight() then
        hud:ClearAllPoints()
        hud:SetPoint("TOPRIGHT",UIParent,"TOPRIGHT",x,y)
    end
end

local function syncVisibility()
    local native=ObjectiveTrackerFrame
    if FC.IsCombat() then
        if hud and (read(native and native.IsShown,native)==true or (not enabledReplacement() and not hiddenNative)) then hud:Hide() end
        return "Tracker changes resume after combat."
    end
    local reason=enabledReplacement() and protectedActivity(native) or nil
    if not enabledReplacement() then reason="Blizzard tracker in use." end
    if reason then
        if not restoreNative() then return "Waiting for Blizzard's tracker to restore." end
        if hud then hud:Hide() end
        return reason
    end
    if not hud then
        hud=makeView(UIParent,true)
        hud:SetWidth(322)
        hud:SetPoint("TOPRIGHT",UIParent,"TOPRIGHT",-38,-231)
    end
    alignHUD(native)
    hud:Show()
    if read(native.IsShown,native)==true then
        hiddenNative=native
        local status=FC.SafeRead(native.Hide,native)
        if status~="ready" or read(native.IsShown,native)~=false then
            if restoreNative() then hud:Hide() end
            return "The client kept Blizzard's tracker visible."
        end
    end
    return "Quest Helper is replacing the Blizzard tracker."
end

function HUD.Status() return HUD.status end

function HUD.Tick()
    local running=FC.IsEnabled("quests")
    if not running and not hiddenNative and not Guide.HasPending() then return end
    local now=GetTime()
    if now<nextRefresh then return end
    nextRefresh=now+.65
    local previous=HUD.status
    local status,result=pcall(function()
        if running and not FC.IsCombat() then
            if FC.QuestData then FC.QuestData.Tick() end
            Route.Tick()
            if Route.state~="waiting" then Guide.Tick(Route.Target()) end
        elseif not running then Guide.Stop() end
        local result=syncVisibility()
        if running then repaint() end
        return result
    end)
    if not status then
        FC.RecordDiagnostic("Quest Helper",result)
        if restoreNative() and hud then hud:Hide() end
        result="Quest Helper paused after a client error. See /fc diagnostics."
        nextRefresh=now+3
    end
    HUD.status=result
    if previous~=result then FC.Refresh("quests") end
end

function HUD.HidePanel() if panel then panel:Hide() end end

function HUD.Render(parent)
    UI.Label(parent,"Quest Helper",0,0,730,true)
    UI.Label(parent,HUD.status,0,25,730)
    UI.Check(parent,"Preview Quest Helper in place of the Blizzard Objective Tracker",0,48,enabledReplacement(),function(enabled)
        UI.Result(setReplacement(enabled))
    end,FC.Store.CanWrite())
    if not panel then
        panel=makeView(parent,false)
        panel:SetPoint("TOPLEFT",0,-85)
        panel:SetSize(730,365)
    end
    panel:Show()
    UI.Height(465)
    repaint()
end

local locationEvents={QUEST_LOG_UPDATE=true,QUEST_ACCEPTED=true,QUEST_REMOVED=true,QUEST_TURNED_IN=true,QUEST_DATA_LOAD_RESULT=true,
    PLAYER_ENTERING_WORLD=true,ZONE_CHANGED=true,ZONE_CHANGED_INDOORS=true,ZONE_CHANGED_NEW_AREA=true,QUEST_POI_UPDATE=true,
    SUPER_TRACKING_PATH_UPDATED=true,PLAYER_REGEN_ENABLED=true}
local function onEvent(event,...)
    if FC.QuestData then FC.QuestData.OnEvent(event,...) end
    if locationEvents[event] then Route.dirty=true end
    if event=="SUPER_TRACKING_CHANGED" or event=="USER_WAYPOINT_UPDATED" or event=="PLAYER_REGEN_ENABLED" then
        Guide.Invalidate()
    end
    if locationEvents[event] or event=="PLAYER_REGEN_DISABLED" or event=="GAME_PAD_ACTIVE_CHANGED" then nextRefresh=0 end
end

local function enable()
    FC.Quests.SyncEnabled()
    Route.Enable()
    nextRefresh=0
end

local function disable()
    FC.Quests.SyncEnabled()
    Route.Stop(true)
    if FC.QuestData then FC.QuestData.Reset() end
    Guide.Stop()
    HUD.HidePanel()
    restoreNative()
    if hud and not hiddenNative then hud:Hide() end
    HUD.status=hiddenNative and "Tracker changes resume after combat." or "Blizzard tracker in use."
end

FC.RegisterModule("quests",{title="Quest Helper",Render=HUD.Render,Enable=enable,Disable=disable,OnEvent=onEvent})
