require "core/editor_slave/class"
require "core/editor_slave/dict"
require "core/editor_slave/func"
require "core/editor_slave/math"

--------------------------------------------------
-- Utility functions
--------------------------------------------------

local function with_default(default_value)
	local mt = { __index = Func.constantly(default_value) }
	
	return function(t)
		return setmetatable(t, mt)
	end
end

local function delta_rotation(mouse_delta_x, mouse_delta_y, camera_right_vector, rotation_speed)
	local rotation_around_world_up = Quaternion(Vector3(0, 0, 1), -mouse_delta_x * rotation_speed)
	local rotation_around_camera_right = Quaternion(camera_right_vector, -mouse_delta_y * rotation_speed)
	local rotation = Quaternion.multiply(rotation_around_world_up, rotation_around_camera_right)
	return rotation
end

local function distance_along_ray(ray_start, ray_dir, point_a, point_b)
	local at = Vector3.dot(point_a - ray_start, ray_dir)
	local bt = Vector3.dot(point_b - ray_start, ray_dir)
	return math.abs(bt - at)
end

local function camera_fov(camera)
	-- Assumes square pixels.
	local width, height = Application.resolution()
	local vertical_fov = Camera.vertical_fov(camera)
	local horizontal_fov = vertical_fov * width / height
	return horizontal_fov, vertical_fov
end


--------------------------------------------------
-- Keyboard control handlers
--------------------------------------------------

local function non_movement_keyboard_control_handler(self, dt, controls)
	if controls.increase_far_range or controls.decrease_far_range then
		local far_range = Camera.far_range(self._camera)
		local range_increase_speed = self._translation_speed * dt * 30
		if controls.increase_far_range then far_range = far_range + range_increase_speed end
		if controls.decrease_far_range then far_range = far_range - range_increase_speed end
		Camera.set_far_range(self._camera, far_range)
		Application.console_send{ type = "message", level = "info", system = "EditorCamera", message = string.format("Camera far range: %.2f M", far_range) }
		self:_notify_state()
	end
end

local function quake_style_wasd_movement_keyboard_control_handler(self, dt, controls)
	-- Handle non-movement keys.
	non_movement_keyboard_control_handler(self, dt, controls)
	
	-- WASD applies translation along camera axes.
	local translation_speed = self._translation_speed * dt * 30
	local camera_pose = Camera.local_pose(self._camera)
	local camera_right_vector = Matrix4x4.x(camera_pose)
	local camera_forward_vector = Matrix4x4.y(camera_pose)
	local camera_up_vector = Matrix4x4.z(camera_pose)
	local offset = Vector3(0, 0, 0)
	
	if self:is_orthographic() then
		local scale = 1 + translation_speed / self._orthographic_zoom / 2
		assert(scale > 0)
		if controls.forward then	offset = offset + Vector3.multiply(camera_up_vector, translation_speed)		end
		if controls.back then		offset = offset + Vector3.multiply(camera_up_vector, -translation_speed)	end
		if controls.up then			self._orthographic_zoom = math.max(1, self._orthographic_zoom / scale)		end
		if controls.down then		self._orthographic_zoom = math.max(1, self._orthographic_zoom * scale)		end
		Camera.set_orthographic_view(self._camera, -self._orthographic_zoom, self._orthographic_zoom, -self._orthographic_zoom, self._orthographic_zoom)
	else
		if controls.forward then	offset = offset + Vector3.multiply(camera_forward_vector, translation_speed)	end
		if controls.back then		offset = offset + Vector3.multiply(camera_forward_vector, -translation_speed)	end
		if controls.up then			offset = offset + Vector3.multiply(camera_up_vector, translation_speed)			end
		if controls.down then		offset = offset + Vector3.multiply(camera_up_vector, -translation_speed)		end
	end
	
	if controls.left then	offset = offset + Vector3.multiply(camera_right_vector, -translation_speed)	end
	if controls.right then	offset = offset + Vector3.multiply(camera_right_vector, translation_speed)	end
	
	local camera_position = Matrix4x4.translation(camera_pose)
	Matrix4x4.set_translation(camera_pose, camera_position + offset)
	Camera.set_local_pose(self._camera, self._unit, camera_pose)
end


--------------------------------------------------
-- Quake-style mouse look camera controls
--------------------------------------------------

