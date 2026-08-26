class_name SimArmorScheme
extends RefCounted
## docs/03's generational ladder, as numbers a unit can actually be built with.
##
## SimArmor fixes what an ArmorType MEANS. SimEntities stores five facets per
## unit. Until this file existed there was nothing in the repository that said
## what a 1955 tank or a 2015 tank actually carries, so the cliff could be
## reasoned about but never fought.
##
## Every number below is derived from docs/03's ladder table, not invented:
##
##   Gen | Era        | Typical armour              | Frontal RHAe (KE) | Pen @2km
##   ----|------------|-----------------------------|-------------------|---------
##   1   | 1950s      | Cast / RHA                  | ~200 mm           | ~180 mm
##   2   | 1960s      | RHA + spaced                | ~320 mm           | ~280 mm
##   3   | 1970s-80s  | Composite                   | ~400 mm           | ~400 mm
##   3.5 | late 80s-90| Composite + heavy metal, ERA| ~620 mm           | ~550 mm
##   4   | 2000s-10s  | Modular composite, heavy ERA| ~800 mm           | ~700 mm
##   5   | 2020s+     | Modular + hard-kill APS     | ~900 mm           | ~750 mm
##
## The table quotes EFFECTIVE frontal protection (RHAe). SimEntities stores
## BASE line-of-sight thickness, and SimArmor multiplies it by the type's
## effectiveness. So the base numbers here are the docs figures DIVIDED by the
## KE column of the matrix -- which is why a Gen 3 tank stores 308 mm of
## composite and not 400 mm. Get that backwards and every composite vehicle in
## the game is 30% too tough.

enum Gen { G1 = 1, G2 = 2, G3 = 3, G3_5 = 4, G4 = 5, G5 = 6 }

## [facet_mm x 5, facet_type x 5, structure_max].
## Facets are FRONT, SIDE, REAR, TOP, BELLY in SimTypes.Facet order.
##
## The side/rear/top numbers come from docs/03's worked example, which quotes a
## Gen 3.5 tank at ~80-100 mm side hull, ~50 mm rear and ~30-50 mm roof. Those
## barely move across seven decades, and that is the point: "every tank's roof
## is thin, in every generation -- the weight simply cannot go there."
const LADDER := {
	Gen.G1: {
		"mm": [210.0, 45.0, 40.0, 20.0, 15.0],
		"type": [SimTypes.ArmorType.CAST, SimTypes.ArmorType.RHA,
			SimTypes.ArmorType.RHA, SimTypes.ArmorType.RHA, SimTypes.ArmorType.RHA],
		"structure": 100.0, "blowout": false, "era": "1950s",
	},
	Gen.G2: {
		"mm": [291.0, 70.0, 45.0, 25.0, 18.0],
		"type": [SimTypes.ArmorType.SPACED, SimTypes.ArmorType.RHA,
			SimTypes.ArmorType.RHA, SimTypes.ArmorType.RHA, SimTypes.ArmorType.RHA],
		"structure": 110.0, "blowout": false, "era": "1960s",
	},
	Gen.G3: {
		"mm": [308.0, 80.0, 45.0, 30.0, 20.0],
		"type": [SimTypes.ArmorType.COMPOSITE, SimTypes.ArmorType.RHA,
			SimTypes.ArmorType.RHA, SimTypes.ArmorType.RHA, SimTypes.ArmorType.RHA],
		"structure": 120.0, "blowout": false, "era": "1970s-80s",
	},
	Gen.G3_5: {
		"mm": [388.0, 90.0, 50.0, 40.0, 25.0],
		"type": [SimTypes.ArmorType.COMPOSITE_HEAVY, SimTypes.ArmorType.RHA,
			SimTypes.ArmorType.RHA, SimTypes.ArmorType.RHA, SimTypes.ArmorType.RHA],
		"structure": 130.0, "blowout": true, "era": "late 80s-90s",
	},
	Gen.G4: {
		"mm": [457.0, 110.0, 55.0, 45.0, 30.0],
		"type": [SimTypes.ArmorType.MODULAR_ERA, SimTypes.ArmorType.ERA_LIGHT,
			SimTypes.ArmorType.RHA, SimTypes.ArmorType.RHA, SimTypes.ArmorType.RHA],
		"structure": 140.0, "blowout": true, "era": "2000s-10s",
	},
	Gen.G5: {
		"mm": [514.0, 130.0, 60.0, 55.0, 40.0],
		"type": [SimTypes.ArmorType.MODULAR_ERA, SimTypes.ArmorType.ERA_HEAVY,
			SimTypes.ArmorType.RHA, SimTypes.ArmorType.RHA, SimTypes.ArmorType.RHA],
		"structure": 150.0, "blowout": true, "era": "2020s+",
	},
}

