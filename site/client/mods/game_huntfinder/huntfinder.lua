HuntFinder = {
  widget = nil,
  searchInputBox = nil,
  teamSizeBox = nil,
  filterBox = nil,
  listPanel = nil,
  huntInfoPanel = nil,
  vocationFilter = nil,

  vocation = "Knight",
  teamSize = "Solo",
  level = 1,
  sortType = 1,
}

-- Extended opcode used to fetch full monster combat data for ANY creature, bypassing the
-- bestiary unlock/kill gate (and without touching the cyclopedia bestiary state). Handled
-- server-side by data/scripts/systems/huntfinder_monster_info.lua. Exposed on the shared
-- HuntFinder table so classes/huntinfopanel.lua sends the same opcode.
HuntFinder.MONSTER_INFO_OPCODE = 181
local OPCODE_HUNTFINDER_MONSTER_INFO = HuntFinder.MONSTER_INFO_OPCODE

local function setHuntFinderButtonActive(active)
  local button = HuntFinder.topMenuButton
  if not button or button:isDestroyed() then
    return
  end

  local imageClip = active and "0 20 20 20" or "0 0 20 20"
  pcall(function()
    button:setOn(active)
    button:setImageClip(imageClip)
  end)
end

-- Polyfill for string.todivide
function string.todivide(str, max)
    local new = ""
    local count = 0
    for word in string.gmatch(str, "%S+") do
        count = count + 1
        if count > max then
            new = new .. "\n"
            count = 1
        end
        new = new .. (count == 1 and "" or " ") .. word
    end
    return new
end

function HuntFinder.init()
  HuntFinder.widget = g_ui.displayUI('styles/huntfinder')
  if not HuntFinder.widget then
    print("[game_huntfinder] Could not load styles/huntfinder.otui; HuntFinder UI was not created.")
    return
  end
  HuntFinder.widget:hide()

  HuntFinder.searchInputBox = HuntFinder.widget:recursiveGetChildById('searchInputBox')
  HuntFinder.teamSizeBox = HuntFinder.widget:recursiveGetChildById('teamSizeBox')
  HuntFinder.filterBox = HuntFinder.widget:recursiveGetChildById('filterBox')

  HuntFinder.listPanel = HuntFinder.widget:recursiveGetChildById('listPanel')
  HuntFinder.huntInfoPanel = HuntFinder.widget:recursiveGetChildById('huntInfoPanel')
  HuntFinder.backButton = HuntFinder.widget:recursiveGetChildById('backButton')
  HuntFinder.closeButton = HuntFinder.widget:recursiveGetChildById('closeButton')
  HuntFinder.separator = HuntFinder.widget:recursiveGetChildById('separator')
  HuntFinder.mainPanel = HuntFinder.widget:recursiveGetChildById('mainPanel')
  HuntFinder.vocationFilter = HuntFinder.widget:recursiveGetChildById('vocationBox')
  HuntFinder.searchText = HuntFinder.widget:recursiveGetChildById('searchText')
  HuntFinder.searchIcon = HuntFinder.widget:recursiveGetChildById('searchIcon')

  -- Snapshot the original separator size so we can restore it when going back to the list
  -- view. The hunt info view stretches the separator across the hunt info panel and pins the
  -- Close/Back buttons to its right edge instead of the parent window's right edge.
  if HuntFinder.separator then
    HuntFinder.separatorOriginalWidth = HuntFinder.separator:getWidth()
  end

  if HuntFinder.searchText then
    HuntFinder.searchText.onTextChange = function(widget, text)
      HuntFinder.searchQuery = text:len() > 0 and text:lower() or nil
      if HuntFinder.searchIcon then
        HuntFinder.searchIcon:setEnabled(text:len() > 0)
      end
      HuntFinder:showListPanel()
      ListPanel:displayHunts()
    end
  end

  HuntConfig:loadJson()
  connect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = offline,
    onMonsterInfo = onMonsterInfo,
    onUpdateBestiaryMonsterData = onBestiaryData,
  })

  -- Dedicated monster-info feed (see OPCODE_HUNTFINDER_MONSTER_INFO). Replaces the bestiary
  -- search fallback so the info panel works for un-hunted creatures too.
  ProtocolGame.registerExtendedOpcode(OPCODE_HUNTFINDER_MONSTER_INFO, onMonsterInfoOpcode)

  HuntFinder.topMenuButton = modules.client_topmenu.addLeftGameButton('huntFinderButton', tr('Hunt Finder'), '/images/topbuttons/huntfinder-mini', toggle)
  if HuntFinder.topMenuButton then
    HuntFinder.topMenuButton.onStyleApply = function()
      local button = HuntFinder.topMenuButton
      if not button or button:isDestroyed() then
        return
      end

      local active = HuntFinder.widget and HuntFinder.widget:isVisible()
      button:setImageClip(active and "0 20 20 20" or "0 0 20 20")
    end
  end
  setHuntFinderButtonActive(false)
