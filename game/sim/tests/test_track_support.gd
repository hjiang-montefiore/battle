extends SceneTree
## The scenario docs/02 pillar 1 actually sells, run end to end.
##
## Kill the illuminator. Keep one ESM truck alive. A semi-active missile must
## then be REFUSED, because nothing is illuminating the target any more.
##
## Before the fix this scenario authorised the shot. SimTrack.refresh() ratcheted
## quality upward and never let it fall, and decay() was suppressed by ANY
## contribution at all -- so a bearing-only ESM cut held a FIRE_CONTROL track
## alive indefinitely and the gate saw a fire-control solution that did not
## exist. That is pillar 1 inverted: the whole point is that you cannot shoot
## what you cannot hold.
##
## The second half matters as much as the first: the track must NOT die. ESM is
## still holding the contact, so it has to settle at CONTACT and stay there.
## A fix that simply dropped the track would trade one wrong answer for another.
##
##   Godot --headless --path game --script sim/tests/test_track_support.gd

var _pass := 0
var _fail := 0


func _ok(what: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("    PASS  %s%s" % [what, "  " + detail if detail else ""])
	else:
		_fail += 1
		print("    FAIL  %s%s" % [what, "  " + detail if detail else ""])


func _q(t: SimTrack) -> String:
	return SimTypes.quality_name(t.quality)


func _initialize() -> void:
	print("Track support: an ESM cut must not hold a fire-control solution")

	var sarh := SimWeaponDef.new({
		"name": "semi-active SAM",
		"guidance": SimTypes.Guidance.SARH,
		"max_range_km": 40.0,
	})

	# ── the illuminator is up ──────────────────────────────────────
	var t := SimTrack.new()
	t.support_q = SimTypes.TrackQuality.NONE
	t.refresh(SimTypes.TrackQuality.FIRE_CONTROL, SimTypes.Classification.TYPE,
			1.0, "illuminator")
	var r := SimWeaponGate.can_launch(sarh, t, 20.0)
	_ok("with the illuminator up, the SARH shot is authorised", r.allowed, r.reason)

	# ── the illuminator dies; only a bearing-only ESM cut remains ──
	# Each solve: clear the per-solve floor, then let ESM contribute CONTACT.
	var solves := 0
	while solves < 40:
		t.support_q = SimTypes.TrackQuality.NONE           # begin_solve()
		t.refresh(SimTypes.TrackQuality.CONTACT, SimTypes.Classification.TYPE,
				0.6, "esm_truck")                          # ESM still hears it
		t.decay(1.0)
		solves += 1

	_ok("the fire-control rung decays away once the illuminator is gone",
		t.quality < SimTypes.TrackQuality.FIRE_CONTROL, "quality=%s" % _q(t))
	_ok("but the track SURVIVES, because ESM is still holding it",
		t.quality == SimTypes.TrackQuality.CONTACT, "quality=%s" % _q(t))

	r = SimWeaponGate.can_launch(sarh, t, 20.0)
	_ok("and the SARH shot is now REFUSED", not r.allowed, r.reason)

	r = SimWeaponGate.still_supported(SimTypes.Guidance.SARH, t)
	_ok("a round already in flight goes ballistic", not r.allowed, r.reason)

	# ── the illuminator comes back ─────────────────────────────────
	t.support_q = SimTypes.TrackQuality.NONE
	t.refresh(SimTypes.TrackQuality.FIRE_CONTROL, SimTypes.Classification.TYPE,
			1.0, "illuminator")
	r = SimWeaponGate.can_launch(sarh, t, 20.0)
	_ok("re-acquiring restores the shot immediately", r.allowed, r.reason)

	# ── nothing at all: the track must eventually go cold ──────────
	var alive := true
	solves = 0
	while alive and solves < 200:
		t.support_q = SimTypes.TrackQuality.NONE
		alive = t.decay(1.0)
		solves += 1
	_ok("with NOTHING contributing, the track finally goes cold",
		not alive, "after %d s" % solves)

	print("\n  %d passed, %d failed" % [_pass, _fail])
	print("  PASS" if _fail == 0 else "  FAIL")
	quit(0 if _fail == 0 else 1)


## Safety net. A parse or runtime error inside _initialize() skips quit() and
## leaves the SceneTree spinning with its stdout unflushed -- which looks
## exactly like a hang and hides the error that caused it. Returning true here
## guarantees the process exits after one iteration no matter what.
func _process(_delta: float) -> bool:
	return true
