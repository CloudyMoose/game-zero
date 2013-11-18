require "core/editor_slave/array"
require "core/editor_slave/class"
require "core/editor_slave/dict"
require "core/editor_slave/func"
require "core/editor_slave/nilable"
require "core/editor_slave/op"

Vector3Boxed = class(Vector3Boxed)

function Vector3Boxed:init(x, y, z)
	if x and not y and not z then
		self:box(x)
	else
		self:box(Vector3(x or 0, y or 0, z or 0))
	end
end

function Vector3Boxed:box(v)
	self.x = v.x
	self.y = v.y
	self.z = v.z
end

function Vector3Boxed:unbox()
	return Vector3(self.x, self.y, self.z)
end

QuaternionBoxed = class(QuaternionBoxed)

function QuaternionBoxed:init(x,y,z,w)
	self:box(Quaternion.from_elements(x or 0, y or 0, z or 0, w or 1))
end

function QuaternionBoxed:box(m)
	self[1], self[2], self[3], self[4] = Quaternion.to_elements(m)
end

function QuaternionBoxed:unbox(m)
	return Quaternion.from_elements( unpack(self,1,4) )
end

Matrix4x4Boxed = class(Matrix4x4Boxed)

function Matrix4x4Boxed:init()
	self:box(Matrix4x4.identity())
end

function Matrix4x4Boxed:box(m)
	self[1], self[2], self[3], self[4], self[5], self[6], self[7], self[8],
		self[9], self[10], self[11], self[12] = Matrix4x4.to_elements(m)
end

function Matrix4x4Boxed:unbox(m)
	return Matrix4x4.from_elements( unpack(self,1,12) )
end

local function is_positive(n)
	return n >= 0
end

local function is_zero(n)
	return math.abs(n) < 0.00001
end


--------------------------------------------------
-- Plane representation
--------------------------------------------------

Plane = Plane or {}

function Plane.normal(plane)
	local x, y, z, _ = Quaternion.to_elements(plane)
	return Vector3(x, y, z)
end

function Plane.point(plane)
	local x, y, z, w = Quaternion.to_elements(plane)
	return Vector3(x * w, y * w, z * w)
end

function Plane.to_point_and_normal(plane)
	local x, y, z, w = Quaternion.to_elements(plane)
	local point = Vector3(x * w, y * w, z * w)
	local normal = Vector3(x, y, z)
	return point, normal
end

function Plane.from_point_and_normal(point_on_plane, plane_normal)
	local origin_to_point = point_on_plane - Vector3(0, 0, 0)
	local distance_from_origin = Vector3.dot(origin_to_point, plane_normal)
	return Quaternion.from_elements(plane_normal.x, plane_normal.y, plane_normal.z, distance_from_origin)
end

function Plane.from_point_and_vectors(point_on_plane, u, v)
	local plane_normal = Vector3.normalize(Vector3.cross(u, v))
	return Plane.from_point_and_normal(point_on_plane, plane_normal)
end

function Plane.from_ccw_points(point_a, point_b, point_c)
	local u = point_b - point_a
	local v = point_c - point_a
	return Plane.from_point_and_vectors(point_a, u, v)
end

function Plane.draw(line_object, plane, point)
	point = point or Plane.point(plane)
	local normal = Plane.normal(plane)
	local y, z = Vector3.make_axes(normal)
	local x_color = Color(255, 153, 153)
	local y_color = Color(153, 255, 153)
	local z_color = Color(153, 153, 255)
	local scale = 0.5
	local y_span = y * 5 * scale
	local z_span = z * 5 * scale
	
	for i = -5, 5 do
		local y_from = point - y_span + z * i * scale
		local y_to = point + y_span + z * i * scale
		local z_from = point - z_span + y * i * scale
		local z_to = point + z_span + y * i * scale
		LineObject.add_line(line_object, y_color, y_from, y_to)
		LineObject.add_line(line_object, z_color, z_from, z_to)
	end
	
	LineObject.add_line(line_object, x_color, point, point + normal * scale)
end

