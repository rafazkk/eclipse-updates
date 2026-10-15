-- Compatibility shim: some clients don't have g_client.setInputLockWidget.
-- Stub it as a no-op so the module works on both modern and older OTClients.
if not g_client then
    g_client = {}
end
if not g_client.setInputLockWidget then
    g_client.setInputLockWidget = function(widget) end
end

-- Resolução robusta dos tipos de recurso. Em otclients diferentes esses
-- globais podem ou não existir, então a gente fixa fallbacks numéricos
-- (BANK_BALANCE = 0, GOLD_EQUIPPED/inventário = 1 — padrão Canary/OTClient).
if not ResourceBank then
    ResourceBank = (ResourceTypes and (ResourceTypes.BANK_BALANCE or ResourceTypes.RESOURCE_BANK_BALANCE)) or 0
end
if not ResourceInventary then
    ResourceInventary = (ResourceTypes and (ResourceTypes.GOLD_EQUIPPED or ResourceTypes.RESOURCE_GOLD_EQUIPPED)) or 1
end
-- Tibia Coins (loja). Em Canary/OTC modernos: COIN_NORMAL=6, COIN_TRANSFERRABLE=7.
if not ResourceCoinNormal then
    ResourceCoinNormal = (ResourceTypes and (ResourceTypes.COIN_NORMAL or ResourceTypes.RESOURCE_COIN_NORMAL)) or 6
end
if not ResourceCoinTransferable then
    ResourceCoinTransferable = (ResourceTypes and (ResourceTypes.COIN_TRANSFERRABLE or ResourceTypes.COIN_TRANSFERABLE or ResourceTypes.RESOURCE_COIN_TRANSFERRABLE)) or 7
end

-- Compatibility helper: tenta vários métodos pra ler ouro do banco/inventário.
-- Cliente moderno usa getResourceBalance, alguns antigos usam getResourceValue.
local function safeGetResource(player, resource)
    if not player or resource == nil then return 0 end
    if type(player.getResourceBalance) == 'function' then
        local ok, v = pcall(player.getResourceBalance, player, resource)
        if ok and type(v) == 'number' then return v end
    end
    if type(player.getResourceValue) == 'function' then
        local ok, v = pcall(player.getResourceValue, player, resource)
        if ok and type(v) == 'number' then return v end
    end
    return 0
end

-- Cache local com os últimos valores recebidos via S_CoinBalance (onParseStoreGetCoin).
-- Em muitos servidores (Canary/OTX) o saldo de Tibia Coins NÃO é publicado via
-- ResourceTypes.COIN_NORMAL/COIN_TRANSFERRABLE, ele só chega pelo pacote da Store.
-- Por isso a leitura via getResourceBalance pode retornar 0 mesmo o player tendo coins.
local lastStoreTibiaCoins = nil
local lastStoreTransferCoins = nil

-- Tenta ler os valores que o módulo game_store já tem em tela (caso a Store
-- tenha sido aberta antes do BattlePass). É um fallback útil pra primeira abertura.
local function readCoinsFromStoreModule()
    if not modules or not modules.game_store then return nil, nil end
    local ctrl = modules.game_store.controllerShop
    if not ctrl or not ctrl.ui or not ctrl.ui.lblCoins then return nil, nil end

    local function extractNumber(text)
        if type(text) ~= 'string' then return nil end
        local n = text:match("%d[%d,]*")
        if not n then return nil end
        return tonumber((n:gsub("[^%d]", "")))
    end

    local lblNormal = ctrl.ui.lblCoins.lblTibiaCoins
    local lblTransfer = ctrl.ui.lblCoins.lblTibiaTransfer
    local n = lblNormal and extractNumber(lblNormal:getText()) or nil
    local t = lblTransfer and extractNumber(lblTransfer:getText()) or nil
    return n, t
end

-- ============================================================================
-- Ponte Cliente <-> Servidor via Extended Opcode (200)
-- O servidor (battlepass_handler.lua) responde a este opcode com payload
-- JSON contendo "action": "missions" ou "rewards".
-- O cliente envia "action": "request" / "reroll" / "claim" / "deluxe".
-- Tudo blindado em pcall pra nunca quebrar o load do módulo.
-- ============================================================================
local BATTLEPASS_EXT_OPCODE = 200

local function bpEncode(tbl)
    if type(json) == 'table' and type(json.encode) == 'function' then
        local ok, encoded = pcall(json.encode, tbl)
        if ok and type(encoded) == 'string' then return encoded end
    end
    -- fallback super simples (só pros campos que usamos)
    if not tbl or type(tbl) ~= 'table' then return '{}' end
    if tbl.action == 'request' then return '{"action":"request"}' end
    if tbl.action == 'deluxe' then return '{"action":"deluxe"}' end
    if tbl.action == 'reroll' then
        return string.format('{"action":"reroll","missionId":%d}', tonumber(tbl.missionId) or 0)
    end
    if tbl.action == 'claim' then
        return string.format('{"action":"claim","stepId":%d,"premium":%s}',
            tonumber(tbl.stepId) or 0, tostring(tbl.premium == true))
    end
    return '{}'
end

local function bpDecode(buffer)
    if type(json) == 'table' and type(json.decode) == 'function' then
        local ok, decoded = pcall(json.decode, buffer)
        if ok and type(decoded) == 'table' then return decoded end
    end
    return nil
end

local function bpSend(payload)
    if not g_game or not g_game.isOnline or not g_game.isOnline() then return end
    local protocolGame = g_game.getProtocolGame and g_game.getProtocolGame() or nil
    if not protocolGame or type(protocolGame.sendExtendedOpcode) ~= 'function' then return end
    pcall(function() protocolGame:sendExtendedOpcode(BATTLEPASS_EXT_OPCODE, payload) end)
end

if g_game then
    g_game.requestBattlePass = function(...)
        bpSend(bpEncode({ action = "request" }))
    end

    g_game.rerollBattlePassMission = function(missionId)
        bpSend(bpEncode({ action = "reroll", missionId = tonumber(missionId) or 0 }))
    end

    g_game.redeemBattlePass = function(stepId, rewardId, objectId)
        local isPremium = (rewardId == 2) -- 1 = free, 2 = premium
        bpSend(bpEncode({
            action = "claim", stepId = tonumber(stepId) or 0,
            premium = isPremium, objectId = objectId
        }))
    end

    g_game.activateBattlePassDeluxe = function()
        bpSend(bpEncode({ action = "deluxe" }))
    end
end

-- Listener: o servidor manda dados via opcode 200, decodificamos e
-- chamamos os callbacks já existentes (BattlePass.onBattlePassMissions/Rewards).
local function onBattlePassExtOpcode(protocol, opcode, buffer)
    if opcode ~= BATTLEPASS_EXT_OPCODE then return end
    if type(buffer) ~= 'string' or buffer == '' then return end
    local data = bpDecode(buffer)
    if not data then return end

    if data.action == "missions" and BattlePass and BattlePass.onBattlePassMissions then
        pcall(BattlePass.onBattlePassMissions,
            data.playerOutfit or {}, data.beginTime or 0, data.endTime or 0,
            data.points or 0, data.rerollPrice or 0, data.battlePassActive == true,
            data.currentRewardStep or 0, data.nextStepPoints or 1,
            data.dailyBeginTime or 0, data.dailyEndTime or 0,
            data.dailyMissions or {}, data.generalMissions or {},
            -- PASS DE EXPANSÃO (VIP): novos campos extras
            data.hasExpansion == true, data.expansionMissions or {}
        )
    elseif data.action == "rewards" and BattlePass and BattlePass.onBattlePassRewards then
        pcall(BattlePass.onBattlePassRewards, data.rewardSteps or {})
    end
end

if ProtocolGame and type(ProtocolGame.registerExtendedOpcode) == 'function' then
    pcall(ProtocolGame.registerExtendedOpcode, BATTLEPASS_EXT_OPCODE, onBattlePassExtOpcode)
end

