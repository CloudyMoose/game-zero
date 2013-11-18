--------------------------------------------------
-- Utility functions
--------------------------------------------------

local visual_raycast = Func.partial(Picking.raycast, Picking.is_visible_and_not_in_group)

local function find_focus_point(camera)
	local camera_pose = Camera.local_pose(camera)
	local camera_position = Matrix4x4.translation(camera_pose)
	local camera_forward_vector = Matrix4x4.forward(camera_pose)
	local camera_far_range = Camera.far_range(camera)
	local hit_object, distance_along_ray = visual_raycast(LevelEditor.objects, camera_position, camera_forward_vector, camera_far_range)

	return hit_object ~= nil
	   and camera_position + camera_forward_vector * distance_along_ray
	    or nil
end

local function visible_world_aabb()
	local visible_objects = Dict.filter(LevelEditor.objects, Picking.is_visible_and_not_in_group)
	local merged_center, merged_radius = AABB.merged_box(visible_objects, Func.method("box"))
	return merged_center, merged_radius
end

local function draw_world_origin_grid(line_object, size)
	if size == 0 then return end

	local nv, nq, nm = Script.temp_count()
	local line_color = LevelEditor.colors.inactive()
	local span = 10
	
	for i = -span, span do
		if i ~= 0 then
			local offset = i * size
			LineObject.add_line(line_object, line_color, Vector3(offset, size * span, 0), Vector3(offset, -size * span, 0))
			LineObject.add_line(line_object, line_color, Vector3(size * span, offset, 0), Vector3(-size * span, offset, 0))
		end
	end

	-- Draw origin on top so ligher lines don't overlap.
	local origin_line_color = Color(0, 0, 0)
	LineObject.add_line(line_object, origin_line_color, Vector3(0, size * span, 0), Vector3(0, -size * span, 0))
	LineObject.add_line(line_object, origin_line_color, Vector3(size * span, 0, 0), Vector3(-size * span, 0, 0))

	Script.set_temp_count(nv, nq, nm)
end

--------------------------------------------------
-- LevelEditor
--------------------------------------------------

LevelEditor = LevelEditor or {}
EditorApi = LevelEditor

LevelEditor.colors = {
	wireframe = function() return Color(38, 0, 67) end,
	hovered = function() return Color(255, 104, 0) end,
	selected = function() return Color(255, 255, 255) end,
	last_selected = function() return Color(67, 255, 163) end,
	inactive = function() return Color(127, 127, 127) end,
	accent = function() return Color(100, 220, 255) end
}

function LevelEditor:init()
	-- World objects
	self.world = Application.new_world()
	self.landscape_decoration_observer = LandscapeDecoration and LandscapeDecoration.create_observer(self.world, Vector3(0,0,0))	
	World.set_flow_enabled(self.world, false)
	self.physics_world = World.physics_world(self.world)
	self.viewport = Application.create_viewport(self.world, "default")
	self.shading_environment = World.create_shading_environment(self.world)
	self.gui = World.create_screen_gui(self.world, "immediate", "material", "core/editor_slave/gui/gui")
	self.world_gui = World.create_world_gui(self.world, Matrix4x4.identity(),1,1,"immediate", "material", "core/editor_slave/gui/gui")
	self.prototype_gui = World.create_world_gui(self.world, Matrix4x4.identity(),1,1, "material", "core/editor_slave/gui/gui", "shadow_caster")
	self.camera_unit = World.spawn_unit(self.world, "core/units/camera")
	self.camera = Unit.camera(self.camera_unit, "camera")
	self.lines = World.create_line_object(self.world)
	self.lines_noz = World.create_line_object(self.world, true)
	self.cubemap_generator = CubemapGenerator(self.world)
	self.skydome_unit = nil
	self.baked_light_resource = nil
	
	-- Keyboard and mouse state.
	self.modifiers = { shift = false, control = false, snap_off = false, camera = false } -- The alt button is reserved for camera control.
	self.mouse = {
		over = false,
		pos = { x = 0, y = 0 },
		delta = { x = 0, y = 0 },
		down = { x = 0, y = 0 },
		wheel = { delta = 0, steps = 0 },
		buttons = { left = false, right = false, middle = false, thumb = false }
	}
	
	-- Default editor objects
	self.editor_camera = EditorCamera(self.camera, self.camera_unit)
	self.grid = { size = 2.5, rotation_snap = 45, is_visible_at_origin = false }
	self.settings = { is_control_key_used_to_move_along_axis_plane = true }
	self.selection = Selection()
	self.scatter_manager = ScatterManager(World.scatter_system(self.world))
	
	-- Editor data
	self.objects = {}
	self.snap_points = {}
	self._unit_node_names = {}
	self._post_world_update_actions = {}
	
	-- Editor state
	local camera_pos = Vector3(0,-10,1)
	local camera_look = Vector3(0,0,1)
	local camera_dir = Vector3.normalize(camera_look - camera_pos)
	Camera.set_local_position(self.camera, self.camera_unit, camera_pos)
	Camera.set_local_rotation(self.camera, self.camera_unit, Quaternion.look( camera_dir, Vector3(0,0,1) ) )
	
	self.editor_camera:load_data()
	self.t = 0
	self._spawn_plane_height = 0
	self._snap_mode = "Relative"
	self.unit_preview = nil

	-- Editor tools
	self.select_tool = SelectTool()
	self.place_tool = PlaceTool()
	self.move_tool = MoveTool()
	self.rotate_tool = RotateTool()
	self.scale_tool = ScaleTool()
	self.box_size_tool = BoxSizeTool()
	self.snap_together_tool = SnapTogetherTool()
	self.note_tool = NoteTool()
	self.prototype_tool = BoxTool(Prototype)
	self.marker_tool = MarkerTool()
	self.trigger_tool = BoxTool(Trigger)
	self.spline_tool = SplineTool()
	self.navmesh_tool = NavmeshTool()
	self.scatter_tool = ScatterTool(self.scatter_manager)
	self.landscape_tool = LandscapeTool()
	self.volume_tool = VolumeTool()
	self.static_pvs_tool = StaticPvsTool()

	self.level_story = LevelStory()
	
	if Application.platform() == "win32" then
		self.tool = self.move_tool
	else
		self.tool = Tool()
	end
