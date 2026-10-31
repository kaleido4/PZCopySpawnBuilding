--[[
    Copy Spawn Building - the Studied buildings window, opened from the
    right-click menu: the buildings the character knows, each with a picture
    of it (CSB_Picture.lua), and a big picture of the one picked.
      * Build (or a double click) starts the placement cursor (CSB_Cursor.lua);
      * Forget takes it off the list, after asking;
      * - and + step through its levels, to see inside under the roof.
    The list is read again whenever a building is studied, updated or
    forgotten (CSB.Store.revision).
--]]

require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"
require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISModalDialog"
require "CopySpawnBuilding/CSB_Store"
require "CopySpawnBuilding/CSB_Picture"

CSB.Window = { byPlayer = {} }

CSB_Window = ISCollapsableWindow:derive("CSB_Window")
CSB_BuildingList = ISScrollingListBox:derive("CSB_BuildingList")
CSB_BuildingPreview = ISPanel:derive("CSB_BuildingPreview")

local PAD = 10
local THUMB_W, THUMB_H = 96, 64
local LIST_W = 300

local function fontHeight(font)
    return getTextManager():getFontHeight(font)
end

local function textWidth(text)
    return getTextManager():MeasureStringX(UIFont.Small, text)
end

local function sizeText(bp)
    return getText("IGUI_CSB_Size", bp.w, bp.h, bp.levels)
end

---------------------------------------------------------------------------
-- The list: a picture, the name and the size of each building
---------------------------------------------------------------------------

function CSB_BuildingList:doDrawItem(y, item, alt)
    local h = item.height
    local top = y + self:getYScroll()
    if top + h < 0 or top >= self.height then return y + h end
    local w = self:getWidth()
    if self.selected == item.index then
        self:drawSelection(0, y, w, h - 1)
    elseif self.mouseoverselected == item.index and self:isMouseOver() and not self:isMouseOverScrollBar() then
        self:drawMouseOverHighlight(0, y, w, h - 1)
    end
    self:drawRectBorder(0, y, w, h, 0.5, self.borderColor.r, self.borderColor.g, self.borderColor.b)

    local bp = item.item
    CSB.Picture.draw(self, bp, PAD / 2, y + (h - THUMB_H) / 2, THUMB_W, THUMB_H)
    local medium, small = fontHeight(UIFont.Medium), fontHeight(UIFont.Small)
    local tx, ty = PAD + THUMB_W, y + (h - medium - small) / 2
    self:drawText(bp.name, tx, ty, 0.9, 0.9, 0.9, 1, UIFont.Medium)
    self:drawText(sizeText(bp), tx, ty + medium, 0.6, 0.6, 0.6, 1, UIFont.Small)
    return y + h
end

---------------------------------------------------------------------------
-- The big picture of the building picked
---------------------------------------------------------------------------

function CSB_BuildingPreview:render()
    ISPanel.render(self)
    local bp = self.bp
    if not bp then
        local small = fontHeight(UIFont.Small)
        self:drawTextCentre(getText("IGUI_CSB_NoneKnown"), self.width / 2, (self.height - small) / 2,
            0.7, 0.7, 0.7, 1, UIFont.Small)
        return
    end
    local medium, small = fontHeight(UIFont.Medium), fontHeight(UIFont.Small)
    self:drawText(bp.name, PAD, PAD, 1, 1, 1, 1, UIFont.Medium)
    self:drawText(sizeText(bp), PAD, PAD + medium, 0.7, 0.7, 0.7, 1, UIFont.Small)
    local top = PAD * 2 + medium + small
    CSB.Picture.draw(self, bp, PAD, top, self.width - PAD * 2, self.height - top - PAD, self.maxZ)
end

function CSB_BuildingPreview:new(x, y, w, h)
    local o = ISPanel.new(self, x, y, w, h)
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.5 }
    o.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 1 }
    return o
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

-- A button on the bottom row, at x (from the right edge when right is true).
local function newButton(window, x, y, h, text, internal, onClick, right)
    local w = math.max(h * 2, textWidth(text) + PAD * 2)
    if right then x = window.width - x - w end
    local button = ISButton:new(x, y, w, h, text, window, onClick)
    button.internal = internal
    button.anchorTop = false
    button.anchorBottom = true
    button.anchorLeft = not right
    button.anchorRight = right == true
    button:initialise()
    button:instantiate()
    window:addChild(button)
    return button
end

function CSB_Window:createChildren()
    ISCollapsableWindow.createChildren(self)
    local th = self:titleBarHeight()
    local bottom = self.height - self:resizeWidgetHeight() - PAD
    local btnH = fontHeight(UIFont.Small) + 6

    local list = CSB_BuildingList:new(PAD, th + PAD, LIST_W, bottom - th - PAD)
    list.anchorBottom = true
    list:initialise()
    list:instantiate()
    list.itemheight = math.max(THUMB_H, fontHeight(UIFont.Medium) + fontHeight(UIFont.Small)) + PAD
    list.drawBorder = true
    list:setOnMouseDownFunction(self, CSB_Window.select)
    list:setOnMouseDoubleClick(self, CSB_Window.onBuild)
    self:addChild(list)
    self.list = list

    local rx = PAD * 2 + LIST_W
    local preview = CSB_BuildingPreview:new(rx, th + PAD, self.width - rx - PAD, bottom - btnH - PAD - th - PAD)
    preview.anchorRight = true
    preview.anchorBottom = true
    preview:initialise()
    preview:instantiate()
    self:addChild(preview)
    self.preview = preview

    local by = bottom - btnH
    self.fewer = newButton(self, rx, by, btnH, "-", "FEWER", CSB_Window.onLevels)
    self.more = newButton(self, rx + self.fewer.width + PAD + textWidth(getText("IGUI_CSB_LevelsShown", 8, 8)) + PAD,
        by, btnH, "+", "MORE", CSB_Window.onLevels)

    self.build = newButton(self, PAD, by, btnH, getText("IGUI_CSB_Build"), "BUILD", CSB_Window.onBuild, true)
    self.forget = newButton(self, PAD * 2 + self.build.width, by, btnH, getText("IGUI_CSB_Forget"), "FORGET",
        CSB_Window.onForget, true)
    self.build:enableAcceptColor()
    self.forget:enableCancelColor()
    self:select(nil)
