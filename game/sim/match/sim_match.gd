class_name SimMatch
extends RefCounted
## A whole match, from a SimMatchSetup to a winner.
##
## Everything below this file already existed: a tick loop, a sensor model,
## armour, movement, an economy, an AI. What did not exist was a START and an
## END -- something that turns the config in setup/ into a world with two bases
## in it, keeps the participants' fates in order, and says when it is over.
## That is all this is. It owns no rules of its own beyond the victory
## condition (SimVictory) and the roster it deals out.
##
## PRESENTATION CALLS step(). Nothing here touches the scene tree; the skirmish
## scene is a viewer over this object and could be replaced by a headless
## harness without changing a line (test_match.gd does exactly that).
##
## ── ONE DECISION WORTH READING ───────────────────────────────────────────────
## SimEntities.faction is set to the player's TEAM, not to their nationality.
##
## The sensor solver keys track tables by faction, and docs/08's coalition
## mechanic is "allied players share a track table" -- which is only true if
## allies have the same faction id. SimPlayerSetup.faction stays what it always
## was, the NATIONAL identity that picks the equipment lineage and the art, and
## it is still what the roster is asked for. This split costs nothing today
## (the roster's faction axis is a no-op seam) and it is what makes a coalition
## fight correct rather than a friendly-fire generator.

enum Phase { SETUP, RUNNING, FINISHED }

## docs/04's economy needs a float to start from. Enough for a factory and a
## few vehicles, not enough to skip the opening.
const DEFAULT_START_CREDITS := 8000.0

var world: SimWorld
var setup: SimMatchSetup
var victory: SimVictory
var terrain: SimTerrain
var arena_key: String = SimArena.SKIRMISH_VALLEY

var human_player_id: int = -1
## When true the human's seat is played by an AI as well. See start().
var autopilot_human: bool = false
var phase: int = Phase.SETUP
## player id -> base centre, as Vector2(x, z). Indexed, never iterated.
var _base_of: Dictionary = {}
var events: PackedStringArray = PackedStringArray()


# ═══════════════════════════════════════════════════════════════════════════
# STARTING A MATCH
# ═══════════════════════════════════════════════════════════════════════════

## Build a world from a setup and put everybody on the map. Returns a match in
## Phase.RUNNING, or one still in Phase.SETUP if the setup does not validate --
## in which case problems() says why and step() does nothing.
## AUTOPILOT drives the human's seat with an AI director.
##
## Without it a headless match has one side that nobody plays: `_begin()` gives
## every participant an AI EXCEPT the human, which is correct when a person is
## at the keyboard and useless in a test. Measured before this existed, a peer
## match ran 30 simulated minutes in which the human's 22 units never received
## a single order, and the match could not end because the unplayed side was
## never threatened and never threatened anyone.
##
## It is not only a test affordance. It is the same thing a game needs for an
## AI takeover when a player drops, and for watching two doctrines fight.
static func start(match_setup: SimMatchSetup,
		arena := SimArena.SKIRMISH_VALLEY,
		autopilot_human := false) -> SimMatch:
	var m := SimMatch.new()
	m.setup = match_setup
	m.arena_key = arena
	m.autopilot_human = autopilot_human
	m._begin()
	return m


func problems() -> PackedStringArray:
	return setup.validate() if setup != null else PackedStringArray(["no setup"])


