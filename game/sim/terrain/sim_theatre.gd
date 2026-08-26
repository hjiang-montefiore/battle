class_name SimTheatre
extends RefCounted
## The four theatres from docs/08, as terrain.
##
## Each is built to the real geography at a coarse scale, because the geography
## is what makes the theatre stress the pillars docs/08 says it stresses. The
## Taiwan Strait is 130-180 km of water with a 3.9 km mountain range behind it;
## that single fact is why it exercises AEW, ASW, anti-ship and the fuel clock
## at once, and no amount of tuning reproduces it on a flat plane.
##
## Deterministic: same seed, same terrain, every time (docs/06).

const TAIWAN_STRAIT := "taiwan_strait"
const KOREAN_PENINSULA := "korean_peninsula"
const CENTRAL_EUROPE := "central_europe"
const NORTH_ATLANTIC := "north_atlantic"

const ALL := [TAIWAN_STRAIT, KOREAN_PENINSULA, CENTRAL_EUROPE, NORTH_ATLANTIC]


## docs/08's Theatres table, as data the setup screen can read.
const STRESSES := {
	TAIWAN_STRAIT: "Naval ASW, AEW&C, anti-ship, the fuel clock -- the only theatre that exercises all six pillars at once",
	KOREAN_PENINSULA: "Massed artillery, the generational cliff, tunnels, terrain masking",
	CENTRAL_EUROPE: "SEAD duels, jamming, ERA vs APFSDS, the coalition mechanic, ground logistics",
	NORTH_ATLANTIC: "Submarine warfare, convoy escort, oiler protection",
}


static func build(key: String, seed_value := 20260826) -> SimTerrain:
	var rng := SimRng.new(seed_value)
	match key:
		TAIWAN_STRAIT: return _taiwan_strait(rng)
		KOREAN_PENINSULA: return _korean_peninsula(rng)
		CENTRAL_EUROPE: return _central_europe(rng)
		NORTH_ATLANTIC: return _north_atlantic(rng)
	return SimTerrain.new(64, 64, 1000.0, "flat")


## Mainland coast to the west, ~150 km of strait, then Taiwan with the Central
## Mountain Range down its spine. Yushan is 3952 m and the range runs about
## 270 km, which puts a hard radar shadow over the whole eastern half of the
## island -- the reason an AEW orbit matters here more than anywhere else.
static func _taiwan_strait(rng: SimRng) -> SimTerrain:
	var t := SimTerrain.new(320, 320, 1600.0, "Taiwan Strait")   # 512 x 512 km
	t.fill(40.0)
	# The strait itself, shallow: the Taiwan Strait averages about 60 m, which
	# is why it is poor submarine water and good mine water.
	t.carve_sea_coast(-90000.0, -256000.0, 60000.0, 256000.0, 60.0, rng, 14000.0, 20)
	# Deep water off the east coast -- the Philippine Sea shelf drops away fast.
	t.carve_sea_coast(170000.0, -256000.0, 256000.0, 256000.0, 3000.0, rng, 11000.0, 18)
	# Mainland coastal hills on the western edge.
	t.add_ridge(-210000.0, -200000.0, -190000.0, 200000.0, 900.0, 45000.0)
	# The Central Mountain Range: ~270 km north-south, peaking near 3950 m.
	t.add_ridge(120000.0, -135000.0, 135000.0, 135000.0, 3950.0, 32000.0)
	# The western coastal plain of Taiwan, where everything actually is.
	t.add_ridge(75000.0, -120000.0, 85000.0, 120000.0, 120.0, 22000.0)
	t.add_noise(rng, 140.0, 10)
	return t


## A mountainous spine with the corridors either side of it. The Taebaek range
## runs down the east; the western corridor is the invasion route and the only
## ground a mechanised force can move on, which is what makes massed artillery
## and terrain masking the theatre's signature.
static func _korean_peninsula(rng: SimRng) -> SimTerrain:
	var t := SimTerrain.new(288, 288, 1200.0, "Korean Peninsula")  # 346 x 346 km
	t.fill(60.0)
	t.carve_sea_coast(-173000.0, -173000.0, -95000.0, 173000.0, 50.0, rng, 16000.0, 16)    # Yellow Sea
	t.carve_sea_coast(120000.0, -173000.0, 173000.0, 173000.0, 1500.0, rng, 12000.0, 15)   # Sea of Japan
	# The Taebaek range, close to the eastern coast and steep.
	t.add_ridge(85000.0, -160000.0, 70000.0, 160000.0, 1600.0, 26000.0)
	# The central highlands either side of the DMZ -- the reason the corridors
	# matter, and where counter-battery radar earns its keep.
	t.add_ridge(-20000.0, -30000.0, 60000.0, 20000.0, 1100.0, 20000.0)
	t.add_ridge(-60000.0, 30000.0, 30000.0, 70000.0, 800.0, 18000.0)
	t.add_noise(rng, 220.0, 7)
	return t


## The North German Plain: open, rolling, and the reason this is the theatre
## where the NATO split shows. Low relief means few places to hide from a
## ground radar, so the fight is about emissions rather than about terrain.
static func _central_europe(rng: SimRng) -> SimTerrain:
	var t := SimTerrain.new(320, 320, 1500.0, "Central Europe")   # 480 x 480 km
	t.fill(90.0)
	t.carve_sea_coast(-240000.0, -240000.0, 240000.0, -195000.0, 40.0, rng, 9000.0, 20)   # Baltic
	# The Harz, and the Thuringian forest -- isolated high ground on a plain,
	# which makes them obvious and contested radar sites.
	t.add_ridge(-30000.0, 40000.0, 25000.0, 70000.0, 1140.0, 17000.0)
	t.add_ridge(40000.0, 95000.0, 120000.0, 130000.0, 980.0, 15000.0)
	# A long, low ridge standing in for the Rhine massifs to the west.
	t.add_ridge(-150000.0, -60000.0, -120000.0, 150000.0, 700.0, 25000.0)
	t.add_noise(rng, 90.0, 12)
	return t


## Open ocean with a continental shelf. Nearly all water, which is the point:
## it is the theatre where the layer, the towed array and the torpedo decide
## everything and terrain masking decides nothing.
static func _north_atlantic(rng: SimRng) -> SimTerrain:
	var t := SimTerrain.new(256, 256, 3000.0, "North Atlantic")   # 768 x 768 km
	t.fill(-3800.0)
	# Continental shelf along the eastern edge, and a scatter of islands that
	# make useful sonar and AEW anchors.
	t.carve_sea(-384000.0, -384000.0, 384000.0, 384000.0, 3800.0)
	# The shelf is SHALLOWER than the basin, so it has to be set, not carved.
	t.set_depth(250000.0, -384000.0, 384000.0, 384000.0, 180.0)
	t.add_ridge(320000.0, -120000.0, 360000.0, 140000.0, 400.0, 26000.0)
	t.add_ridge(-260000.0, 40000.0, -230000.0, 120000.0, 650.0, 20000.0)
	# The Mid-Atlantic Ridge, which matters for bottom-bounce and for hiding.
	# A seamount, not a ridge: it rises to ~1500 m below the surface and must
	# not become an island.
	t.add_seamount(-40000.0, -384000.0, 20000.0, 384000.0, 1500.0, 55000.0)
	return t


static func stresses(key: String) -> String:
	return STRESSES.get(key, "")
