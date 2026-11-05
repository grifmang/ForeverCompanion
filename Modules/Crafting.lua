local _, FC = ...
local Crafting = {live={},inFlight={},seen={},seenOrder={},awaitBags=false}
FC.Crafting=Crafting
local enabled,dirty,nextRefresh=false,true,0
local function goals() local c=FC.Store.Character(); return c and c.crafting or {} end
local function find(id) return FC.Store.Find(goals(),id) end

local function snapshot(source)
    if not FC.Readable(source) or type(source)~="table" or not FC.Number(source.recipeID,1,10000000)
        or source.kind~="modern" or type(source.reagents)~="table" or not FC.Readable(source.reagents) then return nil end
    local label=FC.Label(source.label); local profession=FC.Label(source.profession)
    local build=FC.PlainText(source.build,64)
    if not label or not profession or not build or build=="" then return nil end
    local rows,ids,n={}, {},0
    for key,row in pairs(source.reagents) do
        if not FC.Number(key,1,32) or not FC.Readable(row) or type(row)~="table"
            or not FC.Number(row.itemID,1,10000000) or ids[row.itemID]
            or not FC.Number(row.quantity,1,100000) then return nil end
        rows[key]={itemID=row.itemID,quantity=row.quantity}; ids[row.itemID]=true; n=n+1
    end
    if n==0 or n~=#rows then return nil end
    for index=1,n do if not rows[index] then return nil end end
    return {recipeID=source.recipeID,kind="modern",label=label,profession=profession,build=build,reagents=rows}
end

local function install(record,recipe)
    record.label,record.profession,record.kind=recipe.label,recipe.profession,recipe.kind
    record.build,record.reagents=recipe.build,recipe.reagents
end

