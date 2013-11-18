ParticleEffect = class(ParticleEffect, Object)

local text_size = 0.5

function ParticleEffect:init()
	Object.init(self)
	self.effect = ""
	self.name = ""
	self.drawn_effect = nil
	self.drawn_tm = Matrix4x4Box()
end

function ParticleEffect:redraw(tm)
	if self.effect_id then 
		World.destroy_particles(LevelEditor.world, self.effect_id)
		self.effect_id = nil
	end

	if Application.can_get("particles", self.effect) then
		local position = self:local_position()
		local rotation = self:local_rotation()
		local scale = self:local_scale()
		self.effect_id = World.create_particles(LevelEditor.world, self.effect, position, rotation, scale)
	end

	self.drawn_effect = self.effect
	self.drawn_tm:store(tm)
end

function ParticleEffect:destroy()
	if self.effect_id then
		World.destroy_particles(LevelEditor.world, self.effect_id)
		self.effect_id = nil
	end

	Object.destroy(self)
end

function ParticleEffect:hide()
	if self.effect_id then
		World.destroy_particles(LevelEditor.world, self.effect_id)
		self.effect_id = nil
	end

	self.drawn_effect = nil
end

function ParticleEffect:box(component_id)
	assert(component_id == nil)
	local unscaled_pose = Matrix4x4.from_quaternion_position(self:local_rotation(), self:local_position())
	local scaled_radius = self:local_scale() * 0.5
	return unscaled_pose, scaled_radius
end

function ParticleEffect:duplicate(spawned)
	local copy = setmetatable(Object.duplicate(self, spawned), ParticleEffect)
	copy.effect = self.effect
	copy.name = self.name
	copy.drawn_tm = Matrix4x4Box(self.drawn_tm:unbox())
	return copy
end

function ParticleEffect:spawn_data()
	local sd = Object.spawn_data(self)
	sd.klass = "particle_effect"
	sd.effect = self.effect
	sd.name = self.name
	return sd
end

function ParticleEffect:draw()
	local gui = LevelEditor.world_gui
	local tm, r = self:box()
	
	local text = self.effect
	local font, material = "core/editor_slave/gui/arial", "arial"

	if self:_is_close() then
		font, material = "core/editor_slave/gui/arial_df", "arial_df"
	end

	local min, max = Gui.text_extents(LevelEditor.world_gui, text, font, text_size)
	local p = Vector3(-max.x / 2, 0, 0)
	Gui.text_3d(gui, text, font, text_size, material, tm, p, 0, Color(255, 255, 255))
	
	local scaled_tm = Matrix4x4.copy(tm)
	Matrix4x4.set_scale(scaled_tm, self:local_scale())

	if self.drawn_effect ~= self.effect or not Matrix4x4.equal(self.drawn_tm:unbox(), scaled_tm) then
		self:redraw(scaled_tm)
	end
end

function ParticleEffect:set_visible(visible)
	Object.set_visible(self, visible)

	if not visible and self.effect_id then
		self:hide()
	end
end

function ParticleEffect:_is_close()
	local camera_position = Camera.local_position(LevelEditor.camera)
	local distance_to_camera = Vector3.distance(camera_position, self:local_position())
	return distance_to_camera > 0.00001 and text_size / distance_to_camera > 0.03
end