end

function toggle()
  if not HuntFinder.widget then
    return
  end
  if HuntFinder.widget:isVisible() then
    hide()
  else
    show()
  end
end

function HuntFinder.terminate()
  disconnect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = offline,
    onMonsterInfo = onMonsterInfo,
  })

  ProtocolGame.unregisterExtendedOpcode(OPCODE_HUNTFINDER_MONSTER_INFO)

  ListPanel:clear()
  MapFinder:clear()
  HuntInfo:clear()
  if HuntFinder.widget then
    HuntFinder.widget:destroy()
    HuntFinder.widget = nil
  end

  HuntFinder.searchInputBox = nil
  HuntFinder.teamSizeBox = nil
  HuntFinder.filterBox = nil
  HuntFinder.listPanel = nil
  HuntFinder.huntInfoPanel = nil
  HuntFinder.vocationFilter = nil
  
  if HuntFinder.topMenuButton then
    HuntFinder.topMenuButton:destroy()
    HuntFinder.topMenuButton = nil
  end
end

function HuntFinder:setVocation(vocation)
  HuntFinder.vocation = vocation
  HuntFinder:showListPanel()
  ListPanel:displayHunts()
end

function HuntFinder:setTeamSize(teamSize)
  if teamSize ~= "Solo" and teamSize ~= "Duo" and teamSize ~= "Party x4" then
    teamSize = "Solo"
  end
  HuntFinder.teamSize = teamSize

  if HuntFinder.teamSizeBox then
    HuntFinder.teamSizeBox:setCurrentOption(teamSize)
  end

  HuntFinder:showListPanel()
  ListPanel:displayHunts()
end

function HuntFinder:setSortType(sortType)
  HuntFinder.sortType = sortType
  HuntFinder:showListPanel()
  ListPanel:displayHunts()
end

function HuntFinder:onLevelEdit(newLevel)
  local level = tonumber(newLevel)
  if not level then
    return
  end
  HuntFinder.level = level
  HuntFinder:showListPanel()
  ListPanel:displayHunts()
end

-- Restyles the horizontal separator + close/back buttons. Two layouts:
--   forHuntInfo = true  -> separator stretches to span the hunt info panel's horizontal
--                          extents, with Close/Back stacked to its right edge.
--   forHuntInfo = false -> restore the original fixed-width separator anchored to the left
--                          and Close/Back pinned to the parent's right edge.
--
-- IMPORTANT: we cannot anchor `separator` to `huntInfoPanel` directly because mainPanel
-- already anchors its bottom to `separator.top`. Hooking the separator's left/right into a
-- descendant of mainPanel creates a layout cycle (mainPanel <- separator <- huntInfoPanel
-- <- mainPanel) and crashes the client. Instead we anchor to `mainPanel`, which is the
-- separator's sibling and has well-defined parent-bound horizontal extents.
local function applySeparatorLayout(forHuntInfo)
  local separator   = HuntFinder.separator
  local closeButton = HuntFinder.closeButton
  local backButton  = HuntFinder.backButton
  local searchText  = HuntFinder.searchText
  if not (separator and closeButton and backButton) then return end

  separator:breakAnchors()
  closeButton:breakAnchors()
  backButton:breakAnchors()
  if searchText then searchText:breakAnchors() end

  if forHuntInfo then
    -- Anchor everything horizontally to `parent` (contentPanel). mainPanel's bottom already
    -- depends on separator.top in the otui, so anchoring the separator's left/right to mainPanel
    -- creates a cross-axis cycle that OTClient's anchor solver flags as recursive.
    -- mainPanel itself anchors to parent.left/right with no margin, so parent.left/right is
    -- geometrically identical and breaks the dependency loop.
    separator:addAnchor(AnchorBottom, 'closeButton', AnchorTop)
    separator:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    separator:addAnchor(AnchorRight, 'parent', AnchorRight)
    separator:setMarginBottom(11)
    separator:setMarginLeft(0)
    separator:setMarginRight(0)

    -- Close button sits at the separator's right edge.
    closeButton:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    closeButton:addAnchor(AnchorRight, 'parent', AnchorRight)
    closeButton:setMarginRight(0)

    -- Back button sits immediately to the left of Close.
    backButton:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    backButton:addAnchor(AnchorRight, closeButton:getId(), AnchorLeft)
    backButton:setMarginRight(5)

    -- Search box aligns with the separator's left edge (= parent.left with zero margin).
    if searchText then
      searchText:addAnchor(AnchorBottom, 'parent', AnchorBottom)
      searchText:addAnchor(AnchorLeft, 'parent', AnchorLeft)
      searchText:setMarginLeft(0)
    end
  else
    -- Original layout: fixed-width separator anchored to the left + buttons at the right.
    separator:addAnchor(AnchorBottom, 'closeButton', AnchorTop)
    separator:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    separator:setMarginBottom(11)
    separator:setMarginLeft(10)
    if HuntFinder.separatorOriginalWidth then
      separator:setWidth(HuntFinder.separatorOriginalWidth)
    end

    closeButton:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    closeButton:addAnchor(AnchorRight, 'parent', AnchorRight)
    closeButton:setMarginRight(21)

    backButton:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    backButton:addAnchor(AnchorRight, closeButton:getId(), AnchorLeft)
    backButton:setMarginRight(5)

    -- Restore the original searchText position from the otui (bottom-left of parent + 10px).
    if searchText then
      searchText:addAnchor(AnchorBottom, 'parent', AnchorBottom)
      searchText:addAnchor(AnchorLeft, 'parent', AnchorLeft)
      searchText:setMarginLeft(10)
    end
  end