function Plane.mirror_if_behind(plane, point)
	local origin, normal = Plane.to_point_and_normal(plane)
	local origin_to_point = point - origin
	local distance_along_normal = Vector3.dot(origin_to_point, normal)

	if distance_along_normal < 0 then
		local mirrored_point = point - normal * (2 * distance_along_normal)
		return mirrored_point
	else
		return point
	end
end


--------------------------------------------------
-- Intersection tests
--------------------------------------------------

Intersect = Intersect or {}

function Intersect.ray_line(ray_from, ray_direction, line_point_a, line_point_b)
	local distance_along_ray, normalized_distance_along_line = Intersect.line_line(ray_from, ray_from + ray_direction, line_point_a, line_point_b)
	
	if distance_along_ray == nil then
		-- The ray is parallel to the line.
		return nil, nil
	elseif distance_along_ray < 0 then
		-- The intersection point is behind the start of the ray.
		return nil, nil
	else
		return distance_along_ray, normalized_distance_along_line
	end
end

function Intersect.ray_segment(ray_from, ray_direction, segment_start, segment_end)
	local distance_along_ray, normalized_distance_along_line =
		Intersect.ray_line(ray_from, ray_direction, segment_start, segment_end)
	
	local is_line_parallel_to_or_behind_ray = distance_along_ray == nil

	if is_line_parallel_to_or_behind_ray then
		return nil
	end

	local is_intersection_inside_segment =
		normalized_distance_along_line >= 0 and normalized_distance_along_line <= 1

	if is_intersection_inside_segment then
		return distance_along_ray, normalized_distance_along_line
	else
		return nil, nil
	end
end

function Intersect.ray_plane(from, direction, plane)
	local point_on_plane = Plane.point(plane)
	local plane_normal = Plane.normal(plane)
	local numerator = Vector3.dot(point_on_plane - from, plane_normal)
	local denominator = Vector3.dot(direction, plane_normal)
	local is_ray_start_in_front_of_plane = numerator <= 0
	
	if is_zero(denominator) then
		-- The ray is parallel to the plane.
		if is_zero(numerator) then
			 -- The parallel ray starts inside the plane. The ray intersects the plane from its start and onward.
			return 0, is_ray_start_in_front_of_plane
		else
			-- The parallel ray starts outside the plane. There is no intersection.
			return nil, is_ray_start_in_front_of_plane
		end
	end
	
	local distance_along_ray = numerator / denominator
	return distance_along_ray, is_ray_start_in_front_of_plane
end

function Intersect.ray_sphere(from, direction, center, radius)
	local m = from - center
	local b = Vector3.dot(m, direction)
	local c = Vector3.dot(m, m) - radius * radius

	local is_ray_origin_outside_sphere = c > 0
	local is_ray_pointing_away_from_sphere = b > 0

	if is_ray_origin_outside_sphere and is_ray_pointing_away_from_sphere then
		return nil
	end

	local discriminant = b * b - c
	local is_sphere_missed_by_ray = discriminant < 0
	
	if is_sphere_missed_by_ray then
		return nil
	end

	local distance_along_ray = -b - math.sqrt(discriminant)
	local is_ray_origin_inside_sphere = distance_along_ray < 0
	return is_ray_origin_inside_sphere and 0 or distance_along_ray
end

function Intersect.ray_disc(from, direction, center, radius, normal)
	local plane = Plane.from_point_and_normal(center, normal)
	local distance_along_ray, is_ray_start_in_front_of_plane = Intersect.ray_plane(from, direction, plane)

	if distance_along_ray == nil or distance_along_ray < 0 then
		-- There is no intersection.
		return nil
	end

	-- The ray intersects the disc plane. Check if the intersection point is inside the disc.
	local point_on_plane = from + direction * distance_along_ray
	local point_is_inside_disc = Vector3.distance(point_on_plane, center) < radius
	return point_is_inside_disc and distance_along_ray or nil
end

function Intersect.ray_box(from, direction, pose, radius)
	local is_ray_origin_inside_box = Math.point_in_box(from, pose, radius)

	if is_ray_origin_inside_box then
		return 0
	end

	local distance_along_ray = Math.ray_box_intersection(from, direction, pose, radius)
	local is_box_missed_by_ray = distance_along_ray < 0

	if is_box_missed_by_ray then
		return nil
	end

	return distance_along_ray
