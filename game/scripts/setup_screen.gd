extends Control
## SKIRMISH SETUP. The screen where the game's range lives.
##
## Everything the simulation can express about a match is a property of
## SimMatchSetup and SimPlayerSetup, and almost none of it fits behind an
## "Easy / Normal / Hard" dropdown. Three things in particular are why this
## screen is a table rather than three buttons:
##
##   SKILL IS A LADDER, NOT A DIFFICULTY. SimSkill's eight tiers are real
##   behaviour -- reaction delay, the track quality the AI insists on before it
##   commits, emission discipline, how many axes it can coordinate. Recruit and
##   Warlord get exactly the same information (docs/09 §1 forbids anything
##   else); what changes is what they do with it. Collapsing that into three
##   words would throw away the game.
##
##   DOCTRINE IS THE OPPONENT'S PERSONALITY. SimDoctrine already ships names
##   and one-line descriptions, so they are shown under the row rather than
##   rewritten here.
##
##   THE ERA IS A BAND, NOT A NUMBER. start_epoch and ceiling_epoch are
##   independent, which is what makes "modern but tiny" and "obsolete but
##   enormous" different matches. Hence one timeline with two handles.
##
## VALIDATION IS CONTINUOUS. SimMatchSetup.validate() already returns sentences
## a person can read; they are shown as they become true, not held back until
## Start is pressed. And Start is never greyed out -- pressing it when the
## setup is broken says WHY, because a dead button teaches nothing and a
## refusal with a reason teaches the rule.

const MAX_PLAYERS := 6

var _rows: Array = []              ## Array[Dictionary], one per seat
var _rows_box: VBoxContainer
var _era: EraSlider
var _arena_list: MenuList
var _arena_keys: PackedStringArray = PackedStringArray()
var _arena_note: Label
var _problems: Label
var _summary: Label
var _start_btn: Button
var _seed_edit: LineEdit
var _arena := SimArena.SKIRMISH_VALLEY
var _headless := false


func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"
	AppState.load_options()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	_default_rows()
	_revalidate()
	if "--shot" in OS.get_cmdline_user_args() and not _headless:
		_capture()


func _capture() -> void:
	for _i in range(4):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var out := ProjectSettings.globalize_path("res://../art/renders/game_setup.png")
	print("[setup] ", out, "  err=", img.save_png(out),
		"  ", img.get_width(), "x", img.get_height())
	get_tree().quit()


# ═══════════════════════════════════════════════════════════════════════════
# LAYOUT
# ═══════════════════════════════════════════════════════════════════════════

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.035, 0.048, 0.060)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	col.add_child(head)
	head.add_child(MenuUI.heading("SKIRMISH", 34))
	var sub := MenuUI.body(
		"Every axis below is one the simulation actually reads.", 13)
	sub.size_flags_vertical = Control.SIZE_SHRINK_END
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sub)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)

	body.add_child(_build_theatre_pane())
	body.add_child(_build_right_pane())

	col.add_child(_build_footer())


func _build_theatre_pane() -> Control:
	var panel := MenuUI.panel()
	panel.custom_minimum_size = Vector2(380, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	col.add_child(MenuUI.heading("THEATRE", 18))

	_arena_list = MenuList.new()
	_arena_list.set_active(false)     # the table owns the keyboard here
	col.add_child(_arena_list)
	for key in SimArena.ALL:
		_arena_keys.append(key)
		_arena_list.add_entry(key, _arena_title(key), true, "generated")
	# AUTHORED MAPS. data/maps/ is not a second kind of arena: "map:<name>" is
	# already a legal arena key to SimArena.build(), so a map somebody sculpted
	# in the editor appears here beside the generated ones and needs no special
	# handling anywhere below this line.
	for m in AppState.authored_maps():
		_arena_keys.append(str(m["key"]))
		_arena_list.add_entry(str(m["key"]), str(m["name"]), true, "authored")
	_arena_list.chosen.connect(_choose_arena)
	_arena_list.highlighted.connect(_choose_arena)

	_arena_note = MenuUI.para("", 12, MenuUI.COL_DIM, 330.0)
	_arena_note.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_arena_note)
	_choose_arena(SimArena.SKIRMISH_VALLEY)

	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	seed_row.add_child(MenuUI.body("Seed", 13, MenuUI.COL_TEXT))
	_seed_edit = LineEdit.new()
	_seed_edit.text = str(20260826)
	_seed_edit.custom_minimum_size = Vector2(130, 26)
	_seed_edit.add_theme_font_size_override("font_size", 13)
	seed_row.add_child(_seed_edit)
	var reroll := MenuUI.button("Reroll", 12)
	reroll.pressed.connect(func():
		_seed_edit.text = str(randi() % 90000000 + 1000000))
	seed_row.add_child(reroll)
	col.add_child(seed_row)
	col.add_child(MenuUI.para(
		"The same seed on the same theatre deals the same match. "
		+ "Restart in the pause menu replays exactly this one.", 11,
		MenuUI.COL_DIM, 330.0))
	return panel


