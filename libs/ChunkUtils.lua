local chunkUtils = {}

-- imports

local constants = require("Constants")
local mapUtils = require("MapUtils")

-- constants

local WATER_TILE_NAMES = constants.WATER_TILE_NAMES

local DEFINES_DIRECTION_EAST = defines.direction.east
local DEFINES_WIRE_TYPE_RED = defines.wire_type.red
local DEFINES_WIRE_TYPE_GREEN = defines.wire_type.green

local SENTINEL_IMPASSABLE_CHUNK = constants.SENTINEL_IMPASSABLE_CHUNK

local BASE_PHEROMONE = constants.BASE_PHEROMONE
local PLAYER_PHEROMONE = constants.PLAYER_PHEROMONE
local MOVEMENT_PHEROMONE = constants.MOVEMENT_PHEROMONE
local RESOURCE_PHEROMONE = constants.RESOURCE_PHEROMONE
local BUILDING_PHEROMONES = constants.BUILDING_PHEROMONES

local CHUNK_NORTH_SOUTH = constants.CHUNK_NORTH_SOUTH
local CHUNK_EAST_WEST = constants.CHUNK_EAST_WEST

local CHUNK_ALL_DIRECTIONS = constants.CHUNK_ALL_DIRECTIONS
local CHUNK_IMPASSABLE = constants.CHUNK_IMPASSABLE

local CHUNK_TICK = constants.CHUNK_TICK

local PATH_RATING = constants.PATH_RATING

local PASSABLE = constants.PASSABLE

local RESOURCE_GENERATOR_INCREMENT = constants.RESOURCE_GENERATOR_INCREMENT

-- imported functions

local getChunkByUnalignedXY = mapUtils.getChunkByUnalignedXY

local tRemove = table.remove

local mFloor = math.floor

-- module code

local function fullScan(chunk, can_place_entity, canPlaceQuery)
    local x = chunk.x
    local y = chunk.y
    
    local passableNorthSouth = false
    local passableEastWest = false

    canPlaceQuery.name = "chunk-scanner-ns-rampant"

    local position = canPlaceQuery.position
    position[2] = y
    
    for xi=x, x + 32 do
	position[1] = xi
	if can_place_entity(canPlaceQuery) then
	    passableNorthSouth = true
	    break
	end
    end

    position[1] = x
    canPlaceQuery.name = "chunk-scanner-ew-rampant"
    
    for yi=y, y + 32 do
	position[2] = yi
	if can_place_entity(canPlaceQuery) then
	    passableEastWest = true
	    break
	end
    end
    return passableNorthSouth, passableEastWest
end

local function addEnemyStructureToChunk(map, chunk, entity, base)
    local lookup
    if (entity.type == "unit-spawner") then
	lookup = map.chunkToNests
    elseif (entity.type == "turret") then
	lookup = map.chunkToWorms
    else
	return
    end
    
    local entityCollection = lookup[chunk]
    if not entityCollection then
	lookup[chunk] = 0
    end
    lookup[chunk] = lookup[chunk] + 1

    -- if base then
    -- 	local baseCollection = map.chunkToBases[chunk]
    -- 	if not baseCollection then
    -- 	    baseCollection = {}
    -- 	    map.chunkToBases[chunk] = baseCollection
    -- 	end
    -- 	baseCollection[base.id] = chunk
    -- end
    
end

local function removeEnemyStructureFromChunk(map, chunk, entity)
    local lookup
    if (entity.type == "unit-spawner") then
	lookup = map.chunkToNests
    elseif (entity.type == "turret") then
	lookup = map.chunkToWorms
    else
	return
    end

    -- local base = indexChunk[entity.unit_number]
    -- local indexBase
    -- if base then
    -- 	if (entity.type == "unit-spawner") then
    -- 	    if base.hives[entity.unit_number] then
    -- 		indexBase = base.hives
    -- 	    else
    -- 		indexBase = base.nests
    -- 	    end
    -- 	elseif (entity.type == "turret") then
    -- 	    indexBase = base.worms
    -- 	end
    -- 	indexBase[entity.unit_number] = nil
    -- end
    
    if lookup[chunk] then
	if ((lookup[chunk] - 1) <= 0) then
	    lookup[chunk] = nil
	else
	    lookup[chunk] = lookup[chunk] - 1
	end
    end
