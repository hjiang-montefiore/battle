extends SceneTree
## Every produced unit must resolve to the RIGHT model on disk.
##
## Two bugs lived here, both invisible from inside the sim: naval roles had no
## art row at all, so every ship the economy built -- carriers included --
## drew a grey blockout while its GLB sat in game/assets/units; and the stem
## resolver pattern-matched "family_e<ep>_<code><suffix>", which a national
## variant named for its vehicle (afv_e2_ru_btr60, not afv_e2_ru_apc) can
## never satisfy. MBTs were the only faction art the game had ever shown,
## because "mbt_e4_us" is the one baseline whose suffix is empty.

var _pass := 0
var _fail := 0


func _initialize() -> void:
	print("\n  BATTLE -- model stem resolution")
	print("  " + "-".repeat(58))
	var F := SimPlayerSetup.Faction

	# The variants this project actually built, each named for its vehicle.
	_is("a Russian APC is a BTR, not a US carrier hull",
		SimFactionData.model_stem_for("apc", F.RUSSIA, 2), "afv_e2_ru_btr60")
	_is("a Russian IFV is a BMP", 
		SimFactionData.model_stem_for("ifv", F.RUSSIA, 3), "afv_e3_ru_bmp1")
	_is("a Russian SPH is the mid-hull 2S3",
		SimFactionData.model_stem_for("sph", F.RUSSIA, 3), "art_e3_ru_2s3")
	_is("a Russian MLRS is a BM-21 truck",
		SimFactionData.model_stem_for("mlrs", F.RUSSIA, 2), "art_e2_ru_bm21")
	_is("a Russian recon vehicle is a BRDM",
		SimFactionData.model_stem_for("recon_vehicle", F.RUSSIA, 2), "rec_e2_ru_brdm2")
	_is("a Russian long SAM is an S-300 TEL",
		SimFactionData.model_stem_for("long_sam_launcher", F.RUSSIA, 4),
		"sam_e4_ru_s300tel")
	_is("a Russian SPAAG is a ZSU-23",
		SimFactionData.model_stem_for("spaag", F.RUSSIA, 3), "aad_e3_ru_zsu23")
	_is("a Russian destroyer is a Sovremenny",
		SimFactionData.model_stem_for("air_defence_destroyer", F.RUSSIA, 3),
		"nav_e3_ru_sovremenny")
	_is("a Russian submarine is a Kilo",
		SimFactionData.model_stem_for("submarine", F.RUSSIA, 2), "sub_e2_ru_kilo")
	_is("a PLA destroyer is a 052D",
		SimFactionData.model_stem_for("air_defence_destroyer", F.PLA, 6),
		"nav_e6_cn_052d")
	_is("a PLA IFV is a ZBD-04",
		SimFactionData.model_stem_for("ifv", F.PLA, 6), "afv_e6_cn_zbd04")

	# Ships had no row at all. This is the assertion that would have caught it.
	for role in ["carrier", "cruiser", "corvette", "asw_frigate", "patrol_vessel",
			"amphib", "missile_boat", "air_defence_destroyer", "submarine"]:
		var stem: String = SimFactionData.model_stem_for(role, F.US, 4)
		_ok("a US %s resolves to a hull, not a blockout" % role, stem != "", stem)

	# Older art for a newer unit is honest; the reverse would be a lie.
	_is("the KPA at epoch 4 still fields its epoch-2 Chonma",
		SimFactionData.model_stem_for("mbt", F.KPA, 4), "mbt_e2_kp_chonma")

	# The manifest is a claim about the filesystem, and loses to it.
	_ok("a role with no art row resolves to nothing at all",
		SimFactionData.model_stem_for("not_a_real_role", F.US, 4) == "")

	print("  " + "-".repeat(58))
	print("  %d passed, %d FAILED\n" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _is(what: String, got: String, want: String) -> void:
	_ok(what, got == want, "got '%s', want '%s'" % [got, want])


func _ok(what: String, cond: bool, note := "") -> void:
	if cond:
		_pass += 1
		print("    PASS  %s%s" % [what, "  " + note if note != "" else ""])
	else:
		_fail += 1
		print("    FAIL  %s  %s" % [what, note])


func _process(_d: float) -> bool:
	return true
