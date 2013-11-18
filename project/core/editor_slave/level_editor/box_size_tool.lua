--------------------------------------------------
-- Utility functions
--------------------------------------------------

local function is_box_object(level_object)
	local kind = kind_of(level_object)
	return kind == Prototype or kind == Trigger
end

local box_object_diameter = Func.compose(Func.method("radius"), Op.mul(2))

local function major_axis(radius, local_point)
	local switch = {
		x_pos = { 1, 1 },
		x_neg = { 1, -1 },
		y_pos = { 2, 1 },
		y_neg = { 2, -1 },
		z_pos = { 3, 1 },
		z_neg = { 3, -1 }
	}

	local x_component = local_point.x / radius.x
	local y_component = local_point.y / radius.y
	local z_component = local_point.z / radius.z
	local normalized_point = Vector3(x_component, y_component, z_component)
	local axis_name = Geometry.major_axis_name(normalized_point)
	local axis_index, axis_sign = unpack(switch[axis_name])
	return axis_index, axis_sign
end

local function pick_box_object(x, y)
	local ray_start, ray_dir = LevelEditor:camera_ray(x, y)
	local ray_length = LevelEditor.editor_camera:far_range()
	local box_object, distance_along_ray = Picking.raycast(Picking.is_selectable, LevelEditor.objects, ray_start, ray_dir, ray_length)
	box_object = Nilable.filter(box_object, is_box_object)

	if box_object == nil then
		return nil, nil, nil, nil
	end

	local world_point = ray_start + ray_dir * distance_along_ray
	local axis_pick_point = box_object:to_local(ray_start + ray_dir * (distance_along_ray - 0.001))
	local axis_pick_radius = box_object:radius() + Vector3(0.0001, 0.0001, 0.0001) 
	local axis_index, axis_sign = major_axis(axis_pick_radius, axis_pick_point)
	return box_object, axis_index, axis_sign, world_point
end

local function draw_face_highlight(axis_index, axis_sign, box_object)
	assert(is_box_object(box_object))
	local y = axis_index
	local x = (y % 3) + 1
	local z = (x % 3) + 1
	local tm, r = box_object:box()
	local m = Matrix4x4.copy(tm)
	Matrix4x4.set_x(m, Matrix4x4.axis(tm, x))
	Matrix4x4.set_y(m, Matrix4x4.axis(tm, y) * axis_sign)
	Matrix4x4.set_z(m, Matrix4x4.axis(tm, z))
	
	local size = Vector3(Vector3.element(r, x), Vector3.element(r, z), Vector3.element(r, y))
	local highlight_color = box_object:face_highlight_color()
	Gui.rect_3d(LevelEditor.world_gui, m, Vector3(-size.x, -size.y, size.z + 0.01), 0, Vector3(2 * size.x, 2 * size.y, 0), highlight_color)
end

local quaternion_axis_functions_by_axis_index = { Quaternion.right, Quaternion.forward, Quaternion.up }

local function quaternion_axis(quaternion, axis_index)
	assert(axis_index  ~= nil)
	local axis_function = quaternion_axis_functions_by_axis_index[axis_index]
	assert(axis_function ~= nil)
	local axis = axis_function(quaternion)
	return axis
end

local function box_object_axis(box_object, axis_index, axis_sign)
	assert(is_box_object(box_object))
	local rotation = box_object:local_rotation()
	local axis = quaternion_axis(rotation, axis_index) * axis_sign
	return axis
end


--------------------------------------------------
-- BoxSizeTool
--------------------------------------------------

BoxSizeTool = class(BoxSizeTool, Tool)
BoxSizeTool.Behaviors = BoxSizeTool.Behaviors or {}
local Behaviors = BoxSizeTool.Behaviors

function BoxSizeTool:init()
	self._behavior = Behaviors.Idle()
end

function BoxSizeTool:coordinates()
	return self._behavior:coordinates(self)
end

function BoxSizeTool:update()
	if self._behavior.update ~= nil then
		self._behavior:update(self)
	end
end

function BoxSizeTool:mouse_down(x, y)
	if self._behavior.mouse_down ~= nil then
		self._behavior:mouse_down(self, x, y)
	end
end

function BoxSizeTool:mouse_move(x, y)
	if self._behavior.mouse_move ~= nil then
		self._behavior:mouse_move(self, x, y)
	end
end

function BoxSizeTool:mouse_up(x, y)
	if self._behavior.mouse_up ~= nil then
		self._behavior:mouse_up(self, x, y)
	end
end


--------------------------------------------------
-- Idle behavior
--------------------------------------------------

Behaviors.Idle = class(Behaviors.Idle)

function Behaviors.Idle:init()
	self._box_object_id = nil
	self._axis_index = nil
	self._axis_sign = nil
end

function Behaviors.Idle:coordinates(tool)
	return Nilable.bind(self:_box_object(), box_object_diameter)
end

function Behaviors.Idle:update(tool)
	Nilable.iter(self:_box_object(), Func.partial(draw_face_highlight, self._axis_index, self._axis_sign))
end

