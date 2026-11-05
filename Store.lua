local _, FC = ...
FC.Store = {readOnly = true}
local Store = FC.Store

local function clone(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}; seen[value] = out
    for key, item in pairs(value) do out[clone(key, seen)] = clone(item, seen) end
    return out
end

local function newCharacter(name)
    return {name = name, nextID = 0, wallet = {}, needs = {}, keep = {}, crafting = {},
        legacy = {pins = {}, plans = {}}, adventure = {title = "", meeting = "", tasks = {}},
        questHelper = {view = "route"}}
end

local function quarantine(root, record)
    Store.corrupt = true
    root.quarantine = type(root.quarantine) == "table" and root.quarantine or {}
    if #root.quarantine < 20 then root.quarantine[#root.quarantine + 1] = record end
end

local function cleanList(root, list, maximum, valid)
    local out, seen = {}, {}
    if type(list) ~= "table" then quarantine(root, list); return out end
    for _, record in pairs(list) do
        if #out < maximum and type(record) == "table" and valid(record) and not seen[record.id] then
            out[#out + 1], seen[record.id] = record, true
        else quarantine(root, record) end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

local function validID(record) return FC.Number(record.id, 1, 1000000) end
local function label(value) return type(value) == "string" and FC.Label(value, 96) == value end
local function validAllocation(a)
    return type(a) == "table" and label(a.label) and label(a.treeKey)
        and label(a.perkKey) and FC.Number(a.points, 0, 1000)
end

local function validPriceSource(record)
    local s=record.source
    if s==nil then return true end
    if type(s)~="table" or (s.kind~="merchant" and s.kind~="trainer")
        or type(s.npcGUID)~="string" or #s.npcGUID==0 or #s.npcGUID>128
        or FC.PlainText(s.npcGUID,128)~=s.npcGUID or not label(s.npcName)
        or type(s.identity)~="string" or #s.identity>96 or FC.PlainText(s.identity,96)~=s.identity
        or type(s.quoteKey)~="string" or FC.PlainText(s.quoteKey,192)~=s.quoteKey
        or type(s.stable)~="boolean" or not FC.Number(s.unitCopper,0,10000000000)
        or not FC.Number(s.bundleSize,1,1000000) or not FC.Number(s.quantity,1,9999)
        or not FC.Number(s.observedAt,0,100000000000) then return false end
    if s.kind=="merchant" then
        if not s.stable or not FC.Number(s.itemID,1,10000000)
            or s.identity~=("item:" .. s.itemID .. ":" .. s.bundleSize) or s.quoteKey~="" then return false end
    elseif s.stable or s.identity~="" or s.quoteKey=="" or s.itemID~=nil or s.bundleSize~=1 or s.quantity~=1 then return false end
    local total=s.unitCopper*s.quantity
    return FC.Number(total,0,10000000000) and total==record.copper
end

function Store.Initialize()
    local saved = ForeverCompanionDB
    Store.original, Store.corrupt, Store.character = saved, false, nil
    local future = type(saved) == "table" and type(saved.schema) == "number" and saved.schema > 1
    local unsupported = saved ~= nil and (type(saved) ~= "table"
        or (saved.schema ~= nil and saved.schema ~= 1))
    if future or unsupported then
        Store.root = {schema = 1, settings = {enabled = {}}, characters = {}}
        for _, key in ipairs(FC.keys) do Store.root.settings.enabled[key] = true end
        Store.readOnly, Store.status = true, "Saved data uses an unsupported schema. Original data preserved; writes disabled."
        return "read-only"
    end
    local root = saved and clone(saved) or {schema = 1, settings = {}, characters = {}}
    root.schema = 1
    if type(root.settings) ~= "table" then quarantine(root, root.settings); root.settings = {} end
    if type(root.settings.enabled) ~= "table" then
        if root.settings.enabled ~= nil then quarantine(root, root.settings.enabled) end
        root.settings.enabled = {}
    end
    if root.settings.partySharing == nil then
        root.settings.partySharing = true
    elseif type(root.settings.partySharing) ~= "boolean" then
        quarantine(root, root.settings.partySharing)
        root.settings.partySharing = false
    end
    if root.settings.questReplacement ~= nil and type(root.settings.questReplacement) ~= "boolean" then
        quarantine(root, root.settings.questReplacement)
        root.settings.questReplacement = false
    end
    for _, key in ipairs(FC.keys) do
        if type(root.settings.enabled[key]) ~= "boolean" then
            if root.settings.enabled[key] ~= nil then quarantine(root, root.settings.enabled[key]) end
            root.settings.enabled[key] = true
        end
    end
    if type(root.characters) ~= "table" then quarantine(root, root.characters); root.characters = {} end
    Store.root, Store.readOnly, Store.status = root, false, nil
    ForeverCompanionDB = root
    return "ready"
end

function Store.Character()
    if Store.character then return Store.character end
    local status, guid, name = FC.API.Identity()
    if status ~= "ready" then return nil end
    local record = Store.root.characters[guid]
    if type(record) ~= "table" then
        if record ~= nil and not Store.readOnly then quarantine(Store.root, record) end
        record = newCharacter(name)
    end
    if Store.readOnly then
        Store.character = record
        return record
    end
    local root = Store.root
    if record.questHelper ~= nil and type(record.questHelper) ~= "table" then
        quarantine(root, record.questHelper); record.questHelper = nil
    end
    record.questHelper = record.questHelper or {view = "route"}
    local helper = record.questHelper
    if helper.view ~= "nearby" then helper.view = "route" end
    if type(helper.area) ~= "string" or #helper.area > 80 or not helper.area:match("^[%w:_%-]+$") then helper.area = nil end
    record.wallet = cleanList(root, record.wallet, 100, function(r)
        return validID(r) and label(r.label) and FC.Number(r.copper, 0, 10000000000)
            and type(r.active) == "boolean" and validPriceSource(r)
    end)
    record.needs = cleanList(root, record.needs, 100, function(r)
        return validID(r) and FC.Number(r.itemID, 1, 10000000) and FC.Number(r.quantity, 1, 1000000) and label(r.reason)
    end)
    if record.crafting==nil then record.crafting={} end
    local recipeIDs={}
    record.crafting=cleanList(root,record.crafting,50,function(r)
        if not validID(r) or not FC.Number(r.recipeID,1,10000000) or recipeIDs[r.recipeID]
            or r.kind~="modern" or not label(r.label) or not label(r.profession)
            or not FC.Number(r.requested,1,9999) or not FC.Number(r.remaining,0,r.requested)
            or not FC.Number(r.revision,1,1000000) or type(r.build)~="string" or r.build==""
            or FC.PlainText(r.build,64)~=r.build or type(r.reagents)~="table" then return false end
        local n,seen=0,{}
        for key,reagent in pairs(r.reagents) do
            if not FC.Number(key,1,32) or type(reagent)~="table" or not FC.Number(reagent.itemID,1,10000000)
                or seen[reagent.itemID] or not FC.Number(reagent.quantity,1,100000) then return false end
            seen[reagent.itemID]=true; n=n+1
        end
        if n==0 or n~=#r.reagents then return false end
        for index=1,n do if not r.reagents[index] then return false end end
        recipeIDs[r.recipeID]=true
        return true
    end)
    local keeps = {}
    if type(record.keep) == "table" then
        local count = 0
        for id, reason in pairs(record.keep) do
            if count < 100 and FC.Number(id, 1, 10000000) and label(reason) then
                keeps[id], count = reason, count + 1
            else quarantine(root, {id, reason}) end
        end
    else quarantine(root, record.keep) end
    record.keep = keeps
    if type(record.legacy) ~= "table" then
        quarantine(root, record.legacy); record.legacy = {pins = {}, plans = {}}
    end
    local pins, pinCount = {}, 0
    if type(record.legacy.pins) == "table" then
        for id, enabled in pairs(record.legacy.pins) do
            if pinCount < 100 and FC.Number(id, 1, 1000000) and enabled == true then
                pins[id], pinCount = true, pinCount + 1
            else quarantine(root, {id, enabled}) end
        end
    else quarantine(root, record.legacy.pins) end
    record.legacy.pins = pins
    record.legacy.plans = cleanList(root, record.legacy.plans, 20, function(r)
        if not validID(r) or not label(r.name) or not FC.Number(r.cap, 1, 1000)
            or type(r.allocations) ~= "table" or #r.allocations > 50
            or type(r.manual) ~= "boolean" or type(r.notes) ~= "string"
            or FC.PlainText(r.notes, 192) ~= r.notes then return false end
        local seen, sum = {}, 0
        for _, a in ipairs(r.allocations) do
            if not validAllocation(a) then return false end
            local key = a.treeKey .. ":" .. a.perkKey
            if seen[key] then return false end
            seen[key], sum = true, sum + a.points
        end
        return sum <= r.cap
    end)
    if type(record.adventure) ~= "table" then
        quarantine(root, record.adventure); record.adventure = {title = "", meeting = "", tasks = {}}
    end
    for key, limit in pairs({title = 96, meeting = 192}) do
        local original = record.adventure[key]
        local text = FC.PlainText(original, limit)
        if text == nil or text ~= original then quarantine(root, {key, original}) end
        record.adventure[key] = text or ""
    end
    record.adventure.tasks = cleanList(root, record.adventure.tasks, 20, function(r)
        return validID(r) and label(r.text) and type(r.done) == "boolean"
    end)
    if not FC.Number(record.nextID, 0, 1000000) then quarantine(root, record.nextID) end
    local maxID = FC.Number(record.nextID, 0, 1000000) and record.nextID or 0
    local allIDs={}
    for _, list in ipairs({record.wallet, record.needs, record.legacy.plans, record.adventure.tasks,record.crafting}) do
        for _, r in ipairs(list) do
            if allIDs[r.id] then quarantine(root,{duplicateID=r.id}) end
            allIDs[r.id]=true; maxID = math.max(maxID, r.id)
        end
    end
    record.nextID, record.name, record.observedAt = maxID, name, time()
    root.characters[guid], Store.character = record, record
    if Store.corrupt then
        Store.readOnly = true
        Store.status = "Some saved data is invalid. Original save preserved intact; recovered view is read-only. Restore a backup with the game closed."
        ForeverCompanionDB = Store.original
    end
    return record
end

function Store.CanWrite()
    if not Store.root then return false end
    local character = Store.Character()
    return not Store.readOnly and character ~= nil
end
function Store.NewID()
    if not Store.CanWrite() then return nil, "Saved data is read-only or character data is unavailable." end
    local record = Store.Character()
    if record.nextID >= 1000000 then return nil, "Record ID limit reached." end
    record.nextID = record.nextID + 1
    return record.nextID
end

function Store.Find(list, id)
    for index, record in ipairs(list) do if record.id == id then return record, index end end
end

function Store.Remove(list, id)
    if not Store.CanWrite() then return false, "Saved data is read-only." end
    local _, index = Store.Find(list, id)
    if not index then return false, "That record no longer exists." end
    table.remove(list, index)
    return true
end