end

local function getEntityOverlapChunks(map, entity)
    local boundingBox = entity.prototype.collision_box or entity.prototype.selection_box;
    
    local leftTopChunk = SENTINEL_IMPASSABLE_CHUNK
    local rightTopChunk = SENTINEL_IMPASSABLE_CHUNK
    local leftBottomChunk = SENTINEL_IMPASSABLE_CHUNK
    local rightBottomChunk = SENTINEL_IMPASSABLE_CHUNK
    
    if boundingBox then
        local center = entity.position
        local topXOffset
        local topYOffset
        
        local bottomXOffset
        local bottomYOffset
        
        if (entity.direction == DEFINES_DIRECTION_EAST) then
            topXOffset = boundingBox.left_top.y
            topYOffset = boundingBox.left_top.x
            bottomXOffset = boundingBox.right_bottom.y
            bottomYOffset = boundingBox.right_bottom.x
        else
            topXOffset = boundingBox.left_top.x
            topYOffset = boundingBox.left_top.y
            bottomXOffset = boundingBox.right_bottom.x
            bottomYOffset = boundingBox.right_bottom.y
        end
        
        local leftTopChunkX = mFloor(center.x + topXOffset)
        local leftTopChunkY = mFloor(center.y + topYOffset)
        
        -- used to force things on chunk boundary to not spill over 0.0001
        local rightTopChunkX = mFloor(center.x + bottomXOffset - 0.0001)
        local rightTopChunkY = leftTopChunkY
        
        -- used to force things on chunk boundary to not spill over 0.0001
        local leftBottomChunkX = leftTopChunkX
        local leftBottomChunkY = mFloor(center.y + bottomYOffset - 0.0001)
	
        local rightBottomChunkX = rightTopChunkX 
        local rightBottomChunkY = leftBottomChunkY
	
        leftTopChunk = getChunkByUnalignedXY(map, leftTopChunkX, leftTopChunkY)
        if (leftTopChunkX ~= rightTopChunkX) then
            rightTopChunk = getChunkByUnalignedXY(map, rightTopChunkX, rightTopChunkY)
        end
        if (leftTopChunkY ~= leftBottomChunkY) then
            leftBottomChunk = getChunkByUnalignedXY(map, leftBottomChunkX, leftBottomChunkY)
        end
        if (leftTopChunkX ~= rightBottomChunkX) and (leftTopChunkY ~= rightBottomChunkY) then
            rightBottomChunk = getChunkByUnalignedXY(map, rightBottomChunkX, rightBottomChunkY)
        end
    end
    return leftTopChunk, rightTopChunk, leftBottomChunk, rightBottomChunk
end

-- external functions

function chunkUtils.calculatePassScore(surface, map)
    local count_tiles_filtered = surface.count_tiles_filtered
    local filteredTilesQuery = map.filteredTilesQuery
    
    local passScore = 0
    for i=1,#WATER_TILE_NAMES do
	filteredTilesQuery.name = WATER_TILE_NAMES[i]
	passScore = passScore + count_tiles_filtered(filteredTilesQuery)
    end

    return 1 - (passScore * 0.0009765625)
end

function chunkUtils.scanChunkPaths(chunk, surface, map)
    local pass = CHUNK_IMPASSABLE
    local passableNorthSouth, passableEastWest = fullScan(chunk,
							  surface.can_place_entity,
							  map.canPlaceQuery)
    
    if passableEastWest and passableNorthSouth then
	pass = CHUNK_ALL_DIRECTIONS
    elseif passableEastWest then
	pass = CHUNK_EAST_WEST
    elseif passableNorthSouth then
	pass = CHUNK_NORTH_SOUTH
    end
    return pass
