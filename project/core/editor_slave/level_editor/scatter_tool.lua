--------------------------------------------------
-- Utility functions
--------------------------------------------------

local function is_erase_modifier_held()
	return LevelEditor.modifiers.control == true
end

local function is_only_erase_current_brush_modifier_held()
	return LevelEditor.modifiers.shift == true 
end

local function is_sharpness_adjust_modifier_held()
	return LevelEditor.modifiers.shift == true
end

local function is_unit_object(level_object)
	return kind_of(level_object) == UnitObject
end

local function to_storable_brush_component(brush_component)
	assert(type(brush_component.unit) == "string")
	assert(brush_component.normal == nil or type(brush_component.normal) == "userdata")
	assert(brush_component.frequency > 0)
	
	return {
		unit = brush_component.unit,
		normal = Nilable.map(brush_component.normal, Vector3Box),
		frequency = brush_component.frequency
	}
end

local visual_raycast = Func.partial(Picking.raycast, Func.all{is_unit_object, Picking.is_visible_and_not_in_group})

local function visual_unit_raycast(ray_start, ray_dir, ray_length)
	local unit_object, distance_along_ray, normal = visual_raycast(LevelEditor.objects, ray_start, ray_dir, ray_length)

	if unit_object == nil then
		return nil, nil, nil
	else
		local point = ray_start + ray_dir * distance_along_ray
		return unit_object, point, normal
	end
end

local function draw_axes(position, rotation, radius, alpha)
	local lines = LevelEditor.lines
	local x_axis = Quaternion.right(rotation)
	local y_axis = Quaternion.forward(rotation)
	local z_axis = Quaternion.up(rotation)
	LineObject.add_line(lines, Color(alpha, 255, 0, 0), position, position + x_axis * radius)
	LineObject.add_line(lines, Color(alpha, 0, 255, 0), position, position + y_axis * radius)
	LineObject.add_line(lines, Color(alpha, 0, 0, 255), position, position + z_axis * radius)
end

local function draw_brush(color, position, rotation, radius, sharpness)
	sharpness = sharpness or 1

	local lines = LevelEditor.lines
	local camera = LevelEditor.camera
	local camera_pose = Camera.world_pose(camera)
	local camera_forward = Matrix4x4.y(camera_pose)
	local camera_up = Matrix4x4.z(camera_pose)
	local inner_radius = radius * sharpness
	local ip = position - camera_forward * radius
	local op = ip - camera_forward * inner_radius

	local wts = Camera.world_to_screen
	local inner_pixel_height = 1 / Vector3.distance(wts(camera, ip), wts(camera, ip + camera_up))
	local outer_pixel_height = 1 / Vector3.distance(wts(camera, op), wts(camera, op + camera_up))
	local _, r, g, b = Quaternion.to_elements(color)

	LineObject.add_sphere(lines, Color(51, 0, 0, 0), position - camera_up * inner_pixel_height, inner_radius, 40, 8)
	LineObject.add_sphere(lines, Color(51, r, g, b), position, inner_radius, 40, 8)

	if sharpness < 1 then
		LineObject.add_sphere(lines, Color(20, 0, 0, 0), position - camera_up * outer_pixel_height, radius, 40, 8)
		LineObject.add_sphere(lines, Color(20, r, g, b), position, radius, 40, 8)
	end
end

function draw_unit_mesh(unit_resource_id, position, rotation)
	if unit_resource_id ~= nil then
		local lines = LevelEditor.lines
		local pose = Matrix4x4.from_quaternion_position(rotation, position)
		LineObject.add_unit_meshes(lines, unit_resource_id, Color(40, 200, 255, 255), pose)
	end
end


--------------------------------------------------
-- ScatterTool
--------------------------------------------------

ScatterTool = class(ScatterTool, Tool)
ScatterTool.Behaviors = ScatterTool.Behaviors or {}
local Behaviors = ScatterTool.Behaviors

function ScatterTool.rotation_from_normal(normal, pose)
	local local_z_axis = Matrix4x4.transform_without_translation(Matrix4x4.inverse(pose), normal)
	local local_x_axis, local_y_axis = Vector3.make_axes(local_z_axis)
	local x_axis = Matrix4x4.transform_without_translation(pose, local_x_axis)
	local y_axis = Matrix4x4.transform_without_translation(pose, local_y_axis)
	local z_axis = Matrix4x4.transform_without_translation(pose, local_z_axis)
	local rotated_pose = Matrix4x4.from_axes(x_axis, y_axis, z_axis, Vector3.zero())
	local rotation = Quaternion.from_matrix4x4(rotated_pose)
	return rotation
end

function ScatterTool.vary_rotation(rotation)
	local up_axis = Vector3(0, 0, 1)
	local random_angle = Math.random() * math.pi * 2
	local delta_rotation = Quaternion.axis_angle(up_axis, random_angle)
	local rotation_variation = Quaternion.multiply(rotation, delta_rotation)
	return rotation_variation
