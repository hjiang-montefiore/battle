class_name EraSlider
extends Control
## The timeline, with two handles on it.
##
## The game's range is seventy years wide and the simulation expresses that as
## two independent numbers per player -- start_epoch, the technology you are
## handed, and ceiling_epoch, the highest you may ever reach. Those two numbers
## are what make "advanced but tiny" and "obsolete but enormous" different
## matches, and a single difficulty dropdown cannot say either of them.
##
## So the control is one timeline with two grips: where you begin, and where
## you may end. The band between them is the whole game the match will be.
## Drawn with the years on it rather than the epoch numbers, because a player
## thinks in decades and the epoch index is an implementation detail they
## should be able to ignore forever.

signal changed(start_epoch: int, ceiling_epoch: int)

const E_MIN := 1
const E_MAX := 7
const PAD := 26.0
const TRACK_Y := 30.0
const HANDLE_R := 9.0

var start_epoch := 4
var ceiling_epoch := 6

var _drag := -1            ## 0 = start handle, 1 = ceiling handle, -1 = none
var _active := 0           ## which handle the keyboard moves


func _init() -> void:
	custom_minimum_size = Vector2(560, 96)
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_band(start_e: int, ceiling_e: int, notify := false) -> void:
	start_epoch = clampi(start_e, E_MIN, E_MAX)
	ceiling_epoch = clampi(maxi(ceiling_e, start_epoch), E_MIN, E_MAX)
	queue_redraw()
	if notify:
		changed.emit(start_epoch, ceiling_epoch)


func _x_for(e: int) -> float:
	var span: float = maxf(size.x - PAD * 2.0, 1.0)
	return PAD + float(e - E_MIN) / float(E_MAX - E_MIN) * span


func _epoch_at(x: float) -> int:
	var span: float = maxf(size.x - PAD * 2.0, 1.0)
	var f := (x - PAD) / span * float(E_MAX - E_MIN)
	return clampi(int(round(f)) + E_MIN, E_MIN, E_MAX)


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			grab_focus()
			# Grab the NEARER handle, and break the tie by which side of it the
			# click landed -- without that, two handles stacked on the same
			# epoch can only ever be pulled in one direction.
			var ds := absf(mb.position.x - _x_for(start_epoch))
			var dc := absf(mb.position.x - _x_for(ceiling_epoch))
			if is_equal_approx(ds, dc):
				_drag = 1 if mb.position.x > _x_for(start_epoch) else 0
			else:
				_drag = 0 if ds < dc else 1
			_active = _drag
			_drag_to(mb.position.x)
		else:
			_drag = -1
	elif ev is InputEventMouseMotion and _drag >= 0:
		_drag_to((ev as InputEventMouseMotion).position.x)
	elif ev is InputEventKey:
		var k := ev as InputEventKey
		if not k.pressed or k.echo:
			return
		match k.keycode:
			KEY_LEFT:
				_nudge(-1, k.shift_pressed)
			KEY_RIGHT:
				_nudge(1, k.shift_pressed)
			KEY_TAB:
				_active = 1 - _active
				queue_redraw()
			_:
				return
		accept_event()


func _nudge(dir: int, ceiling_handle: bool) -> void:
	# Shift moves the CEILING, plain arrows move the start. Tab swaps which one
	# the arrows have, for a player who would rather not hold a modifier.
	var which := 1 if ceiling_handle else _active
	if ceiling_handle:
		_active = 1
	if which == 0:
		set_band(start_epoch + dir, ceiling_epoch, true)
	else:
		set_band(start_epoch, ceiling_epoch + dir, true)


func _drag_to(x: float) -> void:
	var e := _epoch_at(x)
	if _drag == 0:
		set_band(e, maxi(ceiling_epoch, e), true)
	else:
		set_band(mini(start_epoch, e), e, true)


func _draw() -> void:
	var font := get_theme_default_font()
	var x0 := _x_for(E_MIN)
	var x1 := _x_for(E_MAX)
	var xs := _x_for(start_epoch)
	var xc := _x_for(ceiling_epoch)

	# The whole span, unlit.
	draw_line(Vector2(x0, TRACK_Y), Vector2(x1, TRACK_Y),
		Color(0.26, 0.31, 0.36), 4.0)
	# The band this match will actually be played inside.
	draw_line(Vector2(xs, TRACK_Y), Vector2(xc, TRACK_Y), MenuUI.COL_ACCENT, 5.0)

	for e in range(E_MIN, E_MAX + 1):
		var x := _x_for(e)
		var lit: bool = e >= start_epoch and e <= ceiling_epoch
		draw_line(Vector2(x, TRACK_Y - 8.0), Vector2(x, TRACK_Y + 8.0),
			MenuUI.COL_ACCENT if lit else Color(0.34, 0.39, 0.44), 1.0)
		var years: String = AppState.EPOCH_YEARS[e]
		var w := font.get_string_size(years, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		draw_string(font, Vector2(x - w * 0.5, TRACK_Y + 24.0), years,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
			MenuUI.COL_TEXT if lit else Color(0.45, 0.50, 0.55))

	for h in range(2):
		var x: float = xs if h == 0 else xc
		var on: bool = _active == h and has_focus()
		draw_circle(Vector2(x, TRACK_Y), HANDLE_R + (2.0 if on else 0.0),
			Color(0.04, 0.06, 0.08))
		draw_circle(Vector2(x, TRACK_Y), HANDLE_R,
			MenuUI.COL_ACCENT if on else Color(0.82, 0.86, 0.90))

	var caption := "start %s   ·   ceiling %s" % [
		AppState.epoch_label(start_epoch), AppState.epoch_label(ceiling_epoch)]
	draw_string(font, Vector2(PAD, TRACK_Y + 50.0), caption,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MenuUI.COL_TEXT)
	draw_string(font, Vector2(PAD, TRACK_Y + 68.0),
		"drag a handle · arrows move the start · shift+arrows move the ceiling",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, MenuUI.COL_DIM)
