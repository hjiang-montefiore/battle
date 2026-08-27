class_name SimFactionData
extends RefCounted
## The researched national rosters in data/factions/<code>.json, resolved onto
## the baseline SimUnitDef. docs/08's faction axis, finally read by the game.
##
## THE SHAPE OF THE DATA. One file per faction code (us uk de fr cn ru tw kp),
## `roles` -> role key -> epoch string ("1".."7") -> entry. An entry records
## the REAL system that fills the role at the epoch it ENTERED service:
## designation, dims_m, mass_t, speed_kmh, road_range_km, crew, and provenance
## (confidence / estimated_fields / basis). Later epochs INHERIT the newest
## entry at or below them, which is how a system that served for thirty years
## is written once. An entry whose designation is null is a researched ABSENCE:
## the nation never fielded the role at that epoch, and the role is not
## buildable -- Taiwan's missing bombers reaching the production panel as a
## gap is the entire point of this file.
##
## THE BASELINE STAYS. Every field the data lacks -- a role a file does not
## cover, an entry without dims, a stat the researcher could not attest --
## falls through to the SimRoster baseline untouched. Missing data degrades to
## the US-flavoured generic, never to zero and never to a crash.
##
## DETERMINISM. Parsed once per faction code into a static cache; every lookup
## after that is a Dictionary index. The one iteration over parsed-JSON keys
## (picking the newest epoch at or below the player's) computes a maximum,
## which no iteration order can change. Model stem resolution walks a SORTED
## stem list with fixed code/epoch preference orders.

const EPOCH_MIN := 1
const EPOCH_MAX := 7

## Faction enum value -> data file code. UKRAINE and JAPAN have no researched
## file yet; they keep the baseline roster (their ART still resolves through
## their lineage below).
const CODES := {
	SimPlayerSetup.Faction.US: "us",
	SimPlayerSetup.Faction.UK: "uk",
	SimPlayerSetup.Faction.GERMANY: "de",
	SimPlayerSetup.Faction.FRANCE: "fr",
	SimPlayerSetup.Faction.PLA: "cn",
	SimPlayerSetup.Faction.RUSSIA: "ru",
	SimPlayerSetup.Faction.ROC: "tw",
	SimPlayerSetup.Faction.KPA: "kp",
}

## Art fallback order per faction: own nation first, then equipment lineage
## (docs/08 -- soviet-derived factions borrow soviet-lineage hulls, never
## western ones), then the US baseline that every role's first model was built
## as. Checked against the FILESYSTEM, not assumed: a parallel workflow is
## adding variant models and whatever is on disk when the def is stamped wins.
const ART_CHAIN := {
	SimPlayerSetup.Faction.US: ["us"],
	SimPlayerSetup.Faction.UK: ["uk", "us"],
	SimPlayerSetup.Faction.GERMANY: ["de", "us"],
	SimPlayerSetup.Faction.FRANCE: ["fr", "us"],
	SimPlayerSetup.Faction.PLA: ["cn", "ru", "us"],
	SimPlayerSetup.Faction.RUSSIA: ["ru", "us"],
	SimPlayerSetup.Faction.ROC: ["tw", "us"],
	SimPlayerSetup.Faction.KPA: ["kp", "ru", "cn", "us"],
	SimPlayerSetup.Faction.UKRAINE: ["ru", "kp", "us"],
	SimPlayerSetup.Faction.JAPAN: ["jp", "us"],
}

## Role -> the US baseline model stem, exactly as the art pipeline names them:
## family_e<epoch>_<code><suffix>. This is skirmish.gd's old MODELS table plus
## the MBT row, moved into the sim so a def can carry its own model and the UI
## keeps exactly one hardcoded thing (the blockout fallback for a missing GLB).
## Faction and epoch variants are derived from these by substitution and then
## verified against the directory listing.
const BASE_STEMS := {
	"mbt": "mbt_e4_us",
	"apc": "afv_e4_us_apc", "ifv": "afv_e4_us_ifv",
	"atgm_carrier": "afv_e4_us_atgm", "light_tank": "afv_e4_us_tankdestroyer",
	"recon_vehicle": "rec_e4_us_recon", "sph": "art_e4_us_sph",
	"mlrs": "art_e4_us_mlrs", "towed_artillery": "art_e4_us_towed",
	"mortar_carrier": "art_e4_us_mortar", "spaag": "aad_e4_us_spaag",
	"shorad_sam": "aad_e4_us_shorad", "long_sam_launcher": "aad_e4_us_longsam",
	"medium_sam_launcher": "sam_e4_us_launcher",
	"search_radar": "rad_e4_us_search", "illuminator": "rad_e4_us_illuminator",
	"counter_battery_radar": "rad_e4_us_counterbty",
	"ground_ew": "ewj_e4_us_jammer", "fuel_truck": "log_e4_us_fueltruck",
	"ammo_truck": "log_e4_us_ammotruck", "command_vehicle": "cmd_e4_us_command",
	"engineer_vehicle": "eng_e4_us_engineer", "repair_vehicle": "eng_e4_us_repair",
	"ballistic_launcher": "msl_e4_us_ballistic",
	"coastal_asm": "msl_e4_us_coastal", "rifle_squad": "inf_e4_us_rifle",
	"at_team": "inf_e6_us_at", "manpads_team": "inf_e6_us_manpads",
	"mortar_team": "inf_e6_us_mortar", "recon_team": "inf_e6_us_recon",
	"special_forces": "inf_e6_us_sf", "engineer_squad": "inf_e6_us_engineer",
}

