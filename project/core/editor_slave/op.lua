Op = Op or {}

-- Op.eq : Value -> (Value -> Bool)
-- Returns a function that will return true if called with a value equal to x.
function Op.eq(x)
	return function(y)
		return x == y
	end
end

-- Op.neq : Value -> (Value -> Bool)
-- Returns a function that will return false if called with a value equal to x.
function Op.neq(x)
	return function(y)
		return x ~= y
	end
end

-- Op.mul : Value -> (Value -> Value)
-- Returns a function that multiplies a value with the specified value.
function Op.mul(x)
	return function(y)
		return x * y
	end
end

-- Op.div : Value -> (Value -> Value)
-- Returns a function that divides a value with the specified value.
function Op.div(x)
	return function(y)
		return y / x
	end
end
