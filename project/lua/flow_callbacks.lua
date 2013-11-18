FlowCallbacks = FlowCallbacks or {}

local M = FlowCallbacks

local font = 'core/performance_hud/debug'
local font_material = 'debug'

function M.message(t)
	local unit = t.unit
	local offset_box = Vector3Box(t.offset or Vector3(0,0,0))
	local text = t.text or "Text"
	local duration = t.duration
	local size = t.size or 1.0
	local color_box = Vector3Box(t.color or Vector3(255,255,255))

	local update = function(dt)
		local pos = Vector3(0,0,0)
		if unit then pos = Unit.world_position(unit, 0) end
		pos = pos + offset_box:unbox()

		local world = Unit.world(unit)
		local rot = Quaternion.look(pos - Matrix4x4.translation(World.debug_camera_pose(world)))
		local tm = Matrix4x4.from_quaternion_position(rot, pos)

		local cu = color_box:unbox()
		local color = Color(cu.x, cu.y, cu.z)
		local min, max = Gui.text_extents(Sample.scene.world_gui, text, font, size)
		Gui.text_3d(Sample.scene.world_gui, text, font, size, font_material, tm, -(min+max)/2, 0, color)
	end

	Sample.scene:add_animation(update)
	if duration then
		Sample.scene:add_trigger(duration, function() print "uninstall" Sample.scene:remove_animation(update) end)
	end
end