--------------------------------------------------
-- Helper functions
--------------------------------------------------

local function set_landscape_undergrowth_visibility(world, visible)
	local units = World.units(world)
	
	for _, unit in ipairs(units) do
		local last_landscape_index = Unit.num_landscapes(unit) - 1
		
		for i = 0, last_landscape_index do
			local landscape = Unit.landscape(unit, i)
			LandscapeEditor.set_undergrowth_visibility(world, landscape, visible)
		end
	end
end

local function draw_offset()
	return Vector3(0, 0, 0.1)
end

local max_face_size = 6


--------------------------------------------------
-- Navmesh
--------------------------------------------------

Navmesh = class(Navmesh, ObjectBase)

function Navmesh:init()
	ObjectBase.init(self)
	self._mesh_builder = Application.create_mesh_builder(max_face_size)
end

function Navmesh:destroy()
	Application.destroy_mesh_builder(self._mesh_builder)
	self._mesh_builder = nil
	ObjectBase.destroy(self)
end

function Navmesh:local_pose(component_id)
	-- Currently, the navmesh cannot be transformed.
	assert(component_id == nil)
	return Matrix4x4.identity()
end

function Navmesh:local_position(component_id)
	-- Currently, the navmesh cannot be transformed.
	assert(component_id == nil)
	return Vector3(0, 0, 0)
end

function Navmesh:set_local_position(position, component_id)
	-- Currently, the navmesh cannot be transformed.
	assert(component_id == nil)
end

function Navmesh:local_rotation(component_id)
	-- Currently, the navmesh cannot be transformed.
	assert(component_id == nil)
	return Quaternion.identity()
end

function Navmesh:set_local_rotation(rotation, component_id)
	-- Currently, the navmesh cannot be transformed.
	assert(component_id == nil)
end

function Navmesh:local_scale(component_id)
	-- Currently, the navmesh cannot be transformed.
	assert(component_id == nil)
	return Vector3(1, 1, 1)
end

function Navmesh:set_local_scale(scale, component_id)
	-- Currently, the navmesh cannot be transformed.
	assert(component_id == nil)
end

function Navmesh:box()
	local min = MeshBuilder.min(self._mesh_builder)
	local max = MeshBuilder.max(self._mesh_builder)
	
	local pos = (max + min) / 2
	local r = max - pos
	return Matrix4x4.from_translation(pos), r
end

function Navmesh:raycast(ray_start, ray_dir, ray_length)
	local padding = 0.1
	local oobb_distance = Intersect.ray_box(ray_start, ray_dir, self:box())

	if oobb_distance ~= nil and oobb_distance < ray_length + padding then
		local distance_along_ray, face_normal, face_index = MeshBuilder.raycast(self._mesh_builder, ray_start, ray_dir, ray_length + padding)
		local adjusted_distance = distance_along_ray ~= nil and distance_along_ray - padding or nil
		return adjusted_distance, face_normal, face_index
	else
		return nil, nil, nil
	end
end

function Navmesh:closest_mesh_point_to_ray(ray_start, ray_dir, ray_length)
	local closest_point, distance_along_ray, distance_to_ray, point_index = MeshBuilder.closest_point_raycast(self._mesh_builder, ray_start, ray_dir, ray_length)
	return closest_point, distance_along_ray, distance_to_ray, point_index
end

function Navmesh:closest_edge_point_to_ray(ray_start, ray_dir, ray_length)
	local edge_point, distance_along_ray, distance_to_ray, point_index_a, point_index_b = MeshBuilder.closest_edge_point_raycast(self._mesh_builder, ray_start, ray_dir, ray_length)
	return edge_point, distance_to_ray, point_index_a, point_index_b
end

function Navmesh:duplicate()
	-- Currently there can only be one navmesh in a level.
	return nil
end

function Navmesh:add_vertex_and_send(v)
	Application.console_send { type = "add_navmesh_vertex", v = v, id = self.id }
end

function Navmesh:add_poly(p)
	MeshBuilder.push_face(self._mesh_builder, unpack(p))
end

function Navmesh:add_poly_and_send(p)
	Application.console_send { type = "add_navmesh_poly", poly = p, id = self.id }
end

function Navmesh:vertex_count()
	return MeshBuilder.point_count(self._mesh_builder)
end

function Navmesh:vertex(i)
	return MeshBuilder.point(self._mesh_builder, i)
