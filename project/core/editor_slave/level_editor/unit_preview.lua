UnitPreview = class(UnitPreview)

function UnitPreview:init(handle)
	self.t = 0
	if handle then
		self.window = Window.open {parent = handle}
	end
	
	self.world = Application.new_world()
	-- Cannot be used, because there is a crash with swept collisions against planes in PhysX.
	-- self.plane = self.world:physics_world():spawn_plane( Vector3(0,0,-10), Vector3(0,0,1), "static", "default", "default" )
	self.plane = self.world:physics_world():spawn_box( Vector3(0,0,-10), Vector3(100,100,1) )
	
	World.set_flow_enabled(self.world, false)
	self.viewport = Application.create_viewport(self.world, "default")
	self.shading_environment = World.create_shading_environment(self.world)
	self.camera_unit = World.spawn_unit(self.world, "core/units/camera")
	self.camera = Unit.camera(self.camera_unit, "camera")
	
	self.skydome_unit = World.spawn_unit(self.world, "core/editor_slave/units/skydome/skydome")
end

function UnitPreview:close()
	Application.destroy_viewport(self.world, self.viewport)
	World.destroy_shading_environment(self.world, self.shading_environment)
	Application.release_world(self.world)
	if self.window then
		Window.close(self.window)
	end
end

function UnitPreview:set_skydome_unit(unit)
	if self.skydome_unit then
		World.destroy_unit(self.world, self.skydome_unit)
		self.skydome_unit = nil
	end
	if unit ~= "" then
		self.skydome_unit = World.spawn_unit(self.world, unit)
	end
end

function UnitPreview:set_shading_environment(shading_environment)
	if shading_environment ~= "" then
		World.set_shading_environment(self.world, self.shading_environment, shading_environment)
	end
end

function UnitPreview:update(dt)
	self.t = math.fmod(self.t + dt, math.pi * 2)

	local tm, radius

	if self.unit ~= nil then
		tm, radius = Unit.box(self.unit)
	else
		tm = Matrix4x4.identity()
		radius = Vector3(1, 1, 1)
	end

	local r = Vector3.length(radius)
	local r = r * 2
	if r < 1 then r = 1 end
	if r > 50 then r = 50 end
	
	local a = self.t
	local x = -r*math.sin(a)
	local y = -r*math.cos(a)
	local z = r/2
	
	local camera_pos = Matrix4x4.translation(tm) + Vector3(x,y,z)
	local camera_look = Matrix4x4.translation(tm)
	local camera_dir = Vector3.normalize(camera_look - camera_pos)
	Camera.set_local_position(self.camera, self.camera_unit, camera_pos)
	Camera.set_local_rotation(self.camera, self.camera_unit, Quaternion.look( camera_dir, Vector3(0,0,1) ) )

	World.update(self.world, dt)
end

function UnitPreview:render()
	ShadingEnvironment.blend(self.shading_environment, {"default", 1})
	ShadingEnvironment.apply(self.shading_environment)
	if self.window then
		Application.render_world(self.world, self.camera, self.viewport, self.shading_environment, self.window)
	else
		Application.render_world(self.world, self.camera, self.viewport, self.shading_environment)
	end
end

function UnitPreview:preview_unit(unit, material)
	self:unspawn()
	self.unit_type = unit
	self.unit_material = material
	self.effect_type = nil
	self.unit = material == nil
		and World.spawn_unit(self.world, unit)
		or World.spawn_unit(self.world, unit, Vector3(0, 0, 0), Quaternion.identity(), material)

	-- Dummy ID, BakedLighting requires an ID to be set. 
	Unit.set_id(self.unit, 1)
	BakedLighting.add_unit(self.world, self.unit)
end

function UnitPreview:preview_particle_effect(effect)
	self:unspawn()
	self.unit_type = nil
	self.unit_material = nil
	self.effect_type = effect
	self.effect_id = World.create_particles(self.world, effect, Vector3(0, 0, 0), Quaternion.identity())
end

function UnitPreview:preview_sound(sound)
	self:preview_unit("core/editor_slave/units/sound_source_icon/sound_source_icon", nil)
end

function UnitPreview:unspawn()
	if self.unit ~= nil then
		World.destroy_unit(self.world, self.unit)
		self.unit = nil
	end

	if self.effect_id ~= nil then
		World.destroy_particles(self.world, self.effect_id)
		self.effect_id = nil
	end
end

function UnitPreview:respawn()
	self:unspawn()

	if self.unit_type then
		self:preview_unit(self.unit_type, self.unit_material)
	elseif self.effect_type then
		self:preview_particle_effect(self.effect_type)
	end
end

function UnitPreview:set_option(option, value)
	if option == "show_physics" then
		self.world:physics_world():set_debug_draw(value)
	end
end