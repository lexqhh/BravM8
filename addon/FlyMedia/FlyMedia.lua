-- FlyMedia : pendant un vol de maître de vol, des images et des clips
-- apparaissent quelques secondes à des moments aléatoires.

local ADDON_NAME = ...
local MEDIA_PATH = "Interface\\AddOns\\FlyMedia\\media\\"
local BOX = 360             -- côté max de la fenêtre (avant mise à l'échelle)
local TAXI_POLL = 0.5       -- vérification de l'atterrissage, en secondes
local FADE = 0.3            -- fondu d'apparition et de disparition, en secondes
local FIRST_DELAY = { 5, 12 }  -- délai avant la première apparition d'un vol
local VICTORY_SOUND = 888   -- son de montée de niveau de WoW
local EASTER_CHANCE = 0.08  -- chance qu'un vol contienne un son rare (environ 1 vol sur 12)
local EASTER_WINDOW = { 20, 50 }  -- moment du son rare, en secondes après le décollage

local DEFAULTS = {
    enabled = true,
    muted   = false,
    locked  = false,
    display = 6,    -- secondes d'affichage d'une image
    gapMin  = 20,   -- pause aléatoire entre deux apparitions (secondes)
    gapMax  = 45,
    scale   = 1,
    point   = nil,  -- { point, relativePoint, x, y } ; nil = centre de l'écran
}

local db
local list = FlyMedia_List or {}
local eggs = FlyMedia_Easter or {}
local easterAt = nil

local inFlight, testMode, hiddenThisFlight = false, false, false
local showing, firstOfFlight, moving = false, true, false
local current, nextAt, hideAt, mediaStart = nil, 0, 0, 0
local soundHandle
local bag = {}
local pollTimer, controlsShown = 0, false

local function Print(msg)
    print("|cff66ccffFlyMedia|r : " .. msg)
end

-- Ordre aléatoire sans répétition tant que tout n'a pas été vu.
local function NextMedia()
    if #bag == 0 then
        for i = 1, #list do bag[i] = i end
        for i = #bag, 2, -1 do
            local j = math.random(i)
            bag[i], bag[j] = bag[j], bag[i]
        end
        if current and #bag > 1 and list[bag[#bag]] == current then
            bag[1], bag[#bag] = bag[#bag], bag[1]
        end
    end
    return list[table.remove(bag)]
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

local function SavePosition()
    local p, _, rp, x, y = frame:GetPoint()
    db.point = { p, rp, x, y }
end

local function ApplyPosition()
    frame:ClearAllPoints()
    if db.point then
        frame:SetPoint(db.point[1], UIParent, db.point[2], db.point[3], db.point[4])
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    frame:SetScale(db.scale)
end

local function StopMediaSound()
    if soundHandle then
        StopSound(soundHandle, 300)
        soundHandle = nil
    end
end

local muteButton
local function RefreshMuteLabel()
    if muteButton then muteButton:SetText(db.muted and "Son" or "Muet") end
end

local function RandomGap()
    local lo, hi = db.gapMin, math.max(db.gapMin, db.gapMax)
    return math.random(lo, hi)
end

local function ShowPopup()
    if #list == 0 then return end
    local m = NextMedia()
    current = m
    mediaStart = GetTime()
    hideAt = mediaStart + math.max(db.display, m.duration or 0)

    -- adapte la fenêtre aux proportions du média
    if m.w >= m.h then
        frame:SetSize(BOX, BOX * m.h / m.w)
    else
        frame:SetSize(BOX * m.w / m.h, BOX)
    end

    -- la texture est complétée jusqu'à une puissance de 2 : on n'affiche que la zone utile
    -- (pour un clip, c'est la première image de la planche)
    tex:SetTexture(MEDIA_PATH .. m.file)
    tex:SetTexCoord(0, m.w / m.tw, 0, m.h / m.th)

    if not db.muted then
        if firstOfFlight then
            pcall(PlaySound, VICTORY_SOUND, "Master")
        end
        StopMediaSound()
        if m.sound then
            local ok, handle = PlaySoundFile(MEDIA_PATH .. m.sound, "Master")
            if ok then soundHandle = handle end
        end
    end
    firstOfFlight = false

    ApplyPosition()
    frame:SetAlpha(0)
    frame:Show()
    showing = true
end

local function HidePopup()
    showing = false
    StopMediaSound()
    tex:SetTexture(nil)   -- libère la texture
    frame:Hide()
    controls:Hide()
    controlsShown = false
    if testMode then
        testMode = false
    end
    if inFlight then
        nextAt = GetTime() + RandomGap()
    end
end

local function StartFlight()
    if inFlight or #list == 0 then return end
    inFlight, firstOfFlight = true, true
    nextAt = GetTime() + math.random(FIRST_DELAY[1], FIRST_DELAY[2])
    easterAt = nil
    if #eggs > 0 and math.random() < EASTER_CHANCE then
        easterAt = GetTime() + math.random(EASTER_WINDOW[1], EASTER_WINDOW[2])
    end
end

-- Son rare : joué seul, entre deux images, sans rien afficher.
local function PlayEaster()
    easterAt = nil
    local egg = eggs[math.random(#eggs)]
    if not db.muted then
        PlaySoundFile(MEDIA_PATH .. egg.sound, "Master")
    end
    -- aucune image ne vient couvrir le son
    nextAt = math.max(nextAt, GetTime() + (egg.duration or 5) + 3)
end

local function EndFlight()
    inFlight = false
    easterAt = nil
    if showing and not testMode then HidePopup() end
end

-- Boutons (visibles seulement au survol) : couper le son, masquer pour ce vol
local closeButton = CreateFrame("Button", nil, controls, "UIPanelButtonTemplate")
closeButton:SetSize(24, 20)
closeButton:SetText("X")
closeButton:SetPoint("BOTTOMRIGHT", controls, "BOTTOMRIGHT", 0, 0)
closeButton:SetScript("OnClick", function()
    if testMode then
        HidePopup()
        return
    end
    hiddenThisFlight = true
    EndFlight()
    HidePopup()
    Print("plus rien jusqu'à l'atterrissage.")
end)

muteButton = CreateFrame("Button", nil, controls, "UIPanelButtonTemplate")
muteButton:SetSize(44, 20)
muteButton:SetPoint("RIGHT", closeButton, "LEFT", -2, 0)
muteButton:SetScript("OnClick", function()
    db.muted = not db.muted
    if db.muted then StopMediaSound() end
    RefreshMuteLabel()
end)

frame:SetScript("OnDragStart", function(self)
    if not db.locked then
        moving = true
        self:StartMoving()
    end
end)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    moving = false
    SavePosition()
end)

-- Ctrl + molette : taille de la fenêtre
frame:SetScript("OnMouseWheel", function(self, delta)
    if not IsControlKeyDown() then return end
    db.scale = math.min(2.5, math.max(0.4, db.scale + delta * 0.1))
    frame:SetScale(db.scale)
end)

---------------------------------------------------------------------------
-- Boucle principale (tourne aussi quand la fenêtre est cachée)
---------------------------------------------------------------------------

local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function(self, elapsed)
    if not (inFlight or showing) then return end
    local now = GetTime()

    -- atterrissage
    if inFlight then
        pollTimer = pollTimer + elapsed
        if pollTimer >= TAXI_POLL then
            pollTimer = 0
            if not UnitOnTaxi("player") then
                EndFlight()
                if not showing then return end
            end
        end
    end

    if not showing then
        if inFlight and easterAt and now >= easterAt then
            PlayEaster()
        elseif inFlight and now >= nextAt then
            ShowPopup()
        end
        return
    end

    local m = current

    -- fondu d'entrée et de sortie
    local a = math.min(1, (now - mediaStart) / FADE, math.max(0, hideAt - now) / FADE)
    frame:SetAlpha(moving and 1 or math.max(0, a))

    -- boutons au survol
    local over = frame:IsMouseOver()
    if over ~= controlsShown then
        controlsShown = over
        controls:SetShown(over)
    end

    -- animation des clips : on parcourt la planche d'images
    if m.type == "video" then
        local f = math.floor((now - mediaStart) * m.fps) % m.frames
        local col = f % m.cols
        local row = math.floor(f / m.cols)
        local l = col * m.w / m.tw
        local t = row * m.h / m.th
        tex:SetTexCoord(l, l + m.w / m.tw, t, t + m.h / m.th)
    end

    if now >= hideAt and not moving then
        HidePopup()
    end
end)

---------------------------------------------------------------------------
-- Détection des vols
---------------------------------------------------------------------------

local function CheckTaxi()
    if UnitOnTaxi("player") then
        if db.enabled and not hiddenThisFlight then StartFlight() end
    else
        hiddenThisFlight = false
        if inFlight then EndFlight() end
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
    Print(("%d média(s), %s, son %s. Affichage %d s, pause de %d à %d s."):format(
        #list, db.enabled and "activé" or "désactivé", db.muted and "coupé" or "actif",
        db.display, db.gapMin, db.gapMax))
    print("  /flymedia on | off — activer ou désactiver")
    print("  /flymedia test — faire apparaître une image tout de suite")
    print("  /flymedia son — couper ou remettre le son")
    print("  /flymedia duree 6 — secondes d'affichage (2 à 30)")
    print("  /flymedia pause 20 45 — pause aléatoire entre deux apparitions")
    print("  /flymedia taille 1 — taille (0.4 à 2.5), ou Ctrl + molette")
    print("  /flymedia verrou — bloquer ou débloquer le déplacement")
    print("  /flymedia reset — remettre la fenêtre au centre")
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
        EndFlight()
        Print("désactivé.")
    elseif cmd == "test" then
        if #list == 0 then
            Print("aucun média dans l'add-on. Lance la mise à jour (raccourci « Mettre à jour FlyMedia »).")
        elseif showing then
            HidePopup()
        else
            testMode, firstOfFlight = true, true
            ShowPopup()
        end
    elseif cmd == "oeuf" then
        -- commande cachée (absente de l'aide) pour tester le son rare
        if #eggs > 0 then PlayEaster() else Print("aucun son rare dans l'add-on.") end
    elseif cmd == "son" or cmd == "mute" then
        db.muted = not db.muted
        if db.muted then StopMediaSound() end
        RefreshMuteLabel()
        Print(db.muted and "son coupé." or "son activé.")
    elseif cmd == "duree" or cmd == "durée" then
        local n = tonumber(arg)
        if n then
            db.display = math.min(30, math.max(2, math.floor(n)))
            Print(("%d s d'affichage."):format(db.display))
        else
            Print("exemple : /flymedia duree 6")
        end
    elseif cmd == "pause" then
        local a, b = arg:match("^(%d+)%s+(%d+)$")
        a, b = tonumber(a), tonumber(b)
        if a and b then
            db.gapMin = math.min(300, math.max(5, math.min(a, b)))
            db.gapMax = math.min(300, math.max(db.gapMin, math.max(a, b)))
            Print(("pause de %d à %d s entre deux apparitions."):format(db.gapMin, db.gapMax))
        else
            Print("exemple : /flymedia pause 20 45")
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
        Print("fenêtre remise au centre, taille par défaut.")
    else
        Help()
    end
end
