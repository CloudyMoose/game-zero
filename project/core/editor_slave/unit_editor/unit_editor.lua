require "core/editor_slave/editor_camera"
require "core/editor_slave/unit_editor/select_tool"

UnitEditor = UnitEditor or {}
EditorApi = UnitEditor

function UnitEditor:init()
	self._modifiers = {
		shift = false,
		control = false,
		camera = false
	}
	
	self._mouse = {
		over = false,
		pos = { x = 0, y = 0 },
		delta = { x = 0, y = 0 },
		down = { x = 0, y = 0 },
		wheel = { delta = 0, steps = 0 },
		buttons = { left = false, right = false, middle = false, thumb = false }
	}

	self._windows = {}
	self._tool = SelectTool()
	self:_init_world()
end

function UnitEditor:shutdown()
	self:_shutdown_world()

	for _, window in pairs(self._windows) do
		Window.close(window)
	end

	self._windows = {}
end

function UnitEditor:load_level(resource_name)
	self:_shutdown_world()
	self:_init_world()
	local level = World.load_level(self._world, resource_name)
	Level.spawn_background(level)
	Level.trigger_level_loaded(level)

	if Level.has_data(level, "shading_environment") then
	 	World.set_shading_environment(self._world, self._shading_environment, Level.get_data(level, "shading_environment"))
	end
end

function UnitEditor:render()
	ShadingEnvironment.blend(self._shading_environment, { "default", 1 })
	ShadingEnvironment.apply(self._shading_environment)
	local did_render_to_any_window = false

	for _, window in pairs(self._windows) do
		Application.render_world(self._world, self._camera, self._viewport, self._shading_environment, window)
		did_render_to_any_window = true
	end

	if not did_render_to_any_window then
		Application.render_world(self._world, self._camera, self._viewport, self._shading_environment)
	end
end

function UnitEditor:update(dt)
	if self._is_quitting then
		Application.quit()
		return
	end

	local mouse = self._mouse
	local editor_camera = self._editor_camera
	editor_camera:update(dt, mouse.pos, mouse.delta)

	if Application.platform() == "win32" then
		local camera_is_controlled_by_mouse = editor_camera:is_controlled_by_mouse() or nil

		if not camera_is_controlled_by_mouse then
			if (mouse.delta.x ~= 0 or mouse.delta.y ~= 0) and not editor_camera:is_animating() then
				local a, b, c = Script.temp_count()
				self._tool:mouse_move(mouse.pos.x, mouse.pos.y)
				Script.set_temp_count(a, b, c)
			end
		end

		if mouse.wheel.delta ~= 0 and mouse.wheel.steps ~= 0 then
			if camera_is_controlled_by_mouse or self._modifiers.camera or self._tool.mouse_wheel == nil then
				editor_camera:mouse_wheel(mouse.wheel.delta, mouse.wheel.steps)
			else
				self._tool:mouse_wheel(mouse.wheel.delta, mouse.wheel.steps)
			end			
		end
	end

	mouse.delta.x = 0
	mouse.delta.y = 0
	mouse.wheel.delta = 0
	mouse.wheel.steps = 0
	
	self._tool:update(dt)
	World.update(self._world, dt)
	LineObject.dispatch(self._world, self._lines)
	LineObject.reset(self._lines)
end

function UnitEditor:_init_world()
	self._world = Application.new_world()
	self._world_gui = World.create_world_gui(self._world, Matrix4x4.identity(), 1, 1, "immediate", "material", "core/editor_slave/gui/gui")
	self._screen_gui = World.create_screen_gui(self._world, "immediate", "material", "core/editor_slave/gui/gui")
	self._lines = World.create_line_object(self._world, false)
	self._viewport = Application.create_viewport(self._world, "default")
	self._shading_environment = World.create_shading_environment(self._world)
	local camera_unit = World.spawn_unit(self._world, "core/units/camera")
	self._camera = Unit.camera(camera_unit, "camera")
	self._editor_camera = EditorCamera(self._camera, camera_unit)
end

function UnitEditor:_shutdown_world()
	Application.destroy_viewport(self._world, self._viewport)
	World.destroy_gui(self._world, self._world_gui)
	World.destroy_gui(self._world, self._screen_gui)
	World.destroy_line_object(self._world, self._lines) 
	World.destroy_shading_environment(self._world, self._shading_environment)
	Application.release_world(self._world)
	self._world = nil
	self._world_gui = nil
	self._screen_gui = nil
	self._lines = nil
	self._viewport = nil
	self._shading_environment = nil
	self._camera = nil
	self._editor_camera = nil
end

-----------------------------------------------------------------------------------------------

function EditorApi:start()
	self:load_level("core/editor_slave/levels/animation_preview_level/animation_preview_level")
end

function EditorApi:quit()
	self._is_quitting = true
end

function EditorApi:attach_renderer(parent_control_handle)
	assert(self._windows[parent_control_handle] == nil)
	local window = Window.open{ parent = parent_control_handle }
	self._windows[parent_control_handle] = window
end

function EditorApi:detach_renderer(parent_control_handle)
	local window = self._windows[parent_control_handle]
	assert(window ~= nil)
	Window.close(window)
	self._windows[parent_control_handle] = nil
end
