local _, FC = ...
local HUD={}
FC.QuestHUD=HUD
local Route,Guide,UI=FC.QuestRoute,FC.QuestGuide,FC.UI
local GOLD,TEXT,DIM,GREEN={1,.82,.43},{1,.94,.83},{.82,.77,.66},{.70,.85,.55}
local panel,launcher,trackerBar,ownedScroll,searchSizing
local nextRefresh,message,messageUntil=0,nil,0
local closeLog,openedThisVisit
local folded={route={},nearby={}}

local function read(fn,...)
    local status,result=FC.SafeRead(fn,...)
    if status=="ready" then return result,true end
end

local function notify(ok,reason)
    if not ok and reason then message,messageUntil=reason,GetTime()+5 end
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
    if panel then panel.resetScroll=true end
end

local function makeView(parent)
    local f=CreateFrame("Frame",nil,parent,"BackdropTemplate")
    f:SetBackdrop({bgFile="Interface/Buttons/WHITE8X8",edgeFile="Interface/Tooltips/UI-Tooltip-Border",edgeSize=12,
        insets={left=3,right=3,top=3,bottom=3}})
    f:SetBackdropColor(.073,.055,.035,1)
    f:SetBackdropBorderColor(.56,.43,.25,.94)
    f:EnableMouse(true)
    local header=f:CreateTexture(nil,"BACKGROUND",nil,1)
    header:SetPoint("TOPLEFT",4,-4); header:SetPoint("TOPRIGHT",-4,-4); header:SetHeight(30)
    if not atlas(header,"ui-questtracker-primary-objective-header") then header:SetColorTexture(.25,.16,.08,.9) end
    f.title=font(f,"title",GOLD)
    f.title:SetPoint("TOPLEFT",12,-11); f.title:SetText("Quest Helper")
    f.back=button(f,"Quest Log",function()
        openedThisVisit=true
        closeLog()
    end)
    f.back:SetSize(80,20); f.back:SetPoint("TOPRIGHT",-9,-8)
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
                local title=record.level and record.level>0 and ("["..record.level.."] "..record.title) or record.title
                out[#out+1]={kind="quest",title=(target and "> " or (record.status=="C" and "? " or ""))..title,
                    body=#body>0 and table.concat(body,"\n") or nil,active=target,side=side,sideAction=sideAction,
                    action=function()
                        if not FC.IsCombat() then closeLog() end
                        notify(Guide.ShowDetails(id))
                    end}
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
    view.party:SetShown(FC.IsEnabled("party"))
    view.summary:SetShown(summary~=nil)
    view.route:SetEnabled(Route.view~="route"); view.nearby:SetEnabled(Route.view~="nearby")
    view.context:SetWidth(view:GetWidth()-24); view.footer:SetWidth(view:GetWidth()-24)
    view.summary:SetWidth(view:GetWidth()-158)
    view.context:SetText(context); view.footer:SetText(footer); view.summary:SetText(summary or "")
    layout(view,rows)
end

local function repaint()
    if not panel or not panel:IsVisible() then return end
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
    paint(panel,rows,summary,footer,context)
end

local function gamepad()
    return InputUtil and read(InputUtil.IsGamepadUIEnabled)==true
end

local function restoreSearch()
    if not searchSizing then return end
    local search=searchSizing
    searchSizing=nil
    if search.box:GetWidth()==search.applied then search.box:SetWidth(search.original) end
end

local function logFrames()
    local log=QuestMapFrame
    local quests=log and log.QuestsFrame
    return log,quests,quests and quests.ScrollFrame,log and log.DetailsFrame
end

local closePending,menuHooked,observedLog

closeLog=function()
    if not ownedScroll then return true end
    if FC.IsCombat() then closePending=true; return false end
    local scroll=ownedScroll
    local _,_,current,details=logFrames()
    if scroll==current and not (details and details:IsShown()) and not scroll:IsShown() then
        local status=FC.SafeRead(scroll.Show,scroll)
        if status~="ready" and not scroll:IsShown() then closePending=true; return false end
    end
    ownedScroll,closePending=nil,nil
    if panel then panel:Hide() end
    nextRefresh=0
    return true
end

local function showLogPane(quests,scroll)
    openedThisVisit=true
    if not panel then
        panel=makeView(quests)
        panel:SetPoint("TOPLEFT",scroll,"TOPLEFT",-1,25)
        panel:SetPoint("BOTTOMRIGHT",scroll,"BOTTOMRIGHT",17,1)
        panel:SetFrameLevel(scroll:GetFrameLevel()+5)
    end
    if not ownedScroll then
        restoreSearch()
        if launcher then launcher:Hide() end
        ownedScroll=scroll
        if FC.SafeRead(scroll.Hide,scroll)~="ready" or scroll:IsShown() then
            closeLog()
            return false,"The quest log kept its quest list visible."
        end
    end
    panel:Show()
    nextRefresh=0
    return true