end

function ScatterTool:init(scatter_manager)
	assert(kind_of(scatter_manager) == ScatterManager)
	self._scatter_manager = scatter_manager
	self._is_brush_point_valid = false
	self._brush_point = Vector3Box()
	self._brush_rotation = QuaternionBox()
	self._brush_radius = 3
	self._brush_sharpness = 0.75
	self._brush_components = {}
	self._scatter_speed = 60
	self._behavior = Behaviors.Idle()
end

function ScatterTool:on_selected()
	if self._behavior.on_selected ~= nil then
		self._behavior:on_selected(self)
	end
end

function ScatterTool:coordinates()
	return self._is_brush_point_valid and self:brush_point() or nil
end

function ScatterTool:update(dt)
	if self._behavior.update ~= nil then
		self._behavior:update(self, dt)
	end
end

function ScatterTool:mouse_down(x, y)
	if self._behavior.mouse_down ~= nil then
		self._behavior:mouse_down(self, x, y)
	end
end

function ScatterTool:mouse_move(x, y)
	if self._behavior.mouse_move ~= nil then
		self._behavior:mouse_move(self, x, y)
	end
end

function ScatterTool:mouse_up(x, y)
	if self._behavior.mouse_up ~= nil then
		self._behavior:mouse_up(self, x, y)
	end
end

function ScatterTool:mouse_wheel(delta, steps)
	local multiplier = steps < 0 and 1 / 1.2 or 1.2

	if is_sharpness_adjust_modifier_held() and not is_erase_modifier_held() then
		if self._brush_sharpness == 0 then
			if steps > 0 then
				self._brush_sharpness = 0.01
			end
		else
			self._brush_sharpness = math.min(math.max(0, self._brush_sharpness * multiplier), 1)
		end

		assert(self._brush_sharpness >= 0 and self._brush_sharpness <= 1)
	else
		self._brush_radius = math.max(0.01, self._brush_radius * multiplier)
		assert(self._brush_radius > 0)
	end
end

function ScatterTool:brush_point()
	-- Center of the brush in world space.
	assert(self._is_brush_point_valid)
	return self._brush_point:unbox()
end

function ScatterTool:brush_rotation()
	-- Rotation required to align spawned units to the painted surface normal.
	assert(self._is_brush_point_valid)
	return self._brush_rotation:unbox()
end

function ScatterTool:brush_radius()
	-- Outer radius of the brush.
	assert(self._brush_radius > 0)
	return self._brush_radius
end

function ScatterTool:eraser_radius()
	return self:brush_radius() * self:brush_sharpness()
end

function ScatterTool:brush_sharpness()
	-- Percentage of the brush that is scattering at full intensity.
	assert(self._brush_sharpness >= 0 and self._brush_sharpness <= 1)
	return self._brush_sharpness
end

function ScatterTool:scatter_speed()
	-- Number of scattered instances per second.
	assert(self._scatter_speed > 0)
	return self._scatter_speed
end

function ScatterTool:set_scatter_speed(instances_per_second)
	assert(instances_per_second > 0)
	self._scatter_speed = instances_per_second
end

function ScatterTool:set_scatter_brush_components(brush_components)
	self._brush_components =
		Array.map(brush_components, to_storable_brush_component)
			 :sort_by(Func.property("frequency"))
end

function ScatterTool:_can_scatter()
	return self._is_brush_point_valid
	   and #self._brush_components > 0
end

function ScatterTool:_can_erase()
	return self._is_brush_point_valid
end

function ScatterTool:_spawn_scattered_unit(owning_unit, position, rotation, scattered_unit_resource_id)
	assert(self:_can_scatter())
	assert(is_unit_object(owning_unit))
	assert(type(owning_unit.id) == "string")
	assert(type(scattered_unit_resource_id) == "string")
	local component_id = nil -- TODO: Support scatter onto unit components.
	local local_position, local_rotation = owning_unit:to_local_position_and_rotation(position, rotation, component_id)
	local instance_id = self._scatter_manager:new_instance_id()
	self._scatter_manager:spawn(owning_unit.id, scattered_unit_resource_id, local_position, local_rotation, instance_id)
	return instance_id
end

function ScatterTool:_unspawn_scattered_units_inside_sphere(position, radius)
	assert(self:_can_erase())
	local should_unspawn = is_only_erase_current_brush_modifier_held()
	  and Func.compose(Func.method("unit_resource_id", self._scatter_manager), Func.partial(Set.contains, Set.of_array(self._brush_components, Func.property("unit"))))
	   or Func.constantly(true)

	local instance_ids = self._scatter_manager:instance_ids_inside_sphere(position, radius):filter(should_unspawn)

	for _, instance_id in ipairs(instance_ids) do
		self._scatter_manager:unspawn(instance_id)
	end

	return instance_ids
