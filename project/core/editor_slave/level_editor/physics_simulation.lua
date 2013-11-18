--------------------------------------------------
-- Utility functions
--------------------------------------------------

local function alive_unit_object(object_id)
	return Nilable.filter(Nilable.bind(object_id, Func.of_table(LevelEditor.objects)), function(level_object) return Unit.alive(level_object._unit) end)
end

local function unit_object_elements(unit_object)
	return Dict.values(LevelEditor:get_unit_node_names(unit_object:type()))
			   :distinct()
			   :sort()
			   :map(Func.partial(SceneElementRef.make, unit_object.id))
end

local function is_unit_object_simulation_running(unit_object)
	local unit = Nilable.filter(unit_object._unit, Unit.alive)
	
	if unit == nil then
		return false
	end

	local actor_count = Unit.num_actors(unit)

	for actor_id = 0, actor_count - 1 do
		local actor = Unit.actor(unit, actor_id)

		if actor ~= nil and Actor.is_physical(actor) then
			-- The actor is kept awake for a bit after it stops moving.
			-- This is a better approach to checking wether or not an actor is at rest.
			if Vector3.length(Actor.velocity(actor)) > 0.004 or Vector3.length(Actor.angular_velocity(actor)) > 0.004 then
				return true
			end
		end
	end

	return false
end

local function is_unit_object_id(value)
	return Validation.is_object_id(value)
	   and kind_of(LevelEditor.objects[value]) == UnitObject
end


--------------------------------------------------
-- PhysicsSimulation
--------------------------------------------------

PhysicsSimulation = PhysicsSimulation or {}

function PhysicsSimulation.begin_simulation(unit_object_ids)
	assert(Validation.is_non_empty_array(unit_object_ids))
	assert(Array.all(unit_object_ids, is_unit_object_id))
	local unit_objects = Array.choose(unit_object_ids, alive_unit_object)
	local scene_element_refs = Array.collect(unit_objects, unit_object_elements)
	local boxed_start_poses = Array.map(scene_element_refs, Func.compose(SceneElementRef.local_pose, Matrix4x4Box))
	Array.iter(unit_objects, Func.method("mobilize"))
	return scene_element_refs, boxed_start_poses
end

function PhysicsSimulation.end_simulation(scene_element_refs, boxed_start_poses)
	-- Immobilize units.
	Array.map(scene_element_refs, SceneElementRef.object_id)
		 :distinct()
		 :choose(alive_unit_object)
		 :iter(Func.method("immobilize"))

	local start_poses = Array.map(boxed_start_poses, Func.method("unbox"))
	local moved_scene_element_refs, new_positions, new_rotations, new_scales = ObjectUtils.moved_elements(scene_element_refs, start_poses)

	if #moved_scene_element_refs > 0 then
		-- Notify the level editor of the new poses, registering an undo entry.
		Application.console_send {
			type = "elements_moved",
			scene_element_refs = moved_scene_element_refs,
			positions = new_positions,
			rotations = new_rotations,
			scales = new_scales,
		}
	end
end

function PhysicsSimulation.remove_deleted_units(scene_element_refs, boxed_start_poses)
	local ser = {}
	local bsp = {}
	for i=1,#scene_element_refs do
		if is_unit_object_id(scene_element_refs[i].object_id) then
			ser[#ser+1] = scene_element_refs[i]
			bsp[#bsp+1] = boxed_start_poses[i]
		end
	end
	return ser, bsp
end

function PhysicsSimulation.is_simulation_running(unit_object_ids)
	if #unit_object_ids == 0 then return false end
	assert(Array.all(unit_object_ids, is_unit_object_id))
	local unit_objects = Array.choose(unit_object_ids, alive_unit_object)
	return #unit_objects > 0 and Array.any(unit_objects, is_unit_object_simulation_running)
end
