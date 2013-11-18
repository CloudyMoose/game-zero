function boot()
	if Window then
		Window.set_cursor("")
		Window.set_clip_cursor(false)
	end
	
	Application.set_autoload_enabled(true)
	
	require "core/editor_slave/tuple"
	require "core/editor_slave/func"
	require "core/editor_slave/op"
	require "core/editor_slave/nilable"
	require "core/editor_slave/array"
	require "core/editor_slave/dict"
	require "core/editor_slave/set"
	require "core/editor_slave/class"
	require "core/editor_slave/validation"
	require "core/editor_slave/math"
	require "core/editor_slave/editor_camera"
	require "core/editor_slave/move_gizmo"
	require "core/editor_slave/rotate_gizmo"
	require "core/editor_slave/scale_gizmo"
	require "core/editor_slave/box_selection"
	require "core/editor_slave/level_editor/lighting"
	require "core/editor_slave/level_editor/picking"
	require "core/editor_slave/level_editor/scene_element_ref"
	require "core/editor_slave/level_editor/align"
	require "core/editor_slave/level_editor/object_utils"
	require "core/editor_slave/level_editor/physics_simulation"
	require "core/editor_slave/level_editor/level_editor"
	require "core/editor_slave/level_editor/grid_plane"
	require "core/editor_slave/level_editor/selection"
	require "core/editor_slave/level_editor/scatter_manager"
	require "core/editor_slave/level_editor/tool"
	require "core/editor_slave/level_editor/select_tool"
	require "core/editor_slave/level_editor/place_tool"
	require "core/editor_slave/level_editor/move_tool"
	require "core/editor_slave/level_editor/rotate_tool"
	require "core/editor_slave/level_editor/scale_tool"
	require "core/editor_slave/level_editor/box_size_tool"
	require "core/editor_slave/level_editor/snap_together_tool"
	require "core/editor_slave/level_editor/object"
	require "core/editor_slave/level_editor/notes"
	require "core/editor_slave/level_editor/unit"
	require "core/editor_slave/level_editor/level_reference"
	require "core/editor_slave/level_editor/group"
	require "core/editor_slave/level_editor/marker_tool"
	require "core/editor_slave/level_editor/box_objects"
	require "core/editor_slave/level_editor/box_tool"
	require "core/editor_slave/level_editor/navmesh_tool"
	require "core/editor_slave/level_editor/particle_effect"
	require "core/editor_slave/level_editor/spline"
	require "core/editor_slave/level_editor/scatter_tool"
	require "core/editor_slave/level_editor/landscape_tool"
	require "core/editor_slave/level_editor/volume_tool"
	require "core/editor_slave/level_editor/unit_preview"
	require "core/editor_slave/level_editor/static_pvs_tool"
	require "core/editor_slave/level_editor/cubemap_generator"
	require "core/editor_slave/level_editor/sound"
	require "core/editor_slave/level_editor/story_teller"
end

function init()
	boot()
	LevelEditor:init()
end

function shutdown()
	LevelEditor:shutdown()
end

function update(dt)
	LevelEditor:update(dt)
end

function render()
	LevelEditor:render(dt)
end
