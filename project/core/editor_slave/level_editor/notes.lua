local function split(text, sep)
	sep = sep or "\n"
	local lines = {}
	local pos = 1

	while true do
		local b,e = text:find(sep, pos)
		if not b then table.insert(lines, text:sub(pos)) break end
		table.insert(lines, text:sub(pos, b-1))
		pos = e + 1
	end
	
	return lines
end

Note = class(Note, Object)

function Note:init()
	Object.init(self)
	self.text = "New note"
	self.color = QuaternionBox(Color(255, 255, 255))
	self.size = 0.5
end

function Note:duplicate(spawned)
	local copy = setmetatable(Object.duplicate(self, spawned), Note)
	copy.text = self.text
	copy.color = QuaternionBox(self.color:unbox())
	copy.size = self.size
	return copy
end

function Note:spawn_data()
	local sd = Object.spawn_data(self)
	sd.klass = "note"
	sd.text = self.text
	sd.color = self.color:unbox()
	sd.size = self.size
	return sd
end

function Note:is_close()
	local distance = Vector3.distance(Camera.local_position(LevelEditor.camera), self:local_position())
	return self.size * self:local_scale().x / distance > 0.03
end

function Note:box(component_id)
	assert(component_id == nil)
	local min, max = Vector3(0, 0, 0), Vector3(0, 0, 0)
	local font = "core/editor_slave/gui/arial"
	
	if self:is_close() then
		font = "core/editor_slave/gui/arial_df"
	end

	local lines = split(self.text)
	local y = 0

	for _, line in ipairs(lines) do
		local lmin, lmax = Gui.text_extents(LevelEditor.world_gui, line, font, self.size)
		Vector3.set_z(lmin, lmin.z + y)
		Vector3.set_z(lmax, lmax.z + y)
		min = Vector3.min(min, lmin)
		max = Vector3.max(max, lmax)
		y = y - self.size
	end

	local scale = self:local_scale()
	min = Vector3.multiply_elements(min, scale)
	max = Vector3.multiply_elements(max, scale)
	local scaled_radius = (max - min) / 2
	local scaled_offset = -(max + min) / 2
	local unscaled_pose = Matrix4x4.from_quaternion_position(self:local_rotation(), self:local_position())
	return unscaled_pose, scaled_radius, scaled_offset
end

function Note:draw()
	local gui = LevelEditor.world_gui
	local tm, r, o = self:box()
	o = Matrix4x4.transform_without_translation(tm, o)
	Matrix4x4.set_translation(tm, Matrix4x4.translation(tm) + o)
	Matrix4x4.set_scale(tm, self:local_scale())
	
	local font, material = "core/editor_slave/gui/arial", "arial"
	
	if self:is_close() then
		font, material = "core/editor_slave/gui/arial_df", "arial_df"
	end

	local lines = split(self.text)
	local y = 0

	for _,line in ipairs(lines) do
		Gui.text_3d(gui, line, font, self.size, material, tm, Vector3(0, y, 0), 0, self.color:unbox())
		y = y - self.size
	end
end

NoteTool = class(NoteTool, Tool)

function NoteTool:mouse_spawn(x, y)
	local n = Note()
	n:set_local_position(LevelEditor:find_spawn_point(x, y))
	LevelEditor.objects[n.id] = n
	LevelEditor:spawned({n})
	
	LevelEditor.selection:clear()
	LevelEditor.selection:add(n.id)
	LevelEditor.selection:send()
end

function NoteTool:update()
	LevelEditor.move_tool:update()
end

function NoteTool:mouse_down(x, y)
	LevelEditor.move_tool:mouse_down(x, y)
end

function NoteTool:mouse_move(x, y)
	LevelEditor.move_tool:mouse_move(x, y)
end

function NoteTool:mouse_up(x, y)
	LevelEditor.move_tool:mouse_up(x, y)
end