end

function ScatterTool:_draw_brush()
	if not self._is_brush_point_valid then return end
	local position = self:brush_point()
	local rotation = self:brush_rotation()
	local brush_radius = self:brush_radius()
	local brush_sharpness = self:brush_sharpness()
	draw_axes(position, rotation, 1, 75)
	draw_brush(Color(255, 255, 255), position, rotation, brush_radius, brush_sharpness)
end

function ScatterTool:_draw_eraser()
	if not self._is_brush_point_valid then return end
	local position = self:brush_point()
	local eraser_radius = self:eraser_radius()
	local eraser_color = is_only_erase_current_brush_modifier_held() and Color(255, 180, 180) or Color(255, 80, 80)
	draw_brush(eraser_color, position, Quaternion.identity(), eraser_radius)
end

function ScatterTool:_resolve_normal(brush_component, surface_normal)
	if brush_component == nil then
		return surface_normal
	end

	local override_normal = brush_component.normal

	if override_normal == nil then
		return surface_normal
	end

	return override_normal:unbox()
end

function ScatterTool:_pick_brush_point(x, y)
	local cam_pos, cam_dir = LevelEditor:camera_ray(x, y)
	local ray_length = LevelEditor.editor_camera:far_range()
	local owning_unit, brush_point, brush_normal = visual_unit_raycast(cam_pos, cam_dir, ray_length)
	
	if owning_unit == nil then
		self._is_brush_point_valid = false
		return nil, nil, nil, nil
	end

	local brush_component = self:_random_brush_component()
	local normal = self:_resolve_normal(brush_component, brush_normal)
	local brush_rotation = ScatterTool.rotation_from_normal(normal, owning_unit:local_pose())
	self._brush_point:store(brush_point)
	self._brush_rotation:store(brush_rotation)
	self._is_brush_point_valid = true
	local scattered_unit_resource_id = Nilable.map(brush_component, Func.property("unit"))
	assert(scattered_unit_resource_id == nil or type(scattered_unit_resource_id) == "string")
	return owning_unit, brush_point, brush_rotation, scattered_unit_resource_id
end

function ScatterTool:_random_point_inside_brush()
	local brush_point = self:brush_point()
	local brush_radius = self:brush_radius()
	local brush_sharpness = self:brush_sharpness()
	local random_point_inside = Sphere.random_point_inside(brush_point, brush_radius)

	local inner_radius = brush_radius * brush_sharpness
	local penumbra_distance = brush_radius - inner_radius
	local accepted_radius = inner_radius + Math.random() * penumbra_distance

	if Vector3.distance(brush_point, random_point_inside) > accepted_radius then
		return nil, nil, nil, nil
	end

	local cam_pos = Camera.local_position(LevelEditor.camera)
	local ray_vector = random_point_inside - cam_pos
	local ray_length = Vector3.length(ray_vector)
	
	if ray_length < 0.000001 then
		return nil, nil, nil, nil
	end

	local ray_dir = ray_vector / ray_length
	local owning_unit, point, surface_normal = visual_unit_raycast(cam_pos, ray_dir, ray_length)
	local brush_component = self:_random_brush_component()
	local normal = self:_resolve_normal(brush_component, surface_normal)
	local rotation = (normal ~= nil and owning_unit ~= nil) and ScatterTool.vary_rotation(ScatterTool.rotation_from_normal(normal, owning_unit:local_pose())) or nil
	local scattered_unit_resource_id = Nilable.map(brush_component, Func.property("unit"))
	assert(scattered_unit_resource_id == nil or type(scattered_unit_resource_id) == "string")
	return owning_unit, point, rotation, scattered_unit_resource_id
end

