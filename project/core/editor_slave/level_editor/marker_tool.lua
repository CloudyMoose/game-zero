Marker = class(Marker, Object)

function Marker:init()
	Object.init(self)
	self.name = ""
end

function Marker:duplicate(spawned)
	local copy = setmetatable(Object.duplicate(self, spawned), Marker)
	copy.name = self.name
	return copy
end

function Marker:spawn_data()
	local sd = Object.spawn_data(self)
	sd.klass = "marker"
	sd.name = self.name
	return sd
end

function Marker:box(component_id)
	assert(component_id == nil)
	local unscaled_pose = Matrix4x4.from_quaternion_position(self:local_rotation(), self:local_position() + Vector3(0, 0, 0.5))
	local scaled_radius = self:local_scale() * 0.5
	return unscaled_pose, scaled_radius
end

function Marker:draw()
	if not self.hidden then
		local gui = LevelEditor.world_gui
		local tm, r = self:box()
		Matrix4x4.set_scale(tm, self:local_scale())
		local font, material = "core/editor_slave/gui/arial", "arial"
		Gui.text_3d(gui, "M", font, 1, material, tm, Vector3(-0.35,-0.35,0), 0, Color(255,255,255))
		Gui.text_3d(gui, self.name, font, 0.3, material, tm, Vector3(0.35,-0.45,0), 0, Color(255,255,255))
	end
end

MarkerTool = class(MarkerTool, Tool)

function MarkerTool:mouse_spawn(x, y)
	local m = Marker()
	m:set_local_position(LevelEditor:find_spawn_point(x, y))
	LevelEditor.objects[m.id] = m
	LevelEditor:spawned({m})
	
	LevelEditor.selection:clear()
	LevelEditor.selection:add(m.id)
	LevelEditor.selection:send()
end

function MarkerTool:update()
	LevelEditor.move_tool:update()
end

function MarkerTool:mouse_down(x,y)
	LevelEditor.move_tool:mouse_down(x,y)
end

function MarkerTool:mouse_move(x,y)
	LevelEditor.move_tool:mouse_move(x,y)
end

function MarkerTool:mouse_up(x,y)
	LevelEditor.move_tool:mouse_up(x,y)
end
