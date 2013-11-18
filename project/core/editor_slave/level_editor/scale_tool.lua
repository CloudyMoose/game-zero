--------------------------------------------------
-- Utility functions
--------------------------------------------------

local install_pivot_behaviors = require "core/editor_slave/level_editor/pivot_behaviors"

local boxed_world_position = Func.compose(Func.partial(SceneElementRef.map, Func.method("world_position")), Vector3Box)
local boxed_local_scale = Func.compose(Func.partial(SceneElementRef.map, Func.method("local_scale")), Vector3Box)

local function start_scale_selected_elements()
	local is_cloning = LevelEditor:is_clone_modifier_held() and LevelEditor.selection:duplicate()
	local local_start_poses = LevelEditor.selection:save_state()
	local world_start_positions = Array.map(LevelEditor.selection:scene_element_refs(), boxed_world_position)
	local local_start_scales = Array.map(LevelEditor.selection:scene_element_refs(), boxed_local_scale)
	return local_start_poses, world_start_positions, local_start_scales, is_cloning
end

local function delta_scale_selected_elements(world_start_positions, local_start_scales, scale_factors, pivot_pose)
	local scene_element_refs = LevelEditor.selection:scene_element_refs()
	local from_pivot_space = Func.partial(Matrix4x4.transform_without_translation, pivot_pose)
	local to_pivot_space = Func.partial(Matrix4x4.transform_without_translation, Matrix4x4.inverse(pivot_pose))

	for index, scene_element_ref in ipairs(scene_element_refs) do
		local object_id, component_id = SceneElementRef.unpack(scene_element_ref)
		local level_object = LevelEditor.objects[object_id]
		local start_position = world_start_positions[index]:unbox()
		local start_scale = local_start_scales[index]:unbox()

		if scale_factors.x > 1 and start_scale.x < 0.01 then start_scale.x = scale_factors.x * 0.005 end
		if scale_factors.y > 1 and start_scale.y < 0.01 then start_scale.y = scale_factors.y * 0.005 end
		if scale_factors.z > 1 and start_scale.z < 0.01 then start_scale.z = scale_factors.z * 0.005 end

		local scale = Vector3.multiply_elements(start_scale, scale_factors)
		local pivot_to_start = start_position - Matrix4x4.translation(pivot_pose)
		local offset_in_pivot_space = to_pivot_space(pivot_to_start)
		local offset = from_pivot_space(Vector3.multiply_elements(offset_in_pivot_space, scale_factors))
		level_object:set_local_scale(scale, component_id)
		level_object:set_world_position(start_position + offset - pivot_to_start, component_id)
	end
end

local function finish_scale_selected_elements(local_start_poses, is_cloning)
	LevelEditor.selection:finish_move(local_start_poses, is_cloning)
end

local function is_non_uniform_scaling_supported()
	local selection = LevelEditor.selection
	if selection:count() > 1 then return false end

	local is_group = Func.compose(kind_of, Op.eq(Group))
	local is_level_reference = Func.compose(kind_of, Op.eq(LevelReference))
	local is_non_container_object = Func.negate(Func.any{is_group, is_level_reference})
	return selection:objects():all(is_non_container_object)
end


--------------------------------------------------
-- ScaleTool
--------------------------------------------------

ScaleTool = class(ScaleTool, Tool)
ScaleTool.Behaviors = ScaleTool.Behaviors or {}
local Behaviors = ScaleTool.Behaviors
install_pivot_behaviors(Behaviors)

function ScaleTool:init()
	self._scale_gizmo = ScaleGizmo()
	self._behavior = Behaviors.Idle()
end

function ScaleTool:on_selected()
	if self._behavior.on_selected ~= nil then
		self._behavior:on_selected(self)
	end
end

function ScaleTool:coordinates()
	return self._behavior:coordinates(self)
end

function ScaleTool:update()
	if self._behavior.update ~= nil then
		self._behavior:update(self)
	end
end

function ScaleTool:is_highlight_suppressed()
	return self._behavior.is_highlight_suppressed and self._behavior:is_highlight_suppressed(self) or false
end

function ScaleTool:on_deselected()
	if self._behavior.on_deselected ~= nil then
		self._behavior:on_deselected(self)
	end
end

function ScaleTool:mouse_down(x, y)
	if self._behavior.mouse_down ~= nil then
		self._behavior:mouse_down(self, x, y)
	end