local function quake_style_mouse_look_mouse_wheel_delta_handler(self, wheel_delta, wheel_steps)
	-- Mouse wheel controls translation speed.
	assert(wheel_steps ~= 0)
	local multiplier = wheel_steps < 0 and 1 / 1.5 or 1.5
	self._translation_speed = math.max(0.0001, self._translation_speed * multiplier)
end

local function quake_style_mouse_look_mouse_delta_handler(self, dx, dy)
	-- Disallow rotation when using orthographic projection.
	if self:is_orthographic() then return end
	
	-- Mouse rotates camera around its own position.
	local camera_pose = Camera.local_pose(self._camera)
	local camera_right_vector = Matrix4x4.x(camera_pose)
	local rotation_speed = self._rotation_speed
	local relative_rotation = delta_rotation(dx, -dy, camera_right_vector, rotation_speed)
	local camera_position = Matrix4x4.translation(camera_pose)
	local camera_rotation = Matrix4x4.rotation(camera_pose)
	
	-- Concatenate matrix operations into new local pose.
	local apply_initial_rotation = Matrix4x4.from_quaternion(camera_rotation)
	local apply_relative_rotation = Matrix4x4.from_quaternion(relative_rotation)
	local operations = { apply_initial_rotation, apply_relative_rotation }
	local new_camera_pose = Array.reduce(operations, Matrix4x4.multiply)
	Matrix4x4.set_translation(new_camera_pose, camera_position)
	Camera.set_local_pose(self._camera, self._unit, new_camera_pose)
end


--------------------------------------------------
-- Maya-style turntable camera controls
--------------------------------------------------

local function store_drag_start(self, mouse_point)
	-- Store screen position where the drag was initiated.
	self._drag_start = self._drag_start or Vector3Box()
	self._drag_start:store(mouse_point.x, mouse_point.y, 0)
	
	-- Store the camera pose at the time the drag was initiated.
	self._drag_start_camera_pose = self._drag_start_camera_pose or Matrix4x4Box()
	self._drag_start_camera_pose:store(Camera.local_pose(self._camera))
	self._drag_start_interest_point_distance = self._interest_point_distance
	self._drag_start_orthographic_zoom = self._orthographic_zoom
end

local function clear_drag_start(self)
	self._drag_start = nil
	self._drag_start_camera_pose = nil
	self._drag_start_interest_point_distance = nil
	self._drag_start_orthographic_zoom = nil
end

local function maya_style_mouse_wheel_delta_handler(self, wheel_delta, wheel_steps)
	if self:is_orthographic() then
		-- Mouse wheel zooms orthographic view.
		local zoom_delta = self._orthographic_zoom * 0.25 + 0.01
		
		if wheel_steps > 0 then
			-- Zooming in.
			zoom_delta = -zoom_delta
		end
		
		self._orthographic_zoom = math.max(1, self._orthographic_zoom + zoom_delta)
		Camera.set_orthographic_view(self._camera, -self._orthographic_zoom, self._orthographic_zoom, -self._orthographic_zoom, self._orthographic_zoom)	
	else
		-- Mouse wheel moves camera toward / away from interest point.
		-- We clamp the maximum camera movement distance to make it
		-- less jarring at great distances from the focus point.
		local distance_delta = math.min(math.abs(self._interest_point_distance) * 0.25 + 0.01, 100)
		
		if wheel_steps < 0 then
			-- Moving backward.
			-- If we've previously overshot the interest point, put it in front of the camera
			-- immediately when we start backing away.
			if self._interest_point_distance < 0 then
				self._interest_point_distance = 0
				distance_delta = 0.01
			end
		else
			-- Moving forward.
			distance_delta = -distance_delta
			
			-- If we've overshot the interest point, clamp delta to a sensible speed.
			if self._interest_point_distance < 0 then
				distance_delta = math.max(-3.25, distance_delta)
			end
		end
		
		self._interest_point_distance = self._interest_point_distance + distance_delta
		
		-- Reposition camera to reflect new interest point distance.
		local camera_pose = Camera.local_pose(self._camera)
		local camera_position = Matrix4x4.translation(camera_pose)
		local camera_forward_vector = Matrix4x4.y(camera_pose)
		local offset = camera_forward_vector * -distance_delta
		Matrix4x4.set_translation(camera_pose, camera_position + offset)
		Camera.set_local_pose(self._camera, self._unit, camera_pose)
	end
