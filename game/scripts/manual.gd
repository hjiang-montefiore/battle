extends Control
## THE FIELD MANUAL -- a browsable record of everything the game can field.
##
## Borrowed from the owner's other RTS (~/Desktop/redalert, gallery.js) along
## with the one rule that makes it worth having:
##
##   IT READS THE TABLES THE SIMULATION READS. Every number on a page comes
##   from SimRoster, SimArsenal or data/factions -- the same rows SimEconomy
##   and SimWeaponCycle consult during a match. Nothing here is transcribed, so
##   a page that disagreed with the battlefield would be a BUG rather than a
##   typo, and would be caught by the tests that already cover those tables.
##
## And the second rule, which is what lets it open from a paused match safely:
##
##   IT IS A READER. It never ticks the world, never touches the match's paused
##   flag, never issues a command and never writes a single simulation value.
##   Opening it and closing it again leaves the screen underneath exactly as it
##   was, which is the whole reason it can be bound to a key in play.
##
## This surfaces the part of the project a player currently cannot see. The
## researched equipment ladders -- real designations, service dates, masses and
## road ranges for eight nations -- have been in data/factions since they were
## written and have never once reached the screen.

const ICONS := "res://assets/icons/"

## The roles worth listing, in the order a player thinks about them. Taken from
## the build panel's own tabs so the manual and the sidebar cannot disagree
## about what category a thing is.
const SECTIONS := [
	["STRUCTURES", ["hq", "power_plant", "refinery", "barracks", "light_factory",
		"heavy_factory", "airbase", "helipad", "naval_yard", "research_facility",
		"repair_depot", "supply_depot", "oil_derrick"]],
	["DEFENCES", ["bunker", "fixed_radar", "fixed_sam", "ew_station",
		"coastal_battery", "hardened_shelter"]],
	["INFANTRY", ["rifle_squad", "at_team", "manpads_team", "mortar_team",
		"recon_team", "special_forces", "engineer_squad"]],
	["VEHICLES", ["mbt", "ifv", "apc", "atgm_carrier", "light_tank",
		"recon_vehicle", "sph", "mlrs", "towed_artillery", "mortar_carrier",
		"spaag", "shorad_sam", "long_sam_launcher", "medium_sam_launcher",
		"search_radar", "illuminator", "counter_battery_radar", "ground_ew",
		"fuel_truck", "ammo_truck", "command_vehicle", "engineer_vehicle",
		"repair_vehicle", "ore_miner", "ballistic_launcher", "coastal_asm"]],
	["AIRCRAFT", ["air_superiority", "multirole", "strike_aircraft", "cas",
		"bomber", "sead", "aewc", "maritime_patrol", "transport_aircraft",
		"tanker", "attack_helicopter", "asw_helicopter", "armed_uav", "isr_uav"]],
	["SEA", ["carrier", "cruiser", "air_defence_destroyer", "asw_frigate",
		"corvette", "missile_boat", "patrol_vessel", "amphib", "submarine"]],
]

var faction: int = SimPlayerSetup.Faction.US
var epoch: int = 4

var _section := 0
var _row := 0
var _rows: Array = []
var _icon_cache: Dictionary = {}

var _list: VBoxContainer
var _detail: VBoxContainer
var _title: Label
var _crumb: Label
var _picture: TextureRect

signal closed


func _ready() -> void:
	# ANCHORS AND OFFSETS, not anchors alone. Under a CanvasLayer there is no
	# parent Control to size against, and set_anchors_preset() by itself left
	# this node at 0 x 0: the backdrop drew nothing, the menu showed straight
	# through, and the list and page collapsed to zero height while the header
	# labels overflowed out of an invisible box. The first render caught it.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_refresh()


func open_at(f: int, e: int, section := -1) -> void:
	faction = f
	epoch = clampi(e, 1, 7)
	if section >= 0:
		_section = clampi(section, 0, SECTIONS.size() - 1)
		_row = 0
	_icon_cache.clear()
	_refresh()


# ── layout ───────────────────────────────────────────────────────────────────