end

-- How many levels the big picture shows, from the ground up.
function CSB_Window:shownLevels()
    if not self.bp then return 0 end
    return self.maxZ and self.maxZ + 1 or self.bp.levels
end

function CSB_Window:updateButtons()
    local bp = self.bp
    self.build:setEnable(bp ~= nil)
    self.forget:setEnable(bp ~= nil)
    self.fewer:setEnable(bp ~= nil and self:shownLevels() > 1)
    self.more:setEnable(bp ~= nil and self:shownLevels() < bp.levels)
    self.preview.maxZ = self.maxZ
end

-- Shows bp in the big picture (nil: none). A building studied again keeps
-- the levels shown.
function CSB_Window:select(bp)
    if not (bp and self.bp and bp.id == self.bp.id) then self.maxZ = nil end
    self.bp = bp
    self.preview.bp = bp
    self:updateButtons()
end

-- Reads the list again, keeping the building picked when it is still known.
function CSB_Window:refresh()
    self.revision = CSB.Store.revision
    local list = self.list
    local keep, before = self.bp and self.bp.id, list.selected
    list:clear()
    local pick
    for i, bp in ipairs(CSB.Store.list(self.player)) do
        list:addItem(bp.name, bp)
        if bp.id == keep then pick = i end
    end
    if #list.items == 0 then
        self:select(nil)
        return
    end
    list.selected = pick or math.max(1, math.min(before, #list.items))
    self:select(list.items[list.selected].item)
end

function CSB_Window:onLevels(button)
    if not self.bp then return end
    local levels = self.bp.levels
    local shown = self:shownLevels() + (button.internal == "MORE" and 1 or -1)
    shown = math.max(1, math.min(shown, levels))
    self.maxZ = shown < levels and shown - 1 or nil
    self:updateButtons()
end

function CSB_Window:onBuild()
    if not self.bp then return end
    getCell():setDrag(CSB_Cursor:new(self.player, self.bp), self.playerNum)
    self:close()
end

function CSB_Window:onForget()
    local bp = self.bp
    if not bp then return end
    local w, h = 350, 150
    local modal = ISModalDialog:new(self:getX() + (self:getWidth() - w) / 2, self:getY() + (self:getHeight() - h) / 2, w, h,
        getText("IGUI_CSB_ForgetConfirm", bp.name), true, self, CSB_Window.onForgetAnswer, self.playerNum, bp)
    modal:initialise()
    modal:addToUIManager()
end

function CSB_Window:onForgetAnswer(button, bp)
    if button.internal ~= "YES" then return end
    CSB.Store.forget(self.player, bp.id)
    self.player:setHaloNote(getText("IGUI_CSB_Forgot", bp.name))
end

function CSB_Window:update()
    ISCollapsableWindow.update(self)
    if self.player:isDead() then
        self:close()
        return
    end
    if self.revision ~= CSB.Store.revision then self:refresh() end
end

function CSB_Window:render()
    ISCollapsableWindow.render(self)
    if self.isCollapsed or not self.bp then return end
    local text = getText("IGUI_CSB_LevelsShown", self:shownLevels(), self.bp.levels)
    -- the buttons move when the window is resized: ask where they are now
    local fewer, small = self.fewer, fontHeight(UIFont.Small)
    self:drawText(text, fewer:getX() + fewer:getWidth() + PAD, fewer:getY() + (fewer:getHeight() - small) / 2,
        0.9, 0.9, 0.9, 1, UIFont.Small)
end

function CSB_Window:close()
    CSB.Window.byPlayer[self.playerNum] = nil
    self:removeFromUIManager()
end

function CSB_Window:new(player)
    local playerNum = player:getPlayerNum()
    local w, h = 780, 520
    local x = getPlayerScreenLeft(playerNum) + (getPlayerScreenWidth(playerNum) - w) / 2
    local y = getPlayerScreenTop(playerNum) + (getPlayerScreenHeight(playerNum) - h) / 2
    local o = ISCollapsableWindow.new(self, x, y, w, h)
    o.player = player
    o.playerNum = playerNum
    o.title = getText("IGUI_CSB_WindowTitle")
    o.minimumWidth = 600
    o.minimumHeight = 360
    o.revision = -1     -- read the list on the first update
    return o
end

-- Opens the window for the player, or brings it to the front.
function CSB.Window.show(player)
    local window = CSB.Window.byPlayer[player:getPlayerNum()]
    if not window then
        window = CSB_Window:new(player)
        window:initialise()
        window:addToUIManager()
        CSB.Window.byPlayer[window.playerNum] = window
    end
    window:setVisible(true)
    window:bringToTop()
    return window
end