const UNITS_DIR := "res://assets/units"

## code -> parsed `roles` Dictionary ({} for a missing or unreadable file, so
## a faction without data is a faction on the baseline, not a crash).
static var _rosters: Dictionary = {}
## Sorted stems of every *_LOD0.glb actually present, scanned once.
static var _stems: PackedStringArray = PackedStringArray()
static var _stems_scanned := false


# ═══════════════════════════════════════════════════════════════════════════
# LOOKUP
# ═══════════════════════════════════════════════════════════════════════════

static func code_for(faction: int) -> String:
	return String(CODES.get(faction, ""))


## The researched entry standing for (faction, role) at `epoch`: the entry
## whose entry-epoch is newest without exceeding `epoch` -- the data records a
## system when it ENTERS service and later epochs inherit it. {} when the data
## simply does not cover the case, which means the baseline stands.
static func entry_for(faction: int, role: String, epoch: int) -> Dictionary:
	var code := code_for(faction)
	if code == "":
		return {}
	var roles := _roles_of(code)
	var per_epoch: Variant = roles.get(role)
	if not (per_epoch is Dictionary):
		return {}
	var e: int = clampi(epoch, EPOCH_MIN, EPOCH_MAX)
	var best := -1
	for k in (per_epoch as Dictionary).keys():
		var ke := int(String(k))
		if ke <= e and ke > best:
			best = ke
	if best < 0:
		return {}
	var en: Variant = (per_epoch as Dictionary).get(str(best))
	return en if en is Dictionary else {}


## A researched ABSENCE: the file covers this faction/role/epoch and says the
## nation fielded NOTHING (designation explicitly null). Distinct from a hole
## in the data, which returns false and leaves the baseline buildable.
static func denied(faction: int, role: String, epoch: int) -> bool:
	var en := entry_for(faction, role, epoch)
	if en.is_empty():
		return false
	return en.get("designation") == null


# ═══════════════════════════════════════════════════════════════════════════
# THE OVERLAY
# ═══════════════════════════════════════════════════════════════════════════

## Write the researched figures over a freshly stamped baseline def, IN PLACE.
## Called by SimRoster._stamp() as the last step, so the def the economy caches
## and the AI reads are the same object. Rules:
##
##   * only fields the entry actually attests are touched; everything else
##     keeps the baseline value (missing dims leave the baseline footprint)
##   * attested figures are REAL and therefore not epoch-scaled -- the epoch
##     multipliers exist to fake generational growth the data now provides
##   * road range becomes a tank size at the ALREADY-SCALED cruise burn, so
##     the vehicle's endurance comes out at the researched range. Ground
##     vehicles only: the aircraft convention is combat radius and the ship
##     convention economical-speed range, neither of which divides by the
##     sim's flat-out speed honestly.
static func overlay(d: SimUnitDef, faction: int) -> void:
	var en := entry_for(faction, d.role, d.epoch)
	if en.is_empty():
		return
	var desig: Variant = en.get("designation")
	if not (desig is String) or String(desig) == "":
		return

	var spd := _num(en, "speed_kmh")
	if spd > 0.0:
		d.speed_kmh = spd
	var mass := _num(en, "mass_t")
	if mass > 0.0:
		d.mass_t = mass
	var crew := int(_num(en, "crew"))
	if crew > 0:
		d.crew = crew

	var dims: Variant = en.get("dims_m")
	if dims is Dictionary:
		var l := _num(dims, "len")
		var w := _num(dims, "width")
		var h := _num(dims, "height")
		if l > 0.0:
			d.length_m = l
		if w > 0.0:
			d.width_m = w
		if h > 0.0:
			d.height_m = h
		if maxf(l, w) > 0.0:
			d.footprint_m = maxf(l, w)

	var rng := _num(en, "road_range_km")
	if rng > 0.0:
		d.road_range_km = rng
		if d.category == SimTypes.Category.GROUND and d.fuel_capacity > 0.0 \
				and d.burn_cruise > 0.0 and d.speed_kmh > 0.0:
			d.fuel_capacity = d.burn_cruise * (rng / d.speed_kmh) * 60.0

	_apply_name(d, String(desig))


