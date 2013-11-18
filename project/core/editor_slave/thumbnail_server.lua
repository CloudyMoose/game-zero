function boot()
	Application.set_autoload_enabled(true)
	require 'core/editor_slave/freeflight'
end

-----------------------------------------------------------------------------------------------------

function class(klass, super)
	if not klass then
		klass = {}
		
		local meta = {}
		meta.__call = function(self, ...)
			local object = {}
			setmetatable(object, klass)
			if object.init then object:init(...) end
			return object
		end
		setmetatable(klass, meta)
	end
	
	if super then
		for k,v in pairs(super) do
			klass[k] = v
		end
	end
	klass.__index = klass
	
	return klass
end

function find_class_from_name(name)
	local start = string.find(string.reverse(name), ".", 1, true)
	local res = start and string.sub(name, 1, #name - start)
	local ext = start and string.sub(name, #name - start + 2)
	return res or "", ext or ""
end

-----------------------------------------------------------------------------------------------------

ThumbnailClasses = ThumbnailClasses or {}

TextureThumb = class(TextureThumb)
ThumbnailClasses.texture = TextureThumb

function TextureThumb:init(tns, req)
	self._tns = tns
	self._request = req
	self._image, self._w, self._h, self._format = World.create_texture_image(tns._world, req.name)
end

function TextureThumb:ready_to_cap()
	return true
end

function TextureThumb:update(dt)
	local w, h = Gui.resolution()
	local y = h - (self._request.h or h)
	Gui.texture(self._tns._gui, "thumbnail_" .. self._format, self._image, Vector3(0, y, 0), Vector3(self._request.w or w, self._request.h or h, 0))
end

function TextureThumb:destroy()
	World.destroy_texture_image(self._tns._world, self._image)
end

-----------------------------------------------------------------------------------------------------

ThumbnailServer = ThumbnailServer or {}
EditorApi = ThumbnailServer

ThumbnailServer.timeout = 20000
ThumbnailServer.sleep = 100

function ThumbnailServer:init()
	self._last_ping = 0
	self._ref_table = {}
	self._requests = {}

	self:init_world()
	self:init_camera()
end

function ThumbnailServer:init_world()
	self._world = Application.new_world()
	self._gui = World.create_screen_gui(self._world, "immediate", "material", "core/editor_slave/gui/gui")
	
	self._viewport = Application.create_viewport(self._world, "default")
	self._shading_environment = World.create_shading_environment(self._world)
end

function ThumbnailServer:init_camera()
	local camera_unit = World.spawn_unit(self._world, "core/units/camera")
	self._camera = Unit.camera(camera_unit, "camera")
	self._freeflight = FreeFlight(self._camera, camera_unit)
	self:set_camera_distance(10)
end

function ThumbnailServer:set_camera_distance(d)
	if d == self._camera_distance then return end

	local camera_pos = Vector3(0,-d,1)
	local camera_look = Vector3(0,0,1)
	local camera_dir = Vector3.normalize(camera_look - camera_pos)
	local camera_rot = Quaternion.look( camera_dir, Vector3(0,0,1) )
	self._freeflight:set_state(camera_pos, camera_rot)
	self._camera_distance = d
end

function ThumbnailServer:generate(instance_id, name, id, w, h, ...)
	self._ref_table[tostring(instance_id)] = true
	local n, c = find_class_from_name(name)
	table.insert(self._requests, {class = c, name = n, path = name, id = id, w = w, h = h, data = {...}})
end

function ThumbnailServer:cancel(id)
	for index, req in ipairs(self._requests) do
		if req.id == id and req ~= self._current_request then
			table.remove(self._requests, index)
			return
		end
	end
end

function ThumbnailServer:close(instance_id)
	self._ref_table[tostring(instance_id)] = nil
	if next(self._ref_table) then
		return
	end
	Application.quit()
end

function ThumbnailServer:ping(instance_id)
	self._ref_table[tostring(instance_id)] = true
	self._last_ping = Application.time_since_launch()
end

function ThumbnailServer:shutdown()
	Application.destroy_viewport(self._world, self._viewport)
	World.destroy_shading_environment(self._world, self._shading_environment)
	Application.release_world(self._world)
end

function ThumbnailServer:render()
	ShadingEnvironment.blend(self._shading_environment, {"default", 1})
	ShadingEnvironment.apply(self._shading_environment)
	Application.render_world(self._world, self._camera, self._viewport, self._shading_environment)
end

function ThumbnailServer:poll_request()
	if not self._current_request then
		while next(self._requests) do
			self._current_request = assert(self._requests[1])
			table.remove(self._requests, 1)

			local req = self._current_request
			local c = ThumbnailClasses[req.class]

			if c and Application.can_get(req.class, req.name) then
				self._current_request.obj = c(self, self._current_request)
				return self._current_request
			else
				--print("Invalid resource: " .. req.name)
				Application.console_send({type = "thumbnail", id = req.id, valid = false, class = req.class})
				self._current_request = nil
			end
		end
	end
	return self._current_request
end

function ThumbnailServer:update(dt)
	self._freeflight:update(dt)
	
	if self:poll_request() then
		local req = self._current_request
		req.obj:update(dt)

		if not self._frame_cap and req.obj:ready_to_cap() then
			local w, h = Gui.resolution()
			self._frame_cap = FrameCapture.screen_shot("thumbnail_send", req.id, req.w or w, req.h or h)
		end

		if self._frame_cap and FrameCapture.completed(self._frame_cap) then
			req.obj:destroy()
			self._current_request = nil
			self._frame_cap = nil
		end
	elseif ThumbnailServer.sleep > 0 then
		Application.sleep(ThumbnailServer.sleep)
	end

	World.update(self._world, dt)

	local ticks = Application.time_since_launch()
	if ticks - self._last_ping > ThumbnailServer.timeout / 1000 then
		Application.quit()
	end
end

----------------------------------------------------------------------------------------

function init()
	boot()
	ThumbnailServer:init()
end

function shutdown()
	ThumbnailServer:shutdown()
end

function update(dt)
	ThumbnailServer:update(dt)
end

function render()
	ThumbnailServer:render()
end
