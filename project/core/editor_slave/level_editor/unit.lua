--------------------------------------------------
-- Utility functions
--------------------------------------------------

local bone_color_palette = {
	{ 161, 106, 48 },
	{ 161, 48, 106 },
	{ 111, 48, 161 },
	{ 48, 103, 161 },
	{ 48, 161, 161 },
	{ 48, 161, 93 },
	{ 104, 161, 48 },
	{ 158, 161, 48 }
}

local function draw_pose(lines, pose, radius)
	local p = Matrix4x4.translation(pose)
	local x = Matrix4x4.x(pose)
	local y = Matrix4x4.y(pose)
	local z = Matrix4x4.z(pose)
	local x_color = Color(255, 0, 0)
	local y_color = Color(0, 255, 0)
	local z_color = Color(0, 0, 255)

	LineObject.add_line(lines, x_color, p, p + x * radius)
	LineObject.add_line(lines, y_color, p, p + y * radius)
	LineObject.add_line(lines, z_color, p, p + z * radius)
end

local function draw_bone(lines, from_pose, to_position, radius, color)
	local from_position = Matrix4x4.translation(from_pose)
	local bone_normal = Vector3.normalize(to_position - from_position)
	local bone_start = from_position + bone_normal * radius
	local bone_end = to_position - bone_normal * radius
	LineObject.add_cone(lines, color, bone_end, bone_start, radius, 4, 4)
end

local function set_material_wireframe_color(material, color)
	if color ~= nil then
		local a, b, c = Script.temp_count()
		Material.set_color(material, "dev_wireframe_color", color)
		Script.set_temp_count(a, b, c)
	end
end

local function set_mesh_wireframe_color(mesh, color)
	Mesh.set_shader_pass_flag(mesh, "dev_wireframe", color ~= nil)
	local last_material_index = Mesh.num_materials(mesh) - 1

	for material_index = 0, last_material_index do
		local material = Mesh.material(mesh, material_index)
		set_material_wireframe_color(material, color)
	end
end

local function set_landscape_wireframe_color(landscape, color)	
	Landscape.set_shader_pass_flag(landscape, "dev_wireframe", color ~= nil)
	local last_material_index = Landscape.num_materials(landscape) - 1

	for material_index = 0, last_material_index do
		local material = Landscape.material(landscape, material_index)
		set_material_wireframe_color(material, color)
	end
end

local function set_unit_wireframe_color(unit, color)
	local last_mesh_index = Unit.num_meshes(unit) - 1

	for mesh_index = 0, last_mesh_index do
		local mesh = Unit.mesh(unit, mesh_index)
		set_mesh_wireframe_color(mesh, color)
	end

	local last_landscape_index = Unit.num_landscapes(unit) - 1
	for landscape_index = 0, last_landscape_index do
		local landscape = Unit.landscape(unit, landscape_index)
		set_landscape_wireframe_color(landscape, color)
	end	
end

local function set_world_position(unit, node_id, world_position)
	assert(world_position ~= nil)
	local parent_node_id = Unit.scene_graph_parent(unit, node_id)

	if parent_node_id == nil then
		Unit.set_local_position(unit, node_id, world_position)
	else
		local parent_tm = Unit.world_pose(unit, parent_node_id)
		local to_local = Matrix4x4.inverse(parent_tm)
		local local_position = Matrix4x4.transform(to_local, world_position)
		Unit.set_local_position(unit, node_id, local_position)
	end
end

local function safe_world_rotation(unit, node_id)
	local local_rotation = Unit.local_rotation(unit, node_id)
	local parent_node_id = Unit.scene_graph_parent(unit, node_id)

	if parent_node_id == nil then
		return local_rotation
	else
		local parent_rotation = safe_world_rotation(unit, parent_node_id)
		return Quaternion.multiply(parent_rotation, local_rotation)
	end
end

