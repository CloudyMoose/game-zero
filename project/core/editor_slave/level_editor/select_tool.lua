--------------------------------------------------
-- Utility functions
--------------------------------------------------

local function selectable_object_at(x, y)
	local ray_start, ray_dir = LevelEditor:camera_ray(x, y)
	local ray_length = LevelEditor.editor_camera:far_range()
	local hit_object = Picking.raycast(Picking.is_selectable, LevelEditor.objects, ray_start, ray_dir, ray_length)
	return hit_object
end

local function unselected_objects_in_frustum(n1, o1, n2, o2, n3, o3, n4, o4)
	local result = {}

	for object_id, level_object in pairs(LevelEditor.objects) do
		if Picking.is_selectable(level_object) and not LevelEditor.selection:includes(object_id) then
			local pose, radius = level_object:box()
			
			if Math.box_in_frustum(pose, radius, n1, o1, n2, o2, n3, o3, n4, o4) then
				result[#result + 1] = level_object
			end
		end
	end

	return result
end

local function unselected_object_in_orthographic_rect(x0, y0, x1, y1)
	local p0 = LevelEditor:camera_ray(x0, y0)
	local p1 = LevelEditor:camera_ray(x1, y1)
	local camera_pose = Camera.local_pose(LevelEditor.camera)
	local camera_right = Matrix4x4.right(camera_pose)
	local camera_up = Matrix4x4.up(camera_pose)
	local n1 = -camera_right
	local o1 = Vector3.dot(p0, n1)
	local n2 = -camera_up
	local o2 = Vector3.dot(p0, n2)
	local n3 = camera_right
	local o3 = Vector3.dot(p1, n3)
	local n4 = camera_up
	local o4 = Vector3.dot(p1, n4)
	local new_objects = unselected_objects_in_frustum(n1, o1, n2, o2, n3, o3, n4, o4)
	return new_objects
end

local function unselected_objects_in_camera_frustum(x0, y0, x1, y1)
	function plane(x0, y0, x1, y1)
		local p0, d0 = LevelEditor:camera_ray(x0, y0)
		local p1, d1 = LevelEditor:camera_ray(x1, y1)
		local n = Vector3.normalize(Vector3.cross(d0, d1))
		local o = Vector3.dot(p0, n)
		return n, o
	end
	
	local n1, o1 = plane(x0, y1, x0, y0)
	local n2, o2 = plane(x1, y1, x0, y1)
	local n3, o3 = plane(x1, y0, x1, y1)
	local n4, o4 = plane(x0, y0, x1, y0)
	local new_objects = unselected_objects_in_frustum(n1, o1, n2, o2, n3, o3, n4, o4)
	return new_objects
end

local function unselected_objects_in_screen_rect(p1, p2)
	local x0 = math.min(p1.x, p2.x)
	local y0 = math.min(p1.y, p2.y)
	local x1 = math.max(p1.x, p2.x)
	local y1 = math.max(p1.y, p2.y)

	if x0 == x1 or y0 == y1 then
		return {}
	end

	return LevelEditor.editor_camera:is_orthographic()
	   and unselected_object_in_orthographic_rect(x0, y0, x1, y1)
	    or unselected_objects_in_camera_frustum(x0, y0, x1, y1)
end

local function perform_selection(pick_scene_element_ref, level_objects, x, y)
	local ray_start, ray_dir = LevelEditor:camera_ray(x, y)
	local ray_length = LevelEditor.editor_camera:far_range()
	local scene_element_ref = pick_scene_element_ref(level_objects, ray_start, ray_dir, ray_length)
	local is_multi_select = LevelEditor:is_multi_select_modifier_held()
	local selection_before = Array.copy(LevelEditor.selection:scene_element_refs())
	local selection_changed = false
	local could_initiate_drag = false

	if scene_element_ref ~= nil then
		if is_multi_select then
			if LevelEditor.selection:includes(scene_element_ref) then
				LevelEditor.selection:remove(scene_element_ref)
			else
				LevelEditor.selection:add(scene_element_ref)
			end
		else
			LevelEditor.selection:clear()
			LevelEditor.selection:add(scene_element_ref)
			could_initiate_drag = true
		end

		selection_changed = true
	else
		if LevelEditor.selection:count() > 0 and not is_multi_select then
			LevelEditor.selection:clear()
			selection_changed = true
		end
	end

	-- Allow each level object to tweak selection of its components.
	if selection_changed and is_multi_select then
		local scene_element_refs = LevelEditor.selection:scene_element_refs()
		local component_ids_by_object_id = Array.group_by(scene_element_refs, SceneElementRef.object_id, SceneElementRef.component_id)
		local sorted_object_ids = Dict.keys(component_ids_by_object_id):sort_by(function (object_id)
			return Array.find_last(scene_element_refs, Func.compose(SceneElementRef.object_id, Op.eq(object_id)))
		end)

		local filtered_scene_element_refs = nil

		for _, object_id in ipairs(sorted_object_ids) do
			local component_ids = component_ids_by_object_id[object_id]
			local level_object = LevelEditor.objects[object_id]

			if Func.has_method(level_object, "filter_component_selection") then
				local filtered_component_ids = level_object:filter_component_selection(component_ids)

				for _, component_id in ipairs(filtered_component_ids) do
					local scene_element_ref = SceneElementRef.make(object_id, component_id)
					filtered_scene_element_refs = filtered_scene_element_refs or {}
					table.insert(filtered_scene_element_refs, scene_element_ref)
				end
			end
		end

		if filtered_scene_element_refs ~= nil then
			LevelEditor.selection:set(filtered_scene_element_refs)
			selection_changed = not Array.eq(LevelEditor.selection:scene_element_refs(), selection_before)
		end
	end

	if selection_changed then
		LevelEditor.selection:send()
	end

	return selection_changed, could_initiate_drag
end

local function pick_level_object(level_objects, ray_start, ray_dir, ray_length)
	local level_object = Picking.raycast(Picking.is_selectable, level_objects, ray_start, ray_dir, ray_length)
	local scene_element_ref = level_object ~= nil and level_object.id or nil
	return scene_element_ref
end

local function pick_component(level_objects, ray_start, ray_dir, ray_length)
	local level_object, _, _, component_id = Picking.component_raycast(Picking.is_selectable, level_objects, ray_start, ray_dir, ray_length)
	local scene_element_ref = component_id ~= nil and SceneElementRef.make(level_object.id, component_id) or nil
	return scene_element_ref
end


--------------------------------------------------
-- SelectTool
--------------------------------------------------

SelectTool = class(SelectTool, Tool)
SelectTool.Behaviors = SelectTool.Behaviors or {}
local Behaviors = SelectTool.Behaviors

function SelectTool:init()
	self._behavior = Behaviors.Idle()
end

function SelectTool:mouse_down(x, y)
	local selection_changed, could_initiate_drag = false, false
	
	if self._behavior.mouse_down ~= nil then
		selection_changed, could_initiate_drag = self._behavior:mouse_down(self, x, y)
	end

	return selection_changed, could_initiate_drag
end

function SelectTool:mouse_move(x, y)
	if self._behavior.mouse_move ~= nil then
		self._behavior:mouse_move(self, x, y)
	end
end

function SelectTool:mouse_up(x, y)
	if self._behavior.mouse_up ~= nil then
		self._behavior:mouse_up(self, x, y)
	end
end

function SelectTool:update()
	if self._behavior.update ~= nil then
		self._behavior:update(self)
	end
end

function SelectTool:set_component_mode(enabled)
	if self._behavior.set_component_mode ~= nil then
		self._behavior:set_component_mode(self, enabled)
	end
end

function SelectTool:set_story_mode(enabled, object_ids)
	if self._behavior.set_story_mode ~= nil then
		self._behavior:set_story_mode(self, enabled, object_ids)
	end
end

function SelectTool:is_in_story_mode()
	return kind_of(self._behavior) == Behaviors.StorySelection
end


--------------------------------------------------
-- Idle behavior
--------------------------------------------------

Behaviors.Idle = class(Behaviors.Idle)

function Behaviors.Idle:init()
end

function Behaviors.Idle:mouse_down(tool, x, y)
	local selection_changed, could_initiate_drag = perform_selection(pick_level_object, LevelEditor.objects, x, y)
	tool._behavior = Behaviors.BoxSelection(x, y)
	return selection_changed, could_initiate_drag
end

function Behaviors.Idle:set_component_mode(tool, enabled)
	if enabled then
		local level_objects = LevelEditor.selection:objects():filter(Func.has_method("component_raycast"))
		
		if #level_objects > 0 then
			tool._behavior = Behaviors.ComponentSelection(level_objects)
			LevelEditor.selection:clear()
			LevelEditor.selection:send()
		end
	end
end

function Behaviors.Idle:set_story_mode(tool, enabled, level_objects)
	if enabled then
		tool._behavior = Behaviors.StorySelection(level_objects)
	end
end

--------------------------------------------------
-- BoxSelection behavior
--------------------------------------------------

Behaviors.BoxSelection = class(Behaviors.BoxSelection)

function Behaviors.BoxSelection:init(x, y)
	self._box_selection = BoxSelection()
	self._box_selection:begin_selection(x, y)
	self._drag_objects = {}
end

function Behaviors.BoxSelection:mouse_move(tool, x, y)
	self._box_selection:refresh_selection(x, y)
	
	for _, level_object in ipairs(self._drag_objects) do
		LevelEditor.selection:remove(level_object.id)
	end
	
	local s = self._box_selection:drag_start()
	local e = self._box_selection:drag_end()
	self._drag_objects = unselected_objects_in_screen_rect(s, e)
	
	for _, level_object in ipairs(self._drag_objects) do
		LevelEditor.selection:add(level_object.id)
	end
end

function Behaviors.BoxSelection:mouse_up(tool)
	if self._box_selection:is_dragging() then
		LevelEditor.selection:send()
	end

	self._box_selection:end_selection()
	tool._behavior = Behaviors.Idle()
end

function Behaviors.BoxSelection:update(tool)
	self._box_selection:draw(LevelEditor.gui)
end


--------------------------------------------------
-- ComponentSelection behavior
--------------------------------------------------

Behaviors.ComponentSelection = class(Behaviors.ComponentSelection)

function Behaviors.ComponentSelection:init(level_objects)
	assert(type(level_objects) == "table")
	assert(not Array.is_empty(level_objects))
	self._level_objects = level_objects
end

function Behaviors.ComponentSelection:mouse_down(tool, x, y)
	local selection_changed, could_initiate_drag = perform_selection(pick_component, self._level_objects, x, y)
	tool._behavior = Behaviors.ComponentBoxSelection(self._level_objects, x, y)
	return selection_changed, could_initiate_drag
end

function Behaviors.ComponentSelection:update(tool)
	if not LevelEditor.editor_camera:is_controlled_by_mouse() then
		Array.iter(self._level_objects, Func.method("draw_components"))
	end
end

function Behaviors.ComponentSelection:set_component_mode(tool, enabled)
	if not enabled then
		local level_object_ids = Array.map(self._level_objects, Func.property("id"))
		tool._behavior = Behaviors.Idle()
		LevelEditor.selection:set(level_object_ids)
		LevelEditor.selection:send()
	end
end


--------------------------------------------------
-- ComponentBoxSelection behavior
--------------------------------------------------

Behaviors.ComponentBoxSelection = class(Behaviors.ComponentBoxSelection)

function Behaviors.ComponentBoxSelection:init(level_objects, x, y)
	assert(type(level_objects) == "table")
	assert(not Dict.is_empty(level_objects))
	self._level_objects = level_objects
	self._box_selection = BoxSelection()
	self._box_selection:begin_selection(x, y)
end

function Behaviors.ComponentBoxSelection:mouse_move(tool, x, y)
	self._box_selection:refresh_selection(x, y)
	-- TODO: Component box selection test.
end

function Behaviors.ComponentBoxSelection:mouse_up(tool)
	if self._box_selection:is_dragging() then
		LevelEditor.selection:send()
	end

	self._box_selection:end_selection()
	tool._behavior = Behaviors.ComponentSelection(self._level_objects)
end

function Behaviors.ComponentBoxSelection:update(tool)
	Array.iter(self._level_objects, Func.method("draw_components"))
	self._box_selection:draw(LevelEditor.gui)
end


--------------------------------------------------
-- StorySelection behavior
--------------------------------------------------

Behaviors.StorySelection = class(Behaviors.StorySelection)

function Behaviors.StorySelection:init(object_ids)
	assert(type(object_ids) == "table")
	self._object_ids = object_ids
end

function Behaviors.StorySelection:mouse_down(tool, x, y)
	local level_objects = Array.map(self._object_ids, Func.of_table(LevelEditor.objects))
	local selection_changed, could_initiate_drag = perform_selection(pick_level_object, level_objects, x, y)
	--tool._behavior = Behaviors.BoxSelection(x, y)
	return selection_changed, could_initiate_drag
end

function Behaviors.StorySelection:set_story_mode(tool, enabled, object_ids)
	if not enabled then
		tool._behavior = Behaviors.Idle()
	else
		self._object_ids = object_ids
	end
end

function Behaviors.StorySelection:set_component_mode(tool, enabled)
	if enabled then
		local level_objects = LevelEditor.selection:objects():filter(Func.has_method("component_raycast"))
		
		if #level_objects > 0 then
			tool._behavior = Behaviors.StoryComponentSelection(level_objects, self._object_ids)
			LevelEditor.selection:clear()
			LevelEditor.selection:send()
		end
	end
end

--------------------------------------------------
-- StoryComponentSelection behavior
--------------------------------------------------

Behaviors.StoryComponentSelection = class(Behaviors.StoryComponentSelection)

function Behaviors.StoryComponentSelection:init(level_objects, all_story_object_ids)
	assert(type(level_objects) == "table")
	assert(not Array.is_empty(level_objects))
	self._level_objects = level_objects
	self._all_story_object_ids = all_story_object_ids
end

function Behaviors.StoryComponentSelection:mouse_down(tool, x, y)
	local selection_changed, could_initiate_drag = perform_selection(pick_component, self._level_objects, x, y)
	--tool._behavior = Behaviors.ComponentBoxSelection(self._level_objects, x, y)
	return selection_changed, could_initiate_drag
end

function Behaviors.StoryComponentSelection:update(tool)
	if not LevelEditor.editor_camera:is_controlled_by_mouse() then
		Array.iter(self._level_objects, Func.method("draw_components"))
	end
end

function Behaviors.StoryComponentSelection:set_story_mode(tool, enabled, level_objects)
	if not enabled then
		tool._behavior = Behaviors.Idle()
	else
		local level_object_ids = Array.map(self._level_objects, Func.property("id"))
		tool._behavior = Behaviors.StorySelection(self._all_story_object_ids)
		LevelEditor.selection:set(level_object_ids)
		LevelEditor.selection:send()
	end
end

function Behaviors.StoryComponentSelection:set_component_mode(tool, enabled)
	if not enabled then
		local level_object_ids = Array.map(self._level_objects, Func.property("id"))
		tool._behavior = Behaviors.StorySelection(self._all_story_object_ids)
		LevelEditor.selection:set(level_object_ids)
		LevelEditor.selection:send()
	end
end