end

function Navmesh:add_vertex(v)
	MeshBuilder.push_point(self._mesh_builder, v)
end

function Navmesh:pop_vertex()
	MeshBuilder.pop_point(self._mesh_builder)
end

function Navmesh:swap_vertex(i1, i2)
	MeshBuilder.swap_points(self._mesh_builder, i1, i2)
end

function Navmesh:move_vertex(i, v)
	MeshBuilder.set_point(self._mesh_builder, i, v)
end

function Navmesh:insert_poly(i, p)
	MeshBuilder.insert_face(self._mesh_builder, i, unpack(p))
end

function Navmesh:remove_poly(i)
	MeshBuilder.remove_face(self._mesh_builder, i)
end

function Navmesh:recalc_bounds()
	MeshBuilder.recalc_bounds(self._mesh_builder)
end

function Navmesh:draw()
	local selected_face_index = LevelEditor.navmesh_tool._selected

	local edge_color = Color(51, 0, 0, 0)
	local fill_color = Color(128, 200, 200, 200)
	local selected_fill_color = Color(128, 255, 255, 0)
	local up_normal_color = Color(102, 0, 0, 255)
	local down_normal_color = Color(102, 255, 0, 0)
	local lines = LevelEditor.lines

	MeshBuilder.draw_filled_faces(self._mesh_builder, LevelEditor.world_gui, 0, fill_color, selected_fill_color, selected_face_index)
	MeshBuilder.draw_unreferenced_points(self._mesh_builder, lines, edge_color)
	MeshBuilder.draw_face_normals(self._mesh_builder, lines, up_normal_color, down_normal_color)
end

function Navmesh:draw_highlight()
	local color = LevelEditor:object_highlight_color(self) or Color(51, 0, 0, 0)
	MeshBuilder.draw_edges(self._mesh_builder, LevelEditor.lines, color)
end

