if not MapFinder then
    MapFinder = {
        widget = nil
    }
    MapFinder.__index = MapFinder
end

local self = MapFinder

local function hasSatelliteMapForFloor(floor)
    if not g_satelliteMap or not g_satelliteMap.hasChunksForView then
        return false
    end

    local ok, result = pcall(g_satelliteMap.hasChunksForView, floor)
    return ok and result == true
end

function MapFinder.init()
    if not HuntFinder.widget then return end
    self.widget = HuntFinder.widget:recursiveGetChildById('minimap')
    if not self.widget then
        print("[game_huntfinder] HuntFinder UI has no 'minimap' widget; map panel was not initialized.")
        return
    end

    if modules.game_minimap and modules.game_minimap.ensureMinimapDataLoaded then
        local ok, loaded = pcall(modules.game_minimap.ensureMinimapDataLoaded)
        if not ok then
            print("[game_huntfinder] Could not initialize shared OTMM data: " .. tostring(loaded))
        end
    end

    self.localPathWidgets = {}
    local player = g_game.getLocalPlayer()
    local position = player and player:getPosition()
    if not position or position.x == nil or position.y == nil or position.z == nil then
        position = {x = 31000, y = 31000, z = 7}
    end
    self.widget:setCameraPosition(position)
    self.widget:setZoom(2)
    if self.widget.setSatelliteMode then
        self.widget:setSatelliteMode(hasSatelliteMapForFloor(position.z))
    end

    self.widget.onFloorChange = function(widget, newPos, oldPos)
        self:onFloorChange(widget, newPos, oldPos)
    end
    self:onFloorChange(self.widget, position, position)
end

function MapFinder:clear()
    if not self.widget then
        return
    end

    self:clearLocalPath()
    self.widget = nil
end

function MapFinder:onFloorChange(widget, newPos, oldPos)
    if not self.widget or not newPos then
        return
    end

    if self.widget.setSatelliteMode then
        self.widget:setSatelliteMode(hasSatelliteMapForFloor(newPos.z))
    end
    if newPos.z > 7 then
        self.widget:setBackgroundColor("#000000ff")
    else
        self.widget:setBackgroundColor("#274DA6")
    end
end

function MapFinder:setHuntPosition(position)
    if not self.widget or not position then return end
    if (position.x == 0 and position.y == 0 and position.z == 0) then
        return
    end
    self.widget:setCameraPosition(position)

    MapFinder:onFloorChange(self.widget, position, {x = 0, y = 0, z = 0})
end

function MapFinder:setPath(coordinates)
    if modules.game_minimap then
        modules.game_minimap.setPath(coordinates)
    end
end

-- Helper function to convert a direction to position delta
local function applyDirection(pos, dir)
    local newPos = {x = pos.x, y = pos.y, z = pos.z}
    if dir == 0 then newPos.y = newPos.y - 1 -- North
    elseif dir == 1 then newPos.x = newPos.x + 1 -- East
    elseif dir == 2 then newPos.y = newPos.y + 1 -- South
    elseif dir == 3 then newPos.x = newPos.x - 1 -- West
    elseif dir == 4 then newPos.x = newPos.x + 1; newPos.y = newPos.y - 1 -- NorthEast
    elseif dir == 5 then newPos.x = newPos.x + 1; newPos.y = newPos.y + 1 -- SouthEast
    elseif dir == 6 then newPos.x = newPos.x - 1; newPos.y = newPos.y + 1 -- SouthWest
    elseif dir == 7 then newPos.x = newPos.x - 1; newPos.y = newPos.y - 1 -- NorthWest
    end
    return newPos
end

-- Helper function to linearly interpolate points between two positions (on same floor)
local function interpolatePoints(startPos, endPos, stepSize)
    local points = {}
    local dx = endPos.x - startPos.x
    local dy = endPos.y - startPos.y
    local distance = math.sqrt(dx * dx + dy * dy)
    
    if distance <= stepSize then
        return points -- Too close, no intermediate points needed
    end
    
    local numSteps = math.floor(distance / stepSize)
    for i = 1, numSteps do
        local t = i / (numSteps + 1)
        table.insert(points, {
            x = math.floor(startPos.x + dx * t + 0.5),
            y = math.floor(startPos.y + dy * t + 0.5),
            z = startPos.z
        })
    end
    
    return points
end

