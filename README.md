# Rose Better Starts

Rose Better Starts is a standalone Civilization VI: Gathering Storm map-generation mod. It does two things while the map is being created:

1. **Start biases are enforced.** When the game chooses where each major civilization starts, the mod makes the civilization's own start bias (the game's `StartBias` tables: Russia and Canada in tundra, Portugal and Phoenicia on the coast, Egypt on floodplains, Mali in desert, and so on) a requirement whenever the map can satisfy it, instead of the stock best-effort matching. The bias tables themselves are not changed.
2. **Strategic resources are guaranteed.** Every major civilization with a land start gets access to all seven strategic resource types within five hexes whenever the generated terrain contains a legal empty plot for them.

The balancing happens once, while the map is being created. The mod has no turn event, gameplay script, UI context, AI change, or post-generation map mutation.

## Start biases

### How the game normally places starts

The engine divides the land into one region per major civilization. The stock script picks the most fertile valid plot of each region, and only then matches civilizations to those plots by bias, tier by tier. A civilization gets its bias only when one of the already-chosen plots happens to satisfy it. Tundra and desert plots are rarely the most fertile plot of a region, so Russia, Canada or Mali usually get an ordinary start. City-states are placed after every major civilization, in regions the engine divides afterwards, and the mod keeps that order.

### What the mod does instead

The mod replaces the two steps that decide that outcome: the plot picked inside each region and the civilization-to-plot matching. Regions, the validity checks a start must pass (water access, passable surroundings, no natural wonder or luxury blocking, the stock distance between civilizations), Balanced and Legendary resources, city-states and ocean starts are the stock code, with one exception: the game rejects a capital with more than two desert tiles among the plot and its six neighbours (one on a Balanced start), so no civilization ever starts inside a desert. For Mali that cap is lifted: a plot that fails only the desert cap stays a candidate that only Mali may take, while every other civilization and the stock fallback keep the game's rule. The placed line shows each start's desert count as `desert`.

