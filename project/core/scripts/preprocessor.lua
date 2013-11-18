local LINE_CHAR = "\n"
local SYMBOL_MT = {__tostring = function(o) return o.name end}
local ORG_TYPE = type

function symbol(s)
	local o = {name = s}
	return setmetatable(o, SYMBOL_MT)
end

function type(o)
	local t = ORG_TYPE(o)
	if t == "table" and getmetatable(o) == SYMBOL_MT then
		return "symbol"
	end
	return t
end

local function count_lines(str)
	local i = 1
	for _ in string.gmatch(str, "[\n\r]") do
		i = i + 1
	end
	return i
end

local function duplicate(str, num)
	local s = ""
	for i = 1, num do
		s = s .. str
	end
	return s
end

local function macro(str, file, block)
	str = string.gsub(str, "@([%w%.:_]+)", function(s) return "symbol('" .. s .. "')" end)
	
	local func, msg = loadstring(block and "do " .. str .. " end" or "return " .. str, "preprocessor: " .. file)
	if not func then
		error("Preprocessor: " .. msg)
	end

	local nl = count_lines(str)
	local ret = func(str, nl, file)
	ret = ORG_TYPE(ret) == "string" and ret or ""
	local diff = nl - count_lines(ret)

	if diff < 0 then
		ret = string.gsub(ret, "[\n\r]", " ")
		diff = nl - count_lines(ret)
	end

	if diff > 0 then
		ret = ret .. duplicate(LINE_CHAR, diff)
	end
	return ret
end

local function strip_comments(str)
	str = string.gsub(str, "%-%-%b[]", function(s) return (string.find(s, "--[[@", 1, true) == 1) and s or duplicate("\n", count_lines(s) - 1) end)
	return string.gsub(str, "%-%-([^%z\n\r]+)", function(s) return (string.find(s, "@") == 1 or string.find(s, "[[@", 1, true) == 1) and ("--" .. s) or "" end)
end

function __preprocess(str, file)
	str = string.gsub(strip_comments(str), "%-%-%b[]", function(s) return macro(string.match(s, "%-%-%[%[@(.+)%]%]"), file, true) end)
	return string.gsub(str, "%-%-@([^%z\n\r]+)", function(s) return macro(s, file) end)
end

--[[
local str = io.open("input.lua"):read("*a")
str = __preprocess(str, "input.lua")
local file = io.open("output.lua", "w")
file:write(str)
file:close()
--print(str)
]]
