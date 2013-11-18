--------------------------------------------------
-- Utility functions
--------------------------------------------------

local colors = {
	inactive = function() return Color(127, 127, 127) end,
	accent = function() return Color(100, 220, 255) end
}

local function intersect_gizmo(editor_camera, position, radius, rotation_axis, x, y)
	local cam, dir = editor_camera:camera_ray(x, y)
	local rotation_plane = Plane.from_point_and_normal(position, rotation_axis)
	local distance_along_dir = Intersect.ray_plane(cam, dir, rotation_plane)

	if distance_along_dir == nil or distance_along_dir == 0 then
		-- The ray is parallel to the rotation plane.
		-- Find the nearest point on the rotation axis handle to the ray.
		local distance_to_rotation_axis_line, distance_along_rotation_axis = Intersect.ray_line(cam, dir, position, position + rotation_axis)
		local sphere_point_on_rotation_axis_line = position + rotation_axis * distance_along_rotation_axis
		local distance_to_rotation_axis_cylinder = Intersect.ray_sphere(cam, dir, sphere_point_on_rotation_axis_line, radius)
												or distance_to_rotation_axis_line

		local point_on_rotation_axis_cylinder = cam + dir * distance_to_rotation_axis_cylinder
		local point_on_rotation_axis_circle = Project.point_on_plane(point_on_rotation_axis_cylinder, rotation_plane)
		return point_on_rotation_axis_circle
	else
		return cam + dir * distance_along_dir
	end
end

local function draw_square(editor_camera, gui, material, layer, pixel_size, color, center)
	local size = editor_camera:screen_size_to_world_size(center, pixel_size)
	local tm = editor_camera:pose()
	Matrix4x4.set_translation(tm, center)
	Gui.bitmap_3d(gui, material, tm, Vector2(-size / 2, -size / 2), layer, Vector2(size, size), color)
end

local function draw_arc(lines, color, center, radius, vertex_normal, plane_normal, circle_segment_count)
	local x = vertex_normal * radius
	local y = Vector3.cross(vertex_normal, plane_normal) * radius
	local segment_count = circle_segment_count / 2
	local offset_radians = math.pi / -2
	local segment_radians = math.pi / segment_count
	local from = center - y

	for i = 1, segment_count do
		local t = offset_radians + segment_radians * i
		local to = center + x * math.cos(t) + y * math.sin(t)
		LineObject.add_line(lines, color, from, to)
		from = to
	end
end

local function draw_fan(editor_camera, gui, material, center, plane_normal, arc_start, arc_end)
	local x = arc_start - center
	local radius = Vector3.length(x)
	if radius < 0.0001 then return end

	local arc_end_vector = arc_end - center
	local y = Vector3.cross(x, plane_normal)
	local segment_radians = 2 * math.pi / 360

	local start_normal = x / radius
	local end_normal = arc_end_vector / radius
	local x_normal = x / radius
	local y_normal = y / radius

	local fan_radians = math.atan2(Vector3.dot(end_normal, y_normal), Vector3.dot(end_normal, x_normal)) - math.atan2(Vector3.dot(start_normal, y_normal), Vector3.dot(start_normal, x_normal))
	local layer = 100
	local from = arc_start
	local t = 0

	local gray = colors.inactive()
	local start_color = Blend.color_with_alpha(gray, 51)
	local end_color = Blend.color_with_alpha(gray, 153)
	
	while t ~= fan_radians do
		t = fan_radians < 0 and math.max(fan_radians, t - segment_radians) or math.min(t + segment_radians, fan_radians)
		local to = center + x * math.cos(t) + y * math.sin(t)
		local color = Interpolate.Linear.color(start_color, end_color, t / fan_radians)
		Gui.triangle(gui, from, center, to, layer, color, material)
		from = to
	end

	draw_square(editor_camera, gui, material, layer, 5, gray, center)
	draw_square(editor_camera, gui, material, layer, 5, gray, arc_start)
	draw_square(editor_camera, gui, material, layer, 5, gray, arc_end)
end

local function find_arc_vertex_normal(point_on_sphere, gizmo_position, axis_plane_normal)
	local axis_plane = Plane.from_point_and_normal(gizmo_position, axis_plane_normal)
	local axis_plane_point = Project.point_on_plane(point_on_sphere, axis_plane)
	local axis_arc_vertex_normal = Vector3.normalize(axis_plane_point - gizmo_position)
	return axis_arc_vertex_normal
end


--------------------------------------------------
-- RotateGizmo
--------------------------------------------------

