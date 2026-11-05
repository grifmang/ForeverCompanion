local _, FC = ...
-- Regular and campaign quests use separate native modules with the same quest
-- block contract. Keep each module's layout pass and pool identity independent.
local function createAdapter(globalName)
local Tracker = {}
local KEY, TEMPLATE = "ForeverCompanionGroupProgress", "ObjectiveTrackerAnimLineTemplate"
local enabled, nextTick, needsLayout = false, 0, false
local module, inLayout, passParty, passNumber = nil, false, nil, 0
local states, stateCount, lastSignature = {}, 0, nil

local function guarded(fn,...)
    local ok,err=pcall(fn,...)
    if not ok then FC.RecordDiagnostic("Objective tracker progress (" .. globalName .. ")",err) end
end

local function field(object,key)
    if not FC.Readable(object) or type(object)~="table" then return nil,false end
    local status,value=FC.SafeRead(function() return object[key] end)
    return value,status=="ready"
end

local function real(value,minimum,maximum)
    return FC.Readable(value) and type(value)=="number" and value==value
        and value>=minimum and value<=maximum
end

local function partyNow()
    local status,party=FC.API.Party()
    if status=="ready" then return party end
end

local function labelFor(id,party)
    if not enabled or not party or not FC.Quests or type(FC.Quests.GroupSummary)~="function" then return nil end
    local summary=FC.Quests.GroupSummary(id,party)
    if not summary or not FC.Number(summary.total,1,100) or not FC.Number(summary.ready,0,summary.total)
        or not FC.Number(summary.unknown,0,summary.total) or not FC.Number(summary.absent,0,summary.total) then return nil end
    local label="Group: " .. summary.ready .. "/" .. summary.total .. " ready"
    if summary.unknown>0 then label=label .. " · " .. summary.unknown .. " unknown" end
    if summary.absent>0 then label=label .. " · " .. summary.absent .. " without quest" end
    return label
end

local function ownsLine(block,state)
    local owner,orOK=field(block,"parentModule")
    local id,idOK=field(block,"id")
    if not orOK or owner~=module or not idOK or not FC.Number(id,1,10000000) or id~=state.id or not state.line then return false end
    local getter=field(block,"GetExistingLine")
    local status,line=FC.SafeRead(getter,block,KEY)
    if status~="ready" or line~=state.line then return false end
    local parent,parentOK=field(line,"parentBlock")
    local template,templateOK=field(line,"template")
    return parentOK and parent==block and templateOK and template==TEMPLATE
end

local function hideLine(block,state)
    if ownsLine(block,state) then state.line:Hide() end
end

local function hideAll()
    for block,state in pairs(states) do
        state.pending=nil
        hideLine(block,state)
    end
end

local function flushLayout()
    if not needsLayout or not module or inLayout or FC.IsCombat() then return end
    local container,read=field(module,"parentContainer")
    if not read or not container then return end
    local status=FC.SafeRead(module.MarkDirty,module)
    if status=="ready" then needsLayout=false end
end

local function requestLayout()
    needsLayout=true
    flushLayout()
end

