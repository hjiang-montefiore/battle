class_name AppState
extends RefCounted
## What survives a scene change.
##
## The game is three scenes now -- title, setup, match -- and Godot frees the
## whole tree between them. A chosen faction cannot be carried in a node, so it
## is carried HERE, in static storage that outlives the tree. This file holds
## no logic beyond that and the options the player set; every decision about
## what a setup MEANS still belongs to SimMatchSetup.

const TITLE_SCENE := "res://scenes/title.tscn"
const SETUP_SCENE := "res://scenes/setup.tscn"
const MATCH_SCENE := "res://scenes/skirmish.tscn"
const EDITOR_SCENE := "res://scenes/map_editor.tscn"

const OPTIONS_PATH := "user://options.cfg"
const QUICKSAVE_PATH := "user://quicksave.json"
const SAVE_DIR := "user://saves"

# ── the handover ─────────────────────────────────────────────────────────────
## Set by the setup screen (or the scenario list), read once by skirmish.gd.
## Null means "nobody chose", and the match falls back to its own default --
## which is what keeps `godot res://scenes/skirmish.tscn -- --test` working
## exactly as it did before a menu existed.
static var pending_setup: SimMatchSetup = null
static var pending_arena: String = SimArena.SKIRMISH_VALLEY
## A save file to resume instead of deploying a fresh match.
static var pending_save: String = ""

## Where "Quit to title" came back from, so the title can put the highlight
## back on the entry the player last used.
static var last_title_entry: int = 0


static func take_setup() -> SimMatchSetup:
	var s := pending_setup
	pending_setup = null
	return s


static func take_save() -> String:
	var p := pending_save
	pending_save = ""
	return p


# ── epochs, as the player reads them ─────────────────────────────────────────
## docs/05. The simulation counts epochs 1-7 and knows nothing about years;
## a player thinks in decades, so the translation lives in the shell.
const EPOCH_NAME := {
	1: "Early Cold War", 2: "Missile Age", 3: "Precision Dawn", 4: "Digital",
	5: "Networked", 6: "Sensor Fusion", 7: "Contested",
}
const EPOCH_YEARS := {
	1: "1950-59", 2: "1960-69", 3: "1970-79", 4: "1980-89",
	5: "1990-2004", 6: "2005-15", 7: "2016-now",
}


static func epoch_label(e: int) -> String:
	var n: int = clampi(e, 1, 7)
	return "%d  %s  %s" % [n, EPOCH_NAME[n], EPOCH_YEARS[n]]


# ── saves ────────────────────────────────────────────────────────────────────
## Everything SimSave has written, newest first. The quicksave is listed
## alongside the named ones because from the player's side it is just the save
## they made most recently with one finger.
static func list_saves() -> Array:
	var out: Array = []
	if FileAccess.file_exists(QUICKSAVE_PATH):
		out.append({
			"path": QUICKSAVE_PATH, "label": "Quicksave",
			"when": FileAccess.get_modified_time(QUICKSAVE_PATH)})
	var dir := DirAccess.open(SAVE_DIR)
	if dir != null:
		for f in dir.get_files():
			if not f.ends_with(".json"):
				continue
			var p: String = SAVE_DIR + "/" + f
			out.append({"path": p, "label": f.get_basename().replace("_", " "),
				"when": FileAccess.get_modified_time(p)})
	out.sort_custom(func(a, b): return a["when"] > b["when"])
	return out


static func newest_save() -> String:
	var all := list_saves()
	return "" if all.is_empty() else str(all[0]["path"])


static func has_continue() -> bool:
	return newest_save() != ""


## A human-sized stamp for a save's row, e.g. "today 14:02".
static func when_label(unix: int) -> String:
	var t := Time.get_datetime_dict_from_unix_time(unix)
	var now := Time.get_datetime_dict_from_unix_time(int(Time.get_unix_time_from_system()))
	var clock := "%02d:%02d" % [t["hour"], t["minute"]]
	if t["year"] == now["year"] and t["month"] == now["month"] \
			and t["day"] == now["day"]:
		return "today " + clock
	return "%04d-%02d-%02d %s" % [t["year"], t["month"], t["day"], clock]


static func ensure_save_dir() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)


# ── options ──────────────────────────────────────────────────────────────────
## Deliberately short. An options screen that offers forty toggles nobody has
## wired up is worse than one that offers four that all work.
static var master_volume := 0.9
static var music_volume := 0.7
static var edge_pan := true
static var fullscreen := false
static var _options_loaded := false


static func load_options() -> void:
	if _options_loaded:
		return
	_options_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(OPTIONS_PATH) != OK:
		apply_options()
		return
	master_volume = float(cfg.get_value("audio", "master", master_volume))
	music_volume = float(cfg.get_value("audio", "music", music_volume))
	edge_pan = bool(cfg.get_value("input", "edge_pan", edge_pan))
	fullscreen = bool(cfg.get_value("video", "fullscreen", fullscreen))
	apply_options()


