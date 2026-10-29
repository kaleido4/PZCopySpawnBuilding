--[[
    Copy Spawn Building - "Study building": the character looks the building
    over, plans in hand, and learns it. Bigger buildings take longer.
--]]

require "TimedActions/ISBaseTimedAction"
require "CopySpawnBuilding/CSB_Capture"
require "CopySpawnBuilding/CSB_Store"

CSB_StudyAction = ISBaseTimedAction:derive("CSB_StudyAction")

function CSB_StudyAction:isValid()
    return self.def ~= nil
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
    local bp, why = CSB.Capture.study(self.def)
    if bp then
        CSB.Store.put(bp)
        CSB.Store.learn(self.character, bp)
        self.character:setHaloNote(getText("IGUI_CSB_Learned", bp.name))
    elseif why == "notLoaded" then
        self.character:setHaloNote(getText("IGUI_CSB_NotLoaded"))
    else
        self.character:setHaloNote(getText("IGUI_CSB_StudyFailed"))
    end
    ISBaseTimedAction.perform(self)
end

function CSB_StudyAction:new(character, def, square)
    local o = ISBaseTimedAction.new(self, character)
    o.def = def
    o.square = square
    o.maxTime = CSB.studyTime(CSB.Capture.area(def))
    if character:isTimedActionInstant() then
        o.maxTime = 1
    end
    return o
end
