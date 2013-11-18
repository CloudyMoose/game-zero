local Scene = require 'lua/scene'
local Character = require 'lua/character'
local U = require 'lua/utility'

Sample.Level = class(Sample.Level, Scene)
local M = Sample.Level

function M:init(options)
	self.options = options
end

function M:start()
	Scene.start(self)

	local options = self.options

	-- Setup camera
	Camera.set_local_position(self.camera, self.camera_unit, Vector3(0,0,2))
	Camera.set_local_rotation(self.camera, self.camera_unit, Quaternion.look(Vector3(0,1,0)))

	-- Load level
	if options.level then
		local level = World.load_level(self.world, options.level)
		Level.spawn_background(level)
		Level.trigger_level_loaded(level)
		if Level.has_data(level, "shading_environment") then
			World.set_shading_environment(self.world, self.shading_environment, Level.get_data(level, "shading_environment"))
		end
	else
		World.spawn_unit(self.world, "core/editor_slave/units/skydome/skydome")
	end

	self.camera_controller = Character(self.world, self.camera, self.camera_unit)
end

function M:update(dt)
	self.camera_controller:update(dt)
	Scene.update(self, dt)

	self:help {
		items = {
			{key=U.plat("wasd", "pad1", "pad1"), text="Move"},
			{key=U.plat("space", "cross", "a"), text="Jump"},
			{key=U.plat("ctrl", "circle", "b"), text="Crouch"},
			{key=U.plat("f1", "start", "start"), text="Toggle help"}
		}
	}
	local action = self:menu {
		title = self.options.title,
		items = {
			{key="esc", text="Exit"}
		}
	}

	if action=="esc" then Sample.menu()
	elseif action=="f2" then self.debug_timpani = not self.debug_timpani update_debug(self)
	end
end

function M:render()
	ShadingEnvironment.blend(self.shading_environment, {"default", 1})
  	ShadingEnvironment.apply(self.shading_environment)
	Application.render_world(self.world, self.camera, self.viewport, self.shading_environment)
end

return M