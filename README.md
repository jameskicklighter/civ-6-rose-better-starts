# Rose Better Starts

Rose Better Starts is a standalone Civilization VI: Gathering Storm map-generation mod. It gives every major civilization with a land start access to all seven strategic resource types within five hexes whenever the generated terrain contains a legal empty plot for them.

The balancing happens once, while the map is being created. The mod has no turn event, gameplay script, UI context, AI change, or post-generation map mutation.

## What it changes

For every human and AI major civilization with a land starting plot, the mod checks for:

- Horses
- Iron
- Niter
- Coal
- Oil
- Aluminum
- Uranium

An existing copy of the resource at a hex distance of five or less satisfies the check. If it is missing, Rose Better Starts places one unit of that resource on a legal empty land plot within the same radius.

Horses and Iron prefer rings two and three. Later strategics prefer rings four and five so they consume fewer early district locations. If those rings contain no legal plot, the remaining rings through five are checked. Existing water Oil counts, but newly placed Oil is kept on land so the mod does not consume a possible Harbor tile.

When several legal plots share the best preferred ring, the choice is scattered by a key derived from the map seed, the start, the resource, and the plot. The same map seed always produces the same placements for every player, and no draw is taken from the game's random-number stream, so the rest of map generation is unchanged.

Resources shared by overlapping five-tile areas count for every affected player. That includes a copy that is closer to another civilization or a city-state, which the checked player may never actually own. Strategic resources still obey their normal reveal technologies.

### Interaction with the Start Position setting

The stock **Start Position** setting has **Balanced** and **Legendary** options (Balanced is the multiplayer default; Standard is the single-player default). With either option, Firaxis tries to add each strategic resource revealed within one era of the starting era to a legal tile within three tiles of every start. Its placement is best-effort and is skipped silently when no tile qualifies. Those additions happen while starts are assigned, before Rose Better Starts runs, so they count as existing copies and are not duplicated. With **Standard**, the mod fills in every missing type on its own. In every case it only adds types still missing within five tiles. The **Resources** setting (Sparse/Standard/Abundant) changes how many resources exist before the mod runs.

### Effect on strategic scarcity

Every land-starting major is guaranteed nearby access to all seven strategics, including Oil, Aluminum, and Uranium. This deliberately softens late-game scarcity: resource wars and trade for missing strategics become less common than on an unmodified map. The rest of the map's resource distribution is untouched.

The mod does **not** change:

- Starting locations, civilization start biases, or player spacing
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

Static maps, scenarios, World Builder maps, true-start-location maps, and third-party map scripts are not modified. This includes:

- **Earth, Mediterranean, Europe, and East Asia** (normal and true-start-location versions). These are pre-built map files; the game places their starts itself without calling the start-assignment code this mod hooks.
- **Four-Leaf Clover and Six-Armed Snowflake.** These are pre-built, symmetrical maps with fixed start positions and resources.
- **Mirror.** This one is procedural, but it moves starts to their mirrored positions after the start-assignment step this mod hooks, so balancing would target the wrong tiles. It would also break the map's symmetry.

Supporting pre-built maps would require changing the map after the game has started. The mod avoids that because of the multiplayer desynchronization risk.

## Best-effort limitations

The radius is the Civ VI hex distance from the assigned starting plot and is fixed at five.

Resource placement must pass the game's own `ResourceBuilder.CanHaveResource` check. Some unusually constrained islands or polar starts may not contain an empty legal tile for every resource. In that case, the mod preserves the generated map and writes an `RBS_UNSATISFIED` entry to `Lua.log`. It never replaces another resource, expands the radius, or terraforms a tile to force success.

Ocean-starting civilizations such as Kupe are deliberately skipped. Resources placed around the initial ocean tile would not reliably be near the civilization's eventual capital, and forcing a land start would change the leader's intended behavior. These starts produce an `RBS_SKIP ... reason=OCEAN_START` log entry.

## Multiplayer design

Rose Better Starts is designed to avoid the runtime synchronization risks found in larger balancing mods:

- All mutations occur inside map generation, immediately after Firaxis assigns starts and before goody huts are placed.
- Candidate starts, resources, and plots use explicit stable ordering.
- Only plots within five tiles of each start are scanned.
- Ties within a ring use the seed-derived key described above, then plot index. The key uses exact integer arithmetic within double precision, so every platform computes identical values.
- The code does not use `math.random`, unordered table traversal for placement, system time, gameplay turn events, or unit/player mutations.
- A canonical fingerprint is logged after generation for host/client comparison.

Every multiplayer participant must enable the same Rose Better Starts version and use the same DLC and gameplay-mod set. Civ VI can still desynchronize when players have mismatched files, DLC, mod versions, or load orders; this mod cannot correct those external mismatches.

## Compatibility

Rose Better Starts is independent from Rose AI and may be enabled alongside it.

Do not enable Rose Better Starts together with Better Balanced Starts, Better Balanced Maps, YnAMP balancing components, or another mod that replaces the same Firaxis map scripts, starting-plot assignment, or resource generation. Which map implementation wins would depend on component load order and would make multiplayer results difficult to audit.

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

- `RBS_BEGIN` — confirms the wrapper and normalizer ran.
- `RBS_AREA` — reports the number of plots scanned within five tiles of a start.
- `RBS_RESOURCE` — records an existing or newly placed resource.
- `RBS_UNSATISFIED` — records a land start/resource pair with no legal plot.
- `RBS_SKIP` — records an intentionally skipped ocean start.
- `RBS_START_FINGERPRINT` — lists the final resource plot and distance for one start.
- `RBS_FINGERPRINT` — reports the map, seeds, counts, and deterministic checksum.

For a multiplayer test, compare every `RBS_START_FINGERPRINT` line and the final `RBS_FINGERPRINT` line from each participant. They should be identical for the same lobby configuration and seeds. The `version` field identifies the placement rules. Version 3 scatters tied placements, so it places resources differently from earlier versions on the same seed; every player must run the same version. `RBS_AREA` lines report how many plots were scanned around each start; a start at least five tiles from any non-wrapping edge (top and bottom; also left and right on Inland Sea and Tilted Axis) should report 91.

Also check `Database.log` and `Modding.log` for component or SQL errors. The manifest should load one front-end configuration component and one in-game `ImportFiles` component; it intentionally contains no `AddGameplayScripts` action.

## Project layout

```text
Rose_Better_Starts.modinfo       Mod metadata and components
Configuration/
  RBS_MapRedirects.sql           Transparent Firaxis-map redirects
Maps/
  RBS_StartNormalizer.lua        Shared deterministic balancing logic
  RBS_*.lua                      Thin wrappers around Firaxis map scripts
README.md                        Installation, behavior, and verification
```

The wrappers include the installed Firaxis scripts at runtime; Firaxis map source is not copied into this repository.
