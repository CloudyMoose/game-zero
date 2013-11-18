--------------------------------------------------
-- Utility functions
--------------------------------------------------

local install_pivot_behaviors = require "core/editor_slave/level_editor/pivot_behaviors"

local boxed_world_position = Func.compose(Func.partial(SceneElementRef.map, Func.method("world_position")), Vector3Box)

local function start_move_selected_elements()
	local is_cloning = LevelEditor:is_clone_modifier_held() and LevelEditor.selection:duplicate()
	local local_start_poses = LevelEditor.selection:save_state()
	local world_start_positions = Array.map(LevelEditor.selection:scene_element_refs(), boxed_world_position)
	return local_start_poses, world_start_positions, is_cloning
end

local function delta_move_selected_elements(world_start_positions, offset)
	local scene_element_refs = LevelEditor.selection:scene_element_refs()

	for index, scene_element_ref in ipairs(scene_element_refs) do
		local object_id, component_id = SceneElementRef.unpack(scene_element_ref)
		local level_object = LevelEditor.objects[object_id]
		local start_position = world_start_positions[index]:unbox()
		level_object:set_world_position(start_position + offset, component_id)
	end
end

local function finish_move_selected_elements(local_start_poses, is_cloning)
	LevelEditor.selection:finish_move(local_start_poses, is_cloning)
end


--------------------------------------------------
-- MoveTool
--------------------------------------------------

MoveTool = class(MoveTool, Tool)
MoveTool.Behaviors = MoveTool.Behaviors or {}
local Behaviors = MoveTool.Behaviors
install_pivot_behaviors(Behaviors)

function MoveTool:init()
	self._move_gizmo = MoveGizmo()
	self._behavior = Behaviors.Idle()
end

function MoveTool:coordinates()
	return self._behavior:coordinates(self)
end

function MoveTool:update()
	if self._behavior.update ~= nil then
		self._behavior:update(self)
	end
end

function MoveTool:is_highlight_suppressed()
	return self._behavior.is_highlight_suppressed and self._behavior:is_highlight_suppressed(self) or false
end

function MoveTool:on_deselected()
	if self._behavior.on_deselected ~= nil then
		self._behavior:on_deselected(self)
	end
end

function MoveTool:mouse_down(x, y)
	if self._behavior.mouse_down ~= nil then
		self._behavior:mouse_down(self, x, y)
	end
end

function MoveTool:mouse_move(x, y)
	if self._behavior.mouse_move ~= nil then
		self._behavior:mouse_move(self, x, y)
	end
end

function MoveTool:mouse_up(x, y)
	if self._behavior.mouse_up ~= nil then
		self._behavior:mouse_up(self, x, y)
	end
end

function MoveTool:keyboard_move(direction)
	if self._behavior.keyboard_move ~= nil then
		self._behavior:keyboard_move(self, direction)
	end
end

function MoveTool:toggle_pivot_edit_mode()
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
	local position = nil

	if LevelEditor.selection:count() == 0 then
		local hovered_object = LevelEditor:hovered_object()
		position = hovered_object == nil and Vector3(0, 0, 0) or hovered_object:local_position()
	else
		position = tool._move_gizmo:position()
	end

	return position
end

function Behaviors.Idle:update(tool)
	LevelEditor.select_tool:update()
	local reference_object, component_id = LevelEditor.selection:last_selected_object()
	
	if reference_object ~= nil then
		-- Update the move gizmo pose from external factors.
		local pivot_pose = reference_object:pivot_pose(component_id)
		local gizmo_pose = LevelEditor:reference_system() == "World" and Matrix4x4.from_translation(Matrix4x4.translation(pivot_pose)) or pivot_pose
		tool._move_gizmo:set_pose(gizmo_pose)

		local mouse_pos = LevelEditor.mouse.pos
		tool._move_gizmo:select_axes(LevelEditor.editor_camera, mouse_pos.x, mouse_pos.y, true)
		tool._move_gizmo:draw_grid_plane()
		tool._move_gizmo:draw(LevelEditor.world_gui, LevelEditor.lines_noz, LevelEditor.editor_camera, true)
	end
end

function Behaviors.Idle:mouse_down(tool, x, y)
	LevelEditor:abort_physics_simulation()

	if tool._move_gizmo:is_axes_selected() and LevelEditor.selection:count() > 0 then
		tool._move_gizmo:start_move(LevelEditor.editor_camera, x, y)
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

function Behaviors.Idle:keyboard_move(tool, direction)
	if LevelEditor.selection:count() == 0 then return end

	local v = direction * LevelEditor.grid.size
	local tm = tool._move_gizmo:pose()
	local offset = Matrix4x4.transform_without_translation(tm, v)
	local local_start_poses, world_start_positions, is_cloning = start_move_selected_elements()
	delta_move_selected_elements(world_start_positions, offset)
	finish_move_selected_elements(local_start_poses, is_cloning)
	tool._move_gizmo:set_position(tool._move_gizmo:position() + offset)
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
	self._local_start_poses, self._world_start_positions, self._is_cloning = start_move_selected_elements()
	self._selected_ids = Set.of_array(LevelEditor.selection:scene_element_refs(), SceneElementRef.object_id)
end

function Behaviors.DragSelectedObjects:coordinates(tool)
	return tool._move_gizmo:position()
end

function Behaviors.DragSelectedObjects:update(tool)
	tool._move_gizmo:draw_grid_plane()
	tool._move_gizmo:draw_drag_start(LevelEditor.lines_noz, LevelEditor.editor_camera)
	tool._move_gizmo:draw(LevelEditor.world_gui, LevelEditor.lines_noz, LevelEditor.editor_camera, true)
end

function Behaviors.DragSelectedObjects:is_highlight_suppressed(tool)
	return true
end

function Behaviors.DragSelectedObjects:on_deselected(tool)
	self:_commit_drag_and_return_to_idle_state(tool)
end

function Behaviors.DragSelectedObjects:mouse_move(tool, x, y)
	local snap_function = LevelEditor:snap_function(tool._move_gizmo:pose(), true, self._selected_ids)
	tool._move_gizmo:delta_move(LevelEditor.editor_camera, x, y, snap_function)
	delta_move_selected_elements(self._world_start_positions, tool._move_gizmo:drag_delta())
end

function Behaviors.DragSelectedObjects:mouse_up(tool, x, y)
	self:_commit_drag_and_return_to_idle_state(tool)
end

function Behaviors.DragSelectedObjects:_commit_drag_and_return_to_idle_state(tool)
	finish_move_selected_elements(self._local_start_poses, self._is_cloning)
	tool._behavior = Behaviors.Idle()
	LevelEditor:raise_highlight_changed()
end
