extends SceneTree

func _init() -> void:
	var t := SimTerrain.new(64, 64, 50.0, "flat")
	t.fill(0.0)
	t.carve_sea(-300.0, -500.0, 300.0, 500.0, 40.0)
	var ax := -1200.0; var az := 0.0; var bx := -225.0; var bz := 575.0
	var n := 4000
	var wet_cells := {}
	var worst := 0.0; var wx := 0.0; var wz := 0.0
	var below := 0
	for s in range(n + 1):
		var f := float(s) / float(n)
		var x := ax + (bx - ax) * f
		var z := az + (bz - az) * f
		var h := t.height_at(x, z)
		if h < 0.0: below += 1
		if h < worst:
			worst = h; wx = x; wz = z
		var c := t._to_cell(x, z)
		if t.height_at_cell(c.x, c.y) < 0.0:
			wet_cells[c] = true
	print("min bilinear %.3f at (%.1f, %.1f); samples below zero: %d of %d" % [worst, wx, wz, below, n])
	print("wet cells traversed: ", wet_cells.keys())
	print("cell of worst: ", t._to_cell(wx, wz), " its height ", t.height_at_cell(t._to_cell(wx,wz).x, t._to_cell(wx,wz).y))
	quit(0)
