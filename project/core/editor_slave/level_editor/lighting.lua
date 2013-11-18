--------------------------------------------------
-- Utility functions
--------------------------------------------------

local normalized_color_components = Func.compose(Quaternion.to_elements, Func.partial(Tuple.map, Op.div(255)))
local color_with_normalized_components = Func.compose(Func.partial(Tuple.map, Op.mul(255)), Color)

local function component_multiply(color_a, color_b)
	local aa, ar, ag, ab = normalized_color_components(color_a)
	local ba, br, bg, bb = normalized_color_components(color_b)
	local color = color_with_normalized_components(aa * ba, ar * br, ag * bg, ab * bb)
	return color
end

local function component_add(color_a, color_b)
	local aa, ar, ag, ab = Quaternion.to_elements(color_a)
	local ba, br, bg, bb = Quaternion.to_elements(color_b)
	local c = Func.compose(Func.partial(math.max, 0), Func.partial(math.min, 255))
	local result = Color(c(aa + ba), c(ar + br), c(ag + bg), c(ab + bb))
	return result
end


--------------------------------------------------
-- Lighting
--------------------------------------------------

Lighting = Lighting or {}

function Lighting.ambient(light_color, surface_color)
	return component_multiply(light_color, surface_color)
end

function Lighting.diffuse(light_dir, light_color, surface_normal, surface_color)
	local diffuse_factor = math.max(0, Vector3.dot(-surface_normal, light_dir));
	local contribution = Blend.color_with_intensity(component_multiply(light_color, surface_color), diffuse_factor)
	return contribution
end

function Lighting.lambert(ambient_color, diffuse_dir, diffuse_color, surface_normal, surface_color)
	local ambient_contribution = Lighting.ambient(ambient_color, surface_color)
	local diffuse_contribution = Lighting.diffuse(diffuse_dir, diffuse_color, surface_normal, surface_color)
	local color = component_add(ambient_contribution, diffuse_contribution)
	return color
end
