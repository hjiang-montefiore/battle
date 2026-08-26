extends SceneTree
## docs/06: the simulation must be reproducible from a seed. A sim that is not
## reproducible cannot be debugged, cannot be replayed, and closes the door
## docs/06 says to hold open for lockstep multiplayer.
var _code := 1

func _run() -> Array:
	var m := SimMatch.start(SimMatchSetup.scenario("peer"),
		SimArena.SKIRMISH_VALLEY, true)
	var w: SimWorld = m.world
	var guard := 0
	while not m.is_finished() and guard < 80:
		m.run_ticks(600)
		guard += 1
	var alive := 0
	for i in range(w.entities.count()):
		if w.entities.is_alive(i):
			alive += 1
	return [m.is_finished(), int(w.elapsed_s), w.damage.kills,
			w.munitions.launched, alive, m.outcome()]

func _initialize() -> void:
	var a := _run()
	var b := _run()
	print("run A: finished=%s t=%ds kills=%d shots=%d alive=%d outcome=%s" % a)
	print("run B: finished=%s t=%ds kills=%d shots=%d alive=%d outcome=%s" % b)
	var same := true
	for i in range(a.size()):
		if a[i] != b[i]:
			same = false
	print("\n  %s" % ("IDENTICAL -- the sim is reproducible" if same
		else "DIVERGED -- same seed, different match"))
	_code = 0 if same else 1
	if not same:
		print("  PASS" if same else "  FAIL")

func _process(_d: float) -> bool:
	quit(_code)
	return true