-- Helper function to flatten nested route coordinates from JSON structure
-- JSON format: {"7": [[{x,y,z}, {x,y,z}], [{x,y,z}]], "8": [[{x,y,z}]]}
local function flattenRouteCoordinates(routeCoords)
    local waypoints = {}
    
    -- Check if it's already a flat array with x,y,z
    if routeCoords[1] and routeCoords[1].x then
        print("[HuntFinder] Coords already flat format")
        return routeCoords
    end
    
    -- Iterate through floors (keys like "6", "7", "8")
    local floors = {}
    for floorKey, _ in pairs(routeCoords) do
        table.insert(floors, floorKey)
    end
    table.sort(floors, function(a, b)
        local floorA, floorB = tonumber(a), tonumber(b)
        if floorA and floorB then
            return floorA < floorB
        end
        return tostring(a) < tostring(b)
    end) -- Sort floors numerically to maintain route order
    
    print("[HuntFinder] Found " .. #floors .. " floors in route data")
    
    for _, floorKey in ipairs(floors) do
        local segments = routeCoords[floorKey]
        if type(segments) == "table" then
            for segIdx, segment in ipairs(segments) do
                if type(segment) == "table" then
                    for wpIdx, waypoint in ipairs(segment) do
                        if waypoint.x then
                            table.insert(waypoints, {x = waypoint.x, y = waypoint.y, z = waypoint.z})
                        end
                    end
                end
            end
        end
    end
    
    print("[HuntFinder] Flattened to " .. #waypoints .. " waypoints")
    return waypoints
end

-- LOCAL ROUTE FUNCTIONS: Draw on info panel's minimap only (not main game minimap)

local function scheduleLocalPathRefresh(self)
    if self.localPathRefreshScheduled then
        return
    end

    self.localPathRefreshScheduled = true
    scheduleEvent(function()
        self.localPathRefreshScheduled = false
        if not self.widget then
            return
        end

        for _, marker in ipairs(self.localPathWidgets or {}) do
            if marker and marker.routePosition then
                pcall(function()
                    self.widget:centerInPosition(marker, marker.routePosition)
                end)
            end
        end
    end, 50)
end

local function addLocalRouteMarker(self, position, isWaypoint, color)
    if not self.widget or not position or not position.x or not position.y or not position.z then
        return
    end

    local marker = g_ui.createWidget('UIWidget', self.widget)
    if not marker then return end
    marker:setWidth(isWaypoint and 8 or 4)
    marker:setHeight(isWaypoint and 8 or 4)
    marker:setBackgroundColor(color or (isWaypoint and "#ffe05b" or "#63e6be"))
    marker:setPhantom(true)
    marker.routePosition = {x = position.x, y = position.y, z = position.z}
    pcall(function()
        self.widget:centerInPosition(marker, marker.routePosition)
    end)
    self.localPathWidgets = self.localPathWidgets or {}
    table.insert(self.localPathWidgets, marker)
    scheduleLocalPathRefresh(self)
end

-- Clear path from info panel minimap
function MapFinder:clearLocalPath()
    for _, marker in ipairs(self.localPathWidgets or {}) do
        if marker then
            marker:destroy()
        end
    end
    self.localPathWidgets = {}
end

local MAX_LOCAL_PATH_MARKERS = 1600

local function collectLocalRouteSegments(routeCoords, segments)
    if type(routeCoords) ~= "table" then
        return
    end

    if routeCoords.x and routeCoords.y and routeCoords.z then
        table.insert(segments, {routeCoords})
        return
    end

    -- A flat point array is one continuous segment. Nested arrays are separate
    -- segments (as used by the HuntFinder JSON), so do not draw a false bridge
    -- between the end of one segment and the start of the next.
    if routeCoords[1] and routeCoords[1].x and routeCoords[1].y and routeCoords[1].z then
        table.insert(segments, routeCoords)
        return
    end

    local keys = {}
    for key, value in pairs(routeCoords) do
        if type(value) == "table" then
            table.insert(keys, key)
        end
    end
    table.sort(keys, function(a, b)
        local numberA, numberB = tonumber(a), tonumber(b)
        if numberA and numberB then
            return numberA < numberB
        end
        return tostring(a) < tostring(b)
    end)

    for _, key in ipairs(keys) do
        collectLocalRouteSegments(routeCoords[key], segments)
    end
end

local function buildLocalRoutePoints(routeCoords)
    local segments = {}
    collectLocalRouteSegments(routeCoords, segments)

    local points = {}
    local function appendPoint(point)
        if #points >= MAX_LOCAL_PATH_MARKERS then
            return false
        end

        local previous = points[#points]
        if not previous or previous.x ~= point.x or previous.y ~= point.y or previous.z ~= point.z then
            table.insert(points, point)
        end
        return #points < MAX_LOCAL_PATH_MARKERS
    end

    for _, segment in ipairs(segments) do
        local validPoints = {}
        for _, point in ipairs(segment) do
            if point.x and point.y and point.z then
                table.insert(validPoints, {
                    x = tonumber(point.x),
                    y = tonumber(point.y),
                    z = tonumber(point.z)
                })
            end
        end

        if #validPoints == 1 then
            appendPoint(validPoints[1])
        end

        for index = 1, #validPoints - 1 do
            if #points >= MAX_LOCAL_PATH_MARKERS then
                return points
            end

            local startPos = validPoints[index]
            local endPos = validPoints[index + 1]
            if startPos.z ~= endPos.z then
                appendPoint(startPos)
                appendPoint(endPos)
            else
                local dx = endPos.x - startPos.x
                local dy = endPos.y - startPos.y
                local steps = math.max(math.abs(dx), math.abs(dy))
                if steps == 0 then
                    appendPoint(startPos)
                else
                    local remaining = math.max(1, MAX_LOCAL_PATH_MARKERS - #points)
                    local stride = math.max(1, math.ceil(steps / remaining))
                    for step = 0, steps, stride do
                        local ratio = step / steps
                        local point = {
                            x = math.floor(startPos.x + dx * ratio + 0.5),
                            y = math.floor(startPos.y + dy * ratio + 0.5),
                            z = startPos.z
                        }
                        if not appendPoint(point) then
                            break
                        end
                    end
                    appendPoint(endPos)
                end
            end
        end
    end

    return points
end

-- Add every expanded coordinate to the HuntFinder minimap. At zoom 2, 4px
-- markers align with tiles and form a continuous route instead of sparse dots.
function MapFinder:addLocalPath(coordinates, color)
    if not self.widget then return end
    for _, position in ipairs(coordinates or {}) do
        addLocalRouteMarker(self, position, false, color)
    end
end

-- Add distinct waypoints to info panel minimap.
function MapFinder:addLocalWaypoints(waypoints, color)
    if not self.widget then return end
    local count = #waypoints
    local sampleRate = math.max(1, math.ceil(count / 100))
    for index, waypoint in ipairs(waypoints) do
        if waypoint.x and waypoint.y and waypoint.z then
            if index == 1 or index == count or index % sampleRate == 0 then
                addLocalRouteMarker(self, waypoint, true, color)
            end
        end
    end
end

local function addLocalRouteLayer(self, routeCoords, lineColor, waypointColor)
    if not routeCoords then return end
    local waypoints = flattenRouteCoordinates(routeCoords)
    self:addLocalPath(buildLocalRoutePoints(routeCoords), lineColor)
    self:addLocalWaypoints(waypoints, waypointColor)
end

-- Set the internal route on the HuntFinder minimap.
function MapFinder:setLocalRoutePath(routeCoords)
    if not self.widget then return end
    self:clearLocalPath()
    addLocalRouteLayer(self, routeCoords, "#63e6be", "#ffe05b")
end

-- Show both the approach route and the hunting route on the embedded map.
function MapFinder:setLocalHuntPaths(wayCoords, routeCoords)
    if not self.widget then return end
    self:clearLocalPath()
    addLocalRouteLayer(self, wayCoords, "#ffc857", "#fff1a8")
    addLocalRouteLayer(self, routeCoords, "#43d9be", "#b8fff0")
end



-- Expand sparse waypoints into a full navigable path using actual pathfinding
-- Handles floor transitions cleanly by not interpolating across floors
function MapFinder:expandRouteWithPathfinding(waypoints)
    if not waypoints or #waypoints < 2 then
        return waypoints or {}
    end
    
    local expandedPath = {}
    local pointSampleRate = 3  -- Only keep every Nth point for less density
    
    print("[HuntFinder] Expanding route with " .. #waypoints .. " waypoints")
    
    for i = 1, #waypoints - 1 do
        local startPos = waypoints[i]
        local endPos = waypoints[i + 1]
        
        -- Validate positions
        if not startPos or not startPos.x or not endPos or not endPos.x then
            print("[HuntFinder] Invalid waypoint at index " .. i)
            goto continue
        end
        
        -- Add start position (always add the waypoint itself)
        table.insert(expandedPath, {x = startPos.x, y = startPos.y, z = startPos.z})
        
        -- Check if this is a floor transition (stairs/ladder)
        if startPos.z ~= endPos.z then
            -- Floor transition: don't add any intermediate points
            -- Just add the waypoints themselves (already added startPos, endPos will be added next iteration or at the end)
            print("[HuntFinder] Floor transition at waypoint " .. i .. ": z=" .. startPos.z .. " -> z=" .. endPos.z)
            goto continue
        end
        
        -- Same floor: try pathfinding between waypoints
        local pathFound = false
        
        local success, path = pcall(function()
            return g_map.findPath(startPos, endPos, 10000, 0)
        end)
        
        if success and path and #path > 0 then
            -- Convert directions to positions
            local currentPos = {x = startPos.x, y = startPos.y, z = startPos.z}
            local stepCount = 0
            
            for _, dir in ipairs(path) do
                currentPos = applyDirection(currentPos, dir)
                stepCount = stepCount + 1
                
                -- Only add every Nth point to reduce density
                if stepCount % pointSampleRate == 0 then
                    table.insert(expandedPath, {x = currentPos.x, y = currentPos.y, z = currentPos.z})
                end
            end
            pathFound = true
            print("[HuntFinder] Pathfinding success: " .. #path .. " steps between waypoints " .. i .. " and " .. (i+1))
        end
        -- If pathfinding fails, waypoints (gems) are still visible.
        -- To fill gaps, add more waypoints to the route data.
        
        ::continue::
    end
    
    -- Add final waypoint
    local lastWaypoint = waypoints[#waypoints]
    if lastWaypoint and lastWaypoint.x then
        table.insert(expandedPath, {x = lastWaypoint.x, y = lastWaypoint.y, z = lastWaypoint.z})
    end
    
    print("[HuntFinder] Expanded path has " .. #expandedPath .. " points")
    
    return expandedPath
end

function MapFinder:setRoutePath(routePath)
    print("[HuntFinder] setRoutePath called, routePath size: " .. (routePath and table.size(routePath) or "nil"))
    if modules.game_minimap then
        if routePath and table.size(routePath) > 0 then
            -- First, flatten the nested coordinate structure from JSON
            local waypoints = flattenRouteCoordinates(routePath)
            
            print("[HuntFinder] After flatten: " .. #waypoints .. " waypoints")
            
            -- If no valid waypoints after flattening, exit
            if #waypoints == 0 then
                print("[HuntFinder] No valid waypoints found after flattening")
                return
            end
            
            -- If only 1 waypoint, prepend player position to create a path TO the destination
            if #waypoints == 1 then
                local player = g_game.getLocalPlayer()
                if player then
                    local playerPos = player:getPosition()
                    print("[HuntFinder] Only 1 waypoint, adding player at: " .. playerPos.x .. "," .. playerPos.y .. "," .. playerPos.z)
                    table.insert(waypoints, 1, {x = playerPos.x, y = playerPos.y, z = playerPos.z})
                end
            end
            
            print("[HuntFinder] Final waypoints before expand: " .. #waypoints)
            
            -- Expand the route waypoints using interpolation
            print("[HuntFinder] About to expand, waypoints count: " .. #waypoints)
            local success, expandedRoute = pcall(function()
                return self:expandRouteWithPathfinding(waypoints)
            end)
            
            if success and expandedRoute then
                print("[HuntFinder] Expansion success, points: " .. #expandedRoute)
                modules.game_minimap.setRoutePath(expandedRoute)
            else
                print("[HuntFinder] Expansion failed: " .. tostring(expandedRoute))
                modules.game_minimap.setRoutePath(waypoints)
            end
            return
        end
        
        -- If no static route, calculate from player to hunt position
        local player = g_game.getLocalPlayer()
        if not player then return end
        
        local startPos = player:getPosition()
        local endPos = self.huntPosition
        
        if startPos and endPos and endPos.x ~= 0 then
            local path, result = g_map.findPath(startPos, endPos, 50000, 0)
            if path and #path > 0 then
                local points = {}
                local currentPos = {x = startPos.x, y = startPos.y, z = startPos.z}
                table.insert(points, {x = currentPos.x, y = currentPos.y, z = currentPos.z})
                
                for _, dir in ipairs(path) do
                    currentPos = applyDirection(currentPos, dir)
                    table.insert(points, {x = currentPos.x, y = currentPos.y, z = currentPos.z})
                end
                
                modules.game_minimap.setRoutePath(points)
            end
        end
    end
end

