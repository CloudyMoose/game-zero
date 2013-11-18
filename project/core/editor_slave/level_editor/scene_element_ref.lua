--------------------------------------------------
-- Utility functions
--------------------------------------------------

-- This string separates the object id from the component id. It has a corresponding
-- constant in Bitsquid.LevelEditor.SceneElementRef.SeparatorChar on the C# side.
local separator_string = "/"


--------------------------------------------------
-- SceneElementRef
--------------------------------------------------

SceneElementRef = SceneElementRef or {}

function SceneElementRef.make(object_id, component_id)
	assert(Validation.is_object_id(object_id))
	assert(component_id == nil or Validation.is_component_id(component_id))
	return component_id == nil
	   and object_id
	    or object_id .. separator_string .. tostring(component_id)
end

function SceneElementRef.unpack(scene_element_ref)
	local separator_index = string.find(scene_element_ref, separator_string, 1, true)
	local object_id, component_id

	if separator_index == nil then
		object_id = scene_element_ref
		component_id = nil
	else
		object_id = string.sub(scene_element_ref, 1, separator_index - 1)
		component_id = string.sub(scene_element_ref, separator_index + 1)
	end

	return object_id, component_id
end

function SceneElementRef.object_id(scene_element_ref)
	local separator_index = string.find(scene_element_ref, separator_string, 1, true)
	local object_id = separator_index == nil and scene_element_ref or string.sub(scene_element_ref, 1, separator_index - 1)
	return object_id
end

function SceneElementRef.component_id(scene_element_ref)
	local separator_index = string.find(scene_element_ref, separator_string, 1, true)
	local component_id = separator_index ~= nil and string.sub(scene_element_ref, separator_index + 1) or nil
	return component_id
end

function SceneElementRef.map(transform, scene_element_ref)
	local object_id, component_id = SceneElementRef.unpack(scene_element_ref)
	local level_object = LevelEditor.objects[object_id]
	local result = transform(level_object, component_id)
	return result
end

SceneElementRef.is_selectable = Func.partial(SceneElementRef.map, Picking.is_selectable)
SceneElementRef.local_pose = Func.partial(SceneElementRef.map, Func.method("local_pose"))
