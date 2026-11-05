local _, FC = ...
local UI = FC.UI
local titles = {legacy = "Legacy Compass", wallet = "Launch Wallet", items = "Keep or Sell?", party = "Adventure Together", settings = "Settings"}

local function ensure()
    if UI.window then return end
    local f = CreateFrame("Frame", "ForeverCompanionWindow", UIParent, "BackdropTemplate")
    UI.window = f
    f:SetSize(850, 610); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
    local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
    f:SetScale(math.min(1, screenWidth / 900, screenHeight / 660))
    f:SetBackdrop({bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 14, insets = {left=4,right=4,top=4,bottom=4}})
    f:SetBackdropColor(0.055, 0.07, 0.085, 0.98); f:SetBackdropBorderColor(0.66, 0.54, 0.31)
    f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if FC.Store.CanWrite() then
            local point, _, relative, x, y = self:GetPoint()
            FC.Store.root.settings.position = {point=point, relative=relative, x=x, y=y}
        end
    end)
    local pos = FC.Store.root.settings.position
    if type(pos) == "table" and type(pos.point) == "string" and type(pos.relative) == "string"
        and type(pos.x) == "number" and type(pos.y) == "number" then
        local ok = pcall(function() f:ClearAllPoints(); f:SetPoint(pos.point, UIParent, pos.relative, pos.x, pos.y) end)
        if not ok then f:ClearAllPoints(); f:SetPoint("CENTER") end
    end
    local heading = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    heading:SetPoint("TOPLEFT", 22, -22); heading:SetText("FOREVER COMPANION")
    local sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", 23, -49); sub:SetText("Plan your journey. Prepare together.  |  Beta prototype")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -7, -7)
    table.insert(UISpecialFrames, "ForeverCompanionWindow")
    UI.tabs = {}
    local keys = {"legacy", "wallet", "items", "party", "settings"}
    for index, key in ipairs(keys) do
        local button = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        button:SetPoint("TOPLEFT", 22 + (index - 1) * 160, -77); button:SetSize(154, 26)
        button:SetText(titles[key]); button:SetScript("OnClick", function() UI.Open(key) end)
        UI.tabs[key] = button
    end
    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 25, -120); scroll:SetPoint("BOTTOMRIGHT", -44, 55)
    UI.scroll = scroll
    UI.child = CreateFrame("Frame", nil, scroll)
    UI.child:SetSize(770, 430); scroll:SetScrollChild(UI.child)
    UI.footer = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    UI.footer:SetPoint("BOTTOMLEFT", 25, 20); UI.footer:SetWidth(775); UI.footer:SetJustifyH("LEFT")
    f:Hide()
end

local function renderSettings(parent)
    UI.Label(parent, "Choose the tools you need", 0, 0, 730, true)
    UI.Label(parent, "Disabling a module keeps its saved records. Automatic group joining has its own switch.", 0, 27)
    for i, key in ipairs(FC.keys) do
        UI.Check(parent, titles[key], 0, 68 + (i - 1) * 42, FC.IsEnabled(key), function(enabled)
            UI.Result(FC.SetEnabled(key, enabled))
        end, FC.Store.CanWrite())
    end
    UI.Label(parent, "Version " .. FC.version .. "  |  /fc diagnostics prints client capabilities and recent errors.", 0, 260)
    UI.Label(parent, FC.Updates and FC.Updates.Status() or "Use /fc updates for release information.", 0, 298)
    UI.Input(parent, "Release page (copy this link)", 0, 356, 730, FC.Updates and FC.Updates.url or "", 128, function() end)
    UI.Label(parent, "Enabled sharing also announces your installed addon version to the active group.", 0, 425)
    UI.Height(480)
end

function UI.Render()
    if not UI.window then return end
    local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    if focus and focus.fcInput then
        UI.footer:SetText(FC.Store.status or UI.message)
        return
    end
    UI.Begin(UI.child)
    if not FC.Store.Character() then
        UI.Label(UI.child, "Character data is not available yet. Try again after entering the world.", 0, 0)
    elseif UI.selected == "settings" then renderSettings(UI.child)
    elseif not FC.IsEnabled(UI.selected) then
        UI.Label(UI.child, titles[UI.selected] .. " is disabled.", 0, 0, 730, true)
        UI.Button(UI.child, "Enable module", 0, 40, 150, function()
            UI.Result(FC.SetEnabled(UI.selected, true))
        end, FC.Store.CanWrite())
        UI.Height(430)
    else
        local module = FC.modules[UI.selected]
        local ok, err = pcall(module.Render, UI.child)
        if not ok then
            FC.RecordDiagnostic(UI.selected .. " render", err)
            UI.Label(UI.child, "This panel is unavailable. Check /fc diagnostics; the other modules remain usable.", 0, 390)
        end
    end
    UI.footer:SetText(FC.Store.status or UI.message)
end

function UI.Open(key)
    ensure()
    key = titles[key] and key or UI.selected or "wallet"
    local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    if focus and focus.fcInput then focus:ClearFocus() end
    UI.selected, UI.message = key, ""
    for tabKey, button in pairs(UI.tabs) do button:SetEnabled(tabKey ~= key) end
    UI.scroll:SetVerticalScroll(0)
    UI.window:Show()
    if key == "legacy" and FC.IsEnabled(key) then FC.Invoke(key, "Load") end
    UI.Render()
end