func _begin() -> void:
	if not problems().is_empty():
		return
	world = SimWorld.new(setup.seed_value)
	terrain = SimArena.build(arena_key, setup.seed_value)
	world.use_terrain(terrain)
	# The path planner builds its passability memo lazily on the first plan --
	# a fraction of a second on a full theatre, which lands as a stall the
	# first time anybody is ordered anywhere. prime_terrain() exists exactly so
	# a loading screen can pay that cost up front, and nothing was calling it.
	world.movement.prime_terrain(SimTypes.Category.GROUND)

	# The layers the spine declares but leaves for a match to install.
	world.arm_on_spawn = true
	world.fire_control = SimFireControl.new(
		world.entities, world.weapons, world.solver, world.economy)
	SimSortie.install(world)
	# Patrol and transport were test-proven but never INSTALLED -- their build
	# agents were cut off before this line, and a system that passes 50 tests
	# while absent from every real match is exactly the "library, not a
	# feature" failure this project keeps catching. All three install here or
	# none of the D/patrol/sortie gestures can reach them.
	SimPatrol.install(world)
	SimTransport.install(world)

	victory = SimVictory.new(world.entities, world.economy, world.damage)

	var bases := SimArena.base_positions(terrain, setup.players.size())
	# Ascending player id, always: the order players are created in decides the
	# order their AIs think in and the order the economy pays them.
	for pid in range(setup.players.size()):
		var p := setup.players[pid] as SimPlayerSetup
		var purse := world.economy.add_player_from_setup(
			pid, p, DEFAULT_START_CREDITS)
		# See the class comment: the SIM's faction is the coalition.
		purse.faction = p.team
		_base_of[pid] = bases[pid]
		victory.add_player(pid, p.team, p.name, p.is_human)
		if p.is_human:
			human_player_id = pid
			if autopilot_human:
				world.add_ai(pid, p.team, p)
		else:
			world.add_ai(pid, p.team, p)
		_deploy(pid, p, bases[pid])
	phase = Phase.RUNNING
	_note("%s begins on %s -- %d participants" % [
		setup.name, terrain.name, setup.players.size()])


func base_position(player_id: int) -> Vector2:
	return _base_of.get(player_id, Vector2.ZERO)


# ═══════════════════════════════════════════════════════════════════════════
# DEPLOYMENT
#
# The base layout is fixed and identical for every player, mirrored only by
# where the base sits on the map. An RTS that randomises the opening position
# of a refinery is randomising the opening build order, which is not tension.
# ═══════════════════════════════════════════════════════════════════════════

## role, dx, dz. Offsets are in metres from the base centre, in a frame rotated
## so that -z points at the middle of the map -- so the factories are always on
## the side facing the enemy and the derricks are always behind.
const BASE_LAYOUT := [
	["hq", 0.0, 0.0],
	["power_plant", -95.0, 60.0],
	["refinery", 95.0, 60.0],
	["oil_derrick", -170.0, 110.0],
	["oil_derrick", 170.0, 110.0],
	["light_factory", -95.0, -80.0],
	["heavy_factory", 95.0, -80.0],
	["barracks", 0.0, -150.0],
]

## Army composition per docs/09 §4 force preset. Each row is
## [role, count], applied in order, and any role the player's epoch or domain
## restrictions forbid is simply skipped -- an epoch-1 army gets no IFVs
## because the IFV does not exist yet, not because of a special case here.
const FORCES := {
	SimPlayerSetup.ForcePreset.NONE: [],
	SimPlayerSetup.ForcePreset.SKIRMISH: [
		["mbt", 2], ["apc", 1], ["recon_vehicle", 1],
	],
	SimPlayerSetup.ForcePreset.GARRISON: [
		["mbt", 2], ["atgm_carrier", 2], ["spaag", 1], ["search_radar", 1],
		["sph", 1], ["fuel_truck", 1],
	],
	SimPlayerSetup.ForcePreset.ARMY: [
		["mbt", 4], ["ifv", 2], ["apc", 1], ["atgm_carrier", 1], ["sph", 2],
		["spaag", 1], ["recon_vehicle", 1], ["search_radar", 1],
		["fuel_truck", 1],
	],
	SimPlayerSetup.ForcePreset.MASSED: [
		["mbt", 8], ["apc", 4], ["towed_artillery", 3], ["sph", 2],
		["spaag", 2], ["recon_vehicle", 1], ["fuel_truck", 1],
	],
}


