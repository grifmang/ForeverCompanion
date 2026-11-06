local _, FC = ...
local Guide={}
FC.QuestGuide=Guide
local owner,priorQuest,attempted,paused,pickup,issue,pendingStop
local watchTarget,watchState,watchNotice,ownedWatch,ownedWatchType

local function read(fn,...)
    local status,result=FC.SafeRead(fn,...)
    if status=="ready" then return result,true end
    return nil,false
end

local function releaseWatch()
    if not ownedWatch then return true end
    local kind,known=read(C_QuestLog and C_QuestLog.GetQuestWatchType,ownedWatch)
    if not known then return false end
    if kind==ownedWatchType then
        local canRemove=QuestUtil and QuestUtil.CanRemoveQuestWatch
        if canRemove and read(canRemove)~=true then return false end
        if read(C_QuestLog.RemoveQuestWatch,ownedWatch)~=true then return false end
    end
    ownedWatch,ownedWatchType=nil,nil
    return true
end

local function syncWatch(id)
    if watchTarget~=id then
        watchTarget,watchState,watchNotice=id,nil,nil
    end
    if ownedWatch and ownedWatch~=id and not releaseWatch() then
        watchNotice="Waiting to clear the previous native quest watch."
        return
    end
    if not id then
        watchNotice=nil
        return
    end
    local kind,known=read(C_QuestLog and C_QuestLog.GetQuestWatchType,id)
    if not known then
        watchNotice="Native quest tracking is unavailable here."
        return
    end
    if kind~=nil then
        watchState,watchNotice="watched",nil
        return
    end
    if watchState=="watched" then
        watchState,watchNotice="paused","Native quest tracking was stopped in Blizzard's tracker."
        if ownedWatch==id then ownedWatch,ownedWatchType=nil,nil end
    end
    if watchState then return end

    local count=read(C_QuestLog.GetNumQuestWatches)
    local limit=Constants and Constants.QuestWatchConsts and Constants.QuestWatchConsts.MAX_QUEST_WATCHES
    if not FC.Number(count,0,1000) or not FC.Number(limit,1,1000) then
        watchNotice="Native quest tracking is unavailable here."
        return
    end
    if count>=limit then
        watchState,watchNotice="blocked","Blizzard's Objective Tracker is full."
        return
    end
    local added=read(C_QuestLog.AddQuestWatch,id)
    local watchedType=read(C_QuestLog.GetQuestWatchType,id)
    if watchedType~=nil then
        if added==true then ownedWatch,ownedWatchType=id,watchedType end
        watchState,watchNotice="watched",nil
    else
        watchState,watchNotice="blocked","Blizzard could not track this quest."
    end
end

function Guide.OnWatchListChanged(id,added)
    if not FC.Readable(id) or not FC.Readable(added) then return end
    if added==false and id then
        if id==ownedWatch then ownedWatch,ownedWatchType=nil,nil end
        if id==watchTarget then
            watchState,watchNotice="paused","Native quest tracking was stopped in Blizzard's tracker."
        end
    end
    if watchState=="blocked" then watchState=nil end
end

local function questNow()
    local id,ok=read(C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID)
    if ok and (id==nil or FC.Number(id,0,10000000)) then return id or 0 end
end

local function canClaimQuest(current)
    local any,ok=read(C_SuperTrack and C_SuperTrack.IsSuperTrackingAnything)
    if not ok then return false end
    return current~=0 or any==false
end

local function samePin(point)
    if not point then return false end
    local pin=read(C_Map and C_Map.GetUserWaypoint)
    if not FC.Readable(pin) or type(pin)~="table" then return false end
    local status,mapID,x,y=FC.SafeRead(function()
        local pos=pin.position
        return pin.uiMapID,pos:GetXY()
    end)
    return status=="ready" and FC.QuestRoute.Point(mapID,x,y)~=nil and mapID==point.mapID
        and math.abs(point.x-x)<0.00001 and math.abs(point.y-y)<0.00001
end

local function pin(point)
    local current,ok=read(C_Map and C_Map.HasUserWaypoint)
    if not ok then return false,"Map pins are unavailable here." end
    if current and not samePin(pickup) and not (owner and samePin(owner.point)) then
        return false,"Your existing map pin was kept."
    end
    local can=read(C_Map.CanSetUserWaypointOnMap,point.mapID)
    if can~=true then return false,"Map pins are unavailable here." end
    local mapPoint=read(UiMapPoint and UiMapPoint.CreateFromCoordinates,point.mapID,point.x,point.y)
    if not mapPoint then return false,"Map pins are unavailable here." end
    local set=read(C_Map.SetUserWaypoint,mapPoint)
    if set==false or not samePin(point) then return false,"The client did not place a map pin." end
    return true
end

local function restore()
    if not owner or FC.IsCombat() then return end
    local previous=owner
    owner=nil
    if previous.kind=="quest" and questNow()==previous.id then
        local id=priorQuest and priorQuest>0 and read(C_QuestLog and C_QuestLog.IsOnQuest,priorQuest)==true and priorQuest or 0
        FC.SafeRead(C_SuperTrack.SetSuperTrackedQuestID,id)
    elseif previous.kind=="pin" and samePin(previous.point) then
        if read(C_SuperTrack and C_SuperTrack.IsSuperTrackingUserWaypoint)==true then
            FC.SafeRead(C_SuperTrack.SetSuperTrackedUserWaypoint,false)
        end
        FC.SafeRead(C_Map.ClearUserWaypoint)
    end
    priorQuest=nil
end

