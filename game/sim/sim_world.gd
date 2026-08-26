class_name SimWorld
extends RefCounted
## The simulation. docs/06.
##
## Three rates, because getting this wrong is the most likely performance
## failure: movement at the simulation rate, sensing on a slow tick, logistics
## and AI slower still. The sensor solve is O(sensors x targets) and is the
## single hottest thing in the game -- running it at 5 Hz instead of 30 Hz is a
## 6x saving no player can perceive, because a radar's real revisit time is
## seconds anyway. The slow tick is MORE realistic, not less.
##
## Nothing here touches the scene tree. Godot's job is to render this and submit
## commands to it; that is the whole contract.

const SIM_HZ := 20.0        ## docs/06 tick budget: simulation 20-30 Hz
const SENSOR_HZ := 5.0      ## docs/06 tick budget: sensor solve 5-10 Hz
## docs/06: "Logistics & AI, 1-2 Hz". Income, upkeep, fuel burn and production
## timers do not need to be resolved twenty times a second, and running them
## slowly is what leaves the frame budget for the sensor solve.
const ECONOMY_HZ := 1.0

var entities: SimEntities
var terrain: SimTerrain = null
var solver: SimSensorSolver
var munitions: SimMunitions
var rng: SimRng

# ── the missing systems, each with a slot in _sim_step() ─────────────────────
## All four are constructed as STUBS. Their step() functions are no-ops until
## the owning agent fills them in, and each reports is_implemented() so a
## half-built game describes itself accurately instead of silently doing
## nothing. Nothing below depends on any of them being real.
var movement: SimMovement
var damage: SimDamage
var economy: SimEconomy
## Slot 8c. Reload timers, the docs/02 §5 gate and the launch. Filled in by the
## combat subsystem at the two call sites the spine marked for it -- the
## ATTACK_TRACK order below, and step 8c in _combat_slot().
var weapons: SimWeaponCycle
## Slot 8b.5. Automatic target selection: which of MY OWN faction's tracks
## should each armed unit be shooting at? Null unless a match layer installs
## one, because the proving ground and the unit tests want units that only ever
## fire when explicitly ordered to. SimWeaponCycle answers "may I shoot at this
## track?"; this answers "which track?", and it answers it from the same
## per-faction table a human player is looking at.
var fire_control: SimFireControl = null
## When true, a unit created by the economy is given the weapons its role
## carries as it appears. Off by default: the spine's own tests spawn unarmed
## units on purpose, and turning this on would change what they measure.
var arm_on_spawn: bool = false
## player id -> SimAiDirector. Iterated through ai_player_ids(), which sorts,
## because docs/06 forbids relying on Dictionary order anywhere in the sim and
## two AIs deciding in an unstable order is a desync.
var ai: Dictionary = {}
## Orders in. The ONLY way anything outside the sim changes it -- the player's
## mouse and every AI push the same commands through the same queue.
var commands: SimCommandQueue

var tick: int = 0
var sensor_tick: int = 0
var elapsed_s: float = 0.0

var _sim_accum: float = 0.0
var _sensor_accum: float = 0.0
var _economy_accum: float = 0.0

## Set false to drive the sim by exact ticks in tests.
var use_accumulator: bool = true


func _init(seed_value: int = 12345) -> void:
	entities = SimEntities.new()
	solver = SimSensorSolver.new(entities)
	rng = SimRng.new(seed_value)
	munitions = SimMunitions.new(entities, solver, rng.fork(0x4D))
	commands = SimCommandQueue.new()
	# Each subsystem gets its OWN forked stream. docs/06 wants a replay to stay
	# stable when an unrelated system changes how often it rolls; that only
	# holds if the streams are independent, so forking here rather than sharing
	# one generator is load-bearing, not tidiness.
	movement = SimMovement.new(entities, terrain, rng.fork(0x4D56))
	damage = SimDamage.new(entities, rng.fork(0x0DA3))
	economy = SimEconomy.new(entities, rng.fork(0xEC0))
	weapons = SimWeaponCycle.new(entities, munitions, solver, rng.fork(0xC0B))
	# docs/04's "an aircraft that runs dry is destroyed" is the economy's rule
	# but the damage layer's authority -- nothing but SimDamage may kill. Wiring
	# them together here is what lets the economy apply it through its owner
	# rather than behind its back.
	economy.set_damage(damage)


