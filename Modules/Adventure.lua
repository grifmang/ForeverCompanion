local _, FC = ...
local Adventure, UI = {sharing=false, pending=nil, shared=nil, status="Local checklist. Group sharing is off."}, FC.UI
FC.Adventure=Adventure

local function draft() local c=FC.Store.Character(); return c and c.adventure end
local function copyTasks(tasks)
    local out={}
    for _,task in ipairs(tasks) do out[#out+1]={id=task.id,text=task.text,done=false} end
    return out
end

function Adventure.SaveDraft(title,meeting)
    if not FC.Store.CanWrite() then return false,"Saved data is read-only." end
    local label,err=FC.PlainText(title or "",96)
    if not label then return false,err end
    local place,pe=FC.PlainText(meeting or "",192)
    if not place then return false,pe end
    draft().title,draft().meeting=label,place
    return true
end

function Adventure.SaveTask(id,text)
    if not FC.Store.CanWrite() then return nil,"Saved data is read-only." end
    local label,err=FC.Label(text)
    if not label then return nil,err end
    local tasks=draft().tasks
    if id then
        local task=FC.Store.Find(tasks,id)
        if not task then return nil,"Task no longer exists." end
        task.text,task.done=label,false
    else
        if #tasks>=20 then return nil,"Limit: 20 tasks per session." end
        id,err=FC.Store.NewID("party")
        if not id then return nil,err end
        tasks[#tasks+1]={id=id,text=label,done=false}
    end
    return id
end

function Adventure.RemoveTask(id) return FC.Store.Remove(draft().tasks,id) end
function Adventure.SetLocalDone(id,done)
    if not FC.Store.CanWrite() then return false,"Saved data is read-only." end
    local task=FC.Store.Find(draft().tasks,id)
    if not task then return false,"Task no longer exists." end
    task.done=done==true
    return true
end

function Adventure.SetSharing(enabled)
    if not FC.Store.CanWrite() then return false,"Saved data is read-only." end
    if enabled==true then
        local ok,err=FC.PartyProtocol.Enable()
        if not ok then Adventure.sharing=false; Adventure.status=err; return false,err end
        Adventure.sharing=true
        Adventure.retired,Adventure.discoveryContext,Adventure.lastAutoJoin=nil,nil,nil
        Adventure.status="Automatic joining enabled. Waiting for the group leader's checklist."
    else
        -- Send the leave while sharing is still enabled, then stop all protocol work.
        Adventure.LeaveShared(); Adventure.sharing=false; FC.PartyProtocol.Disable()
        Adventure.status="Local checklist. Automatic group joining is off."
    end
    FC.Store.root.settings.partySharing=Adventure.sharing
    return true
end

function Adventure.StartShared()
    if not FC.Store.CanWrite() then return false,"Saved data is read-only." end
    if not Adventure.sharing then return false,"Enable group sharing first." end
    local allowed,reason=FC.API.CanCommunicate()
    if not allowed then return false,reason end
    local ps,party=FC.API.Party()
    if ps~="ready" or not party.channel or party.leader~=party.selfName then return false,"The current group leader starts shared sessions." end
    local localDraft=draft()
    local title,err=FC.Label(localDraft.title=="" and "Adventure Together" or localDraft.title)
    if not title then return false,err end
    local id,idError=FC.Store.NewID("session")
    if not id then return false,idError end
    Adventure.LeaveShared()
    local sid=string.format("%x%x",time(),id)
    if #sid>16 then return false,"Cannot allocate a bounded session ID." end
    Adventure.shared={sessionID=sid,owner=party.selfName,revision=1,title=title,meeting=localDraft.meeting,
        tasks=copyTasks(localDraft.tasks),members={[party.selfName]={}},lastActivity=GetTime(),phase="owner",
        context=FC.API.GroupContext(party),channel=party.channel}
    Adventure.status="Session started. Addon members with automatic joining enabled will join."
    return FC.PartyProtocol.Announce(Adventure.shared)
end

function Adventure.PublishDraft()
    local session=Adventure.shared
    local ps,party=FC.API.Party()
    if not session or ps~="ready" or not Adventure.CheckGroup(party) or session.owner~=party.selfName or session.owner~=party.leader then
        return false,"Only the active session's group leader can publish the local draft."
    end
    local allowed,reason=FC.API.CanCommunicate()
    if not allowed then return false,reason end
    if session.revision>=1000000 then return false,"Revision limit reached; start a new session." end
    local localDraft=draft()
    local title,err=FC.Label(localDraft.title=="" and "Adventure Together" or localDraft.title)
    if not title then return false,err end
    session.revision=session.revision+1
    session.title,session.meeting,session.tasks=title,localDraft.meeting,copyTasks(localDraft.tasks)
    session.members={[party.selfName]={}}
    session.lastActivity=GetTime()
    FC.PartyProtocol.Cancel()
    FC.PartyProtocol.Announce(session)
    return FC.PartyProtocol.Snapshot(session)
end

function Adventure.JoinPending()
    if not FC.Store.CanWrite() or not Adventure.sharing then return false,"Enable group sharing before joining." end
    local allowed,reason=FC.API.CanCommunicate()
    if not allowed then return false,reason end
    local invite=Adventure.pending
    if not invite then return false,"No current group invitation." end
    local ps,party=FC.API.Party()
    if ps~="ready" or not FC.API.SameGroup(invite.context,party) or invite.owner~=party.leader or GetTime()-invite.receivedAt>60 then
        Adventure.pending=nil; return false,"Invitation expired or leader changed. Ask the leader to announce again."
    end
    Adventure.LeaveShared()
    Adventure.pending=nil
    Adventure.shared={sessionID=invite.sessionID,owner=invite.owner,revision=invite.revision,tasks={},
        members={},lastActivity=GetTime(),phase="syncing",context=invite.context,channel=party.channel,
        syncRevision=invite.revision,retryAt=GetTime()+15,retryDelay=15}
    Adventure.lastAutoJoin=GetTime()
    Adventure.status="Joined automatically; receiving the group's checklist. Local draft preserved."
    return FC.PartyProtocol.Request(invite.sessionID,invite.revision)
end

function Adventure.IsRetired(sid,party)
    return Adventure.retired and FC.API.SameGroup(Adventure.retired.context,party) and Adventure.retired.ids[sid]
end

local function retire(session)
    local previous=Adventure.retired and Adventure.retired.context
    if not previous or previous.category~=session.context.category or previous.epoch~=session.context.epoch
        or previous.leaderGUID~=session.context.leaderGUID then
        Adventure.retired={context=session.context,ids={},order={}}
    end
    local retired=Adventure.retired
    if retired.ids[session.sessionID] then return end
    retired.ids[session.sessionID]=true
    retired.order[#retired.order+1]=session.sessionID
    if #retired.order>16 then retired.ids[table.remove(retired.order,1)]=nil end
end

function Adventure.LeaveShared(silent)
    local old=Adventure.shared
    if old and not silent and Adventure.sharing and FC.PartyProtocol then FC.PartyProtocol.SendLeave(old) end
    if old then retire(old) end
    Adventure.shared,Adventure.pending=nil,nil
    if FC.PartyProtocol then FC.PartyProtocol.Cancel() end
    if FC.QuestSync then FC.QuestSync.Reset() end
    Adventure.status="Shared session closed. Local draft preserved."
    return true
end

function Adventure.SetReady(taskID,ready)
    local session=Adventure.shared
    if not session or session.phase=="syncing" then return false,"Wait for a complete shared checklist." end
    local ps,party=FC.API.Party()
    if ps~="ready" or not Adventure.CheckGroup(party) or not FC.Store.Find(session.tasks,taskID) then return false,"Shared task unavailable." end
    local allowed,reason=FC.API.CanCommunicate()
    if not allowed then return false,reason end
    session.members[party.selfName]=session.members[party.selfName] or {}
    session.members[party.selfName][taskID]=ready==true
    session.lastActivity=GetTime()
    return FC.PartyProtocol.Ready(session.sessionID,session.revision,taskID,ready==true)
end

-- Called at every protocol boundary as well as roster events, so stale traffic
-- cannot rely on event ordering to escape into another group.
function Adventure.CheckGroup(party)
    local state=Adventure.shared or Adventure.pending
    if not state then return true end
    if not FC.API.SameGroup(state.context,party) or state.owner~=party.leader then
        Adventure.LeaveShared(true)
        Adventure.discoveryContext=nil
        Adventure.status="Group or leader changed. Waiting for the new group's checklist. Local draft preserved."
        return false
    end
    if Adventure.pending and not FC.API.SameGroup(Adventure.pending.context,party) then Adventure.pending=nil end
    if Adventure.shared and Adventure.shared.channel~=party.channel then
        FC.PartyProtocol.Cancel()
        Adventure.shared.channel=party.channel
        Adventure.shared.needsRecovery=true
        Adventure.status="Group format changed. Recovering the shared checklist."
    end
    if Adventure.shared then
        for member in pairs(Adventure.shared.members) do
            if not party.membersByName[member] then
                Adventure.shared.members[member]=nil
                if Adventure.shared.seen then Adventure.shared.seen[member]=nil end
            end
        end
    end
    return true
end

function Adventure.TryAutoJoin()
    if not Adventure.sharing or not Adventure.pending then return end
    local now=GetTime()
    if now<(Adventure.nextJoinAttempt or 0) or now-(Adventure.lastAutoJoin or -10)<10 then return end
    Adventure.nextJoinAttempt=now+2
    Adventure.JoinPending()
end

function Adventure.OnPartyChanged()
    if not Adventure.shared and not Adventure.pending then return end
    local ps,party=FC.API.Party()
    if ps~="ready" then Adventure.status="Group roster unavailable or restricted. Sharing paused."; return end
    Adventure.CheckGroup(party)
end

function Adventure.Tick()
    local now=GetTime()
    if Adventure.pending and now-Adventure.pending.receivedAt>60 then Adventure.pending=nil; FC.Refresh("party") end
    if Adventure.shared and now-Adventure.shared.lastActivity>14400 then
        Adventure.LeaveShared(); Adventure.status="Shared session expired after four hours without activity."; FC.Refresh("party")
    end
    Adventure.TryAutoJoin()
end

function Adventure.Enable()
    -- Preserve explicit opt-outs; defaults are normalized by Store.Initialize.
    Adventure.retired,Adventure.discoveryContext,Adventure.lastAutoJoin,Adventure.nextJoinAttempt=nil,nil,nil,nil
    Adventure.sharing=FC.Store.root.settings.partySharing==true and FC.Store.CanWrite()
    FC.Quests.Enable()
    if FC.QuestLogUI then FC.QuestLogUI.Enable() end
    if FC.ObjectiveTrackerUI then FC.ObjectiveTrackerUI.Enable() end
    if Adventure.sharing then
        local ok,err=FC.PartyProtocol.Enable()
        if not ok then Adventure.sharing=false; Adventure.status=err
        else Adventure.status="Automatic joining enabled. Looking for the group leader's checklist." end
    end
end

function Adventure.Disable()
    Adventure.LeaveShared(); Adventure.sharing=false; FC.PartyProtocol.Disable()
    Adventure.discoveryContext=nil
    FC.Quests.Disable()
    if FC.QuestLogUI then FC.QuestLogUI.Disable() end
    if FC.ObjectiveTrackerUI then FC.ObjectiveTrackerUI.Disable() end
end

function Adventure.Render(parent)
    local view,localDraft=UI.View("party"),draft()
    UI.Label(parent,"Prepare the next adventure",0,0,730,true)
    UI.Check(parent,"Automatically join group sessions and share quest progress and checklist readiness",0,31,Adventure.sharing,function(enabled)
        UI.Result(Adventure.SetSharing(enabled))
    end,FC.Store.CanWrite())
    UI.Label(parent,Adventure.status,0,69)
    local offset=FC.Quests.Render(parent,111)-111
    UI.Input(parent,"Local session name (optional)",0,111+offset,360,view.title or localDraft.title,96,function(t) view.title=t end)
    UI.Input(parent,"Meeting point",380,111+offset,355,view.meeting or localDraft.meeting,192,function(t) view.meeting=t end)
    UI.Button(parent,"Save local details",0,169+offset,170,function()
        UI.Result(Adventure.SaveDraft(view.title or localDraft.title,view.meeting or localDraft.meeting))
    end,FC.Store.CanWrite())
    UI.Input(parent,"Optional manual checklist task",0,209+offset,570,view.task or "",96,function(t) view.task=t end)
    UI.Button(parent,view.taskID and "Save task" or "Add task",590,227+offset,143,function()
        local id,err=Adventure.SaveTask(view.taskID,view.task or "")
        UI.Result(id,err); if id then view.taskID,view.task=nil,"" end
    end,FC.Store.CanWrite())
    local y=273+offset
    if #localDraft.tasks==0 then UI.Label(parent,"Quests appear automatically above. Add optional preparation tasks here.",0,y); y=y+45 end
    for _,task in ipairs(localDraft.tasks) do
        local row=task
        UI.Check(parent,row.text,0,y,row.done,function(done) UI.Result(Adventure.SetLocalDone(row.id,done)) end,FC.Store.CanWrite())
        UI.Button(parent,"Edit",553,y,76,function() view.taskID,view.task=row.id,row.text; UI.scroll:SetVerticalScroll(0) end,FC.Store.CanWrite())
        UI.Button(parent,"Remove",641,y,92,function() UI.Result(Adventure.RemoveTask(row.id)) end,FC.Store.CanWrite()); y=y+40
    end
    UI.Label(parent,"Shared session — local draft stays separate",0,y+7,730,true); y=y+46
    UI.Button(parent,"Start as leader",0,y,155,function() UI.Result(Adventure.StartShared()) end,Adventure.sharing)
    y=y+40
    local session=Adventure.shared
    if session then
        UI.Button(parent,"Leave and pause sharing",0,y,180,function() UI.Result(Adventure.SetSharing(false)) end)
        local ps,party=FC.API.Party()
        if ps=="ready" and session.owner==party.selfName then
            UI.Button(parent,"Publish local draft",195,y,180,function() UI.Result(Adventure.PublishDraft()) end)
            UI.Button(parent,"Announce again",390,y,160,function() UI.Result(FC.PartyProtocol.Announce(session)) end)
        else
            UI.Button(parent,"Request again",195,y,160,function() UI.Result(FC.PartyProtocol.Request(session.sessionID,session.revision)) end)
        end
        y=y+44
        UI.Label(parent,(session.title or "Waiting for checklist") .. "  / revision " .. session.revision .. "  / " .. session.phase,0,y,730,true); y=y+33
        UI.Label(parent,"Meet: " .. (session.meeting or "Waiting for owner"),0,y); y=y+39
        for _,task in ipairs(session.tasks) do
            local row=task
            local members,ready=0,0
            for _,states in pairs(session.members) do members=members+1; if states[row.id]==true then ready=ready+1 end end
            local mine=ps=="ready" and session.members[party.selfName]
            UI.Check(parent,row.text .. "  (" .. ready .. "/" .. members .. " joined ready)",0,y,mine and mine[row.id]==true,function(value)
                local ok,err=Adventure.SetReady(row.id,value)
                UI.Result(ok,err,"Readiness queued; peer receipt is not yet confirmed.")
            end,session.phase~="syncing" and Adventure.sharing and FC.Store.CanWrite()); y=y+40
        end
        UI.Label(parent,"Unreported readiness is unknown. Only joined addon users are counted; no inventory or gold is shared.",0,y); y=y+45
    elseif Adventure.pending then
        UI.Label(parent,"Waiting to join " .. Adventure.pending.owner .. " automatically when communication is available.",0,y); y=y+42
    else UI.Label(parent,"Group members join automatically. The leader saves a checklist and chooses Start as leader.",0,y); y=y+42 end
    UI.Height(y+35)
end

function Adventure.OnEvent(event,...)
    FC.Quests.OnEvent(event,...)
    if FC.QuestLogUI then FC.QuestLogUI.OnEvent(event,...) end
    if FC.ObjectiveTrackerUI then FC.ObjectiveTrackerUI.OnEvent(event,...) end
    if event=="GROUP_ROSTER_UPDATE" or event=="PARTY_LEADER_CHANGED" or event=="PLAYER_REGEN_ENABLED"
        or event=="PLAYER_ENTERING_WORLD" or event=="GROUP_JOINED" or event=="GROUP_LEFT" then Adventure.OnPartyChanged(); FC.Refresh("party")
    elseif event=="PLAYER_REGEN_DISABLED" and Adventure.shared then Adventure.status="Sharing paused during combat."; FC.Refresh("party") end
end
FC.RegisterModule("party",{title="Adventure Together",Render=Adventure.Render,Enable=Adventure.Enable,Disable=Adventure.Disable,OnEvent=Adventure.OnEvent})
