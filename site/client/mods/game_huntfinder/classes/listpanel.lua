if not ListPanel then
    ListPanel = {
        widget = nil,
        huntWidget = nil,
        huntScrollBar = nil,
        searchInputBox = nil,
        vocation = "All",

        -- Scrollable settings
        listWidgetHeight = 183, -- 225x183
        listCapacity = 0,
        listMinWidgets = 0,
        listMaxWidgets = 0,
        listPool = {},
        listData = {},
    }
    ListPanel.__index = ListPanel
end

local self = ListPanel

function ListPanel.init()
    self.widget = HuntFinder.widget:recursiveGetChildById('listPanel')
    self.huntWidget = self.widget:getChildById('hunts')
    self.huntScrollBar = self.widget:getChildById('huntListScrollBar')
    self.searchInputBox = HuntFinder.widget:recursiveGetChildById("searchInputBox")
    self:setupSmartSpinBox(self.searchInputBox)
    self.searchInputBox:updatePossibleValues(HuntConfig:getHuntsLevelList())
end

function ListPanel:setupSmartSpinBox(spinbox)
    function spinbox.updatePossibleValues(box, values)
        table.sort(values)
        box.possibleValues = values
        if #values > 0 then
             box:setMinimum(values[1])
             box:setMaximum(values[#values])
        end
    end

    function spinbox.upSpin(box)
        if not box.possibleValues then box:setValue(box:getValue() + box:getStep()); return end
        local val = box:getValue()
        for _, v in ipairs(box.possibleValues) do
            if v > val then
                box:setValue(v)
                return
            end
        end
        box:setValue(box.maximum)
    end

    function spinbox.downSpin(box)
        if not box.possibleValues then box:setValue(box:getValue() - box:getStep()); return end
        local val = box:getValue()
        local found = box.minimum
        for _, v in ipairs(box.possibleValues) do
            if v >= val then break end
            found = v
        end
        box:setValue(found)
    end
end

function ListPanel:clear()
    if self.widget then
        self.widget:destroyChildren()
        self.widget = nil
    end
    self.huntWidget = nil
    self.huntScrollBar = nil
    self.searchInputBox = nil
end

function ListPanel:canDrawHunt(hunt)
    local vocations = hunt:getVocations()
    if HuntFinder.vocation ~= "All" and (not vocations or not table.contains(vocations, HuntFinder.vocation, true)) then
        return false
    end

    local searchQuery = HuntFinder.searchQuery
    if searchQuery then
        searchQuery = searchQuery:lower()
        local huntName = hunt:getName()
        local monsters = hunt:getMonsters()

        if huntName and huntName:lower():find(searchQuery, 1, true) then
            return true
        end
        
        if monsters then
            for _, monster in ipairs(monsters) do
                if monster.Name and monster.Name:lower():find(searchQuery, 1, true) then
                    return true
                end
            end
        end
        
        return false
    end

    local huntLevel = hunt:getLevel()
    if not huntLevel then
        return false
    end
    local types = hunt:getType()
    if not types or not table.contains(types, HuntFinder.teamSize, true) then
        return false
    end
    local playerLevel = HuntFinder.level or 1
    local result = playerLevel <= huntLevel
    return result
end

function ListPanel:displayHunts()
    if not self.widget or not self.huntWidget then
        return
    end

    local hunts = HuntConfig:getHuntByVocation(HuntFinder.vocation, self)
    if not hunts or #hunts == 0 then
        return
    end

    -- Move tracked hunt to the top, preserve original order for others
    local reorderedHunts = {}
    local trackedHunt = HuntInfo.trackedHunt
    if trackedHunt then
        table.insert(reorderedHunts, trackedHunt)
    end
    for _, hunt in ipairs(hunts) do
        if hunt ~= trackedHunt then
            table.insert(reorderedHunts, hunt)
        end
    end

    self.listCapacity = (math.floor(self.huntWidget:getHeight() / self.listWidgetHeight)) * 3
    self.listMinWidgets = 0
    self.listPool = {}
    self.listData = reorderedHunts

    local usedCount = 0
    local currentIndex = 1
    for i, hunt in ipairs(reorderedHunts) do
        if #self.listPool >= self.listCapacity then
            break
        end

        local widget = self.huntWidget:recursiveGetChildById("widget" .. currentIndex)
        if not widget then
            goto continue
        end

        self:buildWidget(widget, hunt)
        widget:setVisible(true)

        currentIndex = currentIndex + 1
        table.insert(self.listPool, widget)
        usedCount = usedCount + 1

        ::continue::
    end

    for i = usedCount + 1, self.listCapacity do
        local widget = self.huntWidget:recursiveGetChildById("widget" .. i)
        if widget then
            widget:setVisible(false)
        end
    end

    self.listMaxWidgets = math.ceil((#self.listData / 3) - 2)
    self.huntScrollBar:setValue(0)
    self.huntScrollBar:setMinimum(self.listMinWidgets)
    self.huntScrollBar:setMaximum(math.max(0, self.listMaxWidgets))
    self.huntScrollBar.onValueChange = function(list, value, delta) self:onHuntListValueChange(list, value, delta) end


end

function ListPanel:onHuntListValueChange(list, value, delta)
    local itemsPerRow = 3
    local rowsVisible = 2
    local itemsVisible = itemsPerRow * rowsVisible

    local startLabel = (value * itemsPerRow) + 1
    local endLabel = startLabel + itemsVisible - 1

    local currentWidgetIndex = startLabel
    for k, widget in pairs(self.huntWidget:getChildren()) do
        if currentWidgetIndex > endLabel then
            widget:setVisible(false)
            goto continue
        end

        local hunt = self.listData[currentWidgetIndex]
        if not hunt then
            widget:setVisible(false)
            goto continue
        end

        self:buildWidget(widget, hunt)
        currentWidgetIndex = currentWidgetIndex + 1
        :: continue ::
    end
end

function ListPanel:buildWidget(widget, hunt)
    local huntName = widget:recursiveGetChildById('huntNameLabel')
    local huntLocation = widget:recursiveGetChildById('huntWidgetLocation')
    local huntLevel = widget:recursiveGetChildById('huntWidgetLevel')
    local huntLootHour = widget:recursiveGetChildById('huntWidgetLootHour')
    local huntXpHour = widget:recursiveGetChildById('huntWidgetXpHour')
    local highlightHunt = widget:recursiveGetChildById('highlightHunt')
    local trackingHunt = widget:recursiveGetChildById('trackingHunt')



    widget.onClick = function() HuntFinder:showHuntInfo(hunt) end
    widget:setVisible(true)

    huntName:setText(hunt:getName() or "Unknown")
    huntLocation:setText(hunt:getLocation() or "Unknown")
    huntLevel:setText(tostring(hunt:getLevel()) .. "+" or "0+")
    huntLootHour:setText(hunt:getLootHour() or "N/A")
    huntXpHour:setText(hunt:getXPHour() or "N/A")

    if highlightHunt then
        highlightHunt:setVisible(HuntInfo.trackedHunt == hunt)
        trackingHunt:setVisible(HuntInfo.trackedHunt == hunt)
    end

    local monsters = hunt:getMonsters()
    local monsterCount = monsters and #monsters or 0
    local maxMonsters = math.min(monsterCount, 3)
    for i = 0, 2 do
        local monsterWidget = widget:recursiveGetChildById('creatureOutfit' .. i)
        if not monsterWidget then
            goto continue_monster
        end

        local tooltipLabel = widget:recursiveGetChildById('tooltipLabel' .. i)
        if not tooltipLabel then
            goto continue_monster
        end

        local monster = monsters[i + 1]
        if not monster or not monster.Name then
            monsterWidget:setVisible(false)
            tooltipLabel:removeTooltip("")
            tooltipLabel:setVisible(false)
            goto continue_monster
        end

        monsterWidget:setVisible(true)
        monsterWidget:setTooltip(monster.Name)

        tooltipLabel:setTooltip(monster.Name)
        tooltipLabel:setVisible(true)
        tooltipLabel.onClick = function() HuntFinder:showHuntInfo(hunt) end

        local races = g_things.getRacesByName(monster.Name)
        if not races or #races == 0 then
            races = g_things.getRacesByName(monster.Name:lower())
        end

        if races and #races > 0 then
            local raceData = g_things.getRaceData(races[1].raceId)
            if raceData and raceData.outfit then
                monsterWidget:setOutfit(raceData.outfit)
            else
                monsterWidget:setOutfit({auxType = 13})
            end
        else
            monsterWidget:setOutfit({auxType = 13})
        end

        ::continue_monster::
    end
end