function Behaviors.Idle:mouse_down(tool, x, y)
	local box_object, axis_index, axis_sign, intersection_point = pick_box_object(x, y)
	
	if box_object ~= nil then
		-- Clicked a box face. Select the box and initiate drag.
		LevelEditor.selection:clear()
		LevelEditor.selection:add(box_object.id)
		LevelEditor.selection:send()
		tool._behavior = Behaviors.Dragging(box_object, axis_index, axis_sign, intersection_point)
	end
end

function Behaviors.Idle:mouse_move(tool, x, y)
	local box_object, axis_index, axis_sign = pick_box_object(x, y)
	self._box_object_id = box_object ~= nil and box_object.id or nil
	self._axis_index = axis_index
	self._axis_sign = axis_sign
end

function Behaviors.Idle:_box_object()
	return LevelEditor.objects[self._box_object_id]
end


--------------------------------------------------
-- Dragging behavior
--------------------------------------------------

Behaviors.Dragging = class(Behaviors.DraggingFace)

function Behaviors.Dragging:init(box_object, axis_index, axis_sign, drag_start)
	assert(is_box_object(box_object))
	assert(quaternion_axis_functions_by_axis_index[axis_index] ~= nil)
	assert(axis_sign >= -1.0001 and axis_sign <= 1.0001)
	self._box_object = box_object
	self._axis_index = axis_index
	self._axis_sign = axis_sign
	self._drag_start = Vector3Box(drag_start)
	self._drag_start_box_position = Vector3Box(box_object:local_position())
	self._drag_start_box_radius = Vector3Box(box_object:radius())
	self._drag_delta = Vector3Box()
	self._drag_delta_face_offset = 0
end

function Behaviors.Dragging:coordinates(tool)
	return box_object_diameter(self._box_object)
end

function Behaviors.Dragging:update(tool)
	Nilable.iter(self._box_object, Func.partial(draw_face_highlight, self._axis_index, self._axis_sign))
	self:_draw_grid_plane()
end

function Behaviors.Dragging:mouse_move(tool, x, y)
	self:_update_drag_delta(x, y, self:_snap_function())
	local radius = self._drag_start_box_radius:unbox()
	local component_delta = self._drag_delta_face_offset / 2
	local component = math.max(0, Vector3.element(radius, self._axis_index) + component_delta)
	Vector3.set_element(radius, self._axis_index, component)
	self._box_object:set_radius(radius)
	local axis_scale_factor = Vector3.element(self._box_object:local_scale(), self._axis_index)
	local offset = self:_drag_axis() * component_delta * axis_scale_factor
	local position = self._drag_start_box_position:unbox() + offset
	self._box_object:set_local_position(position)
end

function Behaviors.Dragging:mouse_up(tool, x, y)
	tool._behavior = Behaviors.Idle()
	LevelEditor:modified{self._box_object}
end

function Behaviors.Dragging:_drag_axis()
	return box_object_axis(self._box_object, self._axis_index, self._axis_sign)
end

function Behaviors.Dragging:_update_drag_delta(x, y, snap_func)
	local distance_along_axis, drag_axis = self:_relative_offset_from_drag_start(x, y)

	if distance_along_axis ~= nil then
		local delta = drag_axis * distance_along_axis
		local stored_drag_delta = delta
		local stored_face_offset_delta = distance_along_axis

		if snap_func ~= nil then
			local snapped_delta = snap_func(delta, self._drag_start:unbox())
			local snapped_distance_along_axis = Vector3.dot(snapped_delta, drag_axis)
			stored_drag_delta = drag_axis * snapped_distance_along_axis
			stored_face_offset_delta = snapped_distance_along_axis
		end

		local axis_scale_factor = Vector3.element(self._box_object:local_scale(), self._axis_index)

		if axis_scale_factor > 0.00001 then
			stored_face_offset_delta = stored_face_offset_delta / axis_scale_factor
		end

		self._drag_delta:store(stored_drag_delta)
		self._drag_delta_face_offset = stored_face_offset_delta
	end
end

function Behaviors.Dragging:_relative_offset_from_drag_start(x, y)
	local cam_pos, cam_dir = LevelEditor:camera_ray(x, y)
	local drag_start = self._drag_start:unbox()
	local drag_axis = self:_drag_axis()
	local _, distance_along_axis = Intersect.ray_line(cam_pos, cam_dir, drag_start, drag_start + drag_axis)
	return distance_along_axis, drag_axis
end

function Behaviors.Dragging:_snap_function()
	local support_absolute_grid = true
	local grid_origin_pose = self:_grid_origin_pose()
	local excluded_ids_set = Set.of(self._box_object.id)
	return LevelEditor:snap_function(grid_origin_pose, support_absolute_grid, excluded_ids_set)
end

function Behaviors.Dragging:_draw_grid_plane()
	local support_absolute_grid = true
	local grid_origin_pose = self:_grid_origin_pose()
	local grid_center = self._drag_start:unbox() + self._drag_delta:unbox()
	local grid_axis = ({"x", "y", "z"})[self._axis_index]
	LevelEditor:draw_grid_plane(grid_origin_pose, support_absolute_grid, grid_center, grid_axis)
end

function Behaviors.Dragging:_grid_origin_pose()
	return Matrix4x4.from_quaternion_position(self._box_object:local_rotation(), self._drag_start:unbox())
end
