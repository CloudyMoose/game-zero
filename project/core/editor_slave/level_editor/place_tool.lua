--------------------------------------------------
-- Utility functions
--------------------------------------------------

local function drag_spawn_point(x, y, plane_height)
	local cam_pos, cam_dir = LevelEditor:camera_ray(x, y)
	local snapped_point, unsnapped_point = GridPlane.snap_mouse(Matrix4x4.identity(), plane_height, x, y)
	local spawn_point = LevelEditor:is_snap_to_grid_enabled() and snapped_point or unsnapped_point
	return spawn_point
end

local function spawn_unit(unit_type, position, rotation)
	local id = Application.guid()
	local unit = World.spawn_unit(LevelEditor.world, unit_type, position, rotation)	
	Unit.set_id(unit, id)
	if Voxelizer then
		Voxelizer.add_unit(LevelEditor.world, unit)		
	end
	BakedLighting.add_unit(LevelEditor.world, unit)
	local level_object = UnitObject(unit, id, unit_type)
	return level_object
end

local function spawn_particle_effect(effect_type, position, rotation)
	local pose = Matrix4x4.from_quaternion_position(rotation, position)
	local level_object = ParticleEffect()
	level_object.id = Application.guid()
	level_object.effect = effect_type
	level_object:set_local_position(position)
	level_object:set_local_rotation(rotation)
	return level_object
end

local function spawn_sound(sound_event, position, rotation)
	local pose = Matrix4x4.from_quaternion_position(rotation, position)
	local level_object = Sound()
	level_object.id = Application.guid()
	level_object.event = sound_event
	level_object:set_local_position(position)
	level_object:set_local_rotation(rotation)
	return level_object
end

local function commit_spawned_object(level_object)
	LevelEditor.objects[level_object.id] = level_object
	LevelEditor:spawned({level_object})
	LevelEditor.selection:clear()
	LevelEditor.selection:add(level_object.id)
	LevelEditor.selection:send()
end

local function draw_axes(pose)
	local p = Matrix4x4.translation(pose)
	local x = Matrix4x4.x(pose)
	local y = Matrix4x4.y(pose)
	local z = Matrix4x4.z(pose)
	local length = LevelEditor.editor_camera:screen_size_to_world_size(p, 25)
	local x_color = Color(75, 255, 0, 0)
	local y_color = Color(75, 0, 255, 0)
	local z_color = Color(75, 0, 0, 255)
	local lines = LevelEditor.lines_noz
	
	LineObject.add_line(lines, x_color, p, p + x * length)
	LineObject.add_line(lines, y_color, p, p + y * length)
	LineObject.add_line(lines, z_color, p, p + z * length)
end

local function draw_spawn_grid(grid_pose, spawn_point)
	local indicator_radius = LevelEditor.editor_camera:screen_size_to_world_size(spawn_point, 7)
	LevelEditor:draw_grid_plane(grid_pose, false, spawn_point)
	LineObject.add_sphere(LevelEditor.lines, Color(20, 0, 0, 0), spawn_point, indicator_radius, 40, 8)
	draw_axes(Matrix4x4.from_translation(spawn_point))
end


--------------------------------------------------
-- PlaceTool
--------------------------------------------------

PlaceTool = class(PlaceTool, Tool)
PlaceTool.Behaviors = PlaceTool.Behaviors or {}
local Behaviors = PlaceTool.Behaviors

function PlaceTool:init()
	self._placeable_type = nil
	self._placeable_resource_id = nil
	local mouse_pos = LevelEditor.mouse.pos
	self._behavior = Behaviors.Idle(mouse_pos.x, mouse_pos.y)
end

function PlaceTool:on_selected()
	if self._behavior.on_selected ~= nil then
		self._behavior:on_selected(self)
	end
end

function PlaceTool:update()
	if self._behavior.update ~= nil then
		self._behavior:update(self)
	end
end

function PlaceTool:mouse_down(x, y)
	if self._behavior.mouse_down ~= nil then
		self._behavior:mouse_down(self, x, y)
	end
end

function PlaceTool:mouse_move(x, y)
	if self._behavior.mouse_move ~= nil then
		self._behavior:mouse_move(self, x, y)
	end
end

function PlaceTool:mouse_up(x, y)
	if self._behavior.mouse_up ~= nil then
		self._behavior:mouse_up(self, x, y)
	end
end

function PlaceTool:mouse_spawn(x, y)
	if not self:_can_spawn() then return end

	local spawn_point = LevelEditor:find_spawn_point(x, y)
	local level_object = self:_spawn_level_object(spawn_point, Quaternion.identity())
	commit_spawned_object(level_object)
end

