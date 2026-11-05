local _, FC = ...
local Native = {}
FC.QuestLogUI = Native
local enabled, nextRefresh, deferred = false, 0, false
local hooks, rows, rowCount = {}, {}, 0
local companion, hoverRow
local MAX_ROWS = 100

local function hideTooltip()
    if companion then companion:Hide() end
    hoverRow=nil
end

local function hideOwned()
    for _,state in pairs(rows) do state.frame:Hide() end
    hideTooltip()
end

local function guarded(fn,...)
    local ok,err=pcall(fn,...)
    if not ok then hideOwned(); FC.RecordDiagnostic("Native quest log",err) end
end

local function finite(value,minimum,maximum)
    return FC.Readable(value) and type(value)=="number" and value==value
        and value>=minimum and value<=maximum
end

local function read(object,key)
    if not FC.Readable(object) or type(object)~="table" then return nil end
    local status,value=FC.SafeRead(function() return object[key] end)
    if status=="ready" then return value end
end

local function questID(row)
    local id=read(row,"questID")
    local info=read(row,"info")
    if not FC.Number(id,1,10000000) or read(info,"questID")~=id or read(info,"isHeader")==true then return nil end
    return id
end

local function numberFrom(object,method,minimum,maximum)
    local status,value=FC.SafeRead(object and object[method],object)
    if status=="ready" and finite(value,minimum,maximum) then return value end
end

local function partyNow()
    local status,party=FC.API.Party()
    if status=="ready" then return party end
end

local function summaryFor(id,party)
    if enabled and id and party and FC.Quests and FC.Quests.GroupSummary then
        return FC.Quests.GroupSummary(id,party)
    end
end

local function layout()
    local contents=QuestScrollFrame and QuestScrollFrame.Contents
    if contents and type(contents.Layout)=="function" then contents:Layout() end
end

local function restoreRow(row,state)
    state.frame:Hide()
    local changed=false
    if state.appliedHeight and questID(row)==state.id
        and numberFrom(row,"GetHeight",0,10000)==state.appliedHeight then
        row:SetHeight(state.baseHeight)
        changed=true
    end
    state.appliedHeight,state.baseHeight,state.label=nil,nil,nil
    return changed
end

local function cleanup()
    hideOwned()
    if FC.IsCombat() then deferred=true; return end
    local changed=false
    for row,state in pairs(rows) do changed=restoreRow(row,state) or changed end
    if changed then layout() end
    deferred=false
end

