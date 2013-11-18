TopDown = TopDown or {}
TopDownMT = TopDownMT or {}

setmetatable(TopDown, TopDownMT)
TopDown.__index = TopDown

TopDownMT.__call = function(self, ...)
	self = {}
	setmetatable(self, TopDown)
	self:init(...)
	return self
end

function TopDown:init(camera, unit)
	self.camera = camera
	self.unit = unit

	self.input = {}

	self.wheel_axis = Mouse.axis_index("wheel")

	self.key_w = Keyboard.button_index("w")
	self.key_d = Keyboard.button_index("d")
	self.key_a = Keyboard.button_index("a")
	self.key_s = Keyboard.button_index("s")
	self.key_q = Keyboard.button_index("q")
	self.key_e = Keyboard.button_index("e")
end

function TopDown:get_input(input)
	input.translation = Vector3(0,0,0)
	input.zoom = 0

	if Keyboard.button(self.key_w) > 0 then
		input.translation.y = input.translation.y + 1
	end
	if Keyboard.button(self.key_s) > 0 then
		input.translation.y = input.translation.y - 1
	end
	if Keyboard.button(self.key_a) > 0 then
		input.translation.x = input.translation.x - 1
	end
	if Keyboard.button(self.key_d) > 0 then
		input.translation.x = input.translation.x + 1
	end
	
	-- Only apply pad input when window has focus
	if Window and Window.mouse_focus() then
		input.translation = input.translation + Pad1.axis(0)
	end
	
	if self.wheel_axis then
		input.zoom = -Vector3.y(Mouse.axis(self.wheel_axis))
	end
end

function TopDown:update(dt)
	self:get_input(self.input)
	local input = self.input

	if Vector3.length(input.translation) == 0 and input.zoom == 0 then
		return
	end

	local cm = Camera.local_pose(self.camera)

	local t = Matrix4x4.translation(cm)
	t = t + input.translation * t.z * dt
	t.z = t.z * math.exp(input.zoom * dt * 2.0)
	Matrix4x4.set_translation(cm, t)

	Camera.set_local_pose(self.camera, self.unit, cm)
	self:send_state()
end

function TopDown:load_data()
	if Application.has_data("camera") then
		Camera.set_local_pose(self.camera, self.unit, Application.get_data("camera"))
	end
	if Application.has_data("camera_translation_speed") then
		self.translation_speed = Application.get_data("camera_translation_speed")
	end
end

function TopDown:save_data()
	Application.set_data("camera", Camera.local_pose(self.camera, self.camera_unit))
	Application.set_data("camera_translation_speed", self.translation_speed)
end

function TopDown:send_state()
	Application.console_send {
		type = "camera", 
		position = Camera.local_position(self.camera), 
		rotation = Camera.local_rotation(self.camera)
	}
end

function TopDown:set_state(pos, rot)
	Camera.set_local_position(self.camera, self.unit, pos)
	Camera.set_local_rotation(self.camera, self.unit, rot)
end

function TopDown:pose()
	return Camera.local_pose(self.camera, self.camera_unit)
end

function TopDown:listener_size()
	local cm = Camera.local_pose(self.camera)
	local t = Matrix4x4.translation(cm)
	function tow(x,y) return Camera.screen_to_world(self.camera, Vector3(x, t.z, y)) end

	local w,h = Application.resolution()
	local rx = Vector3.distance( tow(w, h/2), tow(w/2, h/2) )
	local ry = Vector3.distance( tow(w/2,h), tow(w/2, h/2) )
	return Vector3(rx, ry, 0)
end