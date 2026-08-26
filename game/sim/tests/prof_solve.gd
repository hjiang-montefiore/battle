extends SceneTree
## Which part of the sensor solve costs the 56 ms?
var _code := 1

func _initialize() -> void:
	var setup := SimMatchSetup.scenario("peer")
	var m := SimMatch.start(setup, SimArena.SKIRMISH_VALLEY, true)
	var w: SimWorld = m.world
	m.run_ticks(400)
	var s := w.solver
	var n := w.entities.count()

	var t0 := Time.get_ticks_usec()
	for i in range(20):
		s.solve(0.2, i)
	var full := (Time.get_ticks_usec() - t0) / 20.0
	print("entities %d | full solve %.2f ms | pairs %d | detections %d"
		% [n, full / 1000.0, s.last_pair_evaluations, s.last_detections])

	# how many sensors are there in total, and what is the pair budget?
	var sensors := 0
	for i in range(n):
		sensors += (w.entities.sensors.get(i, []) as Array).size()
	print("  sensors mounted: %d   worst-case pairs/solve: %d" % [sensors, sensors * n])

	# cost of the raw range test alone across every pair
	var t1 := Time.get_ticks_usec()
	var acc := 0.0
	for rep in range(20):
		for a in range(n):
			for b in range(n):
				acc += w.entities.range_km(a, b)
	var rng := (Time.get_ticks_usec() - t1) / 20.0
	print("  range_km over all %d pairs: %.2f ms  (acc %.0f)" % [n * n, rng / 1000.0, acc])

	# cost of one terrain LOS ray
	var t2 := Time.get_ticks_usec()
	var hits := 0
	for rep in range(2000):
		if w.terrain.has_line_of_sight(-3000.0, 40.0, 3000.0, 3000.0, 40.0, -3000.0):
			hits += 1
	var los := (Time.get_ticks_usec() - t2) / 2000.0
	print("  one terrain LOS ray: %.3f ms  (%d clear of 2000)" % [los / 1000.0, hits])
	_code = 0

func _process(_d: float) -> bool:
	quit(_code)
	return true
