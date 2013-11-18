--------------------------------------------------
-- Utility functions
--------------------------------------------------

local function levels_apply_recursive(visit_level, level)
	visit_level(level)
	Array.iter(Level.nested_levels(level), Func.partial(levels_apply_recursive, visit_level))
end

local function units_apply_recursive(visit_unit, level)
	local function visit_level(l)
		Array.concat(Level.units(l), Level.internal_units(l))
			 :filter(Unit.alive)
			 :iter(visit_unit)
	end
	
	levels_apply_recursive(visit_level, level)
end


--------------------------------------------------
-- LevelReference
--------------------------------------------------

LevelReference = class(LevelReference, Object)

function LevelReference:init(id, resource_name, pos, rot, scl, world)
	assert(type(id) == "string")
	assert(type(resource_name) == "string")
	assert(pos ~= nil)
	assert(rot ~= nil)
	assert(scl ~= nil)
	assert(world ~= nil)
	
	Object.init(self, id)
	self._resource_name = resource_name
	self._world = world
	self._level = World.load_level(world, resource_name, Vector3(0, 0, 0), Quaternion.identity(), Vector3(1, 1, 1), id)
	self._position:store(pos)
	self._rotation:store(rot)
	self._scale:store(scl)
	units_apply_recursive(UnitObject.immobilize_unit, self._level)
	
	local box_pose, box_radius = Level.box(self._level)
	self._box_pose = Matrix4x4Box(box_pose)
	self._box_radius = Vector3Box(Vector3.max(Vector3(0.5, 0.5, 0.5), box_radius))
	self:_pose_changed()
end

function LevelReference:box(component_id)
	assert(component_id == nil)
	local scale = self:local_scale()
	local local_box_pose = self._box_pose:unbox()
	Matrix4x4.set_translation(local_box_pose, Vector3.multiply_elements(Matrix4x4.translation(local_box_pose), scale))
	local unscaled_pose = Matrix4x4.from_quaternion_position(self:local_rotation(), self:local_position())
	local box_pose = Matrix4x4.multiply(local_box_pose, unscaled_pose)
	local box_radius = Vector3.multiply_elements(self._box_radius:unbox(), scale)
	return box_pose, box_radius
end

function LevelReference:duplicate(spawned)
	local id = Application.guid()
	local copy = LevelReference(id, self._resource_name, self:local_position(), self:local_rotation(), self:local_scale(), self._world)
	copy.hidden = self.hidden
	copy.unselectable = self.unselectable
	copy.duplication_source = self
	copy:set_local_pivot(self:local_pivot())
	LevelEditor.objects[id] = copy
	spawned[#spawned + 1] = copy
	return copy
end

function LevelReference:destroy()
	World.destroy_level(self._world, self._level)
	LevelEditor.objects[self.id] = nil
end

function LevelReference:complete_move()
	local complete_move = Func.fork(Unit.disable_physics, Unit.enable_physics, UnitObject.immobilize_unit)
	units_apply_recursive(complete_move, self._level)
end

function LevelReference:spawn_data()
	return {
		id = self.id,
		klass = "level_reference",
		resource_name = self._resource_name,
		pos = self:local_position(),
		rot = self:local_rotation(),
		scl = self:local_scale(),
		pivot = self:local_pivot()
	}
end

function LevelReference:set_visible(visible)
	if visible ~= not self.hidden then
		Object.set_visible(self, visible)
		Level.set_visibility(self._level, visible)
		
		if visible then
			units_apply_recursive(Func.fork(Unit.enable_physics, UnitObject.immobilize_unit), self._level)
		else
			units_apply_recursive(Unit.disable_physics, self._level)
		end
	end
end

function LevelReference:_pose_changed(component_id)
	assert(component_id == nil)
	Level.set_pose(self._level, self:local_pose())
end
