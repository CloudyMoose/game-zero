SmokeTest = class(SmokeTest)

function SmokeTest:init()
	local commands = {
		success = false,
		fail = false,
		heartbeat = false
	}

	local argv = {Application.argv()}
	for i = 1, table.maxn(argv) do
		for cmd,_ in pairs(commands) do
			if argv[i] == '-' .. cmd then
				i = i + 1
				commands[cmd] = argv[i]
			end
			i = i + 1
		end
	end

	self.is_enabled = function() return commands.success and commands.fail and commands.heartbeat end
	for k,v in pairs(commands) do
		self[k] = function(self)
			if self.is_enabled() then
				if k ~= "heartbeat" then
					print("Smoketest returns: ", k)
				end
				print(v)
				if k ~= "heartbeat" and Application.quit then
					Application.quit()
				end
			end
		end
	end
end
