--------------------------------------------------
-- Sound
--------------------------------------------------

Sound = class(Sound, ObjectBase)

local unit = "core/editor_slave/units/sound_source_icon/sound_source_icon"
local text_size = 0.3

function Sound:init()
	ObjectBase.init(self)
	self.event = ""
	self.name = ""
	self.shape = "sphere"
	self.shape_radius = Vector3Box(0, 0, 0)
	self.range = 10
	self._unit = World.spawn_unit(LevelEditor.world, unit)
end

function Sound:destroy()
	if self._unit then
		World.destroy_unit(LevelEditor.world, self._unit)
		self._unit = nil
	end

	ObjectBase.destroy(self)
end

function Sound:box()
	return UnitObject.unscaled_box(self._unit)
end

function Sound:local_pose(component_id)
	assert(component_id == nil)
	return Unit.local_pose(self._unit, 0)
end

function Sound:world_pose(component_id)
	assert(component_id == nil)
	return Unit.world_pose(self._unit, 0)
end

function Sound:local_position(component_id)
	assert(component_id == nil)
	return Unit.local_position(self._unit, 0)
end

function Sound:set_local_position(position, component_id)
	assert(component_id == nil)
	Unit.set_local_position(self._unit, 0, position)
end

function Sound:world_position(component_id)
	assert(component_id == nil)
	return Unit.world_position(self._unit, 0)
end

function Sound:set_world_position(position, component_id)
	assert(component_id == nil)
	Unit.set_local_position(self._unit, 0, position)
end

function Sound:local_rotation(component_id)
	assert(component_id == nil)
	return Unit.local_rotation(self._unit, 0)
end

function Sound:set_local_rotation(rotation, component_id)
	assert(component_id == nil)
	Unit.set_local_rotation(self._unit, 0, rotation)
end

function Sound:local_scale(component_id)
	assert(component_id == nil)
	return Unit.local_scale(self._unit, 0)
end

function Sound:set_local_scale(scale, component_id)
	assert(component_id == nil)
	Unit.set_local_scale(self._unit, 0, scale)
end

function Sound:duplicate(spawned)
	local copy = setmetatable(ObjectBase.duplicate(self, spawned), Sound)
	copy.event = self.event
	copy.name = self.name
	copy.shape = self.shape
	copy.shape_radius = Vector3Box(self.shape_radius:unbox())
	copy.range = self.range
	copy._unit = World.spawn_unit(LevelEditor.world, unit, self:local_position(), self:local_rotation())
	copy:set_local_scale(self:local_scale())
	return copy
end

function Sound:spawn_data()
	local sd = ObjectBase.spawn_data(self)
	sd.klass = "sound"
	sd.event = self.event
	sd.name = self.name
	sd.radius = self.shape_radius:unbox()
	return sd
end

function Sound:draw_event()
	local gui = LevelEditor.world_gui
	local tm = self:local_pose()
	local scale = self:local_scale()

	local text_tm = Matrix4x4.identity()
	Matrix4x4.set_x(text_tm, -Matrix4x4.x(tm))
	Matrix4x4.set_y(text_tm, -Matrix4x4.y(tm))
	Matrix4x4.set_z(text_tm, Matrix4x4.z(tm))
	Matrix4x4.set_translation(text_tm, Matrix4x4.translation(tm) - Vector3(0, 0, 0.7 * scale.z))
	
	local text = self.event
	local font, material = "core/editor_slave/gui/arial", "arial"

	if self:_is_close() then
		font, material = "core/editor_slave/gui/arial_df", "arial_df"
	end

	local min, max = Gui.text_extents(LevelEditor.world_gui, text, font, text_size)
	local p = Vector3(-max.x / 2, 0, 0)
	Gui.text_3d(gui, text, font, text_size, material, text_tm, p, 0, Color(255, 255, 255))
end

function Sound:draw_shape(inner_color)
	local tm = self:box()
	local r = self.shape_radius:unbox()
	local outer_color = Blend.color_with_alpha(inner_color, 128)

	if self.shape == "sphere" then
		local c = r.x
		if r.y < c then c = r.y end
		if r.z < c then c = r.z end
		LineObject.add_sphere(LevelEditor.lines, inner_color, Matrix4x4.translation(tm), c)
		LineObject.add_sphere(LevelEditor.lines, outer_color, Matrix4x4.translation(tm), c + self.range)
	elseif self.shape == "box" then
		LineObject.add_box(LevelEditor.lines, inner_color, tm, r)
		LineObject.add_box(LevelEditor.lines, outer_color, tm, r + Vector3(self.range, self.range, self.range))
	end
end

function Sound:draw_highlight()
	local color = ObjectBase.draw_highlight(self)

	if color ~= nil then
		self:draw_shape(color)
		self:draw_event()
	end
end

function Sound:set_visible(visible)
	ObjectBase.set_visible(self, visible)
	Unit.set_unit_visibility(self._unit, visible)
end

function Sound:radius()
	local r = self.shape_radius:unbox()
	if 0.5 > r.x then r.x = 0.5 end
	if 0.5 > r.y then r.y = 0.5 end
	if 0.5 > r.z then r.z = 0.5 end
	return r
end

function Sound:set_radius(r)
	self.shape_radius:store(r)
end

function Sound:_is_close()
	local camera_position = Camera.local_position(LevelEditor.camera)
	local distance_to_camera = Vector3.distance(camera_position, self:local_position())
	return distance_to_camera > 0.00001 and text_size / distance_to_camera > 0.03
end
