--------------------------------------------------
-- Utility functions
--------------------------------------------------

local install_pivot_behaviors = require "core/editor_slave/level_editor/pivot_behaviors"

local function boxed_unscaled_world_pose(scene_element_ref)
	local object_id, component_id = SceneElementRef.unpack(scene_element_ref)
	local level_object = LevelEditor.objects[object_id]
	local world_position = level_object:world_position(component_id)
	local world_rotation = level_object:world_rotation(component_id)
	local unscaled_world_pose = Matrix4x4.from_quaternion_position(world_rotation, world_position)
	return Matrix4x4Box(unscaled_world_pose)
end

local function start_rotate_selected_elements()
	local is_cloning = LevelEditor:is_clone_modifier_held() and LevelEditor.selection:duplicate()
	local local_start_poses = LevelEditor.selection:save_state()
	local world_start_poses = Array.map(LevelEditor.selection:scene_element_refs(), boxed_unscaled_world_pose)
	return local_start_poses, world_start_poses, is_cloning
end

local function delta_rotate_selected_elements(world_start_poses, pivot_point, delta_rotation)
	local translate_objects_so_pivot_is_at_origin = Matrix4x4.from_translation(-pivot_point)
	local apply_delta_rotation = Matrix4x4.from_quaternion(delta_rotation)
	local translate_objects_back_to_pivot = Matrix4x4.from_translation(pivot_point)
	local operations = { translate_objects_so_pivot_is_at_origin, apply_delta_rotation, translate_objects_back_to_pivot }
	local transformation = Array.reduce(operations, Matrix4x4.multiply)
	local scene_element_refs = LevelEditor.selection:scene_element_refs()

	for index, scene_element_ref in ipairs(scene_element_refs) do
		local object_id, component_id = SceneElementRef.unpack(scene_element_ref)
		local level_object = LevelEditor.objects[object_id]
		local start_pose = world_start_poses[index]:unbox()
		local new_pose = Matrix4x4.multiply(start_pose, transformation)
		level_object:set_world_position(Matrix4x4.translation(new_pose), component_id)
		level_object:set_world_rotation(Matrix4x4.rotation(new_pose), component_id)
	end
end

local function finish_rotate_selected_elements(local_start_poses, is_cloning)
	LevelEditor.selection:finish_move(local_start_poses, is_cloning)
end

local function transform_selected_elements()
	local scene_element_refs = LevelEditor.selection:scene_element_refs()
	for index, scene_element_ref in ipairs(scene_element_refs) do
		local object_id, component_id = SceneElementRef.unpack(scene_element_ref)
		local level_object = LevelEditor.objects[object_id]
		if kind_of(level_object) == UnitObject then
			local unit = level_object._unit
			World.update_unit(Unit.world(unit), unit)
		end
	end
end

local function rotation_coordinates(rotation)
	local radians = { Convert.Quaternion.yaw_pitch_roll(rotation) }
	local degrees = Array.map(radians, math.deg)
	return Vector3(unpack(degrees))
end


--------------------------------------------------
-- RotateTool
--------------------------------------------------

RotateTool = class(RotateTool, Tool)
RotateTool.Behaviors = RotateTool.Behaviors or {}
local Behaviors = RotateTool.Behaviors
install_pivot_behaviors(Behaviors)

function RotateTool:init()
	self._rotate_gizmo = RotateGizmo()
	self._behavior = Behaviors.Idle()
end

function RotateTool:on_selected()
	if self._behavior.on_selected ~= nil then
		self._behavior:on_selected(self)
	end
end

function RotateTool:coordinates()
	return self._behavior:coordinates(self)
end

function RotateTool:set_pivot_pose(pivot_pose)
	local use_world_axes = LevelEditor:reference_system() == "World"
	local gizmo_pose = use_world_axes and Matrix4x4.from_translation(Matrix4x4.translation(pivot_pose)) or pivot_pose
	self._rotate_gizmo:set_pose(gizmo_pose)
end

function RotateTool:update()
	if self._behavior.update ~= nil then
		self._behavior:update(self)
	end
end

function RotateTool:is_highlight_suppressed()
	return self._behavior.is_highlight_suppressed and self._behavior:is_highlight_suppressed(self) or false
end

function RotateTool:on_deselected()
	if self._behavior.on_deselected ~= nil then
		self._behavior:on_deselected(self)
	end
end

function RotateTool:mouse_down(x, y)
	LevelEditor:abort_physics_simulation()

	if self._behavior.mouse_down ~= nil then
		self._behavior:mouse_down(self, x, y)
	end
end

function RotateTool:mouse_move(x, y)
	if self._behavior.mouse_move ~= nil then
		self._behavior:mouse_move(self, x, y)
	end
end

function RotateTool:mouse_up(x, y)
	if self._behavior.mouse_up ~= nil then
		self._behavior:mouse_up(self, x, y)
	end
end

function RotateTool:keyboard_rotate(local_axis)
	if self._behavior.keyboard_rotate ~= nil then
		self._behavior:keyboard_rotate(self, local_axis)
	end
end

function RotateTool:toggle_pivot_edit_mode()
	if self._behavior.toggle_pivot_edit_mode ~= nil then
		self._behavior:toggle_pivot_edit_mode(self)
	end
end


--------------------------------------------------
-- Idle behavior
--------------------------------------------------

Behaviors.Idle = class(Behaviors.Idle)

function Behaviors.Idle:init()
end

function Behaviors.Idle:coordinates(tool)
	local rotation = nil

	if LevelEditor.selection:count() == 0 then
		local hovered_object = LevelEditor:hovered_object()
		rotation = hovered_object == nil and Quaternion.identity() or hovered_object:local_rotation()
	else
		rotation = tool._rotate_gizmo:rotation()
	end

	return rotation_coordinates(rotation)