end

function Intersect.ray_triangle(from, direction, tri_a, tri_b, tri_c)
	local plane_normal = Geometry.triangle_normal(tri_a, tri_b, tri_c)
	local numerator = Vector3.dot(tri_a - from, plane_normal)

	if numerator > 0 then
		-- The ray start is behind the plane. We only intersect front-facing triangles.
		return nil
	end

	local denominator = Vector3.dot(direction, plane_normal)
	
	if is_zero(denominator) then
		-- The ray is parallel to the plane.
		if is_zero(numerator) then
			-- The parallel ray starts inside the plane, but does it intersect the triangle?
			if Geometry.is_point_inside_triangle(from, tri_a, tri_b, tri_c) then
				-- The ray intersects the triangle from its start and onward.
				return 0
			else
				-- The ray starts outside the triangle. Test ray against triangle edges.
				local edge_distances = {
					Intersect.ray_segment(from, direction, tri_a, tri_b) or -1.0,
					Intersect.ray_segment(from, direction, tri_b, tri_c) or -1.0,
					Intersect.ray_segment(from, direction, tri_c, tri_a) or -1.0
				}

				local _, distance = Array.filter(edge_distances, is_positive):min()
				return distance
			end
		else
			-- The parallel ray starts outside the plane. There is no intersection.
			return nil
		end
	end
	
	-- The ray is not parallel to the plane.
	local distance_along_ray = numerator / denominator

	if distance_along_ray < 0 then
		-- The ray is pointing away from the triangle's plane.
		return nil
	end

	local point_on_plane = from + direction * distance_along_ray
	local is_triangle_hit_by_ray = Geometry.is_point_inside_triangle(point_on_plane, tri_a, tri_b, tri_c)
	return is_triangle_hit_by_ray and distance_along_ray or nil
end

function Intersect.line_line(line_a_pt1, line_a_pt2, line_b_pt1, line_b_pt2)
	local line_a_vector = line_a_pt2 - line_a_pt1
	local line_b_vector = line_b_pt2 - line_b_pt1
	local a = Vector3.dot(line_a_vector, line_a_vector)
	local e = Vector3.dot(line_b_vector, line_b_vector)
	local b = Vector3.dot(line_a_vector, line_b_vector)
	local d = a * e - b * b
	
	if d < 0.001 then
		-- The lines are parallel. There is no intersection.
		return nil, nil
	end
	
	local r = line_a_pt1 - line_b_pt1
	local c = Vector3.dot(line_a_vector, r)
	local f = Vector3.dot(line_b_vector, r)
	local normalized_distance_along_line_a = (b * f - c * e) / d
	local normalized_distance_along_line_b = (a * f - b * c) / d
	return normalized_distance_along_line_a, normalized_distance_along_line_b
end

-- Returns a value between [0, 1] that can be used to interpolate between two points that define a segment.
function Intersect.segment_point(segment_start, segment_end, point)
	local segment_vector = segment_end - segment_start
	local squared_length_of_segment = Vector3.dot(segment_vector, segment_vector)
	
	if is_zero(squared_length_of_segment) then
		-- The segment is of zero length.
		-- Since we return a value clamped to [0, 1], we can return 0.
		-- If we would not return a clamed value, this case is undefined.
		return 0
	end
	
	local segment_start_to_point = point - segment_start
	local normalized_distance_along_segment = Vector3.dot(segment_start_to_point, segment_vector) / squared_length_of_segment
	local clamped_normalized_distance_along_segment = math.max(0, math.min(normalized_distance_along_segment, 1))
	return clamped_normalized_distance_along_segment
end

