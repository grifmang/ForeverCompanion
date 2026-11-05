local _, FC = ...
local Quests = {records={}, removed={}, revision=0, status="loading", complete=false, generation=nil}
FC.Quests = Quests
local requested, titles, requestCount, titleCount = {}, {}, 0, 0
local dirty, enabled, nextScan, lastScan = true, false, 0, -1
local MAX_QUESTS, MAX_OBJECTIVES = 100, 8

-- Read fields behind the same protected/secret-value boundary as API results.
local function field(value, key)
    if not FC.Readable(value) or type(value)~="table" then return nil, false end
    local status, result = FC.SafeRead(function() return value[key] end)
    return result, status=="ready"
end

local function text(value, maximum)
    if not FC.Readable(value) or type(value)~="string" then return nil end
    -- Sanitize before truncating; validate the whole string and cut only at a
    -- UTF-8 boundary. Native titles/objectives can exceed the display budget.
    local clean = FC.PlainText(value, #value)
    if not clean or clean=="" then return nil end
    if #clean<=maximum then return clean end
    local stop=maximum+1
    while stop>1 and clean:byte(stop)>=128 and clean:byte(stop)<=191 do stop=stop-1 end
    return clean:sub(1,stop-1)
end

function Quests.Label(id)
    if not FC.Number(id,1,10000000) then return "Unknown quest" end
    if titles[id] then return titles[id] end
    local status, title = FC.SafeRead(C_QuestLog and C_QuestLog.GetTitleForQuestID,id)
    title = status=="ready" and text(title,96) or nil
    if title then
        if titleCount<400 then titles[id]=title; titleCount=titleCount+1 end
        return title
    end
    if not requested[id] and requestCount<400 and not FC.IsCombat()
        and C_QuestLog and type(C_QuestLog.RequestLoadQuestByID)=="function" then
        requested[id],requestCount=true,requestCount+1
        FC.SafeRead(C_QuestLog.RequestLoadQuestByID,id)
    end
    return "Quest #" .. id
end

local function boolean(value) return FC.Readable(value) and type(value)=="boolean" end
local function same(a,b)
    if not a or a.title~=b.title or a.status~=b.status or a.observed~=b.observed or #a.objectives~=#b.objectives then return false end
    for i,objective in ipairs(a.objectives) do
        local other=b.objectives[i]
        if objective.text~=other.text or objective.have~=other.have or objective.need~=other.need
            or objective.finished~=other.finished then return false end
    end
    return true
end

local function commit(records,status,complete)
    local changed=Quests.status~=status or Quests.complete~=complete
    for id,record in pairs(records) do if not same(Quests.records[id],record) then changed=true end end
    for id in pairs(Quests.records) do if not records[id] then changed=true end end
    if not changed then return end
    Quests.revision=Quests.revision+1
    for id,record in pairs(records) do
        record.version=same(Quests.records[id],record) and Quests.records[id].version or Quests.revision
        if record.observed then Quests.removed[id]=nil end
    end
    Quests.records,Quests.status,Quests.complete=records,status,complete
    FC.Refresh("party")
end

local function staleRecords()
    local records={}
    for id,old in pairs(Quests.records) do
        records[id]={id=id,title=old.title,status=old.status,objectives=old.objectives,observed=false,version=old.version}
    end
    return records
end

local function objectives(id)
    local status, list=FC.SafeRead(C_QuestLog and C_QuestLog.GetQuestObjectives,id)
    if status~="ready" or not FC.Readable(list) or type(list)~="table" then return {},"U" end
    -- Check the documented array shape, including sparse/oversized results.
    local shape,valid,n=FC.SafeRead(function()
        local n=0
        for key in pairs(list) do
            if not FC.Number(key,1,MAX_OBJECTIVES) then return false,0 end
            n=n+1
        end
        return true,n
    end)
    if shape~="ready" or valid~=true or not FC.Number(n,0,MAX_OBJECTIVES) then return {},"P" end
    local out,partial={},false
    for i=1,n do
        local row,read=field(list,i)
        local label,lr=field(row,"text")
        local have,hr=field(row,"numFulfilled")
        local need,nr=field(row,"numRequired")
        local finished,fr=field(row,"finished")
        local objective={text=text(label,192) or ("Objective " .. i)}
        if hr and FC.Number(have,0,999999) then objective.have=have else partial=true end
        if nr and FC.Number(need,0,999999) then objective.need=need else partial=true end
        if fr and boolean(finished) then objective.finished=finished else partial=true end
        if not read or not lr or not text(label,192) then partial=true end
        out[#out+1]=objective
    end
    return out,partial and "P" or nil
end

local function scan()
    local status,shown,total=FC.SafeRead(C_QuestLog and C_QuestLog.GetNumQuestLogEntries)
    if status~="ready" or not FC.Number(shown,0,1000) or not FC.Number(total,0,1000) then
        commit(staleRecords(),status=="restricted" and "restricted" or "unavailable",false)
        return false
    end
    local records,seen,count,rows={}, {},0,0
    local complete,readableRows,restricted=true,0,false
    for index=1,shown do
        local rs,info=FC.SafeRead(C_QuestLog and C_QuestLog.GetInfo,index)
        local header,read=field(info,"isHeader")
        if rs~="ready" or not read or not boolean(header) then
            complete=false
            restricted=restricted or rs=="restricted" or not read
        elseif header then
            readableRows=readableRows+1
            local collapsed,cr=field(info,"isCollapsed")
            if not cr or not boolean(collapsed) or collapsed then complete=false end
        else
            readableRows=readableRows+1
            rows=rows+1
            local id,ir=field(info,"questID")
            if not ir or not FC.Number(id,1,10000000) or seen[id] then complete=false
            else
                seen[id]=true
                if count>=MAX_QUESTS then complete=false
                else
                    local title=field(info,"title")
                    title=text(title,96) or Quests.Label(id)
                    local list,problem=objectives(id)
                    local cs,done=FC.SafeRead(C_QuestLog and C_QuestLog.IsComplete,id)
                    local failed,fr=field(info,"isFailed")
                    local state="A"
                    if problem then state=problem; complete=false
                    elseif cs~="ready" or not boolean(done) or not fr or not boolean(failed) then state="U"; complete=false
                    elseif failed then state="F"
                    elseif done then state="C" end
                    records[id]={id=id,title=title,status=state,objectives=list,observed=true}
                    count=count+1
                end
            end
        end
    end
    if shown>0 and readableRows==0 then
        commit(staleRecords(),restricted and "restricted" or "unavailable",false)
        return false
    end
    if rows~=total then complete=false end
    if not complete then
        -- A partial view never authoritatively removes a quest. Prefer retaining
        -- existing IDs over newly exposed IDs if the combined view exceeds 100.
        local oldIDs={}
        for id in pairs(Quests.records) do oldIDs[#oldIDs+1]=id end
        table.sort(oldIDs)
        for _,id in ipairs(oldIDs) do
            if not records[id] then
                if count>=MAX_QUESTS then
                    local remove
                    for candidate in pairs(records) do
                        if not Quests.records[candidate] and (not remove or candidate>remove) then remove=candidate end
                    end
                    if remove then records[remove]=nil; count=count-1 end
                end
                if count<MAX_QUESTS then
                    local old=Quests.records[id]
                    records[id]={id=id,title=old.title,status=old.status,objectives=old.objectives,observed=false}
                    count=count+1
                end
            end
        end
    end
    commit(records,complete and "ready" or "partial",complete)
    return complete
end

function Quests.Enable()
    if enabled then return end
    enabled,dirty,nextScan,lastScan=true,true,0,-1
    Quests.records,Quests.removed,Quests.revision,Quests.status,Quests.complete={},{},0,"loading",false
    Quests.generation=nil
    if FC.Store.CanWrite() then Quests.generation=FC.Store.NewID("quests") end
end

function Quests.Disable()
    enabled,dirty=false,false
    commit(staleRecords(),"disabled",false)
end

function Quests.Tick()
    if not enabled or not dirty or GetTime()<nextScan or FC.IsCombat() then return end
    dirty=false
    lastScan=GetTime()
    local complete=scan()
    nextScan=GetTime()+(complete and 1 or 5)
    if not complete then dirty=true end
end

local events={PLAYER_LOGIN=true,PLAYER_ENTERING_WORLD=true,PLAYER_REGEN_ENABLED=true,
    QUEST_LOG_UPDATE=true,QUEST_ACCEPTED=true,QUEST_REMOVED=true,QUEST_TURNED_IN=true,
    QUEST_WATCH_UPDATE=true,QUEST_LOG_CRITERIA_UPDATE=true,QUEST_DATA_LOAD_RESULT=true}
function Quests.OnEvent(event,id)
    if enabled and (event=="QUEST_REMOVED" or event=="QUEST_TURNED_IN") and FC.Number(id,1,10000000) then
        local records={}
        for key,record in pairs(Quests.records) do if key~=id then records[key]=record end end
        local before=Quests.revision
        commit(records,Quests.status,Quests.complete)
        if Quests.revision==before and not Quests.removed[id] then Quests.revision=Quests.revision+1 end
        Quests.removed[id]=Quests.revision
        local count,oldest,version=0
        for key,value in pairs(Quests.removed) do
            count=count+1; if not version or value<version then oldest,version=key,value end
        end
        if count>100 then Quests.removed[oldest]=nil end
    end
    if enabled and event=="PLAYER_REGEN_DISABLED" then
        commit(staleRecords(),"restricted",false)
        dirty=true
    end
    if event=="QUEST_DATA_LOAD_RESULT" and FC.Number(id,1,10000000) then
        if titles[id] then titles[id]=nil; titleCount=math.max(0,titleCount-1) end
        FC.Refresh("party")
    end
    if enabled and events[event] then dirty=true; nextScan=math.min(nextScan,lastScan+1) end
end

local stateLabels={A="In progress",C="Ready for turn-in",F="Failed",U="Unknown",P="Partial progress"}
local function localState(id)
    local record=Quests.records[id]
    if not record then return nil,Quests.complete and "Not in current log" or "Unknown / not observed" end
    if not record.observed then return nil,"Stale / not observed" end
    return record,stateLabels[record.status] or "Unknown"
end

local function peerAbsent(peer,id,now)
    local record=peer.quests and peer.quests[id]
    return peer.seen and now-peer.seen<=240 and peer.status=="R"
        and peer.manifestObservedAt and now-peer.manifestObservedAt<=240
        and not (peer.expected and peer.expected[id])
        and not (record and record.version>peer.manifestSequence)
end

local function peerState(peer,id,now)
    if not peer.seen or now-peer.seen>240 or peer.status=="U" then return nil,"Stale / unavailable" end
    local expected=peer.expected and peer.expected[id]
    local record=peer.quests and peer.quests[id]
    if not expected then
        return nil,peerAbsent(peer,id,now) and "Not in reported log" or "Unknown / not reported"
    end
    if not record or record.version<expected then return nil,"Waiting for progress" end
    if not record.observedAt or now-record.observedAt>240 then return nil,"Stale / unavailable" end
    return record,stateLabels[record.status] or "Unknown"
end

-- A read-only view for native UI. The denominator is the active roster, not
-- just the clients that have sent packets. Missing reports are never failures.
function Quests.GroupSummary(id,party)
    if not FC.Number(id,1,10000000) or not FC.IsEnabled("party") then return nil end
    if not party then
        local status
        status,party=FC.API.Party()
        if status~="ready" then return nil end
    end
    if not party.channel then return nil end
    local session=FC.Adventure and FC.Adventure.shared
    local sync=FC.QuestSync
    local sharing=FC.Adventure and FC.Adventure.sharing
    local current=sharing and session and session.phase~="syncing"
        and FC.API.SameGroup(session.context,party) and sync and sync.sid==session.sessionID
        and FC.API.SameGroup(sync.context,party) and sync.channel==party.channel
    local summary={ready=0,total=0,unknown=0,absent=0,members={}}
    local names={}
    for name in pairs(party.membersByName) do names[#names+1]=name end
    table.sort(names)
    local now=GetTime()
    for _,name in ipairs(names) do
        local record,label,absent
        if name==party.selfName then
            record,label=localState(id)
            absent=not record and Quests.complete and not Quests.records[id]
        else
            local peer=current and session.members[name] and sync.peers[name]
            if peer and peer.guid==party.memberGUIDs[name] then
                record,label=peerState(peer,id,now)
                absent=not record and peerAbsent(peer,id,now)
            else label=sharing and "Unknown / not reporting" or "Sharing paused" end
        end
        summary.total=summary.total+1
        if record and record.status=="C" then summary.ready=summary.ready+1
        elseif absent then summary.absent=summary.absent+1
        elseif not record or (record.status~="A" and record.status~="F") then summary.unknown=summary.unknown+1 end
        summary.members[#summary.members+1]={name=name==party.selfName and "You" or (FC.PlainText(name,192) or "Group member"),
            label=label,record=record}
    end
    summary.text=summary.ready .. "/" .. summary.total .. " ready"
    if summary.unknown>0 then summary.text=summary.text .. " · " .. summary.unknown .. " unknown" end
    if summary.absent>0 then summary.text=summary.text .. " · " .. summary.absent .. " without quest" end
    summary.note=not sharing and "Sharing paused; only your own progress is available."
        or (not current and "Waiting for group tracking. The leader can start it in /fc party."
        or "Ready means ready for turn-in. All active group members are counted.")
    return summary
end

function Quests.Render(parent,y)
    local UI,view=FC.UI,FC.UI.View("party")
    y=y or 0
    UI.Label(parent,"Automatic quest progress",0,y,730,true); y=y+31
    if FC.Adventure.sharing and not FC.Adventure.shared then
        UI.Button(parent,"Start group tracking as leader",0,y,250,function() UI.Result(FC.Adventure.StartShared()) end)
        y=y+39
    end
    UI.Button(parent,view.questGroup and "My quests" or "My quests (selected)",0,y,170,function() view.questGroup=false end)
    UI.Button(parent,view.questGroup and "Group quests (selected)" or "Group quests",185,y,180,function() view.questGroup=true end)
    y=y+35
    local note=({ready="Your quest log is up to date.",
        partial="Partial quest log. Expand collapsed quest headers or wait for unavailable progress; unseen quests stay stale.",
        loading="Reading your quest log…",disabled="Tracking paused. Last observations are stale.",
        restricted="Quest log restricted; last observations are stale.",unavailable="Quest log unavailable; retrying automatically."})[Quests.status] or "Quest log unknown."
    UI.Label(parent,note,0,y,730); y=y+42
    local ids,union,peers={}, {},{}
    for id in pairs(Quests.records) do union[id]=true end
    if view.questGroup then
        local ps,party=FC.API.Party()
        for name,peer in pairs(FC.QuestSync and FC.QuestSync.peers or {}) do
            if ps=="ready" and party.membersByName[name] and name~=party.selfName then
                peers[#peers+1]={name=name,peer=peer}
                for id in pairs(peer.expected or {}) do union[id]=true end
                for id in pairs(peer.quests or {}) do union[id]=true end
            end
        end
        table.sort(peers,function(a,b) return a.name<b.name end)
        UI.Label(parent,"Member-reported progress from joined addon users. Unknown and absent quests never count as ready.",0,y,730); y=y+42
    end
    for id in pairs(union) do ids[#ids+1]=id end
    table.sort(ids)
    local now=GetTime()
    if #ids==0 then UI.Label(parent,"No quests currently observed.",0,y); y=y+32 end
    local function details(name,record,label)
        UI.Label(parent,name .. ": " .. label,15,y,700); y=y+30
        if record then
            for i,objective in ipairs(record.objectives or {}) do
                local description=objective.text or ("Objective " .. i)
                if objective.have~=nil and objective.need~=nil then description=description .. " — " .. objective.have .. "/" .. objective.need
                elseif objective.finished==true then description=description .. " — done"
                else description=description .. " — progress unknown" end
                UI.Label(parent,description,30,y,680); y=y+40
            end
            if #(record.objectives or {})==0 then UI.Label(parent,"No objective details reported.",30,y,680); y=y+30 end
        end
    end
    for index=1,math.min(#ids,MAX_QUESTS) do
        local id=ids[index]
        local mine,label=localState(id)
        local summary=label
        if view.questGroup then
            local ready=mine and mine.status=="C" and 1 or 0
            for _,member in ipairs(peers) do
                local record=peerState(member.peer,id,now)
                if record and record.status=="C" then ready=ready+1 end
            end
            summary=ready .. "/" .. (#peers+1) .. " reporting members ready for turn-in"
        end
        UI.Label(parent,(Quests.records[id] and Quests.records[id].title or Quests.Label(id)) .. "  — " .. summary,0,y,610)
        UI.Button(parent,view.questDetails==id and "Hide" or "Details",640,y,93,function()
            view.questDetails=view.questDetails~=id and id or nil
        end)
        y=y+45
        if view.questDetails==id then
            details("You",mine,label)
            if view.questGroup then
                for _,member in ipairs(peers) do
                    local record,state=peerState(member.peer,id,now)
                    details(member.name,record,state)
                end
            end
        end
    end
    if #ids>MAX_QUESTS then UI.Label(parent,(#ids-MAX_QUESTS) .. " additional quest IDs omitted (100-row display limit).",0,y); y=y+34 end
    return y+20
end