func _build_right_pane() -> Control:
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var era_panel := MenuUI.panel()
	var era_col := VBoxContainer.new()
	era_col.add_theme_constant_override("separation", 4)
	era_panel.add_child(era_col)
	era_col.add_child(MenuUI.heading("ERA", 18))
	era_col.add_child(MenuUI.para(
		"Where every side starts, and how far it may climb. "
		+ "A row's Advanced panel can override its own band.", 12,
		MenuUI.COL_DIM, 560.0))
	_era = EraSlider.new()
	_era.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_era.changed.connect(_era_changed)
	era_col.add_child(_era)
	outer.add_child(era_panel)

	var players := MenuUI.panel()
	players.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var pcol := VBoxContainer.new()
	pcol.add_theme_constant_override("separation", 6)
	players.add_child(pcol)

	var ph := HBoxContainer.new()
	ph.add_theme_constant_override("separation", 12)
	ph.add_child(MenuUI.heading("PLAYERS", 18))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ph.add_child(spacer)
	var add := MenuUI.button("Add AI", 12)
	add.pressed.connect(func(): _add_row(false))
	ph.add_child(add)
	var drop := MenuUI.button("Remove last", 12)
	drop.pressed.connect(_remove_last)
	ph.add_child(drop)
	pcol.add_child(ph)
	pcol.add_child(_column_headings())

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pcol.add_child(scroll)
	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("separation", 4)
	scroll.add_child(_rows_box)
	outer.add_child(players)
	return outer


func _column_headings() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for spec in [["SEAT", 64], ["FACTION", 132], ["SKILL", 138],
			["DOCTRINE", 168], ["TEAM", 58], ["", 92]]:
		var l := MenuUI.body(str(spec[0]), 11, MenuUI.COL_DIM)
		l.custom_minimum_size = Vector2(float(spec[1]), 0)
		row.add_child(l)
	return row


func _build_footer() -> Control:
	var panel := MenuUI.panel(MenuUI.COL_PLATE, MenuUI.COL_PLATE_EDGE)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)

	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 2)
	_summary = MenuUI.body("", 13, MenuUI.COL_TEXT)
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary.clip_text = true
	texts.add_child(_summary)
	_problems = MenuUI.para("", 12, MenuUI.COL_BAD, 600.0)
	texts.add_child(_problems)
	row.add_child(texts)

	var back := MenuUI.button("Back  (Esc)", 14)
	back.custom_minimum_size = Vector2(130, 36)
	back.pressed.connect(_back)
	row.add_child(back)

	_start_btn = MenuUI.button("START  (Enter)", 16)
	_start_btn.custom_minimum_size = Vector2(180, 36)
	_start_btn.pressed.connect(_start)
	row.add_child(_start_btn)
	return panel


# ═══════════════════════════════════════════════════════════════════════════
# THE TABLE
# ═══════════════════════════════════════════════════════════════════════════

func _default_rows() -> void:
	_add_row(true)
	_add_row(false)