-- Returns two values between [0, 1] that can be used to interpolate between the two points that define a segment.
function Intersect.segment_segment(a_start, a_end, b_start, b_end)
	local a_vector = a_end - a_start
	local b_vector = b_end - b_start
	local b_start_to_a_start = a_start - b_start
	local a_squared_len = Vector3.dot(a_vector, a_vector)
	local b_squared_len = Vector3.dot(b_vector, b_vector)
	local f = Vector3.dot(b_vector, b_start_to_a_start)
	local a_is_zero_len = is_zero(a_squared_len)
	local b_is_zero_len = is_zero(b_squared_len)
	
	if a_is_zero_len and b_is_zero_len then
		-- Both segments degenerate into points.
		return 0, 0
	elseif a_is_zero_len then
		-- Segment A is a point.
		return 0, math.max(0, math.min(f / b_squared_len, 1))
	else
		local c = Vector3.dot(a_vector, b_start_to_a_start)
		
		if b_is_zero_len then
			-- Segment B is a point.
			return math.max(0, math.min(-c / a_squared_len, 1)), 0
		else
			-- General case.
			local b = Vector3.dot(a_vector, b_vector)
			local denom = a_squared_len * b_squared_len - b * b
			assert(denom >= 0)
			
			local s = is_zero(denom) and 0 or math.max(0, math.min((b * f - c * b_squared_len) / denom, 1))
			local t = (b * s + f) / b_squared_len
			
			-- If t is not in the [0, 1] range, clamp it and recalculate s, since the closest point has now moved.
			if t < 0 then
				s = math.max(0, math.min(-c / a_squared_len, 1))
				t = 0
			elseif t > 1 then
				s = math.max(0, math.min((b - c) / a_squared_len, 1))
				t = 1
			end
			
			return s, t
		end
	end
end


--------------------------------------------------
-- Projection
--------------------------------------------------

Project = Project or {}

function Project.point_on_plane(point, plane)
	local inverted_plane_normal = -Plane.normal(plane)
	local distance_from_plane = Intersect.ray_plane(point, inverted_plane_normal, plane)
	local result = point + inverted_plane_normal * distance_from_plane
	return result
end

Project.vector_on_plane = Project.point_on_plane


--------------------------------------------------
-- Interpolation
--------------------------------------------------

Interpolate = Interpolate or {}
Interpolate.Linear = Interpolate.Linear or {}

function Interpolate.Linear.points(point_a, point_b, t)
	local vector = point_b - point_a
	return point_a + vector * t
end

function Interpolate.Linear.color(color_a, color_b, t)
	local aa, ar, ag, ab = Quaternion.to_elements(color_a)
	local ba, br, bg, bb = Quaternion.to_elements(color_b)
	local da, dr, dg, db = ba - aa, br - ar, bg - ag, bb - ab
	local ra, rr, rg, rb = aa + da * t, ar + dr * t, ag + dg * t, ab + db * t
	local result = Quaternion.from_elements(ra, rr, rg, rb)
	return result
end


--------------------------------------------------
-- Blend
--------------------------------------------------

Blend = Blend or {}

function Blend.color_with_alpha(color, alpha)
	local _, r, g, b = Quaternion.to_elements(color)
	local result = Quaternion.from_elements(alpha, r, g, b)
	return result
end

Blend.color_with_color = Interpolate.Linear.color

function Blend.color_with_intensity(color, intensity)
	local a, r, g, b = Quaternion.to_elements(color)
	local s = Func.compose(Op.mul(intensity), Func.partial(math.max, 0), Func.partial(math.min, 255))
	local result = Quaternion.from_elements(a, s(r), s(g), s(b))
	return result
end

local function primary_colors_at_alpha(a)
	local values = { 0, 128, 255 }

	return Array.collect(values, function(r)
		return Array.collect(values, function(g)
			return Array.map(values, function(b)
				return Color(a, r, g, b)
			end)
		end)
	end)
end

function Blend.dominant_color(color)
	local nv, nq, nm = Script.temp_count()
	local a = Quaternion.to_elements(color)
	local palette = primary_colors_at_alpha(a)
	local result = Blend.snap_color(palette, color)
	local _, r, g, b = Quaternion.to_elements(result)
	Script.set_temp_count(nv, nq, nm)
	return Color(a, r, g, b)
end

function Blend.invert_color(color)
	local a, r, g, b = Quaternion.to_elements(color)
	local result = Color(a, 255 - r, 255 - g, 255 - b)
	return result
end

