local _, FC = ...
local API = {}
FC.PriceAPI = API

-- Read-only snapshots of the native Forever merchant/trainer catalogues.
local function fail(status, reason)
    return status == "restricted" and "restricted" or "unavailable", nil, reason
end

local function read(fn, ...)
    if not FC.Readable(fn) then return "restricted" end
    return FC.SafeRead(fn, ...)
end

local function field(object, key)
    if not FC.Readable(object) then return "restricted" end
    if object == nil then return "unavailable" end
    return FC.SafeRead(function() return object[key] end)
end

local function visible(frame)
    local status, fn = field(frame, "IsVisible")
    if status ~= "ready" then return status, false end
    return read(fn, frame)
end

local function text(value, maximum, truncate)
    if not FC.Readable(value) or type(value) ~= "string" then return nil end
    local clean = FC.PlainText(value, #value)
    if not clean then return nil end
    clean = clean:gsub("%s+", " ")
    if #clean <= maximum then return clean end
    if not truncate then return nil end
    local stop = maximum + 1
    while stop > 1 and clean:byte(stop) >= 128 and clean:byte(stop) <= 191 do stop = stop - 1 end
    return clean:sub(1, stop - 1)
end

local function npc()
    local gs, guid = read(UnitGUID, "npc")
    local ns, name = read(UnitName, "npc")
    if gs ~= "ready" then return gs end
    if ns ~= "ready" then return ns end
    if type(guid) ~= "string" or #guid == 0 or #guid > 128 or guid:find("[^ -~]") then
        return "unavailable"
    end
    name = text(name, 96, true)
    if not name or name == "" then return "unavailable" end
    return "ready", guid, name
end

local function offer(catalogue, index, label, bundle, identity)
    return {kind = catalogue.kind, npcGUID = catalogue.npcGUID, npcName = catalogue.npcName,
        apiIndex = index, identity = identity, label = label, quoteKey = "", bundleSize = bundle,
        observedAt = catalogue.observedAt, stable = catalogue.kind == "merchant"}
end

local function merchantRow(catalogue, index)
    local status, name, _, price, bundle, stock, purchasable, usable, extended, currency =
        read(GetMerchantItemInfo, index)
    if status ~= "ready" then return nil, true end
    local label = text(name, 96, true)
    if not label or label == "" or not FC.Number(bundle, 1, 1000000) then return nil, true end
    local ids, itemID = read(GetMerchantItemID, index)
    if ids ~= "ready" or not FC.Number(itemID, 1, 10000000) then return nil, true end
    local row = offer(catalogue, index, label, bundle, "item:" .. itemID .. ":" .. bundle)
    local reason
    if not FC.Number(stock, -1, 1000000000) then reason = "Stock is unknown."
    elseif stock == 0 then reason = "This offer is out of stock."
    elseif purchasable ~= true then reason = "This offer is not confirmed purchasable."
    elseif extended ~= false then reason = "Alternate or unknown costs are not supported."
    elseif currency ~= nil then reason = "Currency offers are not supported."
    elseif usable ~= true and usable ~= false then reason = "Offer flags are incomplete."
    elseif not FC.Number(price, 0, 10000000000) then reason = "Gold price is unknown." end
    row.unitCopper, row.unsupportedReason = reason == nil and price or nil, reason
    return row
end

local function trainerGold()
    -- The native UI interprets the same cost tuple as training points for pets.
    local fs, fn = field(C_Trainer, "GetTrainerType")
    local es, trainerTypes = field(Enum, "TrainerType")
    local ps, petType = field(trainerTypes, "Pet")
    if fs ~= "ready" or es ~= "ready" or ps ~= "ready" or not FC.Number(petType, 0, 1000) then
        return false
    end
    local status, kind = read(fn)
    return status == "ready" and FC.Number(kind, 0, 1000) and kind ~= petType
end

local function trainerKey(name, subtext, category)
    local parts = {name, subtext == nil and "" or subtext, category == nil and "" or category}
    for i = 1, 3 do
        parts[i] = text(parts[i], 192, false)
        if not parts[i] then return nil end
    end
    -- Length prefixes prevent collisions when names contain separator characters.
    local key = #parts[1] .. ":" .. parts[1] .. #parts[2] .. ":" .. parts[2]
        .. #parts[3] .. ":" .. parts[3]
    if #key <= 192 then return key end
end

local function trainerRow(catalogue, index, gold)
    local status, name, kind, _, _, subtext, category = read(GetTrainerServiceInfo, index)
    if status ~= "ready" then return nil, true end
    -- Headers, categories, and already learned services are not offers.
    if kind ~= "available" and kind ~= "unavailable" then return nil end
    local fullName=type(name)=="string" and name or nil
    if fullName and type(subtext)=="string" and subtext~="" then fullName=fullName .. " (" .. subtext .. ")" end
    local label = text(fullName, 96, true)
    if not label or label == "" then return nil, true end
    local row = offer(catalogue, index, label, 1, "")
    local key = trainerKey(name, subtext, category)
    local cs, cost, profession = read(GetTrainerServiceCost, index)
    local reason
    if not key then reason = "Service description is incomplete or too long."
    elseif not gold then reason = "Gold trainer costs cannot be verified."
    elseif cs ~= "ready" or not FC.Number(cost, 0, 10000000000) then reason = "Gold price is unknown."
    elseif profession ~= true and profession ~= false then reason = "Service cost flags are incomplete." end
    row.quoteKey = key or ""
    row.unitCopper, row.unsupportedReason = reason == nil and cost or nil, reason
    return row
end

local function scan(kind)
    if not FC.Readable(kind) then return fail("restricted", "Catalogue kind is restricted.") end
    if kind ~= nil and kind ~= "merchant" and kind ~= "trainer" then
        return fail("unavailable", "Choose a merchant or trainer catalogue.")
    end
    local ms, merchantShown = visible(MerchantFrame)
    local ts, trainerShown = visible(ClassTrainerFrame)
    if kind == nil then
        if ms == "ready" and merchantShown == true then kind = "merchant"
        elseif ts == "ready" and trainerShown == true then kind = "trainer" end
    end
    local frame = kind == "merchant" and MerchantFrame or ClassTrainerFrame
    if (kind == "merchant" and (ms ~= "ready" or merchantShown ~= true))
        or (kind == "trainer" and (ts ~= "ready" or trainerShown ~= true)) or kind == nil then
        return fail("unavailable", "Open the native merchant or trainer window.")
    end
    if kind == "merchant" then
        local ss, tab = field(frame, "selectedTab")
        if ss ~= "ready" or tab ~= 1 then return fail(ss, "Select the merchant's sale catalogue, not buyback.") end
    end
    local ns, guid, name = npc()
    if ns ~= "ready" then return fail(ns, "NPC identity is unavailable.") end
    local ds, observedAt = read(time)
    if ds ~= "ready" or not FC.Number(observedAt, 0, 100000000000) then
        return fail(ds, "Quote time is unavailable.")
    end
    local countFn = kind == "merchant" and GetMerchantNumItems or GetNumTrainerServices
    local infoFn = kind == "merchant" and GetMerchantItemInfo or GetTrainerServiceInfo
    local costFn = kind == "merchant" and GetMerchantItemID or GetTrainerServiceCost
    if not FC.Readable(infoFn) or not FC.Readable(costFn)
        or type(infoFn) ~= "function" or type(costFn) ~= "function" then
        return fail("unavailable", "This client does not expose the supported price APIs.")
    end
    local status, count = read(countFn)
    if status ~= "ready" or not FC.Number(count, 0, 1000000) then
        return fail(status, "Catalogue size is unavailable.")
    end
    local catalogue = {kind = kind, npcGUID = guid, npcName = name, observedAt = observedAt,
        offers = {}, partial = count > 200}
    local gold = kind == "trainer" and trainerGold()
    local keys = {}
    for index = 1, math.min(count, 200) do
        local row, skipped
        if kind == "merchant" then row, skipped = merchantRow(catalogue, index)
        else row, skipped = trainerRow(catalogue, index, gold) end
        if skipped then catalogue.partial = true end
        if row then
            catalogue.offers[#catalogue.offers + 1] = row
            if kind == "trainer" and row.quoteKey ~= "" then
                local prior = keys[row.quoteKey]
                if prior then
                    prior.unitCopper, row.unitCopper = nil, nil
                    prior.unsupportedReason, row.unsupportedReason = "Service description is ambiguous.", "Service description is ambiguous."
                else keys[row.quoteKey] = row end
            end
        end
    end
    local vs, shown = visible(frame)
    local rs, currentGUID, currentName = npc()
    local cs, currentCount = read(countFn)
    if vs ~= "ready" or shown ~= true or rs ~= "ready" or currentGUID ~= guid or currentName ~= name
        or cs ~= "ready" or currentCount ~= count then
        return fail("unavailable", "The NPC catalogue changed; scan again.")
    end
    if kind == "merchant" then
        local ss, tab = field(frame, "selectedTab")
        if ss ~= "ready" or tab ~= 1 then return fail(ss, "The merchant catalogue changed; scan again.") end
    end
    return "ready", catalogue
end

function API.Scan(kind)
    local status, result, catalogue, reason = FC.SafeRead(scan, kind)
    if status ~= "ready" then return fail(status, "Price data is restricted or unavailable.") end
    return result, catalogue, reason
end

local function refresh(old)
    if not FC.Readable(old) or type(old) ~= "table" then return fail("unavailable", "Choose an offer again.") end
    local fields = {"kind", "npcGUID", "npcName", "apiIndex", "identity", "quoteKey", "unitCopper"}
    local snapshot = {}
    for _, key in ipairs(fields) do
        local status, value = field(old, key)
        if status ~= "ready" then return fail(status, "Offer data is restricted.") end
        snapshot[key] = value
    end
    if (snapshot.kind ~= "merchant" and snapshot.kind ~= "trainer")
        or type(snapshot.npcGUID) ~= "string" or type(snapshot.npcName) ~= "string"
        or not FC.Number(snapshot.unitCopper, 0, 10000000000) then
        return fail("unavailable", "Choose a supported offer again.")
    end
    local status, catalogue, reason = API.Scan(snapshot.kind)
    if status ~= "ready" then return status, nil, reason end
    if catalogue.npcGUID ~= snapshot.npcGUID or catalogue.npcName ~= snapshot.npcName then
        return fail("unavailable", "Return to the same NPC and choose the offer again.")
    end
    local match
    for _, row in ipairs(catalogue.offers) do
        local same
        if snapshot.kind == "merchant" then
            same = type(snapshot.identity) == "string" and snapshot.identity ~= "" and row.identity == snapshot.identity
            if catalogue.partial then
                same=same and row.apiIndex==snapshot.apiIndex and row.unitCopper==snapshot.unitCopper
            end
        else
            same = FC.Number(snapshot.apiIndex, 1, 200) and row.apiIndex == snapshot.apiIndex
                and type(snapshot.quoteKey) == "string" and snapshot.quoteKey ~= "" and row.quoteKey == snapshot.quoteKey
                and row.unitCopper == snapshot.unitCopper
        end
        if same then
            if match then return fail("unavailable", "The offer is ambiguous; choose it again.") end
            match = row
        end
    end
    if not match then return fail("unavailable", "The offer changed; choose it again.") end
    if match.unitCopper == nil then return fail("unavailable", match.unsupportedReason or "This offer is unsupported.") end
    match.partial=catalogue.partial
    return "ready", match
end

function API.RefreshOffer(old)
    local status, result, fresh, reason = FC.SafeRead(refresh, old)
    if status ~= "ready" then return fail(status, "Offer data is restricted or unavailable.") end
    return result, fresh, reason
end
