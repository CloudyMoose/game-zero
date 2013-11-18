function init()
	Application.set_autoload_enabled(true)
	require "core/editor_slave/unit_editor/unit_editor"
	UnitEditor:init()
end

function shutdown()
	UnitEditor:shutdown()
end

function update(dt)
	UnitEditor:update(dt)
end

function render()
	UnitEditor:render(dt)
end
