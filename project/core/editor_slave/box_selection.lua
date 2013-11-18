require "core/editor_slave/class"

BoxSelection = class(BoxSelection)

function BoxSelection:init()
	self._is_active = false
	self._is_dragging = false
	self._drag_start = Vector3Box()
	self._drag_end = Vector3Box()
end

function BoxSelection:is_active()
	return self._is_active
end

function BoxSelection:is_dragging()
	return self._is_dragging
end

function BoxSelection:drag_start()
	return self._drag_start:unbox()
end

function BoxSelection:drag_end()
	return self._drag_end:unbox()
end

function BoxSelection:top_left()
	local top_left = Vector3.min(self:drag_start(), self:drag_end())
	return top_left
end

function BoxSelection:bottom_right()
	local bottom_right = Vector3.max(self:drag_start(), self:drag_end())
	return bottom_right
end

function BoxSelection:begin_selection(x, y)
	self._is_active = true
	self._is_dragging = false
	self._drag_start:store(x, y, 0)
	self._drag_end:store(x, y, 0)
end

function BoxSelection:refresh_selection(x, y)
	if self._is_active then
		local prev = self:drag_end()
		
		if x ~= prev.x or y ~= prev.y then
			self._drag_end:store(x, y, 0)
			self._is_dragging = true
		end
	end
end

function BoxSelection:end_selection()
	if self._is_active then
		self._is_active = false
		self._is_dragging = false
		self._drag_start:store(0, 0, 0)
		self._drag_end:store(0, 0, 0)
	end
end

function BoxSelection:draw(gui)
	if self._is_dragging then
		local s = self._drag_start:unbox()
		local e = self._drag_end:unbox()
		Gui.rect(gui, s, e - s, Color(128, 0, 255, 0))
	end
end
