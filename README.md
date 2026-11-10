# Rose Better Starts

Rose Better Starts is a standalone Civilization VI: Gathering Storm map-generation mod. It does two things while the map is being created:

1. **Start biases are enforced.** When the game chooses where each major civilization starts, the mod makes the civilization's own start bias (the game's `StartBias` tables: Russia and Canada in tundra, Portugal and Phoenicia on the coast, Egypt on floodplains, Mali in desert, and so on) a requirement whenever the map can satisfy it, instead of the stock best-effort matching. The bias tables themselves are not changed.
2. **Strategic resources are guaranteed.** Every major civilization with a land start gets access to all seven strategic resource types within five hexes whenever the generated terrain contains a legal empty plot for them, and otherwise within ten hexes, on a plot closer to it than to any other start.
3. **Equal land on Pangaea.** On Pangaea every civilization's region holds about the same number of usable land plots (see "Equal-area regions"), and a "Larger Pangaea" map option generates the continent with less water.
4. **Rose Snowflake.** One map of its own: six identical arms around a hub, for six players and spectators (see "Rose Snowflake").

The balancing happens once, while the map is being created. The mod has no turn event, gameplay script, UI context, AI change, or post-generation map mutation.

## Rose Snowflake

A map script of the mod's own (`Maps/RBS_Snowflake.lua`, listed as **Rose Snowflake**), inspired by the six-player balanced maps: six arms around a central hub, generated with six-fold rotational symmetry. The script builds one sixth of the map (a 60-degree wedge) and copies every plot of it to the five other rotations, so each player's arm, the islands beside it and its share of the hub are the same terrain, features, rivers, bonus and strategic resources, goody huts and coastal lowlands. The details are random each game (coastline, hills, woods, rivers, island shapes, where each resource sits, which luxuries form each set); the symmetry is not.

- **Arms**, laid out like the Firaxis six-player map, from the hub outwards:
  - a short desert right where the arm meets the hub, with a river (the "desert river") running its length, its banks desert floodplains;
  - the middle of the arm: woods on one side, rainforest on the other, and a small group of about three mountains between them for district adjacency;
  - the start near the back on the arm's centre line, not on the coast (the sea is three tiles away at the tip, so the capital can build a Harbor), with a river beside it; one back corner is tundra with woods, the other a small desert with floodplains and two mountains at its far end; both corners are two tiles thick.
  - Up to five rivers per arm (start, gate desert, woods side, rainforest side, desert corner) and a few grassland or plains floodplains besides the desert ones.
  - **Three of every strategic resource**, each in a region that suits it (Horses in open land, Iron in the hills and the desert corner, Niter and Oil in the gate desert and the tundra, Oil also in a rainforest marsh, Coal in the woods and hills, Aluminium in the desert corner, the rainforest and the plains, Uranium in the tundra woods, the woods and the desert corner), plus four offshore Oil fields per arm, and every sixth of the hub adds three more strategic types drawn each game.
  - Bonus resources in every region (wheat on a desert floodplain, deer, bananas, copper, sheep, stone, cattle, rice), food and production next to the start, and plenty of sea food: seven fish and two crabs per arm.
  - Starts are 24 tiles apart; an arm has about 125 land tiles.
