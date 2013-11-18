FreeFlight = FreeFlight or {}
FreeFlightMT = FreeFlightMT or {}

setmetatable(FreeFlight, FreeFlightMT)
FreeFlight.__index = FreeFlight

FreeFlightMT.__call = function(self, ...)
	self = {}
	setmetatable(self, FreeFlight)
	self:init(...)
	return self
end

function FreeFlight:init(camera, unit)
	self.camera = camera
	self.unit = unit
	self.translation_speed = 0.05
	self.rotation_speed = 0.003
	
	self.input = {}

	self.mouse_axis = Mouse.axis_index("mouse")
	self.wheel_axis = Mouse.axis_index("wheel")
	
	self.key_w = Keyboard.button_index("w")
	self.key_d = Keyboard.button_index("d")
	self.key_a = Keyboard.button_index("a")
	self.key_s = Keyboard.button_index("s")
	self.key_q = Keyboard.button_index("q")
	self.key_e = Keyboard.button_index("e")
end

function FreeFlight:translate(v)
	local cm = Camera.local_pose(self.camera)
	local trans = Matrix4x4.translation(cm)
	Matrix4x4.set_translation(cm, trans + v)
	Camera.set_local_pose(self.camera, self.unit, cm)
end

function FreeFlight:get_input(input)
	input.translation = Vector3(0,0,0)
	input.rotation = Vector3(0,0,0)
	input.translation_speed_change = 0

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
	if Keyboard.button(self.key_e) > 0 then
		input.translation.z = input.translation.z + 1
	end
	if Keyboard.button(self.key_q) > 0 then
		input.translation.z = input.translation.z - 1
	end
	
	if self.mouse_axis then input.rotation = input.rotation + Mouse.axis(self.mouse_axis) end
	
	-- Only apply pad input when window has focus
	if Window and Window.mouse_focus() then
		input.translation = input.translation + Pad1.axis(0)
		local pad_rotation = Pad1.axis(1) * 10
		pad_rotation.y = -pad_rotation.y
		input.rotation = input.rotation + pad_rotation
	end
	
	if self.wheel_axis then
		input.translation_speed_change = Vector3.y(Mouse.axis(self.wheel_axis))
	end
end

function FreeFlight:update(dt)
	self:get_input(self.input)
	local input = self.input

	if self.wheel_axis then
		local translation_change_speed = self.translation_speed * 0.1
		self.translation_speed = self.translation_speed + input.translation_speed_change * translation_change_speed
		if self.translation_speed < 0.001 then
			self.translation_speed = 0.001
		end
	end
	
	if Vector3.length(input.translation) == 0 and Vector3.length(input.rotation) == 0 then
		return
	end
	
	local cm = Camera.local_pose(self.camera)
	local trans = Matrix4x4.translation(cm)
	Matrix4x4.set_translation(cm, Vector3(0,0,0))
	
	local q1 = Quaternion( Vector3(0,0,1), -input.rotation.x * self.rotation_speed )
	local q2 = Quaternion( Matrix4x4.x(cm), -input.rotation.y * self.rotation_speed )
	local q = Quaternion.multiply(q1, q2)
	cm = Matrix4x4.multiply(cm, Matrix4x4.from_quaternion(q))
	
	local offset = Matrix4x4.transform_without_translation(cm, input.translation * self.translation_speed)
	trans = Vector3.add(trans, offset)
	Matrix4x4.set_translation(cm, trans)
	Camera.set_local_pose(self.camera, self.unit, cm)
	
	self:send_state()
	self:save_data()
end

function FreeFlight:load_data()
	if Application.has_data("camera") then
		Camera.set_local_pose(self.camera, self.unit, Application.get_data("camera"))
	end
	if Application.has_data("camera_translation_speed") then
		self.translation_speed = Application.get_data("camera_translation_speed")
	end
end

function FreeFlight:save_data()
	Application.set_data("camera", Camera.local_pose(self.camera, self.camera_unit))
	Application.set_data("camera_translation_speed", self.translation_speed)
end

function FreeFlight:send_state()
	Application.console_send {
		type = "camera", 
		position = Camera.local_position(self.camera), 
		rotation = Camera.local_rotation(self.camera)
	}
end

function FreeFlight:set_state(pos, rot)
	Camera.set_local_position(self.camera, self.unit, pos)
	Camera.set_local_rotation(self.camera, self.unit, rot)
end

function FreeFlight:pose()
	return Camera.local_pose(self.camera, self.camera_unit)
end
