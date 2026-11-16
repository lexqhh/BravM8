-- FlyMedia : diaporama d'images et de clips pendant les vols de maître de vol.

local ADDON_NAME = ...
local MEDIA_PATH = "Interface\\AddOns\\FlyMedia\\media\\"
local BOX = 360            -- côté max de la fenêtre (avant mise à l'échelle)
local TAXI_POLL = 0.5      -- vérification de l'atterrissage, en secondes

local DEFAULTS = {
    enabled  = true,
    muted    = false,
    locked   = false,
    interval = 8,
    scale    = 1,
    point    = nil,  -- { point, relativePoint, x, y }
}

local db
local list = FlyMedia_List or {}

local active, testMode, hiddenThisFlight = false, false, false
local current, showUntil, mediaStart = nil, 0, 0
local soundHandle
local bag = {}
local pollTimer, controlsShown = 0, false

local function Print(msg)
    print("|cff66ccffFlyMedia|r : " .. msg)
end

-- Ordre aléatoire sans répétition tant que tout n'a pas été vu.
local function NextIndex()
    if #bag == 0 then
        for i = 1, #list do bag[i] = i end
        for i = #bag, 2, -1 do
            local j = math.random(i)
            bag[i], bag[j] = bag[j], bag[i]
        end
        -- évite de revoir tout de suite le dernier média affiché
        if current and #bag > 1 and list[bag[#bag]] == current then
            bag[1], bag[#bag] = bag[#bag], bag[1]
        end
    end
    return table.remove(bag)
end

---------------------------------------------------------------------------
-- Fenêtre
---------------------------------------------------------------------------

local frame = CreateFrame("Frame", "FlyMediaFrame", UIParent)
frame:SetSize(BOX, BOX * 9 / 16)
frame:SetFrameStrata("HIGH")
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:EnableMouseWheel(true)
frame:RegisterForDrag("LeftButton")
frame:Hide()

local bg = frame:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0, 0, 0, 0.55)

local tex = frame:CreateTexture(nil, "ARTWORK")
tex:SetAllPoints()

local controls = CreateFrame("Frame", nil, frame)
controls:SetPoint("BOTTOMRIGHT", -4, 4)
controls:SetSize(1, 1)
controls:Hide()

local function MakeButton(label, width, onClick, anchor)
    local b = CreateFrame("Button", nil, controls, "UIPanelButtonTemplate")
    b:SetSize(width, 20)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    if anchor then
        b:SetPoint("RIGHT", anchor, "LEFT", -2, 0)
    else
        b:SetPoint("BOTTOMRIGHT", controls, "BOTTOMRIGHT", 0, 0)
    end
    return b
end

local function SavePosition()
    local p, _, rp, x, y = frame:GetPoint()
    db.point = { p, rp, x, y }
end

local function ApplyPosition()
    frame:ClearAllPoints()
    if db.point then
        frame:SetPoint(db.point[1], UIParent, db.point[2], db.point[3], db.point[4])
    else
        frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -220, -160)
    end
    frame:SetScale(db.scale)
end

local function StopSound_()
    if soundHandle then
        StopSound(soundHandle, 300)
        soundHandle = nil
    end
end

local function PlayMediaSound(m)
    StopSound_()
    if m.sound and not db.muted then
        local ok, handle = PlaySoundFile(MEDIA_PATH .. m.sound, "Master")
        if ok then soundHandle = handle end
    end
end

local muteButton

local function RefreshMuteLabel()
    if muteButton then muteButton:SetText(db.muted and "Son" or "Muet") end
end

local function ShowMedia(m)
    current = m
    mediaStart = GetTime()
    showUntil = mediaStart + math.max(db.interval, m.duration or 0)

    -- adapte la fenêtre aux proportions du média
    local w, h = m.w, m.h
    if w >= h then
        frame:SetSize(BOX, BOX * h / w)
    else
        frame:SetSize(BOX * w / h, BOX)
    end

    -- la texture est complétée jusqu'à une puissance de 2 : on n'affiche que la zone utile
    -- (pour un clip, c'est la première image de la planche)
    tex:SetTexture(MEDIA_PATH .. m.file)
    tex:SetTexCoord(0, m.w / m.tw, 0, m.h / m.th)
    PlayMediaSound(m)
end

local function ShowNext()
    if #list == 0 then return end
    ShowMedia(list[NextIndex()])
end

local function Stop()
    active, testMode = false, false
    StopSound_()
    tex:SetTexture(nil)   -- libère la texture
    current = nil
    frame:Hide()
end

local function Start(isTest)
    if #list == 0 then
        if isTest then Print("aucun média dans l'add-on. Lance la mise à jour (FlyMedia.bat).") end
        return
    end
    active, testMode = true, isTest and true or false
    ApplyPosition()
    frame:Show()
    ShowNext()
end

-- Boutons (visibles seulement au survol)
local closeButton = MakeButton("X", 24, function()
    if testMode then
        Stop()
    else
        hiddenThisFlight = true
        Stop()
        Print("masqué pour ce vol. /flymedia pour les options.")
    end
end)
local nextButton = MakeButton(">>", 32, ShowNext, closeButton)
muteButton = MakeButton("Muet", 44, function()
    db.muted = not db.muted
    if db.muted then StopSound_() end
    RefreshMuteLabel()
end, nextButton)

frame:SetScript("OnDragStart", function(self)
    if not db.locked then self:StartMoving() end
end)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SavePosition()
end)