- **City-state islands.** Each gap between two arms holds an island about three tiles thick (about 40 tiles, wooded and partly rainforest) with two coastal city-state sites, twelve in all, a mountain, fish, crabs, land bonuses and two Coal. Like the luxuries, the islands alternate a strategic set, A, B, C, A, B, C: two Oil (on land), two Uranium or two Aluminium, each on a flat desert tile (the one terrain all three accept, so the islands' land stays the same). In the offline runs the city-states were 13 tiles from the nearest capital and at least 10 from each other. With fewer city-states, each island gets one before any gets a second, spread evenly; with 7 to 11 the second sites go to some islands only, so those counts cannot be perfectly even.
- **Hub.** One round landmass (about 200 tiles) around a seven-tile lake, with a river in every sixth (from one side of the sixth, past the lake, to a bay beside the arm), two hub luxuries, three strategic types, two bonuses and a fish per sixth, and six natural wonder sites inside it, toward the gaps between the arms. The **Hub Natural Wonders** option places none, three (alternate sites) or six. Every arm has the same distances to the wonders in each case: the start sits on its arm's centre line, and the sites are 8 tiles apart, the game's minimum between natural wonders. The wonders are drawn at random, each site its own, leaving out the volcanic ones (Kilimanjaro, Vesuvius), which would erupt beside one arm only, and any excluded in the advanced setup; a single-tile wonder's tile takes the terrain it needs. With Three, multi-tile wonders can be drawn too: they start on the site, so every arm has the same distance to them, and spread from there unevenly, as they do by design (never onto an arm or a planned resource tile). With Six only single-tile wonders are used, since neighbouring sites are exactly the minimum distance apart. If any site cannot take a wonder, none is placed, so the map stays equal; with Six, the map then tries three on alternate sites (12 tiles apart, in case the game wants more than 8 between neighbours). If the even placement fails altogether, up to three wonders of any kind (multi-tile and coastal ones such as the Galapagos included) are placed in the hub where they fit, uneven but in the middle (`_WONDERS uneven` in the log). Rivers stay at least two tiles from the wonder sites: the game refuses these wonders next to a river.
- **Luxuries** are the one thing that differs. The arms alternate three sets, A, B, C, A, B, C, of three luxury types with two copies each (open land: one near the start, one mid-arm; woods: both in the woods; rainforest: both in the rainforest); the six islands alternate sets D, E, F of two types (one on land near the inner city-state, one in the water near the outer); the hub holds G and H, one copy of each per sixth. Each set's types are drawn at random among the luxuries whose rules fit its tiles, all 17 types different when the game has enough (`shared=0` on the log line).
- **Players.** Majors take an even spread of arms (all six with six players; 0, 2, 4 with three; opposite arms with two), turned by a random offset, with the players shuffled. Spectator slots (leader `LEADER_SPECTATOR` or civilization `CIVILIZATION_SPECTATOR`, as the Better Spectator Mod uses) never take an arm: each starts on a small snow islet in a corner of the grid, outside the symmetric area (the Better Spectator Mod removes the spectator's units at the start). The lobby allows up to 12 players so spectators fit; a seventh civilization would start on an islet as well (`RBS_SNOWFLAKE_OVERFLOW`).
- **Size.** 64x64 plots on the Small map size (costs and city targets of Small), about 1,250 land tiles.
- **Log.** `RBS_SNOWFLAKE_*` lines in `Lua.log`: `_LAND` (land per zone in one sixth), `_ISLAND`, `_RIVERS`, `_WONDERS`, `_LUXURIES` (each set's types), `_MAJORS` (player, arm, luxury set), `_MINORS`, `_ISLET`, and `_FINGERPRINT` with a checksum over every plot and the starts for comparing multiplayer peers. `missed_slots`, `resource_fails` and `luxury_fails` should read 0.

The other parts of the mod (start biases, strategic top-up, equal regions) do not run on this map: its starts and resources are already fixed by the script.

## Start biases

### How the game normally places starts

The engine divides the land into one region per major civilization. The stock script picks the most fertile valid plot of each region, and only then matches civilizations to those plots by bias, tier by tier. A civilization gets its bias only when one of the already-chosen plots happens to satisfy it. Tundra and desert plots are rarely the most fertile plot of a region, so Russia, Canada or Mali usually get an ordinary start. City-states are placed after every major civilization, in regions the engine divides afterwards; the mod keeps that order but places them by the civilizations' regions instead (see "City-states").

### What the mod does instead

The mod replaces the two steps that decide that outcome: the plot picked inside each region and the civilization-to-plot matching. Regions, the validity checks a start must pass (water access, passable surroundings, no natural wonder or luxury blocking, the stock distance between civilizations), Balanced and Legendary resources, city-states and ocean starts are the stock code, with one exception: the game rejects a capital with more than two desert tiles among the plot and its six neighbours (one on a Balanced start), so no civilization ever starts inside a desert. For Mali that cap is lifted: a plot that fails only the desert cap stays a candidate that only Mali may take, while every other civilization and the stock fallback keep the game's rule. The placed line shows each start's desert count as `desert`. The second exception is the polar rows: the game keeps every capital out of the rows within 15 percent of the top and bottom edges, which is where most tundra lies, so on a map with little land just inside that limit (Archipelago) Canada and Russia find no tundra start. For those two the limit is 5 percent: a plot in between that passes every other stock check (the snow cap included, so the capital never sits in the ice) is a candidate only they may take, and the placed line reads `edge=yes`.

- **Tiers.** Each civilization's bias rows come from the game's `StartBiasTerrains`, `StartBiasFeatures`, `StartBiasResources` and `StartBiasRivers` tables, with their tiers (1 strongest, 5 weakest). The civilization's tier-1 and tier-2 rows are **required**, all of them together, whenever at least one region has a valid plot that satisfies them; a tier-3 group is required only when it is the civilization's strongest tier (England, Japan and Norway's coast, the river civilizations, Greece and Korea's hills). If no region can satisfy every required tier, the strongest tier alone is required; if no region can satisfy even that, nothing is enforced and the civilization is placed like one without a bias. Tiers 4 and 5 are never required. In the current game data only Maya has two required tiers: grass or plains around the start and a plantation luxury within two tiles; its tier-3 rows, which list every other land terrain (Firaxis's way of keeping Maya inland), never count. Every tier a plot satisfies adds its weight (5 for tier 1 down to 1 for tier 5) to a preference score, except a tier 3 below a stronger tier, which in the game's data is a fallback terrain list rather than a wish and is neither required nor scored.
- **Satisfaction**, measured within the ranges the stock matching uses (terrain and feature rows within three tiles of the start, resource rows within two, river rows on the start plot; the start plot itself is not counted), with stricter minimums than the stock's single tile. Within a tier, rows of one kind are pooled, so Ethiopia's hills tier counts grass, plains, desert and tundra hills together. A tier's terrain rows need at least 4 matching tiles together, one of them next to the start plot (Mali asks for three adjacent desert tiles first: when it ranks regions, one that offers three adjacent beats one that offers the standard single adjacent tile, and either beats a region with no desert, so it never trades a desert region for an empty one and never loses its place in the order; the log says `enforced=strict` when its region offers three adjacent and `enforced=all` with `level=standard` when only the standard rule could be met there; when spacing blocks every strict plot at pick time, the standard rule decides and the placed line reads `level=standard`; a group of mountains needs no adjacent one, since the stock validity check allows at most one impassable neighbour and none on a Balanced start); its feature rows at least 5, one of them adjacent (1 and no adjacency when the tier lists a geothermal fissure or volcano); its resource rows at least 1; a river row needs the start plot on a river; the `TERRAIN_COAST` row needs the start plot itself next to sea water, so a coastal civilization can build a Harbor at its capital. So Canada and Russia start on the tundra edge, Mali on the desert edge and Vietnam inside its woods, rather than a few tiles away from them. A tier is satisfied when any of its groups reaches its minimums.
- **Order.** Civilizations with enforced tiers are placed first, human players before AIs among them (a human Mali takes the better desert region before an AI Nubia; `human=yes` on the `RBS_BIAS` line), then the one with the fewest satisfying regions before the others, then by strongest tier. Ties are broken by a key derived from the map seed and the player slot, never with a draw from the map generator's random stream, so lobby order alone does not decide. Civilizations without a required tier follow in the same key order. That greedy pass is then repaired by a maximum matching: when a civilization was left without a satisfying region although one could be freed by moving another civilization to a region that also satisfies it, the regions are exchanged (`plan=matched` in the log), so the number of civilizations with a satisfying region is the largest the map allows.
- **Fertility.** The engine's plot fertility, the value the stock pick sorts by, is a single-plot score: twice the plot's Food, Production, Science, Culture and Faith plus its Gold, +2 with fresh water, +1 on a river, +1 per adjacent mountain, +1 next to a natural wonder, +5 for a luxury on the plot, -5 on tundra, and 0 on snow, on mountains and next to ice. The stock pick also applies a region weighting that is 0 near internal region borders (and, through a bug in the engine's border test, for whole regions), so a stock start is the best single tile among whatever plots that weighting leaves. The mod ranks plots by a neighbourhood value instead: the engine's per-plot score summed over the plot and every plot within two tiles, the plot and its first ring at double weight. A start on a grassland river tile surrounded by hills and woods therefore outranks a lone rich tile in the middle of nothing. The single-plot and weighted values are only logged. Three civilizations get yields from the terrain their bias sends them to that the engine's value does not know (it even clamps a tundra tile to 0): Russia (+1 Production and +1 Faith on tundra, counted as the Production alone, since tundra stays weaker for growth than Canada's farmed tundra), Canada (farms on tundra, counted as +1 Food) and Mali (+1 Food and +1 Faith on desert next to the City Center, counted double for a stronger pull toward desert). The mod adds those, in the engine's units, to that civilization's own view of a plot's fertility (the plot and its first ring at double weight; Mali's only next to the centre), so Russia weighs a tundra-ringed plot the way Russia will use it, while every other civilization sees the plain value. The bonus appears as `bonus` on the placed line.
- **Choice.** Among a region's valid plots that meet the enforced tiers (or, when none does, those that meet the most of them), fertility decides first: the plots within 15 percent of the best fertility form a band, and within that band the highest preference score wins, then fertility, then plot index. So Germany gets a river start and Netherlands a coastal one when a nearly-as-good plot offers it, and a preference never pulls a civilization onto a start more than 15 percent below the best it could have had. Each civilization takes the free region whose best such plot ranks highest by enforced tiers met, then the number of satisfying plots in the region (up to four, so one lone plot near a border loses to a region with several), then the region's best fertility, then preference score (the lowest region index on a tie). When the stock loop reaches that region, the civilization gets the best such plot that keeps the stock distance from the starts already placed, the same check the stock pick applies, among the plots the stock loop lists for the region at that moment. When no valid plot keeps that distance, the region gets the stock pick, as it would without the mod.
- **Crowding.** Picks are made region by region, in the stock loop's order, so a pick can leave a later region with no satisfying plot outside the stock buffer; its civilization would then get the stock pick's fallback plot, which fails a validity check (that happened to Brazil in a 2026-10-19 game: 39 valid plots in its region, all within the buffer of five earlier starts). Among a civilization's equally good plots (same level, within the band), one that would leave every other unplaced region some satisfying plot is preferred over one that would box a region in (a region with no satisfying plot left is protected through its remaining valid plots, so it still gets a start of its own); and after the preference score, when a region is down to eight such plots or fewer, one that blocks fewer of them. Otherwise fertility decides within the band as usual. The look-ahead never leaves the band and never overrides a required tier. A region that has no valid plot outside the buffer when its turn comes still gets the stock pick, which applies no look-ahead of its own.
- **Final re-matching.** Once every region has its plot, a civilization whose enforced tiers are unmet at its own plot looks for another picked plot that meets them, by augmenting paths: a civilization gives up its plot only to move to one that also meets its own enforced tiers, or when it has none to meet. The displaced civilizations take the plots left over, best fertility first. The stock script matches this way too, over plots chosen without any bias; here it only repairs what crowding spoiled, and it never reduces the number of satisfied civilizations.

### Limits

- Only land starts of major civilizations. Kupe's ocean start and maps that ask the engine to ignore biases are placed by the stock code (city-states follow their own rules, below). Spectator slots take no region (see "Best-effort limitations").
- A bias is enforced inside the engine's regions: if no region contains a tundra edge with a valid start, no civilization is sent to the tundra. `Lua.log` reports this as `enforced=no`.
- Tiers 4 and 5 (Australia's cattle, Mali's mines, Germany's river) only tilt the choice within the 15 percent fertility band; Niter within two tiles is rare, so the Ottomans' row will seldom find a plot in the band.
- Spacing is the stock rule: each pick keeps the stock distance (more than ten tiles) from the starts already placed, the check the stock pick applies. Because biased picks land elsewhere than the stock picks, a later region can be left without such a plot where an unmodded map would not have been; the crowding look-ahead makes that rare, and when it still happens the stock fallback is used, as without the mod (`mode=BASE` with a `failed_check` in `Lua.log`; `spacing=forced` when even the fallback is within the buffer). The mod adds no minimum distance of its own.
- A region with no valid plot at all (a sliver of polar land, a region of mountains) gets the stock fallback plot whatever civilization holds it; the final re-matching hands such a plot to a civilization with nothing to meet when another picked plot satisfies the one that drew it.
- No terrain is changed and nothing is added to satisfy a bias. The mod chooses among the plots the map already has.

### Equal-area regions

The engine divides the land into one region per civilization by a measure of its own, which on Pangaea gave tundra regions nearly twice the land of fertile ones (a 2026-10-24 game: Canada 308 and Russia 312 land plots, Brazil 161). On Pangaea the mod lets the engine divide as usual and then hands the start placement its own regions instead, for the whole start assignment (capitals and the city-state zones):

- **What counts.** Passable land that is not snow, on the largest landmass, and there only the part you can walk across: mountains separate land the way water does, so a strip behind a mountain line stays outside every region, as do smaller islands (both go to the city-state "outside" zone). Snow is attached to a region but not counted; mountains and impassable natural wonders join none.
- **How.** Seeds spread over the land, only in the rows where a capital may start (each next seed the counted plot farthest from the seeds so far), so no region is anchored in the polar rows. Then the regions grow one plot at a time: the region with the fewest counted plots so far takes its free plot nearest its seed, so the regions stay level until the land is used up. Up to five rounds then move each seed to its region's centre (kept in those rows) and regrow, so the regions come out compact. Last, neighbouring regions two or more counted plots apart trade border plots, the largest gap first, never cutting a region in two (`moves` in the log).
- **Result.** Regions with the same number of counted plots within two or three (on the offline test maps: 122 to 124, and 321 to 323 for twelve civilizations on a large Pangaea); a wider gap falls back to the engine's regions (below). No tile is changed, and nothing draws from the random stream.
- **Trade-off.** Equal land is not equal quality: a tundra or desert region now has as much land as a grassland one, but poorer land, and the mod does not edit the map to make up for it.
- **Fallback.** The engine's regions are used as before on every other map, and on Pangaea when a mountain range cuts the land so that the walkable part holds less than 85 percent of it (`reason=split`), when it holds fewer than 20 counted plots per civilization (`too_small`), when the regions still differ by more than 3 counted plots or 10 percent of their size after levelling (`spread`), when the engine divided fewer regions than there are civilizations (`engine_count`), or when the game refuses the replacement (`refused`). `RBS_REGIONS mode=fallback` (or `refused`) with the reason; no line on maps that keep the engine's regions.
- Spectator slots are left out first, so the regions are counted for the real civilizations only.

### Larger Pangaea

A map option, off by default, on the Pangaea setup screen. Ticked, the Pangaea is generated with less water: 40, 46 or 52 percent for low, standard and high sea level, instead of the stock 53, 58 and 63 (BBM's Pangaea Ultima uses 43, 51 and 57, so this is a little more land than BBM at every sea level). Everything else is the stock Pangaea generator, step for step with the same random draws; the land is generated that way from the start, nothing is changed afterwards. Unticked, the stock generator runs unchanged. The option is part of the lobby's map settings, so every player generates the same map; the fingerprint reports it as `larger`.

### City-states

The stock script places each city-state in a region the engine divides for city-states, at that region's most fertile plot passing the stock checks, so one civilization's land can hold three city-states and its neighbour's none. The mod spreads them over the civilizations' regions instead, with the game's spacing rules as hard limits:

- **Zones.** Each civilization's region (the land the engine divided for the major civilizations) is a zone; land in no region forms one more zone, used only when no region can take a city-state.
- **Placement first.** Each city-state goes to the zone holding the fewest city-states so far, among the zones that still have a plot passing every stock city-state check: more than six tiles from every civilization (five on a water map such as Archipelago), more than five from every city-state already placed, passable surroundings, the natural wonder buffer, no luxury or strategic resource on the tile, no oasis. Ties go to the zone with the most such plots left, then the lower region index. So with 12 city-states and 8 civilizations every region gets one before any gets a second, and the four extra go to the roomiest regions; a region too small or too crowded to fit one is skipped.
- **Then fertility.** Inside its zone the city-state first avoids a plot that would leave another region, one holding no more city-states than its own, without any usable plot (every one of that region's plots within five tiles of it): small regions have their few usable plots near their borders, where a neighbour's city-state would otherwise take them away. Among the rest it takes the plot with the best neighbourhood fertility (the measure the civilizations use), lowest plot index on a tie. A city-state can start in the polar rows, as in the stock game (only capitals are kept out of them), but polar land rarely ranks high.
- **When the rules cannot all be kept.** If no zone has a plot passing every check, the plots that keep both distances but fail a later check come next, by the same zone rule and look-ahead (then the most checks passed, then fertility). If no land plot keeps both distances, the city-state takes the plot that falls least short of them: each plot is scored by how many tiles short it is of the civilization distance and of the city-state distance (a rule it keeps is never short), the worse of the two counts first, then the better, then the civilization side alone, so a plot next to a capital is never traded for one next to a city-state; the later checks and fertility decide the rest.
- The stock loop still decides how many city-states are placed (one per city-state region the engine divides, at most the number in the lobby), and the city-states' own start biases still match them to the chosen plots, as in the stock game. The rules apply with or without start biases. Every machine computes the same result.

`RBS_MINOR_PLACED` lines in `Lua.log` show each pick, `RBS_MINOR_END` the totals (see "Verifying a generated map").

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

**Ten-tile fallback.** When no copy and no legal plot (land, or Coast for Oil) lies within five hexes, rings six to ten are searched, the nearest ring first. Only a plot closer to this start than to any other civilization's or city-state's start counts, so the fallback never serves a neighbour first and can never land within five tiles of another start. An existing copy there satisfies the check (`EXISTING_FAR`); otherwise one unit is placed on the nearest legal land plot (`PLACED_FAR`), and for Oil on a Coast tile when no land plot qualifies (`PLACED_OFFSHORE_FAR`).

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

Enabling the mod transparently affects the existing Firaxis map selections; it does not add duplicate `Rose` map entries. Their names, images, and normal setup options remain unchanged. The one new entry is the mod's own map, Rose Snowflake (see above).

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

The radius is the Civ VI hex distance from the assigned starting plot and is fixed at five, with the ten-tile fallback above.

Resource placement must pass the game's own `ResourceBuilder.CanHaveResource` check. Some unusually constrained islands or polar starts may not contain an empty legal tile for every resource. Oil has the offshore fallback described above; Horses, Iron, Niter, Coal, Aluminum, and Uranium are land-only. In that case, the mod preserves the generated map and writes an `RBS_UNSATISFIED` entry to `Lua.log`. It never replaces another resource, goes beyond ten tiles, or terraforms a tile to force success.

Spectator slots added by spectator mods (leader `LEADER_SPECTATOR` or civilization `CIVILIZATION_SPECTATOR`) are left out of the land division: the stock script would reserve one region per alive major, spectators included, so a ninth of the map stayed empty around one of its best starts. While the stock script assigns starts, the mod hides spectator slots from its major list (the list is restored afterwards); every spectator then gets the passable land plot (with at least two passable land neighbours) farthest from all starts, logged as `RBS_SPECTATOR`, so its units stand where nobody settles, and the resource normalizer skips it with an `RBS_SKIP ... reason=SPECTATOR` entry. That start plot stays reserved. Every machine sees the same lobby configuration, so all filter the same slots.

Ocean-starting civilizations such as Kupe are deliberately skipped. Resources placed around the initial ocean tile would not reliably be near the civilization's eventual capital, and forcing a land start would change the leader's intended behavior. These starts produce an `RBS_SKIP ... reason=OCEAN_START` log entry.

## Multiplayer design

Rose Better Starts is designed to avoid the runtime synchronization risks found in larger balancing mods:

- All mutations occur inside map generation: start biases while Firaxis assigns starts, strategic resources immediately after and before goody huts are placed.
- Candidate starts, resources, and plots use explicit stable ordering.
- Start-bias placement looks only at the valid plots of each region (the engine's, or the equal-area regions on Pangaea, grown from fixed seeds by distance, the smallest region first, ties by plot index) (the stock validity checks, at most 400 plots per region), reads each plot's fertility once, and compares plots with integer distances; the two matchings (regions at planning time, plots at the end) are augmenting-path searches over sorted lists; strategic placement scans only plots within five tiles of each start.
- Ties use the seed-derived key described above, then plot index. The key uses exact integer arithmetic within double precision, so every platform computes identical values. Preference scores are integers.
- The code does not use `math.random`, unordered table traversal for placement, system time, gameplay turn events, or unit/player mutations, and it takes no draw from the map generator's random stream.
- A canonical fingerprint is logged after generation for host/client comparison; it covers the start-bias placement and the resources.
- Rose Snowflake is a full map script, so like every Firaxis script it draws from the map generator's synchronised random stream (`TerrainBuilder.GetRandomNumber`), always in a fixed order (plots in index order, sorted candidate lists, integer geometry), and logs its own fingerprint (`RBS_SNOWFLAKE_FINGERPRINT`).

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
- `RBS_BIAS_REGION` — one line per engine region: its plot count, how many plots passed the stock validity checks (`candidates`, including the `desert_only` plots that fail only the desert cap and are open to Mali alone, and the `edge_only` plots in the polar rows open to Canada and Russia alone) and how many of those the engine's region-weighted fertility rates above 0 (`weighted_positive`).
- `RBS_BIAS` — one line per major civilization: its bias tiers (`tiers=T2:TERRAIN_TUNDRA/TERRAIN_TUNDRA_HILLS,...`), the required tiers (`required=T1+T2`), what was enforced (`enforced=strict` for a civilization whose raised adjacency rule its region meets, `all`, `strongest` when only the strongest tier could be satisfied, `no` when none could), the number of regions that satisfy the enforced tiers (`options`, with `options_strict`, `options_all` and `options_strongest` for each level), its placement order, its region, `plan=greedy` or `matched` (the matching pass moved it) and `level` (`strict` or `standard` for a civilization with a raised adjacency rule, `-` otherwise).
- `RBS_BIAS_PLACED` — the region and plot each civilization received when its region was picked, `satisfied=yes` when its enforced tiers are met there, the preference score, its fertility (`fertility`, the neighbourhood value as that civilization sees it, with `bonus` the civilization tile bonus included in it; `plot_fertility` is the engine's single-plot value and `weighted` its region-weighted value, the one the stock pick sorts by) next to `best_fertility` (the fertility it could have had without its preferences; the difference is the price of the preference, at most the `band` percentage), `satisfying` (how many plots of the region met the same tiers), `boxes` and `damage` (what the chosen plot costs the regions still to be picked: regions left without a satisfying or valid plot, and the blocked share of the remaining plots of regions down to eight or fewer, in thousandths, summed), `candidates` (the region's valid plots at pick time), `failed_check` (for a stock fallback plot, the first stock validity check it fails: `luxury`, `water_access`, `adjacent`, `natural_wonder`, `resource` or `oasis`; `-` otherwise), the mode, `spacing=forced` when the fallback plot is also within the stock distance of another start (the stock script does the same), `desert` (desert tiles among the capital and its six neighbours; above 2, or 1 on a Balanced start, only for Mali), `level` (`strict` or `standard` for a civilization placed under a raised adjacency rule, `-` otherwise) and `edge` (`yes` for a Canada or Russia start in the polar rows the game keeps other capitals out of; always `no` on a `BASE` line, even when the stock fallback plot lies in those rows). Modes: `BIAS` (enforced tiers met), `UNMET` (they could be met on this map, but every such plot was taken by an earlier civilization or sits too close to a start already placed), `PREFERENCE` (no enforceable tier, placed by fertility and preference) or `BASE` (the stock pick for that region, reported the same way).
- `RBS_BIAS_REMATCH` — one line per civilization the final re-matching moved: the plot it was picked for (`from`), the picked plot it received (`to`), whether its enforced tiers are met there and that plot's fertility. The civilization's final start is the `to` plot.
- `RBS_BIAS_END` — totals after the re-matching (`enforced`, `satisfied`, `unmet`, `base` picks, `rematched` moves, `on_fallback` civilizations whose final start is a stock fallback plot) and the bias checksum, which the final fingerprint includes.
- `RBS_MINOR_BEGIN` — the city-state placement ran: the number of city-states, the zones (one per civilization region) with their land plot counts (`zone_plots=region:plots,...`) and the land outside every region (`outside_plots`).
- `RBS_MINOR_PLACED` — one line per city-state: its plot, its zone (`-1` for land outside every region), `level` (`full` when the plot passes every stock check, `spaced` when it keeps both distances but fails a later check, `short` when no land plot kept both distances), the zones' city-state counts before this pick (`counts`, in zone order) and how many plots each zone had at that level (`live`), `boxes` (how many regions with no more city-states the pick still left without a plot at that level; 0 unless every plot of the zone would), its distance to the nearest civilization (`major_distance`) and to the nearest earlier city-state (`minor_distance`, `-1` for the first), its fertility, and the size of the engine's city-state region the stock loop offered (`region_plots`, not used).
- `RBS_MINOR_END` — totals: city-states placed, the final count per zone, outside, the number at each level and a checksum of the city-state plots. Printed when the stock script matches city-states to their plots, so it is missing on a map that ignores start biases.
- `RBS_MINOR_FALLBACK` — only when no civilization region was recorded (the zone placement could not run): a city-state whose engine region had no plot keeping the stock distances, with the stock fallback plot (`stock`) and the plot taken instead (`picked`), each with its distance to the nearest civilization (`stock_major`, `picked_major`) and to the nearest earlier city-state (`stock_minor`, `picked_minor`), whether the picked plot passes the two stock distance checks (`major_check`, `minor_check`) and the region's plot count.
- `RBS_BEGIN` — confirms the wrapper and normalizer ran.
- `RBS_AREA` — reports the number of plots scanned within five tiles of a start.
- `RBS_RESOURCE` — records an existing or newly placed resource (`status=EXISTING`, `PLACED`, or `PLACED_OFFSHORE` for fallback Oil on water; `EXISTING_FAR`, `PLACED_FAR` and `PLACED_OFFSHORE_FAR` from the ten-tile fallback).
- `RBS_UNSATISFIED` — records a land start/resource pair with no legal plot within ten tiles (`reason=NO_LEGAL_LAND_PLOT_WITHIN_10`, or `..._OR_OFFSHORE_..._WITHIN_10` for Oil); `closer_to_other` counts the plots in rings six to ten that held or could take the resource but were turned down because they lie at least as close to another start.
- `RBS_SKIP` — records an intentionally skipped ocean start or spectator slot.
- `RBS_SPECTATOR_FILTER` — printed when the lobby has spectator slots: whether hiding them from the stock script took effect (`applied=yes`, with the major count before and after). `applied=no` means the game refused the change and the stock script reserved a region for the spectator as without the mod; the fingerprint repeats it as `spectator_filter`.
- `RBS_SPECTATOR` — the start given to a spectator slot after the real civilizations and city-states are placed: the land plot farthest from every start, with that distance.
- `RBS_START_FINGERPRINT` — lists the final resource plot and distance for one start.
- `RBS_REGIONS` — the region mode (`equal`, `fallback`, `refused`; no line on maps that keep the engine's regions), the number of regions, the counted plots, the smallest and largest region (`min`, `max`, counted plots), the re-centring rounds used, the plots no region reached (`unreached`), the border plots traded in the levelling (`moves`) and the regions' checksum; one `RBS_REGION` line per region with its counted plots, all its plots and its seed plot.
- `RBS_LARGER_PANGAEA` — printed when the Larger Pangaea option is ticked: the water percent used.
- `RBS_FINGERPRINT` — reports the map, seeds, counts, and deterministic checksum; `bias`, `minor` and `regions` are the checksums of the major placement, the city-state placement and the equal-area regions, `regions_mode` the region mode and `larger` the Larger Pangaea option, all included in `checksum`.

For a multiplayer test, compare every `RBS_BIAS_PLACED` and `RBS_MINOR_PLACED` line, every `RBS_START_FINGERPRINT` line and the final `RBS_FINGERPRINT` line from each participant. They should be identical for the same lobby configuration and seeds. The `version` field identifies the placement rules. Version 3 scatters tied placements, version 4 adds the offshore Oil fallback, version 5 adds start-bias enforcement (`bias_version` 1; `bias_version` 2 adds the neighbourhood fertility, the crowding look-ahead and the two matchings; `bias_version` 3 adds the city-state fallback; `bias_version` 4 the polar rows for Canada and Russia and the city-state zones; `bias_version` 5 human players first among biased civilizations), version 6 leaves spectator slots out of the land division (`spectators` in the fingerprint counts them), version 7 adds the equal-area regions and the Larger Pangaea option, and version 8 the ten-tile resource fallback and the Larger Pangaea water of 40/46/52, so each places starts or resources differently from earlier versions on the same seed; every player must run the same version and `bias_version`. `RBS_AREA` lines report how many plots were scanned around each start; a start at least five tiles from any non-wrapping edge (top and bottom; also left and right on Inland Sea and Tilted Axis) should report 91.

Also check `Database.log` and `Modding.log` for component or SQL errors. The manifest should load one front-end configuration component, one front-end text component and one in-game `ImportFiles` component; it intentionally contains no `AddGameplayScripts` action.

## Project layout

```text
Rose_Better_Starts.modinfo       Mod metadata and components
Configuration/
  RBS_MapRedirects.sql           Transparent Firaxis-map redirects
  RBS_MapOptions.sql             Map options (Larger Pangaea)
  RBS_Snowflake.sql              Rose Snowflake map entry, size and option
  RBS_Text.xml                   Option and map text
Maps/
  RBS_StartNormalizer.lua        Strategic resource normalizer and mod installer
  RBS_StartBias.lua              Start-bias enforcement for major civilizations
  RBS_EqualRegions.lua           Equal-area regions (Pangaea)
  RBS_LargerPangaea.lua          Larger Pangaea land generation
  RBS_Snowflake.lua              Rose Snowflake map script
  RBS_*.lua                      Thin wrappers around Firaxis map scripts
README.md                        Installation, behavior, and verification
```

The wrappers include the installed Firaxis scripts at runtime. The one exception is `RBS_LargerPangaea.lua`, which carries a copy of the stock Pangaea land-generation functions with the water shares changed, because the stock functions keep their state where a wrapper cannot reach it.
