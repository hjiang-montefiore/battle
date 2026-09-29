extends Control
## THE ERA BAR -- the seven epochs as a ladder you can see yourself climbing.
##
## Borrowed from the owner's other RTS (~/Desktop/redalert, #erabar), and it
## answers a real gap. Epoch progression is the entire Empire Earth half of
## this game's pitch, and until now the HUD reported it as a single number in a
## line of text -- "epoch 4" -- beside the credits. A player could not see how
## far they had come, how far the setup lets them go, or that an advance was
## under way at all.
##
## Seven segments, one per epoch, named with the SAME labels the setup screen's
## era slider uses (AppState.EPOCH_NAME / EPOCH_YEARS), so the two cannot
## disagree about what epoch 5 is called. Past epochs are filled, the current
## one is lit, anything above the match's CEILING is shaded out because it
## cannot be reached, and an advance in progress fills the next segment as it
## goes.
##
## A READER, like the field manual: it is handed numbers every frame and
## touches nothing.

const SEG_GAP := 3.0

var epoch := 4
var ceiling := 7
var progress := 0.0          ## 0..1 toward epoch + 1, when advancing
var advancing := false

var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = get_theme_default_font()


func set_state(e: int, c: int, p: float, adv: bool) -> void:
	# Redraw only when something a player could see has changed. The bar is fed
	# every frame and a progress fill moves continuously, so the comparison is
	# on the rounded fill rather than the raw float.
	var changed := e != epoch or c != ceiling or adv != advancing \
		or int(p * 200.0) != int(progress * 200.0)
	epoch = e
	ceiling = c
	progress = clampf(p, 0.0, 1.0)
	advancing = adv
	if changed:
		queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var n := AppState.EPOCH_NAME.size()
	var seg_w := (w - SEG_GAP * float(n - 1)) / float(n)
	var bar_h := 8.0
	var y := h - bar_h

	for k in range(1, n + 1):
		var x := float(k - 1) * (seg_w + SEG_GAP)
		var r := Rect2(x, y, seg_w, bar_h)
		var col: Color
		if k > ceiling:
			col = Color(0.12, 0.13, 0.14, 0.9)         # cannot be reached here
		elif k < epoch:
			col = Color(0.55, 0.46, 0.26)               # climbed
		elif k == epoch:
			col = Color(0.92, 0.72, 0.30)               # where you stand
		else:
			col = Color(0.22, 0.25, 0.27)               # ahead, reachable
		draw_rect(r, col)
		# The advance under way, filling the NEXT segment as it goes.
		if advancing and k == epoch + 1 and k <= ceiling:
			draw_rect(Rect2(x, y, seg_w * progress, bar_h), Color(0.92, 0.72, 0.30, 0.75))

	# The label: where you are, by name and by decade, because a player thinks
	# in decades and the epoch index is an implementation detail.
	var label := "%s  ·  %s" % [AppState.EPOCH_NAME.get(epoch, "?"),
		AppState.EPOCH_YEARS.get(epoch, "")]
	if advancing and epoch < ceiling:
		label += "   →  advancing %d%%" % int(progress * 100.0)
	elif epoch >= ceiling:
		label += "   ·  at this match's ceiling"
	if _font != null:
		draw_string(_font, Vector2(0.0, y - 5.0), label, HORIZONTAL_ALIGNMENT_LEFT,
			-1.0, 12, Color(0.84, 0.88, 0.90))
