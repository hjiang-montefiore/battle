extends Node3D
## THE TITLE. The way into the game, and -- until now -- the way that did not
## exist: the executable booted straight into a match and Esc did nothing, so
## a player could neither choose a fight nor leave one.
##
## Two decisions are worth stating because they are the ones the screen is
## built around.
##
## KEYBOARD FIRST. Arrows move, Enter confirms, Esc backs out. The mouse works,
## but it feeds the SAME highlight rather than running beside it, so there is
## never a frame where the pointer and the keyboard disagree about what Enter
## would do. See MenuList.
##
## A LIVE MATCH BEHIND THE MENU, not a picture of one. skirmish.tscn is
## instanced in attract mode -- both seats played by the AI, no HUD, camera
## drifting over the fighting -- and blurred. It costs a real match's worth of
## simulation, and it buys the one thing a still image cannot: the backdrop is
## the actual game, at the actual scale, so it cannot quietly stop being true.
##
## CONTINUE DISAPPEARS rather than greying out. Everything else that cannot be
## chosen is shown and says why -- Campaign is listed, disabled and honest --
## because a hidden entry teaches the player nothing. Continue is the exception
## because "nothing to continue" is the state of a game that has never been
## played, and a first-time player should not open the game to a dead row.

const ATTRACT_SCENE := preload("res://scenes/skirmish.tscn")
const MENU_W := 560.0

var _attract: Node3D
var _list: MenuList
var _blurb: Label
var _page := "root"
var _sub: VBoxContainer
var _scenario_keys: PackedStringArray = PackedStringArray()
var _save_paths: Array = []
var _headless := false


func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"
	AppState.load_options()
	AppState.pending_save = ""
	AppState.pending_setup = null
	_start_attract()
	_start_music()
	_build_ui()
	_show_root()
	var argv := OS.get_cmdline_user_args()
	if "--shot" in argv and not _headless:
		# `--shot --page scenarios` renders a sub-page instead of the root, so
		# every screen in the shell can be reviewed without a human clicking
		# through to it.
		var i := argv.find("--page")
		if i >= 0 and i + 1 < argv.size():
			match argv[i + 1]:
				"scenarios": _show_scenarios()
				"load": _show_load()
				"options": _show_options()
				"manual": _open_manual(SimPlayerSetup.Faction.US, 4)
				# A national page, which is where the researched data lives.
				"manual-de":
					_open_manual(SimPlayerSetup.Faction.GERMANY, 4)
					_manual.call("open_at", SimPlayerSetup.Faction.GERMANY, 4, 3)
		_capture(argv[i + 1] if i >= 0 and i + 1 < argv.size() else "root")


## The backdrop. It is the match scene, told to play itself.
func _start_attract() -> void:
	if _headless:
		return
	var s := ATTRACT_SCENE.instantiate()
	s.set("attract_mode", true)
	AppState.pending_setup = AppState.attract_setup()
	AppState.pending_arena = SimArena.SKIRMISH_VALLEY
	add_child(s)
	_attract = s


