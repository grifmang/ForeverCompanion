local _, FC = ...
local Data = {revision=0}
FC.QuestData = Data

-- Consume an installed QuestieDB, not a copy of its data or runtime.
local CONTRACT, INDEX_BATCH, MAX_IDS = 4, 48, 20000
local MAX_POINTS, MAX_SEEN_STARTS, MAX_PER_MAP = 72, 24000, 1200
local provider, providerState, searchRequested, workCache, offerCache
local offers, offerMap, offerExpiry = {}, nil, nil
local nativeRequests={}

local function value(fn,...)
    if type(fn)~="function" then return nil end
    local ok,a,b,c,d,e=pcall(fn,...)
    if not ok then return nil end
    if not FC.Readable(a) then a=nil end
    if not FC.Readable(b) then b=nil end
    if not FC.Readable(c) then c=nil end
    if not FC.Readable(d) then d=nil end
    if not FC.Readable(e) then e=nil end
    return a,b,c,d,e
end

local function field(t,k)
    if not FC.Readable(t) or type(t)~="table" then return nil end
    local v=t[k]
    if FC.Readable(v) then return v end
end

local function text(s)
    return FC.Readable(s) and type(s)=="string" and #s>0 and FC.PlainText(s,180) or nil
end

local function idOK(id) return FC.Number(id,1,10000000) end
local function changed()
    Data.revision=Data.revision+1
    offerCache=nil
end

-- The ZoneDB public support API exposes these maps as Lua strings. The only
-- consumed format is an integer-to-integer table; never evaluate the string.
local function numericMap(out,source)
    if type(source)~="string" or #source>512000 or not source:match("^%s*return%s*{") then return end
    source=source:gsub("%-%-%[%[.-%]%]",""):gsub("%-%-[^\r\n]*","")
    for line in source:gmatch("[^\r\n]+") do
        local a,b=line:match("^%s*%[(%d+)%]%s*=%s*(%d+)%s*,?%s*$")
        if a and b then
            a,b=tonumber(a),tonumber(b)
            if idOK(a) and FC.Number(b,0,10000000) then out[a]=b end
        end
    end
end

local function providerFlavor(lib)
    local mode=value(field(field(lib,"ModeIndicator"),"GetStatus"))
    if field(mode,"mode")=="baked" then
        -- The public mode indicator reports expansion only for Source mode.
        -- Baked artifacts instead declare their selected flavor in TOC metadata.
        local addon=field(lib,"addonName") or "QuestieDB"
        return value(C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata,addon,"X-Flavor")
    end
    return field(mode,"expansion")
end

local function discoverProvider()
    if providerState then return provider end
    local lib=LibQuestieDB
    local quest=field(lib,"Quest")
    local expansion=providerFlavor(lib)
    if not lib then
        providerState="Install QuestieDB Forever to find nearby quests."
    elseif type(expansion)~="string" or expansion:lower()~="forever"
        or value(field(lib,"RequireContract"),CONTRACT)~=true
        or type(field(quest,"GetAllIds"))~="function" or type(field(quest,"GetAll"))~="function" then
        providerState="An updated QuestieDB Forever is needed for nearby quests."
    else
        local private=field(value(field(field(lib,"Support"),"Get"),"ZoneDB"),"private")
        local maps,parents={},{}
        numericMap(maps,field(private,"areaIdToUiMapId"))
        numericMap(maps,field(private,"areaIdToUiMapIdOverride"))
        numericMap(parents,field(private,"subZoneToParentZone"))
        numericMap(parents,field(private,"subZoneToParentZoneOverride"))
        if not next(maps) then
            providerState="QuestieDB Forever has no supported map data."
        else
            provider={lib=lib,quest=quest,npc=field(lib,"Npc"),object=field(lib,"Object"),item=field(lib,"Item"),
                maps=maps,parents=parents,areas={},index={},discoveryWork={},size=0,cursor=1}
            providerState="QuestieDB Forever locations are approximate."
        end
    end
    return provider
end

