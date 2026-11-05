local _, FC = ...
FC.API = {}
local API = FC.API

function API.Money()
    local status, value = FC.SafeRead(GetMoney)
    if status ~= "ready" then return status end
    if not FC.Number(value, 0, 100000000000000) then return "unavailable" end
    return "ready", value
end

function API.Identity()
    local status, guid = FC.SafeRead(UnitGUID, "player")
    local ns, name, realm = FC.SafeRead(UnitFullName, "player")
    if status ~= "ready" or type(guid) ~= "string" or ns ~= "ready" or type(name) ~= "string" then
        return "unavailable"
    end
    if type(realm) ~= "string" or realm == "" then
        local rs, current = FC.SafeRead(GetRealmName)
        realm = rs == "ready" and type(current) == "string" and current or ""
    end
    return "ready", guid, name .. (realm ~= "" and "-" .. realm:gsub("%s", "") or "")
end

function API.Inventory()
    if FC.IsCombat() then return "restricted" end
    if not C_Container or not C_Container.GetContainerNumSlots or not C_Container.GetContainerItemInfo then
        return "unavailable"
    end
    local counts, quest = {}, {}
    local last = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
    if not FC.Number(last, 0, 6) then last = 4 end
    for bag = 0, last do
        local status, slots = FC.SafeRead(C_Container.GetContainerNumSlots, bag)
        if status ~= "ready" or not FC.Number(slots, 0, 200) then return status == "ready" and "loading" or status end
        for slot = 1, slots do
            local itemStatus, info = FC.SafeRead(C_Container.GetContainerItemInfo, bag, slot)
            if itemStatus ~= "ready" then return itemStatus end
            if info then
                local id, count = info.itemID, info.stackCount
                if not FC.Number(id, 1, 10000000) or not FC.Number(count, 1, 10000000) then return "restricted" end
                counts[id] = (counts[id] or 0) + count
                if C_Container.GetContainerItemQuestInfo then
                    local qs, qi = FC.SafeRead(C_Container.GetContainerItemQuestInfo, bag, slot)
                    if qs == "ready" and qi and FC.Readable(qi.isQuestItem) then
                        quest[id] = quest[id] == true or qi.isQuestItem == true
                    else quest[id] = true end
                else quest[id] = true end
            end
        end
    end
    return "ready", counts, quest
end

local requested = {}
function API.Item(itemID)
    if not FC.Number(itemID, 1, 10000000) then return "unavailable" end
    local fn = C_Item and C_Item.GetItemInfo or GetItemInfo
    local status, name, link, quality, _, _, _, _, _, _, _, _, classID = FC.SafeRead(fn, itemID)
    if status ~= "ready" then return status end
    if type(name) ~= "string" then
        if requested[itemID] == "failed" then return "unavailable", {name = "Item #" .. itemID} end
        if not requested[itemID] and C_Item and C_Item.RequestLoadItemDataByID then
            requested[itemID] = true
            FC.SafeRead(C_Item.RequestLoadItemDataByID, itemID)
        end
        return "loading", {name = "Item #" .. itemID}
    end
    return "ready", {name = name, link = link, quality = quality, isQuestItem = classID == 12}
end

function API.ItemLoaded(itemID, success)
    if FC.Number(itemID, 1, 10000000) and FC.Readable(success) then
        requested[itemID] = success == false and "failed" or nil
    end
end

local function fullName(unit)
    local s, name, realm = FC.SafeRead(UnitFullName, unit)
    if s ~= "ready" or type(name) ~= "string" then return nil end
    if type(realm) ~= "string" or realm == "" then
        local rs, current = FC.SafeRead(GetRealmName)
        if rs ~= "ready" or type(current) ~= "string" then return nil end
        realm = current
    end
    return name .. "-" .. realm:gsub("%s", "")
end

-- Group lifecycle events distinguish a replacement group even with the same leader.
-- Epochs are local only; they are never sent or persisted.
local groupEpochs = {}
function API.GroupChanged(category)
    if not FC.Readable(category) or not FC.Number(category, 1, 2) then return end
    groupEpochs[category] = (groupEpochs[category] or 0) + 1
end

function API.GroupContext(party)
    return {category=party.category,epoch=party.epoch,leaderGUID=party.leaderGUID}
end

function API.SameGroup(context, party)
    return context and party.channel and context.category==party.category
        and context.epoch==party.epoch and context.leaderGUID==party.leaderGUID
end

function API.Party()
    if FC.IsCombat() then return "restricted" end
    local home, instance = LE_PARTY_CATEGORY_HOME or 1, LE_PARTY_CATEGORY_INSTANCE or 2
    local ins, instanceGroup = FC.SafeRead(IsInGroup, instance)
    if ins ~= "ready" then return ins end
    -- Unit tokens describe the active group; instance groups take precedence.
    local category = instanceGroup == true and instance or home
    local gs, grouped = FC.SafeRead(IsInGroup, category)
    if gs ~= "ready" then return gs end
    local result = {membersByName = {}, memberGUIDs = {}, selfName = fullName("player"),
        category=category,epoch=groupEpochs[category] or 0}
    if not result.selfName then return "unavailable" end
    if grouped ~= true then return "ready", result end
    local rs, raid = FC.SafeRead(IsInRaid, category)
    local ns, count = FC.SafeRead(GetNumGroupMembers, category)
    if rs ~= "ready" then return rs end
    if ns ~= "ready" then return ns end
    if not FC.Number(count, 1, raid == true and 40 or 5) then return "loading" end
    result.raid = raid == true
    result.channel = category == instance and "INSTANCE_CHAT" or (result.raid and "RAID" or "PARTY")
    for index = 1, count do
        local unit = result.raid and "raid" .. index or (index == 1 and "player" or "party" .. (index-1))
        local es, exists = FC.SafeRead(UnitExists, unit)
        if es ~= "ready" then return es end
        if not exists then return "loading" end
        local name = fullName(unit)
        local us, guid = FC.SafeRead(UnitGUID, unit)
        if us ~= "ready" then return us end
        if not name or type(guid) ~= "string" or guid == "" or result.membersByName[name] then return "loading" end
        result.membersByName[name],result.memberGUIDs[name] = true,guid
        local ls, leader = FC.SafeRead(UnitIsGroupLeader, unit, category)
        if ls ~= "ready" then return ls end
        if leader then
            if result.leader then return "loading" end
            result.leader,result.leaderGUID = name,guid
        end
    end
    if not result.leader or not result.membersByName[result.selfName] then return "loading" end
    return "ready", result
end

function API.Sender(name, party)
    if not FC.Readable(name) or type(name) ~= "string" then return nil end
    if party.membersByName[name] then return name end
    if name:find("-", 1, true) then return nil end
    local found
    for member in pairs(party.membersByName) do
        if member:match("^(.-)-") == name then
            if found then return nil end
            found = member
        end
    end
    return found
end

function API.CanCommunicate()
    if FC.IsCombat() then return false, "Sharing paused during combat." end
    if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return false, "Group communication unavailable." end
    for _, fn in ipairs({"InChatMessagingLockdown", "AreOutgoingAddonChatMessagesRestricted"}) do
        if C_ChatInfo[fn] then
            local s, restricted = FC.SafeRead(C_ChatInfo[fn])
            if s ~= "ready" or restricted then return false, "Client restricts group communication." end
        end
    end
    local status, party = API.Party()
    if status ~= "ready" then return false, "Group roster unavailable; sharing paused." end
    if not party.channel then return false, "Join a party, raid or instance group to share." end
    return true, nil, party
end