-- Use watched IDs rather than currently fitting blocks: otherwise a line that
-- pushes a block below the height limit could trigger an endless relayout loop.
local function signature(party)
    local status,count=FC.SafeRead(C_QuestLog and C_QuestLog.GetNumQuestWatches)
    if status~="ready" or not FC.Number(count,0,100) then return "unavailable" end
    local ids,seen={},{}
    for i=1,count do
        local rs,id=FC.SafeRead(C_QuestLog.GetQuestIDForQuestWatchIndex,i)
        if rs~="ready" or not FC.Number(id,1,10000000) then return "unavailable" end
        if not seen[id] then ids[#ids+1]=id; seen[id]=true end
    end
    table.sort(ids)
    local result={}
    for _,id in ipairs(ids) do result[#result+1]=id .. ":" .. (labelFor(id,party) or "-") end
    return table.concat(result,"|")
end

local function appendLine(block,questID)
    if not FC.Readable(block) or not FC.Number(questID,1,10000000) then return end
    local state=states[block]
    if not state then return end
    local pending=state.pending
    state.pending=nil -- A SetPOIInfo call can reserve height at most once.
    if not enabled or not inLayout or not passParty or FC.IsCombat() or pending~=questID or state.id~=questID then return end
    local owner,ownerOK=field(block,"parentModule")
    local id,idOK=field(block,"id")
    local cached,cachedOK=field(block,"cached")
    if not ownerOK or owner~=module or not idOK or id~=questID or not cachedOK or cached then return end
    local widthStatus,width=FC.SafeRead(block.GetWidth,block)
    local edge,edgeOK=field(block,"rightEdgeOffset")
    if widthStatus~="ready" or not real(width,40,2000) or not edgeOK or not real(edge,-2000,0)
        or width+edge<40 then return end
    local label=labelFor(questID,passParty)
    if not label then return end
    local existingStatus,existing=FC.SafeRead(block.GetExistingLine,block,KEY)
    if existingStatus~="ready" then return end
    -- Refuse to replace a line that somebody else placed under our key.
    if existing and existing~=state.line then return end
    -- The generic animated template supplies FadeInAnim required by the POI
    -- block's PlayAddAnimation, without QuestObjectiveLine's quest-state hooks.
    -- Leave state nil: quest objective loops only mutate their indexed lines,
    -- and their final sweep only fades lines explicitly marked Completed.
    -- Native AddObjective handles right-edge reservations, wrapping and height.
    local status,line=FC.SafeRead(block.AddObjective,block,KEY,label,TEMPLATE,true,OBJECTIVE_DASH_STYLE_HIDE)
    if status~="ready" or not line then return end
    state.line,state.addedPass=line,passNumber
    if ownsLine(block,state) then line:Show() end
end

local function getBlock(self,id,optTemplate)
    if not FC.Readable(self) or self~=module or not enabled or not inLayout or not passParty or FC.IsCombat()
        or not FC.Number(id,1,10000000) then return end
    local status,block=FC.SafeRead(self.GetExistingBlock,self,id,optTemplate)
    if status~="ready" or not block then return end
    local owner,ownerOK=field(block,"parentModule")
    local bound,boundOK=field(block,"id")
    if not ownerOK or owner~=module or not boundOK or bound~=id then return end
    local state=states[block]
    if not state then
        if stateCount>=100 then return end
        for _,name in ipairs({"SetPOIInfo","AddObjective","GetExistingLine","GetWidth"}) do
            local fn,read=field(block,name)
            if not read or type(fn)~="function" then return end
        end
        state={}
        states[block],stateCount=state,stateCount+1
        hooksecurefunc(block,"SetPOIInfo",function(current,questID) guarded(appendLine,current,questID) end)
    end
    hideLine(block,state)
    state.id,state.pending=id,id
end

local function beginLayout(self)
    if self~=module then return end
    inLayout,passParty=true,nil
    passNumber=passNumber+1
    hideAll()
    if enabled and not FC.IsCombat() then
        passParty=partyNow() -- One roster snapshot for the entire native pass.
        lastSignature=signature(passParty)
    end
end

local function endLayout(self)
    if self~=module then return end
    local combat=FC.IsCombat()
    for block,state in pairs(states) do
        state.pending=nil
        local used,usedOK=field(block,"used")
        local cached,cachedOK=field(block,"cached")
        if not enabled or combat or not usedOK or not used or not cachedOK or cached
            or state.addedPass~=passNumber then hideLine(block,state) end
    end
    inLayout,passParty=false,nil
    -- Never MarkDirty from native layout hooks; pending work is flushed by Tick
    -- or the independent combat/lifecycle event frame.
end

local function install()
    if module or type(hooksecurefunc)~="function" then return end
    local candidate,read=field(_G,globalName)
    if not read or not candidate then return end
    for _,name in ipairs({"BeginLayout","EndLayout","GetBlock","GetExistingBlock","MarkDirty","IsVisible"}) do
        local fn,ok=field(candidate,name)
        if not ok or type(fn)~="function" then return end
    end
    if not C_QuestLog or type(C_QuestLog.GetNumQuestWatches)~="function"
        or type(C_QuestLog.GetQuestIDForQuestWatchIndex)~="function"
        or not FC.Readable(OBJECTIVE_DASH_STYLE_HIDE) or OBJECTIVE_DASH_STYLE_HIDE==nil then return end
    module=candidate
    hooksecurefunc(module,"BeginLayout",function(self) guarded(beginLayout,self) end)
    hooksecurefunc(module,"GetBlock",function(...) guarded(getBlock,...) end)
    hooksecurefunc(module,"EndLayout",function(self) guarded(endLayout,self) end)
    module:HookScript("OnHide",function()
        lastSignature=nil -- Showing unchanged watched quests must restore hidden lines.
        guarded(hideAll)
    end)
    needsLayout=true
end

local function tick(party)
    if not enabled or GetTime()<nextTick then return end
    nextTick=GetTime()+1
    install()
    if FC.IsCombat() then hideAll(); needsLayout=true; return end
    flushLayout()
    if not module or inLayout then return end
    local status,visible=FC.SafeRead(module.IsVisible,module)
    if status~="ready" or not visible then return end
    local current=signature(party) -- The coordinator shares one roster per poll.
    if current~=lastSignature then
        lastSignature=current
        requestLayout()
    end
end

function Tracker.Enable()
    if enabled then return end
    enabled,nextTick,lastSignature=true,0,nil
    guarded(install)
    guarded(requestLayout)
end

function Tracker.Disable()
    enabled=false
    guarded(hideAll)
    guarded(requestLayout)
end

function Tracker.Tick(party) guarded(tick,party) end

local rosterEvents={GROUP_ROSTER_UPDATE=true,GROUP_JOINED=true,GROUP_LEFT=true,PARTY_LEADER_CHANGED=true,
    PLAYER_ENTERING_WORLD=true,PLAYER_LOGIN=true}
function Tracker.OnEvent(event)
    if not enabled then return end
    guarded(function()
        if event=="ADDON_LOADED" then install(); flushLayout()
        elseif rosterEvents[event] then requestLayout() end
    end)
end

-- Cleanup and native relayout still complete if Disable stops module ticking
-- during combat. Only our own line is hidden; native geometry waits for regen.
local events=CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent",function(_,event)
    guarded(function()
        if event=="PLAYER_REGEN_DISABLED" then
            hideAll(); needsLayout=true
        elseif event=="PLAYER_REGEN_ENABLED" then
            if enabled then install() end
            flushLayout()
        elseif enabled then install(); flushLayout() end
    end)
end)
return Tracker
end

local adapters={createAdapter("QuestObjectiveTracker"),createAdapter("CampaignQuestObjectiveTracker")}
local Native={}
FC.ObjectiveTrackerUI=Native
local active,nextPoll=false,0

function Native.Enable()
    active,nextPoll=true,0
    for _,adapter in ipairs(adapters) do adapter.Enable() end
end

function Native.Disable()
    active=false
    for _,adapter in ipairs(adapters) do adapter.Disable() end
end

function Native.Tick()
    if not active or GetTime()<nextPoll then return end
    nextPoll=GetTime()+1
    local status,party=FC.API.Party()
    for _,adapter in ipairs(adapters) do adapter.Tick(status=="ready" and party or false) end
end

function Native.OnEvent(event)
    for _,adapter in ipairs(adapters) do adapter.OnEvent(event) end
end
