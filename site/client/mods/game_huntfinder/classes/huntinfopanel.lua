if not HuntInfo then
    HuntInfo = {
        monsters = {},
        widget = nil,
        radioSelected = nil,
        lastMonsterWidget = nil,
        trackerKillsWidget = nil, -- show kills for the tracked hunt
        trackedHunt = nil, -- Store the currently tracked hunt
        showingCharms = false
    }
    HuntInfo.__index = HuntInfo
end

local self = HuntInfo
local itemCache = {}
local itemCacheBuilt = false

local monsterCache = {}
local monsterCacheBuilt = false

local function buildMonsterCache()
    if monsterCacheBuilt then return end
    
    -- Iterate a reasonable range of monster IDs
    -- Using getRaceData is safer and provides the name directly
    for id = 1, 5000 do
        local raceData = g_things.getRaceData(id)
        if raceData and raceData.name then
             local name = raceData.name
             if name and name ~= "" then
                 monsterCache[name:lower()] = id
             end
        end
    end
    monsterCacheBuilt = true
end

local function getMonsterIdByName(name)
    if not name then return 0 end
    
    -- Try direct lookup first
    local races = g_things.getRacesByName(name)
    if races and #races > 0 then
        return races[1].raceId
    end

    -- Build cache if needed
    buildMonsterCache()
    
    -- Try lowercase lookup from cache
    return monsterCache[name:lower()] or 0
end

local function buildItemCache()
    if itemCacheBuilt then return end

    -- Index market items first (have names from market data)
    local marketTypes = g_things.findThingTypeByAttr(ThingAttrMarket, ThingCategoryItem)
    if marketTypes then
        for _, itemType in pairs(marketTypes) do
            local name = itemType:getName()
            if name and name ~= "" then
                itemCache[name:lower()] = itemType:getId()
            end
        end
    end

    -- Also scan ALL item types to catch custom/non-market items that have names
    -- (e.g. custom equipment: Monk Robe, Jo Staff, Harmony Amulet, etc.)
    local allTypes = g_things.getThingTypes(ThingCategoryItem)
    if allTypes then
        for _, itemType in pairs(allTypes) do
            if itemType then
                local name = itemType:getName()
                if name and name ~= "" then
                    local id = itemType:getId()
                    if id and id > 0 and not itemCache[name:lower()] then
                        itemCache[name:lower()] = id
                    end
                end
            end
        end
    end

    itemCacheBuilt = true
end

local function getItemIdByName(name)
    if not name then return 0 end
    
    -- Try direct lookup first (if function exists)
    if g_things.getItemByName then
        local id = g_things.getItemByName(name)
        if id and id > 0 then return id end
    end

    -- Build cache if needed
    buildItemCache()
    
    -- Try lowercase lookup from cache
    return itemCache[name:lower()] or 0
end


local charmNameToId = {
    ["wound"] = {id = 0, name = "Wound", description = "Your attacks have a %d%% chance to deal physical damage equal to 5%% of the target's initial hit points.", bonus = 5},
    ["enflame"] = {id = 1, name = "Enflame", description = "Your attacks have a %d%% chance to deal fire damage equal to 5%% of the target's initial hit points.", bonus = 5},
    ["poison"] = {id = 2, name = "Poison", description = "Your attacks have a %d%% chance to deal earth damage equal to 5%% of the target's initial hit points.", bonus = 5},
    ["freeze"] = {id = 3, name = "Freeze", description = "Your attacks have a %d%% chance to deal ice damage equal to 5%% of the target's initial hit points.", bonus = 5},
    ["zap"] = {id = 4, name = "Zap", description = "Your attacks have a %d%% chance to deal energy damage equal to 5%% of the target's initial hit points.", bonus = 5},
    ["curse"] = {id = 5, name = "Curse", description = "Your attacks have a %d%% chance to deal death damage equal to 5%% of the target's initial hit points.", bonus = 5},
    ["parry"] = {id = 7, name = "Parry", description = "Each time you take damage, you have a %d%% chance to reflect it back to the aggressor.", bonus = 5},
    ["dodge"] = {id = 8, name = "Dodge", description = "Grants a %d%% chance to dodge an attack.", bonus = 5},
    ["low blow"] = {id = 15, name = "Low Blow", description = "Adds %d%% critical hit chance to attacks with critical hit weapons.", bonus = 4},
    ["divine wrath"] = {id = 16, name = "Divine Wrath", description = "Your attacks have a %d%% chance to deal holy damage equal to 5%% of the target's initial hit points.", bonus = 5},
    ["savage blow"] = {id = 19, name = "Savage Blow", description = "Adds %d%% critical extra damage to attacks with critical hit weapons.", bonus = 20},
    ["carnage"] = {id = 22, name = "Carnage", description = "Killing a monster has %d%% chance to deal physical damage equal to 15%% of its maximum health to all monsters in small radius.", bonus = 10},
    ["overpower"] = {id = 23, name = "Overpower", description = "Your attacks have a %d%% chance to deal damage equal to 5%% of your maximum health.", bonus = 5},
    ["overflux"] = {id = 24, name = "Overflux", description = "Your attacks have a %d%% chance to deal damage equal to 2.5%% of your maximum mana.", bonus = 5},
    ["cripple"] = {id = 6, name = "Cripple", description = "Your attacks have a %d%% chance to paralyse the target for 10 seconds.", bonus = 6},
    ["adrenaline burst"] = {id = 9, name = "Adrenaline Burst", description = "Each time you're hit you have a %d%% chance to trigger a burst of adrenaline, boosting your speed by 150%% for 10 seconds.", bonus = 6},
    ["numb"] = {id = 10, name = "Numb", description = "After being attacked, you have a %d%% chance to paralyse the aggressor for 10 seconds.", bonus = 6},
    ["cleanse"] = {id = 11, name = "Cleanse", description = "Each time you're hit, you have a %d%% chance to cleanse one random negative status effect and gain temporary immunity to it for 11 seconds.", bonus = 6},
    ["bless"] = {id = 12, name = "Bless", description = "Blesses you, reducing skill and experience loss by %d%% when killed by the chosen creature.", bonus = 6},
    ["scavenge"] = {id = 13, name = "Scavenge", description = "Increases your chance of successfully skinning/dusting a skinnable/dustable creature by %d%%.", bonus = 60},
    ["gut"] = {id = 14, name = "Gut", description = "Gutting the creature yields %d%% more creature products.", bonus = 6},
    ["vampiric embrace"] = {id = 17, name = "Vampiric Embrace", description = "Increases your current life leech by %.1f%%.", bonus = 1.6},
    ["void's call"] = {id = 18, name = "Void's Call", description = "Increases your current mana leech by %.1f%%.", bonus = 0.8},
    ["fatal hold"] = {id = 20, name = "Fatal Hold", description = "Your attacks have a %d%% chance to prevent creatures from fleeing due to low health for 30 seconds.", bonus = 30},
    ["void inversion"] = {id = 21, name = "Void Inversion", description = "%d%% chance to gain mana instead of losing it when taking mana drain damage.", bonus = 20},
}