RotateGizmo = class(RotateGizmo)

function RotateGizmo:init()
	self._position = Vector3Box()
	self._rotation = QuaternionBox()
	self._rotation_axis = Vector3Box()
	self._delta_rotation = QuaternionBox()
	self._drag_start_handle = Vector3Box(0, 0, 1)
	self._drag_handle = Vector3Box(0, 0, 1)
end

function RotateGizmo:position()
	return self._position:unbox()
end

function RotateGizmo:set_position(position)
	return self._position:store(position)
end

function RotateGizmo:rotation()
	return self._rotation:unbox()
end

function RotateGizmo:set_rotation(rotation)
	self._rotation:store(rotation)
end

function RotateGizmo:pose()
	return Matrix4x4.from_quaternion_position(self:rotation(), self:position())
end

function RotateGizmo:set_pose(tm)
	self:set_rotation(Matrix4x4.rotation(tm))
	self:set_position(Matrix4x4.translation(tm))
end

function RotateGizmo:delta_rotation()
	return self._delta_rotation:unbox()
end

function RotateGizmo:draw(lines, editor_camera)
	local position = self:position()
	local rotation = self:rotation()
	local x_axis = Quaternion.right(rotation)
	local y_axis = Quaternion.forward(rotation)
	local z_axis = Quaternion.up(rotation)
	local radius = self:_radius(editor_camera)
	local outer_radius = self:_outer_radius(editor_camera)
	local segments = 360 / 5
	local gray = colors.inactive()
	local yellow = Color(255, 255, 0)
	local x_color = self._selected == "x" and yellow or Color(255, 0, 0)
	local y_color = self._selected == "y" and yellow or Color(0, 255, 0)
	local z_color = self._selected == "z" and yellow or Color(0, 0, 255)
	local w_color = self._selected == "w" and yellow or colors.accent()
	
	local neg_w_axis
	local point_on_sphere

	if editor_camera:is_orthographic() then
		neg_w_axis = Matrix4x4.forward(editor_camera:pose())
		point_on_sphere = position - neg_w_axis * radius
	else
		local camera_position = Matrix4x4.translation(editor_camera:pose())
		neg_w_axis = Vector3.normalize(position - camera_position)
		local distance_to_sphere = Intersect.ray_sphere(camera_position, neg_w_axis, position, radius)
		point_on_sphere = distance_to_sphere == nil
		   and position - neg_w_axis * radius
			or camera_position + neg_w_axis * distance_to_sphere
	end

	local arc_vertex_normal = Func.partial(find_arc_vertex_normal, point_on_sphere, position)

	-- Draw camera-facing rotation handles.
	LineObject.add_circle(lines, gray, position, radius, neg_w_axis, segments)
	LineObject.add_circle(lines, w_color, position, outer_radius, neg_w_axis, segments)

	-- Draw axis rotation handles.
	draw_arc(lines, x_color, position, radius, arc_vertex_normal(x_axis), x_axis, segments)
	draw_arc(lines, y_color, position, radius, arc_vertex_normal(y_axis), y_axis, segments)
	draw_arc(lines, z_color, position, radius, arc_vertex_normal(z_axis), z_axis, segments)
end

function RotateGizmo:draw_drag_handles(gui, lines, editor_camera)
	local center = self:position()
	local radius = self:_radius(editor_camera)
	local drag_start_handle = self._drag_start_handle:unbox()
	local drag_handle = self._drag_handle:unbox()
	local fan_start = center + drag_start_handle * radius
	local fan_end = center + drag_handle * radius
	local gray = colors.inactive()
	
	LineObject.add_line(lines, gray, center, fan_start)
	LineObject.add_line(lines, gray, center, fan_end)

	local material = "depth_test_disabled"
	local rotation_axis = self._rotation_axis:unbox()
	draw_fan(editor_camera, gui, material, center, rotation_axis, fan_start, fan_end)
end