func _build() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Opaque. At 0.97 the menu underneath ghosted through the light text.
	bg.color = Color(0.035, 0.045, 0.055, 1.0)
	add_child(bg)

	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.add_theme_constant_override("margin_left", 48)
	pad.add_theme_constant_override("margin_right", 48)
	pad.add_theme_constant_override("margin_top", 30)
	pad.add_theme_constant_override("margin_bottom", 26)
	add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	pad.add_child(col)

	_title = Label.new()
	_title.text = "FIELD MANUAL"
	_title.add_theme_font_size_override("font_size", 30)
	col.add_child(_title)

	_crumb = Label.new()
	_crumb.add_theme_font_size_override("font_size", 12)
	_crumb.add_theme_color_override("font_color", Color(0.62, 0.68, 0.72))
	col.add_child(_crumb)

	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.split_offset = 380
	col.add_child(body)

	var left := ScrollContainer.new()
	left.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(left)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 1)
	left.add_child(_list)

	var right := ScrollContainer.new()
	right.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(right)
	var rcol := VBoxContainer.new()
	rcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rcol.add_theme_constant_override("separation", 8)
	right.add_child(rcol)

	_picture = TextureRect.new()
	_picture.custom_minimum_size = Vector2(0, 190)
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rcol.add_child(_picture)

	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 3)
	rcol.add_child(_detail)

	var keys := Label.new()
	keys.text = ("arrows move  ·  left/right change section  ·  "
		+ "[ ] change epoch  ·  \\ changes nation  ·  Esc closes")
	keys.add_theme_font_size_override("font_size", 11)
	keys.add_theme_color_override("font_color", Color(0.52, 0.58, 0.62))
	col.add_child(keys)


# ── the pages ────────────────────────────────────────────────────────────────

func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	_rows.clear()

	var name_of := SimPlayerSetup.faction_name(faction)
	_crumb.text = "%s  ·  epoch %d  ·  %s" % [name_of, epoch,
		String(SECTIONS[_section][0])]

	for role in SECTIONS[_section][1]:
		var d := SimRoster.make(String(role), epoch, faction)
		# A ROLE A NATION DOES NOT FIELD IS LISTED AND SAID SO, not hidden.
		# Taiwan builds no bomber, and that absence is researched history --
		# a manual that quietly omitted it would be teaching the player the
		# roster is smaller than it is.
		_rows.append([String(role), d])

	for k in range(_rows.size()):
		_list.add_child(_row_button(k))
	_row = clampi(_row, 0, maxi(_rows.size() - 1, 0))
	_show(_row)


func _row_button(k: int) -> Control:
	var role: String = _rows[k][0]
	var d = _rows[k][1]
	var b := Button.new()
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 13)
	b.custom_minimum_size = Vector2(0, 30)
	b.flat = k != _row
	if d == null:
		b.text = "%s   — not fielded" % _pretty(role)
		b.disabled = true
	else:
		b.text = "%s   %.0f" % [d.name, d.cost]
		var ico := _icon(role)
		if ico != null:
			b.icon = ico
			b.expand_icon = true
	b.pressed.connect(func(): _row = k; _refresh_selection())
	return b


func _refresh_selection() -> void:
	for k in range(_list.get_child_count()):
		var b := _list.get_child(k) as Button
		if b != null:
			b.flat = k != _row
	_show(_row)