end

function LevelEditor:set_tool(tool)
	assert(tool ~= nil)

	if tool == self.tool then
		return
	end

	local refresh_highlight = self.tool.is_highlight_suppressed ~= nil or tool.is_highlight_suppressed ~= nil

	if self.tool.on_deselected then
		self.tool:on_deselected()
	end

	self.tool = tool
	
	if tool.on_selected then
		tool:on_selected()
	end

	if refresh_highlight then
		self:raise_highlight_changed()
	end
end

function LevelEditor:set_skydome_unit(unit)
	if self.skydome_unit then
		World.destroy_unit(self.world, self.skydome_unit)
		self.skydome_unit = nil
	end
	if unit ~= "" then
		self.skydome_unit = World.spawn_unit(self.world, unit)
		
		-- HACK: Must have same id as the skydome unit added in LevelData.cs : Export().
		Unit.set_id(self.skydome_unit, "skydome-unit")
	end
end

function LevelEditor:set_background_visibility(visible)
	if Unit.alive(self.skydome_unit) then
		Unit.set_unit_visibility(self.skydome_unit, visible)
	end
end

function LevelEditor:set_shading_environment(shading_environment)
	if shading_environment ~= "" then
		World.set_shading_environment(self.world, self.shading_environment, shading_environment)
	end
end

function LevelEditor:set_baked_lighting(resource)
	assert(self.baked_light_resource == nil)
	if Application.can_get("baked_lighting", resource) then
		self.baked_light_resource = resource
		BakedLighting.map(self.world, resource)
	end
end

function LevelEditor:shutdown()
	self:close_unit_preview()

	for id, level_object in pairs(self.objects) do
		level_object:destroy()
	end

	self.scatter_manager:shutdown()
	Application.destroy_viewport(self.world, self.viewport)
	World.destroy_shading_environment(self.world, self.shading_environment)
	Application.release_world(self.world)
	self.skydome_unit = nil
	self.baked_light_resource = nil
end

function LevelEditor:reset()
	LevelEditor:shutdown()
	LevelEditor:init()
end

function LevelEditor:hovered_object()
	local obj = self.objects[self._hovered_object_id]
	
	if obj == nil then
		-- No hovered object.
		return nil
	elseif obj._unit ~= nil then
		-- The hovered object is a unit. Make sure it is still alive.
		-- If not, clear hovered object reference and return nil.
		if Unit.alive(obj._unit) then
			return obj
		else
			self:set_hovered_object(nil)
			return nil
		end
	else
		-- Our object reference is a lua object.
		return obj
	end
end

function LevelEditor:enable_batch_bake_mode()
	self._batch_bake_mode = true
end

function LevelEditor:enqueue_post_world_update_action(action)
	assert(Validation.is_function(action))
	table.insert(self._post_world_update_actions, action)
end

function LevelEditor:perform_post_world_update_actions()
	for _, action in ipairs(self._post_world_update_actions) do
		action()
	end

	self._post_world_update_actions = {}
end

function LevelEditor:set_hovered_object(hovered_object)
	local previous_hovered_object = self.objects[self._hovered_object_id]
	self._hovered_object_id = hovered_object and hovered_object.id or nil

	if previous_hovered_object ~= hovered_object then
		if previous_hovered_object ~= nil then
			previous_hovered_object:highlight_changed()
		end

		if hovered_object ~= nil then
			hovered_object:highlight_changed()
		end
	end
end

