--------------------------------------------------
-- Utility functions
--------------------------------------------------

local radius = 0.5

local function snap_point_pose(boxed_transforms, index)
	assert(index ~= nil)
	local boxed_tm = boxed_transforms[index]
	local tm = boxed_tm:unbox()
	return tm
end

local snap_point_position = Func.compose(snap_point_pose, Matrix4x4.translation)

local function draw_snap_points(boxed_transforms, get_color)
	local lines = LevelEditor.lines

	for index = 1, #boxed_transforms do
		local position = snap_point_position(boxed_transforms, index)
		local color = get_color(index)
		LineObject.add_sphere(lines, color, position, radius)
	end
end

local function draw_axes(pose)
	local position = Matrix4x4.translation(pose)
	local x_axis = Matrix4x4.x(pose)
	local y_axis = Matrix4x4.y(pose)
	local z_axis = Matrix4x4.z(pose)
	local scale = LevelEditor.editor_camera:screen_size_to_world_size(position, 85)
	local lines = LevelEditor.lines_noz
	LineObject.add_line(lines, Color(255, 0, 0), position, position + x_axis * scale)
	LineObject.add_line(lines, Color(0, 255, 0), position, position + y_axis * scale)
	LineObject.add_line(lines, Color(0, 0, 255), position, position + z_axis * scale)
end

local function calc_delta_transformation(source_tm, dest_tm)
	local pivot_point = Matrix4x4.translation(source_tm)
	local offset = Matrix4x4.translation(dest_tm) - pivot_point
	local delta_rotation = Quaternion.multiply(Matrix4x4.rotation(dest_tm), Quaternion.inverse(Matrix4x4.rotation(source_tm)))
	
	local translate_objects_so_pivot_is_at_origin = Matrix4x4.from_translation(-pivot_point)
	local apply_delta_rotation = Matrix4x4.from_quaternion(delta_rotation)
	local translate_objects_back_to_pivot = Matrix4x4.from_translation(pivot_point)
	local offset_objects = Matrix4x4.from_translation(offset)
	local operations = { translate_objects_so_pivot_is_at_origin, apply_delta_rotation, translate_objects_back_to_pivot, offset_objects }
	local transformation = Array.reduce(operations, Matrix4x4.multiply)

	return transformation
end

local function all_snap_points()
	local boxed_transforms = {}

	for _, level_object in pairs(LevelEditor.objects) do
		if type(level_object.add_snap_points) == "function" then
			level_object:add_snap_points(boxed_transforms)
		end
	end

	return boxed_transforms
end

local function intersection_distance(ray_start, ray_dir, boxed_tm)
	local tm = boxed_tm:unbox()
	local position = Matrix4x4.translation(tm)
	local distance_or_nil = Intersect.ray_sphere(ray_start, ray_dir, position, radius)
	return distance_or_nil
end

local function ray_pick_snap_point(boxed_transforms, ray_start, ray_dir)
	local index, boxed_tm = Array.min_by(boxed_transforms, Func.partial(intersection_distance, ray_start, ray_dir))
	return index, boxed_tm
end

local function screen_pick_snap_point(boxed_transforms, x, y)
	local cam_pos, cam_dir = LevelEditor:camera_ray(x, y)
	local index, boxed_tm = ray_pick_snap_point(boxed_transforms, cam_pos, cam_dir)
	return index, boxed_tm
end


--------------------------------------------------
-- SnapTogetherTool
--------------------------------------------------

SnapTogetherTool = class(SnapTogetherTool, Tool)
SnapTogetherTool.Behaviors = SnapTogetherTool.Behaviors or {}
local Behaviors = SnapTogetherTool.Behaviors

function SnapTogetherTool:init()
	self._snap_points = {}
	self._behavior = Behaviors.Idle()
end

function SnapTogetherTool:on_selected()
	self:_refresh_snap_points()
end

function SnapTogetherTool:coordinates()
	return self._behavior:coordinates(self)
end

function SnapTogetherTool:update()
	if self._behavior.update ~= nil then
		self._behavior:update(self)
	end
end

function SnapTogetherTool:mouse_down(x, y)
	if self._behavior.mouse_down ~= nil then
		self._behavior:mouse_down(self, x, y)
	end
end

function SnapTogetherTool:mouse_move(x, y)
	if self._behavior.mouse_move ~= nil then
		self._behavior:mouse_move(self, x, y)
	end
end

function SnapTogetherTool:mouse_up(x, y)
	if self._behavior.mouse_up ~= nil then
		self._behavior:mouse_up(self, x, y)
	end
