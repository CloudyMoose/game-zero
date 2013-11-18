--------------------------------------------------
-- Utility functions
--------------------------------------------------

local function screen_length_at_position(position, vector)
	return LevelEditor.editor_camera:screen_length_at_position(position, vector)
end

local function snap_vector(tm, vector)
	local size = LevelEditor.grid.size
	if size == 0 then return vector end
	
	local origin = Matrix4x4.translation(tm)
	vector = vector - origin

	local x_axis = Matrix4x4.x(tm)
	local y_axis = Matrix4x4.y(tm)
	local z_axis = Matrix4x4.z(tm)
	local x_dp = Vector3.dot(vector, x_axis)
	local y_dp = Vector3.dot(vector, y_axis)
	local z_dp = Vector3.dot(vector, z_axis)
	
	local snapped =
		x_axis * math.floor(x_dp / size + 0.5) * size +
		y_axis * math.floor(y_dp / size + 0.5) * size +
		z_axis * math.floor(z_dp / size + 0.5) * size
	
	return snapped + origin
end

local function snap_xy(tm, vector)
	local size = LevelEditor.grid.size
	if size == 0 then return vector end
	
	local x_axis = Matrix4x4.x(tm)
	local y_axis = Matrix4x4.y(tm)
	local z_axis = Matrix4x4.z(tm)
	local x_dp = Vector3.dot(vector, x_axis)
	local y_dp = Vector3.dot(vector, y_axis)
	local z_dp = Vector3.dot(vector, z_axis)
	
	local snapped =
		x_axis * math.floor(x_dp / size + 0.5) * size +
		y_axis * math.floor(y_dp / size + 0.5) * size +
		z_axis * z_dp
	
	return snapped
end


--------------------------------------------------
-- GridPlane functions
--------------------------------------------------

GridPlane = GridPlane or {}

function GridPlane.snap_offset(tm, offset, from_point)
	local size = LevelEditor.grid.size
	if size == 0 then return offset end
	
	local offsetted_point = from_point + offset
	local snapped_point = snap_vector(tm, offsetted_point)
	local snapped_offset = snapped_point - from_point
	return snapped_offset
end

function GridPlane.snap_mouse(tm, plane_height, x, y)
	local cam_pos, cam_dir = LevelEditor:camera_ray(x, y)
	local plane_normal = Matrix4x4.up(tm)
	local plane_point = Matrix4x4.translation(tm) + plane_normal * plane_height
	local plane = Plane.from_point_and_normal(plane_point, plane_normal)
	local distance = Intersect.ray_plane(cam_pos, cam_dir, plane)
	local unsnapped_point = distance == nil and Plane.point(plane) or cam_pos + cam_dir * distance
	local snapped_point = snap_xy(tm, unsnapped_point)
	return snapped_point, unsnapped_point
end

function GridPlane.snap_number(size, number)
	return size == 0 and number or math.floor(number / size + 0.5) * size
end

function GridPlane.draw(line_object, color, tm, center, axes)
	local size = LevelEditor.grid.size
	if size == 0 then return end
	
	local grid_center = snap_vector(tm, center)
	local x = nil
	local y = nil

	if axes == "z" then
		x = Matrix4x4.z(tm)
		y = Array.map({ "x", "y" }, function(a) return Matrix4x4[a](tm) end)
				 :sort_by(Func.partial(screen_length_at_position, grid_center))[2]
	elseif axes == "xz" then
		x = Matrix4x4.z(tm)
		y = Matrix4x4.x(tm)
	elseif axes == "yz" then
		x = Matrix4x4.z(tm)
		y = Matrix4x4.y(tm)
	else
		x = Matrix4x4.x(tm)
		y = Matrix4x4.y(tm)
	end

	local transparent_color = Blend.color_with_alpha(color, 0)
	
	for i = -10, 10 do
		local abs_i = math.abs(i)

		for j = -10, 10 do
			local abs_j = math.abs(j)

			local alpha = math.min(abs_i * abs_i + abs_j * abs_j, 100) / 100
			local line_color = Interpolate.Linear.color(color, transparent_color, alpha)
			local p = grid_center + (x * i * size)+ (y * j * size)
			LineObject.add_line(line_object, line_color, -size / 2 * x + p, size / 2 * x + p)
			LineObject.add_line(line_object, line_color, -size / 2 * y + p, size / 2 * y + p)
		end
	end
end

function GridPlane.draw_cross(line_object, tm, center)
	if LevelEditor.grid.size == 0 then return end
	
	local size = LevelEditor.editor_camera:screen_size_to_world_size(center, 5)
	local color = Color(0, 255, 0)
	local x = Matrix4x4.x(tm)
	local y = Matrix4x4.y(tm)
	local x_span = x * size
	local y_span = y * size
	LineObject.add_line(line_object, color, center - x_span, center + x_span)
	LineObject.add_line(line_object, color, center - y_span, center + y_span)
end
