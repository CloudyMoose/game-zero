Sample.Utility = Sample.Utility or {}
local M = Sample.Utility

function M.is_pc()
	return Application.platform() == Application.WIN32 or Application.platform() == Application.MACOSX
end

function M.plat(pc, ps3, x360)
	local p = Application.platform()
	if p == Application.PS3 then return ps3 end
	if p == Application.X360 then return x360 end
	return pc
end

return M