end

local function maya_style_turntable_rotation_mouse_move_handler(self, x, y)
	-- Disallow rotation when using orthographic projection.
	if self:is_orthographic() then return end
	
	-- Mouse rotates around interest point.
	local mouse_delta = Vector3(x, y, 0) - self._drag_start:unbox()
	local camera_pose = self._drag_start_camera_pose:unbox()
	local camera_right_vector = Matrix4x4.x(camera_pose)
	local rotation_speed = self._rotation_speed
	local relative_rotation = delta_rotation(mouse_delta.x, -mouse_delta.y, camera_right_vector, rotation_speed)
	local camera_position = Matrix4x4.translation(camera_pose)
	local camera_rotation = Matrix4x4.rotation(camera_pose)
	local camera_forward_vector = Matrix4x4.y(camera_pose)
	local interest_point_distance = math.max(0, self._interest_point_distance)
	local interest_point = camera_position + camera_forward_vector * interest_point_distance
	
	-- Concatenate matrix operations into new local pose.
	local apply_initial_rotation = Matrix4x4.from_quaternion(camera_rotation)
	local apply_relative_rotation = Matrix4x4.from_quaternion(relative_rotation)
	local translate_to_interest_point = Matrix4x4.from_translation(interest_point)
	local back_away_from_interest_point = Matrix4x4.from_translation(Vector3(0, -interest_point_distance, 0))
	local operations = { back_away_from_interest_point, apply_initial_rotation, apply_relative_rotation, translate_to_interest_point }
	local new_camera_pose = Array.reduce(operations, Matrix4x4.multiply)
	Camera.set_local_pose(self._camera, self._unit, new_camera_pose)
end

local function maya_style_pan_mouse_move_handler(self, x, y)
	-- Mouse pans camera up, down and sideways.
	local mouse_delta = Vector3(x, y, 0) - self._drag_start:unbox()
	local camera_pose = self._drag_start_camera_pose:unbox()
	local camera_right_vector = Matrix4x4.x(camera_pose)
	local camera_up_vector = Matrix4x4.z(camera_pose)
	local pan_speed = 0
	
	if self:is_orthographic() then
		local a = Camera.world_to_screen(self._camera, Vector3(0, 0, 0))
		local b = Camera.world_to_screen(self._camera, camera_right_vector)
		local dist = Vector3.distance(a, b)
		pan_speed = -1 / dist
	else
		pan_speed = math.abs(self._drag_start_interest_point_distance) * -0.0005
	end
	
	local offset = camera_right_vector * (mouse_delta.x * pan_speed) + camera_up_vector * (mouse_delta.y * pan_speed)
	local camera_position = Matrix4x4.translation(camera_pose)
	Matrix4x4.set_translation(camera_pose, camera_position + offset)
	Camera.set_local_pose(self._camera, self._unit, camera_pose)
end

local function maya_style_dolly_mouse_move_handler(self, x, y)
	local drag_start = self._drag_start:unbox()
	local screen_distance = ((y - drag_start.y) - (x - drag_start.x))
	local is_moving_closer = screen_distance < 0
	
	if self:is_orthographic() then
		-- Mouse zooms orthographic view.
		local zoom_speed = (is_moving_closer and self._drag_start_orthographic_zoom / 3 or self._drag_start_orthographic_zoom) / 500
		local zoom_delta = screen_distance * zoom_speed
		self._orthographic_zoom = math.max(1, self._drag_start_orthographic_zoom + zoom_delta)
		Camera.set_orthographic_view(self._camera, -self._orthographic_zoom, self._orthographic_zoom, -self._orthographic_zoom, self._orthographic_zoom)
	else
		-- Mouse moves camera toward / away from interest point.
		local abs_distance = math.max(1, math.abs(self._drag_start_interest_point_distance))
		local dolly_speed = (is_moving_closer and -(abs_distance / 5 - abs_distance) or (abs_distance * 4)) / 1000
		local distance_delta = screen_distance * dolly_speed
		self._interest_point_distance = self._drag_start_interest_point_distance + distance_delta
		
		-- If we've overshot the interest point, put it in front of the camera immediately when we start backing away.
		if self._interest_point_distance <= 0 and not is_moving_closer then
			self._drag_start_interest_point_distance = 0
			self._interest_point_distance = 0
		end
		
		-- Reposition camera to reflect new interest point distance.
		local camera_pose = self._drag_start_camera_pose:unbox()
		local camera_position = Matrix4x4.translation(camera_pose)
		local camera_forward_vector = Matrix4x4.y(camera_pose)
		local offset = camera_forward_vector * -distance_delta
		Matrix4x4.set_translation(camera_pose, camera_position + offset)
		Camera.set_local_pose(self._camera, self._unit, camera_pose)
	end