function RotateGizmo:select_axis(editor_camera, x, y)
	local position = self:position()
	local radius = self:_radius(editor_camera)
	local threshold_distance = editor_camera:screen_size_to_world_size(position, 10)
	local outer_radius = self:_outer_radius(editor_camera)

	-- Picking strategy:
	-- Perform an intersection with the gizmo geometry.
	-- Project the intersection point onto each axis plane in turn.
	-- Ignore points that are too far from the plane, or too far from the circle radius.
	-- If it is close to the plane, and a certain distance from the radius

	local ray_start, ray_direction = editor_camera:camera_ray(x, y)
	local distance_to_sphere = Intersect.ray_sphere(ray_start, ray_direction, position, radius)

	if distance_to_sphere == nil then
		-- We did not hit the sphere, but we might hit the view-aligned axis disc.
		local w_axis = self:_w_axis_normal(editor_camera)
		local distance_to_view_aligned_axis_disc = Intersect.ray_disc(ray_start, ray_direction, position, outer_radius + threshold_distance, w_axis)
		self._selected = distance_to_view_aligned_axis_disc ~= nil and "w" or nil
	else
		-- The ray hit the sphere. Project the sphere intersection point onto each axis plane.
		-- The plane point that is closest to the sphere point determines the selected plane.
		-- If the distance is too great, the selected plane becomes nil.
		local point_on_sphere = ray_start + ray_direction * distance_to_sphere
		local rotation = self:rotation()

		local axis_planes = {
			x = Plane.from_point_and_normal(position, Quaternion.right(rotation)),
			y = Plane.from_point_and_normal(position, Quaternion.forward(rotation)),
			z = Plane.from_point_and_normal(position, Quaternion.up(rotation))
		}

		local function distance_to_axis_handle(axis, plane)
			local point_on_axis_plane = Project.point_on_plane(point_on_sphere, plane)
			local distance_from_plane = Vector3.distance(point_on_axis_plane, point_on_sphere)

			if distance_from_plane > threshold_distance then
				return nil
			end

			local distance_from_circle = math.abs(Vector3.distance(point_on_axis_plane, position) - radius)
			return distance_from_circle <= threshold_distance and distance_from_circle or nil
		end

		self._selected = Dict.min_by(axis_planes, distance_to_axis_handle)
	end
end

function RotateGizmo:is_axis_selected()
	return self._selected ~= nil
end

function RotateGizmo:start_rotate(editor_camera, x, y)
	local gizmo_position = self:position()
	local gizmo_radius = self:_radius(editor_camera)
	local rotation_axis = self:_rotation_axis_normal(editor_camera, self._selected)
	local intersection = intersect_gizmo(editor_camera, gizmo_position, gizmo_radius, rotation_axis, x, y)
	local drag_start_handle = Vector3.normalize(intersection - gizmo_position)
	self._drag_start_handle:store(drag_start_handle)
	self._drag_handle:store(drag_start_handle)
	self._rotation_axis:store(rotation_axis)
	self._delta_rotation:store(Quaternion.identity())
end

function RotateGizmo:delta_rotate(editor_camera, x, y, snap_func)
	assert(Array.contains({ "x", "y", "z", "w" }, self._selected))
	local gizmo_position = self:position()
	local gizmo_radius = self:_radius(editor_camera)
	local rotation_axis = self._rotation_axis:unbox()
	local intersection = intersect_gizmo(editor_camera, gizmo_position, gizmo_radius, rotation_axis, x, y)
	local drag_handle = Vector3.normalize(intersection - gizmo_position)
	local drag_start_handle = self._drag_start_handle:unbox()
	local x_axis = drag_start_handle
	local y_axis = Vector3.cross(drag_start_handle, rotation_axis)
	local radians = math.atan2(Vector3.dot(drag_start_handle, y_axis), Vector3.dot(drag_start_handle, x_axis)) - math.atan2(Vector3.dot(drag_handle, y_axis), Vector3.dot(drag_handle, x_axis))

	if snap_func ~= nil then
		radians = snap_func(radians)
	end

	local delta_rotation = Quaternion.axis_angle(rotation_axis, radians)
	self._delta_rotation:store(delta_rotation)
	self._drag_handle:store(drag_handle)
end

function RotateGizmo:_radius(editor_camera)
	return editor_camera:screen_size_to_world_size(self:position(), 92)
end

function RotateGizmo:_outer_radius(editor_camera)
	return editor_camera:screen_size_to_world_size(self:position(), 105)
end

function RotateGizmo:_rotation_axis_normal(editor_camera, axis)
	if axis == "x" then
		return Quaternion.right(self:rotation())
	elseif axis == "y" then
		return Quaternion.forward(self:rotation())
	elseif axis == "z" then
		return Quaternion.up(self:rotation())
	elseif axis == "w" then
		return self:_w_axis_normal(editor_camera)
	end

	assert(false)
end

function RotateGizmo:_w_axis_normal(editor_camera)
	local camera_pose = editor_camera:pose()
	return editor_camera:is_orthographic()
	   and -Matrix4x4.forward(camera_pose)
	    or Vector3.normalize(Matrix4x4.translation(camera_pose) - self:position())
end
