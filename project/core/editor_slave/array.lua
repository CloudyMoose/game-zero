--------------------------------------------------
-- Utility functions
--------------------------------------------------

local function best(array, as_comparable, compare)
	local count = #array
	local best_index = nil
	local best_comparable_value = nil
	
	for index = 1, count do
		local value = array[index]
		local comparable_value = as_comparable(index, value)
		
		if comparable_value ~= nil then
			if best_comparable_value == nil or compare(comparable_value, best_comparable_value) then
				best_index = index
				best_comparable_value = comparable_value
			end
		end
	end
	
	local best_value = best_index ~= nil and array[best_index] or nil
	return best_index, best_value
end


--------------------------------------------------
-- Array functions
--------------------------------------------------

Array = Array or {}
Array.MetaTable = Array.MetaTable or { __index = Array }

-- Array.is_empty : Array<Value> -> Bool
-- Returns true if the supplied array is empty, otherwise false.
function Array.is_empty(array)
	return #array == 0
end

-- Array.clear : Array<Value> -> ()
-- Removes all values from the supplied array.
-- Warning: This function will mutate the array in-place.
function Array.clear(array)
	while #array > 0 do
		table.remove(array)
	end
end

-- Array.cycle_index : Array<Value> -> Int -> Index
-- Returns a valid index in the specified array by cycling the supplied integer to the array length.
-- This operation is simply (index % count) in languages that use zero-based indices, but is more
-- involved when dealing with one-based indices.
function Array.cycle_index(array, index)
	return ((index - 1) % #array) + 1
end

-- Array.concat : (Array<Value>, Array<Value>, ...) -> Array<Value>
-- Returns a new array with all the elements of each supplied array in order.
function Array.concat(...)
	local new_array = setmetatable({}, Array.MetaTable)

	for _, array in ipairs{...} do
		for _, value in ipairs(array) do
			table.insert(new_array, value)
		end
	end
	
	return new_array
end

-- Array.first : Array<Value> -> Nilable<Value>
-- Array.first : Array<Value> -> (Value -> Bool) -> Nilable<Value>
-- Returns the first element in the array. If a predicate is supplied, returns
-- the first element in the array where test(value) evaluates to true.
-- If the array is empty, or no match is found, returns nil.
function Array.first(array, test)
	local count = #array

	for index = 1, count do
		local value = array[index]
		
		if test == nil or test(value) then
			return value
		end
	end
	
	return nil
end

-- Array.last : Array<Value> -> Nilable<Value>
-- Array.last : Array<Value> -> (Value -> Bool) -> Nilable<Value>
-- Returns the last element in the array. If a predicate is supplied, returns
-- the last element in the array where test(value) evaluates to true.
-- If the array is empty, or no match is found, returns nil.
function Array.last(array, test)
	for index = #array, 1, -1 do
		local value = array[index]
		
		if test == nil or test(value) then
			return value
		end
	end
	
	return nil
end

-- Array.find : Array<Value> -> (Value -> Bool) -> (Index, Value)
-- Returns (index, value) of the first element where test(value) evaluates to true.
-- If no match is found, returns (nil, nil).
function Array.find(array, test)
	local count = #array
	
	for index = 1, count do
		local value = array[index]
		
		if test(value) then
			return index, value
		end
	end
	
	return nil, nil
end

-- Array.findi : Array<Value> -> (Index -> Value -> Bool) -> (Index, Value)
-- Returns (index, value) of the first element where test(index, value) evaluates to true.
-- If no match is found, returns (nil, nil).
function Array.findi(array, test)
	local count = #array
	
	for index = 1, count do
		local value = array[index]
		
		if test(index, value) then
			return index, value
		end
	end
	
	return nil, nil
end

-- Array.find_last : Array<Value> -> (Value -> Bool) -> (Index, Value)
-- Returns (index, value) of the last element where test(value) evaluates to true.
-- If no match is found, returns (nil, nil).
function Array.find_last(array, test)
	for index = #array, 1, -1 do
		local value = array[index]
		
		if test(value) then
			return index, value
		end
	end
	
	return nil, nil
end

-- Array.index_of : Array<Value> -> Value -> Index
-- Returns the index of an element in an array.
-- If no match is found, returns nil.
function Array.index_of(array, value)
	if value == nil then
		return nil
	end
	
	local count = #array
	
	for index = 1, count do
		if array[index] == value then
			return index
		end
	end
	
	return nil
end

-- Array.contains : Array<Value> -> Value -> Bool
-- Returns true if an array contains the specified element.
function Array.contains(array, value)
	return Array.index_of(array, value) ~= nil
end

-- Array.filter : Array<Value> -> (Value -> Bool) -> Array<Value>
-- Returns a new array containing only the elements where test(value) evaluates to true.
function Array.filter(array, test)
	local count = #array
	local new_array = setmetatable({}, Array.MetaTable)
	
	for index = 1, count do
		local value = array[index]
		
		if test(value) then
			table.insert(new_array, value)
		end
	end
	
	return new_array
end

-- Array.filteri : Array<Value> -> (Index -> Value -> Bool) -> Array<Value>
-- Returns a new array containing only the elements where test(index, value) evaluates to true.
function Array.filteri(array, test)
	local count = #array
	local new_array = setmetatable({}, Array.MetaTable)
	
	for index = 1, count do
		local value = array[index]
		
		if test(index, value) then
			table.insert(new_array, value)
		end
	end
	
	return new_array
end

-- Array.of : (Value, ...) -> Array<Value>
-- Returns a new array with all the supplied values.
-- Can also be considered the inverse of the built-in unpack function.
function Array.of(...)
	return {...}
end

-- Array.copy : Array<Value> -> Array<Value>
-- Returns a new array with all the elements of the supplied array.
-- Does not perform a deep copy of the contents.
function Array.copy(array)
	local count = #array
	local new_array = setmetatable({}, Array.MetaTable)
	
	for index = 1, count do
		new_array[index] = array[index]
	end
	
	return new_array
end

-- Array.map : Array<Value> -> (Value -> Result) -> Array<Result>
-- Returns a new array with the results of applying transform(value) to each element in order.
-- Raises an error if the transform function returns nil.
-- If you need to create a sparse array, use Dict.map instead.
-- If you need to filter out returned nil-values, use Array.choose instead.
--
-- Example:
--   numbers = { 1, 2, 3 }
--   square = function(n) return n * n end
--   Array.map(numbers, square) => { square(1), square(2), square(3) } => { 1, 4, 9 }
function Array.map(array, transform)
	local count = #array
	local new_array = setmetatable({}, Array.MetaTable)
	
	for index = 1, count do
		local transformed_value = transform(array[index])
		assert(transformed_value ~= nil)
		new_array[index] = transformed_value
	end
	
	return new_array
end

-- Array.mapi : Array<Value> -> (Index -> Value -> Result) -> Array<Result>
-- Returns a new array with the results of applying transform(index, value) to each element in order.
-- Raises an error if the transform function returns nil.
-- If you need to create a sparse array, use Dict.mapi instead.
-- If you need to filter out returned nil-values, use Array.choosei instead.
function Array.mapi(array, transform)
	local count = #array
	local new_array = setmetatable({}, Array.MetaTable)
	
	for index = 1, count do
		local transformed_value = transform(index, array[index])
		assert(transformed_value ~= nil)
		new_array[index] = transformed_value
	end
	
	return new_array
end

-- Array.choose : Array<Value> -> (Value -> Nilable<Result>) -> Array<Result>
-- Returns a new array with the non-nil results of applying transform(value) to each element in order.
-- Like Array.map, but filters out nil values from the resulting array.
function Array.choose(array, transform)
	local new_array = setmetatable({}, Array.MetaTable)

	for _, value in ipairs(array) do
		local transformed_value = transform(value)
		
		if transformed_value ~= nil then
			table.insert(new_array, transformed_value)
		end
	end

	return new_array
end

-- Array.choosei : Array<Value> -> (Index -> Value -> Nilable<Result>) -> Array<Result>
-- Returns a new array with the non-nil results of applying transform(index, value) to each element in order.
-- Like Array.mapi, but filters out nil values from the resulting array.
function Array.choosei(array, transform)
	local count = #array
	local new_array = setmetatable({}, Array.MetaTable)

	for index = 1, count do
		local transformed_value = transform(index, array[index])

		if transformed_value ~= nil then
			table.insert(new_array, transformed_value)
		end
	end

	return new_array
end

-- Array.collect : Array<Value> -> (Value -> Array<Result>) -> Array<Result>
-- Applies permute(value) to each element in the supplied array. Returns a new array with the concatenated results.
-- Other common names for this operation are SelectMany (C# Linq), collect_concat and flat_map (Ruby).
-- Also represents the Bind operation for the List monad.
--
-- Example:
--   letters = { "a", "b", "c" }
--   variants = function(s) return { string.upper(s), string.lower(s) } end
--   Array.collect(letters, variants) => { "A", "a", "B", "b", "C", "c" }
function Array.collect(array, permute)
	local new_array = setmetatable({}, Array.MetaTable)
	
	for _, value in ipairs(array) do
		for _, permutation in ipairs(permute(value)) do
			table.insert(new_array, permutation)
		end
	end
	
	return new_array
end

-- Array.iter : Array<Value> -> (Value -> ()) -> ()
-- Calls visit(value) for each value.
function Array.iter(array, visit)
	local count = #array
	
	for index = 1, count do
		visit(array[index])
	end
end

-- Array.iteri : Array<Value> -> (Index -> Value -> ()) -> ()
-- Calls visit(index, value) for each entry.
function Array.iteri(array, visit)
	local count = #array
	
	for index = 1, count do
		visit(index, array[index])
	end
end

-- Array.reduce : Array<Value> -> (Value -> Value -> Value) -> Value
-- Returns the result of applying accumulate(result, value) to each element in order.
-- Similar to Array.fold, but simplified for the common case where the accumulate function returns the same type as its argument.
-- If the array has a single element, that element is returned and the accumulate function is never called.
-- Calling Array.reduce with an empty array will yield an error.
--
-- Example:
--   numbers = { 1, 2, 3 }
--   sum = function(a, b) return a + b end
--   Array.reduce(numbers, sum) => sum(sum(sum(0, 1), 2), 3) => 6
function Array.reduce(array, accumulate)
	local count = #array
	assert(count > 0)
	local result = array[1]
	
	for index = 2, count do
		result = accumulate(result, array[index])
	end
	
	return result
end

-- Array.fold : Array<Value> -> Result -> (Result -> Value -> Result) -> Result
-- Returns the result of applying accumulate(result, value) to each element in order.
-- Generalized Array.reduce. More powerful in that you can supply an initial result, 
-- and that it supports different types for the values and the result.
-- Since you supply the initial result, Array.fold also works with empty arrays.
--
-- Example:
--   charcodes = { 72, 105, 33 }
--   decode = function(result, n) return result .. string.char(n) end
--   Array.fold(charcodes, "Message: ", decode) => decode(decode(decode("Message: ", 72), 105), 33) => "Message: Hi!"
function Array.fold(array, init, accumulate)
	local count = #array
	local result = init
	
	for index = 1, count do
		result = accumulate(result, array[index])
	end
	
	return result
end

-- Array.group_by : Array<Value> -> (Value -> Key) -> Dict<Key, Array<Value>>
-- Array.group_by : Array<Value> -> (Value -> Key) -> (Value -> Result) -> Dict<Key, Array<Result>>
-- Returns a new dict constructed by calling get_key on each element in turn. The return value
-- of get_key determines which group each array element belongs to. The results are returned as
-- a dict mapping an array of group members to each key. If the optional transform function is
-- supplied, each element is transformed by it before it is added to its assigned group. 
-- If the transform function returns nil, that element is excluded from all groups.
function Array.group_by(array, get_key, transform)
	local count = #array
	local groups = setmetatable({}, Dict.MetaTable)

	for index = 1, count do
		local value = array[index]
		local inserted_value = value

		if transform ~= nil then
			inserted_value = transform(value)
		end

		if inserted_value ~= nil then
			local key = get_key(value)
			local group = groups[key]

			if group == nil then
				group = setmetatable({}, Array.MetaTable)
				groups[key] = group
			end

			table.insert(group, inserted_value)
		end
	end

	return groups
end

-- Array.sort : Array<Value> -> Array<Value>
-- Array.sort : Array<Value> -> (Value -> Value -> Bool) -> Array<Value>
-- Returns a new array with the elements sorted by calling compare(a, b) for each successive element.
-- The optional compare function is expected to return true when a is less than b.
-- If the compare function is not supplied, the standard Lua operator < is used.
function Array.sort(array, compare)
	local new_array = setmetatable(Array.copy(array), Array.MetaTable)
	
	if (compare == nil) then
		table.sort(new_array)
	else
		table.sort(new_array, compare)
	end
	
	return new_array
end

-- Array.sort_by : Array<Value> -> (Value -> Comparable) -> Array<Value>
-- Returns a new array with the elements sorted by the value returned by the as_comparable function for each successive element.
function Array.sort_by(array, as_comparable)
	local compare = function(a, b) return as_comparable(a) < as_comparable(b) end
	return Array.sort(array, compare)
end

-- Array.min : Array<Value> -> (Index, Value)
-- Array.min : Array<Value> -> (Value -> Value -> Bool) -> (Index, Value)
-- Returns (index, value) of the smallest element determined by calling compare(a, b) for each successive element.
-- The optional compare function is expected to return true when a is less than b.
-- If the compare function is not supplied, the standard Lua operator < is used.
-- If the array is empty, returns (nil, nil).
function Array.min(array, compare)
	compare = compare or function(a, b) return a < b end
	return best(array, function(_, value) return value end, function(a, b) return compare(a, b) end)
end

-- Array.min_by : Array<Value> -> (Value -> Comparable) -> (Index, Value)
-- Returns (index, value) of the smallest element by comparing the values returned by the as_comparable function for each element.
-- If as_comparable returns nil, the value is ignored.
-- If no minimum value is found, returns (nil, nil).
function Array.min_by(array, as_comparable)
	return best(array, function(_, value) return as_comparable(value) end, function(a, b) return a < b end)
end

-- Array.min_byi : Array<Value> -> (Index -> Value -> Comparable) -> (Index, Value)
-- Returns (index, value) of the smallest element by comparing the values returned by the as_comparable function for each element.
-- Same as Array.min_by, but the as_comparable function is supplied with (index, value) instead of just the value.
-- If as_comparable returns nil, the value is ignored.
-- If no minimum value is found, returns (nil, nil).
function Array.min_byi(array, as_comparable)
	return best(array, as_comparable, function(a, b) return a < b end)
end

-- Array.max : Array<Value> -> (Index, Value)
-- Array.max : Array<Value> -> (Value -> Value -> Bool) -> (Index, Value)
-- Returns (index, value) of the largest element determined by calling compare(a, b) for each successive element.
-- The optional compare function is expected to return true when a is less than b.
-- If the compare function is not supplied, the standard Lua operator < is used.
-- If the array is empty, returns (nil, nil).
function Array.max(array, compare)
	compare = compare or function(a, b) return a < b end
	return best(array, function(_, value) return value end, function(a, b) return compare(b, a) end)
end

-- Array.max_by : Array<Value> -> (Value -> Comparable) -> (Index, Value)
-- Returns (index, value) of the largest element by comparing the values returned by the as_comparable function for each element.
-- If as_comparable returns nil, the value is ignored.
-- If no maximum value is found, returns (nil, nil).
function Array.max_by(array, as_comparable)
	return best(array, function(_, value) return as_comparable(value) end, function(a, b) return a > b end)
end

-- Array.max_byi : Array<Value> -> (Index -> Value -> Comparable) -> (Index, Value)
-- Returns (index, value) of the largest element by comparing the values returned by the as_comparable function for each element.
-- Same as Array.max_by, but the as_comparable function is supplied with (index, value) instead of just the value.
-- If as_comparable returns nil, the value is ignored.
-- If no maximum value is found, returns (nil, nil).
function Array.max_byi(array, as_comparable)
	return best(array, as_comparable, function(a, b) return a > b end)
end

-- Array.partition : Array<Value> -> (Value -> Bool) -> (Array<Value>, Array<Value>)
-- Partitions an array into two new arrays. The assign_bucket function is applied
-- to each value. If it returns true, the value is placed in the first bucket.
-- If untrue, the value is placed in the second bucket. The result is a tuple of
-- (true_values, false_values)
--
-- Example:
--   numbers = { 1, 2, 3, 4, 5 }
--   is_even = function(n) return (n % 2) == 0 end
--   even, odd = Array.partition(numbers, is_even)
--   even => { 2, 4 }
--   odd => { 1, 3, 5 }
function Array.partition(array, assign_bucket)
	return Array.partitioni(array, function(_, value) return assign_bucket(value) end)
end

-- Array.partitioni : Array<Value> -> (Index -> Value -> Bool) -> (Array<Value>, Array<Value>)
-- Partitions an array into two new arrays. The assign_bucket function is applied to
-- each (index, value). If it returns true, the value is placed in the first bucket.
-- If untrue, the value is placed in the second bucket. The result is a tuple of
-- (true_values, false_values)
function Array.partitioni(array, assign_bucket)
	local count = #array
	local true_values = setmetatable({}, Array.MetaTable)
	local false_values = setmetatable({}, Array.MetaTable)
	
	for index = 1, count do
		local value = array[index]
		local test_result = not not assign_bucket(index, value)
		local bucket = test_result and true_values or false_values
		table.insert(bucket, value)
	end
	
	return true_values, false_values
end

-- Array.distinct : Array<Value> -> Array<Value>
-- Returns a new array containing only unique elements. Element order is preserved.
function Array.distinct(array)
	local count = #array
	local seen = {}
	local new_array = setmetatable({}, Array.MetaTable)
	
	for index = 1, count do
		local value = array[index]
		
		if seen[value] == nil then
			seen[value] = true
			table.insert(new_array, value)
		end
	end
	
	return new_array
end

-- Array.init : Count -> (Index -> Value)
-- Returns a new array of count values generated by calling generate(index).
function Array.init(count, generate)
	local new_array = setmetatable({}, Array.MetaTable)
	
	for index = 1, count do
		local value = generate(index)
		assert(value ~= nil)
		table.insert(new_array, value)
	end
	
	return new_array
end

-- Array.reverse : Array<Value> -> Array<Value>
-- Returns a new array with the elements reversed.
function Array.reverse(array)
	local new_array = setmetatable({}, Array.MetaTable)
	
	for index = #array, 1, -1 do
		table.insert(new_array, array[index])
	end
	
	return new_array
end

-- Array.insert : Array<Value> -> Value -> Array<Value>
-- Array.insert : Array<Value> -> Index -> Value -> Array<Value>
-- Returns a new array with the supplied element added at the specified index.
function Array.insert(array, value_or_index, value)
	local new_array = Array.copy(array)
	
	if value == nil then
		table.insert(new_array, value_or_index)
	else
		table.insert(new_array, value_or_index, value)
	end
	
	return new_array
end

-- Array.sub : Array<Value> -> Index -> Array<Value>
-- Array.sub : Array<Value> -> Index -> Index -> Array<Value>
-- Returns a new array with the elements in the requested subrange, specified by start and optional end index.
-- If an end index is not supplied, every element from the start index onward will be returned.
-- Works just like string.sub, but operates on arrays.
function Array.sub(array, start_index, end_index)
	end_index = end_index or #array
	local new_array = setmetatable({}, Array.MetaTable)
	
	for index = start_index, end_index do
		table.insert(new_array, array[index])
	end
	
	return new_array
end

-- Array.eq : Array<Value> -> Array<Value> -> Bool
-- Returns true if the content of both arrays are equal.
-- If both arrays are nil, returns true.
-- If only one of the arrays are nil, returns false.
-- If the optional eq function is supplied, it will be called on each pair of elements.
-- Otherwise, the standard Lua operator == is used to compare elements.
function Array.eq(array, other, eq)
	if array == other then
		return true
	end

	if array == nil or other == nil then
		return false
	end

	local count = #array

	if count ~= #other then
		return false
	end

	eq = eq or function(a, b) return a == b end

	for index = 1, count do
		local a = array[index]
		local b = other[index]

		if not eq(a, b) then
			return false
		end
	end

	return true
end

-- Array.any : Array<Value> -> (Value -> Bool) -> Bool
-- Returns true if the supplied test function returns true for any element in the array.
function Array.any(array, test)
	return Array.find(array, test) ~= nil
end

-- Array.all : Array<Value> -> (Value -> Bool) -> Bool
-- Returns true if the supplied test function returns true for all elements in the array.
function Array.all(array, test)
	return Array.find(array, Func.negate(test)) == nil
end
