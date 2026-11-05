local _, FC = ...
local Protocol,Adventure={prefix="FCompanion1",queue={},enabled=false,rates={},requests={}},FC.Adventure
FC.PartyProtocol=Protocol

local function number(text,minimum,maximum)
    if type(text)~="string" or #text>7 or not text:match("^%d+$") then return nil end
    local n=tonumber(text)
    return FC.Number(n,minimum,maximum) and n or nil
end
local function sessionID(text) return type(text)=="string" and #text<=16 and #text>0 and text:match("^%w+$") and text or nil end
local function hex(text) return (text:gsub(".",function(c) return string.format("%02X",c:byte()) end)) end
local function unhex(text)
    if type(text)~="string" or #text>192 or #text%2~=0 or text:find("[^%x]") then return nil end
    return (text:gsub("%x%x",function(pair) return string.char(tonumber(pair,16)) end))
end
local function fields(text)
    local out={}
    for part in (text .. "|"):gmatch("(.-)|") do
        out[#out+1]=part
        if #out>8 then return nil end
    end
    return out
end
local function packet(kind,sid,revision,...)
    local result={"1",kind,sid,tostring(revision)}
    for i=1,select("#",...) do result[#result+1]=tostring(select(i,...)) end
    return table.concat(result,"|")
end

function Protocol.Cancel()
    Protocol.queue,Protocol.buffer={},nil
    Protocol.snapshotQueued,Protocol.snapshotDue,Protocol.lastSnapshotKey,Protocol.lastSnapshotAt=nil,nil,nil,nil
    Protocol.lastHeartbeat=nil
    Protocol.lastAnnounceKey,Protocol.lastAnnounceAt=nil,nil
end

local function queue(message,discovery)
    if not Protocol.enabled or #message>240 or #Protocol.queue>=128 then return false,"Sharing queue unavailable or full." end
    if not Adventure.sharing or not FC.IsEnabled("party") then return false,"Group sharing is disabled." end
    local status,party=FC.API.Party()
    local session=Adventure.shared
    if status~="ready" or not party.channel or not Adventure.CheckGroup(party) then
        return false,"Current group session unavailable."
    end
    if discovery then
        if message~=packet("H","0",1) or session then return false,"Discovery unavailable." end
    elseif not session or not FC.API.SameGroup(session.context,party) then return false,"Current group session unavailable." end
    Protocol.queue[#Protocol.queue+1]={text=message,queuedAt=GetTime(),
        context=discovery and FC.API.GroupContext(party) or session.context,
        channel=party.channel,sessionID=session and session.sessionID,discovery=discovery==true}
    return true
end

local function transmit(message,context,channel,sid,discovery,version)
    if not Protocol.enabled or not Adventure.sharing or not FC.IsEnabled("party") then return false,"Group sharing is disabled." end
    local allowed,reason,party=FC.API.CanCommunicate()
    if not allowed then return false,reason end
    local session=Adventure.shared
    if not Adventure.CheckGroup(party) or not FC.API.SameGroup(context,party) or channel~=party.channel then
        return false,"Group changed; stale update discarded."
    end
    if version then
        if not FC.Updates or not FC.Updates.ValidMessage(message) then return false,"Invalid version announcement." end
    elseif discovery then
        if message~=packet("H","0",1) or session then return false,"Stale discovery discarded." end
    elseif not session or session.sessionID~=sid then return false,"Stale session discarded." end
    local success=Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success
    if success==nil then return false,"Client message-result enum unavailable." end
    local status,result=FC.SafeRead(C_ChatInfo.SendAddonMessage,Protocol.prefix,message,channel)
    if status~="ready" or result~=success then return false,"Client did not accept the addon message." end
    Protocol.lastSend=GetTime()
    return true
end

function Protocol.SendQuest(message,sid,context,channel)
    if type(message)~="string" or #message>240 or message:sub(1,2)~="2|"
        or GetTime()-(Protocol.lastSend or -1)<0.25 then return false end
    return transmit(message,context,channel,sid)
end

function Protocol.SendVersion(message,party)
    if not FC.Updates or not FC.Updates.ValidMessage(message) or not party or not party.channel
        or GetTime()-(Protocol.lastSend or -1)<0.25 then return false end
    return transmit(message,FC.API.GroupContext(party),party.channel,nil,false,true)
end

function Protocol.Enable()
    if not C_ChatInfo or not C_ChatInfo.RegisterAddonMessagePrefix
        or not Enum or not Enum.RegisterAddonMessagePrefixResult then
        return false,"Client addon message registration unavailable. Local checklist still works."
    end
    local status,registered=FC.SafeRead(C_ChatInfo.IsAddonMessagePrefixRegistered,Protocol.prefix)
    if status~="ready" or registered~=true then
        local rs,result=FC.SafeRead(C_ChatInfo.RegisterAddonMessagePrefix,Protocol.prefix)
        if rs~="ready" or result~=Enum.RegisterAddonMessagePrefixResult.Success then
            return false,"Client could not register group sharing. Local checklist still works."
        end
    end
    Protocol.enabled=true
    return true
end

function Protocol.Disable() Protocol.enabled=false; Protocol.Cancel(); Protocol.rates,Protocol.requests={},{} end

function Protocol.Announce(session,automatic)
    local status,party=FC.API.Party()
    if status~="ready" or not Adventure.CheckGroup(party) or not FC.API.SameGroup(session.context,party)
        or session.owner~=party.selfName or session.owner~=party.leader then return false,"Only the session's group leader can announce." end
    local message=packet("A",session.sessionID,session.revision,#session.tasks)
    for _,entry in ipairs(Protocol.queue) do if entry.text==message then return true end end
    local key=session.sessionID .. ":" .. session.revision
    if automatic and Protocol.lastAnnounceKey==key and GetTime()-(Protocol.lastAnnounceAt or 0)<10 then return true end
    local ok,err=queue(message)
    if ok then Protocol.lastAnnounceKey,Protocol.lastAnnounceAt=key,GetTime() end
    return ok,err
end

function Protocol.Discover()
    local message=packet("H","0",1)
    for _,entry in ipairs(Protocol.queue) do if entry.discovery then return true end end
    return queue(message,true)
end

function Protocol.Request(sid,revision)
    for _,pending in ipairs(Protocol.queue) do
        if pending.text==packet("Q",sid,revision) then return true end
    end
    return queue(packet("Q",sid,revision))
end

function Protocol.Snapshot(session,automatic)
    local status,party=FC.API.Party()
    if status~="ready" or not Adventure.CheckGroup(party) or not FC.API.SameGroup(session.context,party)
        or session.owner~=party.selfName or session.owner~=party.leader then return false,"Only the current group leader can publish a snapshot." end
    local key=session.sessionID .. ":" .. session.revision
    local now=GetTime()
    if Protocol.snapshotQueued==key then
        -- A late requester may have missed B. One follow-up serves all such peers.
        if automatic then Protocol.snapshotDue=Protocol.snapshotDue or now+10 end
        return true
    end
    if automatic and Protocol.lastSnapshotKey==key and now-(Protocol.lastSnapshotAt or 0)<10 then
        Protocol.snapshotDue=Protocol.lastSnapshotAt+10
        return true
    end
    local parts={{kind="N",key=0,text=session.title},{kind="M",key=1,text=session.meeting:sub(1,96)},
        {kind="M",key=2,text=session.meeting:sub(97,192)}}
    for _,task in ipairs(session.tasks) do parts[#parts+1]={kind="T",key=task.id,text=task.text} end
    if #Protocol.queue+#parts+2>128 then return false,"Sharing queue full. Try publishing again shortly." end
    local messages={packet("B",session.sessionID,session.revision,#parts,#session.tasks)}
    for index,part in ipairs(parts) do
        messages[#messages+1]=packet("P",session.sessionID,session.revision,index,part.kind,part.key,hex(part.text))
    end
    messages[#messages+1]=packet("E",session.sessionID,session.revision,#parts)
    for _,message in ipairs(messages) do if #message>240 then return false,"Session text exceeds packet limits." end end
    for _,message in ipairs(messages) do
        local ok,err=queue(message)
        if not ok then return false,err end
    end
    Protocol.snapshotQueued,Protocol.lastSnapshotKey,Protocol.lastSnapshotAt=key,key,now
    Protocol.snapshotDue=nil
    Protocol.queue[#Protocol.queue].snapshotEnd=key
    return true
end

function Protocol.Ready(sid,revision,taskID,ready)
    return queue(packet("R",sid,revision,taskID,ready and 1 or 0))
end

function Protocol.ReplayOwn(session)
    local status,party=FC.API.Party()
    if status~="ready" or session.phase=="syncing" then return false end
    if not Adventure.CheckGroup(party) or not FC.API.SameGroup(session.context,party) then return false end
    -- A fresh replay replaces queued heartbeats, rather than multiplying with peers.
    for i=#Protocol.queue,1,-1 do if Protocol.queue[i].replay then table.remove(Protocol.queue,i) end end
    local states=session.members[party.selfName] or {}
    local messages={packet("K",session.sessionID,session.revision)}
    for _,task in ipairs(session.tasks) do
        if type(states[task.id])=="boolean" then
            messages[#messages+1]=packet("S",session.sessionID,session.revision,task.id,states[task.id] and 1 or 0)
        end
    end
    if #Protocol.queue+#messages>128 then return false end
    for _,message in ipairs(messages) do
        local ok=queue(message)
        if not ok then return false end
        Protocol.queue[#Protocol.queue].replay=true
    end
    Protocol.lastHeartbeat=GetTime()
    return true
end

local function recoverRevision(session,revision)
    if revision<=(session.syncRevision or session.revision) then return end
    Protocol.Cancel()
    session.members={}; session.phase="syncing"
    session.syncRevision,session.retryDelay,session.retryAt=revision,15,GetTime()+15
    Adventure.status="Owner has a newer revision. Requesting the complete checklist; readiness is unknown."
    Protocol.Request(session.sessionID,revision)
    FC.Refresh("party")
end

function Protocol.SendLeave(session)
    -- One explicit opt-out message can be sent before disabling the queue.
    if not Protocol.enabled then return false,"Sharing disabled." end
    if GetTime()-(Protocol.lastSend or -1)>0.25 then
        return transmit(packet("L",session.sessionID,session.revision),session.context,session.channel,session.sessionID)
    end
    return false,"Opt-out could not be sent; peer readiness will expire."
end

local function acceptSnapshot()
    local b,session=Protocol.buffer,Adventure.shared
    if not b or not b.ended or not session or b.received~=b.count then return end
    local title,m1,m2,tasks,ids=nil,nil,nil,{},{}
    for index=1,b.count do
        local part=b.parts[index]
        if not part then return end
        if part.kind=="N" and part.key==0 and not title then title=part.text
        elseif part.kind=="M" and part.key==1 and m1==nil then m1=part.text
        elseif part.kind=="M" and part.key==2 and m2==nil then m2=part.text
        elseif part.kind=="T" and part.key>=1 and not ids[part.key] then
            local label=FC.Label(part.text)
            if not label then Protocol.buffer=nil; return end
            ids[part.key]=true; tasks[#tasks+1]={id=part.key,text=label}
        else Protocol.buffer=nil; return end
    end
    local label=FC.Label(title)
    local meeting=m1~=nil and m2~=nil and FC.PlainText(m1 .. m2,192) or nil
    if not label or not meeting or #tasks~=b.taskCount then Protocol.buffer=nil; return end
    local ps,party=FC.API.Party()
    if ps~="ready" or not Adventure.CheckGroup(party) or session.owner~=party.leader or session.sessionID~=b.sid
        or (session.syncRevision or session.revision)>b.revision then Protocol.buffer=nil; return end
    local changed=session.revision~=b.revision or session.phase=="syncing"
    session.title,session.meeting,session.tasks,session.revision=label,meeting,tasks,b.revision
    session.phase="current"
    session.syncRevision,session.retryAt,session.retryDelay=nil,nil,nil
    if changed then session.lastActivity=GetTime() end
    if changed then session.members={} end
    session.members[session.owner]=session.members[session.owner] or {}
    session.members[party.selfName]=session.members[party.selfName] or {}
    session.seen=session.seen or {}; session.seen[session.owner]=GetTime(); session.seen[party.selfName]=GetTime()
    Protocol.buffer=nil
    Adventure.status="Owner's complete checklist received. Update your own readiness below."
    if changed then Protocol.ReplayOwn(session) end
    FC.Refresh("party")
end

function Protocol.Receive(prefix,payload,channel,sender)
    if not Protocol.enabled or not FC.IsEnabled("party") or not Adventure.sharing then return end
    if not FC.Readable(prefix) or not FC.Readable(payload) or not FC.Readable(channel) or not FC.Readable(sender) then return end
    if prefix~=Protocol.prefix or (channel~="PARTY" and channel~="RAID" and channel~="INSTANCE_CHAT")
        or type(payload)~="string" or #payload>240 then return end
    if FC.IsCombat() then return end
    local ps,party=FC.API.Party()
    if ps~="ready" or not party.channel or not Adventure.CheckGroup(party) or channel~=party.channel then return end
    local member=FC.API.Sender(sender,party)
    if not member or member==party.selfName then return end
    local now=GetTime()
    local rate=Protocol.rates[member]
    if not rate or now-rate.started>=10 then rate={started=now,count=0}; Protocol.rates[member]=rate end
    rate.count=rate.count+1
    if rate.count>80 then return end
    local f=fields(payload)
    if not f or not sessionID(f[3]) then return end
    if f[1]=="3" then
        if #f==4 and f[2]=="V" and f[3]=="0" and FC.Updates then FC.Updates.Receive(f[4],member,party) end
        return
    elseif f[1]=="2" then
        local session=Adventure.shared
        if session and session.sessionID==f[3] and session.owner==party.leader and session.members[member] then
            FC.QuestSync.Tick(party,session)
            FC.QuestSync.Receive(f,member,party)
        end
        return
    elseif f[1]~="1" then return end
    local rev=number(f[4],1,1000000)
    if not rev then return end
    local kind,sid,session=f[2],f[3],Adventure.shared
    if kind=="H" then
        if #f~=4 or sid~="0" or rev~=1 then return end
        if session and session.owner==party.selfName then Protocol.Announce(session,true) end
        return
    end
    if kind=="A" then
        local count=number(f[5],0,20)
        if #f~=5 or not count or member~=party.leader then return end
        if session and session.owner==member and session.sessionID==sid then
            recoverRevision(session,rev); return
        end
        if Adventure.IsRetired(sid,party) then return end
        Adventure.pending={sessionID=sid,revision=rev,owner=member,receivedAt=now,context=FC.API.GroupContext(party)}
        Adventure.status="Group checklist found. Joining automatically when communication is available."
        Adventure.TryAutoJoin()
        FC.Refresh("party"); return
    end
    if not session or session.sessionID~=sid or session.owner~=party.leader then return end
    if kind=="Q" then
        if #f~=4 or session.owner~=party.selfName or rev>session.revision then return end
        if now-(Protocol.requests[member] or -20)<10 then return end
        Protocol.requests[member]=now
        Protocol.Snapshot(session,true)
        return
    end
    if member==session.owner then
        if rev<(session.syncRevision or session.revision) then return end
        if kind=="L" and #f==4 then
            Adventure.LeaveShared(true); Adventure.status="Owner ended the session. Local draft preserved."; FC.Refresh("party"); return
        elseif kind=="K" and #f==4 and rev>session.revision then
            recoverRevision(session,rev); return
        elseif kind=="B" then
            local count,taskCount=number(f[5],3,23),number(f[6],0,20)
            if #f~=6 or not count or not taskCount or count~=taskCount+3 then return end
            if Protocol.buffer and Protocol.buffer.revision>rev then return end
            Protocol.buffer={sid=sid,revision=rev,owner=member,count=count,taskCount=taskCount,
                started=now,parts={},received=0,ended=false}
            if rev>session.revision then
                if rev>(session.syncRevision or session.revision) then
                    session.syncRevision,session.retryDelay,session.retryAt=rev,15,now+15
                end
                session.members={}; session.phase="syncing"; Adventure.status="Owner changed the checklist. Waiting for a complete update."; FC.Refresh("party")
            end
            return
        elseif kind=="P" then
            local b=Protocol.buffer
            if #f~=8 or not b or b.sid~=sid or b.revision~=rev or b.owner~=member then return end
            local index,key=number(f[5],1,b.count),number(f[7],0,1000000)
            local text=unhex(f[8])
            if not index or not key or text==nil or (f[6]~="N" and f[6]~="M" and f[6]~="T") then return end
            local old=b.parts[index]
            if old then
                if old.kind~=f[6] or old.key~=key or old.text~=text then Protocol.buffer=nil end
                return
            end
            b.parts[index]={kind=f[6],key=key,text=text}; b.received=b.received+1
            acceptSnapshot(); return
        elseif kind=="E" then
            local b=Protocol.buffer
            if #f~=5 or not b or b.revision~=rev or b.sid~=sid or number(f[5],3,23)~=b.count then return end
            b.ended=true; acceptSnapshot(); return
        end
    end
    if rev~=session.revision or session.phase=="syncing" then return end
    if kind=="K" and #f==4 then
        local newlySeen=session.members[member]==nil
        session.members[member]=session.members[member] or {}
        session.seen=session.seen or {}; session.seen[member]=now
        Adventure.status="Joined participant confirmed the current revision."
        if newlySeen and not party.raid then Protocol.ReplayOwn(session) end
    elseif (kind=="R" or kind=="S") and #f==6 then
        local id=number(f[5],1,1000000)
        if not id or (f[6]~="0" and f[6]~="1") or not session.members[member] or not FC.Store.Find(session.tasks,id) then return end
        session.members[member][id]=f[6]=="1"
        session.seen=session.seen or {}; session.seen[member]=now
        if kind=="R" then session.lastActivity=now end
    elseif kind=="L" and #f==4 then
        session.members[member]=nil
        FC.QuestSync.RemoveMember(member)
        if session.seen then session.seen[member]=nil end
    else return end
    FC.Refresh("party")
end

function Protocol.Tick()
    FC.Quests.Tick()
    FC.QuestSync.Expire()
    if not Protocol.enabled then return end
    local now=GetTime()
    Adventure.Tick()
    local ps,party=FC.API.Party()
    if ps~="ready" then return end
    if not Adventure.CheckGroup(party) then return end
    FC.QuestSync.Tick(party,Adventure.shared)
    if Protocol.buffer and now-Protocol.buffer.started>15 then
        Protocol.buffer=nil; Adventure.status="Incomplete snapshot expired. Request again; local draft is preserved."; FC.Refresh("party")
    end
    for member in pairs(Protocol.rates) do
        if not party.membersByName[member] then Protocol.rates[member]=nil; Protocol.requests[member]=nil end
    end
    local session=Adventure.shared
    local stagger=0
    for i=1,#party.selfName do stagger=(stagger+party.selfName:byte(i))%15 end
    if not session and not Adventure.pending and party.channel and party.leader~=party.selfName then
        if not FC.API.SameGroup(Adventure.discoveryContext,party) or Adventure.discoveryChannel~=party.channel then
            Adventure.discoveryContext,Adventure.discoveryChannel=FC.API.GroupContext(party),party.channel
            Adventure.discoveryAttempts,Adventure.nextDiscovery=0,now+stagger%3
        end
        if Adventure.discoveryAttempts<3 and now>=Adventure.nextDiscovery then
            if Protocol.Discover() then Adventure.discoveryAttempts=Adventure.discoveryAttempts+1 end
            Adventure.nextDiscovery=now+30+stagger%5
        end
    end
    if session then
        if party.channel then
            if session.needsRecovery then
                session.needsRecovery=nil
                if session.owner==party.selfName then Protocol.Announce(session); Protocol.Snapshot(session)
                else Protocol.Request(session.sessionID,session.revision) end
                Protocol.ReplayOwn(session)
            end
            if Protocol.snapshotDue and now>=Protocol.snapshotDue then
                Protocol.snapshotDue=nil
                Protocol.Snapshot(session,true)
            end
            if session.phase=="syncing" and not Protocol.buffer and now>=(session.retryAt or 0) then
                if Protocol.Request(session.sessionID,session.syncRevision or session.revision) then
                    session.retryDelay=math.min((session.retryDelay or 15)*2,60)
                    session.retryAt=now+session.retryDelay+stagger%5
                else session.retryAt=now+5 end
            end
            session.seen=session.seen or {}
            for member,observed in pairs(session.seen) do
                if member~=party.selfName and now-observed>120 then session.members[member]=nil; session.seen[member]=nil; FC.Refresh("party") end
            end
            -- Heartbeat freshness does not extend the four-hour user-activity expiry.
            if session.phase~="syncing" and now-(Protocol.lastHeartbeat or -80)>60+stagger then
                if session.owner==party.selfName then Protocol.Announce(session,true) end
                Protocol.ReplayOwn(session)
            end
        end
    end
    if now-(Protocol.lastSend or -1)<0.25 then return end
    local allowed,reason=FC.API.CanCommunicate()
    if not allowed then Adventure.status=reason; return end
    if #Protocol.queue==0 then
        if FC.Updates and FC.Updates.Pump(party) then return end
        FC.QuestSync.Pump(); return
    end
    local entry=Protocol.queue[1]
    if not FC.API.SameGroup(entry.context,party) or entry.channel~=party.channel then table.remove(Protocol.queue,1); return end
    if now-entry.queuedAt>60 then
        Protocol.Cancel()
        if Adventure.shared then Adventure.shared.needsRecovery=true end
        Adventure.status="Queued update expired. Recovering the checklist when sharing resumes."
        FC.Refresh("party"); return
    end
    local ok,err=transmit(entry.text,entry.context,entry.channel,entry.sessionID,entry.discovery)
    if ok then
        table.remove(Protocol.queue,1)
        if entry.snapshotEnd then Protocol.snapshotQueued=nil end
    else Protocol.lastSend=now; Adventure.status=err end
end
