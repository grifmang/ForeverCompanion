local addonName, FC = ...
FC.name, FC.version = addonName, "0.1.10-prototype"
FC.modules, FC.diagnostics, FC.pending = {}, {}, {}
FC.keys = {"legacy", "wallet", "items", "quests", "party"}
local unpackValues = unpack or table.unpack

function FC.Readable(value)
    if issecretvalue and issecretvalue(value) then return false end
    if type(value) == "table" and issecrettable and issecrettable(value) then return false end
    return true
end

function FC.RecordDiagnostic(context, err)
    local message = "Restricted or unavailable data"
    if FC.Readable(err) and type(err) == "string" then
        message = err:gsub("[\r\n]", " "):sub(1, 160)
    end
    FC.diagnostics[#FC.diagnostics + 1] = context .. ": " .. message
    if #FC.diagnostics > 20 then table.remove(FC.diagnostics, 1) end
end

local function pack(...) return {n = select("#", ...), ...} end
function FC.SafeRead(fn, ...)
    if type(fn) ~= "function" then return "unavailable" end
    local result = pack(pcall(fn, ...))
    if not result[1] then
        FC.RecordDiagnostic("Client read", result[2])
        return "error"
    end
    for i = 2, result.n do
        if not FC.Readable(result[i]) then return "restricted" end
    end
    return "ready", unpackValues(result, 2, result.n)
end

function FC.Number(value, minimum, maximum)
    return FC.Readable(value) and type(value) == "number"
        and value == value and value >= minimum and value <= maximum
        and value % 1 == 0
end

function FC.PlainText(value, maximum)
    if not FC.Readable(value) or type(value) ~= "string" then return nil, "Enter text." end
    local text = value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        :gsub("|H.-|h(.-)|h", "%1"):gsub("|[TA].-|[ta]", "")
        :gsub("|", ""):gsub("[%z\1-\31\127]", " ")
        :gsub("^%s+", ""):gsub("%s+$", "")
    if #text > maximum then return nil, "Text is too long (" .. maximum .. " bytes maximum)." end
    -- Reject malformed UTF-8, overlong encodings, surrogate code points and incomplete byte sequences.
    local i = 1
    while i <= #text do
        local b = text:byte(i)
        local count = b < 128 and 1 or (b >= 194 and b <= 223 and 2
            or (b >= 224 and b <= 239 and 3 or (b >= 240 and b <= 244 and 4 or 0)))
        if count == 0 or i + count - 1 > #text then return nil, "Text must be valid UTF-8." end
        for j = 1, count - 1 do
            local c = text:byte(i + j)
            if c < 128 or c > 191 then return nil, "Text must be valid UTF-8." end
        end
        local b2 = text:byte(i + 1)
        if (b == 224 and b2 < 160) or (b == 237 and b2 > 159)
            or (b == 240 and b2 < 144) or (b == 244 and b2 > 143) then
            return nil, "Text must be valid UTF-8."
        end
        i = i + count
    end
    return text
end

function FC.Label(value, maximum)
    local text, err = FC.PlainText(value, maximum or 96)
    if not text then return nil, err end
    if text == "" then return nil, "Enter a name or reason." end
    return text
end

function FC.PositiveInteger(text, maximum)
    if type(text) ~= "string" or not text:match("^%d+$") or #text > 10 then
        return nil, "Enter a whole positive number."
    end
    local value = tonumber(text)
    if not FC.Number(value, 1, maximum) then return nil, "Number exceeds the allowed limit." end
    return value
end

function FC.IsCombat()
    local status, active = FC.SafeRead(InCombatLockdown)
    return status ~= "ready" or active == true
end

function FC.Print(text)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffd8b56cForever Companion:|r " .. text) end
end

function FC.RegisterModule(key, module)
    FC.modules[key] = module
end

function FC.IsEnabled(key)
    return FC.Store and FC.Store.root and FC.Store.root.settings.enabled[key] == true
end

function FC.Invoke(key, method, ...)
    local module = FC.modules[key]
    if not module or type(module[method]) ~= "function" then return end
    local ok, err = pcall(module[method], ...)
    if not ok then FC.RecordDiagnostic(key .. "." .. method, err) end
end

function FC.Refresh(key)
    if FC.pending[key] then return end
    FC.pending[key] = true
    local function refresh()
        FC.pending[key] = nil
        if FC.UI and FC.UI.window and FC.UI.window:IsShown() and FC.UI.selected == key then FC.UI.Render() end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.1, refresh) else refresh() end
end

function FC.SetEnabled(key, enabled)
    if not FC.Store.CanWrite() then return false, "Saved data is read-only." end
    FC.Store.root.settings.enabled[key] = enabled == true
    FC.Invoke(key, enabled and "Enable" or "Disable")
    FC.Refresh(key)
    return true
end

function FC.FormatMoney(copper)
    if not FC.Number(copper, 0, 100000000000000) then return "Unavailable" end
    return string.format("%dg %02ds %02dc", math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end

function FC.GoldInput(copper)
    return string.format("%d.%04d", math.floor(copper / 10000), copper % 10000)
end