if not BattlePass then
    BattlePass = {}
    BattlePass.__index = BattlePass

    BattlePass.window = nil
    BattlePass.missionPanel = nil
    BattlePass.progressPanel = nil
    BattlePass.outfitWidget = nil
    BattlePass.scrollBarWidget = nil
    BattlePass.dailyRerollWindow = nil

    BattlePass.beginTime = 1777334400  -- 28/abr/2026 00:00 UTC (ontem)
    BattlePass.endTime = 1782777600    -- 30/jun/2026 00:00 UTC (futuro)
    BattlePass.progressPoints = 0
    BattlePass.dailyRerollPrice = 0
    BattlePass.premiumBattlepass = false
    BattlePass.currentRewardStep = 0
    BattlePass.nextStepPoints = 0
    BattlePass.currentReward = 0
    BattlePass.dailyMissionsBegin = 0
    BattlePass.dailyMissionsExpire = 0
    BattlePass.dailyMissions = {}
    BattlePass.seassonMissions = {}

    BattlePass.isAnimatingWalk = false
    BattlePass.lastRewardStep = 0
    BattlePass.lastCameraPosition = 0

    -- Common variables
    BattlePass.rewardMinMargin = 195
    BattlePass.rewardMaxMargin = 18045
end

local function getMissionIndex(index)
    return MissionsDisplacement[index]
end

local function getOrdenedMissions(missions)
    local bronzeMissions = {}
    local silverMissions = {}
    local goldMissions = {}
    local orderedWithIndex = {}

    for _, mission in ipairs(BattlePass.seassonMissions) do
        if mission.rewardPoints == 100 then
            table.insert(bronzeMissions, mission)
        elseif mission.rewardPoints == 200 then
            table.insert(silverMissions, mission)
        elseif mission.rewardPoints == 300 then
            table.insert(goldMissions, mission)
        end
    end

    local bronzeIndex = 1
    local silverIndex = 1
    local goldIndex = 1

    for i, missionType in ipairs(MissionTypesOrder) do
        local indexDestino = MissionsDisplacement[i]
        local mission = nil

        if missionType == "bronze" and bronzeMissions[bronzeIndex] then
            mission = bronzeMissions[bronzeIndex]
            bronzeIndex = bronzeIndex + 1
        elseif missionType == "silver" and silverMissions[silverIndex] then
            mission = silverMissions[silverIndex]
            silverIndex = silverIndex + 1
        elseif missionType == "gold" and goldMissions[goldIndex] then
            mission = goldMissions[goldIndex]
            goldIndex = goldIndex + 1
        end

        if mission then
            table.insert(orderedWithIndex, { data = mission, index = indexDestino })
        end
    end
    return orderedWithIndex
end

local function getFormatedTime(dailyEndTime)
    local timeLeft = dailyEndTime - os.time()
    if timeLeft <= 0 then
        return "Expired", "Expired"
    end

    local days = math.floor(timeLeft / 86400)
    local hours = math.floor((timeLeft % 86400) / 3600)
    local minutes = math.floor((timeLeft % 3600) / 60)
    local seconds = timeLeft % 60

    local function formatUnit(value, singular, plural)
        return value == 1 and string.format("%d %s", value, singular) or string.format("%02d %s", value, plural)
    end

    local shortFormat, longFormat
    if days > 0 then
        shortFormat = formatUnit(days, "Day left", "Days left")
        longFormat = formatUnit(days, "Day", "Days") .. string.format(" and %02d hours left", hours)
    elseif hours > 0 then
        shortFormat = formatUnit(hours, "Hour left", "Hours left")
        longFormat = formatUnit(hours, "Hour", "Hours") .. string.format(" and %02d minutes left", minutes)
    elseif minutes > 0 then
        shortFormat = formatUnit(minutes, "Minute left", "Minutes left")
        longFormat = formatUnit(minutes, "Minute", "Minutes") .. string.format(" and %02d seconds left", seconds)
    else
        shortFormat = string.format("%02d Seconds left", seconds)
        longFormat = shortFormat
    end
    return shortFormat, longFormat
end

local function getTimeUntil(timestamp)
    local timeLeft = timestamp - os.time()
    if timeLeft <= 0 then
        return "00:00:00:00"
    end

    local days = math.floor(timeLeft / 86400)
    local hours = math.floor((timeLeft % 86400) / 3600)
    local minutes = math.floor((timeLeft % 3600) / 60)
    local seconds = timeLeft % 60
    return string.format("%02d:%02d:%02d:%02d", days, hours, minutes, seconds)
end

local function timerEvent(widget, endTime)
        if not widget or not widget:isVisible() or os.time() > endTime then
                return
        end

        widget:setText(BattlePass:running() and (string.format("New missions available in: %s", getTimeUntil(endTime))) or "                              Expired")
        scheduleEvent(function()
                timerEvent(widget, endTime)
        end, 1000)
end

function redirectToStore()
    BattlePass.window:hide()
    g_client.setInputLockWidget(nil)

    -- Em OTClient moderno (Mehah/v8/Canary) o jeito certo de abrir a Store
    -- eh chamar o modulo game_store. APIs antigas (g_game.openStore) podem
    -- nao existir. Tentamos varias formas em ordem de preferencia e a
    -- primeira que funcionar abre a loja.
    local opened = false

    -- 1) Modulo game_store moderno
    if not opened and modules and modules.game_store then
        local s = modules.game_store
        if type(s.show) == 'function' then
            local ok = pcall(s.show); if ok then opened = true end
        end
        if not opened and type(s.toggle) == 'function' then
            local ok = pcall(s.toggle); if ok then opened = true end
        end
        if not opened and type(s.open) == 'function' then
            local ok = pcall(s.open); if ok then opened = true end
        end
    end

    -- 2) Modulo game_shop (alguns servers usam esse nome)
    if not opened and modules and modules.game_shop then
        local s = modules.game_shop
        if type(s.show) == 'function' then
            local ok = pcall(s.show); if ok then opened = true end
        end
        if not opened and type(s.toggle) == 'function' then
            local ok = pcall(s.toggle); if ok then opened = true end
        end
    end

    -- 3) APIs antigas do g_game (compatibilidade)
    if not opened and g_game and type(g_game.openStore) == 'function' then
        local ok = pcall(g_game.openStore); if ok then opened = true end
        if opened and type(g_game.requestStoreOffers) == 'function' then
            pcall(g_game.requestStoreOffers, 3, "", 20)
        end
    end

    if not opened then
        -- Avisa o player que nao conseguiu abrir a loja
        if modules.game_textmessage and modules.game_textmessage.displayGameMessage then
            pcall(modules.game_textmessage.displayGameMessage,
                "Não foi possível abrir a Store. Verifique se o módulo game_store está ativo.")
        else
            print("[BattlePass] Não foi possível abrir a Store: módulo game_store/game_shop não encontrado.")
        end
    end
end

