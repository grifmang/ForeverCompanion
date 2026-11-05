local _, FC = ...
local API = {status="loading", cache=nil, observedAt=nil}
FC.LegacyAPI = API

function API.Load()
    if FC.IsCombat() then return "restricted" end
    local status, version, _, _, interface = FC.SafeRead(GetBuildInfo)
    if status ~= "ready" or type(version) ~= "string" or not version:match("^1%.60%.") or interface ~= 16001 then
        return "unavailable"
    end
    if not LegacySystem then
        local load = C_AddOns and C_AddOns.LoadAddOn or LoadAddOn
        local loaded, success = FC.SafeRead(load, "Blizzard_LegacySystem")
        if loaded ~= "ready" or not success then return "loading" end
    end
    if not Constants or not Constants.LegacyConsts then return "unavailable" end
    return "ready"
end

function API.Challenges()
    local state = API.Load()
    if state ~= "ready" then API.status=state; return state,API.cache end
    local currency = Constants.LegacyConsts.LEGACY_POINTS_TRAIT_CURRENCY_ID
    if not FC.Number(currency,1,10000000) or not C_Traits or not C_Traits.GetTraitCurrencyForAchievement then
        API.status="unavailable"; return API.status,API.cache
    end
    local status, categories = FC.SafeRead(GetCategoryList)
    if status ~= "ready" or type(categories) ~= "table" then API.status=status; return status,API.cache end
    local list, seen, scanned = {}, {}, 0
    for _, categoryID in ipairs(categories) do
        if not FC.Number(categoryID,1,1000000) then return "restricted",API.cache end
        local cs, category = FC.SafeRead(GetCategoryInfo,categoryID)
        local ns, count = FC.SafeRead(GetCategoryNumAchievements,categoryID)
        if cs ~= "ready" or ns ~= "ready" or not FC.Number(count,0,500) then return "loading",API.cache end
        for index=1,count do
            scanned=scanned+1
            if scanned>500 then API.status="unavailable"; return API.status,API.cache end
            local infoStatus,id,name,_,completed,_,_,_,_,_,_,_,_,wasEarnedByMe = FC.SafeRead(GetAchievementInfo,categoryID,index)
            if infoStatus~="ready" or not FC.Number(id,1,1000000) then return "loading",API.cache end
            local ps,points=FC.SafeRead(C_Traits.GetTraitCurrencyForAchievement,currency,id)
            if ps~="ready" then return ps,API.cache end
            if FC.Number(points,1,1000) and not seen[id] then
                local row={id=id,name=FC.PlainText(name,192) or ("Challenge #" .. id),
                    category=FC.PlainText(category,192) or "Legacy",
                    points=points,criteria={},progress=nil,
                    scope="Character completion; Legacy rewards contribute to account progression"}
                if type(completed)=="boolean" and type(wasEarnedByMe)=="boolean" then
                    row.completed=completed and wasEarnedByMe
                end
                local qs,numCriteria=FC.SafeRead(GetAchievementNumCriteria,id)
                local progress,total=0,0
                if qs=="ready" and FC.Number(numCriteria,0,100) then
                    for c=1,numCriteria do
                        local s,text,_,done,quantity,required=FC.SafeRead(GetAchievementCriteriaInfo,id,c)
                        local criterion={label="Progress unavailable"}
                        if s=="ready" then
                            criterion.label=FC.PlainText(text,192) or "Criterion"
                            if FC.Readable(done) and type(done)=="boolean" then criterion.done=done end
                            if FC.Number(quantity,0,100000000) and FC.Number(required,1,100000000) then
                                criterion.quantity,criterion.required=quantity,required
                                progress=progress+math.min(quantity/required,1); total=total+1
                            elseif done==true then progress=progress+1; total=total+1 end
                        end
                        row.criteria[#row.criteria+1]=criterion
                    end
                    if total==numCriteria and total>0 then row.progress=progress/total end
                end
                list[#list+1],seen[id]=row,true
            end
        end
    end
    if #list==0 then API.status="loading"; return API.status,API.cache end
    API.cache,API.observedAt,API.status=list,time(),"ready"
    return "ready",list
end

function API.Perks()
    local status=API.Load()
    if status~="ready" or not FC.Readable(LegacyTreeData) or type(LegacyTreeData)~="table" or not C_Traits then
        return status=="ready" and "unavailable" or status
    end
    local result={trees={},byKey={}}
    if LegacySystem and LegacySystem.GetCurrencyInfo then
        local cs,info=FC.SafeRead(LegacySystem.GetCurrencyInfo)
        if cs=="ready" and info and FC.Number(info.maxQuantity,1,1000) then result.cap=info.maxQuantity end
    end
    for _, tree in ipairs(LegacyTreeData) do
        if not FC.Readable(tree) or not FC.Number(tree.treeID,1,1000000) then return "restricted" end
        local cs,config=FC.SafeRead(C_Traits.GetConfigIDByTreeID,tree.treeID)
        local ns,nodes=FC.SafeRead(C_Traits.GetTreeNodes,tree.treeID)
        if cs~="ready" or ns~="ready" or not config or type(nodes)~="table" then return "loading" end
        local treeKey=tostring(tree.treeID)
        local group={key=treeKey,name=FC.PlainText(tree.name,96) or treeKey,perks={}}
        for i,nodeID in ipairs(nodes) do
            if i>150 or not FC.Number(nodeID,1,1000000) then return "unavailable" end
            local nodeStatus,node=FC.SafeRead(C_Traits.GetNodeInfo,config,nodeID)
            if nodeStatus~="ready" or not node or not FC.Readable(node.entryIDs) or type(node.entryIDs)~="table" then return "loading" end
            for _,entryID in ipairs(node.entryIDs) do
                if not FC.Number(entryID,1,1000000) then return "restricted" end
                local es,entry=FC.SafeRead(C_Traits.GetEntryInfo,config,entryID)
                if es~="ready" or not entry or not FC.Number(entry.definitionID,1,1000000) then return "loading" end
                local ds,definition=FC.SafeRead(C_Traits.GetDefinitionInfo,entry.definitionID)
                if ds~="ready" or not definition then return "loading" end
                local name=FC.Readable(definition.overrideName) and definition.overrideName or nil
                if not name and FC.Number(definition.spellID,1,10000000) and C_Spell and C_Spell.GetSpellName then
                    local ss,spellName=FC.SafeRead(C_Spell.GetSpellName,definition.spellID)
                    if ss=="ready" then name=spellName end
                end
                local label=FC.PlainText(name,96)
                if not label or not FC.Number(entry.maxRanks,1,1000) then return "loading" end
                -- Display ranks as a planning aid. Validate spending only for unit-cost perks.
                local costStatus,costs=FC.SafeRead(C_Traits.GetNodeCost,config,nodeID)
                if costStatus~="ready" or type(costs)~="table" then return "loading" end
                local unitCost=false
                for _,cost in ipairs(costs) do
                    if not FC.Readable(cost) then return "restricted" end
                    if not FC.Readable(cost.ID) or not FC.Readable(cost.amount) then return "restricted" end
                    if cost.ID==Constants.LegacyConsts.LEGACY_POINTS_TRAIT_CURRENCY_ID and cost.amount==1 then unitCost=true end
                end
                if unitCost then
                    local perk={treeKey=treeKey,perkKey=tostring(entryID),label=label,maxRanks=entry.maxRanks}
                    group.perks[#group.perks+1]=perk
                    result.byKey[treeKey .. ":" .. perk.perkKey]=perk
                end
            end
        end
        result.trees[#result.trees+1]=group
    end
    if not next(result.byKey) or not result.cap then return "unavailable",result end
    return "ready",result
end

function API.OpenNative(challengeID)
    if API.Load()~="ready" then return false,"Legacy UI unavailable, locked, or restricted." end
    local status
    if challengeID and type(ShowLegacyChallenge)=="function" then
        status=FC.SafeRead(ShowLegacyChallenge,challengeID,false)
    elseif type(ToggleLegacySystemUI)=="function" then status=FC.SafeRead(ToggleLegacySystemUI)
    else return false,"Native Legacy UI unavailable." end
    return status=="ready",status~="ready" and "Cannot open the Legacy UI right now." or nil
end
