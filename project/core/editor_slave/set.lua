require 'core/editor_slave/dict'

Set = Set or {}
Set.MetaTable = Set.MetaTable or { __index = Set }

-- Set.is_empty : Set<Value> -> Bool
-- Returns true if the supplied set is empty, or false if the set has at least one element.
Set.is_empty = Dict.is_empty

-- Set.contains : Set<Value> -> Value -> Bool
-- Returns true if a set contains the specified key, otherwise returns false.
function Set.contains(set, element)
	return set[element] ~= nil
end

-- Set.map : Set<Value> -> (Value -> Result) -> Set<Result>
-- Returns a new set with the results of applying transform(value) to each element.
-- If transform(value) returns nil, the entry will be excluded from the resulting set.
function Set.map(set, transform)
	local new_set = setmetatable({}, Set.MetaTable)
	
	for value in pairs(set) do
		local transformed_value = transform(value)

		if transformed_value ~= nil then
			new_set[transformed_value] = true
		end
	end
	
	return new_set
end

-- Set.iter : Set<Value> -> (Value -> ())) -> ())
-- Calls visit(value) for each value in the set. Elements are visited in random order.
function Set.iter(set, visit)
	for value in pairs(set) do
		visit(value)
	end
end

-- Set.of : (Value, ...) -> Set<Value>
-- Returns a new set with all the supplied values.
function Set.of(...)
	return Set.of_array({...})
end

-- Set.of_array : Array<Value> -> Set<Value>
-- Set.of_array : Array<Value> -> (Value -> Result) -> Set<Result>
-- Returns a new set containing unique elements from the supplied array.
-- If the optional transform function is supplied, applies it to each element and constructs the set from its return values.
-- If transform(value) returns nil, the entry will be excluded from the resulting set.
-- If transform(value) returns a value that is already in the set, the new value will replace the old value.
function Set.of_array(array, transform)
	local count = #array
	local new_set = setmetatable({}, Set.MetaTable)
	
	for index = 1, count do
		local value = array[index]
		local transformed_value = transform ~= nil and transform(value) or value
		
		if transformed_value ~= nil then
			new_set[transformed_value] = true
		end
	end
	
	return new_set
end

-- Set.to_array : Set<Value> -> Array<Value>
-- Returns a new array with the unordered elements of the set.
function Set.to_array(set)
	return Dict.keys(set)
end

-- Set.copy : Set<Value> -> Set<Value>
-- Returns a new set with all the elements of the supplied set.
-- Does not perform a deep copy of the contents.
function Set.copy(set)
	return setmetatable(Dict.copy(set), Set.MetaTable)
end

-- Set.union : Set<Value> -> Set<Value> -> Set<Value>
-- Returns a new set with all the elements from both sets.
function Set.union(set_a, set_b)
	return setmetatable(Dict.merge(set_a, set_b), Set.MetaTable)
end

-- Set.difference : Set<Value> -> Set<Value> -> Set<Value>
-- Returns a new set with the elements of the second set removed from the first.
function Set.difference(set, excluded_set)
	return setmetatable(Dict.exclude(set, excluded_set), Set.MetaTable)
end