local function set_world_rotation(unit, node_id, world_rotation)
	assert(world_rotation ~= nil)
	local parent_node_id = Unit.scene_graph_parent(unit, node_id)

	if parent_node_id == nil then
		Unit.set_local_rotation(unit, node_id, world_rotation)
	else
		local parent_rotation = safe_world_rotation(unit, parent_node_id)
		local to_local = Quaternion.inverse(parent_rotation)
		local local_rotation = Quaternion.multiply(to_local, world_rotation)
		Unit.set_local_rotation(unit, node_id, local_rotation)
	end
end


--------------------------------------------------
-- UnitObject
--------------------------------------------------

UnitObject = class(UnitObject, ObjectBase)

-- Immobilizes a unit by freezing all its actors and linking any
-- free scene graph nodes to the root.
function UnitObject.immobilize_unit(unit, immobilized_actor_ids)
	-- Convert all dynamic actors into kinematic actors.
	local actor_count = Unit.num_actors(unit)

	for actor_id = 0, actor_count - 1 do
		local actor = Unit.actor(unit, actor_id)

		if actor ~= nil and Actor.is_physical(actor) then
			Actor.set_kinematic(actor, true)

			if immobilized_actor_ids ~= nil then
				table.insert(immobilized_actor_ids, actor_id)
			end
		end
	end

	-- Parent free nodes to the root node.
	-- At this point, unparented nodes will be those that
	-- were previously controlled by dynamic actors.
	local node_count = Unit.num_scene_graph_items(unit)

	for node_id = 1, node_count - 1 do
		if Unit.scene_graph_parent(unit, node_id) == nil then
			Unit.scene_graph_link(unit, node_id, 0)
		end
	end
end

-- Returns the unscaled bounding box of a non-parented unit.
-- Since the level editor does not use parenting, this should work for all units in the world.
function UnitObject.unscaled_box(unit)
	local scaled_pose, unscaled_radius = Unit.box(unit)
	local scale = Matrix4x4.scale(scaled_pose)
	local unscaled_position = Matrix4x4.translation(scaled_pose)
	local unscaled_rotation = Unit.local_rotation(unit, 0)
	local unscaled_pose = Matrix4x4.from_quaternion_position(unscaled_rotation, unscaled_position)
	local scaled_radius = Vector3.multiply_elements(unscaled_radius, scale)
	return unscaled_pose, scaled_radius
end

-- MG: If you add parameters here, make sure you update the call to init in LevelEditor:reload_unit() as well.
function UnitObject:init(u, id, type, name, material)
	ObjectBase.init(self, id)
	self._unit = u
	self._local_component_pivots = {}
	self.name = name
	
	Unit.set_data(u, "id", id)
	Unit.set_data(u, "type", type)
	Unit.set_data(u, "material", material)
	self:immobilize()
end

function UnitObject:is_root_component(component_id)
	return component_id == nil or self:_node_id(component_id) == 0
end

function UnitObject:box(component_id)
	local tm, r

	if component_id == nil then
		tm, r = UnitObject.unscaled_box(self._unit)
	
		if r.x <= 0 and r.y <= 0 and r.z <= 0 then
			r = Vector3(0.5, 0.5, 0.5)
		end
	else
		-- Use world-aligned bounding boxes for now.
		tm = Matrix4x4.from_translation(self:world_position(component_id))
		r = Vector3(0.5, 0.5, 0.5)
	end

	return tm, r
end

function UnitObject:local_pose(component_id)
	return Unit.local_pose(self._unit, self:_node_id(component_id))
end

function UnitObject:world_pose(component_id)
	return Unit.world_pose(self._unit, self:_node_id(component_id))
end

function UnitObject:local_position(component_id)
	return Unit.local_position(self._unit, self:_node_id(component_id))
end

function UnitObject:set_local_position(position, component_id)
	Unit.set_local_position(self._unit, self:_node_id(component_id), position)
	LevelEditor.scatter_manager:update_scatter_transforms_for_unit(self.id)
