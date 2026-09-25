-- ===========================================================================
-- Rose Better Starts
-- Deterministic, map-generation-only strategic resource normalization.
-- ===========================================================================

RoseBetterStarts = RoseBetterStarts or {};

local VERSION = 3;
local MAX_DISTANCE = 5;
local CHECKSUM_MODULUS = 2147483647;
local MIX_MULTIPLIER = 48271;

local STRATEGIC_RESOURCES = {
  { Type = "RESOURCE_HORSES",  PreferredRings = { 2, 3, 4, 5, 1 } },
  { Type = "RESOURCE_IRON",    PreferredRings = { 2, 3, 4, 5, 1 } },
  { Type = "RESOURCE_NITER",   PreferredRings = { 4, 5, 3, 2, 1 } },
  { Type = "RESOURCE_COAL",    PreferredRings = { 4, 5, 3, 2, 1 } },
  { Type = "RESOURCE_OIL",     PreferredRings = { 4, 5, 3, 2, 1 } },
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

local function CollectStartingPlots(playerIDs, playerCount, startsByIndex, reservedStartPlots)
  for listIndex = 1, playerCount do
    local playerID = playerIDs[listIndex];
    local player = Players[playerID];
    if player ~= nil then
      local startPlot = player:GetStartingPlot();
      if startPlot ~= nil then
        local startIndex = startPlot:GetIndex();
        reservedStartPlots[startIndex] = true;
        if startsByIndex ~= nil then
          startsByIndex[#startsByIndex + 1] = {
            PlayerID = playerID,
            Plot = startPlot,
            PlotIndex = startIndex,
            Nearby = CollectNearbyPlots(startPlot)
          };
        end
      elseif startsByIndex ~= nil then
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
local function FindPlacementPlot(startRecord, resourceDefinition, resourceIndex, resourceHash, reservedStartPlots, seed)
  local bestPlot = nil;
  local bestDistance = -1;
  local bestRank = MAX_DISTANCE + 1;
  local bestKey = CHECKSUM_MODULUS;
  local bestPlotIndex = -1;
  local nearby = startRecord.Nearby;

  for nearbyNumber = 1, #nearby do
    local entry = nearby[nearbyNumber];
    local distance = entry.Distance;
    local plotIndex = entry.PlotIndex;
    if distance >= 1 and reservedStartPlots[plotIndex] ~= true then
      local rank = GetRingRank(resourceDefinition, distance);
      if rank <= bestRank then
        local key = GetTieBreakKey(seed, startRecord.PlotIndex, resourceIndex, plotIndex);
        local better = rank < bestRank
          or key < bestKey
          or (key == bestKey and plotIndex < bestPlotIndex);
        local plot = entry.Plot;
        if better
          and not plot:IsWater()
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
    seed
  );

  if placementPlot == nil then
    print(
      "RBS_UNSATISFIED player=" .. tostring(startRecord.PlayerID)
      .. " start=" .. tostring(startRecord.PlotIndex)
      .. " resource=" .. resourceDefinition.Type
      .. " reason=NO_LEGAL_LAND_PLOT_WITHIN_5"
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
    .. " status=PLACED"
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

  print(
    "RBS_FINGERPRINT version=" .. tostring(VERSION)
    .. " map=" .. tostring(RoseBetterStarts.BaseMapFile or GetConfigurationValue(MapConfiguration, "MAP_SCRIPT"))
    .. " map_seed=" .. GetConfigurationValue(MapConfiguration, "RANDOM_SEED")
    .. " game_seed=" .. GetConfigurationValue(GameConfiguration, "GAME_SYNC_RANDOM_SEED")
    .. " majors=" .. tostring(#starts)
    .. " skipped_ocean=" .. tostring(skippedOceanStarts)
    .. " unsatisfied=" .. tostring(unsatisfiedCount)
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

  local baseCreate = AssignStartingPlots.Create;
  AssignStartingPlots.Create = function(args)
    local startDatabase = baseCreate(args);
    RoseBetterStarts.NormalizeMajorStrategics();
    return startDatabase;
  end;
end
