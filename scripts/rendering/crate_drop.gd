class_name CrateDrop
extends Node3D
## A supply crate coming down under a parachute. Purely decoration: unlike a
## meteor, where this lands never depends on anything that happens on the way
## down, so nothing about who gets hurt or who runs where needs the fall
## itself to be simulated. See SupplyScramble for the half that touches bots.
##
## Runs on frame time via EventManager's _visuals, which is why it can be this
## simple: it still freezes on pause and rides the speed ladder like every
## other decoration, without needing a place on the simulation clock.

const FALL_SECONDS := 4.0
const DROP_HEIGHT := 90.0
const CRATE_SIZE := 1.6
const CANOPY_RADIUS := 2.6

## How far the crate drifts sideways as it falls, and how fast it swings.
## Dies out towards the ground: a chute drifts in open air, not the instant
## before the load it's carrying stops moving.
const SWAY_AMOUNT := 1.4
const SWAY_SPEED := 1.1

const WOOD_COLOR := Color(0.52, 0.36, 0.2)
const CANOPY_COLOR := Color(0.85, 0.32, 0.22)

var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _elapsed := 0.0
var _previous := Vector3.ZERO
var _current := Vector3.ZERO
var _sway_phase := 0.0


## Builds a crate dropping straight down onto `at`, ready to be adopted as a
## visual. `rng` only staggers the sway, so crates dropped together do not
## swing in lockstep.
static func create(at: Vector3, rng: RandomNumberGenerator) -> CrateDrop:
	var drop := CrateDrop.new()
	drop._to = at
	drop._from = at + Vector3(0.0, DROP_HEIGHT, 0.0)
	drop._sway_phase = rng.randf() * TAU
	drop._build()
	drop._previous = drop._from
	drop._current = drop._from
	drop.position = drop._from
	return drop


## One frame step. Returns false once it has touched down. The crate itself
## is not freed at that point: it stays parented to EventManager as a static
## landed prop, the same way the rest of the world keeps standing after an
## event finishes touching it.
func advance(delta: float) -> bool:
	_elapsed += delta
	var t := _elapsed / FALL_SECONDS
	_previous = _current
	if t >= 1.0:
		_current = _to
		position = _to
		return false

	var sway := sin(_sway_phase + _elapsed * SWAY_SPEED) * SWAY_AMOUNT * (1.0 - t)
	_current = _from.lerp(_to, t) + Vector3(sway, 0.0, 0.0)
	position = _current
	return true


func render(alpha: float) -> void:
	position = _previous.lerp(_current, clampf(alpha, 0.0, 1.0))


func _build() -> void:
	var crate := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * CRATE_SIZE
	crate.mesh = box
	var wood := StandardMaterial3D.new()
	wood.albedo_color = WOOD_COLOR
	wood.roughness = 0.9
	crate.material_override = wood
	add_child(crate)

	var canopy := MeshInstance3D.new()
	var dome := SphereMesh.new()
	dome.radius = CANOPY_RADIUS
	dome.height = CANOPY_RADIUS * 1.2
	dome.radial_segments = 12
	dome.rings = 6
	canopy.mesh = dome
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = CANOPY_COLOR
	cloth.roughness = 1.0
	canopy.material_override = cloth
	# Squashed rather than a full sphere, so it reads as a canopy rather than
	# a balloon tied to the crate.
	canopy.scale = Vector3(1.0, 0.45, 1.0)
	canopy.position = Vector3(0.0, CRATE_SIZE * 1.8, 0.0)
	add_child(canopy)
