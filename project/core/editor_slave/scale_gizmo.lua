--------------------------------------------------
-- Utility functions & constants
--------------------------------------------------

local min_scale_factor = 0.01
local tip_scale = 0.055

local colors = {
	inactive = function() return Color(127, 127, 127) end,
	accent = function() return Color(100, 220, 255) end
}

local function camera_normal_to_point(editor_camera, point)
	local camera_pose = editor_camera:pose()
	local camera_position = Matrix4x4.translation(camera_pose)
	local camera_to_point = point - camera_position
	local normal = Vector3.normalize(camera_to_point)
	return normal
end

local function camera_distance_to_point(editor_camera, point)
	local camera_pose = editor_camera:pose()
	local camera_position = Matrix4x4.translation(camera_pose)
	local camera_forward_vector = Matrix4x4.y(camera_pose)
	local camera_to_point = point - camera_position
	local dp = Vector3.dot(camera_to_point, camera_forward_vector)
	return -dp
end

local function draw_box(editor_camera, gui, material, layer, radius, tm, color)
	local nv, nq, nm = Script.temp_count()
	local zero = Vector3(0, 0, 0)
	local center = Matrix4x4.translation(tm)
	local camera_normal = camera_normal_to_point(editor_camera, center)
	local light_from_camera = Func.partial(Lighting.diffuse, camera_normal, Color(255, 255, 255))
	local size = Vector3(radius.x * 2, radius.y * 2, 0)

	local function make_side(x, y, z)
		local r = radius
		local rect_tm = Matrix4x4.from_axes(x, y, z, center + r.x * -x + r.y * y + r.z * -z)
		local color = light_from_camera(Matrix4x4.y(rect_tm), color)
		local side = { rect_tm, color }
		return side
	end

	local function side_distance_to_camera(side)
		local m = side[1]
		local face_center = Matrix4x4.translation(m) + Matrix4x4.x(m) * (size.x / 2) + Matrix4x4.z(m) * (size.y / 2)
		return camera_distance_to_point(editor_camera, face_center)
	end

	local x = Matrix4x4.x(tm)
	local y = Matrix4x4.y(tm)
	local z = Matrix4x4.z(tm)

	local sides = {
		make_side(x, y, z),    -- front
		make_side(-x, -y, -z), -- back
		make_side(x, z, -y),   -- top
		make_side(-x, -z, y),  -- bottom
		make_side(-y, x, z),   -- right
		make_side(y, -x, -z)   -- left
	}

	for i, side in ipairs(Array.sort_by(sides, side_distance_to_camera)) do
		Gui.bitmap_3d(gui, material, side[1], zero, layer + i, size, side[2])
	end

	Script.set_temp_count(nv, nq, nm)
end

local function draw_box_handle(editor_camera, gui, material, color, box_tm, axis_length, layer)
	local tip_radius = axis_length * tip_scale
	local box_radius = Vector3(tip_radius, tip_radius, tip_radius)
	draw_box(editor_camera, gui, material, layer, box_radius, box_tm, color)
end

local function box_hit_test(editor_camera, x, y, tm, offset, size)
	local cam_pos, cam_dir = editor_camera:camera_ray(x, y)
	local m = Matrix4x4.copy(tm)
	Matrix4x4.set_translation(m, Matrix4x4.transform(tm, offset))
	return Math.ray_box_intersection(cam_pos, cam_dir, m, size)
end

local function best_box_hit_test(editor_camera, x, y, tm, values)
	local min = nil
	local best = nil
	
	for _, v in ipairs(values) do
		local hit = box_hit_test(editor_camera, x, y, tm, v[1], v[2])
		
		if hit > 0 and (min == nil or hit < min) then
			min = hit
			best = v[3]
		end
	end
	
	return best
end


--------------------------------------------------
-- ScaleGizmo
--------------------------------------------------

ScaleGizmo = class(ScaleGizmo)

function ScaleGizmo:init()
	self._position = Vector3Box()
	self._rotation = QuaternionBox()
	self._delta_scale_factors = Vector3Box(1, 1, 1)
	self._drag_start = Vector3Box()
	self._is_non_uniform_scaling_supported = true
end

function ScaleGizmo:x_axis()
	return Quaternion.right(self:rotation())
end

function ScaleGizmo:y_axis()
	return Quaternion.forward(self:rotation())
end

function ScaleGizmo:z_axis()
	return Quaternion.up(self:rotation())
end

function ScaleGizmo:position()
	return self._position:unbox()
end

function ScaleGizmo:set_position(position)
	self._position:store(position)
end

function ScaleGizmo:rotation()
	return self._rotation:unbox()
end

function ScaleGizmo:set_rotation(rotation)
	self._rotation:store(rotation)
end

function ScaleGizmo:pose()
	return Matrix4x4.from_quaternion_position(self:rotation(), self:position())
end

function ScaleGizmo:set_pose(tm)
	self:set_rotation(Matrix4x4.rotation(tm))
	self:set_position(Matrix4x4.translation(tm))
end

