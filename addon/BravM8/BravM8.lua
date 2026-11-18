-- BravM8 : pendant un vol de maître de vol, des images et des clips
-- apparaissent quelques secondes à des moments aléatoires.

local ADDON_NAME = ...
local MEDIA_PATH = "Interface\\AddOns\\BravM8\\media\\"
local BOX = 360             -- côté max de la fenêtre (avant mise à l'échelle)
local TAXI_POLL = 0.5       -- vérification de l'atterrissage, en secondes
local FADE = 0.3            -- fondu d'apparition et de disparition, en secondes
local FIRST_DELAY = { 3, 6 }   -- délai avant la première apparition d'un vol
local DB_VERSION = 3           -- à augmenter quand les réglages par défaut changent
local VICTORY_SOUND = 888   -- son de montée de niveau de WoW
local EASTER_CHANCE = 1 / 6 -- chance qu'un vol contienne le son rare (1 vol sur 6)
local EASTER_SLOT = 2       -- le son rare remplace la 2e image du vol

local DEFAULTS = {
    enabled = true,
    muted   = false,
    locked  = false,
    display = 5,    -- secondes d'affichage d'une image
    gapMin  = 5,    -- pause aléatoire entre deux apparitions (secondes)
    gapMax  = 12,   -- => environ 5 images sur un vol d'1 min, 9 à 10 sur 2 min
    scale   = 1,
    point   = nil,  -- { point, relativePoint, x, y } ; nil = centre de l'écran
    onDeath = true, -- une image quand le personnage meurt
    onHearth = true, -- une image pendant l'incantation de la pierre de foyer
    onBag   = true, -- diaporama pendant la sieste dans le sac de couchage
}
local HEARTHSTONE = 8690

-- Sac de couchage douillet (Cozy Sleeping Bag) : +1 % d'XP par minute, 3 cumuls max
local SLEEPING_BAG_ITEM = 211527
local WELL_RESTED = 429959   -- buff « Well-Rested » gagné chaque minute dans le sac
local WELL_RESTED_MAX = 3
local BAG_ARM = 300          -- après avoir posé le sac, on a 5 min pour se coucher dessus
local BAG_MAX = 190          -- le diaporama s'arrête au plus tard après 3 min 10

local db
local list = BravM8_List or {}
local eggs = BravM8_Easter or {}
local easterThisFlight, slot = false, 0
local inBag, bagEndAt, bagUsedAt, restedStacks = false, 0, -1000, 0

local inFlight, testMode, hiddenThisFlight = false, false, false
local eventMode = nil   -- "death" ou "hearth" quand l'image vient d'un événement hors vol
local showing, firstOfFlight, moving = false, true, false
local current, nextAt, hideAt, mediaStart = nil, 0, 0, 0
local soundHandle
local bag = {}
local pollTimer, controlsShown = 0, false

local function Print(msg)
    print("|cff66ccffBravM8|r : " .. msg)
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

local frame = CreateFrame("Frame", "BravM8Frame", UIParent)
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

-- deux textures : pendant qu'une planche de clip est affichée, la suivante
-- se charge dans l'autre (invisible), pour enchaîner sans saccade
local texA = frame:CreateTexture(nil, "ARTWORK")
texA:SetAllPoints()
local texB = frame:CreateTexture(nil, "ARTWORK")
texB:SetAllPoints()
texB:SetAlpha(0)
local tex, spare = texA, texB
local page, sparePage = 1, nil

local function LoadPage(t, m, p)
    t:SetTexture(MEDIA_PATH .. m.pages[p].file)
end

-- affiche l'image n° f (à partir de 0) d'un clip
local function SetClipFrame(m, f)
    local p = math.floor(f / m.perPage) + 1
    if p ~= page then
        if sparePage ~= p then LoadPage(spare, m, p) end
        tex, spare = spare, tex
        tex:SetAlpha(1)
        spare:SetAlpha(0)
        page = p
        -- précharge la planche suivante (ou la première, si le clip boucle)
        local nextP = p % #m.pages + 1
        if nextP ~= p then
            LoadPage(spare, m, nextP)
            sparePage = nextP
        else
            sparePage = nil
        end
    end
    local pg = m.pages[p]
    local i = f - (p - 1) * m.perPage
    local col = i % pg.cols
    local row = math.floor(i / pg.cols)
    local l, t = col * m.w / pg.tw, row * m.h / pg.th
    tex:SetTexCoord(l, l + m.w / pg.tw, t, t + m.h / pg.th)
end

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
    -- (pour un clip, c'est la première image de la première planche)
    tex, spare = texA, texB
    tex:SetAlpha(1)
    spare:SetAlpha(0)
    page, sparePage = 1, nil
    tex:SetTexture(MEDIA_PATH .. m.file)
    tex:SetTexCoord(0, m.w / m.tw, 0, m.h / m.th)
    if m.pages and #m.pages > 1 then
        LoadPage(spare, m, 2)
        sparePage = 2
    end

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
    texA:SetTexture(nil)   -- libère les textures
    texB:SetTexture(nil)
    frame:Hide()
    controls:Hide()
    controlsShown = false
    testMode, eventMode = false, nil
    -- même rythme en vol et dans le sac de couchage
    if inFlight or inBag then
        nextAt = GetTime() + RandomGap()
    end
end

local function EndBag(hideNow)
    if not inBag then return end
    inBag = false
    if hideNow and showing and not testMode and not eventMode then HidePopup() end
end

local function StartFlight()
    if inFlight or #list == 0 then return end
    EndBag(true)
    inFlight, firstOfFlight = true, true
    nextAt = GetTime() + math.random(FIRST_DELAY[1], FIRST_DELAY[2])
    slot = 0
    easterThisFlight = #eggs > 0 and math.random() < EASTER_CHANCE
end

-- Son rare : joué à la place d'une image, sans rien afficher.
local function PlayEaster()
    local egg = eggs[math.random(#eggs)]
    if not db.muted then
        PlaySoundFile(MEDIA_PATH .. egg.sound, "Master")
    end
    -- la pause suivante commence une fois le son terminé
    nextAt = GetTime() + (egg.duration or 5) + RandomGap()
end

local function EndFlight()
    inFlight = false
    easterThisFlight = false
    if showing and not testMode and not eventMode then HidePopup() end
end

-- Diaporama dans le sac de couchage : les images s'enchaînent sans longue pause
local function StartBag()
    if not db.enabled or not db.onBag or inFlight or inBag or #list == 0 then return end
    inBag, firstOfFlight = true, true
    bagEndAt = GetTime() + BAG_MAX
    nextAt = GetTime() + 1
    if showing and not testMode and not eventMode then nextAt = 0 end
end

local function WellRestedStacks()
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return 0 end
    local aura = C_UnitAuras.GetPlayerAuraBySpellID(WELL_RESTED)
    return aura and math.max(1, aura.applications or 1) or 0
end

local function IsSleepingBag(spellID)
    if not spellID then return false end
    local getItemSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    if not getItemSpell then return false end
    local _, itemSpell = getItemSpell(SLEEPING_BAG_ITEM)
    return itemSpell ~= nil and itemSpell == spellID
end

-- Une seule image, hors vol (mort, pierre de foyer)
local function ShowEventPopup(kind)
    if not db.enabled or inFlight or inBag or showing or #list == 0 then return end
    eventMode, firstOfFlight = kind, true
    ShowPopup()
    if kind == "hearth" then
        -- reste affichée jusqu'à la fin de l'incantation (environ 10 s)
        local endMS = select(5, UnitCastingInfo("player"))
        if endMS then hideAt = math.max(hideAt, endMS / 1000) end
    end
end

local HEARTHSTONE_ITEM = 6948

local function IsHearthstone(spellID)
    if not spellID then return false end
    if spellID == HEARTHSTONE then return true end
    -- sort réellement lancé par l'objet « Pierre de foyer » dans cette version du jeu
    local getItemSpell = (C_Item and C_Item.GetItemSpell) or GetItemSpell
    if getItemSpell then
        local _, itemSpell = getItemSpell(HEARTHSTONE_ITEM)
        if itemSpell == spellID then return true end
    end
    -- variantes qui portent le même nom (selon la version du jeu)
    if C_Spell and C_Spell.GetSpellName and spellID then
        local name = C_Spell.GetSpellName(spellID)
        return name ~= nil and name == C_Spell.GetSpellName(HEARTHSTONE)
    end
    return false
end

-- Boutons (visibles seulement au survol) : couper le son, masquer pour ce vol
local closeButton = CreateFrame("Button", nil, controls, "UIPanelButtonTemplate")
closeButton:SetSize(24, 20)
closeButton:SetText("X")
closeButton:SetPoint("BOTTOMRIGHT", controls, "BOTTOMRIGHT", 0, 0)
closeButton:SetScript("OnClick", function()
    if testMode or eventMode then
        HidePopup()
        return
    end
    if inBag then
        EndBag(true)
        Print("diaporama arrêté.")
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
    if not (inFlight or inBag or showing) then return end
    local now = GetTime()

    -- fin de la sieste : 3 min écoulées (on laisse finir l'image en cours)
    if inBag and now >= bagEndAt then
        EndBag(false)
        if not showing then return end
    end

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
        if inBag and now >= nextAt then
            ShowPopup()
        elseif inFlight and now >= nextAt then
            slot = slot + 1
            if easterThisFlight and slot == EASTER_SLOT then
                PlayEaster()
            else
                ShowPopup()
            end
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

    -- animation des clips : on parcourt les planches d'images
    if m.type == "video" then
        SetClipFrame(m, math.floor((now - mediaStart) * m.fps) % m.frames)
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
        BravM8DB = BravM8DB or {}
        db = BravM8DB
        -- nouveaux réglages de rythme : on remplace les anciens enregistrés
        if db.version ~= DB_VERSION then
            db.display, db.gapMin, db.gapMax = DEFAULTS.display, DEFAULTS.gapMin, DEFAULTS.gapMax
            db.version = DB_VERSION
        end
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
-- Mort et pierre de foyer
---------------------------------------------------------------------------

local extra = CreateFrame("Frame")
extra:RegisterEvent("PLAYER_DEAD")
extra:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
extra:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
extra:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
extra:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
extra:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
extra:RegisterUnitEvent("UNIT_AURA", "player")
extra:RegisterEvent("PLAYER_UPDATE_RESTING")
extra:RegisterEvent("PLAYER_REGEN_DISABLED")
extra:RegisterEvent("PLAYER_ENTERING_WORLD")
extra:SetScript("OnEvent", function(self, event, unit, castGUID, spellID)
    if not db then return end
    if event == "PLAYER_ENTERING_WORLD" then
        -- cumuls déjà présents à la connexion : ce n'est pas une nouvelle sieste
        restedStacks = WellRestedStacks()
        return
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- sac posé : la zone de repos qui suit vient de lui
        if IsSleepingBag(spellID) then bagUsedAt = GetTime() end
        return
    elseif event == "PLAYER_UPDATE_RESTING" then
        if IsResting() then
            if GetTime() - bagUsedAt < BAG_ARM and WellRestedStacks() < WELL_RESTED_MAX then
                StartBag()
            end
        else
            EndBag(true)   -- sorti de la zone du sac
        end
        return
    elseif event == "UNIT_AURA" then
        local stacks = WellRestedStacks()
        if stacks ~= restedStacks then
            local gained = stacks > restedStacks
            restedStacks = stacks
            if stacks >= WELL_RESTED_MAX then
                EndBag(false)  -- bonus au maximum : l'image en cours finit, puis stop
            elseif gained and IsResting() then
                StartBag()     -- sac d'un membre du groupe : démarre au 1er cumul
            end
        end
        return
    elseif event == "PLAYER_REGEN_DISABLED" then
        EndBag(true)       -- combat : la sieste est finie
        return
    end
    if event == "PLAYER_DEAD" then
        if db.onDeath then ShowEventPopup("death") end
    elseif event == "UNIT_SPELLCAST_START" then
        if db.onHearth and IsHearthstone(spellID) then ShowEventPopup("hearth") end
    elseif eventMode == "hearth" and IsHearthstone(spellID) then
        -- incantation finie, annulée ou ratée : l'image part avec
        HidePopup()
    end
end)

---------------------------------------------------------------------------
-- Commandes
---------------------------------------------------------------------------

local function Help()
    Print(("%d média(s), %s, son %s. Affichage %d s, pause de %d à %d s."):format(
        #list, db.enabled and "activé" or "désactivé", db.muted and "coupé" or "actif",
        db.display, db.gapMin, db.gapMax))
    print("  /bravm8 on | off — activer ou désactiver")
    print("  /bravm8 test — faire apparaître une image tout de suite")
    print("  /bravm8 son — couper ou remettre le son")
    print(("  /bravm8 mort — image à la mort (%s)"):format(db.onDeath and "oui" or "non"))
    print(("  /bravm8 foyer — image pendant la pierre de foyer (%s)"):format(db.onHearth and "oui" or "non"))
    print(("  /bravm8 sac — diaporama dans le sac de couchage (%s)"):format(db.onBag and "oui" or "non"))
    print("  /bravm8 duree 5 — secondes d'affichage (2 à 30)")
    print("  /bravm8 pause 5 12 — pause aléatoire entre deux apparitions")
    print("  /bravm8 taille 1 — taille (0.4 à 2.5), ou Ctrl + molette")
    print("  /bravm8 verrou — bloquer ou débloquer le déplacement")
    print("  /bravm8 reset — remettre la fenêtre au centre")
end

SLASH_BRAVM81 = "/bravm8"
SlashCmdList.BRAVM8 = function(input)
    local cmd, arg = (input or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if cmd == "on" then
        db.enabled = true
        Print("activé.")
        CheckTaxi()
    elseif cmd == "off" then
        db.enabled = false
        EndFlight()
        EndBag(true)
        Print("désactivé.")
    elseif cmd == "test" then
        if #list == 0 then
            Print("aucun média dans l'add-on. Lance la mise à jour (raccourci « Mettre à jour BravM8 »).")
        elseif showing then
            HidePopup()
        else
            testMode, firstOfFlight = true, true
            ShowPopup()
        end
    elseif cmd == "oeuf" then
        -- commande cachée (absente de l'aide) pour tester le son rare
        if #eggs > 0 then PlayEaster() else Print("aucun son rare dans l'add-on.") end
    elseif cmd == "mort" then
        db.onDeath = not db.onDeath
        Print(db.onDeath and "image à la mort activée." or "image à la mort désactivée.")
    elseif cmd == "foyer" then
        db.onHearth = not db.onHearth
        Print(db.onHearth and "image pendant la pierre de foyer activée."
            or "image pendant la pierre de foyer désactivée.")
    elseif cmd == "sac" then
        db.onBag = not db.onBag
        if not db.onBag then EndBag(true) end
        Print(db.onBag and "diaporama dans le sac de couchage activé."
            or "diaporama dans le sac de couchage désactivé.")
    elseif cmd == "diapo" then
        -- commande cachée : lancer le diaporama du sac sans sac
        if inBag then EndBag(true) else StartBag() end
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
            Print("exemple : /bravm8 duree 6")
        end
    elseif cmd == "pause" then
        local a, b = arg:match("^(%d+)%s+(%d+)$")
        a, b = tonumber(a), tonumber(b)
        if a and b then
            db.gapMin = math.min(300, math.max(5, math.min(a, b)))
            db.gapMax = math.min(300, math.max(db.gapMin, math.max(a, b)))
            Print(("pause de %d à %d s entre deux apparitions."):format(db.gapMin, db.gapMax))
        else
            Print("exemple : /bravm8 pause 20 45")
        end
    elseif cmd == "taille" then
        local n = tonumber(arg)
        if n then
            db.scale = math.min(2.5, math.max(0.4, n))
            frame:SetScale(db.scale)
            Print(("taille %.1f."):format(db.scale))
        else
            Print("exemple : /bravm8 taille 1.2")
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
