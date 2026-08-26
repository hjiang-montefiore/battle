class_name SimMatchSetup
extends RefCounted
## A whole match: one human, N AI. docs/09 §4, §6.
##
## The scenario system needs no separate mechanism -- start epoch, ceiling
## epoch, force preset and doctrine already express every scenario in docs/09
## §4, and the presets below are those rows as data.

var players: Array = []            ## Array[SimPlayerSetup]
var name: String = "Skirmish"
var seed_value: int = 12345


func add(p: SimPlayerSetup) -> SimPlayerSetup:
	players.append(p)
	return p


func humans() -> Array:
	return players.filter(func(p): return p.is_human)


func ais() -> Array:
	return players.filter(func(p): return not p.is_human)


## Allied players share a track table -- exactly the coalition mechanic in
## docs/08, with no new system: fusion simply spans more than one player.
func teams() -> Dictionary:
	var out: Dictionary = {}
	for p in players:
		if not out.has(p.team):
			out[p.team] = []
		out[p.team].append(p)
	return out


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	for p in players:
		problems.append_array(p.validate())

	if players.size() < 2:
		problems.append("a match needs at least two participants")
	if humans().size() > 1:
		problems.append("this is a single-player game -- at most one human")

	var team_ids: Array = teams().keys()
	if team_ids.size() < 2:
		problems.append("every participant is on the same team -- nobody to fight")

	# A named scenario whose ceilings are all equal is a peer fight; that is
	# legal, so it is not reported. What is worth catching is a participant who
	# cannot reach any domain the map requires -- the scenario layer owns that,
	# not this class.
	return problems


func describe() -> String:
	var lines := PackedStringArray()
	lines.append("=== %s ===" % name)
	for p in players:
		lines.append(p.describe())
	var problems := validate()
	if problems.is_empty():
		lines.append("setup valid")
	else:
		lines.append("PROBLEMS:")
		for pr in problems:
			lines.append("  ! " + pr)
	return "\n".join(lines)


# ── the docs/09 §4 scenario table, as data ───────────────────────────────────

static func scenario(key: String) -> SimMatchSetup:
	var m := SimMatchSetup.new()
	match key:
		"hold_the_line":
			# Beat the fuel clock while they out-tech you.
			m.name = "Hold the Line"
			m.add(SimPlayerSetup.new({"name": "You", "is_human": true, "team": 0,
				"faction": SimPlayerSetup.Faction.ROC,
				"start_epoch": 5, "ceiling_epoch": 5,
				"starting_forces": SimPlayerSetup.ForcePreset.GARRISON}))
			m.add(SimPlayerSetup.new({"name": "PLA", "team": 1,
				"faction": SimPlayerSetup.Faction.PLA,
				"start_epoch": 5, "ceiling_epoch": 7,
				"starting_forces": SimPlayerSetup.ForcePreset.ARMY,
				"skill": SimSkill.Level.PROFESSIONAL,
				"doctrine": SimDoctrine.make(SimDoctrine.Profile.SENSOR_DOMINANCE)}))
		"the_gap":
			# Survive the mass until the generation gap opens.
			m.name = "The Gap"
			m.add(SimPlayerSetup.new({"name": "You", "is_human": true, "team": 0,
				"faction": SimPlayerSetup.Faction.US,
				"start_epoch": 1, "ceiling_epoch": 7,
				"starting_forces": SimPlayerSetup.ForcePreset.SKIRMISH}))
			m.add(SimPlayerSetup.new({"name": "KPA", "team": 1,
				"faction": SimPlayerSetup.Faction.KPA,
				"start_epoch": 2, "ceiling_epoch": 2,
				"starting_forces": SimPlayerSetup.ForcePreset.MASSED,
				"skill": SimSkill.Level.REGULAR,
				"doctrine": SimDoctrine.make(SimDoctrine.Profile.ATTRITION)}))
		"peer":
			m.name = "Peer"
			m.add(SimPlayerSetup.new({"name": "You", "is_human": true, "team": 0,
				"faction": SimPlayerSetup.Faction.GERMANY,
				"start_epoch": 4, "ceiling_epoch": 6}))
			m.add(SimPlayerSetup.new({"name": "Russia", "team": 1,
				"faction": SimPlayerSetup.Faction.RUSSIA,
				"start_epoch": 4, "ceiling_epoch": 6,
				"skill": SimSkill.Level.ELITE}))
		"blind":
			# Fight with your picture under constant attack.
			m.name = "Blind"
			m.add(SimPlayerSetup.new({"name": "You", "is_human": true, "team": 0,
				"faction": SimPlayerSetup.Faction.FRANCE,
				"start_epoch": 6, "ceiling_epoch": 6}))
			m.add(SimPlayerSetup.new({"name": "PLA", "team": 1,
				"faction": SimPlayerSetup.Faction.PLA,
				"start_epoch": 6, "ceiling_epoch": 6,
				"skill": SimSkill.Level.ELITE,
				"doctrine": SimDoctrine.make(SimDoctrine.Profile.DENIAL)}))
		"coalition":
			# You have no organic AEW. Protect the ally who does.
			m.name = "Coalition"
			m.add(SimPlayerSetup.new({"name": "You", "is_human": true, "team": 0,
				"faction": SimPlayerSetup.Faction.GERMANY,
				"start_epoch": 5, "ceiling_epoch": 6}))
			var ally := SimPlayerSetup.new({"name": "US ally", "team": 0,
				"faction": SimPlayerSetup.Faction.US,
				"start_epoch": 5, "ceiling_epoch": 6,
				"skill": SimSkill.Level.PROFESSIONAL,
				"doctrine": SimDoctrine.make(SimDoctrine.Profile.SENSOR_DOMINANCE)})
			m.add(ally)
			m.add(SimPlayerSetup.new({"name": "Russia", "team": 1,
				"faction": SimPlayerSetup.Faction.RUSSIA,
				"start_epoch": 5, "ceiling_epoch": 6,
				"skill": SimSkill.Level.VETERAN}))
			m.add(SimPlayerSetup.new({"name": "Russian ally", "team": 1,
				"faction": SimPlayerSetup.Faction.RUSSIA,
				"start_epoch": 5, "ceiling_epoch": 6,
				"skill": SimSkill.Level.REGULAR}))
		"overmatch":
			# The escape-valve stress test: can mass beat generation?
			m.name = "Overmatch"
			m.add(SimPlayerSetup.new({"name": "You", "is_human": true, "team": 0,
				"faction": SimPlayerSetup.Faction.US,
				"start_epoch": 7, "ceiling_epoch": 7,
				"starting_forces": SimPlayerSetup.ForcePreset.SKIRMISH}))
			for i in range(3):
				m.add(SimPlayerSetup.new({"name": "Mass %d" % (i + 1), "team": 1,
					"faction": SimPlayerSetup.Faction.KPA,
					"start_epoch": 3, "ceiling_epoch": 3,
					"starting_forces": SimPlayerSetup.ForcePreset.MASSED,
					"skill": SimSkill.Level.REGULAR,
					"doctrine": SimDoctrine.make(SimDoctrine.Profile.ATTRITION)}))
	return m


const SCENARIOS := ["hold_the_line", "the_gap", "peer", "blind",
					"coalition", "overmatch"]