func _add_row(human: bool) -> void:
	if _rows.size() >= MAX_PLAYERS:
		_problems.text = "at most %d seats" % MAX_PLAYERS
		return
	var seat := _rows.size()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_child(box)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)

	var seat_label := MenuUI.body("You" if human else "AI %d" % (seat + 1), 14,
		MenuUI.COL_ACCENT if human else MenuUI.COL_TEXT)
	seat_label.custom_minimum_size = Vector2(64, 30)
	seat_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(seat_label)

	var faction := MenuUI.option()
	faction.custom_minimum_size = Vector2(132, 30)
	for f in range(10):
		faction.add_item(SimPlayerSetup._faction_name(f), f)
	faction.select(SimPlayerSetup.Faction.US if human
		else SimPlayerSetup.Faction.RUSSIA)
	row.add_child(faction)

	var skill := MenuUI.option()
	skill.custom_minimum_size = Vector2(138, 30)
	for lv in range(SimSkill.LEVEL_COUNT):
		skill.add_item(SimSkill.name_of(lv), lv)
	skill.select(SimSkill.Level.VETERAN)
	skill.disabled = human
	row.add_child(skill)

	var doctrine := MenuUI.option()
	doctrine.custom_minimum_size = Vector2(168, 30)
	for k in SimDoctrine.NAMES.keys():
		doctrine.add_item(SimDoctrine.name_of(k), k)
	# Greyed on your own row, and truthfully so: a doctrine is what an AI
	# director reads to decide when to attack and what to spend on sensors.
	# Nothing reads yours, because you are the one deciding.
	doctrine.disabled = human
	row.add_child(doctrine)

	var team := SpinBox.new()
	team.min_value = 0
	team.max_value = MAX_PLAYERS - 1
	team.value = 0 if human else 1
	team.custom_minimum_size = Vector2(58, 30)
	row.add_child(team)

	var adv_btn := MenuUI.button("Advanced", 11)
	adv_btn.custom_minimum_size = Vector2(92, 30)
	adv_btn.toggle_mode = true
	row.add_child(adv_btn)

	var blurb := MenuUI.para("", 11, MenuUI.COL_DIM, 600.0)
	box.add_child(blurb)

	var advanced := _advanced_panel(human)
	advanced.visible = false
	box.add_child(advanced)
	adv_btn.toggled.connect(func(on: bool): advanced.visible = on)

	var r := {
		"human": human, "box": box, "faction": faction, "skill": skill,
		"doctrine": doctrine, "team": team, "blurb": blurb,
		"seat_label": seat_label,
		"start": advanced.get_meta("start"),
		"ceiling": advanced.get_meta("ceiling"),
		"forces": advanced.get_meta("forces"),
		"domains": advanced.get_meta("domains"),
	}
	_rows.append(r)
	# The historical default, which is also what SimPlayerSetup would pick on
	# its own -- shown rather than left implicit, because "Russia plays Denial
	# unless you say otherwise" is a fact about the game worth seeing.
	_sync_default_doctrine(r)

	faction.item_selected.connect(func(_i):
		_sync_default_doctrine(r)
		_revalidate())
	for w in [skill, doctrine]:
		w.item_selected.connect(func(_i): _revalidate())
	team.value_changed.connect(func(_v): _revalidate())
	r["start"].value_changed.connect(func(_v): _revalidate())
	r["ceiling"].value_changed.connect(func(_v): _revalidate())
	r["forces"].item_selected.connect(func(_i): _revalidate())
	for c in r["domains"].values():
		(c as CheckBox).toggled.connect(func(_on): _revalidate())
	_revalidate()


