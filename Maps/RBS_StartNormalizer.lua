-- ===========================================================================
-- Rose Better Starts
-- Deterministic, map-generation-only strategic resource normalization.
-- ===========================================================================

RoseBetterStarts = RoseBetterStarts or {};

-- Start-bias enforcement for major civilizations (installed by Install below).
include "RBS_StartBias";

local VERSION = 6;
local MAX_DISTANCE = 5;
local CHECKSUM_MODULUS = 2147483647;
local MIX_MULTIPLIER = 48271;

local STRATEGIC_RESOURCES = {
  { Type = "RESOURCE_HORSES",  PreferredRings = { 2, 3, 4, 5, 1 } },
  { Type = "RESOURCE_IRON",    PreferredRings = { 2, 3, 4, 5, 1 } },
  { Type = "RESOURCE_NITER",   PreferredRings = { 4, 5, 3, 2, 1 } },
  { Type = "RESOURCE_COAL",    PreferredRings = { 4, 5, 3, 2, 1 } },
  -- Oil may fall back to a Coast tile (sea or lake) when no land tile qualifies.
  { Type = "RESOURCE_OIL",     PreferredRings = { 4, 5, 3, 2, 1 }, OffshoreFallback = true },
  { Type = "RESOURCE_ALUMINUM", PreferredRings = { 4, 5, 3, 2, 1 } },
  { Type = "RESOURCE_URANIUM", PreferredRings = { 4, 5, 3, 2, 1 } }
};

local function GetConfigurationValue(configuration, key)
  if configuration == nil or configuration.GetValue == nil then
    return "unknown";
  end

  local value = configuration.GetValue(key);
  if value == nil then
    return "unknown";
  end

  return tostring(value);
end

local function AddChecksum(checksum, value)
  return (checksum * 31 + value) % CHECKSUM_MODULUS;
end

-- Park-Miller style mixing kept below 2^47 so double arithmetic stays exact.
local function Mix(state, value)
  return (state * MIX_MULTIPLIER + value) % CHECKSUM_MODULUS;
end

-- The map seed is part of the shared game configuration, so every multiplayer
-- participant derives the same value. It only breaks ties between equally
-- preferred plots; it never consumes the map generator's random stream.
local function GetMapSeed()
  local value = nil;
  if MapConfiguration ~= nil and MapConfiguration.GetValue ~= nil then
    value = tonumber(MapConfiguration.GetValue("RANDOM_SEED"));
  end
  if value == nil then
    return 0;
  end
  return math.floor(value) % CHECKSUM_MODULUS;
end

-- (a * b) mod CHECKSUM_MODULUS for a, b below 2^31, split so every
-- intermediate stays below 2^53 and remains exact in double arithmetic.
local function MulMod(a, b)
  local high = math.floor(a / 65536);
  local low = a % 65536;
  return ((high * b) % CHECKSUM_MODULUS * 65536 + low * b) % CHECKSUM_MODULUS;
end

-- Squaring rounds make the key non-linear in the plot index, so a different
-- seed reshuffles the candidate order instead of rotating one fixed order.
local function GetTieBreakKey(seed, startIndex, resourceIndex, plotIndex)
  local key = Mix(seed, startIndex + 1);
  key = Mix(key, resourceIndex + 1);
  key = Mix(key, plotIndex + 1);
  key = Mix(MulMod(key, key), plotIndex + 1);
  return Mix(MulMod(key, key), 0);
end

-- Shared with RBS_StartBias.lua, which breaks its own ties the same way.
RoseBetterStarts.GetMapSeed = GetMapSeed;
RoseBetterStarts.GetTieBreakKey = GetTieBreakKey;

