--------------------------------------------------
-- Utility functions & constants
--------------------------------------------------

local tip_scale = 0.25

local function draw_cone(gui, material, color, base_point, axis, radius, length, segments, layer)
	local x_axis, y_axis = unpack(Array.map({ Vector3.make_axes(axis) }, function(v) return v * radius end))

	local function base_point_at_index(index)
		local t = math.pi * 2 / segments * index;
		return x_axis * math.cos(t) + y_axis * math.sin(t) + base_point;
	end

	local tip_point = length * axis + base_point
	local base_points = Array.init(segments, base_point_at_index)

	for index = 1, #base_points do
		local next_index = Array.cycle_index(base_points, index + 1)
		local base_point_a = base_points[index]
		local base_point_b = base_points[next_index]
		Gui.triangle(gui, base_point_a, base_point_b, tip_point, layer, color, material)
	end
end

local function draw_axis(gui, material, lines, color, p, axis, length, layer)
	local tip_length = length * tip_scale
	local line_length = length - tip_length
	local tip_base_point = p + axis * line_length
	LineObject.add_line(lines, color, p, tip_base_point)
end

local function draw_arrowhead(gui, material, lines, color, p, axis, length, layer)
	local tip_length = length * tip_scale
	local tip_radius = length * tip_scale / 4
	local tip_segments = 16
	local line_length = length - tip_length
	local tip_base_point = p + axis * line_length
	draw_cone(gui, material, color, tip_base_point, axis, tip_radius, tip_length, tip_segments, layer)
end

local function box_hit_test(cam_pos, cam_dir, tm, offset, size)
	local m = Matrix4x4.copy(tm)
	Matrix4x4.set_translation(m, Matrix4x4.transform(tm, offset))
	return Math.ray_box_intersection(cam_pos, cam_dir, m, size)
end

local function iff(t, a, b)
	if t then return a else return b end
end


--------------------------------------------------
-- MoveGizmo
--------------------------------------------------

MoveGizmo = class(MoveGizmo)

function MoveGizmo:init()
	self._rotation = QuaternionBox()
	self._drag_start = Vector3Box(0, 0, 0)
	self._drag_delta = Vector3Box(0, 0, 0)
	self._grab_offset_from_drag_start = Vector3Box(0, 0, 0)
end

function MoveGizmo:x_axis()
	return Quaternion.right(self:rotation())
end

function MoveGizmo:y_axis()
	return Quaternion.forward(self:rotation())
end

function MoveGizmo:z_axis()
	return Quaternion.up(self:rotation())
end

function MoveGizmo:position()
	return self:drag_start() + self:drag_delta()
end

function MoveGizmo:set_position(position)
	self._drag_start:store(position)
	self._drag_delta:store(0, 0, 0)
end

function MoveGizmo:rotation()
	return self._rotation:unbox()
end

function MoveGizmo:set_rotation(q)
	self._rotation:store(q)
end

function MoveGizmo:pose()
	return Matrix4x4.from_quaternion_position(self:rotation(), self:position())
end

function MoveGizmo:set_pose(tm)
	self:set_rotation(Matrix4x4.rotation(tm))
	self:set_position(Matrix4x4.translation(tm))
end

function MoveGizmo:drag_start()
	return self._drag_start:unbox()
end

function MoveGizmo:drag_delta()
	return self._drag_delta:unbox()
end

