local Level = require 'lua/level'
local Scene = require 'lua/scene'
local U = require 'lua/utility'

Sample.Menu = class(Sample.Menu, Scene)
local M = Sample.Menu

local font = 'core/performance_hud/debug'
local font_material = 'debug'
	
function M:start()
	Scene.start(self)
	self.skydome = World.spawn_unit(self.world, "core/editor_slave/units/skydome/skydome")
end

function M:update(dt)
	Scene.update(self,dt)
	
	Sample.show_help = true
	local action = self:menu {
		title = "Bitsquid Empty Sample",
		items = {
			{key="1", text="Empty level"},
			{key="esc", text="Exit"}
		}
	}

	if action=="1" then				Sample.set_scene(Level{level="levels/empty", title = "Empty Level"})
	elseif action == "esc" then		Application.quit()
	end
end

function M:render()
	ShadingEnvironment.blend(self.shading_environment, {"default", 1})
  	ShadingEnvironment.apply(self.shading_environment)
	Application.render_world(self.world, self.camera, self.viewport, self.shading_environment)
end

return M