--------------------------------------------------
-- Utility functions
--------------------------------------------------

local function ensure_world_gui(rects, world_gui, gui_material)
	if Array.is_empty(rects) then
		local pose = Matrix4x4.identity()
		local zero = Vector3(0, 0, 0)
		local white = Color(255, 255, 255, 255)

		for i = 1, 6 do
			rects[i] = Gui.bitmap_3d(world_gui, gui_material, pose, zero, 0, zero, white)
		end
	else
		assert(#rects == 6)
	end
end

local function destroy_world_gui(rects, world_gui)
	Array.iter(rects, Func.partial(Gui.destroy_bitmap_3d, world_gui))
	Array.clear(rects)
	assert(#rects == 0)
end

local function for_each_world_gui_rect(visit, tm, radius, top_color, side_color, bottom_color)
	if radius.x == 0 and radius.y == 0 and radius.z == 0 then return end

	local nv, nq, nm = Script.temp_count()
	local origin = Vector3(0, 0, 0)
	local center = Matrix4x4.translation(tm)

	-- Draw sides.
	for y = 0, 1 do 
		local i = 2 * y + 1
		local x = (y + 2) % 3 + 1
		local z = (y + 1) % 3 + 1
		local y = y + 1
		local m = Matrix4x4.identity()
		Matrix4x4.set_x(m, Matrix4x4.axis(tm, x))
		Matrix4x4.set_y(m, Matrix4x4.axis(tm, y))
		Matrix4x4.set_z(m, Matrix4x4.axis(tm, z))
		local r = Vector3(Vector3.element(radius, x), Vector3.element(radius, y), Vector3.element(radius, z))
		local size = Vector3(r.x * 2, r.z * 2, 0)
		Matrix4x4.set_translation(m, center + Matrix4x4.transform_without_translation(m, Vector3(-r.x, -r.y, -r.z)))
		visit(i, m, origin, 1, size, side_color)
		Matrix4x4.set_x(m, -Matrix4x4.x(m))
		Matrix4x4.set_y(m, -Matrix4x4.y(m))
		Matrix4x4.set_translation(m, center + Matrix4x4.transform_without_translation(m, Vector3(-r.x, -r.y, -r.z)))
		visit(i + 1, m, origin, 1, size, side_color)
	end

	-- Draw top and bottom.
	local x = Matrix4x4.x(tm)
	local y = Matrix4x4.y(tm)
	local z = Matrix4x4.z(tm)
	local r = radius
	local size = Vector3(r.x * 2, r.y * 2, 0)
	local top = Matrix4x4.from_axes(x, -z, y, center + r.x * -x + r.y * -y + r.z * z)
	local bottom = Matrix4x4.from_axes(x, z, -y, center + r.x * -x + r.y * y + r.z * -z)
	visit(5, top, origin, 2, size, top_color)
	visit(6, bottom, origin, 0, size, bottom_color)
	Script.set_temp_count(nv, nq, nm)
end

local function transparent_box_colors(base_color, alpha)
	local side_color = Blend.color_with_alpha(base_color, alpha)
	local top_color = Interpolate.Linear.color(side_color, Color(alpha, 255, 255, 255), 0.6)
	local bottom_color = Interpolate.Linear.color(side_color, Color(alpha, 0, 0, 0), 0.2)
	return top_color, side_color, bottom_color
end

local function make_transparent_box(position, rotation, scale, radius, color, alpha)
	return Box(LevelEditor.prototype_gui, "retained", "trigger", position, rotation, scale, radius, transparent_box_colors(color, alpha))
end

local function make_opaque_box(position, rotation, scale, radius, color)
	return Box(LevelEditor.prototype_gui, "retained", "prototype", position, rotation, scale, radius, color)
end


--------------------------------------------------
-- Box
--------------------------------------------------

Box = class(Box)

function Box:init(world_gui, gui_mode, gui_material, position, rotation, scale, radius, top_color, side_color, bottom_color)
	assert(world_gui ~= nil)
	assert(gui_mode == "retained" or gui_mode == "immediate")
	assert(type(gui_material) == "string")
	self._world_gui = world_gui
	self._gui_mode = gui_mode
	self._gui_material = gui_material
	self._position = Vector3Box(position)
	self._rotation = QuaternionBox(rotation)
	self._scale = Vector3Box(scale)
	self._radius = Vector3Box(radius)
	self._top_color = QuaternionBox()
	self._side_color = QuaternionBox()
	self._bottom_color = QuaternionBox()
	self:set_colors(top_color, side_color, bottom_color)
	self._is_visible = true
	self._needs_repaint = true
end

function Box:destroy()
	if self._rects ~= nil then
		destroy_world_gui(self._rects, self._world_gui)
		self._rects = nil
	end
end

function Box:clone()
	return Box(self._world_gui, self._gui_mode, self._gui_material, self:position(), self:rotation(), self:scale(), self:radius(), self:colors())
end

function Box:position()
	return self._position:unbox()
end

function Box:set_position(position)
	self._position:store(position)
	self._needs_repaint = true
end

function Box:rotation()
	return self._rotation:unbox()
end

function Box:set_rotation(rotation)
	self._rotation:store(rotation)
	self._needs_repaint = true
end

function Box:scale()
	return self._scale:unbox()
end

function Box:set_scale(scale)
	self._scale:store(scale)
	self._needs_repaint = true
end

function Box:radius()
	return self._radius:unbox()
end

function Box:set_radius(radius)
	self._radius:store(radius)
	self._needs_repaint = true
end

function Box:colors()
	return self._top_color:unbox(), self._side_color:unbox(), self._bottom_color:unbox()
end

function Box:set_colors(top_color, side_color, bottom_color)
	self._top_color:store(top_color)
	self._side_color:store(side_color or top_color)
	self._bottom_color:store(bottom_color or top_color)
	self._needs_repaint = true
end

function Box:is_visible()
	return self._is_visible
end

function Box:set_visible(visible)
	assert(visible == true or visible == false)
	if visible == self._is_visible then return end
	self._is_visible = visible
	self._needs_repaint = true

	if self._gui_mode == "retained" and not visible then
		-- We need to explicitly call this to update retained-mode guis,
		-- because the draw method is not invoked on hidden objects.
		self:draw()
	end
end

function Box:encompass(...)
	-- Assumes world-space axis alignment and scale.
	local points = { ... }
	assert(#points > 0)
	local min_point = Array.fold(points, points[1], Vector3.min)
	local max_point = Array.fold(points, points[1], Vector3.max)
	local radius = (max_point - min_point) / 2
	self:set_position(min_point + radius)
	self:set_radius(radius)
end

function Box:set_vertical_extents(nz, pz)
	local nx, ny, _, px, py, _ = self:_extents()
	self:_set_extents(nx, ny, nz, px, py, pz)
end

function Box:_extents()
	local position = self:position()
	local radius = self:radius()
	local nx = position.x - radius.x
	local ny = position.y - radius.y
	local nz = position.z - radius.z
	local px = position.x + radius.x
	local py = position.y + radius.y
	local pz = position.z + radius.z
	return nx, ny, nz, px, py, pz
end

function Box:_set_extents(nx, ny, nz, px, py, pz)
	local radius = Vector3(px - nx, py - ny, pz - nz) / 2
	local min_point = Vector3(nx, ny, nz)
	self:set_position(min_point + radius)
	self:set_radius(radius)
end

function Box:pose()
	local pose = Matrix4x4.from_quaternion_position(self:rotation(), self:position())
	Matrix4x4.set_scale(pose, self:scale())
	return pose
end

function Box:box()
	local unscaled_pose = Matrix4x4.from_quaternion_position(self:rotation(), self:position())
	local scaled_radius = Vector3.multiply_elements(self:radius(), self:scale())
	return unscaled_pose, scaled_radius
end

function Box:draw()
	assert(self._gui_mode == "immediate" or self._gui_mode == "retained")

	if self._gui_mode == "immediate" then
		self:_draw_to_immediate_mode_gui()
	elseif self._needs_repaint then
		self:_update_retained_mode_gui()
	end

	self._needs_repaint = nil
end

function Box:draw_edges(line_object, color)
	local tm, r = self:box()
	LineObject.add_box(line_object, color, tm, r)
end

function Box:draw_side_labels(color)
	local tm, radius = self:box()
	OOBB.draw_side_labels(LevelEditor.world_gui, tm, radius, 3, color)
end

function Box:_draw_to_immediate_mode_gui()
	if not self:is_visible() then return end

	local function draw_gui_bitmap(_, ...)
		Gui.bitmap_3d(self._world_gui, self._gui_material, ...)
	end

	local tm = self:pose()
	local radius = self:radius()
	for_each_world_gui_rect(draw_gui_bitmap, tm, radius, self:colors())
end

function Box:_update_retained_mode_gui()
	if self:is_visible() then
		self._rects = self._rects or {}
		ensure_world_gui(self._rects, self._world_gui, self._gui_material)

		local function update_prototype_gui_bitmap(i, ...)
			Gui.update_bitmap_3d(self._world_gui, self._rects[i], self._gui_material, ...)
		end

		local tm = self:pose()
		local radius = self:radius()
		for_each_world_gui_rect(update_prototype_gui_bitmap, tm, radius, self:colors())
	elseif self._rects ~= nil then
		destroy_world_gui(self._rects, self._world_gui)
		self._rects = nil
	end
end


--------------------------------------------------
-- BoxObject
--------------------------------------------------

BoxObject = class(BoxObject, ObjectBase)

function BoxObject:init(id, box)
	assert(kind_of(box) == Box)
	ObjectBase.init(self, id)
	self._box = box
end

function BoxObject:destroy()
	self._box:destroy()
	self._box = nil
	ObjectBase.destroy(self)
end

function BoxObject:duplicate(spawned)
	local copy = setmetatable(ObjectBase.duplicate(self, spawned), BoxObject)
	copy._box = self._box:clone()
	return copy
end

function BoxObject:draw()
	self._box:draw()
end

function BoxObject:draw_highlight()
	local highlight_color = ObjectBase.draw_highlight(self)

	if highlight_color ~= nil then
		local label_color = Blend.color_with_alpha(highlight_color, 255)
		self._box:draw_side_labels(label_color)
	end
end

function BoxObject:draw_edges(line_object, color)
	self._box:draw_edges(line_object, color)
end

function BoxObject:box(component_id)
	assert(component_id == nil)
	return self._box:box()
end

function BoxObject:local_position(component_id)
	assert(component_id == nil)
	return self._box:position()
end

function BoxObject:set_local_position(position, component_id)
	assert(component_id == nil)
	self._box:set_position(position)
end

function BoxObject:local_rotation(component_id)
	assert(component_id == nil)
	return self._box:rotation()
end

function BoxObject:set_local_rotation(rotation, component_id)
	assert(component_id == nil)
	self._box:set_rotation(rotation)
end

function BoxObject:local_scale(component_id)
	assert(component_id == nil)
	return self._box:scale()
end

function BoxObject:set_local_scale(scale, component_id)
	assert(component_id == nil)
	self._box:set_scale(scale)
end

function BoxObject:radius()
	return self._box:radius()
end

function BoxObject:set_radius(radius)
	self._box:set_radius(radius)
	self:reset_pivot()
end

function BoxObject:closest_mesh_point_to_ray(from, dir, tres)
	local tm, r = self:box()
	return OOBB.closest_point_to_ray(tm, r, from, dir, tres)
end

function BoxObject:spawn_data()
	local data = ObjectBase.spawn_data(self)
	data.radius = self:radius()
	return data
end

function BoxObject:reset_pivot()
	self:set_local_pivot(-self._box:radius())
end

function BoxObject:set_visible(visible)
	ObjectBase.set_visible(self, visible)
	self._box:set_visible(visible)
end

function BoxObject:face_highlight_color()
	local _, side_color, _ = self._box:colors()
	local dominant_color = Blend.dominant_color(Blend.color_with_alpha(side_color, 128))
	local result = Blend.color_with_color(dominant_color, Color(128, 255, 255, 255), 0.8)
	return result
end


--------------------------------------------------
-- Trigger
--------------------------------------------------

Trigger = class(Trigger, BoxObject)

function Trigger.make_box(position, rotation, scale, radius)
	return make_transparent_box(position, rotation, scale, radius, Color(255, 255, 0), 128)
end

function Trigger.make(position, rotation, scale, radius)
	return Trigger(nil, position, rotation, scale, radius, "")
end

function Trigger:init(id, position, rotation, scale, radius, name)
	assert(type(name) == "string")
	local box = Trigger.make_box(position, rotation, scale, radius)
	BoxObject.init(self, id, box)
	self._name = name
end

function Trigger:duplicate(spawned)
	local copy = setmetatable(BoxObject.duplicate(self, spawned), Trigger)
	copy._name = self._name
	return copy
end

function Trigger:spawn_data()
	local data = BoxObject.spawn_data(self)
	data.klass = "trigger"
	data.name = self._name
	return data
end

function Trigger:draw()
	BoxObject.draw(self)
	self:draw_edges(LevelEditor.lines, Color(128, 255, 255, 255))
end

function Trigger:face_highlight_color()
	return Color(128, 255, 0, 0)
end


--------------------------------------------------
-- Prototype
--------------------------------------------------

Prototype = class(Prototype, BoxObject)

function Prototype.make_box(position, rotation, scale, radius)
	return make_opaque_box(position, rotation, scale, radius, Color(255, 255, 255))
end

function Prototype.make(position, rotation, scale, radius)
	return Prototype(nil, position, rotation, scale, radius, "default", "default", Color(255, 255, 255), true)
end

function Prototype:init(id, position, rotation, scale, radius, physics_material, shape_template, color, visible)
	assert(type(physics_material) == "string")
	assert(type(shape_template) == "string")
	assert(color ~= nil)
	assert(type(visible) == "boolean")
	local box = visible
	  and make_opaque_box(position, rotation, scale, radius, color)
	   or make_transparent_box(position, rotation, scale, radius, color, 40)
	BoxObject.init(self, id, box)
	self._physics_material = physics_material
	self._shape_template = shape_template
	self._visible = visible
end

function Prototype:duplicate(spawned)
	local copy = setmetatable(BoxObject.duplicate(self, spawned), Prototype)
	copy._physics_material = self._physics_material
	copy._shape_template = self._shape_template
	copy._visible = self._visible
	return copy
end

function Prototype:spawn_data()
	local color, _, _ = self._box:colors()
	local data = BoxObject.spawn_data(self)
	data.klass = "prototype"
	data.color = color
	data.physics_material = self._physics_material
	data.shape_template = self._shape_template
	data.visible = self._visible
	return data
end
