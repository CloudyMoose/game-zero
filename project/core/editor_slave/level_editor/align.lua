--------------------------------------------------
-- Functions for aligning level objects
--------------------------------------------------

Align = Align or {}

function Align.to_floor(floor_object, aligned_object, aligned_component_id)
	-- Raycast towards the floor object along the world up axis passing through the bottom center of the aligned object.
	local tcv, tcq, tcm = Script.temp_count()
	local pose, radius = aligned_object:box(aligned_component_id)
	local center = Matrix4x4.translation(pose)
	local up = Matrix4x4.up(pose)
	local bottom_center = -radius.z * up + center
	local position_to_bottom_center = bottom_center - aligned_object:world_position(aligned_component_id)
	local ray_start = bottom_center + Vector3(0, 0, 10000)
	local ray_dir = Vector3(0, 0, -1)
	local distance = floor_object:raycast(ray_start, ray_dir, 20000)

	if distance ~= nil then
		local intersection_point = distance * ray_dir + ray_start
		aligned_object:set_world_position(intersection_point - position_to_bottom_center, aligned_component_id)
	end
	
	Script.set_temp_count(tcv, tcq, tcm)
end