## The per-seat overrides. Kept behind a disclosure because a first-time player
## should be able to start a match without meeting any of it, and a returning
## one should not have to leave the screen to express "army only, massed, but
## a generation behind".
func _advanced_panel(human: bool) -> Control:
	var panel := MenuUI.panel(Color(0.02, 0.035, 0.048, 0.9),
		MenuUI.COL_PLATE_EDGE)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	panel.add_child(col)

	var era_row := HBoxContainer.new()
	era_row.add_theme_constant_override("separation", 8)
	era_row.add_child(MenuUI.body("Epoch band", 12, MenuUI.COL_TEXT))
	var start := SpinBox.new()
	start.min_value = SimPlayerSetup.EPOCH_MIN
	start.max_value = SimPlayerSetup.EPOCH_MAX
	start.value = 4
	era_row.add_child(start)
	era_row.add_child(MenuUI.body("to", 12))
	var ceiling := SpinBox.new()
	ceiling.min_value = SimPlayerSetup.EPOCH_MIN
	ceiling.max_value = SimPlayerSetup.EPOCH_MAX
	ceiling.value = 6
	era_row.add_child(ceiling)
	col.add_child(era_row)

	var force_row := HBoxContainer.new()
	force_row.add_theme_constant_override("separation", 8)
	force_row.add_child(MenuUI.body("Starting force", 12, MenuUI.COL_TEXT))
	var forces := MenuUI.option(12)
	forces.custom_minimum_size = Vector2(150, 28)
	for k in range(5):
		forces.add_item(SimPlayerSetup._preset_name(k).capitalize(), k)
	forces.select(SimPlayerSetup.ForcePreset.ARMY)
	force_row.add_child(forces)
	force_row.add_child(MenuUI.para(
		"what is on the map at t+0; independent of the epoch band", 11,
		MenuUI.COL_DIM, 260.0))
	col.add_child(force_row)

	var dom_row := HBoxContainer.new()
	dom_row.add_theme_constant_override("separation", 10)
	dom_row.add_child(MenuUI.body("May build", 12, MenuUI.COL_TEXT))
	var domains := {}
	for spec in [["Ground", SimPlayerSetup.Domain.GROUND],
			["Infantry", SimPlayerSetup.Domain.INFANTRY],
			["Air", SimPlayerSetup.Domain.AIR],
			["Naval", SimPlayerSetup.Domain.NAVAL],
			["Structures", SimPlayerSetup.Domain.STRUCTURES]]:
		var c := CheckBox.new()
		c.text = str(spec[0])
		c.button_pressed = true
		c.add_theme_font_size_override("font_size", 12)
		dom_row.add_child(c)
		domains[int(spec[1])] = c
	col.add_child(dom_row)
	if human:
		col.add_child(MenuUI.para(
			"Skill and doctrine belong to the AI seats; yours are your own.",
			11, MenuUI.COL_DIM, 420.0))

	panel.set_meta("start", start)
	panel.set_meta("ceiling", ceiling)
	panel.set_meta("forces", forces)
	panel.set_meta("domains", domains)
	return panel


func _remove_last() -> void:
	if _rows.size() <= 2:
		_problems.text = "a match needs at least two participants"
		return
	var r: Dictionary = _rows.pop_back()
	(r["box"] as Node).queue_free()
	_revalidate()


func _sync_default_doctrine(r: Dictionary) -> void:
	var f: int = (r["faction"] as OptionButton).get_selected_id()
	var want := SimPlayerSetup.default_doctrine_for(f)
	var d := r["doctrine"] as OptionButton
	for i in range(d.item_count):
		if d.get_item_id(i) == want:
			d.select(i)
			break


func _era_changed(start_e: int, ceiling_e: int) -> void:
	# The global slider is the fast path: it writes every row. A row that wants
	# to differ opens Advanced and moves its own, which the slider will
	# overwrite the next time it is touched -- deliberately, because a hidden
	# override that survives the visible control is how a setup screen starts
	# lying about what it is about to start.
	for r in _rows:
		(r["start"] as SpinBox).set_value_no_signal(start_e)
		(r["ceiling"] as SpinBox).set_value_no_signal(ceiling_e)
	_revalidate()


# ═══════════════════════════════════════════════════════════════════════════
# THEATRE
# ═══════════════════════════════════════════════════════════════════════════

func _arena_title(key: String) -> String:
	match key:
		SimArena.SKIRMISH_VALLEY: return "Skirmish Valley"
		SimArena.OPEN_STEPPE: return "Open Steppe"
		SimArena.COASTAL_SHELF: return "Coastal Shelf"
	return key


func _choose_arena(key: String) -> void:
	if key == "":
		return
	_arena = key
	if key.begins_with(SimMapFile.ARENA_PREFIX):
		_arena_note.text = ("An authored map from data/maps/. Its own bases, "
			+ "its own oil, its own heightfield -- the match layer cannot tell "
			+ "it apart from a generated one.")
	else:
		_arena_note.text = SimArena.description(key)
	_revalidate()


# ═══════════════════════════════════════════════════════════════════════════
# THE SETUP ITSELF
# ═══════════════════════════════════════════════════════════════════════════

