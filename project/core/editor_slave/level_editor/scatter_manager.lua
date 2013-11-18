--------------------------------------------------
-- Utility functions
--------------------------------------------------

local function to_world(unit_owner_id, local_position, local_rotation)
	local owner = LevelEditor.objects[unit_owner_id]
	assert(owner ~= nil)
	local component_id = nil -- TODO: Support scatter onto unit components.
	return owner:to_global_position_and_rotation(local_position, local_rotation, component_id)
end

local function is_valid_scatter_pool_fade_method(fade_method)
	return Array.map({ "POP", "SLIDE_Z", "SCALE" }, Func.of_table(ScatterSystem)):contains(fade_method)
end

local function validate_scatter_pool_settings(scatter_pool_settings)
	assert(type(scatter_pool_settings) == "table")
	assert(type(scatter_pool_settings.unit) == "string")
	assert(type(scatter_pool_settings.spawn_distance) == "number")
	assert(type(scatter_pool_settings.unspawn_distance) == "number")
	assert(is_valid_scatter_pool_fade_method(scatter_pool_settings.fade_method))

	local assert_is_number = Func.compose(type, Op.eq("number"), assert)
	Nilable.iter(scatter_pool_settings.fade_range, assert_is_number)
	Nilable.iter(scatter_pool_settings.fade_from, assert_is_number)
	Nilable.iter(scatter_pool_settings.fade_to, assert_is_number)
end


--------------------------------------------------
-- ScatterManager
--------------------------------------------------

ScatterManager = class(ScatterManager)

function ScatterManager:init(scatter_system)
	self._scatter_system = scatter_system
	self._scatter_observer = ScatterSystem.make_observer(scatter_system, Vector3(0, 0, 0))
	self._scatter_pool_settings_by_unit_resource_id = {}
	self._scatter_pool_ids_by_unit_resource_id = {}
	self._scatter_instance_ids_by_unit_owner_id = {}
	self._scattered_unit_owner_ids = {}
	self._scattered_unit_resource_ids = {}
	self._scattered_unit_positions = {}
	self._scattered_unit_rotations = {}
	self._engine_instance_ids_by_instance_id = {}
	self._last_used_instance_id = 0
end

function ScatterManager:shutdown()
	-- Unspawn all scattered instances.
	self:unspawn_all()

	-- Destroy all pools.
	self._scatter_pool_settings_by_unit_resource_id = {}
	self._scatter_pool_ids_by_unit_resource_id = {}
	ScatterSystem.destroy_all_brushes(self._scatter_system)

	-- Destroy observer.
	if self._scatter_observer ~= nil then
		ScatterSystem.destroy_observer(self._scatter_system, self._scatter_observer)
		self._scatter_observer = nil
	end
end

function ScatterManager:unspawn_all()
	Dict.iter(self._scattered_unit_resource_ids, Func.method("unspawn", self))
	self._engine_instance_ids_by_instance_id = {}
	self._last_used_instance_id = 0
end

function ScatterManager:update(camera)
	if self._scatter_observer ~= nil then
		local position = Camera.local_position(camera)
		local rotation = Camera.local_rotation(camera)
		ScatterSystem.move_observer(self._scatter_system, self._scatter_observer, position, rotation)
	end
end

function ScatterManager:new_instance_id()
	self._last_used_instance_id = self._last_used_instance_id + 1
	return self._last_used_instance_id
end

function ScatterManager:spawn(unit_owner_id, unit_resource_id, local_position, local_rotation, instance_id)
	assert(type(unit_owner_id) == "string")
	assert(type(unit_resource_id) == "string")
	local nv, nq, nm = Script.temp_count()
	local pool_id = self:_scatter_pool_for_unit_resource_id(unit_resource_id)
	local world_position, world_rotation = to_world(unit_owner_id, local_position, local_rotation)
	local engine_instance_id = ScatterSystem.spawn(self._scatter_system, pool_id, world_position, world_rotation)
	self:_register_engine_instance_id(engine_instance_id, instance_id)
	assert(self._scattered_unit_resource_ids[instance_id] == nil)
	assert(self._scattered_unit_positions[instance_id] == nil)
	assert(self._scattered_unit_rotations[instance_id] == nil)
	self._scattered_unit_resource_ids[instance_id] = unit_resource_id
	self._scattered_unit_positions[instance_id] = Vector3Box(local_position)
	self._scattered_unit_rotations[instance_id] = QuaternionBox(local_rotation)
	self:_register_instance_owner(instance_id, unit_owner_id)
	Script.set_temp_count(nv, nq, nm)
end

