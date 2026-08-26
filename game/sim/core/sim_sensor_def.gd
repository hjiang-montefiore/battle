class_name SimSensorDef
extends RefCounted
## One sensor mounted on one unit. docs/02 §2.

var domain: int = SimTypes.Domain.RF_ACTIVE
var band: int = SimTypes.Band.X
var reference_range_km: float = 100.0  ## range vs a 1 m^2 target, unjammed
## Decisive. An E-3 is not a special unit type -- it is a radar with a very
## large mount_height, and the horizon formula does the rest (docs/02 §4).
## A NEGATIVE value means the transducer is streamed below the thermocline:
## towed array, variable-depth sonar, or a helicopter's dipping sonar.
var mount_height_m: float = 10.0
var fov_deg: float = 360.0
var revisit_seconds: float = 0.0       ## 0 = every solve; >0 staggers it
var eccm_rating: int = 0               ## 0-5, rises by epoch, offsets jamming
var emits: bool = true                 ## if true, using it makes you detectable

## The quiet workhorse of the whole design. A long-range search radar can FIND
## things but never GUIDE a missile; that needs a separate fire-control set.
## This one field is why real SAM batteries are several vehicles, and it hands
## the player a target priority the game never has to explain:
## kill the illuminator, not the search radar.
var max_quality: int = SimTypes.TrackQuality.TRACK

var name: String = "sensor"
var radar_gen: int = 3                 ## R-ladder position, docs/11 §3
var esm_gen: int = 3                   ## P-ladder position, docs/11 §7
var aew_gen: int = 3                   ## A-ladder position, docs/11 §4
var phase_offset: int = 0              ## staggers the solve across ticks


func _init(p: Dictionary = {}) -> void:
	for k in p.keys():
		if k in self:
			set(k, p[k])


func is_passive() -> bool:
	return domain == SimTypes.Domain.RF_PASSIVE \
		or domain == SimTypes.Domain.ACOUSTIC_PASSIVE \
		or domain == SimTypes.Domain.IR \
		or domain == SimTypes.Domain.EO \
		or domain == SimTypes.Domain.MAGNETIC


## Two-way propagation applies only to sensors that transmit and then listen for
## their own reflection.
func is_two_way() -> bool:
	return domain == SimTypes.Domain.RF_ACTIVE \
		or domain == SimTypes.Domain.ACOUSTIC_ACTIVE


## A single passive array gives a bearing and nothing else, whatever its
## max_quality claims. Turning that into a firing solution needs target motion
## analysis or a second platform triangulating -- which is exactly why hunting a
## submarine is slow, tense and cooperative (docs/02 §8.1).
func is_bearing_only() -> bool:
	return domain == SimTypes.Domain.RF_PASSIVE \
		or domain == SimTypes.Domain.ACOUSTIC_PASSIVE \
		or domain == SimTypes.Domain.MAGNETIC


## Streamed below the thermocline?
func is_below_layer() -> bool:
	return mount_height_m < 0.0
