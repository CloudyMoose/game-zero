require "core/editor_slave/box_selection"
require "core/editor_slave/class"

--------------------------------------------------
-- SelectTool
--------------------------------------------------

SelectTool = class(SelectTool)
SelectTool.Behaviors = SelectTool.Behaviors or {}
local Behaviors = SelectTool.Behaviors

function SelectTool:init()
	self._behavior = Behaviors.Idle()
end

function SelectTool:mouse_down(x, y)
	local selection_changed, could_initiate_drag = false, false
	
	if self._behavior.mouse_down ~= nil then
		selection_changed, could_initiate_drag = self._behavior:mouse_down(self, x, y)
	end

	return selection_changed, could_initiate_drag
end

function SelectTool:mouse_move(x, y)
	if self._behavior.mouse_move ~= nil then
		self._behavior:mouse_move(self, x, y)
	end
end

function SelectTool:mouse_up(x, y)
	if self._behavior.mouse_up ~= nil then
		self._behavior:mouse_up(self, x, y)
	end
end

function SelectTool:update(dt)
	if self._behavior.update ~= nil then
		self._behavior:update(self, dt)
	end
end


--------------------------------------------------
-- Idle behavior
--------------------------------------------------

Behaviors.Idle = class(Behaviors.Idle)

function Behaviors.Idle:init()
end

function Behaviors.Idle:mouse_down(tool, x, y)
	local selection_changed, could_initiate_drag = false, false
	tool._behavior = Behaviors.BoxSelection(x, y)
	return selection_changed, could_initiate_drag
end


--------------------------------------------------
-- BoxSelection behavior
--------------------------------------------------

Behaviors.BoxSelection = class(Behaviors.BoxSelection)

function Behaviors.BoxSelection:init(x, y)
	self._box_selection = BoxSelection()
	self._box_selection:begin_selection(x, y)
end

function Behaviors.BoxSelection:mouse_move(tool, x, y)
	self._box_selection:refresh_selection(x, y)
end

function Behaviors.BoxSelection:mouse_up(tool)
	self._box_selection:end_selection()
	tool._behavior = Behaviors.Idle()
end

function Behaviors.BoxSelection:update(tool, dt)
	self._box_selection:draw(UnitEditor._screen_gui)
end
