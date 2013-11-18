CubemapGenerator = class(CubemapGenerator)

function CubemapGenerator:init(world)
	self.world = world
	self.unit = World.spawn_unit(self.world, "core/units/camera")
	self.camera = Unit.camera(self.unit, "camera")
end

function CubemapGenerator:create(position, shading_environment, filename)
	local viewport = Application.create_viewport(self.world, "default")	

	ShadingEnvironment.blend(shading_environment, {"default", 1})
	ShadingEnvironment.apply(shading_environment)
	Application.set_render_setting("generate_cubemap", "true")
	
	Application.create_cubemap(self.world, viewport, shading_environment, position, "cubemap_result", filename)
		
	Application.set_render_setting("generate_cubemap", "false")
end