end

function chunkUtils.scorePlayerBuildings(surface, map, natives)
    local entities = surface.find_entities_filtered(map.filteredEntitiesPlayerQuery)

    local playerObjects = 0
    local safeBuildings = natives.safeBuildings
    local safeEntities = natives.safeEntities
    local safeEntityName = natives.safeEntityName
    if safeBuildings then
	for i=1, #entities do
	    local entity = entities[i]
	    local entityType = entity.type

	    if safeEntities[entityType] or safeEntityName[entity.name] then
		entity.destructible = false
	    end

	    playerObjects = playerObjects + (BUILDING_PHEROMONES[entityType] or 0)
	end
    else
	for i=1, #entities do
	    playerObjects = playerObjects + (BUILDING_PHEROMONES[entities[i].type] or 0)
	end
    end

    return playerObjects
end

function chunkUtils.scoreEnemyBuildings(surface, map)
    local query = map.filteredEntitiesEnemyTypeQuery
    
    query.type = "unit-spawner"
    local nests = surface.count_entities_filtered(map.filteredEntitiesEnemyTypeQuery)
    
    query.type = "turret"
    local worms = surface.count_entities_filtered(map.filteredEntitiesEnemyTypeQuery)

    return nests, worms
end

function chunkUtils.initialScan(chunk, natives, surface, map)
    local passScore = chunkUtils.calculatePassScore(surface, map)

    if (passScore >= 0.40) then
	local pass = chunkUtils.scanChunkPaths(chunk, surface, map)
	
	local playerObjects = chunkUtils.scorePlayerBuildings(surface, map, natives)

	local nests, worms = chunkUtils.scoreEnemyBuildings(surface, map)

	local resources = surface.count_entities_filtered(map.countResourcesQuery) * 0.001
	
	if ((playerObjects > 0) or (nests > 0)) and (pass == CHUNK_IMPASSABLE) then
	    pass = CHUNK_ALL_DIRECTIONS
	end

	chunkUtils.setNestCount(map, chunk, nests)
	chunkUtils.setPlayerBaseGenerator(map, chunk, playerObjects)
	chunkUtils.setResourceGenerator(map, chunk, resources)
	chunkUtils.setWormCount(map, chunk, worms)

	chunk[PASSABLE] = pass
	chunk[PATH_RATING] = passScore

	return chunk
    end

    return SENTINEL_IMPASSABLE_CHUNK
end

function chunkUtils.chunkPassScan(chunk, surface, map)
    local passScore = chunkUtils.calculatePassScore(surface, map)

    if (passScore >= 0.40) then
	local pass = chunkUtils.scanChunkPaths(chunk, surface, map)
	
	local playerObjects = chunkUtils.getPlayerBaseGenerator(map, chunk)

	local nests = chunkUtils.getNestCount(map, chunk)

	if ((playerObjects > 0) or (nests > 0)) and (pass == CHUNK_IMPASSABLE) then
	    pass = CHUNK_ALL_DIRECTIONS
	end

	chunk[PASSABLE] = pass
	chunk[PATH_RATING] = passScore

	return chunk
    end

    return SENTINEL_IMPASSABLE_CHUNK
end

function chunkUtils.analyzeChunk(chunk, natives, surface, map)    
    local playerObjects = chunkUtils.scorePlayerBuildings(surface, map, natives)
    chunkUtils.setPlayerBaseGenerator(map, chunk, playerObjects)
end

-- function chunkUtils.remakeChunk(map, chunk, surface, natives, tick, tempQuery)
--     tempQuery.force = "enemy"
--     local enemies = surface.find_entities_filtered(tempQuery)

