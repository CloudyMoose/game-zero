--------------------------------------------------
-- Utility functions
--------------------------------------------------

local function raise_highlight_changed(scene_element_ref)
	if scene_element_ref == nil then return end
	local object_id, component_id = SceneElementRef.unpack(scene_element_ref)
	local level_object = LevelEditor.objects[object_id]

	if level_object ~= nil then
		level_object:highlight_changed(component_id)
	end
end


--------------------------------------------------
-- Selection
--------------------------------------------------

-- Tools for manipulating the selected scene elements in the editor. The selection
-- is represented by a collection of SceneElementRef, each SceneElementRef identifying an
-- individual object or a component inside an object.

Selection = class(Selection)

function Selection:init()
	self._scene_element_refs = {}
	self._lookup = {}
end

-- Returns true if the specified scene element is a part of the selection.
function Selection:includes(scene_element_ref)
	return self._lookup[scene_element_ref] ~= nil
end

-- Returns a list of all selected scene element refs.
-- A scene element ref may simply be an object id, or it can be an object id
-- combined with a component id, such as a particular node inside a unit.
function Selection:scene_element_refs()
	return self._scene_element_refs
end

-- Returns a list of all level objects that have selected components, excluding group members.
function Selection:objects()
	return Array.map(self._scene_element_refs, SceneElementRef.object_id)
				:distinct()
				:choose(Func.of_table(LevelEditor.objects))
end

-- Returns the last selected level object and component id.
function Selection:last_selected_object()
	local scene_element_ref = Array.last(self:scene_element_refs())

	if scene_element_ref ~= nil then
		local object_id, component_id = SceneElementRef.unpack(scene_element_ref)
		local level_object = LevelEditor.objects[object_id]
		return level_object, component_id
	end

	return nil, nil
end

