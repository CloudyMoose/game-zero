Picking = Picking or {}

function Picking.raycast(predicate, level_objects, ray_start, ray_dir, ray_length)
	local min_distance = ray_length
	local hit_object = nil
	local best_normal = Vector3Box(-ray_dir)
	
	for _, level_object in pairs(level_objects) do
		if predicate(level_object) then
			local nv, nq, nm = Script.temp_count()
			local distance, normal = level_object:raycast(ray_start, ray_dir, min_distance)

			if distance ~= nil and distance < min_distance then
				min_distance = distance
				hit_object = level_object
				best_normal:store(normal)
			end
			
			Script.set_temp_count(nv, nq, nm)
		end
	end

	if hit_object == nil then
		return nil, nil, nil
	else
		return hit_object, min_distance, best_normal:unbox()
	end
end

function Picking.component_raycast(predicate, level_objects, ray_start, ray_dir, ray_length)
	local min_distance = ray_length
	local hit_object = nil
	local hit_component_id = nil
	local best_normal = Vector3Box(-ray_dir)
	
	for _, level_object in pairs(level_objects) do
		if predicate(level_object) then
			local nv, nq, nm = Script.temp_count()
			local distance, normal, component_id = level_object:component_raycast(ray_start, ray_dir, min_distance)

			if distance ~= nil and distance < min_distance then
				min_distance = distance
				hit_object = level_object
				hit_component_id = component_id
				best_normal:store(normal)
			end
			
			Script.set_temp_count(nv, nq, nm)
		end
	end

	if hit_object == nil then
		return nil, nil, nil
	else
		return hit_object, min_distance, best_normal:unbox(), hit_component_id
	end
end

function Picking.is_visible(level_object)
	return not level_object.hidden
end

function Picking.is_visible_and_not_in_group(level_object)
	return level_object.parent_id == nil and not level_object.hidden
end

function Picking.is_selectable(level_object)
	if level_object.can_select and not level_object:can_select() then
		return false
	end

	if level_object.parent_id ~= nil then
		return false
	end

	if level_object.hidden or level_object.unselectable then
		return false
	end

	return true
end
