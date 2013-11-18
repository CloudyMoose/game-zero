require 'core/editor_slave/array'

--------------------------------------------------
-- Utility functions
--------------------------------------------------

local function best(dict, as_comparable, compare)
	local best_key = nil
	local best_comparable_value = nil
	
	for key, value in pairs(dict) do
		local comparable_value = as_comparable(key, value)
		
		if comparable_value ~= nil then
			if best_comparable_value == nil or compare(comparable_value, best_comparable_value) then
				best_key = key
				best_comparable_value = comparable_value
			end
		end
	end
	
	local best_value = best_key ~= nil and dict[best_key] or nil
	return best_key, best_value
end


--------------------------------------------------
-- Dict functions
--------------------------------------------------

Dict = Dict or {}
Dict.MetaTable = Dict.MetaTable or { __index = Dict }

-- Dict.is_empty : Dict<Key, Value> -> Bool
-- Returns true if the supplied dict is empty, or false if the dict has at least one key.
function Dict.is_empty(dict)
	for _, _ in pairs(dict) do
		return false
	end
	
	return true
end

-- Dict.keys : Dict<Key, Value> -> Array<Key>
-- Returns a new array containing the unordered keys of the supplied dict.
function Dict.keys(dict)
	local keys = setmetatable({}, Array.MetaTable)
	
	for key, _ in pairs(dict) do
		table.insert(keys, key)
	end
	
	return keys
end

-- Dict.keys : Dict<Key, Value> -> Array<Value>
-- Returns a new array containing the unordered values of the supplied dict.
function Dict.values(dict)
	local values = setmetatable({}, Array.MetaTable)
	
	for _, value in pairs(dict) do
		table.insert(values, value)
	end
	
	return values
end

-- Dict.contains_key : Dict<Key, Value> -> Key -> Bool
-- Returns true if a dict contains the specified key, otherwise returns false.
function Dict.contains_key(dict, key)
	return dict[key] ~= nil
end

-- Dict.filter : Dict<Key, Value> -> (Key -> Value -> Bool) -> Dict<Key, Value>
-- Returns a new dict containing only the elements where test(key, value) evaluates to true.
function Dict.filter(dict, test)
	local new_dict = setmetatable({}, Dict.MetaTable)
	
	for key, value in pairs(dict) do
		if test(key, value) then
			new_dict[key] = value
		end
	end
	
	return new_dict
end

-- Dict.find : Dict<Key, Value> -> (Key -> Value -> Bool) -> (Key, Value)
-- Returns (key, value) of a random element where test(key, value) evaluates to true.
-- If no match is found, returns (nil, nil).
function Dict.find(dict, test)
	for key, value in pairs(dict) do
		if test(key, value) then
			return key, value
		end
	end
	
	return nil, nil
end

-- Dict.pick : Dict<Key, Value> -> (Key -> Value -> Result) -> Result
-- Returns the first non-nil result of calling choose(key, value) on elements in a dict.
-- If no match is found, returns nil.
-- If multiple matches exist, pick returns one of the matches at random.
function Dict.pick(dict, choose)
	for key, value in pairs(dict) do
		local result = choose(key, value)
		
		if result ~= nil then
			return result
		end
	end
	
	return nil
end

-- Dict.copy : Dict<Key, Value> -> Dict<Key, Value>
-- Returns a new dict with all the elements of the supplied dict.
-- Does not perform a deep copy of the contents.
function Dict.copy(dict)
	local new_dict = setmetatable({}, Dict.MetaTable)
	
	for key, value in pairs(dict) do
		new_dict[key] = value
	end
	
	return new_dict
end

-- Dict.map : Dict<Key, Value> -> (Key -> Value -> Result) -> Dict<Key, Result>
-- Returns a new dict with the results of applying transform(key, value) to each element.
-- If transform(key, value) returns nil, the entry will be excluded from the resulting dict.
function Dict.map(dict, transform)
	local new_dict = setmetatable({}, Dict.MetaTable)
	
	for key, value in pairs(dict) do
		new_dict[key] = transform(key, value)
	end
	
	return new_dict
end

-- Dict.remap : Dict<Key, Value> -> (Key -> Value -> (NewKey, Result)) -> Dict<NewKey, Result>
-- Returns a new dict with the results of applying transform(key, value) to each element.
-- The transform function is expected to return (key, value) for each entry to store in the resulting dict.
-- If transform(key, value) returns (key, nil), the entry will be excluded from the resulting dict.
function Dict.remap(dict, transform)
	local new_dict = setmetatable({}, Dict.MetaTable)
	
	for key, value in pairs(dict) do
		local new_key, new_value = transform(key, value)
		
		if new_key ~= nil and new_value ~= nil then
			-- We consider duplicate keys an error.
			-- If you wanted to replace an existing element, you'd get non-deterministic results since elements are unordered.
			assert(new_dict[new_key] == nil)
			new_dict[new_key] = new_value
		end
	end
	
	return new_dict