end

--------------------------------------------------
-- Pad controls
--------------------------------------------------

local function default_pad_handler(self, dt, pad)
	if not pad then
		return
	end

	-- Apply translation
	local translation = pad.axis(0)
	if Vector3.length(translation) > 0 then			
		local translation_speed = self._translation_speed * dt * 30
		local camera_pose = Camera.local_pose(self._camera)
		local camera_right_vector = Matrix4x4.x(camera_pose)
		local camera_forward_vector = Matrix4x4.y(camera_pose)
		local camera_up_vector = Matrix4x4.z(camera_pose)
		local offset = Vector3(0, 0, 0)
		
		if self:is_orthographic() then
			offset = offset + camera_up_vector * translation_speed * translation.y
		else
			offset = offset + camera_forward_vector * translation_speed * translation.y
		end
		offset = offset + camera_right_vector * translation_speed * translation.x

		local camera_position = Matrix4x4.translation(camera_pose)
		Matrix4x4.set_translation(camera_pose, camera_position + offset)
		Camera.set_local_pose(self._camera, self._unit, camera_pose)
	end

	-- Apply rotation
	if not self:is_orthographic() then
		local rotation = pad.axis(1)*10
		if Vector3.length(rotation) > 0 then
			local camera_pose = Camera.local_pose(self._camera)
			
			rotation.y = - rotation.y

			local q1 = Quaternion( Vector3(0,0,1), -rotation.x * self._rotation_speed )
			local q2 = Quaternion( Matrix4x4.x(camera_pose), -rotation.y * self._rotation_speed )
			local q = Quaternion.multiply(q1, q2)

			local trans = Matrix4x4.translation(camera_pose)
			Matrix4x4.set_translation(camera_pose, Vector3(0,0,0))
			camera_pose = Matrix4x4.multiply(camera_pose, Matrix4x4.from_quaternion(q))
			Matrix4x4.set_translation(camera_pose, trans)
			Camera.set_local_pose(self._camera, self._unit, camera_pose)
		end
	end
end


--------------------------------------------------
-- Control handler tables
--------------------------------------------------

-- Signature: handler(editor_camera, mouse_point)
local EnterControlStyleHandlers = with_default(Func.ignore) {
	MayaStyleTurntableRotation = store_drag_start,
	MayaStylePan = store_drag_start,
	MayaStyleDolly = store_drag_start
}

-- Signature: handler(editor_camera)
local ExitControlStyleHandlers = with_default(Func.ignore) {
	MayaStyleTurntableRotation = clear_drag_start,
	MayaStylePan = clear_drag_start,
	MayaStyleDolly = clear_drag_start,
	QuakeStyleMouseLook = function(editor_camera) editor_camera._interest_point_distance = 10 end
}

-- Signature: handler(editor_camera, dt, controls_table)
local KeyboardControlHandlers = with_default(non_movement_keyboard_control_handler) {
	QuakeStyleMouseLook = quake_style_wasd_movement_keyboard_control_handler
}

-- Signature: handler(editor_camera, x, y)
local MouseMoveHandlers = with_default(Func.ignore) {
	MayaStyleTurntableRotation = maya_style_turntable_rotation_mouse_move_handler,
	MayaStylePan = maya_style_pan_mouse_move_handler,
	MayaStyleDolly = maya_style_dolly_mouse_move_handler
}

-- Signature: handler(editor_camera, dx, dy)
local MouseDeltaHandlers = with_default(Func.ignore) {
	QuakeStyleMouseLook = quake_style_mouse_look_mouse_delta_handler
}