end

function UnitObject:world_position(component_id)
	return Unit.world_position(self._unit, self:_node_id(component_id))
end

function UnitObject:set_world_position(position, component_id)
	set_world_position(self._unit, self:_node_id(component_id), position)
	LevelEditor.scatter_manager:update_scatter_transforms_for_unit(self.id)
end

function UnitObject:local_rotation(component_id)
	return Unit.local_rotation(self._unit, self:_node_id(component_id))
end

function UnitObject:set_local_rotation(rotation, component_id)
	Unit.set_local_rotation(self._unit, self:_node_id(component_id), rotation)
	LevelEditor.scatter_manager:update_scatter_transforms_for_unit(self.id)
end

function UnitObject:world_rotation(component_id)
	return safe_world_rotation(self._unit, self:_node_id(component_id))
end

function UnitObject:set_world_rotation(rotation, component_id)
	set_world_rotation(self._unit, self:_node_id(component_id), rotation)
	LevelEditor.scatter_manager:update_scatter_transforms_for_unit(self.id)
end

function UnitObject:local_scale(component_id)
	return Unit.local_scale(self._unit, self:_node_id(component_id))
end

function UnitObject:set_local_scale(scale, component_id)
	Unit.set_local_scale(self._unit, self:_node_id(component_id), scale)
	LevelEditor.scatter_manager:update_scatter_transforms_for_unit(self.id)
end

function UnitObject:local_pivot(component_id)
	if component_id == nil then
		return ObjectBase.local_pivot(self, nil)
	else
		local boxed_pivot = self._local_component_pivots[component_id]
		return boxed_pivot == nil and Vector3(0, 0, 0) or boxed_pivot:unbox()
	end
end

function UnitObject:set_local_pivot(offset, component_id)
	if component_id == nil then
		ObjectBase.set_local_pivot(self, offset, nil)
	else
		local boxed_pivot = self._local_component_pivots[component_id]
		
		if boxed_pivot == nil then
			boxed_pivot = Vector3Box()
			self._local_component_pivots[component_id] = boxed_pivot
		end

		boxed_pivot:store(offset)
	end
end

function UnitObject:_node_id(component_id)
	if component_id == nil then
		return 0
	end

	assert(type(component_id) == "string")
	local node_id = Unit.node(self._unit, component_id)
	return node_id
end