function PlaceTool:key(key)
	if self._behavior.key ~= nil then
		self._behavior:key(self, key)
	end
end

function PlaceTool:coordinates()
	return self._behavior:coordinates(self)
end

function PlaceTool:set_placeable(placeable_type, resource_id)
	assert(placeable_type == nil or placeable_type == "Unit" or placeable_type == "ParticleEffect" or placeable_type == "Sound")
	assert(resource_id == nil or type(resource_id) == "string")
	self._placeable_type = placeable_type
	self._placeable_resource_id = resource_id
end

function PlaceTool:_can_spawn()
	return self._placeable_type ~= nil and self._placeable_resource_id ~= nil
end

function PlaceTool:_spawn_level_object(position, rotation)
	assert(self:_can_spawn())

	if self._placeable_type == "Unit" then
		return spawn_unit(self._placeable_resource_id, position, rotation)
	elseif self._placeable_type == "ParticleEffect" then
		return spawn_particle_effect(self._placeable_resource_id, position, rotation)
	elseif self._placeable_type == "Sound" then
		return spawn_sound(self._placeable_resource_id, position, rotation)
	end
end

function PlaceTool:_draw_level_object_mesh(position, rotation)
	if self._placeable_resource_id == nil then return end

	local lines = LevelEditor.lines
	local color = Color(20, 200, 255, 255)
	local pose = Matrix4x4.from_quaternion_position(rotation, position)

	if self._placeable_type == "Unit" then
		LineObject.add_unit_meshes(lines, self._placeable_resource_id, color, pose)
	elseif self._placeable_type == "ParticleEffect" then
		LineObject.add_box(lines, color, pose, Vector3(0.5, 0.5, 0.5))
	elseif self._placeable_type == "Sound" then
		LineObject.add_unit_meshes(lines, "core/editor_slave/units/sound_source_icon/sound_source_icon", color, pose)
	end
end


--------------------------------------------------
-- Idle behavior
--------------------------------------------------

Behaviors.Idle = class(Behaviors.Idle)

function Behaviors.Idle:init(x, y)
	local spawn_point = LevelEditor:find_spawn_point(x, y)
	self._spawn_point = Vector3Box(spawn_point)
end

function Behaviors.Idle:coordinates(tool)
	return self._spawn_point:unbox()
end

function Behaviors.Idle:on_selected(tool)
	local mouse_pos = LevelEditor.mouse.pos
	local spawn_point = LevelEditor:find_spawn_point(mouse_pos.x, mouse_pos.y)
	self._spawn_point:store(spawn_point)
end

function Behaviors.Idle:mouse_down(tool, x, y)
	if not tool:_can_spawn() then return end

	local spawn_point = self._spawn_point:unbox()
	local level_object = tool:_spawn_level_object(spawn_point, Quaternion.identity())
	tool._behavior = Behaviors.DragObject(level_object, spawn_point.z)
end

function Behaviors.Idle:mouse_move(tool, x, y)
	local spawn_point = LevelEditor:find_spawn_point(x, y)
	self._spawn_point:store(spawn_point)
end

function Behaviors.Idle:update(tool)
	if LevelEditor.editor_camera:is_controlled_by_mouse() then return end

	local spawn_point = self._spawn_point:unbox()
	local grid_pose = Matrix4x4.from_translation(Vector3(0, 0, spawn_point.z))
	draw_spawn_grid(grid_pose, spawn_point)
	tool:_draw_level_object_mesh(spawn_point, Quaternion.identity())
end


--------------------------------------------------
-- Drag object behavior
--------------------------------------------------

Behaviors.DragObject = class(Behaviors.DragObject)

function Behaviors.DragObject:init(level_object, plane_height)
	self._dragged_object = level_object
	self._plane_height = plane_height
end

function Behaviors.DragObject:coordinates(tool)
	return self._dragged_object:local_position()
end

function Behaviors.DragObject:mouse_move(tool, x, y)
	local spawn_point = drag_spawn_point(x, y, self._plane_height)
	self._dragged_object:set_local_position(spawn_point)
end

function Behaviors.DragObject:mouse_up(tool, x, y)
	local spawn_point = drag_spawn_point(x, y, self._plane_height)
	self._dragged_object:set_local_position(spawn_point)
	commit_spawned_object(self._dragged_object)
	tool._behavior = Behaviors.Idle(x, y)
end

function Behaviors.DragObject:update(tool)
	local spawn_point = self._dragged_object:local_position()
	local grid_pose = Matrix4x4.from_translation(Vector3(0, 0, spawn_point.z))
	draw_spawn_grid(grid_pose, spawn_point)
	self._dragged_object:draw()
	tool:_draw_level_object_mesh(spawn_point, Quaternion.identity())
end
