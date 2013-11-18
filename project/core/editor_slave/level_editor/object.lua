--------------------------------------------------
-- ObjectBase
--------------------------------------------------

ObjectBase = class(ObjectBase)

function ObjectBase:init(id)
	assert(id == nil or Validation.is_object_id(id))
	self.id = id
	self.hidden = false
	self.unselectable = false
	self._local_pivot = Vector3Box(0, 0, 0)

	if self.id == nil and Application.guid then
		self.id = Application.guid()
	end
end

function ObjectBase:destroy()
	LevelEditor.objects[self.id] = nil
end

function ObjectBase:duplicate(spawned)
	local copy = ObjectBase()
	copy.hidden = self.hidden
	copy.unselectable = self.unselectable
	copy.duplication_source = self
	copy:set_local_pivot(self:local_pivot())
	assert(Validation.is_object_id(copy.id))
	LevelEditor.objects[copy.id] = copy
	spawned[#spawned + 1] = copy
	return copy
end

function ObjectBase:spawn_data()
	return {
		id = self.id,
		pos = self:local_position(),
		rot = self:local_rotation(),
		scl = self:local_scale(),
		pivot = self:local_pivot()
	}
end

function ObjectBase:raycast(ray_start, ray_dir, ray_length)
	local pose, radius = self:box()
	local is_ray_origin_inside_box = Math.point_in_box(ray_start, pose, radius)
	if is_ray_origin_inside_box then return nil, nil end

	local distance_along_ray = Math.ray_box_intersection(ray_start, ray_dir, pose, radius)
	local is_box_missed_by_ray = distance_along_ray < 0
	if is_box_missed_by_ray then return nil, nil end

	if distance_along_ray < ray_length then
		return distance_along_ray, -ray_dir
	else
		return nil, nil
	end
end

function ObjectBase:world_pivot(component_id)
	local local_pivot = self:local_pivot(component_id)
	return self:to_global(local_pivot, component_id)
end

function ObjectBase:set_world_pivot(point, component_id)
	local local_pivot = self:to_local(point, component_id)
	self:set_local_pivot(local_pivot, component_id)
end

function ObjectBase:center_pivot(component_id)
	local tm, _ = self:box(component_id)
	local center = Matrix4x4.translation(tm)
	self:set_world_pivot(center, component_id)
end

function ObjectBase:reset_pivot(component_id)
	self:set_local_pivot(Vector3(0, 0, 0), component_id)
end

function ObjectBase:pivot_pose(component_id)
	local rotation = self:world_rotation(component_id)
	local position = self:world_pivot(component_id)
	local pivot_pose = Matrix4x4.from_quaternion_position(rotation, position)
	return pivot_pose
end

function ObjectBase:local_pose(component_id)
	local position = self:local_position(component_id)
	local rotation = self:local_rotation(component_id)
	local scale = self:local_scale(component_id)
	local pose = Matrix4x4.from_quaternion_position(rotation, position)
	Matrix4x4.set_scale(pose, scale)
	return pose
end

function ObjectBase:complete_move()
end

function ObjectBase:to_global(local_position, component_id)
	return Matrix4x4.transform(self:world_pose(component_id), local_position)
end

function ObjectBase:to_local(world_position, component_id)
	local tmi = Matrix4x4.inverse(self:world_pose(component_id))
	return Matrix4x4.transform(tmi, world_position)
end

function ObjectBase:to_global_position_and_rotation(local_position, local_rotation, component_id)
	local tm = self:world_pose(component_id)
	local local_pose = Matrix4x4.from_quaternion_position(local_rotation, local_position)
	local world_pose = Matrix4x4.multiply(local_pose, tm)
	local world_position = Matrix4x4.translation(world_pose)
	local world_rotation = Matrix4x4.rotation(world_pose)
	return world_position, world_rotation
end

function ObjectBase:to_local_position_and_rotation(world_position, world_rotation, component_id)
	local tmi = Matrix4x4.inverse(self:world_pose(component_id))
	local world_pose = Matrix4x4.from_quaternion_position(world_rotation, world_position)
	local local_pose = Matrix4x4.multiply(world_pose, tmi)
	local local_position = Matrix4x4.translation(local_pose)
	local local_rotation = Matrix4x4.rotation(local_pose)
	return local_position, local_rotation
end

function ObjectBase:set_visible(flag)
	self.hidden = not flag
end

function ObjectBase:set_selectable(flag)
	self.unselectable = not flag
end

function ObjectBase:highlight_changed(component_id)
end

function ObjectBase:draw()
end

function ObjectBase:draw_highlight()
	local tm, r = self:box()
	local color = LevelEditor:object_highlight_color(self)

	if color == nil then
		return nil
	end

	LineObject.add_box(LevelEditor.lines, color, tm, r)
	return color
end

function ObjectBase:draw_snap_points()
end

function ObjectBase:draw_components()
end


--------------------------------------------------
-- ObjectBase subclass required overrides
--------------------------------------------------

function ObjectBase:box(component_id)
	assert(false, "Subclasses must implement box(component_id).")
end

function ObjectBase:local_position(component_id)
	assert(false, "Subclasses must implement local_position(component_id).")
end

function ObjectBase:set_local_position(position, component_id)
	assert(false, "Subclasses must implement set_local_position(position, component_id).")
end

function ObjectBase:local_rotation(component_id)
	assert(false, "Subclasses must implement local_rotation(component_id).")
end

function ObjectBase:set_local_rotation(rotation, component_id)
	assert(false, "Subclasses must implement set_local_rotation(rotation, component_id).")
end

function ObjectBase:local_scale(component_id)
	assert(false, "Subclasses must implement local_scale(component_id).")
end

function ObjectBase:set_local_scale(scale, component_id)
	assert(false, "Subclasses must implement set_local_scale(scale, component_id).")
end


--------------------------------------------------
-- ObjectBase optional component support overrides
--------------------------------------------------

function ObjectBase:is_root_component(component_id)
	assert(component_id == nil, "Subclasses must override for component support.")
	return true
end

function ObjectBase:world_pose(component_id)
	assert(component_id == nil, "Subclasses must override for component support.")
	return self:local_pose()
end

function ObjectBase:world_position(component_id)
	assert(component_id == nil, "Subclasses must override for component support.")
	return self:local_position()
end

function ObjectBase:set_world_position(position, component_id)
	assert(component_id == nil, "Subclasses must override for component support.")
	self:set_local_position(position)
end

function ObjectBase:world_rotation(component_id)
	assert(component_id == nil, "Subclasses must override for component support.")
	return self:local_rotation()
end

function ObjectBase:set_world_rotation(rotation, component_id)
	assert(component_id == nil, "Subclasses must override for component support.")
	return self:set_local_rotation(rotation)
end

function ObjectBase:local_pivot(component_id)
	assert(component_id == nil, "Subclasses must override for component support.")
	return self._local_pivot:unbox()
end

function ObjectBase:set_local_pivot(offset, component_id)
	assert(component_id == nil, "Subclasses must override for component support.")
	self._local_pivot:store(offset)
end


--------------------------------------------------
-- Object
--------------------------------------------------

Object = class(Object, ObjectBase)

function Object:init(id)
	ObjectBase.init(self, id)
	self._position = Vector3Box()
	self._rotation = QuaternionBox()
	self._scale = Vector3Box(1, 1, 1)
end

function Object:duplicate(spawned)
	local copy = setmetatable(ObjectBase.duplicate(self, spawned), Object)
	copy._position = Vector3Box(self:local_position())
	copy._rotation = QuaternionBox(self:local_rotation())
	copy._scale = Vector3Box(self:local_scale())
	return copy
end

function Object:local_position(component_id)
	assert(component_id == nil)
	return self._position:unbox()
end

function Object:set_local_position(position, component_id)
	assert(component_id == nil)
	self._position:store(position)
	self:_pose_changed(component_id)
end

function Object:local_rotation(component_id)
	assert(component_id == nil)
	return self._rotation:unbox()
end

function Object:set_local_rotation(rotation, component_id)
	assert(component_id == nil)
	self._rotation:store(rotation)
	self:_pose_changed(component_id)
end

function Object:local_scale(component_id)
	assert(component_id == nil)
	return self._scale:unbox()
end

function Object:set_local_scale(scale, component_id)
	assert(component_id == nil)
	self._scale:store(scale)
	self:_pose_changed(component_id)
end

function Object:_pose_changed(component_id)
end
