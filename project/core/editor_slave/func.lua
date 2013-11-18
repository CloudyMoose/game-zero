Func = Func or {}

-- Func.id : Value -> Value
-- Pass-through identity function. Returs whatever is passed to it.
function Func.id(x)
	return x
end

-- Func.constantly : Value -> (Any -> Value)
-- Returns a function that will always return the supplied value.
function Func.constantly(x)
	return function()
		return x
	end
end

-- Func.ignore : ... -> ()
-- Ignores all arguments, performs no operation and returns nothing.
function Func.ignore()
end

-- Func.of_table : Table -> (Key -> Value)
-- Returns a function that will index the supplied table with its argument.
function Func.of_table(table)
	return function(key)
		return table[key]
	end
end

-- Func.property : String -> (Obj -> Value)
-- Returns a function that will look up the value of a property on an object.
function Func.property(name)
	return function(obj)
		return obj[name]
	end
end

-- Func.has_property : String -> (Obj -> Bool)
-- Returns a function that will check if an object has a named property.
-- Useful when filtering collections of objects.
--
-- Example:
--   named_objects = Array.filter(level_objects, Func.has_property("name"))
function Func.has_property(name)
	return function(obj)
		return rawget(obj, name) ~= nil
	end
end

-- Func.method : String -> ((Obj, ...) -> Any)
-- Func.method : String -> Obj -> (... -> Any)
-- Returns a function that will invoke a named method on an object.
-- The instance parameter is optional.
-- If supplied, the returned function will invoke the named method on the supplied instance.
-- Otherwise, returns a function that will invoke the named method on whatever object is supplied as the first parameter.
--
-- Example:
--   normals = { Vector3Box(1, 0, 0), Vector3Box(0, 1, 0) }
--   unboxed_normals = Array.map(normals, Func.method("unbox")) -- Invoke x:unbox() on each element.
--
--   snap = Func.method("snap", LevelEditor.grid) -- Equivalent to Func.partial(Func.method("snap"), LevelEditor.grid)
--   snapped_point = snap(pt) -- Invoke LevelEditor.grid:snap(pt)
function Func.method(name, instance)
	if instance == nil then
		return function(obj, ...)
			return obj[name](obj, ...)
		end
	else
		return function(...)
			return instance[name](instance, ...)
		end
	end
end

-- Func.has_method : String -> (Obj -> Bool)
-- Returns a function that will check if an object implements a named method.
-- Useful when filtering collections of objects.
--
-- Example:
--   raycastable_objects = Array.filter(level_objects, Func.has_method("raycast"))
function Func.has_method(name)
	return function(obj)
		local func = obj[name]
		return func ~= nil and type(func) == "function"
	end
end

-- Func.invocation : String -> ... -> (Obj -> Any)
-- Returns a function that will invoke a named method with the supplied arguments on an object.
-- Use in place of Func.method(name) when you need to supply additional arguments to the method.
function Func.invocation(name, ...)
	local args = { ... }

	return function(obj)
		return obj[name](obj, unpack(args))
	end
end

-- Func.partial : ((Value, ...) -> Any) -> Value -> ((...) -> Any)
-- Partial function application.
--
-- Example:
--   multiply = function(a, b) return a * b end
--   multiply(3, 3) => 9
--   triple = Func.partial(multiply, 3)
--   triple(3) => 9
function Func.partial(func, a, b, c, d, e, f, g, h, i, terminator)
	if terminator ~= nil then assert(terminator == nil, "Too many presupplied arguments.")
	elseif i ~= nil then return function(...) return func(a, b, c, d, e, f, g, h, i, ...) end
	elseif h ~= nil then return function(...) return func(a, b, c, d, e, f, g, h, ...) end
	elseif g ~= nil then return function(...) return func(a, b, c, d, e, f, g, ...) end
	elseif f ~= nil then return function(...) return func(a, b, c, d, e, f, ...) end
	elseif e ~= nil then return function(...) return func(a, b, c, d, e, ...) end
	elseif d ~= nil then return function(...) return func(a, b, c, d, ...) end
	elseif c ~= nil then return function(...) return func(a, b, c, ...) end
	elseif b ~= nil then return function(...) return func(a, b, ...) end
	elseif a ~= nil then return function(...) return func(a, ...) end
	else return func end
end

-- Func.drop : Number -> (... -> Any) -> (... -> Any)
-- Returns a new function that discards its first n arguments, then returns
-- the result of calling func with the remaining arguments.
function Func.drop(n, func)
	if n < 0 then assert(n >= 0, "Can't drop less than zero arguments.")
	elseif n == 0 then return func
	elseif n == 1 then return function(_, ...) return func(...) end
	elseif n == 2 then return function(_, _, ...) return func(...) end
	elseif n == 3 then return function(_, _, _, ...) return func(...) end
	elseif n == 4 then return function(_, _, _, _, ...) return func(...) end
	elseif n == 5 then return function(_, _, _, _, _, ...) return func(...) end
	else assert(n > 5, "Can't drop that many arguments.") end
end


-- Func.compose : (... -> Any) -> (Any -> Any) -> (... -> Any)
-- Function composition. Returns a new function that applies f, then g to its arguments.
-- Additional functions for h, i, and so on can be supplied to chain additional functions.
--
-- Example:
--   calc_area = Func.compose(Vector3.cross, Vector3.length)
--   area = calc_area(parallelogram)
function Func.compose(f, g, h, i, j, terminator)
	if terminator ~= nil then assert(terminator == nil, "Too many functions.")
	elseif j ~= nil then return function(...) return j(i(h(g(f(...))))) end
	elseif i ~= nil then return function(...) return i(h(g(f(...)))) end
	elseif h ~= nil then return function(...) return h(g(f(...))) end
	elseif g ~= nil then return function(...) return g(f(...)) end
	else return f end
end

-- Func.fork : ((Value -> ()), ...) -> (Value -> ())
-- Returns a new function that applies all the supplied functions to its argument.
--
-- Example:
--   log = Func.fork(print, write_to_file)
--   log("This is written to both the console and a file.")
function Func.fork(...)
	local handlers = {...}
	
	return function(...)
		for _, visit in ipairs(handlers) do
			visit(...)
		end
	end
end

-- Func.negate : (... -> Bool) -> (... -> Bool)
-- Returns a new function that negates the result of the supplied function.
function Func.negate(func)
	return function(...)
		return not func(...)
	end
end

-- Func.any : ((... -> Bool), ...) -> (... -> Bool)
-- Returns a new function that returns true if any of the specified functions return true for the supplied arguments.
function Func.any(predicates)
	assert(type(predicates) == "table")

	return function(...)
		for _, test in ipairs(predicates) do
			if test(...) then
				return true
			end
		end

		return false
	end
end

-- Func.all : ((... -> Bool), ...) -> (... -> Bool)
-- Returns a new function that returns true if all the specified functions return true for the supplied arguments.
function Func.all(predicates)
	assert(type(predicates) == "table")

	return function(...)
		for _, test in ipairs(predicates) do
			if not test(...) then
				return false
			end
		end

		return true
	end
end