function UnitObject:duplicate(spawned)	
	local copy

	if self:material() == nil then
		copy = World.spawn_unit(LevelEditor.world, self:type(), self:local_position(), self:local_rotation())
	else
		copy = World.spawn_unit(LevelEditor.world, self:type(), self:local_position(), self:local_rotation(), self:material())
	end

	local nlights = Unit.num_lights(self._unit)

	for i = 0, nlights - 1 do
		Light.set_data(copy, Unit.light(copy, i), Unit.light(self._unit, i))
	end


	local id = Application.guid()
	local uo = UnitObject(copy, id, self:type(), self.name, self:material())
	Unit.set_id(copy, id)
	uo.hidden = self.hidden
	uo.unselectable = self.unselectable
	uo.duplication_source = self
	uo._local_component_pivots = Array.map(self._local_component_pivots, function(boxed_pivot) return Vector3Box(boxed_pivot:unbox()) end)
	uo:set_local_scale(self:local_scale())
	uo:set_local_pivot(self:local_pivot())

	-- Apply local pose tweaks.
	local num_nodes = Unit.num_scene_graph_items(copy)
	
	for node_id = 0, num_nodes - 1 do
		Unit.set_local_pose(copy, node_id, Unit.local_pose(self._unit, node_id))
	end

	LevelEditor.objects[id] = uo
	LevelEditor.scatter_manager:duplicate_scatter_for_unit(self.id, id)
	spawned[#spawned + 1] = uo

	if Voxelizer then
		Voxelizer.add_unit(LevelEditor.world, copy)
	end
	BakedLighting.add_unit(LevelEditor.world, copy)
	
	return uo
end

function UnitObject:destroy()
	LevelEditor.scatter_manager:unspawn_scatter_for_unit(self.id)
	if Voxelizer then
		Voxelizer.remove_unit(LevelEditor.world, self._unit)
	end
	BakedLighting.add_unit(LevelEditor.world, self._unit)
	World.destroy_unit(LevelEditor.world, self._unit)
	LevelEditor.objects[self.id] = nil
end

function UnitObject:complete_move()
	-- This function is typically called after World.update the following frame.
	-- Thus, we must guard against objects having been deleted by then.
	if not Unit.alive(self._unit) then
		return
	end

	LevelEditor.scatter_manager:update_scatter_transforms_for_unit(self.id)
	Unit.disable_physics(self._unit)
	Unit.enable_physics(self._unit)
	self:immobilize()
end

function UnitObject:spawn_data()
	return {
		id = self.id,
		klass = "unit",
		type = self:type(),
		pos = self:local_position(),
		rot = self:local_rotation(),
		scl = self:local_scale(),
		pivot = self:local_pivot(),
		name = self.name,
		material = self:material()
	}
end

function UnitObject:immobilize()
	if self._immobilized_actor_ids == nil then
		self._immobilized_actor_ids = {}
		UnitObject.immobilize_unit(self._unit, self._immobilized_actor_ids)
	else
		UnitObject.immobilize_unit(self._unit, nil)
	end
end

function UnitObject:mobilize()
	if self._immobilized_actor_ids ~= nil then
		local lookup_actor = Func.partial(Unit.actor, self._unit)
		local set_dynamic = function(actor) Actor.set_kinematic(actor, false) end
		Array.iter(self._immobilized_actor_ids, Func.compose(lookup_actor, set_dynamic))
		self._immobilized_actor_ids = nil
	end
end

function UnitObject:type()
	return Unit.get_data(self._unit, "type")
end

function UnitObject:material()
	return Unit.get_data(self._unit, "material")
end

function UnitObject:draw_box(tm, radius, material, color)
	local p = Matrix4x4.translation(tm)
	
	for y = 0,2 do
		local i = 2*y + 1
		local x = (y + 2) % 3 + 1
		local z = (y + 1) % 3 + 1
		local y = y+1
		
		local m = Matrix4x4.identity()
		Matrix4x4.set_x(m, Matrix4x4.axis(tm, x) )
		Matrix4x4.set_y(m, Matrix4x4.axis(tm, y) )
		Matrix4x4.set_z(m, Matrix4x4.axis(tm, z) )
		local r = Vector3(Vector3.element(radius,x), Vector3.element(radius,y), Vector3.element(radius,z))
		
		local size = Vector3(r.x*2, r.z*2, 0)
		Matrix4x4.set_translation(m, p + Matrix4x4.transform_without_translation(m, Vector3(-r.x, -r.y, -r.z)))
		Gui.bitmap_3d(LevelEditor.world_gui, material, m, Vector3(0,0,0), 0, size, color)
		
		Matrix4x4.set_x(m, -Matrix4x4.x(m))
		Matrix4x4.set_y(m, -Matrix4x4.y(m))
		Matrix4x4.set_translation(m, p + Matrix4x4.transform_without_translation(m, Vector3(-r.x, -r.y, -r.z)))
		Gui.bitmap_3d(LevelEditor.world_gui, material, m, Vector3(0,0,0), 0, size, color)
	end
end

function UnitObject:highlight_changed(component_id)
	if Unit.alive(self._unit) then
		local wireframe_color = component_id == nil and LevelEditor:object_highlight_color(self) or nil
		set_unit_wireframe_color(self._unit, wireframe_color)
	end
end

function UnitObject:draw_highlight()
	if LevelEditor:object_highlight_color(self) == nil then
		return
	end

	local num_lights = Unit.num_lights(self._unit)

	for i = 0, num_lights - 1 do
		Light.debug_draw(Unit.light(self._unit, i), LevelEditor.lines)
	end
end

function UnitObject:draw_snap_points()
	local lines = LevelEditor.lines
	local snap_points = LevelEditor.snap_points[self:type()] or {}
	
	local pos = Unit.world_position(self._unit, 0)
	LineObject.add_sphere(lines, Color(0,255,255), pos, 0.5)
	
	for _,p in ipairs(snap_points) do
		local pos = Unit.world_position(self._unit, Unit.node(self._unit, p))
		LineObject.add_sphere(lines, Color(0,255,255), pos, 0.5)
	end
end

function UnitObject:draw_components()
	local function distance_to_root(node_id)
		local parent_node_id = Unit.scene_graph_parent(self._unit, node_id)
		return parent_node_id == nil and 0 or 1 + distance_to_root(parent_node_id)
	end

	local unselected_bone_colors = Array.map(bone_color_palette, Func.compose(unpack, Color))

	local function unselected_color(node_id)
		local distance = distance_to_root(node_id)
		local index = Array.cycle_index(unselected_bone_colors, distance + 1)
		return unselected_bone_colors[index]
	end

	local function get_owned_node_id(scene_element_ref)
		local object_id, component_id = SceneElementRef.unpack(scene_element_ref)
		return object_id == self.id and self:_node_id(component_id) or nil
	end

	local selected_node_ids = Set.of_array(LevelEditor.selection:scene_element_refs(), get_owned_node_id)
	local last_selected_node_id = Nilable.bind(Array.last(LevelEditor.selection:scene_element_refs()), get_owned_node_id)
	local selected_color = LevelEditor.colors.selected()
	local last_selected_color = LevelEditor.colors.last_selected()

	local function node_color(node_id, x)
		assert(node_id ~= nil)

		if Set.contains(selected_node_ids, node_id) then
			return node_id == last_selected_node_id and last_selected_color or selected_color
		end

		local parent_node_id = Unit.scene_graph_parent(self._unit, node_id)
		return parent_node_id == nil and unselected_color(x) or node_color(parent_node_id, x)
	end

	local lines = LevelEditor.lines_noz
	local node_names_by_node_id = LevelEditor:get_unit_node_names(self:type())
	local bone_radius = self:_bone_radius()

	for _, component_id in pairs(node_names_by_node_id) do
		local scene_element_ref = SceneElementRef.make(self.id, component_id)

		-- Draw coordinate system axis.
		local node_id = self:_node_id(component_id)
		local pose = Unit.world_pose(self._unit, node_id)
		draw_pose(lines, pose, bone_radius)

		-- Draw sphere around coordinate system center.
		local position = Matrix4x4.translation(pose)
		LineObject.add_sphere(lines, node_color(node_id, node_id), position, bone_radius, 24, 1)

		-- Draw connecting bone to parent.
		local parent_node_id = Unit.scene_graph_parent(self._unit, node_id)

		if parent_node_id ~= nil then
			local parent_pose = Unit.world_pose(self._unit, parent_node_id)
			draw_bone(lines, parent_pose, position, bone_radius, node_color(parent_node_id, parent_node_id))
		end
	end
end

function UnitObject:add_snap_points(t)
	local snap_points = LevelEditor.snap_points[self:type()] or {}
	local tm = Unit.world_pose(self._unit, 0)
	local box = Matrix4x4Boxed()
	box:box(tm)
	t[#t + 1] = box
	
	for _,p in ipairs(snap_points) do
		if Unit.has_node(self._unit, p) then
			local tm = Unit.world_pose(self._unit, Unit.node(self._unit, p))
			local box = Matrix4x4Boxed()
			box:box(tm)
			t[#t + 1] = box
		end
	end
end

function UnitObject:raycast(ray_start, ray_dir, ray_length)
	local oobb_distance = Intersect.ray_box(ray_start, ray_dir, self:box())

	if oobb_distance ~= nil and oobb_distance < ray_length then
		return Unit.mesh_raycast(self._unit, ray_start, ray_dir, ray_length)
	else
		return nil, nil
	end
end

function UnitObject:component_raycast(ray_start, ray_dir, ray_length)
	local node_names_by_node_id = LevelEditor:get_unit_node_names(self:type())
	local min_distance = ray_length
	local component_id = nil
	local bone_radius = self:_bone_radius()

	for node_id, node_name in pairs(node_names_by_node_id) do
		local nv, nq, nm = Script.temp_count()
		local node_position = Unit.world_position(self._unit, node_id)
		local distance_to_sphere = Intersect.ray_sphere(ray_start, ray_dir, node_position, bone_radius)

		if distance_to_sphere ~= nil and distance_to_sphere < min_distance then
			min_distance = distance_to_sphere
			component_id = node_name
		end

		local parent_node_id = Unit.scene_graph_parent(self._unit, node_id)

		if parent_node_id ~= nil then
			local parent_node_position = Unit.world_position(self._unit, parent_node_id)
			local segment_normal = Vector3.normalize(node_position - parent_node_position)
			local segment_start = parent_node_position + segment_normal * bone_radius
			local segment_end = node_position - segment_normal * bone_radius
			local distance_to_segment, normalized_distance_along_segment = Intersect.ray_segment(ray_start, ray_dir, segment_start, segment_end)

			if distance_to_segment ~= nil and distance_to_segment < min_distance then
				local point_on_ray = ray_start + ray_dir * distance_to_segment
				local point_on_segment = segment_start + (segment_end - segment_start) * normalized_distance_along_segment
				
				if Vector3.distance(point_on_ray, point_on_segment) < bone_radius then
					min_distance = distance_to_segment
					component_id = node_names_by_node_id[parent_node_id]
				end
			end
		end

		Script.set_temp_count(nv, nq, nm)
	end

	if component_id ~= nil then
		return min_distance, -ray_dir, component_id
	end

	return nil, nil, nil
end

function UnitObject:filter_component_selection(component_ids)
	local component_node_id = Func.method("_node_id", self)
	local selected_node_ids = Set.of_array(component_ids, component_node_id)

	local function parent_is_unselected(node_id)
		local parent_node_id = Unit.scene_graph_parent(self._unit, node_id)

		if parent_node_id == nil then
			return true
		end

		if Set.contains(selected_node_ids, parent_node_id) then
			return false
		end

		return parent_is_unselected(parent_node_id)
	end
	
	local filtered_component_ids = Array.filter(component_ids, Func.compose(component_node_id, parent_is_unselected))
	return filtered_component_ids
end

function UnitObject:closest_mesh_point_to_ray(from, dir, tres)
	local closest_point, distance_along_ray, distance_to_ray = Unit.mesh_closest_point_raycast(self._unit, from, dir, tres)
	return closest_point, distance_along_ray, distance_to_ray
end

function UnitObject:set_visible(visible)
	if (visible and self.hidden) or (not visible and not self.hidden) then
		ObjectBase.set_visible(self, visible)
		Unit.set_unit_visibility(self._unit, visible)
		Unit.disable_physics(self._unit)

		if visible then
			Unit.enable_physics(self._unit)
			self:immobilize()
		end
	end
end

function UnitObject:_bone_radius()
	local min_radius = 0.01
	local max_radius = 0.5
	local oobb_radius = Tuple.second(self:box())
	local minor_oobb_axis_length = math.min(oobb_radius.x, oobb_radius.y, oobb_radius.z)
	local radius = minor_oobb_axis_length / 10
	return math.min(math.max(min_radius, radius), max_radius)
end