function ScaleGizmo:delta_scale_factors()
	return self._delta_scale_factors:unbox()
end

function ScaleGizmo:reset_delta_scale_factors()
	self._delta_scale_factors:store(1, 1, 1)
end

function ScaleGizmo:draw(gui, lines, editor_camera, hide_unselected)
	local p = self:position()
	local x = self:x_axis()
	local y = self:y_axis()
	local z = self:z_axis()
	
	local tm = Matrix4x4.from_axes(x, y, z, p)
	local length = self:_axis_length(editor_camera)
	local scale_factors = self:delta_scale_factors()
	
	local x_color = Color(255, 0, 0)
	local y_color = Color(0, 255, 0)
	local z_color = Color(0, 0, 255)
	local w_color = colors.accent()
	local yellow = Color(255, 255, 0)
	local gray = colors.inactive()
	local transparent = Color(0, 0, 0, 0)
	
	local material = "depth_test_disabled"
	local base_layer = 100
	local camera_pose = editor_camera:pose()
	local camera_position = Matrix4x4.translation(camera_pose)
	local camera_forward_vector = Matrix4x4.y(camera_pose)

	local function tip_position(axis_index)
		local tip_radius = length * tip_scale
		local scaled_axis = Matrix4x4.axis(tm, axis_index) * Vector3.element(scale_factors, axis_index)
		local box_center = Matrix4x4.translation(tm) + scaled_axis * (length - tip_radius)
		return box_center
	end

	local function axis_color(axis_name, default_color)
		if self:_is_axis_selected(axis_name) then return yellow end
		if hide_unselected then return transparent end
		if not self._is_non_uniform_scaling_supported and axis_name ~= "xyz" then return gray end
		return default_color
	end

	local function box_distance_from_camera(handle)
		local box_center = handle[1]
		local camera_to_box_center = box_center - camera_position
		local dp = Vector3.dot(camera_to_box_center, camera_forward_vector)
		return -dp
	end

	local handles = {
		{ tip_position(1), axis_color("x", x_color), x },
		{ tip_position(2), axis_color("y", y_color), y },
		{ tip_position(3), axis_color("z", z_color), z },
		{ p, self._selected == "xyz" and yellow or w_color },
	}

	local box_tm = Matrix4x4.copy(tm)

	for i, handle in ipairs(Array.sort_by(handles, box_distance_from_camera)) do
		local layer = base_layer + i
		local position = handle[1]
		local color = handle[2]
		local axis = handle[3]
		Matrix4x4.set_translation(box_tm, position)
		draw_box_handle(editor_camera, gui, material, color, box_tm, length, layer)
		
		if axis ~= nil then
			local tip_radius = length * tip_scale
			local line_start = p + axis * tip_radius
			local line_end = position - axis * tip_radius
			LineObject.add_line(lines, color, line_start, line_end)
		end
	end
	
	local b = length / 2
	
	local function t(pos)
		return Matrix4x4.transform(tm, Vector3.multiply_elements(pos, scale_factors))
	end
	
	local s = self._selected
	LineObject.add_line(lines, axis_color("xy", x_color), t(Vector3(b, 0, 0)), t(Vector3(b, b, 0)))
	LineObject.add_line(lines, axis_color("xz", x_color), t(Vector3(b, 0, 0)), t(Vector3(b, 0, b)))
	LineObject.add_line(lines, axis_color("xy", y_color), t(Vector3(0, b, 0)), t(Vector3(b, b, 0)))
	LineObject.add_line(lines, axis_color("yz", y_color), t(Vector3(0, b, 0)), t(Vector3(0, b, b)))
	LineObject.add_line(lines, axis_color("xz", z_color), t(Vector3(0, 0, b)), t(Vector3(b, 0, b)))
	LineObject.add_line(lines, axis_color("yz", z_color), t(Vector3(0, 0, b)), t(Vector3(0, b, b)))
end

function ScaleGizmo:draw_drag_start(gui, editor_camera)
	local p = self:position()
	local r = self:rotation()
	local length = self:_axis_length(editor_camera)
	local color = colors.inactive()
	local material = "depth_test_disabled"
	local base_layer = 90
	local tip_radius = length * tip_scale
	local box_radius = Vector3(tip_radius, tip_radius, tip_radius)
	local box_pose = Matrix4x4.from_quaternion_position
	local line_length = length - tip_radius
	
	local handles = {
		x = box_pose(r, p + self:x_axis() * line_length),
		y = box_pose(r, p + self:y_axis() * line_length),
		z = box_pose(r, p + self:z_axis() * line_length)
	}

	for axis_name, box_tm in pairs(handles) do
		if self:_is_axis_selected(axis_name) then
			draw_box(editor_camera, gui, material, base_layer, box_radius, box_tm, color)
		end
	end
end

function ScaleGizmo:set_non_uniform_scaling_supported(supported)
	assert(supported == true or supported == false)
	self._is_non_uniform_scaling_supported = supported
end

