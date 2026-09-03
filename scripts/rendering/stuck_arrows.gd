class_name StuckArrows
extends Node3D
## Permanent arrows left behind by archer fire — "как в Minecraft от скелета":
## one embedded in the ground near a boss that just took ranged damage, one
## left standing in a corpse War's own archers actually killed. A single
## fixed-size ring-buffer pool for the whole session, the same "one MultiMesh,
## not one node per shot" reasoning ArrowSwarm/GroundEjecta already use, just
## never advancing and never freeing a slot on its own — a stuck arrow does
## not fly anywhere, it just sits there until the pool wraps around and
## reuses its slot for a newer one.
##
## Owned once by EventManager (see its own archer_shot()/archer_kill()), not
## per boss fight or per war — arrows from completely different fights share
## the same pool, the same way GameHUD's minimap already shares one dot
## budget across the whole crowd rather than one per event.

## Generous but bounded: a long fight can fire far more shots than this, and
## the oldest arrows are simply overwritten rather than the pool growing —
## the same "cap it, never let a real run's crowd size decide your instance
## count" rule STOMP/MELEE effective-attacker caps already follow.
const SLOT_COUNT := 400
const LENGTH := 1.3
const RADIUS := 0.045
const COLOR := Color(0.32, 0.22, 0.12)

## How far along its own length an arrow is buried — 0 would leave it lying
## flat on the surface with nothing "stuck" about it, 1 would hide it
## entirely. A third in is a fletching-and-shaft-visible arrow, an
## arrowhead-and-tip-invisible one.
const GROUND_EMBED_SHARE := 0.35
const BODY_EMBED_SHARE := 0.4

var _multimesh: MultiMeshInstance3D
var _next_slot := 0
## Total ever stuck, for the same testability reason ArrowSwarm's own
## _shots_fired exists.
var _stuck_total := 0


static func create() -> StuckArrows:
	var arrows := StuckArrows.new()
	arrows._build()
	return arrows


## How many have ever been stuck, in the ground or in a body combined.
func stuck_total() -> int:
	return _stuck_total


## Embeds one near-vertically at `at` (already a real ground point — callers
## pass world.get_height() themselves, this does not know about World), with
## a random lean and yaw so a cluster of them does not read as one arrow
## copy-pasted.
func stick_in_ground(at: Vector3, rng: RandomNumberGenerator) -> void:
	var lean := Vector3(rng.randf_range(-0.35, 0.35), -1.0, rng.randf_range(-0.35, 0.35))
	_place(at, lean, GROUND_EMBED_SHARE)


## Embeds one in a corpse at `at` (a bot's own death position — callers
## already know it, this does not reach into BotManager) — angled outward
## and mostly horizontal, the way an arrow that struck a standing body would
## still be sitting when it fell.
func stick_in_body(at: Vector3, rng: RandomNumberGenerator) -> void:
	var out := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.15, 0.35), rng.randf_range(-1.0, 1.0))
	_place(at + Vector3.UP * 0.9, out, BODY_EMBED_SHARE)


func _place(at: Vector3, direction: Vector3, embed_share: float) -> void:
	var slot := _next_slot
	_next_slot = (_next_slot + 1) % SLOT_COUNT
	_stuck_total += 1
	var dir := direction.normalized() if direction.length() > 0.001 else Vector3.DOWN
	# The arrow's own length runs along the mesh's local Y (see _build()'s
	# CylinderMesh) — offsetting the placement point backward along `dir` by
	# embed_share of the length is what makes the tip disappear into the
	# surface instead of hovering with its point exactly on it.
	var pos := at - dir * (LENGTH * embed_share)
	_multimesh.multimesh.set_instance_transform(slot, Transform3D(_facing_basis(dir), pos))


## Same technique as ArrowSwarm's own _facing_basis() (duplicated, not
## shared — this project's own established rule for small per-file visual
## helpers): a basis whose local Y points along `dir`, since CylinderMesh
## builds its height along Y, not Basis.looking_at()'s -Z.
func _facing_basis(dir: Vector3) -> Basis:
	var y_axis := dir
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

	for i in SLOT_COUNT:
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
