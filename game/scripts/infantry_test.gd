extends Node3D
## Verifies the infantry pipeline inside the engine, not just in Blender.
##
## The infantry budget rests on one claim: export the skeleton and its eleven
## clips ONCE, export 392 variant meshes carrying no animation at all, and bind
## the single library to all of them at runtime. tools/verify_clip_share.py
## already proves that holds in Blender. This proves it survives the glTF round
## trip into Godot, which is a different question — Godot rebuilds the scene
## graph on import, and animation tracks resolve by NODE PATH, so a library
## whose skeleton sits at a different path than the variant's is useless no
## matter how well the bone names match.
##
## Run: Godot --headless --path game --script scripts/infantry_test.gd

const ASSETS := "res://assets/units/"
const LIB := "inf_rig_clips"
const ERA_LADDER := ["inf_e1_us_rifle", "inf_e2_us_rifle", "inf_e3_us_rifle",
	"inf_e4_us_rifle", "inf_e5_us_rifle", "inf_e6_us_rifle", "inf_e7_us_rifle"]
const FACTION_ROW := ["inf_e6_us_rifle", "inf_e6_uk_rifle", "inf_e6_de_rifle",
	"inf_e6_fr_rifle", "inf_e6_cn_rifle", "inf_e6_ru_rifle",
	"inf_e6_tw_rifle", "inf_e6_kp_rifle"]
const ROLES := ["inf_e6_us_at", "inf_e6_us_manpads", "inf_e6_us_recon",
	"inf_e6_us_engineer", "inf_e6_us_sf", "inf_e6_us_mortar"]
## Godot bones have an origin but no tail, so the top of the skull is not a
## joint position anywhere in the skeleton — the highest joint is the head
## bone's own origin at the base of the skull. Asserting 1.78 (the tip of the
## head bone in Blender) fails every correct asset by exactly the head's
## length, which is what the first run of this check did.
const HEAD_JOINT_Y := 1.60
const H_TOL := 0.10

var _fail := 0
var _pass := 0
var _lines: Array[String] = []