## Load a theatre. Without one the world is a featureless plane, which is what
## the proving ground and most unit tests want.
func set_theatre(key: String) -> SimTerrain:
	return use_terrain(SimTheatre.build(key, rng.state()))


## Install a heightfield built anywhere -- a docs/08 theatre, a compact skirmish
## arena, or a test fixture -- and hand it to EVERY system that needs it.
##
## This exists because there were four of them and only two were being told.
## The sensor solver and the path planner were wired; the economy was not, so
## in a real match placement had terrain == null and silently skipped the water
## check, the map bounds and the build radius. One entry point is the fix.
func use_terrain(t: SimTerrain) -> SimTerrain:
	terrain = t
	solver.terrain = t
	movement.set_terrain(t)
	economy.set_terrain(t)
	return terrain


## Advance by wall-clock dt. Presentation calls this; it is the only entry point.
func step(dt: float) -> void:
	if not use_accumulator:
		_sim_step(1.0 / SIM_HZ)
		return
	_sim_accum += dt
	var sim_dt := 1.0 / SIM_HZ
	# Bound catch-up so a stall cannot spiral.
	var guard := 0
	while _sim_accum >= sim_dt and guard < 8:
		_sim_accum -= sim_dt
		_sim_step(sim_dt)
		guard += 1


## ═══════════════════════════════════════════════════════════════════════════
## THE TICK ORDER, AND WHY IT IS THIS ORDER
##
## Order matters enormously in an RTS, and getting it wrong produces bugs that
## look like physics problems rather than sequencing problems. Every adjacency
## below is deliberate; the justification is on the slot it constrains.
##
##   1  AI            decide from LAST tick's picture, emit commands only
##   2  COMMANDS      drain, validate ownership, turn orders into intent
##   3  ECONOMY       (1 Hz) income, upkeep, fuel, production, SPAWNS
##   4  MOVEMENT      plan and steer: write velocity and heading
##   5  INTEGRATE     the one place a position ever changes
##   6  SIGNATURES    age acoustic transients once per tick
##   7  MUNITIONS     rounds fly through the world as it is NOW
##   8  COMBAT        resolve what arrived, apply damage, then let units fire
##   9  SENSORS       (5 Hz) build the picture from the post-damage world
##
## The rule that makes this readable: each slot has exactly one writer, listed
## in the ownership table at the bottom of sim_entities.gd. A slot reads LAST
## tick's value of anything owned by a slot that runs after it, and THIS tick's
## value of anything owned by a slot that ran before it. That is a property you
## can reason about; an arbitrary order is not.
## ═══════════════════════════════════════════════════════════════════════════
func _sim_step(dt: float) -> void:
	tick += 1
	elapsed_s += dt

	# ── 1. AI ───────────────────────────────────────────────────────────────
	# FIRST, and deliberately: the AI decides from the picture the sensor solve
	# built at the END of the previous tick. That is not a compromise, it is the
	# correct model -- a commander acts on the picture he has, which is always
	# one revisit old. Running the AI after the solve inside the same tick would
	# give it a zero-latency reaction no human could match, and would quietly
	# undo the docs/09 §2 reaction-latency dial that difficulty is built on.
	#
	# It writes nothing. Its only output is commands, which slot 2 executes on
	# this same tick, so ordering it first costs it no responsiveness.
	_ai_slot(dt)

	# ── 2. COMMANDS ─────────────────────────────────────────────────────────
	# The player's mouse and the AI arrive through the same queue and are
	# validated the same way. Before movement, so an order given this tick is
	# acted on this tick; before economy, so a PRODUCE issued now is in the
	# queue when the economy tick looks at it.
	_command_slot()

	# ── 3. ECONOMY ──────────────────────────────────────────────────────────
	# 1 Hz (docs/06). Runs BEFORE anything iterates the entity arrays, because
	# it is the only slot allowed to CREATE entities. Growing the arrays while
	# a later loop is midway through range(count()) is the classic sim crash,
	# and confining spawns to one early slot makes it structurally impossible.
	# A unit that finishes production this tick is therefore fully present for
	# movement, munitions and sensing on the same tick -- never half-present.
	_economy_accum += dt
	var economy_dt := 1.0 / ECONOMY_HZ
	if _economy_accum >= economy_dt:
		_economy_slot(_economy_accum)
		_economy_accum = 0.0

	# ── 4. MOVEMENT ─────────────────────────────────────────────────────────
	# Plans paths and steers. It writes VELOCITY and HEADING and never position.
	# Splitting the decision from the integration keeps _integrate() the single
	# place a position changes, which is what makes the replay hash meaningful
	# and what stops two systems each nudging a unit half a step.
	_movement_slot(dt)

	# ── 5. INTEGRATE ────────────────────────────────────────────────────────
	_integrate(dt)

	# ── 6. SIGNATURES ───────────────────────────────────────────────────────
	# Age transients once per tick, before anything reads them, so a torpedo
	# seeker and the sensor solve see the same value on the same tick.
	entities.decay_transients(dt)

	# ── 7. MUNITIONS ────────────────────────────────────────────────────────
	# AFTER movement and integration. This is the ordering the whole slot list
	# exists for: a round measures its closest approach against ground truth, so
	# if it flew before the world moved, every round would be chasing last
	# tick's position. At 20 Hz against a 300 m/s aircraft that is 15 m of
	# systematic lead error built into every engagement in the game -- an error
	# that would read as "the missiles are inaccurate" and never as "the tick
	# order is wrong".
	#
	# Tier A runs at the full simulation rate: the guidance loop is
	# re-validated every tick, not just at launch (docs/10 §4, §9).
	munitions.step(dt)

	# ── 8. COMBAT ───────────────────────────────────────────────────────────
	# AFTER munitions, for the mirror-image reason: a projectile decides HIT,
	# NEAR_MISS or MISS inside its own step, so damage can only be resolved from
	# terminations that already exist. Resolving damage first would apply last
	# tick's impacts to this tick's world, and would let a unit that is about to
	# die still take its shot.
	_combat_slot(dt)

	# ── 9. SENSORS ──────────────────────────────────────────────────────────
	# LAST, at 5 Hz. The picture is built from the world AFTER damage: a unit
	# killed this tick must not contribute a fresh observation, and a unit that
	# started burning this tick should be seen burning on this tick's solve.
	# Sensing is an observation of the world, so it observes the finished one.
	_sensor_accum += dt
	var sensor_dt := 1.0 / SENSOR_HZ
	if _sensor_accum >= sensor_dt:
		solver.solve(_sensor_accum, sensor_tick)
		sensor_tick += 1
		_sensor_accum = 0.0


