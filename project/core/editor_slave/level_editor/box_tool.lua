--------------------------------------------------
-- Utility functions
--------------------------------------------------

local visual_raycast = Func.partial(Picking.raycast, Picking.is_visible_and_not_in_group)

local function drag_plane_point(plane_height, x, y)
	local cam_pos, cam_dir = LevelEditor:camera_ray(x, y)
	local snapped_point, unsnapped_point = GridPlane.snap_mouse(Matrix4x4.identity(), plane_height, x, y)
	local plane_point = LevelEditor:is_snap_to_grid_enabled() and snapped_point or unsnapped_point
	return plane_point
end

local function extents(start_point, end_point)
	local min_point = Vector3.min(start_point, end_point)
	local max_point = Vector3.max(start_point, end_point)
	return min_point, max_point
end

local function unboxed_extents(boxed_start_point, boxed_end_point)
	local start_point = boxed_start_point:unbox()
	local end_point = boxed_end_point:unbox()
	return extents(start_point, end_point)
end

local function with_z(vector, z)
	return Vector3(vector.x, vector.y, z)
end

local function closest_point_height(x, y)
	local cam_pos, cam_dir = LevelEditor:camera_ray(x, y)
	local ray_length = LevelEditor.editor_camera:far_range()
	local level_object, distance_along_ray = visual_raycast(LevelEditor.objects, cam_pos, cam_dir, ray_length)

	if level_object == nil then
		return nil
	end

	local point_in_mesh = level_object:closest_mesh_point_to_ray(cam_pos, cam_dir, ray_length)
	return point_in_mesh ~= nil and point_in_mesh.z or nil
end

local function hit_surface_height(x, y)
	local cam_pos, cam_dir = LevelEditor:camera_ray(x, y)
	local ray_length = LevelEditor.editor_camera:far_range()
	local level_object, distance_along_ray = visual_raycast(LevelEditor.objects, cam_pos, cam_dir, ray_length)

	if level_object == nil then
		return nil
	end

	local point_on_ray = cam_pos + cam_dir * distance_along_ray
	return point_on_ray.z
end

local function projected_camera_ray_height(base_point, x, y)
	local cam_pos, cam_dir = LevelEditor:camera_ray(x, y)
	local up_vector = Vector3(0, 0, 1)
	local t = Vector3.dot(up_vector, cam_dir)
	local distance = Vector3.dot(cam_pos - base_point, up_vector - t * cam_dir) / (1 - t * t)

	if LevelEditor:snap_mode() == "Relative" then
		local snapped_distance = LevelEditor:is_snap_to_grid_enabled() and GridPlane.snap_number(LevelEditor.grid.size, distance) or distance
		return base_point.z + snapped_distance
	end

	assert(LevelEditor:snap_mode() == "Absolute")
	local end_height = base_point.z + distance
	return LevelEditor:is_snap_to_grid_enabled() and GridPlane.snap_number(LevelEditor.grid.size, end_height) or end_height
end


--------------------------------------------------
-- BoxTool
--------------------------------------------------

BoxTool = class(BoxTool, Tool)
BoxTool.Behaviors = BoxTool.Behaviors or {}
local Behaviors = BoxTool.Behaviors

function BoxTool:init(box_object_class)
	self._behavior = Behaviors.Idle()
	self._box_object_class = box_object_class
end

function BoxTool:on_selected()
	if self._behavior.on_selected ~= nil then
		self._behavior:on_selected(self)
	end
end

function BoxTool:coordinates()
	return self._behavior:coordinates(self)
end

function BoxTool:update()
	if self._behavior.update ~= nil then
		self._behavior:update(self)
	end
end

function BoxTool:mouse_down(x, y)
	if self._behavior.mouse_down ~= nil then
		self._behavior:mouse_down(self, x, y)
	end
end

function BoxTool:mouse_move(x, y)
	if self._behavior.mouse_move ~= nil then
		self._behavior:mouse_move(self, x, y)
	end
end

function BoxTool:mouse_up(x, y)
	if self._behavior.mouse_up ~= nil then
		self._behavior:mouse_up(self, x, y)
	end
end

function BoxTool:key(direction)
	if self._behavior.key ~= nil then
		self._behavior:key(self, direction)
	end
end

function BoxTool:_make_box(center, radius)
	local box = self._box_object_class.make_box(center, Quaternion.identity(), Vector3(1, 1, 1), radius)
	return box
end

function BoxTool:_spawn(center, radius)
	local level_object = self._box_object_class.make(center, Quaternion.identity(), Vector3(1, 1, 1), radius)
	level_object:reset_pivot()
	LevelEditor.objects[level_object.id] = level_object
	LevelEditor:spawned({level_object})
	LevelEditor.selection:clear()
	LevelEditor.selection:add(level_object.id)
	LevelEditor.selection:send()
end


--------------------------------------------------
-- Idle behavior
--------------------------------------------------

Behaviors.Idle = class(Behaviors.Idle)

