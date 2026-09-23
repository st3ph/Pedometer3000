-- Init DB
Pedometer3000DB = Pedometer3000DB or {
    totalDistance = 0,
    point = "CENTER",
    relativePoint = "CENTER",
    xOfs = 0,
    yOfs = 0
}

local lastPosition = nil
local lastMapID = nil
local timer = 0
local CHECK_INTERVAL = 0.25 -- Vérification plus fréquente (4x par seconde) pour la précision des virages

-- Constante de conversion : 1 yard de WoW = 0.9144 mètre
local YARDS_TO_METERS = 0.9144

-- Tampon pour accumuler les fractions de mètres réels
local distanceBuffer = 0.0

-- Seuil minimal en yards (~5 cm) sous lequel on ignore la variation
local MIN_MOVEMENT_THRESHOLD = 0.05

---------------------------------------------------------
-- UI
---------------------------------------------------------
local displayFrame = CreateFrame("Frame", "DistanceTrackerFrame", UIParent, "BackdropTemplate")
displayFrame:SetSize(180, 40)
displayFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

displayFrame:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
})
displayFrame:SetBackdropColor(0, 0, 0, 0.5)
displayFrame:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

displayFrame:SetMovable(true)
displayFrame:EnableMouse(true)
displayFrame:RegisterForDrag("LeftButton")

displayFrame:SetScript("OnDragStart", function(self)
    self:StartMoving()
end)

displayFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relativePoint, xOfs, yOfs = self:GetPoint()
    Pedometer3000DB.point = point
    Pedometer3000DB.relativePoint = relativePoint
    Pedometer3000DB.xOfs = xOfs
    Pedometer3000DB.yOfs = yOfs
end)

local distanceText = displayFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
distanceText:SetPoint("CENTER", displayFrame, "CENTER", 0, 0)

---------------------------------------------------------

local function UpdateTextDisplay()
    local meters = math.floor(Pedometer3000DB.totalDistance or 0)
    if meters >= 1000 then
        distanceText:SetText(string.format("Podomètre: %.2f km", meters / 1000))
    else
        distanceText:SetText(string.format("Podomètre: %d m", meters))
    end
end

local eventHandler = CreateFrame("Frame")
eventHandler:RegisterEvent("ADDON_LOADED")
eventHandler:SetScript("OnEvent", function(self, event, addonName)
    if addonName == "Pedometer3000" then
        if Pedometer3000DB.point then
            displayFrame:ClearAllPoints()
            displayFrame:SetPoint(
                Pedometer3000DB.point,
                UIParent,
                Pedometer3000DB.relativePoint,
                Pedometer3000DB.xOfs,
                Pedometer3000DB.yOfs
            )
        end
        UpdateTextDisplay()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

---------------------------------------------------------

local function GetCurrentPosition()
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return nil, nil end

    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return nil, nil end

    return mapID, pos
end

local function CalculateDistanceInYards(mapID, pos1, pos2)
    local _, worldPos1 = C_Map.GetWorldPosFromMapPos(mapID, pos1)
    local _, worldPos2 = C_Map.GetWorldPosFromMapPos(mapID, pos2)

    if not worldPos1 or not worldPos2 then return 0 end

    local dx = worldPos2.x - worldPos1.x
    local dy = worldPos2.y - worldPos1.y

    -- Distance euclidienne en yards
    return math.sqrt(dx * dx + dy * dy)
end

displayFrame:SetScript("OnUpdate", function(self, elapsed)
    timer = timer + elapsed
    if timer < 0.15 then return end
    timer = 0

    -- Don't calculate distance if player is not moving, mounted, flying or using taxi
    if GetUnitSpeed("player") == 0 or IsMounted() or IsFlying() or UnitOnTaxi("player") then 
        lastPosition = nil
        lastMapID = nil
        return 
    end

    local currentMapID, currentPos = GetCurrentPosition()
    if not currentMapID or not currentPos then return end

    if lastMapID == currentMapID and lastPosition then
        local distYards = CalculateDistanceInYards(currentMapID, lastPosition, currentPos)

        -- Handle noise & TP
        if distYards >= 0.08 and distYards < 200 then
            local distMeters = distYards * YARDS_TO_METERS
            distanceBuffer = distanceBuffer + distMeters

            if distanceBuffer >= 1.0 then
                local metersToAdd = math.floor(distanceBuffer)
                Pedometer3000DB.totalDistance = Pedometer3000DB.totalDistance + metersToAdd
                
                distanceBuffer = distanceBuffer - metersToAdd
                UpdateTextDisplay()
            end
        end
    end

    lastMapID = currentMapID
    lastPosition = currentPos
end)

---------------------------------------------------------
-- Slash commands
---------------------------------------------------------
SLASH_DISTANCETRACKER1 = "/pedometer3000"
SlashCmdList["DISTANCETRACKER"] = function(msg)
    if msg == "reset" then
        Pedometer3000DB.totalDistance = 0
        distanceBuffer = 0.0
        UpdateTextDisplay()
        print("|cFF00FF00[Pedometer 3000]|r Compteur réinitialisé.")
    elseif msg == "lock" then
        local isMovable = displayFrame:IsMovable()
        displayFrame:SetMovable(not isMovable)
        displayFrame:EnableMouse(not isMovable)
        print("|cFF00FF00[Pedometer 3000]|r Fenêtre " .. (isMovable and "verrouillée" or "déverrouillée") .. ".")
    else
        print("|cFF00FF00[Pedometer 3000]|r Options:")
        print("  /pedometer3000 reset : Réinitialise la distance à zéro")
        print("  /pedometer3000 lock  : Verrouille/Déverrouille le déplacement de la fenêtre")
    end
end