function init()
    -- The Battle Pass button is defined in modules/game_mainpanel/mainoptionspanel.otui
    -- and calls modules.game_battlepass.toggle() directly via @onClick.

    BattlePass.window = g_ui.displayUI('battlepass')
    BattlePass.window:hide()

    BattlePass.missionPanel = BattlePass.window:recursiveGetChildById('missionPanel')
    BattlePass.progressPanel = BattlePass.window:recursiveGetChildById('progressPanel')
    BattlePass.outfitWidget = BattlePass.window:recursiveGetChildById('playerOutfit')
    BattlePass.scrollBarWidget = BattlePass.window:recursiveGetChildById('progressPanelScrollBar')

    BattlePass.scrollBarWidget.canChangeValue = function()
        return not BattlePass.isAnimatingWalk
    end

    local progressPanelContent = BattlePass.window:recursiveGetChildById('progressPanelContent')
    if progressPanelContent then
        progressPanelContent.onMousePress = function(widget, mousePos, button)
            if button == MouseLeftButton and not BattlePass.isAnimatingWalk then
                BattlePass.isDragging = true
                BattlePass.dragStartX = mousePos.x
                BattlePass.dragStartScrollValue = BattlePass.scrollBarWidget:getValue()
            end
        end

        progressPanelContent.onMouseMove = function(widget, mousePos)
            if BattlePass.isDragging and not BattlePass.isAnimatingWalk then
                local deltaX = mousePos.x - BattlePass.dragStartX
                local scrollChange = -deltaX * 1.5 -- Adjust the multiplier for sensitivity
                local newScrollValue = BattlePass.dragStartScrollValue + scrollChange
                newScrollValue = math.max(BattlePass.scrollBarWidget:getMinimum(), math.min(newScrollValue, BattlePass.scrollBarWidget:getMaximum()))
                BattlePass.scrollBarWidget:setValue(newScrollValue)
            end
        end

        progressPanelContent.onMouseRelease = function(widget, mousePos, button)
            if button == MouseLeftButton then
                BattlePass.isDragging = false
            end
        end
    end

    g_keyboard.bindKeyPress('Tab', toggleNextWindow, BattlePass.window)

    loadMenu('challengesMenu')
    onCreateRewardContainers()

    connect(g_game, {
        onGameStart = online,
        onGameEnd = offline,
        onResourceBalance = onResourceBalance,
        onParseStoreGetCoin = onParseStoreGetCoin,
        onBattlePassMissions = BattlePass.onBattlePassMissions,
        onBattlePassRewards = BattlePass.onBattlePassRewards,
    })
end

function terminate()
    g_keyboard.unbindKeyPress('Tab', toggleNextWindow, BattlePass.window)

    if BattlePass.window then
        BattlePass.window:destroy()
        BattlePass.window = nil
    end

    disconnect(g_game, {
        onGameStart = online,
        onGameEnd = offline,
        onResourceBalance = onResourceBalance,
        onParseStoreGetCoin = onParseStoreGetCoin,
        onBattlePassMissions = BattlePass.onBattlePassMissions,
        onBattlePassRewards = BattlePass.onBattlePassRewards
    })
end

function toggle()
    if not BattlePass.window then
        return
    end

    if BattlePass.window:isVisible() then
        hide()
    else
        BattlePass:showBattlePass()
    end
end

function online()
    -- Load battlepass config
    BattlePass:loadConfigJson()
    BattlePass:loadPlayerPosition()

    -- Reset daily mission panel
    local dailyMissionsPanel = BattlePass.window:recursiveGetChildById('dailyMissionsBg')
    dailyMissionsPanel:destroyChildren()
    for i = 1, 2 do
        local widget = g_ui.createWidget('DailyMissionWidget', dailyMissionsPanel)
        local imageBackground = widget:recursiveGetChildById('dailyMissionIconImage')
        local image = i == 1 and 'daily-free-icon' or 'daily-vip-icon'
        imageBackground:setImageSource('/images/game/battlepass/' .. image)
    end

    -- Reset mission panel
    local missionsPanel = BattlePass.window:recursiveGetChildById('missionsBackground')
    missionsPanel:destroyChildren()
    for i = 1, 26 do
        g_ui.createWidget('MissionWidget', missionsPanel)
    end

    if BattlePassRewards.claimRewardWindow then
        BattlePassRewards.claimRewardWindow:destroy()
        BattlePassRewards.claimRewardWindow = nil
    end
end

function offline()
    hide()
    BattlePass.lastRewardStep = BattlePass.currentRewardStep
    BattlePass.lastCameraPosition = RewardPositions[BattlePass.currentRewardStep].scrollPosition
    BattlePass.outfitWidget:setMarginLeft(165)
    BattlePass:saveConfigJson()

    if BattlePassRewards.claimRewardWindow then
        BattlePassRewards.claimRewardWindow:destroy()
        BattlePassRewards.claimRewardWindow = nil
    end
end

function BattlePass:showBattlePass()
    BattlePass.window:show(true)
    BattlePass.window:raise()
    BattlePass.window:focus()
    g_client.setInputLockWidget(BattlePass.window)

    -- Pede ao servidor os dados do battle pass (missões + recompensas)
    -- assim que o módulo abre. Sem isso, tudo fica "Locked".
    if g_game and g_game.isOnline and g_game.isOnline() then
        pcall(function() g_game.requestBattlePass(0) end)
    end

    BattlePass.updateCoinsPanel()
end

function show()
    BattlePass.window:show(true)
    BattlePass.window:raise()
    BattlePass.window:focus()

    g_keyboard.bindKeyPress('Tab', toggleNextWindow, BattlePass.window)
    g_client.setInputLockWidget(BattlePass.window)
end

function hide()
    BattlePass.window:hide()
    g_client.setInputLockWidget(nil)
    g_keyboard.unbindKeyPress('Tab', toggleNextWindow, BattlePass.window)
end

function onCreateRewardContainers()
    local progressPanelContent = BattlePass.window:recursiveGetChildById('progressPanelContent')
    if not progressPanelContent then return end

    for i, data in ipairs(RewardPositions) do
        for rewardType, position in pairs(data.positions) do
            local rewardWidgetId = rewardType .. "RewardWidget" .. i
            local rewardWidget = g_ui.createWidget('RewardWidget', progressPanelContent)
            rewardWidget:setId(rewardWidgetId)
            rewardWidget:setMarginLeft(position.marginLeft)
            rewardWidget:setMarginTop(position.marginTop)
            rewardWidget:setVisible(false)

            local rewardBoxImage = rewardWidget:recursiveGetChildById("rewardBoxImage")
            if rewardType == "free" then
                rewardBoxImage:setImageSource("/images/game/battlepass/free-reward-chest")
                rewardBoxImage:setImageClip("30 32 29 31")
            else
                rewardBoxImage:setImageSource("/images/game/battlepass/vip-reward-chest")
                rewardBoxImage:setImageClip("30 32 29 31")
            end
            rewardBoxImage:setTooltip(string.format("Battle Pass %s Reward\nUnlocked at level %d", string.capitalize(rewardType), i))

            rewardWidget.rewardBox.onClick = function()
                BattlePass.scrollBarWidget:setValue(RewardPositions[i].scrollPosition)
                BattlePassRewards:onConfirmClaimReward(i, rewardType)
            end

            local blockedRewardId = rewardType .. "BlockedRewardWidget" .. i
            local blockedReward = g_ui.createWidget('BlockedRewardWidget', progressPanelContent)
            blockedReward:setId(blockedRewardId)
            blockedReward:setMarginLeft(position.marginLeft)
            blockedReward:setMarginTop(position.marginTop)
            blockedReward:setVisible(true)
            local lockedBoxImage = blockedReward:recursiveGetChildById("lockedBoxImage")
            if rewardType == "free" then
                lockedBoxImage:setImageSource("/images/game/battlepass/free-reward-chest")
            else
                lockedBoxImage:setImageSource("/images/game/battlepass/vip-reward-chest")
            end
            lockedBoxImage:setTooltip(string.format("Battle Pass %s Reward\nUnlock at level %d", string.capitalize(rewardType), i))
        end
    end
end

