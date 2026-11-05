local _, FC = ...
local API = {}
FC.RecipeAPI = API

-- Read-only adapter for the Forever professions UI. Never cache a partial read.
local function field(value, key)
    if not FC.Readable(value) or type(value) ~= "table" then return nil, false end
    local status, result = FC.SafeRead(function() return value[key] end)
    return result, status == "ready"
end

local function method(value, key, ...)
    if not FC.Readable(value) then return "restricted" end
    if value == nil then return "unavailable" end
    local fn, readable = field(value, key)
    if not readable then return "restricted" end
    return FC.SafeRead(fn, ...)
end

local function fail(status, reason)
    if status ~= "restricted" and status ~= "loading" then status = "unavailable" end
    return status, nil, reason
end

local function text(value, maximum)
    if not FC.Readable(value) or type(value) ~= "string" then return nil end
    local clean = FC.PlainText(value, #value)
    if not clean or clean == "" then return nil end
    if #clean <= maximum then return clean end
    local stop = maximum + 1
    while stop > 1 and clean:byte(stop) >= 128 and clean:byte(stop) <= 191 do stop = stop - 1 end
    return clean:sub(1, stop - 1)
end

local function array(value, maximum)
    if not FC.Readable(value) or type(value) ~= "table" then return nil end
    local status, count = FC.SafeRead(function()
        local n = 0
        for key in pairs(value) do
            if not FC.Number(key, 1, maximum) then return nil end
            n = n + 1
            if n > maximum then return nil end
        end
        for i = 1, n do
            if not FC.Readable(value[i]) or value[i] == nil then return nil end
        end
        return n
    end)
    if status == "ready" then return count end
end

local function identity(info, recipeID)
    local id, ir = field(info, "recipeID")
    local learned, lr = field(info, "learned")
    return ir and lr and FC.Number(id, 1, 10000000) and id == recipeID and learned == true
end

function API.Read(recipeID)
    if not FC.Number(recipeID, 1, 10000000) then
        return fail("unavailable", "Choose a learned recipe.")
    end
    -- These native predicates back Professions.InLocalCraftingMode.
    -- A linked or guild recipe's learned flag is not proof of own knowledge.
    for _, predicate in ipairs({"IsNPCCrafting", "IsTradeSkillGuild", "IsTradeSkillGuildMember", "IsTradeSkillLinked"}) do
        local cs, external = method(C_TradeSkillUI, predicate)
        if cs ~= "ready" then return fail(cs, "Own profession context cannot be verified.") end
        if external ~= false then return fail("unavailable", "Open your own profession recipes.") end
    end
    local status, info = method(C_TradeSkillUI, "GetRecipeInfo", recipeID)
    if status ~= "ready" then return fail(status, "Recipe information is unavailable.") end
    if info == nil then return fail("loading", "Recipe information is not loaded.") end
    if not identity(info, recipeID) then return fail("unavailable", "Recipe is not a known learned recipe.") end
    local recraft, rr = field(info, "isRecraft")
    local level, lr = field(info, "unlockedRecipeLevel")
    if not rr or not lr then return fail("restricted", "Recipe variant is restricted.") end
    if recraft == true or level ~= nil then
        return fail("unavailable", "Recrafting and recipe levels are not supported.")
    end
    local name, nr = field(info, "name")
    local label = nr and text(name, 96)
    if not label then return fail("restricted", "Recipe name is unavailable.") end

    local ss, schematic = method(C_TradeSkillUI, "GetRecipeSchematic", recipeID, false)
    if ss ~= "ready" then return fail(ss, "Recipe ingredients are unavailable.") end
    if schematic == nil then return fail("loading", "Recipe ingredients are not loaded.") end
    local id, ir = field(schematic, "recipeID")
    local kind, kr = field(schematic, "recipeType")
    if not ir or not kr then return fail("restricted", "Recipe identity is restricted.") end
    -- Forever TradeskillRecipeType: Item=1, Salvage=2, Enchant=3, Gathering=4.
    if not FC.Number(id, 1, 10000000) or id ~= recipeID or (kind ~= 1 and kind ~= 3) then
        return fail("unavailable", "This recipe type is not supported.")
    end
    local slots, sr = field(schematic, "reagentSlotSchematics")
    local count = sr and array(slots, 32)
    if not count or count == 0 then return fail("unavailable", "Complete recipe ingredients are required.") end
    local reagents, byID = {}, {}
    for i = 1, count do
        local slot = field(slots, i)
        local required, rr = field(slot, "required")
        local slotType, tr = field(slot, "dataSlotType")
        local quantity, qr = field(slot, "quantityRequired")
        local choices, cr = field(slot, "reagents")
        local variables, vr = field(slot, "variableQuantities")
        if not rr or not tr or not qr or not cr or not vr then
            return fail("restricted", "Recipe ingredients are restricted.")
        end
        -- Optional allocations cannot be reconstructed by a plain per-ID read.
        -- Reject the whole recipe instead of omitting a selected consumed input.
        if required ~= true or slotType ~= 1 or not FC.Number(quantity, 1, 100000)
            or (variables ~= nil and array(variables, 32) ~= 0) or array(choices, 32) ~= 1 then
            return fail("unavailable", "Optional, alternative or variable ingredients are not supported.")
        end
        local choice = field(choices, 1)
        local itemID, itemRead = field(choice, "itemID")
        local currencyID, currencyRead = field(choice, "currencyID")
        if not itemRead or not currencyRead then return fail("restricted", "Ingredient identity is restricted.") end
        if not FC.Number(itemID, 1, 10000000) or currencyID ~= nil then
            return fail("unavailable", "Only fixed item ingredients are supported.")
        end
        local row = byID[itemID]
        if row then
            if row.quantity + quantity > 100000 then return fail("unavailable", "Ingredient quantity exceeds the limit.") end
            row.quantity = row.quantity + quantity
        else
            row = {itemID = itemID, quantity = quantity}
            byID[itemID], reagents[#reagents + 1] = row, row
        end
    end

    local ps, professionInfo = method(C_TradeSkillUI, "GetProfessionInfoByRecipeID", recipeID)
    if ps ~= "ready" then return fail(ps, "Profession information is unavailable.") end
    local professionName, pr = field(professionInfo, "professionName")
    local profession = pr and text(professionName, 96)
    local bs, version, build = FC.SafeRead(GetBuildInfo)
    version, build = text(version, 64), text(build, 64)
    if bs ~= "ready" then return fail(bs, "Client build is unavailable.") end
    if not profession or not version or not build or #version + #build + 1 > 64 then
        return fail("loading", "Recipe metadata is not loaded.")
    end
    -- Detect a changed/unlearned recipe before publishing the atomic snapshot.
    local rs, current = method(C_TradeSkillUI, "GetRecipeInfo", recipeID)
    if rs ~= "ready" then return fail(rs, "Recipe information changed; try again.") end
    if not identity(current, recipeID) then return fail("loading", "Recipe information changed; try again.") end
    return "ready", {recipeID = recipeID, label = label, profession = profession,
        kind = "modern", build = version .. "/" .. build, reagents = reagents}
end

function API.Selected()
    local visible, shown = method(ProfessionsFrame, "IsVisible", ProfessionsFrame)
    if visible ~= "ready" or shown ~= true then
        return fail(visible, "Open your profession window and select a learned recipe.")
    end
    local page = field(ProfessionsFrame, "CraftingPage")
    local form = field(page, "SchematicForm")
    local fs, formShown = method(form, "IsVisible", form)
    if fs ~= "ready" or formShown ~= true then
        return fail(fs, "Select a recipe in the profession crafting page.")
    end
    local ts, transaction = method(form, "GetTransaction", form)
    local rs, recraft = method(transaction, "IsRecraft", transaction)
    local ls, level = method(form, "GetCurrentRecipeLevel", form)
    if ts ~= "ready" or rs ~= "ready" or ls ~= "ready" then
        return fail("unavailable", "Selected recipe variant cannot be verified.")
    end
    if recraft ~= false or level ~= nil then
        return fail("unavailable", "Recrafting and recipe levels are not supported.")
    end
    -- Native Forever source getter; do not guess a list index or frame property.
    local status, info = method(form, "GetRecipeInfo", form)
    if status ~= "ready" then return fail(status, "The selected recipe is unavailable.") end
    local recipeID, readable = field(info, "recipeID")
    if not readable or not FC.Number(recipeID, 1, 10000000) or not identity(info, recipeID) then
        return fail("unavailable", "Select a learned crafting recipe.")
    end
    local readStatus, snapshot, reason = API.Read(recipeID)
    if readStatus ~= "ready" then return readStatus, nil, reason end
    local vs, stillShown = method(ProfessionsFrame, "IsVisible", ProfessionsFrame)
    local rs, selected = method(form, "GetRecipeInfo", form)
    if vs ~= "ready" or rs ~= "ready" or stillShown ~= true or not identity(selected, recipeID) then
        return fail("loading", "Recipe selection changed; try again.")
    end
    return "ready", snapshot
end
