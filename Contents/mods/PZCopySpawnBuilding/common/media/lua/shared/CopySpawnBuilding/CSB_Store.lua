--[[
    Copy Spawn Building - where blueprints are kept.

    Blueprints can be big (a barn is a few hundred tiles), so they are kept
    once per save in global mod data, by id. Which ones a character knows is
    kept on the character, like learned recipes: a new character starts with
    none, and studying a building again on the same spot reuses its blueprint.

    Every copy built is kept too, so it can be taken down again later.

        ModData "CopySpawnBuilding".blueprints[id] = blueprint (see CSB_Core.lua)
        ModData "CopySpawnBuilding".spawned[sid] = copy record (see CSB.Spawn.place)
        ModData "CopySpawnBuilding".nextSpawn = number for the next sid
        player mod data CopySpawnBuilding.known[id] = true
--]]

require "CopySpawnBuilding/CSB_Core"

CSB.Store = {}

local KEY = "CopySpawnBuilding"

function CSB.Store.data()
    local data = ModData.getOrCreate(KEY)
    data.blueprints = data.blueprints or {}
    data.spawned = data.spawned or {}
    data.nextSpawn = data.nextSpawn or 1
    return data
end

-- Keeps the record of a copy that was built; gives it its sid.
function CSB.Store.addSpawn(record)
    local data = CSB.Store.data()
    record.sid = "c" .. data.nextSpawn
    data.nextSpawn = data.nextSpawn + 1
    data.spawned[record.sid] = record
    return record.sid
end

function CSB.Store.removeSpawn(sid)
    CSB.Store.data().spawned[sid] = nil
end

-- The records of the copies built: { [sid] = record }
function CSB.Store.spawns()
    return CSB.Store.data().spawned
end

function CSB.Store.put(bp)
    CSB.Store.data().blueprints[bp.id] = bp
end

function CSB.Store.get(id)
    return CSB.Store.data().blueprints[id]
end

local function knownTable(player)
    local modData = player:getModData()
    modData.CopySpawnBuilding = modData.CopySpawnBuilding or {}
    modData.CopySpawnBuilding.known = modData.CopySpawnBuilding.known or {}
    return modData.CopySpawnBuilding.known
end

function CSB.Store.knows(player, id)
    return knownTable(player)[id] == true
end

function CSB.Store.learn(player, bp)
    knownTable(player)[bp.id] = true
end

function CSB.Store.forget(player, id)
    knownTable(player)[id] = nil
end

-- The blueprints the character knows, sorted by name.
function CSB.Store.list(player)
    local list = {}
    for id in pairs(knownTable(player)) do
        local bp = CSB.Store.get(id)
        if bp then table.insert(list, bp) end
    end
    table.sort(list, function(a, b)
        if a.name == b.name then return a.id < b.id end
        return a.name < b.name
    end)
    return list
end