function loadMenu(menuId)
    local buttons = {
        challengesMenuButton = 'challengesMenu',
        expansionMenuButton  = 'expansionMenu',
        rewardsMenuButton    = 'rewardsMenu'
    }

    -- if menuId == 'challengesMenu' and not BattlePass:running() then
    --     menuId = 'rewardsMenu'
    -- end

    for buttonName, buttonId in pairs(buttons) do
        local button = BattlePass.window.mainPanel.optionsTabBar:getChildById(buttonId)
        if button then
            button:setChecked(false)
        end
    end

    local selectedButton = BattlePass.window.mainPanel.optionsTabBar:getChildById(menuId)
    if selectedButton then
        selectedButton:setChecked(true)
    end

    -- Guarda a aba ativa para o configureMissionPanel saber o que renderizar.
    BattlePass.activeMissionTab = menuId

    -- Contador de versão: invalida qualquer scheduleEvent pendente de uma
    -- troca de aba anterior (resolve o bug da "primeira parte sumida"
    -- quando o player volta de Rewards rápido para Challenges).
    BattlePass.tabSwitchVersion = (BattlePass.tabSwitchVersion or 0) + 1
    local thisSwitch = BattlePass.tabSwitchVersion

    if menuId == 'challengesMenu' then
        BattlePass.missionPanel:show(true)
        if g_game.isOnline() and BattlePass.progressPanel:isVisible() then
            local nextUnlock = BattlePass.getNextResetWeek(BattlePass.calculateWeekNumber())
            local unlockInfo = BattlePass.window:recursiveGetChildById("unlockInfo")
            timerEvent(unlockInfo, nextUnlock)
        end

        BattlePass.progressPanel:hide()
        BattlePass.window:setHeight(595)
        -- Re-renderiza o painel mostrando as missoes normais (daily + season).
        pcall(function() BattlePass:configureMissionPanel() end)
    elseif menuId == 'expansionMenu' then
        -- Aba VIP: mostra as missoes da expansao OU mensagem de bloqueado.
        BattlePass.missionPanel:show(true)
        BattlePass.progressPanel:hide()
        BattlePass.window:setHeight(595)
        pcall(function() BattlePass:configureMissionPanel() end)
    elseif menuId == 'rewardsMenu' then
        BattlePass.scrollBarWidget:setValue(BattlePass.lastCameraPosition)
        BattlePass.outfitWidget:setDirection(BattlePass.currentRewardStep == 0 and East or North)
        g_game.requestBattlePass(1)

        scheduleEvent(function()
            -- Se o player já trocou de aba, este evento é ignorado.
            if BattlePass.tabSwitchVersion ~= thisSwitch then return end
            BattlePass.missionPanel:hide()
            BattlePass.progressPanel:show(true)
            BattlePass.window:setHeight(515)
            -- Reseta posição e scroll para que a animação de caminhada sempre toque.
            BattlePass.scrollBarWidget:setValue(0)
            BattlePass.outfitWidget:setMarginLeft(BattlePass.rewardMinMargin)
            BattlePass.outfitWidget:setDirection(East)
            BattlePass:updatePlayerPosition()
        end, 50)
    end

    g_client.setInputLockWidget(BattlePass.window)
end

