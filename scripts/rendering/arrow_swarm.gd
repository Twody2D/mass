class_name ArrowSwarm
extends Node3D
## A small pool of arrows in flight, shared by one boss fight's archers — the
## same "one MultiMesh, not one node per shot" reasoning GroundEjecta already
## uses for its debris, at a scale a few times smaller. Not literal: a real
## archer count can run into the dozens (Monster.MAX_EFFECTIVE_ARCHERS and
## its siblings), and this does not try to draw one arrow per archer per
## shot — whoever calls fire() samples its own attackers (see Monster's own
## note in _sweep()), the same "decoration approximates the real rate, does
## not model every individual" restraint the abstract per-second damage
## itself already leans on.
##
## Each slot flies a straight line from where it fired to wherever the
## target was at that instant — a boss can walk during the half second an
## arrow is in the air, and the arrow does not curve to follow it, the same
## way a real one would not — over FLIGHT_SECONDS, then goes idle (scaled to
## zero, the same "MultiMesh has no per-instance visibility" trick every
## other pooled effect here already uses) until fire() reuses that slot.
##
## Deliberately stays at the world origin and is never repositioned: built
## once by whichever boss owns it and handed to EventManager.adopt_visual()
## through the same on_effect callable GroundEjecta already travels through
## (see Monster._build()), so it lives as a sibling of the boss, not a
## child — a child would inherit the boss's own moving, rotating transform,
## which every position written here already assumes is not happening
## (both endpoints of every arrow are absolute world coordinates).

const SLOT_COUNT := 32
const FLIGHT_SECONDS := 0.55
const LENGTH := 1.6
const RADIUS := 0.045
const COLOR := Color(0.32, 0.22, 0.12)

## Local-space endpoints per slot — this node's own transform never moves,
## so these already are world coordinates.
var _start := PackedVector3Array()
var _end := PackedVector3Array()
var _elapsed := PackedFloat32Array()
var _active := PackedByteArray()
var _next_slot := 0
var _multimesh: MultiMeshInstance3D
## Total shots ever fired, never reset — a public counter that exists only
## so verify_monster.gd (and any other test) can confirm fire() actually ran
## during a fight without reaching into private state, the same reasoning
## CrowdRenderer.tier_report()/VegetationRenderer.placed_positions() already
## exist for.
var _shots_fired := 0


## Builds an empty pool, ready for fire() and adopt_visual(). Built
## synchronously here rather than in _ready() — the same reasoning
## GroundEjecta.create() already follows — so a caller can fire() into it
## the instant it is built, without waiting for it to actually enter the
## tree.
static func create() -> ArrowSwarm:
	var swarm := ArrowSwarm.new()
	swarm._build()
	return swarm


## Launches one arrow from `from` to `to`. Slots are reused round-robin,
## oldest first — cheap, and good enough at this pool size, the same "no
## real allocator" reasoning every other fixed-size pool in this project
## already leans on. At the sampling rates callers actually use this rarely
## has to cut an arrow's flight short to reuse its slot; when it does, one
## arrow jumps to a new trajectory a frame early, not a crash or a leak.
func fire(from: Vector3, to: Vector3) -> void:
	var slot := _next_slot
	_next_slot = (_next_slot + 1) % SLOT_COUNT
	_start[slot] = from
	_end[slot] = to
	_elapsed[slot] = 0.0
	_active[slot] = 1
	_shots_fired += 1


## How many arrows have ever been fired into this pool — see _shots_fired's
## own note.
func shots_fired() -> int:
	return _shots_fired


## How many are in flight right now, for the same testability reason.
func active_count() -> int:
	var n := 0
	for v in _active:
		if v == 1:
			n += 1
	return n


## Advances every arrow currently in flight. Always returns true: like
## Crater, this is decoration that outlives any single shot, not something
## that finishes — it is freed only when the boss that owns it is.
func advance(delta: float) -> bool:
	var mm := _multimesh.multimesh
	for i in SLOT_COUNT:
		if _active[i] == 0:
			continue
		_elapsed[i] += delta
		var t := _elapsed[i] / FLIGHT_SECONDS
		if t >= 1.0:
			_active[i] = 0
			mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
			continue
		var start: Vector3 = _start[i]
		var end: Vector3 = _end[i]
		var pos := start.lerp(end, t)
		mm.set_instance_transform(i, Transform3D(_facing_basis(end - start), pos))
	return true


## A basis whose own Y axis (the way CylinderMesh builds its height) points
## along `dir` — built directly rather than through Basis.looking_at(), which
## assumes -Z is forward and would need an extra 90-degree correction for a
## mesh whose long axis is Y instead.
func _facing_basis(dir: Vector3) -> Basis:
	var y_axis := dir.normalized() if dir.length() > 0.001 else Vector3.UP
	var x_axis := y_axis.cross(Vector3.UP)
	if x_axis.length() < 0.001:
		x_axis = Vector3.RIGHT
	x_axis = x_axis.normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	return Basis(x_axis, y_axis, z_axis)


func _build() -> void:
	_multimesh = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.0
	shaft.bottom_radius = RADIUS
	shaft.height = LENGTH
	shaft.radial_segments = 5
	shaft.rings = 1
	mm.mesh = shaft
	mm.instance_count = SLOT_COUNT
	_multimesh.multimesh = mm
	var material := StandardMaterial3D.new()
	material.albedo_color = COLOR
	material.roughness = 1.0
	_multimesh.material_override = material
	add_child(_multimesh)

	_start.resize(SLOT_COUNT)
	_end.resize(SLOT_COUNT)
	_elapsed.resize(SLOT_COUNT)
	_active.resize(SLOT_COUNT)
	for i in SLOT_COUNT:
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