function Blend.color_distance(first_color, second_color)
	local a1, r1, g1, b1 = Quaternion.to_elements(first_color)
	local a2, r2, g2, b2 = Quaternion.to_elements(second_color)
	local ad = math.abs(a2 - a1)
	local rd = math.abs(r2 - r1)
	local gd = math.abs(g2 - g1)
	local bd = math.abs(b2 - b1)
	return ad + rd + gd + bd
end

function Blend.snap_color(palette, color)
	assert(Validation.is_non_empty_array(palette))
	local distance_to_color = Func.partial(Blend.color_distance, color)
	local _, snapped_color = Array.min_by(palette, distance_to_color)
	assert(snapped_color ~= nil)
	return snapped_color
end


--------------------------------------------------
-- Geometry
--------------------------------------------------

Geometry = Geometry or {}

function Geometry.major_axis_name(vector)
	local x_dp = Vector3.dot(vector, Vector3.x_axis())
	local y_dp = Vector3.dot(vector, Vector3.y_axis())
	local z_dp = Vector3.dot(vector, Vector3.z_axis())
	
	local dot_products_by_axis_name = {
		["x_pos"] = x_dp,
		["x_neg"] = -x_dp,
		["y_pos"] = y_dp,
		["y_neg"] = -y_dp,
		["z_pos"] = z_dp,
		["z_neg"] = -z_dp
	}
	
	local axis_name = Dict.max(dot_products_by_axis_name)
	return axis_name
end

function Geometry.triangle_normal(point_a, point_b, point_c)
	return Vector3.normalize(Vector3.cross(point_b - point_a, point_c - point_a))
end

function Geometry.is_point_inside_triangle(point_on_plane, tri_a, tri_b, tri_c)
	-- Translate the triangle so the point is at the origin.
	local pa = tri_a - point_on_plane
	local pb = tri_b - point_on_plane
	local pc = tri_c - point_on_plane
	
	-- Compute normal vectors for triangles pab and pbc.
	local pab_n = Vector3.cross(pa, pb)
	local pbc_n = Vector3.cross(pb, pc)
	
	-- Unless the normals point in the same direction, the point is outside our triangle.
	-- If one of the normals is a zero vector, the point is on the line defined by the edge segment.
	-- Such a point can still be inside the triangle, provided the point is on the edge segment.
	if Vector3.dot(pab_n, pbc_n) < 0 then
		return false
	end

	-- Compute normal vector for triangle pca.
	-- If the pca normal points in the same direction as the best normal of the
	-- ones above (or the point is on the edge), it is inside the triangle.
	local pca_n = Vector3.cross(pc, pa)
	local best_normal = Vector3.dot(pab_n, pab_n) > Vector3.dot(pbc_n, pbc_n) and pab_n or pbc_n
	local dot_product = Vector3.dot(best_normal, pca_n)
	
	if dot_product < 0 then
		return false
	elseif dot_product > 0 then
		return true
	else
		-- This is a degenerate triangle, and the point is co-linear to its edges.
		-- The point is inside the triangle if it is on any edge segment.
		-- Since the point is co-linear to the edge segment, we can do a simple point-in-aabb check.
		local min_p = Vector3.min(pa, Vector3.min(pb, pc))
		local max_p = Vector3.max(pa, Vector3.max(pb, pc))
		return min_p.x <= 0 and min_p.y <= 0 and min_p.z <= 0 and max_p.x >= 0 and max_p.y >= 0 and max_p.z >= 0
	end
end

function Geometry.is_triangle_ccw(point_a, point_b, point_c, face_normal)
	local is_ccw = Vector3.dot(point_c - point_a, Vector3.cross(face_normal, point_b - point_a)) > 0
	return is_ccw
end