## The gun each generation carries, as docs/03's "Penetration at 2 km" column.
## docs/03 is emphatic that this belongs to the ROUND and not to the tank --
## "the same 120 mm tube fired ~350 mm rounds in 1979 and ~750 mm rounds in
## 2003" -- so these are ammunition entries that happen to be indexed by the
## generation that first fielded them, and nothing stops a Gen 3 hull firing a
## Gen 4 round once docs/11's ammunition ladder is researched.
const GUNS := {
	Gen.G1: {"name": "90mm APCR", "pen": 180.0, "mv": 900.0},
	Gen.G2: {"name": "105mm APDS", "pen": 280.0, "mv": 1400.0},
	Gen.G3: {"name": "105mm APFSDS", "pen": 400.0, "mv": 1600.0},
	Gen.G3_5: {"name": "120mm DU rod", "pen": 550.0, "mv": 1700.0},
	Gen.G4: {"name": "120mm APFSDS", "pen": 700.0, "mv": 1750.0},
	Gen.G5: {"name": "130mm APFSDS", "pen": 750.0, "mv": 1800.0},
}

## Muzzle velocity matters twice over: it sets how fast the round arrives and
## how STEEPLY its penetration falls off (SimArmor.ke_retention). A 900 m/s
## APCR loses its advantage in a few hundred metres; a 1750 m/s long rod barely
## notices two kilometres. Same curve, opposite feel.


## Give unit `i` the armour of a generation. Called by whoever spawns the unit
## -- the ownership table says armour is set once at spawn and never touched
## again, so this must not be called from the damage slot.
##
## armor_class is set to the generation, which is how the resolver later
## recovers whether the vehicle has blowout panels without SimEntities needing
## a field for it.
static func apply(entities: SimEntities, i: int, gen: int) -> void:
	var row: Dictionary = LADDER.get(gen, LADDER[Gen.G1])
	entities.set_damage_profile(i, SimTypes.DamageModel.ARMORED,
		row["structure"], row["mm"], row["type"], gen)


## docs/03: catastrophic loss is "far likelier without blowout panels -- a real
## generational difference worth modelling."
##
## This reads the generation back out of armor_class, which is a COARSE proxy
## and is honest about being one: blowout panels are really a design decision
## per vehicle, not per epoch, and docs/11 notes that a carousel autoloader
## structurally prevents them regardless of how modern the tank is. When unit
## data files exist this should become a per-unit flag; until they do, "Gen 3.5
## and later stows its ammunition behind panels" is the right default and the
## resolver accepts a per-unit override for the vehicles it is wrong about.
static func default_blowout(armor_class: int) -> bool:
	var row: Dictionary = LADDER.get(armor_class, {})
	return row.get("blowout", false)


## A tank round for a generation, ready to hand to SimMunitions.fire().
## Tier B: ballistic, unguided, contact-fuzed, and it must be aimed above the
## target because gravity acts on it -- SimMunitions._ballistic_aim_y handles
## that, which is why these arrive at all.
static func make_gun_round(gen: int) -> SimMunitionDef:
	var g: Dictionary = GUNS.get(gen, GUNS[Gen.G1])
	return SimMunitionDef.new({
		"name": g["name"],
		"tier": SimMunitionDef.Tier.B,
		"guidance": SimTypes.Guidance.UNGUIDED,
		"fuze": SimMunitionDef.Fuze.CONTACT,
		"muzzle_velocity": g["mv"],
		"max_speed": g["mv"],
		"launch_speed": g["mv"],
		"max_flight_seconds": 20.0,
		"damage_class": SimTypes.DamageClass.KE,
		"penetration_mm": g["pen"],
	})


## The escape valve docs/03 builds in deliberately: "a modern top-attack ATGM
## carried by cheap infantry kills any MBT ever built." Tandem, so ERA does not
## save the target either, and CE so range does not blunt it.
static func make_top_attack_atgm() -> SimMunitionDef:
	return SimMunitionDef.new({
		"name": "TopATGM",
		"tier": SimMunitionDef.Tier.A,
		"guidance": SimTypes.Guidance.IR_EO,
		"fuze": SimMunitionDef.Fuze.CONTACT,
		"boost_seconds": 1.5, "sustain_seconds": 4.0,
		"boost_accel": 120.0, "sustain_accel": 20.0,
		"launch_speed": 40.0, "max_speed": 250.0,
		"max_flight_seconds": 40.0,
		"damage_class": SimTypes.DamageClass.CE,
		"penetration_mm": 900.0, "tandem": true,
	})


static func generation_name(gen: int) -> String:
	match gen:
		Gen.G1: return "Gen 1"
		Gen.G2: return "Gen 2"
		Gen.G3: return "Gen 3"
		Gen.G3_5: return "Gen 3.5"
		Gen.G4: return "Gen 4"
		Gen.G5: return "Gen 5"
	return "unrated"


## Effective frontal protection against a damage class, in RHAe millimetres.
## The number docs/03's ladder table quotes, recomputed from what is actually
## stored so the two can never drift apart.
static func frontal_rhae(gen: int, damage_class := SimTypes.DamageClass.KE) -> float:
	var row: Dictionary = LADDER.get(gen, LADDER[Gen.G1])
	return SimArmor.effective_mm(row["mm"][SimTypes.Facet.FRONT],
		row["type"][SimTypes.Facet.FRONT], damage_class)