function LevelEditor:update(dt)
	self.t = self.t + dt
	
	LineObject.reset(self.lines)
	LineObject.reset(self.lines_noz)
	
	World.update(self.world, dt)
	self:perform_post_world_update_actions()

	self.editor_camera:update(dt, self.mouse.pos, self.mouse.delta)

	World.update_unit(self.world, self.camera_unit)

	self.editor_camera:save_data()
	self.scatter_manager:update(self.camera)
	self.level_story:update()
	
	local tm = self.editor_camera:world()
	local camera_pos = Matrix4x4.translation(tm)
	
	if StaticPvs.is_any_mapped(self.world) then
		StaticPvs.set_observer(self.world, camera_pos)
	end

	if Voxelizer then
		Voxelizer.set_observer(self.world,tm)
	end		

	if self._batch_bake_mode == true then
		Application.console_send { type = "update_complete" }
		return
	end

	if LandscapeDecoration then
		LandscapeDecoration.move_observer(self.world, self.landscape_decoration_observer, camera_pos)
	end
	
	if Application.platform() == "win32" then
		if self.grid.is_visible_at_origin then
			draw_world_origin_grid(self.lines, self.grid.size)
		end

		local camera_is_controlled_by_mouse = self.editor_camera:is_controlled_by_mouse() or nil

		if camera_is_controlled_by_mouse ~= self._camera_was_controlled_by_mouse then
			self:raise_highlight_changed()
		end

		self._camera_was_controlled_by_mouse = camera_is_controlled_by_mouse

		if not camera_is_controlled_by_mouse then
			if (self.mouse.delta.x ~= 0 or self.mouse.delta.y ~= 0) and not self.editor_camera:is_animating() then
				local a, b, c = Script.temp_count()
				local mouse_pos = self.mouse.pos
				local cam_pos, cam_dir = self:camera_ray(mouse_pos.x, mouse_pos.y)
				local ray_length = self.editor_camera:far_range()
				local hovered_object, distance_along_ray = visual_raycast(self.objects, cam_pos, cam_dir, ray_length)

				if hovered_object ~= nil and not Picking.is_selectable(hovered_object) then
					hovered_object = nil
				end

				self:set_hovered_object(hovered_object)
				self._spawn_plane_height = distance_along_ray == nil and 0 or GridPlane.snap_number(0.001, (distance_along_ray * cam_dir + cam_pos).z)
				self.tool:mouse_move(mouse_pos.x, mouse_pos.y)
				Script.set_temp_count(a, b, c)
			end
		end

		-- Handle mouse wheel input.
		local mouse_wheel = self.mouse.wheel

		if mouse_wheel.delta ~= 0 and mouse_wheel.steps ~= 0 then
			if self.editor_camera:is_controlled_by_mouse() or self.modifiers.camera or self.tool.mouse_wheel == nil then
				self.editor_camera:mouse_wheel(mouse_wheel.delta, mouse_wheel.steps)
			else
				self.tool:mouse_wheel(mouse_wheel.delta, mouse_wheel.steps)
			end			
		end
	end

	for _, level_object in pairs(self.objects) do
		if not level_object.hidden then
			local a, b, c = Script.temp_count()
			level_object:draw()
			level_object:draw_highlight()
			Script.set_temp_count(a, b, c)
		end
	end
	
	self:update_physics_simulation()
	self.tool:update(dt)

	local full_time = 1
	local fade_time = 0.5
	if self.flash_text and self.flash_age < full_time + fade_time then
		self.flash_age = self.flash_age + dt
		local size = 50
		local min, max = Gui.text_extents(LevelEditor.gui, self.flash_text, "core/editor_slave/gui/arial_df", size)
		local w,h = Application.resolution()
		local x = w/2 - (min.x + max.x)/2
		local y = h/2 - (min.z + max.z)/2
		local alpha = 255
		if self.flash_age > full_time + fade_time then
			alpha = 0
		elseif self.flash_age > full_time then
			alpha = 255 - 255*(self.flash_age - full_time)/fade_time
		end
		local m = 10
		Gui.rect(self.gui, Vector3(x+min.x-m,y+min.z-m,-1), Vector3(max.x-min.x+2*m,max.z-min.z+2*m,0), Color(alpha/4,0,0,0))
		Gui.text(self.gui, self.flash_text, "core/editor_slave/gui/arial_df", size, "arial_df", Vector3(x,y,0), Color(alpha, 255,255,255))
	end
	
	LineObject.dispatch(self.world, self.lines)
	LineObject.dispatch(self.world, self.lines_noz)
	
	if self.unit_preview then
		self.unit_preview:update(dt)
	end
	
	self.mouse.delta.x = 0
	self.mouse.delta.y = 0
	self.mouse.wheel.delta = 0
	self.mouse.wheel.steps = 0

	local tool_coords = self.tool.coordinates and self.tool:coordinates() or self:find_spawn_point(self.mouse.pos.x, self.mouse.pos.y)
	if not Vector3.is_valid(tool_coords) then tool_coords = nil end
	Application.console_send { type = "set_spawn_point", point = tool_coords or Vector3(0, 0, 0) }
end

function LevelEditor:render()
	--Application.update_render_world(self.world) 
	if Voxelizer then
	--	Voxelizer.voxelize(self.world)
	end

	ShadingEnvironment.blend(self.shading_environment, {"default", 1})
	ShadingEnvironment.apply(self.shading_environment)

	if not self.unit_preview or self.unit_preview.window then
		Application.render_world(self.world, self.camera, self.viewport, self.shading_environment)
	end
	if self.unit_preview then
		self.unit_preview:render(dt)
	end
end

