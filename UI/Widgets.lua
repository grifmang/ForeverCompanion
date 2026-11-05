local _, FC = ...
FC.UI = {views = {}, message = ""}
local UI = FC.UI
local function widget(parent, kind, create)
    parent.fcPools = parent.fcPools or {}
    parent.fcCounts = parent.fcCounts or {}
    parent.fcPools[kind] = parent.fcPools[kind] or {}
    local index = (parent.fcCounts[kind] or 0) + 1
    parent.fcCounts[kind] = index
    local pool = parent.fcPools[kind]
    if not pool[index] then pool[index] = create() end
    pool[index]:Show()
    return pool[index]
end

function UI.Begin(parent)
    for _, pool in pairs(parent.fcPools or {}) do
        for _, frame in ipairs(pool) do frame:Hide() end
    end
    parent.fcCounts = {}
end

function UI.View(key)
    UI.views[key] = UI.views[key] or {}
    return UI.views[key]
end

function UI.Label(parent, text, x, y, width, gold)
    local fs = widget(parent, "label", function() return parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight") end)
    fs:ClearAllPoints(); fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    fs:SetWidth(width or 690); fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP")
    fs:SetTextColor(gold and 0.85 or 0.82, gold and 0.71 or 0.84, gold and 0.42 or 0.87)
    fs:SetText(text)
    return fs
end

function UI.Button(parent, text, x, y, width, callback, enabled)
    local button = widget(parent, "button", function() return CreateFrame("Button", nil, parent, "UIPanelButtonTemplate") end)
    button:ClearAllPoints(); button:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    button:SetSize(width or 110, 24); button:SetText(text)
    button:SetEnabled(enabled ~= false)
    button:SetScript("OnClick", function()
        local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
        if focus and focus.fcInput then focus:ClearFocus() end
        local ok, err = pcall(callback)
        if not ok then FC.RecordDiagnostic("Button", err); UI.message = "Action failed. See /fc diagnostics." end
        UI.Render()
    end)
    return button
end

function UI.Input(parent, label, x, y, width, value, maximum, changed)
    local holder = widget(parent, "input", function()
        local h = CreateFrame("Frame", nil, parent)
        h.caption = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h.caption:SetPoint("TOPLEFT"); h.caption:SetJustifyH("LEFT")
        h.edit = CreateFrame("EditBox", nil, h, "InputBoxTemplate")
        h.edit:SetAutoFocus(false); h.edit:SetPoint("TOPLEFT", 6, -17); h.edit:SetHeight(25)
        h.edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        h.edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        h.edit.fcInput = true
        return h
    end)
    holder:ClearAllPoints(); holder:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    holder:SetSize(width, 45); holder.caption:SetText(label)
    holder.edit:SetWidth(width - 12); holder.edit:SetMaxLetters(maximum or 96)
    holder.edit:SetScript("OnTextChanged", nil)
    holder.edit:SetText(value or ""); holder.edit:SetCursorPosition(0)
    holder.edit:SetScript("OnTextChanged", function(self) if changed then changed(self:GetText()) end end)
    holder.edit:SetScript("OnEditFocusLost", function() FC.Refresh(UI.selected or "wallet") end)
    return holder.edit
end

function UI.Check(parent, text, x, y, checked, callback, enabled)
    local check = widget(parent, "check", function()
        local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        c.fcText = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        c.fcText:SetPoint("LEFT", c, "RIGHT", 2, 0)
        c.fcText:SetJustifyH("LEFT")
        return c
    end)
    check:ClearAllPoints(); check:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    check:SetSize(24, 24); check:SetChecked(checked == true); check:SetEnabled(enabled ~= false)
    check.fcText:SetText(text); check.fcText:SetWidth(560)
    check:SetScript("OnClick", function(self)
        local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
        if focus and focus.fcInput then focus:ClearFocus() end
        local ok, err = pcall(callback, self:GetChecked() == true)
        if not ok then FC.RecordDiagnostic("Checkbox", err); UI.message = "Action failed. See /fc diagnostics." end
        UI.Render()
    end)
    return check
end

function UI.Status(_, text) UI.message = text or "" end
function UI.Result(ok, err, success)
    UI.message = ok and (success or "Saved.") or (err or "Action unavailable.")
end
function UI.Height(height) if UI.child then UI.child:SetHeight(math.max(height, 430)) end end