# ═══════════════════════════════════════════════════════════════════════════
# THE SLOTS. Each is a real call site with a stubbed subsystem behind it.
# Later agents fill in the subsystem, NOT this file -- which is what keeps four
# parallel agents out of one another's merge conflicts.
# ═══════════════════════════════════════════════════════════════════════════

## Slot 1. Every AI decides, in ascending player-id order.
func _ai_slot(dt: float) -> void:
	for pid in ai_player_ids():
		(ai[pid] as SimAiDirector).step(dt)


## Slot 2. Orders become intent.
##
## OWNERSHIP IS ENFORCED HERE, not trusted. A command whose issuer does not own
## the unit is rejected and counted. That is what makes docs/09 §1 structural on
## the output side: an AI physically cannot move somebody else's army, however
## its decision logic is written.
func _command_slot() -> void:
	for c in commands.drain():
		var cmd := c as SimCommandQueue.Command
		if not _command_is_authorised(cmd):
			commands.note_rejected()
			continue
		# An authorised order can still be IMPOSSIBLE -- a move order to a
		# mobility-killed tank, a build the player cannot afford. Those count as
		# rejected too, so the counters mean "orders that changed something"
		# rather than "orders that were allowed to try".
		if _execute_command(cmd):
			commands.note_executed()
		else:
			commands.note_rejected()


func _command_is_authorised(c: SimCommandQueue.Command) -> bool:
	# BUILD places a new structure and names no existing unit.
	if c.kind == SimTypes.OrderKind.BUILD:
		return c.issuer >= 0
	if c.unit < 0 or c.unit >= entities.count():
		return false
	if entities.alive[c.unit] == 0:
		return false
	return entities.owner[c.unit] == c.issuer


