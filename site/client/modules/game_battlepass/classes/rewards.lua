if not BattlePassRewards then
    BattlePassRewards = {}
    BattlePassRewards.__index = BattlePassRewards

    BattlePassRewards.claimRewardWindow = nil
    BattlePassRewards.confirmRewardWindow = nil

    BattlePassRewards.rewardWidthIncrement = 80
    BattlePassRewards.rewardEmptyHeight = 140

    BattlePassRewards.selectedItemId = -1

    BattlePassRewards.textReward = ''
end

local skillName = {
    [0] = "Fist Fighting",
    [1] = "Club Fighting",
    [2] = "Sword Fighting",
    [3] = "Axe Fighting",
    [4] = "Distance Fighting",
    [5] = "Shielding",
    [13] = "Magic Level"
}

local self = BattlePassRewards
function BattlePassRewards:onConfirmClaimReward(index, rewardType)
    local reward = self:getReward(index, rewardType)
    if not reward then
        return
    end

    reward.rewardType = reward.rewardType or 1
    reward.charges    = reward.charges    or 0
    -- Para Item único: garante defaults. Para Multi Items (rewardType=17)
    -- NÃO sobrescreve itemId/count pois os dados ficam em reward.items.
    local rTypeName = (BattleRewardTypes and BattleRewardTypes[reward.rewardType]) or ""
    if rTypeName ~= "Multi Items" then
        reward.itemId = reward.itemId or 2160
        reward.count  = reward.count  or 1
    end

    if self.confirmRewardWindow then
        self.confirmRewardWindow:destroy()
        self.confirmRewardWindow = nil
    end
    if self.claimRewardWindow then
        self.claimRewardWindow:destroy()
        self.claimRewardWindow = nil
    end

    self.claimRewardWindow = g_ui.createWidget("SelectRewardWindow", rootWidget)
    local widgetsPanel = self.claimRewardWindow:recursiveGetChildById("rewardsInfoPanel")

    local rewardLabel = self.claimRewardWindow:recursiveGetChildById("rewardLabel")
    if rewardLabel then
        local text = rewardLabel:getText() or ""
        pcall(function() rewardLabel:setText(string.format(text, index)) end)
    end

    -- Função única e robusta para fechar a janela de claim, garantindo que
    -- o input lock seja liberado e a janela do battle pass volte a aparecer.
    local function closeClaimWindow()
        if self.confirmRewardWindow then
            pcall(function() self.confirmRewardWindow:destroy() end)
            self.confirmRewardWindow = nil
        end
        if self.claimRewardWindow then
            pcall(function() self.claimRewardWindow:destroy() end)
            self.claimRewardWindow = nil
        end
        pcall(function() g_client.setInputLockWidget(nil) end)
        if BattlePass and BattlePass.showBattlePass then
            pcall(function() BattlePass:showBattlePass() end)
        end
    end

    self.claimRewardWindow.onEscape = closeClaimWindow

    local closeBtn = self.claimRewardWindow:recursiveGetChildById("close")
    if closeBtn then closeBtn.onClick = closeClaimWindow end
    -- X no canto superior direito da janela
    local closeX = self.claimRewardWindow:recursiveGetChildById("closeX")
    if closeX then closeX.onClick = closeClaimWindow end

    local function okfunction()
        if self.selectedItemId == -1 and (BattleRewardTypes[reward.rewardType] == "Boosted Exercise" or BattleRewardTypes[reward.rewardType] == "Exercise Item" or
         BattleRewardTypes[reward.rewardType] == "Extra Skill" or BattleRewardTypes[reward.rewardType] == "Elemental Outfit" or BattleRewardTypes[reward.rewardType] == "Choosable Item") then
            modules.game_textmessage.displayFailureMessage("You must select an item before collecting the reward.")
            return
        end

        local rewardId   = reward.rewardId
        local rewardKind = reward.rewardType
        local selectedId = self.selectedItemId
        closeClaimWindow()
        self:onRedeemReward(index, rewardId, rewardKind, selectedId)
    end

    local cancelFunc = function()
        if self.confirmRewardWindow then
            pcall(function() self.confirmRewardWindow:destroy() end)
            self.confirmRewardWindow = nil
        end
        if self.claimRewardWindow then
            self.claimRewardWindow:show()
            pcall(function() g_client.setInputLockWidget(self.claimRewardWindow) end)
        end
    end

    self.claimRewardWindow:recursiveGetChildById("collectRewardButton").onClick = function()
        if self.selectedItemId == -1 and (BattleRewardTypes[reward.rewardType] == "Boosted Exercise" or BattleRewardTypes[reward.rewardType] == "Exercise Item" or
         BattleRewardTypes[reward.rewardType] == "Extra Skill" or BattleRewardTypes[reward.rewardType] == "Elemental Outfit" or BattleRewardTypes[reward.rewardType] == "Choosable Item") then
            modules.game_textmessage.displayFailureMessage("You must select an item before collecting the reward.")
            return
        end

        if BattleRewardTypes[reward.rewardType] == "Extra Skill" then
            self.textReward = string.format("You will receive +%d skill points in %s\nfor %d hours (Scroll 30 days).", reward.count, skillName[self.selectedItemId], reward.durationTime)
        elseif BattleRewardTypes[reward.rewardType] == "Elemental Outfit" then
            local elements = {
                [1] = "Death",
                [2] = "Energy",
                [3] = "Holy",
                [4] = "Ice",
                [5] = "Earth",
                [6] = "Fire"
            }
            self.textReward = string.format("You will receive the %s Elemental Outfits\nwith addons %s.", elements[self.selectedItemId], reward.addons and "enabled" or "disabled")
        elseif BattleRewardTypes[reward.rewardType] == "Choosable Item" then
            local selectedItemName = ""
            for _, v in pairs(reward.choosableValues) do
                if v.thingId == self.selectedItemId then
                    local item = Item.create(v.thingId)
                    selectedItemName = item and item:getName() or getItemNameById(v.thingId)
                    break
                end
            end
            self.textReward = string.format("You will receive %dx %s.", reward.count, string.capitalize(selectedItemName))
        end

        -- Fallback: garante que o modal de confirmação nunca fique vazio.
        -- Para recompensas do tipo Item e Multi Items (e qualquer tipo não
        -- tratado explicitamente acima), reconstrói o texto a partir dos
        -- dados do reward de forma segura, sem depender do pcall de populate.
        if not self.textReward or self.textReward == '' then
            local rtype = BattleRewardTypes and BattleRewardTypes[reward.rewardType] or ""
            if rtype == "Item" then
                local itemName = ""
                pcall(function()
                    local n = getItemNameById and getItemNameById(reward.itemId) or ""
                    itemName = (type(string.capitalize) == 'function' and string.capitalize(n)) or n
                end)
                if itemName == "" then itemName = "item" end
                self.textReward = string.format("You will receive %dx %s.", reward.count or 1, itemName)
            elseif rtype == "Multi Items" then
                self.textReward = "You will receive the following items.\nClick Confirm to collect."
            else
                self.textReward = "Click Confirm to collect your reward."
            end
        end

        self.claimRewardWindow:hide()
        self.confirmRewardWindow = g_ui.createWidget("ConfirmReward", rootWidget)

        self.confirmRewardWindow.onEscape = cancelFunc
        self.confirmRewardWindow:recursiveGetChildById('cancel').onClick = cancelFunc
        self.confirmRewardWindow:recursiveGetChildById('confirm').onClick = okfunction
        self.confirmRewardWindow:recursiveGetChildById('textContent'):setText(self.textReward)

        g_client.setInputLockWidget(self.confirmRewardWindow)
    end

    BattlePass.window:hide()

    -- Envolve todo o populamento da janela em pcall para que se algum
    -- branch específico (Outfit, Multi Items, etc.) crashar por causa de
    -- um campo opcional faltando, a janela ainda continue clicável e o
    -- botão Close (já registrado acima) funcione normalmente.
    local populateOk, populateErr = pcall(function()
    self.textReward = ''
    local infoLabel = self.claimRewardWindow:recursiveGetChildById("infoLabel")
    local rewardsInfoPanel = self.claimRewardWindow:recursiveGetChildById("rewardsInfoPanel")
    local outfitsInfoPanel = self.claimRewardWindow:recursiveGetChildById("outfitsInfoPanel")
    rewardsInfoPanel:setVisible(true)
    outfitsInfoPanel:setVisible(false)
    rewardsInfoPanel:setWidth(self.rewardWidthIncrement)
    local rewardsInfoScrollBar = self.claimRewardWindow:recursiveGetChildById("rewardsInfoScrollBar")
    rewardsInfoScrollBar:setVisible(true)

    -- Auxiliar: usa setColorText se disponível, senão setText simples.
    local function safeLabel(lbl, text)
        if not lbl then return end
        if type(lbl.setColorText) == 'function' then
            pcall(lbl.setColorText, lbl, text)
        else
            pcall(lbl.setText, lbl, text)
        end
    end

    local width = 0
    local normalHeight = 250

    self.selectedItemId = -1
    if BattleRewardTypes[reward.rewardType] == "Outfit" then
        local function rotateOutfit(value)
            self.currentOutfitDirection = self.currentOutfitDirection or Directions.North
            local direction = self.currentOutfitDirection + value
            if direction < Directions.North then
                direction = Directions.West
            elseif direction > Directions.West then
                direction = Directions.North
            end
            self.currentOutfitDirection = direction

            local index = 1
            while true do
                local outfitWidget = rewardsInfoPanel:recursiveGetChildById("rewardSlot" .. index - 1)
                if not outfitWidget then break end
                if outfitWidget:isVisible() then
                    outfitWidget.rewardOutfit:setDirection(direction)
                end
                index = index + 1
            end
        end

        local function setupOutfitWidget(outfitWidget, outfitData, currentOutfit)
            outfitWidget.rewardOutfit:setVisible(true)
            outfitWidget.rewardOutfit:setOutfit({
                type = outfitData.thingId,
                head = currentOutfit.head,
                body = currentOutfit.body,
                legs = currentOutfit.legs,
                feet = currentOutfit.feet,
                addons = reward.addons
            })

            outfitWidget:setImageSource('/images/game/battlepass/ground-bg')
            if self.currentOutfitDirection then
                outfitWidget.rewardOutfit:setDirection(self.currentOutfitDirection)
            end
        end

        local previousButton = self.claimRewardWindow:recursiveGetChildById("rotatePrevButton")
        local nextButton = self.claimRewardWindow:recursiveGetChildById("rotateNextButton")

        rewardsInfoPanel:setVisible(true)
        nextButton:setVisible(true)
        previousButton:setVisible(true)

        nextButton.onClick = function()
            rotateOutfit(-1)
        end
        previousButton.onClick = function()
            rotateOutfit(1)
        end

        local outfitName = ''
        local addonText = ''
        for k, v in pairs(reward.randomValues) do
            local widget = widgetsPanel:recursiveGetChildById("rewardSlot" .. k - 1)
            widget:setVisible(true)
            widget.rewardOutfit:setVisible(true)

            local currentOutfit = g_game.getLocalPlayer():getOutfit()
            local displayOutfit = {type = v.thingId, head = currentOutfit.head, body = currentOutfit.body, legs = currentOutfit.legs, feet = currentOutfit.feet, addons = reward.addons}
            --widget.rewardOutfit:setOutfit(displayOutfit)
            setupOutfitWidget(widget, v, currentOutfit)
            addonText = reward.addons == 1 and "first addon" or (reward.addons == 2 and "second addon" or "full addons")
            local tooltipText = string.format("%s with %s", v.thingName, addonText)
            widget.rewardOutfit:setTooltip(tooltipText)
            --widget.rewardOutfit:setImageSource('/images/game/battlepass/ground-bg')
            width = width + self.rewardWidthIncrement
            outfitName = tooltipText
        end

        infoLabel:setText(string.format("You will receive the following outfit with %s:", addonText))
        self.textReward = string.format("You will receive the following outfit:\n%s.", outfitName)
    elseif BattleRewardTypes[reward.rewardType] == "Random Item" then
        for k, v in pairs(reward.randomValues) do
            local widget = widgetsPanel:recursiveGetChildById("rewardSlot" .. k - 1)
            widget:setVisible(true)
            widget.rewardItem:setVisible(true)
            widget.rewardItem:setItemId(v.thingId)
            pcall(function() widget.rewardItem:setItemCount(tonumber(reward.count) or 1) end)
            widget.rewardItem.rewardItemCount:setText("")
            local item = widget.rewardItem:getItem()
            if item then
                widget.rewardItem:setTooltip(string.capitalize(item:getName()))
                widget.rewardItem:setFixedSize(not item:isWrapable())
            end
            width = width + self.rewardWidthIncrement
        end

        local message = "You will receive a random item from the list bellow:"
        if reward.stuck then
            message = message .. "\n[color=white]The reward will be bound to your character.[/color]"
        end

       self.textReward = string.format("You will receive a random item from the list.")
       infoLabel:setColorText(message)
    elseif BattleRewardTypes[reward.rewardType] == "Random Mount" then
        for k, v in pairs(reward.randomValues) do
            local widget = widgetsPanel:recursiveGetChildById("rewardSlot" .. k - 1)
            if not widget then
                widget = g_ui.createWidget("RewardInfoSlot", rewardsInfoPanel)
                widget:setId("rewardSlot" .. k - 1)
            end
            widget:setVisible(true)
            widget:setPhantom(false)
            widget.rewardOutfit:setVisible(true)
            widget.rewardOutfit:setTooltip(v.thingName)
            widget:setImageSource('/images/game/battlepass/ground-bg')
            widget.rewardOutfit:setOutfit({type = v.thingId})
            width = width + self.rewardWidthIncrement
        end

        infoLabel:setText("You will receive a random mount from the list bellow:")
        self.textReward = string.format("You will receive a random mount from the list.")
    elseif BattleRewardTypes[reward.rewardType] == "Item" then
        local widget = widgetsPanel:recursiveGetChildById("rewardSlot0")
        if widget then
            widget:setVisible(true)
            -- Acessa o BigItem pelo id (mais robusto que widget.rewardItem direto).
            local rewardItem = widget:recursiveGetChildById("rewardItem") or widget.rewardItem
            if rewardItem then
                rewardItem:setVisible(true)
                pcall(function() rewardItem:setItemId(tonumber(reward.itemId) or 0) end)
                pcall(function() rewardItem:setItemCount(tonumber(reward.count) or 1) end)

                local countLabel = rewardItem:recursiveGetChildById("rewardItemCount")
                if countLabel then
                    pcall(function() countLabel:setText("") end)
                end

                local itemName = getItemNameById(reward.itemId) or ""
                local item = rewardItem:getItem()
                if item then
                    itemName = item:getName()
                    pcall(function() rewardItem:setFixedSize(not item:isWrapable()) end)
                    if reward.itemId == 63246 then
                        pcall(function() rewardItem:setFixedSize(true) end)
                    end
                end

                if (reward.charges or 0) > 0 then
                    pcall(function() rewardItem:setTooltip(string.format("%s\nCharges: %s", string.capitalize(itemName), reward.charges)) end)
                else
                    pcall(function() rewardItem:setTooltip(string.format("%sx %s", reward.count or 1, string.capitalize(itemName))) end)
                end

                width = width + self.rewardWidthIncrement

                local message = "You will receive the following item."
                if reward.stuck then
                    message = message .. "\n[color=white]The reward will be bound to your character.[/color]"
                end
                safeLabel(infoLabel, message)
                self.textReward = string.format("You will receive the following item: %d %s.", reward.count or 1, string.capitalize(itemName))
            end
        end

    elseif BattleRewardTypes[reward.rewardType] == "Boosted Exercise" or BattleRewardTypes[reward.rewardType] == "Exercise Item" then
        for k, v in pairs(reward.randomValues) do
            local widget = widgetsPanel:recursiveGetChildById("rewardSlot" .. k - 1)
            widget:setVisible(true)
            widget.rewardItem:setVisible(true)
            widget.rewardItem:setItemId(v.thingId)

            local item = widget.rewardItem:getItem()
            local itemName = getItemNameById(v.itemId)
            if item then
                itemName = item:getName()
            end

            widget.rewardItem:setTooltip(string.capitalize(itemName))
            widget:setFocusable(true)
            normalHeight = 260

            widget.rewardItem.onClick = function(w)
                if w:isFocused() then
                    self.selectedItemId = v.thingId

                    self.textReward = string.format("You must choose one %s,\nhave %d charges.", string.capitalize(itemName), reward.charges)
                end
            end

            width = width + self.rewardWidthIncrement
        end

        local message = "You must choose [color=white]one[/color] of the following items, have [color=white]" .. reward.charges .. " charges.[/color]"
        if reward.stuck then
            message = message .. "\n[color=white]The reward will be bound to your character.[/color]"
        end

       infoLabel:setColorText(message)
    elseif BattleRewardTypes[reward.rewardType] == "Charms" then
        infoLabel:setColorText("You will receive [color=white]+" .. reward.count .. " charm points[/color] on your character.")
        rewardsInfoPanel:setVisible(false)
        rewardsInfoScrollBar:setVisible(false)
        normalHeight = self.rewardEmptyHeight
        self.textReward = string.format("You will receive +%d charm points on your character.", reward.count)
    elseif BattleRewardTypes[reward.rewardType] == "Prey" then
        infoLabel:setColorText("You will receive [color=white]+" .. reward.count .. " prey wildcards[/color] on your character.")
        rewardsInfoPanel:setVisible(false)
        rewardsInfoScrollBar:setVisible(false)
        normalHeight = self.rewardEmptyHeight
        self.textReward = string.format("You will receive +%d prey wildcards on your character.", reward.count)
    elseif BattleRewardTypes[reward.rewardType] == "Regen" then
        infoLabel:setColorText("You will receive [color=white]" .. reward.durationTime .. " hours (Scroll 30 days) of Double Regeneration[/color].")
        rewardsInfoPanel:setVisible(false)
        rewardsInfoScrollBar:setVisible(false)
        normalHeight = self.rewardEmptyHeight
        self.textReward = string.format("You will receive %d hours (Scroll 30 days)\nof Double Regeneration.", reward.durationTime)
    elseif BattleRewardTypes[reward.rewardType] == "Instant Reward" then
        infoLabel:setColorText("You will receive [color=white]+" .. reward.count .. " instant rewards[/color] on your character.")
        rewardsInfoPanel:setVisible(false)
        rewardsInfoScrollBar:setVisible(false)
        normalHeight = self.rewardEmptyHeight
        self.textReward = string.format("You will receive +%d instant rewards on your character.", reward.count)
    elseif BattleRewardTypes[reward.rewardType] == "Double Skill" then
        infoLabel:setColorText("You will receive [color=white]" .. reward.durationTime .. " hours (Scroll 30 days) of Double Skill[/color].")
        rewardsInfoPanel:setVisible(false)
        rewardsInfoScrollBar:setVisible(false)
        normalHeight = self.rewardEmptyHeight
        self.textReward = string.format("You will receive %d hours (Scroll 30 days)\nof Double Skill.", reward.durationTime)
    elseif BattleRewardTypes[reward.rewardType] == "Level" then
        infoLabel:setColorText("You will receive [color=white]+" .. reward.count .. " Level[/color] on your character.")
        rewardsInfoPanel:setVisible(false)
        rewardsInfoScrollBar:setVisible(false)
        normalHeight = self.rewardEmptyHeight
        self.textReward = string.format("You will receive +%d Level on your character.", reward.count)
    elseif BattleRewardTypes[reward.rewardType] == "Overload Forge" then
        infoLabel:setColorText("You will receive [color=white]" .. reward.durationTime .. " hours (Scroll 30 days) of Exaltation Overload[/color].")
        rewardsInfoPanel:setVisible(false)
        rewardsInfoScrollBar:setVisible(false)
        normalHeight = self.rewardEmptyHeight
        self.textReward = string.format("You will receive %d hours (Scroll 30 days)\nof Exaltation Overload.", reward.durationTime)
    elseif BattleRewardTypes[reward.rewardType] == "Exp Boost" then
        infoLabel:setColorText("You will receive [color=white]" .. reward.durationTime .. " hours of store XP Boost[/color].")
        rewardsInfoPanel:setVisible(false)
        rewardsInfoScrollBar:setVisible(false)
        normalHeight = self.rewardEmptyHeight
        self.textReward = string.format("You will receive %d hours of store XP Boost,\nlinked to your skill tab.", reward.durationTime)
    elseif BattleRewardTypes[reward.rewardType] == "Extra Skill" then
        infoLabel:setColorText("You will receive [color=white]+" .. reward.count .. " skill points[/color] in the skill of your choice for [color=white]" .. reward.durationTime .. " hours[/color].")
        rewardsInfoPanel:setVisible(true)
        rewardsInfoScrollBar:setVisible(true)

        local skills = {0, 1, 2, 3, 4, 5, 13}
        for k, v in pairs(skills) do
            local widget = widgetsPanel:recursiveGetChildById("rewardSlot" .. k - 1)
            widget:setVisible(true)
            widget.rewardSpecial:setVisible(true)
            widget.rewardSpecial:setTooltip(skillName[v] .. " (" .. reward.count .. " points for " .. reward.durationTime .. " hours)")
            widget.rewardSpecial:setImageSource('/images/game/battlepass/skills/' .. v)

            widget:setFocusable(true)

            widget.rewardSpecial.onClick = function(w)
                if w:isFocused() then
                    self.selectedItemId = v
                end
            end

            width = width + self.rewardWidthIncrement
        end

    elseif BattleRewardTypes[reward.rewardType] == "Elemental Outfit" then
        local function rotateOutfit(value)
            self.currentOutfitDirection = self.currentOutfitDirection or Directions.North
            local direction = self.currentOutfitDirection + value
            if direction < Directions.North then
                direction = Directions.West
            elseif direction > Directions.West then
                direction = Directions.North
            end
            self.currentOutfitDirection = direction

            local index = 1
            while true do
                local outfitWidget = outfitsInfoPanel:recursiveGetChildById("outfitPreview" .. index - 1)
                if not outfitWidget then break end
                if outfitWidget:isVisible() then
                    outfitWidget.rewardOutfit:setDirection(direction)
                end
                index = index + 1
            end
        end

        local function setupOutfitWidget(outfitWidget, outfitData, currentOutfit)
            outfitWidget.rewardOutfit:setVisible(true)
            outfitWidget.rewardOutfit:setOutfit({
                type = outfitData.looktype,
                head = currentOutfit.head,
                body = currentOutfit.body,
                legs = currentOutfit.legs,
                feet = currentOutfit.feet,
                addons = reward.addons
            })
            outfitWidget.rewardOutfit:setTooltip(outfitData.name)
            outfitWidget:setTooltip(outfitData.name)
            outfitWidget:setImageSource('/images/game/battlepass/ground-bg')
            if self.currentOutfitDirection then
                outfitWidget.rewardOutfit:setDirection(self.currentOutfitDirection)
            end
        end

        local previousButton = self.claimRewardWindow:recursiveGetChildById("previousButton")
        local nextButton = self.claimRewardWindow:recursiveGetChildById("nextButton")

        infoLabel:setColorText("You will receive the [color=white]Elemental Outfit[/color] of your choice.")
        rewardsInfoPanel:setVisible(true)
        outfitsInfoPanel:setVisible(true)
        nextButton:setVisible(true)
        previousButton:setVisible(true)

        nextButton.onClick = function()
            rotateOutfit(-1)
        end
        previousButton.onClick = function()
            rotateOutfit(1)
        end

        normalHeight = 340

        local elements = {
            [1] = "Death",
            [2] = "Energy",
            [3] = "Holy",
            [4] = "Ice",
            [5] = "Earth",
            [6] = "Fire"
        }

        for i = 1, 6 do
            local widget = widgetsPanel:recursiveGetChildById("rewardSlot" .. i - 1)
            widget:setVisible(true)
            widget.rewardSpecial:setVisible(true)
            widget.rewardSpecial:setImageSource('/images/game/battlepass/tiles/' .. i)
            widget.rewardSpecial:setTooltip("Elemental Outfit " .. elements[i])
            widget:setFocusable(true)

            if i == 1 then
                widget:recursiveFocus(2)
                self.selectedItemId = i

                local currentOutfit = g_game.getLocalPlayer():getOutfit()
                local index = 1
                for _, v in pairs(reward.maleOutfit[i]) do
                    local outfitWidget = outfitsInfoPanel:recursiveGetChildById("outfitPreview" .. index - 1)
                    setupOutfitWidget(outfitWidget, v, currentOutfit)
                    index = index + 1
                end
                for _, v in pairs(reward.femaleOutfit[i]) do
                    local outfitWidget = outfitsInfoPanel:recursiveGetChildById("outfitPreview" .. index - 1)
                    setupOutfitWidget(outfitWidget, v, currentOutfit)
                    index = index + 1
                end
            end

            widget.rewardSpecial.onClick = function(w)
                if w:isFocused() then
                    self.selectedItemId = i
                    local currentOutfit = g_game.getLocalPlayer():getOutfit()
                    local index = 1
                    for _, v in pairs(reward.maleOutfit[i]) do
                        local outfitWidget = outfitsInfoPanel:recursiveGetChildById("outfitPreview" .. index - 1)
                        setupOutfitWidget(outfitWidget, v, currentOutfit)
                        index = index + 1
                    end
                    for _, v in pairs(reward.femaleOutfit[i]) do
                        local outfitWidget = outfitsInfoPanel:recursiveGetChildById("outfitPreview" .. index - 1)
                        setupOutfitWidget(outfitWidget, v, currentOutfit)
                        index = index + 1
                    end
                end
            end

            width = width + self.rewardWidthIncrement
        end
    elseif BattleRewardTypes[reward.rewardType] == "Choosable Item" then
        for k, v in pairs(reward.choosableValues) do
            local widget = widgetsPanel:recursiveGetChildById("rewardSlot" .. k - 1)
            widget:setVisible(true)
            widget.rewardItem:setVisible(true)
            widget.rewardItem:setItemId(v.thingId)
            pcall(function() widget.rewardItem:setItemCount(tonumber(reward.count) or 1) end)
            widget.rewardItem.rewardItemCount:setText("")

            local item = widget.rewardItem:getItem()
            local itemName = getItemNameById(v.thingId)
            if item then
                itemName = item:getName()
                widget.rewardItem:setFixedSize(not item:isWrapable())
            end

            widget.rewardItem:setTooltip(string.format("%dx %s", reward.count, string.capitalize(itemName)))
            widget:setFocusable(true)
            normalHeight = 260

            widget.rewardItem.onClick = function(w)
                if w:isFocused() then
                    self.selectedItemId = v.thingId
                    self.textReward = string.format("You have selected %dx %s.", reward.count, string.capitalize(itemName))
                end
            end

            width = width + self.rewardWidthIncrement
        end

        local message = "You must choose [color=white]one[/color] of the following items:"
        if reward.stuck then
            message = message .. "\n[color=white]The reward will be bound to your character.[/color]"
        end

        infoLabel:setColorText(message)
        
    elseif BattleRewardTypes[reward.rewardType] == "Multi Items" then
        local stuck = reward.stuck or false
        local namesList = ''
        local itemsList = (type(reward.items) == "table") and reward.items or {}
        for k, v in ipairs(itemsList) do
            local widget = widgetsPanel:recursiveGetChildById("rewardSlot" .. k - 1)
            if not widget then
                widget = g_ui.createWidget("RewardInfoSlot", rewardsInfoPanel)
                widget:setId("rewardSlot" .. k - 1)
            end
            widget:setVisible(true)
            local ri = widget:recursiveGetChildById("rewardItem") or widget.rewardItem
            if ri then
                ri:setVisible(true)
                pcall(function() ri:setItemId(v.itemId) end)
                pcall(function() ri:setItemCount(tonumber(v.count) or 1) end)
                local countLbl = ri:recursiveGetChildById("rewardItemCount")
                if countLbl then
                    pcall(function() countLbl:setText("") end)
                end
                local item = ri:getItem()
                local iName = (getItemNameById and getItemNameById(v.itemId)) or ""
                if item then
                    iName = item:getName() or iName
                    pcall(function() ri:setFixedSize(not item:isWrapable()) end)
                end
                iName = (type(string.capitalize) == 'function' and string.capitalize(iName)) or iName
                pcall(function() ri:setTooltip(string.format("%dx %s", v.count or 1, iName)) end)
                if namesList ~= '' then
                    namesList = namesList .. ", " .. (v.count or 1) .. "x " .. iName
                else
                    namesList = (v.count or 1) .. "x " .. iName
                end
            end
            width = width + self.rewardWidthIncrement
            if v.stuck then stuck = true end
        end

        local message = "Você receberá os seguintes itens:"
        if stuck then
            message = message .. "\n[color=white]Os itens ficarão vinculados ao personagem.[/color]"
        end

        safeLabel(infoLabel, message)
        self.textReward = string.format("Você receberá os seguintes itens:\n%s", namesList)
    end

    local rewardCount = 0
    local i = 0
    while true do
        local widget = widgetsPanel:recursiveGetChildById("rewardSlot" .. i)
        if not widget then
            break
        end
        if widget:isVisible() then
            rewardCount = rewardCount + 1
        end
        i = i + 1
    end

    if rewardCount >= 6 then
        rewardsInfoPanel:setWidth(465)
    else
        rewardsInfoPanel:setWidth(math.min(430, width) + 10)
    end

    self.claimRewardWindow:setSize(tosize(500 .. " " .. normalHeight))

    if width <= 175 then
        rewardsInfoScrollBar:setVisible(false)
        rewardsInfoPanel:setImageSource("")
    end
    end) -- fim do pcall do populamento
    if not populateOk then
        print("[BattlePass] populate falhou: " .. tostring(populateErr))
        pcall(function() self.claimRewardWindow:setSize(tosize("500 250")) end)
    end

    -- Pós-populate: ajusta tamanho do painel e janela para o número real de
    -- itens visíveis, esconde a scrollbar quando não é necessária, e aplica
    -- glow dourado nos slots de item visíveis.
    pcall(function()
        local sb = self.claimRewardWindow:recursiveGetChildById("rewardsInfoScrollBar")
        local rp = self.claimRewardWindow:recursiveGetChildById("rewardsInfoPanel")
        if not sb or not rp then return end

        local visSlots = {}
        local idx = 0
        while true do
            local slot = rp:recursiveGetChildById("rewardSlot" .. idx)
            if not slot then break end
            if slot:isVisible() then
                visSlots[#visSlots + 1] = slot
            end
            idx = idx + 1
        end
        local visCount = #visSlots

        -- Corrige a largura do painel para garantir que o slot caiba inteiro
        -- (quando o pcall de populate falha, a largura fica em 80px e o slot
        -- de 66px + 9px de padding de cada lado = 84px mínimo necessário).
        -- borderExtra = 0: a borda de 2px é desenhada DENTRO do widget pelo
        -- OTClient, portanto não precisa de espaço extra no painel.
        local slotSize    = 66
        local cellSpacing = 10
        local panelPad    = 9   -- padding-left e padding-right do painel
        local neededWidth = slotSize * math.max(1, visCount)
                          + cellSpacing * math.max(0, visCount - 1)
                          + panelPad * 2
        rp:setWidth(math.min(465, neededWidth))

        -- Esconde scrollbar e remove fundo cinza extra para poucos itens.
        if visCount <= 2 then
            sb:setVisible(false)
            rp:setImageSource("")
            -- Encolhe o painel ao tamanho justo do slot (66px + 18px de padding).
            rp:setHeight(84)
            -- Reduz a altura total da janela proporcionalmente (95 -> 84 = 11px menos).
            local curW, curH = self.claimRewardWindow:getWidth(), self.claimRewardWindow:getHeight()
            local newH = math.max(180, curH - 11)
            self.claimRewardWindow:setSize(tosize(curW .. " " .. newH))
        end

        -- Glow dourado em cada slot visível.
        -- onFocusChange dispara ANTES do OTClient aplicar o estilo $focus,
        -- então usamos scheduleEvent(fn, 0) para recolocar a borda amarela
        -- no próximo tick do loop de eventos, DEPOIS que o $focus foi pintado.
local function applyGlow(widget)
    pcall(function()
        widget:setBorderWidth(2)
        widget:setBorderColor("#FFB800")
        widget:setBackgroundColor("#332400")
    end)
end

for _, slot in ipairs(visSlots) do
    pcall(function()
        applyGlow(slot)

        slot.onFocusChange = function(widget, focused)
            scheduleEvent(function()
                if widget and not widget:isDestroyed() then
                    applyGlow(widget)
                end
            end, 0)
        end

        slot.onHoverChange = function(widget, hovered)
            scheduleEvent(function()
                if widget and not widget:isDestroyed() then
                    applyGlow(widget)
                end
            end, 0)
        end
    end)
end
end)

    -- IMPORTANTE: NAO bloquear o input lock na janela de claim. Quando esse
    -- lock e ativado, os botoes Close/closeX nao recebem clique e a janela
    -- fica travada exigindo restart do cliente. O input lock so deve ser
    -- usado na janela de confirmacao (ConfirmReward).
end

function BattlePassRewards:onRedeemReward(index, internalRewardId, internalRewardType, objectId)
    if not g_game.isOnline() then
        return
    end
    g_game.redeemBattlePass(index, internalRewardId, objectId)
end


function BattlePassRewards:getRewardDescription(reward)
    if reward.rewardType == 1 then
        local itemName = getItemNameById(reward.itemId)
        return string.format("%dx %s", reward.count, string.capitalize(itemName))
    end

    return "Reward Type: " .. BattleRewardTypes[reward.rewardType]
end

function BattlePassRewards:getReward(index, rewardType)
    local isFreeReward = (rewardType == "free")
    for _, step in ipairs(BattlePass.rewardSteps) do
        if step.stepId == index then
            for _, reward in ipairs(step.rewards) do
                if isFreeReward and reward.freeReward then
                    return reward
                elseif not isFreeReward and not reward.freeReward then
                    return reward
                end
            end
        end
    end
    return nil
end