-- Adds the specified scene element to the selection.
function Selection:add(scene_element_ref)
	if not self:includes(scene_element_ref) then
		local old_last_selected = Array.last(self._scene_element_refs)
		self._scene_element_refs[#self._scene_element_refs + 1] = scene_element_ref
		self._lookup[scene_element_ref] = true
		raise_highlight_changed(scene_element_ref)
		raise_highlight_changed(old_last_selected)
	end
end

-- Removes the specified scene element from the selection.
function Selection:remove(scene_element_ref)
	if self:includes(scene_element_ref) then
		local old_last_selected = Array.last(self._scene_element_refs)
		self._scene_element_refs = Array.filter(self._scene_element_refs, Op.neq(scene_element_ref))
		self._lookup[scene_element_ref] = nil
		raise_highlight_changed(scene_element_ref)

		if scene_element_ref == old_last_selected then
			local new_last_selected = Array.last(self._scene_element_refs)
			raise_highlight_changed(new_last_selected)
		end
	end
end

-- Clears the selection.
function Selection:clear()
	local previous_selection = self._scene_element_refs
	self._scene_element_refs = {}
	self._lookup = {}
	Array.iter(previous_selection, raise_highlight_changed)
end

-- Sets the selection to the specified items.
function Selection:set(scene_element_refs)
	local old_set = self._lookup
	local new_set = Set.of_array(scene_element_refs)
	local added_set = Set.difference(new_set, old_set)
	local removed_set = Set.difference(old_set, new_set)
	local old_last_selected = Array.last(self._scene_element_refs)
	local new_last_selected = Array.last(scene_element_refs)
	self._scene_element_refs = scene_element_refs
	self._lookup = new_set
	added_set:iter(raise_highlight_changed)
	removed_set:iter(raise_highlight_changed)

	if new_last_selected ~= old_last_selected then
		raise_highlight_changed(new_last_selected)
		raise_highlight_changed(old_last_selected)
	end
end

-- Returns an object-oriented bounding box encompassing all selected objects.
-- If no objects are selected, returns nil, nil.
function Selection:oobb()
	local selected_objects = self:objects()
	local merged_pose, merged_radius = OOBB.merged_box(selected_objects, Func.method("box"))
	return merged_pose, merged_radius
end

function Selection:export_obj(file)
	local expand_groups
	expand_groups = function (lo)
		if kind_of(lo) == Group then
			return Array.collect(lo:children(), expand_groups)
		else
			return {lo}
		end
	end
	local flat = Array.collect(self:objects(), expand_groups)
	local units = Array.map(Array.filter(flat, function(lo) return Unit.alive(lo._unit) end), function(lo) return lo._unit end)
	Application.export_mesh_geometry(file, units)
end

function Selection:count()
	return #self._scene_element_refs
end

function Selection:send()
	Application.console_send { type = "selection", selection = self._scene_element_refs }
end

function Selection:save()
	return Array.copy(self._scene_element_refs)
end


--------------------------------------------------
-- Moving and rotating units
--------------------------------------------------

function Selection:align_to(dest_position, dest_rotation)
	if self:count() == 0 then return end

	-- We have a selection. Align the last selected object to the destination transform,
	-- and arrange the remaining objects relative to the last selected object.
	local reference_object, reference_component_id = self:last_selected_object()
	local reference_tm = reference_object:pivot_pose(reference_component_id)
	local to_reference_tm = Matrix4x4.inverse(reference_tm)
	local dest_tm = Matrix4x4.from_quaternion_position(dest_rotation, dest_position)
	local to_dest_tm = Matrix4x4.multiply(to_reference_tm, dest_tm)
	local state = self:save_state()

	for _, scene_element_ref in ipairs(self._scene_element_refs) do
		local object_id, component_id = SceneElementRef.unpack(scene_element_ref)
		local level_object = LevelEditor.objects[object_id]
		local world_position = level_object:world_position(component_id)
		local world_rotation = level_object:world_rotation(component_id)
		local world_pose = Matrix4x4.from_quaternion_position(world_rotation, world_position)
		local relative_to_dest_tm = Matrix4x4.multiply(world_pose, to_dest_tm)
		level_object:set_world_position(Matrix4x4.translation(relative_to_dest_tm), component_id)
		level_object:set_world_rotation(Matrix4x4.rotation(relative_to_dest_tm), component_id)
	end
	
	self:finish_move(state, false)
end

function Selection:align_to_floor(floor_object)
	if self:count() == 0 then return end
	local state = self:save_state()
	
	for _, scene_element_ref in ipairs(self._scene_element_refs) do
		local object_id, component_id = SceneElementRef.unpack(scene_element_ref)
		local level_object = LevelEditor.objects[object_id]
		Align.to_floor(floor_object, level_object, component_id)
	end

	self:finish_move(state, false)
end

function Selection:duplicate()
	-- TODO: Currently we only allow duplication of whole level objects, not components.
	if Array.any(self:scene_element_refs(), SceneElementRef.component_id) then
		return false
	end

	-- Don't allow duplication in story mode
	if LevelEditor.select_tool:is_in_story_mode() then
		return false
	end

	self._before_duplicate = self._scene_element_refs
	self._spawned = {}
	local copies = {}
	
	for _, o in ipairs(self:objects()) do
		local copy = o:duplicate(self._spawned)

		if copy ~= nil then
			copies[#copies + 1] = copy.id
		end
	end

	self:set(copies)
	return true
end

function Selection:save_state()
	local boxed_pose = Func.compose(SceneElementRef.local_pose, Matrix4x4Box)
	return Array.map(self._scene_element_refs, boxed_pose)
end

function Selection:finish_move(boxed_start_poses, cloned)
	local start_poses = Array.map(boxed_start_poses, Func.method("unbox"))
	local moved_scene_element_refs, new_positions, new_rotations, new_scales = ObjectUtils.moved_elements(self._scene_element_refs, start_poses)

	if #moved_scene_element_refs == 0 then
		if cloned then
			for _, o in ipairs(self._spawned) do
				o:destroy()
			end

			self:set(self._before_duplicate)
		end
	else
		if cloned then
			LevelEditor:cloned(self._spawned)
		end

		-- Call level_object:complete_move() on all moved objects.
		Set.of_array(moved_scene_element_refs, SceneElementRef.object_id)
		   :map(Func.of_table(LevelEditor.objects))
		   :iter(Func.method("complete_move"))

		-- Notify the level editor of the new poses, registering an undo entry.
		Application.console_send {
			type = "elements_moved",
			scene_element_refs = moved_scene_element_refs,
			positions = new_positions,
			rotations = new_rotations,
			scales = new_scales
		}
	end
end


--------------------------------------------------
-- Pivot control
--------------------------------------------------

function Selection:center_pivots()
	self:_perform_pivot_operation(Func.method("center_pivot"))
end

function Selection:reset_pivots()
	self:_perform_pivot_operation(Func.method("reset_pivot"))
end

function Selection:_perform_pivot_operation(alter)
	local function altered_local_pivot(scene_element_ref)
		local object_id, component_id = SceneElementRef.unpack(scene_element_ref)
		local level_object = LevelEditor.objects[object_id]
		alter(level_object, component_id)
		return level_object:local_pivot()
	end

	local pivots = Array.map(self._scene_element_refs, altered_local_pivot)
	Application.console_send { type = "pivots_moved", scene_element_refs = self._scene_element_refs, pivots = pivots }
end