function toggleNextWindow()
    local widgetList = {
      "challengesMenu",
      "expansionMenu",
      "rewardsMenu"
    }

    local selectedIndex = nil
    for i, widget in ipairs(widgetList) do
      if widget == menuId then
        selectedIndex = i
        break
      end
    end

    if not selectedIndex then
        selectedIndex = 1
    end

    local nextWidgetId = (selectedIndex == #widgetList and 1 or selectedIndex + 1)
    menuId = widgetList[nextWidgetId]
    loadMenu(menuId)
end

function BattlePass.onBattlePassMissions(playerOutfit, beginTime, endTime, points, rerollPrice, battlePassActive, currentRewardStep, nextStepPoints, dailyBeginTime, dailyEndTime, dailyMissions, generalMissions, hasExpansion, expansionMissions)
    BattlePass.outfitWidget:setOutfit(playerOutfit)
    BattlePass.beginTime = beginTime
    BattlePass.endTime = endTime
    BattlePass.progressPoints = points
    BattlePass.dailyRerollPrice = rerollPrice
    BattlePass.premiumBattlepass = battlePassActive
    BattlePass.currentRewardStep = currentRewardStep
    BattlePass.nextStepPoints = nextStepPoints
    BattlePass.dailyMissionsBegin = dailyBeginTime
    BattlePass.dailyMissionsExpire = dailyEndTime

    BattlePass.dailyMissions = dailyMissions
    BattlePass.seassonMissions = generalMissions

    -- PASS DE EXPANSÃO (VIP)
    BattlePass.hasExpansion = hasExpansion == true
    BattlePass.expansionMissions = expansionMissions or {}

    local getVipPassTicketButton = BattlePass.window:recursiveGetChildById('getVipPassTicket')
    local getVipPassTicketBorder = BattlePass.window:recursiveGetChildById('getVipPassTicketBorder')
    if getVipPassTicketButton then
        getVipPassTicketButton:setVisible(false)
        getVipPassTicketBorder:setVisible(false)
    end

    BattlePass:configureMissionPanel()

    -- Reset player data in case of season ends
    if BattlePass.currentRewardStep == 0 then
        BattlePass.lastCameraPosition = 0
        BattlePass.lastRewardStep = 0
        BattlePass.outfitWidget:setMarginLeft(165)
        BattlePass.scrollBarWidget:setValue(0)
    end
end

function BattlePass.onBattlePassRewards(rewardSteps)
    BattlePass.rewardSteps = {}
    BattlePass.rewardSteps = rewardSteps
    BattlePass:configureRewardPanel()
end

function BattlePass.calculateWeekNumber()
    local targetTime = os.time()
    local begindate = os.time{year=os.date("*t", BattlePass.beginTime).year, month=os.date("*t", BattlePass.beginTime).month, day=os.date("*t", BattlePass.beginTime).day, hour=10, min=0, sec=0}
    local diffSeconds = os.difftime(targetTime, begindate)
    local diffDays = diffSeconds / 86400
    local weekNumber = diffDays / 7
    return math.ceil(weekNumber)
end

function BattlePass.getNextResetWeek(currentIndex)
    local nextDays = 7 * currentIndex
    local begindate = os.time{year=os.date("*t", BattlePass.beginTime).year, month=os.date("*t", BattlePass.beginTime).month, day=os.date("*t", BattlePass.beginTime).day, hour=10, min=0, sec=0}
    local nextResetTime = begindate + (nextDays * 86400)
    local tableDate = os.date("*t", nextResetTime)
    return os.time{year=tableDate.year, month=tableDate.month, day=tableDate.day, hour=10, min=0, sec=0}
end

function BattlePass:configureMissionPanel()
    -- IMPORTANTE: NAO abrir o modal automaticamente quando o servidor manda
    -- atualizacao (ex: apos um kill). Se a janela nao estiver visivel,
    -- apenas guardamos os dados em memoria; eles serao aplicados quando o
    -- player abrir o Battle Pass manualmente.
    if not BattlePass.window or not BattlePass.window:isVisible() then
        return
    end

    -- Current reward points (com proteção contra divisão por zero)
    -- Quando o player chega no level maximo, o servidor envia
    -- nextStepPoints = 0. Em vez de mostrar "8200/0", exibimos "MAX"
    -- e enchemos a barra de progresso ate 100%. Alem disso, o texto
    -- ganha uma cor DOURADA pra destacar a conquista de chegar no topo.
    BattlePass.window:recursiveGetChildById("playerLevel"):setText(BattlePass.currentRewardStep)
    local progressLabel
    local isMaxLevel = (not BattlePass.nextStepPoints or BattlePass.nextStepPoints <= 0)
    if isMaxLevel then
        progressLabel = string.format("%s / MAX", tostring(BattlePass.progressPoints or 0))
    else
        progressLabel = string.format("%s/%s", tostring(BattlePass.progressPoints or 0), tostring(BattlePass.nextStepPoints))
    end
    local progressTextWidget = BattlePass.window:recursiveGetChildById("currentlyLevelText")
    progressTextWidget:setText(progressLabel)
    -- Cor especial dourada quando atinge o nivel maximo, branca normal caso contrario.
    pcall(function()
        if isMaxLevel then
            progressTextWidget:setColor('#FFD700')
        else
            progressTextWidget:setColor('#FFFFFF')
        end
    end)
    local nextPts = (BattlePass.nextStepPoints and BattlePass.nextStepPoints > 0) and BattlePass.nextStepPoints or 1
    local pctValue = isMaxLevel and 100 or (BattlePass.progressPoints / nextPts * 100)
    BattlePass.window:recursiveGetChildById("levelProgress"):setPercent(pctValue)
    -- Tambem dourar o numero do nivel (playerLevel) quando estiver no MAX.
    pcall(function()
        local playerLevelWidget = BattlePass.window:recursiveGetChildById("playerLevel")
        if playerLevelWidget then
            if isMaxLevel then
                playerLevelWidget:setColor('#FFD700')
            else
                playerLevelWidget:setColor('#FFFFFF')
            end
        end
    end)

    -- BattlePass end time (com proteção contra divisão por zero)
    local seasonTotalTime = BattlePass.endTime - BattlePass.beginTime
    if seasonTotalTime <= 0 then seasonTotalTime = 1 end
    local timeRemaining = BattlePass.endTime - os.time()
    local seasonPercent = (timeRemaining / seasonTotalTime) * 100
    local seasonTimeText, seasonTimeTooltip = getFormatedTime(BattlePass.endTime)
    BattlePass.window:recursiveGetChildById("seasonTimeText"):setText(seasonTimeText)
    BattlePass.window:recursiveGetChildById("seasonHourglassIcon"):setTooltip(seasonTimeTooltip)
    BattlePass.window:recursiveGetChildById("seasonTimeProgress"):setPercent(seasonPercent)

    -- Next unlocked missions
    local nextUnlock = BattlePass.getNextResetWeek(BattlePass.calculateWeekNumber())
    local unlockInfo = BattlePass.window:recursiveGetChildById("unlockInfo")
    unlockInfo:setText(string.format("New missions available in: %s", getTimeUntil(nextUnlock)))
    timerEvent(unlockInfo, nextUnlock)

    -- Daily end time (com proteção contra divisão por zero)
    local dailyTotalTime = BattlePass.dailyMissionsExpire - BattlePass.dailyMissionsBegin
    if dailyTotalTime <= 0 then dailyTotalTime = 1 end
    local dailyTimeRemaining = BattlePass.dailyMissionsExpire - os.time()
    local dailyPercent = (dailyTimeRemaining / dailyTotalTime) * 100
    local dailyTimeText, dailyTimeTooltip = getFormatedTime(BattlePass.dailyMissionsExpire)
    BattlePass.window:recursiveGetChildById("dailyTimeText"):setText(dailyTimeText)
    BattlePass.window:recursiveGetChildById("hourglassIcon"):setTooltip(dailyTimeTooltip)
    BattlePass.window:recursiveGetChildById("dailyTimeProgress"):setPercent(dailyPercent)

    -- Daily Missions: popula em ordem direta e esconde os widgets sem dados,
    -- evitando que apareçam slots vazios com "?" / "Locked".
    local dailyMissionsPanel = BattlePass.window:recursiveGetChildById('dailyMissionsBg')
    local dailyTotal = dailyMissionsPanel:getChildCount()
    for slot = 1, dailyTotal do
        local w = dailyMissionsPanel:getChildByIndex(slot)
        if w then w:setVisible(false) end
    end

    for k, v in ipairs(BattlePass.dailyMissions or {}) do
        if k > dailyTotal then break end

        local widget = dailyMissionsPanel:getChildByIndex(k)
        if not widget then break end
        widget:setVisible(true)

        -- Nome da daily mission: aceita string vazia/nil sem deixar
        -- o label travado em "Locked". Se vier vazio, usa fallback
        -- "Daily 1/2" para garantir feedback visual ao player.
        local nameRaw = v.missionName
        if type(nameRaw) ~= "string" or nameRaw == "" then
            nameRaw = "Daily " .. k
        end
        local name = nameRaw
        local pts  = tonumber(v.rewardPoints) or 100
        local cur  = tonumber(v.currentProgress) or 0
        local mx   = tonumber(v.maxProgress) or 1
        if mx <= 0 then mx = 1 end
        local completed = cur >= mx

        -- Forca a atualizacao do nome FORA do pcall do setChildD para
        -- nao mascarar erros silenciosos: se o id "dailyMissionName"
        -- existir, o setText eh chamado direto.
        local nameLabel = widget:recursiveGetChildById("dailyMissionName")
        if nameLabel then nameLabel:setText(name) end

        local function setChildD(id, fn)
            local c = widget:recursiveGetChildById(id)
            if c then pcall(fn, c) end
        end
        setChildD("dailyMissionName",         function(c) c:setText(name) end)
        setChildD("dailyMissionPoints",       function(c) c:setText(tostring(pts)) end)
        setChildD("dailyMissionProgress",     function(c) c:setPercent(cur / mx * 100) end)
        setChildD("dailyMissionProgressText", function(c) c:setText(string.format("%s/%s", tostring(cur), tostring(mx))) end)
        setChildD("dailyMissionInformation",  function(c) c:setTooltip(tostring(v.missionDescription or "")) end)
        setChildD("dailyBlockedMissionIcon",  function(c) c:setVisible(false) end)
        setChildD("dailyFreeIcon",            function(c) c:setVisible(false) end)
        setChildD("dailyRerollButton",        function(c) c:setVisible(not completed) end)
        widget:recursiveGetChildById("dailyRerollButton").onClick = function() if not BattlePass:running() then return true end BattlePass:rerollDailyMission(v) end

        local icon = (k == 1 and "daily-free-icon" or "daily-vip-icon")
        if completed then
            icon = "daily-icon-complete"
        end

        widget:recursiveGetChildById("dailyMissionIconImage"):setImageSource("/images/game/battlepass/" .. icon)
        widget:recursiveGetChildById("dailyProgressPanel"):setVisible(not completed)
        widget:recursiveGetChildById("dailyCompletedIcon"):setVisible(completed)

        if not BattlePass:running() then
            widget:setEnabled(false)
            widget:setVisible(false)
        end

        -- Card da daily mission clicavel
        widget:setFocusable(true)
        widget.onClick = function()
            local desc = tostring(v.missionDescription or "")
            local nm   = tostring(v.missionName or "")
            local msg  = string.format("[%s] %s\nProgresso: %s/%s", nm, desc, tostring(cur), tostring(mx))
            if displayInfoBox then
                pcall(displayInfoBox, nm, msg)
            elseif modules.game_textmessage and modules.game_textmessage.displayGameMessage then
                pcall(modules.game_textmessage.displayGameMessage, msg)
            end
        end
    end

    -- General missions: COLOCACAO SEQUENCIAL.
    -- Ordenamos as missoes por tipo (bronze -> silver -> gold) e RECRIAMOS
    -- os widgets do zero a cada render. Isso evita o bug onde o grid layout
    -- nao reorganizava corretamente apos esconder/reexibir slots, deixando
    -- buracos no meio do painel a partir da 2a renderizacao. Ao destruir e
    -- criar exatamente N MissionWidgets em ordem, o grid de 13 colunas x 2
    -- linhas sempre empacota as missoes lado a lado, preenchendo a 1a linha
    -- primeiro e transbordando para a 2a quando passar de 13.
    local missionsPanel = BattlePass.window:recursiveGetChildById('missionsBackground')

    -- PASS DE EXPANSAO (VIP): escolhe a fonte das missoes pela aba ativa.
    --   * challengesMenu (default) -> missoes normais da season
    --   * expansionMenu            -> missoes VIP (so se o player desbloqueou)
    local activeTab = BattlePass.activeMissionTab or 'challengesMenu'
    local sourceMissions = BattlePass.seassonMissions or {}
    if activeTab == 'expansionMenu' then
        sourceMissions = BattlePass.expansionMissions or {}
    end

    -- Se a aba Expansao esta ativa mas o player NAO tem o pass de expansao,
    -- nao renderiza missoes -- mostra um aviso de bloqueado e um botao para
    -- abrir a Store onde o item de desbloqueio pode ser comprado.
    -- IMPORTANTE: sempre restaura o cellSize/cellSpacing/colunas DEFAULT do
    -- grid antes de renderizar qualquer coisa. Sem isso, se o player tiver
    -- aberto a aba Expansao bloqueada (que aumenta a celula para caber a
    -- mensagem), ao voltar para Challenges/Rewards o grid renderiza os
    -- badges com tamanho gigante/esticado.
    pcall(function()
        local layout = missionsPanel:getLayout()
        if layout then
            pcall(function() layout:setCellSize({ width = 104, height = 154 }) end)
            pcall(function() layout:setCellWidth(104) end)
            pcall(function() layout:setCellHeight(154) end)
            pcall(function() layout:setCellSpacing(3) end)
            pcall(function() layout:setNumColumns(13) end)
            pcall(function() layout:setNumLines(2) end)
        end
    end)

    -- PASS DE EXPANSAO BLOQUEADO: nao bloqueia mais a renderizacao -- a
    -- aba mostra os MESMOS badges das missoes VIP, mas com aparencia
    -- "locked" (cadeado, dim, sem progresso) para o player ver o que tem
    -- dentro antes de comprar. Apenas marca a flag pra reusar la embaixo.
    local expansionLocked = (activeTab == 'expansionMenu' and not BattlePass.hasExpansion)

    -- BANNER de aviso da Store: aparece flutuando no TOPO do painel de
    -- missoes apenas quando a aba Expansao esta bloqueada. Eh criado no
    -- PAI do missionsPanel (nao dentro dele) pra nao cair no grid layout
    -- e bagunçar a posicao dos badges. Em qualquer outra aba ele eh
    -- destruido pra nao aparecer indevidamente.
    pcall(function()
        local parent = missionsPanel:getParent()
        if parent then
            local oldBanner = parent:getChildById('expansionLockedBanner')
            if oldBanner then pcall(function() oldBanner:destroy() end) end
            if expansionLocked then
                local banner = g_ui.createWidget('Label', parent)
                if banner then
                    banner:setId('expansionLockedBanner')
                    pcall(function() banner:setText("PASSE DE EXPANSAO BLOQUEADO  -  Adquira o Expansion na Store para liberar missoes exclusivas e ganhar pontos extras no seu Passe de Batalha.") end)
                    pcall(function() banner:setTextAlign(AlignCenter) end)
                    pcall(function() banner:setTextWrap(true) end)
                    pcall(function() banner:setFont('verdana-11px-rounded') end)
                    pcall(function() banner:setColor('#FFD700') end)
                    pcall(function() banner:setBackgroundColor('#000000C8') end)
                    pcall(function() banner:setHeight(38) end)
                    pcall(function() banner:addAnchor(AnchorTop,   'missionsBackground', AnchorTop)   end)
                    pcall(function() banner:addAnchor(AnchorLeft,  'missionsBackground', AnchorLeft)  end)
                    pcall(function() banner:addAnchor(AnchorRight, 'missionsBackground', AnchorRight) end)
                    pcall(function() banner:setMarginTop(3) end)
                    pcall(function() banner:setMarginLeft(3) end)
                    pcall(function() banner:setMarginRight(3) end)
                    pcall(function() banner:setFocusable(true) end)
                    pcall(function() banner:raise() end)
                    banner.onClick = function() pcall(redirectToStore) end
                end
            end
        end
    end)

    -- 1) Separa por tipo e monta a lista ordenada (bronze, silver, gold).
    local bronzeMissions, silverMissions, goldMissions = {}, {}, {}
    for _, m in ipairs(sourceMissions) do
        local pts = tonumber(m.rewardPoints) or 100
        if pts >= 300 then
            table.insert(goldMissions, m)
        elseif pts >= 200 then
            table.insert(silverMissions, m)
        else
            table.insert(bronzeMissions, m)
        end
    end
    local ordered = {}
    for _, m in ipairs(bronzeMissions) do table.insert(ordered, m) end
    for _, m in ipairs(silverMissions) do table.insert(ordered, m) end
    for _, m in ipairs(goldMissions)   do table.insert(ordered, m) end

    -- 2) Apaga TODOS os slots existentes do painel para garantir que o
    --    grid layout reorganize do zero.
    pcall(function() missionsPanel:destroyChildren() end)

    -- 2.1) Ajusta APENAS o numero de colunas/linhas do grid para que as
    --      missoes fiquem em 2 linhas. NAO mexer no cellSize nem no
    --      cellSpacing -- esses valores sao definidos no .otui (104x154)
    --      e o layout interno de cada MissionWidget (nome + barra de
    --      progresso) foi desenhado pra esse tamanho exato. Esticar a
    --      celula faz o nome e o texto de progresso se sobreporem.
    local missionCount = #ordered
    if missionCount > 0 then
        pcall(function()
            local cols = math.max(1, math.ceil(missionCount / 2))
            local layout = missionsPanel:getLayout()
            if layout then
                pcall(function() layout:setNumColumns(cols) end)
                pcall(function() layout:setNumLines(2) end)
            end
        end)
    end

    -- 3) Cria um MissionWidget novo para CADA missao da lista ordenada.
    --    O grid layout cuida da posicao automaticamente.
    for i, data in ipairs(ordered) do
        local widget = g_ui.createWidget('MissionWidget', missionsPanel)
        if widget then
            pcall(function()
                    widget:setVisible(true)
                    pcall(function() widget:setEnabled(true) end)
                    pcall(function() widget:setImageSource("/images/game/battlepass/missionBg") end)
                    local name = tostring(data.missionName or "")
                    local pts  = tonumber(data.rewardPoints) or 100
                    local cur  = tonumber(data.currentProgress) or 0
                    local mx   = tonumber(data.maxProgress) or 1
                    if mx <= 0 then mx = 1 end

                    -- Missao bloqueada quando a aba Expansao esta ativa e o
                    -- player nao tem o pass, OU quando o servidor marcou
                    -- explicitamente a missao com locked=true.
                    local isLocked = expansionLocked or (data.locked == true)

                    local function setChild(id, fn)
                        local c = widget:recursiveGetChildById(id)
                        if c then pcall(fn, c) end
                    end

                    setChild("missionPanel",       function(c) c:setVisible(true) end)
                    setChild("missionName",        function(c) c:setVisible(true) c:setText(name) end)
                    setChild("missionPoints",      function(c) c:setVisible(true) c:setText(tostring(pts)) end)
                    setChild("missionInformation", function(c) c:setVisible(true) c:setTooltip(tostring(data.missionDescription or "")) end)

                    if isLocked then
                        -- BADGE BLOQUEADO (preview): mostra nome + icone do
                        -- rank pro player ver o que tem dentro do pass, sem
                        -- barra de progresso. O overlay blockPattern fica
                        -- bem TRANSPARENTE (opacity 0.35) pra dar a sensacao
                        -- de "bloqueado" sem cobrir o texto do nome embaixo.
                        -- Click no card abre a Store.
                        setChild("missionProgress",     function(c) c:setVisible(false) end)
                        setChild("missionProgressText", function(c) c:setVisible(false) end)
                        setChild("progressPanel",       function(c) c:setVisible(false) end)
                        setChild("completedIcon",       function(c) c:setVisible(false) end)
                        setChild("missionIconImage",    function(c) c:setVisible(true) end)
                        -- Na aba Expansao bloqueada usamos sempre o gold-icon
                        -- pra reforcar o tema VIP/premium do passe de expansao.
                        local rankIcon = expansionLocked and "gold-icon" or (MissionRankIcons[pts] or MissionRankIcons[100] or "bronze-icon")
                        setChild("missionIconImage", function(c) c:setImageSource("/images/game/battlepass/" .. rankIcon) end)

                        -- Overlay de cadeado: visivel mas bem translucido pra
                        -- nao tampar o nome / icone do rank.
                        setChild("blockedMissionIcon", function(c)
                            c:setVisible(true)
                            pcall(function() c:setOpacity(0.35) end)
                            -- garante que ele fique ATRAS do nome (caso o z
                            -- order tenha sido alterado em runs anteriores)
                            pcall(function() c:lower() end)
                        end)

                        -- Tom levemente escurecido pra reforcar o "bloqueado"
                        -- sem matar a legibilidade.
                        pcall(function() widget:setColor('#B0B0B0FF') end)
                        setChild("missionName",   function(c) c:setColor('#FFD27F') end)
                        setChild("missionPoints", function(c) c:setColor('#FFD27F') end)

                        widget:setFocusable(true)
                        widget.onClick = function()
                            local msg = string.format("[BLOQUEADO] %s\n\n%s\n\nAdquira o Pass de Expansao na Store para desbloquear esta missao VIP.", name, tostring(data.missionDescription or ""))
                            if displayInfoBox then
                                pcall(displayInfoBox, "Pass de Expansao", msg)
                            end
                            pcall(redirectToStore)
                        end
                    else
                        -- Renderizacao NORMAL (Challenges / Expansion liberado)
                        setChild("missionProgress",    function(c) c:setVisible(true) c:setPercent(cur / mx * 100) end)
                        setChild("missionProgressText",function(c) c:setVisible(true) c:setText(string.format("%s/%s", tostring(cur), tostring(mx))) end)
                        setChild("blockedMissionIcon", function(c) c:setVisible(false) end)
                        setChild("missionIconImage",   function(c) c:setVisible(true) end)

                        local completed = cur >= mx
                        local rankIcon = MissionRankIcons[pts] or MissionRankIcons[100] or "bronze-icon"
                        local missionIcon = completed and (rankIcon .. "-complete") or rankIcon
                        setChild("missionIconImage", function(c) c:setImageSource("/images/game/battlepass/" .. missionIcon) end)
                        setChild("progressPanel",    function(c) c:setVisible(not completed) end)
                        setChild("completedIcon",    function(c) c:setVisible(completed) end)

                        widget:setFocusable(true)
                        widget.onClick = function()
                            local msg = string.format("[%s] %s\nProgresso: %s/%s", name, tostring(data.missionDescription or ""), tostring(cur), tostring(mx))
                            if displayInfoBox then
                                pcall(displayInfoBox, name, msg)
                            elseif modules.game_textmessage and modules.game_textmessage.displayGameMessage then
                                pcall(modules.game_textmessage.displayGameMessage, msg)
                            end
                        end
                    end
                end)
        end
    end