end

function HUD.OpenLog(view)
    if not FC.IsEnabled("quests") or FC.IsCombat() or gamepad() then
        return false,"Quest Helper is unavailable here."
    end
    local log,quests,scroll,details=logFrames()
    if not log or not log:IsVisible() then
        FC.SafeRead(OpenQuestLog)
        log,quests,scroll,details=logFrames()
    end
    if not log or not log:IsVisible() or not quests or not scroll then
        return false,"Open the Quest and Map Log to use Quest Helper."
    end
    if not quests:IsShown() and QuestLogDisplayMode then
        FC.SafeRead(log.SetDisplayMode,log,QuestLogDisplayMode.Quests)
    end
    if details and details:IsShown() then FC.SafeRead(QuestMapFrame_CloseQuestDetails) end
    if not quests:IsVisible() or (not ownedScroll and not scroll:IsVisible()) then
        return false,"Open the Quests tab to use Quest Helper."
    end
    if view then setView(view) end
    local ok,reason=showLogPane(quests,scroll)
    if ok and UI.window and UI.window:IsShown() then UI.window:Hide() end
    return ok,reason
end

local function syncLog(running)
    local log,quests,scroll,details=logFrames()
    local visibleLog=log and log:IsVisible()
    if not running or not visibleLog then openedThisVisit=nil end
    if running and log and observedLog~=log and not FC.IsCombat() then
        log:HookScript("OnHide",function()
            openedThisVisit=nil
            nextRefresh=0
        end)
        log:HookScript("OnShow",function() nextRefresh=0 end)
        observedLog=log
    end
    if ownedScroll then
        local detailsShown=details and details:IsShown()
        if not running or closePending or not quests or not quests:IsVisible()
            or gamepad() or detailsShown or ownedScroll:IsShown() then
            if panel and (detailsShown or ownedScroll:IsShown()) then panel:Hide() end
            closeLog()
        end
    end
    if FC.IsCombat() then return end
    -- Native quest details and other map tabs keep their normal navigation.
    -- Returning to the stock list is respected until the pane closes.
    if running and visibleLog and not openedThisVisit and quests and quests:IsVisible() then
        if details and details:IsShown() then
            openedThisVisit=true
        elseif not gamepad() and scroll and scroll:IsVisible() and not ownedScroll then
            local ok=showLogPane(quests,scroll)
            if ok then return end
        end
    end
    if running and not menuHooked and Menu and type(Menu.ModifyMenu)=="function" then
        Menu.ModifyMenu("MENU_QUEST_MAP_FRAME_SETTINGS",function(_,root)
            if FC.IsEnabled("quests") and not gamepad() and not FC.IsCombat() then
                root:CreateButton("Quest Helper",function() notify(HUD.OpenLog()) end)
            end
        end)
        menuHooked=true
    end
    local search=scroll and scroll.SearchBox
    local visible=running and not gamepad() and log and log:IsVisible() and search and search:IsVisible()
        and not (QuestLogCount and QuestLogCount:IsVisible()) and not ownedScroll
    if not visible then
        if launcher then launcher:Hide() end
        restoreSearch()
        return
    end
    local width=search:GetWidth()
    if not searchSizing or searchSizing.box~=search or width~=searchSizing.applied then
        restoreSearch()
        if width<185 then if launcher then launcher:Hide() end; return end
        searchSizing={box=search,original=width,applied=width-102}
        search:SetWidth(searchSizing.applied)
        if math.abs(search:GetWidth()-searchSizing.applied)>.5 then
            search:SetWidth(width)
            searchSizing=nil
            if launcher then launcher:Hide() end
            return
        end
    end
    if not launcher then
        launcher=button(scroll,"Quest Helper",function() notify(HUD.OpenLog()) end)
        launcher:SetSize(98,20)
        launcher:SetPoint("LEFT",search,"RIGHT",4,0)
    end
    launcher:Show()
end

local function chooseArea(button)
    if FC.IsCombat() or not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(button,function(_,root)
        root:CreateTitle("Track a quest area")
        if Route.area then
            root:CreateButton("Stop route",function() Route.Stop(); Guide.Stop(); nextRefresh=0 end)
        end
        for _,group in ipairs(Route.sections) do
            if group.mapID then
                local key=group.key
                root:CreateButton(group.label.." ("..#group.rows..")",function()
                    Route.Track(key)
                    Guide.Resume()
                    folded.route[key]=true
                    nextRefresh=0
                end)
            end
        end
        root:CreateButton("Open Quest Route",function() notify(HUD.OpenLog("route")) end)
    end)
end

