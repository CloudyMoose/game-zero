Spline = class(Spline, Object)

function Spline:init()
	Object.init(self)
	self.name = ""
	self.points = {}
	self.color = QuaternionBox(Color(255, 255, 255))
end

function Spline:duplicate(spawned)
	local copy = setmetatable(Object.duplicate(self, spawned), Spline)
	copy.name = self.name
	copy.points = {}

	for i, p in ipairs(self.points) do
		copy.points[i] = Vector3Boxed(self.points[i])
	end

	copy.color = QuaternionBox(self.color:unbox())
	return copy
end

function Spline:spawn_data()
	local sd = Object.spawn_data(self)
	sd.klass = "spline"
	sd.name = self.name
	sd.points = {}
	for i,p in ipairs(self.points) do
		sd.points[i] = self.points[i]:unbox()
	end
	sd.color = self.color:unbox()
	return sd
end

function Spline:draw()
	local tm = self:local_pose()
	
	local offset = Vector3(0,0,0.01)
	
	local points = {}
	for i=1,#self.points do
		points[i] = Matrix4x4.transform(tm, self.points[i]:unbox())
	end
	
	if LevelEditor.selection:includes(self.id) then
		local gui = LevelEditor.world_gui
		local font, material = "core/editor_slave/gui/arial", "arial"
		local w,h = Application.resolution()
		local cam,dir = LevelEditor:camera_ray(w/2,h/2)
		local z = Vector3(0,0,1)
		local y = Vector3.normalize(Vector3(dir.x, dir.y, 0))
		local x = Vector3.cross(y,z)
		for i=1, #points, 3 do
			local tm = Matrix4x4.from_axes(x, y, z, points[i])
			local lmin, lmax = Gui.text_extents(gui, (i-1)/3+1, font, 0.5)
			Gui.text_3d(gui, (i-1)/3+1, font, 0.5, material, tm, Vector3(-(lmin.x + lmax.x)/2,0.6,0), 0, Color(0,0,0))
			LineObject.add_sphere(LevelEditor.lines, Color(0,0,0), points[i], 0.5)
			if i+1 <= #points then
				LineObject.add_sphere(LevelEditor.lines, Color(255,255,255), points[i+1], 0.2)
				LineObject.add_sphere(LevelEditor.lines, Color(255,255,255), points[i+2], 0.2)
			end
		end
	end
	
	local color = self.color:unbox()
	
	for i=1, #points-3, 3 do
		local A = points[i]
		local A_c = points[i+1]
		local B_c = points[i+2]
		local B = points[i+3]
		
		local plast = nil
		for t = 0,1.025,0.05 do
			local s = 1-t
			local p = s*s*s*A + 3*s*s*t*A_c + 3*s*t*t*B_c + t*t*t*B + offset
			if plast then
				LineObject.add_line(LevelEditor.lines, color, plast,p)
			end
			plast = p
		end
	end
end

function Spline:box()
	local min, max = Vector3(0,0,0), Vector3(0,0,0)
	for i, p in ipairs(self.points) do
		min = Vector3.min(min, p:unbox())
		max = Vector3.max(max, p:unbox())
	end
	
	local scale = self:local_scale()
	min = Vector3.multiply_elements(min, scale)
	max = Vector3.multiply_elements(max, scale)
	local scaled_radius = (max - min) / 2
	local scaled_offset = (max + min) / 2
	local unscaled_pose = Matrix4x4.from_quaternion_position(self:local_rotation(), self:local_position())
	Matrix4x4.set_translation(unscaled_pose, Matrix4x4.transform(unscaled_pose, scaled_offset))
	return unscaled_pose, scaled_radius, scaled_offset
end