local imbuementTypes = {
    ["strike"] = 3, -- Added missing type (Critical Chance)
    ["epiphany"] = 66,
    ["void"] = 51,
    ["vampirism"] = 48,
    ["dragon hide"] = 36,
    ["cloud fabric"] = 33,
    ["snake skin"] = 30,
    ["lich shroud"] = 27,
    ["reap"] = 24,
    ["quara scale"] = 42,
    ["demon presence"] = 39,
}

function onSelectionChange(widget, selectedWidget)
    if self.lastMonsterWidget then
        self.lastMonsterWidget:setBackgroundColor("#363636")
        self.lastMonsterWidget:setColor("#c0c0c0")
    end

    self.trackerKillsWidget.onCheckChange = function(seldWidget) end
    if selectedWidget then
        local serverInfo = self.monsters[selectedWidget.actionId]
        local races = g_things.getRacesByName(selectedWidget:getText())
        if not races or #races == 0 then
            races = g_things.getRacesByName(selectedWidget:getText():lower())
        end
        local monsterId = 0
        local raceData = nil

        if races and #races > 0 then
            monsterId = races[1].raceId
            raceData = g_things.getRaceData(monsterId)
        end

        local planeCreature = self.widget:recursiveGetChildById('creatureInfoOutfit')
        if raceData and raceData.outfit then
            planeCreature:setOutfit(raceData.outfit)
        else
            planeCreature:setOutfit({auxType = 13})
        end

        local monsterName = self.widget:recursiveGetChildById('creatureName')
        monsterName:setText(selectedWidget:getText())

        if serverInfo then
            local health = self.widget:recursiveGetChildById('health')
            local experience = self.widget:recursiveGetChildById('experience')
            local speed = self.widget:recursiveGetChildById('speed')
            local armor = self.widget:recursiveGetChildById('armor')
            local mitigation = self.widget:recursiveGetChildById('mitigation')

            health:setText(serverInfo[1])
            experience:setText(serverInfo[2])
            speed:setText(serverInfo[3])
            armor:setText(serverInfo[4])
            mitigation:setText(serverInfo[5])

            local elements = self.widget:recursiveGetChildById('elements')
            elements:destroyChildren()
            for elementId, percent in pairs(serverInfo[6]) do
                local widgetElement = g_ui.createWidget('ElementInfo', elements)
                widgetElement.progress:setBackgroundColor('white')
                widgetElement:setId(elementId)
                widgetElement:setActionId(elementId)
                local name = elementName[elementId]
                widgetElement.icon:setImageSource('/images/game/cyclopedia/icons/monster-icon-'.. name ..'-resist')
                widgetElement.icon:setTooltip(string.capitalize(name))

                widgetElement.progress:setValue(percent, 0, 150)
                widgetElement.progress:setTooltip(tr('Sensitive to %s: %d%% (neutral)', name, percent))
                if percent < 50 then
                    widgetElement.progress:setBackgroundColor('red')
                    widgetElement.progress:setTooltip(tr('Sensitive to %s: %d%% (strong)', name, percent))
                elseif percent < 100 then
                    widgetElement.progress:setBackgroundColor('#e4c00a')
                    widgetElement.progress:setTooltip(tr('Sensitive to %s: %d%% (strong)', name, percent))
                elseif percent > 100 then
                    widgetElement.progress:setBackgroundColor('#18ce18')
                    widgetElement.progress:setTooltip(tr('Sensitive to %s: %d%% (weak)', name, percent))
                end
            end
        else
            -- Clear dynamic info if no server data
            local health = self.widget:recursiveGetChildById('health')
            local experience = self.widget:recursiveGetChildById('experience')
            local speed = self.widget:recursiveGetChildById('speed')
            local armor = self.widget:recursiveGetChildById('armor')
            local mitigation = self.widget:recursiveGetChildById('mitigation')
            
            health:setText("?")
            experience:setText("?")
            speed:setText("?")
            armor:setText("?")
            mitigation:setText("?")
            self.widget:recursiveGetChildById('elements'):destroyChildren()
        end

        -- self.trackerKillsWidget
        if monsterId > 0 then
            self.trackerKillsWidget:setChecked(modules.game_cyclopedia.Bestiary.monsterInTracker(monsterId))
            self.trackerKillsWidget:setEnabled(true)
            self.trackerKillsWidget.onCheckChange = function(seldWidget)
                modules.game_cyclopedia.Bestiary.onTrackMonster(seldWidget:isChecked(), monsterId)
            end
        else
            self.trackerKillsWidget:setChecked(false)
            self.trackerKillsWidget:setEnabled(false)
        end

        if self.showingCharms then
            local monsterName = selectedWidget:getText()
            local hunt = self.currentHunt or self.trackedHunt
            local charmName = nil
            if hunt then
                local monsters = hunt:getMonsters()
                for _, monster in ipairs(monsters) do
                    if monster.Name == monsterName then
                        charmName = monster.Charm
                        break
                    end
                end
            end

            local charmData = charmName and charmNameToId[charmName:lower()] or nil
            if charmData then
                self.charmOpacity:setVisible(false)
                self.charmImage:setImageSource(string.format("/images/game/cyclopedia/monster-bonus-effects/monster-bonus-effects-%d", charmData.id))
                self.charmImage:setTooltip(string.todivide(charmData.name .. ": " .. string.format(charmData.description, charmData.bonus), 10))
            else
                self.charmOpacity:setVisible(true)
                self.charmImage:setImageSource('')
                self.charmImage:setTooltip('')
            end
        end

        selectedWidget:setBackgroundColor("#585858")
        selectedWidget:setColor("#ff9854")
    end

    self.lastMonsterWidget = selectedWidget