--     local points = 0
--     for f=1, #enemies do
-- 	local enemy = enemies[f]
-- 	local entityType = enemies[f].type
-- 	if not ((enemy.name == "small-tendril-biter-rampant") or (enemy.name == "biter-spawner-hive-rampant")) then
-- 	    if (entityType == "unit-spawner") then
-- 		points = points + 3
-- 	    elseif (entityType == "turret") then
-- 		points = points + 2
-- 	    elseif (entityType == "unit") then
-- 		points = points + 1
-- 	    end
-- 	    enemy.destroy()
-- 	end
--     end
--     -- local foundBase = findNearbyBase(natives, chunk) or createBase(map, natives, chunk, surface, tick)
--     -- if foundBase then
--     -- 	foundBase.upgradePoints = foundBase.upgradePoints + points
--     -- end    
-- end

function chunkUtils.getNestCount(map, chunk)
    return map.chunkToNests[chunk] or 0
end

function chunkUtils.getWormCount(map, chunk)
    return map.chunkToWorms[chunk] or 0
end

function chunkUtils.setWormCount(map, chunk, count)
    if (count == 0) then
	map.chunkToWorms[chunk] = nil
    else
	map.chunkToWorms[chunk] = count
    end
end

function chunkUtils.setNestCount(map, chunk, count)
    if (count == 0) then
	map.chunkToNests[chunk] = nil
    else
	map.chunkToNests[chunk] = count
    end
end

function chunkUtils.getNestCount(map, chunk)
    return map.chunkToNests[chunk] or 0
end

function chunkUtils.getWormCount(map, chunk)
    return map.chunkToWorms[chunk] or 0
end

function chunkUtils.getEnemyStructureCount(map, chunk)
    return (map.chunkToNests[chunk] or 0) + (map.chunkToWorms[chunk] or 0)
end

function chunkUtils.getRetreatTick(map, chunk)
    return map.chunkToRetreats[chunk] or 0
end

function chunkUtils.getRallyTick(map, chunk)
    return map.chunkToRallys[chunk] or 0
end

function chunkUtils.setRallyTick(map, chunk, tick)
    map.chunkToRallys[chunk] = tick 
end

function chunkUtils.setRetreatTick(map, chunk, tick)
    map.chunkToRetreats[chunk] = tick
end

function chunkUtils.setResourceGenerator(map, chunk, resourceGenerator)
    if (resourceGenerator == 0) then
	map.chunkToResource[chunk] = nil
    else
	map.chunkToResource[chunk] = resourceGenerator
    end
end

function chunkUtils.getResourceGenerator(map, chunk)
    return map.chunkToResource[chunk] or 0
end

function chunkUtils.addResourceGenerator(map, chunk, delta)
    map.chunkToResource[chunk] = (map.chunkToResource[chunk] or 0) + delta
end

function chunkUtils.getPlayerBaseGenerator(map, chunk)
    return map.chunkToPlayerBase[chunk] or 0
end