end

function Behaviors.Idle:update(tool)
	LevelEditor.select_tool:update()
	local reference_object, component_id = LevelEditor.selection:last_selected_object()

	if reference_object ~= nil then
		-- Update the rotate gizmo pose from external factors.
		local pivot_pose = reference_object:pivot_pose(component_id)
		tool:set_pivot_pose(pivot_pose)

		local mouse_pos = LevelEditor.mouse.pos
		tool._rotate_gizmo:select_axis(LevelEditor.editor_camera, mouse_pos.x, mouse_pos.y)
		tool._rotate_gizmo:draw(LevelEditor.lines_noz, LevelEditor.editor_camera)
	end
end

function Behaviors.Idle:mouse_down(tool, x, y)
	if tool._rotate_gizmo:is_axis_selected() and LevelEditor.selection:count() > 0 then
		tool._rotate_gizmo:start_rotate(LevelEditor.editor_camera, x, y)
		tool._behavior = Behaviors.RotateSelectedObjects()
		LevelEditor:raise_highlight_changed()
	else
		LevelEditor.select_tool:mouse_down(x, y)
	end
end

function Behaviors.Idle:mouse_move(tool, x, y)
	LevelEditor.select_tool:mouse_move(x, y)
end

function Behaviors.Idle:mouse_up(tool, x, y)
	LevelEditor.select_tool:mouse_up(x, y)
end

function Behaviors.Idle:keyboard_rotate(tool, local_axis)
	if LevelEditor.selection:count() == 0 then return end

	-- Since this can be called when we're not the current tool, we must explicitly
	-- align the gizmo to the reference objects pivot pose before we rotate.
	local reference_object, component_id = LevelEditor.selection:last_selected_object()
	local pivot_pose = reference_object:pivot_pose(component_id)
	tool:set_pivot_pose(pivot_pose)

	-- Calculate delta rotation.
	local radians = LevelEditor.grid.rotation_snap / 180 * math.pi
	local tm = tool._rotate_gizmo:pose()
	local world_axis = Matrix4x4.transform_without_translation(tm, local_axis)
	local delta_rotation = Quaternion.axis_angle(world_axis, radians)
	local pivot_point = Matrix4x4.translation(tm)

	-- Apply delta rotation.
	transform_selected_elements()
	local local_start_poses, world_start_poses, is_cloning = start_rotate_selected_elements()
	delta_rotate_selected_elements(world_start_poses, pivot_point, delta_rotation)
	finish_rotate_selected_elements(local_start_poses, is_cloning)

	-- Since this can be called when we're not the current tool, we must explicitly
	-- align the gizmo to the the reference objects pivot point after we rotate.
	if LevelEditor:reference_system() == "Local" then
		local reference_object_rotation = reference_object:world_rotation(component_id)
		tool._rotate_gizmo:set_rotation(reference_object_rotation)
	end
end

function Behaviors.Idle:toggle_pivot_edit_mode(tool)
	local reference_object, component_id = LevelEditor.selection:last_selected_object()

	if reference_object ~= nil then
		tool._behavior = Behaviors.EditPivot(reference_object, component_id)
	end
end


--------------------------------------------------
-- RotateSelectedObjects behavior
--------------------------------------------------

Behaviors.RotateSelectedObjects = class(Behaviors.RotateSelectedObjects)

function Behaviors.RotateSelectedObjects:init()
	self._local_start_poses, self._world_start_poses, self._is_cloning = start_rotate_selected_elements()
end

function Behaviors.RotateSelectedObjects:coordinates(tool)
	return rotation_coordinates(tool._rotate_gizmo:rotation())
end

function Behaviors.RotateSelectedObjects:update(tool)
	tool._rotate_gizmo:draw(LevelEditor.lines_noz, LevelEditor.editor_camera)
	tool._rotate_gizmo:draw_drag_handles(LevelEditor.world_gui, LevelEditor.lines_noz, LevelEditor.editor_camera)
end

function Behaviors.RotateSelectedObjects:is_highlight_suppressed(tool)
	return true
end

function Behaviors.RotateSelectedObjects:on_deselected(tool)
	self:_commit_rotation_and_return_to_idle_state(tool)
end

function Behaviors.RotateSelectedObjects:mouse_move(tool, x, y)
	local snap_func = LevelEditor:is_angle_snap_enabled()
		and Func.partial(GridPlane.snap_number, LevelEditor.grid.rotation_snap / 180 * math.pi)
		or nil
	
	tool._rotate_gizmo:delta_rotate(LevelEditor.editor_camera, x, y, snap_func)
	delta_rotate_selected_elements(self._world_start_poses, tool._rotate_gizmo:position(), tool._rotate_gizmo:delta_rotation())

	if LevelEditor:reference_system() == "Local" then
		-- Orient the rotate gizmo after the reference object.
		local reference_object, component_id = LevelEditor.selection:last_selected_object()
		local reference_object_rotation = reference_object:world_rotation(component_id)
		tool._rotate_gizmo:set_rotation(reference_object_rotation)
	end
end

function Behaviors.RotateSelectedObjects:mouse_up(tool, x, y)
	self:_commit_rotation_and_return_to_idle_state(tool)
end

function Behaviors.RotateSelectedObjects:_commit_rotation_and_return_to_idle_state(tool)
	finish_rotate_selected_elements(self._local_start_poses, self._is_cloning)
	tool._behavior = Behaviors.Idle()
	LevelEditor:raise_highlight_changed()
end