local function activeRows()
    local pool=QuestScrollFrame and QuestScrollFrame.titleFramePool
    if not pool or type(pool.EnumerateActive)~="function" then return nil end
    local status,list=FC.SafeRead(function()
        local result={}
        for row in pool:EnumerateActive() do
            if #result>=MAX_ROWS or not FC.Readable(row) then return nil end
            result[#result+1]=row
        end
        return result
    end)
    if status=="ready" and type(list)=="table" then return list end
end

local function tooltip(row,party)
    if not enabled or FC.IsCombat() or not row or not row:IsVisible() or not row:IsMouseOver() then
        hideTooltip(); return
    end
    if party==nil then party=partyNow() end
    local summary=summaryFor(questID(row),party)
    if not summary then hideTooltip(); return end
    if not companion then
        if _G.ForeverCompanionQuestLogTooltip then return end
        companion=CreateFrame("GameTooltip","ForeverCompanionQuestLogTooltip",UIParent,"GameTooltipTemplate")
        companion:EnableMouse(false)
        companion:SetClampedToScreen(true)
    end
    hoverRow=row
    companion:SetOwner(row,"ANCHOR_NONE")
    companion:ClearAllPoints()
    if GameTooltip and GameTooltip:IsShown() and GameTooltip:IsOwned(row) then
        companion:SetPoint("TOPLEFT",GameTooltip,"BOTTOMLEFT",0,-4)
    else companion:SetPoint("TOPLEFT",row,"TOPRIGHT",8,0) end
    companion:ClearLines()
    companion:SetText("Adventure Together",0.85,0.71,0.42)
    companion:AddLine(summary.ready .. "/" .. summary.total .. " members ready for turn-in",1,1,1,true)
    companion:AddLine(summary.unknown .. " unknown; " .. summary.absent .. " without quest",0.8,0.8,0.8,true)
    companion:AddLine(FC.PlainText(summary.note or "",256) or "Progress unavailable.",0.8,0.8,0.8,true)
    for i=1,math.min(12,#summary.members) do
        local member=summary.members[i]
        companion:AddLine((FC.PlainText(member.name,192) or "Group member") .. ": "
            .. (FC.PlainText(member.label,192) or "Unknown"),0.9,0.9,0.9,true)
    end
    if #summary.members>12 then companion:AddLine((#summary.members-12) .. " more members",0.8,0.8,0.8) end
    companion:Show()
end

local function stateFor(row)
    local state=rows[row]
    if state then return state end
    if rowCount>=MAX_ROWS or type(row.HookScript)~="function" then return nil end
    local frame=CreateFrame("Frame",nil,row)
    frame:EnableMouse(false)
    frame:Hide()
    frame.text=frame:CreateFontString(nil,"OVERLAY","ObjectiveFont")
    frame.text:SetPoint("TOPLEFT")
    frame.text:SetJustifyH("LEFT")
    frame.text:SetTextColor(0.8,0.8,0.8)
    state={frame=frame}
    rows[row],rowCount=state,rowCount+1
    row:HookScript("OnEnter",function(self) if enabled then guarded(tooltip,self) end end)
    local function leave(self)
        if hoverRow==self then hideTooltip() end
    end
    row:HookScript("OnLeave",leave)
    row:HookScript("OnHide",function(self)
        state.frame:Hide()
        leave(self)
    end)
    return state
end

local function updateRow(row,party)
    local state=rows[row]
    local id=questID(row)
    if state and state.id~=id then
        -- A native full rebuild sets every acquired row's height. Do not apply
        -- the previous quest's geometry to a recycled title button.
        state.frame:Hide()
        state.appliedHeight,state.baseHeight,state.label=nil,nil,nil
        state.blocked=false
        state.id=id
    end
    local summary=summaryFor(id,party)
    if not summary or not row:IsShown() then return state and restoreRow(row,state) or false end
    state=state or stateFor(row)
    if not state or state.blocked then return false end
    state.id=id
    local currentHeight=numberFrom(row,"GetHeight",1,10000)
    if state.appliedHeight and currentHeight~=state.appliedHeight then
        -- A different layout owner wins for this binding. Only the native full
        -- rebuild (which explicitly resets row height) can establish a baseline.
        state.frame:Hide(); state.blocked=true
        state.appliedHeight,state.baseHeight=nil,nil
        return false
    end
    local text=read(row,"Text")
    local width=numberFrom(text,"GetWidth",50,1000)
    local rowTop=numberFrom(row,"GetTop",-100000,100000)
    local textTop=numberFrom(text,"GetTop",-100000,100000)
    local baseHeight=state.baseHeight or currentHeight
    if not width or not rowTop or not textTop or not baseHeight then return restoreRow(row,state) end
    local inset=rowTop-textTop
    if not finite(inset,0,50) or baseHeight<inset+5 then return restoreRow(row,state) end
    local label="Adventure Together: " .. summary.ready .. "/" .. summary.total .. " ready for turn-in"
    if summary.unknown>0 or summary.absent>0 then
        label=label .. "\n" .. summary.unknown .. " unknown; " .. summary.absent .. " without quest"
    end
    local frame=state.frame
    if state.label==label and state.width==width and frame:IsShown() then return false end
    frame.text:SetWidth(width)
    frame.text:SetText(label)
    local height=numberFrom(frame.text,"GetStringHeight",1,500)
    if not height then return restoreRow(row,state) end
    frame:ClearAllPoints()
    -- XML Text begins eight pixels below the row. Derive that inset rather
    -- than assuming it so title wrapping, tags and flavor padding stay native.
    frame:SetPoint("TOPLEFT",text,"TOPLEFT",0,-(baseHeight-inset-3))
    frame:SetSize(width,height)
    local appliedHeight=baseHeight+height+4
    local changed=currentHeight~=appliedHeight
    state.baseHeight,state.appliedHeight=baseHeight,appliedHeight
    state.label,state.width=label,width
    row:SetHeight(appliedHeight)
    frame:Show()
    return changed
end

local function refresh()
    if not enabled then return end
    if FC.IsCombat() then cleanup(); return end
    if not QuestScrollFrame or not QuestScrollFrame:IsVisible() then cleanup(); return end
    local list=activeRows()
    if not list then cleanup(); return end
    local party=partyNow() -- Reuse one active roster for every row and hover.
    local active,changed={},false
    local hovered
    for _,row in ipairs(list) do
        active[row]=true
        changed=updateRow(row,party) or changed
        if row:IsVisible() and row:IsMouseOver() then hovered=row end
    end
    for row,state in pairs(rows) do
        if not active[row] then restoreRow(row,state) end
    end
    if changed then layout() end
    if hovered then tooltip(hovered,party or false) else hideTooltip() end
    deferred=false
end

local function nativeRebuilt()
    -- The native builder has explicitly SetHeight on every active title. Never
    -- subtract our previous extension from those newly authoritative heights.
    for _,state in pairs(rows) do
        state.frame:Hide()
        state.appliedHeight,state.baseHeight,state.label=nil,nil,nil
        state.blocked=false
    end
    if enabled then refresh() end
end

local function install()
    if type(hooksecurefunc)~="function" then return end
    if not hooks.update and type(QuestLogQuests_Update)=="function" then
        hooksecurefunc("QuestLogQuests_Update",function() guarded(nativeRebuilt) end)
        hooks.update=true
    end
    if not hooks.enter and type(QuestMapLogTitleButton_OnEnter)=="function" then
        hooksecurefunc("QuestMapLogTitleButton_OnEnter",function(row) if enabled then guarded(tooltip,row) end end)
        hooks.enter=true
    end
    if QuestScrollFrame and hooks.scroll~=QuestScrollFrame then
        QuestScrollFrame:HookScript("OnHide",function() guarded(cleanup) end)
        QuestScrollFrame:HookScript("OnShow",function() if enabled then guarded(refresh) end end)
        hooks.scroll=QuestScrollFrame
    end
end

-- Deferred native height cleanup must still run after Adventure is disabled.
local events=CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent",function(_,event)
    guarded(function()
        if event=="PLAYER_REGEN_DISABLED" then cleanup()
        elseif event=="PLAYER_REGEN_ENABLED" then
            if deferred then cleanup() end
            if enabled then install(); refresh() end
        elseif enabled then install() end
    end)
end)

function Native.Enable()
    enabled,nextRefresh=true,0
    guarded(install)
    guarded(refresh)
end

function Native.Disable()
    enabled=false
    guarded(cleanup)
end

function Native.Tick()
    if not enabled or GetTime()<nextRefresh then return end
    nextRefresh=GetTime()+1
    guarded(install)
    guarded(refresh)
end

function Native.OnEvent(event)
    if enabled and event=="ADDON_LOADED" then guarded(install) end
end