end

function HuntInfo.init()
    self.widget = HuntFinder.widget:recursiveGetChildById('huntInfoPanel')
    self.radioSelected = UIRadioGroup.create()
    self.statsPanel = self.widget:recursiveGetChildById('statsPanel')
    self.creatureCharmPanel = self.widget:recursiveGetChildById('creatureCharmPanel')
    self.creatureInfoButton = self.widget:recursiveGetChildById('creatureInfoButton')
    self.charmImage = self.widget:recursiveGetChildById('charmImage')
    self.charmOpacity = self.widget:recursiveGetChildById('charmOpacity')
    self.trackerKillsWidget = self.widget:recursiveGetChildById('trackerKills')
    self.floorUp = self.widget:recursiveGetChildById('floorUp')
    self.floorDown = self.widget:recursiveGetChildById('floorDown')
    
    self.floorUp.onClick = function()
        local minimap = self.widget:recursiveGetChildById('minimap')
        if minimap then
            minimap:floorUp(1)
        end
    end

    self.floorDown.onClick = function()
        local minimap = self.widget:recursiveGetChildById('minimap')
        if minimap then
            minimap:floorDown(1)
        end
    end
    
    connect(self.radioSelected, { onSelectionChange = onSelectionChange })

    self.showingCharms = false
    self:updateButtonState()
    self.creatureInfoButton.onClick = function()
        self.showingCharms = not self.showingCharms
        self:updatePanels()
        self:updateButtonState()
        if self.showingCharms and self.radioSelected:getSelectedWidget() then
            onSelectionChange(nil, self.radioSelected:getSelectedWidget())
        end
    end
end

function HuntInfo:clear()
    if self.widget then
        self.widget:destroyChildren()
        self.widget = nil
    end

    if self.radioSelected then
        disconnect(self.radioSelected, { onSelectionChange = onSelectionChange })
        self.radioSelected:destroy()
        self.radioSelected = nil
    end

    if self.lastMonsterWidget then
        self.lastMonsterWidget = nil
    end
    self.trackedHunt = nil
    self.showingCharms = false

    self.trackerKillsWidget = nil
end

function HuntInfo:updatePanels()
    self.statsPanel:setVisible(not self.showingCharms)
    self.creatureCharmPanel:setVisible(self.showingCharms)
end