local function makeTrackerBar(native)
    -- The tracker hides itself with no watched objectives. Keep the controls
    -- on its parent so Nearby can still be opened from the same spot.
    local bar=CreateFrame("Frame",nil,native:GetParent())
    -- Forever moves its header below the combined top padding.
    bar:SetPoint("BOTTOMLEFT",native.Header,"TOPLEFT",9,2)
    bar:SetPoint("BOTTOMRIGHT",native.Header,"TOPRIGHT",-9,2)
    bar:SetFrameLevel(native.Header:GetFrameLevel()+1)
    bar.padding=0
    function bar:GetTopPadding() return self.padding end
    bar.route=button(bar,"Route",function() notify(HUD.OpenLog("route")) end)
    bar.route:SetSize(62,19); bar.route:SetPoint("TOPLEFT")
    bar.nearby=button(bar,"Nearby",function() notify(HUD.OpenLog("nearby")) end)
    bar.nearby:SetSize(62,19); bar.nearby:SetPoint("LEFT",bar.route,"RIGHT",5,0)
    bar.area=button(bar,"Track Area",chooseArea)
    bar.area:SetSize(80,19); bar.area:SetPoint("LEFT",bar.nearby,"RIGHT",5,0)
    bar.target=font(bar,"small",GOLD)
    bar.target:SetPoint("TOPLEFT",1,-23); bar.target:SetPoint("TOPRIGHT",-1,-23)
    bar.target:SetWordWrap(false)
    native:AddTopPaddingProvider(bar)
    return bar
end

local function syncTracker(running)
    if FC.IsCombat() then return end
    local native=ObjectiveTrackerFrame
    if not native or not native.Header or type(native.AddTopPaddingProvider)~="function" or type(native.MarkDirty)~="function" then return end
    local editing=EditModeManagerFrame and read(EditModeManagerFrame.IsEditModeActive,EditModeManagerFrame)==true
    local allowed=running and not gamepad() and not editing
        and read(native.ShouldShowHeader,native)~=false
    if not trackerBar and allowed then trackerBar=makeTrackerBar(native) end
    if not trackerBar then return end
    local target=Route.Target()
    local group=Route.area and Route.byKey[Route.area]
    local label
    if target then
        label="Tracking: "..target.record.title
        local _,party=sessionNow()
        if party then
            local summary=FC.Quests.GroupSummary(target.id,party)
            if summary then label=label.." · "..summary.text end
        end
    elseif group or Route.area then label="Route: "..(group and group.label or "waiting for quest data") end
    local padding=allowed and (label and 41 or 24) or 0
    trackerBar.target:SetText(label or "")
    trackerBar.target:SetShown(label~=nil)
    trackerBar.area:SetShown(trackerBar:GetWidth()>=214 and MenuUtil and type(MenuUtil.CreateContextMenu)=="function" or false)
    trackerBar:SetHeight(math.max(1,padding))
    trackerBar:SetShown(allowed)
    if trackerBar.padding~=padding then
        trackerBar.padding=padding
        native:MarkDirty()
    end
end

function HUD.Status()
    if not FC.IsEnabled("quests") then return "Quest Helper is disabled." end
    return HUD.status or "Quest Helper uses the Objective Tracker and Quest and Map Log."
end

function HUD.Tick()
    local running=FC.IsEnabled("quests")
    if not running and not ownedScroll and not searchSizing and not (trackerBar and trackerBar.padding>0)
        and not Guide.HasPending() then return end
    local now=GetTime()
    if now<nextRefresh then return end
    nextRefresh=now+.65
    local status,err=pcall(function()
        if running and not FC.IsCombat() then
            if FC.QuestData then FC.QuestData.Tick() end
            Route.Tick()
            if Route.state~="waiting" then Guide.Tick(Route.Target()) end
        elseif not running then Guide.Stop() end
        syncLog(running)
        syncTracker(running)
        if running then repaint() end
    end)
    if not status then
        FC.RecordDiagnostic("Quest Helper",err)
        pcall(closeLog)
        pcall(syncLog,false)
        pcall(syncTracker,false)
        HUD.status="Quest Helper paused after a client error. See /fc diagnostics."
        nextRefresh=now+3
    else
        HUD.status=nil
    end
end

function HUD.Render(parent)
    UI.Label(parent,"Quest Helper",0,0,730,true)
    UI.Label(parent,"Quest Helper opens with the Quest and Map Log. Route and Nearby are also in the Objective Tracker.",0,27,730)
    UI.Button(parent,"Open Quest Helper",0,58,170,function() UI.Result(HUD.OpenLog()) end)
    UI.Height(430)
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
    closeLog()
    syncLog(false)
    syncTracker(false)
    nextRefresh=0
end

FC.RegisterModule("quests",{title="Quest Helper",Render=HUD.Render,Enable=enable,Disable=disable,OnEvent=onEvent})
