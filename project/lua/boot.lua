-- Project namespace
Sample = Sample or {}

require 'lua/class'
require 'lua/flow_callbacks'
local Menu = require 'lua/menu'
local Level = require 'lua/level'

function Sample.set_scene(scene)
	if Sample.scene then
		Sample.scene:shutdown()
	end
	Sample.scene = scene
	if Sample.scene then
		Sample.scene:start()
	end
end

function Sample.menu()
	Sample.set_scene(Menu())
end

function init()
	if Window then
		Window.set_focus()
		Window.set_mouse_focus(true)
	end

	if LEVEL_EDITOR_TEST then
		Application.autoload_resource_package("__level_editor_test")
		Sample.set_scene(Level {level = "__level_editor_test"})
		
		-- Copy camera data from application (set by level editor) if any
		-- if Application.has_data("camera") then
		--	Camera.set_local_pose(self.camera, self.camera_unit, Application.get_data("camera"))
		--end
	else
		Sample.show_help = true
		Sample.menu()
	end
end

function shutdown()
	if Sample.scene then
		Sample.scene:shutdown()
	end
end

function update(dt)
	if Keyboard.pressed(Keyboard.button_index('f5')) then
		LEVEL_EDITOR_EXIT_TEST = true
	end

	if LEVEL_EDITOR_TEST and LEVEL_EDITOR_EXIT_TEST then
		-- Application.set_data('camera', Camera.local_pose(game.camera, game.camera_unit))
		Application.console_send { type = 'stop_testing' }
	end

	if Sample.scene then
		Sample.scene:update(dt)
	end
end

function render()
	if Sample.scene then
		Sample.scene:render()
	end
end