end


function BattlePass:configureRewardPanel()
    local rewardPanel = BattlePass.window:recursiveGetChildById('progressPanelContent')
    if not rewardPanel then
        return
    end

    for k, v in ipairs(BattlePass.rewardSteps) do
        for i, reward in ipairs(v.rewards) do
            local rewardType = reward.freeReward and "free" or "premium"
            local rewardWidget = rewardPanel:getChildById(rewardType .. "RewardWidget" .. v.stepId)
            local blockedReward = rewardPanel:getChildById(rewardType .. "BlockedRewardWidget" .. v.stepId)
            -- Nem todo step tem widget para os dois tipos (free/premium): o layout
            -- definido em RewardPositions cria caixas free apenas em alguns niveis.
            -- Se o widget correspondente nao existir, pulamos esse reward em vez de
            -- estourar :setVisible() em nil (o que abortaria o loop dentro do pcall
            -- e deixaria todas as caixas no estado padrao = trancadas).
            if rewardWidget and blockedReward then
                local isStepReached = v.stepId <= BattlePass.currentRewardStep
                local isPremiumOk = reward.freeReward or BattlePass.premiumBattlepass
                local availableReward = isStepReached and isPremiumOk
                if availableReward then
                    blockedReward:setVisible(false)
                    rewardWidget:setVisible(true)
                else
                    blockedReward:setVisible(true)
                    rewardWidget:setVisible(false)
                end

                local enabled = not reward.hasClamedReward
                local text = reward.hasClamedReward and "Claimed" or "Claim Reward"

                rewardWidget:recursiveGetChildById("collectRewardLabel"):setText(text)
                rewardWidget:recursiveGetChildById("rewardBox"):setEnabled(enabled)
                local rewardBoxImage = rewardWidget:recursiveGetChildById("rewardBoxImage")
                if reward.hasClamedReward then
                    if rewardType == "free" then
                        rewardBoxImage:setImageSource("/images/game/battlepass/free-reward-chest-open")
                        rewardBoxImage:setImageClip("26 22 38 42")
                        rewardBoxImage:setSize("38 42")
                        rewardBoxImage:setMarginTop(-10)
                    else
                        rewardBoxImage:setImageSource("/images/game/battlepass/vip-reward-chest-open")
                        rewardBoxImage:setImageClip("24 20 40 44")
                        rewardBoxImage:setSize("40 44")
                        rewardBoxImage:setMarginTop(-12)
                    end
                else
                    if rewardType == "free" then
                        rewardBoxImage:setImageSource("/images/game/battlepass/free-reward-chest")
                        rewardBoxImage:setImageClip("30 32 29 31")

                    else
                        rewardBoxImage:setImageSource("/images/game/battlepass/vip-reward-chest")
                        rewardBoxImage:setImageClip("30 32 29 31")
                    end
                end
                local rewardTypeText = reward.freeReward and "Free" or "Deluxe"
                rewardBoxImage:setTooltip(string.format("Battle Pass %s Reward\n%s at level %d", string.capitalize(rewardTypeText), (reward.hasClamedReward and "Claimed" or "Unlocked"), v.stepId))

                -- Set lockedBoxImage for blocked rewards (always closed chest)
                local lockedBoxImage = blockedReward:recursiveGetChildById("lockedBoxImage")
                if rewardType == "free" then
                    lockedBoxImage:setImageSource("/images/game/battlepass/free-reward-chest")
                else
                    lockedBoxImage:setImageSource("/images/game/battlepass/vip-reward-chest")
                end
                lockedBoxImage:setTooltip(string.format("Battle Pass %s Reward\nUnlock at level %d", string.capitalize(rewardTypeText), v.stepId))
            end
        end
    end