function ScatterTool:_random_brush_component()
	local count = #self._brush_components
	
	if count < 2 then
		return self._brush_components[count]
	end

	local end_ranges =
		Array.fold(self._brush_components, {}, function(memo, brush_component)
			local prev_end = memo[#memo] or 0
			memo[#memo + 1] = prev_end + brush_component.frequency
			return memo
		end)

	assert(#end_ranges > 0)
	local random = Math.random() * end_ranges[#end_ranges]
	local index = Array.find(end_ranges, function(end_range) return random <= end_range end)
	assert(index <= count)
	local brush_component = self._brush_components[index]
	assert(brush_component ~= nil)
	return brush_component
end


--------------------------------------------------
-- Idle behavior
--------------------------------------------------

Behaviors.Idle = class(Behaviors.Idle)

function Behaviors.Idle:init()
end

function Behaviors.Idle:on_selected(tool)
	local mouse_pos = LevelEditor.mouse.pos
	tool:_pick_brush_point(mouse_pos.x, mouse_pos.y)
end

function Behaviors.Idle:mouse_down(tool, x, y)
	-- Prevent scatter while in landscape edit mode.
	if LevelEditor.landscape_tool:is_editing() then
		return
	end

	if is_erase_modifier_held() then
		if tool:_can_erase() then
			self:_start_erasing(tool, x, y)
		end
	elseif tool:_can_scatter() then
		self:_start_scattering(tool, x, y)
	end
end

function Behaviors.Idle:mouse_move(tool, x, y)
	tool:_pick_brush_point(x, y)
end

function Behaviors.Idle:update(tool, dt)
	if LevelEditor.editor_camera:is_controlled_by_mouse() then return end
	
	if is_erase_modifier_held() then
		tool:_draw_eraser()
	else
		tool:_draw_brush()
	end
end

function Behaviors.Idle:_start_erasing(tool, x, y)
	local brush_point = tool:brush_point()
	local eraser_radius = tool:eraser_radius()
	local erased_instance_ids = tool:_unspawn_scattered_units_inside_sphere(brush_point, eraser_radius)
	tool._behavior = Behaviors.Erase(erased_instance_ids)
end

function Behaviors.Idle:_start_scattering(tool, x, y)
	local owning_unit, brush_point, brush_rotation, scattered_unit_resource_id = tool:_pick_brush_point(x, y)
	local rotation = ScatterTool.vary_rotation(brush_rotation)
	local instance_id = tool:_spawn_scattered_unit(owning_unit, brush_point, rotation, scattered_unit_resource_id)
	tool._behavior = Behaviors.Place(instance_id)
end


--------------------------------------------------
-- Place behavior
--------------------------------------------------

Behaviors.Place = class(Behaviors.Place)

function Behaviors.Place:init(instance_id)
	self._created_instance_id = instance_id
end

function Behaviors.Place:mouse_move(tool, x, y)
	tool:_pick_brush_point(x, y)
	tool._behavior = Behaviors.Scatter({ self._created_instance_id })
end

function Behaviors.Place:mouse_up(tool, x, y)
	tool._scatter_manager:send_scattered_instance_ids({ self._created_instance_id })
	tool._behavior = Behaviors.Idle()
end

function Behaviors.Place:update(tool, dt)
	tool:_draw_brush()
end


--------------------------------------------------
-- Scatter behavior
--------------------------------------------------

Behaviors.Scatter = class(Behaviors.Scatter)

function Behaviors.Scatter:init(created_instance_ids)
	assert(type(created_instance_ids) == "table")
	self._created_instance_ids = created_instance_ids
	self._accumulated_time = 0
end

function Behaviors.Scatter:mouse_move(tool, x, y)
	tool:_pick_brush_point(x, y)
end

function Behaviors.Scatter:mouse_up(tool, x, y)
	tool._scatter_manager:send_scattered_instance_ids(self._created_instance_ids)
	tool._behavior = Behaviors.Idle()
end

function Behaviors.Scatter:update(tool, dt)
	tool:_draw_brush()
	if not tool:_can_scatter() then return end

	self._accumulated_time = self._accumulated_time + dt
	local rate = 1 / tool:scatter_speed()

	while self._accumulated_time > rate do
		local nv, nq, nm = Script.temp_count()
		local owning_unit, position, rotation, scattered_unit_resource_id = tool:_random_point_inside_brush()

		if (owning_unit ~= nil) then
			local instance_id = tool:_spawn_scattered_unit(owning_unit, position, rotation, scattered_unit_resource_id)
			table.insert(self._created_instance_ids, instance_id)
		end

		self._accumulated_time = self._accumulated_time - rate
		Script.set_temp_count(nv, nq, nm)
	end
end


--------------------------------------------------
-- Erase behavior
--------------------------------------------------

Behaviors.Erase = class(Behaviors.Erase)

function Behaviors.Erase:init(erased_instance_ids)
	assert(type(erased_instance_ids) == "table")
	self._erased_instance_ids = erased_instance_ids
end

function Behaviors.Erase:mouse_move(tool, x, y)
	tool:_pick_brush_point(x, y)
end

function Behaviors.Erase:mouse_up(tool, x, y)
	tool._scatter_manager:send_unscattered_instance_ids(self._erased_instance_ids)
	tool._behavior = Behaviors.Idle()
end

function Behaviors.Erase:update(tool, dt)
	tool:_draw_eraser()
	if not tool:_can_erase() then return end

	local brush_point = tool:brush_point()
	local eraser_radius = tool:eraser_radius()
	local erased_instance_ids = tool:_unspawn_scattered_units_inside_sphere(brush_point, eraser_radius)
	
	for _, instance_id in ipairs(erased_instance_ids) do
		table.insert(self._erased_instance_ids, instance_id)
	end
end