-- Ctrl + molette : taille de la fenêtre
frame:SetScript("OnMouseWheel", function(self, delta)
    if not IsControlKeyDown() then return end
    db.scale = math.min(2.5, math.max(0.4, db.scale + delta * 0.1))
    frame:SetScale(db.scale)
end)

frame:SetScript("OnUpdate", function(self, elapsed)
    if not active then return end
    local now = GetTime()

    -- atterrissage
    if not testMode then
        pollTimer = pollTimer + elapsed
        if pollTimer >= TAXI_POLL then
            pollTimer = 0
            if not UnitOnTaxi("player") then
                Stop()
                return
            end
        end
    end

    -- boutons au survol
    local over = self:IsMouseOver()
    if over ~= controlsShown then
        controlsShown = over
        controls:SetShown(over)
    end

    local m = current
    if not m then return end

    -- animation des clips : on parcourt la planche d'images
    if m.type == "video" then
        local f = math.floor((now - mediaStart) * m.fps) % m.frames
        local col = f % m.cols
        local row = math.floor(f / m.cols)
        local l = col * m.w / m.tw
        local t = row * m.h / m.th
        tex:SetTexCoord(l, l + m.w / m.tw, t, t + m.h / m.th)
    end

    if now >= showUntil then
        ShowNext()
    end
end)

---------------------------------------------------------------------------
-- Détection des vols
---------------------------------------------------------------------------

local function CheckTaxi()
    if UnitOnTaxi("player") then
        if not active and db.enabled and not hiddenThisFlight then
            Start(false)
        end
    else
        hiddenThisFlight = false
        if active and not testMode then Stop() end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_CONTROL_LOST")
events:RegisterEvent("PLAYER_CONTROL_GAINED")
events:RegisterEvent("TAXIMAP_CLOSED")
events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        FlyMediaDB = FlyMediaDB or {}
        db = FlyMediaDB
        for k, v in pairs(DEFAULTS) do
            if db[k] == nil then db[k] = v end
        end
        RefreshMuteLabel()
        self:UnregisterEvent("ADDON_LOADED")
        return
    end
    if not db then return end
    -- le statut « en vol » n'est pas toujours à jour au moment de l'événement
    C_Timer.After(0.3, CheckTaxi)
    C_Timer.After(1.5, CheckTaxi)
end)

---------------------------------------------------------------------------
-- Commandes
---------------------------------------------------------------------------

local function Help()
    Print(("%d média(s), %s, son %s, %d s par média."):format(
        #list, db.enabled and "activé" or "désactivé",
        db.muted and "coupé" or "actif", db.interval))
    print("  /flymedia on | off — activer ou désactiver")
    print("  /flymedia test — aperçu sans voler (X pour fermer)")
    print("  /flymedia son — couper ou remettre le son")
    print("  /flymedia duree 8 — secondes par média (3 à 60)")
    print("  /flymedia taille 1 — taille de la fenêtre (0.4 à 2.5), ou Ctrl + molette")
    print("  /flymedia verrou — bloquer ou débloquer le déplacement")
    print("  /flymedia reset — remettre la fenêtre à sa place")
end

SLASH_FLYMEDIA1 = "/flymedia"
SlashCmdList.FLYMEDIA = function(input)
    local cmd, arg = (input or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if cmd == "on" then
        db.enabled = true
        Print("activé.")
        CheckTaxi()
    elseif cmd == "off" then
        db.enabled = false
        if active and not testMode then Stop() end
        Print("désactivé.")
    elseif cmd == "test" then
        if active then Stop() else Start(true) end
    elseif cmd == "son" or cmd == "mute" then
        db.muted = not db.muted
        if db.muted then StopSound_() end
        RefreshMuteLabel()
        Print(db.muted and "son coupé." or "son activé.")
    elseif cmd == "duree" or cmd == "durée" then
        local n = tonumber(arg)
        if n then
            db.interval = math.min(60, math.max(3, math.floor(n)))
            Print(("%d s par média."):format(db.interval))
        else
            Print("exemple : /flymedia duree 10")
        end
    elseif cmd == "taille" then
        local n = tonumber(arg)
        if n then
            db.scale = math.min(2.5, math.max(0.4, n))
            frame:SetScale(db.scale)
            Print(("taille %.1f."):format(db.scale))
        else
            Print("exemple : /flymedia taille 1.2")
        end
    elseif cmd == "verrou" or cmd == "lock" then
        db.locked = not db.locked
        Print(db.locked and "fenêtre verrouillée." or "fenêtre déplaçable.")
    elseif cmd == "reset" then
        db.point, db.scale = nil, 1
        ApplyPosition()
        Print("position et taille remises par défaut.")
    else
        Help()
    end
end
