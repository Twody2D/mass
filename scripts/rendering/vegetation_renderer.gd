class_name VegetationRenderer
extends Node3D
## Trees scattered across the island's ordinary ground — the answer to
## "there isn't a single tree on this island," a real run's complaint about
## how little there was left to actually point a camera at.
##
## One MultiMeshInstance3D per species, the same reasoning CrowdRenderer's
## own tiers already use: a handful of draw calls for thousands of
## instances instead of a node each. Unlike the crowd, there is no per-tick
## update here at all — trees do not move, so populate() runs once whenever
## the island is (re)generated and nothing touches these buffers again
## until the next rebuild.
##
## Five imported CC0 models (assets/models/trees/, see assets/CREDITS.md),
## not procedural meshes: a convincing tree silhouette out of code-built
## primitives is exactly the kind of job this project's own knights already
## show is expensive to get right, and a ready low-poly, vertex-coloured
## pack already speaks the same visual language BlobMesh does — no texture,
## no lighting model to reconcile.

const MODEL_PATHS := [
	"res://assets/models/trees/Normal_Tree01.fbx",
	"res://assets/models/trees/Normal_Tree02.fbx",
	"res://assets/models/trees/Fir01.fbx",
	"res://assets/models/trees/Fir02.fbx",
	"res://assets/models/trees/Dead_Tree01.fbx",
]

## How many trees the island gets in total, split roughly evenly across the
## five species by nothing more than random choice. Picked to read as an
## actual forest from the camera without asking MultiMesh to draw anything
## it would notice — see verify_vegetation.gd for the measured cost.
const COUNT := 2200
## Generous over COUNT: most samples land outside the band trees are
## allowed in (too low, too high, too close to the volcano) and are simply
## discarded, the same bounded-attempts shape World.random_land_point()
## itself already uses rather than looping until satisfied.
const MAX_ATTEMPTS := COUNT * 8

## Trees grow between the beach and the rocky highlands, expressed as a
## share of TERRAIN_HEIGHT the same way World._ramp_color() bands its own
## palette — this deliberately sits inside the grass/highland range, never
## on sand or on bare rock. No separate volcano check is needed: the
## mountain's own added height (IslandGenerator._volcano_offset()) already
## pushes anywhere partway up its flank above MAX_HEIGHT_SHARE, and a first
## version's extra clearance margin on top of that turned out to exile
## trees to a thin coastal ring instead of letting them cover the island's
## actual ordinary ground.
const MIN_HEIGHT_SHARE := 0.05
const MAX_HEIGHT_SHARE := 0.62

const SCALE_MIN := 0.75
const SCALE_MAX := 1.35

var _tiers: Array[MultiMeshInstance3D] = []
## Every tree's world position, flat across all species — kept alongside
## the MultiMesh buffers rather than read back from them, because
## MultiMesh.get_instance_transform() only reflects what was set once a
## real RenderingServer backend is driving it; headless verify tools get a
## default identity back instead. The same reasoning CrowdRenderer's own
## tier_report()/near_tier_nodes() exist for: state a tool needs has to be
## exposed on its own, not reconstructed by reading the render buffer.
var _placed := PackedVector3Array()


## Scatters (or rescatters, on a restart) trees over the current island.
## Deterministic in `map_seed` alone, the same contract every other seeded
## system here already keeps.
func populate(world: World, map_seed: int) -> void:
	if world == null:
		push_error("VegetationRenderer: needs a world.")
		return
	_ensure_tiers()

	var rng := RandomNumberGenerator.new()
	# A stream of its own, clear of every other system that seeds off
	# map_seed — the same reasoning IslandGenerator's own noise/ridge/coast/
	# volcano streams already follow.
	rng.seed = map_seed + 1729

	var peak := GameConfig.TERRAIN_HEIGHT
	var min_height := peak * MIN_HEIGHT_SHARE
	var max_height := peak * MAX_HEIGHT_SHARE

	var species_count := MODEL_PATHS.size()
	var transforms: Array[Array] = []
	for i in species_count:
		transforms.append([])
	_placed.resize(0)

	var placed := 0
	var attempt := 0
	while placed < COUNT and attempt < MAX_ATTEMPTS:
		attempt += 1
		var point := world.random_land_point(rng)
		var height := world.get_height(point.x, point.y)
		if height < min_height or height > max_height:
			continue

		var species := rng.randi() % species_count
		var tree_scale := rng.randf_range(SCALE_MIN, SCALE_MAX)
		var yaw := rng.randf() * TAU
		var tree_basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * tree_scale)
		var origin := Vector3(point.x, height, point.y)
		(transforms[species] as Array).append(Transform3D(tree_basis, origin))
		_placed.append(origin)
		placed += 1

	for i in species_count:
		var list: Array = transforms[i]
		var mm := _tiers[i].multimesh
		mm.instance_count = list.size()
		for j in list.size():
			mm.set_instance_transform(j, list[j])


## How many trees actually got placed, summed across every species. Used by
## tooling rather than by anything at runtime.
func tree_count() -> int:
	var total := 0
	for tier in _tiers:
		total += tier.multimesh.instance_count
	return total


## Every tree's world position from the last populate() call — see _placed's
## own note on why this exists instead of reading the MultiMesh buffers back.
func placed_positions() -> PackedVector3Array:
	return _placed


func _ensure_tiers() -> void:
	if not _tiers.is_empty():
		return
	for path in MODEL_PATHS:
		var mesh := _load_mesh(path)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = 0

		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		add_child(node)
		_tiers.append(node)


## Pulls the Mesh resource out of an imported scene rather than keeping the
## scene's own node around — MultiMesh wants a Mesh, not a hierarchy, and
## every one of these files is a single mesh under its scene root anyway.
static func _load_mesh(path: String) -> Mesh:
	var packed: PackedScene = load(path)
	var instance: Node3D = packed.instantiate()
	var mesh: Mesh = null
	for child in instance.find_children("*", "MeshInstance3D", true, false):
		mesh = (child as MeshInstance3D).mesh
		break
	instance.free()
	if mesh == null:
		push_error("VegetationRenderer: no mesh found in %s." % path)
	return mesh