func _note(ok: bool, msg: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	_lines.append(("  ok   " if ok else "  FAIL ") + msg)


func _find(node: Node, type_name: String) -> Node:
	if node.get_class() == type_name:
		return node
	for c in node.get_children():
		var f := _find(c, type_name)
		if f != null:
			return f
	return null


func _instance(name: String) -> Node3D:
	var path := ASSETS + name + ".glb"
	if not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	return packed.instantiate() as Node3D


func _ready() -> void:
	print("infantry pipeline self-test")

	# ── 1. the clip library ────────────────────────────────────────
	var lib_scene := _instance(LIB)
	_note(lib_scene != null, "clip library loads")
	if lib_scene == null:
		_finish()
		return
	add_child(lib_scene)
	var lib_ap := _find(lib_scene, "AnimationPlayer") as AnimationPlayer
	_note(lib_ap != null, "clip library carries an AnimationPlayer")
	if lib_ap == null:
		_finish()
		return

	var clip_names := lib_ap.get_animation_list()
	_note(clip_names.size() >= 11,
		"library holds %d clip(s): %s" % [clip_names.size(),
			", ".join(PackedStringArray(clip_names)).substr(0, 90)])

	# the four locomotion cycles are the ones that carry the contract
	for want in ["walk", "walk_crouch", "run", "sprint"]:
		var found := false
		for c in clip_names:
			if String(c).ends_with(want):
				found = true
		_note(found, "locomotion clip present: " + want)

	var lib_skel := _find(lib_scene, "Skeleton3D") as Skeleton3D
	_note(lib_skel != null and lib_skel.get_bone_count() == 20,
		"library skeleton has 20 bones (got %d)" %
		[0 if lib_skel == null else lib_skel.get_bone_count()])

	# ── 2. the reference-speed contract ────────────────────────────
	var clips_json := {}
	var f := FileAccess.open(ASSETS + "clips.json", FileAccess.READ)
	if f != null:
		var parsed = JSON.parse_string(f.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY:
			clips_json = parsed
	_note(not clips_json.is_empty(), "clips.json readable by the engine")
	for want in ["walk", "run", "sprint"]:
		var e = clips_json.get(want, {})
		var spd := float(e.get("speed", 0.0)) if typeof(e) == TYPE_DICTIONARY else 0.0
		_note(spd > 0.1,
			"%s publishes a reference speed (%.2f m/s)" % [want, spd])
	# rate = unit_speed / clip_speed. Confirm the arithmetic the game will do.
	var walk_ref := float((clips_json.get("walk", {}) as Dictionary).get("speed", 0.0))
	if walk_ref > 0.0:
		var rate := 1.9 / walk_ref
		_note(rate > 1.0 and rate < 2.5,
			"a 1.9 m/s unit plays walk at rate %.3f" % rate)

	# ── 3. variants: geometry, skin, and no embedded animation ─────
	var all_variants: Array = []
	all_variants.append_array(ERA_LADDER)
	all_variants.append_array(FACTION_ROW)
	all_variants.append_array(ROLES)
	var seen := {}
	var checked := 0
	for name in all_variants:
		if seen.has(name):
			continue
		seen[name] = true
		var inst := _instance(String(name) + "_LOD0")
		if inst == null:
			_note(false, "%s missing" % name)
			continue
		add_child(inst)
		var skel := _find(inst, "Skeleton3D") as Skeleton3D
		var mesh := _find(inst, "MeshInstance3D") as MeshInstance3D
		var ap := _find(inst, "AnimationPlayer") as AnimationPlayer
		var ok := skel != null and skel.get_bone_count() == 20
		ok = ok and mesh != null and mesh.skin != null
		# a variant must NOT carry its own clips - that is the whole saving
		ok = ok and (ap == null or ap.get_animation_list().is_empty())
		if not ok:
			_note(false, "%s: bones=%d mesh=%s skin=%s clips=%d" % [
				name, 0 if skel == null else skel.get_bone_count(),
				mesh != null, mesh != null and mesh.skin != null,
				0 if ap == null else ap.get_animation_list().size()])
			inst.queue_free()
			continue
		# Scale: measure the SKELETON, not the mesh bounding box. The AABB
		# includes whatever the soldier is carrying, and it is measured in
		# BIND pose where a hand-held object sits at a steep angle — a MANPADS
		# launcher made a 1.8 m soldier measure 2.26 m. The skeleton is the
		# soldier; the AABB is the soldier plus its equipment.
		var top := 0.0
		for b in skel.get_bone_count():
			top = maxf(top, skel.get_bone_global_pose(b).origin.y)
		if absf(top - HEAD_JOINT_Y) > H_TOL:
			_note(false, "%s highest joint is %.2f m, expected %.2f"
				% [name, top, HEAD_JOINT_Y])
		else:
			checked += 1
		# the AABB still matters for culling, so flag anything absurd
		var aabb := mesh.get_aabb()
		if aabb.size.y > 3.0 or aabb.size.y < 1.0:
			_note(false, "%s bind-pose AABB is %.2f m tall" % [name, aabb.size.y])
		inst.queue_free()
	_note(checked == seen.size(),
		"%d/%d variants: 20 bones, skinned, no embedded clips, correct scale"
			% [checked, seen.size()])

	# ── 4. the actual bet: library drives a variant ────────────────
	var subject := _instance("inf_e6_us_rifle_LOD0")
	if subject != null:
		add_child(subject)
		var skel := _find(subject, "Skeleton3D") as Skeleton3D
		var ap := AnimationPlayer.new()
		subject.add_child(ap)
		ap.root_node = ap.get_path_to(subject)
		var bound := 0
		for libname in lib_ap.get_animation_library_list():
			var al := lib_ap.get_animation_library(libname)
			if al != null:
				ap.add_animation_library("shared" if libname == "" else libname, al)
				bound += al.get_animation_list().size()
		_note(bound >= 11, "bound %d shared clip(s) onto a variant" % bound)

		var target := ""
		for c in ap.get_animation_list():
			if String(c).ends_with("walk"):
				target = String(c)
		_note(target != "", "found walk on the variant's player")
		if target != "" and skel != null:
			var idx := skel.find_bone("thigh_l")
			_note(idx >= 0, "variant exposes bone thigh_l")
			if idx >= 0:
				var anim := ap.get_animation(target)
				# do the tracks actually resolve against THIS scene graph?
				var resolved := 0
				for t in anim.get_track_count():
					var p := anim.track_get_path(t)
					if subject.get_node_or_null(NodePath(p.get_concatenated_names())) != null:
						resolved += 1
				_note(resolved > 0,
					"%d/%d tracks resolve against the variant's node paths"
						% [resolved, anim.get_track_count()])

				var rest := skel.get_bone_pose_rotation(idx)
				ap.play(target)
				ap.seek(anim.length * 0.35, true)
				ap.advance(0.0)
				var posed := skel.get_bone_pose_rotation(idx)
				var moved: float = rest.angle_to(posed)
				_note(moved > 0.02,
					"walk actually rotates thigh_l by %.1f degrees" %
					rad_to_deg(moved))
		subject.queue_free()

	_finish()


func _finish() -> void:
	for l in _lines:
		print(l)
	print("\n%d passed, %d failed" % [_pass, _fail])
	print("PASS" if _fail == 0 else "FAIL")
	get_tree().quit(0 if _fail == 0 else 1)
