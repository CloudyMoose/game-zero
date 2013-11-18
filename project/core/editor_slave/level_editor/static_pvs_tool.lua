--------------------------------------------------
-- Utility functions
--------------------------------------------------

local function draw_bounds(bounds, edge_color, fill_color)
	local bmin = bounds:min()
	local extents = bounds:extents()
	local center = bounds:center()
		
	local c = bounds:corners()
	local layer = 0
	local fill_alpha = Quaternion.to_elements(fill_color)
	local top_color = Interpolate.Linear.color(fill_color, Color(fill_alpha, 255, 255, 255), 0.3)
	local bottom_color = Interpolate.Linear.color(fill_color, Color(fill_alpha, 0, 0, 0), 0.3)
	-- Z+
	Gui.triangle(LevelEditor.world_gui, c[6], c[5], c[7], layer, top_color)
	Gui.triangle(LevelEditor.world_gui, c[7], c[8], c[6], layer, top_color)
	-- Z-
	Gui.triangle(LevelEditor.world_gui, c[4], c[3], c[1], layer, bottom_color)
	Gui.triangle(LevelEditor.world_gui, c[1], c[2], c[4], layer, bottom_color)
	-- Y+
	Gui.triangle(LevelEditor.world_gui, c[5], c[6], c[2], layer, fill_color)
	Gui.triangle(LevelEditor.world_gui, c[2], c[1], c[5], layer, fill_color)
	-- Y-
	Gui.triangle(LevelEditor.world_gui, c[8], c[7], c[3], layer, fill_color)
	Gui.triangle(LevelEditor.world_gui, c[3], c[4], c[8], layer, fill_color)
	-- X+
	Gui.triangle(LevelEditor.world_gui, c[6], c[8], c[4], layer, fill_color)
	Gui.triangle(LevelEditor.world_gui, c[4], c[2], c[6], layer, fill_color)
	-- X-
	Gui.triangle(LevelEditor.world_gui, c[7], c[5], c[1], layer, fill_color)
	Gui.triangle(LevelEditor.world_gui, c[1], c[3], c[7], layer, fill_color)
	
	local s = bounds:slices()
	local cell_size = Vector3.divide_elements(extents * 2.0, Vector3(s['x'], s['y'], s['z']))
	local half_cell = cell_size / 2.0

	
	for x = 1, s['x'] do
		for y = 1, s['y'] do
			for z = 1, s['z'] do
				local c = Vector3.multiply_elements(cell_size, Vector3(x - 1, y - 1, z - 1)) + half_cell
				LineObject.add_box(LevelEditor.lines, edge_color, Matrix4x4.from_translation(bmin + c), half_cell)
			end
		end
	end
end


--------------------------------------------------
-- Model
--------------------------------------------------

PvsVolume = class(PvsVolume)

function PvsVolume:init(min, max)
	self._min = Vector3Box(min)
	self._max = Vector3Box(max)
	self._slices = {x = 1, y = 1, z = 1}
	self:_update_corners()
end

function PvsVolume:set_extremes(pmin, pmax)
	self._min = Vector3Box(pmin)
	self._max = Vector3Box(pmax)
	self:_update_corners()
end

function PvsVolume:set_slices(slices)
	self._slices['x'] = slices['x']
	self._slices['y'] = slices['y']
	self._slices['z'] = slices['z']
end

function PvsVolume:slices()
	return self._slices
end

function PvsVolume:corners()
	return Array.map(self._corners, Func.method("unbox"))
end

function PvsVolume:extents()
	local min, max = self._min:unbox(), self._max:unbox()
	return (max - min) / 2.0
end

function PvsVolume:center()
	local min, max = self._min:unbox(), self._max:unbox()
	local e = (max - min) / 2.0
	return min + e
end

function PvsVolume:min()
	return self._min:unbox()
end

function PvsVolume:max()
	return self._max:unbox()
end

function PvsVolume:_update_corners()
	local e = self:extents()
	local c = self:center()
	local corners = {
		c + Vector3(-e.x, e.y, -e.z),
		c + Vector3(e.x, e.y, -e.z),
		c + Vector3(-e.x, -e.y, -e.z),
		c + Vector3(e.x, -e.y, -e.z),
		c + Vector3(-e.x, e.y, e.z),
		c + Vector3(e.x, e.y, e.z),
		c + Vector3(-e.x, -e.y, e.z),
		c + Vector3(e.x, -e.y, e.z)
	}
	
	self._corners = Array.map(corners, Vector3Box) 