## Returns true when the order actually changed something.
func _execute_command(c: SimCommandQueue.Command) -> bool:
	match c.kind:
		SimTypes.OrderKind.MOVE:
			return movement.order_move(c.unit, c.x, c.z)
		SimTypes.OrderKind.STOP:
			movement.order_stop(c.unit)
			return true
		SimTypes.OrderKind.SET_EMCON:
			entities.emcon[c.unit] = c.value
			return true
		SimTypes.OrderKind.SET_MOVE_STATE:
			entities.move_state[c.unit] = c.value
			return true
		SimTypes.OrderKind.PRODUCE:
			return economy.queue_production(c.issuer, c.unit, c.key)
		SimTypes.OrderKind.BUILD:
			return economy.spawn_unit(c.issuer, c.key, c.x, c.z) >= 0
		SimTypes.OrderKind.ATTACK_TRACK:
			# Fire control. The track is assigned to the unit's weapons and slot
			# 8c runs the gate and the launch. Deliberately NOT resolved to an
			# entity here: docs/09 §1.3, a track is a hypothesis, not a pointer,
			# and the only place it becomes an index is inside the weapon cycle
			# where a projectile in flight genuinely needs one.
			if not weapons.engage(c.unit, c.track_id):
				return false
			# A hand-picked target is not second-guessed by automatic
			# retargeting until the track it names is gone.
			if fire_control != null:
				fire_control.note_manual_order(c.unit)
			return true
		SimTypes.OrderKind.CANCEL:
			return false
	return false


## Slot 3. docs/06's 1-2 Hz logistics tier. `dt` here is the elapsed seconds
## since this slot last ran, not the simulation tick -- fuel burn is per minute.
func _economy_slot(dt: float) -> void:
	economy.step(dt)
	if arm_on_spawn:
		_arm_new_units()


## Everything the economy created on this tick gets the weapons its ROLE
## carries. This is the seam the combat layer left open on purpose: it built a
## working weapon cycle and said "nothing arms units today". Whoever owns the
## roster does, and the roster is the economy's.
##
## spawned_this_step is an ascending PackedInt32Array rebuilt each economy tick,
## so this is deterministic and costs nothing on a tick that spawned nothing.
func _arm_new_units() -> void:
	for i in economy.spawned_this_step:
		var d := economy.def_of(i)
		if d == null:
			continue
		SimArsenal.arm(weapons, i, d.role, d.epoch)


## Slot 4. Path planning and steering.
func _movement_slot(dt: float) -> void:
	movement.step(dt)


## Slot 5 is _integrate(), below.

## Slot 8. Combat resolution, in two ordered halves.
func _combat_slot(dt: float) -> void:
	# 8a. What arrived. munitions.last_impacts holds exactly this tick's
	# terminations, snapshotted, with the facet already derived from impact
	# geometry (docs/10 §6). This is the seam that was missing: rounds flew,
	# guided and arrived, and nothing happened.
	for im in munitions.last_impacts:
		var impact := im as SimImpact
		if not impact.is_arrival():
			continue
		if not entities.is_alive(impact.target):
			continue
		var pen := SimArmor.penetration_at_range_mm(
			impact.penetration_mm, impact.damage_class, impact.range_m)
		damage.resolve_impact(impact.target, impact.facet, impact.damage_class,
			pen, impact.blast_fraction, impact.tandem)

	# 8b. Burn-down, crew recovery, wreck expiry.
	damage.step(dt)

	# 8b.5. WHICH track? Before the weapon cycle, so a target chosen on this
	# tick can be fired at on this tick; after damage, so a unit that just died
	# is never assigned one. It writes no entity state -- its only output is an
	# engagement on the weapon cycle, the same one an ATTACK_TRACK order sets.
	if fire_control != null:
		fire_control.step(dt)

	# 8c. The weapon cycle. Reload timers, SimWeaponGate checks and launches --
	# after damage, so a unit killed this tick does not get to fire, and after
	# munitions, so a round fired now begins its flight on the next tick with a
	# full dt rather than a partial one.
	weapons.step(dt)


## Register an AI opponent. Note what it is handed: a SimAiWorldView, and there
## is no overload that takes the entity store. docs/09 §1.3 -- "The AI module is
## constructed without a reference to the entity store at all, so the query it
## would need cannot be written."
func add_ai(player_id: int, faction_id: int, setup: SimPlayerSetup) -> SimAiDirector:
	var view := ai_view_for(player_id, faction_id, setup)
	var director := SimAiDirector.new(view, rng.fork(0xA100 + player_id))
	ai[player_id] = director
	return director


## Build the whitelist bundle for one player. Public so a test can construct one
## and try to break out of it.
func ai_view_for(player_id: int, faction_id: int,
		setup: SimPlayerSetup = null) -> SimAiWorldView:
	return SimAiWorldView.new(
		SimOwnForcesView.new(entities, player_id, faction_id),
		solver.table_for(faction_id),
		terrain,
		economy,
		commands,
		setup,
		player_id)


