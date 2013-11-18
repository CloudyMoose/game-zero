Sample.Character = class(Sample.Character)
local M = Sample.Character

local U = require 'lua/utility'

local translation_speed = 5.0
local rotation_speed = 1.0
local jump_velocity = 5.0
local glue_translation_speed = -2
local gravity = 9.82
local camera_offset = 1.7
local crouching_camera_offset = 0.8
local camera_behind = 5.0

local crouch_test_offset = 0.11
local mover_height = 2
local mover_radius = 0.5

function M:init(world, camera, camera_unit)
	self.camera = camera
	self.camera_unit = camera_unit

	self.unit = World.spawn_unit(world, "units/character")
	self.mover = Unit.mover(self.unit)
	self.crouching = false

	self.camera_mode = "first-person"
	self.velocity = Vector3Box()
end

local function get_input()
	local input = {}
	if U.is_pc() then
		input.pan = Mouse.axis(Mouse.axis_index("mouse"))
		input.move = Vector3 (
			Keyboard.button(Keyboard.button_index("d")) - Keyboard.button(Keyboard.button_index("a")),
			Keyboard.button(Keyboard.button_index("w")) - Keyboard.button(Keyboard.button_index("s")),
			0
		)
		input.jump = Keyboard.pressed(Keyboard.button_index("space"))
		input.crouch = Keyboard.pressed(Keyboard.button_index("left ctrl"))
	elseif Sample.show_help then
		input.pan = Vector3(0,0,0)
		input.move = Vector3(0,0,0)
	elseif Application.platform() == "ps3" or Application.platform() == "x360" then
		input.pan = Pad1.axis(Pad1.axis_index("right")) * 10
		Vector3.set_y(input.pan, -input.pan.y)
		input.move = Pad1.axis(Pad1.axis_index("left"))
		input.jump = Pad1.pressed(Pad1.button_index(U.plat(nil, "cross", "a")))
		input.crouch = Pad1.pressed(Pad1.button_index(U.plat(nil, "circle", "b")))
	end
	return input
end

local function compute_rotation(self, input, dt)
	local qo = Camera.local_rotation(self.camera, self.camera_unit)
	local cm = Matrix4x4.from_quaternion(qo)

	local q1 = Quaternion( Vector3(0,0,1), -Vector3.x(input.pan) * rotation_speed * dt )
	local q2 = Quaternion( Matrix4x4.x(cm), -Vector3.y(input.pan) * rotation_speed * dt )
	local q = Quaternion.multiply(q1, q2)
	local qres = Quaternion.multiply(q, qo)
	return qres
end

local function compute_translation(self, input, dt)
	local move = Vector3(0,0,0)

	local pose = Unit.local_pose(self.unit, 0)
	Matrix4x4.set_translation(pose, Vector3(0,0,0))
	local local_move = input.move*translation_speed*dt
	move = Matrix4x4.transform(pose, local_move)

	if Mover.standing_frames(self.mover) > 0 then
		if input.jump then
			self.velocity:store(0,0,jump_velocity)
		else
			self.velocity:store(0,0,0)
			move.z = move.z + glue_translation_speed * dt
		end
	else
		local v = self.velocity:unbox()
		v.z = v.z - dt * gravity
		self.velocity:store(v)
	end
	
	local v = self.velocity:unbox()
	move = move + dt*v
	Mover.move(self.mover, move, dt)
	return Mover.position(self.mover)
end

function M:update(dt)
	local input = get_input()

	if input.crouch then
		if not self.crouching then
			self.mover = Unit.set_mover(self.unit, "crouch")
			self.crouching = true
		elseif Unit.mover_fits_at(self.unit, "default", Mover.position(self.mover)) then
			self.mover = Unit.set_mover(self.unit, "default")
			self.crouching = false
		end
	end

	local q = compute_rotation(self, input, dt)
	local p = compute_translation(self, input, dt)

	local rot_x = Quaternion.rotate(q, Vector3(1,0,0))
	rot_x.z = 0
	rot_x = Vector3.normalize(rot_x)
	local angle = math.atan2(rot_x.y, rot_x.x)
	local project_q = Quaternion(Vector3(0,0,1), angle)

	local pose = Matrix4x4.from_quaternion_position(project_q,p)
	Unit.set_local_pose(self.unit, 0, pose)

	local cam_pose = Matrix4x4.from_quaternion(q)
	local cam_p
	if self.camera_mode == "first-person" then
		if self.crouching then
			cam_p = p + Vector3(0,0,crouching_camera_offset)
		else
			cam_p = p + Vector3(0,0,camera_offset)
		end
	elseif self.camera_mode == "third-person" then
		cam_p = p + Vector3(0,0,camera_offset) - Matrix4x4.y(cam_pose)*camera_behind
	end
	Matrix4x4.set_translation(cam_pose, cam_p)
	Camera.set_local_pose(self.camera, self.camera_unit, cam_pose)

	local tw = Unit.world(self.unit):timpani_world()
	tw:set_listener(0, cam_pose)
	tw:set_listener_mode(0, TimpaniWorld.LISTENER_3D)
end

function M:cycle_camera_mode()
	local modes = {"third-person", "first-person"}
	for i=1,#modes-1 do
		if self.camera_mode == modes[i] then
			self.camera_mode = modes[i+1]
			return
		end
	end
	self.camera_mode = modes[1]
end

return M