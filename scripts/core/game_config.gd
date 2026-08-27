extends Node
## Central configuration for Mass.
##
## Single place to tune the simulation. Nothing here contains logic: other
## systems read these values, this node never reads theirs.
##
## Values marked "restart-scoped" are consumed when the world and the bots are
## built, so changing them takes effect on the next restart, not immediately.

# --- Scale --------------------------------------------------------------------

## Reference points: 100 debug, 1000 development, 5000 stress test, 10000 target.
## Sitting at the development figure while the slice is still being built; the
## target is 10000 and the project has been measured there.
const DEFAULT_BOT_COUNT := 1000
const MIN_BOT_COUNT := 1
const MAX_BOT_COUNT := 100000

## Seed for the island and for the initial simulation state. The same seed must
## always produce the same map and the same starting layout.
const DEFAULT_MAP_SEED := 20260826

# --- World --------------------------------------------------------------------

## Side of the square world in metres. The island is inscribed in it.
const MAP_SIZE := 1024.0

## Heightmap grid is HEIGHTMAP_RESOLUTION x HEIGHTMAP_RESOLUTION samples.
const HEIGHTMAP_RESOLUTION := 256

## Terrain at or below this height is water, above it is land.
const WATER_LEVEL := 0.0

## Peak terrain height in metres above water level. Sixty on a 1024 m island is
## a four percent grade: measurably a hill and visually a pancake. The crowd
## needs somewhere to run to that reads as high ground from the air.
const TERRAIN_HEIGHT := 140.0

# --- Simulation timing --------------------------------------------------------

## Fixed simulation rate. Rendering runs at free FPS, independent of this.
const SIMULATION_TICK_HZ := 20.0
const SIMULATION_TICK_SECONDS := 1.0 / SIMULATION_TICK_HZ

## AI decisions are spread across this many ticks: on tick t only bots with
## i % AI_BUCKET_COUNT == t % AI_BUCKET_COUNT re-decide. Same average cost,
## no per-tick spike.
const AI_BUCKET_COUNT := 8

## Spiral-of-death guard: never run more ticks than this in a single frame, no
## matter how far behind the accumulator has fallen.
const MAX_TICKS_PER_FRAME := 4

const DEFAULT_SIM_SPEED := 1.0
const MIN_SIM_SPEED := 0.0
const MAX_SIM_SPEED := 8.0

# --- Bots ---------------------------------------------------------------------

const BOT_MOVE_SPEED := 3.5       ## metres per second
const BOT_SPEED_VARIATION := 0.3  ## +/- fraction, so bots do not move in lockstep
const BOT_ARRIVAL_RADIUS := 2.0   ## distance at which a target counts as reached
const BOT_MAX_HEALTH := 100.0

## How close two bots may get before they push each other apart. Roughly the
## width of a knight, so they crowd rather than overlap.
const SEPARATION_RADIUS := 1.3

## Share of an overlap each of the two bots gives up per tick. At 0.5 a pair
## resolves in a single pass; lower is softer but leaves them touching longer.
const SEPARATION_RELAXATION := 0.5

## Visual size of one bot, in metres. Deliberately larger than a person: these
## are toy figurines on a 1024 m island, and at human scale they disappear.
const BOT_HEIGHT := 2.4
const BOT_RADIUS := 0.33

# --- Teams --------------------------------------------------------------------

## Chosen to stay apart from each other and from the island when seen from
## altitude, which is the distance the crowd is mostly viewed at.
const TEAM_COLORS := [
	Color(0.898, 0.282, 0.302),  ## red
	Color(0.271, 0.576, 0.898),  ## blue
	Color(0.298, 0.686, 0.314),  ## green
	Color(0.961, 0.651, 0.137),  ## yellow
	Color(0.639, 0.353, 0.827),  ## purple
]

# --- Restart-scoped runtime values --------------------------------------------

## Written by the debug UI, read when the simulation is rebuilt. Both setters
## clamp and warn instead of failing silently on nonsense input.

var bot_count := DEFAULT_BOT_COUNT:
	set(value):
		if value < MIN_BOT_COUNT or value > MAX_BOT_COUNT:
			push_warning("GameConfig: bot_count %d out of range [%d, %d], clamped."
				% [value, MIN_BOT_COUNT, MAX_BOT_COUNT])
		bot_count = clampi(value, MIN_BOT_COUNT, MAX_BOT_COUNT)

var map_seed := DEFAULT_MAP_SEED

func team_count() -> int:
	return TEAM_COLORS.size()

func reset_to_defaults() -> void:
	bot_count = DEFAULT_BOT_COUNT
	map_seed = DEFAULT_MAP_SEED