end

function ScaleTool:mouse_move(x, y)
	if self._behavior.mouse_move ~= nil then
		self._behavior:mouse_move(self, x, y)
	end
end

function ScaleTool:mouse_up(x, y)
	if self._behavior.mouse_up ~= nil then
		self._behavior:mouse_up(self, x, y)
	end
end

function ScaleTool:toggle_pivot_edit_mode()
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
	local scale = nil

	if LevelEditor.selection:count() == 0 then
		local hovered_object = LevelEditor:hovered_object()
		scale = hovered_object == nil and Vector3(1, 1, 1) or hovered_object:local_scale()
	else
		local last_selected_object, component_id = LevelEditor.selection:last_selected_object()
		scale = last_selected_object == nil and Vector3(1, 1, 1) or last_selected_object:local_scale(component_id)
	end

	return scale
end

function Behaviors.Idle:update(tool)
	LevelEditor.select_tool:update()
	local reference_object, component_id = LevelEditor.selection:last_selected_object()
	
	if reference_object ~= nil then
		-- Update the scale gizmo pose from external factors.
		local pivot_pose = reference_object:pivot_pose(component_id)
		tool._scale_gizmo:set_pose(pivot_pose)

		local can_scale_non_uniform = is_non_uniform_scaling_supported()
		tool._scale_gizmo:set_non_uniform_scaling_supported(can_scale_non_uniform)

		local mouse_pos = LevelEditor.mouse.pos
		tool._scale_gizmo:select_axes(LevelEditor.editor_camera, mouse_pos.x, mouse_pos.y)
		tool._scale_gizmo:draw(LevelEditor.world_gui, LevelEditor.lines_noz, LevelEditor.editor_camera, false)
	end
end

function Behaviors.Idle:mouse_down(tool, x, y)
	LevelEditor:abort_physics_simulation()

	if tool._scale_gizmo:is_axes_selected() and LevelEditor.selection:count() > 0 then
		tool._scale_gizmo:start_scale(LevelEditor.editor_camera, x, y)
		tool._behavior = Behaviors.DragSelectedObjects()
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

function Behaviors.Idle:toggle_pivot_edit_mode(tool)
	local reference_object, component_id = LevelEditor.selection:last_selected_object()

	if reference_object ~= nil then
		tool._behavior = Behaviors.EditPivot(reference_object, component_id)
	end
end


--------------------------------------------------
-- DragSelectedObjects behavior
--------------------------------------------------

Behaviors.DragSelectedObjects = class(Behaviors.DragSelectedObjects)

function Behaviors.DragSelectedObjects:init()
	self._local_start_poses, self._world_start_positions, self._local_start_scales, self._is_cloning  = start_scale_selected_elements()
	self._selected_ids = Set.of_array(LevelEditor.selection:scene_element_refs(), SceneElementRef.object_id)
end

function Behaviors.DragSelectedObjects:coordinates(tool)
	return tool._scale_gizmo:position()
end

function Behaviors.DragSelectedObjects:update(tool)
	tool._scale_gizmo:draw_drag_start(LevelEditor.world_gui, LevelEditor.editor_camera)
	tool._scale_gizmo:draw(LevelEditor.world_gui, LevelEditor.lines_noz, LevelEditor.editor_camera, true)
end

function Behaviors.DragSelectedObjects:is_highlight_suppressed(tool)
	return true
end

function Behaviors.DragSelectedObjects:on_deselected(tool)
	self:_commit_drag_and_return_to_idle_state(tool)
end

function Behaviors.DragSelectedObjects:mouse_move(tool, x, y)
	tool._scale_gizmo:delta_scale(LevelEditor.editor_camera, x, y)
	delta_scale_selected_elements(self._world_start_positions, self._local_start_scales, tool._scale_gizmo:delta_scale_factors(), tool._scale_gizmo:pose())
end

function Behaviors.DragSelectedObjects:mouse_up(tool, x, y)
	self:_commit_drag_and_return_to_idle_state(tool)
end

function Behaviors.DragSelectedObjects:_commit_drag_and_return_to_idle_state(tool)
	finish_scale_selected_elements(self._local_start_poses, self._is_cloning)
	tool._behavior = Behaviors.Idle()
	tool._scale_gizmo:reset_delta_scale_factors()
	LevelEditor:raise_highlight_changed()
end