end

-- Dict.iter : Dict<Key, Value> -> (Key -> Value -> ()) -> ()
-- Calls visit(key, value) for each pair.
function Dict.iter(dict, visit)
	for key, value in pairs(dict) do
		visit(key, value)
	end
end

-- Dict.fold : Dict<Key, Value> -> Result -> (Result -> Key -> Value -> Result) -> Result
-- Returns the result of applying accumulate(result, key, value) to each element.
-- The accumulate function is expected to return a single value that can be supplied as the first argument to itself on the next pass.
function Dict.fold(dict, init, accumulate)
	local result = init
	
	for key, value in pairs(dict) do
		result = accumulate(result, key, value)
	end
	
	return result
end

-- Dict.merge : Dict<Key, Value> -> Dict<Key, Value> -> Dict<Key, Value>
-- Returns a new dict with all the entries from both dicts.
-- Elements in the second dict replace elements in the first if there are conflicting keys.
function Dict.merge(dict_a, dict_b)
	local new_dict = Dict.copy(dict_a)
	
	for key, value in pairs(dict_b) do
		new_dict[key] = value
	end
	
	return new_dict
end

-- Dict.exclude : Dict<Key, Value> -> Dict<Key, Value> -> Dict<Key, Value>
-- Returns a new dict with the keys of the second dict removed from the first.
function Dict.exclude(dict, excluded_dict)
	local new_dict = Dict.copy(dict)

	for key, _ in pairs(excluded_dict) do
		new_dict[key] = nil
	end

	return new_dict
end

-- Dict.min : Dict<Key, Value> -> (Key, Value)
-- Dict.min : Dict<Key, Value> -> (Value -> Value -> Bool) -> (Key, Value)
-- Returns (key, value) of the smallest element determined by calling compare(a, b) for all values.
-- The optional compare function is expected to return true when a is less than b.
-- If the compare function is not supplied, the standard Lua operator < is used.
-- If the dict is empty, returns (nil, nil).
function Dict.min(dict, compare)
	compare = compare or function(a, b) return a < b end
	return best(dict, function(_, value) return value end, function(a, b) return compare(a, b) end)
end

-- Dict.min_by : Dict<Key, Value> -> (Key -> Value -> Comparable) -> (Key, Value)
-- Returns (key, value) of the smallest element by comparing the results of calling as_comparable(key, value) for each entry.
-- If as_comparable returns nil, the entry is ignored.
-- If no minimum value is found, returns (nil, nil).
function Dict.min_by(dict, as_comparable)
	return best(dict, as_comparable, function(a, b) return a < b end)
end

-- Dict.max : Dict<Key, Value> -> (Key, Value)
-- Dict.max : Dict<Key, Value> -> (Value -> Value -> Bool) -> (Key, Value)
-- Returns (key, value) of the largest element determined by calling compare(a, b) for all values.
-- The optional compare function is expected to return true when a is less than b.
-- If the compare function is not supplied, the standard Lua operator < is used.
-- If the dict is empty, returns (nil, nil).
function Dict.max(dict, compare)
	compare = compare or function(a, b) return a < b end
	return best(dict, function(_, value) return value end, function(a, b) return compare(b, a) end)
end

-- Dict.max_by : Dict<Key, Value> -> (Key -> Value -> Comparable) -> (Key, Value)
-- Returns (key, value) of the largest element by comparing the results of calling as_comparable(key, value) for each entry.
-- If as_comparable returns nil, the entry is ignored.
-- If no maximum value is found, returns (nil, nil).
function Dict.max_by(dict, as_comparable)
	return best(dict, as_comparable, function(a, b) return a > b end)
end

-- Dict.of_array : Array<Value> -> (Value -> Key) -> Dict<Key, Value>
-- Dict.of_array : Array<Value> -> (Value -> Key) -> (Value -> Result) -> Dict<Key, Result>
-- Returns a new dict constructed from calling get_key and get_value on each value in the supplied array.
-- Raises an error if either call yields nil.
function Dict.of_array(array, get_key, get_value)
	local get_key_and_value = get_value == nil
	  and function(_, value) return get_key(value), value end
	   or function(_, value) return get_key(value), get_value(value) end
	
	local new_dict = Dict.remap(array, get_key_and_value)
	return new_dict
end