end

function BattlePass:getStepsToReward(rewardStep)
    local stepsToReward = 0
    for i, data in ipairs(RewardPositions) do
        if i <= rewardStep then
            stepsToReward = stepsToReward + data.stepsTo
        end
    end
    return stepsToReward
end

function BattlePass:loadPlayerPosition()
    -- First execution
    local stepsToReward = BattlePass:getStepsToReward(BattlePass.lastRewardStep)
    if stepsToReward == 0 then
        return
    end

    local newProgress = BattlePass.rewardMinMargin + stepsToReward * 32
    local playerProgress = math.max(BattlePass.rewardMinMargin, math.min(newProgress, BattlePass.rewardMaxMargin))

    BattlePass.outfitWidget:setMarginLeft(playerProgress)
    BattlePass.scrollBarWidget:setValue(BattlePass.lastCameraPosition)
end

function BattlePass:updatePlayerPosition()
    local stepsToReward = BattlePass:getStepsToReward(BattlePass.currentRewardStep)
        local newProgress = BattlePass.rewardMinMargin + stepsToReward * 32
        local playerProgress = math.max(BattlePass.rewardMinMargin, math.min(newProgress, BattlePass.rewardMaxMargin))

    if playerProgress > 195 then
        BattlePass.lastCameraPosition = RewardPositions[BattlePass.lastRewardStep].scrollPosition
        BattlePass:doAnimatePlayerMove(playerProgress)
    end

    -- Force save data
    BattlePass:saveConfigJson()
end

function BattlePass:running()
    local timeLeft = BattlePass.endTime - os.time()
    if timeLeft <= 0 then
        return false
    end

    return true
end