end

function SnapTogetherTool:key(key)
	if self._behavior.key ~= nil then
		self._behavior:key(self, key)
	end
end

function SnapTogetherTool:_refresh_snap_points()
	self._snap_points = all_snap_points()
end


--------------------------------------------------
-- Idle behavior
--------------------------------------------------

Behaviors.Idle = class(Behaviors.Idle)

function Behaviors.Idle:init()
end

function Behaviors.Idle:coordinates(tool)
	local hovered_object = LevelEditor:hovered_object()
	return hovered_object == nil and Vector3(0, 0, 0) or hovered_object:local_position()
end

function Behaviors.Idle:mouse_down(tool, x, y)
	local hovered_object = LevelEditor:hovered_object()
	local dragged_object = nil

	if hovered_object ~= nil and not LevelEditor:is_multi_select_modifier_held() and Array.contains(LevelEditor.selection:objects(), hovered_object) then
		dragged_object = hovered_object
	else
		local _, could_initiate_drag = LevelEditor.select_tool:mouse_down(x, y)

		if could_initiate_drag then
			dragged_object = LevelEditor.selection:objects()[1]
		end
	end

	if dragged_object ~= nil then
		LevelEditor.select_tool:mouse_up(x, y) -- Cancel drag selection.
		tool._behavior = Behaviors.DragObjects(dragged_object:local_pose())
	end
end

function Behaviors.Idle:mouse_move(tool, x, y)
	LevelEditor.select_tool:mouse_move(x, y)
end

function Behaviors.Idle:mouse_up(tool, x, y)
	LevelEditor.select_tool:mouse_up(x, y)
end

function Behaviors.Idle:update(tool)
	LevelEditor.select_tool:update()
	local hovered_object = LevelEditor:hovered_object()

	if hovered_object ~= nil then
		draw_axes(hovered_object:local_pose())
	end
end


--------------------------------------------------
-- Drag objects behavior
--------------------------------------------------

Behaviors.DragObjects = class(Behaviors.DragObjects)

function Behaviors.DragObjects:init(reference_object_pose)
	self._reference_object_pose = Matrix4x4Box(reference_object_pose)
	self._dest_snap_point_index = nil
	self._is_cloning = LevelEditor:is_clone_modifier_held() and LevelEditor.selection:duplicate()
	self._start_poses = LevelEditor.selection:save_state()
end

function Behaviors.DragObjects:coordinates(tool)
	local pose = self._dest_snap_point_index == nil
				 and self._reference_object_pose:unbox()
				  or snap_point_pose(tool._snap_points, self._dest_snap_point_index)

	return Matrix4x4.translation(pose)
end

function Behaviors.DragObjects:mouse_move(tool, x, y)
	local had_snap_point = self._dest_snap_point_index ~= nil
	self._dest_snap_point_index = screen_pick_snap_point(tool._snap_points, x, y)

	if self._dest_snap_point_index ~= nil then
		-- Align object poses relative to the snap point.
		local transformation = self:_snap_transformation(tool)

		for index, level_object in ipairs(LevelEditor.selection:objects()) do 
			local start_pose = self._start_poses[index]:unbox()
			local snapped_pose = Matrix4x4.multiply(start_pose, transformation)
			level_object:set_local_position(Matrix4x4.translation(snapped_pose))
			level_object:set_local_rotation(Matrix4x4.rotation(snapped_pose))
		end
	elseif had_snap_point then
		-- Restore original pose.
		for index, level_object in ipairs(LevelEditor.selection:objects()) do
			local start_pose = self._start_poses[index]:unbox()
			level_object:set_local_position(Matrix4x4.translation(start_pose))
			level_object:set_local_rotation(Matrix4x4.rotation(start_pose))
		end
	end
end

function Behaviors.DragObjects:mouse_up(tool, x, y)
	LevelEditor.selection:finish_move(self._start_poses, self._is_cloning)
	tool:_refresh_snap_points()
	tool._behavior = Behaviors.Idle()
end

function Behaviors.DragObjects:update(tool)
	local regular_color = Color(0, 255, 255)
	local highlight_color = Color(255, 0, 255)

	local function color_at_index(index)
		return index == self._dest_snap_point_index and highlight_color or regular_color
	end

	draw_snap_points(tool._snap_points, color_at_index)
end

function Behaviors.DragObjects:_snap_transformation(tool)
	local dest_pose = snap_point_pose(tool._snap_points, self._dest_snap_point_index)
	local transformation = calc_delta_transformation(self._reference_object_pose:unbox(), dest_pose)
	return transformation
end