function Geometry.triangulate_face(points, face_normal)
	-- These arrays track the point indices surrounding a particular index.
	-- We will mutate these as we cut off ear triangles during the triangulation process.
	local prev = Array.mapi(points, function(i) return Array.cycle_index(points, i - 1) end)
	local next = Array.mapi(points, function(i) return Array.cycle_index(points, i + 1) end)

	-- An 'ear triangle' is a triangle with ccw winding order
	-- which does not contain any other points from the face.
	-- The 'ear tip' is the outmost (or second) vertex of such a triangle.
	local function is_ear_tip(index)
		local tcv, tcq, tcm = Script.temp_count()
		local prev_index = prev[index]
		local next_index = next[index]
		local point_a = points[prev_index]
		local point_b = points[index]
		local point_c = points[next_index]
		local result = false
		
		if Geometry.is_triangle_ccw(point_a, point_b, point_c, face_normal) then
			local plane = Plane.from_point_and_normal(point_b, face_normal)
			local examined_index = next[next_index]
			result = true
			
			while examined_index ~= prev_index do
				local pt_on_plane = Project.point_on_plane(points[examined_index], plane)
				
				if Geometry.is_point_inside_triangle(pt_on_plane, point_a, point_b, point_c) then
					result = false
					break
				end
				
				examined_index = next[examined_index]
			end
		end
		
		Script.set_temp_count(tcv, tcq, tcm)
		return result
	end
	
	-- A degenerate triangle is a triangle with zero area.
	-- I.e. it has two parallel edges.
	local function is_degenerate_triangle(index)
		local tcv, tcq, tcm = Script.temp_count()
		local a = points[prev[index]]
		local b = points[index]
		local c = points[next[index]]
		local cross_product = Vector3.cross(a - b, c - b)
		local is_degenerate = is_zero(Vector3.dot(cross_product, cross_product))
		Script.set_temp_count(tcv, tcq, tcm)
		return is_degenerate
	end
	
	local index = 1
	local count = #points
	local triangle_indices = Array.init(0)
	local consecutive_failures = 0
	
	local function add_triangle_ear(index)
		table.insert(triangle_indices, prev[index])
		table.insert(triangle_indices, index)
		table.insert(triangle_indices, next[index])
	end
	
	local function remove_vertex(index)
		local prev_index = prev[index]
		local next_index = next[index]
		
		-- Remove the vertex from our next and prev index arrays by unlinking it.
		next[prev_index] = next_index
		prev[next_index] = prev_index
		count = count - 1
		
		-- Restart from the vertex prior to the one we just removed.
		consecutive_failures = 0
		return prev_index
	end
	
	while count >= 3 do
		if is_degenerate_triangle(index) then
			-- We can safely discard degenerate triangles.
			index = remove_vertex(index)
		elseif is_ear_tip(index) then
			-- This is an ear triangle. Add it to our index buffer.
			add_triangle_ear(index)
			index = remove_vertex(index)
		else
			-- This is not an ear triangle.
			consecutive_failures = consecutive_failures + 1
			
			if consecutive_failures >= count then
				-- The face is invalid. We're unable to triangulate it.
				return Array.init(0)
			else
				-- Try the next one.
				index = next[index]
			end
		end
	end
	
	-- The result is a flat list of triangle index triplets.
	return triangle_indices
end

function Geometry.is_planar_face_self_overlapping(points)
	local point_count = #points

	for i = 1, point_count do
		local edge_a_start = points[i]
		local edge_a_end = points[Array.cycle_index(points, i + 1)]
		
		for j = i + 1, point_count do
			local edge_b_start = points[j]
			local edge_b_end = points[Array.cycle_index(points, j + 1)]
			
			-- Get normalized distances along edge lines. If both are in the range [0, 1], they may intersect.
			local ad, bd = Intersect.line_line(edge_a_start, edge_a_end, edge_b_start, edge_b_end)
			
			if ad ~= nil and bd ~= nil and ad > 0 and ad < 1 and bd > 0 and bd < 1 then
				local point_on_edge_a = edge_a_start + (edge_a_end - edge_a_start) * ad
				local point_on_edge_b = edge_b_start + (edge_b_end - edge_b_start) * bd
				local distance = Vector3.distance(point_on_edge_a, point_on_edge_b)
				return distance < 0.0001
			end
		end
	end
	
	return false
end

