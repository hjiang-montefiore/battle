extends SceneTree
## The map editor's scripted authoring session, run sceneless for CI.
##
##     godot --path game --headless --script res://sim/tests/test_map_file_editor.gd
##
## The editor's document logic -- op recording, incremental-vs-replay
## equality, placement refusals, undo, save/load -- lives in
## scripts/map_editor.gd with every visual call null-guarded, so the same
## session that runs inside the scene (--test) runs here with no viewport at
## all. One session, two harnesses, zero duplicated assertions.


func _init() -> void:
	var editor: Node3D = (load("res://scripts/map_editor.gd") as GDScript).new()
	var failed: int = editor.run_test_session()
	editor.free()
	quit(1 if failed > 0 else 0)