- **Tiers.** Each civilization's bias rows come from the game's `StartBiasTerrains`, `StartBiasFeatures`, `StartBiasResources` and `StartBiasRivers` tables, with their tiers (1 strongest, 5 weakest). The civilization's tier-1 and tier-2 rows are **required**, all of them together, whenever at least one region has a valid plot that satisfies them; a tier-3 group is required only when it is the civilization's strongest tier (England, Japan and Norway's coast, the river civilizations, Greece and Korea's hills). If no region can satisfy every required tier, the strongest tier alone is required; if no region can satisfy even that, nothing is enforced and the civilization is placed like one without a bias. Tiers 4 and 5 are never required. In the current game data only Maya has two required tiers: grass or plains around the start and a plantation luxury within two tiles; its tier-3 rows, which list every other land terrain (Firaxis's way of keeping Maya inland), never count. Every tier a plot satisfies adds its weight (5 for tier 1 down to 1 for tier 5) to a preference score, except a tier 3 below a stronger tier, which in the game's data is a fallback terrain list rather than a wish and is neither required nor scored.
- **Satisfaction**, measured within the ranges the stock matching uses (terrain and feature rows within three tiles of the start, resource rows within two, river rows on the start plot; the start plot itself is not counted), with stricter minimums than the stock's single tile. Within a tier, rows of one kind are pooled, so Ethiopia's hills tier counts grass, plains, desert and tundra hills together. A tier's terrain rows need at least 4 matching tiles together, one of them next to the start plot (Mali asks for three adjacent desert tiles first: when it ranks regions, one that offers three adjacent beats one that offers the standard single adjacent tile, and either beats a region with no desert, so it never trades a desert region for an empty one and never loses its place in the order; the log says `enforced=strict` when its region offers three adjacent and `enforced=all` with `level=standard` when only the standard rule could be met there; when spacing blocks every strict plot at pick time, the standard rule decides and the placed line reads `level=standard`; a group of mountains needs no adjacent one, since the stock validity check allows at most one impassable neighbour and none on a Balanced start); its feature rows at least 5, one of them adjacent (1 and no adjacency when the tier lists a geothermal fissure or volcano); its resource rows at least 1; a river row needs the start plot on a river; the `TERRAIN_COAST` row needs the start plot itself next to sea water, so a coastal civilization can build a Harbor at its capital. So Canada and Russia start on the tundra edge, Mali on the desert edge and Vietnam inside its woods, rather than a few tiles away from them. A tier is satisfied when any of its groups reaches its minimums.
- **Order.** Civilizations with enforced tiers are placed first, the one with the fewest satisfying regions before the others, then by strongest tier. Ties are broken by a key derived from the map seed and the player slot, never with a draw from the map generator's random stream, so lobby order alone does not decide. Civilizations without a required tier follow in the same key order. That greedy pass is then repaired by a maximum matching: when a civilization was left without a satisfying region although one could be freed by moving another civilization to a region that also satisfies it, the regions are exchanged (`plan=matched` in the log), so the number of civilizations with a satisfying region is the largest the map allows.
- **Fertility.** The engine's plot fertility, the value the stock pick sorts by, is a single-plot score: twice the plot's Food, Production, Science, Culture and Faith plus its Gold, +2 with fresh water, +1 on a river, +1 per adjacent mountain, +1 next to a natural wonder, +5 for a luxury on the plot, -5 on tundra, and 0 on snow, on mountains and next to ice. The stock pick also applies a region weighting that is 0 near internal region borders (and, through a bug in the engine's border test, for whole regions), so a stock start is the best single tile among whatever plots that weighting leaves. The mod ranks plots by a neighbourhood value instead: the engine's per-plot score summed over the plot and every plot within two tiles, the plot and its first ring at double weight. A start on a grassland river tile surrounded by hills and woods therefore outranks a lone rich tile in the middle of nothing. The single-plot and weighted values are only logged. Three civilizations get yields from the terrain their bias sends them to that the engine's value does not know (it even clamps a tundra tile to 0): Russia (+1 Production and +1 Faith on tundra, counted as the Production alone, since tundra stays weaker for growth than Canada's farmed tundra), Canada (farms on tundra, counted as +1 Food) and Mali (+1 Food and +1 Faith on desert next to the City Center, counted double for a stronger pull toward desert). The mod adds those, in the engine's units, to that civilization's own view of a plot's fertility (the plot and its first ring at double weight; Mali's only next to the centre), so Russia weighs a tundra-ringed plot the way Russia will use it, while every other civilization sees the plain value. The bonus appears as `bonus` on the placed line.
- **Choice.** Among a region's valid plots that meet the enforced tiers (or, when none does, those that meet the most of them), fertility decides first: the plots within 15 percent of the best fertility form a band, and within that band the highest preference score wins, then fertility, then plot index. So Germany gets a river start and Netherlands a coastal one when a nearly-as-good plot offers it, and a preference never pulls a civilization onto a start more than 15 percent below the best it could have had. Each civilization takes the free region whose best such plot ranks highest by enforced tiers met, then the number of satisfying plots in the region (up to four, so one lone plot near a border loses to a region with several), then the region's best fertility, then preference score (the lowest region index on a tie). When the stock loop reaches that region, the civilization gets the best such plot that keeps the stock distance from the starts already placed, the same check the stock pick applies, among the plots the stock loop lists for the region at that moment. When no valid plot keeps that distance, the region gets the stock pick, as it would without the mod.
- **Crowding.** Picks are made region by region, in the stock loop's order, so a pick can leave a later region with no satisfying plot outside the stock buffer; its civilization would then get the stock pick's fallback plot, which fails a validity check (that happened to Brazil in a 2026-10-19 game: 39 valid plots in its region, all within the buffer of five earlier starts). Among a civilization's equally good plots (same level, within the band), one that would leave every other unplaced region some satisfying plot is preferred over one that would box a region in (a region with no satisfying plot left is protected through its remaining valid plots, so it still gets a start of its own); and after the preference score, when a region is down to eight such plots or fewer, one that blocks fewer of them. Otherwise fertility decides within the band as usual. The look-ahead never leaves the band and never overrides a required tier. A region that has no valid plot outside the buffer when its turn comes still gets the stock pick, which applies no look-ahead of its own.
- **Final re-matching.** Once every region has its plot, a civilization whose enforced tiers are unmet at its own plot looks for another picked plot that meets them, by augmenting paths: a civilization gives up its plot only to move to one that also meets its own enforced tiers, or when it has none to meet. The displaced civilizations take the plots left over, best fertility first. The stock script matches this way too, over plots chosen without any bias; here it only repairs what crowding spoiled, and it never reduces the number of satisfied civilizations.

### Limits

