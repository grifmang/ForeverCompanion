local _, FC = ...
local Items, UI = {hooked=false, cacheStatus="loading"}, FC.UI
FC.Items = Items
local marked = setmetatable({}, {__mode="k"})

function Items.InvalidateTooltip()
    if GameTooltip and marked[GameTooltip] then GameTooltip:Hide(); marked[GameTooltip]=nil end
end
function Items.InvalidateAfterCraft()
    Items.cacheStatus="loading"
    Items.InvalidateTooltip()
end

function Items.ParseItem(text)
    if type(text) ~= "string" or #text > 2048 then return nil, "Paste an item link or numeric item ID." end
    local id = text:match("^%s*(%d+)%s*$") or text:match("|Hitem:(%d+):") or text:match("^item:(%d+)")
    if not id then return nil, "Use an item link or numeric item ID." end
    return FC.PositiveInteger(id, 10000000)
end

function Items.SaveNeed(id, input, quantity, reason)
    if not FC.Store.CanWrite() then return nil, "Saved data is read-only." end
    local itemID, err = Items.ParseItem(input)
    if not itemID then return nil, err end
    local count, countError = FC.PositiveInteger(quantity, 1000000)
    if not count then return nil, countError end
    local label, labelError = FC.Label(reason)
    if not label then return nil, labelError end
    local list = FC.Store.Character().needs
    if id then
        local record = FC.Store.Find(list, id)
        if not record then return nil, "Need no longer exists." end
        record.itemID,record.quantity,record.reason=itemID,count,label
    else
        if #list >= 100 then return nil, "Limit: 100 material needs." end
        id, err = FC.Store.NewID("items")
        if not id then return nil, err end
        list[#list+1]={id=id,itemID=itemID,quantity=count,reason=label}
    end
    return id
end

function Items.SaveKeep(input, reason)
    if not FC.Store.CanWrite() then return false, "Saved data is read-only." end
    local id, err = Items.ParseItem(input)
    if not id then return false, err end
    local label, labelError = FC.Label(reason)
    if not label then return false, labelError end
    local keeps, count = FC.Store.Character().keep, 0
    for _ in pairs(keeps) do count=count+1 end
    if not keeps[id] and count >= 100 then return false, "Limit: 100 Keep rules." end
    keeps[id] = label
    return true
end

function Items.RemoveNeed(id) return FC.Store.Remove(FC.Store.Character().needs, id) end
function Items.RemoveKeep(id)
    if not FC.Store.CanWrite() then return false, "Saved data is read-only." end
    FC.Store.Character().keep[id] = nil
    return true
end

function Items.Scan()
    if FC.Crafting.awaitBags then Items.cacheStatus="loading"; return end
    local status, counts, quests = FC.API.Inventory()
    Items.cacheStatus = status
    if status == "ready" then Items.counts,Items.quests=counts,quests end
end

function Items.Advice(itemID)
    local character = FC.Store.Character()
    if not character then return "unavailable" end
    local required, reasons = 0, {}
    for _, need in ipairs(character.needs) do
        if need.itemID == itemID then required=required+need.quantity; reasons[#reasons+1]=need.reason .. " (" .. need.quantity .. ")" end
    end
    local materials,craftReasons,uncertain=FC.Crafting.Requirements()
    required=required+(materials[itemID] or 0)
    for _,reason in ipairs(craftReasons[itemID] or {}) do reasons[#reasons+1]=reason end
    local data = {required=required, permanent=character.keep[itemID], reasons=reasons,uncertain=uncertain}
    local status, item = FC.API.Item(itemID)
    data.quest = not item or item.isQuestItem == true or (Items.quests and Items.quests[itemID] == true)
    if Items.cacheStatus == "ready" then
        data.carried = Items.counts[itemID] or 0
        data.shortage = math.max(required-data.carried,0)
    end
    if status ~= "ready" then data.quest=true end
    if Items.cacheStatus=="ready" and not uncertain and not data.permanent and not data.quest then
        data.surplus=math.max(data.carried-required,0)
    end
    return Items.cacheStatus, data
end

local function addAdvice(tooltip, data)
    if not FC.IsEnabled("items") or not FC.Readable(data) or type(data) ~= "table" then return end
    local itemID = data.id
    if not FC.Number(itemID, 1, 10000000) or marked[tooltip] then return end
    local status, advice = Items.Advice(itemID)
    if not advice or (advice.required == 0 and not advice.permanent and not advice.uncertain) then return end
    marked[tooltip] = true
    tooltip:AddLine(" ")
    tooltip:AddLine("Forever Companion — Keep or Sell?", 0.85,0.71,0.42)
    if advice.permanent then tooltip:AddLine("Always keep: " .. advice.permanent, 0.45,0.9,0.65,true) end
    for index, reason in ipairs(advice.reasons) do
        if index > 5 then tooltip:AddLine("More needs listed in /fc items.",0.8,0.8,0.8,true); break end
        tooltip:AddLine("Needed for " .. reason,0.8,0.85,0.9,true)
    end
    if status == "ready" then
        tooltip:AddLine("Total needed " .. advice.required .. " | carrying " .. advice.carried,0.8,0.85,0.9,true)
        if not advice.permanent and not advice.quest and not advice.uncertain then
            tooltip:AddLine(advice.shortage > 0 and ("Still need " .. advice.shortage)
                or ("Surplus across all bags: " .. advice.surplus),0.8,0.85,0.9,true)
        end
    else tooltip:AddLine("Inventory " .. status .. "; no sale recommendation.",0.9,0.7,0.4,true) end
    if advice.uncertain then tooltip:AddLine("Requirements are unverified or saved data is read-only. Known reservations retained; no surplus recommendation.",0.9,0.7,0.4,true) end
    if advice.quest then tooltip:AddLine("Quest or unknown item status: keep until checked.",0.9,0.7,0.4,true) end
    tooltip:AddLine("Advice covers total bags; it does not prevent sales.",0.7,0.7,0.7,true)
end

function Items.Enable()
    FC.Crafting.Enable()
    Items.Scan()
    if Items.hooked then return end
    local function guarded(tooltip, data)
        if tooltip ~= GameTooltip then return end
        local ok, err = pcall(addAdvice, tooltip, data)
        if not ok then FC.RecordDiagnostic("Item tooltip", err) end
    end
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, guarded)
        GameTooltip:HookScript("OnTooltipCleared", function(self) marked[self]=nil end)
        GameTooltip:HookScript("OnHide", function(self) marked[self]=nil end)
        Items.hooked = true
    else FC.RecordDiagnostic("Item tooltip", "Supported item tooltip processor unavailable.") end
end

function Items.Disable()
    FC.Crafting.Disable()
    if GameTooltip and marked[GameTooltip] then GameTooltip:Hide(); marked[GameTooltip]=nil end
end

function Items.Render(parent)
    Items.Scan()
    local view, character = UI.View("items"), FC.Store.Character()
    UI.Label(parent, "Remember why you need it", 0, 0, 730, true)
    UI.Label(parent, "Recipe goals update required materials as you gather and craft. Keep advice does not prevent sales.",0,31)
    local y=FC.Crafting.Render(parent,72)
    UI.Label(parent,"Materials to keep — combined across goals",0,y,730,true); y=y+35
    local totals,_,uncertain=FC.Crafting.Requirements()
    for _,need in ipairs(character.needs) do totals[need.itemID]=(totals[need.itemID] or 0)+need.quantity end
    local materialIDs={}; for id,quantity in pairs(totals) do if quantity>0 then materialIDs[#materialIDs+1]=id end end
    table.sort(materialIDs)
    if uncertain then UI.Label(parent,"Some requirements are unverified or saved data is read-only. Known needs are shown; surplus is withheld.",0,y,730); y=y+43 end
    if #materialIDs==0 then UI.Label(parent,"No active material reservations yet.",0,y); y=y+35 end
    for index=1,math.min(#materialIDs,100) do
        local itemID=materialIDs[index]
        local _,item=FC.API.Item(itemID)
        local status,advice=Items.Advice(itemID)
        UI.Label(parent,(item and item.name or "Item #" .. itemID) .. " — " .. totals[itemID] .. " needed",0,y,730)
        local detail=status=="ready" and ("Carrying " .. advice.carried .. " / still need " .. advice.shortage) or "Bag counts pending or unavailable"
        if status=="ready" and advice.surplus~=nil then detail=detail .. " / surplus " .. advice.surplus end
        UI.Label(parent,detail,0,y+23,730); y=y+52
    end
    if #materialIDs>100 then UI.Label(parent,(#materialIDs-100) .. " more material rows are still reserved in item advice.",0,y); y=y+35 end
    if view.manualExtras==nil then view.manualExtras=#character.needs>0 or next(character.keep)~=nil end
    UI.Check(parent,"Manual reservations and Always keep",0,y,view.manualExtras,function(value) view.manualExtras=value end); y=y+42
    if not view.manualExtras then UI.Height(y+25); return end
    local offset=y-70
    UI.Input(parent,"Item link or ID",0,70+offset,300,view.item or "",2048,function(t) view.item=t end)
    UI.Input(parent,"Quantity",320,70+offset,130,view.quantity or "",10,function(t) view.quantity=t end)
    UI.Input(parent,"Reason / goal",470,70+offset,265,view.reason or "",96,function(t) view.reason=t end)
    UI.Button(parent,view.id and "Save changes" or "Add material need",0,127+offset,165,function()
        local id,err=Items.SaveNeed(view.id,view.item or "",view.quantity or "",view.reason or "")
        UI.Result(id,err)
        if id then view.id,view.item,view.quantity,view.reason=nil,"","","" end
    end,FC.Store.CanWrite())
    UI.Button(parent,"Always keep",180,127+offset,135,function()
        local ok,err=Items.SaveKeep(view.item or "",view.reason or "")
        UI.Result(ok,err)
        if ok then view.id,view.item,view.quantity,view.reason=nil,"","","" end
    end,FC.Store.CanWrite())
    if view.id then UI.Button(parent,"Cancel edit",330,127+offset,120,function() view.id,view.item,view.quantity,view.reason=nil,"","","" end) end
    UI.Label(parent,"Carried bags only. Manual reservations add to crafting goals. Inventory: " .. Items.cacheStatus,0,173+offset)
    y=213+offset
    if #character.needs==0 and next(character.keep)==nil then UI.Label(parent,"Optional manual needs supplement automatic recipe requirements.",0,y); y=y+45 end
    for _, need in ipairs(character.needs) do
        local row = need
        local _,item=FC.API.Item(row.itemID)
        local _,advice=Items.Advice(row.itemID)
        UI.Label(parent,(item and item.name or "Item #" .. row.itemID) .. " — " .. row.reason .. " (" .. row.quantity .. ")",0,y,530)
        local detail=advice.carried and ("Carrying " .. advice.carried .. " / total needed " .. advice.required
            .. (advice.surplus~=nil and (" / surplus " .. advice.surplus) or " / surplus unavailable")) or "Carried count unavailable"
        UI.Label(parent,detail,0,y+22,530)
        UI.Button(parent,"Edit",547,y,80,function()
            view.id,view.item,view.quantity,view.reason=row.id,tostring(row.itemID),tostring(row.quantity),row.reason
            UI.scroll:SetVerticalScroll(0)
        end,FC.Store.CanWrite())
        UI.Button(parent,"Remove",639,y,96,function() UI.Result(Items.RemoveNeed(row.id)) end,FC.Store.CanWrite())
        y=y+62
    end
    if next(character.keep) then UI.Label(parent,"Always keep",0,y,730,true); y=y+36 end
    local ids={}; for id in pairs(character.keep) do ids[#ids+1]=id end; table.sort(ids)
    for _, id in ipairs(ids) do
        local itemID=id
        local _,item=FC.API.Item(itemID)
        UI.Label(parent,(item and item.name or "Item #" .. itemID) .. " — " .. character.keep[itemID],0,y,620)
        UI.Button(parent,"Remove",639,y-4,96,function() UI.Result(Items.RemoveKeep(itemID)) end,FC.Store.CanWrite())
        y=y+40
    end
    UI.Height(y+30)
end

function Items.OnEvent(event,...)
    FC.Crafting.OnEvent(event,...)
    if event=="ITEM_DATA_LOAD_RESULT" or event=="GET_ITEM_INFO_RECEIVED" then FC.API.ItemLoaded(...) end
    if event=="BAG_UPDATE_DELAYED" or event=="ITEM_DATA_LOAD_RESULT" or event=="GET_ITEM_INFO_RECEIVED" or event=="PLAYER_REGEN_ENABLED" then
        Items.Scan(); FC.Refresh("items")
        if GameTooltip and marked[GameTooltip] then GameTooltip:Hide(); marked[GameTooltip]=nil end
    elseif event=="PLAYER_REGEN_DISABLED" then Items.cacheStatus="restricted" end
end

function Items.Tick() FC.Crafting.Tick() end

FC.RegisterModule("items",{title="Keep or Sell?",Render=Items.Render,Enable=Items.Enable,Disable=Items.Disable,OnEvent=Items.OnEvent})