end

function PvsVolume:clone()
	local v = PvsVolume(self:min(), self:max())
	v:set_slices(self:slices())
	return v
end


--------------------------------------------------
-- StaticPvsTool
--------------------------------------------------

StaticPvsTool = class(StaticPvsTool, Tool)
StaticPvsTool.Behaviors = StaticPvsTool.Behaviors or {}
local Behaviors = StaticPvsTool.Behaviors

function StaticPvsTool:init()
	self._fill_color = QuaternionBox(Color(255, 255, 255))
	self._edge_color = QuaternionBox(Color(64, 255, 0, 0))
	self._behavior_stack = { Behaviors.Idle() }
end

function StaticPvsTool:bounds()
	return self._bounds
end

function StaticPvsTool:on_selected()
end

function StaticPvsTool:update_form()
	Application.console_send { type = "set_pvs_bounds", min = self:_behavior():bounds():min(), max = self:_behavior():bounds():max()}
end

function StaticPvsTool:set_bounds(pmin, pmax)
	self:_behavior():bounds():set_extremes(pmin, pmax)
end

function StaticPvsTool:set_slices(slices)
	self:_behavior():bounds():set_slices(slices)
end

function StaticPvsTool:update()
	self:_behavior():draw(self)
end

function StaticPvsTool:mouse_down(x, y)
	self:_behavior():mouse_down(self, x, y)
end

function StaticPvsTool:mouse_move(x, y)
	LevelEditor.move_tool:mouse_move(x, y)
	self:_behavior():mouse_move(self, x, y)
end

function StaticPvsTool:mouse_up(x, y)
	self:_behavior():mouse_up(self)
	LevelEditor.move_tool:mouse_up(x, y)
end

function StaticPvsTool:pick_point(x, y)	
	local screen_points =
		Array.map(self:_behavior():bounds():corners(), function(v) return LevelEditor.world_to_screen(v) end)
		
	local mouse_point = Vector3(x, 0, y)
	local pixel_threshold = 8
	
	local distances = Array.map(screen_points, function(p) return Vector3(p.x, 0, p.z) end)
						   :map(Func.partial(Vector3.distance, mouse_point))
	
	
	local closest = Array.min_byi(screen_points, function(id, _) return distances[id] end)
	local selected_id = nil
	
	if closest ~= nil then
		local point_id = closest
		if distances[point_id] <= pixel_threshold then
			selected_id = point_id
		end
	end
	
	return selected_id
end

function StaticPvsTool:key(key)
	self:_behavior():key(self, key)
end

