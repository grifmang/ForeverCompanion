local _, FC = ...
local Legacy,UI={},FC.UI
FC.Legacy=Legacy

function Legacy.Pin(id,enabled)
    if not FC.Store.CanWrite() then return false,"Saved data is read-only." end
    if not FC.Number(id,1,1000000) then return false,"Invalid challenge." end
    local pins=FC.Store.Character().legacy.pins
    local count=0; for _ in pairs(pins) do count=count+1 end
    if enabled and not pins[id] and count>=100 then return false,"Limit: 100 pinned challenges." end
    pins[id]=enabled and true or nil
    return true
end

function Legacy.NextGoals()
    local status,list=FC.LegacyAPI.Challenges()
    if not list then return status,{} end
    local result,pins={},FC.Store.Character().legacy.pins
    for _,row in ipairs(list) do if not row.completed then result[#result+1]=row end end
    table.sort(result,function(a,b)
        if pins[a.id]~=pins[b.id] then return pins[a.id]==true end
        if (a.progress~=nil)~=(b.progress~=nil) then return a.progress~=nil end
        if (a.progress or -1)~=(b.progress or -1) then return (a.progress or -1)>(b.progress or -1) end
        if a.name~=b.name then return a.name<b.name end
        return a.id<b.id
    end)
    return status,result
end

function Legacy.SavePlan(id,name,allocations,notes,manualCap)
    if not FC.Store.CanWrite() then return nil,"Saved data is read-only." end
    local title,err=FC.Label(name)
    if not title then return nil,err end
    local note,noteError=FC.PlainText(notes or "",192)
    if not note then return nil,noteError end
    if type(allocations)~="table" or #allocations==0 or #allocations>50 then return nil,"Add 1–50 perk allocations." end
    local status,perks=FC.LegacyAPI.Perks()
    local manual=manualCap~=nil
    if not manual and (status~="ready" or not perks) then
        return nil,"Live perk data is unavailable. Switch to manual mode and enter a planning cap."
    end
    local cap=manual and manualCap or perks.cap
    if not FC.Number(cap,1,1000) then return nil,"Enter a whole planning cap between 1 and 1000." end
    local saved,seen,sum={}, {},0
    for _,a in ipairs(allocations) do
        local tree=FC.Label(a.treeKey,96)
        local key=FC.Label(a.perkKey,96)
        local label=FC.Label(a.label,96)
        if not tree or not key or not label or not FC.Number(a.points,0,1000) then return nil,"Check each perk name and whole point count." end
        local identity=tree .. ":" .. key
        if seen[identity] then return nil,"A perk can appear only once in a plan." end
        seen[identity]=true
        if not manual then
            local live=perks.byKey[identity]
            if not live or a.points>live.maxRanks then return nil,"Perk is unavailable or exceeds its observed rank limit." end
            label=live.label
        end
        sum=sum+a.points
        saved[#saved+1]={treeKey=tree,perkKey=key,label=label,points=a.points}
    end
    if sum>cap then return nil,"Plan spends " .. sum .. " points; cap is " .. cap .. "." end
    local list=FC.Store.Character().legacy.plans
    local record
    if id then record=FC.Store.Find(list,id); if not record then return nil,"Plan no longer exists." end
    else
        if #list>=20 then return nil,"Limit: 20 plans per character." end
        id,err=FC.Store.NewID("legacy"); if not id then return nil,err end
        record={id=id}; list[#list+1]=record
    end
    record.name,record.allocations,record.notes,record.cap,record.manual=title,saved,note,cap,manual
    return id
end

local function resetPlan(view)
    view.editID,view.planName,view.notes,view.allocations=nil,"","",{}
    view.cap,view.manual="16",true
end

local function planEditor(parent,view,y)
    view.allocations=view.allocations or {}
    if view.manual==nil then view.manual=true end
    UI.Label(parent,"Perk plans — planning only; apply points in the native Legacy panel",0,y,730,true); y=y+35
    UI.Input(parent,"Plan name",0,y,375,view.planName or "",96,function(t) view.planName=t end)
    UI.Input(parent,"Point cap (manual beta reference: 16)",395,y,340,view.cap or "16",4,function(t) view.cap=t end); y=y+55
    UI.Input(parent,"Plan notes",0,y,735,view.notes or "",192,function(t) view.notes=t end); y=y+60
    UI.Check(parent,"Manual plan: editable names and cap; not validated against live perks",0,y,view.manual,function(enabled)
        view.manual=enabled; view.allocations={}
        UI.message="Changing plan mode clears draft allocations. Saved plans are unchanged."
    end); y=y+40
    if view.manual then
        UI.Input(parent,"Tree (e.g. Adventure)",0,y,245,view.tree or "",96,function(t) view.tree=t end)
        UI.Input(parent,"Perk name",260,y,330,view.perk or "",96,function(t) view.perk=t end)
        UI.Input(parent,"Points",607,y,130,view.points or "",4,function(t) view.points=t end); y=y+55
        UI.Button(parent,"Add / update perk",0,y,180,function()
            local tree,err=FC.Label(view.tree or "")
            local perk,pe=FC.Label(view.perk or "")
            local points,qe=FC.PositiveInteger(view.points or "",1000)
            if not tree or not perk or not points then UI.message=err or pe or qe; return end
            for _,a in ipairs(view.allocations) do
                if a.treeKey==tree and a.perkKey==perk then a.points=points; return end
            end
            if #view.allocations>=50 then UI.message="Limit: 50 allocations."; return end
            view.allocations[#view.allocations+1]={treeKey=tree,perkKey=perk,label=perk,points=points}
        end,FC.Store.CanWrite()); y=y+38
    else
        local status,perks=FC.LegacyAPI.Perks()
        if status~="ready" then UI.Label(parent,"Live perk data " .. status .. ". Use manual mode or refresh after unlocking Legacy.",0,y); y=y+40
        else
            view.cap=tostring(perks.cap)
            UI.Label(parent,"Client cap: " .. perks.cap .. ". Adjust the point count below, then choose a perk.",0,y); y=y+32
            UI.Input(parent,"Points for selected perk",0,y,240,view.points or "1",4,function(t) view.points=t end); y=y+58
            for _,tree in ipairs(perks.trees) do
                UI.Label(parent,tree.name,0,y,730,true); y=y+30
                for _,perk in ipairs(tree.perks) do
                    local option=perk
                    UI.Button(parent,option.label .. " (max " .. option.maxRanks .. ")",0,y,530,function()
                        local count,err=FC.PositiveInteger(view.points or "1",option.maxRanks)
                        if not count then UI.message=err; return end
                        for _,a in ipairs(view.allocations) do
                            if a.treeKey==option.treeKey and a.perkKey==option.perkKey then a.points=count; return end
                        end
                        if #view.allocations>=50 then UI.message="Limit: 50 allocations."; return end
                        view.allocations[#view.allocations+1]={treeKey=option.treeKey,perkKey=option.perkKey,label=option.label,points=count}
                    end,FC.Store.CanWrite()); y=y+32
                end
            end
        end
    end
    local sum=0
    for index,a in ipairs(view.allocations) do
        local rowIndex=index
        sum=sum+a.points
        UI.Label(parent,a.label .. "  /  " .. a.treeKey .. "  /  " .. a.points .. " points",0,y,590)
        UI.Button(parent,"Remove",632,y-4,100,function() table.remove(view.allocations,rowIndex) end,FC.Store.CanWrite()); y=y+38
    end
    UI.Label(parent,"Draft allocation: " .. sum .. " points",0,y); y=y+32
    UI.Button(parent,view.editID and "Save plan changes" or "Save plan",0,y,170,function()
        local cap,err=FC.PositiveInteger(view.cap or "16",1000)
        if view.manual and not cap then UI.message=err; return end
        local id,e=Legacy.SavePlan(view.editID,view.planName or "",view.allocations,view.notes or "",view.manual and cap or nil)
        UI.Result(id,e,"Plan saved. Apply points using the native Legacy UI.")
        if id then resetPlan(view) end
    end,FC.Store.CanWrite())
    UI.Button(parent,"Clear draft",186,y,120,function() resetPlan(view) end); y=y+48
    for _,plan in ipairs(FC.Store.Character().legacy.plans) do
        local row=plan
        local points=0; for _,a in ipairs(plan.allocations) do points=points+a.points end
        UI.Label(parent,row.name .. " — " .. points .. "/" .. row.cap .. (row.manual and " (manual)" or " (client-validated when saved)"),0,y,515)
        UI.Button(parent,"Edit",535,y-4,85,function()
            view.editID,view.planName,view.notes,view.cap,view.manual=row.id,row.name,row.notes,tostring(row.cap),row.manual
            view.allocations={}; for _,a in ipairs(row.allocations) do view.allocations[#view.allocations+1]={treeKey=a.treeKey,perkKey=a.perkKey,label=a.label,points=a.points} end
        end,FC.Store.CanWrite())
        UI.Button(parent,"Remove",632,y-4,100,function() UI.Result(FC.Store.Remove(FC.Store.Character().legacy.plans,row.id)) end,FC.Store.CanWrite()); y=y+42
    end
    return y
end

function Legacy.Render(parent)
    local view=UI.View("legacy")
    UI.Label(parent,"Choose your next milestone",0,0,730,true)
    UI.Label(parent,"Pinned goals come first. Progress ordering is a planning aid, not an optimal leveling route.",0,30)
    UI.Button(parent,"Refresh client data",0,65,170,function() FC.LegacyAPI.cache=nil; FC.LegacyAPI.Challenges() end)
    UI.Button(parent,"Native Legacy UI",185,65,160,function() UI.Result(FC.LegacyAPI.OpenNative()) end)
    UI.Button(parent,view.mode=="plans" and "Show goals" or "Perk plans",360,65,145,function() view.mode=view.mode=="plans" and "goals" or "plans" end)
    if view.mode=="plans" then UI.Height(planEditor(parent,view,113)+40); return end
    UI.Input(parent,"Search challenge or category",0,108,540,view.search or "",96,function(t) view.search=t end)
    UI.Check(parent,"Next goals only",555,123,view.nextOnly~=false,function(enabled) view.nextOnly=enabled end)
    local status,list
    if view.nextOnly~=false then status,list=Legacy.NextGoals() else status,list=FC.LegacyAPI.Challenges() end
    local note="Client data: " .. status
    if status~="ready" and FC.LegacyAPI.observedAt then note=note .. " — last observed " .. date("%H:%M",FC.LegacyAPI.observedAt) end
    UI.Label(parent,note .. ". Progress remains unknown when the client cannot expose it.",0,170)
    local y,count=211,0
    local search=(view.search or ""):lower()
    for _,row in ipairs(list or {}) do
        if search=="" or (row.name .. " " .. row.category):lower():find(search,1,true) then
            local challenge=row
            count=count+1
            local progress=row.completed and "Complete" or (row.progress and (math.floor(row.progress*100) .. "%") or "Progress unavailable")
            UI.Label(parent,row.name .. "  /  " .. row.category .. "  /  " .. progress,0,y,558)
            UI.Check(parent,"",573,y-7,FC.Store.Character().legacy.pins[row.id]==true,function(enabled) UI.Result(Legacy.Pin(challenge.id,enabled)) end,FC.Store.CanWrite())
            UI.Button(parent,"Details",632,y-4,100,function() view.detail=view.detail==challenge.id and nil or challenge.id end)
            y=y+36
            if view.detail==row.id then
                UI.Label(parent,row.scope .. " — " .. row.points .. " Legacy point(s)",0,y,730,true); y=y+29
                for _,criterion in ipairs(row.criteria) do
                    local text=criterion.label .. (criterion.quantity and (" — " .. criterion.quantity .. "/" .. criterion.required) or (criterion.done==true and " — complete" or " — unavailable"))
                    UI.Label(parent,text,12,y,710); y=y+40
                end
                UI.Button(parent,"Open native challenge",0,y,210,function() UI.Result(FC.LegacyAPI.OpenNative(challenge.id)) end); y=y+40
            end
        end
    end
    if count==0 then UI.Label(parent,status=="ready" and "No matching unfinished goals. Try all challenges or save a perk plan."
        or "Legacy data is locked, loading, restricted or unsupported. Perk plans work in manual mode.",0,y); y=y+50 end
    UI.Label(parent,"Checkboxes pin goals. Saved perk plans are available from the Perk plans button above.",0,y)
    UI.Height(y+60)
end

function Legacy.OnEvent(event)
    if event=="ACHIEVEMENT_EARNED" or event=="CRITERIA_UPDATE" or event=="TRAIT_CONFIG_UPDATED"
        or event=="PLAYER_LEVEL_UP" or event=="PLAYER_REGEN_ENABLED" then FC.Refresh("legacy") end
end
FC.RegisterModule("legacy",{title="Legacy Compass",Render=Legacy.Render,Load=FC.LegacyAPI.Load,OnEvent=Legacy.OnEvent})
