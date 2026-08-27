class_name SimRng
extends RefCounted
## Seeded, replicated PRNG. docs/06: "no randf() outside a seeded PRNG stream."
##
## Godot's global RNG is shared mutable state and reseeds itself; using it
## anywhere in the sim would break replay, bug reproduction and AI regression
## testing. This is a plain xorshift64* so a given seed produces the same
## stream on any machine and any Godot build.

## 0x9E3779B97F4A7C15 does not fit a SIGNED 64-bit integer, which is all
## GDScript has. Written as the equivalent signed decimal so the stream
## matches the usual xorshift64* constants bit for bit.
const GOLDEN := -7046029254386353131   # 0x9E3779B97F4A7C15
const MULT := 0x2545F4914F6CDD1D

var _state: int = MULT


func _init(seed_value: int = GOLDEN) -> void:
	set_seed(seed_value)


func set_seed(seed_value: int) -> void:
	# Never allow a zero state; xorshift would latch at zero forever.
	_state = seed_value if seed_value != 0 else MULT


func next_u64() -> int:
	var x := _state
	x ^= x >> 12
	x ^= x << 25
	x ^= x >> 27
	_state = x
	return x * MULT


## Uniform in [0, 1).
func next_float() -> float:
	# Top 53 bits, so the mantissa is filled without bias.
	var v := (next_u64() >> 11) & 0x1FFFFFFFFFFFFF
	return float(v) / float(1 << 53)


func next_range(lo: float, hi: float) -> float:
	return lo + (hi - lo) * next_float()


## Uniform integer in [lo, hi].
func next_int(lo: int, hi: int) -> int:
	if hi <= lo:
		return lo
	return lo + int(next_float() * float(hi - lo + 1))


## Independent stream derived from this one, so a subsystem can draw without
## perturbing anyone else's sequence -- which is what keeps a replay stable when
## an unrelated system changes how often it rolls.
func fork(salt: int) -> SimRng:
	return SimRng.new(_state ^ (salt * GOLDEN))


func state() -> int:
	return _state


## Restore a previously saved state verbatim. This is NOT set_seed(): a seed is
## scrambled defensively, a saved state must come back bit for bit so the
## stream continues exactly where it left off. The zero guard still applies
## because a zero state would latch the generator forever, and a legitimately
## saved state can never be zero.
func restore_state(saved: int) -> void:
	_state = saved if saved != 0 else MULT
