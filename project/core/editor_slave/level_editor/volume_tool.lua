--------------------------------------------------
-- Utility functions
--------------------------------------------------

local function spawn_volume(volume)
	assert(kind_of(volume) == Volume)
	assert(Validation.is_object_id(volume.id))
	LevelEditor.objects[volume.id] = volume
	LevelEditor:spawned({volume})
	LevelEditor.selection:clear()
	LevelEditor.selection:add(volume.id)
	LevelEditor.selection:send()
end

local function choose_any_volume(id, level_object)
	return kind_of(level_object) == Volume and level_object or nil
end

local function selected_volume()
	return Dict.pick(LevelEditor.selection:objects(), choose_any_volume)
end

local function volume_creation_height()
	local mouse_point = LevelEditor.mouse.pos
	local spawn_point = LevelEditor:find_spawn_point(mouse_point.x, mouse_point.y)
	return GridPlane.snap_number(LevelEditor.grid.size, spawn_point.z + LevelEditor.grid.size)
end

local function draw_triangles(points, indices, offset, color)
	local layer = 1
	local count = #indices
	
	for i = 1, count, 3 do
		local index_a, index_b, index_c = unpack(indices, i, i + 3)
		local point_a = points[index_a] + offset
		local point_b = points[index_b] + offset
		local point_c = points[index_c] + offset
		Gui.triangle(LevelEditor.world_gui, point_a, point_b, point_c, layer, color)
	end
end

local function draw_side_quad(bottom_left, bottom_right, height_offset, color)
	local layer = 1
	local top_left = bottom_left + height_offset
	local top_right = bottom_right + height_offset
	Gui.triangle(LevelEditor.world_gui, bottom_left, bottom_right, top_right, layer, color)
	Gui.triangle(LevelEditor.world_gui, bottom_left, top_right, top_left, layer, color)
end

local function draw_face_loop(points, height_offset, color)
	local count = #points
	
	for first_point_index = 1, count do
		local second_point_index = (first_point_index % count) + 1
		local first_point = points[first_point_index]
		local second_point = points[second_point_index]
		draw_side_quad(first_point, second_point, height_offset, color)
	end
end

local function draw_line_loop(points, offset, get_line_color)
	local count = #points
	
	for first_point_index = 1, count do
		local second_point_index = (first_point_index % count) + 1
		local color = get_line_color(points, first_point_index, second_point_index)
		local first_point = points[first_point_index] + offset
		local second_point = points[second_point_index] + offset
		LineObject.add_line(LevelEditor.lines, color, first_point, second_point)
	end
end

local function draw_segmentation(points, line_color, edge_vector)
	for _, point in ipairs(points) do
		LineObject.add_line(LevelEditor.lines, line_color, point, point + edge_vector)
	end
end

local function draw_point_handles(points, handle_color, offset)
	offset = offset or Vector3(0, 0, 0)
	
	for _, point in ipairs(points) do
		local world_point = point + offset
		local radius = LevelEditor.editor_camera:screen_size_to_world_size(world_point, 5) / 2
		LineObject.add_sphere(LevelEditor.lines, handle_color, world_point, radius)
	end
end

