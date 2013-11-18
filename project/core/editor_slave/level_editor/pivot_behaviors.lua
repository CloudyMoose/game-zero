--------------------------------------------------
-- Utility functions
--------------------------------------------------

local function is_level_object_with_adjustable_pivot(level_object)
	return level_object ~= nil
	   and type(level_object.id) == "string"
	   and type(level_object.pivot_pose) == "function"
	   and type(level_object.local_pivot) == "function"
	   and type(level_object.set_world_pivot) == "function"
end

local function install(Behaviors)

	--------------------------------------------------
	-- EditPivot behavior
	--------------------------------------------------

	Behaviors.EditPivot = class(Behaviors.EditPivot)

	function Behaviors.EditPivot:init(level_object, component_id)
		assert(is_level_object_with_adjustable_pivot(level_object))
		assert(component_id == nil or type(component_id) == "string")
		self._level_object = level_object
		self._component_id = component_id
		self._pivot_gizmo = MoveGizmo()
	end

	function Behaviors.EditPivot:on_selected(tool)
		tool._behavior = Behaviors.Idle()
	end

	function Behaviors.EditPivot:coordinates(tool)
		return self._pivot_gizmo:position()
	end

	function Behaviors.EditPivot:update(tool)
		LevelEditor.select_tool:update()
		
		-- Update the pivot gizmo pose from external factors.
		local pivot_pose = self._level_object:pivot_pose(self._component_id)
		local gizmo_pose = LevelEditor:reference_system() == "World" and Matrix4x4.from_translation(Matrix4x4.translation(pivot_pose)) or pivot_pose
		self._pivot_gizmo:set_pose(gizmo_pose)

		local mouse_pos = LevelEditor.mouse.pos
		self._pivot_gizmo:select_axes(LevelEditor.editor_camera, mouse_pos.x, mouse_pos.y, false)
		self._pivot_gizmo:draw_grid_plane()
		self._pivot_gizmo:draw(LevelEditor.world_gui, LevelEditor.lines_noz, LevelEditor.editor_camera, false)
	end

	function Behaviors.EditPivot:mouse_down(tool, x, y)
		if self._pivot_gizmo:is_axes_selected() and LevelEditor.selection:count() > 0 then
			self._pivot_gizmo:start_move(LevelEditor.editor_camera, x, y)
			tool._behavior = Behaviors.DragPivot(self._level_object, self._component_id, self._pivot_gizmo)
		else
			local selection_changed = LevelEditor.select_tool:mouse_down(x, y)

			if selection_changed then
				tool._behavior = Behaviors.Idle()
			end
		end
	end

	function Behaviors.EditPivot:mouse_move(tool, x, y)
		LevelEditor.select_tool:mouse_move(x, y)
	end

	function Behaviors.EditPivot:mouse_up(tool, x, y)
		LevelEditor.select_tool:mouse_up(x, y)
	end

	function Behaviors.EditPivot:toggle_pivot_edit_mode(tool)
		tool._behavior = Behaviors.Idle()
	end


	--------------------------------------------------
	-- DragPivot behavior
	--------------------------------------------------

	Behaviors.DragPivot = class(Behaviors.DragPivot)

	function Behaviors.DragPivot:init(level_object, component_id, pivot_gizmo)
		assert(is_level_object_with_adjustable_pivot(level_object))
		assert(component_id == nil or type(component_id) == "string")
		assert(kind_of(pivot_gizmo) == MoveGizmo)
		self._level_object = level_object
		self._component_id = component_id
		self._pivot_gizmo = pivot_gizmo
	end

	function Behaviors.DragPivot:coordinates(tool)
		return self._pivot_gizmo:position()
	end

	function Behaviors.DragPivot:update(tool)
		self._pivot_gizmo:draw_grid_plane()
		self._pivot_gizmo:draw_drag_start(LevelEditor.lines_noz, LevelEditor.editor_camera)
		self._pivot_gizmo:draw(LevelEditor.world_gui, LevelEditor.lines_noz, LevelEditor.editor_camera, false)
	end

	function Behaviors.DragPivot:mouse_move(tool, x, y)
		local snap_function = LevelEditor:snap_function(self._pivot_gizmo:pose(), true)
		self._pivot_gizmo:delta_move(LevelEditor.editor_camera, x, y, snap_function)
		self._level_object:set_world_pivot(self._pivot_gizmo:position(), self._component_id)
	end

	function Behaviors.DragPivot:mouse_up(tool, x, y)
		local did_move = Vector3.length(self._pivot_gizmo:drag_delta()) > 0.000001

		if did_move then
			Application.console_send {
				type = "pivots_moved",
				scene_element_refs = { SceneElementRef.make(self._level_object.id, self._component_id) },
				pivots = { self._level_object:local_pivot(self._component_id) }
			}
		end

		tool._behavior = Behaviors.EditPivot(self._level_object, self._component_id)
	end

end

return install