## Everything on this page is read live. Nothing is stored, so nothing can go
## stale against the tables a match actually plays from.
func _show(k: int) -> void:
	for c in _detail.get_children():
		c.queue_free()
	if k < 0 or k >= _rows.size():
		return
	var role: String = _rows[k][0]
	var d = _rows[k][1]

	var stem := SimFactionData.model_stem_for(role, faction, epoch)
	_picture.texture = _icon(role)

	if d == null:
		_head(_pretty(role))
		_line("This nation fields no %s at epoch %d." % [_pretty(role).to_lower(), epoch])
		_line("Researched absence, not a gap in the game.")
		return

	_head(d.name)
	if d.designation != "" and d.designation != d.name:
		_line(d.designation, Color(0.86, 0.72, 0.42))

	_rule()
	_stat("Cost", "%.0f credits" % d.cost)
	_stat("Build time", "%.0f s" % d.build_seconds)
	if d.built_by != "":
		_stat("Built at", _pretty(d.built_by))
	if d.requires.size() > 0:
		_stat("Requires", ", ".join(d.requires))

	if not d.is_structure:
		_rule()
		if d.speed_kmh > 0.0:
			_stat("Speed", "%.0f km/h" % d.speed_kmh)
		if d.road_range_km > 0.0:
			_stat("Road range", "%.0f km" % d.road_range_km)
		if d.mass_t > 0.0:
			_stat("Mass", "%.1f t" % d.mass_t)
		if d.crew > 0:
			_stat("Crew", str(d.crew))
		if d.length_m > 0.0:
			_stat("Dimensions", "%.1f x %.1f x %.1f m" % [d.length_m, d.width_m, d.height_m])

	# WHAT IT SHOOTS, straight out of the arsenal the weapon cycle arms from.
	var guns := SimArsenal.loadout(role, epoch)
	if guns.size() > 0:
		_rule()
		_head2("ARMAMENT")
		for m in guns:
			var w: SimWeaponDef = m["weapon"]
			_stat(w.name, "%.1f-%.1f km" % [w.min_range_km, w.max_range_km])
	elif SimArsenal.is_combatant(role):
		_rule()
		_line("Unarmed at this epoch.")

	if d.is_structure:
		_rule()
		if d.power_supply > 0.0:
			_stat("Power", "+%.0f MW" % d.power_supply)
		if d.power_draw > 0.0:
			_stat("Power", "-%.0f MW" % d.power_draw)
		if d.extraction_per_min > 0.0:
			_stat("Extraction", "%.0f crude/min" % d.extraction_per_min)
		if d.refine_capacity > 0.0:
			_stat("Refining", "%.0f cr/min, and where ore is unloaded"
				% d.refine_capacity)
		if d.build_radius_m > 0.0:
			_stat("Build radius", "%.0f m" % d.build_radius_m)
		if d.structure_hp > 0.0:
			_stat("Structure", "%.0f" % d.structure_hp)

	_rule()
	_stat("Model", stem if stem != "" else "blockout")


# ── small builders ───────────────────────────────────────────────────────────

func _head(t: String) -> void:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 21)
	_detail.add_child(l)


func _head2(t: String) -> void:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color(0.86, 0.72, 0.42))
	_detail.add_child(l)


func _line(t: String, c := Color(0.76, 0.81, 0.84)) -> void:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", c)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(l)


func _stat(k: String, v: String) -> void:
	var h := HBoxContainer.new()
	var a := Label.new()
	a.text = k
	a.custom_minimum_size = Vector2(150, 0)
	a.add_theme_font_size_override("font_size", 12)
	a.add_theme_color_override("font_color", Color(0.56, 0.62, 0.66))
	var b := Label.new()
	b.text = v
	b.add_theme_font_size_override("font_size", 12)
	h.add_child(a)
	h.add_child(b)
	_detail.add_child(h)


func _rule() -> void:
	var r := ColorRect.new()
	r.custom_minimum_size = Vector2(0, 1)
	r.color = Color(0.20, 0.25, 0.29)
	_detail.add_child(r)


func _pretty(s: String) -> String:
	return s.replace("_", " ").capitalize()


func _icon(role: String) -> Texture2D:
	if _icon_cache.has(role):
		return _icon_cache[role]
	var tex: Texture2D = null
	var stem := SimFactionData.model_stem_for(role, faction, epoch)
	if stem != "":
		var p := ICONS + stem + ".png"
		if ResourceLoader.exists(p):
			tex = load(p) as Texture2D
	_icon_cache[role] = tex
	return tex


# ── input ────────────────────────────────────────────────────────────────────

func _unhandled_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return
	var k := (ev as InputEventKey).keycode
	match k:
		KEY_ESCAPE:
			closed.emit()
		KEY_DOWN:
			_row = mini(_row + 1, _rows.size() - 1)
			_refresh_selection()
		KEY_UP:
			_row = maxi(_row - 1, 0)
			_refresh_selection()
		KEY_RIGHT:
			_section = (_section + 1) % SECTIONS.size()
			_row = 0
			_icon_cache.clear()
			_refresh()
		KEY_LEFT:
			_section = (_section - 1 + SECTIONS.size()) % SECTIONS.size()
			_row = 0
			_icon_cache.clear()
			_refresh()
		KEY_BRACKETRIGHT:
			epoch = clampi(epoch + 1, 1, 7)
			_icon_cache.clear()
			_refresh()
		KEY_BRACKETLEFT:
			epoch = clampi(epoch - 1, 1, 7)
			_icon_cache.clear()
			_refresh()
		KEY_BACKSLASH:
			faction = (faction + 1) % 8
			_icon_cache.clear()
			_refresh()
		_:
			return
	get_viewport().set_input_as_handled()