function Crafting.Track(recipe,quantity)
    if not FC.Store.CanWrite() then return nil,"Saved data is read-only." end
    recipe=snapshot(recipe)
    if not recipe then return nil,"Complete, supported recipe data is required." end
    local crafts=FC.PositiveInteger(quantity,9999)
    if not crafts then return nil,"Enter 1–9999 crafts, not output items." end
    local record
    for _,goal in ipairs(goals()) do if goal.recipeID==recipe.recipeID then record=goal; break end end
    if record then
        if record.revision>=1000000 then return nil,"Edit limit reached; remove this goal and track it again." end
        record.revision=record.revision+1
    else
        if #goals()>=50 then return nil,"Limit: 50 crafting goals." end
        local id,err=FC.Store.NewID("crafting"); if not id then return nil,err end
        record={id=id,recipeID=recipe.recipeID,revision=1}; goals()[#goals()+1]=record
    end
    install(record,recipe); record.requested,record.remaining=crafts,crafts
    Crafting.live[record.id]=recipe
    FC.Items.InvalidateTooltip()
    FC.Refresh("items")
    return record.id
end

function Crafting.SetRemaining(id,quantity)
    if not FC.Store.CanWrite() then return false,"Saved data is read-only." end
    if type(quantity)~="string" or not quantity:match("^%d+$") or #quantity>4 then return false,"Enter 0–9999 remaining crafts." end
    local n=tonumber(quantity)
    local record=find(id)
    if not record or not FC.Number(n,0,9999) then return false,"Goal unavailable or craft count invalid." end
    if record.revision>=1000000 then return false,"Edit limit reached; remove and track again." end
    record.remaining,record.requested,record.revision=n,math.max(n,record.requested),record.revision+1
    dirty=true
    FC.Items.InvalidateTooltip()
    FC.Refresh("items"); return true
end

function Crafting.Remove(id)
    local ok,err=FC.Store.Remove(goals(),id)
    if ok then Crafting.live[id]=nil; FC.Items.InvalidateTooltip(); FC.Refresh("items") end
    return ok,err
end

function Crafting.Requirements()
    local totals,reasons,uncertain={}, {},not FC.Store.CanWrite()
    for _,goal in ipairs(goals()) do
        if goal.remaining>0 then
            local live=Crafting.live[goal.id]
            local ingredients=live and live.reagents or goal.reagents
            if not live then uncertain=true end
            for _,row in ipairs(ingredients) do
                totals[row.itemID]=(totals[row.itemID] or 0)+row.quantity*goal.remaining
                reasons[row.itemID]=reasons[row.itemID] or {}
                reasons[row.itemID][#reasons[row.itemID]+1]=goal.label .. " (" .. goal.remaining .. " crafts)"
            end
        end
    end
    return totals,reasons,uncertain
end

function Crafting.Refresh()
    if not enabled or FC.IsCombat() then return end
    for _,goal in ipairs(goals()) do
        if goal.remaining>0 then
            local status,data=FC.RecipeAPI.Read(goal.recipeID)
            local current=status=="ready" and snapshot(data) or nil
            if current and current.recipeID==goal.recipeID then
                Crafting.live[goal.id]=current
                if FC.Store.CanWrite() then install(goal,current) end
            else Crafting.live[goal.id]=nil end
        end
    end
    FC.Items.InvalidateTooltip(); FC.Refresh("items")
end

local function castIdentity(unit,guid,spellID)
    return FC.Readable(unit) and unit=="player" and FC.Readable(guid) and type(guid)=="string"
        and #guid>0 and #guid<=128 and FC.Number(spellID,1,10000000)
end

local function begin(unit,guid,spellID)
    if not enabled or not FC.Store.CanWrite() or not castIdentity(unit,guid,spellID)
        or Crafting.seen[guid] or Crafting.inFlight[guid] then return end
    local record
    for _,goal in ipairs(goals()) do if goal.recipeID==spellID and goal.remaining>0 then record=goal; break end end
    if not record then return end
    -- Do not attribute an unrelated/uncertain spell to a cached goal.
    local status,data=FC.RecipeAPI.Read(spellID)
    local current=status=="ready" and snapshot(data) or nil
    if not current or current.recipeID~=spellID then return end
    local n=0; for _ in pairs(Crafting.inFlight) do n=n+1 end
    if n>=64 then return end
    Crafting.inFlight[guid]={goalID=record.id,revision=record.revision,recipeID=spellID,started=GetTime()}
end

local function succeed(unit,guid,spellID)
    if not enabled or not FC.Store.CanWrite() or not castIdentity(unit,guid,spellID) then return end
    local cast=Crafting.inFlight[guid]
    Crafting.inFlight[guid]=nil
    if not cast or Crafting.seen[guid] or cast.recipeID~=spellID or GetTime()-cast.started>180 then return end
    Crafting.seen[guid]=true; Crafting.seenOrder[#Crafting.seenOrder+1]=guid
    if #Crafting.seenOrder>256 then Crafting.seen[table.remove(Crafting.seenOrder,1)]=nil end
    local goal=find(cast.goalID)
    if not goal or goal.recipeID~=spellID or goal.revision~=cast.revision or goal.remaining<=0 then return end
    goal.remaining=goal.remaining-1
    Crafting.awaitBags=true
    FC.Items.InvalidateAfterCraft()
    FC.Refresh("items")
end

function Crafting.Enable()
    enabled,dirty,nextRefresh=true,true,0
    Crafting.live,Crafting.inFlight,Crafting.seen,Crafting.seenOrder={}, {}, {},{}
    Crafting.awaitBags=false
end
function Crafting.Disable()
    enabled=false; Crafting.live,Crafting.inFlight={},{}
end
function Crafting.Tick()
    if not enabled then return end
    local now=GetTime()
    for guid,cast in pairs(Crafting.inFlight) do if now-cast.started>180 then Crafting.inFlight[guid]=nil end end
    if dirty and now>=nextRefresh and not FC.IsCombat() then
        dirty=false; nextRefresh=now+2; Crafting.Refresh()
    end
end

local recipeEvents={TRADE_SKILL_SHOW=true,TRADE_SKILL_LIST_UPDATE=true,TRADE_SKILL_DATA_SOURCE_CHANGED=true,
    TRADE_SKILL_DETAILS_UPDATE=true,TRADE_SKILL_CLOSE=true,NEW_RECIPE_LEARNED=true,PLAYER_ENTERING_WORLD=true,PLAYER_REGEN_ENABLED=true}
function Crafting.OnEvent(event,...)
    if event=="UNIT_SPELLCAST_SENT" then local unit,_,guid,id=...; begin(unit,guid,id)
    elseif event=="UNIT_SPELLCAST_START" then local unit,guid,id=...; begin(unit,guid,id)
    elseif event=="UNIT_SPELLCAST_SUCCEEDED" then succeed(...)
    elseif event=="UNIT_SPELLCAST_FAILED" or event=="UNIT_SPELLCAST_INTERRUPTED" or event=="UNIT_SPELLCAST_FAILED_QUIET" then
        local unit,guid=...
        if FC.Readable(unit) and unit=="player" and FC.Readable(guid) and type(guid)=="string" then Crafting.inFlight[guid]=nil end
    elseif event=="BAG_UPDATE_DELAYED" then Crafting.awaitBags=false
    end
    if recipeEvents[event] then
        if event~="TRADE_SKILL_CLOSE" then Crafting.live={} end
        FC.Items.InvalidateTooltip()
        dirty=true
    end
end

function Crafting.Render(parent,y)
    local UI,view=FC.UI,FC.UI.View("items")
    local status,current,reason=FC.RecipeAPI.Selected()
    UI.Label(parent,"Track a recipe, keep its materials",0,y,730,true); y=y+32
    UI.Label(parent,status=="ready" and ("Selected: " .. current.label .. " — " .. current.profession)
        or (reason or "Open your profession and select a recipe."),0,y,730); y=y+46
    UI.Input(parent,view.craftingID and "Crafts remaining (0 completes)" or "Number of crafts (not output items)",0,y,280,view.crafts or "1",4,function(t) view.crafts=t end)
    UI.Button(parent,view.craftingID and "Update remaining" or "Track selected recipe",300,y+18,200,function()
        local ok,err
        if view.craftingID then ok,err=Crafting.SetRemaining(view.craftingID,view.crafts or "")
        else
            local state,data,why=FC.RecipeAPI.Selected()
            if state~="ready" then UI.Result(false,why or "Recipe data unavailable."); return end
            ok,err=Crafting.Track(data,view.crafts or "1")
        end
        UI.Result(ok,err); if ok then view.craftingID,view.crafts=nil,"1" end
    end,FC.Store.CanWrite() and (view.craftingID~=nil or status=="ready"))
    if view.craftingID then UI.Button(parent,"Cancel edit",515,y+18,120,function() view.craftingID,view.crafts=nil,"1" end) end
    y=y+65
    UI.Label(parent,"Gathering updates shortages. Confirmed own crafts reduce remaining goals; canceled casts do not.",0,y,730); y=y+43
    if Crafting.awaitBags then
        UI.Label(parent,"Waiting for bags to update after crafting; surplus advice is paused.",0,y,730)
        y=y+43
    end
    if #goals()==0 then UI.Label(parent,"Choose a known recipe in your profession window to begin. No individual material entry is needed.",0,y,730); y=y+44 end
    for _,goal in ipairs(goals()) do
        local row=goal
        UI.Label(parent,row.label .. " — " .. (row.remaining==0 and "complete" or (row.remaining .. " crafts remaining")),0,y,530)
        local note=row.remaining==0 and "Materials released." or (Crafting.live[row.id] and "Recipe requirements verified this session." or "Cached requirements: open your profession to revalidate; surplus is withheld.")
        UI.Label(parent,note,0,y+23,530)
        UI.Button(parent,"Edit",547,y,80,function() view.craftingID,view.crafts=row.id,tostring(row.remaining); UI.scroll:SetVerticalScroll(0) end,FC.Store.CanWrite())
        UI.Button(parent,"Remove",639,y,96,function() UI.Result(Crafting.Remove(row.id)) end,FC.Store.CanWrite())
        y=y+65
    end
    return y+12
end