func _start_music() -> void:
	if _headless:
		return
	var m := preload("res://scripts/music.gd").new()
	add_child(m)
	m.menu_mode()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)

	# A live battle at full contrast fights the text in front of it; blurred,
	# it reads as depth instead of as competition.
	# Blurred enough that the text wins, not so much that the backdrop stops
	# being recognisable as armour crossing ground -- at LOD 3 it was mush, and
	# a backdrop nobody can identify is no better than a gradient.
	layer.add_child(MenuUI.scrim(0.35) if _headless else MenuUI.blur_rect(1.7, 0.30))
	# ...and a wash under the menu column itself, so the contrast of the words
	# does not depend on whether the camera happens to be over dark woodland or
	# a sunlit slope at the moment somebody reads them.
	layer.add_child(MenuUI.left_scrim(0.62, 0.90))

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 86)
	margin.add_theme_constant_override("margin_top", 64)
	margin.add_theme_constant_override("margin_right", 86)
	margin.add_theme_constant_override("margin_bottom", 48)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)

	var title := MenuUI.heading("BATTLE", 64)
	col.add_child(title)
	var tag := MenuUI.body(
		"Sensor-first real-time strategy.  1950 to now, seven epochs.", 15)
	col.add_child(tag)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 26)
	col.add_child(spacer)

	# The menu column is 560 px wide, not the whole screen: a row's note --
	# which save Continue would open, how many scenarios there are -- belongs
	# beside its entry, and stretched across a 1600 px window it ends up a
	# quarter of a metre from the word it describes.
	_sub = VBoxContainer.new()
	_sub.add_theme_constant_override("separation", 4)
	_sub.custom_minimum_size = Vector2(MENU_W, 0)
	_sub.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(_sub)

	_blurb = MenuUI.para("", 13, MenuUI.COL_DIM, MENU_W)
	_blurb.custom_minimum_size = Vector2(MENU_W, 52)
	_blurb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(_blurb)

	var tail := Control.new()
	tail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(tail)

	var foot := MenuUI.body(
		"arrows move  ·  Enter confirms  ·  Esc backs out", 12)
	col.add_child(foot)


func _clear_sub() -> void:
	for c in _sub.get_children():
		_sub.remove_child(c)
		c.queue_free()
	_list = null


func _new_list() -> MenuList:
	var l := MenuList.new()
	l.custom_minimum_size = Vector2(MENU_W, 0)
	l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_sub.add_child(l)
	_list = l
	return l


# ── the root menu ────────────────────────────────────────────────────────────

const BLURB := {
	"continue": "Pick up the most recent save where it was left.",
	"skirmish": "Choose the theatre, the factions, the skill and the era band, then fight it.",
	"scenarios": "Thirteen authored fights from docs/09 and the theatre table -- each one a different question.",
	"campaign": "Not built. The scenario list is where the authored fights live for now.",
	"load": "Every save on this machine, newest first.",
	"editor": "Sculpt a map. Anything saved into data/maps/ becomes a theatre the skirmish screen can pick.",
	"options": "Volume, edge scrolling, fullscreen.",
	"quit": "Leave the game.",
}


func _show_root() -> void:
	_page = "root"
	_clear_sub()
	var l := _new_list()
	# CONTINUE IS ABSENT, not greyed, when there is nothing to continue.
	if AppState.has_continue():
		var newest := AppState.list_saves()[0] as Dictionary
		l.add_entry("continue", "Continue", true,
			"%s  ·  %s" % [newest["label"],
				AppState.when_label(int(newest["when"]))])
	l.add_entry("skirmish", "Skirmish")
	l.add_entry("scenarios", "Scenarios", true,
		"%d authored" % SimMatchSetup.SCENARIOS.size())
	# Shown, disabled, and honest about why -- the opposite of Continue, and
	# deliberately so: this one is a promise the game has not kept yet, and
	# hiding it would be hiding the shape of the game.
	l.add_entry("campaign", "Campaign", false, "not built yet")
	l.add_entry("load", "Load", AppState.has_continue(),
		"" if AppState.has_continue() else "no saves yet")
	l.add_entry("editor", "Map Editor")
	# The field manual. Reachable from the title AND from a paused match,
	# because the question "what does this thing actually do" arrives in both
	# places and a player should not have to quit to answer it.
	l.add_entry("manual", "Field Manual", true, "every unit, every nation")
	l.add_entry("options", "Options")
	l.add_entry("quit", "Quit")
	l.chosen.connect(_root_chosen)
	l.highlighted.connect(func(id: String): _blurb.text = BLURB.get(id, ""))
	# Esc at the top of the tree has nowhere to back out TO, so it moves the
	# highlight to Quit rather than quitting: one more Enter leaves, and a
	# mis-pressed key never closes the game.
	l.cancelled.connect(func(): l.highlight("quit"))
	l.highlight_index(mini(AppState.last_title_entry, l.count() - 1))
	_blurb.text = BLURB.get(l.selected_id(), "")