## An eliminated player stops thinking. Called by the match layer when a player
## is knocked out; without it a defeated AI keeps issuing orders to an army that
## no longer exists and keeps paying for the decision loop every tick.
func remove_ai(player_id: int) -> bool:
	return ai.erase(player_id)


## Ascending, always. docs/06: never iterate an unordered container where order
## affects outcome, and the order two AIs issue commands in absolutely does.
func ai_player_ids() -> Array:
	var ids: Array = ai.keys()
	ids.sort()
	return ids


## Honest status of the four systems this spine only declared. A subsystem that
## half-works and is described as working costs more than one described
## accurately, so the world reports what is actually wired.
func subsystem_status() -> Dictionary:
	return {
		"movement": movement.is_implemented(),
		"damage": damage.is_implemented(),
		"economy": economy.is_implemented(),
		"ai": ai_player_ids().any(func(p): return (ai[p] as SimAiDirector).is_implemented()),
	}


## Hand-written movement. docs/06 forbids Godot physics for units: RigidBody3D
## and CharacterBody3D are neither deterministic nor suited to hundreds of units.
func _integrate(dt: float) -> void:
	for i in range(entities.count()):
		if entities.alive[i] == 0:
			continue
		entities.pos_x[i] += entities.vel_x[i] * dt
		entities.pos_y[i] += entities.vel_y[i] * dt
		entities.pos_z[i] += entities.vel_z[i] * dt


## Run exactly n simulation ticks, ignoring the accumulator. For tests and for
## the headless AI-vs-AI harness, which needs to run many times real speed.
func run_ticks(n: int) -> void:
	var sim_dt := 1.0 / SIM_HZ
	for _i in range(n):
		_sim_step(sim_dt)


## The AI's entire interface (docs/06, docs/09 §1). It is handed this and never
## the entity store, so it cannot read ground truth even by accident.
func track_table_for(faction_id: int) -> SimTrackTable:
	return solver.table_for(faction_id)


## Hash of sim state for replay verification and desync detection. docs/06
## milestone 1: "Hash the sim state every N ticks; a replay that diverges tells
## you exactly which tick broke."
func state_hash() -> int:
	var buf := PackedFloat64Array()
	for i in range(entities.count()):
		buf.append(entities.pos_x[i])
		buf.append(entities.pos_y[i])
		buf.append(entities.pos_z[i])
		buf.append(entities.vel_x[i])
		buf.append(entities.vel_z[i])
		buf.append(float(entities.alive[i]))
		buf.append(float(entities.emcon[i]))
		# The spine's state is part of the sim, so it is part of the hash. A
		# desync in health, facing, orders or fuel is still a desync, and the
		# whole value of hashing is that it catches the one you did not predict.
		buf.append(snappedf(entities.structure[i], 0.0001))
		buf.append(float(entities.components[i]))
		buf.append(snappedf(entities.heading_rad[i], 0.000001))
		buf.append(snappedf(entities.speed_ms[i], 0.0001))
		buf.append(float(entities.move_state[i]))
		buf.append(float(entities.owner[i]))
		buf.append(float(entities.has_dest[i]))
		buf.append(snappedf(entities.dest_x[i], 0.001))
		buf.append(snappedf(entities.dest_z[i], 0.001))
		buf.append(float(entities.path_cursor[i]))
		buf.append(float(entities.path_len[i]))
		buf.append(snappedf(entities.fuel[i], 0.001))
	# Track state matters too -- a desync in the picture is still a desync.
	for f in solver.faction_ids():
		var table: SimTrackTable = solver.tables[f]
		for id in table.track_ids():
			var t := table.get_track(id)
			buf.append(float(t.quality))
			buf.append(float(t.classification))
			buf.append(snappedf(t.age_s, 0.0001))
	# PackedByteArray has no .hash() in Godot 4; the global hash() takes the
	# array directly and is stable for a given byte sequence.
	return hash(buf)


func describe() -> String:
	var lines := PackedStringArray()
	lines.append("tick %d  (%.2f s)  sensor solves %d" % [tick, elapsed_s, sensor_tick])
	var st := subsystem_status()
	var missing := PackedStringArray()
	for k in ["movement", "damage", "economy", "ai"]:
		if not st[k]:
			missing.append(k)
	if not missing.is_empty():
		lines.append("NOT IMPLEMENTED: " + ", ".join(missing))
	for f in solver.faction_ids():
		lines.append((solver.tables[f] as SimTrackTable).describe())
	return "\n".join(lines)
