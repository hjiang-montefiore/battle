class_name OptionsPanel
extends VBoxContainer
## Four settings that all do something.
##
## Reached from two places -- the title and the pause menu -- and it is the
## same object in both, because an options screen that exists twice will
## eventually disagree with itself about what is set. Everything here writes
## straight through to AppState and takes effect on the frame it is changed;
## there is no Apply button, because there is nothing that needs one.

signal closed()


func _init() -> void:
	add_theme_constant_override("separation", 10)
	AppState.load_options()
	_row_slider("Master volume", AppState.master_volume, func(v):
		AppState.master_volume = v
		AppState.apply_options()
		AppState.save_options())
	_row_slider("Music volume", AppState.music_volume, func(v):
		AppState.music_volume = v
		AppState.apply_options()
		AppState.save_options())
	_row_check("Edge scrolling", AppState.edge_pan,
		"Pushing the pointer into the screen edge pans the camera.", func(on):
			AppState.edge_pan = on
			AppState.save_options())
	_row_check("Fullscreen", AppState.fullscreen, "", func(on):
		AppState.fullscreen = on
		AppState.apply_options()
		AppState.save_options())

	add_child(MenuUI.para(
		"Arrows move, Enter confirms, Esc goes back. In a match: Esc opens "
		+ "this menu, F5 quicksaves, F9 quickloads, Space pauses.", 12,
		MenuUI.COL_DIM, 520.0))

	var back := MenuUI.button("Back")
	back.custom_minimum_size = Vector2(120, 30)
	back.pressed.connect(func(): closed.emit())
	var wrap := HBoxContainer.new()
	wrap.add_child(back)
	add_child(wrap)


func _row_slider(label: String, value: float, on_change: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := MenuUI.body(label, 15, MenuUI.COL_TEXT)
	l.custom_minimum_size = Vector2(170, 0)
	row.add_child(l)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	slider.custom_minimum_size = Vector2(230, 20)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var read := MenuUI.body("%d%%" % int(round(value * 100.0)), 14,
		MenuUI.COL_ACCENT)
	read.custom_minimum_size = Vector2(56, 0)
	read.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(read)
	slider.value_changed.connect(func(v: float):
		read.text = "%d%%" % int(round(v * 100.0))
		on_change.call(v))
	add_child(row)


func _row_check(label: String, on: bool, note: String,
		on_change: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := MenuUI.body(label, 15, MenuUI.COL_TEXT)
	l.custom_minimum_size = Vector2(170, 0)
	row.add_child(l)
	var check := CheckButton.new()
	check.button_pressed = on
	check.toggled.connect(func(v: bool): on_change.call(v))
	row.add_child(check)
	if note != "":
		row.add_child(MenuUI.para(note, 12, MenuUI.COL_DIM, 240.0))
	add_child(row)