function chunkUtils.addSquadToChunk(map, chunk, squad)
    if (chunk ~= squad.chunk) then
	local chunkToSquad = map.chunkToSquad
	chunkUtils.removeSquadFromChunk(map, squad)
	if not chunkToSquad[chunk] then
	    chunkToSquad[chunk] = {}
	end
	chunkToSquad[chunk][#chunkToSquad[chunk]+1] = squad

	squad.chunk = chunk
    end
end

function chunkUtils.removeSquadFromChunk(map, squad)
    local chunkToSquad = map.chunkToSquad
    if squad.chunk then
	local squads = chunkToSquad[squad.chunk]
	if squads then
	    for i=#squads, 1, -1 do    
		if (squads[i] == squad) then
		    tRemove(squads, i)
		    break
		end
	    end
	    if (#squads == 0) then
		chunkToSquad[squad.chunk] = nil
	    end
	end
    end
end

function chunkUtils.getSquadsOnChunk(map, chunk)
    return map.chunkToSquad[chunk] or {}
end

function chunkUtils.setPlayerBaseGenerator(map, chunk, playerGenerator)
    if (playerGenerator == 0) then
	map.chunkToPlayerBase[chunk] = nil
    else
	map.chunkToPlayerBase[chunk] = playerGenerator
    end
end

function chunkUtils.addPlayerBaseGenerator(map, chunk, playerGenerator)
    map.chunkToPlayerBase[chunk] = (map.chunkToPlayerBase[chunk] or 0) + playerGenerator
end

function chunkUtils.createChunk(topX, topY)
    local chunk = {
	x = topX,
	y = topY
    }
    chunk[MOVEMENT_PHEROMONE] = 0
    chunk[BASE_PHEROMONE] = 0
    chunk[PLAYER_PHEROMONE] = 0
    chunk[RESOURCE_PHEROMONE] = 0
    chunk[PASSABLE] = 0
    chunk[CHUNK_TICK] = 0
    chunk[PATH_RATING] = 0
    
    return chunk
end

function chunkUtils.colorChunk(x, y, tileType, surface)
    local tiles = {}
    for xi=x+5, x + 27 do
	for yi=y+5, y + 27 do
	    tiles[#tiles+1] = {name=tileType, position={xi, yi}}
	end
    end
    surface.set_tiles(tiles, false)
end

function chunkUtils.entityForPassScan(map, entity)
    local leftTop, rightTop, leftBottom, rightBottom = getEntityOverlapChunks(map, entity)

    if (leftTop ~= SENTINEL_IMPASSABLE_CHUNK) then
	map.chunkToPassScan[leftTop] = true
    end
    if (rightTop ~= SENTINEL_IMPASSABLE_CHUNK) then
	map.chunkToPassScan[rightTop] = true
    end
    if (leftBottom ~= SENTINEL_IMPASSABLE_CHUNK) then
	map.chunkToPassScan[leftBottom] = true
    end
    if (rightBottom ~= SENTINEL_IMPASSABLE_CHUNK) then
	map.chunkToPassScan[rightBottom] = true
    end
end

function chunkUtils.registerEnemyBaseStructure(map, entity, base)
    local entityType = entity.type
    if ((entityType == "unit-spawner") or (entityType == "turret")) and (entity.force.name == "enemy") then
	local leftTop, rightTop, leftBottom, rightBottom = getEntityOverlapChunks(map, entity)
	
	if (leftTop ~= SENTINEL_IMPASSABLE_CHUNK) then
	    addEnemyStructureToChunk(map, leftTop, entity, base)
	end
	if (rightTop ~= SENTINEL_IMPASSABLE_CHUNK) then
	    addEnemyStructureToChunk(map, rightTop, entity, base)
	end
	if (leftBottom ~= SENTINEL_IMPASSABLE_CHUNK) then
	    addEnemyStructureToChunk(map, leftBottom, entity, base)
	end
	if (rightBottom ~= SENTINEL_IMPASSABLE_CHUNK) then
	    addEnemyStructureToChunk(map, rightBottom, entity, base)
	end	
    end
end

function chunkUtils.unregisterEnemyBaseStructure(map, entity)
    local entityType = entity.type
    if ((entityType == "unit-spawner") or (entityType == "turret")) and (entity.force.name == "enemy") then
	local leftTop, rightTop, leftBottom, rightBottom = getEntityOverlapChunks(map, entity)
	
	if (leftTop ~= SENTINEL_IMPASSABLE_CHUNK) then
	    removeEnemyStructureFromChunk(map, leftTop, entity)
	end
	if (rightTop ~= SENTINEL_IMPASSABLE_CHUNK) then
	    removeEnemyStructureFromChunk(map, rightTop, entity)
	end
	if (leftBottom ~= SENTINEL_IMPASSABLE_CHUNK) then
	    removeEnemyStructureFromChunk(map, leftBottom, entity)
	end
	if (rightBottom ~= SENTINEL_IMPASSABLE_CHUNK) then
	    removeEnemyStructureFromChunk(map, rightBottom, entity)
	end
    end
end

function chunkUtils.addRemovePlayerEntity(map, entity, natives, addObject, creditNatives)
    local leftTop, rightTop, leftBottom, rightBottom
    local entityValue
    if (BUILDING_PHEROMONES[entity.type] ~= nil) and (entity.force.name == "player") then
        entityValue = BUILDING_PHEROMONES[entity.type]

        leftTop, rightTop, leftBottom, rightBottom = getEntityOverlapChunks(map, entity)
        if not addObject then
    	    if creditNatives then
    		natives.points = natives.points + entityValue
    	    end
    	    entityValue = -entityValue
    	end
    	if (leftTop ~= SENTINEL_IMPASSABLE_CHUNK) then
	    chunkUtils.addPlayerBaseGenerator(map, leftTop, entityValue)
    	end
    	if (rightTop ~= SENTINEL_IMPASSABLE_CHUNK) then
	    chunkUtils.addPlayerBaseGenerator(map, rightTop, entityValue)
    	end
    	if (leftBottom ~= SENTINEL_IMPASSABLE_CHUNK) then
	    chunkUtils.addPlayerBaseGenerator(map, leftBottom, entityValue)
    	end
    	if (rightBottom ~= SENTINEL_IMPASSABLE_CHUNK) then
	    chunkUtils.addPlayerBaseGenerator(map, rightBottom, entityValue)
    	end
    end
    return entity
end

function chunkUtils.unregisterResource(entity, map)
    if entity.prototype.infinite_resource then
	return
    end
    local leftTop, rightTop, leftBottom, rightBottom = getEntityOverlapChunks(map, entity)
    
    if (leftTop ~= SENTINEL_IMPASSABLE_CHUNK) then
	chunkUtils.addResourceGenerator(map, leftTop, -RESOURCE_GENERATOR_INCREMENT)
    end
    if (rightTop ~= SENTINEL_IMPASSABLE_CHUNK) then
	chunkUtils.addResourceGenerator(map, rightTop, -RESOURCE_GENERATOR_INCREMENT)
    end
    if (leftBottom ~= SENTINEL_IMPASSABLE_CHUNK) then
	chunkUtils.addResourceGenerator(map, leftBottom, -RESOURCE_GENERATOR_INCREMENT)
    end
    if (rightBottom ~= SENTINEL_IMPASSABLE_CHUNK) then
	chunkUtils.addResourceGenerator(map, rightBottom, -RESOURCE_GENERATOR_INCREMENT)
    end
end

function chunkUtils.makeImmortalEntity(surface, entity)
    local repairPosition = entity.position
    local repairName = entity.name
    local repairForce = entity.force
    local repairDirection = entity.direction

    local wires
    if (entity.type == "electric-pole") then
	wires = entity.neighbours
    end
    entity.destroy()
    local newEntity = surface.create_entity({position=repairPosition,
					     name=repairName,
					     direction=repairDirection,
					     force=repairForce})
    if wires then
	for connectType,neighbourGroup in pairs(wires) do
	    if connectType == "copper" then
		for _,v in pairs(neighbourGroup) do
		    newEntity.connect_neighbour(v);
		end
	    elseif connectType == "red" then
		for _,v in pairs(neighbourGroup) do
		    newEntity.connect_neighbour({wire = DEFINES_WIRE_TYPE_RED, target_entity = v});
		end
	    elseif connectType == "green" then
		for _,v in pairs(neighbourGroup) do
		    newEntity.connect_neighbour({wire = DEFINES_WIRE_TYPE_GREEN, target_entity = v});
		end
	    end
	end
    end

    newEntity.destructible = false
end

return chunkUtils
