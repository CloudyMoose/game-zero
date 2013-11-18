Validation = Validation or {}

function Validation.is_guid(value)
	return type(value) == "string"
	   and #value >= 32
	   and string.match(value, "[^%x%-]") == nil
end

Validation.is_object_id = Validation.is_guid

function Validation.is_component_id(value)
	return type(value) == "string"
	   and #value > 0
end

function Validation.is_table(value)
	return type(value) == "table"
end

function Validation.is_function(value)
	return type(value) == "function"
end

function Validation.is_object_with_method(method_name, object)
	assert(type(method_name) == "string")
	local metatable = getmetatable(object)
	return Validation.is_function(metatable.__call)
	   and Validation.is_table(metatable.__index)
	   and Validation.is_function(metatable.__index[method_name])
end

function Validation.is_non_empty_array(value)
	return Validation.is_table(value)
	   and #value > 0
end

function Validation.is_non_empty_dict(value)
	return Validation.is_table(value)
	   and not Dict.empty(value)
end