function Spline:select_point(x,y, only_handles)
	local cam,dir = LevelEditor:camera_ray(x,y)
	
	local min = 1000000
	local best = nil
	
	for i,gp in ipairs(self.points) do
		local p = self:to_global(gp:unbox())
		local r = 0.2
		if i%3==1 then
			if only_handles then r=0 else r=0.5 end
		end
		local c = Math.ray_box_intersection(cam,dir,Matrix4x4.from_translation(p), Vector3(r,r,r))
		if c > 0 and c < min then
			best = i
			min = c
		end
	end
	
	if best then return best end
	
	-- Create new points?
	local best_t = nil
	for i=1, #self.points-3, 3 do
		local A = self.points[i]:unbox()
		local A_c = self.points[i+1]:unbox()
		local B_c = self.points[i+2]:unbox()
		local B = self.points[i+3]:unbox()
		
		local r = 0.5
		local len = Vector3.distance(A, A_c) + Vector3.distance(A_c, B_c) + Vector3.distance(B_c, B)
		local step = 2*r / math.ceil(len)
		
		for t = 0,1+step/2,step do
			local s = 1-t
			local p = self:to_global(s*s*s*A + 3*s*s*t*A_c + 3*s*t*t*B_c + t*t*t*B)
			local c = Math.ray_box_intersection(cam,dir,Matrix4x4.from_translation(p), Vector3(r,r,r))
			if c > 0 and c < min then
				best = i
				best_t = t
				min = c
			end
		end
	end
	
	if best then
		-- Use de Casteljau to split in a new control point
		local i = best
		local t = best_t
		
		local p_1 = self.points[i]:unbox()
		local p_2 = self.points[i+1]:unbox()
		local p_3 = self.points[i+2]:unbox()
		local p_4 = self.points[i+3]:unbox()
		
		p_12 = Vector3.lerp(p_1, p_2, t)
		p_23 = Vector3.lerp(p_2, p_3, t)
		p_34 = Vector3.lerp(p_3, p_4, t)
		p_123 = Vector3.lerp(p_12, p_23, t)
		p_234 = Vector3.lerp(p_23, p_34, t)
		p_1234 = Vector3.lerp(p_123, p_234, t)
		
		self.points[i+1]:box(p_12)
		self.points[i+2]:box(p_123)
		table.insert( self.points, i+3, Vector3Boxed(p_1234))
		table.insert( self.points, i+4, Vector3Boxed(p_234))
		table.insert( self.points, i+5, Vector3Boxed(p_34))
		
		LevelEditor:modified({self})
		
		best = i+3
	end
	
	return best	
end

SplineTool = class(SplineTool, Tool)

function SplineTool:init()
	self.move_gizmo = MoveGizmo()
end

function SplineTool:mouse_spawn(x, y)
	if self.mode == "creating" then
		self:mouse_down(x,y)
		self:finish_creating()
		return
	end

	if self.mode then return end

	local n = Spline()
	local spawn_point = LevelEditor:find_spawn_point(x, y)
	n:set_local_position(spawn_point)
	LevelEditor.objects[n.id] = n
	LevelEditor:spawned({n})
	
	LevelEditor.selection:clear()
	LevelEditor.selection:add(n.id)
	LevelEditor.selection:send()
	
	self.mode = "creating"
	self.spline = n.id
	self.points = {Vector3Boxed(n:to_local(spawn_point))}
	self.drag_point = nil
end

