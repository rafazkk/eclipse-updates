minimapWidget = nil
minimapButton = nil
minimapWindow = nil
fullmapView = false
local loaded = false
local otmmLoaded = false
local satelliteAvailable = false
oldZoom = nil
oldPos = nil

local function fixMinimapButtonImage()
  local button = minimapButton
  if not button then
    return
  end

  local ok, destroyed = pcall(function()
    return button:isDestroyed()
  end)
  if ok and destroyed then
    return
  end

  local active = button:isOn()
  local imageClip = active and "0 20 20 20" or "0 0 20 20"
  pcall(function() button:setImageClip(imageClip) end)
  pcall(function()
    button:setImageBorder(0)
  end)
  pcall(function() button:setImageOffset("0 0") end)
  pcall(function() button:setImageSize("20 20") end)
end

local function updateChangeViewButtonVisibility()
  if not minimapWindow then
    return
  end

  local button = minimapWindow:recursiveGetChildById('changeView')
  if button then
    button:setVisible(satelliteAvailable)
  end
end

local flagToFilePath = {
  ["up"] = "data/images/game/minimap/flag18.png",
  ["flag"] = "data/images/game/minimap/flag9.png",
  ["skull"] = "data/images/game/minimap/flag12.png",
  ["crossmark"] = "data/images/game/minimap/flag4.png",
  ["star"] = "data/images/game/minimap/flag3.png",
  ["sword"] = "data/images/game/minimap/flag8.png",
  ["red up"] = "data/images/game/minimap/flag14.png",
  ["?"] = "data/images/game/minimap/flag1.png",
  ["checkmark"] = "data/images/game/minimap/flag0.png",
  ["red left"] = "data/images/game/minimap/flag17.png",
  ["red right"] = "data/images/game/minimap/flag16.png",
  ["!"] = "data/images/game/minimap/flag2.png",
  ["down"] = "data/images/game/minimap/flag19.png",
  ["mouth"] = "data/images/game/minimap/flag6.png",
  ["lock"] = "data/images/game/minimap/flag10.png",
  ["red down"] = "data/images/game/minimap/flag15.png",
  ["bag"] = "data/images/game/minimap/flag11.png",
  ["cross"] = "data/images/game/minimap/flag5.png",
  ["spear"] = "data/images/game/minimap/flag7.png",
  ["$"] = "data/images/game/minimap/flag13.png",
}

--[[local regions = {
  ["svarground"] = {
    fromPos = { x = 32143, y = 31042, z = 7 },
    toPos = { x = 32350, y = 31251, z = 7 },
    size = { width = 207, height = 209 },
    image = "/data/minimap/regions/19-(32143-31042-7)subarea-0298-5160667f70d26dfc4db196d9dae5b048e060adf7a824c3a1c4383ee8ef6d6e51.png",
    markedColor = "#FFFF0044"
  },
}--]]

function init()
  minimapWindow = g_ui.displayUI('realminimap')
  if not minimapWindow then
    print("[game_realminimap] Could not load realminimap.otui; module UI was not created.")
    return
  end
  minimapWindow:hide()

  minimapButton = modules.client_topmenu.addRightGameToggleButton('minimapButton',
      tr('Real Minimap') .. ' (Ctrl+M)', '/images/topbuttons/minimap', toggle)
  if minimapButton then
    minimapButton.onStyleApply = function()
      fixMinimapButtonImage()
    end
    fixMinimapButtonImage()
    minimapButton:setOn(false)
  end

  minimapWidget = minimapWindow:recursiveGetChildById('realMinimap')
  updateChangeViewButtonVisibility()

  connect(g_game, {
    onGameStart = online,
    onGameEnd = offline,
  })

  connect(LocalPlayer, {
    onPositionChange = updateCameraPosition
  })

  loadMap()

  if g_game.isOnline() then
    online()
  end
end

function terminate()
  disconnect(g_game, {
    onGameStart = online,
    onGameEnd = offline,
  })

  disconnect(LocalPlayer, {
    onPositionChange = updateCameraPosition
  })

  if minimapWindow then
    minimapWindow:destroy()
    minimapWindow = nil
  end
  if minimapButton then
    minimapButton:destroy()
  end
end

