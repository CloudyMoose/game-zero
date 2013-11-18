 LevelStory = class(LevelStory)

function LevelStory:init()
	self.world = LevelEditor.world
	self.onion_skin_lines = World.create_line_object(self.world)
end

function LevelStory:preview(story_data, ids, time)
 	local teller = Application.main_world():storyteller()
 	local blob = teller:editor_compile(story_data, unpack(ids))
 	local units = Array.map(ids, function (id) return LevelEditor.objects[id]._unit end)
 	local story = teller:editor_play(blob, unpack(units))
 	teller:set_speed(story, 0)

 	self:draw_onion_skins(teller, story, time, units)

 	teller:set_time(story, time)
 	teller:editor_write_out()
 	teller:stop(story)
end

function LevelStory:update()
end

function LevelStory:draw_onion_skins(teller, story, time, units)
	LineObject.reset(self.onion_skin_lines)

	local skin_step = 1/10
	local skins_before = 10
	local skins_after = 10
	for i=-skins_before,skins_after do
		local skip = i==0
		local t = time + i*skin_step
		if t <=0 then skip = true end
		local opacity = 1 - (math.abs(i)-1) / math.max(skins_before, skins_after)
		if not skip then
			teller:set_time(story, t)
			teller:editor_write_out()
			for _,u in ipairs(units) do
				self:draw_onion_skin(u, opacity)
			end
		end
	end

	LineObject.dispatch(self.world, self.onion_skin_lines)
end

function LevelStory:draw_onion_skin(unit, opacity)
	local color = Color(opacity*128, 255, 255, 0)
	World.update_unit(self.world, unit)
	LineObject.add_unit_meshes(self.onion_skin_lines, unit, color)
end

function LevelStory:finish_preview(ids)
	local refs = Array.map(ids, SceneElementRef.make)
	local units = Array.map(ids, Func.of_table(LevelEditor.objects))
	local new_positions = Array.map(units, function (level_object) return level_object:local_position(nil) end )
	local new_rotations = Array.map(units, function (level_object) return level_object:local_rotation(nil) end )
	local new_scales = Array.map(units, function (level_object) return level_object:local_scale(nil) end )

	-- Call level_object:complete_move() on all moved objects.
	Set.of_array(refs, SceneElementRef.object_id):map(Func.of_table(LevelEditor.objects)):iter(Func.method("complete_move"))

	-- Notify the level editor of the new poses, registering an undo entry.
	Application.console_send {
		type = "elements_moved",
		scene_element_refs = refs,
		positions = new_positions,
		rotations = new_rotations,
		scales = new_scales,
		fix_story_rotation_angles = true
	}
end

function LevelStory:end_story_mode()
	LineObject.reset(self.onion_skin_lines)
	LineObject.dispatch(self.world, self.onion_skin_lines)
end
