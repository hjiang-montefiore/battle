extends Node
## The score's playback contract, implemented. tools/music_synth.py composed
## three battle layers in ONE key and tempo with exact bar-multiple lengths so
## the game can CROSSFADE on a shared playhead instead of switching tracks --
## this node is the other half of that bargain.
##
##   battle_calm  120 s  \  both started at match start, sample-locked, only
##   battle_action 120 s /  their GAINS move: combat crossfades calm->action
##                          over 2 s, back over 4 s when the guns fall silent
##   battle_peril  60 s     ADDITIVE above action while the player's collapse
##                          timer runs, phase-locked at playhead mod 60
##   sting_contact          first enemy contact of the match, once
##   sting_epoch            each epoch advance
##
## Headroom is baked into the WAVs (music peaks at 0.22 against the SFX bank's
## 0.89), so every player here runs at unity and SFX always sit on top.
##
## Like GameAudio, this READS game state and writes none of it. It is driven
## by set_state() from the scene each frame; a headless run never starts it.

const DIR := "res://assets/audio/music/"
const XFADE_IN := 2.0
const XFADE_OUT := 4.0
const PERIL_IN := 2.0
const PERIL_OUT := 3.0
const COMBAT_HOLD_S := 8.0

var _calm: AudioStreamPlayer
var _action: AudioStreamPlayer
var _peril: AudioStreamPlayer
var _sting: AudioStreamPlayer
var _clips: Dictionary = {}
var _combat_until := -1.0e9
var _t := 0.0
var _contact_stung := false
var _last_epoch := -1


func _ready() -> void:
	for base in ["battle_calm", "battle_action", "battle_peril",
			"sting_contact", "sting_epoch", "menu_theme"]:
		var s := _load_wav(DIR + base + ".wav")
		if s != null:
			_clips[base] = s
	_calm = _mk("battle_calm", 0.0)
	_action = _mk("battle_action", -60.0)
	_peril = _mk("battle_peril", -60.0)
	_sting = AudioStreamPlayer.new()
	add_child(_sting)
	# One shared playhead: start together, loop by length. calm and action are
	# the same 120.000 s so they never drift; peril is exactly half and is
	# started with the others, so playhead mod 60 holds by construction.
	for p in [_calm, _action, _peril]:
		if p.stream != null:
			p.play()


func _mk(clip: String, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	var s: AudioStreamWAV = _clips.get(clip)
	if s != null:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = s.data.size() / 2
		p.stream = s
	p.volume_db = db
	add_child(p)
	return p


func _process(dt: float) -> void:
	_t += dt
	var fighting := _t < _combat_until
	_slide(_action, 0.0 if fighting else -60.0,
		dt * 60.0 / (XFADE_IN if fighting else XFADE_OUT))
	_slide(_calm, -60.0 if fighting else 0.0,
		dt * 60.0 / (XFADE_IN if fighting else XFADE_OUT))


func _slide(p: AudioStreamPlayer, target_db: float, step: float) -> void:
	if p == null:
		return
	p.volume_db = move_toward(p.volume_db, target_db, step)


## The scene reports what is happening; the score reacts. All arguments are
## things the PLAYER could know -- kills involving own units, own collapse
## timer, own epoch, own contact count -- so the music cannot leak the enemy's
## state any more than the UI can.
func set_state(own_combat_now: bool, in_collapse: bool,
		contacts_held: int, epoch: int) -> void:
	if own_combat_now:
		_combat_until = _t + COMBAT_HOLD_S
	_slide(_peril, 0.0 if in_collapse else -60.0,
		1.0 / (PERIL_IN if in_collapse else PERIL_OUT))
	if not _contact_stung and contacts_held > 0:
		_contact_stung = true
		_play_sting("sting_contact")
	if _last_epoch >= 0 and epoch > _last_epoch:
		_play_sting("sting_epoch")
	_last_epoch = epoch


func _play_sting(clip: String) -> void:
	var s: AudioStreamWAV = _clips.get(clip)
	if s != null and _sting != null:
		_sting.stream = s
		_sting.play()


## Same runtime RIFF reader as GameAudio: generated WAVs have no .import
## sidecar and the editor import pass hangs on this project.
func _load_wav(path: String) -> AudioStreamWAV:
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return null
	var bytes := fa.get_buffer(fa.get_length())
	fa.close()
	if bytes.size() < 44 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF":
		return null
	var rate := 44100
	var channels := 1
	var bits := 16
	var pcm := PackedByteArray()
	var i := 12
	while i + 8 <= bytes.size():
		var tag := bytes.slice(i, i + 4).get_string_from_ascii()
		var size := bytes.decode_u32(i + 4)
		var body := i + 8
		if tag == "fmt ":
			channels = bytes.decode_u16(body + 2)
			rate = int(bytes.decode_u32(body + 4))
			bits = bytes.decode_u16(body + 14)
		elif tag == "data":
			pcm = bytes.slice(body, mini(body + size, bytes.size()))
		i = body + size + (size & 1)
	if pcm.is_empty() or bits != 16:
		return null
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.stereo = channels == 2
	s.data = pcm
	return s