end

function HuntFinder:showListPanel()
  if not HuntFinder.widget then
    return
  end
  if HuntFinder.listPanel:isVisible() then
    return
  end
  HuntFinder.listPanel:setVisible(true)
  HuntFinder.huntInfoPanel:setVisible(false)
  HuntFinder.backButton:setVisible(false)
  HuntFinder.widget:setWidth(747)
  applySeparatorLayout(false)
end

function HuntFinder:showHuntInfo(hunt)
  if not HuntFinder.widget then
    return
  end
  if HuntFinder.huntInfoPanel:isVisible() then
    return
  end
  HuntFinder.listPanel:setVisible(false)
  HuntFinder.huntInfoPanel:setVisible(true)
  HuntFinder.backButton:setVisible(true)
  HuntFinder.widget:setWidth(920)
  applySeparatorLayout(true)
  HuntInfo:displayHunt(hunt)
end

function onGameStart()
  if not HuntFinder.widget then
    return
  end
  ListPanel.init()
  HuntInfo.init()
  MapFinder.init()
end

function offline()
  hide()
end

function show()
  if not HuntFinder.widget then
    return
  end
  HuntFinder.widget:show(true)
  HuntFinder.widget:raise()
  HuntFinder.widget:focus()
  HuntFinder:showListPanel()
  ListPanel:displayHunts()
  g_client.setInputLockWidget(HuntFinder.widget)
  setHuntFinderButtonActive(true)

  HuntFinder.searchText:setText("")
  HuntFinder.searchQuery = nil
  if HuntFinder.searchIcon then
    HuntFinder.searchIcon:setEnabled(false)
  end

  local player = g_game.getLocalPlayer()
  if not player then
    return
  end

  HuntFinder.searchInputBox:setValue(HuntConfig:getPlayerFloorLevel(player:getLevel()))
  HuntFinder.vocationFilter:setCurrentOption(translateVocationName(player:getVocation()))
end

function hide()
  if not HuntFinder.widget then
    return
  end
  HuntFinder.widget:hide()
  g_client.setInputLockWidget(nil)
  setHuntFinderButtonActive(false)
end

function onMonsterInfo(monsters)
  HuntInfo:setMonsters(monsters)
end

function onBestiaryData(data)
  if not HuntFinder.widget or not HuntFinder.widget:isVisible() then return end
  HuntInfo:updateMonsterData(data)
end

-- Response of OPCODE_HUNTFINDER_MONSTER_INFO: JSON with the full monster combat data
-- (works for any creature, hunted or not). Same shape HuntInfo:updateMonsterData expects.
function onMonsterInfoOpcode(protocol, opcode, buffer)
  if not HuntFinder.widget or not HuntFinder.widget:isVisible() then return end

  local data = json.decode(buffer)
  if not data then return end

  HuntInfo:updateMonsterData(data)
end