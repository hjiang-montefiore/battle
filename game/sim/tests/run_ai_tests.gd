extends SceneTree
## Runs every AI suite and sums their verdicts.
##
## WHY THIS EXISTS. test_ai_works.gd and test_ai_hunt.gd carried 119 assertions
## -- including the placement_problem() fence that is the whole information
## firewall for base building -- and were wired into NOTHING. run_sim_tests.gd
## is self-contained, with its own explicit suite list, so a repo-wide grep for
## either filename found only their own header comments. The headline "169
## passed" covered no AI code at all, and the assertions behind every claim
## that the AI was fixed would never have run again unless somebody remembered
## the filenames.
##
## That is the same failure this project keeps catching in other clothes: work
## that passes its tests while being installed in nothing.

const SUITES := [
	"res://sim/tests/test_ai.gd",        # fairness: the firewall
	"res://sim/tests/test_ai_works.gd",  # siting, budget, build order
	"res://sim/tests/test_ai_hunt.gd",   # is it actually dangerous
]


func _initialize() -> void:
	var exe := OS.get_executable_path()
	var project := ProjectSettings.globalize_path("res://")
	var failed := 0
	print("\n  BATTLE -- every AI suite")
	print("  " + "=".repeat(58))
	for s in SUITES:
		var out: Array = []
		var code := OS.execute(exe, ["--headless", "--path", project,
			"--script", s], out, true)
		var text: String = "\n".join(out)
		var line := "no verdict"
		for l in text.split("\n"):
			var t := l.strip_edges()
			if t.contains("passed,") and (t.contains("failed") or t.contains("FAILED")):
				line = t
		if code != 0:
			failed += 1
		print("  %-26s %s%s" % [s.get_file(), line,
			"" if code == 0 else "   <-- EXIT %d" % code])
	print("  " + "=".repeat(58))
	print("  %d suite(s) FAILED\n" % failed)
	quit(1 if failed > 0 else 0)


func _process(_d: float) -> bool:
	return true