function Behaviors.Idle:init()
	local mouse_point = LevelEditor.mouse.pos
	local start_point = LevelEditor:find_spawn_point(mouse_point.x, mouse_point.y)
	self._start_point = Vector3Box(start_point)
end

function Behaviors.Idle:coordinates(tool)
	return self._start_point:unbox()
end

function Behaviors.Idle:on_selected(tool)
	local mouse_pos = LevelEditor.mouse.pos
	local start_point = LevelEditor:find_spawn_point(mouse_pos.x, mouse_pos.y)
	self._start_point:store(start_point)
end

function Behaviors.Idle:mouse_down(tool, x, y)
	local start_point = self._start_point:unbox()
	local box = tool:_make_box(start_point, Vector3(0, 0, 0))
	tool._behavior = Behaviors.DefiningBaseArea(box, start_point)
end

function Behaviors.Idle:mouse_move(tool, x, y)
	local start_point = LevelEditor:find_spawn_point(x, y)
	self._start_point:store(start_point)
end

function Behaviors.Idle:update(tool)
	if LevelEditor.editor_camera:is_controlled_by_mouse() then return end

	local start_point = self._start_point:unbox()
	local grid_pose = Matrix4x4.from_translation(Vector3(0, 0, start_point.z))
	LevelEditor:draw_grid_plane(grid_pose, false, start_point)
	GridPlane.draw_cross(LevelEditor.lines_noz, grid_pose, start_point)
end


--------------------------------------------------
-- DefiningBaseArea behavior
--------------------------------------------------

Behaviors.DefiningBaseArea = class(Behaviors.DefiningBaseArea)

function Behaviors.DefiningBaseArea:init(box, start_point)
	assert(kind_of(box) == Box)
	self._start_point = Vector3Box(start_point)
	self._end_point = Vector3Box(start_point)
	self._box = box
end

function Behaviors.DefiningBaseArea:coordinates(tool)
	return self._end_point:unbox()
end

function Behaviors.DefiningBaseArea:mouse_move(tool, x, y)
	local start_point = self._start_point:unbox()
	local end_point = drag_plane_point(self._start_point.z, x, y)
	self._end_point:store(end_point)
	self._box:encompass(start_point, end_point)
end

function Behaviors.DefiningBaseArea:mouse_up(tool, x, y)
	local start_point = self._start_point:unbox()
	local end_point = drag_plane_point(self._start_point.z, x, y)
	self._box:encompass(start_point, end_point)
	tool._behavior = Behaviors.ExtrudingHeight(self._box, end_point)
end

function Behaviors.DefiningBaseArea:update(tool)
	local end_point = self._end_point:unbox()
	local grid_pose = Matrix4x4.from_translation(Vector3(0, 0, self._start_point.z))
	local white = Color(255, 255, 255)
	LevelEditor:draw_grid_plane(grid_pose, false, end_point)
	GridPlane.draw_cross(LevelEditor.lines_noz, grid_pose, end_point)
	self._box:draw()
	self._box:draw_side_labels(white)
	self._box:draw_edges(LevelEditor.lines, white)
end


--------------------------------------------------
-- ExtrudingHeight behavior
--------------------------------------------------

Behaviors.ExtrudingHeight = class(Behaviors.ExtrudingHeight)

function Behaviors.ExtrudingHeight:init(box, reference_point)
	assert(kind_of(box) == Box)
	self._box = box
	self._reference_point = Vector3Box(reference_point)
end

function Behaviors.ExtrudingHeight:coordinates(tool)
	return self._box:radius()
end

function Behaviors.ExtrudingHeight:mouse_move(tool, x, y)
	self:_update_box_size_from_mouse(x, y)
end

function Behaviors.ExtrudingHeight:mouse_up(tool, x, y)
	self:_update_box_size_from_mouse(x, y)

	if Vector3.length(self._box:radius()) > 0.01 then
		tool:_spawn(self._box:position(), self._box:radius())
		self._box:destroy()
		tool._behavior = Behaviors.Idle()
	end
end

function Behaviors.ExtrudingHeight:update(tool)
	local white = Color(255, 255, 255)
	self._box:draw()
	self._box:draw_side_labels(white)
	self._box:draw_edges(LevelEditor.lines, white)
end

function Behaviors.ExtrudingHeight:_update_box_size_from_mouse(x, y)
	local reference_point = self._reference_point:unbox()
	local grid_height = Func.partial(projected_camera_ray_height, reference_point)
	local snapped_end_height

	if LevelEditor:is_snap_to_point_enabled() then
		snapped_end_height = closest_point_height(x, y) or grid_height(x, y)
	elseif LevelEditor:is_snap_to_surface_enabled() then
		snapped_end_height = hit_surface_height(x, y) or grid_height(x, y)
	else
		snapped_end_height = grid_height(x, y)
	end

	local min_point, max_point = extents(reference_point, with_z(reference_point, snapped_end_height))
	self._box:set_vertical_extents(min_point.z, max_point.z)
end