-- Signature: handler(editor_camera, wheel_delta, wheel_steps)
local MouseWheelDeltaHandlers = with_default(Func.ignore) {
	None = maya_style_mouse_wheel_delta_handler,
	QuakeStyleMouseLook = quake_style_mouse_look_mouse_wheel_delta_handler,
}

-- Signature: handler(editor_camera, dt, pad)
local PadControlHandlers = with_default(Func.ignore) {
	QuakeStyleMouseLook = default_pad_handler
}

--------------------------------------------------
--  EditorCamera
--------------------------------------------------

EditorCamera = class(EditorCamera)

function EditorCamera:init(camera, unit)
	assert(camera ~= nil)
	assert(unit ~= nil)
	self._camera = camera
	self._unit = unit
	self._translation_speed = 0.05
	self._rotation_speed = 0.003
	self._orthographic_zoom = 10
	self._interest_point_distance = 10
	self.controls = {}
	self._control_style = "None"
end

function EditorCamera:pose()
	return Camera.local_pose(self._camera)
end

function EditorCamera:set_control_style(style, mouse_point)
	-- Invoke exit and enter handlers.
	ExitControlStyleHandlers[self._control_style](self)
	EnterControlStyleHandlers[style](self, mouse_point)
	
	-- Change into the new event handlers.
	assert(type(KeyboardControlHandlers[style]) == "function")
	assert(type(MouseMoveHandlers[style]) == "function")
	assert(type(MouseDeltaHandlers[style]) == "function")
	assert(type(MouseWheelDeltaHandlers[style]) == "function")
	assert(type(ExitControlStyleHandlers[style]) == "function")
	assert(type(PadControlHandlers[style]) == "function")
	self._control_style = style
end

function EditorCamera:far_range()
	return Camera.far_range(self._camera)
end

function EditorCamera:is_controlled_by_mouse()
	return self._control_style ~= "None"
end

function EditorCamera:mouse_wheel(delta, steps)
	if not self:is_animating() then
		MouseWheelDeltaHandlers[self._control_style](self, delta, steps)
	end
end

function EditorCamera:load_data()
	if Application.has_data("camera") then
		-- Orient the editor camera to the requested pose.
		-- Since the editor camera cannot be rolled, we
		-- only use the forward vector and position.
		self:_stop_animating()
		local requested_local_pose = Application.get_data("camera")
		local requested_rotation = Matrix4x4.rotation(requested_local_pose)
		local rotation = Quaternion.look(Quaternion.forward(requested_rotation), Vector3.up())
		local translation = Matrix4x4.translation(requested_local_pose)
		local local_pose = Matrix4x4.from_quaternion_position(rotation, translation)
		Camera.set_local_pose(self._camera, self._unit, local_pose)
	end
	
	if Application.has_data("camera_translation_speed") then
		local translation_speed = Application.get_data("camera_translation_speed")
		assert(translation_speed > 0)
		self._translation_speed = translation_speed
	end
end

function EditorCamera:save_data()
	Application.set_data("camera", Camera.local_pose(self._camera))
	Application.set_data("camera_translation_speed", self._translation_speed)
end

function EditorCamera:is_orthographic()
	local is_orthographic = Camera.projection_type(self._camera) == Camera.ORTHOGRAPHIC
	return is_orthographic
end

function EditorCamera:update(dt, mouse_point, mouse_delta)
	local before_tm = Camera.local_pose(self._camera)

	if self:is_animating() then
		-- Animate camera towards target position until we've reached our destination.
		-- The user can't control the camera while we're animating.
		local camera_pose = Camera.local_pose(self._camera)
		local camera_position = Matrix4x4.translation(camera_pose)
		local current_to_target = self:target_camera_position() - camera_position
		local frame_distance = self._target_camera_speed * dt
		
		if Vector3.length(current_to_target) <= frame_distance then
			self:_stop_animating()
		else
			local new_camera_position = camera_position + Vector3.normalize(current_to_target) * frame_distance
			Matrix4x4.set_translation(camera_pose, new_camera_position)
			Camera.set_local_pose(self._camera, self._unit, camera_pose)
		end
	else
		-- We're not animating. Respond to user input.
		if mouse_delta.x ~= 0 or mouse_delta.y ~= 0 then
			MouseMoveHandlers[self._control_style](self, mouse_point.x, mouse_point.y)
			MouseDeltaHandlers[self._control_style](self, mouse_delta.x, mouse_delta.y)
		end
		
		if not Dict.is_empty(self.controls) then
			KeyboardControlHandlers[self._control_style](self, dt, self.controls)
		end

		PadControlHandlers[self._control_style](self, dt, Pad1)
	end

	local after_tm = Camera.local_pose(self._camera)
	
	if not Matrix4x4.equal(before_tm, after_tm) then
		self:_notify_state()
	end
