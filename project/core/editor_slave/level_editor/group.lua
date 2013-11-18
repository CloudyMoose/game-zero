--------------------------------------------------
-- Utility functions
--------------------------------------------------

local visual_raycast = Func.partial(Picking.raycast, Picking.is_visible) 
local object_box_as_array = Func.compose(Func.method("box"), Func.partial(Tuple.take, 2), Array.of)

local function compute_box(object_ids)
	if Array.is_empty(object_ids) then
		return Matrix4x4.identity(), Vector3(0.5, 0.5, 0.5), Vector3(1, 1, 1)
	end

	-- The last object will determine the orientation of the bounding box and the scale of the group.
	local lookup_object = Func.of_table(LevelEditor.objects)
	Array.iter(object_ids, function(id) if lookup_object(id) == nil then print("Unknown", id) end end)
	local level_objects = Array.map(object_ids, lookup_object)
	local boxes = Array.reverse(level_objects):collect(object_box_as_array)
	assert(#boxes >= 2)
	local tm, r = Math.merge_boxes(unpack(boxes))
	local scale = Array.last(level_objects):local_scale()
	return tm, r, scale
end


--------------------------------------------------
-- Group
--------------------------------------------------

Group = class(Group, Object)

function Group:init(id, child_ids)
	assert(Validation.is_object_id(id))
	assert(#child_ids > 0)
	assert(Array.all(child_ids, Validation.is_object_id))
	Object.init(self, id)
	self._child_ids = Array.copy(child_ids)
	
	local unscaled_pose, scaled_radius, scale = compute_box(child_ids)
	self._position:store(Matrix4x4.translation(unscaled_pose))
	self._rotation:store(Matrix4x4.rotation(unscaled_pose))
	self._scale:store(scale)
	self._radius = Vector3Box(Vector3.divide_elements(scaled_radius, scale))
	
	local scaled_pose = Matrix4x4.copy(unscaled_pose)
	Matrix4x4.set_scale(scaled_pose, scale)
	local to_group = Matrix4x4.inverse(scaled_pose)
	local to_group_rotation = Quaternion.inverse(self:local_rotation())
	
	for _, child_id in ipairs(child_ids) do
		local nv, nq, nm = Script.temp_count()
		local o = LevelEditor.objects[child_id]
		o.parent_id = id
		o._group_local_position = Vector3Box(Matrix4x4.transform(to_group, o:local_position()))
		o._group_local_rotation = QuaternionBox(Quaternion.multiply(to_group_rotation, o:local_rotation()))
		o._group_local_scale = Vector3Box(Vector3.divide_elements(o:local_scale(), scale))
		Script.set_temp_count(nv, nq, nm)
	end
end

function Group:child_selection_order()
	return Array.copy(self._child_ids)
end

function Group:destroy()
	Object.destroy(self)

	for _, id in ipairs(self._child_ids) do
		local o = LevelEditor.objects[id]
		
		if o then
			o.parent_id = nil
			o._group_local_position = nil
			o._group_local_rotation = nil
			o._group_local_scale = nil
		end
	end
end

function Group:duplicate(spawned)
	-- Duplicate child objects first, then create a new Group that refer to the new child objects.
	-- The group needs to be added to the spawned list last, so append it to an empty table for now.
	local spawned_groups = {}
	local copy = setmetatable(Object.duplicate(self, spawned_groups), Group)
	assert(Validation.is_object_id(self.id))
	assert(Validation.is_object_id(copy.id))
	assert(copy.id ~= self.id)
	copy._radius = Vector3Box(self._radius:unbox())
	copy._child_ids = {}

	for _, id in ipairs(self._child_ids) do
		local nv, nq, nm = Script.temp_count()
		local o = LevelEditor.objects[id]
		local co = o:duplicate(spawned)

		if co ~= nil then
			co.parent_id = copy.id
			co._group_local_position = Vector3Box(o._group_local_position:unbox())
			co._group_local_rotation = QuaternionBox(o._group_local_rotation:unbox())
			co._group_local_scale = Vector3Box(o._group_local_scale:unbox())
			assert(Validation.is_object_id(co.id))
			table.insert(copy._child_ids, co.id)
		end
		Script.set_temp_count(nv, nq, nm)
	end

	-- Append the spawned group to the end of the spawned list.
	assert(#spawned_groups == 1)
	table.insert(spawned, spawned_groups[1])
	return copy
end

function Group:spawn_data()
	local sd = Object.spawn_data(self)
	sd.klass = "group"
	sd.ids = self._child_ids
	return sd
end

function Group:box(component_id)
	assert(component_id == nil)
	local unscaled_pose = Matrix4x4.from_quaternion_position(self:local_rotation(), self:local_position())
	local scaled_radius = Vector3.multiply_elements(self._radius:unbox(), self:local_scale())
	return unscaled_pose, scaled_radius
end

function Group:raycast(ray_start, ray_dir, ray_length)
	local oobb_distance = Intersect.ray_box(ray_start, ray_dir, self:box())

	if oobb_distance ~= nil and oobb_distance < ray_length then
		local member_objects = Array.choose(self._child_ids, Func.of_table(LevelEditor.objects))
		local _, distance, normal = visual_raycast(member_objects, ray_start, ray_dir, ray_length)
		return distance, normal
	else
		return nil, nil
	end
end

function Group:set_local_position(position, component_id)
	Object.set_local_position(self, position, component_id)
	self:_update_child_transforms()
end

function Group:set_local_rotation(rotation, component_id)
	Object.set_local_rotation(self, rotation, component_id)
	self:_update_child_transforms()
end

function Group:set_local_scale(scale, component_id)
	Object.set_local_scale(self, scale, component_id)
	self:_update_child_transforms()
end

function Group:highlight_changed(component_id)
	assert(component_id == nil)

	for _, id in ipairs(self._child_ids) do
		local o = LevelEditor.objects[id]
		o:highlight_changed()
	end
end

function Group:children()
	return Array.map(self._child_ids, Func.of_table(LevelEditor.objects))
end

function Group:_update_child_transforms()
	local group_scale = self:local_scale()
	local unscaled_group_tm = Matrix4x4.from_quaternion_position(self:local_rotation(), self:local_position())
	local scaled_group_tm = Matrix4x4.copy(unscaled_group_tm)
	Matrix4x4.set_scale(scaled_group_tm, group_scale)

	for _, o in ipairs(self:children()) do
		local nv, nq, nm = Script.temp_count()
		local scale = Vector3.multiply_elements(o._group_local_scale:unbox(), group_scale)
		local unscaled_local_tm = Matrix4x4.from_quaternion_position(o._group_local_rotation:unbox(), o._group_local_position:unbox())
		local scaled_local_tm = Matrix4x4.copy(unscaled_local_tm)
		Matrix4x4.set_scale(scaled_local_tm, scale)
		local unscaled_world_tm = Matrix4x4.multiply(unscaled_local_tm, unscaled_group_tm)
		local scaled_world_tm = Matrix4x4.multiply(scaled_local_tm, scaled_group_tm)
		o:set_world_position(Matrix4x4.translation(scaled_world_tm))
		o:set_world_rotation(Matrix4x4.rotation(unscaled_world_tm))
		o:set_local_scale(scale)
		Script.set_temp_count(nv, nq, nm)
	end
end
