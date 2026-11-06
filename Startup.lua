local _, FC = ...
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
local started=false

local function diagnostics()
    local s,version,build,_,interface=FC.SafeRead(GetBuildInfo)
    FC.Print("Version " .. FC.version .. " | client " .. (s=="ready" and (tostring(version) .. " build " .. tostring(build) .. " interface " .. tostring(interface)) or "unavailable"))
    FC.Print("Capabilities: money=" .. tostring(type(GetMoney)=="function")
        .. ", bags=" .. tostring(C_Container~=nil) .. ", tooltip=" .. tostring(TooltipDataProcessor~=nil)
        .. ", Legacy=" .. tostring(LegacySystem~=nil) .. ", recipes=" .. tostring(C_TradeSkillUI~=nil)
        .. ", vendor prices=" .. tostring(type(GetMerchantItemInfo)=="function") .. ", trainer prices=" .. tostring(type(GetTrainerServiceCost)=="function")
        .. ", quests=" .. tostring(C_QuestLog~=nil) .. ", party comms=" .. tostring(C_ChatInfo~=nil))
    if FC.QuestHUD then FC.Print(FC.QuestHUD.Status()) end
    if FC.Store.status then FC.Print(FC.Store.status) end
    for _,line in ipairs(FC.diagnostics) do FC.Print(line) end
end

local function start()
    if started then return end
    if not FC.Store.root then FC.Store.Initialize() end
    if not FC.Store.Character() then return end
    started=true
    for _,event in ipairs({"PLAYER_MONEY","BAG_UPDATE_DELAYED","ITEM_DATA_LOAD_RESULT","GET_ITEM_INFO_RECEIVED",
        "ACHIEVEMENT_EARNED","CRITERIA_UPDATE","TRAIT_CONFIG_UPDATED","PLAYER_LEVEL_UP","GROUP_ROSTER_UPDATE",
        "PARTY_LEADER_CHANGED","GROUP_JOINED","GROUP_LEFT","CHAT_MSG_ADDON","PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED","PLAYER_ENTERING_WORLD",
        "QUEST_LOG_UPDATE","QUEST_ACCEPTED","QUEST_REMOVED","QUEST_TURNED_IN","QUEST_AUTOCOMPLETE","QUEST_COMPLETE","QUEST_WATCH_UPDATE","QUEST_DATA_LOAD_RESULT","QUEST_LOG_CRITERIA_UPDATE",
        "QUEST_WATCH_LIST_CHANGED","QUEST_POI_UPDATE","SUPER_TRACKING_CHANGED","SUPER_TRACKING_PATH_UPDATED","USER_WAYPOINT_UPDATED",
        "ZONE_CHANGED","ZONE_CHANGED_INDOORS","ZONE_CHANGED_NEW_AREA","GOSSIP_SHOW","GOSSIP_CLOSED","GOSSIP_OPTIONS_UPDATE",
        "QUEST_GREETING","QUEST_FINISHED","QUEST_DETAIL","QUESTLINE_UPDATE","MINIMAP_UPDATE_TRACKING","GAME_PAD_ACTIVE_CHANGED",
        "CVAR_UPDATE","SKILL_LINES_CHANGED","SPELLS_CHANGED",
        "TRADE_SKILL_SHOW","TRADE_SKILL_CLOSE","TRADE_SKILL_LIST_UPDATE","TRADE_SKILL_DETAILS_UPDATE","TRADE_SKILL_DATA_SOURCE_CHANGED","NEW_RECIPE_LEARNED",
        "UNIT_SPELLCAST_SENT","UNIT_SPELLCAST_START","UNIT_SPELLCAST_SUCCEEDED","UNIT_SPELLCAST_FAILED","UNIT_SPELLCAST_INTERRUPTED","UNIT_SPELLCAST_FAILED_QUIET",
        "MERCHANT_SHOW","MERCHANT_UPDATE","MERCHANT_CLOSED","TRAINER_SHOW","TRAINER_UPDATE","TRAINER_CLOSED",
        "TRAINER_DESCRIPTION_UPDATE","TRAINER_SERVICE_INFO_NAME_UPDATE","UPDATE_FACTION"}) do
        local ok=pcall(events.RegisterEvent,events,event)
        if not ok then FC.RecordDiagnostic("Event",event .. " unavailable") end
    end
    for _,key in ipairs(FC.keys) do if FC.IsEnabled(key) then FC.Invoke(key,"Enable") end end
    SLASH_FOREVERCOMPANION1="/fc"
    SlashCmdList.FOREVERCOMPANION=function(message)
        local command=(message or ""):match("^%s*(%S*)"):lower()
        if command=="help" then FC.Print("/fc | /fc legacy | /fc wallet | /fc items | /fc quests | /fc party | /fc settings | /fc updates | /fc diagnostics")
        elseif command=="updates" and FC.Updates then FC.Updates.PrintStatus()
        elseif command=="diagnostics" then diagnostics()
        elseif command=="quests" and FC.IsEnabled("quests") then
            local status,opened=FC.SafeRead(FC.QuestHUD.OpenLog)
            if status~="ready" or not opened then FC.UI.Open("quests") end
        elseif command=="" or FC.modules[command] or command=="settings" then FC.UI.Open(command~="" and command or nil)
        else FC.Print("Unknown command. Use /fc help.") end
    end
    FC.Print("Prototype loaded. Open /fc. In-game and two-player verification is still required.")
