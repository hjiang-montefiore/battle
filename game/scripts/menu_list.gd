class_name MenuList
extends VBoxContainer
## A keyboard-first list of choices. Arrows move, Enter confirms, Esc backs out.
##
## The owner asked for keyboard-first explicitly, and that is a stronger
## constraint than it looks: it means the HIGHLIGHT, not the mouse pointer, is
## the source of truth about what is selected, and the mouse has to feed the
## highlight rather than run alongside it. Hovering therefore MOVES the
## highlight instead of drawing a second one, so there is never a frame where
## the keyboard and the pointer disagree about what Enter would do.
##
## Entries that cannot be chosen are shown and marked, never hidden -- except
## where the caller omits them outright, which is what Continue does when there
## is nothing to continue. A disabled row says why; an absent row says nothing,
## and that is the difference between honest and evasive.

signal chosen(id: String)
signal cancelled()
signal highlighted(id: String)

const ROW_H := 34.0

var _rows: Array = []          ## [{id, text, note, enabled, button, label, mark}]
var _index := 0
var _active := true


func _init() -> void:
	add_theme_constant_override("separation", 2)
	set_process_unhandled_key_input(true)


func set_active(on: bool) -> void:
	_active = on
	set_process_unhandled_key_input(on)
	_restyle()


func is_active() -> bool:
	return _active


func add_entry(id: String, text: String, enabled := true, note := "") -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.custom_minimum_size = Vector2(0, ROW_H)

	# The highlight is a lit BAR down the left of the row rather than a filled
	# background: at a glance it reads as a cursor sitting beside a list, which
	# is what it is, and it survives being drawn over a moving battle.
	var mark := ColorRect.new()
	mark.custom_minimum_size = Vector2(4, ROW_H - 6)
	mark.color = Color(0, 0, 0, 0)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(mark)

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 19)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)

	var note_label: Label = null
	if note != "":
		note_label = Label.new()
		note_label.text = note
		note_label.add_theme_font_size_override("font_size", 12)
		note_label.add_theme_color_override("font_color", MenuUI.COL_DIM)
		note_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		note_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(note_label)

	# An invisible button over the whole row carries the mouse. The visuals are
	# the labels above; this only catches hover and click.
	var hit := Button.new()
	hit.flat = true
	hit.focus_mode = Control.FOCUS_NONE
	hit.set_anchors_preset(Control.PRESET_FULL_RECT)
	hit.mouse_filter = Control.MOUSE_FILTER_STOP

	var stack := Control.new()
	stack.custom_minimum_size = Vector2(0, ROW_H)
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_child(row)
	stack.add_child(hit)
	add_child(stack)

	var idx := _rows.size()
	# The pointer works whether or not this list currently owns the keyboard.
	# `_active` governs KEYS ONLY -- a list that is merely not the focused one,
	# like the theatre column beside a form, must still be clickable, and it
	# must still show which row is chosen.
	hit.mouse_entered.connect(func():
		if enabled:
			_move_to(idx))
	hit.pressed.connect(func():
		_move_to(idx)
		_confirm())

	_rows.append({"id": id, "text": text, "note": note, "enabled": enabled,
		"label": label, "mark": mark, "note_label": note_label})
	if not _rows[_index]["enabled"]:
		_index = _first_enabled()
	_restyle()


func clear_entries() -> void:
	for c in get_children():
		c.queue_free()
	_rows.clear()
	_index = 0


func count() -> int:
	return _rows.size()


func selected_id() -> String:
	if _index < 0 or _index >= _rows.size():
		return ""
	return str(_rows[_index]["id"])


func highlight(id: String) -> void:
	for i in range(_rows.size()):
		if _rows[i]["id"] == id and _rows[i]["enabled"]:
			_move_to(i)
			return


func highlight_index(i: int) -> void:
	if i >= 0 and i < _rows.size() and _rows[i]["enabled"]:
		_move_to(i)


func highlighted_index() -> int:
	return _index


## The keyboard path, exposed so a headless check can drive the menu without a
## window -- and so a screen that owns the keyboard itself can forward the
## arrows to a list it is standing beside. Deliberately does NOT consult
## `_active`: an explicit call IS the activation. Returns true if the key meant
## something to this list.
func handle_key(code: int) -> bool:
	if _rows.is_empty():
		return false
	match code:
		KEY_UP, KEY_W:
			_step(-1)
			return true
		KEY_DOWN, KEY_S:
			_step(1)
			return true
		KEY_HOME:
			_move_to(_first_enabled())
			return true
		KEY_END:
			_move_to(_last_enabled())
			return true
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_confirm()
			return true
		KEY_ESCAPE:
			cancelled.emit()
			return true
	return false


func _unhandled_key_input(ev: InputEvent) -> void:
	var k := ev as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if _active and handle_key(k.keycode):
		get_viewport().set_input_as_handled()


func _step(dir: int) -> void:
	if _rows.is_empty():
		return
	var i := _index
	for _n in range(_rows.size()):
		i = wrapi(i + dir, 0, _rows.size())
		if _rows[i]["enabled"]:
			_move_to(i)
			return


func _first_enabled() -> int:
	for i in range(_rows.size()):
		if _rows[i]["enabled"]:
			return i
	return 0


func _last_enabled() -> int:
	for i in range(_rows.size() - 1, -1, -1):
		if _rows[i]["enabled"]:
			return i
	return 0


func _move_to(i: int) -> void:
	if i == _index:
		return
	_index = i
	_restyle()
	highlighted.emit(selected_id())


func _confirm() -> void:
	if _index < 0 or _index >= _rows.size():
		return
	if not _rows[_index]["enabled"]:
		return
	chosen.emit(str(_rows[_index]["id"]))


func _restyle() -> void:
	for i in range(_rows.size()):
		var r: Dictionary = _rows[i]
		var on: bool = i == _index
		var label: Label = r["label"]
		var mark: ColorRect = r["mark"]
		if not r["enabled"]:
			label.add_theme_color_override("font_color", Color(0.42, 0.46, 0.50))
			mark.color = Color(0, 0, 0, 0)
		elif on:
			label.add_theme_color_override("font_color", MenuUI.COL_ACCENT)
			mark.color = MenuUI.COL_ACCENT
		else:
			label.add_theme_color_override("font_color", MenuUI.COL_TEXT)
			mark.color = Color(0, 0, 0, 0)