function BattlePass:doAnimatePlayerMove(targetMargin)
    if targetMargin == BattlePass.outfitWidget:getMarginLeft() then
        return
    end

    local player = g_game.getLocalPlayer()
    pcall(function() BattlePass.outfitWidget:setDirection(East) end)
    pcall(function() BattlePass.outfitWidget:setAnimate(true) end)
    pcall(function() BattlePass.outfitWidget:setIdleAnimate(false) end)
    pcall(function() BattlePass.outfitWidget:setStaticWalking(true) end)

    BattlePass.isAnimatingWalk = true
    local currentMargin = BattlePass.outfitWidget:getMarginLeft()
    local scrollBar = BattlePass.scrollBarWidget

    local function finishAnimation()
        BattlePass.outfitWidget:setMarginLeft(targetMargin)
        pcall(function() BattlePass.outfitWidget:setAnimate(false) end)
        pcall(function() BattlePass.outfitWidget:setStaticWalking(false) end)
        pcall(function() BattlePass.outfitWidget:setIdleAnimate(true) end)
        BattlePass.isAnimatingWalk = false
        BattlePass.lastRewardStep = BattlePass.currentRewardStep
        BattlePass.lastCameraPosition = RewardPositions[BattlePass.currentRewardStep].scrollPosition

        -- Force save data
        BattlePass:saveConfigJson()

        scheduleEvent(function()
            BattlePass.outfitWidget:setDirection(North)
        end, 150)
    end

    local function animateStep()
        if not BattlePass.outfitWidget:isVisible() then
            finishAnimation()
            return true
        end

        if currentMargin < targetMargin then
            currentMargin = math.min(currentMargin + 3, targetMargin)
            BattlePass.outfitWidget:setMarginLeft(currentMargin)
            if currentMargin < targetMargin then
                scheduleEvent(animateStep, 25)
                if currentMargin >= 350 then
                    scrollBar:setValue(scrollBar:getValue() + 3)
                end
            else
                finishAnimation()
            end
        else
            finishAnimation()
        end
    end

    animateStep()
end

function BattlePass:loadConfigJson()
    if not LoadedPlayer:isLoaded() then return end

    local file = "/characterdata/" .. LoadedPlayer:getId() .. "/battlepass.json"
    if g_resources.fileExists(file) then
        local status, result = pcall(function()
            return json.decode(g_resources.readFileContents(file))
        end)

        if not status then
            return g_logger.error("Error while reading characterdata file. Details: " .. result)
        end

        BattlePass.lastRewardStep = result.currentRewardStep or 0
        BattlePass.lastCameraPosition = result.lastCameraPosition or 0
    else
        BattlePass.lastRewardStep = 0
        BattlePass.lastCameraPosition = 0
    end
end

function BattlePass:saveConfigJson()
        local config = { currentRewardStep = BattlePass.lastRewardStep, lastCameraPosition = BattlePass.lastCameraPosition }
        if not LoadedPlayer:isLoaded() then return end

        local file = "/characterdata/" .. LoadedPlayer:getId() .. "/battlepass.json"
        local status, result = pcall(function() return json.encode(config, 2) end)
        if not status then
                return g_logger.error("Error while saving profile Battlepass data. Data won't be saved. Details: " .. result)
        end

        if result:len() > 100 * 1024 * 1024 then
                return g_logger.error("Something went wrong, file is above 100MB, won't be saved")
        end
        g_resources.writeFileContents(file, result)
end

function BattlePass:rerollDailyMission(data)
    if BattlePass.dailyRerollWindow then
        BattlePass.dailyRerollWindow:destroy()
    end

    local player = g_game.getLocalPlayer()
    if not player then
        return
    end

    BattlePass.window:hide()

    local okButton = function()
        BattlePass.dailyRerollWindow:destroy()
        BattlePass.dailyRerollWindow = nil
        g_client.setInputLockWidget(nil)
        g_game.rerollBattlePassMission(data.missionId)
    end

    local cancelButton = function()
        BattlePass.dailyRerollWindow:destroy()
        BattlePass.dailyRerollWindow = nil
        BattlePass:showBattlePass()
        g_client.setInputLockWidget(BattlePass.window)
    end

    local message = {}
    setStringColor(message, string.format("Are you sure you want to reroll the mission %s for %s", data.missionName, comma_value(BattlePass.dailyRerollPrice * player:getLevel())), "#c0c0c0")
    setStringColor(message, " $", "#f7e6fe")
    setStringColor(message, " ?", "#c0c0c0")

    BattlePass.dailyRerollWindow = displayGeneralBox(tr('Confirm mission reroll'), message, {
        { text=tr('Ok'), callback = okButton },
        { text=tr('Cancel'), callback = cancelButton },
    }, okButton, cancelButton)

    BattlePass.dailyRerollWindow:recursiveGetChildById('messageBoxLabel'):setFont("Verdana Bold-11px-wheel")
    g_client.setInputLockWidget(BattlePass.dailyRerollWindow)
end

-- Atualiza o painel inferior esquerdo com saldo de Tibia Coins (total) e
-- Transferable Coins (incluindo). Mesmo padrão visual da Store.
--
function BattlePass.updateCoinsPanel()
    if not BattlePass.window then return end
    local lblTibiaCoins = BattlePass.window:recursiveGetChildById('lblTibiaCoins')
    local lblTibiaTransfer = BattlePass.window:recursiveGetChildById('lblTibiaTransfer')
    if not lblTibiaCoins and not lblTibiaTransfer then return end

    local coinNormal, coinTransfer

    -- 1) Cache do pacote onParseStoreGetCoin
    if lastStoreTibiaCoins and lastStoreTibiaCoins > 0 then coinNormal = lastStoreTibiaCoins end
    if lastStoreTransferCoins and lastStoreTransferCoins >= 0 and lastStoreTibiaCoins then coinTransfer = lastStoreTransferCoins end

    -- 2) getCoinsBalance() do próprio módulo game_store (mesma função usada pela Store)
    if (not coinNormal or coinNormal == 0) and modules and modules.game_store then
        local ok, n, t = pcall(function()
            if type(modules.game_store.getCoinsBalance) == 'function' then
                return modules.game_store.getCoinsBalance()
            end
        end)
        if ok and type(n) == 'number' and n > 0 then coinNormal = n end
        if ok and type(t) == 'number' and t >= 0 then coinTransfer = t end
    end

    -- 3) getResourceBalance direto via ResourceTypes
    --    (idêntico ao fixServerNoSend0xF2 do game_store que sabidamente funciona)
    local player = g_game.getLocalPlayer()
    if player and ResourceTypes then
        if not coinNormal or coinNormal == 0 then
            local ok, v = pcall(function()
                return player:getResourceBalance(ResourceTypes.COIN_NORMAL)
            end)
            if ok and type(v) == 'number' and v > 0 then coinNormal = v end
        end
        if not coinTransfer then
            local ok, v = pcall(function()
                return player:getResourceBalance(ResourceTypes.COIN_TRANSFERRABLE)
            end)
            if ok and type(v) == 'number' then coinTransfer = v end
        end
    end

    coinNormal = coinNormal or 0
    coinTransfer = coinTransfer or 0

    if lblTibiaCoins then
        lblTibiaCoins:setText(comma_value(coinNormal))
        lblTibiaCoins:setTooltip("Tibia Coins")
    end
    if lblTibiaTransfer then
        lblTibiaTransfer:setText(string.format("(Including: %s", comma_value(coinTransfer)))
        lblTibiaTransfer:setTooltip("Transferable Tibia Coins")
    end
end

function onResourceBalance(resourceType, value)
    if resourceType == ResourceCoinNormal then
        lastStoreTibiaCoins = tonumber(value) or lastStoreTibiaCoins
    elseif resourceType == ResourceCoinTransferable then
        lastStoreTransferCoins = tonumber(value) or lastStoreTransferCoins
    end
    if not BattlePass.window or not BattlePass.window:isVisible() then
        return
    end
    BattlePass.updateCoinsPanel()
end

-- Handler do pacote da Store (S_CoinBalance / 0xDF). Mesma assinatura usada
-- por modules/game_store/game_store.lua. Atualiza o cache e o painel.
function onParseStoreGetCoin(getTibiaCoins, getTransferableCoins)
    lastStoreTibiaCoins = tonumber(getTibiaCoins) or lastStoreTibiaCoins
    lastStoreTransferCoins = tonumber(getTransferableCoins) or lastStoreTransferCoins
    if BattlePass.window and BattlePass.window:isVisible() then
        BattlePass.updateCoinsPanel()
    end
end
