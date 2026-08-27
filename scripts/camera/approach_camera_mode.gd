class_name ApproachCameraMode
extends CameraMode
## A one-shot cinematic flight to a target: not steered, just played. Wheel
## and mouse do nothing here — Orbit and FPV Drone are the modes for a hand
## on the stick; this one is for a director's cut.
##
## The path is a fixed quadratic Bezier computed once in enter(), not
## recomputed as the target moves: a spline is a shape in space, and
## re-deriving it every frame from a moving target would mean the "curve"
## keeps warping under the camera instead of being a curve at all. What does
## track the target live is where the camera *looks* while flying the fixed
## path — the position is a dolly on a physical track, the head on top of it
## is free to pan.
##
## Easing lives entirely in how time maps to progress along that path
## (smoothstep, the standard ease-in-ease-out S-curve), not in a separate
## velocity model — the acceleration and deceleration the TODO item asks for
## are exactly what a slow-fast-slow reparameterisation of a fixed curve
## already gives for free.

## How far from the target the flight ends, and how high above it — a flat
## dead-on framing reads worse than a slightly raised, slightly offset one.
const APPROACH_DISTANCE := 40.0
const APPROACH_HEIGHT := 12.0

## How much the path bulges upward at its midpoint, as a fraction of the
## straight-line travel distance. Zero would be a straight dash at the
## target; this is what makes it a curve rather than a cut.
const ARC_HEIGHT := 0.35

## Flight duration is sized from distance at this notional speed, then
## clamped: a target ten metres away should not take as long to reach as one
## a kilometre off, but neither should feel rushed or dragged out.
const SPEED_FOR_DURATION := 140.0
const MIN_SECONDS := 2.5
const MAX_SECONDS := 7.0

## Used only when entering with no target resolvable yet, the same fallback
## Orbit uses: a point straight ahead of wherever the switch left the camera.
const FALLBACK_LOOK_DISTANCE := 60.0

var _start := Vector3.ZERO
var _control := Vector3.ZERO
var _end := Vector3.ZERO
var _duration := MIN_SECONDS
var _elapsed := 0.0

## What to look at once the live target stops resolving — the target's last
## known spot, or the fallback point if there was never a target at all.
var _look_fallback := Vector3.ZERO


func id() -> StringName:
	return &"approach"


func enter(rig: CameraRig, from: Transform3D) -> void:
	var resolved: Variant = rig.target().resolve()
	var look_point: Vector3
	if resolved != null:
		look_point = resolved
	else:
		look_point = from.origin + (-from.basis.z) * FALLBACK_LOOK_DISTANCE
	_look_fallback = look_point

	var flat := Vector3(look_point.x - from.origin.x, 0.0, look_point.z - from.origin.z)
	var approach_dir := flat.normalized() if flat.length() > 0.001 else -from.basis.z

	_start = from.origin
	_end = look_point - approach_dir * APPROACH_DISTANCE
	_end.y = look_point.y + APPROACH_HEIGHT

	var travel := _start.distance_to(_end)
	var midpoint := (_start + _end) * 0.5
	_control = midpoint + Vector3(0.0, travel * ARC_HEIGHT, 0.0)

	_duration = clampf(travel / SPEED_FOR_DURATION, MIN_SECONDS, MAX_SECONDS)
	_elapsed = 0.0


func process(delta: float, rig: CameraRig) -> Transform3D:
	_elapsed = minf(_elapsed + delta, _duration)
	var t := _elapsed / _duration if _duration > 0.0 else 1.0
	var position := _bezier(_start, _control, _end, _smoothstep(t))

	var resolved: Variant = rig.target().resolve()
	var look_point: Vector3 = resolved if resolved != null else _look_fallback
	var to_look := look_point - position
	var basis := Basis.looking_at(to_look, Vector3.UP) if to_look.length() > 0.001 else Basis.IDENTITY
	return Transform3D(basis, position)


func wants_mouse_capture() -> bool:
	return false


## True once the flight has covered its full duration and is holding at the
## end of the path. Exists so a future Director can tell "still flying in"
## apart from "arrived and watching".
func is_arrived() -> bool:
	return _elapsed >= _duration


func _bezier(a: Vector3, b: Vector3, c: Vector3, t: float) -> Vector3:
	return a.lerp(b, t).lerp(b.lerp(c, t), t)


func _smoothstep(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)
