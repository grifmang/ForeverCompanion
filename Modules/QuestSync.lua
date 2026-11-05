local _, FC = ...
local Sync = {peers={},pending={}}
FC.QuestSync=Sync

local function number(value,minimum,maximum)
    if type(value)~="string" or #value>8 or not value:match("^%d+$") then return nil end
    local n=tonumber(value)
    return FC.Number(n,minimum,maximum) and n or nil
end
local function count(values) local n=0; for _ in pairs(values) do n=n+1 end; return n end
local function message(kind,...)
    local out={"2",kind,Sync.sid,tostring(FC.Quests.generation)}
    for i=1,select("#",...) do out[#out+1]=tostring(select(i,...)) end
    return table.concat(out,"|")
end
local function tuple(objective)
    return (objective.have~=nil and tostring(objective.have) or "?") .. ","
        .. (objective.need~=nil and tostring(objective.need) or "?") .. ","
        .. (objective.finished==nil and "?" or (objective.finished and "1" or "0"))
end
local function recordMessage(record)
    local objectives={}
    for _,objective in ipairs(record.objectives) do objectives[#objectives+1]=tuple(objective) end
    return message("J",record.version,record.id,record.status,table.concat(objectives,";"))
end
local function progressKey(record)
    local out={record.status}
    for _,objective in ipairs(record.objectives) do out[#out+1]=tuple(objective) end
    return table.concat(out,";")
end

function Sync.Reset()
    Sync.peers,Sync.pending,Sync.known={}, {}, {}
    Sync.sid,Sync.context,Sync.channel,Sync.manifest,Sync.manifestDirty=nil,nil,nil,nil,nil
    Sync.lastRevision,Sync.lastReplay,Sync.lastManifest,Sync.requestPending=nil,nil,nil,nil
    Sync.lastMembership=nil
    Sync.lastProgress={}
    Sync.lastSend,Sync.lastRepair=nil,nil
end
Sync.Reset()

function Sync.RemoveMember(member) Sync.peers[member]=nil end

local function put(id,entry)
    if not Sync.pending[id] and count(Sync.pending)>=200 then
        local oldest,version
        for key,item in pairs(Sync.pending) do
            if item.deleted and (not version or item.version<version) then oldest,version=key,item.version end
        end
        if oldest then Sync.pending[oldest]=nil else return end
    end
    Sync.pending[id]=entry
end

local function manifest()
    local source,ids=FC.Quests,{}
    for id,record in pairs(source.records) do if record.observed then ids[#ids+1]=id end end
    table.sort(ids)
    local chunks,current={},""
    for _,id in ipairs(ids) do
        local part=id .. ":" .. source.records[id].version
        if #current+#part+1>180 then chunks[#chunks+1]=current; current="" end
        current=current=="" and part or current .. "," .. part
    end
    chunks[#chunks+1]=current
    local status=source.status=="ready" and source.complete and "R" or (source.status=="partial" and "P" or "U")
    if status=="U" then chunks={""} end
    Sync.manifest={chunks=chunks,index=1,sequence=math.max(1,source.revision),status=status}
    Sync.manifestDirty=nil
end

local function replay()
    for id,record in pairs(FC.Quests.records) do
        if record.observed then put(id,{version=record.version}) end
    end
    Sync.manifestDirty=true
    Sync.lastReplay=GetTime()
end

function Sync.Expire()
    local now=GetTime()
    for _,peer in pairs(Sync.peers) do
        if peer.buffer and now-peer.buffer.started>20 then peer.buffer=nil end
        local fresh=now-peer.seen<=240
        if peer.fresh~=fresh then peer.fresh=fresh; FC.Refresh("party") end
        for _,record in pairs(peer.quests) do
            local expired=not record.observedAt or now-record.observedAt>240
            if record.expired~=expired then record.expired=expired; FC.Refresh("party") end
        end
    end
end

function Sync.Tick(party,session)
    if not session or not FC.Adventure.sharing or not FC.Quests.generation then
        if Sync.sid then Sync.Reset() end
        return
    end
    if session.phase=="syncing" then return end
    if Sync.sid~=session.sessionID or not FC.API.SameGroup(Sync.context,party) then
        Sync.Reset(); Sync.sid=session.sessionID; Sync.context=FC.API.GroupContext(party)
        Sync.channel=party.channel; Sync.requestPending=true
        replay()
    elseif Sync.channel~=party.channel then
        Sync.pending,Sync.manifest={},nil; Sync.channel=party.channel; Sync.requestPending=true; replay()
    end
    local now,source=GetTime(),FC.Quests
    for member,peer in pairs(Sync.peers) do
        if not party.membersByName[member] or party.memberGUIDs[member]~=peer.guid then Sync.peers[member]=nil
        end
    end
    if Sync.lastRevision~=source.revision then
        local known={}
        for id,record in pairs(source.records) do
            if record.observed then
                known[id]=record.version
                if Sync.known[id]~=record.version then put(id,{version=record.version}) end
                if record.status=="A" or record.status=="C" or record.status=="F" then
                    local key=progressKey(record)
                    if Sync.lastProgress[id]~=key then session.lastActivity=now; Sync.lastProgress[id]=key end
                end
            end
        end
        for id,version in pairs(Sync.known) do
            if not known[id] then
                if (source.complete and source.status=="ready") or source.removed[id] then
                    put(id,{deleted=true,version=source.removed[id] or math.max(1,source.revision)})
                    if Sync.lastProgress[id] then session.lastActivity=now; Sync.lastProgress[id]=nil end
                else known[id]=version end
            end
        end
        Sync.known,Sync.lastRevision=known,source.revision
        local observed={}
        for id,record in pairs(source.records) do if record.observed then observed[#observed+1]=id end end
        table.sort(observed)
        local membership=source.status .. ":" .. tostring(source.complete) .. ":" .. table.concat(observed,",")
        if membership~=Sync.lastMembership then Sync.manifestDirty=true; Sync.lastMembership=membership end
    end
    if now-(Sync.lastReplay or -100)>90 then replay() end
    if not Sync.manifest and now-(Sync.lastManifest or -40)>30 then Sync.manifestDirty=true end
    -- Leave a record-drain interval even when membership/status changes rapidly.
    if not Sync.manifest and Sync.manifestDirty and now-(Sync.lastManifest or -10)>=5 then manifest() end
end

function Sync.Pump()
    if not Sync.sid or GetTime()-(Sync.lastSend or -1)<0.5 then return end
    local payload,kind,id
    if Sync.requestPending then payload,kind=message("Q"),"Q"
    elseif Sync.manifest then
        local m=Sync.manifest
        payload,kind=message("M",m.sequence,m.index,#m.chunks,m.status .. ":" .. m.chunks[m.index]),"M"
    else
        for key,item in pairs(Sync.pending) do
            if not id or item.deleted then id=key end
            if item.deleted then break end
        end
        if id then
            local entry,record=Sync.pending[id],FC.Quests.records[id]
            if entry.deleted then payload=message("D",entry.version,id)
            elseif record and record.observed then payload=recordMessage(record)
            else Sync.pending[id]=nil; return end
            kind="J"
        end
    end
    if not payload then return end
    local ok=FC.PartyProtocol.SendQuest(payload,Sync.sid,Sync.context,Sync.channel)
    if not ok then return end
    Sync.lastSend=GetTime()
    if kind=="Q" then Sync.requestPending=nil
    elseif kind=="M" then
        Sync.manifest.index=Sync.manifest.index+1
        if Sync.manifest.index>#Sync.manifest.chunks then Sync.manifest=nil; Sync.lastManifest=GetTime() end
    else Sync.pending[id]=nil end
end

local function objectives(text)
    if type(text)~="string" or #text>136 then return nil end
    local out={}
    if text=="" then return out end
    for part in (text .. ";"):gmatch("(.-);") do
        if #out>=8 then return nil end
        local have,need,done=part:match("^([%d?]+),([%d?]+),([01?])$")
        if not have then return nil end
        local h=have~="?" and number(have,0,999999) or nil
        local n=need~="?" and number(need,0,999999) or nil
        if (have~="?" and not h) or (need~="?" and not n) then return nil end
        local value={have=h,need=n}
        if done~="?" then value.finished=done=="1" end
        out[#out+1]=value
    end
    return out
end

local function peerFor(member,generation,party)
    local peer=Sync.peers[member]
    if peer and peer.guid~=party.memberGUIDs[member] then peer=nil; Sync.peers[member]=nil end
    if peer and generation<peer.generation then return nil end
    if not peer or generation>peer.generation then
        peer={guid=party.memberGUIDs[member],generation=generation,quests={},expected={},deletions={},manifestSequence=0,status="U",seen=0}
        Sync.peers[member]=peer
    end
    return peer
end

local function manifestPart(text)
    if type(text)~="string" or #text>182 then return nil end
    local status,body=text:match("^([RPU]):(.*)$")
    if not status or (status=="U" and body~="") then return nil end
    local ids={}
    if body~="" then
        for part in (body .. ","):gmatch("(.-),") do
            local a,b=part:match("^(%d+):(%d+)$")
            local id,version=number(a,1,10000000),number(b,1,1000000)
            if not id or not version or ids[id] or count(ids)>=100 then return nil end
            ids[id]=version
        end
    end
    return status,ids
end

function Sync.Receive(f,member,party)
    local generation=number(f[4],1,1000000)
    if not generation then return end
    local kind=f[2]
    if kind=="Q" then
        if #f~=4 then return end
        if GetTime()-(Sync.lastReplay or -100)>=60 then replay() end
        return
    end
    local seq=number(f[5],1,1000000)
    if not seq then return end
    if kind=="J" or kind=="D" then
        local id=number(f[6],1,10000000)
        if not id or (kind=="D" and #f~=6) or (kind=="J" and #f~=8) then return end
        local list
        if kind=="J" then
            if not ({A=true,C=true,F=true,U=true,P=true})[f[7]] then return end
            list=objectives(f[8]); if not list then return end
            if f[7]=="C" then
                for _,objective in ipairs(list) do if objective.finished==nil or objective.have==nil or objective.need==nil then return end end
            end
        end
        local peer=peerFor(member,generation,party); if not peer then return end
        if seq<=(peer.deletions[id] or 0) then return end
        local old=peer.quests[id]
        if old and seq<old.version then return end
        if kind=="D" then
            if old or peer.expected[id] then FC.Adventure.shared.lastActivity=GetTime() end
            peer.quests[id]=nil
            if (peer.expected[id] or 0)<=seq then peer.expected[id]=nil end
            peer.deletions[id]=seq
            if count(peer.deletions)>100 then
                local oldest,version
                for key,v in pairs(peer.deletions) do if not version or v<version then oldest,version=key,v end end
                peer.deletionFloor=math.max(peer.deletionFloor or 0,version)
                peer.deletions[oldest]=nil
            end
        else
            if seq<=peer.manifestSequence and peer.expected[id]~=seq then return end
            if seq<=(peer.deletionFloor or 0) and peer.expected[id]~=seq then return end
            if not old and count(peer.quests)>=100 then return end
            local incoming={status=f[7],objectives=list}
            if old and seq==old.version and progressKey(old)~=progressKey(incoming) then return end
            if not old or progressKey(old)~=progressKey(incoming) then FC.Adventure.shared.lastActivity=GetTime() end
            peer.quests[id]={id=id,status=f[7],objectives=list,version=seq,observedAt=GetTime()}
            if seq>peer.manifestSequence and (peer.expected[id] or count(peer.expected)<100) then peer.expected[id]=seq end
        end
        peer.seen=GetTime(); FC.Refresh("party"); return
    elseif kind~="M" or #f~=8 then return end
    local index,total=number(f[6],1,12),number(f[7],1,12)
    local status,ids=manifestPart(f[8])
    if not index or not total or index>total or not status or (status=="U" and total~=1) then return end
    for _,version in pairs(ids) do if version>seq then return end end
    local peer=peerFor(member,generation,party)
    if not peer or seq<peer.manifestSequence or seq<=(peer.deletionFloor or 0) then return end
    local b=peer.buffer
    if b and seq<b.sequence then return end
    if not b or b.sequence~=seq then
        b={sequence=seq,total=total,status=status,parts={},raw={},received=0,started=GetTime()}; peer.buffer=b
    end
    if b.total~=total or b.status~=status then peer.buffer=nil; return end
    if b.parts[index] then if b.raw[index]~=f[8] then peer.buffer=nil end; return end
    b.parts[index],b.raw[index]=ids,f[8]; b.received=b.received+1
    if b.received~=b.total then return end
    local all={}
    for part=1,b.total do
        for id,version in pairs(b.parts[part]) do
            if all[id] or count(all)>=100 then peer.buffer=nil; return end
            all[id]=version
        end
    end
    peer.buffer=nil; peer.status=status; peer.seen=GetTime(); peer.manifestSequence=seq
    peer.manifestObservedAt=GetTime()
    if status=="R" then
        for id,record in pairs(peer.quests) do if record.version<=seq and not all[id] then peer.quests[id]=nil end end
        for id,version in pairs(peer.expected) do if version<=seq then peer.expected[id]=nil end end
        for id,version in pairs(peer.deletions) do if version<=seq and not all[id] then peer.deletions[id]=nil end end
    elseif status=="P" then
        for id,version in pairs(peer.expected) do
            if version<=seq and not all[id] then peer.expected[id]=nil end
        end
        for id,record in pairs(peer.quests) do
            if record.version<=seq and not all[id] then record.observedAt=nil end
        end
    end
    for id,version in pairs(all) do
        if version>(peer.deletions[id] or 0) and (peer.expected[id] or count(peer.expected)<100) then
            peer.expected[id]=math.max(peer.expected[id] or 0,version)
            local record=peer.quests[id]
            if record and record.version==version then record.observedAt=GetTime() end
        end
    end
    FC.Refresh("party")
end