function ScatterManager:unspawn(instance_id)
	self:engine_unspawn(instance_id)
	self:_unregister_instance_owner(instance_id)
	self:_unregister_engine_instance_id(instance_id)
	self._scattered_unit_resource_ids[instance_id] = nil
	self._scattered_unit_positions[instance_id] = nil
	self._scattered_unit_rotations[instance_id] = nil
end

function ScatterManager:spawn_unless_exists(unit_owner_id, unit_resource_id, local_position, local_rotation, instance_id)
	assert(type(instance_id) == "number")

	if self._scattered_unit_resource_ids[instance_id] == nil then
		self:spawn(unit_owner_id, unit_resource_id, local_position, local_rotation, instance_id)
	end
end

function ScatterManager:unspawn_if_exists(instance_id)
	assert(type(instance_id) == "number")

	if self._scattered_unit_resource_ids[instance_id] ~= nil then
		self:unspawn(instance_id)
	end
end

function ScatterManager:engine_unspawn(instance_id)
	assert(self._scattered_unit_resource_ids[instance_id] ~= nil)
	assert(self._scattered_unit_positions[instance_id] ~= nil)
	assert(self._scattered_unit_rotations[instance_id] ~= nil)
	local engine_instance_id = self:_to_engine_instance_id(instance_id)
	ScatterSystem.unspawn(self._scatter_system, engine_instance_id)
end

function ScatterManager:engine_respawn(instance_id)
	local nv, nq, nm = Script.temp_count()
	local unit_resource_id = self._scattered_unit_resource_ids[instance_id]
	local unit_owner_id = self._scattered_unit_owner_ids[instance_id]
	local local_position = self._scattered_unit_positions[instance_id]:unbox()
	local local_rotation = self._scattered_unit_rotations[instance_id]:unbox()
	local pool_id = self._scatter_pool_ids_by_unit_resource_id[unit_resource_id]
	local world_position, world_rotation = to_world(unit_owner_id, local_position, local_rotation)
	local engine_instance_id = self:_to_engine_instance_id(instance_id)
	ScatterSystem.respawn(self._scatter_system, pool_id, world_position, world_rotation, engine_instance_id)
	Script.set_temp_count(nv, nq, nm)
end

function ScatterManager:align_scatter_to_landscape_in_unit(unit_owner_id)
	local instance_ids = self:instance_ids_for_unit(unit_owner_id)

	if #instance_ids == 0 then
		return
	end

	local landscape_unit_object = LevelEditor.objects[unit_owner_id]
	local landscape_pose = landscape_unit_object:local_pose()
	local landscape_world_up = Matrix4x4.up(landscape_pose)
	
	for _, instance_id in ipairs(instance_ids) do
		local tcv, tcq, tcm = Script.temp_count()
		local boxed_local_position = self._scattered_unit_positions[instance_id]
		local boxed_local_rotation = self._scattered_unit_rotations[instance_id]
		local world_position, world_rotation = landscape_unit_object:to_global_position_and_rotation(boxed_local_position:unbox(), boxed_local_rotation:unbox())

		local ray_start = world_position + landscape_world_up * 10000
		local ray_dir = -landscape_world_up
		local distance, normal = landscape_unit_object:raycast(ray_start, ray_dir, 20000)

		if distance ~= nil then
			local new_world_position = distance * ray_dir + ray_start
			local new_world_rotation = ScatterTool.vary_rotation(ScatterTool.rotation_from_normal(normal, landscape_pose))
			local new_local_position, new_local_rotation = landscape_unit_object:to_local_position_and_rotation(new_world_position, new_world_rotation)
			boxed_local_position:store(new_local_position)
			boxed_local_rotation:store(new_local_rotation)
		end

		Script.set_temp_count(tcv, tcq, tcm)
	end

	self:update_scatter_transforms_for_unit(unit_owner_id)

	Application.console_send {
		type = "update_scatter",
		scatter_data = self:scatter_data(instance_ids)
	}
end

function ScatterManager:update_scatter_transforms_for_unit(unit_owner_id)
	local instance_ids = self:instance_ids_for_unit(unit_owner_id)
	local count = #instance_ids

	for i = 1, count do
		self:engine_unspawn(instance_ids[i])
	end

	for i = count, 1, -1 do
		self:engine_respawn(instance_ids[i])
	end
end

function ScatterManager:update_scatter_pool_settings(scatter_pool_settings)
	validate_scatter_pool_settings(scatter_pool_settings)
	local unit_resource_id = scatter_pool_settings.unit
	local instance_ids = self:instance_ids_for_unit_resource_id(unit_resource_id)
	local count = #instance_ids

	for i = 1, count do
		self:engine_unspawn(instance_ids[i])
	end

	self._scatter_pool_settings_by_unit_resource_id[unit_resource_id] = scatter_pool_settings
	local old_pool_id = self._scatter_pool_ids_by_unit_resource_id[unit_resource_id]

	if old_pool_id ~= nil then
		ScatterSystem.destroy_brush(self._scatter_system, old_pool_id)
		local new_pool_id = ScatterSystem.make_brush(self._scatter_system, scatter_pool_settings)
		self._scatter_pool_ids_by_unit_resource_id[unit_resource_id] = new_pool_id
	end

	for i = count, 1, -1 do
		self:engine_respawn(instance_ids[i])
	end
