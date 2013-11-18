ObjectUtils = ObjectUtils or {}

function ObjectUtils.has_element_moved(scene_element_ref, start_pose)
	local object_id, component_id = SceneElementRef.unpack(scene_element_ref)
	local level_object = LevelEditor.objects[object_id]
	local end_pose = level_object:local_pose(component_id)
	local has_moved = not Matrix4x4.equal(start_pose, end_pose)
	return has_moved
end

function ObjectUtils.moved_elements(scene_element_refs, start_poses)
	local moved_scene_element_refs = {}
	local new_positions = {}
	local new_rotations = {}
	local new_scales = {}

	local function add(index, scene_element_ref)
		-- Skip unmoved elements.
		if scene_element_refs[index] == scene_element_ref and not ObjectUtils.has_element_moved(scene_element_ref, start_poses[index]) then
			return
		end

		local object_id, component_id = SceneElementRef.unpack(scene_element_ref)
		local level_object = LevelEditor.objects[object_id]
		local is_root_component = level_object:is_root_component(component_id)

		-- Recursively add child objects to the list of reported moved objects.
		if is_root_component and level_object._child_ids ~= nil then
			assert(Array.all(level_object._child_ids, Validation.is_object_id))
			Array.iteri(level_object._child_ids, add)
		end

		-- A root point move is sent as a regular non-component move.
		-- This ensures undo works property when moving the root point in component mode.
		table.insert(moved_scene_element_refs, is_root_component and object_id or scene_element_ref)
		table.insert(new_positions, level_object:local_position(component_id))
		table.insert(new_rotations, level_object:local_rotation(component_id))
		table.insert(new_scales, level_object:local_scale(component_id))
	end

	Array.iteri(scene_element_refs, add)
	assert(#new_positions == #moved_scene_element_refs)
	assert(#new_rotations == #moved_scene_element_refs)
	assert(#new_scales == #moved_scene_element_refs)
	return moved_scene_element_refs, new_positions, new_rotations, new_scales
end