-- Plots within MAX_DISTANCE of a start, in ascending plot-index order. The
-- square offset window contains every plot within that hex distance. The
-- lookup range is twice the radius so the engine's own range check can never
-- trim the window (its metric is not documented); GetPlotDistance does the
-- real filtering, and the seen set guards wrapped duplicates.
local function CollectNearbyPlots(startPlot)
  local startIndex = startPlot:GetIndex();
  local startX = startPlot:GetX();
  local startY = startPlot:GetY();
  local nearby = {};
  local seen = {};

  for dy = -MAX_DISTANCE, MAX_DISTANCE do
    for dx = -MAX_DISTANCE, MAX_DISTANCE do
      local plot = Map.GetPlotXY(startX, startY, dx, dy, MAX_DISTANCE * 2);
      if plot ~= nil then
        local plotIndex = plot:GetIndex();
        if seen[plotIndex] ~= true then
          seen[plotIndex] = true;
          local distance = Map.GetPlotDistance(startIndex, plotIndex);
          if distance <= MAX_DISTANCE then
            nearby[#nearby + 1] = { Plot = plot, PlotIndex = plotIndex, Distance = distance };
          end
        end
      end
    end
  end

  table.sort(nearby, function(left, right)
    return left.PlotIndex < right.PlotIndex;
  end);
  return nearby;
end

local function GetRingRank(resourceDefinition, distance)
  for rank = 1, #resourceDefinition.PreferredRings do
    if resourceDefinition.PreferredRings[rank] == distance then
      return rank;
    end
  end

  return MAX_DISTANCE + 1;
end

-- Spectator mods (e.g. Better Spectator Mod) add a major slot with this leader.
-- Map generation still gives it a start, but no civilization will settle there.
local function IsSpectator(playerID)
  if PlayerConfigurations == nil then
    return false;
  end
  local config = PlayerConfigurations[playerID];
  if config == nil then
    return false;
  end
  return config:GetLeaderTypeName() == "LEADER_SPECTATOR"
    or config:GetCivilizationTypeName() == "CIVILIZATION_SPECTATOR";
end

-- The stock script divides the land into one region per alive major,
-- spectators included, and gives each one a start, so with a spectator slot
-- a ninth of the map stayed empty around one of its best starts. During
-- AssignStartingPlots.Create the player manager's major list is filtered,
-- so neither the stock script nor the start-bias plan sees a spectator; the
-- list is restored whatever happens inside Create. Afterwards every
-- spectator gets the passable land plot farthest from all starts
-- (RBS_SPECTATOR), so its units, if its mod gives it any, stand where
-- nobody settles; the normalizer then skips it as before (RBS_SKIP). The
-- slot's leader and civilization come from the shared lobby
-- configuration, so every machine filters the same slots.
local function AliveSpectators()
  local spectators = {};
  if PlayerManager == nil or PlayerManager.GetAliveMajorIDs == nil or PlayerManager.GetAliveMajorsCount == nil then
    return spectators;
  end
  local ids = PlayerManager.GetAliveMajorIDs();
  local count = PlayerManager.GetAliveMajorsCount();
  for n = 1, count do
    if IsSpectator(ids[n]) then
      spectators[#spectators + 1] = ids[n];
    end
  end
  return spectators;
end

-- Replaces the two major-list functions with filtered ones for the duration
-- of Create; returns the function that restores them and the major count
-- read back through the manager before and after, so the caller can tell
-- whether the replacement took effect (the game's table is not the offline
-- mock; a count that did not drop means the stock script still sees the
-- spectator, as without the mod).
local function InstallSpectatorFilter(spectators)
  if #spectators == 0 or type(PlayerManager) ~= "table" then
    return function() end, -1, -1;
  end
  local isSpectator = {};
  for n = 1, #spectators do
    isSpectator[spectators[n]] = true;
  end
  local baseIDs = PlayerManager.GetAliveMajorIDs;
  local baseCount = PlayerManager.GetAliveMajorsCount;
  local function FilteredIDs()
    local ids = baseIDs();
    local count = baseCount();
    local filtered = {};
    for n = 1, count do
      if isSpectator[ids[n]] ~= true then
        filtered[#filtered + 1] = ids[n];
      end
    end
    return filtered;
  end
  local before = baseCount();
  PlayerManager.GetAliveMajorIDs = FilteredIDs;
  PlayerManager.GetAliveMajorsCount = function()
    return #FilteredIDs();
  end;
  local after = PlayerManager.GetAliveMajorsCount();
  return function()
    PlayerManager.GetAliveMajorIDs = baseIDs;
    PlayerManager.GetAliveMajorsCount = baseCount;
  end, before, after;
end

local SPECTATOR_MIN_LAND_NEIGHBOURS = 2;

local function PassableLandNeighbours(plot)
  local count = 0;
  for direction = 0, 5 do
    local other = Map.GetAdjacentPlot(plot:GetX(), plot:GetY(), direction);
    if other ~= nil and not other:IsWater() and not other:IsImpassable() then
      count = count + 1;
    end
  end
  return count;
end

-- Each spectator gets the passable land plot, with at least
-- SPECTATOR_MIN_LAND_NEIGHBOURS passable land neighbours so its units can
-- stand there, whose distance to the nearest start (majors, city-states,
-- spectators placed before it) is largest; the lowest plot index on a tie.
local function AssignSpectatorStarts(spectators)
  RoseBetterStarts.SpectatorCount = #spectators;
  if #spectators == 0 then
    return;
  end
  local isSpectator = {};
  for n = 1, #spectators do
    isSpectator[spectators[n]] = true;
  end
  local taken = {};
  local function Collect(ids, count)
    for n = 1, count do
      local player = Players[ids[n]];
      if player ~= nil and isSpectator[ids[n]] ~= true then
        local plot = player:GetStartingPlot();
        if plot ~= nil then
          taken[#taken + 1] = plot:GetIndex();
        end
      end
    end
  end
  Collect(PlayerManager.GetAliveMajorIDs(), PlayerManager.GetAliveMajorsCount());
  Collect(PlayerManager.GetAliveMinorIDs(), PlayerManager.GetAliveMinorsCount());

  for n = 1, #spectators do
    local bestIndex = nil;
    local bestDistance = -1;
    for plotIndex = 0, Map.GetPlotCount() - 1 do
      local plot = Map.GetPlotByIndex(plotIndex);
      if plot ~= nil and not plot:IsWater() and not plot:IsImpassable() then
        local nearest = nil;
        for t = 1, #taken do
          local distance = Map.GetPlotDistance(plotIndex, taken[t]);
          if nearest == nil or distance < nearest then
            nearest = distance;
            if nearest <= bestDistance then
              break;
            end
          end
        end
        if nearest == nil then
          nearest = 0;
        end
        if nearest > bestDistance and PassableLandNeighbours(plot) >= SPECTATOR_MIN_LAND_NEIGHBOURS then
          bestDistance = nearest;
          bestIndex = plotIndex;
        end
      end
    end
    local playerID = spectators[n];
    local player = Players[playerID];
    if bestIndex ~= nil and player ~= nil then
      player:SetStartingPlot(Map.GetPlotByIndex(bestIndex));
      taken[#taken + 1] = bestIndex;
      print("RBS_SPECTATOR player=" .. tostring(playerID)
        .. " plot=" .. tostring(bestIndex)
        .. " distance=" .. tostring(bestDistance));
    else
      print("RBS_SPECTATOR player=" .. tostring(playerID) .. " plot=-1 distance=-1");
    end
  end
end

local function CollectStartingPlots(playerIDs, playerCount, startsByIndex, reservedStartPlots)
  for listIndex = 1, playerCount do
    local playerID = playerIDs[listIndex];
    local player = Players[playerID];
    if player ~= nil then
      local startPlot = player:GetStartingPlot();
      local spectator = startsByIndex ~= nil and IsSpectator(playerID);
      if spectator then
        print("RBS_SKIP player=" .. tostring(playerID)
          .. " start=" .. tostring(startPlot ~= nil and startPlot:GetIndex() or -1)
          .. " reason=SPECTATOR");
      end
      if startPlot ~= nil then
        local startIndex = startPlot:GetIndex();
        reservedStartPlots[startIndex] = true;
        if startsByIndex ~= nil and not spectator then
          startsByIndex[#startsByIndex + 1] = {
            PlayerID = playerID,
            Plot = startPlot,
            PlotIndex = startIndex,
            Nearby = CollectNearbyPlots(startPlot)
          };
        end
      elseif startsByIndex ~= nil and not spectator then
        print("RBS_UNSATISFIED player=" .. tostring(playerID) .. " start=-1 resource=ALL reason=NO_STARTING_PLOT");
      end
    end
  end
end

local function CollectMajorStarts()
  local starts = {};
  local reservedStartPlots = {};

  local majorIDs = PlayerManager.GetAliveMajorIDs();
  CollectStartingPlots(majorIDs, PlayerManager.GetAliveMajorsCount(), starts, reservedStartPlots);

  local minorIDs = PlayerManager.GetAliveMinorIDs();
  CollectStartingPlots(minorIDs, PlayerManager.GetAliveMinorsCount(), nil, reservedStartPlots);

  table.sort(starts, function(left, right)
    if left.PlotIndex == right.PlotIndex then
      return left.PlayerID < right.PlayerID;
    end
    return left.PlotIndex < right.PlotIndex;
  end);

  return starts, reservedStartPlots;
end

-- Nearest existing copy; ties keep the lowest plot index (nearby is sorted).
local function FindExistingResource(nearby, resourceIndex)
  local nearestPlot = nil;
  local nearestDistance = MAX_DISTANCE + 1;

  for nearbyNumber = 1, #nearby do
    local entry = nearby[nearbyNumber];
    local plot = entry.Plot;
    if entry.Distance < nearestDistance
      and plot:GetResourceCount() > 0
      and plot:GetResourceType() == resourceIndex then
      nearestPlot = plot;
      nearestDistance = entry.Distance;
    end
  end

  return nearestPlot, nearestDistance;
end

-- Best legal plot by preferred ring. Plots in the same ring are ordered by a
-- seed-derived key so placements scatter around the start instead of always
-- taking the lowest plot index; plot index settles any remaining tie.
-- Land search takes land plots only. The offshore search takes water plots
-- only and skips ring 1, the tiles next to the future capital. Lakes are
-- allowed: base generation places Oil on any legal Coast tile, lakes included,
-- and Offshore Oil Rigs can be built there.
local function FindPlacementPlot(startRecord, resourceDefinition, resourceIndex, resourceHash, reservedStartPlots, seed, offshore)
  local bestPlot = nil;
  local bestDistance = -1;
  local bestRank = MAX_DISTANCE + 1;
  local bestKey = CHECKSUM_MODULUS;
  local bestPlotIndex = -1;
  local nearby = startRecord.Nearby;
  local minimumDistance = offshore and 2 or 1;

  for nearbyNumber = 1, #nearby do
    local entry = nearby[nearbyNumber];
    local distance = entry.Distance;
    local plotIndex = entry.PlotIndex;
    if distance >= minimumDistance and reservedStartPlots[plotIndex] ~= true then
      local rank = GetRingRank(resourceDefinition, distance);
      if rank <= bestRank then
        local key = GetTieBreakKey(seed, startRecord.PlotIndex, resourceIndex, plotIndex);
        local better = rank < bestRank
          or key < bestKey
          or (key == bestKey and plotIndex < bestPlotIndex);
        local plot = entry.Plot;
        local water = plot:IsWater();
        if better
          and water == offshore
          and not plot:IsImpassable()
          and not plot:IsNaturalWonder()
          and plot:GetResourceCount() == 0
          and ResourceBuilder.CanHaveResource(plot, resourceHash) then
          bestPlot = plot;
          bestDistance = distance;
          bestRank = rank;
          bestKey = key;
          bestPlotIndex = plotIndex;
        end
      end
    end
  end

  return bestPlot, bestDistance;
end

-- Plot:GetResourceType returns a database index, while ResourceBuilder's
-- placement functions use the resource type hash.
local function EnsureResource(startRecord, resourceDefinition, resourceIndex, resourceHash, reservedStartPlots, seed)
  local existingPlot, existingDistance = FindExistingResource(startRecord.Nearby, resourceIndex);
  if existingPlot ~= nil then
    print(
      "RBS_RESOURCE player=" .. tostring(startRecord.PlayerID)
      .. " start=" .. tostring(startRecord.PlotIndex)
      .. " resource=" .. resourceDefinition.Type
      .. " status=EXISTING"
      .. " plot=" .. tostring(existingPlot:GetIndex())
      .. " distance=" .. tostring(existingDistance)
    );
    return true;
  end

  local placementPlot, placementDistance = FindPlacementPlot(
    startRecord,
    resourceDefinition,
    resourceIndex,
    resourceHash,
    reservedStartPlots,
    seed,
    false
  );
  local placedStatus = "PLACED";
  local unsatisfiedReason = "NO_LEGAL_LAND_PLOT_WITHIN_5";

  if placementPlot == nil and resourceDefinition.OffshoreFallback then
    placementPlot, placementDistance = FindPlacementPlot(
      startRecord,
      resourceDefinition,
      resourceIndex,
      resourceHash,
      reservedStartPlots,
      seed,
      true
    );
    placedStatus = "PLACED_OFFSHORE";
    unsatisfiedReason = "NO_LEGAL_LAND_OR_OFFSHORE_PLOT_WITHIN_5";
  end

  if placementPlot == nil then
    print(
      "RBS_UNSATISFIED player=" .. tostring(startRecord.PlayerID)
      .. " start=" .. tostring(startRecord.PlotIndex)
      .. " resource=" .. resourceDefinition.Type
      .. " reason=" .. unsatisfiedReason
    );
    return false;
  end

  ResourceBuilder.SetResourceType(placementPlot, resourceHash, 1);
  local placedResourceIndex = placementPlot:GetResourceType();
  if placedResourceIndex ~= resourceIndex then
    print(
      "RBS_UNSATISFIED player=" .. tostring(startRecord.PlayerID)
      .. " start=" .. tostring(startRecord.PlotIndex)
      .. " resource=" .. resourceDefinition.Type
      .. " reason=SET_RESOURCE_FAILED"
      .. " expected_index=" .. tostring(resourceIndex)
      .. " actual_index=" .. tostring(placedResourceIndex)
    );
    return false;
  end

  print(
    "RBS_RESOURCE player=" .. tostring(startRecord.PlayerID)
    .. " start=" .. tostring(startRecord.PlotIndex)
    .. " resource=" .. resourceDefinition.Type
    .. " status=" .. placedStatus
    .. " plot=" .. tostring(placementPlot:GetIndex())
    .. " distance=" .. tostring(placementDistance)
  );
  return true;
end

local function PrintFingerprint(starts, skippedOceanStarts, unsatisfiedCount)
  local checksum = 17;

  for startNumber = 1, #starts do
    local startRecord = starts[startNumber];
    local fields = {};
    checksum = AddChecksum(checksum, startRecord.PlayerID + 1);
    checksum = AddChecksum(checksum, startRecord.PlotIndex + 1);

    if startRecord.Plot:IsWater() then
      fields[1] = "OCEAN_START";
      checksum = AddChecksum(checksum, 97);
    else
      for resourceNumber = 1, #STRATEGIC_RESOURCES do
        local resourceDefinition = STRATEGIC_RESOURCES[resourceNumber];
        local resourceRow = GameInfo.Resources[resourceDefinition.Type];
        local resourcePlot = nil;
        local resourceDistance = MAX_DISTANCE + 1;

        if resourceRow ~= nil then
          resourcePlot, resourceDistance = FindExistingResource(startRecord.Nearby, resourceRow.Index);
        end

        local resourcePlotIndex = -1;
        if resourcePlot ~= nil then
          resourcePlotIndex = resourcePlot:GetIndex();
          fields[#fields + 1] = resourceDefinition.Type
            .. ":" .. tostring(resourcePlotIndex)
            .. "@" .. tostring(resourceDistance);
        else
          fields[#fields + 1] = resourceDefinition.Type .. ":MISSING";
          resourceDistance = -1;
        end

        checksum = AddChecksum(checksum, resourceNumber);
        checksum = AddChecksum(checksum, resourcePlotIndex + 1);
        checksum = AddChecksum(checksum, resourceDistance + 1);
      end
    end

    print(
      "RBS_START_FINGERPRINT player=" .. tostring(startRecord.PlayerID)
      .. " start=" .. tostring(startRecord.PlotIndex)
      .. " data=" .. table.concat(fields, ",")
    );
  end

  checksum = AddChecksum(checksum, skippedOceanStarts);
  checksum = AddChecksum(checksum, unsatisfiedCount);
  checksum = AddChecksum(checksum, RoseBetterStarts.BiasChecksum or 0);

  print(
    "RBS_FINGERPRINT version=" .. tostring(VERSION)
    .. " map=" .. tostring(RoseBetterStarts.BaseMapFile or GetConfigurationValue(MapConfiguration, "MAP_SCRIPT"))
    .. " map_seed=" .. GetConfigurationValue(MapConfiguration, "RANDOM_SEED")
    .. " game_seed=" .. GetConfigurationValue(GameConfiguration, "GAME_SYNC_RANDOM_SEED")
    .. " majors=" .. tostring(#starts)
    .. " skipped_ocean=" .. tostring(skippedOceanStarts)
    .. " unsatisfied=" .. tostring(unsatisfiedCount)
    .. " spectators=" .. tostring(RoseBetterStarts.SpectatorCount or 0)
    .. " spectator_filter=" .. tostring(RoseBetterStarts.SpectatorFilter or "none")
    .. " bias_version=" .. tostring(RoseBetterStarts.StartBiasVersion or 0)
    .. " bias_enabled=" .. tostring(RoseBetterStarts.StartBiasEnabled == true)
    .. " bias=" .. tostring(RoseBetterStarts.BiasChecksum or 0)
    .. " checksum=" .. tostring(checksum)
  );
end

function RoseBetterStarts.NormalizeMajorStrategics()
  local starts, reservedStartPlots = CollectMajorStarts();
  local seed = GetMapSeed();
  local skippedOceanStarts = 0;
  local unsatisfiedCount = 0;

  print(
    "RBS_BEGIN version=" .. tostring(VERSION)
    .. " map=" .. tostring(RoseBetterStarts.BaseMapFile or GetConfigurationValue(MapConfiguration, "MAP_SCRIPT"))
    .. " radius=" .. tostring(MAX_DISTANCE)
    .. " majors=" .. tostring(#starts)
  );

  for startNumber = 1, #starts do
    local startRecord = starts[startNumber];

    -- A start at least five tiles from every non-wrapping edge must report 91 plots.
    print(
      "RBS_AREA player=" .. tostring(startRecord.PlayerID)
      .. " start=" .. tostring(startRecord.PlotIndex)
      .. " plots=" .. tostring(#startRecord.Nearby)
    );

    if startRecord.Plot:IsWater() then
      skippedOceanStarts = skippedOceanStarts + 1;
      print(
        "RBS_SKIP player=" .. tostring(startRecord.PlayerID)
        .. " start=" .. tostring(startRecord.PlotIndex)
        .. " reason=OCEAN_START"
      );
    else
      for resourceNumber = 1, #STRATEGIC_RESOURCES do
        local resourceDefinition = STRATEGIC_RESOURCES[resourceNumber];
        local resourceRow = GameInfo.Resources[resourceDefinition.Type];

        if resourceRow == nil then
          unsatisfiedCount = unsatisfiedCount + 1;
          print(
            "RBS_UNSATISFIED player=" .. tostring(startRecord.PlayerID)
            .. " start=" .. tostring(startRecord.PlotIndex)
            .. " resource=" .. resourceDefinition.Type
            .. " reason=RESOURCE_NOT_FOUND"
          );
        elseif not EnsureResource(
          startRecord,
          resourceDefinition,
          resourceRow.Index,
          resourceRow.Hash,
          reservedStartPlots,
          seed
        ) then
          unsatisfiedCount = unsatisfiedCount + 1;
        end
      end
    end
  end

  PrintFingerprint(starts, skippedOceanStarts, unsatisfiedCount);
end

function RoseBetterStarts.Install(baseMapFile)
  if RoseBetterStarts.Installed then
    return;
  end

  if AssignStartingPlots == nil or AssignStartingPlots.Create == nil then
    error("Rose Better Starts could not find AssignStartingPlots.Create");
  end

  RoseBetterStarts.Installed = true;
  RoseBetterStarts.BaseMapFile = baseMapFile;

  if RoseBetterStarts.InstallStartBias ~= nil then
    RoseBetterStarts.InstallStartBias();
  end

  local baseCreate = AssignStartingPlots.Create;
  AssignStartingPlots.Create = function(args)
    local spectators = AliveSpectators();
    local restore = function() end;
    RoseBetterStarts.SpectatorFilter = "none";
    if #spectators > 0 then
      local okInstall, restoreOrError, before, after = pcall(InstallSpectatorFilter, spectators);
      local applied = false;
      if okInstall then
        restore = restoreOrError;
        applied = (after == before - #spectators);
      else
        before = -1;
        after = -1;
      end
      if not applied then
        -- Leave the stock script the unfiltered list, as without the mod.
        restore();
        restore = function() end;
        RoseBetterStarts.SpectatorFilter = "no";
      else
        RoseBetterStarts.SpectatorFilter = "yes";
      end
      print("RBS_SPECTATOR_FILTER spectators=" .. tostring(#spectators)
        .. " applied=" .. tostring(applied and "yes" or "no")
        .. " majors=" .. tostring(before) .. "->" .. tostring(after));
    end
    local ok, startDatabase = pcall(baseCreate, args);
    restore();
    if not ok then
      error(startDatabase, 0);
    end
    AssignSpectatorStarts(spectators);
    RoseBetterStarts.NormalizeMajorStrategics();
    return startDatabase;
  end;
end
