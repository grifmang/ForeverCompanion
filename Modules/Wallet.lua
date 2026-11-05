local _, FC = ...
local Wallet, UI = {live={}}, FC.UI
FC.Wallet = Wallet
local enabled,dirty,nextScan=false,true,0
local LIMIT=10000000000
local function goals() local c=FC.Store.Character(); return c and c.wallet or {} end
local function ordered()
    local out={}; for _,record in ipairs(goals()) do out[#out+1]=record end
    table.sort(out,function(a,b) return a.id<b.id end); return out
end

local function source(offer,quantity)
    if type(offer)~="table" or not FC.Readable(offer) or not FC.Number(offer.unitCopper,0,LIMIT)
        or not FC.Number(offer.bundleSize,1,1000000) or not FC.Number(quantity,1,9999)
        or (offer.kind~="merchant" and offer.kind~="trainer") or not FC.Number(offer.observedAt,0,100000000000) then return nil end
    local npc=FC.Label(offer.npcName)
    local guid=FC.PlainText(offer.npcGUID,128)
    local key=FC.PlainText(offer.quoteKey or "",192)
    if not npc or not guid or guid=="" or not key then return nil end
    local data={kind=offer.kind,npcGUID=guid,npcName=npc,identity=offer.identity,quoteKey=key,
        stable=offer.stable,unitCopper=offer.unitCopper,bundleSize=offer.bundleSize,quantity=quantity,observedAt=offer.observedAt}
    if offer.kind=="merchant" then
        local id,bundle
        if type(offer.identity)=="string" then id,bundle=offer.identity:match("^item:(%d+):(%d+)$") end
        id,bundle=tonumber(id),tonumber(bundle)
        if offer.stable~=true or not FC.Number(id,1,10000000) or bundle~=offer.bundleSize or key~="" then return nil end
        data.itemID=id
    elseif offer.stable~=false or offer.identity~="" or key=="" or offer.bundleSize~=1 or quantity~=1 then return nil end
    local total=data.unitCopper*quantity
    if not FC.Number(total,0,LIMIT) then return nil end
    return data,total
end

function Wallet.ObserveMoney()
    local status,balance=FC.API.Money()
    if not enabled then return status,balance end
    if status~="ready" then
        Wallet.partial=true
        Wallet.baseline=nil; return status
    end
    if Wallet.baseline~=nil then
        local delta=balance-Wallet.baseline
        local key=delta>=0 and "increased" or "decreased"
        local total=(Wallet[key] or 0)+math.abs(delta)
        if total>100000000000000 then Wallet.partial=true end
        Wallet[key]=math.min(total,100000000000000)
    end
    Wallet.baseline=balance
    return status,balance
end

function Wallet.BudgetOffer(offer,bundles)
    if not FC.Store.CanWrite() then return nil,"Saved data is read-only." end
    dirty=true; Wallet.live={}
    local status,fresh,reason=FC.PriceAPI.RefreshOffer(offer)
    if status~="ready" then dirty=true; return nil,reason or "Choose the offer again." end
    local quantity=fresh.kind=="trainer" and 1 or FC.PositiveInteger(bundles,9999)
    local data,total=source(fresh,quantity)
    local label=FC.Label(fresh.label)
    if not data or not label then return nil,"Offer or bundle total exceeds supported limits." end
    local record
    for _,candidate in ipairs(goals()) do
        local s=candidate.source
        if s and s.kind==data.kind and s.npcGUID==data.npcGUID
            and ((s.stable and data.stable and s.identity==data.identity)
                or (not s.stable and not data.stable and s.quoteKey==data.quoteKey)) then record=candidate; break end
    end
    if not record then
        if #goals()>=100 then return nil,"Limit: 100 reservations." end
        local id,err=FC.Store.NewID("wallet"); if not id then return nil,err end
        record={id=id}; goals()[#goals()+1]=record
    end
    record.label,record.copper,record.source,record.active=label,total,data,true
    Wallet.live[record.id]=data.stable and not fresh.partial
    dirty=true; FC.Refresh("wallet"); return record.id
end

function Wallet.SetQuantity(id,bundles)
    if not FC.Store.CanWrite() then return false,"Saved data is read-only." end
    local record=FC.Store.Find(goals(),id)
    local quantity=FC.PositiveInteger(bundles,9999)
    if not record or not record.source or record.source.kind~="merchant" or not quantity then return false,"Choose a vendor budget and 1–9999 bundles." end
    local total=record.source.unitCopper*quantity
    if not FC.Number(total,0,LIMIT) then return false,"Bundle total exceeds the supported limit." end
    record.source.quantity,record.copper=quantity,total
    Wallet.live[id]=nil; dirty=true; FC.Refresh("wallet"); return true
end

function Wallet.Capture()
    local status,catalogue,reason=FC.PriceAPI.Scan(Wallet.kind)
    Wallet.live={}
    if status~="ready" then Wallet.catalogue=nil; Wallet.priceStatus=reason; return false end
    Wallet.catalogue=catalogue; Wallet.kind=catalogue.kind; Wallet.priceStatus=nil
    local byKey,duplicates={},{}
    for _,offer in ipairs(catalogue.offers) do
        if offer.kind=="merchant" then
            if byKey[offer.identity] then duplicates[offer.identity]=true else byKey[offer.identity]=offer end
        end
    end
    if FC.Store.CanWrite() and not catalogue.partial then
        for _,record in ipairs(goals()) do
            local s=record.source
            if record.active and s and s.stable and s.kind==catalogue.kind and s.npcGUID==catalogue.npcGUID then
                local offer=not duplicates[s.identity] and byKey[s.identity]
                local current,total
                if offer then current,total=source(offer,s.quantity) end
                if current and current.identity==s.identity and current.itemID==s.itemID and current.bundleSize==s.bundleSize then
                    record.source,record.copper=current,total
                    Wallet.live[record.id]=true
                end
            end
        end
    end
    return true
end

function Wallet.Enable()
    enabled,dirty,nextScan=true,true,0
    Wallet.live,Wallet.catalogue,Wallet.kind={},nil,nil
    Wallet.increased,Wallet.decreased,Wallet.partial,Wallet.baseline=0,0,false,nil
    Wallet.ObserveMoney()
end
function Wallet.Disable() enabled=false; Wallet.live,Wallet.catalogue,Wallet.baseline={},nil,nil end
function Wallet.Tick()
    if not enabled or not dirty or GetTime()<nextScan then return end
    dirty=false; nextScan=GetTime()+2
    if not Wallet.Capture() and Wallet.kind then dirty=true end
    FC.Refresh("wallet")
end

function Wallet.ParseGold(text)
    if type(text) ~= "string" or #text > 16 then return nil, "Enter an amount in gold." end
    text = text:match("^%s*(.-)%s*$")
    local whole, fraction = text:match("^(%d+)%.(%d+)$")
    if not whole then whole = text:match("^(%d+)$"); fraction = "" end
    if not whole or #fraction > 4 or #whole > 7 then return nil, "Use gold with at most four decimal places." end
    local amount = tonumber(whole) * 10000 + tonumber((fraction .. "0000"):sub(1, 4))
    if not FC.Number(amount, 0, 10000000000) then return nil, "Amount must be between 0 and 1,000,000 gold." end
    return amount
end

function Wallet.Save(id, label, goldText)
    if not FC.Store.CanWrite() then return nil, "Saved data is read-only." end
    local name, err = FC.Label(label)
    if not name then return nil, err end
    local copper, amountError = Wallet.ParseGold(goldText)
    if not copper then return nil, amountError end
    local list = FC.Store.Character().wallet
    if id then
        local record = FC.Store.Find(list, id)
        if not record then return nil, "Reservation no longer exists." end
        if record.source then return nil,"Imported prices are source-owned; edit vendor bundle quantity instead." end
        record.label, record.copper = name, copper
    else
        if #list >= 100 then return nil, "Limit: 100 reservations." end
        id, err = FC.Store.NewID("wallet")
        if not id then return nil, err end
        list[#list + 1] = {id=id, label=name, copper=copper, active=true}
    end
    return id
end

function Wallet.Finish(id)
    if not FC.Store.CanWrite() then return false, "Saved data is read-only." end
    local record = FC.Store.Find(FC.Store.Character().wallet, id)
    if not record then return false, "Reservation no longer exists." end
    record.active = not record.active
    Wallet.live[id]=nil; dirty=true; nextScan=0; FC.Refresh("wallet")
    return true
end

function Wallet.Remove(id)
    local ok,err=FC.Store.Remove(FC.Store.Character().wallet,id)
    if ok then Wallet.live[id]=nil end
    return ok,err
end
function Wallet.Summary()
    local status, balance = Wallet.ObserveMoney()
    local character = FC.Store.Character()
    if not character then return "unavailable" end
    local reserved,estimated = 0,not FC.Store.CanWrite()
    for _, record in ipairs(character.wallet) do
        if record.active then
            reserved=reserved+record.copper
            if record.source and not Wallet.live[record.id] then estimated=true end
        end
    end
    if status ~= "ready" then return status, {reserved=reserved} end
    local allocations,remaining={},balance
    for _,record in ipairs(ordered()) do
        if record.active then
            local funded=math.min(remaining,record.copper)
            allocations[record.id]={funded=funded,shortfall=record.copper-funded}
            remaining=remaining-funded
        end
    end
    return "ready", {balance=balance, reserved=reserved, available=FC.Store.CanWrite() and math.max(balance-reserved,0) or nil,
        shortfall=math.max(reserved-balance,0),allocations=allocations,estimated=estimated}
end

function Wallet.Render(parent)
    local view, character = UI.View("wallet"), FC.Store.Character()
    local status, totals = Wallet.Summary()
    UI.Label(parent, "Give your gold a job", 0, 0, 750, true)
    UI.Label(parent, "Carried: " .. FC.FormatMoney(totals and totals.balance)
        .. "    Reserved: " .. FC.FormatMoney(totals and totals.reserved), 0, 32)
    local available=status=="ready" and totals.available
    UI.Label(parent,status=="ready" and ((totals.estimated and "Estimated spendable: " or "Available to spend: ")
        .. FC.FormatMoney(available) .. "    Shortfall: " .. FC.FormatMoney(totals.shortfall))
        or "Current balance unavailable; reservations are still saved.",0,57)
    UI.Label(parent,"Observed session balance changes: +" .. FC.FormatMoney(Wallet.increased or 0)
        .. " / -" .. FC.FormatMoney(Wallet.decreased or 0) .. (Wallet.partial and " (partial observations)" or ""),0,90,730)
    UI.Label(parent,"Older goals fund first. Balance changes are net observations; Finish marks a purchase completed.",0,126,730)
    local y=173
    if view.sourceID then
        local editing=FC.Store.Find(character.wallet,view.sourceID)
        UI.Label(parent,"Edit vendor quantity: " .. (editing and editing.label or "Goal unavailable"),0,y,730,true); y=y+32
        UI.Input(parent,"Vendor bundles",0,y,260,view.sourceQuantity or "1",4,function(t) view.sourceQuantity=t end)
        UI.Button(parent,"Update quantity",280,y+18,170,function()
            local ok,err=Wallet.SetQuantity(view.sourceID,view.sourceQuantity or "")
            UI.Result(ok,err); if ok then view.sourceID=nil end
        end,FC.Store.CanWrite())
        UI.Button(parent,"Cancel",465,y+18,100,function() view.sourceID=nil end); y=y+70
    end
    if view.manual==nil then
        view.manual=false; for _,record in ipairs(character.wallet) do if not record.source then view.manual=true; break end end
    end
    UI.Check(parent,"Custom gold goals",0,y,view.manual,function(value) view.manual=value end); y=y+38
    if view.manual then
        UI.Input(parent,"Goal",0,y,420,view.label or "",96,function(t) view.label=t end)
        UI.Input(parent,"Amount in gold (1.0001 = 1g 1c)",440,y,300,view.amount or "",16,function(t) view.amount=t end)
        UI.Button(parent,view.id and "Save changes" or "Reserve gold",0,y+56,150,function()
            local id,err=Wallet.Save(view.id,view.label or "",view.amount or "")
            UI.Result(id,err); if id then view.id,view.label,view.amount=nil,"","" end
        end,FC.Store.CanWrite())
        if view.id then UI.Button(parent,"Cancel edit",165,y+56,120,function() view.id,view.label,view.amount=nil,"","" end) end
        y=y+103
    end
    UI.Label(parent,"Trainer and vendor prices",0,y,730,true); y=y+32
    local catalogue=Wallet.catalogue
    UI.Label(parent,catalogue and ("Observed at " .. catalogue.npcName .. (catalogue.kind=="trainer" and " — trainer quotes" or " — vendor bundles"))
        or (Wallet.priceStatus or "Visit a trainer or vendor to capture displayed gold prices."),0,y,730); y=y+43
    if catalogue then
        UI.Input(parent,"Filter offers (Enter to apply)",0,y,440,view.filter or "",96,function(t) view.filter=t; view.offerPage=1 end)
        UI.Input(parent,"Vendor bundles; training uses one",460,y,275,view.bundles or "1",4,function(t) view.bundles=t end); y=y+62
        local offers={}
        local query=(view.filter or ""):lower()
        for _,offer in ipairs(catalogue.offers) do if query=="" or offer.label:lower():find(query,1,true) then offers[#offers+1]=offer end end
        local pages=math.max(1,math.ceil(#offers/8))
        view.offerPage=math.max(1,math.min(view.offerPage or 1,pages))
        UI.Label(parent,"Page " .. view.offerPage .. "/" .. pages .. (catalogue.partial and " — partial catalogue" or ""),0,y,390)
        UI.Button(parent,"Previous",480,y-4,110,function() view.offerPage=math.max(1,view.offerPage-1) end,view.offerPage>1)
        UI.Button(parent,"Next",605,y-4,110,function() view.offerPage=math.min(pages,view.offerPage+1) end,view.offerPage<pages); y=y+36
        if #offers==0 then UI.Label(parent,"No matching offers observed.",0,y); y=y+32 end
        for index=(view.offerPage-1)*8+1,math.min(view.offerPage*8,#offers) do
            local offer=offers[index]
            UI.Label(parent,offer.label,0,y,530)
            local detail=offer.unitCopper~=nil and (FC.FormatMoney(offer.unitCopper) .. (offer.kind=="merchant"
                and (" per bundle of " .. offer.bundleSize) or " for one service — recorded quote")) or (offer.unsupportedReason or "Price unavailable")
            UI.Label(parent,detail,0,y+31,530)
            UI.Button(parent,"Budget",600,y,130,function()
                local id,err=Wallet.BudgetOffer(offer,view.bundles or "1")
                UI.Result(id,err,"Budget saved from the observed price.")
            end,FC.Store.CanWrite() and offer.unitCopper~=nil)
            y=y+72
        end
    end
    UI.Label(parent,"Your budgets — older goals funded first",0,y+8,730,true); y=y+48
    if #character.wallet==0 then UI.Label(parent,"Choose an observed offer above, or add a custom goal.",0,y); y=y+40 end
    for _, record in ipairs(ordered()) do
        local row = record
        UI.Label(parent,row.label .. (row.active and "" or " (finished)"),0,y,435)
        UI.Button(parent, "Edit", 452, y-4, 78, function()
            if row.source then view.sourceID,view.sourceQuantity,view.id=row.id,tostring(row.source.quantity),nil
            else view.manual=true; view.id,view.label,view.amount,view.sourceID=row.id,row.label,FC.GoldInput(row.copper),nil end
            UI.scroll:SetVerticalScroll(0)
        end, FC.Store.CanWrite() and (not row.source or row.source.kind=="merchant"))
        UI.Button(parent, row.active and "Finish" or "Reopen", 537, y-4, 85, function() UI.Result(Wallet.Finish(row.id)) end, FC.Store.CanWrite())
        UI.Button(parent, "Remove", 630, y-4, 100, function() UI.Result(Wallet.Remove(row.id)) end, FC.Store.CanWrite())
        local allocation=totals and totals.allocations and totals.allocations[row.id]
        UI.Label(parent,"Target: " .. FC.FormatMoney(row.copper) .. "    " .. (row.active and
            ((totals and totals.estimated and "Estimate funded: " or "Funded: ") .. FC.FormatMoney(allocation and allocation.funded)) or "Reservation released"),0,y+33,730)
        UI.Label(parent,row.active and ("Shortfall: " .. FC.FormatMoney(allocation and allocation.shortfall)) or "",0,y+60,730)
        y=y+88
        if row.source then
            local s=row.source
            local ds,when=FC.SafeRead(date,"%Y-%m-%d %H:%M",s.observedAt)
            local description=s.kind=="merchant" and (s.quantity .. " bundles × " .. s.bundleSize .. " items") or "One trainer service; historical quote"
            UI.Label(parent,description .. " at " .. s.npcName .. " / " .. (ds=="ready" and when or "recorded price")
                .. (Wallet.live[row.id] and " / current observation" or " / saved estimate"),0,y,730); y=y+43
        end
    end
    UI.Height(y + 30)
end

function Wallet.OnEvent(event)
    if event=="PLAYER_MONEY" then Wallet.ObserveMoney(); if Wallet.kind then dirty=true end; FC.Refresh("wallet")
    elseif event=="MERCHANT_SHOW" or event=="TRAINER_SHOW" then
        Wallet.kind=event=="MERCHANT_SHOW" and "merchant" or "trainer"
        Wallet.live,Wallet.catalogue={},nil; dirty=true; nextScan=0; FC.Refresh("wallet")
    elseif event=="MERCHANT_CLOSED" or event=="TRAINER_CLOSED" then
        local closed=event=="MERCHANT_CLOSED" and "merchant" or "trainer"
        if Wallet.kind==closed or not Wallet.kind then
            Wallet.kind,Wallet.catalogue=nil,nil; Wallet.live={}; dirty=false; FC.Refresh("wallet")
        end
    elseif event=="MERCHANT_UPDATE" or event=="TRAINER_UPDATE" or event=="TRAINER_DESCRIPTION_UPDATE"
        or event=="TRAINER_SERVICE_INFO_NAME_UPDATE" or event=="UPDATE_FACTION" or event=="PLAYER_REGEN_ENABLED" then
        Wallet.live={}; dirty=true
    end
end
FC.RegisterModule("wallet", {title="Launch Wallet", Render=Wallet.Render,Enable=Wallet.Enable,Disable=Wallet.Disable,Tick=Wallet.Tick,OnEvent=Wallet.OnEvent})