- Only land starts of major civilizations. Kupe's ocean start, city-states (apart from the fallback case below) and maps that ask the engine to ignore biases are placed by the stock code. Spectator slots take no region (see "Best-effort limitations").
- A bias is enforced inside the engine's regions: if no region contains a tundra edge with a valid start, no civilization is sent to the tundra. `Lua.log` reports this as `enforced=no`.
- Tiers 4 and 5 (Australia's cattle, Mali's mines, Germany's river) only tilt the choice within the 15 percent fertility band; Niter within two tiles is rare, so the Ottomans' row will seldom find a plot in the band.
- Spacing is the stock rule: each pick keeps the stock distance (more than ten tiles) from the starts already placed, the check the stock pick applies. Because biased picks land elsewhere than the stock picks, a later region can be left without such a plot where an unmodded map would not have been; the crowding look-ahead makes that rare, and when it still happens the stock fallback is used, as without the mod (`mode=BASE` with a `failed_check` in `Lua.log`; `spacing=forced` when even the fallback is within the buffer). The mod adds no minimum distance of its own.
- A region with no valid plot at all (a sliver of polar land, a region of mountains) gets the stock fallback plot whatever civilization holds it; the final re-matching hands such a plot to a civilization with nothing to meet when another picked plot satisfies the one that drew it.
- City-state placement keeps the stock rules, with one exception. When no plot of a city-state's region keeps the stock distance from every civilization (more than six tiles) and from the city-states already placed (more than five), the stock script falls back to the region's most fertile land plot, however close to a capital; in a crowded game that put a city-state one tile from a capital. The mod then takes the region's passable land plot that falls least short of the two distance rules: each plot is scored by how many tiles short it is of the civilization distance and of the city-state distance (a rule it keeps is never short), the worse of the two counts first, then the better, then the civilization side alone, so a plot next to a capital is never traded for one next to a city-state; the stock checks and fertility decide the rest (`RBS_MINOR_FALLBACK` in `Lua.log`). The rule can set a city-state a tile or two nearer a civilization than the stock fallback would, when that keeps it farther from another city-state. A stock pick that keeps both distances is never changed, and the rule applies with or without start biases. City-state positions still differ from an unmodded map with the same seed, because the engine divides their regions around the majors' starts and because the later random draws (the city-state bias shuffle, ley lines, Balanced resources, goody huts) follow different starts; every machine computes the same result.
- No terrain is changed and nothing is added to satisfy a bias. The mod chooses among the plots the map already has.

## Strategic resources

For every human and AI major civilization with a land starting plot, the mod checks for:

- Horses
- Iron
- Niter
- Coal
- Oil
- Aluminum
- Uranium

An existing copy of the resource at a hex distance of five or less satisfies the check. If it is missing, Rose Better Starts places one unit of that resource on a legal empty land plot within the same radius.

Horses and Iron prefer rings two and three. Later strategics prefer rings four and five so they consume fewer early district locations. If those rings contain no legal plot, the remaining rings through five are checked.

Oil is placed on land whenever a legal land plot exists. Existing water Oil already counts. If no land plot qualifies, as on some island or coastal starts, Oil falls back to a legal Coast tile, sea or lake, in rings two through five, using the same ring preference. It never uses a tile directly next to the start, so the capital's own coastline stays free for a Harbor. Offshore Oil needs an Offshore Oil Rig (Plastics) instead of an Oil Well. Base-game generation also places Oil on Coast and lake tiles; unlike base generation, the fallback does not avoid water next to polar ice. Other coastal tiles in rings two and three can still be used, so Harbor space is not guaranteed.

When several legal plots share the best preferred ring, the choice is scattered by a key derived from the map seed, the start, the resource, and the plot. The same map seed always produces the same placements for every player, and no draw is taken from the game's random-number stream, so the rest of map generation is unchanged.

Resources shared by overlapping five-tile areas count for every affected player. That includes a copy that is closer to another civilization or a city-state, which the checked player may never actually own. Strategic resources still obey their normal reveal technologies.

### Interaction with the Start Position setting

The stock **Start Position** setting has **Balanced** and **Legendary** options (Balanced is the multiplayer default; Standard is the single-player default). With either option, Firaxis tries to add each strategic resource revealed within one era of the starting era to a legal tile within three tiles of every start. Its placement is best-effort and is skipped silently when no tile qualifies. Those additions happen while starts are assigned, before Rose Better Starts runs, so they count as existing copies and are not duplicated. With **Standard**, the mod fills in every missing type on its own. In every case it only adds types still missing within five tiles. The **Resources** setting (Sparse/Standard/Abundant) changes how many resources exist before the mod runs.

### Effect on strategic scarcity

Every land-starting major is guaranteed nearby access to all seven strategics, including Oil, Aluminum, and Uranium. This deliberately softens late-game scarcity: resource wars and trade for missing strategics become less common than on an unmodified map. The rest of the map's resource distribution is untouched.

The mod does **not** change:

- The start bias tables, the stock distance rules between starts, or the engine's start regions
- Terrain, hills, features, rivers, natural wonders, yields, or coastlines
- Existing bonus, luxury, or strategic resources
- City-state starts
- Global resource abundance outside the starting areas

## Supported maps

Enabling the mod transparently affects the existing Firaxis map selections; it does not add duplicate `Rose` map entries. Their names, images, and normal setup options remain unchanged.

Gathering Storm maps:

- Continents
- Fractal
- Inland Sea
- Island Plates
- Lakes
- Pangaea
- Seven Seas
- Shuffle
- Small Continents
- Terra
- Continents and Islands
- Primordial
- Splintered Fractal
- Tilted Axis

Additional Firaxis maps are wrapped when their content is installed:

- Archipelago (`Archipelago_XP2.lua`, supplied through Rise and Fall content)
- Highlands (Byzantium & Gaul Pack)
- Wetlands (Portugal Pack)

Both parts of the mod apply to the same maps. Static maps, scenarios, World Builder maps, true-start-location maps, and third-party map scripts are not modified. This includes:

- **Earth, Mediterranean, Europe, and East Asia** (normal and true-start-location versions). These are pre-built map files; the game places their starts itself without calling the start-assignment code this mod hooks.
- **Four-Leaf Clover and Six-Armed Snowflake.** These are pre-built, symmetrical maps with fixed start positions and resources.
- **Mirror.** This one is procedural, but it moves starts to their mirrored positions after the start-assignment step this mod hooks, so balancing would target the wrong tiles. It would also break the map's symmetry.

Supporting pre-built maps would require changing the map after the game has started. The mod avoids that because of the multiplayer desynchronization risk.

A map script that creates its start positions with the engine's `IGNORESTARTBIAS` option keeps the stock placement; the mod then only adds strategic resources.

## Best-effort limitations

The radius is the Civ VI hex distance from the assigned starting plot and is fixed at five.

Resource placement must pass the game's own `ResourceBuilder.CanHaveResource` check. Some unusually constrained islands or polar starts may not contain an empty legal tile for every resource. Oil has the offshore fallback described above; Horses, Iron, Niter, Coal, Aluminum, and Uranium are land-only. In that case, the mod preserves the generated map and writes an `RBS_UNSATISFIED` entry to `Lua.log`. It never replaces another resource, expands the radius, or terraforms a tile to force success.

Spectator slots added by spectator mods (leader `LEADER_SPECTATOR` or civilization `CIVILIZATION_SPECTATOR`) are left out of the land division: the stock script would reserve one region per alive major, spectators included, so a ninth of the map stayed empty around one of its best starts. While the stock script assigns starts, the mod hides spectator slots from its major list (the list is restored afterwards); every spectator then gets the passable land plot (with at least two passable land neighbours) farthest from all starts, logged as `RBS_SPECTATOR`, so its units stand where nobody settles, and the resource normalizer skips it with an `RBS_SKIP ... reason=SPECTATOR` entry. That start plot stays reserved. Every machine sees the same lobby configuration, so all filter the same slots.

Ocean-starting civilizations such as Kupe are deliberately skipped. Resources placed around the initial ocean tile would not reliably be near the civilization's eventual capital, and forcing a land start would change the leader's intended behavior. These starts produce an `RBS_SKIP ... reason=OCEAN_START` log entry.

## Multiplayer design

Rose Better Starts is designed to avoid the runtime synchronization risks found in larger balancing mods:

- All mutations occur inside map generation: start biases while Firaxis assigns starts, strategic resources immediately after and before goody huts are placed.
- Candidate starts, resources, and plots use explicit stable ordering.
- Start-bias placement looks only at the valid plots of each engine region (the stock validity checks, at most 400 plots per region), reads each plot's fertility once, and compares plots with integer distances; the two matchings (regions at planning time, plots at the end) are augmenting-path searches over sorted lists; strategic placement scans only plots within five tiles of each start.
- Ties use the seed-derived key described above, then plot index. The key uses exact integer arithmetic within double precision, so every platform computes identical values. Preference scores are integers.
- The code does not use `math.random`, unordered table traversal for placement, system time, gameplay turn events, or unit/player mutations, and it takes no draw from the map generator's random stream.
- A canonical fingerprint is logged after generation for host/client comparison; it covers the start-bias placement and the resources.

Every multiplayer participant must enable the same Rose Better Starts version and use the same DLC and gameplay-mod set. Civ VI can still desynchronize when players have mismatched files, DLC, mod versions, or load orders; this mod cannot correct those external mismatches.

## Compatibility

Rose Better Starts is independent from Rose AI and may be enabled alongside it.

Do not enable Rose Better Starts together with Better Balanced Starts, Better Balanced Maps, YnAMP balancing components, or another mod that replaces the same Firaxis map scripts or starting-plot assignment. Which map implementation wins would depend on component load order and would make multiplayer results difficult to audit.

Mods that only change the `StartBias` tables (a civilization pack with its own biases, a balance mod that edits them) are compatible: the mod reads whatever those tables hold when the map is generated.

Mods that only change how many resources are generated are compatible. Rose Better Starts does not replace `ResourceGenerator.lua`; it runs after resources are generated and counts whatever is already near each start. For example, More Strategic Resources, which replaces `ResourceGenerator.lua` to add about a third more strategics, has been played alongside it: more starts already have each strategic, so the mod places fewer. In multiplayer every player still needs the identical mod set.

Mods that do not alter map generation or front-end map registration are generally compatible.

## Installation

1. Copy this repository folder into the Civ VI Mods directory, commonly:

   ```text
   %USERPROFILE%\Documents\My Games\Sid Meier's Civilization VI\Mods\Rose Better Starts
   ```

2. Confirm `Rose_Better_Starts.modinfo` is directly inside that folder.
3. Enable **Rose Better Starts** under Additional Content.
4. In multiplayer, install and enable the identical version for every player before creating the lobby.
5. Create a fresh game or lobby. Existing saves are not changed, and a saved setup may require reselecting its map after the redirect is enabled.

The mod requires Gathering Storm. Disabling it restores the original Firaxis map registrations the next time Civ VI rebuilds its configuration database.

## Verifying a generated map

Open:

```text
%LOCALAPPDATA%\Firaxis Games\Sid Meier's Civilization VI\Logs\Lua.log
```

Search for these records:

- `RBS_BIAS_BEGIN` — the start-bias placement ran; `candidates` is the number of valid plots found across all regions.
- `RBS_BIAS_REGION` — one line per engine region: its plot count, how many plots passed the stock validity checks (`candidates`, including the `desert_only` plots that fail only the desert cap and are open to Mali alone) and how many of those the engine's region-weighted fertility rates above 0 (`weighted_positive`).
- `RBS_BIAS` — one line per major civilization: its bias tiers (`tiers=T2:TERRAIN_TUNDRA/TERRAIN_TUNDRA_HILLS,...`), the required tiers (`required=T1+T2`), what was enforced (`enforced=strict` for a civilization whose raised adjacency rule its region meets, `all`, `strongest` when only the strongest tier could be satisfied, `no` when none could), the number of regions that satisfy the enforced tiers (`options`, with `options_strict`, `options_all` and `options_strongest` for each level), its placement order, its region, `plan=greedy` or `matched` (the matching pass moved it) and `level` (`strict` or `standard` for a civilization with a raised adjacency rule, `-` otherwise).
- `RBS_BIAS_PLACED` — the region and plot each civilization received when its region was picked, `satisfied=yes` when its enforced tiers are met there, the preference score, its fertility (`fertility`, the neighbourhood value as that civilization sees it, with `bonus` the civilization tile bonus included in it; `plot_fertility` is the engine's single-plot value and `weighted` its region-weighted value, the one the stock pick sorts by) next to `best_fertility` (the fertility it could have had without its preferences; the difference is the price of the preference, at most the `band` percentage), `satisfying` (how many plots of the region met the same tiers), `boxes` and `damage` (what the chosen plot costs the regions still to be picked: regions left without a satisfying or valid plot, and the blocked share of the remaining plots of regions down to eight or fewer, in thousandths, summed), `candidates` (the region's valid plots at pick time), `failed_check` (for a stock fallback plot, the first stock validity check it fails: `luxury`, `water_access`, `adjacent`, `natural_wonder`, `resource` or `oasis`; `-` otherwise), the mode, `spacing=forced` when the fallback plot is also within the stock distance of another start (the stock script does the same), `desert` (desert tiles among the capital and its six neighbours; above 2, or 1 on a Balanced start, only for Mali), and `level` (`strict` or `standard` for a civilization placed under a raised adjacency rule, `-` otherwise). Modes: `BIAS` (enforced tiers met), `UNMET` (they could be met on this map, but every such plot was taken by an earlier civilization or sits too close to a start already placed), `PREFERENCE` (no enforceable tier, placed by fertility and preference) or `BASE` (the stock pick for that region, reported the same way).
- `RBS_BIAS_REMATCH` — one line per civilization the final re-matching moved: the plot it was picked for (`from`), the picked plot it received (`to`), whether its enforced tiers are met there and that plot's fertility. The civilization's final start is the `to` plot.
- `RBS_BIAS_END` — totals after the re-matching (`enforced`, `satisfied`, `unmet`, `base` picks, `rematched` moves, `on_fallback` civilizations whose final start is a stock fallback plot) and the bias checksum, which the final fingerprint includes.
- `RBS_MINOR_FALLBACK` — a city-state whose region had no plot keeping the stock distances: the stock fallback plot (`stock`) and the plot taken instead (`picked`), each with its distance to the nearest civilization (`stock_major`, `picked_major`) and to the nearest earlier city-state (`stock_minor`, `picked_minor`, `-1` when none was placed yet), whether the picked plot passes the two stock distance checks (`major_check`, `minor_check`) and the region's plot count. No line means every city-state kept the stock distances.
- `RBS_BEGIN` — confirms the wrapper and normalizer ran.
- `RBS_AREA` — reports the number of plots scanned within five tiles of a start.
- `RBS_RESOURCE` — records an existing or newly placed resource (`status=EXISTING`, `PLACED`, or `PLACED_OFFSHORE` for fallback Oil on water).
- `RBS_UNSATISFIED` — records a land start/resource pair with no legal plot.
- `RBS_SKIP` — records an intentionally skipped ocean start or spectator slot.
- `RBS_SPECTATOR_FILTER` — printed when the lobby has spectator slots: whether hiding them from the stock script took effect (`applied=yes`, with the major count before and after). `applied=no` means the game refused the change and the stock script reserved a region for the spectator as without the mod; the fingerprint repeats it as `spectator_filter`.
- `RBS_SPECTATOR` — the start given to a spectator slot after the real civilizations and city-states are placed: the land plot farthest from every start, with that distance.
- `RBS_START_FINGERPRINT` — lists the final resource plot and distance for one start.
- `RBS_FINGERPRINT` — reports the map, seeds, counts, and deterministic checksum.

For a multiplayer test, compare every `RBS_BIAS_PLACED` line, every `RBS_START_FINGERPRINT` line and the final `RBS_FINGERPRINT` line from each participant. They should be identical for the same lobby configuration and seeds. The `version` field identifies the placement rules. Version 3 scatters tied placements, version 4 adds the offshore Oil fallback, version 5 adds start-bias enforcement (`bias_version` 1; `bias_version` 2 adds the neighbourhood fertility, the crowding look-ahead and the two matchings; `bias_version` 3 adds the city-state fallback), and version 6 leaves spectator slots out of the land division (`spectators` in the fingerprint counts them), so each places starts or resources differently from earlier versions on the same seed; every player must run the same version and `bias_version`. `RBS_AREA` lines report how many plots were scanned around each start; a start at least five tiles from any non-wrapping edge (top and bottom; also left and right on Inland Sea and Tilted Axis) should report 91.

Also check `Database.log` and `Modding.log` for component or SQL errors. The manifest should load one front-end configuration component and one in-game `ImportFiles` component; it intentionally contains no `AddGameplayScripts` action.

## Project layout

```text
Rose_Better_Starts.modinfo       Mod metadata and components
Configuration/
  RBS_MapRedirects.sql           Transparent Firaxis-map redirects
Maps/
  RBS_StartNormalizer.lua        Strategic resource normalizer and mod installer
  RBS_StartBias.lua              Start-bias enforcement for major civilizations
  RBS_*.lua                      Thin wrappers around Firaxis map scripts
README.md                        Installation, behavior, and verification
```

The wrappers include the installed Firaxis scripts at runtime; Firaxis map source is not copied into this repository.
