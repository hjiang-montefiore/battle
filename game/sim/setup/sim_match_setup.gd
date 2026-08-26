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
		"sino_russian_early":
			# docs/08: before ~2000 Chinese equipment is Soviet-DERIVED -- the
			# same tank lineage, the same fighters, the same submarines. This is
			# very nearly a mirror match, and doctrine is the only thing in it.
			m.name = "Amur, 1969"
			m.add(SimPlayerSetup.new({"name": "You", "is_human": true, "team": 0,
				"faction": SimPlayerSetup.Faction.PLA,
				"start_epoch": 2, "ceiling_epoch": 2,
				"starting_forces": SimPlayerSetup.ForcePreset.ARMY}))
			m.add(SimPlayerSetup.new({"name": "Russia", "team": 1,
				"faction": SimPlayerSetup.Faction.RUSSIA,
				"start_epoch": 2, "ceiling_epoch": 2,
				"starting_forces": SimPlayerSetup.ForcePreset.ARMY,
				"skill": SimSkill.Level.VETERAN,
				"doctrine": SimDoctrine.make(SimDoctrine.Profile.ATTRITION)}))
		"sino_russian_late":
			# And by epoch 7 the two answer the sensor question in OPPOSITE
			# ways: the PLA networked and indigenous, Russia denial-focused.
			# docs/08: "a player who has learned to fight one in epoch 2 has
			# learned almost nothing about fighting the other in epoch 7."
			m.name = "Amur, now"
			m.add(SimPlayerSetup.new({"name": "You", "is_human": true, "team": 0,
				"faction": SimPlayerSetup.Faction.PLA,
				"start_epoch": 7, "ceiling_epoch": 7}))
			m.add(SimPlayerSetup.new({"name": "Russia", "team": 1,
				"faction": SimPlayerSetup.Faction.RUSSIA,
				"start_epoch": 7, "ceiling_epoch": 7,
				"skill": SimSkill.Level.ELITE,
				"doctrine": SimDoctrine.make(SimDoctrine.Profile.DENIAL)}))
		"eastern_front":
			# Russia against Ukraine: the same SOVIET lineage on both sides, so
			# neither can out-generation the other. The smaller force answers by
			# attacking what the larger one runs on -- Interdiction, the only
			# doctrine that goes after fuel, supply and the sensor net directly.
			m.name = "Eastern Front"
			m.add(SimPlayerSetup.new({"name": "You", "is_human": true, "team": 0,
				"faction": SimPlayerSetup.Faction.UKRAINE,
				"start_epoch": 5, "ceiling_epoch": 6,
				"starting_forces": SimPlayerSetup.ForcePreset.GARRISON,
				"doctrine": SimDoctrine.make(SimDoctrine.Profile.INTERDICTION)}))
			m.add(SimPlayerSetup.new({"name": "Russia", "team": 1,
				"faction": SimPlayerSetup.Faction.RUSSIA,
				"start_epoch": 5, "ceiling_epoch": 6,
				"starting_forces": SimPlayerSetup.ForcePreset.MASSED,
				"skill": SimSkill.Level.PROFESSIONAL,
				"doctrine": SimDoctrine.make(SimDoctrine.Profile.DENIAL)}))
		"east_china_sea":
			# PLA against Japan. A maritime theatre, so it leans on the pillars
			# the Taiwan Strait row in docs/08 calls out: ASW, AEW&C and
			# anti-ship. Japan fields no strategic offensive arm, which the
			# force restriction expresses directly.
			m.name = "East China Sea"
			var jp := SimPlayerSetup.new({"name": "You", "is_human": true, "team": 0,
				"faction": SimPlayerSetup.Faction.JAPAN,
				"start_epoch": 6, "ceiling_epoch": 7,
				"doctrine": SimDoctrine.make(SimDoctrine.Profile.SENSOR_DOMINANCE)})
			m.add(jp)
			m.add(SimPlayerSetup.new({"name": "PLA", "team": 1,
				"faction": SimPlayerSetup.Faction.PLA,
				"start_epoch": 6, "ceiling_epoch": 7,
				"skill": SimSkill.Level.ELITE,
				"doctrine": SimDoctrine.make(SimDoctrine.Profile.SENSOR_DOMINANCE)}))
		"central_europe":
			# docs/08's Theatres table: the theatre that showcases the NATO
			# split, because all four Western factions appear side by side with
			# visibly different armor and different dependence on the picture.
			m.name = "Central Europe"
			m.add(SimPlayerSetup.new({"name": "You", "is_human": true, "team": 0,
				"faction": SimPlayerSetup.Faction.GERMANY,
				"start_epoch": 5, "ceiling_epoch": 6}))
			m.add(SimPlayerSetup.new({"name": "US", "team": 0,
				"faction": SimPlayerSetup.Faction.US,
				"start_epoch": 5, "ceiling_epoch": 6,
				"skill": SimSkill.Level.PROFESSIONAL}))
			m.add(SimPlayerSetup.new({"name": "France", "team": 0,
				"faction": SimPlayerSetup.Faction.FRANCE,
				"start_epoch": 5, "ceiling_epoch": 6,
				"skill": SimSkill.Level.VETERAN}))
			m.add(SimPlayerSetup.new({"name": "Russia", "team": 1,
				"faction": SimPlayerSetup.Faction.RUSSIA,
				"start_epoch": 5, "ceiling_epoch": 7,
				"starting_forces": SimPlayerSetup.ForcePreset.MASSED,
				"skill": SimSkill.Level.ELITE,
				"doctrine": SimDoctrine.make(SimDoctrine.Profile.DENIAL)}))
		"north_atlantic":
			# Submarine warfare, convoy escort, oiler protection. The theatre
			# that exercises the torpedo and the layer rather than the tank.
			m.name = "North Atlantic"
			var uk := SimPlayerSetup.new({"name": "You", "is_human": true, "team": 0,
				"faction": SimPlayerSetup.Faction.UK,
				"start_epoch": 6, "ceiling_epoch": 6})
			uk.set_army_only()
			uk.restrict_to(SimPlayerSetup.Domain.NAVAL
				| SimPlayerSetup.Domain.AIR | SimPlayerSetup.Domain.STRUCTURES)
			m.add(uk)
			var ru := SimPlayerSetup.new({"name": "Russia", "team": 1,
				"faction": SimPlayerSetup.Faction.RUSSIA,
				"start_epoch": 6, "ceiling_epoch": 6,
				"skill": SimSkill.Level.ELITE,
				"doctrine": SimDoctrine.make(SimDoctrine.Profile.INTERDICTION)})
			ru.restrict_to(SimPlayerSetup.Domain.NAVAL
				| SimPlayerSetup.Domain.AIR | SimPlayerSetup.Domain.STRUCTURES)
			m.add(ru)
		"korean_peninsula":
			# Massed artillery, the generational cliff, terrain masking. The
			# KPA is the design's stress test: the one weapon system that needs
			# no track at all, but firing it CREATES one.
			m.name = "Korean Peninsula"
			m.add(SimPlayerSetup.new({"name": "You", "is_human": true, "team": 0,
				"faction": SimPlayerSetup.Faction.ROC,
				"start_epoch": 6, "ceiling_epoch": 6,
				"starting_forces": SimPlayerSetup.ForcePreset.GARRISON}))
			m.add(SimPlayerSetup.new({"name": "KPA", "team": 1,
				"faction": SimPlayerSetup.Faction.KPA,
				"start_epoch": 3, "ceiling_epoch": 3,
				"starting_forces": SimPlayerSetup.ForcePreset.MASSED,
				"skill": SimSkill.Level.REGULAR,
				"doctrine": SimDoctrine.make(SimDoctrine.Profile.ATTRITION)}))
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


const SCENARIOS := [
	# docs/09 §4
	"hold_the_line", "the_gap", "peer", "blind", "coalition", "overmatch",
	# docs/08 Theatres, plus the China/Russia relationship docs/08 describes
	"sino_russian_early", "sino_russian_late", "eastern_front",
	"east_china_sea", "central_europe", "north_atlantic", "korean_peninsula",
]