function StaticPvsTool:_behavior()
	return self._behavior_stack[#self._behavior_stack]
end

function StaticPvsTool:_push_behavior(behavior)
	table.insert(self._behavior_stack, behavior)
end

function StaticPvsTool:_pop_behavior()
	table.remove(self._behavior_stack)
end

function StaticPvsTool:_reset_behavior()
	self._behavior_stack = { Behaviors.Idle() }
end

function StaticPvsTool:_reroot_behavior(behavior)
	self._behavior_stack = { Behaviors.Idle(), behavior }
end


--------------------------------------------------
-- Idle behavior
--------------------------------------------------

Behaviors.Idle = class(Behaviors.Idle)

function Behaviors.Idle:init()
	self._current_point_id = nil
	self._bounds = PvsVolume(Vector3(-1, -1, -1), Vector3(1, 1, 1))
end

function Behaviors.Idle:mouse_down(tool, x, y)
	if self._current_point_id ~= nil then
		new_behavior = Behaviors.Moving(self._current_point_id, self:bounds():clone())
		tool:_push_behavior(new_behavior)
		
		--new_behavior:mouse_move(tool, x, y)
		--new_behavior:mouse_down(tool, x, y)
	end
end

function Behaviors.Idle:mouse_move(tool, x, y)
	self._current_point_id = tool:pick_point(x, y)
end

function Behaviors.Idle:set_bounds(bounds)
	self._bounds = bounds
end

function Behaviors.Idle:bounds()
	return self._bounds
end

function Behaviors.Idle:mouse_up(tool)
end

function Behaviors.Idle:key(tool, key)
end

function Behaviors.Idle:draw(tool)	
	for i, corner in ipairs(self:bounds():corners()) do
		local radius = LevelEditor.editor_camera:screen_size_to_world_size(corner, 6) / 2
		local col = nil
		if self._current_point_id == i then
			col = Color(255, 255, 255)
		else
			col = Color(80, 80, 80)
		end
		LineObject.add_sphere(LevelEditor.lines, col, corner, radius)
	end
	draw_bounds(self:bounds(), Color(80, 80, 80), Color(50, 255, 0, 0))
end


--------------------------------------------------
-- Moving behavior
--------------------------------------------------

Behaviors.Moving = class(Behaviors.Moving)

function Behaviors.Moving:init(point_id, bounds)
	self._move_point_id = point_id
	self._hover_point_id = nil
	self._move_gizmo = MoveGizmo()
	self._bounds = bounds
	self._move_gizmo:set_position(self._bounds:corners()[point_id])
end

function Behaviors.Moving:mouse_down(tool, x, y)
	local is_over_move_gizmo = self._move_gizmo:is_axes_selected()
	
	if is_over_move_gizmo then
		self._move_gizmo:start_move(LevelEditor.editor_camera, x, y)
		
		local center = self._bounds:center()
		local center_to_corner = self._bounds:corners()[self._move_point_id] - center
		new_behavior = Behaviors.Dragging(center - center_to_corner, center + center_to_corner, self._move_gizmo)
		new_behavior:bounds():set_slices(self:bounds():slices())
		tool:_push_behavior(new_behavior)
	elseif self._hover_point_id ~= nil then
		tool:_pop_behavior()
		tool:_behavior():set_bounds(self._bounds)
		tool:_push_behavior(Behaviors.Moving(self._hover_point_id, self._bounds:clone()))
	else
		tool:_pop_behavior()
		tool:_behavior():set_bounds(self._bounds)
	end
end

function Behaviors.Moving:bounds()
	return self._bounds
end

function Behaviors.Moving:mouse_move(tool, x, y)
	self._move_gizmo:select_axes(LevelEditor.editor_camera, x, y, true)
	
	if not self._move_gizmo:is_axes_selected() then
		self._hover_point_id = tool:pick_point(x, y)
	end
end

function Behaviors.Moving:mouse_up(tool)
	--handled by dragging
end

function Behaviors.Moving:key(tool, key)
	if key == "esc" then
		tool:_pop_behavior()
	end
end

function Behaviors.Moving:draw(tool)
	for i, corner in ipairs(self._bounds:corners()) do
		local radius = LevelEditor.editor_camera:screen_size_to_world_size(corner, 6) / 2
		local col = Color(80, 80, 80)
		if self._move_point_id == i then
			col = Color(0, 0, 0)
		elseif self._hover_point_id == i then
			col = Color(255, 255, 255)
		end
		LineObject.add_sphere(LevelEditor.lines, col, corner, radius)
	end
	draw_bounds(self._bounds, Color(80, 80, 80), Color(50, 255, 0, 0))
	self._move_gizmo:draw(LevelEditor.world_gui, LevelEditor.lines_noz, LevelEditor.editor_camera, true)
end


--------------------------------------------------
-- Dragging behavior
--------------------------------------------------

Behaviors.Dragging = class(Behaviors.Dragging)

function Behaviors.Dragging:init(static_point, moving_point, move_gizmo)
	self._move_gizmo = move_gizmo
	self._position = Vector3Box(move_gizmo:position())
	self._bounds = PvsVolume(static_point, moving_point)
end

function Behaviors.Dragging:bounds()
	return self._bounds
end

function Behaviors.Dragging:mouse_down(tool, x, y)	
end

function Behaviors.Dragging:mouse_move(tool, x, y)
	self._move_gizmo:delta_move(LevelEditor.editor_camera, x, y)
	self._position:store(self._move_gizmo:drag_start() + self._move_gizmo:drag_delta())
	self._bounds:set_extremes(self._bounds:min(), self._position:unbox())
end

function Behaviors.Dragging:mouse_up(tool)
	tool:_pop_behavior()
	tool:_behavior():bounds():set_extremes(Vector3.min(self._bounds:min(), self._bounds:max()), Vector3.max(self._bounds:min(), self._bounds:max()))
	tool:update_form()
end

function Behaviors.Dragging:key(tool, key)
	if key == "esc" then
		self._move_gizmo:set_position(self._move_gizmo:drag_start())
		tool:_pop_behavior()
	end
end

function Behaviors.Dragging:draw(tool)
	draw_bounds(self._bounds, Color(80, 80, 80), Color(50, 255, 0, 0))
	self._move_gizmo:draw(LevelEditor.world_gui, LevelEditor.lines_noz, LevelEditor.editor_camera, true)
end