local function stillOwned()
    if owner.kind=="quest" then return questNow()==owner.id end
    return samePin(owner.point) and read(C_SuperTrack and C_SuperTrack.IsSuperTrackingUserWaypoint)==true
end

local function clientEndedQuest(nextID)
    if not owner or owner.kind~="quest" or owner.id==nextID or questNow()~=0 then return false end
    local record=FC.Quests.records[owner.id]
    return (FC.Quests.removed[owner.id] or (record and record.observed and record.status=="C"))
        and read(C_SuperTrack and C_SuperTrack.IsSuperTrackingAnything)==false
end

function Guide.Tick(row)
    if FC.IsCombat() then return end
    if pendingStop then Guide.Stop() end
    local nextID=row and row.id
    if owner and not stillOwned() then
        if clientEndedQuest(nextID) then
            if not nextID then
                local old=priorQuest
                if old and old>0 and read(C_QuestLog and C_QuestLog.IsOnQuest,old)==true then
                    FC.SafeRead(C_SuperTrack.SetSuperTrackedQuestID,old)
                end
                priorQuest=nil
            end
            owner=nil
        else
            local previous=owner
            owner,priorQuest,paused=nil,nil,true
            if previous.kind=="pin" and samePin(previous.point) then FC.SafeRead(C_Map.ClearUserWaypoint) end
        end
    end
    if not row then
        restore()
        syncWatch(nil)
        attempted,issue=nil,nil
        return
    end
    syncWatch(nextID)
    if watchState=="paused" then
        if priorQuest==nextID then priorQuest=nil end
        restore()
        return
    end
    local point=row.point
    local native=point and not point.approximate
    local key=nextID..":"..tostring(point and point.mapID)..":"..tostring(point and point.x)..":"..tostring(point and point.y)
    if paused or (attempted==key and (not owner or owner.id==nextID)) then return end
    attempted,issue=key,nil
    if owner and owner.kind=="quest" and not native then restore() end
    if owner and owner.kind=="pin" and native then restore() end
    if samePin(pickup) then FC.SafeRead(C_Map.ClearUserWaypoint) end
    pickup=nil
    local current=questNow()
    if current==nil or not canClaimQuest(current) then
        if not owner or owner.kind~="pin" then
            issue=current==nil and "Quest guidance is unavailable." or "Existing map guidance kept."
            return
        end
    end
    if native then
        local original=priorQuest
        if original==nil then original=current end
        FC.SafeRead(C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID,nextID)
        if questNow()==nextID then
            -- A pre-existing selection of this same quest is safe to leave alone on stop.
            priorQuest=original
            owner={kind="quest",id=nextID}
            return
        end
        restore()
    end
    -- A supplemental pin can only claim navigation when it won't displace any
    -- existing native target, including pins, content and vignette tracking.
    if point and (owner and owner.kind=="pin" or read(C_SuperTrack and C_SuperTrack.IsSuperTrackingAnything)==false) then
        local ok,reason=pin(point)
        if ok then
            FC.SafeRead(C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint,true)
            if read(C_SuperTrack and C_SuperTrack.IsSuperTrackingUserWaypoint)==true then
                owner={kind="pin",id=nextID,point=point}
            else
                if samePin(point) then FC.SafeRead(C_Map.ClearUserWaypoint) end
                owner=nil
                issue="Map guidance is unavailable here."
            end
        else
            issue=reason or "Map guidance is unavailable here."
            if owner and owner.id~=nextID then restore() end
        end
    else issue=point and "Existing map guidance kept." or "This quest has no map destination." end
end

function Guide.Resume()
    if owner and not FC.IsCombat() and not stillOwned() then
        local previous=owner
        owner,priorQuest=nil,nil
        if previous.kind=="pin" and samePin(previous.point) then FC.SafeRead(C_Map.ClearUserWaypoint) end
    end
    attempted,paused,issue=nil,nil,nil
    watchState,watchNotice=nil,nil
end

function Guide.Invalidate()
    if issue and not paused then attempted=nil end
    if watchState=="blocked" then watchState=nil end
end

function Guide.WatchPaused(id) return id==watchTarget and watchState=="paused" end

function Guide.HasPending() return owner~=nil or pickup~=nil or pendingStop==true or ownedWatch~=nil end

function Guide.Stop()
    if FC.IsCombat() then pendingStop=true; return end
    restore()
    syncWatch(nil)
    if samePin(pickup) then FC.SafeRead(C_Map.ClearUserWaypoint) end
    pickup,attempted,paused,issue,pendingStop=nil,nil,nil,nil,nil
end

function Guide.ShowDetails(id)
    if FC.IsCombat() then return false,"Quest details are unavailable in combat." end
    if FC.Number(id,1,10000000) then
        local status=FC.SafeRead(QuestMapFrame_OpenToQuestDetails,id)
        if status=="ready" then return true end
    end
    return false,"Open this quest in the quest log."
end

function Guide.ShowPoint(point)
    if FC.IsCombat() then return false,"Map actions are unavailable in combat." end
    if not point then return false,"No map location is available." end
    local ok,message=pin(point)
    if ok then
        if owner and owner.kind=="pin" then owner=nil; paused=true end
        pickup=point
    end
    FC.SafeRead(OpenWorldMap,point.mapID)
    return ok,message
end

function Guide.Status()
    if watchNotice then return watchNotice end
    if paused then return "Map guidance paused after a tracking change." end
    if owner then return owner.kind=="pin" and "Approximate map guidance" or "Quest marked on map" end
    return issue
end