end

events:SetScript("OnEvent",function(_,event,...)
    if event=="ADDON_LOADED" then
        local name=...
        if name==FC.name then FC.Store.Initialize() end
        if started and FC.IsEnabled("party") and FC.QuestLogUI then FC.QuestLogUI.OnEvent(event,name) end
        if started and FC.IsEnabled("party") and FC.ObjectiveTrackerUI then FC.ObjectiveTrackerUI.OnEvent(event,name) end
        if started and FC.IsEnabled("quests") then FC.Invoke("quests","OnEvent",event,name) end
    elseif event=="PLAYER_LOGIN" then start()
    else
        if not started then start() end
        if event=="GROUP_JOINED" or event=="GROUP_LEFT" then FC.API.GroupChanged(...) end
        if event=="CHAT_MSG_ADDON" then
            local ok,err=pcall(FC.PartyProtocol.Receive,...)
            if not ok then FC.RecordDiagnostic("Party message",err) end
        end
        FC.Quests.OnEvent(event,...)
        for _,key in ipairs(FC.keys) do if FC.IsEnabled(key) then FC.Invoke(key,"OnEvent",event,...) end end
    end
end)

local elapsed=0
events:SetScript("OnUpdate",function(_,delta)
    elapsed=elapsed+delta
    if elapsed<0.25 then return end
    elapsed=0
    if started then
        local questOK,questError=pcall(FC.Quests.Tick)
        if not questOK then FC.RecordDiagnostic("Quest log",questError) end
        if FC.QuestHUD then FC.QuestHUD.Tick() end -- Restore native quest-log layout after deferred cleanup.
    end
    if started and FC.IsEnabled("party") then
        local ok,err=pcall(FC.PartyProtocol.Tick)
        if not ok then FC.RecordDiagnostic("Party tick",err) end
        if FC.QuestLogUI then
            local uiOK,uiError=pcall(FC.QuestLogUI.Tick)
            if not uiOK then FC.RecordDiagnostic("Quest log UI",uiError) end
        end
        if FC.ObjectiveTrackerUI then
            local trackerOK,trackerError=pcall(FC.ObjectiveTrackerUI.Tick)
            if not trackerOK then FC.RecordDiagnostic("Objective tracker UI",trackerError) end
        end
    end
    if started and FC.IsEnabled("items") then FC.Invoke("items","Tick") end
    if started and FC.IsEnabled("wallet") then FC.Invoke("wallet","Tick") end
end)