## Roles that deploy FORWARD of the base rather than in the muster area.
##
## Every RTS opens with a scout, and this game needs one more than most: the
## map has a ridge down the middle, and two bases 9 km apart with 340 m of
## rock between them cannot see each other at all -- correctly, because
## docs/02 makes blocked line of sight an absolute, not a penalty. A force
## that starts entirely behind its own hill spends the opening minutes unable
## to find anybody. A picket out front is how a real formation answers that,
## and it is the same answer for the player and for the AI.
const PICKET_ROLES := ["recon_vehicle", "recon_team"]
const PICKET_RANGE_M := 1500.0


func _deploy(player_id: int, p: SimPlayerSetup, base: Vector2) -> void:
	# Face the middle of the map. atan2(x, z) is the sim's heading convention
	# (SimEntities.heading_toward uses exactly this), so the same number can be
	# handed straight to place_starting_unit.
	var facing := atan2(-base.x, -base.y)
	var placed_structures := 0
	for row in BASE_LAYOUT:
		var role := String(row[0])
		if not _role_allowed(p, role):
			continue
		var at := _rotate(base, float(row[1]), float(row[2]), facing)
		var i := world.economy.place_starting_unit(
			player_id, role, at.x, at.y, facing)
		if i >= 0:
			placed_structures += 1
			SimArsenal.arm(world.weapons, i, role, p.start_epoch)

	var army: Array = FORCES.get(p.starting_forces, [])
	var slot := 0
	var pickets := 0
	var placed_units := 0
	for row in army:
		var role := String(row[0])
		if not _role_allowed(p, role):
			continue
		for _k in range(int(row[1])):
			var at: Vector2
			if role in PICKET_ROLES:
				# Out in front, spread across the approach so the picket is a
				# screen rather than a single point of failure.
				at = _rotate(base, float(pickets) * 700.0 - 350.0,
					-PICKET_RANGE_M, facing)
				pickets += 1
			else:
				at = _rotate(base, _muster_x(slot), _muster_z(slot), facing)
				slot += 1
			var i := world.economy.place_starting_unit(
				player_id, role, at.x, at.y, facing)
			if i < 0:
				continue
			placed_units += 1
			SimArsenal.arm(world.weapons, i, role, p.start_epoch)
	_note("%s deploys %d structures and %d units at %.0f, %.0f" % [
		p.name, placed_structures, placed_units, base.x, base.y])


## Is this role legal for this player at all? Domain restrictions (docs/09's
## "army only") and epoch gating, asked BEFORE placement so a refusal is a skip
## rather than a -1 nobody looks at.
func _role_allowed(p: SimPlayerSetup, role: String) -> bool:
	var d := SimRoster.make(role, p.start_epoch, p.faction)
	if d == null:
		return false
	return p.allows(d.domain)


## A muster area in front of the base: rows of six, 34 m apart, starting 230 m
## out. Wide enough that nothing spawns inside anything and close enough that
## the whole force is on screen when the match opens.
static func _muster_x(slot: int) -> float:
	return float(slot % 6) * 34.0 - 85.0


static func _muster_z(slot: int) -> float:
	return -230.0 - float(slot / 6) * 34.0


## Rotate a base-local offset into world space around the base centre.
static func _rotate(base: Vector2, dx: float, dz: float,
		facing: float) -> Vector2:
	var s := sin(facing)
	var c := cos(facing)
	return Vector2(base.x + dx * c + dz * s, base.y - dx * s + dz * c)


# ═══════════════════════════════════════════════════════════════════════════
# RUNNING
# ═══════════════════════════════════════════════════════════════════════════

## Advance by wall-clock seconds. The world's own accumulator turns this into
## whole simulation ticks; the victory layer is stepped by the same dt so a
## capitulation clock measures simulated seconds and not frames.
func step(dt: float) -> void:
	if phase != Phase.RUNNING:
		return
	var before := world.elapsed_s
	world.step(dt)
	_after_ticks(world.elapsed_s - before)