## Build the real SimMatchSetup from what the table says. Called on EVERY
## change, because the thing being validated has to be the thing that will be
## started -- validating a summary of the form is how a setup screen comes to
## disagree with the match it launches.
func _compose() -> SimMatchSetup:
	var s := SimMatchSetup.new()
	s.name = "Skirmish"
	s.seed_value = _seed_value()
	for i in range(_rows.size()):
		var r: Dictionary = _rows[i]
		var p := SimPlayerSetup.new()
		p.is_human = bool(r["human"])
		p.faction = (r["faction"] as OptionButton).get_selected_id()
		p.name = "You" if p.is_human else SimPlayerSetup._faction_name(p.faction)
		p.team = int((r["team"] as SpinBox).value)
		p.skill = (r["skill"] as OptionButton).get_selected_id()
		p.doctrine = SimDoctrine.make(
			(r["doctrine"] as OptionButton).get_selected_id())
		p.start_epoch = int((r["start"] as SpinBox).value)
		p.ceiling_epoch = int((r["ceiling"] as SpinBox).value)
		p.starting_forces = (r["forces"] as OptionButton).get_selected_id()
		var mask := 0
		for bit in (r["domains"] as Dictionary):
			if ((r["domains"] as Dictionary)[bit] as CheckBox).button_pressed:
				mask |= int(bit)
		p.allowed_domains = mask
		s.add(p)
	return s


func _seed_value() -> int:
	var t := _seed_edit.text.strip_edges()
	if t.is_valid_int():
		return int(t)
	# A word is a perfectly good seed, and refusing one would be the screen
	# being fussy about something the simulation does not care about.
	return int(abs(hash(t))) if t != "" else 20260826


func _revalidate() -> void:
	if _summary == null:
		return
	var s := _compose()
	var problems := s.validate()
	_problems.text = "" if problems.is_empty() \
		else "· " + "\n· ".join(problems)
	_problems.add_theme_color_override("font_color",
		MenuUI.COL_BAD if not problems.is_empty() else MenuUI.COL_DIM)
	var teams := s.teams()
	var sides := PackedStringArray()
	var keys: Array = teams.keys()
	keys.sort()
	for t in keys:
		var names := PackedStringArray()
		for p in teams[t]:
			names.append(SimPlayerSetup._faction_name((p as SimPlayerSetup).faction))
		sides.append("+".join(names))
	_summary.text = "%s  on  %s  ·  epoch %d-%d  ·  seed %d" % [
		" vs ".join(sides), _arena_title(_arena),
		_era.start_epoch, _era.ceiling_epoch, _seed_value()]
	for r in _rows:
		if bool(r["human"]):
			(r["blurb"] as Label).text = ("Skill and doctrine describe an AI "
				+ "commander. This seat is you; the faction and the era band "
				+ "are what it decides.")
			continue
		var d := (r["doctrine"] as OptionButton).get_selected_id()
		(r["blurb"] as Label).text = "%s  %s" % [SimSkill.blurb(
			(r["skill"] as OptionButton).get_selected_id()),
			SimDoctrine.blurb(d)]


func _start() -> void:
	var s := _compose()
	var problems := s.validate()
	# NOT greyed out. A refusal that names the rule teaches it; a dead button
	# leaves the player guessing which of eight controls is the wrong one.
	if not problems.is_empty():
		_problems.text = "cannot start -- " + problems[0]
		return
	AppState.pending_setup = s
	AppState.pending_arena = _arena
	AppState.pending_save = ""
	get_tree().change_scene_to_file(AppState.MATCH_SCENE)


func _back() -> void:
	get_tree().change_scene_to_file(AppState.TITLE_SCENE)


func _unhandled_key_input(ev: InputEvent) -> void:
	var k := ev as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	match k.keycode:
		KEY_ESCAPE:
			_back()
		KEY_ENTER, KEY_KP_ENTER:
			_start()
		KEY_UP, KEY_DOWN:
			# The screen owns the keyboard so that Enter always means START
			# rather than "confirm whichever list happens to be focused"; the
			# arrows are forwarded to the theatre column, which is the only
			# list on the screen. A focused spin box or dropdown consumes its
			# own arrows before this ever runs.
			_arena_list.handle_key(k.keycode)
		_:
			return
	get_viewport().set_input_as_handled()