function Geometry.closest_point_to_ray(points, ray_start, ray_direction, ray_length)
	local function distance_along_ray(index, point)
		return Vector3.dot(point - ray_start, ray_direction)
	end

	local function is_less_than_ray_length(index, distance)
		return distance < ray_length
	end

	local function distance_to_ray(index, distance)
		local point_in_box = points[index]
		local point_on_ray = ray_start + ray_direction * distance
		return Vector3.distance(point_in_box, point_on_ray)
	end

	local best_point_index, best_distance_along_ray =
		Dict.map(points, distance_along_ray)
			:filter(is_less_than_ray_length)
			:min_by(distance_to_ray)
	
	-- Can return nil if all points are father away than ray_length.
	return points[best_point_index], best_distance_along_ray
end


--------------------------------------------------
-- AABB
--------------------------------------------------

AABB = AABB or {}

function AABB.merged_box(objects, calc_object_oobb)
	if Dict.is_empty(objects) then
		return nil, nil
	end

	local boxed_min = Vector3Box(math.huge, math.huge, math.huge)
	local boxed_max = Vector3Box(-math.huge, -math.huge, -math.huge)
	local components = { "x", "y", "z" }

	for _, object in pairs(objects) do
		local nv, nq, nm = Script.temp_count()
		local pose, radius = calc_object_oobb(object)
		local points = OOBB.points(pose, radius)
		local object_min = Array.reduce(points, Vector3.min)
		local object_max = Array.reduce(points, Vector3.max)

		for _, component in ipairs(components) do
			boxed_min[component] = math.min(boxed_min[component], object_min[component])
			boxed_max[component] = math.max(boxed_max[component], object_max[component])
		end

		Script.set_temp_count(nv, nq, nm)
	end

	local min = boxed_min:unbox()
	local max = boxed_max:unbox()
	local merged_radius = (max - min) / 2
	local merged_center = min + merged_radius
	return merged_center, merged_radius
end


--------------------------------------------------
-- OOBB
--------------------------------------------------

OOBB = OOBB or {}

function OOBB.merged_box(objects, calc_object_oobb)
	-- Order matters, since the first object determines the pose axis.
	-- Thus, we do not accept a Dict for this function.
	local count = #objects
	
	if count == 0 then
		return nil, nil
	end
	
	local merged_pose, merged_radius = calc_object_oobb(objects[1])
	
	for i = 2, count do
		local object = objects[i]
		local pose, radius = calc_object_oobb(object);
		merged_pose, merged_radius = Math.merge_boxes(merged_pose, merged_radius, pose, radius)
	end
	
	return merged_pose, merged_radius
end

function OOBB.points(box_pose, box_radius)
	local box_center = Matrix4x4.translation(box_pose)
	local box_x = Matrix4x4.x(box_pose)
	local box_y = Matrix4x4.y(box_pose)
	local box_z = Matrix4x4.z(box_pose)
	local box_top_center = box_center + box_z * box_radius.z
	local box_bottom_center = box_center + box_z * -box_radius.z
	
	local box_points = {
		box_top_center + box_x * box_radius.x + box_y * box_radius.y,
		box_top_center + box_x * -box_radius.x + box_y * box_radius.y,
		box_top_center + box_x * -box_radius.x + box_y * -box_radius.y,
		box_top_center + box_x * box_radius.x + box_y * -box_radius.y,
		box_bottom_center + box_x * box_radius.x + box_y * box_radius.y,
		box_bottom_center + box_x * -box_radius.x + box_y * box_radius.y,
		box_bottom_center + box_x * -box_radius.x + box_y * -box_radius.y,
		box_bottom_center + box_x * box_radius.x + box_y * -box_radius.y,
	}
	
	return box_points
end

function OOBB.closest_point_to_ray(box_pose, box_radius, ray_start, ray_direction, ray_length)
	local nv, nq, nm = Script.temp_count()
	local points = OOBB.points(box_pose, box_radius)
	local best_point, best_distance_along_ray =
		Geometry.closest_point_to_ray(points, ray_start, ray_direction, ray_length)

	local x, y, z = Nilable.map(best_point, Vector3.to_elements)
	Script.set_temp_count(nv, nq, nm)

	if x == nil then
		return nil, nil
	else
		return Vector3(x, y, z), best_distance_along_ray
	end