## Exact ticks, for tests and for a headless harness that wants to run many
## times real speed.
func run_ticks(n: int) -> void:
	if phase != Phase.RUNNING:
		return
	world.run_ticks(n)
	_after_ticks(float(n) / SimWorld.SIM_HZ)


func _after_ticks(simulated_s: float) -> void:
	if simulated_s <= 0.0:
		return
	victory.step(simulated_s)
	# A player knocked out stops deciding. Ascending, because two AIs being
	# removed in an unstable order would be a desync in the replay.
	for pid in victory.newly_eliminated:
		world.remove_ai(pid)
	for e in victory.events:
		_note(e)
	victory.events = PackedStringArray()
	if victory.is_finished():
		phase = Phase.FINISHED
		_note(victory.headline())


func is_finished() -> bool:
	return phase == Phase.FINISHED


func outcome() -> int:
	return victory.outcome if victory != null else SimVictory.Outcome.UNDECIDED


func standing(player_id: int) -> SimVictory.Standing:
	return victory.standing(player_id) if victory != null else null


## One line a screen can put in front of the player when it is over.
func headline() -> String:
	return victory.headline() if victory != null else ""


## Seconds of simulated time since the match began.
func elapsed_s() -> float:
	return world.elapsed_s if world != null else 0.0


# ═══════════════════════════════════════════════════════════════════════════
# WHAT A VIEWER NEEDS
#
# Convenience over world.*, so the scene script never has to know which
# subsystem owns which fact.
# ═══════════════════════════════════════════════════════════════════════════

func credits(player_id: int) -> float:
	return world.economy.credits(player_id)


func epoch(player_id: int) -> int:
	return world.economy.epoch_of(player_id)


func purse(player_id: int) -> SimEconomy.Purse:
	return world.economy.purse(player_id)


## The player's own units, alive, ascending.
func own_units(player_id: int) -> PackedInt32Array:
	return world.entities.indices_of_owner(player_id)


## The player's PICTURE of the enemy: their coalition's track table, which is
## the only thing they are entitled to see. The viewer renders this and never
## the enemy entities, which is docs/02 made visible.
func picture_for(player_id: int) -> SimTrackTable:
	var team: int = 0
	if setup != null and player_id >= 0 and player_id < setup.players.size():
		team = (setup.players[player_id] as SimPlayerSetup).team
	return world.solver.table_for(team)


