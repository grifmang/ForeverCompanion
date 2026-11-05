local _, FC = ...
local Route={sections={},byKey={},nearby={},view="route",dirty=true}
FC.QuestRoute=Route
local TURN,INSTANCE,UNKNOWN="turnin","instance","unknown"
local labels={[TURN]="Turn in",[INSTANCE]="Instances",[UNKNOWN]="Location unknown"}

local function value(fn,...)
    local status,result=FC.SafeRead(fn,...)
    if status=="ready" then return result end
end

local function field(object,key)
    if not FC.Readable(object) or type(object)~="table" then return nil end
    return value(function() return object[key] end)
end

local function finite(n,min,max)
    return FC.Readable(n) and type(n)=="number" and n==n and n>=min and n<=max
end

function Route.Point(mapID,x,y)
    if FC.Number(mapID,1,10000000) and finite(x,0,1) and finite(y,0,1) and (x~=0 or y~=0) then
        return {mapID=mapID,x=x,y=y}
    end
end

local function coords(v)
    if not FC.Readable(v) or type(v)~="table" then return end
    local get=field(v,"GetXY")
    local status,x,y=FC.SafeRead(get,v)
    if status=="ready" and finite(x,-100000000,100000000) and finite(y,-100000000,100000000) then return x,y end
end

local function world(mapID,v)
    if not FC.Readable(v) or type(v)~="table" then return end
    local status,space,pos=FC.SafeRead(C_Map and C_Map.GetWorldPosFromMapPos,mapID,v)
    if status~="ready" or not FC.Number(space,0,10000000) then return end
    local x,y=coords(pos)
    if x then return {space=space,x=x,y=y} end
end

local function playerWorld(mapID)
    if not mapID then return end
    local pos=value(C_Map and C_Map.GetPlayerMapPosition,mapID,"player")
    local x,y=coords(pos)
    if Route.Point(mapID,x,y) then return world(mapID,pos) end
end

local function distance(point,player)
    if not player or not point then return nil end
    if point.world==nil then
        point.world=world(point.mapID,value(CreateVector2D,point.x,point.y)) or false
    end
    local dest=point.world
    if not dest or dest.space~=player.space then return nil end
    local dx,dy=dest.x-player.x,dest.y-player.y
    return math.sqrt(dx*dx+dy*dy)
end

local function mapInfo(mapID) return value(C_Map and C_Map.GetMapInfo,mapID) end
local function area(point)
    local info=mapInfo(point.mapID)
    local mapType=field(info,"mapType")
    local types=Enum and Enum.UIMapType
    if types and types.Dungeon and mapType==types.Dungeon then return INSTANCE,labels[INSTANCE] end
    if not info or (types and (mapType==types.Cosmic or mapType==types.World or mapType==types.Continent)) then
        return UNKNOWN,labels[UNKNOWN]
    end
    local label=FC.Label(point.label or field(info,"name"),96) or ("Map "..point.mapID)
    local key=point.key
    if type(key)~="string" or #key>80 or not (key:match("^map:%d+$") or key:match("^map:%d+:area:%d+$")) then key="map:"..point.mapID end
    return key,label
end

local function isInstance(record)
    local tag=field(value(C_QuestLog and C_QuestLog.GetQuestTagInfo,record.id),"tagID")
    local tags=Enum and Enum.QuestTag
    return tag and ((tags and (tag==tags.Dungeon or tag==tags.Raid or tag==tags.Heroic))
        or tag==81 or tag==62 or tag==85 or tag==88 or tag==89)
end

local function nativePoint(id)
    local status,mapID,x,y=FC.SafeRead(C_QuestLog and C_QuestLog.GetNextWaypoint,id)
    if status=="ready" then return Route.Point(mapID,x,y) end
end

