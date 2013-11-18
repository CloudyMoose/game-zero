--------------------------------------------------
-- Nilable functions
--------------------------------------------------

Nilable = Nilable or {}

-- Nilable.filter : Nilable<Value> -> (Value -> Bool) -> Nilable<Value>
-- Returns nil if the supplied value is nil. If not, invokes test(value), and returns the value if the test passed. Else, returns nil.
function Nilable.filter(value, test)
	if value ~= nil and test(value) then
		return value
	end

	return nil
end

-- Nilable.bind : Nilable<Value> -> (Value -> Nilable<Result>) -> Nilable<Result>
-- Returns nil if the supplied value is nil. If not, returns the result of calling continuation(value).
function Nilable.bind(value, continuation)
	if value == nil then
		return nil
	end

	return continuation(value)
end

-- Nilable.map : Nilable<Value> -> (Value -> Result) -> Nilable<Result>
-- Returns nil if the supplied value is nil. If not, returns the result of calling transform(value).
-- Raises an error if transform(value) returns nil.
function Nilable.map(value, transform)
	if value == nil then
		return nil
	end

	local a, b, c, d, e, f, g, h, i, terminator = transform(value)
	assert(terminator == nil, "Too many return values.")
	assert(a ~= nil, "The transform function must return a value.")
	return a, b, c, d, e, f, g, h, i
end

-- Nilable.iter : Nilable<Value> -> (Value -> ()) -> ()
-- Calls visit(value) unless value is nil.
function Nilable.iter(value, visit)
	if value ~= nil then
		visit(value)
	end
end

-- Nilable.fold : Nilable<Value> -> Result -> (Result -> Value -> Result) -> Result
-- Returns init if the supplied value is nil. Otherwise, returns the result of calling accumulate(init, value).
function Nilable.fold(value, init, accumulate)
	if value == nil then
		return init
	end

	local result = accumulate(init, value)
	assert(result ~= nil, "The accumulate function must return a value.")
	return result
end

-- Nilable.fold_back : Nilable<Value> -> Result -> (Value -> Result -> Result) -> Result
-- Returns init if the supplied value is nil. Otherwise, returns the result of calling accumulate(value, init).
function Nilable.fold_back(value, init, accumulate)
	if value == nil then
		return init
	end
	
	local result = accumulate(value, init)
	assert(result ~= nil, "The accumulate function must return a value.")
	return result
end

-- Nilable.get : Nilable<Value> -> Value
-- Raises an error if the supplied value is nil. Otherwise returns the value without altering it.
function Nilable.get(value)
	assert(value ~= nil, "Can't call get on a nil value.")
	return value
end

-- Nilable.try_invoke : Nilable<Value> -> String -> Any
-- Returns nil if the supplied object is nil or the object does not implement the specified method.
-- Otherwise, returns the result of invoking the method on the object with the supplied arguments.
function Nilable.try_invoke(obj, method_name, ...)
	if obj ~= nil then
		local func = obj[method_name]

		if func ~= nil and type(func) == "function" then
			return func(obj, ...)
		end
	end

	return nil
end