local function draw_foundation(points, commit_will_close)
	if commit_will_close then
		local color = Color(255, 255, 255)
		draw_line_loop(points, Vector3.zero(), Func.constantly(color))
		draw_point_handles(points, color)
	else
		local close_line_color = Color(128, 128, 128)
		local line_color = Color(255, 255, 255)
		
		local function get_line_color(points, first_point_index, second_point_index)
			return (#points > 2 and second_point_index == 1) and close_line_color or line_color
		end
		
		draw_line_loop(points, Vector3.zero(), get_line_color)
		draw_point_handles(points, Color(0, 0, 0))
	end
end

local function draw_face_split_indicator(bottom_point, up_vector, height)
	local height_offset = up_vector * height
	local top_point = bottom_point + height_offset
	local line_color = Color(100, 255, 255, 255)
	
	-- Draw segmented line.
	local segment_height = 0.1
	local segment_count = height / segment_height
	local segment_offset = up_vector * segment_height
	local top_cap_plane = Plane.from_point_and_normal(top_point, -up_vector)
	
	for i = 0, segment_count - 1, 3 do
		local from = bottom_point + up_vector * (segment_height * i)
		local distance_to_top_cap = Intersect.ray_plane(from, up_vector, top_cap_plane)
		local to = from + up_vector * math.min(segment_height * 2, distance_to_top_cap)
		LineObject.add_line(LevelEditor.lines, line_color, from, to)
	end
	
	draw_point_handles({ bottom_point, top_point }, Color(40, 0, 0, 0))
end

local function draw_editing_representation(points, up_vector, height, selected_point_indices, move_gizmo_controls_top)
	local line_color = Color(0, 0, 0, 0)
	local selected_edge_color = Color(128, 255, 255, 255)
	local affected_cap_color = Color(64, 255, 255, 255)
	local handle_color = Color(0, 0, 0)
	local selected_handle_color = Color(255, 255, 255)
	local height_offset = up_vector * height
	local is_selected_point = function(index, _) return Array.contains(selected_point_indices, index) end
	local selected, unselected = Array.partitioni(points, is_selected_point)
	local is_anything_selected = #selected_point_indices ~= 0
	
	local function get_line_color(is_affected, points, first_point_index, second_point_index)
		local is_selected = is_selected_point(first_point_index) and is_selected_point(second_point_index)
		return is_selected and selected_edge_color or (is_affected and affected_cap_color or line_color)
	end
	
	draw_line_loop(points, Vector3.zero(), Func.partial(get_line_color, is_anything_selected and not move_gizmo_controls_top))
	
	if height > 0.01 then
		draw_line_loop(points, height_offset, Func.partial(get_line_color, is_anything_selected and move_gizmo_controls_top))
		draw_segmentation(unselected, line_color, height_offset)
		draw_segmentation(selected, selected_edge_color, height_offset)
		draw_point_handles(unselected, handle_color, height_offset)
		draw_point_handles(selected, selected_handle_color, height_offset)
	end
	
	draw_point_handles(unselected, handle_color)
	draw_point_handles(selected, selected_handle_color)
end

local function draw_label(text, pose, radius)
	local font, material = "core/editor_slave/gui/arial", "arial"
	local _, max = Gui.text_extents(LevelEditor.world_gui, text, font, 1)
	if Vector3.length(max) < 0.0001 then return end

	local ratio = max.x / max.z
	local center = Matrix4x4.translation(pose)
	local min_size = LevelEditor.editor_camera:screen_size_to_world_size(center, 20)
	local max_size = LevelEditor.editor_camera:screen_size_to_world_size(center, 64)
	local text_size = math.max(min_size, math.min(2 * radius.x / ratio, 2 * radius.z, max_size))
	_, max = Gui.text_extents(LevelEditor.world_gui, text, font, text_size)

	local gui = LevelEditor.world_gui
	local camera = LevelEditor.camera
	local offset = Vector2(-max.x / 2, math.max(-radius.z + min_size / 4, -max.z / 2))
	local layer = 0
	local color = Color(255, 255, 255)

	Gui.text_3d(gui, text, font, text_size, material, pose, offset, layer, color)
end

local function is_selectable_volume(level_object)
	return kind_of(level_object) == Volume and not level_object.hidden and not level_object.unselectable
end

local function find_volume_at_point(x, y)
	local cam_pos, cam_dir = LevelEditor:camera_ray(x, y)
	
	local intersection_distance = function(volume)
		local distance = Math.ray_box_intersection(cam_pos, cam_dir, volume:box())
		return distance >= 0 and distance or nil
	end
	
	local _, closest_volume = Dict.values(LevelEditor.objects)
								  :filter(is_selectable_volume)
								  :min_by(intersection_distance)
	return closest_volume
end

local function unbox_vector_at_height(height, boxed_point)
	local point = boxed_point:unbox()
	Vector3.set_z(point, height)
	return point
end

local function copy_boxed_vector(v)
	return Vector3Box(v:unbox())
end

local function vector3_to_vector2(v)
	return Vector2(v.x, v.z)
end

local function to_local_offset(matrix, vector)
	return Matrix4x4.transform_without_translation(Matrix4x4.inverse(matrix), vector)
end

local function finalize_volume_for_extrude(volume)
	local new_volume = volume:deep_copy()
	
	-- Reorder volume points in CCW order if needed.
	local points = Array.map(new_volume.points, Func.method("unbox"))
	local up_vector = new_volume:up_vector()
	local num_cw_triangles = 0
	local num_ccw_triangles = 0
	
	for index = 1, #points do
		local prev_index = Array.cycle_index(points, index - 1)
		local next_index = Array.cycle_index(points, index + 1)
		local point_a = points[prev_index]
		local point_b = points[index]
		local point_c = points[next_index]
		
		if Geometry.is_triangle_ccw(point_a, point_b, point_c, up_vector) then
			num_ccw_triangles = num_ccw_triangles + 1
		else
			num_cw_triangles = num_cw_triangles + 1
		end
	end
	
	if num_ccw_triangles < num_cw_triangles then
		new_volume:update_points(Array.reverse(new_volume.points):map(Func.method("unbox")))
	end
	
	-- Translate points so they are centered around the move / rotate point.
	local _, _, center = new_volume:box()
	local point_offset = -center
	Vector3.set_z(point_offset, 0)
	local offset_tm = Matrix4x4.from_translation(point_offset)
	
	local function translate_around_center(point)
		local pt = point:unbox()
		return Matrix4x4.transform(offset_tm, pt)
	end
	
	new_volume:update_points(Array.map(new_volume.points, translate_around_center))
	new_volume.top = 0
	new_volume.bottom = 0
	new_volume:set_local_position(center)
	return new_volume
end


--------------------------------------------------
-- Volume
--------------------------------------------------

Volume = class(Volume, Object)

function Volume.create(id, type, pos, rot, scl, name, points, cap_triangulation, color, top, bottom)
	local volume = Volume()
	volume.id = assert(id)
	volume.type = assert(type)
	volume.name = assert(name)
	volume.points = Array.map(points, Vector3Box)
	volume.cap_triangulation = Array.copy(cap_triangulation)
	volume.color:store(color)
	volume.top = assert(top)
	volume.bottom = assert(bottom)
	volume:set_local_position(pos)
	volume:set_local_rotation(rot)
	volume:set_local_scale(scl)
	return volume
end

function Volume:init()
	Object.init(self)
	self.type = ""
	self.name = ""
	self.top = 0
	self.bottom = 0
	self.points = {}
	self.cap_triangulation = {}
	self.color = QuaternionBox(Color(0, 0, 0))
end

function Volume:deep_copy()
	local copy = Volume()
	copy.hidden = self.hidden
	copy.unselectable = self.unselectable
	copy.type = self.type
	copy.name = self.name
	copy.top = self.top
	copy.bottom = self.bottom
	copy.points = Array.map(self.points, copy_boxed_vector)
	copy.cap_triangulation = Array.copy(self.cap_triangulation)
	copy.color:store(self.color:unbox())
	copy:set_local_position(self:local_position())
	copy:set_local_rotation(self:local_rotation())
	copy:set_local_scale(self:local_scale())
	copy:set_local_pivot(self:local_pivot())
	return copy
end

function Volume:duplicate(spawned)
	local copy = setmetatable(Object.duplicate(self, spawned), Volume)
	copy.type = self.type
	copy.name = self.name
	copy.top = self.top
	copy.bottom = self.bottom
	copy.points = Array.map(self.points, copy_boxed_vector)
	copy.cap_triangulation = Array.copy(self.cap_triangulation)
	copy.color = QuaternionBox(self.color:unbox())
	return copy
end

function Volume:spawn_data()
	local sd = Object.spawn_data(self)
	sd.klass = "volume"
	sd.type = self.type
	sd.name = self.name
	sd.top = self.top
	sd.bottom = self.bottom
	sd.points = Array.map(self.points, Func.method("unbox"))
	sd.cap_triangulation = Array.copy(self.cap_triangulation)
	sd.color = self.color:unbox()
	return sd
end

function Volume:update_points(points)
	local can_triangulate = not Geometry.is_planar_face_self_overlapping(points)
	self.points = Array.map(points, Vector3Box)
	self.cap_triangulation = can_triangulate and Geometry.triangulate_face(points, Vector3.up()) or Array.init(0)
	self.radius = nil
	self.center = nil
end

function Volume:draw()
	local bottom_points = self:_world_space_points_at_height(self.bottom)
	local height = self:height()
	local up_vector = self:up_vector()
	local height_offset = up_vector * height
	
	local color = self.color:unbox()
	local side_color = Blend.color_with_alpha(color, 128)
	local bottom_color = Blend.color_with_alpha(Interpolate.Linear.color(color, Color(0, 0, 0), 0.4), 128)
	
	-- Draw bottom.
	draw_triangles(bottom_points, self.cap_triangulation, Vector3.zero(), bottom_color)

	-- Draw name label.
	local pose, radius = self:box()
	draw_label(self.name, pose, radius)
	
	if height > 0.01 then
		-- Draw sides.
		draw_face_loop(bottom_points, height_offset, side_color)

		-- Draw top.
		local top_color = Blend.color_with_alpha(Interpolate.Linear.color(color, Color(255, 255, 255), 0.2), 128)
		draw_triangles(bottom_points, self.cap_triangulation, height_offset, top_color)
	end
end

function Volume:draw_highlight()
	local tm, r = self:box()
	local color = LevelEditor:object_highlight_color(self) or Color(30, 255, 255, 255)
	self:_draw_wireframe(color)
end

function Volume:_draw_wireframe(color)
	local bottom_points = self:_world_space_points_at_height(self.bottom)
	local get_line_color = Func.constantly(color)
	local height = self:height()
	local up_vector = self:up_vector()
	local height_offset = up_vector * height

	draw_line_loop(bottom_points, Vector3.zero(), get_line_color)

	if height > 0.01 then
		draw_line_loop(bottom_points, height_offset, get_line_color)
		draw_segmentation(bottom_points, get_line_color(), height_offset)
	end
end

function Volume:raycast(ray_start, ray_dir, ray_length)
	-- Perform broad-phase against oobb.
	local oobb_distance = Intersect.ray_box(ray_start, ray_dir, self:box())

	if oobb_distance == nil or oobb_distance >= ray_length then
		return nil, nil
	end

	local nv, nq, nm = Script.temp_count()
	local top_points = self:_world_space_points_at_height(self.top)
	local bottom_points = self:_world_space_points_at_height(self.bottom)
	assert(#bottom_points == #top_points)
	
	local min_distance = nil
	local best_normal = Vector3Box(-ray_dir)

	local function update_best_candidate(point_a, point_b, point_c)
		local distance = Intersect.ray_triangle(ray_start, ray_dir, point_a, point_b, point_c)

		if distance ~= nil and (min_distance == nil or distance < min_distance) then
			min_distance = distance
			best_normal:store(Geometry.triangle_normal(point_a, point_b, point_c))
		end
	end

	-- Test against top and bottom caps.
	local cap_triangle_count = #self.cap_triangulation

	for triangle_index = 1, cap_triangle_count, 3 do
		local index_a, index_b, index_c = unpack(self.cap_triangulation, triangle_index, triangle_index + 2)
		update_best_candidate(top_points[index_a], top_points[index_b], top_points[index_c])
		update_best_candidate(bottom_points[index_c], bottom_points[index_b], bottom_points[index_a])
	end

	-- Test against sides.
	local point_count = #top_points

	for index_a = 1, point_count do
		local index_b = (index_a % point_count) + 1
		update_best_candidate(top_points[index_a], bottom_points[index_a], bottom_points[index_b])
		update_best_candidate(bottom_points[index_b], top_points[index_b], top_points[index_a])
	end

	Script.set_temp_count(nv, nq, nm)

	if min_distance == nil then
		return nil, nil
	else
		return min_distance, best_normal:unbox()
	end
end

function Volume:local_extents()
	if self.radius == nil or self.center == nil then
		local nv, nq, nm = Script.temp_count()
		local min, max = nil, nil
	
		if #self.points > 0 then
			local bottom_points = Array.map(self.points, Func.partial(unbox_vector_at_height, self.bottom))
			local top_points = Array.map(self.points, Func.partial(unbox_vector_at_height, self.top))
			local local_points = Array.concat(bottom_points, top_points)
			
			min = Array.fold(local_points, Vector3(math.huge, math.huge, math.huge), Vector3.min)
			max = Array.fold(local_points, Vector3(-math.huge, -math.huge, -math.huge), Vector3.max)
		else
			min = Vector3.zero()
			max = Vector3.zero()
		end
		
		self.radius = Vector3Box((max - min) / 2)
		self.center = Vector3Box((max + min) / 2)
		Script.set_temp_count(nv, nq, nm)
	end

	return self.radius:unbox(), self.center:unbox()
end

function Volume:grid_origin_pose()
	return Matrix4x4.from_quaternion_position(self:local_rotation(), self:local_position())
end

function Volume:box()
	local unscaled_radius, unscaled_center = self:local_extents()
	local scale = self:local_scale()
	local scaled_center = Vector3.multiply_elements(unscaled_center, scale)
	local scaled_radius = Vector3.multiply_elements(unscaled_radius, scale)
	local unscaled_pose = Matrix4x4.from_quaternion_position(self:local_rotation(), self:local_position())
	Matrix4x4.set_translation(unscaled_pose, Matrix4x4.transform(unscaled_pose, scaled_center))
	return unscaled_pose, scaled_radius, scaled_center
end

function Volume:closest_mesh_point_to_ray(ray_start, ray_direction, ray_length)
	local nv, nq, nm = Script.temp_count()
	local bottom_points = self:_world_space_points_at_height(self.bottom)
	local top_points = self:_world_space_points_at_height(self.top)
	local world_points = Array.concat(bottom_points, top_points)
	local best_point, best_distance_along_ray =
		Geometry.closest_point_to_ray(world_points, ray_start, ray_direction, ray_length)

	local x, y, z = Nilable.map(best_point, Vector3.to_elements)
	Script.set_temp_count(nv, nq, nm)

	if x == nil then
		return nil, nil
	else
		return Vector3(x, y, z), best_distance_along_ray
	end
end

function Volume:up_vector()
	return Quaternion.up(self:local_rotation()) * self:local_scale().z
end

function Volume:height()
	return self.top - self.bottom
end

function Volume:set_vertical_extents(bottom, top)
	self.top = math.max(bottom, top)
	self.bottom = math.min(bottom, top)
	self.radius = nil
	self.center = nil
end

function Volume:point_id_to_index(point_id)
	return Array.cycle_index(self.points, point_id)
end

function Volume:point_index_to_id(point_index, is_top)
	return is_top and point_index + #self.points or point_index
end

function Volume:is_top_point_id(point_id)
	return point_id ~= nil and point_id > #self.points
end

function Volume:id_of_point_at_screen(x, y)
	local screen_points = self:_drawn_points()
	local mouse_point = Vector2(x, y)
	local pixel_threshold = 8
	
	local pixel_distance_to_mouse_point = function(point)
		local pixel_distance = Vector3.distance(mouse_point, point)
		return pixel_distance <= pixel_threshold and pixel_distance or nil
	end
	
	return Tuple.first(Array.min_by(screen_points, pixel_distance_to_mouse_point))
end

function Volume:ids_of_points_inside_screen_rect(top_left, bottom_right)
	local screen_points = self:_drawn_points()
	
	local function is_point_id_within_rect(point_id)
		local p = screen_points[point_id]
		return p.x >= top_left.x and p.x < bottom_right.x and p.y >= top_left.y and p.y < bottom_right.y 
	end
	
	local point_ids = Array.mapi(screen_points, Tuple.first):filter(is_point_id_within_rect)
	return point_ids
end

function Volume:_drawn_points()
	local bottom_points = self:_world_space_points_at_height(self.bottom)
	local top_points = self:_world_space_points_at_height(self.top)
	local world_points = Array.concat(bottom_points, top_points)
	local screen_points = Array.map(world_points, LevelEditor.world_to_screen):map(vector3_to_vector2)
	return screen_points, world_points
end

function Volume:_world_space_point_with_id(point_id)
	local point_index = self:point_id_to_index(point_id)
	local local_height = self:is_top_point_id(point_id) and self.top or self.bottom
	local local_point = unbox_vector_at_height(local_height, self.points[point_index])
	return self:to_global(local_point)
end

function Volume:_world_space_points_at_height(local_height)
	local tm = self:local_pose()
	
	local function transform(point)
		local local_point = unbox_vector_at_height(local_height, point)
		return Matrix4x4.transform(tm, local_point)
	end
	
	return Array.map(self.points, transform)
end

function Volume:closest_edge_intersection(x, y)
	local screen_points, world_points = self:_drawn_points()
	local mouse_point = Vector2(x, y)
	local pixel_threshold = 4
	
	-- Map of edge start point id to edge end point id.
	-- Example for a prism: { 1=>2, 2=>3, 3=>1,   4=>5, 5=>6, 6=>4 }
	local edge_end_point_ids_by_edge_start_point_id =
		Array.mapi(screen_points,
			function(edge_start_point_id)
				local next_point_id = edge_start_point_id + 1
				return edge_start_point_id % #self.points == 0 and next_point_id - #self.points or next_point_id
			end)
	
	-- Find the edge closest to the mouse point in screen space.
	-- We only accept edges that are within the threshold pixel distance.
	local function pixel_distance_to_mouse_point(edge_start_point_id, edge_end_point_id)
		local screen_edge_start = screen_points[edge_start_point_id]
		local screen_edge_end = screen_points[edge_end_point_id]
		local distance_along_edge = Intersect.segment_point(screen_edge_start, screen_edge_end, mouse_point)
		local screen_point_on_edge = Interpolate.Linear.points(screen_edge_start, screen_edge_end, distance_along_edge)
		local pixel_distance = Vector3.distance(mouse_point, screen_point_on_edge)
		return pixel_distance <= pixel_threshold and pixel_distance or nil
	end
	
	local edge_start_point_id, edge_end_point_id = Array.min_byi(edge_end_point_ids_by_edge_start_point_id, pixel_distance_to_mouse_point)
	
	if edge_start_point_id == nil then
		-- There is no edge close enough.
		return nil, nil, nil
	else
		-- Find the closest point on the edge in world space.
		local cam_pos, cam_dir = LevelEditor:camera_ray(x, y)
		local ray_distance = Camera.far_range(LevelEditor.camera) - Camera.near_range(LevelEditor.camera)
		local distance_along_edge = Intersect.segment_segment(world_points[edge_start_point_id], world_points[edge_end_point_id], cam_pos, cam_pos + cam_dir * ray_distance)
		return edge_start_point_id, edge_end_point_id, distance_along_edge
	end
end


--------------------------------------------------
-- VolumeTool
--------------------------------------------------

VolumeTool = class(VolumeTool, Tool)
VolumeTool.Behaviors = VolumeTool.Behaviors or {}
local Behaviors = VolumeTool.Behaviors

function VolumeTool:init()
	self.volume_type = "default"
	self.color = QuaternionBox(Color(255, 255, 255))
	self._behavior_stack = { Behaviors.Idle() }
end

function VolumeTool:update()
	self:_behavior():draw(self)
end

function VolumeTool:on_selected()
	local selected_volumes = Array.filter(LevelEditor.selection:objects(), is_selectable_volume)
	
	if #selected_volumes == 1 then
		local new_behavior = Behaviors.Editing(selected_volumes[1])
		self:_reroot_behavior(new_behavior)
	else
		self:_reset_behavior()
	end
end

function VolumeTool:mouse_spawn(x, y)
	self:_behavior():mouse_spawn(self, x, y)
end

function VolumeTool:mouse_down(x, y)
	self:_behavior():mouse_down(self, x, y)
end

function VolumeTool:mouse_move(x, y)
	LevelEditor.move_tool:mouse_move(x, y)
	self:_behavior():mouse_move(self, x, y)
end

function VolumeTool:mouse_up(x, y)
	self:_behavior():mouse_up(self, x, y)
	LevelEditor.move_tool:mouse_up(x, y)
end

function VolumeTool:key(key)
	self:_behavior():key(self, key)
end

function VolumeTool:_behavior()
	return self._behavior_stack[#self._behavior_stack]
end

function VolumeTool:_push_behavior(behavior)
	table.insert(self._behavior_stack, behavior)
end

function VolumeTool:_pop_behavior()
	table.remove(self._behavior_stack)
end

function VolumeTool:_reset_behavior()
	self._behavior_stack = { Behaviors.Idle() }
end

function VolumeTool:_reroot_behavior(behavior)
	self._behavior_stack = { Behaviors.Idle(), behavior }
end

function VolumeTool:_spawn_and_edit_cube_volume(x, y)
	local creation_height = volume_creation_height()
	local snapped_point, unsnapped_point = GridPlane.snap_mouse(Matrix4x4.identity(), creation_height, x, y)
	local world_point = LevelEditor:is_snap_to_grid_enabled() and snapped_point or unsnapped_point
	local new_volume = Volume()
	
	new_volume:update_points {
		Vector3(-1, -1, 0),
		Vector3( 1, -1, 0),
		Vector3( 1,  1, 0),
		Vector3(-1,  1, 0)
	}
	
	new_volume.type = self.volume_type
	new_volume.color = QuaternionBox(self.color:unbox())
	new_volume.top = 2
	new_volume.bottom = 0
	new_volume:set_local_position(world_point)
	spawn_volume(new_volume)
	local new_behavior = Behaviors.Editing(new_volume)
	self:_reroot_behavior(new_behavior)
end


--------------------------------------------------
-- Idle behavior
--------------------------------------------------

Behaviors.Idle = class(Behaviors.Idle)

function Behaviors.Idle:init()
end

function Behaviors.Idle:mouse_spawn(tool, x, y)
	tool:_spawn_and_edit_cube_volume(x, y)
end

function Behaviors.Idle:mouse_down(tool, x, y)
	local clicked_volume = find_volume_at_point(x, y)
	local new_behavior = nil
	
	if clicked_volume == nil then
		local creation_height = volume_creation_height()
		local new_volume = Volume()
		new_volume.top = creation_height
		new_volume.bottom = creation_height
		new_volume.type = tool.volume_type
		new_volume.color = QuaternionBox(tool.color:unbox())
		new_behavior = Behaviors.Creating(new_volume)
		new_behavior:mouse_down(tool, x, y)
	else
		LevelEditor.selection:clear()
		LevelEditor.selection:add(clicked_volume.id)
		LevelEditor.selection:send()
		new_behavior = Behaviors.Editing(clicked_volume)
	end
	
	tool:_push_behavior(new_behavior)
end

function Behaviors.Idle:mouse_move(tool, x, y)
end

function Behaviors.Idle:mouse_up(tool, x, y)
end

function Behaviors.Idle:key(tool, key)
end

function Behaviors.Idle:draw(tool)
	local volume = selected_volume()
	
	if volume ~= nil then
		local new_behavior = Behaviors.Editing(volume)
		tool:_reroot_behavior(new_behavior)
		return
	end

	if LevelEditor.editor_camera:is_controlled_by_mouse() then return end

	local creation_height = volume_creation_height()
	local mouse_point = LevelEditor.mouse.pos
	local grid_origin_pose = Matrix4x4.identity()
	local snapped_point, unsnapped_point = GridPlane.snap_mouse(grid_origin_pose, creation_height, mouse_point.x, mouse_point.y)
	local world_point = LevelEditor:is_snap_to_grid_enabled() and snapped_point or unsnapped_point
	LevelEditor:draw_grid_plane(grid_origin_pose, false, world_point)
	GridPlane.draw_cross(LevelEditor.lines_noz, grid_origin_pose, world_point)
end


--------------------------------------------------
-- Creating behavior
--------------------------------------------------

Behaviors.Creating = class(Behaviors.Creating)

function Behaviors.Creating:init(volume)
	self._volume = volume
	self._mouse_down_will_close = false
end

function Behaviors.Creating:mouse_spawn(tool, x, y)
end

function Behaviors.Creating:mouse_down(tool, x, y)
	local new_behavior = nil
	
	if self._mouse_down_will_close then
		local finalized_volume = finalize_volume_for_extrude(self._volume)
		local spawn_point = LevelEditor:find_spawn_point(x, y)
		new_behavior = Behaviors.CreatingExtruding(finalized_volume, spawn_point)
	else
		local snapped_point, unsnapped_point = GridPlane.snap_mouse(Matrix4x4.identity(), self._volume.bottom, x, y)
		local world_point = LevelEditor:is_snap_to_grid_enabled() and snapped_point or unsnapped_point
		local local_point = self._volume:to_local(world_point)
		Vector3.set_z(local_point, 0)
		self._volume:update_points(Array.map(self._volume.points, Func.method("unbox")):insert(local_point))
		new_behavior = Behaviors.CreatingDragging(self._volume, local_point)
	end
	
	tool:_push_behavior(new_behavior)
end

function Behaviors.Creating:mouse_move(tool, x, y)
	self._mouse_down_will_close = #self._volume.points > 2 and self._volume:id_of_point_at_screen(x, y) == 1
end

function Behaviors.Creating:mouse_up(tool, x, y)
end

function Behaviors.Creating:key(tool, key)
	if key == "enter" then
		local finalized_volume = finalize_volume_for_extrude(self._volume)
		local mouse_point = LevelEditor.mouse.pos
		local spawn_point = LevelEditor:find_spawn_point(mouse_point.x, mouse_point.y)
		local new_behavior = Behaviors.CreatingExtruding(finalized_volume, spawn_point)
		tool:_push_behavior(new_behavior)
	end
end

function Behaviors.Creating:draw(tool)
	if LevelEditor.editor_camera:is_controlled_by_mouse() then return end

	local mouse_point = LevelEditor.mouse.pos
	local grid_origin_pose = Matrix4x4.identity()
	local snapped_point, unsnapped_point = GridPlane.snap_mouse(grid_origin_pose, self._volume.bottom, mouse_point.x, mouse_point.y)
	local world_point = LevelEditor:is_snap_to_grid_enabled() and snapped_point or unsnapped_point
	LevelEditor:draw_grid_plane(grid_origin_pose, false, world_point)
	GridPlane.draw_cross(LevelEditor.lines_noz, grid_origin_pose, world_point)
	
	local bottom_points = self._volume:_world_space_points_at_height(self._volume.bottom)
	draw_foundation(bottom_points, self._mouse_down_will_close)
end


--------------------------------------------------
-- CreatingDragging behavior
--------------------------------------------------

Behaviors.CreatingDragging = class(Behaviors.CreatingDragging)

function Behaviors.CreatingDragging:init(volume, local_drag_start)
	self._volume = volume
	self._local_drag_start = Vector3Box(local_drag_start)
	self._original_points = Array.map(self._volume.points, copy_boxed_vector)
	self._mouse_up_will_close = false
end

function Behaviors.CreatingDragging:mouse_spawn(tool, x, y)
end

function Behaviors.CreatingDragging:mouse_down(tool, x, y)
end

function Behaviors.CreatingDragging:mouse_move(tool, x, y)
	local snapped_point, unsnapped_point = GridPlane.snap_mouse(Matrix4x4.identity(), self._volume.bottom, x, y)
	local world_point = LevelEditor:is_snap_to_grid_enabled() and unsnapped_point or snapped_point
	local local_destination = self._volume:to_local(world_point)
	Vector3.set_z(local_destination, 0)
	local offset = local_destination - self._local_drag_start:unbox()
	
	local function apply_offset_if_dragged(index, point)
		return index == #self._volume.points and point:unbox() + offset or point:unbox()
	end
	
	local function is_closed_loop(screen_points)
		local pixel_distance = Vector3.distance(screen_points[1], screen_points[#screen_points])
		local pixel_threshold = 8
		return pixel_distance <= pixel_threshold
	end
	
	self._volume:update_points(Array.mapi(self._original_points, apply_offset_if_dragged))
	self._mouse_up_will_close = #self._volume.points > 2 and is_closed_loop(self._volume:_drawn_points())
end

function Behaviors.CreatingDragging:mouse_up(tool, x, y)
	tool:_pop_behavior()
	
	if self._mouse_up_will_close then
		local all_points_except_the_last = Array.map(self._volume.points, Func.method("unbox")):sub(1, #self._volume.points - 1)
		self._volume:update_points(all_points_except_the_last)
		local finalized_volume = finalize_volume_for_extrude(self._volume)
		local spawn_point = LevelEditor:find_spawn_point(x, y)
		local new_behavior = Behaviors.CreatingExtruding(finalized_volume, spawn_point)
		tool:_push_behavior(new_behavior)
	end
end

function Behaviors.CreatingDragging:key(tool, key)
end

function Behaviors.CreatingDragging:draw(tool)
	if LevelEditor.editor_camera:is_controlled_by_mouse() then return end

	local mouse_point = LevelEditor.mouse.pos
	local grid_origin_pose = Matrix4x4.identity()
	local snapped_point, unsnapped_point = GridPlane.snap_mouse(grid_origin_pose, self._volume.bottom, mouse_point.x, mouse_point.y)
	local world_point = LevelEditor:is_snap_to_grid_enabled() and snapped_point or unsnapped_point
	LevelEditor:draw_grid_plane(grid_origin_pose, false, world_point)
	GridPlane.draw_cross(LevelEditor.lines_noz, grid_origin_pose, world_point)
	local bottom_points = self._volume:_world_space_points_at_height(self._volume.bottom)
	
	if self._mouse_up_will_close then
		local all_points_except_the_last = bottom_points:sub(1, #bottom_points - 1)
		draw_foundation(all_points_except_the_last, self._mouse_up_will_close)
	else
		draw_foundation(bottom_points, self._mouse_up_will_close)
	end
end


--------------------------------------------------
-- CreatingExtruding behavior
--------------------------------------------------

Behaviors.CreatingExtruding = class(Behaviors.CreatingExtruding)

function Behaviors.CreatingExtruding:init(volume, reference_point)
	self._volume = volume
	self._drag_start = Vector3Box(reference_point)
end

function Behaviors.CreatingExtruding:mouse_spawn(tool, x, y)
end

function Behaviors.CreatingExtruding:mouse_down(tool, x, y)
end

function Behaviors.CreatingExtruding:mouse_move(tool, x, y)
	local cam_pos, cam_dir = LevelEditor:camera_ray(x, y)
	local up_vector = self._volume:up_vector()
	local t = Vector3.dot(up_vector, cam_dir)
	local height = Vector3.dot(cam_pos - self._drag_start:unbox(), up_vector - t * cam_dir) / (1 - t * t)
	local snapped_height = LevelEditor:is_snap_to_grid_enabled() and GridPlane.snap_number(LevelEditor.grid.size, height) or height
	self._volume:set_vertical_extents(0, snapped_height)
end

function Behaviors.CreatingExtruding:mouse_up(tool, x, y)
	if self._volume:height() > 0.01 then
		spawn_volume(self._volume)
		local new_behavior = Behaviors.Editing(self._volume)
		tool:_reroot_behavior(new_behavior)
	end
end

function Behaviors.CreatingExtruding:key(tool, key)
	if key == "enter" and self._volume:height() > 0.01 then
		spawn_volume(self._volume)
		local new_behavior = Behaviors.Editing(self._volume)
		tool:_reroot_behavior(new_behavior)
	end
end

function Behaviors.CreatingExtruding:draw(tool)
	if LevelEditor.editor_camera:is_controlled_by_mouse() then return end

	local bottom_points = self._volume:_world_space_points_at_height(self._volume.bottom)
	local get_line_color = Func.constantly(Color(255, 255, 255))
	local up_vector = self._volume:up_vector()
	local height = self._volume:height()
	local height_offset = up_vector * height
	draw_line_loop(bottom_points, Vector3.zero(), get_line_color)
	
	if height > 0.01 then
		draw_line_loop(bottom_points, height_offset, get_line_color)
		draw_segmentation(bottom_points, get_line_color(), height_offset)
	end
end


--------------------------------------------------
-- Editing behavior
--------------------------------------------------

Behaviors.Editing = class(Behaviors.Editing)

function Behaviors.Editing:init(edited_volume)
	assert(kind_of(edited_volume) == Volume)
	self._edited_volume = edited_volume
	self._selected_point_indices = {}
	self._move_gizmo = MoveGizmo()
	self._box_selection = BoxSelection()
end

function Behaviors.Editing:mouse_spawn(tool, x, y)
	tool:_spawn_and_edit_cube_volume(x, y)
end

function Behaviors.Editing:mouse_down(tool, x, y)
	if self:_is_move_gizmo_visible() and self._move_gizmo:is_axes_selected() then
		-- Initiate drag of move gizmo axis.
		self:_start_drag(tool, x, y)
	elseif self:_is_split_face_indicator_visible() then
		-- Insert a new point, splitting the face.
		local new_point_id = self:_split_face(unpack(self._add_point_info))
		self._selected_point_indices = { self._edited_volume:point_id_to_index(new_point_id) }
		self:_attach_move_gizmo_to_point_id(new_point_id)
		self._move_gizmo:set_selected_axes("xy")
		self:_start_drag(tool, x, y)
	else
		-- Update point selection.
		local should_initiate_point_drag = self:_handle_selection_mouse_down(x, y)
		
		if should_initiate_point_drag then
			self._move_gizmo:set_selected_axes("xy")
			self:_start_drag(tool, x, y)
		end
	end
end

function Behaviors.Editing:mouse_move(tool, x, y)
	if self._box_selection:is_active() then
		self._box_selection:refresh_selection(x, y)
		return
	end

	local volume = self._edited_volume
	local hover_point_id = volume:id_of_point_at_screen(x, y)
	local is_over_move_gizmo = false
	self._add_point_info = nil
	
	if self:_is_move_gizmo_visible() then
		if hover_point_id == self._move_gizmo_point_id then
			self._move_gizmo:set_selected_axes("xy")
		else
			self._move_gizmo:select_axes(LevelEditor.editor_camera, x, y, true)
			is_over_move_gizmo = self._move_gizmo:is_axes_selected()
		end
	end
	
	if not is_over_move_gizmo and hover_point_id == nil then
		-- Are we close enough to add a point?
		local edge_start_point_id, edge_end_point_id, distance_along_edge = volume:closest_edge_intersection(x, y)
		
		if edge_start_point_id ~= nil then
			self._add_point_info = { edge_start_point_id, edge_end_point_id, distance_along_edge }
		end
	end
end

function Behaviors.Editing:mouse_up(tool, x, y)
	if self._box_selection:is_active() then
		local volume = self._edited_volume

		if self._box_selection:is_dragging() then		
			-- Select all points encompassed by box selection.
			local top_left = self._box_selection:top_left()
			local bottom_right = self._box_selection:bottom_right()
			local point_indices = volume:ids_of_points_inside_screen_rect(top_left, bottom_right)
										:map(Func.method("point_id_to_index", volume))
										:distinct()
			
			if LevelEditor:is_multi_select_modifier_held() then
				self._selected_point_indices = Array.concat(self._selected_point_indices, point_indices):distinct()
			else
				self._selected_point_indices = point_indices
			end
		else
			-- Did enter box selection mode, but didn't move the mouse.
			-- Treat as volume selection click.
			local clicked_volume = find_volume_at_point(x, y)
			
			if clicked_volume == nil then
				-- Clicked outside any volume. Go to idle behavior.
				LevelEditor.selection:clear()
				LevelEditor.selection:send()
				tool:_reset_behavior()
			elseif clicked_volume ~= volume then
				-- Clicked on a different volume. Change the selection.
				LevelEditor.selection:clear()
				LevelEditor.selection:add(clicked_volume.id)
				LevelEditor.selection:send()
				local new_behavior = Behaviors.Editing(clicked_volume)
				tool:_reroot_behavior(new_behavior)
			end
		end
		
		self._box_selection:end_selection()
	end
end

function Behaviors.Editing:key(tool, key)
	local volume = self._edited_volume
	
	if key == "delete" and #self._selected_point_indices > 0 and #volume.points - #self._selected_point_indices >= 3 then
		-- Delete selected points.
		local is_selected_index = Func.partial(Array.contains, self._selected_point_indices)
		volume:update_points(Array.filteri(volume.points, Func.negate(is_selected_index)):map(Func.method("unbox")))
		LevelEditor:modified({volume})
		self._selected_point_indices = {}
		self:_attach_move_gizmo_to_point_id(nil)
	end
end

function Behaviors.Editing:draw(tool)
	local volume = selected_volume()
	
	if volume == nil or volume.id ~= self._edited_volume.id then
		local new_behavior = volume == nil and Behaviors.Idle() or Behaviors.Editing(volume)
		tool:_reroot_behavior(new_behavior)
		return
	end

	self._edited_volume = volume
	local is_move_gizmo_visible = self:_is_move_gizmo_visible()
	local is_over_move_gizmo = is_move_gizmo_visible and self._move_gizmo:is_axes_selected()
	local bottom_points = volume:_world_space_points_at_height(volume.bottom)
	local up_vector = volume:up_vector()
	local height = volume:height()
	local move_gizmo_controls_top = volume:is_top_point_id(self._move_gizmo_point_id or 1)
	
	-- Draw grid, if visible.
	if is_move_gizmo_visible then
		self._move_gizmo:set_rotation(volume:local_rotation())
		self._move_gizmo:draw_grid_plane(volume:grid_origin_pose())
	end

	-- Draw volume editing overlays (handles and lines).
	draw_editing_representation(bottom_points, up_vector, height, self._selected_point_indices, move_gizmo_controls_top)

	-- Draw move gizmo, if visible.
	if is_move_gizmo_visible then
		self._move_gizmo:draw(LevelEditor.world_gui, LevelEditor.lines_noz, LevelEditor.editor_camera, true)
	end

	if not is_over_move_gizmo then
		-- Draw face split indicator.
		if self:_is_split_face_indicator_visible() then
			local edge_start_point_id, edge_end_point_id, distance_along_edge = unpack(self._add_point_info)
			local edge_start_index = volume:point_id_to_index(edge_start_point_id)
			local edge_end_index = volume:point_id_to_index(edge_end_point_id)
			local point_on_bottom_edge = Interpolate.Linear.points(bottom_points[edge_start_index], bottom_points[edge_end_index], distance_along_edge)
			draw_face_split_indicator(point_on_bottom_edge, up_vector, height)
		end
	end
	
	-- Draw box selection.
	self._box_selection:draw(LevelEditor.gui)
end

function Behaviors.Editing:_start_drag(tool, x, y)
	self._move_gizmo:start_move(LevelEditor.editor_camera, x, y)
	local new_behavior = Behaviors.EditingDragging(self._edited_volume, self._move_gizmo, self._selected_point_indices, self._move_gizmo_point_id)
	tool:_push_behavior(new_behavior)
end

function Behaviors.Editing:_split_face(edge_start_point_id, edge_end_point_id, distance_along_edge)
	local volume = self._edited_volume
	local edge_start_index = volume:point_id_to_index(edge_start_point_id)
	local edge_end_index = volume:point_id_to_index(edge_end_point_id)
	local local_edge_start = volume.points[edge_start_index]:unbox()
	local local_edge_end = volume.points[edge_end_index]:unbox()
	local local_new_point = Interpolate.Linear.points(local_edge_start, local_edge_end, distance_along_edge)
	local new_point_index = edge_start_index + 1
	volume:update_points(Array.map(volume.points, Func.method("unbox")):insert(new_point_index, local_new_point))
	local is_top_click = volume:is_top_point_id(edge_start_point_id)
	local new_point_id = volume:point_index_to_id(new_point_index, is_top_click)
	return new_point_id
end

function Behaviors.Editing:_handle_selection_mouse_down(x, y)
	local volume = self._edited_volume
	local clicked_point_id = volume:id_of_point_at_screen(x, y)
	local clicked_point_index = clicked_point_id ~= nil and volume:point_id_to_index(clicked_point_id) or nil
	local index_in_selection = clicked_point_id ~= nil and Array.index_of(self._selected_point_indices, clicked_point_index) or nil
	
	if LevelEditor:is_multi_select_modifier_held() then
		-- Multi-select mode.
		if clicked_point_id == nil then
			self._box_selection:begin_selection(x, y)
		else
			if index_in_selection == nil then
				table.insert(self._selected_point_indices, clicked_point_index)
			else
				table.remove(self._selected_point_indices, index_in_selection)
			end
			
			local is_top_click = volume:is_top_point_id(clicked_point_id)
			self:_attach_move_gizmo_to_any_selected_point(is_top_click)
		end
		
		return false
	else
		-- Not in multi-select mode.
		if clicked_point_id == nil then
			-- Clear selection.
			self._selected_point_indices = {}
			self:_attach_move_gizmo_to_point_id(nil)
			self._box_selection:begin_selection(x, y)
			return false
		else
			if index_in_selection == nil then
				-- Replace selection.
				self._selected_point_indices = { clicked_point_index }
			end
			
			self:_attach_move_gizmo_to_point_id(clicked_point_id)
			return true
		end
	end
	
	assert(false)
	return false
end

function Behaviors.Editing:_is_move_gizmo_visible()
	return self._move_gizmo_point_id ~= nil and not LevelEditor:is_multi_select_modifier_held()
end

function Behaviors.Editing:_is_split_face_indicator_visible()
	return self._add_point_info ~= nil and not LevelEditor:is_multi_select_modifier_held()
end

function Behaviors.Editing:_attach_move_gizmo_to_point_id(point_id)
	self._move_gizmo_point_id = point_id
	
	if point_id ~= nil then
		local volume = self._edited_volume
		local world_point = volume:_world_space_point_with_id(point_id)
		self._move_gizmo:set_position(world_point)
		self._move_gizmo:set_rotation(volume:local_rotation())
	end
end

function Behaviors.Editing:_attach_move_gizmo_to_any_selected_point(prefer_top_point)
	local volume = self._edited_volume
	local selected_indices = self._selected_point_indices
	local move_gizmo_point_index = self._move_gizmo_point_id ~= nil and volume:point_id_to_index(self._move_gizmo_point_id) or nil
	
	if #selected_indices == 0 then
		-- No points are selected. Hide the move gizmo.
		self:_attach_move_gizmo_to_point_id(nil)
	elseif Array.contains(selected_indices, move_gizmo_point_index) then
		-- The move gizmo is already on a selected point.
		return
	else
		-- Attach the move gizmo to the most recently selected point.
		local point_id = volume:point_index_to_id(selected_indices[#selected_indices], prefer_top_point)
		self:_attach_move_gizmo_to_point_id(point_id)
	end
end


--------------------------------------------------
-- EditingDragging behavior
--------------------------------------------------

Behaviors.EditingDragging = class(Behaviors.EditingDragging)

function Behaviors.EditingDragging:init(edited_volume, move_gizmo, dragged_point_indices, move_gizmo_point_id)
	assert(kind_of(edited_volume) == Volume)
	assert(kind_of(move_gizmo) == MoveGizmo)
	assert(Validation.is_non_empty_array(dragged_point_indices))
	assert(type(move_gizmo_point_id) == "number")
	self._edited_volume = edited_volume
	self._move_gizmo = move_gizmo
	self._move_gizmo_point_id = move_gizmo_point_id
	self._dragged_point_indices = dragged_point_indices
	self._original_points = Array.map(self._edited_volume.points, copy_boxed_vector)
	
	if self:_move_gizmo_controls_top() then
		self._original_height = self._edited_volume.top
	else
		self._original_height = self._edited_volume.bottom
	end
end

function Behaviors.EditingDragging:mouse_spawn(tool, x, y)
end

function Behaviors.EditingDragging:mouse_down(tool, x, y)
end

function Behaviors.EditingDragging:mouse_move(tool, x, y)
	local volume = self._edited_volume
	local snap_function = LevelEditor:snap_function(volume:grid_origin_pose(), false, Set.of(volume.id))
	self._move_gizmo:delta_move(LevelEditor.editor_camera, x, y, snap_function)
	local local_offset = to_local_offset(volume:local_pose(), self._move_gizmo:drag_delta())
	
	local apply_offset_if_dragged = function(index, point)
		if Array.contains(self._dragged_point_indices, index) then
			local new_point = point:unbox() + local_offset
			Vector3.set_z(new_point, 0)
			return new_point
		else
			return point:unbox()
		end
	end
	
	volume:update_points(Array.mapi(self._original_points, apply_offset_if_dragged))
	self:_apply_height_offset(local_offset.z)
end

function Behaviors.EditingDragging:mouse_up(tool, x, y)
	local function was_point_modified(index, point)
		return not Vector3.equal(point:unbox(), self._original_points[index]:unbox())
	end
	
	local volume = self._edited_volume
	
	local function height_was_modified()
		return (self:_move_gizmo_controls_top() and volume.top or volume.bottom) ~= self._original_height
	end
	
	local function points_were_modified()
		return #volume.points ~= #self._original_points or Array.findi(volume.points, was_point_modified) ~= nil
	end

	if height_was_modified() or points_were_modified() then
		LevelEditor:modified({volume})
	end
	
	tool:_pop_behavior()
end

function Behaviors.EditingDragging:key(tool, key)
end

function Behaviors.EditingDragging:draw(tool)
	local volume = self._edited_volume
	local bottom_points = volume:_world_space_points_at_height(volume.bottom)
	
	-- Draw grid.
	self._move_gizmo:draw_grid_plane(volume:grid_origin_pose())
	
	-- Draw volume editing overlays (handles and lines).
	draw_editing_representation(bottom_points, volume:up_vector(), volume:height(), self._dragged_point_indices, self:_move_gizmo_controls_top())
	
	-- Draw move gizmo.
	self._move_gizmo:draw_drag_start(LevelEditor.lines_noz, LevelEditor.editor_camera)
	self._move_gizmo:draw(LevelEditor.world_gui, LevelEditor.lines_noz, LevelEditor.editor_camera, true)
end

function Behaviors.EditingDragging:_apply_height_offset(height)
	local volume = self._edited_volume
	
	if self:_move_gizmo_controls_top() then
		volume:set_vertical_extents(volume.bottom, self._original_height + height)
	else
		volume:set_vertical_extents(self._original_height + height, volume.top)
	end
end

function Behaviors.EditingDragging:_move_gizmo_controls_top()
	return self._edited_volume:is_top_point_id(self._move_gizmo_point_id)
end