## Structures this player owns that can currently turn out units, ascending.
func production_structures(player_id: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in world.entities.indices_of_owner(player_id):
		if world.entities.is_structure[i] == 0:
			continue
		if not world.economy.is_operational(i):
			continue
		if world.economy.production_options(player_id, i).is_empty():
			continue
		out.append(i)
	return out


## Structure roles this player may place right now, ascending.
func buildable_structures(player_id: int) -> PackedStringArray:
	var out := PackedStringArray()
	for role in world.economy.buildable(player_id):
		if SimRoster.is_structure_role(role):
			out.append(role)
	return out


# ═══════════════════════════════════════════════════════════════════════════
# SAVE / LOAD (SimSave)
#
# The match dict carries what _begin() cannot rebuild from the world snapshot:
# the setup (players, doctrines, tech limits), the arena key, the seats, the
# bases and the victory standings. from_save() rebuilds the SHELL exactly the
# way _begin() does -- same wiring, same registration order -- except that it
# deploys nobody and builds no arena: the units come back through the entity
# snapshot and the terrain comes back bit-exact from the save, so the restored
# match cannot drift from the saved one even if SimArena's generators change.
# ═══════════════════════════════════════════════════════════════════════════

func to_dict() -> Dictionary:
	var players: Array = []
	for p in setup.players:
		var ps := p as SimPlayerSetup
		players.append({
			"p": SimSave.enc_props(ps, ["doctrine"]),
			"doctrine": SimSave.enc_props(ps.doctrine),
			"tech_floor": _tech_dict_out(ps.tech_floor),
			"tech_ceiling": _tech_dict_out(ps.tech_ceiling),
		})
	var bases := {}
	for pid in _base_of:
		bases[str(pid)] = SimSave.enc_v2(_base_of[pid])
	return {
		"setup": {
			"name": setup.name,
			"seed": str(setup.seed_value),
			"players": players,
		},
		"arena_key": arena_key,
		"autopilot_human": autopilot_human,
		"phase": phase,
		"bases": bases,
		"victory": victory.to_dict(),
	}


## Rebuild a match from a SimSave dictionary. SimSave.restore() is the caller;
## it has already checked the format version.
static func from_save(d: Dictionary) -> SimMatch:
	var md: Dictionary = d["match"]
	var wd: Dictionary = d["world"]
	var sd: Dictionary = md["setup"]

	var s := SimMatchSetup.new()
	s.name = String(sd["name"])
	s.seed_value = int(String(sd["seed"]))
	for pd in (sd["players"] as Array):
		var p := SimPlayerSetup.new({})
		SimSave.dec_props(p, pd["p"])
		SimSave.dec_props(p.doctrine, pd["doctrine"])
		p.tech_floor = _tech_dict_in(pd["tech_floor"])
		p.tech_ceiling = _tech_dict_in(pd["tech_ceiling"])
		s.add(p)

	var m := SimMatch.new()
	m.setup = s
	m.arena_key = String(md["arena_key"])
	m.autopilot_human = bool(md["autopilot_human"])

	# The shell, mirroring _begin() line for line -- minus arena generation and
	# minus deployment, both of which the snapshot supersedes.
	m.world = SimWorld.new(s.seed_value)
	m.terrain = SimSave.terrain_from_dict(wd["terrain"])
	m.world.use_terrain(m.terrain)
	m.world.movement.prime_terrain(SimTypes.Category.GROUND)
	m.world.arm_on_spawn = true
	m.world.fire_control = SimFireControl.new(
		m.world.entities, m.world.weapons, m.world.solver, m.world.economy)
	SimSortie.install(m.world)
	SimPatrol.install(m.world)
	SimTransport.install(m.world)
	m.victory = SimVictory.new(m.world.entities, m.world.economy, m.world.damage)
	for pid in range(s.players.size()):
		var p := s.players[pid] as SimPlayerSetup
		var purse := m.world.economy.add_player_from_setup(
			pid, p, DEFAULT_START_CREDITS)
		purse.faction = p.team
		m.victory.add_player(pid, p.team, p.name, p.is_human)
		if p.is_human:
			m.human_player_id = pid
			if m.autopilot_human:
				m.world.add_ai(pid, p.team, p)
		else:
			m.world.add_ai(pid, p.team, p)

	for k in (md["bases"] as Dictionary):
		m._base_of[int(String(k))] = SimSave.dec_v2(md["bases"][k])
	m.world.apply_dict(wd)
	m.victory.from_dict(md["victory"])
	m.phase = int(md["phase"])
	return m


## The per-ladder tech limits are String -> int dictionaries; the generic
## capture skips dictionaries by policy, so they ride explicitly. Values are
## coerced back to int because max_generation() has a typed int return.
static func _tech_dict_out(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[String(k)] = int(d[k])
	return out


static func _tech_dict_in(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[String(k)] = int(d[k])
	return out


func _note(line: String) -> void:
	if line == "":
		return
	events.append(line)
	if events.size() > 200:
		events.remove_at(0)


func describe() -> String:
	var lines := PackedStringArray()
	lines.append("%s -- %s" % [setup.name, terrain.name if terrain else "no map"])
	lines.append(victory.describe() if victory != null else "no victory layer")
	lines.append("shots %d  kills %d  %s" % [
		world.weapons.shots_fired, world.damage.kills,
		world.fire_control.describe() if world.fire_control else ""])
	return "\n".join(lines)
