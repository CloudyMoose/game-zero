function boot()
	Application.set_autoload_enabled(true)
	require 'core/editor_slave/freeflight'
end

-----------------------------------------------------------------------------------------------------

BasicEditor = BasicEditor or {}

function BasicEditor:init()
	self:init_world()
	self:init_camera()
	self.t = 0
	self.loaded_level = nil
end

function BasicEditor:init_world()
	self.world = Application.new_world()
	self.gui = World.create_screen_gui(self.world, "immediate", "material", "core/editor_slave/gui/gui")
	self.viewport = Application.create_viewport(self.world, "default")
	self.shading_environment = World.create_shading_environment(self.world)
	self.lines = World.create_line_object(self.world, false)
end

function BasicEditor:init_camera()
	local camera_unit = World.spawn_unit(self.world, "core/units/camera")
	self.camera = Unit.camera(camera_unit, "camera")
	local camera_pos = Vector3(0,-10,1)
	local camera_look = Vector3(0,0,1)
	local camera_dir = Vector3.normalize(camera_look - camera_pos)
	Camera.set_local_position(self.camera, camera_unit, camera_pos)
	Camera.set_local_rotation(self.camera, camera_unit, Quaternion.look( camera_dir, Vector3(0,0,1) ) )
	self.freeflight = FreeFlight(self.camera, camera_unit)
end

function BasicEditor:shutdown()
	Application.destroy_viewport(self.world, self.viewport)
	World.destroy_shading_environment(self.world, self.shading_environment)
	Application.release_world(self.world)
end

function BasicEditor:reboot()
	self:shutdown()
	self:init_world()
	self:init_camera()
	self.loaded_level = nil
	self.t = 0
	self.id = nil
end

function BasicEditor:load_level(level)
	if level == self.loaded_level then return end
	self:reboot()
	self.loaded_level = level
	level = World.load_level(self.world, level)
	Level.spawn_background(level)
	Level.trigger_level_loaded(level)
	if Level.has_data(level, "shading_environment") then
	 	World.set_shading_environment(self.world, self.shading_environment, Level.get_data(level, "shading_environment"))
	end
end

function BasicEditor:render()
	ShadingEnvironment.blend(self.shading_environment, {"default", 1})
	ShadingEnvironment.apply(self.shading_environment)
	Application.render_world(self.world, self.camera, self.viewport, self.shading_environment)
end

function BasicEditor:update(dt)
	-- Update freeflight
	self.freeflight:update(dt)
	local space = Keyboard.button_index("space")
	if Keyboard.pressed(space) then
		Window.set_mouse_focus( not Window.mouse_focus() )
	end
	
	-- Update world
	if self.paused then dt = 0 end
	World.update(self.world, dt)
	
	LineObject.dispatch(self.world, self.lines)
	LineObject.reset(self.lines)
end

----------------------------------------------------------------------------------------

function init()
	boot()
	BasicEditor:init()
end

function shutdown()
	BasicEditor:shutdown()
end

function update(dt)
	BasicEditor:update(dt)
end

function render()
	BasicEditor:render(dt)
end

function focus()
	if Window then
		Window.set_focus()
	end
end