function ScaleGizmo:select_axes(editor_camera, x, y)
	local axis_length = self:_axis_length(editor_camera)
	local hit_box_length = axis_length

	local tm = self:pose()
	local l = hit_box_length / 2
	local w = axis_length * tip_scale
	local b = axis_length / 4
	local pick = Func.partial(best_box_hit_test, editor_camera, x, y, tm)
	local box_radius = Vector3(w, w, w)

	if self._is_non_uniform_scaling_supported then
		-- Perform hit test against boxes first. Only perform axis tests if we don't hit a box.
		self._selected = pick {
			{ Vector3(l, 0, 0), box_radius, "x" },
			{ Vector3(0, l, 0), box_radius, "y" },
			{ Vector3(0, 0, l), box_radius, "z" },
			{ Vector3(0, 0, 0), box_radius, "xyz" }
		} or pick {
			{ Vector3(l, 0, 0), Vector3(l, w, w), "x" },
			{ Vector3(0, l, 0), Vector3(w, l, w), "y" },
			{ Vector3(0, 0, l), Vector3(w, w, l), "z" },
			{ Vector3(0, b, b), Vector3(0, b, b), "yz" },
			{ Vector3(b, 0, b), Vector3(b, 0, b), "xz" },
			{ Vector3(b, b, 0), Vector3(b, b, 0), "xy" }
		}
	else
		-- Only support the uniform scaling handle.
		self._selected = pick { { Vector3(0, 0, 0), box_radius, "xyz" } }
	end

	self._hovered = self._selected

	if EditorApi:is_axis_plane_modifier_held() and self._selected ~= nil and #self._selected == 1 then
		local axis_planes = { x = "yz", y = "xz", z = "xy" }
		self._selected = axis_planes[self._selected]
	end
end

function ScaleGizmo:selected_axes()
	return self._selected
end

function ScaleGizmo:set_selected_axes(axes)
	assert(axes == nil or Array.contains({ "x", "y", "z", "xy", "xz", "yz", "xyz" }, axes))
	self._selected = axes
end

function ScaleGizmo:is_axes_selected()
	return self._selected ~= nil
end

function ScaleGizmo:_is_axis_selected(axis_name)
	if self._selected == nil then return false end
	if self._selected == "xyz" then return true end
	return string.find(self._selected, axis_name) ~= nil
end

function ScaleGizmo:_is_axis_hovered(axis_name)
	if self._hovered == nil then return false end
	if self._hovered == "xyz" then return true end
	return string.find(self._hovered, axis_name) ~= nil
end

function ScaleGizmo:start_scale(editor_camera, x, y)
	self._delta_scale_factors:store(1, 1, 1)
	local drag_start_scale = self._selected == "xyz" and Vector3(1, 1, 1) or self:_scale_factors_at(editor_camera, x, y)
	self._drag_start:store(drag_start_scale)
end

function ScaleGizmo:delta_scale(editor_camera, x, y)
	local drag_end = self:_scale_factors_at(editor_camera, x, y)
	local s = self._drag_start:unbox()
	local e = drag_end
	local clamp = Func.partial(math.max, min_scale_factor)
	local stored_delta = Vector3(clamp(e.x / s.x), clamp(e.y / s.y), clamp(e.z / s.z))
	self._delta_scale_factors:store(stored_delta)
end

function ScaleGizmo:_scale_factors_at(editor_camera, x, y)
	local cam_pos, cam_dir = editor_camera:camera_ray(x, y)
	local position = self:position()
	local scaled_axis_indices = Array.choosei({"x", "y", "z"}, function(i, v) return self:_is_axis_selected(v) and i or nil end)
	local axis = self:_drag_axis(editor_camera)
	local distance_along_axis = axis ~= nil and Tuple.second(Intersect.ray_line(cam_pos, cam_dir, position, position + axis)) or nil
	local scale_factor = distance_along_axis == nil and 1 or distance_along_axis / self:_axis_length(editor_camera) + 1
	local scale_factors = Vector3(1, 1, 1)
	Array.iter(scaled_axis_indices, function(axis_index) Vector3.set_element(scale_factors, axis_index, scale_factor) end)
	return scale_factors
end

function ScaleGizmo:_axis_length(editor_camera)
	return editor_camera:screen_size_to_world_size(self:position(), 85)
end

function ScaleGizmo:_axis_by_index(axis_index)
	if axis_index == 1 then
		return self:x_axis()
	elseif axis_index == 2 then
		return self:y_axis()
	elseif axis_index == 3 then
		return self:z_axis()
	end

	assert(axis_index >= 1 and axis_index <= 3)
end

function ScaleGizmo:_drag_axis(editor_camera)
	local hovered_axis_indices = Array.choosei({"x", "y", "z"}, function(i, v) return self:_is_axis_hovered(v) and i or nil end)

	if #hovered_axis_indices == 3 then
		return Matrix4x4.right(editor_camera:pose())
	end

	local axis = Vector3.normalize(Array.map(hovered_axis_indices, Func.method("_axis_by_index", self)):fold(Vector3(0, 0, 0), Vector3.add))
	return axis
end