end

function ScatterManager:hide_scatter_for_unit(unit_owner_id)
	local instance_ids = self:instance_ids_for_unit(unit_owner_id)

	for _, instance_id in ipairs(instance_ids) do
		self:engine_unspawn(instance_id)
	end
end

function ScatterManager:show_scatter_for_unit(unit_owner_id)
	local instance_ids = self:instance_ids_for_unit(unit_owner_id)
	local count = #instance_ids

	for i = count, 1, -1 do
		self:engine_respawn(instance_ids[i])
	end
end

function ScatterManager:unspawn_scatter_for_unit(unit_owner_id)
	local instance_ids = self:instance_ids_for_unit(unit_owner_id)

	for _, instance_id in ipairs(instance_ids) do
		self:unspawn(instance_id)
	end
end

function ScatterManager:duplicate_scatter_for_unit(unit_owner_id, new_unit_owner_id)
	local instance_ids = self:instance_ids_for_unit(unit_owner_id)

	for _, instance_id in ipairs(instance_ids) do
		local unit_resource_id = self._scattered_unit_resource_ids[instance_id]
		local local_position = self._scattered_unit_positions[instance_id]:unbox()
		local local_rotation = self._scattered_unit_rotations[instance_id]:unbox()
		local new_instance_id = self:new_instance_id()
		self:spawn(new_unit_owner_id, unit_resource_id, local_position, local_rotation, new_instance_id)
	end
end

function ScatterManager:instance_ids_for_unit(unit_owner_id)
	assert(type(unit_owner_id) == "string")
	local set = self._scatter_instance_ids_by_unit_owner_id[unit_owner_id]
	return set == nil and {} or Set.to_array(set)
end

function ScatterManager:instance_ids_for_unit_resource_id(unit_resource_id)
	assert(type(unit_resource_id) == "string")
	return Dict.filter(self._scattered_unit_resource_ids, function(_, x) return x == unit_resource_id end):keys()
end

function ScatterManager:instance_ids_inside_sphere(center, radius)
	local instance_ids = setmetatable({}, Array.MetaTable)
	local local_sphere_centers_by_unit_owner_id = {}

	for instance_id, boxed_position in pairs(self._scattered_unit_positions) do
		local nv, nq, nm = Script.temp_count()

		local unit_owner_id = self._scattered_unit_owner_ids[instance_id]
		assert(unit_owner_id ~= nil)
		local boxed_local_sphere_center = local_sphere_centers_by_unit_owner_id[unit_owner_id]

		if boxed_local_sphere_center == nil then
			local owner_pose = LevelEditor.objects[unit_owner_id]:local_pose()
			local inv_tm = Matrix4x4.inverse(owner_pose)
			boxed_local_sphere_center = Vector3Box(Matrix4x4.transform(inv_tm, center))
			local_sphere_centers_by_unit_owner_id[unit_owner_id] = boxed_local_sphere_center
		end

		local local_position = boxed_position:unbox()
		local local_sphere_center = boxed_local_sphere_center:unbox()

		if Vector3.distance(local_position, local_sphere_center) <= radius then
			table.insert(instance_ids, instance_id)
		end

		Script.set_temp_count(nv, nq, nm)
	end

	return instance_ids
end

function ScatterManager:unit_resource_id(instance_id)
	assert(type(instance_id) == "number")
	local unit_resource_id = self._scattered_unit_resource_ids[instance_id]
	assert(unit_resource_id ~= nil)
	assert(type(unit_resource_id) == "string")
	return unit_resource_id
end

function ScatterManager:send_scattered_instance_ids(instance_ids)
	assert(type(instance_ids) == "table")
	if #instance_ids == 0 then return end

	Application.console_send {
		type = "scattered",
		scatter_data = self:scatter_data(instance_ids)
	}
end

function ScatterManager:send_unscattered_instance_ids(instance_ids)
	assert(type(instance_ids) == "table")
	if #instance_ids == 0 then return end

	Application.console_send {
		type = "unscattered",
		instance_ids = instance_ids
	}
end