function toggle()
  if not minimapButton then return end

  if minimapButton:isOn() then
    minimapWindow:hide()
    minimapButton:setOn(false)
  else
    minimapWindow:show()
    minimapButton:setOn(true)
  end
end

function onClose()
  if minimapButton then
    minimapButton:setOn(false)
  end
  minimapWindow:hide()
end

function online()
  local benchmark = g_clock.millis()
  loadMap()
  updateCameraPosition()
  print("[game_realminimap] Loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end

function offline()
  if minimapWindow then
    minimapWindow:hide()
  end
  if minimapButton then
    minimapButton:setOn(false)
  end
end

function updateCameraPosition()
  if not minimapWidget then return end
  local player = g_game.getLocalPlayer()
  if not player then return end
  local position = player:getPosition()
  -- The local player can exist briefly before its first valid position arrives.
  -- Passing nil to the C++ Position binding throws and interrupts module callbacks.
  if not position or position.x == nil or position.y == nil or position.z == nil then
    return
  end
  minimapWidget:setCameraPosition(position)
end

local function loadOtmmCache()
  if otmmLoaded or not g_minimap or not g_minimap.loadOtmm then
    return otmmLoaded
  end

  local cachePaths = {
    '/minimap.otmm',
    '/data/minimap.otmm',
  }

  for _, path in ipairs(cachePaths) do
    if g_resources.fileExists(path) then
      local ok, result = pcall(function()
        return g_minimap.loadOtmm(path)
      end)
      if ok and result then
        otmmLoaded = true
        print("[game_realminimap] Loaded OTMM cache: " .. path)
        return true
      end
      print("[game_realminimap] Found OTMM cache but could not load it: " .. path)
    end
  end

  return false
end

function loadMap()
  if loaded or not g_minimap then return end
  print("[game_realminimap] Loading minimap images through g_minimap...")

  local files = g_resources.listDirectoryFiles('/data/minimap') or {}
  local loadedCount = 0
  for _, filePath in ipairs(files) do
    if g_resources.isFileType(filePath, 'png') then
      local parts = filePath:split('/')
      local fileName = parts[#parts]
      local matches = regexMatch(fileName, [[minimap-([0-9]+)-([0-9]+)-([0-9]+)-([0-9]+)-([0-9a-zA-Z]+)\.bmp.lzma.png]])
      local match = matches and matches[1]
      if match then
        local refSize = tonumber(match[2])
        local posX = tonumber(match[3])
        local posY = tonumber(match[4])
        local posZ = tonumber(match[5])

        -- UIMinimap's g_minimap.loadImage maps one image pixel to one world tile.
        -- Other resolutions need the old custom renderer and cannot be loaded by this source.
        if refSize == 32 then
          local path = '/data/minimap/' .. fileName
          local ok, result = pcall(function()
            return g_minimap.loadImage(path, {x = posX * 32, y = posY * 32, z = posZ}, 1)
          end)
          if ok and result then
            loadedCount = loadedCount + 1
          else
            print("[game_realminimap] Could not load minimap sector: " .. path)
          end
        end
      end
    end
  end

  local cacheLoaded = loadOtmmCache()

  local satellitePath = '/data/things/1530'
  satelliteAvailable = false
  if g_satelliteMap and g_resources.fileExists(satellitePath .. '/satellite/index.dat') then
    local ok, result = pcall(function()
      return g_satelliteMap.loadFloors(satellitePath, 0, 15)
    end)
    satelliteAvailable = ok and result or false
  end
  updateChangeViewButtonVisibility()

  if minimapWidget then
    local player = g_game.getLocalPlayer()
    local position = player and player:getPosition()
    if not position or position.x == nil or position.y == nil or position.z == nil then
      position = {x = 31000, y = 31000, z = 7}
    end
    minimapWidget:setCameraPosition(position)
    minimapWidget:setSatelliteMode(false)
  end

  loaded = loadedCount > 0 or cacheLoaded
  print(string.format("[game_realminimap] Minimap loaded: %d PNG sectors; OTMM cache: %s; satellite data: %s",
    loadedCount, cacheLoaded and "loaded" or "not found",
    satelliteAvailable and "available" or "not installed"))
  if not loaded then
    print("[game_realminimap] No map cache found. Add minimap.otmm at /minimap.otmm or compatible PNG sectors under /data/minimap.")
  end
end