end

function EditorCamera:find_viewport_framing(pose, radius)
	local box_center = Matrix4x4.translation(pose)
	local camera_pose = Camera.local_pose(self._camera)
	local box_to_camera_dir = -Matrix4x4.y(camera_pose)
	
	local camera_position = Matrix4x4.translation(camera_pose)
	local horizontal_distance = Func.partial(distance_along_ray, camera_position, Matrix4x4.x(camera_pose))
	local vertical_distance = Func.partial(distance_along_ray, camera_position, Matrix4x4.z(camera_pose))
	
	local box_points = OOBB.points(pose, radius)
	local projections_on_line = Array.map(box_points, function(pt) return Vector3.dot(pt - box_center, box_to_camera_dir) end)
	local horizontal_distances_to_line = Array.mapi(box_points, function(i, pt) return horizontal_distance(pt, projections_on_line[i] * box_to_camera_dir + box_center) end)
	local vertical_distances_to_line = Array.mapi(box_points, function(i, pt) return vertical_distance(pt, projections_on_line[i] * box_to_camera_dir + box_center) end)
	
	local horizontal_fov, vertical_fov = camera_fov(self._camera)
	local required_distances_to_fit_horizontally = Array.mapi(horizontal_distances_to_line, function(i, d) return projections_on_line[i] + d / math.tan(horizontal_fov / 2) end)
	local required_distances_to_fit_vertically = Array.mapi(vertical_distances_to_line, function(i, d) return projections_on_line[i] + d / math.tan(vertical_fov / 2) end)
	local _, required_horizontal_distance = required_distances_to_fit_horizontally:max()
	local _, required_vertical_distance = required_distances_to_fit_vertically:max()
	
	local interest_point_distance = math.max(0, required_horizontal_distance, required_vertical_distance)
	local framing_camera_position = box_center + box_to_camera_dir * interest_point_distance
	return framing_camera_position, interest_point_distance
end

function EditorCamera:frame_oobb(pose, radius)
	local target_camera_position, interest_point_distance = self:find_viewport_framing(pose, radius)
	local distance_to_target = Vector3.distance(Camera.local_position(self._camera), target_camera_position)
	
	if distance_to_target > 0.001 then
		self._target_camera_position = Vector3Box(target_camera_position)
		self._target_camera_speed = distance_to_target * 3
		self._interest_point_distance = interest_point_distance
	end
end

function EditorCamera:world()
	return Camera.local_pose(self._camera)
end

function EditorCamera:set_state(position, rotation, translation_speed, rotation_speed, projection_type, orthographic_zoom, interest_point_distance, far_range)
	assert(position ~= nil)
	assert(rotation ~= nil)
	assert(translation_speed > 0)
	assert(rotation_speed > 0)
	assert(projection_type == Camera.ORTHOGRAPHIC or projection_type == Camera.PERSPECTIVE)
	assert(orthographic_zoom > 0)
	assert(type(interest_point_distance) == "number")
	assert(type(far_range) == "number")
	
	self:_stop_animating()
	local tm = Matrix4x4.from_quaternion_position(rotation, position)
	Camera.set_local_pose(self._camera, self._unit, tm)
	self._translation_speed = translation_speed
	self._rotation_speed = rotation_speed
	Camera.set_projection_type(self._camera, projection_type)
	self._orthographic_zoom = orthographic_zoom
	self._interest_point_distance = interest_point_distance
	Camera.set_far_range(self._camera, far_range)
end

function EditorCamera:camera_ray(x, y)
	local cam = Camera.screen_to_world(self._camera, Vector3(x, 0, y))
	local dir = self:is_orthographic()
		and Matrix4x4.forward(Camera.local_pose(self._camera))
		 or Vector3.normalize(Camera.screen_to_world(self._camera, Vector3(x, 1, y)) - cam)

	return cam, dir
end