const ManualScript := preload("res://scripts/manual.gd")
var _manual: Control
var _manual_layer: CanvasLayer


## Opens the field manual over whatever is on screen and takes it away again.
## It is a READER: it is added, it is freed, and nothing underneath is touched
## -- no pause flag, no menu state, no simulation call. That is the property
## that lets the same screen open from a live match.
func _open_manual(f: int, e: int) -> void:
	if _manual != null:
		return
	# ITS OWN CANVAS LAYER, high. Added as a plain child it drew UNDERNEATH the
	# menu that opened it -- visible in the first render as a ghost of the word
	# FIELD MANUAL behind BATTLE. Both scenes put their HUD on a CanvasLayer, so
	# a manual that is merely a later sibling is still beneath them.
	_manual_layer = CanvasLayer.new()
	_manual_layer.layer = 100
	add_child(_manual_layer)
	_manual = ManualScript.new()
	_manual_layer.add_child(_manual)
	_manual.call("open_at", f, e)
	_manual.connect("closed", _close_manual)
	_manual.grab_focus()


func _close_manual() -> void:
	if _manual_layer != null:
		_manual_layer.queue_free()
		_manual_layer = null
	_manual = null


func _root_chosen(id: String) -> void:
	AppState.last_title_entry = _list.highlighted_index()
	match id:
		"continue":
			_resume(AppState.newest_save())
		"skirmish":
			get_tree().change_scene_to_file(AppState.SETUP_SCENE)
		"scenarios":
			_show_scenarios()
		"load":
			_show_load()
		"editor":
			get_tree().change_scene_to_file(AppState.EDITOR_SCENE)
		"manual":
			_open_manual(SimPlayerSetup.Faction.US, 4)
		"options":
			_show_options()
		"quit":
			get_tree().quit()


# ── scenarios ────────────────────────────────────────────────────────────────

## Which ground an authored fight is fought on. Several scenario keys ARE
## theatre keys, and the ones that are not still name a place; North Atlantic
## in particular restricts both sides to navy and air, so putting it on an
## inland valley would produce a match neither side could play.
const SCENARIO_ARENA := {
	"korean_peninsula": SimTheatre.KOREAN_PENINSULA,
	"central_europe": SimTheatre.CENTRAL_EUROPE,
	"north_atlantic": SimTheatre.NORTH_ATLANTIC,
	"east_china_sea": SimTheatre.TAIWAN_STRAIT,
	"hold_the_line": SimTheatre.TAIWAN_STRAIT,
	"sino_russian_early": SimArena.OPEN_STEPPE,
	"sino_russian_late": SimArena.OPEN_STEPPE,
	"eastern_front": SimArena.OPEN_STEPPE,
	"the_gap": SimArena.SKIRMISH_VALLEY,
	"peer": SimArena.SKIRMISH_VALLEY,
	"blind": SimArena.SKIRMISH_VALLEY,
	"coalition": SimArena.OPEN_STEPPE,
	"overmatch": SimArena.SKIRMISH_VALLEY,
}


static func arena_for_scenario(key: String) -> String:
	return SCENARIO_ARENA.get(key, SimArena.SKIRMISH_VALLEY)


func _show_scenarios() -> void:
	_page = "scenarios"
	_clear_sub()
	var l := _new_list()
	_scenario_keys = PackedStringArray()
	for key in SimMatchSetup.SCENARIOS:
		var m := SimMatchSetup.scenario(key)
		if m.players.is_empty():
			continue
		_scenario_keys.append(key)
		l.add_entry(key, m.name, true, _scenario_note(m))
	l.add_entry("back", "Back")
	l.chosen.connect(func(id: String):
		if id == "back":
			_show_root()
		else:
			_start_scenario(id))
	l.highlighted.connect(func(id: String):
		_blurb.text = "" if id == "back" else _scenario_blurb(id))
	l.cancelled.connect(_show_root)
	_blurb.text = _scenario_blurb(l.selected_id())