local function mapPoints(mapID,cache)
    if not FC.Number(mapID,1,10000000) then return {} end
    if cache[mapID] then return cache[mapID] end
    local byID={}
    local pins=value(GetQuestsOnMapCached or (C_QuestLog and C_QuestLog.GetQuestsOnMap),mapID)
    local n=value(function() return type(pins)=="table" and #pins or 0 end)
    if FC.Number(n,1,1000) then
        for i=1,n do
            local pin=field(pins,i)
            local id=field(pin,"questID")
            if FC.Number(id,1,10000000) and field(pin,"isMapIndicatorQuest")==false then
                local point=Route.Point(mapID,field(pin,"x"),field(pin,"y"))
                if point then point.approximate=true; byID[id]=point end
            end
        end
    end
    cache[mapID]=byID
    return byID
end

local function section(model,key,label,mapID)
    local list=model[key]
    if not list then list={key=key,label=label,mapID=mapID,rows={},byID={}}; model[key]=list end
    return list
end

local function add(model,key,label,record,point,mapID)
    local group=section(model,key,label,mapID)
    local row=group.byID[record.id]
    if not row then
        row={record=record,id=record.id,points={}}
        group.byID[record.id]=row
        group.rows[#group.rows+1]=row
    end
    if point then row.points[#row.points+1]=point end
end

local function dataPoints(record,phase)
    local result={}
    local points=FC.QuestData and FC.QuestData.Points(record,phase)
    for _,p in ipairs(points or {}) do
        local point=Route.Point(p.mapID,p.x,p.y)
        local objective=p.objectiveIndex and record.objectives[p.objectiveIndex]
        if point and (phase~="work" or not objective or objective.finished~=true) then
            point.key,point.label,point.approximate=p.key,p.label,true
            result[#result+1]=point
            if #result>=300 then break end
        end
    end
    return result
end

local function refineNative(native,points)
    if not native then return end
    local position=world(native.mapID,value(CreateVector2D,native.x,native.y))
    if not position then return end
    local best,nearest
    for _,point in ipairs(points) do
        if point.mapID==native.mapID and point.key and point.key:match("^map:%d+:area:%d+$") then
            local d=distance(point,position)
            if d and d<=200 and (not nearest or d<nearest) then best,nearest=point,d end
        end
    end
    if best then native.key,native.label=best.key,best.label end
end

local function sameAreaModel(mapID)
    local model,cache={},{}
    for _,record in pairs(FC.Quests.records) do
        local phase=record.status=="C" and "turnin" or "work"
        local points={}
        if record.observed and (record.status=="A" or record.status=="C") then
            local native=nativePoint(record.id)
            points=dataPoints(record,phase)
            refineNative(native,points)
            if native then
                if phase=="work" and #record.objectives==1 then
                    -- A single objective must not appear in both a broad map
                    -- fallback and an inferred subarea on that same map.
                    for i=#points,1,-1 do
                        if points[i].mapID==native.mapID and points[i].key~=native.key then table.remove(points,i) end
                    end
                end
                table.insert(points,1,native)
            elseif #points==0 then
                local questMap=value(GetQuestUiMapID,record.id)
                local poi=mapPoints(mapID,cache)[record.id] or mapPoints(questMap,cache)[record.id]
                if poi then points[1]=poi end
            end
        end
        if phase=="turnin" and record.observed then
            add(model,TURN,labels[TURN],record)
            for _,p in ipairs(points) do add(model,TURN,labels[TURN],record,p) end
        elseif isInstance(record) then
            add(model,INSTANCE,labels[INSTANCE],record)
            for _,p in ipairs(points) do add(model,INSTANCE,labels[INSTANCE],record,p) end
        else
            local placed=false
            for _,p in ipairs(points) do
                local key,label=area(p)
                if key~=UNKNOWN then
                    add(model,key,label,record,p,p.mapID)
                    placed=true
                end
            end
            if not placed then add(model,UNKNOWN,labels[UNKNOWN],record) end
        end
    end
    return model
end

local function better(a,b)
    if a.distance~=b.distance then
        if not a.distance then return false elseif not b.distance then return true end
        return a.distance<b.distance
    end
    return a.id<b.id
end

local function rank(model,player)
    for _,group in pairs(model) do
        group.distance=nil
        for _,row in ipairs(group.rows) do
            row.point,row.distance=nil,nil
            for _,p in ipairs(row.points) do
                local d=distance(p,player)
                if not row.point or (d and (not row.distance or d<row.distance)) then row.point,row.distance=p,d end
            end
            if row.distance and (not group.distance or row.distance<group.distance) then group.distance=row.distance end
        end
        table.sort(group.rows,better)
    end
end

local function groups(model,mapID)
    local out={}
    for _,group in pairs(model) do out[#out+1]=group end
    local weights={[TURN]=2,[INSTANCE]=3,[UNKNOWN]=4}
    table.sort(out,function(a,b)
        if a.key==Route.area or b.key==Route.area then return a.key==Route.area and b.key~=Route.area end
        local aw,bw=weights[a.key] or 1,weights[b.key] or 1
        if aw~=bw then return aw<bw end
        if (a.mapID==mapID)~=(b.mapID==mapID) then return a.mapID==mapID end
        if a.distance~=b.distance then
            if not a.distance then return false elseif not b.distance then return true end
            return a.distance<b.distance
        end
        if a.label~=b.label then return a.label<b.label end
        return a.key<b.key
    end)
    return out
end

local function nearby(mapID,player)
    local candidates,status
    if FC.QuestData then candidates,status=FC.QuestData.Nearby(mapID) end
    local out,byStop,counts={},{},{}
    for _,candidate in ipairs(candidates or {}) do
        local point=candidate.point and Route.Point(candidate.point.mapID,candidate.point.x,candidate.point.y)
        if point then point.approximate=candidate.point.approximate==true end
        local name=FC.Label(candidate.giver,96)
        local giver=name or "Map quest offers"
        local key=candidate.giverKey or name or (point and ("pin:"..point.mapID..":"..math.floor(point.x*100)..":"..math.floor(point.y*100))) or giver
        local d=distance(point,player)
        local stop=byStop[key]
        if not stop then
            stop={label=giver,rows={},byID={},distance=d,key=tostring(key)}
            out[#out+1]=stop
            byStop[key]=stop
        elseif d and (not stop.distance or d<stop.distance) then
            stop.distance=d
        end
        local row=stop.byID[candidate.id]
        if not row then
            local workKey=candidate.workKey
            if workKey then
                counts[workKey]=counts[workKey] or {}
                counts[workKey][candidate.id]=true
            end
            row={id=candidate.id,title=FC.Label(candidate.title,160) or ("Quest #"..candidate.id),
                point=point,distance=d,confirmed=candidate.confirmed,workKey=workKey,workLabel=FC.Label(candidate.workLabel,96)}
            stop.rows[#stop.rows+1]=row
            stop.byID[candidate.id]=row
        else
            row.confirmed=row.confirmed or candidate.confirmed
            if point and (not row.point or (d and (not row.distance or d<row.distance))) then row.point,row.distance=point,d end
        end
    end
    for _,stop in ipairs(out) do
        for _,row in ipairs(stop.rows) do
            local set=row.workKey and counts[row.workKey]
            local first=set and next(set)
            row.bundle=first and next(set,first)~=nil
        end
        table.sort(stop.rows,better)
    end
    table.sort(out,function(a,b)
        if a.distance~=b.distance then
            if not a.distance then return false elseif not b.distance then return true end
            return a.distance<b.distance
        end
        return a.key<b.key
    end)
    return out,status or "Nearby pickup data is unavailable."
end

local function prefs()
    local character=FC.Store.Character()
    return character and character.questHelper
end

local function save()
    local p=FC.Store.CanWrite() and prefs()
    if p then p.area,p.view=Route.area,Route.view end
end

local function choose()
    if not Route.area then Route.target,Route.state=nil,nil; return end
    local group=Route.byKey[Route.area]
    local current=Route.target and FC.Quests.records[Route.target]
    local row=group and group.byID[Route.target]
    if row and row.record.observed then
        Route.state="tracking"
        return
    end
    if Route.target and ((current and (not current.observed or current.status=="U" or current.status=="P"))
        or (not current and not FC.Quests.removed[Route.target] and not FC.Quests.complete)) then
        Route.state="waiting"
        return
    end
    if current and current.status=="A" and Route.byKey[UNKNOWN] and Route.byKey[UNKNOWN].byID[current.id] then
        Route.state="waiting"
        return
    end
    Route.target=nil
    for _,candidate in ipairs(group and group.rows or {}) do
        if candidate.distance and candidate.record.status=="A" and candidate.record.observed then
            Route.target,Route.state=candidate.id,"tracking"
            return
        end
    end
    Route.state=group and "no-distance" or (FC.Quests.complete and "finished" or "waiting")
end

function Route.Enable()
    local p=prefs()
    Route.view=type(p)=="table" and p.view=="nearby" and "nearby" or "route"
    Route.area=type(p)=="table" and p.area or nil
    Route.target=nil
    Route.dirty=true
end

function Route.SetView(view)
    if view~="route" and view~="nearby" then return end
    Route.view=view
    save()
end

function Route.Track(key,id)
    local group=Route.byKey[key]
    if not group or key==UNKNOWN or key==TURN or key==INSTANCE then return end
    local row=id and group.byID[id]
    if id and (not row or not row.record.observed or row.record.status~="A") then return end
    Route.area,Route.target=key,id
    choose()
    save()
end

function Route.Stop(preserve)
    Route.area,Route.target,Route.state=nil,nil,nil
    if not preserve then save() end
end

function Route.Target()
    if Route.state~="tracking" or not Route.target then return nil end
    local group=Route.byKey[Route.area]
    return group and group.byID[Route.target]
end

function Route.Tick()
    if FC.IsCombat() then return end
    local mapID=value(C_Map and C_Map.GetBestMapForUnit,"player")
    if not FC.Number(mapID,1,10000000) then mapID=nil end
    local revision,provider=FC.Quests.revision,FC.QuestData and FC.QuestData.revision
    if Route.dirty or Route.revision~=revision or Route.provider~=provider or Route.mapID~=mapID then
        Route.dirty,Route.revision,Route.provider,Route.mapID=false,revision,provider,mapID
        Route.byKey=sameAreaModel(mapID)
    end
    local player=playerWorld(mapID)
    rank(Route.byKey,player)
    choose()
    Route.sections=groups(Route.byKey,mapID)
    if Route.view=="nearby" then Route.nearby,Route.nearbyStatus=nearby(mapID,player) end
    Route.mapLabel=mapID and FC.Label(field(mapInfo(mapID),"name"),96) or "Current area"
end