end

function OOBB.draw_side_labels(world_gui, box_pose, box_radius, layer, color)
	local p = Matrix4x4.translation(box_pose)
	local distance = Vector3.distance(Camera.local_position(LevelEditor.camera), p)
	local size = distance / 50
	local font = "core/editor_slave/gui/arial"
		
	local m = Matrix4x4.identity()
	Matrix4x4.set_translation(m, p)
	
	if box_radius.z > 0 then
		local text = string.format("%.2f m", box_radius.z * 2)
		local min, max = Gui.text_extents(world_gui, text, font, size)
		local p = Vector3(-max.x / 2, box_radius.z + size, 0)
		Gui.text_3d(world_gui, text, font, size, "arial", m, p, layer, color)
	end
	
	if box_radius.x > 0 then
		local text = string.format("%.2f m", box_radius.x * 2)
		Matrix4x4.set_x(m, Matrix4x4.x(box_pose))
		Matrix4x4.set_z(m, Matrix4x4.y(box_pose))
		Matrix4x4.set_y(m, Matrix4x4.z(box_pose))
		local min, max = Gui.text_extents(world_gui, text, font, size)
		local p = Vector3(-max.x / 2, -box_radius.y - size, -box_radius.z)
		Gui.text_3d(world_gui, text, font, size, "arial", m, p, layer, color)
		Matrix4x4.set_x(m, -Matrix4x4.x(box_pose))
		Matrix4x4.set_z(m, -Matrix4x4.y(box_pose))
		Gui.text_3d(world_gui, text, font, size, "arial", m, p, layer, color)
	end
	
	if box_radius.y > 0 then
		local text = string.format("%.2f m", box_radius.y * 2)
		Matrix4x4.set_x(m, -Matrix4x4.y(box_pose))
		Matrix4x4.set_z(m, Matrix4x4.x(box_pose))
		Matrix4x4.set_y(m, Matrix4x4.z(box_pose))
		local min, max = Gui.text_extents(world_gui, text, font, size)
		local p = Vector3(-max.x / 2, -box_radius.x - size, -box_radius.z)
		Gui.text_3d(world_gui, text, font, size, "arial", m, p, layer, color)
		Matrix4x4.set_x(m, Matrix4x4.y(box_pose))
		Matrix4x4.set_z(m, -Matrix4x4.x(box_pose))
		Gui.text_3d(world_gui, text, font, size, "arial", m, p, layer, color)
	end
end


--------------------------------------------------
-- Sphere
--------------------------------------------------

Sphere = Sphere or {}

function Sphere.random_point_inside(center, radius)
	-- Pick random point inside 2 x 2 box.
	-- Pick new points until one is found to be inside inside unit sphere.
	-- Faster and more random than the alternatives.
	local x, y, z = 2, 2, 2

	while x * x + y * y + z * z > 1 do
		x = Math.random() * 2 - 1
		y = Math.random() * 2 - 1
		z = Math.random() * 2 - 1
	end

	local world_x = center.x + x * radius
	local world_y = center.y + y * radius
	local world_z = center.z + z * radius

	return Vector3(world_x, world_y, world_z)
end

function Sphere.random_point_on_surface(center, radius)
	local z = Math.random() * 2 - 1
	local a = Math.random() * 2 * math.pi
	local i = math.sqrt(1 - z * z)
	local x = i * math.cos(a)
	local y = i * math.sin(a)
	local dir = Vector3(x, y, z)
	return center + dir * radius
end


--------------------------------------------------
-- Convert
--------------------------------------------------

Convert = Convert or {}
Convert.Quaternion = Convert.Quaternion or {}

function Convert.Quaternion.yaw_pitch_roll(q)
	local x, y, z, w = Quaternion.to_elements(q)
	local yaw = math.atan2(2 * (w * x + y * z), (1 - 2 * (x * x + y * y)))
	local pitch = math.asin(math.max(-1, math.min(2 * (w * y - z * x), 1)))
	local roll = math.atan2(2 * (w * z + x * y) , (1 - 2 * (y * y + z * z)))
	return yaw, pitch, roll
end
