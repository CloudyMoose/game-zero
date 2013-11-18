Tuple = Tuple or {}

-- Tuple.first : (Value, ...) -> Value
-- Returns the first element of a tuple returned by another function, or nil if the element does not exist.
function Tuple.first(x)
	return x
end

-- Tuple.second : (Any, Value, ...) -> Value
-- Returns the second element of a tuple returned by another function, or nil if the element does not exist.
function Tuple.second(_, x)
	return x
end

-- Tuple.third : (Any, Any, Value, ...) -> Value
-- Returns the third element of a tuple returned by another function, or nil if the element does not exist.
function Tuple.third(_, _, x)
	return x
end

-- Tuple.flip : (Value, Other) -> (Other, Value)
-- Returns the supplied arguments in reverse order.
function Tuple.flip(a, b)
	return b, a
end

-- Tuple.map : (Value -> Result) -> (Value, ...) -> (Result, ...)
-- Applies the supplied transform function to each element in the tuple and returns a new tuple with the results.
function Tuple.map(transform, ...)
	return unpack(Array.map({...}, transform))
end

-- Tuple.take : Number -> (Any, ...) -> (Any, ...)
-- Returns the first count supplied values.
function Tuple.take(count, a, b, c, d, e, f, g, h, i)
	if count <= 0 then return nil
	elseif count == 1 then return a
	elseif count == 2 then return a, b
	elseif count == 3 then return a, b, c
	elseif count == 4 then return a, b, c, d
	elseif count == 5 then return a, b, c, d, e
	elseif count == 6 then return a, b, c, d, e, f
	elseif count == 7 then return a, b, c, d, e, f, g
	elseif count == 8 then return a, b, c, d, e, f, g, h
	elseif count == 9 then return a, b, c, d, e, f, g, h, i
	else assert(count <= 9, "Can't take that many arguments.") end
end