function Navmesh:draw_edit(poly, pos)
	local red = Color(255, 0, 0)
	local grey = Color(128, 255, 200, 200)
	local v = {}
	local o = draw_offset()
	
	for _,i in ipairs(poly) do
		if i <= self:vertex_count() then
			v[#v+1] = self:vertex(i) + o
		end
	end
	v[#v+1] = pos + o
	
	for i=3, #v do
		Gui.triangle(LevelEditor.world_gui, v[1], v[i-1], v[i], 0, grey)
	end
	for i=2, #v do
		local v0 = v[i-1]
		local v1 = v[i-0]
		LineObject.add_line(LevelEditor.lines, red, v0, v1)
	end
end


--------------------------------------------------
-- NavmeshTool
--------------------------------------------------

NavmeshTool = class(NavmeshTool, Tool)

function NavmeshTool:init()
	self._ray_hit = Vector3Boxed(0,0,0)
	self._snap_vertex = nil
	self._snap_range = 1.0
	self._poly = {}
	self.mode = "create"
	self.state = nil
end

function NavmeshTool:activate(id)
	self._navmesh = LevelEditor.objects[id]
end

function NavmeshTool:snap(cam, dir)
	local ray_length = LevelEditor.editor_camera:far_range()
	local _, _, distance_to_ray, point_index = self._navmesh:closest_mesh_point_to_ray(cam, dir, ray_length)
	self._snap_vertex = (distance_to_ray ~= nil and distance_to_ray < self._snap_range) and point_index or nil
	self._snap_edge = nil
	
	if self._snap_vertex == nil then
		local edge_point, edge_distance_to_ray, point_index_a, point_index_b = self._navmesh:closest_edge_point_to_ray(cam, dir, ray_length)

		self._snap_edge_point = Vector3Boxed()

		if edge_distance_to_ray ~= nil and edge_distance_to_ray < self._snap_range then
			self._snap_edge = { point_index_a, point_index_b }
			self._snap_edge_point:box(edge_point)
		end
	end
end

function NavmeshTool:spawn()
	if self.state == "creating" then
		self._navmesh:add_poly_and_send(self._poly)
		self._poly = {}
		self.state = nil
	end
end

function NavmeshTool:mouse_spawn(x, y)
	if self._snap_edge then
		Application.console_send { type = "navmesh_split_edge", v = self._snap_edge_point:unbox(),
			i1 = self._snap_edge[1], i2 = self._snap_edge[2], id = self._navmesh.id
		}
	elseif not self._snap_vertex then
		self._navmesh:add_vertex_and_send(self._ray_hit:unbox())
		if self.state == "creating" then
			self._poly[#self._poly + 1] = self._navmesh:vertex_count() + 1
			if #self._poly == 3 then self:spawn() end
		end
	end
end

function NavmeshTool:update()
	-- Handle snap vertex deleted, for example by Undo
	if self._snap_vertex and self._snap_vertex > self._navmesh:vertex_count() then
		self._snap_vertex = nil
	end

	if self.mode == "create" and self.state == "creating" then
		local pos = self._ray_hit:unbox()
		if self._snap_vertex then pos = self._navmesh:vertex(self._snap_vertex) end
		self._navmesh:draw_edit(self._poly, pos)
	end
	
	if self._snap_vertex then
		local v = self._navmesh:vertex(self._snap_vertex) + draw_offset()
		LineObject.add_sphere(LevelEditor.lines, Color(255,0,0), v, 0.3)
	elseif self._snap_edge then
		local v = self._snap_edge_point:unbox() + draw_offset()
		LineObject.add_sphere(LevelEditor.lines, Color(0,255,0), v, 0.3)
	else
		local v = self._ray_hit:unbox() + draw_offset()
		LineObject.add_sphere(LevelEditor.lines, Color(0,0,0), v, 0.3)
	end
end

function NavmeshTool:on_selected()
	set_landscape_undergrowth_visibility(LevelEditor.world, false)
end

function NavmeshTool:on_deselected()
	set_landscape_undergrowth_visibility(LevelEditor.world, true)
end

function NavmeshTool:mouse_down(x, y)
	if self._snap_vertex then
		if self.mode == "create" and self.state == nil then
			self._poly = {self._snap_vertex}
			self.state = "creating"
		elseif self.mode == "create" and self.state == "creating" then
			self._poly[#self._poly + 1] = self._snap_vertex
			if #self._poly == 3 then self:spawn() end
		elseif self.mode == "move" then
			self.state = "moving"
			self._move_vertex = self._snap_vertex
		end
	else
		self._selected = self:select(x, y)
	end
end

local function picking_predicate(level_object)
	return Picking.is_visible_and_not_in_group(level_object)
   	   and kind_of(level_object) ~= Navmesh
end

local visual_raycast = Func.partial(Picking.raycast, picking_predicate)

function NavmeshTool:mouse_move(x, y)
	local cam, dir = LevelEditor:camera_ray(x, y)
	local ray_length = LevelEditor.editor_camera:far_range()
	local _, distance_along_ray = visual_raycast(LevelEditor.objects, cam, dir, ray_length)
	local spawn_plane_height = distance_along_ray == nil and 0 or GridPlane.snap_number(0.001, (distance_along_ray * dir + cam).z)
	local _, spawn_point = GridPlane.snap_mouse(Matrix4x4.identity(), spawn_plane_height, x, y)
	self._ray_hit:box(spawn_point)
	
	if LevelEditor.modifiers.control then
		self._snap_vertex = nil
		self._snap_edge = nil
	else
		self:snap(cam, dir)
	end
	
	if self.state == "moving" then
		self._navmesh:move_vertex(self._move_vertex, spawn_point)
	end
end

function NavmeshTool:mouse_up(x, y)
	if self.state == "moving" then
		Application.console_send { type = "navmesh_vertex_moved", i = self._move_vertex, v = self._navmesh:vertex(self._move_vertex), id = self._navmesh.id }
		self.state = nil
	end
end

function NavmeshTool:key(key)
	if key == "esc" then
		self.state = nil
	end
	if key == "delete" then
		if self._selected then
			Application.console_send { type = "remove_navmesh_poly", i = self._selected, id = self._navmesh.id}
			self._selected = nil
		elseif self._snap_vertex then
			Application.console_send { type = "remove_navmesh_vertex", i = self._snap_vertex, id = self._navmesh.id}
			self._snap_vertex = nil
		end
	end
end

function NavmeshTool:select(x, y)
	local ray_start, ray_dir = LevelEditor:camera_ray(x, y)
	local ray_length = LevelEditor.editor_camera:far_range()
	local _, _, face_index = self._navmesh:raycast(ray_start, ray_dir, ray_length)
	return face_index
end
