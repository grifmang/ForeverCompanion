local _, FC = ...
local Updates={url="https://github.com/grifmang/ForeverCompanion/releases"}
FC.Updates=Updates
local lastContext,lastChannel,lastSend,nextSend,notified,reported=nil,nil,-120,0,false,nil

-- Deliberately small version grammar: stable or this project's prototype
-- channel, with an optional monotonically increasing CI build number.
local function component(value,maximum)
    if type(value)~="string" or #value>7 or not value:match("^%d+$") then return nil end
    local number=tonumber(value)
    if not FC.Number(number,0,maximum) or tostring(number)~=value then return nil end
    return number
end

function Updates.Parse(value)
    if not FC.Readable(value) or type(value)~="string" or #value>48 then return nil end
    local major,minor,patch,suffix=value:match("^(%d+)%.(%d+)%.(%d+)(.*)$")
    major,minor,patch=component(major,9999),component(minor,9999),component(patch,9999)
    if not major or not minor or not patch then return nil end
    local stable,build=false,0
    if suffix=="" then stable=true
    elseif suffix~="-prototype" then
        local number=suffix:match("^%-prototype%.(%d+)$")
        build=component(number,9999999)
        if not build or build==0 then return nil end
    end
    return {major,minor,patch,stable and 1 or 0,build}
end

function Updates.Newer(a,b)
    local first,second=Updates.Parse(a),Updates.Parse(b)
    if not first or not second then return false end
    for i=1,5 do
        if first[i]~=second[i] then return first[i]>second[i] end
    end
    return false
end

function Updates.Message()
    if Updates.Parse(FC.version) then return "3|V|0|" .. FC.version end
end

function Updates.ValidMessage(message)
    return FC.Readable(message) and type(message)=="string" and #message<=56
        and message==Updates.Message()
end

function Updates.Receive(version,member,party)
    if not FC.IsEnabled("party") or not FC.Adventure.sharing or FC.IsCombat()
        or not party or not party.channel or not party.membersByName[member]
        or member==party.selfName or not Updates.Parse(version) then return end
    if not Updates.Newer(version,FC.version) then return end
    if not reported or Updates.Newer(version,reported) then reported=version end
    if not notified then
        notified=true -- Per login, not per session: leader/session churn cannot spam.
        FC.Print("A group member reports a newer addon version (" .. version .. "). Check releases: " .. Updates.url)
    end
    FC.Refresh("settings")
end

function Updates.Pump(party)
    if not FC.IsEnabled("party") or not FC.Adventure.sharing or not party or not party.channel
        or FC.IsCombat() or not FC.PartyProtocol.enabled then return false end
    local now=GetTime()
    if not FC.API.SameGroup(lastContext,party) or lastChannel~=party.channel then
        lastContext,lastChannel=FC.API.GroupContext(party),party.channel
        local stagger=0
        for i=1,#party.selfName do stagger=(stagger+party.selfName:byte(i))%15 end
        nextSend=math.max(now+stagger, lastSend+30)
    end
    if now<nextSend then return false end
    local message=Updates.Message()
    if message and FC.PartyProtocol.SendVersion(message,party) then
        lastSend,nextSend=now,now+120
        return true
    end
    nextSend=now+5
    return false
end

function Updates.Status()
    if reported then return "A group member reported version " .. reported .. ". Check GitHub to confirm an available release." end
    return "GitHub is not checked inside WoW. Newer group versions can trigger one notice per login while sharing is enabled."
end

function Updates.PrintStatus()
    FC.Print("Installed version: " .. FC.version)
    FC.Print(Updates.Status())
    FC.Print("Release downloads: " .. Updates.url)
end
