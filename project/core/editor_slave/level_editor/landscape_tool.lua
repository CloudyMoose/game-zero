LandscapeTool = class(LandscapeTool, Tool)

function LandscapeTool:init()
	self._edit_unit = nil	
	self._show_marker = true
	self._brush = "pencil_brush"
	
	self.brush_radius = 2.5
	self.brush_strength = 0.1
	self.brush_falloff = 0.9
	self.layer = 0
	self.channel = 0
end

function LandscapeTool:is_highlight_suppressed()
	return self:is_editing()
end

function LandscapeTool:is_editing()
	return self._edit_unit ~= nil
end

function LandscapeTool:start_editing(unit_id, new_landscape)
	local unit_object = LevelEditor.objects[unit_id]
	local unit = unit_object._unit
	LevelEditor.scatter_manager:hide_scatter_for_unit(unit_id);
	LandscapeEditor.load(Unit.landscape(unit, 0), new_landscape, LevelEditor.world)
	self._edit_unit = unit
	unit_object:highlight_changed()
end

function LandscapeTool:stop_editing(unit_id)
	local unit_object = LevelEditor.objects[unit_id]
	local unit = unit_object._unit
	LandscapeEditor.unload(Unit.landscape(unit, 0), LevelEditor.world)
	LevelEditor.scatter_manager:show_scatter_for_unit(unit_id);
	self._edit_unit = nil
	unit_object:highlight_changed()
end

function LandscapeTool:select_brush(brush)
	self._brush = brush
end

function LandscapeTool:find_landscape(units)	
	for _,id in ipairs(units) do
		local u = LevelEditor.objects[id]._unit
		if u and Unit.num_landscapes(u) > 0 then
			local data = {}
			data["landscape"] = id
			Application.console_send { type = "select_landscape", data = data }
			return
		end		
	end
end

function LandscapeTool:change_material(layer, channel, material, material_resource)
	LandscapeEditor.change_material(LevelEditor.world, Unit.landscape(self._edit_unit, 0), layer, channel, material, material_resource)
end

function LandscapeTool:update_brush_pos(mouse_x, mouse_y)	
	local p, y = LevelEditor:camera_ray(mouse_x, mouse_y)
	local z = 0
	local t = (z-Vector3.z(p))/Vector3.z(y)
	return p + y*t
end

function LandscapeTool:mouse_down(x, y)
	self._mouse_pressed = true
end

function LandscapeTool:mouse_move(x, y)
end

function LandscapeTool:mouse_up()
	self._mouse_pressed = false
	LandscapeEditor.invalidate_decoration(LevelEditor.world, self.brush_radius)
end

local function is_strength_adjust_modifier_held()
	return LevelEditor.modifiers.shift == true
end

local function is_falloff_adjust_modifier_held()
	return LevelEditor.modifiers.control == true
end

function LandscapeTool:mouse_wheel(delta, steps)
	local multiplier = steps < 0 and 1 / 1.2 or 1.2

	if is_falloff_adjust_modifier_held() then
		if self.brush_falloff == 0 then
			if steps > 0 then
				self.brush_falloff = 0.01
			end
		else
			multiplier = steps < 0 and 1.2 or 1/1.2;
			self.brush_falloff = math.min(math.max(0, self.brush_falloff * multiplier), 2)
		end
		assert(self.brush_falloff >= 0 and self.brush_falloff <= 2)
		LevelEditor:flash(string.format("Falloff: %.3f",self.brush_falloff))
	elseif is_strength_adjust_modifier_held() then
		self.brush_strength = math.max(0.01, self.brush_strength * multiplier)
		assert(self.brush_strength > 0)
		LevelEditor:flash(string.format("Strength: %.3f",self.brush_strength))
	else
		self.brush_radius = math.max(0.01, self.brush_radius * multiplier)
		assert(self.brush_radius > 0)
		LevelEditor:flash(string.format("Radius: %.3f",self.brush_radius))
	end
end

function LandscapeTool:update()
	if self._edit_unit then
		local mouse_pos = Vector3(LevelEditor.mouse.pos.x, 0, LevelEditor.mouse.pos.y)
		local p, y = LevelEditor:camera_ray(mouse_pos.x, mouse_pos.z)
		
		local strength = self.brush_strength
		local radius = self.brush_radius
		local falloff = self.brush_falloff
		local channel = self.channel
		local layer = self.layer
		local brush_color = Vector3(1,1,1)
		local brush_type = 1
		if layer > 0 then
			local brush_colors = { 	Vector3(1,0,0), Vector3(0,1,0), Vector3(0,0,1), Vector3(1,1,1) }
			brush_color = brush_colors[channel + 1]
			brush_type = 0
		end		
		
		if not LevelEditor.editor_camera:is_controlled_by_mouse() then
			if not self._mouse_pressed then
				LandscapeEditor.brush(Unit.landscape(self._edit_unit, 0), "sample_height", mouse_pos, LevelEditor.camera, LevelEditor.world, radius, strength, falloff, p, y, layer, channel, brush_color, brush_type)	
			end

			LandscapeEditor.brush(Unit.landscape(self._edit_unit, 0), "mark", mouse_pos, LevelEditor.camera, LevelEditor.world, radius, strength, falloff, p, y, layer, channel, brush_color, brush_type)

			if self._mouse_pressed then
				if LevelEditor.modifiers.shift then
					LandscapeEditor.brush(Unit.landscape(self._edit_unit, 0), "smooth", mouse_pos, LevelEditor.camera, LevelEditor.world, radius, strength, falloff, p, y, layer, channel, brush_color, brush_type)
				else
					if self._brush == "pencil_brush" then
						if layer == 0 then
							strength = strength * 0.001
						end				
						if LevelEditor.modifiers.control then
							LandscapeEditor.brush(Unit.landscape(self._edit_unit, 0), "draw_sub", mouse_pos, LevelEditor.camera, LevelEditor.world, radius, strength, falloff, p, y, layer, channel, brush_color, brush_type)
						else
							LandscapeEditor.brush(Unit.landscape(self._edit_unit, 0), "draw_add", mouse_pos, LevelEditor.camera, LevelEditor.world, radius, strength, falloff, p, y, layer, channel, brush_color, brush_type)
						end				
					elseif self._brush == "smooth_brush" then
						LandscapeEditor.brush(Unit.landscape(self._edit_unit, 0), "smooth", mouse_pos, LevelEditor.camera, LevelEditor.world, radius, strength, falloff, p, y, layer, channel, brush_color, brush_type)
					else
						LandscapeEditor.brush(Unit.landscape(self._edit_unit, 0), "flatten", mouse_pos, LevelEditor.camera, LevelEditor.world, radius, strength, falloff, p, y, layer, channel, brush_color, brush_type)
					end
				end
			end
		end
	end
end