function ScatterManager:scatter_data(instance_ids)
	-- The returned table will look like this:
	-- {
	--     <unit_object_id> = {
	--         <unit_resource_id> = {
	--             instance_ids = [1, 4, 5, ...]
	--             positions = [Vector3, ...]
	--             rotations = [Quaternion, ...]
	--         }
	--         ...
	--     }
	--     ...
	-- }
	local scatter_data = {}

	for _, instance_id in ipairs(instance_ids) do
		local unit_owner_id = self._scattered_unit_owner_ids[instance_id]
		local per_unit_owner_data = scatter_data[unit_owner_id]

		if per_unit_owner_data == nil then
			per_unit_owner_data = {}
			scatter_data[unit_owner_id] = per_unit_owner_data
		end

		local unit_resource_id = self._scattered_unit_resource_ids[instance_id]
		local per_unit_resource_data = per_unit_owner_data[unit_resource_id]

		if per_unit_resource_data == nil then
			per_unit_resource_data = { instance_ids = {}, positions = {}, rotations = {} }
			per_unit_owner_data[unit_resource_id] = per_unit_resource_data
		end

		local local_position = self._scattered_unit_positions[instance_id]:unbox()
		local local_rotation = self._scattered_unit_rotations[instance_id]:unbox()
		table.insert(per_unit_resource_data.instance_ids, instance_id)
		table.insert(per_unit_resource_data.positions, local_position)
		table.insert(per_unit_resource_data.rotations, local_rotation)
	end

	return scatter_data
end

function ScatterManager:_scatter_pool_for_unit_resource_id(unit_resource_id)
	assert(type(unit_resource_id) == "string")
	local pool_id = self._scatter_pool_ids_by_unit_resource_id[unit_resource_id]

	if pool_id == nil then
		local scatter_pool_settings = self:_scatter_pool_settings_for_unit_resource_id(unit_resource_id)
		pool_id = ScatterSystem.make_brush(self._scatter_system, scatter_pool_settings)
		self._scatter_pool_ids_by_unit_resource_id[unit_resource_id] = pool_id
	end
	
	return pool_id
end

function ScatterManager:_scatter_pool_settings_for_unit_resource_id(unit_resource_id)
	assert(type(unit_resource_id) == "string")
	local scatter_pool_settings = self._scatter_pool_settings_by_unit_resource_id[unit_resource_id]

	if scatter_pool_settings == nil then
		scatter_pool_settings = {
			unit = unit_resource_id,
			spawn_distance = 150,
			unspawn_distance = 160,
			fade_method = ScatterSystem.SCALE,
			fade_range = 10
		}

		self._scatter_pool_settings_by_unit_resource_id[unit_resource_id] = scatter_pool_settings
	end

	return scatter_pool_settings
end

function ScatterManager:_register_engine_instance_id(engine_instance_id, instance_id)
	assert(type(engine_instance_id) == "number")
	assert(type(instance_id) == "number")
	assert(self._engine_instance_ids_by_instance_id[instance_id] == nil)
	self._last_used_instance_id = math.max(self._last_used_instance_id, instance_id)
	self._engine_instance_ids_by_instance_id[instance_id] = engine_instance_id
end

function ScatterManager:_unregister_engine_instance_id(instance_id)
	assert(type(instance_id) == "number")
	assert(self._engine_instance_ids_by_instance_id[instance_id] ~= nil)
	self._engine_instance_ids_by_instance_id[instance_id] = nil
end

function ScatterManager:_to_engine_instance_id(instance_id)
	assert(type(instance_id) == "number")
	local engine_instance_id = self._engine_instance_ids_by_instance_id[instance_id]
	assert(engine_instance_id ~= nil)
	return engine_instance_id
end

function ScatterManager:_register_instance_owner(instance_id, unit_owner_id)
	assert(type(unit_owner_id) == "string")
	assert(self._scattered_unit_owner_ids[instance_id] == nil)
	self._scattered_unit_owner_ids[instance_id] = unit_owner_id
	
	local owned_instances = self._scatter_instance_ids_by_unit_owner_id[unit_owner_id]

	if owned_instances == nil then
		owned_instances = {}
		self._scatter_instance_ids_by_unit_owner_id[unit_owner_id] = owned_instances
	end

	assert(owned_instances[instance_id] == nil)
	owned_instances[instance_id] = true
	self._scattered_unit_owner_ids[instance_id] = unit_owner_id
end

function ScatterManager:_unregister_instance_owner(instance_id)
	local unit_owner_id = self._scattered_unit_owner_ids[instance_id]
	assert(unit_owner_id ~= nil)
	local owned_instances = self._scatter_instance_ids_by_unit_owner_id[unit_owner_id]
	assert(owned_instances ~= nil)
	assert(owned_instances[instance_id] ~= nil)
	owned_instances[instance_id] = nil
	self._scattered_unit_owner_ids[instance_id] = nil
	
	if Set.is_empty(owned_instances) then
		self._scatter_instance_ids_by_unit_owner_id[unit_owner_id] = nil
	end
end