static func save_options() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("input", "edge_pan", edge_pan)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.save(OPTIONS_PATH)


const MUSIC_BUS := "Music"


## The score needs its own fader, and the only place a fader can live that
## every player picks up automatically is a BUS. music.gd cross-fades its three
## stems by writing volume_db on them every frame, so a music slider that wrote
## the same field would be overwritten within one frame -- this is not a
## refinement, it is the only version that works.
static func ensure_buses() -> int:
	var i := AudioServer.get_bus_index(MUSIC_BUS)
	if i >= 0:
		return i
	AudioServer.add_bus()
	i = AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, MUSIC_BUS)
	AudioServer.set_bus_send(i, "Master")
	return i


## Volumes are applied to BUSES rather than to each player, so a clip created
## after the slider moved is already at the right level -- the bug you get from
## walking a list of existing AudioStreamPlayers instead.
static func apply_options() -> void:
	AudioServer.set_bus_volume_db(0,
		-80.0 if master_volume <= 0.001 else linear_to_db(master_volume))
	AudioServer.set_bus_mute(0, master_volume <= 0.001)
	var mb := ensure_buses()
	AudioServer.set_bus_volume_db(mb,
		-80.0 if music_volume <= 0.001 else linear_to_db(music_volume))
	AudioServer.set_bus_mute(mb, music_volume <= 0.001)
	if DisplayServer.get_name() == "headless":
		return
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen \
		else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want:
		DisplayServer.window_set_mode(want)


# ── deep copy ────────────────────────────────────────────────────────────────
## A setup a match has been dealt from is no longer the setup that was chosen:
## SimDoctrine.adapt() rewrites an AI's doctrine while it plays, and a match
## restarted from that object would face an opponent who had already learned
## from the game you just lost. So every hand-off copies.
static func clone_setup(s: SimMatchSetup) -> SimMatchSetup:
	var out := SimMatchSetup.new()
	if s == null:
		return out
	out.name = s.name
	out.seed_value = s.seed_value
	for src in s.players:
		var p := src as SimPlayerSetup
		var q := SimPlayerSetup.new()
		q.name = p.name
		q.faction = p.faction
		q.is_human = p.is_human
		q.team = p.team
		q.start_epoch = p.start_epoch
		q.ceiling_epoch = p.ceiling_epoch
		q.advance_cost_mult = p.advance_cost_mult
		q.tech_floor = p.tech_floor.duplicate()
		q.tech_ceiling = p.tech_ceiling.duplicate()
		q.allowed_domains = p.allowed_domains
		q.starting_forces = p.starting_forces
		q.skill = p.skill
		q.resource_mult = p.resource_mult
		q.doctrine = SimDoctrine.make(
			p.doctrine.profile if p.doctrine != null
			else SimPlayerSetup.default_doctrine_for(p.faction))
		out.add(q)
	return out


## The match the title runs behind its menu: two AIs of different doctrines,
## already equipped, on the valley. Deliberately not the player's last setup --
## the backdrop should look the same every time the game is opened.
static func attract_setup() -> SimMatchSetup:
	var s := SimMatchSetup.new()
	s.name = "Attract"
	s.seed_value = 20260929
	s.add(SimPlayerSetup.new({
		"name": "Blue", "is_human": true, "team": 0,
		"faction": SimPlayerSetup.Faction.US,
		"start_epoch": 5, "ceiling_epoch": 6,
		"skill": SimSkill.Level.PROFESSIONAL,
		"starting_forces": SimPlayerSetup.ForcePreset.ARMY}))
	s.add(SimPlayerSetup.new({
		"name": "Red", "team": 1,
		"faction": SimPlayerSetup.Faction.RUSSIA,
		"start_epoch": 5, "ceiling_epoch": 6,
		"skill": SimSkill.Level.PROFESSIONAL,
		"starting_forces": SimPlayerSetup.ForcePreset.ARMY,
		"doctrine": SimDoctrine.make(SimDoctrine.Profile.DENIAL)}))
	return s


# ── authored maps ────────────────────────────────────────────────────────────
## Whatever is sitting in data/maps/. These are not a second kind of arena:
## "map:<name>" is already a legal arena key to SimArena.build(), so a map
## somebody sculpted in the editor reaches the setup screen with no new
## plumbing at all. Listed by reading the directory rather than by keeping an
## index, because an index is a thing that can be wrong.
static func authored_maps() -> Array:
	var out: Array = []
	var dir_path := ProjectSettings.globalize_path(SimMapFile.MAPS_DIR)
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	var names := dir.get_files()
	names.sort()
	for f in names:
		if not f.ends_with(".json"):
			continue
		var stem := f.get_basename()
		var mf := SimMapFile.load_map(dir_path.path_join(f))
		if mf == null:
			continue        # a refused file is already on the error log
		out.append({
			"key": SimMapFile.ARENA_PREFIX + stem,
			"name": mf.map_name,
			"author": mf.author,
			"path": dir_path.path_join(f)})
	return out