## The designation becomes the unit's name -- a German player fields a
## "Leopard 2A4", not a "Main Battle Tank". One guard: SimAiRoles classifies
## OWN units by the words of their name (a commander knowing his own army),
## and "S-300PS" carries none of the words "SAM launcher" does. If the bare
## designation would change what the AI believes the unit is FOR, the baseline
## role name rides along after it; if even the combined name misclassifies
## (a designation word colliding with an earlier keyword), the baseline name
## stands and the designation lives in d.designation only. Same skill issue on
## both sides of the screen: the human reads the HUD, the AI reads the words.
static func _apply_name(d: SimUnitDef, desig: String) -> void:
	d.designation = desig
	var spd_ms := d.max_speed_ms()
	var want := SimAiRoles.classify(d.base_name, d.category, d.is_structure, spd_ms)
	if SimAiRoles.classify(desig, d.category, d.is_structure, spd_ms) == want:
		d.name = desig
		return
	var combined := desig + " " + d.base_name
	if SimAiRoles.classify(combined, d.category, d.is_structure, spd_ms) == want:
		d.name = combined


# ═══════════════════════════════════════════════════════════════════════════
# MODELS
# ═══════════════════════════════════════════════════════════════════════════

## The model stem for (role, faction, epoch), resolved against what actually
## exists in res://assets/units: own faction code first, then the lineage
## chain, then the US baseline; within a code, the player's epoch, then older
## art (an old model for a new unit is honest; the reverse is a lie), then
## newer. A candidate matches its exact stem or any variant-suffixed stem
## ("mbt_e4_ru" also claims "mbt_e4_ru_t72"; exact wins, then sorted-first).
## "" for a role the art pipeline has no row for -- the UI's blockout case.
static func model_stem_for(role: String, faction: int, epoch: int) -> String:
	var template := String(BASE_STEMS.get(role, ""))
	if template == "":
		return ""
	var at := template.find("_e")
	var us := template.find("_us")
	if at < 0 or us < 0:
		return template
	var family := template.substr(0, at)
	var suffix := template.substr(us + 3)
	var stems := _asset_stems()
	if stems.is_empty():
		return template
	var chain: Array = ART_CHAIN.get(faction, ["us"])
	for code in chain:
		for ep in _epoch_order(epoch):
			var cand := "%s_e%d_%s%s" % [family, ep, String(code), suffix]
			var found := _find_stem(stems, cand)
			if found != "":
				return found
	return template


## The player's epoch, then downward to 1, then upward to 7.
static func _epoch_order(epoch: int) -> PackedInt32Array:
	var e: int = clampi(epoch, EPOCH_MIN, EPOCH_MAX)
	var out := PackedInt32Array([e])
	for k in range(e - 1, EPOCH_MIN - 1, -1):
		out.append(k)
	for k in range(e + 1, EPOCH_MAX + 1):
		out.append(k)
	return out


static func _find_stem(stems: PackedStringArray, cand: String) -> String:
	if stems.has(cand):
		return cand
	var prefixed := cand + "_"
	for s in stems:
		if String(s).begins_with(prefixed):
			return s
	return ""


static func _asset_stems() -> PackedStringArray:
	if _stems_scanned:
		return _stems
	_stems_scanned = true
	var seen: Dictionary = {}
	var dir := DirAccess.open(UNITS_DIR)
	if dir != null:
		for f in dir.get_files():
			var name := String(f)
			if name.ends_with("_LOD0.glb"):
				seen[name.substr(0, name.length() - 9)] = true
			elif name.ends_with("_LOD0.glb.remap"):
				seen[name.substr(0, name.length() - 15)] = true
	var keys: Array = seen.keys()
	keys.sort()
	_stems = PackedStringArray()
	for k in keys:
		_stems.append(k)
	return _stems


# ═══════════════════════════════════════════════════════════════════════════
# LOADING
# ═══════════════════════════════════════════════════════════════════════════

static func _roles_of(code: String) -> Dictionary:
	var cached: Variant = _rosters.get(code)
	if cached is Dictionary:
		return cached
	var roles := _parse(code)
	_rosters[code] = roles
	return roles


static func _parse(code: String) -> Dictionary:
	var path := (ProjectSettings.globalize_path("res://")
		+ "../data/factions/%s.json" % code).simplify_path()
	if not FileAccess.file_exists(path):
		# An exported build may carry the data inside res:// instead.
		path = "res://data/factions/%s.json" % code
		if not FileAccess.file_exists(path):
			push_warning("SimFactionData: no data for '%s'; baseline roster stands" % code)
			return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_warning("SimFactionData: %s did not parse; baseline roster stands" % path)
		return {}
	var roles: Variant = (parsed as Dictionary).get("roles")
	return roles if roles is Dictionary else {}


static func _num(en: Dictionary, key: String) -> float:
	var v: Variant = en.get(key)
	if v is float or v is int:
		return float(v)
	return 0.0