function MoveGizmo:draw(gui, lines, editor_camera, show_arrowheads)
	local p = self:position()
	local x = self:x_axis()
	local y = self:y_axis()
	local z = self:z_axis()
	
	local tm = Matrix4x4.from_axes(x, y, z, p)
	local length = self:_arrow_length(editor_camera)
	
	local x_color = Color(255, 0, 0)
	local y_color = Color(0, 255, 0)
	local z_color = Color(0, 0, 255)
	local yellow = Color(255, 255, 0)
	
	local material = "depth_test_disabled"
	local base_layer = 100
	local camera_pose = editor_camera:pose()
	local camera_position = Matrix4x4.translation(camera_pose)
	local camera_forward_vector = Matrix4x4.y(camera_pose)

	local function tip_distance_from_camera(arrow)
		local axis = arrow[1]
		local tip = length * axis + p
		local camera_to_tip = tip - camera_position
		local dp = Vector3.dot(camera_to_tip, camera_forward_vector)
		return -dp
	end

	local arrows = {
		{ x, string.find(self._selected or "", "x") and yellow or x_color },
		{ y, string.find(self._selected or "", "y") and yellow or y_color },
		{ z, string.find(self._selected or "", "z") and yellow or z_color }
	}

	for i, arrow in ipairs(Array.sort_by(arrows, tip_distance_from_camera)) do
		draw_axis(gui, material, lines, arrow[2], p, arrow[1], length, base_layer + i)

		if show_arrowheads then
			draw_arrowhead(gui, material, lines, arrow[2], p, arrow[1], length, base_layer + i)
		end
	end
	
	local b = self:_arrow_length(editor_camera) / 4
	
	local function t(pos)
		return Matrix4x4.transform(tm, pos)
	end
	
	LineObject.add_line(lines, iff(self._selected == "xy", yellow, x_color), t(Vector3(b, 0, 0)), t(Vector3(b, b, 0)))
	LineObject.add_line(lines, iff(self._selected == "xz", yellow, x_color), t(Vector3(b, 0, 0)), t(Vector3(b, 0, b)))
	LineObject.add_line(lines, iff(self._selected == "xy", yellow, y_color), t(Vector3(0, b, 0)), t(Vector3(b, b, 0)))
	LineObject.add_line(lines, iff(self._selected == "yz", yellow, y_color), t(Vector3(0, b, 0)), t(Vector3(0, b, b)))
	LineObject.add_line(lines, iff(self._selected == "xz", yellow, z_color), t(Vector3(0, 0, b)), t(Vector3(b, 0, b)))
	LineObject.add_line(lines, iff(self._selected == "yz", yellow, z_color), t(Vector3(0, 0, b)), t(Vector3(0, b, b)))
end

function MoveGizmo:draw_drag_start(lines, editor_camera)
	local p = self:drag_start()
	local x = self:x_axis()
	local y = self:y_axis()
	local z = self:z_axis()
	local length = editor_camera:screen_size_to_world_size(p, 25)
	local x_color = Color(75, 255, 0, 0)
	local y_color = Color(75, 0, 255, 0)
	local z_color = Color(75, 0, 0, 255)
	
	LineObject.add_line(lines, x_color, p, p + x * length)
	LineObject.add_line(lines, y_color, p, p + y * length)
	LineObject.add_line(lines, z_color, p, p + z * length)
end

function MoveGizmo:draw_grid_plane(explicit_grid_origin_pose)
	if not self:is_axes_selected() then return end

	local support_absolute_grid = explicit_grid_origin_pose == nil
	local grid_origin_pose = explicit_grid_origin_pose or self:pose()
	LevelEditor:draw_grid_plane(grid_origin_pose, support_absolute_grid, self:position(), self:selected_axes())
end

function MoveGizmo:select_axes(editor_camera, x, y, show_arrowheads)
	local arrow_length = self:_arrow_length(editor_camera)
	local hit_box_length = show_arrowheads and arrow_length or arrow_length - arrow_length * tip_scale

	local tm = self:pose()
	local l = hit_box_length / 2
	local w = arrow_length * tip_scale / 4
	local b = arrow_length / 8
	
	self._selected = self:_pick(editor_camera, x, y, tm, {
		{ Vector3(l, 0, 0), Vector3(l, w, w), "x" },
		{ Vector3(0, l, 0), Vector3(w, l, w), "y" },
		{ Vector3(0, 0, l), Vector3(w, w, l), "z" },
		{ Vector3(0, b, b), Vector3(0, b, b), "yz" },
		{ Vector3(b, 0, b), Vector3(b, 0, b), "xz" },
		{ Vector3(b, b, 0), Vector3(b, b, 0), "xy" },
	})
end

function MoveGizmo:selected_axes()
	return self._selected
end

function MoveGizmo:set_selected_axes(axes)
	assert(axes == nil or Array.contains({ "x", "y", "z", "xy", "xz", "yz" }, axes))
	self._selected = axes