local function areaInfo(db,areaID)
    if not idOK(areaID) then return nil end
    if db.areas[areaID]~=nil then return db.areas[areaID] or nil end
    local mapID=db.maps[areaID]
    local info=idOK(mapID) and value(C_Map and C_Map.GetMapInfo,mapID)
    local mapType=field(info,"mapType")
    local types=Enum and Enum.UIMapType
    -- Some historical Questie maps are routing aliases, not live UiMaps.
    if not types or not mapType or (mapType~=types.Zone and mapType~=types.Dungeon and mapType~=types.Micro) then
        db.areas[areaID]=false
        return nil
    end
    local label=text(field(info,"name"))
    local key="map:" .. mapID
    local parent=db.parents[areaID]
    if parent and parent~=areaID and db.maps[parent]==mapID then
        local sub=text(value(C_Map and C_Map.GetAreaInfo,areaID))
        if sub and sub~=label then key,label=key .. ":area:" .. areaID,sub end
    end
    local area={mapID=mapID,key=key,label=label}
    db.areas[areaID]=area
    return area
end

local function coord(x)
    return FC.Readable(x) and type(x)=="number" and x==x and x>=0 and x<=100
end

local function addSpawns(db,spawns,out,objectiveIndex,limit)
    if type(spawns)~="table" then return end
    local areas={}
    for area in pairs(spawns) do if idOK(area) then areas[#areas+1]=area end end
    table.sort(areas)
    -- Preserve at least one valid point for each known area before retaining
    -- alternative spawns. A dense spawn list should not hide another work area.
    local alternatives={}
    for _,areaID in ipairs(areas) do
        local area=areaInfo(db,areaID)
        local points=field(spawns,areaID)
        if area and type(points)=="table" then
            local first=true
            for i=1,math.min(#points,24) do
                local point=field(points,i)
                local x,y,phase=field(point,1),field(point,2),field(point,3)
                -- Phase rules are not exposed as a QuestieDB consumer API.
                if coord(x) and coord(y) and (x~=0 or y~=0) and (phase==nil or phase==0) then
                    local p={mapID=area.mapID,x=x/100,y=y/100,label=area.label,key=area.key,
                        objectiveIndex=objectiveIndex,approximate=true}
                    if first then out[#out+1]=p; first=false
                    elseif #alternatives<limit then alternatives[#alternatives+1]=p end
                    if #out>=limit then return end
                end
            end
        end
    end
    for _,p in ipairs(alternatives) do
        if #out>=limit then return end
        out[#out+1]=p
    end
end

local function addEntity(db,entity,id,out,index,limit)
    if idOK(id) and #out<limit then addSpawns(db,value(field(entity,"spawns"),id),out,index,limit) end
end

local function addItem(db,item,out,index,limit)
    if not idOK(item) then return end
    for _,source in ipairs({{"npcDrops",db.npc},{"objectDrops",db.object}}) do
        local entities=value(field(db.item,source[1]),item)
        if type(entities)=="table" then
            for i=1,math.min(#entities,12) do addEntity(db,source[2],field(entities,i),out,index,limit) end
        end
    end
end

local function addEndPoints(db,id,out)
    local ends=value(field(db.quest,"finishedBy"),id)
    for kind=1,2 do
        local ids=field(ends,kind)
        if type(ids)=="table" then
            for i=1,math.min(#ids,12) do addEntity(db,kind==1 and db.npc or db.object,field(ids,i),out,nil,MAX_POINTS) end
        end
    end
end

local function simpleObjectiveKinds(db,id)
    local data=value(field(db.quest,"objectives"),id)
    local kinds={}
    for kind=1,3 do
        local entries=field(data,kind)
        if type(entries)=="table" then
            for i=1,math.min(#entries,12) do
                local entry=field(entries,i)
                local target=field(entry,1)
                if idOK(target) then
                    local entity=kind==1 and db.npc or kind==2 and db.object or db.item
                    kinds[#kinds+1]={kind=kind,id=target,name=text(value(field(entity,"name"),target))}
                end
            end
        end
    end
    local credits=field(data,5)
    if type(credits)=="table" then
        for i=1,math.min(#credits,12) do
            local entry=field(credits,i)
            local ids,proxy=field(entry,1),field(entry,2)
            if type(ids)=="table" then
                kinds[#kinds+1]={kind=1,ids=ids,name=text(value(field(db.npc,"name"),proxy))}
            end
        end
    end
    return kinds
end

local objectiveKinds={monster=1,object=2,item=3}
local function objectiveIndex(record,entries,entry)
    local objectives=record.objectives
    local index,count,allMatches=nil,0,0
    local name=entry.name and entry.name:lower()
    local sameKind=0
    for _,other in ipairs(entries) do if other.kind==entry.kind then sameKind=sameKind+1 end end
    for i,objective in ipairs(objectives) do
        local kind=objectiveKinds[objective.type]
        if kind==entry.kind or not objective.type then
            if kind==entry.kind then allMatches=allMatches+1 end
            if name and objective.text and objective.text:lower():find(name,1,true) then
                count=count+1
                index=i
            end
        end
    end
    if count==1 then return index end
    if #objectives==1 and #entries==1
        and (not objectives[1].type or objectiveKinds[objectives[1].type]==entry.kind) then return 1 end
    if allMatches==1 and sameKind==1 then
        for i,objective in ipairs(objectives) do if objectiveKinds[objective.type]==entry.kind then return i end end
    end
end

local function workPoints(db,id,record)
    local out={}
    local entries=simpleObjectiveKinds(db,id)
    for _,entry in ipairs(entries) do
        local index=record and objectiveIndex(record,entries,entry)
        if not record or (index and record.objectives[index].finished==false) then
            local limit=math.min(MAX_POINTS,#out+18)
            if entry.ids then
                for i=1,math.min(#entry.ids,10) do addEntity(db,db.npc,field(entry.ids,i),out,index,limit) end
            elseif entry.kind==3 then addItem(db,entry.id,out,index,limit)
            else addEntity(db,entry.kind==1 and db.npc or db.object,entry.id,out,index,limit) end
        end
        if #out>=MAX_POINTS then return out end
    end

    local extra=value(field(db.quest,"extraObjectives"),id)
    if type(extra)=="table" then
        for i=1,math.min(#extra,12) do
            local entry=field(extra,i)
            local index=field(entry,4)
            if not record or (FC.Number(index,1,#record.objectives) and record.objectives[index].finished==false) then
                addSpawns(db,field(entry,1),out,record and index or nil,MAX_POINTS)
            end
        end
    end
    local objective=record and record.objectives[1]
    if not record or (#record.objectives==1 and objective.finished==false and objective.type=="event") then
        local trigger=value(field(db.quest,"triggerEnd"),id)
        addSpawns(db,field(trigger,2),out,record and 1 or nil,MAX_POINTS)
    end
    return out
end

function Data.Points(record,phase)
    if (phase~="work" and phase~="turnin") or type(record)~="table"
        or not idOK(record.id) or not record.observed or FC.IsCombat() then return {} end
    local db=discoverProvider()
    if not db then return {} end
    workCache=workCache or {}
    local key=record.id .. ":" .. phase
    local cached=workCache[key]
    if cached and cached.version==record.version then return cached.points end
    local points={}
    if phase=="turnin" then addEndPoints(db,record.id,points)
    elseif phase=="work" and type(record.objectives)=="table" then points=workPoints(db,record.id,record) end
    workCache[key]={version=record.version,points=points}
    return points
end

local function indexStarts(db,id)
    local starts=value(field(db.quest,"startedBy"),id)
    for kind=1,2 do
        local ids=field(starts,kind)
        local entity=kind==1 and db.npc or db.object
        if type(ids)=="table" then
            for i=1,math.min(#ids,10) do
                local giver=field(ids,i)
                local points={}
                addEntity(db,entity,giver,points,nil,12)
                if #points>0 then
                    local name=text(value(field(entity,"name"),giver))
                    local faction=kind==1 and value(field(entity,"friendlyToFaction"),giver)
                    for _,p in ipairs(points) do
                        local map=db.index[p.mapID] or {}
                        db.index[p.mapID]=map
                        if #map<MAX_PER_MAP and db.size<MAX_SEEN_STARTS then
                            map[#map+1]={id=id,giver=name,giverKey=kind .. ":" .. giver,point=p,faction=faction}
                            db.size=db.size+1
                        end
                    end
                end
            end
        end
    end
end

function Data.Tick()
    if FC.IsCombat() then return end
    if offerExpiry and GetTime()>=offerExpiry then offers,offerExpiry={},nil; changed() end
    if not searchRequested then return end
    local db=discoverProvider()
    if not db or db.indexed then return end
    if not db.ids then
        db.ids=value(field(db.quest,"GetAllIds"))
        if type(db.ids)~="table" then
            providerState="QuestieDB Forever's quest index is unavailable."
            db.indexed=true
            changed()
            return
        end
    end
    local last=math.min(#db.ids,MAX_IDS)
    for i=db.cursor,math.min(last,db.cursor+INDEX_BATCH-1) do
        local id=field(db.ids,i)
        if idOK(id) then indexStarts(db,id) end
    end
    db.cursor=db.cursor+INDEX_BATCH
    if db.cursor>last or db.size>=MAX_SEEN_STARTS then db.indexed=true end
    -- Publish the growing index periodically rather than redrawing per batch.
    if db.indexed or math.floor(db.cursor/INDEX_BATCH)%4==0 then changed() end
end

local gateFields={"name","requiredLevel","requiredMaxLevel","requiredRaces","requiredClasses","preQuestSingle",
    "preQuestGroup","exclusiveTo","parentQuest","availableStartingWith","availableUntilCompleted","disabledByQuest",
    "specialFlags","requiredMinRep","requiredMaxRep","requiredSourceItems","requiredSpell","nextQuestInChain","requiredSkill"}

local function maskIntersects(a,b)
    if not FC.Number(a,0,9007199254740991) or not FC.Number(b,0,9007199254740991) then return nil end
    if a==0 then return true end
    while a>0 and b>0 do
        if a%2==1 and b%2==1 then return true end
        a,b=math.floor(a/2),math.floor(b/2)
    end
    return false
end

local function history(ctx,id)
    if not idOK(id) then return nil end
    if ctx.done[id]==nil then
        local done=value(C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted,id)
        ctx.done[id]=type(done)=="boolean" and (done and 1 or 0) or -1
    end
    return ctx.done[id]
end

local function active(ctx,id)
    if not idOK(id) then return nil end
    if ctx.active[id]==nil then
        local record=FC.Quests and FC.Quests.records[id]
        local inLog=value(C_QuestLog and C_QuestLog.IsOnQuest,id)
        ctx.active[id]=record and record.observed and 1 or type(inLog)=="boolean" and (inLog and 1 or 0) or -1
    end
    return ctx.active[id]
end

local function anyComplete(ctx,list,acceptExclusive,db)
    if type(list)~="table" or #list==0 then return nil end
    local unknown=false
    for i=1,math.min(#list,50) do
        local id=field(list,i)
        if FC.Number(id,-10000000,10000000) and id~=0 then
            local done=history(ctx,math.abs(id))
            if done==1 then return true end
            if done~=0 then unknown=true end
            if acceptExclusive and id>0 then
                local alternatives=value(field(db.quest,"exclusiveTo"),id)
                local alternative=anyComplete(ctx,alternatives,false,db)
                if alternative==true then return true end
                -- A missing/unreadable history result for an alternative is
                -- not proof that this prerequisite is unsatisfied.
                if alternative==nil and type(alternatives)=="table" and #alternatives>0 then unknown=true end
            end
        else unknown=true end
    end
    if unknown or #list>50 then return nil end
    return false
end

local function meetsRep(requirement,min)
    local id,amount=field(requirement,1),field(requirement,2)
    if not idOK(id) or not FC.Number(amount,-100000,100000) then return true end
    local standing=field(value(C_Reputation and C_Reputation.GetFactionDataByID,id),"currentStanding")
    if not FC.Number(standing,-100000,100000) then return true end
    if min then return standing>=amount end
    return standing<=amount
end

local function meetsSkill(requirement)
    local id,minimum=field(requirement,1),field(requirement,2)
    if not idOK(id) or not FC.Number(minimum,0,10000) then return true end
    local info=value(C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID,id)
    local rank=field(info,"rank")
    return field(info,"skillID")~=id or not FC.Number(rank,0,10000) or rank>=minimum
end

local function eligible(db,ctx,id)
    if ctx.eligible[id]~=nil then return ctx.eligible[id] or nil end
    local row=value(field(db.quest,"GetAll"),id,gateFields)
    local name=text(field(row,1))
    ctx.eligible[id]=false
    if not name or active(ctx,id)==1 then return nil end
    local level,max=field(row,2),field(row,3)
    if ctx.level and ((FC.Number(level,1,1000) and ctx.level<level) or (FC.Number(max,1,1000) and ctx.level>max)) then return nil end
    if maskIntersects(field(row,4),ctx.race)==false or maskIntersects(field(row,5),ctx.class)==false then return nil end
    if history(ctx,id)==1 then
        local repeatable=value(C_QuestLog and C_QuestLog.IsRepeatableQuest,id)
        local flags=field(row,13)
        if repeatable~=true and not (repeatable==nil and FC.Number(flags,0,2147483647) and flags%2==1) then return nil end
    end

    local single,group=field(row,6),field(row,7)
    if type(single)=="table" and #single>0 then
        if anyComplete(ctx,single,false,db)==false then return nil end
    elseif type(group)=="table" then
        for i=1,math.min(#group,50) do
            local prerequisite=field(group,i)
            if anyComplete(ctx,{prerequisite},true,db)==false then return nil end
        end
    end
    local exclusive=field(row,8)
    if anyComplete(ctx,exclusive,false,db)==true then return nil end
    if type(exclusive)=="table" then
        for i=1,math.min(#exclusive,50) do if active(ctx,field(exclusive,i))==1 then return nil end end
    end
    local parent,starting,ending,disabled=field(row,9),field(row,10),field(row,11),field(row,12)
    if active(ctx,parent)==0
        or (history(ctx,starting)==0 and active(ctx,starting)==0)
        or history(ctx,ending)==1 or active(ctx,disabled)==1 then return nil end
    if not meetsRep(field(row,14),true) or not meetsRep(field(row,15),false) then return nil end
    local items=field(row,16)
    if type(items)=="table" then
        for i=1,math.min(#items,12) do
            local item=field(items,i)
            if idOK(item) and value(C_Item and C_Item.GetItemCount or GetItemCount,item)==0 then return nil end
        end
    end
    local spell=field(row,17)
    if idOK(spell) and value(IsPlayerSpell,spell)==false then return nil end
    local followup=field(row,18)
    if history(ctx,followup)==1 or active(ctx,followup)==1 then return nil end
    if not meetsSkill(field(row,19)) then return nil end
    ctx.eligible[id]=name
    return name
end

local function mapScope(mapID)
    local maps={}
    for _=1,5 do
        if not idOK(mapID) or maps[mapID] then break end
        local info=value(C_Map and C_Map.GetMapInfo,mapID)
        local mapType=field(info,"mapType")
        local types=Enum and Enum.UIMapType
        if not types or not mapType or (mapType~=types.Zone and mapType~=types.Dungeon and mapType~=types.Micro) then break end
        maps[mapID]=true
        if mapType==types.Zone then break end
        mapID=field(info,"parentMapID")
    end
    return maps
end

local function workArea(db,id)
    if db.discoveryWork[id]~=nil then return db.discoveryWork[id] or nil end
    local representative
    for _,p in ipairs(workPoints(db,id)) do
        if not representative then representative=p
        elseif p.key~=representative.key then db.discoveryWork[id]=false; return nil end
    end
    db.discoveryWork[id]=representative or false
    return representative
end

local function nativeNearby(mapID,maps,seen,rows,db)
    if not C_QuestLine then return end
    local localStories=value(C_CVar and C_CVar.GetCVarBool or GetCVarBool,"questPOILocalStory")==true
    local hidden=value(C_Minimap and C_Minimap.IsTrackingHiddenQuests)==true
    local account=value(C_Minimap and C_Minimap.IsTrackingAccountCompletedQuests)==true
    -- Request only the player's current map. A map parent's readable native
    -- offers are useful, but an off-map request could fight the World Map UI.
    if not nativeRequests[mapID] then
        nativeRequests[mapID]=true
        value(C_QuestLine.RequestQuestLinesForMap,mapID)
    end
    for _,map in ipairs(maps) do
        local lines=value(C_QuestLine.GetAvailableQuestLines,map)
        if type(lines)=="table" then
            for i=1,math.min(#lines,150) do
                local line=field(lines,i)
                local id=field(line,"questID")
                local start=field(line,"startMapID")
                local title=text(field(line,"questName"))
                local x,y=field(line,"x"),field(line,"y")
                if idOK(id) and not seen[id] and title and (not idOK(start) or start==map)
                    and field(line,"inProgress")==false and (hidden or field(line,"isHidden")==false)
                    and (localStories or field(line,"isLocalStory")==false)
                    and (account or field(line,"isAccountCompleted")==false)
                    and value(C_QuestLog and C_QuestLog.IsOnQuest,id)~=true
                    and (value(C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted,id)~=true
                        or value(C_QuestLog and C_QuestLog.IsRepeatableQuest,id)==true)
                    and coord(x) and coord(y) and x<=1 and y<=1 and (x~=0 or y~=0) then
                    local work=db and workArea(db,id)
                    rows[#rows+1]={id=id,title=title,point={mapID=map,x=x,y=y},confirmed=false,
                        workKey=work and work.key,workMapID=work and work.mapID,workLabel=work and work.label}
                    seen[id]=true
                end
            end
        end
    end
end

function Data.Nearby(mapID)
    if not idOK(mapID) or FC.IsCombat() then return {},"Nearby quests are unavailable here." end
    searchRequested=true
    local db=discoverProvider()
    local status=providerState
    if db and not db.indexed then status="Reading QuestieDB Forever locations…"
    elseif db and providerState=="QuestieDB Forever locations are approximate." then status="Nearby offers may need prerequisites." end
    if offerCache and offerCache.mapID==mapID then return offerCache.rows,status end

    local rows,confirmed,seen={}, {}, {}
    if offerMap==mapID then
        for _,row in ipairs(offers) do
            local record=FC.Quests and FC.Quests.records[row.id]
            if not (record and record.observed) and value(C_QuestLog and C_QuestLog.IsOnQuest,row.id)~=true then
                local work=db and workArea(db,row.id)
                rows[#rows+1]={id=row.id,title=row.title,giver=row.giver,point=row.point,confirmed=true,
                    workKey=work and work.key,workMapID=work and work.mapID,workLabel=work and work.label}
                confirmed[row.id]=true
                seen[row.id]=true
            end
        end
    end
    local mapIDs={}
    for map in pairs(mapScope(mapID)) do mapIDs[#mapIDs+1]=map end
    table.sort(mapIDs,function(a,b) if a==b then return false elseif a==mapID then return true elseif b==mapID then return false end; return a<b end)
    if db then
        local _,_,raceID=value(UnitRace,"player")
        local _,class=value(UnitClass,"player")
        local level=value(UnitLevel,"player")
        local enum=field(db.lib,"Enum")
        local faction=value(UnitFactionGroup,"player")
        local ctx={done={},active={},eligible={},race=field(field(enum,"raceMaskById"),raceID),
            class=field(field(enum,"classKeys"),class),level=FC.Number(level,1,1000) and level or nil}
        for _,map in ipairs(mapIDs) do
            for _,start in ipairs(db.index[map] or {}) do
                local opposite=(start.faction=="A" and faction=="Horde") or (start.faction=="H" and faction=="Alliance")
                local title=not opposite and not confirmed[start.id] and eligible(db,ctx,start.id)
                if title then
                    local work=workArea(db,start.id)
                    rows[#rows+1]={id=start.id,title=title,giver=start.giver,giverKey=start.giverKey,
                        point=start.point,confirmed=false,workKey=work and work.key,workMapID=work and work.mapID,workLabel=work and work.label}
                    seen[start.id]=true
                end
            end
        end
    end
    if #mapIDs>0 then nativeNearby(mapID,mapIDs,seen,rows,db) end
    offerCache={mapID=mapID,rows=rows}
    return rows,status
end

local function captureOffers(legacy)
    if FC.IsCombat() then return end
    local mapID=value(C_Map and C_Map.GetBestMapForUnit,"player")
    if not idOK(mapID) then return end
    local position=value(C_Map and C_Map.GetPlayerMapPosition,mapID,"player")
    local x,y
    if position then x,y=value(field(position,"GetXY"),position) end
    local point
    if coord(x) and x<=1 and coord(y) and y<=1 and (x~=0 or y~=0) then
        point={mapID=mapID,x=x,y=y,key="map:" .. mapID,approximate=true}
    end
    local giver=text(value(UnitName,"npc"))
    local rows={}
    local function append(id,title)
        if idOK(id) and title then rows[#rows+1]={id=id,title=title,giver=giver,point=point,confirmed=true} end
    end
    if legacy then
        local total=value(GetNumAvailableQuests)
        if FC.Number(total,0,200) then
            for i=1,math.min(total,40) do
                local _,_,_,_,id=value(GetAvailableQuestInfo,i)
                append(id,text(value(GetAvailableTitle,i)))
            end
        end
    else
        local list=value(C_GossipInfo and C_GossipInfo.GetAvailableQuests)
        if type(list)=="table" then
            for i=1,math.min(#list,40) do
                local row=field(list,i)
                append(field(row,"questID"),text(field(row,"title")))
            end
        end
    end
    offers,offerMap,offerExpiry=rows,mapID,GetTime()+90
    changed()
end

function Data.OnEvent(event,arg)
    if event=="ADDON_LOADED" then
        if arg=="QuestieDB" then Data.Reset() end
    elseif event=="GOSSIP_SHOW" or event=="GOSSIP_OPTIONS_UPDATE" then
        captureOffers(false)
    elseif event=="QUEST_GREETING" then
        captureOffers(true)
    elseif event=="QUEST_ACCEPTED" or event=="QUEST_TURNED_IN" or event=="QUEST_REMOVED" then
        if idOK(arg) then
            for i=#offers,1,-1 do if offers[i].id==arg then table.remove(offers,i) end end
            if workCache then workCache[arg .. ":work"],workCache[arg .. ":turnin"]=nil,nil end
        end
        changed()
    elseif event=="PLAYER_ENTERING_WORLD" or event=="ZONE_CHANGED_NEW_AREA" then
        offers,offerMap,offerExpiry,nativeRequests={},nil,nil,{}
        changed()
    elseif event=="QUESTLINE_UPDATE" then
        if FC.Readable(arg) and arg==true then nativeRequests={} end
        changed()
    elseif event=="PLAYER_LEVEL_UP" or event=="UPDATE_FACTION" or event=="BAG_UPDATE_DELAYED"
        or event=="SKILL_LINES_CHANGED" or event=="SPELLS_CHANGED" or event=="PLAYER_REGEN_ENABLED"
        or event=="MINIMAP_UPDATE_TRACKING" or event=="CVAR_UPDATE" or event=="QUEST_LOG_UPDATE" then
        changed()
    end
end

function Data.Reset()
    provider,providerState,searchRequested,workCache=nil,nil,nil,nil
    offers,offerMap,offerExpiry,nativeRequests={},nil,nil,{}
    changed()
end