function EditorCamera:screen_size_to_world_size(position, size)
	local camera_right_vector = Matrix4x4.x(Camera.world_pose(self._camera))
	local pixel_scale = self:screen_length_at_position(position, camera_right_vector)
	return size / pixel_scale
end

function EditorCamera:screen_length_at_position(position, vector)
	local a = Camera.world_to_screen(self._camera, position)
	local b = Camera.world_to_screen(self._camera, position + vector)
	local screen_length = Vector3.distance(a, b)
	return screen_length
end

function EditorCamera:is_animating()
	return self._target_camera_position ~= nil and self._target_camera_speed ~= nil
end

function EditorCamera:_stop_animating()
	if self:is_animating() then
		local camera_pose = Camera.local_pose(self._camera)
		Matrix4x4.set_translation(camera_pose, self:target_camera_position())
		Camera.set_local_pose(self._camera, self._unit, camera_pose)
		self._target_camera_position = nil
		self._target_camera_speed = nil
	end
	
	assert(not self:is_animating())
end

function EditorCamera:target_camera_position()
	if self._target_camera_position == nil then return nil end

	return self:is_orthographic()
	   and Project.point_on_plane(self._target_camera_position:unbox(), self._orthographic_plane:unbox())
	    or self._target_camera_position:unbox()
end

function EditorCamera:set_perspective()
	if not self:is_orthographic() then return end

	assert(self._perspective_local_pose ~= nil)
	assert(self._perspective_near_range ~= nil)
	assert(self._perspective_far_range ~= nil)
	Camera.set_local_pose(self._camera, self._unit, self._perspective_local_pose:unbox())
	Camera.set_near_range(self._camera, self._perspective_near_range)
	Camera.set_far_range(self._camera, self._perspective_far_range)
	Camera.set_projection_type(self._camera, Camera.PERSPECTIVE)
	self._perspective_local_pose = nil
	self._perspective_near_range = nil
	self._perspective_far_range = nil
	self:_notify_state()
end

function EditorCamera:set_orthographic(world_center, world_radius, focus_point, front, up)
	self:_stop_animating()
	local camera_pose = Camera.local_pose(self._camera)

	if not self:is_orthographic() then
		assert(self._perspective_local_pose == nil)
		assert(self._perspective_near_range == nil)
		assert(self._perspective_far_range == nil)
		self._perspective_local_pose = Matrix4x4Box(camera_pose)
		self._perspective_near_range = Camera.near_range(self._camera)
		self._perspective_far_range = Camera.far_range(self._camera)
	end

	if not world_center then
		world_center = Vector3(0,0,0)
		world_radius = Vector3(1,1,1)
	end

	local padding = 1
	local distance_along_ray = padding + Math.ray_box_intersection(world_center, -front, Matrix4x4.from_translation(world_center), world_radius)
	local back_face_point = world_center - front * distance_along_ray
	local front_face_point = world_center + front * distance_along_ray
	local camera_plane = Plane.from_point_and_normal(back_face_point, front)
	self._orthographic_plane = QuaternionBox(camera_plane)

	local camera_position = Project.point_on_plane(focus_point, camera_plane)
	local camera_rotation = Quaternion.look(front, up)
	Matrix4x4.set_rotation(camera_pose, camera_rotation)
	Matrix4x4.set_translation(camera_pose, camera_position)
	Camera.set_local_pose(self._camera, self._unit, camera_pose)
	Camera.set_projection_type(self._camera, Camera.ORTHOGRAPHIC)
	Camera.set_near_range(self._camera, padding)
	Camera.set_far_range(self._camera, Vector3.distance(back_face_point, front_face_point))
	Camera.set_orthographic_view(self._camera, -self._orthographic_zoom, self._orthographic_zoom, -self._orthographic_zoom, self._orthographic_zoom)
	self:_notify_state()
end

function EditorCamera:_notify_state()
	Application.console_send {
		type = "camera", 
		position = Camera.local_position(self._camera), 
		rotation = Camera.local_rotation(self._camera),
		translation_speed = self._translation_speed, 
		rotation_speed = self._rotation_speed,
		projection_type = Camera.projection_type(self._camera),
		orthographic_zoom = self._orthographic_zoom,
		interest_point_distance = self._interest_point_distance,
		far_range = Camera.far_range(self._camera)
	}
end