function SplineTool:update()
	if self.mode == "creating/curving" then
		local spline = LevelEditor.objects[self.spline]
		local p = spline:to_global(self.points[#self.points-1]:unbox())
		local q = spline:to_global(self.points[#self.points]:unbox())
		LineObject.add_line(LevelEditor.lines, Color(0,0,255), p,2*q-p)
	elseif self.spline and LevelEditor.objects[self.spline] and self.drag_point then
		local spline = LevelEditor.objects[self.spline]
		local i0 = self.drag_point
		while i0%3 ~= 0 do i0 = i0 - 1 end
		local i1 = i0 + 1
		local i2 = i0 + 2
		if i0<1 then i0 = 1 end
		if i1>#spline.points then i1 = #spline.points end
		if i2>#spline.points then i2 = #spline.points end
		local p0 = spline:to_global(spline.points[i0]:unbox())
		local p1 = spline:to_global(spline.points[i1]:unbox())
		local p2 = spline:to_global(spline.points[i2]:unbox())
		LineObject.add_line(LevelEditor.lines, Color(0,0,255), p0, p1)
		LineObject.add_line(LevelEditor.lines, Color(0,0,255), p1, p2)
		self.move_gizmo:draw(LevelEditor.world_gui, LevelEditor.lines_noz, LevelEditor.editor_camera, true)
	else
		LevelEditor.move_tool:update()
	end
end

function SplineTool:mouse_down(x, y)
	if self.mode == "creating" then
		local spline = LevelEditor.objects[self.spline]
		local spawn_point = LevelEditor:find_spawn_point(x, y)
		local where = spline:to_local(spawn_point)
		local t = self.points
		if #t == 1 then
			t[#t+1] = Vector3Boxed(t[#t].x, t[#t].y, t[#t].z)
		else
			local p = 2*t[#t]:unbox() - t[#t-1]:unbox()
			t[#t+1] = Vector3Boxed(p.x,p.y,p.z)
		end
		t[#t+1] = Vector3Boxed(where.x, where.y, where.z)
		t[#t+1] = Vector3Boxed(where.x, where.y, where.z)
		
		spline.points = self.points
		self.mode = "creating/curving"
	else
		if self.drag_point and self.move_gizmo:is_axes_selected() then
			self.mode = "drag_point"
			self.move_gizmo:start_move(LevelEditor.editor_camera, x, y)
		elseif LevelEditor.selection:count() == 1 and kind_of(LevelEditor.selection:objects()[1]) == Spline then
			local spline = LevelEditor.selection:objects()[1]
			self.spline = spline.id
			self.drag_point = spline:select_point(x, y, LevelEditor.modifiers.shift)
			if self.drag_point then
				self.mode = "drag_point"
				self.move_gizmo:set_selected_axes("xy")
				self.move_gizmo:set_position(spline:to_global(spline.points[self.drag_point]:unbox()))
				self.move_gizmo:start_move(LevelEditor.editor_camera, x, y)
			else
				LevelEditor.move_tool:mouse_down(x,y)
			end
		else
			LevelEditor.move_tool:mouse_down(x,y)
		end
	end
end

function SplineTool:mouse_move(x, y)
	LevelEditor.move_tool:mouse_move(x, y)
	if self.mode == "creating" then
		local spline = LevelEditor.objects[self.spline]
		local spawn_point = LevelEditor:find_spawn_point(x, y)
		local where = spline:to_local(spawn_point)
		local t = {}
		for i,p in pairs(self.points) do t[i] = p end
		if #t == 1 then
			t[#t+1] = Vector3Boxed(t[#t].x, t[#t].y, t[#t].z)
		else
			local p = 2*t[#t]:unbox() - t[#t-1]:unbox()
			t[#t+1] = Vector3Boxed(p.x,p.y,p.z)
		end
		t[#t+1] = Vector3Boxed(where.x, where.y, where.z)
		t[#t+1] = t[#t]
		
		spline.points = t
	elseif self.mode == "creating/curving" then
		local spline = LevelEditor.objects[self.spline]
		local cam, dir = LevelEditor:camera_ray(x,y)
		local q = spline:to_global(self.points[#self.points]:unbox())
		local t = (q.z - cam.z) / dir.z
		local p = cam + dir*t
		
		self.points[#self.points-1]:box(spline:to_local(2*q-p))
		
		spline.points = self.points
	elseif self.mode == "drag_point" then
		local spline = LevelEditor.objects[self.spline]
		local snap_func = nil
		local i = self.drag_point
		if i % 3 == 1 and not LevelEditor.modifiers.control then snap_func = Func.partial(GridPlane.snap_offset, spline:local_pose()) end
		self.move_gizmo:delta_move(LevelEditor.editor_camera, x, y, snap_func)
		local p = self.move_gizmo:position()
		local delta = spline:to_local(p) - spline.points[i]:unbox()
		spline.points[i]:box( spline:to_local( p ) )
		local solo_drag = LevelEditor.modifiers.shift
		if i%3 == 1 then
			if i-1 >=1 then spline.points[i-1]:box( spline.points[i-1]:unbox() + delta) end
			if i+1<=#spline.points then spline.points[i+1]:box( spline.points[i+1]:unbox() + delta) end
		elseif i%3 == 2 then
			if i-2>=1 and not solo_drag then spline.points[i-2]:box( 2*spline.points[i-1]:unbox() - spline.points[i]:unbox() ) end
		elseif i%3 == 0 then
			if i+2<=#spline.points and not solo_drag then spline.points[i+2]:box( 2*spline.points[i+1]:unbox() - spline.points[i]:unbox() ) end
		end
	elseif self.drag_point then
		self.move_gizmo:select_axes(LevelEditor.editor_camera, x, y, true)
	end
end

function SplineTool:mouse_up(x, y)
	if self.mode == "creating/curving" then
		self.mode = "creating"
	elseif self.mode == "drag_point" then
		if Vector3.length(self.move_gizmo:drag_delta()) > 0 then
			LevelEditor:modified({LevelEditor.objects[self.spline]})
		end
		self.mode = nil
	end
	LevelEditor.move_tool:mouse_up(x, y)
end

function SplineTool:finish_creating()
	self.mode = ""
	local spline = LevelEditor.objects[self.spline]
	spline.points = self.points
	self.mode = nil
	LevelEditor:modified({spline})
end

function SplineTool:key(key)
	if self.mode == "creating" then
		if key == "esc" or key == "enter" then
			self:finish_creating()
		end
	end
	if self.spline and self.drag_point and key == "delete" then
		local spline = LevelEditor.objects[self.spline]
		local i = self.drag_point
		if #spline.points <= 4 then return end
		if i%3==1 then
			if i==#spline.points then i=i-1 end
			if i>1 then i=i-1 end
			table.remove(spline.points, i)
			table.remove(spline.points, i)
			table.remove(spline.points, i)
		elseif i%3==2 then
			spline.points[i]:box(spline.points[i-1])
		elseif i%3==0 then
			spline.points[i]:box(spline.points[i+1])
		end
		LevelEditor:modified({spline})
		self.drag_point = nil
	end
end
