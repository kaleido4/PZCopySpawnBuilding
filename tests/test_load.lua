dofile(ROOT .. "/tests/harness.lua")

print("Loading and storage")

-- Stubs of the game classes the mod's UI files build on, enough to load them.
local function class()
    local c = {}
    c.__index = c
    function c:derive(name)
        local d = setmetatable({}, { __index = self })
        d.__index = d
        d.Type = name
        return d
    end
    function c.new(self, character)
        local o = setmetatable({}, self)
        o.character = character
        return o
    end
    function c:init() end
    function c:setSprite(s) self.sprite = s end
    function c:setNorthSprite(s) self.northSprite = s end
    return c
end

ISBaseTimedAction = class()
ISBuildingObject = class()
ISCollapsableWindow = class()
ISScrollingListBox = class()
ISPanel = class()
local added = {}
Events = setmetatable({}, { __index = function(_, name)
    return { Add = function(fn) added[name] = fn end }
end })

local modData = {}
ModData = { getOrCreate = function(key)
    modData[key] = modData[key] or {}
    return modData[key]
end }

local FILES = {
    "shared/CopySpawnBuilding/CSB_Core.lua",
    "shared/CopySpawnBuilding/CSB_Store.lua",
    "shared/CopySpawnBuilding/CSB_Capture.lua",
    "shared/CopySpawnBuilding/CSB_Spawn.lua",
    "client/CopySpawnBuilding/CSB_StudyAction.lua",
    "client/CopySpawnBuilding/CSB_Picture.lua",
    "client/CopySpawnBuilding/CSB_Window.lua",
    "client/CopySpawnBuilding/CSB_ContextMenu.lua",
    "client/CopySpawnBuilding/CSB_Update.lua",
    "server/CopySpawnBuilding/CSB_Cursor.lua",
}

test("every mod file loads", function()
    for _, file in ipairs(FILES) do
        dofile(MOD .. file)
    end
    truthy(CSB_StudyAction, "study action")
    truthy(CSB_Cursor, "cursor")
    truthy(CSB_Window and CSB.Window.show, "window")
    truthy(added.OnFillWorldObjectContextMenu == CSB.Menu.fill, "context menu hooked")
end)

local function newPlayer()
    local p = { md = {} }
    function p:getModData() return self.md end
    return p
end

test("learned buildings are kept per character, blueprints once per save", function()
    local bob, kate = newPlayer(), newPlayer()
    CSB.Store.put({ id = "1_1", name = "Shed", tiles = {} })
    CSB.Store.learn(bob, CSB.Store.get("1_1"))
    truthy(CSB.Store.knows(bob, "1_1"), "Bob knows it")
    falsy(CSB.Store.knows(kate, "1_1"), "Kate does not")
    eq(modData.CopySpawnBuilding.blueprints["1_1"].name, "Shed")
end)

test("known buildings are listed by name", function()
    local p = newPlayer()
    CSB.Store.put({ id = "a", name = "Shed", tiles = {} })
    CSB.Store.put({ id = "b", name = "Barn", tiles = {} })
    CSB.Store.put({ id = "c", name = "Barn", tiles = {} })
    for _, id in ipairs({ "a", "b", "c" }) do CSB.Store.learn(p, CSB.Store.get(id)) end
    local list = CSB.Store.list(p)
    eq(#list, 3)
    eq(list[1].id, "b") eq(list[2].id, "c") eq(list[3].id, "a")
end)

test("a forgotten building leaves the list", function()
    local p = newPlayer()
    CSB.Store.put({ id = "x", name = "Shed", tiles = {} })
    CSB.Store.learn(p, CSB.Store.get("x"))
    CSB.Store.forget(p, "x")
    eq(#CSB.Store.list(p), 0)
end)

test("studying, learning and forgetting tell the window to read the list again", function()
    local p = newPlayer()
    local before = CSB.Store.revision
    CSB.Store.put({ id = "r", name = "Shed", tiles = {} })
    truthy(CSB.Store.revision > before, "put")
    before = CSB.Store.revision
    CSB.Store.learn(p, CSB.Store.get("r"))
    truthy(CSB.Store.revision > before, "learn")
    before = CSB.Store.revision
    CSB.Store.forget(p, "r")
    truthy(CSB.Store.revision > before, "forget")
    before = CSB.Store.revision
    CSB.Store.list(p)
    eq(CSB.Store.revision, before, "reading the list changes nothing")
end)

finish("Loading and storage")