func _scenario_note(m: SimMatchSetup) -> String:
	var you := m.humans()
	var epochs := "epoch ?"
	if not you.is_empty():
		var p := you[0] as SimPlayerSetup
		epochs = "epoch %d-%d" % [p.start_epoch, p.ceiling_epoch]
	return "%d players  ·  %s" % [m.players.size(), epochs]


func _scenario_blurb(key: String) -> String:
	if key == "" or key == "back":
		return ""
	var m := SimMatchSetup.scenario(key)
	var parts := PackedStringArray()
	for p in m.players:
		var ps := p as SimPlayerSetup
		parts.append("%s %s" % [SimPlayerSetup._faction_name(ps.faction),
			"(you)" if ps.is_human else SimSkill.name_of(ps.skill)])
	var arena := arena_for_scenario(key)
	var ground := SimArena.description(arena)
	if ground == "":
		ground = SimTheatre.stresses(arena)
	return "%s  --  %s\n%s" % [m.name, ", ".join(parts), ground]


func _start_scenario(key: String) -> void:
	var m := SimMatchSetup.scenario(key)
	if m.players.is_empty():
		_blurb.text = "that scenario is not authored"
		return
	AppState.pending_setup = m
	AppState.pending_arena = arena_for_scenario(key)
	get_tree().change_scene_to_file(AppState.MATCH_SCENE)


# ── load ─────────────────────────────────────────────────────────────────────

func _show_load() -> void:
	_page = "load"
	_clear_sub()
	var l := _new_list()
	_save_paths = []
	var saves := AppState.list_saves()
	for i in range(saves.size()):
		var row: Dictionary = saves[i]
		_save_paths.append(str(row["path"]))
		l.add_entry("slot%d" % i, str(row["label"]), true,
			AppState.when_label(int(row["when"])))
	if saves.is_empty():
		l.add_entry("none", "nothing saved yet", false)
	l.add_entry("back", "Back")
	l.chosen.connect(func(id: String):
		if id == "back":
			_show_root()
		elif id.begins_with("slot"):
			_resume(str(_save_paths[int(id.substr(4))])))
	l.cancelled.connect(_show_root)
	_blurb.text = "A save restores the whole simulation -- every unit, every track, every RNG stream."


func _resume(path: String) -> void:
	if path == "" or not FileAccess.file_exists(path):
		_blurb.text = "that save is gone"
		_show_root()
		return
	AppState.pending_save = path
	get_tree().change_scene_to_file(AppState.MATCH_SCENE)


# ── options ──────────────────────────────────────────────────────────────────

func _show_options() -> void:
	_page = "options"
	_clear_sub()
	var panel := OptionsPanel.new()
	panel.closed.connect(_show_root)
	_sub.add_child(panel)
	_blurb.text = ""


func _unhandled_key_input(ev: InputEvent) -> void:
	# Only the options page has no MenuList of its own to answer Esc.
	var k := ev as InputEventKey
	if k == null or not k.pressed or k.echo or _page != "options":
		return
	if k.keycode == KEY_ESCAPE:
		_show_root()
		get_viewport().set_input_as_handled()


func _capture(page := "root") -> void:
	# Several frames, not one: the blur reads the BACK BUFFER, so the first
	# frame it is drawn on has nothing behind it yet and the menu would be
	# captured over black.
	for _i in range(6):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var out := ProjectSettings.globalize_path(
		"res://../art/renders/game_title.png" if page == "root"
		else "res://../art/renders/game_title_%s.png" % page)
	print("[title] ", out, "  err=", img.save_png(out),
		"  ", img.get_width(), "x", img.get_height())
	get_tree().quit()
