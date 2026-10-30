--[[
    Copy Spawn Building - "Study building" / "Study structure": the character
    looks it over, plans in hand, and learns it. Bigger ones take longer.

    target is { def = BuildingDef } for a building, or { structure = found }
    for a structure (CSB.Capture.findStructure). A structure is looked for
    again when the study is done, in case it changed meanwhile.
--]]

require "TimedActions/ISBaseTimedAction"
require "CopySpawnBuilding/CSB_Capture"
require "CopySpawnBuilding/CSB_Store"

CSB_StudyAction = ISBaseTimedAction:derive("CSB_StudyAction")

local FAILED = {
    notLoaded = "IGUI_CSB_NotLoaded",
    tooBig = "IGUI_CSB_TooBig",
}

function CSB_StudyAction:isValid()
    return self.target ~= nil
end

function CSB_StudyAction:update()
    self.character:faceLocation(self.square:getX(), self.square:getY())
end

function CSB_StudyAction:start()
    self:setAnimVariable("ReadType", "newspaper")
    self:setActionAnim(CharacterActionAnims.Read)
    self:setOverrideHandModelsString(nil, "MapInHand")
end

function CSB_StudyAction:stop()
    ISBaseTimedAction.stop(self)
end

function CSB_StudyAction:perform()
    local bp, why
    if self.target.def then
        bp, why = CSB.Capture.study(self.target.def, self.square:getZ())
        CSB.Capture.writeReport("building", bp, why)
    else
        bp, why = CSB.Capture.studyStructure(self.square)
        CSB.Capture.writeReport("structure", bp, why)
    end
    if bp then
        CSB.Store.put(bp)
        CSB.Store.learn(self.character, bp)
        self.character:setHaloNote(getText("IGUI_CSB_Learned", bp.name))
    else
        self.character:setHaloNote(getText(FAILED[why] or "IGUI_CSB_StudyFailed"))
    end
    ISBaseTimedAction.perform(self)
end

function CSB_StudyAction:new(character, target, square)
    local o = ISBaseTimedAction.new(self, character)
    o.target = target
    o.square = square
    local area = target.def and CSB.Capture.area(target.def, square:getZ()) or target.structure.count
    o.maxTime = CSB.studyTime(area)
    if character:isTimedActionInstant() then
        o.maxTime = 1
    end
    return o
end