end

function MoveGizmo:is_axes_selected()
	return self._selected ~= nil
end

function MoveGizmo:is_axis_selected(axis)
	return string.find(self._selected, axis) ~= nil
end

function MoveGizmo:start_move(editor_camera, x, y)
	self._drag_start:store(self:position())
	self._drag_delta:store(0, 0, 0)
	self._grab_offset_from_drag_start:store(self:_relative_offset_from_drag_start(editor_camera, x, y) or Vector3(0, 0, 0))
end

function MoveGizmo:delta_move(editor_camera, x, y, snap_func)
	local mouse_offset_from_drag_start = self:_relative_offset_from_drag_start(editor_camera, x, y)
	
	if mouse_offset_from_drag_start ~= nil then
		local delta = mouse_offset_from_drag_start - self._grab_offset_from_drag_start:unbox()
		local stored_delta = delta

		if snap_func ~= nil then
			local snapped_delta = snap_func(delta, self:drag_start())
			local pose = self:pose()
			stored_delta = Vector3(0, 0, 0)
			
			for _, axis in ipairs{"x", "y", "z"} do
				local movement_axis = Matrix4x4[axis](pose)
				local contribution = self:is_axis_selected(axis) and snapped_delta or delta
				local axis_contribution = Vector3.dot(contribution, movement_axis) * movement_axis
				stored_delta = stored_delta + axis_contribution
			end
		end

		self._drag_delta:store(stored_delta)
	end
end

function MoveGizmo:_relative_offset_from_drag_start(editor_camera, x, y)
	local cam_pos, cam_dir = editor_camera:camera_ray(x, y)
	local drag_start = self:drag_start()
	local movement_axis = self:_movement_axis()
	local movement_plane = self:_movement_plane()
	
	if movement_axis ~= nil then
		-- Restrict to axis.
		local _, distance_along_axis = Intersect.ray_line(cam_pos, cam_dir, drag_start, drag_start + movement_axis)
		if distance_along_axis ~= nil then
			return movement_axis * distance_along_axis
		end
	elseif movement_plane ~= nil then
		-- Restrict to plane.
		local distance_along_cam_dir = Intersect.ray_plane(cam_pos, cam_dir, movement_plane)
		
		if distance_along_cam_dir ~= nil then
			local mouse_point_on_plane = cam_pos + cam_dir * distance_along_cam_dir
			return mouse_point_on_plane - drag_start
		end	
	end
	
	-- No intersection, or no axis selected.
	return nil
end

function MoveGizmo:_movement_axis()
	if self._selected == "x" then
		return self:x_axis()
	elseif self._selected == "y" then
		return self:y_axis()
	elseif self._selected == "z" then
		return self:z_axis()
	else
		return nil
	end
end

function MoveGizmo:_movement_plane()
	if self._selected == "xy" then
		return Plane.from_point_and_vectors(self:drag_start(), self:x_axis(), self:y_axis())
	elseif self._selected == "xz" then
		return Plane.from_point_and_vectors(self:drag_start(), self:x_axis(), self:z_axis())
	elseif self._selected == "yz" then
		return Plane.from_point_and_vectors(self:drag_start(), self:y_axis(), self:z_axis())
	else
		return nil
	end
end

function MoveGizmo:_arrow_length(editor_camera)
	return editor_camera:screen_size_to_world_size(self:position(), 85)
end

function MoveGizmo:_pick(editor_camera, x, y, tm, values)
	local min = nil
	local best_index = nil
	local cam_pos, cam_dir = editor_camera:camera_ray(x, y)
	
	for index, data in ipairs(values) do
		local hit = box_hit_test(cam_pos, cam_dir, tm, data[1], data[2])
		
		if hit > 0 and (min == nil or hit < min) then
			min = hit
			best_index = index
		end
	end

	if best_index == nil then
		return nil
	end

	if EditorApi:is_axis_plane_modifier_held() and best_index <= 3 then
		best_index = best_index + 3
	end

	local best_axis = values[best_index][3]
	return best_axis
end