function LevelEditor:spawned(objects)
	local data = {}
	for _,o in ipairs(objects) do
		data[#data + 1] = o:spawn_data()
	end
	Application.console_send { type = "spawned", data = data }
	LevelEditor.selection:send()
end

function LevelEditor:cloned(objects)
	local sources = {}
	local data = {}
	local new_ids = {}
	
	for _, o in ipairs(objects) do
		sources[#sources + 1] = o.duplication_source.id
		data[#data + 1] = o:spawn_data()
		new_ids[#new_ids + 1] = o.id
	end

	local scatter_instance_ids = Array.collect(new_ids, Func.method("instance_ids_for_unit", self.scatter_manager))
	local scatter_data = self.scatter_manager:scatter_data(scatter_instance_ids)
	Application.console_send { type = "cloned", sources = sources, data = data, scatter_data = scatter_data }
	LevelEditor.selection:send()
end

function LevelEditor:modified(objects)
	local data = {}
	for _,o in ipairs(objects) do
		data[#data + 1] = o:spawn_data()
	end
	Application.console_send { type = "modified", data = data }
end

function LevelEditor:spawn_level(id, resource_name, pos, rot, scl, pivot)
	local a, b, c = Script.temp_count()
	local lr = LevelReference(id, resource_name, pos, rot, scl, self.world)
	lr:set_local_pivot(pivot)
	self.objects[id] = lr
	Script.set_temp_count(a, b, c)
	self:enqueue_post_world_update_action(Func.method("complete_move", lr))
end

function LevelEditor:spawn_unit(id, type, pos, rot, scl, pivot, name, material)
	local a, b, c = Script.temp_count()
	local u = World.spawn_unit(self.world, type, pos, rot, material)
	local uo = UnitObject(u, id, type, name, material)
	uo:set_local_scale(scl)
	uo:set_local_pivot(pivot)
	Unit.set_id(u, id)
	self.objects[id] = uo
	Script.set_temp_count(a, b, c)
	self:enqueue_post_world_update_action(Func.method("complete_move", uo))
	if Voxelizer then
		Voxelizer.add_unit(self.world, u)		
	end	
	BakedLighting.add_unit(self.world, u)
end

function LevelEditor:spawn_note(id, pos, rot, scl, pivot, text, color, size)
	local a, b, c = Script.temp_count()
	local n = Note()
	n.id = id
	n.text = text
	n.color:store(color)
	n.size = size
	n:set_local_position(pos)
	n:set_local_rotation(rot)
	n:set_local_scale(scl)
	n:set_local_pivot(pivot)
	self.objects[n.id] = n
	Script.set_temp_count(a, b, c)
end

function LevelEditor:spawn_prototype(id, pos, rot, scl, pivot, color, radius, material, shape, visible)
	local a, b, c = Script.temp_count()
	local n = Prototype(id, pos, rot, scl, radius, material, shape, color, visible)
	n:set_local_pivot(pivot)
	self.objects[n.id] = n
	Script.set_temp_count(a, b, c)
end

function LevelEditor:spawn_group(id, pivot, children)
	local a, b, c = Script.temp_count()
	local n = Group(id, children)
	n:set_local_pivot(pivot)
	self.objects[n.id] = n
	
	Application.console_send {
		type = "group_pose",
		id = n.id,
		pos = n:local_position(),
		rot = n:local_rotation(),
		scl = n:local_scale(),
		pivot = n:local_pivot()
	}

	Script.set_temp_count(a, b, c)
end

function LevelEditor:spawn_marker(id, pos, rot, scl, pivot, name)
	local a, b, c = Script.temp_count()
	local n = Marker()
	n.id = id
	n.name = name
	n:set_local_position(pos)
	n:set_local_rotation(rot)
	n:set_local_scale(scl)
	n:set_local_pivot(pivot)
	self.objects[n.id] = n
	Script.set_temp_count(a, b, c)
end

function LevelEditor:spawn_trigger(id, pos, rot, scl, pivot, radius, name)
	local a, b, c = Script.temp_count()
	local n = Trigger(id, pos, rot, scl, radius, name)
	n:set_local_pivot(pivot)
	self.objects[n.id] = n
	Script.set_temp_count(a, b, c)
end

function LevelEditor:spawn_particle_effect(id, pos, rot, scl, pivot, effect, name)
	local a, b, c = Script.temp_count()
	local n = ParticleEffect()
	n.id = id
	n.effect = effect
	n.name = name
	n:set_local_position(pos)
	n:set_local_rotation(rot)
	n:set_local_scale(scl)
	n:set_local_pivot(pivot)
	self.objects[n.id] = n
	Script.set_temp_count(a, b, c)
end

function LevelEditor:spawn_sound(id, pos, rot, scl, pivot, event, name, shape, radius, range)
	local a, b, c = Script.temp_count()
	local n = Sound()
	n.id = id
	n.event = event
	n.name = name
	n.shape = shape
	n.shape_radius:store(radius)
	n.range = range
	n:set_local_position(pos)
	n:set_local_rotation(rot)
	n:set_local_scale(scl)
	n:set_local_pivot(pivot)
	self.objects[n.id] = n
	Script.set_temp_count(a, b, c)
end

function LevelEditor:spawn_spline(id, pos, rot, scl, pivot, name, points, color)
	local a, b, c = Script.temp_count()
	local n = Spline()
	n.id = id
	n.name = name
	
	for i, p in ipairs(points) do
		n.points[i] = Vector3Boxed(p)
	end

	n.color:store(color)
	n:set_local_position(pos)
	n:set_local_rotation(rot)
	n:set_local_scale(scl)
	n:set_local_pivot(pivot)
	self.objects[n.id] = n
	Script.set_temp_count(a, b, c)
end

function LevelEditor:spawn_navmesh(id)
	local a, b, c = Script.temp_count()
	local n = Navmesh()
	n.id = id
	self.objects[n.id] = n

	if self.tool == self.navmesh_tool then
		self.navmesh_tool:activate(id)
	end
	Script.set_temp_count(a, b, c)
end

function LevelEditor:spawn_volume(id, type, pos, rot, scl, pivot, name, points, cap_triangulation, color, top, bottom)
	local a, b, c = Script.temp_count()
	local volume = Volume.create(id, type, pos, rot, scl, name, points, cap_triangulation, color, top, bottom)
	volume:set_local_pivot(pivot)
	self.objects[volume.id] = volume
	Script.set_temp_count(a, b, c)
end

function LevelEditor:set_volume_type(type, color)
	self.volume_tool.volume_type = type
	self.volume_tool.color = QuaternionBox(color)
end

function LevelEditor:unspawn(id)
	assert(Validation.is_object_id(id))

	if self._hovered_object_id == id then
		self:set_hovered_object(nil)
	end

	local level_object = self.objects[id]
	
	if level_object ~= nil then
		level_object:destroy()
	end
	
	if self.selection:includes(id) then
		self.selection:remove(id)
		self.selection:send()
	end
end

function LevelEditor:set_mouse_state(x, y, left, right, middle)
	assert(type(x) == "number")
	assert(type(y) == "number")
	assert(type(left) == "boolean")
	assert(type(right) == "boolean")
	assert(type(middle) == "boolean")
	self.mouse.pos.x = x
	self.mouse.pos.y = y
	self.mouse.buttons.left = left
	self.mouse.buttons.right = right
	self.mouse.buttons.middle = middle
end

function LevelEditor:mouse_wheel(delta)
	local mouse_wheel = self.mouse.wheel
	mouse_wheel.delta = mouse_wheel.delta + delta
	mouse_wheel.steps = mouse_wheel.steps + (delta < 0 and -1 or 1)
end

function LevelEditor:mouse_outside()
	self.mouse.over = false
	self:set_hovered_object(nil)
end

function LevelEditor:mouse_down(x, y)
	assert(type(x) == "number")
	assert(type(y) == "number")
	self.mouse.down.x = x
	self.mouse.down.y = y
	self.tool:mouse_down(x, y)
end

function LevelEditor:mouse_move(x, y, dx, dy)
	self.mouse.over = true
	self.mouse.delta.x = self.mouse.delta.x + dx
	self.mouse.delta.y = self.mouse.delta.y + dy
end

function LevelEditor:mouse_up(x, y)
	self.tool:mouse_up(x, y)
end

function LevelEditor:mouse_spawn()
	local mouse_pos = self.mouse.pos

	if self.tool.mouse_spawn then
		self.tool:mouse_spawn(mouse_pos.x, mouse_pos.y)
	else
		self.place_tool:mouse_spawn(mouse_pos.x, mouse_pos.y)
	end
end

function LevelEditor:find_spawn_point(x, y)
	local snapped_point, unsnapped_point = GridPlane.snap_mouse(Matrix4x4.identity(), self._spawn_plane_height, x, y)
	local spawn_point = self:is_snap_to_grid_enabled() and snapped_point or unsnapped_point
	return spawn_point
end

function LevelEditor:move_scene_element(scene_element_ref, pos, rot, scl)
	local object_id, component_id = SceneElementRef.unpack(scene_element_ref)
	local level_object = self.objects[object_id]
	level_object:set_local_position(pos, component_id)
	level_object:set_local_rotation(rot, component_id)
	level_object:set_local_scale(scl, component_id)
	self:enqueue_post_world_update_action(Func.method("complete_move", level_object))
end

function LevelEditor:move_pivot(scene_element_ref, pivot)
	local object_id, component_id = SceneElementRef.unpack(scene_element_ref)
	local level_object = self.objects[object_id]
	level_object:set_local_pivot(pivot)
end

function LevelEditor:reference_system()
	return self._reference_system
end

function LevelEditor:set_reference_system(mode)
	assert(mode == "Local" or mode == "World")
	self._reference_system = mode
end

function LevelEditor:grid_pose(tm)
	local mode = self._snap_mode
	assert(mode == "Relative" or mode == "Absolute")
	local grid_pose = Matrix4x4.copy(tm)

	if mode == "Absolute" then
		Matrix4x4.set_translation(grid_pose, Vector3(0, 0, 0))
	end

	return grid_pose
end

function LevelEditor:set_snap_enabled(grid, surface, point)
	assert(type(grid) == "boolean")
	assert(type(surface) == "boolean")
	assert(type(point) == "boolean")
	self._is_snap_to_grid_enabled = grid
	self._is_snap_to_surface_enabled = surface
	self._is_snap_to_point_enabled = point
	local mouse_pos = self.mouse.pos
	self.tool:mouse_move(mouse_pos.x, mouse_pos.y)
end

function LevelEditor:snap_mode()
	return self._snap_mode
end

function LevelEditor:set_snap_mode(mode)
	assert(mode == "Relative" or mode == "Absolute")
	self._snap_mode = mode
end

function LevelEditor:set_grid_size(size)
	assert(type(size) == "number")
	self.grid.size = size
end

function LevelEditor:set_grid_visualization_at_origin(enabled)
	assert(type(enabled) == "boolean")
	self.grid.is_visible_at_origin = enabled
end

function LevelEditor:set_is_control_key_used_to_move_along_axis_plane(enabled)
	assert(type(enabled) == "boolean")
	self.settings.is_control_key_used_to_move_along_axis_plane = enabled
end

function LevelEditor:set_rotation_snap(snap)
	assert(type(snap) == "number")
	self.grid.rotation_snap = snap
end

function LevelEditor:camera_ray(x, y)
	return self.editor_camera:camera_ray(x, y)
end

function LevelEditor.world_to_screen(world_point)
	return Camera.world_to_screen(LevelEditor.camera, world_point)
end

function LevelEditor:key(key)
	if self.selection:count() > 0 then
		if key == "move_down" then self.move_tool:keyboard_move(Vector3(0, 0, -1)) end
		if key == "move_up" then self.move_tool:keyboard_move(Vector3(0, 0, 1)) end
		if key == "move_left" then self.move_tool:keyboard_move(Vector3(-1, 0, 0)) end
		if key == "move_right" then self.move_tool:keyboard_move(Vector3(1, 0, 0)) end
		if key == "move_back" then self.move_tool:keyboard_move(Vector3(0, -1, 0)) end
		if key == "move_forward" then self.move_tool:keyboard_move(Vector3(0, 1, 0)) end
		
		if key == "rotate_ccw_x" then self.rotate_tool:keyboard_rotate(Vector3(1, 0, 0)) end
		if key == "rotate_cw_x" then self.rotate_tool:keyboard_rotate(Vector3(-1, 0, 0)) end
		if key == "rotate_cw_y" then self.rotate_tool:keyboard_rotate(Vector3(0,-1, 0)) end
		if key == "rotate_ccw_y" then self.rotate_tool:keyboard_rotate(Vector3(0, 1, 0)) end
		if key == "rotate_ccw_z" then self.rotate_tool:keyboard_rotate(Vector3(0, 0, 1)) end
		if key == "rotate_cw_z" then self.rotate_tool:keyboard_rotate(Vector3(0, 0, -1)) end
		
		if key == "hover_align_selected_objects" then self:hover_align_selected_objects() end
	end
	
	if key == "hover_pick_placeable" then self:hover_pick_placeable() end
	if self.tool.key then self.tool:key(key) end
end

function LevelEditor:frame_hovered_object()
	local hovered_object = self:hovered_object()
	
	if hovered_object ~= nil then 
		self:frame_objects({ hovered_object.id }, 0)
	end
end

function LevelEditor:frame_objects(object_ids, min_radius)
	local level_objects = Array.map(object_ids, Func.of_table(self.objects))
	local merged_pose, merged_radius = self:oobb_for_framing(level_objects)
	if merged_pose == nil then return end

	local max_radius = #object_ids == 1 and 30 or 10000
	local min_r = Vector3(min_radius, min_radius, min_radius)
	local max_r = Vector3(max_radius, max_radius, max_radius)
	local framed_radius = Vector3.max(min_r, Vector3.min(merged_radius, max_r))
	self.editor_camera:frame_oobb(merged_pose, framed_radius)

	-- The camera will pan to reveal the objects.
	-- We don't want the hovered object indicator to show during the pan.
	self:set_hovered_object(nil)
end

function LevelEditor:oobb_for_framing(level_objects)
	-- Special case for landscape units:
	-- If we request to frame a single landscape, frame a
	-- point on the landscape instead of its bounding box.
	local function is_landscape_unit_object(level_object)
		local unit = level_object._unit
		return Unit.alive(unit) and Unit.num_landscapes(unit) > 0
	end

	local function calc_object_oobb(level_object, override_world_position)
		local pose, radius

		if is_landscape_unit_object(level_object) then
			pose = Matrix4x4.from_translation(level_object:world_pivot())
			radius = Vector3(10, 10, 10)
		else
			pose, radius = level_object:box()
		end

		if override_world_position ~= nil then
			pose = Matrix4x4.from_translation(override_world_position)
		end

		return pose, radius
	end

	if self.mouse.over and #level_objects == 1 and is_landscape_unit_object(level_objects[1]) then
		-- We've requested to frame a single landscape unit.
		-- Try to find an intersection point at the last known mouse position.
		-- if the mouse is not hovering the landscape, center the camera on
		-- the landscape origin, to show the manipulator.
		local ray_start, ray_dir = self:camera_ray(self.mouse.pos.x, self.mouse.pos.y)
		local ray_length = self.editor_camera:far_range()
		local hit_object, distance_along_ray = visual_raycast(level_objects, ray_start, ray_dir, ray_length)

		if hit_object == level_objects[1] then
			return calc_object_oobb(level_objects[1], ray_start + ray_dir * distance_along_ray)
		end
	end

	local oobb_pose, oobb_radius = OOBB.merged_box(level_objects, calc_object_oobb)
	return oobb_pose, oobb_radius
end

function LevelEditor:set_placeable(placeable_type, resource_id)
	assert(placeable_type == nil or placeable_type == "Unit" or placeable_type == "ParticleEffect" or placeable_type == "Sound")
	assert(resource_id == nil or type(resource_id) == "string")
	self.place_tool:set_placeable(placeable_type, resource_id)
end

function LevelEditor:hover_pick_placeable()
	local hovered_object = self:hovered_object()
	
	if hovered_object ~= nil then
		local kind = kind_of(hovered_object)

		if kind == UnitObject then
			Application.console_send { type = "set_placeable", placeable_type = "Unit", resource_id = hovered_object:type() }
		elseif kind == ParticleEffect then
			Application.console_send { type = "set_placeable", placeable_type = "ParticleEffect", resource_id = hovered_object.effect }
		elseif kind == Sound then
			Application.console_send { type = "set_placeable", placeable_type = "Sound", resource_id = hovered_object.sound }
		end
	end
end

function LevelEditor:hover_align_selected_objects()
	local hovered_object = self:hovered_object()
	
	if hovered_object ~= nil then
		self:flash("Align")
		local rotation = hovered_object:world_rotation(component_id)
		local position = hovered_object:world_pivot(component_id)
		self.selection:align_to(position, rotation)
	end
end

function LevelEditor:align_selected_objects_to_floor(floor_object_id)
	local floor_object = self.objects[floor_object_id]
	self.selection:align_to_floor(floor_object)
end

function LevelEditor:set_text(id, text)
	self.objects[id].text = text
end

function LevelEditor:flash(s)
	self.flash_text = s
	self.flash_age = 0
end

function LevelEditor:send_unit_node_info(unit_resource, node_names)
	assert(type(unit_resource) == "string")
	assert(type(node_names) == "table")
	self:_store_unit_node_names(unit_resource, node_names)

	local function get_unit_node_info(node_name)
		if not UnitResource.has_node(unit_resource, node_name) then
			return nil
		end

		local node_id = UnitResource.node(unit_resource, node_name)
		local pose = UnitResource.local_pose(unit_resource, node_id)
		
		local info = {
			pos = Matrix4x4.translation(pose),
			rot = Matrix4x4.rotation(pose),
			scl = Matrix4x4.scale(pose)
		}

		return info
	end

	local info_by_node_name = Dict.of_array(node_names, Func.id, get_unit_node_info)

	local message = {
		type = "unit_node_info",
		unit = unit_resource,
		nodes = info_by_node_name
	}

	Application.console_send(message)
end

function LevelEditor:_store_unit_node_names(unit_resource, node_names)
	local function get_node_id(_, node_name)
		if UnitResource.has_node(unit_resource, node_name) then
			return UnitResource.node(unit_resource, node_name), node_name
		else
			return nil, nil
		end
	end

	local node_names_by_node_id = Dict.remap(node_names, get_node_id)
	self._unit_node_names[unit_resource] = node_names_by_node_id
end

function LevelEditor:get_unit_node_names(unit_resource)
	assert(type(unit_resource) == "string")
	local node_names_by_node_id = self._unit_node_names[unit_resource]
	assert(node_names_by_node_id ~= nil) -- Must exist, since send_unit_node_info() is called before the first instance of a unit is spawned.
	return node_names_by_node_id
end

function LevelEditor:reload_unit(source_dir, data_dir, unit_type)
	local units = {}
	local pos = {}
	local rot = {}
	local scl = {}
	local pivot = {}
	local type = {}
	local name = {}
	local material = {}

	-- Save all units
	-- TODO: Save component tweak state.
	for id, o in pairs(self.objects) do
		if kind_of(o) == UnitObject and o:type() == unit_type then
			units[#units+1] = id
			pos[id] = o:local_position()
			rot[id] = o:local_rotation()
			scl[id] = o:local_scale()
			pivot[id] = o:local_pivot()
			type[id] = o:type()
			name[id] = o.name
			material[id] = o:material()
		end
	end
	
	-- Delete them
	for _, id in ipairs(units) do
		if Voxelizer then		
			Voxelizer.remove_unit(LevelEditor.world, self.objects[id]._unit)			
		end			
		World.destroy_unit(LevelEditor.world, self.objects[id]._unit)
	end
	
	if self.unit_preview then
		self.unit_preview:unspawn()
	end
	
	-- Unload all unit data here
	Application.reload_autoloaded_dependencies(source_dir, data_dir, "unit", unit_type)

	-- Respawn the units
	for _, id in ipairs(units) do
		local o = self.objects[id]
		local unit = World.spawn_unit(LevelEditor.world, type[id], pos[id], rot[id], material[id])
		Unit.set_id(unit, id)
		o:init(unit, id, type[id], name[id], material[id])
		o:set_local_scale(scl[id])
		o:set_local_pivot(pivot[id])
		o:highlight_changed()
		self:enqueue_post_world_update_action(Func.method("complete_move", o))
		if Voxelizer then
			Voxelizer.add_unit(LevelEditor.world, unit)			
		end		
		BakedLighting.add_unit(LevelEditor.world, unit)

	end
	
	if self.unit_preview then
		self.unit_preview:respawn()
	end
end

function LevelEditor:set_light(id, light_name, properties)
	p = properties
	local unit = self.objects[id]._unit
	local light = Unit.light(unit, light_name)
	Light.set_type(light, properties.type)
	Light.set_falloff_start(light, properties.falloff_start)
	Light.set_falloff_end(light, properties.falloff_end)
	Light.set_color(light, properties.color)
	Light.set_falloff_exponent(light, properties.falloff_exponent)
	Light.set_spot_angle_start(light, properties.spot_angle_start)
	Light.set_spot_angle_end(light, properties.spot_angle_end)
	Light.set_casts_shadows(light, properties.casts_shadows)
	Unit.set_light_material(unit, light, properties.material)	
end

function LevelEditor:set_snap_points(unit, points)
	self.snap_points[unit] = points
end

function LevelEditor:set_visible(id, visible)
	self.objects[id]:set_visible(visible)
end

function LevelEditor:set_selectable(id, selectable)
	self.objects[id]:set_selectable(selectable)
end

function LevelEditor:open_unit_preview(handle)
	if self.unit_preview then
		self.unit_preview:close()
	end
	self.unit_preview = UnitPreview(handle)
end

function LevelEditor:close_unit_preview()
	if self.unit_preview then
		self.unit_preview:close()
	end
	self.unit_preview = nil
end

function LevelEditor:preview_unit(unit, material)
	if self.unit_preview then
		self.unit_preview:preview_unit(unit, material)
	end
end

function LevelEditor:preview_particle_effect(effect)
	if self.unit_preview then
		self.unit_preview:preview_particle_effect(effect)
	end
end

function LevelEditor:preview_sound(sound)
	if self.unit_preview then
		self.unit_preview:preview_sound(sound)
	end
end

function LevelEditor:set_preview_option(option, value)
	if self.unit_preview then
		self.unit_preview:set_option(option, value)
	end
end

function LevelEditor:unselect_unselectable()
	local new_selection = Array.filter(LevelEditor.selection:scene_element_refs(), SceneElementRef.is_selectable)
	self.selection:set(new_selection)
	self.selection:send()
end

function LevelEditor:is_axis_plane_modifier_held()
	return self.settings.is_control_key_used_to_move_along_axis_plane and self.modifiers.control
end

function LevelEditor:is_multi_select_modifier_held()
	return self.modifiers.shift == true
end

function LevelEditor:is_clone_modifier_held()
	return self.modifiers.shift == true
end

function LevelEditor:is_angle_snap_enabled()
	return self._is_snap_to_grid_enabled and not self.modifiers.snap_off
end

function LevelEditor:is_snap_to_grid_enabled()
	return self._is_snap_to_grid_enabled and not self.modifiers.snap_off
end

function LevelEditor:is_snap_to_surface_enabled()
	return self._is_snap_to_surface_enabled and not self.modifiers.snap_off
end

function LevelEditor:is_snap_to_point_enabled()
	return self._is_snap_to_point_enabled and not self.modifiers.snap_off
end

function LevelEditor:draw_grid_plane(grid_origin_pose, support_absolute_grid, fade_center, axes)
	local intensity = self:is_snap_to_grid_enabled() and 200 or 64
	local color = Color(intensity, 255, 255, 255)
	local grid_pose = support_absolute_grid and LevelEditor:grid_pose(grid_origin_pose) or grid_origin_pose
	GridPlane.draw(self.lines, color, grid_pose, fade_center, axes)
end

function LevelEditor:snap_function(grid_origin_pose, support_absolute_grid, excluded_ids_set)
	local is_snap_to_grid_enabled = self:is_snap_to_grid_enabled()
	local is_snap_to_surface_enabled = self:is_snap_to_surface_enabled()
	local is_snap_to_point_enabled = self:is_snap_to_point_enabled()
	local is_snap_enabled = is_snap_to_grid_enabled or is_snap_to_surface_enabled or is_snap_to_point_enabled

	if not is_snap_enabled then
		return nil
	end

	local function snap(offset, from_point)
		local nv, nq, nm = Script.temp_count()
		local candidate_snapped_offsets = {}
		local unsnapped_point = from_point + offset

		if is_snap_to_grid_enabled then
			local grid_pose = support_absolute_grid and LevelEditor:grid_pose(grid_origin_pose) or grid_origin_pose
			local snapped_offset = GridPlane.snap_offset(grid_pose, offset, from_point)
			local correction_length = Vector3.distance(from_point + snapped_offset, unsnapped_point)
			candidate_snapped_offsets[snapped_offset] = correction_length
		end

		if is_snap_to_surface_enabled or is_snap_to_point_enabled then
			local mouse_pos = self.mouse.pos
			local cam_pos, cam_dir = self:camera_ray(mouse_pos.x, mouse_pos.y)
			local ray_length = self.editor_camera:far_range()
			local snappable_objects = Nilable.fold(excluded_ids_set, self.objects, Dict.exclude)
			local snap_object, distance_along_ray = visual_raycast(snappable_objects, cam_pos, cam_dir, ray_length)

			if is_snap_to_surface_enabled then
				local snap_to_surface_candidate =
					Nilable.map(snap_object, function() return cam_pos + cam_dir * distance_along_ray end)

				if snap_to_surface_candidate ~= nil then
					local snapped_offset = snap_to_surface_candidate - from_point
					local correction_length = Vector3.distance(from_point + snapped_offset, unsnapped_point)
					candidate_snapped_offsets[snapped_offset] = correction_length
				end
			end

			if is_snap_to_point_enabled then
				local snap_to_point_candidate =
					Nilable.try_invoke(snap_object, "closest_mesh_point_to_ray", cam_pos, cam_dir, ray_length)

				if snap_to_point_candidate ~= nil then
					local snapped_offset = snap_to_point_candidate - from_point
					local correction_length = Vector3.distance(from_point + snapped_offset, unsnapped_point)
					candidate_snapped_offsets[snapped_offset] = correction_length
				end
			end
		end
		
		local best_snapped_offset = Dict.min(candidate_snapped_offsets)
		local x, y, z = Vector3.to_elements(best_snapped_offset or Vector3(0, 0, 0))
		Script.set_temp_count(nv, nq, nm)
		return Vector3(x, y, z)
	end

	return snap
end

function LevelEditor:begin_physics_simulation(unit_object_ids)
	if self._active_physics_simulation ~= nil then
		self:_end_physics_simulation()
	end

	local scene_element_refs, start_poses = PhysicsSimulation.begin_simulation(unit_object_ids)
	assert(#scene_element_refs == #start_poses)

	if #scene_element_refs > 0 then
		self._active_physics_simulation = { scene_element_refs = scene_element_refs, start_poses = start_poses }
		print("Physics simulation started.")
	end
end

function LevelEditor:update_physics_simulation()
	if self._active_physics_simulation ~= nil then
		self._active_physics_simulation.scene_element_refs, self._active_physics_simulation.start_poses = 
			PhysicsSimulation.remove_deleted_units(self._active_physics_simulation.scene_element_refs, self._active_physics_simulation.start_poses)
		local unit_object_ids = Array.map(self._active_physics_simulation.scene_element_refs, SceneElementRef.object_id):distinct()

		if not PhysicsSimulation.is_simulation_running(unit_object_ids) then
			print("Physics simulation finished.")
			self:_end_physics_simulation()
		end
	end
end

function LevelEditor:abort_physics_simulation()
	if self._active_physics_simulation ~= nil then
		print("Physics simulation aborted.")
		self:_end_physics_simulation()
	end
end

function LevelEditor:_end_physics_simulation()
	assert(self._active_physics_simulation ~= nil)
	PhysicsSimulation.end_simulation(self._active_physics_simulation.scene_element_refs, self._active_physics_simulation.start_poses)
	self._active_physics_simulation = nil
end

function LevelEditor:raise_highlight_changed()
	local raise_highlight_changed = Func.method("highlight_changed")
	Array.iter(self.selection:objects(), raise_highlight_changed)
	Nilable.iter(self:hovered_object(), raise_highlight_changed)
end

function LevelEditor:object_highlight_color(level_object)
	assert(level_object ~= nil)

	if level_object.hidden then
		return nil
	end

	if self.editor_camera:is_controlled_by_mouse() then
		return nil
	end

	if self.tool.is_highlight_suppressed and self.tool:is_highlight_suppressed() then
		return nil
	end

	-- The object should be highlighted.
	-- If the object is a landscape unit we don't draw the hover highlight, since it can be quite distracting.
	local highlighted_object = self:_find_root_object(level_object)
	local is_landscape_unit_object = Unit.alive(highlighted_object._unit) and Unit.num_landscapes(highlighted_object._unit) > 0
	local use_hover_highlight = not is_landscape_unit_object
	local hover_color = (use_hover_highlight and highlighted_object.id == self._hovered_object_id)
	  and LevelEditor.colors.hovered()
	   or nil

	local selection_color = nil

	if self.selection:includes(highlighted_object.id) then
		local is_last_selected = self.selection:last_selected_object() == highlighted_object
		selection_color = is_last_selected and LevelEditor.colors.last_selected() or LevelEditor.colors.selected()
	end

	if hover_color ~= nil then
		return selection_color ~= nil
		   and Blend.color_with_color(selection_color, hover_color, 0.3125)
		    or Blend.color_with_alpha(hover_color, 80)
	end

	return selection_color
end

function LevelEditor:_find_root_object(level_object)
	local parent_id = level_object.parent_id

	if parent_id == nil then
		return level_object
	end

	local parent_object = LevelEditor.objects[parent_id]
	assert(parent_object ~= nil)
	return self:_find_root_object(parent_object)
end

function LevelEditor:view_perspective()
	self.editor_camera:set_perspective()
	self:set_background_visibility(true)
end

function LevelEditor:view_top()
	self:_view_orthographic(Vector3(0, 0, -1), Vector3(0, 1, 0))
end

function LevelEditor:view_front()
	self:_view_orthographic(Vector3(0, -1, 0), Vector3(0, 0, 1))
end

function LevelEditor:view_back()
	self:_view_orthographic(Vector3(0, 1, 0), Vector3(0, 0, 1))
end

function LevelEditor:view_right()
	self:_view_orthographic(Vector3(-1, 0, 0), Vector3(0, 0, 1))
end

function LevelEditor:view_left()
	self:_view_orthographic(Vector3(1, 0, 0), Vector3(0, 0, 1))
end

function LevelEditor:_view_orthographic(front, up)
	local world_center, world_radius = visible_world_aabb()
	local focus_point = find_focus_point(self.camera) or Vector3(0, 0, 0)
	self.editor_camera:set_orthographic(world_center, world_radius, focus_point, front, up)
	self:set_background_visibility(false)
end

function LevelEditor:set_camera_control_style(style)
	self.editor_camera:set_control_style(style, self.mouse.pos);
end
