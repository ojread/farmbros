extends Node
class_name WanderBrain
## Server-only AI. Wanders: pick a nearby spot, walk there, pause, repeat.
## After being fed (see follow()), trails behind a player for a while instead.
## Clients never run this; they just receive the paths the server sends, plus
## the `following` flag so they can show a heart.

signal following_changed

@export var walker: PathWalker
@export var radius := 256.0     # global pixels (the world is scaled 4x)
@export var min_pause := 2.0
@export var max_pause := 6.0

## True while following someone. Replicated to clients.
@export var following := false:
	set(value):
		if following == value:
			return
		following = value
		following_changed.emit()

# All distances are global pixels (one tile is 64).
const MAX_FOLLOW_SEC := 120.0
## Closer than this to the leader, the animal stays put.
const FOLLOW_STOP_DIST := 112.0
## When it does move, it aims for a spot this far from the leader.
const FOLLOW_STAND_OFF := 64.0
const FOLLOW_REPATH_SEC := 0.5

var _home := Vector2.ZERO
var _pause_left := 0.0

var _leader: Node2D
var _follow_left := 0.0
var _repath_left := 0.0


func _ready() -> void:
	if not multiplayer.is_server():
		set_process(false)
		return

	_home = walker.body.global_position
	_pause_left = randf_range(0.0, max_pause)  # Stagger so herds don't sync up.


## Server only. Trail `leader` for `seconds` (adds to any time already left).
func follow(leader: Node2D, seconds: float) -> void:
	_leader = leader
	_follow_left = minf(_follow_left + seconds, MAX_FOLLOW_SEC)
	_repath_left = 0.0
	following = true


func _process(delta: float) -> void:
	if following:
		_follow(delta)
		return

	if walker.is_walking():
		return

	_pause_left -= delta
	if _pause_left > 0.0:
		return

	_pause_left = randf_range(min_pause, max_pause)

	var offset := Vector2.from_angle(randf() * TAU) \
			* randf_range(radius * 0.25, radius)
	walker.walk_to(_home + offset)


func _follow(delta: float) -> void:
	_follow_left -= delta

	# Lose interest if time is up, the leader left, or they went to another area.
	var world := walker.world
	if _follow_left <= 0.0 or not is_instance_valid(_leader) \
			or _leader.is_queued_for_deletion() \
			or world.area_at(_leader.global_position) != world.area_at(walker.body.global_position):
		_stop_following()
		return

	_repath_left -= delta
	if _repath_left > 0.0:
		return
	_repath_left = FOLLOW_REPATH_SEC

	var here := walker.body.global_position
	var there := _leader.global_position
	if here.distance_to(there) <= FOLLOW_STOP_DIST:
		if walker.is_walking():
			walker.stop()
		return

	walker.walk_to(there + (here - there).limit_length(FOLLOW_STAND_OFF))


func _stop_following() -> void:
	_leader = null
	_follow_left = 0.0
	following = false
	if walker.is_walking():
		walker.stop()
	# Wander around wherever we ended up, not the old spot.
	_home = walker.body.global_position
	_pause_left = randf_range(min_pause, max_pause)