function HuntInfo:updateButtonState()
    if self.showingCharms then
        self.creatureInfoButton:setImageSource("/images/game/wiki/hunt-finder/health-info-button")
        self.creatureInfoButton:setTooltip("Click to show monster stats and hide charm")
    else
        self.creatureInfoButton:setImageSource("/images/game/wiki/hunt-finder/charm-info-button")
        self.creatureInfoButton:setTooltip("Click to show charm and hide monster stats")
    end
end

function HuntInfo:displayHunt(hunt)
    self.currentHunt = hunt -- Store the current hunt
    MapFinder:setHuntPosition(hunt:getPosition())
    local huntName = self.widget:getChildById('huntName')
    local huntLevel = self.widget:recursiveGetChildById('huntLevel')
    local huntXpHour = self.widget:recursiveGetChildById('huntXpHour')
    local huntLootHour = self.widget:recursiveGetChildById('huntLootHour')
    local huntLocation = self.widget:recursiveGetChildById('huntLocation')
    local trackHuntOnMap = self.widget:recursiveGetChildById('trackHuntOnMap')

    huntName:setText(hunt:getName())
    huntLevel:setText(hunt:getLevel() .. " +")
    huntXpHour:setText(hunt:getXPHour())
    huntLootHour:setText(hunt:getLootHour())
    huntLocation:setText(hunt:getLocation())
    trackHuntOnMap:setChecked(self.trackedHunt == hunt)

    local creaturesInfo = self.widget:recursiveGetChildById('creaturesInfo')
    creaturesInfo:destroyChildren()

    if self.radioSelected then
        self.radioSelected:destroy()
    end
    self.radioSelected = UIRadioGroup.create()
    connect(self.radioSelected, { onSelectionChange = onSelectionChange })

    self.lastMonsterWidget = nil
    for _, monster in ipairs(hunt:getMonsters()) do
        local widget = g_ui.createWidget('UIWidget', creaturesInfo)
        widget:setPhantom(false)
        widget:setText(monster.Name)
        widget:setHeight(14)
        widget:setTextAlign(AlignLeft)
        widget:setTextOffset(topoint('2 0'))
        widget:setWidth(creaturesInfo:getWidth() - 15)
        widget:setId(monster.Name)
        widget:setTooltip(monster.Name)
        widget:setFont("Verdana Bold-11px")
        widget:setColor("#c0c0c0")

        local races = g_things.getRacesByName(monster.Name)
        if not races or #races == 0 then
            races = g_things.getRacesByName(monster.Name:lower())
        end

        if races and #races > 0 then
            widget.actionId = races[1].raceId
        else
            widget.actionId = 0
        end
        widget:setTextAlign(AlignLeft)
        self.radioSelected:addWidget(widget)
        
        widget.onClick = function(w)
            -- Force UI update directly
            onSelectionChange(nil, w)
            if self.radioSelected then
                 self.radioSelected:selectWidget(w, true)
            end
        end
    end

    self.radioSelected:selectWidget(self.radioSelected:getFirstWidget())

    local imbuiContentPanel = self.widget:recursiveGetChildById('imbuiContentPanel')
    local imbues = hunt:getRecommendedImbuesByVocation(HuntFinder.vocation)
    for i = 1, 3 do
        local widget = imbuiContentPanel:getChildById('slot' .. i - 1)
        local activeSlot = imbues[i]

        if not activeSlot then
            widget:setImageSource("/images/game/imbuing/slot")
            widget:setImageClip("0 0 66 66")
            widget:setTooltip('')
        else
            local imageId = imbuementTypes[activeSlot:lower()] or 3
            widget:setImageSource("/images/game/imbuing/icons/" .. imageId)
            widget:setImageClip("0 0 64 64")
            widget:setTooltip(activeSlot)
        end
    end

    local suppliesContentPanel = self.widget:recursiveGetChildById('suppliesContentPanel')
    local supplies = hunt:getRecommendedSuppliesByVocation(HuntFinder.vocation)
    for i, widget in ipairs(suppliesContentPanel:getChildren()) do
        local itemName = supplies[i]
        if not itemName then
            widget:setItemId(0)
            widget:setTooltip('')
        else
            local itemId = getItemIdByName(itemName)
            if itemId > 0 then
                widget:setItemId(itemId)
                widget:setTooltip(itemName)
                
                widget.onMouseRelease = function(widget, mousePos, mouseButton)
                    if mouseButton == MouseRightButton then
                        local menu = g_ui.createWidget('PopupMenu')
                        menu:setGameMenu(true)
                        menu:addOption(tr('Cyclopedia Info'), function() 
                            modules.game_cyclopedia.CyclopediaItems.onRedirect(itemId) 
                        end)
                        menu:display(mousePos)
                    end
                end
            else
                widget:setItemId(0)
                widget:setTooltip('')
            end
        end
    end

    local lootContentPanel = self.widget:recursiveGetChildById('lootContentPanel')
    local valuableDrops = hunt:getValuableDrops()
    for i, widget in ipairs(lootContentPanel:getChildren()) do
        local itemName = valuableDrops[i]
        if not itemName then
            widget:setItemId(0)
            widget:setTooltip('')
        else
            local itemId = getItemIdByName(itemName)
            if itemId > 0 then
                widget:setItemId(itemId)
                widget:setTooltip(itemName)

                widget.onMouseRelease = function(widget, mousePos, mouseButton)
                    if mouseButton == MouseRightButton then
                        local menu = g_ui.createWidget('PopupMenu')
                        menu:setGameMenu(true)
                        menu:addOption(tr('Cyclopedia Info'), function() modules.game_cyclopedia.CyclopediaItems.onRedirect(itemId) end)
                        local buttonText = modules.game_quickloot.inWhiteList(itemId) and 'Remove from Loot List' or 'Add to Loot List'
                        menu:addOption(tr(buttonText), function() self:onAddToLootList(itemId) end)
                        menu:display(mousePos)
                    end
                end
            end
        end
    end

    -- Initialize the info panel minimap with the internal hunting route (RoutePath)
    -- Uses LOCAL route (displays only on info panel, not main game minimap)
    MapFinder:setLocalRoutePath(hunt:getRouteCoordinates())
    MapFinder:setHuntPosition(hunt:getPosition())
    
    local howToGetButton = self.widget:recursiveGetChildById('howToGetButton')
    local isShowingHuntRoute = true  -- true = showing RoutePath, false = showing WayPath
    
    howToGetButton.onClick = function()
        if isShowingHuntRoute then
            -- Switch to show WayPath (route TO the hunt)
            MapFinder:setLocalRoutePath(hunt:getCoordinates())  -- WayPath coordinates
            MapFinder:setHuntPosition(hunt:getTemplePosition())
            howToGetButton:setText("Show Route")
        else
            -- Switch to show RoutePath (internal hunting route)
            MapFinder:setLocalRoutePath(hunt:getRouteCoordinates())  -- RoutePath coordinates
            MapFinder:setHuntPosition(hunt:getPosition())
            howToGetButton:setText("How To Get Here")
        end
        isShowingHuntRoute = not isShowingHuntRoute
    end

    trackHuntOnMap.onCheckChange = function(widget, checked)
        print("HuntFinder: Track path checkbox changed: " .. tostring(checked))
        if checked then
            self.trackedHunt = hunt
            print("HuntFinder: Setting path and route.")

            -- Mark BOTH paths on the map at once: the WayPath (how to get to the hunt) and
            -- the RoutePath (the route to follow inside the hunt). Stacked after a single clear.
            local wayCoords = hunt:getCoordinates()        -- WayPath - route TO the hunt
            local huntRouteCoords = hunt:getRouteCoordinates() -- RoutePath - route INSIDE the hunt
            modules.game_minimap.setHuntPaths(wayCoords, huntRouteCoords)
            MapFinder:setLocalHuntPaths(wayCoords, huntRouteCoords)

            -- setHuntPaths already drew the static WayPath (and RoutePath) above. Only when the
            -- static WayPath is missing do we fall back to a dynamic player->temple path.
            local routeCoords = wayCoords  -- WayPath - route TO the hunt
            print("HuntFinder: wayPath coords size: " .. (routeCoords and table.size(routeCoords) or "nil"))
            if not (routeCoords and table.size(routeCoords) > 0) then
                 -- Calculate dynamic path from player to temple/start
                 print("HuntFinder: Static route missing, calculating dynamic path...")
                 local player = g_game.getLocalPlayer()
                 local endPos = hunt:getTemplePosition()
                 
                 if player and endPos and endPos.x ~= 0 then
                     local startPos = player:getPosition()
                     local path, result = g_map.findPath(startPos, endPos, 50000, 0)
                     if path and #path > 0 then
                         print("HuntFinder: Dynamic path generated (" .. #path .. " steps).")
                         local points = {}
                         local currentPos = {x=startPos.x, y=startPos.y, z=startPos.z}
                         
                         table.insert(points, {x=currentPos.x, y=currentPos.y, z=currentPos.z})
                         for _, dir in ipairs(path) do
                            if dir == 0 then currentPos.y = currentPos.y - 1
                            elseif dir == 1 then currentPos.x = currentPos.x + 1
                            elseif dir == 2 then currentPos.y = currentPos.y + 1
                            elseif dir == 3 then currentPos.x = currentPos.x - 1
                            elseif dir == 4 then currentPos.x = currentPos.x + 1; currentPos.y = currentPos.y - 1
                            elseif dir == 5 then currentPos.x = currentPos.x + 1; currentPos.y = currentPos.y + 1
                            elseif dir == 6 then currentPos.x = currentPos.x - 1; currentPos.y = currentPos.y + 1
                            elseif dir == 7 then currentPos.x = currentPos.x - 1; currentPos.y = currentPos.y - 1
                            end
                            table.insert(points, {x=currentPos.x, y=currentPos.y, z=currentPos.z})
                         end
                         MapFinder:setRoutePath(points)
                         MapFinder:setLocalHuntPaths(points, huntRouteCoords)
                     else
                         print("HuntFinder: Dynamic path calculation failed or path too long.")
                     end
                 else
                     print("HuntFinder: Cannot calculate path (missing player or target).")
                 end
            end
        else
            self.trackedHunt = nil
            print("HuntFinder: Clearing path.")
            modules.game_minimap.clearPath()
            modules.game_minimap.clearRoutePath()
            MapFinder:setLocalRoutePath(hunt:getRouteCoordinates())
        end
        ListPanel:displayHunts()
    end

    local equipmentsImageSource = {
        ["neck"] = "/images/game/slots/neck",
        ["head"] = "/images/game/slots/head",
        ["backpack"] = "/images/game/slots/back",
        ["body"] = "/images/game/slots/body",
        ["leftHand"] = "/images/game/slots/left-hand",
        ["rightHand"] = "/images/game/slots/right-hand",
        ["leg"] = "/images/game/slots/legs",
        ["feet"] = "/images/game/slots/feet",
        ["finger"] = "/images/game/slots/finger",
        ["ammo"] = "/images/game/slots/ammo",
    }

    local equipmentsPanel = self.widget:recursiveGetChildById('equipmentsPanel')
    local recomented = hunt:getEquipmentsByVocation(HuntFinder.vocation)
    for i, widget in ipairs(equipmentsPanel:getChildren()) do
        local equipment = recomented[widget:getId()]
        if not equipment or equipment == "" then
            widget:setItemId(0)
            widget:setImageSource(equipmentsImageSource[widget:getId()])
        else
            local itemId = getItemIdByName(equipment)
            if itemId > 0 then
                widget:setItemId(itemId)
                widget:setTooltip(string.capitalize(equipment))
                widget:setImageSource('/images/ui/item')

                widget.onMouseRelease = function(widget, mousePos, mouseButton)
                    if mouseButton == MouseRightButton then
                        local menu = g_ui.createWidget('PopupMenu')
                        menu:setGameMenu(true)
                        menu:addOption(tr('Cyclopedia Info'), function() 
                            if Cyclopedia and Cyclopedia.Items and Cyclopedia.Items.onRedirect then
                                Cyclopedia.Items.onRedirect(itemId)
                            elseif modules.game_cyclopedia and modules.game_cyclopedia.Cyclopedia and modules.game_cyclopedia.Cyclopedia.Items and modules.game_cyclopedia.Cyclopedia.Items.onRedirect then
                                modules.game_cyclopedia.Cyclopedia.Items.onRedirect(itemId)
                            end
                        end)
                        menu:display(mousePos)
                    end
                end
            else
                widget:setItemId(0)
                widget:setImageSource(equipmentsImageSource[widget:getId()])
            end
        end
    end

    local ammoWidget = equipmentsPanel:getChildById('ammo')
    local trinketWidget = self.widget:recursiveGetChildById('trinketItem')
    if ammoWidget and trinketWidget then
        trinketWidget:setItemId(ammoWidget:getItemId())
        trinketWidget:setTooltip(ammoWidget:getTooltip())
    end

    -- Default backpack: always show Luminaris Backpack (id 51954) if no backpack is configured
    local backpackWidget = equipmentsPanel:getChildById('backpack')
    if backpackWidget and backpackWidget:getItemId() == 0 then
        backpackWidget:setItemId(63000)
        backpackWidget:setTooltip("Luminaris Backpack")
        backpackWidget:setImageSource('/images/ui/item')
    end

    self:updatePanels()
end

local elementName = {
    [0] = "physical",
    [1] = "fire",
    [2] = "earth",
    [3] = "energy",
    [4] = "ice",
    [5] = "holy",
    [6] = "death",
    [7] = "healing"
}

local resistanceElementId = {
    physical = 0,
    fire = 1,
    earth = 2,
    energy = 3,
    ice = 4,
    holy = 5,
    death = 6,
    healing = 7
}

local function getLocalHuntMonster(monsterName)
    local hunt = self.currentHunt or self.trackedHunt
    if not hunt or not hunt.getMonsters then
        return nil
    end

    local expectedName = tostring(monsterName or ""):lower()
    for _, monster in ipairs(hunt:getMonsters() or {}) do
        if type(monster) == "table" and tostring(monster.Name or ""):lower() == expectedName then
            return monster
        end
    end
    return nil
end

local function getLocalMonsterStat(monster, fieldNames)
    if type(monster) == "table" then
        for _, fieldName in ipairs(fieldNames) do
            local value = monster[fieldName]
            if value ~= nil and value ~= "" then
                return tostring(value)
            end
        end
    end
    return "?"
end

local function parseLocalResistances(resistances)
    local values = {}
    if type(resistances) ~= "string" then
        return values
    end

    for name, value in string.gmatch(resistances, "([^:,]+):%s*([%+%-]?%d+%.?%d*)%%?") do
        local element = string.lower(name):match("^%s*(.-)%s*$")
        local elementId = resistanceElementId[element]
        local percent = tonumber(value)
        if elementId ~= nil and percent ~= nil then
            values[elementId] = percent
        end
    end
    return values
end

local function renderElementInfo(elements, combat, localMonster)
    if not elements then
        return
    end

    elements:destroyChildren()
    local values = {}
    if type(combat) == "table" then
        for elementId, percent in pairs(combat) do
            elementId = tonumber(elementId)
            percent = tonumber(percent)
            if elementId ~= nil and elementName[elementId] and percent ~= nil then
                values[elementId] = percent
            end
        end
    end

    if not next(values) and localMonster then
        values = parseLocalResistances(localMonster.Resistances)
    end

    for elementId = 0, 7 do
        local percent = values[elementId]
        local name = elementName[elementId]
        if percent ~= nil then
            local widgetElement = g_ui.createWidget("ElementInfo", elements)
            widgetElement.progress:setBackgroundColor("white")
            widgetElement:setId(elementId)
            widgetElement.actionId = elementId
            widgetElement.icon:setImageSource("/images/game/cyclopedia/icons/monster-icon-" .. name .. "-resist")
            widgetElement.icon:setTooltip(string.capitalize(name))
            widgetElement.progress:setValue(percent, 0, 150)
            widgetElement.progress:setTooltip(tr("Sensitive to %s: %d%% (neutral)", name, math.floor(percent + 0.5)))

            if percent < 50 then
                widgetElement.progress:setBackgroundColor("red")
                widgetElement.progress:setTooltip(tr("Sensitive to %s: %d%% (very weak)", name, math.floor(percent + 0.5)))
            elseif percent < 100 then
                widgetElement.progress:setBackgroundColor("#f1c40f")
                widgetElement.progress:setTooltip(tr("Sensitive to %s: %d%% (strong)", name, math.floor(percent + 0.5)))
            elseif percent > 100 then
                widgetElement.progress:setBackgroundColor("#18ce18")
                widgetElement.progress:setTooltip(tr("Sensitive to %s: %d%% (weak)", name, math.floor(percent + 0.5)))
            end
        end
    end
end

local function updateSelectedCharm(self, monsterName, localMonster)
    if not self.showingCharms or not self.charmOpacity or not self.charmImage then
        return
    end

    local charmName = localMonster and localMonster.Charm
    local charmData = charmName and charmNameToId[tostring(charmName):lower()] or nil
    if charmData then
        self.charmOpacity:setVisible(false)
        self.charmImage:setImageSource(string.format(
            "/images/game/cyclopedia/monster-bonus-effects/monster-bonus-effects-%d",
            charmData.id
        ))
        self.charmImage:setTooltip(string.todivide(
            charmData.name .. ": " .. string.format(charmData.description, charmData.bonus),
            10
        ))
    else
        self.charmOpacity:setVisible(true)
        self.charmImage:setImageSource("")
        self.charmImage:setTooltip("No charm data for " .. tostring(monsterName or "this creature"))
    end
end

function onSelectionChange(widget, selectedWidget)
    if self.lastMonsterWidget then
        self.lastMonsterWidget:setBackgroundColor("#363636")
        self.lastMonsterWidget:setColor("#c0c0c0")
    end

    if selectedWidget then
        selectedWidget:setBackgroundColor("#585858")
        selectedWidget:setColor("#FFA500")
        self.lastMonsterWidget = selectedWidget

        local serverInfo = self.monsters[selectedWidget.actionId]
        
        local monsterId = getMonsterIdByName(selectedWidget:getText())
        local raceData = nil
        local localMonster = getLocalHuntMonster(selectedWidget:getText())

        if monsterId > 0 then
            raceData = g_things.getRaceData(monsterId)
        end

        if not serverInfo then
            local planeCreature = self.widget:recursiveGetChildById('creatureInfoOutfit')
            local monsterName = self.widget:recursiveGetChildById('creatureName')
            local health = self.widget:recursiveGetChildById('health')
            local experience = self.widget:recursiveGetChildById('experience')
            local speed = self.widget:recursiveGetChildById('speed')
            local armor = self.widget:recursiveGetChildById('armor')
            local mitigation = self.widget:recursiveGetChildById('mitigation')

            if raceData and raceData.outfit then
                planeCreature:setOutfit(raceData.outfit)
            else
                planeCreature:setOutfit({auxType = 13})
            end
            monsterName:setText(selectedWidget:getText())
            health:setText(getLocalMonsterStat(localMonster, {"MaxHealth", "Health", "maxHealth", "health"}))
            experience:setText(getLocalMonsterStat(localMonster, {"Experience", "experience"}))
            speed:setText(getLocalMonsterStat(localMonster, {"Speed", "speed"}))
            armor:setText(getLocalMonsterStat(localMonster, {"Armor", "armor"}))
            mitigation:setText(getLocalMonsterStat(localMonster, {"Mitigation", "mitigation"}))
            renderElementInfo(self.widget:recursiveGetChildById('elements'), nil, localMonster)
            updateSelectedCharm(self, selectedWidget:getText(), localMonster)
            
            if monsterId > 0 then
                -- Fetch full monster data via the dedicated extended opcode, which bypasses
                -- the bestiary unlock/kill gate and never touches the cyclopedia bestiary.
                local protocolGame = g_game.getProtocolGame()
                if protocolGame then
                    protocolGame:sendExtendedOpcode(HuntFinder.MONSTER_INFO_OPCODE, tostring(monsterId))
                end
            end
            return
        end

        local planeCreature = self.widget:recursiveGetChildById('creatureInfoOutfit')
        if raceData and raceData.outfit then
            planeCreature:setOutfit(raceData.outfit)
        else
            planeCreature:setOutfit({auxType = 13})
        end

        -- self.trackerKillsWidget
        if monsterId > 0 then
            local isTracked = false
            if Cyclopedia and Cyclopedia.storedTrackerData then
                for _, entry in pairs(Cyclopedia.storedTrackerData) do
                    -- Entry can be {id, ...} (server) or {raceId=id} (local opt)
                    local entryId = entry.raceId or entry[1]
                    if entryId == monsterId then
                        isTracked = true
                        break
                    end
                end
            end
            
            self.trackerKillsWidget.onCheckChange = nil -- Avoid triggering old callback
            self.trackerKillsWidget:setChecked(isTracked)
            self.trackerKillsWidget:setEnabled(true)
            self.trackerKillsWidget.onCheckChange = function(seldWidget)
                -- g_game.sendStatusTrackerBestiary(monsterId, seldWidget:isChecked())
                
                local checked = seldWidget:isChecked()
                g_game.sendStatusTrackerBestiary(monsterId, checked)
                
                -- Optimistic update: Update local data immediately
                if Cyclopedia and Cyclopedia.storedTrackerData then
                    if checked then
                        -- Add if not exists
                        local exists = false
                        for _, entry in pairs(Cyclopedia.storedTrackerData) do
                            local entryId = entry.raceId or entry[1]
                            if entryId == monsterId then exists = true; break end
                        end
                        if not exists then
                            -- Insert compatible with server structure: {raceId, kills, ?, ?, maxKills}
                            -- We use 0 as placeholders to avoid nil errors in Bestiary
                            table.insert(Cyclopedia.storedTrackerData, {monsterId, 0, 0, 0, 1})
                        end
                    else
                        -- Remove if exists
                        for i, entry in pairs(Cyclopedia.storedTrackerData) do
                            local entryId = entry.raceId or entry[1]
                            if entryId == monsterId then
                                table.remove(Cyclopedia.storedTrackerData, i)
                                break
                            end
                        end
                    end
                end
            end
        else
            self.trackerKillsWidget:setChecked(false)
            self.trackerKillsWidget:setEnabled(false)
        end

        local monsterName = self.widget:recursiveGetChildById('creatureName')
        local health = self.widget:recursiveGetChildById('health')
        local experience = self.widget:recursiveGetChildById('experience')
        local speed = self.widget:recursiveGetChildById('speed')
        local armor = self.widget:recursiveGetChildById('armor')
        local mitigation = self.widget:recursiveGetChildById('mitigation')

        monsterName:setText(selectedWidget:getText())
        health:setText(tostring(serverInfo[1] or getLocalMonsterStat(localMonster, {"MaxHealth", "Health", "maxHealth", "health"})))
        experience:setText(tostring(serverInfo[2] or getLocalMonsterStat(localMonster, {"Experience", "experience"})))
        speed:setText(tostring(serverInfo[3] or getLocalMonsterStat(localMonster, {"Speed", "speed"})))
        armor:setText(tostring(serverInfo[4] or getLocalMonsterStat(localMonster, {"Armor", "armor"})))
        mitigation:setText(tostring(serverInfo[5] or getLocalMonsterStat(localMonster, {"Mitigation", "mitigation"})))

        local elements = self.widget:recursiveGetChildById('elements')
        renderElementInfo(elements, serverInfo[6], localMonster)
        updateSelectedCharm(self, selectedWidget:getText(), localMonster)

    end
end


function HuntInfo:setMonsters(monsters)
    self.monsters = monsters
    if self.radioSelected then
        local selected = self.radioSelected:getSelectedWidget()
        if selected then
             onSelectionChange(self.radioSelected, selected)
        end
    end
end

function HuntInfo:updateMonsterData(data)
    if not self.monsters then self.monsters = {} end
    
    local combat = {}
    if data.combat then
        -- Bestiary sends 1-8 (Physical, Fire, Earth, Energy, Ice, Holy, Death, Healing)
        -- HuntInfo expects 0-7 (Physical, Fire, Earth, Energy, Ice, Holy, Death, Healing)
        for i=1,8 do
            combat[i-1] = data.combat[i]
        end
    end

    self.monsters[data.id] = {
        data.maxHealth,
        data.experience,
        data.speed,
        data.armor,
        (data.mitigation or 0) .. "%",
        combat
    }

    if self.radioSelected then
        local selected = self.radioSelected:getSelectedWidget()
        -- Refresh if we are looking at this monster
        if selected and selected.actionId == data.id then
             onSelectionChange(self.radioSelected, selected)
        end
    end
end

function HuntInfo:onAddToLootList(itemId)
    if not modules.game_quickloot.inWhiteList(itemId) then
		modules.game_quickloot.addToQuickLoot(itemId)
	else
		modules.game_quickloot.removeItemInList(itemId)
	end
end

