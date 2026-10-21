-- ===========================================================================
-- Rose Better Starts
-- Start-bias enforcement for major civilizations, driven by the game's own
-- StartBias tables (StartBiasTerrains, StartBiasFeatures, StartBiasResources,
-- StartBiasRivers). Deterministic, runs once during map generation inside the
-- stock AssignStartingPlots flow.
-- ===========================================================================
--
-- How the stock script places majors: the engine divides the land into one
-- region per major civilization; the script picks the most fertile valid plot
-- of each region; only then does it match civilizations to those plots by
-- bias. A civilization gets its bias only when one of the already-chosen
-- plots happens to satisfy it, which is why Russia rarely sees tundra.
--
-- This module replaces the two steps that decide that outcome:
--   __SetStartMajor   the plot picked inside each region
--   __InitStartBias   the civilization-to-plot matching (majors only)
-- Everything else is the stock code: region division, the validity checks
-- a start must pass, Balanced/Legendary resources, city-states (placed after
-- every major, as the stock script already does), and ocean starts.
--
-- Rules:
--   * A civilization's tier 1 and tier 2 rows are REQUIRED, all of them
--     together, whenever at least one region has a valid plot that satisfies
--     them. A tier 3 row group is required only when it is the civilization's
--     strongest tier. If no region can satisfy every required tier, the
--     strongest tier alone is required; if no region can satisfy that
--     either, nothing is enforced. Tiers 4 and 5 are never required. Every
--     tier a plot satisfies adds a weight (5 for tier 1 down to 1 for tier 5)
--     to a preference score, except a tier 3 that is not the civilization's
--     strongest tier: in the game's data such rows are fallback terrain
--     lists (Maya's "any land"), not a wish for that terrain, so they are
--     neither required nor scored.
--   * Within a tier, rows of one kind are pooled (the stock matching treats a
--     tier's rows as alternatives): a tier is satisfied when its terrain rows
--     together, its feature rows together, its resource rows together, its
--     river row or its coast row reach the minimum for that kind. Measured
--     within the stock ranges (terrain and features within 3 tiles, resources
--     within 2, the river on the start plot itself); the start plot is not
--     counted. Terrain needs TERRAIN_MINIMUM tiles, one of them next to the
--     start plot (TERRAIN_ADJACENT_MINIMUM; a civilization listed in
--     CIV_TERRAIN_ADJACENT_MINIMUM, Mali, ranks a region that gives it
--     that many adjacent above a region that gives it the standard one,
--     and either above a region with nothing, in its own planning slot:
--     enforced=strict or all with level=strict or standard in the log; at
--     pick time, when spacing blocks every strict plot, the standard rule
--     decides) unless every terrain of the group
--     is a mountain (the stock validity check allows at most one impassable
--     neighbour, none on a Balanced start); TERRAIN_COAST needs the start
--     plot next to sea water
--     (so a Harbor fits at the capital); features need FEATURE_MINIMUM, one
--     of them adjacent (RARE_FEATURE_MINIMUM and no adjacency when the group
--     holds a rare feature); resources RESOURCE_MINIMUM. So Canada and
--     Russia start on the tundra edge and Vietnam inside its woods, not a
--     few tiles away from them.
--   * Civilizations with enforced tiers are placed first, those with the
--     fewest satisfying regions before the others, then by strongest tier;
--     ties break by a key derived from the map seed and the player slot,
--     never with a draw from the map generator's random stream, so lobby
--     order alone does not decide. That greedy pass is then repaired by a
--     maximum matching (augmenting paths): when a civilization was left
--     without a satisfying region although one could be freed by moving
--     another civilization to a region that also satisfies it, the regions
--     are exchanged, so the number of civilizations with a satisfying
--     region is the largest the map allows.
--   * Among a region's plots that meet the enforced tiers (or, when none
--     does, the plots that meet the most of them), fertility decides
--     first. Fertility here is a neighbourhood value: the engine's per-plot
--     fertility (twice the plot's non-Gold yields plus its Gold, +2 with
--     fresh water, +1 on a river, +1 per adjacent mountain, +1 next to a
--     natural wonder, +5 for a luxury, -5 on tundra, 0 on snow, mountains
--     and next to ice) summed over the plot and the plots within
--     FERTILITY_RING_RADIUS, the plot and its first ring at double weight.
--     The stock major pick sorts by the single-plot value alone, with a
--     region weighting that is 0 near region borders (and, through a bug
--     in the engine's test, for whole regions), which is why stock starts
--     vary so much; the single-plot and weighted values are only logged.
--     The plots within PREFERENCE_BAND_PERCENT of the best fertility
--     form a band, and within the band the highest preference score wins,
--     then fertility, then plot index. A preference can tilt a start within
--     the band but never pull it below the band. Each civilization takes the
--     free region whose best such plot ranks highest by (enforced tiers met,
--     number of satisfying plots up to REGION_ROBUSTNESS_CAP, the region's
--     best fertility, preference score; the lowest region index on a tie).
--     When the stock loop reaches that region, the civilization
--     gets the best such plot that keeps the stock distance from the starts
--     already placed; when none does, the stock pick decides, as without the
--     mod.
--   * Civilization tile bonuses. Three civilizations get yields from the
--     terrain their bias sends them to that the engine's plot value does
--     not know (it even clamps a tundra tile to 0): Mother Russia (+1
--     Production and +1 Faith on tundra, counted as the Production alone),
--     Laurier's farms on tundra (counted as +1 Food) and Mali's Songs of
--     the Jeli (+1 Food and +1 Faith on desert next to the City Center,
--     counted double for a stronger pull toward desert). CIV_TILE_BONUSES adds them,
--     in the engine's units, to that civilization's own view of a plot's
--     ring fertility, so its band and its best plot are judged with its
--     ability in mind; every other civilization sees the plain value.
--   * Mali's desert. The stock validity check rejects a major start with
--     more than 2 desert tiles among the capital and its six neighbours (1
--     on a Balanced start), so no civilization ever starts inside a desert.
--     For the civilizations in CIV_ADJACENT_DESERT_LIMIT (Mali) that one
--     rule is lifted up to the listed count: a plot that fails only the
--     desert cap stays a candidate that only they may take; every other
--     civilization and the stock fallback keep the game's cap.
--   * Crowding. Picks are made region by region, so a pick can leave a
--     later region with no satisfying plot outside the stock buffer (its
--     civilization then falls to the stock pick, whose fallback plot fails
--     a validity check). Among a civilization's equally good plots (same
--     level, within the band), one that would leave every other unplaced
--     region some satisfying plot (some valid plot, for a region with no
--     satisfying plot left) is preferred over one that would box a region
--     in; and after the preference score, when a region is down to
--     CROWDING_SCARCE_LIVE such plots or fewer, one that blocks fewer of
--     them. Otherwise fertility decides within the band as usual.
--   * Final re-matching. Once every region has its plot, civilizations whose
--     enforced tiers are unmet at their own plot look for another picked
--     plot that meets them, by augmenting paths: a civilization gives up its
--     plot only to move to one that also meets its own enforced tiers, or
--     when it has none to meet. The displaced civilizations take the plots
--     left over. The stock script matches this way too, over plots chosen
--     without any bias; here it only repairs what crowding spoiled.

RoseBetterStarts = RoseBetterStarts or {};

local BIAS_VERSION = 2;
local ENFORCE_START_BIASES = true;

-- Tiers 1 and 2 are always required, all of them together; tier 3 only when
-- it is the civilization's strongest tier; tiers 4 and 5 never.
local ALWAYS_REQUIRED_MAX_TIER = 2;
local STRONGEST_REQUIRED_MAX_TIER = 3;
-- Among plots that meet the enforced tiers, a preference may choose any plot
-- whose fertility is within this share of the best such plot's fertility.
local PREFERENCE_BAND_PERCENT = 15;
local TERRAIN_RANGE = 3;
local RESOURCE_RANGE = 2;
-- Plots within this distance of a start count toward its fertility (0: the
-- engine's single-plot value alone).
local FERTILITY_RING_RADIUS = 2;
-- Yields a civilization's ability adds to tiles its bias sends it to, which
-- the engine's plot fertility does not know. Values are in the engine's
-- units (2 per Food, Production, Faith or Science), added per matching tile
-- to that civilization's ring fertility with the ring weights (the plot and
-- its first ring double), within MaxDistance of the plot.
local CIV_TILE_BONUSES = {
  -- Mother Russia: +1 Production and +1 Faith on tundra tiles, counted as
  -- the Production alone (tundra stays weaker for growth than Canada's
  -- farmed tundra).
  CIVILIZATION_RUSSIA = { MaxDistance = 2, Terrains = { TERRAIN_TUNDRA = 2, TERRAIN_TUNDRA_HILLS = 2 } },
  -- The Last Best West: farms on tundra, counted as +1 Food.
  CIVILIZATION_CANADA = { MaxDistance = 2, Terrains = { TERRAIN_TUNDRA = 2, TERRAIN_TUNDRA_HILLS = 2 } },
  -- Songs of the Jeli: +1 Food and +1 Faith on desert tiles next to the
  -- City Center (the centre tile counted too), counted double for a
  -- stronger pull toward desert.
  CIVILIZATION_MALI = { MaxDistance = 1, Terrains = { TERRAIN_DESERT = 8, TERRAIN_DESERT_HILLS = 8 } }
};
-- A terrain bias needs TERRAIN_ADJACENT_MINIMUM matching tiles next to the
-- start plot; a civilization listed here first asks for this many (its
-- strict profile) and falls back to the standard rule when no region, or
-- at pick time no plot, can give it. With the stock desert cap lifted for
-- Mali, three adjacent desert tiles are possible.
local CIV_TERRAIN_ADJACENT_MINIMUM = {
  CIVILIZATION_MALI = 3
};
-- The stock start check allows at most 2 desert tiles among the capital and
-- its six neighbours (1 on a Balanced start). A civilization listed here may
-- start on a plot with up to this many instead, when the plot passes every
-- other stock check; 7 lifts the cap entirely.
local CIV_ADJACENT_DESERT_LIMIT = {
  CIVILIZATION_MALI = 7
};
-- Valid plots kept per region, in fertility order. The stock pick walks the
-- whole region until one plot clears every check, so a low cap would leave
-- the plan without a plot that keeps the stock distance from its neighbours
-- while the stock pick would still find one; 400 covers a Huge map's regions.
local MAX_CANDIDATES_PER_REGION = 400;

local TERRAIN_MINIMUM = 4;
local TERRAIN_ADJACENT_MINIMUM = 1;
local FEATURE_MINIMUM = 5;
local FEATURE_ADJACENT_MINIMUM = 1;
local RARE_FEATURE_MINIMUM = 1;
local RESOURCE_MINIMUM = 1;
local COAST_MINIMUM = 1;

-- Regions are compared by how many satisfying plots they hold, capped here,
-- so a region with one lone satisfying plot loses to one with several while
-- fertility still decides between well-stocked regions.
local REGION_ROBUSTNESS_CAP = 4;

-- Look-ahead at pick time: the share of a region's remaining plots a
-- candidate would block, in thousandths, summed over the unplaced regions
-- that are down to CROWDING_SCARCE_LIVE such plots or fewer (a region with
-- more to spare costs nothing, so fertility keeps deciding within the band).
local CROWDING_SCALE = 1000;
local CROWDING_SCARCE_LIVE = 8;

local TIER_WEIGHT_BASE = 6;
local SCORE_SCALE = 1000;
local CHECKSUM_MODULUS = 2147483647;

local COAST_TERRAIN = "TERRAIN_COAST";
local RARE_FEATURES = {
  FEATURE_GEOTHERMAL_FISSURE = true,
  FEATURE_VOLCANO = true
};

local EMPTY_PROFILE = { CivType = "NONE", Tiers = {}, RequiredTiers = {}, StrongestTier = nil };

local BaseSetStartMajor = nil;
local BaseInitStartBias = nil;

local function AddChecksum(checksum, value)
  return (checksum * 31 + value) % CHECKSUM_MODULUS;
end

local function YesNo(flag)
  if flag then
    return "yes";
  end
  return "no";
end

-- Plots within radius of a plot, the plot itself excluded, with the tile
-- attributes the bias rules read, so later evaluations make no engine calls.
-- The square offset window contains every plot within that hex distance;
-- GetPlotDistance does the real filtering and the seen set guards wrapped
-- duplicates. Counting is order-independent, so the list is not sorted.
local function CollectWithin(centerPlot, radius)
  local centerIndex = centerPlot:GetIndex();
  local centerX = centerPlot:GetX();
  local centerY = centerPlot:GetY();
  local nearby = {};
  local seen = {};

  for dy = -radius, radius do
    for dx = -radius, radius do
      local plot = Map.GetPlotXY(centerX, centerY, dx, dy, radius * 2);
      if plot ~= nil then
        local plotIndex = plot:GetIndex();
        if seen[plotIndex] ~= true then
          seen[plotIndex] = true;
          local distance = Map.GetPlotDistance(centerIndex, plotIndex);
          if distance >= 1 and distance <= radius then
            local resource = -1;
            if plot:GetResourceCount() > 0 then
              resource = plot:GetResourceType();
            end
            nearby[#nearby + 1] = {
              PlotIndex = plotIndex,
              Distance = distance,
              Terrain = plot:GetTerrainType(),
              Feature = plot:GetFeatureType(),
              Resource = resource,
              SeaWater = (plot:IsWater() and not plot:IsLake())
            };
          end
        end
      end
    end
  end

  return nearby;
end

local function BuildIndexByType(rows, field)
  local byType = {};
  for row in rows() do
    if row[field] ~= nil then
      byType[row[field]] = row.Index;
    end
  end
  return byType;
end

local function AddBiasRow(profiles, civType, tier, kind, name, index, passable)
  if civType == nil or tier == nil then
    return;
  end
  -- A type missing from this ruleset (content not enabled) cannot be matched.
  if kind ~= "RIVER" and index == nil then
    return;
  end
  if kind == "TERRAIN" and name == COAST_TERRAIN then
    kind = "COAST";
  end

  local profile = profiles[civType];
  if profile == nil then
    profile = { CivType = civType, TierRows = {} };
    profiles[civType] = profile;
  end

  local rows = profile.TierRows[tier];
  if rows == nil then
    rows = {};
    profile.TierRows[tier] = rows;
  end

  rows[#rows + 1] = { Kind = kind, Name = name, Index = index, Passable = (passable ~= false) };
end

local function CompareRows(left, right)
  if left.Kind ~= right.Kind then
    return left.Kind < right.Kind;
  end
  return left.Name < right.Name;
end

-- One group per kind in a tier: the indices its rows match, pooled, with the
-- minimum count that satisfies the group. Kinds: TERRAIN, COAST, FEATURE,
-- RESOURCE, RIVER.
local function BuildGroups(rows)
  local byKind = {};
  local kinds = {};
  for r = 1, #rows do
    local row = rows[r];
    local group = byKind[row.Kind];
    if group == nil then
      group = { Kind = row.Kind, Indices = {}, Rare = false, Passable = false, Count = 0 };
      byKind[row.Kind] = group;
      kinds[#kinds + 1] = row.Kind;
    end
    if row.Index ~= nil then
      group.Indices[row.Index] = true;
    end
    if row.Kind == "FEATURE" and RARE_FEATURES[row.Name] == true then
      group.Rare = true;
    end
    if row.Passable then
      group.Passable = true;
    end
    group.Count = group.Count + 1;
  end
  table.sort(kinds);

  local groups = {};
  for k = 1, #kinds do
    local group = byKind[kinds[k]];
    group.AdjacentMinimum = 0;
    if group.Kind == "TERRAIN" then
      group.Minimum = TERRAIN_MINIMUM;
      -- A group of mountains cannot ask for an adjacent one: the stock
      -- validity check allows at most one impassable neighbour, none on a
      -- Balanced start.
      if group.Passable then
        group.AdjacentMinimum = TERRAIN_ADJACENT_MINIMUM;
      end
    elseif group.Kind == "COAST" then
      group.Minimum = COAST_MINIMUM;
    elseif group.Kind == "FEATURE" then
      if group.Rare then
        group.Minimum = RARE_FEATURE_MINIMUM;
      else
        group.Minimum = FEATURE_MINIMUM;
        group.AdjacentMinimum = FEATURE_ADJACENT_MINIMUM;
      end
    elseif group.Kind == "RESOURCE" then
      group.Minimum = RESOURCE_MINIMUM;
    else
      group.Minimum = 1;
    end
    groups[k] = group;
  end
  return groups;
end

local function TierLabel(profile)
  local parts = {};
  for t = 1, #profile.Tiers do
    local tier = profile.Tiers[t];
    local names = {};
    for r = 1, #tier.Rows do
      names[r] = tier.Rows[r].Name;
    end
    parts[t] = "T" .. tostring(tier.Tier) .. ":" .. table.concat(names, "/");
  end
  if #parts == 0 then
    return "none";
  end
  return table.concat(parts, ",");
end

-- One profile per civilization type with bias rows: the tiers sorted by tier
-- number, each with its rows (sorted, for the log) and its groups, the
-- strongest tier (when it is tier 1 to 3) and the required tiers.
local function LoadBiasProfiles()
  local terrainIndex = BuildIndexByType(GameInfo.Terrains, "TerrainType");
  local terrainMountain = {};
  for row in GameInfo.Terrains() do
    if row.TerrainType ~= nil then
      terrainMountain[row.TerrainType] = (row.Mountain == true or row.Mountain == 1);
    end
  end
  local featureIndex = BuildIndexByType(GameInfo.Features, "FeatureType");
  local resourceIndex = BuildIndexByType(GameInfo.Resources, "ResourceType");
  local profiles = {};
  local civTypes = {};

  for row in GameInfo.StartBiasTerrains() do
    AddBiasRow(profiles, row.CivilizationType, row.Tier, "TERRAIN", row.TerrainType, terrainIndex[row.TerrainType], terrainMountain[row.TerrainType] ~= true);
  end
  for row in GameInfo.StartBiasFeatures() do
    AddBiasRow(profiles, row.CivilizationType, row.Tier, "FEATURE", row.FeatureType, featureIndex[row.FeatureType]);
  end
  for row in GameInfo.StartBiasResources() do
    AddBiasRow(profiles, row.CivilizationType, row.Tier, "RESOURCE", row.ResourceType, resourceIndex[row.ResourceType]);
  end
  for row in GameInfo.StartBiasRivers() do
    AddBiasRow(profiles, row.CivilizationType, row.Tier, "RIVER", "RIVER", 0);
  end

  for civType, _ in pairs(profiles) do
    civTypes[#civTypes + 1] = civType;
  end
  table.sort(civTypes);

  for c = 1, #civTypes do
    local profile = profiles[civTypes[c]];
    local tiers = {};
    local tierNumbers = {};
    for tier, _ in pairs(profile.TierRows) do
      tierNumbers[#tierNumbers + 1] = tier;
    end
    table.sort(tierNumbers);
    for t = 1, #tierNumbers do
      local rows = profile.TierRows[tierNumbers[t]];
      table.sort(rows, CompareRows);
      tiers[t] = { Tier = tierNumbers[t], Rows = rows, Groups = BuildGroups(rows) };
    end
    profile.Tiers = tiers;
    profile.TierRows = nil;
    profile.StrongestTier = nil;
    profile.RequiredTiers = {};
    if #tiers > 0 then
      local strongest = tiers[1].Tier;
      if strongest <= STRONGEST_REQUIRED_MAX_TIER then
        profile.StrongestTier = strongest;
      end
      for t = 1, #tiers do
        local tier = tiers[t].Tier;
        if tier <= ALWAYS_REQUIRED_MAX_TIER or (tier == strongest and tier <= STRONGEST_REQUIRED_MAX_TIER) then
          profile.RequiredTiers[#profile.RequiredTiers + 1] = tier;
        end
      end
    end
  end

  -- Tile bonuses, by terrain index; a civilization without bias rows still
  -- gets a profile for its bonus.
  local bonusCivs = {};
  for civType, _ in pairs(CIV_TILE_BONUSES) do
    bonusCivs[#bonusCivs + 1] = civType;
  end
  table.sort(bonusCivs);
  for n = 1, #bonusCivs do
    local civType = bonusCivs[n];
    local bonus = CIV_TILE_BONUSES[civType];
    local names = {};
    for name, _ in pairs(bonus.Terrains) do
      names[#names + 1] = name;
    end
    table.sort(names);
    local byIndex = {};
    local any = false;
    for k = 1, #names do
      local index = terrainIndex[names[k]];
      if index ~= nil then
        byIndex[index] = bonus.Terrains[names[k]];
        any = true;
      end
    end
    if any then
      local profile = profiles[civType];
      if profile == nil then
        profile = { CivType = civType, Tiers = {}, RequiredTiers = {}, StrongestTier = nil };
        profiles[civType] = profile;
      end
      profile.TileBonus = { MaxDistance = bonus.MaxDistance, ByIndex = byIndex };
    end
  end

  -- Desert limits: a civilization without bias rows still gets a profile.
  local desertCivs = {};
  for civType, _ in pairs(CIV_ADJACENT_DESERT_LIMIT) do
    desertCivs[#desertCivs + 1] = civType;
  end
  table.sort(desertCivs);
  for n = 1, #desertCivs do
    local civType = desertCivs[n];
    local profile = profiles[civType];
    if profile == nil then
      profile = { CivType = civType, Tiers = {}, RequiredTiers = {}, StrongestTier = nil };
      profiles[civType] = profile;
    end
    profile.DesertLimit = CIV_ADJACENT_DESERT_LIMIT[civType];
  end

  -- Strict profiles: a copy with the raised adjacency minimum on the
  -- passable terrain groups, tried before the standard profile; Base points
  -- back to the standard one for the fallback. Built last so the copy
  -- carries the tile bonus and the desert limit.
  local strictCivs = {};
  for civType, _ in pairs(CIV_TERRAIN_ADJACENT_MINIMUM) do
    strictCivs[#strictCivs + 1] = civType;
  end
  table.sort(strictCivs);
  for n = 1, #strictCivs do
    local civType = strictCivs[n];
    local profile = profiles[civType];
    local adjacentMinimum = CIV_TERRAIN_ADJACENT_MINIMUM[civType];
    if profile ~= nil and #profile.Tiers > 0 then
      local strict = {
        CivType = civType, Tiers = {}, RequiredTiers = profile.RequiredTiers, StrongestTier = profile.StrongestTier,
        TileBonus = profile.TileBonus, DesertLimit = profile.DesertLimit, Base = profile
      };
      local raised = false;
      for t = 1, #profile.Tiers do
        local tier = profile.Tiers[t];
        local groups = {};
        for g = 1, #tier.Groups do
          local group = tier.Groups[g];
          local copy = {
            Kind = group.Kind, Indices = group.Indices, Rare = group.Rare, Passable = group.Passable,
            Count = group.Count, Minimum = group.Minimum, AdjacentMinimum = group.AdjacentMinimum
          };
          if copy.Kind == "TERRAIN" and copy.Passable and copy.AdjacentMinimum < adjacentMinimum then
            copy.AdjacentMinimum = adjacentMinimum;
            raised = true;
          end
          groups[g] = copy;
        end
        strict.Tiers[t] = { Tier = tier.Tier, Rows = tier.Rows, Groups = groups };
      end
      if raised then
        profile.Strict = strict;
      end
    end
  end

  return profiles;
end

-- Matching tiles of a group around a plot: the total within the group's
-- range and the number of them adjacent to the plot.
local function CountGroup(group, plot, nearby)
  if group.Kind == "RIVER" then
    if plot:IsRiver() then
      return 1, 1;
    end
    return 0, 0;
  end

  local count = 0;
  local adjacent = 0;
  if group.Kind == "COAST" then
    for n = 1, #nearby do
      local entry = nearby[n];
      if entry.Distance == 1 and entry.SeaWater then
        count = count + 1;
      end
    end
    return count, count;
  end

  local maxDistance = TERRAIN_RANGE;
  if group.Kind == "RESOURCE" then
    maxDistance = RESOURCE_RANGE;
  end
  local indices = group.Indices;

  for n = 1, #nearby do
    local entry = nearby[n];
    if entry.Distance <= maxDistance then
      local matches = false;
      if group.Kind == "TERRAIN" then
        matches = (indices[entry.Terrain] == true);
      elseif group.Kind == "FEATURE" then
        matches = (indices[entry.Feature] == true);
      else
        matches = (entry.Resource >= 0 and indices[entry.Resource] == true);
      end
      if matches then
        count = count + 1;
        if entry.Distance == 1 then
          adjacent = adjacent + 1;
        end
      end
    end
  end

  return count, adjacent;
end

-- Evaluates a plot against a profile. Returns the satisfied tiers (tier
-- number -> true), the preference score (an integer: the tier weights of
-- every satisfied tier) and each tier's best group count (for the log).
local function EvaluatePlot(profile, plot, nearby)
  local flags = {};
  local counts = {};
  local score = 0;

  for t = 1, #profile.Tiers do
    local tier = profile.Tiers[t];
    local tierSatisfied = false;
    local tierBest = 0;

    for g = 1, #tier.Groups do
      local group = tier.Groups[g];
      local count, adjacent = CountGroup(group, plot, nearby);
      if count >= group.Minimum and adjacent >= group.AdjacentMinimum then
        tierSatisfied = true;
      end
      if count > tierBest then
        tierBest = count;
      end
    end

    if tierSatisfied then
      flags[tier.Tier] = true;
      local weight = TIER_WEIGHT_BASE - tier.Tier;
      if weight < 1 then
        weight = 1;
      end
      -- A tier 3 below a stronger tier is a fallback list, not a wish.
      if tier.Tier == STRONGEST_REQUIRED_MAX_TIER and profile.StrongestTier ~= tier.Tier then
        weight = 0;
      end
      score = score + weight * SCORE_SCALE;
    end
    counts[tier.Tier] = tierBest;
  end

  return flags, score, counts;
end

-- True when every tier in the list is satisfied (an empty list is met), and
-- the number of listed tiers that are.
local function TiersMet(flags, tiers)
  local met = 0;
  for n = 1, #tiers do
    if flags[tiers[n]] == true then
      met = met + 1;
    end
  end
  return met == #tiers, met;
end

local function TierListLabel(tiers)
  if tiers == nil or #tiers == 0 then
    return "none";
  end
  local parts = {};
  for n = 1, #tiers do
    parts[n] = "T" .. tostring(tiers[n]);
  end
  return table.concat(parts, "+");
end

-- A plot is within the preference band when its fertility is at least
-- (100 - PREFERENCE_BAND_PERCENT) percent of the best fertility; with a best
-- fertility of zero or less there is no band.
local function InBand(fertility, bestFertility)
  if bestFertility <= 0 then
    return fertility >= bestFertility;
  end
  return fertility * 100 >= bestFertility * (100 - PREFERENCE_BAND_PERCENT);
end

-- The stock __GetValidAdjacent for a major start (minor 0), with the desert
-- rule separated: returns whether the plot passes it all, whether it passes
-- everything but the desert cap, and the desert count (the plot and its six
-- neighbours). Kept in step with the stock function: the row limits, the
-- impassable and water limits, the desert and snow caps, and the Balanced
-- start's stricter values.
local function ValidAdjacentDetail(self, plot)
  local impassable = 0;
  local water = 0;
  local desert = 0;
  local snow = 0;
  local gridWidth, gridHeight = Map.GetGridSize();
  local terrainType = plot:GetTerrainType();
  if terrainType == g_TERRAIN_TYPE_SNOW or terrainType == g_TERRAIN_TYPE_SNOW_HILLS then
    snow = snow + 1;
  end
  if terrainType == g_TERRAIN_TYPE_DESERT or terrainType == g_TERRAIN_TYPE_DESERT_HILLS then
    desert = desert + 1;
  end
  local maxRows = math.ceil(gridHeight * self.uiStartMaxY / 100);
  local minRows = math.ceil(gridHeight * self.uiStartMinY / 100);
  if plot:GetY() <= minRows or plot:GetY() > gridHeight - maxRows or (maxRows == 0 and minRows == 0) then
    return false, false, desert;
  end
  for direction = 0, DirectionTypes.NUM_DIRECTION_TYPES - 1, 1 do
    local adjacentPlot = Map.GetAdjacentPlot(plot:GetX(), plot:GetY(), direction);
    if adjacentPlot ~= nil then
      if adjacentPlot:GetX() >= 0 and adjacentPlot:GetY() < gridHeight then
        local adjacentTerrain = adjacentPlot:GetTerrainType();
        if adjacentPlot:IsImpassable() == true then
          impassable = impassable + 1;
        end
        if adjacentPlot:IsWater() == true then
          water = water + 1;
        end
        if adjacentTerrain == g_TERRAIN_TYPE_SNOW or adjacentTerrain == g_TERRAIN_TYPE_SNOW_HILLS then
          snow = snow + 1;
        end
        if adjacentTerrain == g_TERRAIN_TYPE_DESERT or adjacentTerrain == g_TERRAIN_TYPE_DESERT_HILLS then
          desert = desert + 1;
        end
      else
        impassable = impassable + 1;
      end
    end
  end
  local balancedStart = 0;
  if self.uiStartConfig == 1 then
    balancedStart = 1;
  end
  local rejected = false;
  if (impassable >= 2 - balancedStart or (self.landMap == true and impassable >= 2)) and self.waterMap == false then
    rejected = true;
  elseif self.waterMap == true and impassable >= 2 - balancedStart then
    rejected = true;
  elseif water + impassable >= 4 - balancedStart and self.waterMap == false then
    rejected = true;
  elseif water >= 3 - balancedStart then
    rejected = true;
  elseif water >= 4 and self.waterMap == true then
    rejected = true;
  elseif snow > 1 - balancedStart then
    rejected = true;
  end
  local desertRejected = (desert > 2 - balancedStart);
  return (not rejected) and (not desertRejected), not rejected, desert;
end

-- The stock __SetStartMajor checks, in the stock order, without the distance
-- check against other majors (applied at pick time against the starts
-- already placed). Returns "ok", "desert" (fails only the desert cap of the
-- adjacency check, usable by a civilization in CIV_ADJACENT_DESERT_LIMIT)
-- or "fail", and the desert count.
local function CheckPlot(self, plot)
  if plot:IsImpassable() == true then
    return "fail", 0;
  end
  if plot:IsWater() == true then
    return "fail", 0;
  end
  if (math.ceil(self.iDefaultNumberMajor * 1.25) + self.iDefaultNumberMinor > self.iNumMinorCivs + self.iNumMajorCivs) then
    if self:__LuxuryBuffer(plot) == false then
      return "fail", 0;
    end
  end
  if self:__GetWaterCheck(plot) == false then
    return "fail", 0;
  end
  local passesAll, passesExceptDesert, desert = ValidAdjacentDetail(self, plot);
  if not passesExceptDesert then
    return "fail", desert;
  end
  if self:__NaturalWonderBuffer(plot, false) == false then
    return "fail", desert;
  end
  if plot:GetResourceCount() > 0 and not self:__BonusResource(plot) then
    return "fail", desert;
  end
  if plot:GetFeatureType() == g_FEATURE_OASIS then
    return "fail", desert;
  end
  if passesAll then
    if self:__GetValidAdjacent(plot, 0) ~= true and RoseBetterStarts.AdjacencyMismatchPrinted ~= true then
      -- The ported check and the instance's own disagree: another mod may
      -- have replaced __GetValidAdjacent. Printed once; the port stands.
      RoseBetterStarts.AdjacencyMismatchPrinted = true;
      print("RBS_BIAS_CHECK_MISMATCH plot=" .. tostring(plot:GetIndex()));
    end
    return "ok", desert;
  end
  return "desert", desert;
end

-- The stock __MajorCivBuffer rejects a plot within this distance of another
-- major's start (distance <= limit).
local function MajorBufferLimit()
  local maxStart = GlobalParameters.START_DISTANCE_MAJOR_CIVILIZATION or 9;
  local range = GlobalParameters.START_DISTANCE_RANGE_MAJOR or 2;
  return maxStart - range;
end

local function FarFromPlaced(plotIndex, placedPlots, limit)
  for n = 1, #placedPlots do
    if Map.GetPlotDistance(plotIndex, placedPlots[n]:GetIndex()) <= limit then
      return false;
    end
  end
  return true;
end

-- The neighbourhood fertility of a plot: the engine's per-plot fertility of
-- the plot and of every plot within FERTILITY_RING_RADIUS, the plot and its
-- first ring at double weight. Water plots count with their own (small)
-- value. Read once per candidate at planning time; nothing the picks change
-- (a bonus resource removed under a start, food and production added next
-- to it) lies within reach of a candidate that keeps the stock distance.
local function RingFertility(self, plot)
  local centerIndex = plot:GetIndex();
  local total = 2 * self:__BaseFertility(centerIndex);
  if FERTILITY_RING_RADIUS <= 0 then
    return total;
  end
  local centerX = plot:GetX();
  local centerY = plot:GetY();
  local seen = {};
  seen[centerIndex] = true;
  for dy = -FERTILITY_RING_RADIUS, FERTILITY_RING_RADIUS do
    for dx = -FERTILITY_RING_RADIUS, FERTILITY_RING_RADIUS do
      local other = Map.GetPlotXY(centerX, centerY, dx, dy, FERTILITY_RING_RADIUS * 2);
      if other ~= nil then
        local otherIndex = other:GetIndex();
        if seen[otherIndex] ~= true then
          seen[otherIndex] = true;
          local distance = Map.GetPlotDistance(centerIndex, otherIndex);
          if distance >= 1 and distance <= FERTILITY_RING_RADIUS then
            local weight = 1;
            if distance == 1 then
              weight = 2;
            end
            total = total + weight * self:__BaseFertility(otherIndex);
          end
        end
      end
    end
  end
  return total;
end

-- Valid plots of one region by neighbourhood fertility, then plot index; at
-- most MAX_CANDIDATES_PER_REGION of them. The engine's single-plot value
-- and its region-weighted value are kept for the log.
local function CollectRegionCandidates(self, regionIndex, plotIndices)
  local candidates = {};
  if plotIndices == nil then
    return candidates;
  end

  -- Validity first (cheap engine checks), the ring value only for the
  -- plots that pass.
  local valid = {};
  for n = 1, #plotIndices do
    local plotIndex = plotIndices[n];
    local plot = Map.GetPlotByIndex(plotIndex);
    if plot ~= nil then
      local status, desert = CheckPlot(self, plot);
      if status ~= "fail" then
        valid[#valid + 1] = {
          Plot = plot,
          PlotIndex = plotIndex,
          Y = plot:GetY(),
          Terrain = plot:GetTerrainType(),
          Fertility = RingFertility(self, plot),
          PlotFertility = self:__BaseFertility(plotIndex),
          Weighted = self:__WeightedFertility(plotIndex, regionIndex, true),
          Nearby = nil,
          Blocked = false,
          DesertOnly = (status == "desert"),
          DesertCount = desert
        };
      end
    end
  end
  table.sort(valid, function(left, right)
    if left.Fertility == right.Fertility then
      return left.PlotIndex < right.PlotIndex;
    end
    return left.Fertility > right.Fertility;
  end);

  for n = 1, #valid do
    if #candidates >= MAX_CANDIDATES_PER_REGION then
      break;
    end
    candidates[#candidates + 1] = valid[n];
  end

  return candidates;
end

local function RobustnessKey(best)
  local count = best.SatisfyingCount or 0;
  if count > REGION_ROBUSTNESS_CAP then
    count = REGION_ROBUSTNESS_CAP;
  end
  return count;
end

-- Whether a civilization may take a candidate: every civilization may take
-- a plot that passes the stock checks; a plot that fails only the stock
-- desert cap is open to a civilization whose DesertLimit covers its count.
local function AllowedFor(profile, candidate)
  if candidate.DesertOnly ~= true then
    return true;
  end
  local limit = profile.DesertLimit;
  return limit ~= nil and (candidate.DesertCount or 0) <= limit;
end

-- A civilization's tile bonus at a candidate: its bonus value for the plot's
-- own terrain (double weight) and for each plot within the bonus distance
-- (double weight in the first ring), from the cached nearby tiles.
local function TileBonusFor(profile, candidate)
  local bonus = profile.TileBonus;
  if bonus == nil then
    return 0;
  end
  local total = 0;
  local own = bonus.ByIndex[candidate.Terrain];
  if own ~= nil then
    total = total + 2 * own;
  end
  local nearby = candidate.Nearby or {};
  for n = 1, #nearby do
    local entry = nearby[n];
    if entry.Distance <= bonus.MaxDistance and entry.Distance <= FERTILITY_RING_RADIUS then
      local value = bonus.ByIndex[entry.Terrain];
      if value ~= nil then
        local weight = 1;
        if entry.Distance == 1 then
          weight = 2;
        end
        total = total + weight * value;
      end
    end
  end
  return total;
end

-- The best candidate for a profile with the given enforced tiers; with
-- placedPlots, only candidates that keep the stock distance from them.
-- Plots meeting the most enforced tiers come first (all of them when
-- possible); among them, the plots within the preference band of the best
-- fertility compete by preference score, then fertility, then plot index.
-- The result carries BestFertility (the fertility the civilization could
-- have had without preferences), MetCount (the enforced tiers met) and
-- SatisfyingCount (plots at that level). With a crowding function (pick
-- time), the plots within the band are compared by the regions they would
-- box in before the preference score, and by the share of other regions'
-- satisfying plots they block after it.
local function BestCandidateForCiv(profile, candidates, placedPlots, limit, enforcedTiers, crowding)
  local evaluated = {};
  local bestMet = -1;

  for n = 1, #candidates do
    local candidate = candidates[n];
    if AllowedFor(profile, candidate) and (placedPlots == nil or FarFromPlaced(candidate.PlotIndex, placedPlots, limit)) then
      if candidate.Nearby == nil then
        candidate.Nearby = CollectWithin(candidate.Plot, TERRAIN_RANGE);
      end
      local flags, score, counts = EvaluatePlot(profile, candidate.Plot, candidate.Nearby);
      local satisfied, met = TiersMet(flags, enforcedTiers);
      if met > bestMet then
        bestMet = met;
      end
      local requiredCount = 0;
      if enforcedTiers[1] ~= nil then
        requiredCount = counts[enforcedTiers[1]] or 0;
      end
      local bonus = TileBonusFor(profile, candidate);
      evaluated[#evaluated + 1] = {
        Candidate = candidate,
        Satisfied = satisfied,
        MetCount = met,
        Score = score,
        Fertility = candidate.Fertility + bonus,
        Bonus = bonus,
        PlotIndex = candidate.PlotIndex,
        RequiredCount = requiredCount
      };
    end
  end
  if #evaluated == 0 then
    return nil;
  end

  local satisfyingCount = 0;
  for n = 1, #evaluated do
    local entry = evaluated[n];
    if entry.MetCount == bestMet then
      satisfyingCount = satisfyingCount + 1;
    end
  end

  local function AtLevel(entry)
    return entry.MetCount == bestMet;
  end

  local bestFertility = nil;
  for n = 1, #evaluated do
    local entry = evaluated[n];
    if AtLevel(entry) and (bestFertility == nil or entry.Fertility > bestFertility) then
      bestFertility = entry.Fertility;
    end
  end

  local contenders = {};
  for n = 1, #evaluated do
    local entry = evaluated[n];
    if AtLevel(entry) and InBand(entry.Fertility, bestFertility) then
      entry.Boxes = 0;
      entry.Damage = 0;
      if crowding ~= nil then
        entry.Boxes, entry.Damage = crowding(entry.Candidate);
      end
      contenders[#contenders + 1] = entry;
    end
  end

  local best = nil;
  for n = 1, #contenders do
    local entry = contenders[n];
    local better = false;
    if best == nil then
      better = true;
    elseif entry.Boxes ~= best.Boxes then
      better = entry.Boxes < best.Boxes;
    elseif entry.Score ~= best.Score then
      better = entry.Score > best.Score;
    elseif entry.Damage ~= best.Damage then
      better = entry.Damage < best.Damage;
    elseif entry.Fertility ~= best.Fertility then
      better = entry.Fertility > best.Fertility;
    else
      better = entry.PlotIndex < best.PlotIndex;
    end
    if better then
      best = entry;
    end
  end
  best.BestFertility = bestFertility;
  best.SatisfyingCount = satisfyingCount;
  return best;
end

-- The greedy region comparison: true when left ranks above right.
local function BetterRegion(left, right)
  if left.Satisfied ~= right.Satisfied then
    return left.Satisfied == true;
  elseif (left.Level or 0) ~= (right.Level or 0) then
    return (left.Level or 0) > (right.Level or 0);
  elseif left.MetCount ~= right.MetCount then
    return left.MetCount > right.MetCount;
  elseif RobustnessKey(left) ~= RobustnessKey(right) then
    return RobustnessKey(left) > RobustnessKey(right);
  elseif left.BestFertility ~= right.BestFertility then
    return left.BestFertility > right.BestFertility;
  elseif left.Score ~= right.Score then
    return left.Score > right.Score;
  elseif left.Fertility ~= right.Fertility then
    return left.Fertility > right.Fertility;
  end
  return false;
end

local function CompareCivs(left, right)
  local leftRequired = (#left.Enforced > 0);
  local rightRequired = (#right.Enforced > 0);
  if leftRequired ~= rightRequired then
    return leftRequired;
  end
  if leftRequired then
    if left.Options ~= right.Options then
      return left.Options < right.Options;
    end
    if left.Profile.StrongestTier ~= right.Profile.StrongestTier then
      return left.Profile.StrongestTier < right.Profile.StrongestTier;
    end
  end
  if left.Key ~= right.Key then
    return left.Key < right.Key;
  end
  return left.PlayerID < right.PlayerID;
end

local function GetSeed()
  if RoseBetterStarts.GetMapSeed ~= nil then
    return RoseBetterStarts.GetMapSeed();
  end
  return 0;
end

local function GetKey(seed, playerID, listIndex)
  if RoseBetterStarts.GetTieBreakKey ~= nil then
    return RoseBetterStarts.GetTieBreakKey(seed, playerID + 1, 7, listIndex);
  end
  return listIndex;
end

-- Plans every major's region. Called once, from the first __SetStartMajor
-- call, when the stock script has built majorList and divided the regions
-- but placed nobody yet. The plot inside each region is chosen later, when
-- the stock loop reaches that region (RoseSetStartMajor), so the stock
-- distance check sees exactly the starts the stock pick would have seen.
local function PlanMajorRegions(self, firstRegionIndex, firstRegionPlots)
  local profiles = LoadBiasProfiles();
  local seed = GetSeed();
  local regionCount = self.iNumMajorCivs;
  local regions = {};
  local candidateTotal = 0;

  for r = 0, regionCount - 1 do
    local plotIndices = nil;
    if r == firstRegionIndex then
      plotIndices = firstRegionPlots;
    else
      plotIndices = StartPositioner.GetMajorCivStartPlots(r);
    end
    local candidates = CollectRegionCandidates(self, r, plotIndices);
    candidateTotal = candidateTotal + #candidates;
    regions[r] = { Index = r, Candidates = candidates };
    local weightedPositive = 0;
    local desertOnly = 0;
    for n = 1, #candidates do
      if (candidates[n].Weighted or 0) > 0 then
        weightedPositive = weightedPositive + 1;
      end
      if candidates[n].DesertOnly then
        desertOnly = desertOnly + 1;
      end
    end
    local plotCount = 0;
    if plotIndices ~= nil then
      plotCount = #plotIndices;
    end
    print(
      "RBS_BIAS_REGION region=" .. tostring(r)
      .. " plots=" .. tostring(plotCount)
      .. " candidates=" .. tostring(#candidates)
      .. " weighted_positive=" .. tostring(weightedPositive)
      .. " desert_only=" .. tostring(desertOnly)
    );
  end

  print(
    "RBS_BIAS_BEGIN version=" .. tostring(BIAS_VERSION)
    .. " majors=" .. tostring(regionCount)
    .. " regions=" .. tostring(regionCount)
    .. " candidates=" .. tostring(candidateTotal)
    .. " always_required_max_tier=" .. tostring(ALWAYS_REQUIRED_MAX_TIER)
    .. " strongest_required_max_tier=" .. tostring(STRONGEST_REQUIRED_MAX_TIER)
    .. " band=" .. tostring(PREFERENCE_BAND_PERCENT)
  );

  -- Each civilization's best candidate per region, evaluated once (no
  -- distance check at planning time, so the greedy pass can reuse it).
  local civs = {};
  for listIndex = 1, regionCount do
    local playerID = self.majorList[listIndex];
    local civType = "UNKNOWN";
    if PlayerConfigurations ~= nil and PlayerConfigurations[playerID] ~= nil then
      civType = PlayerConfigurations[playerID]:GetCivilizationTypeName() or "UNKNOWN";
    end
    local profile = profiles[civType] or EMPTY_PROFILE;
    local required = profile.RequiredTiers;
    local strongest = {};
    if profile.StrongestTier ~= nil then
      strongest[1] = profile.StrongestTier;
    end

    -- Regions with a valid plot meeting every required tier, and regions
    -- meeting the strongest tier alone (the fallback requirement).
    local bestAll = {};
    local optionsAll = 0;
    local bestStrong = {};
    local optionsStrong = 0;
    for r = 0, regionCount - 1 do
      local best = BestCandidateForCiv(profile, regions[r].Candidates, nil, 0, required);
      bestAll[r] = best;
      if #required > 0 and best ~= nil and best.Satisfied then
        optionsAll = optionsAll + 1;
      end
      if #required > 1 then
        best = BestCandidateForCiv(profile, regions[r].Candidates, nil, 0, strongest);
      end
      bestStrong[r] = best;
      if #strongest > 0 and best ~= nil and best.Satisfied then
        optionsStrong = optionsStrong + 1;
      end
    end

    -- The strict profile (a raised adjacency minimum) ranks above the
    -- standard one: a region's record is its strict best when that is
    -- satisfied (Level 2), else its standard best (Level 1 when satisfied,
    -- 0 otherwise), so the plan prefers a strict region, then a standard
    -- one, and never trades the standard one for a region with nothing.
    local optionsStrict = 0;
    local strictProfile = profile.Strict;
    if strictProfile ~= nil and #required > 0 and optionsAll > 0 then
      local merged = {};
      for r = 0, regionCount - 1 do
        local strictBest = BestCandidateForCiv(strictProfile, regions[r].Candidates, nil, 0, required);
        local chosen = bestAll[r];
        local level = 0;
        if strictBest ~= nil and strictBest.Satisfied then
          chosen = strictBest;
          level = 2;
          optionsStrict = optionsStrict + 1;
        elseif chosen ~= nil and chosen.Satisfied then
          level = 1;
        end
        if chosen ~= nil then
          chosen.Level = level;
        end
        merged[r] = chosen;
      end
      bestAll = merged;
    end

    local enforced = {};
    local enforceMode = "no";
    local bestByRegion = bestAll;
    local options = 0;
    if #required > 0 and optionsAll > 0 then
      enforced = required;
      enforceMode = "all";
      options = optionsAll;
    elseif #strongest > 0 and optionsStrong > 0 then
      enforced = strongest;
      enforceMode = "strongest";
      bestByRegion = bestStrong;
      options = optionsStrong;
    elseif #required > 0 then
      -- Nothing enforceable on this map: evaluate with no requirement, so
      -- the pick is by fertility and preference like an unbiased civ's.
      bestByRegion = {};
      for r = 0, regionCount - 1 do
        bestByRegion[r] = BestCandidateForCiv(profile, regions[r].Candidates, nil, 0, enforced);
      end
    end

    civs[#civs + 1] = {
      ListIndex = listIndex,
      PlayerID = playerID,
      CivType = civType,
      Profile = profile,
      Enforced = enforced,
      EnforceMode = enforceMode,
      BestByRegion = bestByRegion,
      Options = options,
      OptionsAll = optionsAll,
      OptionsStrongest = optionsStrong,
      OptionsStrict = optionsStrict,
      Strict = strictProfile,
      Key = GetKey(seed, playerID, listIndex)
    };
  end
  table.sort(civs, CompareCivs);

  -- The best free region for a civilization: the greedy choice. Every free
  -- region without a valid plot ranks last (the stock pick decides there).
  local function ChooseRegion(civ, regionUsed)
    local chosenRegion = nil;
    local chosenBest = nil;
    for r = 0, regionCount - 1 do
      if regionUsed[r] ~= true then
        local best = civ.BestByRegion[r];
        if best ~= nil and (chosenBest == nil or BetterRegion(best, chosenBest)) then
          chosenRegion = r;
          chosenBest = best;
        end
      end
    end
    if chosenRegion == nil then
      for r = 0, regionCount - 1 do
        if regionUsed[r] ~= true then
          chosenRegion = r;
          break;
        end
      end
    end
    return chosenRegion;
  end

  -- Greedy pass: each civilization, in order, takes the best free region.
  local greedyRegion = {};
  local regionUsed = {};
  for n = 1, #civs do
    local r = ChooseRegion(civs[n], regionUsed);
    greedyRegion[n] = r;
    if r ~= nil then
      regionUsed[r] = true;
    end
  end

  -- Matching pass: a civilization the greedy pass left without a satisfying
  -- region looks for one through augmenting paths (a civilization on the
  -- path moves only to another region that satisfies it), so the number of
  -- civilizations with a satisfying region is the largest possible. Seeded
  -- with the greedy result, so nothing moves unless a civilization gains.
  local function Satisfies(civ, r)
    local best = civ.BestByRegion[r];
    return #civ.Enforced > 0 and best ~= nil and best.Satisfied == true;
  end
  local orders = {};
  for n = 1, #civs do
    local civ = civs[n];
    local list = {};
    for r = 0, regionCount - 1 do
      if Satisfies(civ, r) then
        list[#list + 1] = r;
      end
    end
    table.sort(list, function(a, b)
      local left = civ.BestByRegion[a];
      local right = civ.BestByRegion[b];
      if BetterRegion(left, right) then
        return true;
      elseif BetterRegion(right, left) then
        return false;
      end
      return a < b;
    end);
    orders[n] = list;
  end
  local owner = {};
  local matched = {};
  for n = 1, #civs do
    local r = greedyRegion[n];
    if r ~= nil and Satisfies(civs[n], r) then
      owner[r] = n;
      matched[n] = r;
    end
  end
  local function Augment(n, seen)
    local list = orders[n];
    for k = 1, #list do
      local r = list[k];
      if seen[r] ~= true then
        seen[r] = true;
        if owner[r] == nil or Augment(owner[r], seen) then
          owner[r] = n;
          matched[n] = r;
          return true;
        end
      end
    end
    return false;
  end
  for n = 1, #civs do
    if matched[n] == nil and #orders[n] > 0 then
      Augment(n, {});
    end
  end

  -- Final regions: matched civilizations keep their matched region; the
  -- others choose among the rest, in order, as in the greedy pass.
  regionUsed = {};
  local finalRegion = {};
  for n = 1, #civs do
    if matched[n] ~= nil then
      finalRegion[n] = matched[n];
      regionUsed[matched[n]] = true;
    end
  end
  for n = 1, #civs do
    if finalRegion[n] == nil then
      local r = ChooseRegion(civs[n], regionUsed);
      finalRegion[n] = r;
      if r ~= nil then
        regionUsed[r] = true;
      end
    end
  end

  local plan = { ByRegion = {}, ByListIndex = {}, Order = {}, RegionCount = regionCount, Civs = civs };

  for n = 1, #civs do
    local civ = civs[n];
    local chosenRegion = finalRegion[n];
    local planLabel = "greedy";
    if chosenRegion ~= greedyRegion[n] then
      planLabel = "matched";
    end
    -- A civilization with a strict profile is judged by it when its region
    -- satisfies the strict rule, by the standard profile otherwise.
    local entryProfile = civ.Profile;
    local entryMode = civ.EnforceMode;
    local entryLevel = "-";
    if civ.Strict ~= nil and civ.EnforceMode == "all" and chosenRegion ~= nil then
      local best = civ.BestByRegion[chosenRegion];
      if best ~= nil and best.Level == 2 then
        entryProfile = civ.Strict;
        entryMode = "strict";
        entryLevel = "strict";
      else
        entryLevel = "standard";
      end
    end

    print(
      "RBS_BIAS player=" .. tostring(civ.PlayerID)
      .. " civ=" .. tostring(civ.CivType)
      .. " order=" .. tostring(n)
      .. " tiers=" .. TierLabel(civ.Profile)
      .. " required=" .. TierListLabel(civ.Profile.RequiredTiers)
      .. " enforced=" .. tostring(entryMode)
      .. " options=" .. tostring(civ.Options)
      .. " options_all=" .. tostring(civ.OptionsAll)
      .. " options_strongest=" .. tostring(civ.OptionsStrongest)
      .. " options_strict=" .. tostring(civ.OptionsStrict)
      .. " region=" .. tostring(chosenRegion or -1)
      .. " plan=" .. planLabel
      .. " level=" .. entryLevel
    );

    plan.Order[#plan.Order + 1] = civ.ListIndex;
    if chosenRegion ~= nil then
      local entry = {
        ListIndex = civ.ListIndex,
        PlayerID = civ.PlayerID,
        CivType = civ.CivType,
        Profile = entryProfile,
        Enforced = civ.Enforced,
        EnforceMode = entryMode,
        Level = entryLevel,
        Region = chosenRegion,
        Candidates = regions[chosenRegion].Candidates,
        Plot = nil,
        BasePlot = nil,
        Satisfied = false,
        Score = 0,
        Fertility = 0,
        BestFertility = 0,
        RequiredCount = 0,
        Mode = "BASE",
        Forced = false
      };
      plan.ByRegion[chosenRegion] = entry;
      plan.ByListIndex[civ.ListIndex] = entry;

      -- The region's plots that satisfy its civilization's enforced tiers
      -- (every valid plot for an unenforced one): what the look-ahead
      -- protects for this region while earlier regions pick.
      local satisfying = {};
      local satisfyingBase = nil;
      if entry.Profile.Base ~= nil then
        satisfyingBase = {};
      end
      local candidates = entry.Candidates;
      for c = 1, #candidates do
        local candidate = candidates[c];
        local keep = AllowedFor(entry.Profile, candidate);
        if keep and #entry.Enforced > 0 then
          if candidate.Nearby == nil then
            candidate.Nearby = CollectWithin(candidate.Plot, TERRAIN_RANGE);
          end
          local flags = EvaluatePlot(entry.Profile, candidate.Plot, candidate.Nearby);
          keep = TiersMet(flags, entry.Enforced);
          if satisfyingBase ~= nil and not keep then
            -- Plots that meet the standard rule but not the strict one: the
            -- look-ahead's second line of protection for this region.
            local baseFlags = EvaluatePlot(entry.Profile.Base, candidate.Plot, candidate.Nearby);
            if TiersMet(baseFlags, entry.Enforced) then
              satisfyingBase[#satisfyingBase + 1] = candidate;
            end
          end
        end
        if keep then
          satisfying[#satisfying + 1] = candidate;
        end
      end
      entry.Satisfying = satisfying;
      entry.SatisfyingBase = satisfyingBase;
    end
  end

  return plan;
end

-- After a start is placed, the candidates of every unplaced region within
-- the stock buffer of it are marked blocked, so the look-ahead knows which
-- satisfying plots each region still has.
local function MarkBlocked(plan, plotIndex, limit)
  for r = 0, plan.RegionCount - 1 do
    local entry = plan.ByRegion[r];
    if entry ~= nil and entry.Plot == nil and entry.BasePlot == nil then
      local candidates = entry.Candidates;
      for n = 1, #candidates do
        local candidate = candidates[n];
        if candidate.Blocked ~= true and Map.GetPlotDistance(plotIndex, candidate.PlotIndex) <= limit then
          candidate.Blocked = true;
        end
      end
    end
  end
end

-- The crowding measure for one pick: for a candidate, how many unplaced
-- regions it would leave without any live plot (boxes), and the share of
-- the live plots of the scarce regions it would block, in thousandths,
-- summed (damage). A region's live plots are its satisfying plots outside
-- the buffer of the starts placed so far; a region with none left (its
-- civilization will be UNMET) is protected through its remaining valid
-- plots instead, so it still gets a start of its own rather than the stock
-- fallback. Regions with nothing left are skipped. A hex distance is at
-- least the row difference, which filters most pairs before the engine
-- call.
local function Unblocked(list, profile)
  local live = {};
  for n = 1, #list do
    if list[n].Blocked ~= true and (profile == nil or AllowedFor(profile, list[n])) then
      live[#live + 1] = list[n];
    end
  end
  return live;
end

local function CrowdingFor(plan, regionIndex, limit)
  local groups = {};
  for r = 0, plan.RegionCount - 1 do
    local entry = plan.ByRegion[r];
    if entry ~= nil and r ~= regionIndex and entry.Plot == nil and entry.BasePlot == nil then
      local live = Unblocked(entry.Satisfying or {});
      if #live == 0 and entry.SatisfyingBase ~= nil then
        live = Unblocked(entry.SatisfyingBase);
      end
      if #live == 0 then
        live = Unblocked(entry.Candidates or {}, entry.Profile or EMPTY_PROFILE);
      end
      if #live > 0 then
        groups[#groups + 1] = live;
      end
    end
  end
  if #groups == 0 then
    return nil;
  end

  return function(candidate)
    local boxes = 0;
    local damage = 0;
    local y = candidate.Y;
    local plotIndex = candidate.PlotIndex;
    for g = 1, #groups do
      local live = groups[g];
      local blocked = 0;
      for n = 1, #live do
        local other = live[n];
        if math.abs(other.Y - y) <= limit and Map.GetPlotDistance(plotIndex, other.PlotIndex) <= limit then
          blocked = blocked + 1;
        end
      end
      if blocked == #live then
        boxes = boxes + 1;
      end
      if #live <= CROWDING_SCARCE_LIVE then
        damage = damage + math.floor(blocked * CROWDING_SCALE / #live);
      end
    end
    return boxes, damage;
  end;
end

-- The first stock validity check a plot fails, in the stock order, or
-- "none". Used to describe the stock fallback plot, which fails at least
-- one of them; "none" would mean the candidate filter and the stock checks
-- disagree.
local function FirstFailedCheck(self, plot, limit)
  if plot:IsImpassable() == true then
    return "impassable";
  end
  if plot:IsWater() == true then
    return "water";
  end
  if not FarFromPlaced(plot:GetIndex(), self.majorStartPlots, limit) then
    return "major_buffer";
  end
  if (math.ceil(self.iDefaultNumberMajor * 1.25) + self.iDefaultNumberMinor > self.iNumMinorCivs + self.iNumMajorCivs) then
    if self:__LuxuryBuffer(plot) == false then
      return "luxury";
    end
  end
  if self:__GetWaterCheck(plot) == false then
    return "water_access";
  end
  if self:__GetValidAdjacent(plot, 0) == false then
    return "adjacent";
  end
  if self:__NaturalWonderBuffer(plot, false) == false then
    return "natural_wonder";
  end
  if plot:GetResourceCount() > 0 and not self:__BonusResource(plot) then
    return "resource";
  end
  if plot:GetFeatureType() == g_FEATURE_OASIS then
    return "oasis";
  end
  return "none";
end

-- The candidates of a region as the stock loop sees that region now: only
-- plots in the list the stock loop passes for it (the plan read every
-- region before the stock loop marked any region used; the lists are not
-- expected to change, this guards the assumption).
local function CandidatesForPick(self, entry, plots, regionIndex)
  local picked = {};
  if plots == nil then
    return picked;
  end
  local allowed = {};
  for n = 1, #plots do
    allowed[plots[n]] = true;
  end
  for n = 1, #entry.Candidates do
    local candidate = entry.Candidates[n];
    if allowed[candidate.PlotIndex] == true then
      picked[#picked + 1] = candidate;
    end
  end
  return picked;
end

local function PrintPlaced(entry, plot)
  local plotIndex = -1;
  if plot ~= nil then
    plotIndex = plot:GetIndex();
  end
  local spacing = "stock";
  if entry.Forced then
    spacing = "forced";
  end
  print(
    "RBS_BIAS_PLACED player=" .. tostring(entry.PlayerID)
    .. " civ=" .. tostring(entry.CivType)
    .. " region=" .. tostring(entry.Region)
    .. " plot=" .. tostring(plotIndex)
    .. " satisfied=" .. YesNo(entry.Satisfied)
    .. " score=" .. tostring(entry.Score)
    .. " fertility=" .. tostring(entry.Fertility)
    .. " bonus=" .. tostring(entry.Bonus or 0)
    .. " plot_fertility=" .. tostring(entry.PlotFertility or 0)
    .. " weighted=" .. tostring(entry.Weighted or 0)
    .. " best_fertility=" .. tostring(entry.BestFertility)
    .. " band=" .. tostring(PREFERENCE_BAND_PERCENT)
    .. " required_count=" .. tostring(entry.RequiredCount)
    .. " satisfying=" .. tostring(entry.SatisfyingCount or 0)
    .. " boxes=" .. tostring(entry.Boxes or 0)
    .. " damage=" .. tostring(entry.Damage or 0)
    .. " candidates=" .. tostring(entry.PickCandidates or 0)
    .. " failed_check=" .. tostring(entry.FailedCheck or "-")
    .. " mode=" .. tostring(entry.Mode)
    .. " spacing=" .. spacing
    .. " desert=" .. tostring(entry.DesertCount or -1)
    .. " level=" .. tostring(entry.Level or "-")
  );
end

-- Replaces AssignStartingPlots.__SetStartMajor. The stock loop asks for one
-- plot per region, in its own order; the first call plans which civilization
-- gets which region, and every call picks that civilization's best valid
-- plot among those that keep the stock distance from the starts already
-- placed (the plots the stock loop has collected so far, the same list the
-- stock pick checks). When no valid plot keeps that distance, the stock pick
-- decides, as it would without the mod. The stock side effects of a pick
-- (removing a bonus resource under the start, topping up food and
-- production) are applied here, as the stock function applies them before
-- returning.
--
-- Modes: BIAS, the enforced tiers are met at the chosen plot; UNMET, they
-- could be met in some region, but every such plot was taken by an earlier
-- civilization or sits too close to a start already placed; PREFERENCE, no
-- enforceable tier, placed by fertility and preference; BASE, the stock pick.
local function RoseSetStartMajor(self, plots, regionIndex)
  if not ENFORCE_START_BIASES or self.noStartBiases then
    return BaseSetStartMajor(self, plots, regionIndex);
  end

  if self.RoseStartPlan == nil then
    self.RoseStartPlan = PlanMajorRegions(self, regionIndex, plots);
  end

  local plan = self.RoseStartPlan;
  local entry = plan.ByRegion[regionIndex];
  if entry == nil then
    -- A region the plan did not see (more regions than civilizations).
    entry = {
      ListIndex = -1, PlayerID = -1, CivType = "NONE", Profile = EMPTY_PROFILE, Enforced = {},
      EnforceMode = "no", Region = regionIndex, Candidates = {}, Plot = nil, BasePlot = nil,
      Satisfied = false, Score = 0, Fertility = 0, BestFertility = 0, RequiredCount = 0,
      Mode = "BASE", Forced = false
    };
    plan.ByRegion[regionIndex] = entry;
  end

  local limit = MajorBufferLimit();
  local candidates = CandidatesForPick(self, entry, plots, regionIndex);
  entry.PickCandidates = #candidates;
  local crowding = nil;
  if #candidates > 0 and plan.RegionCount ~= nil then
    crowding = CrowdingFor(plan, regionIndex, limit);
  end
  local best = BestCandidateForCiv(entry.Profile, candidates, self.majorStartPlots, limit, entry.Enforced, crowding);
  if entry.EnforceMode == "strict" and (best == nil or not best.Satisfied) and entry.Profile.Base ~= nil then
    -- No plot here meets the raised adjacency after spacing: the standard
    -- rule decides, and the civilization is judged by it from now on (the
    -- stock pick included, when nothing clears the buffer).
    best = BestCandidateForCiv(entry.Profile.Base, candidates, self.majorStartPlots, limit, entry.Enforced, crowding);
    entry.Profile = entry.Profile.Base;
    entry.EnforceMode = "all";
    entry.Level = "standard";
  end
  if best ~= nil then
    local plot = best.Candidate.Plot;
    self:__TryToRemoveBonusResource(plot);
    self:__AddBonusFoodProduction(plot);
    entry.Plot = plot;
    entry.Satisfied = best.Satisfied;
    entry.Score = best.Score;
    entry.Fertility = best.Fertility;
    entry.Bonus = best.Bonus;
    entry.DesertCount = best.Candidate.DesertCount;
    entry.DesertOnly = (best.Candidate.DesertOnly == true);
    entry.PlotFertility = best.Candidate.PlotFertility;
    entry.Weighted = best.Candidate.Weighted;
    entry.BestFertility = best.BestFertility;
    entry.SatisfyingCount = best.SatisfyingCount;
    entry.RequiredCount = best.RequiredCount;
    entry.Boxes = best.Boxes;
    entry.Damage = best.Damage;
    if #entry.Enforced > 0 then
      if best.Satisfied then
        entry.Mode = "BIAS";
      else
        entry.Mode = "UNMET";
      end
    else
      entry.Mode = "PREFERENCE";
    end
    PrintPlaced(entry, plot);
    if plan.RegionCount ~= nil then
      MarkBlocked(plan, plot:GetIndex(), limit);
    end
    return plot;
  end

  -- Stock pick for this region. The stock function returns its fallback
  -- plot when no plot clears every check, so the stock distance to other
  -- starts is then not guaranteed ("forced"), as without the mod.
  local plot = BaseSetStartMajor(self, plots, regionIndex);
  entry.BasePlot = plot;
  entry.Mode = "BASE";
  if plot ~= nil then
    local nearby = CollectWithin(plot, TERRAIN_RANGE);
    local flags, score, counts = EvaluatePlot(entry.Profile or EMPTY_PROFILE, plot, nearby);
    local satisfied, met = TiersMet(flags, entry.Enforced);
    entry.Satisfied = satisfied;
    entry.Score = score;
    entry.RequiredCount = 0;
    if entry.Enforced[1] ~= nil then
      entry.RequiredCount = counts[entry.Enforced[1]] or 0;
    end
    entry.Bonus = TileBonusFor(entry.Profile or EMPTY_PROFILE, { Terrain = plot:GetTerrainType(), Nearby = nearby });
    entry.Fertility = RingFertility(self, plot) + entry.Bonus;
    entry.PlotFertility = self:__BaseFertility(plot:GetIndex());
    entry.Weighted = self:__WeightedFertility(plot:GetIndex(), regionIndex, true);
    entry.BestFertility = entry.Fertility;
    entry.Forced = not FarFromPlaced(plot:GetIndex(), self.majorStartPlots, limit);
    entry.FailedCheck = FirstFailedCheck(self, plot, limit);
    local _, _, desertCount = ValidAdjacentDetail(self, plot);
    entry.DesertCount = desertCount;
  end
  PrintPlaced(entry, plot);
  if plot ~= nil and plan.RegionCount ~= nil then
    MarkBlocked(plan, plot:GetIndex(), limit);
  end
  return plot;
end

-- Final re-matching over the picked plots. A civilization whose enforced
-- tiers are unmet at its own plot looks for a picked plot that meets them,
-- through augmenting paths: a civilization on the path moves only to a plot
-- that also meets its own enforced tiers, or it has none to meet. Seeded
-- with the civilizations already satisfied, so nothing moves unless one
-- gains. The civilizations left unmatched keep their own plot when nobody
-- took it, else take the plots left over, in plan order, best fertility
-- first. Returns listIndex -> plot and sets entry.Satisfied, entry.Rematched
-- and entry.FinalPlot; prints one RBS_BIAS_REMATCH line per move.
local function RematchStarts(self, plan)
  local order = plan.Order or {};
  local entries = {};
  local plots = {};
  local holder = {};
  for n = 1, #order do
    local entry = plan.ByListIndex[order[n]];
    if entry ~= nil then
      local plot = entry.Plot or entry.BasePlot;
      entries[#entries + 1] = entry;
      entry.OwnPlot = plot;
      if plot ~= nil then
        plots[#plots + 1] = plot;
        holder[plot:GetIndex()] = entry;
      end
    end
  end

  -- A plot that only a desert civilization may hold (picked above the stock
  -- desert cap) is never handed to another civilization.
  local function PlotAllowed(entry, plot)
    local held = holder[plot:GetIndex()];
    if held == nil or held.DesertOnly ~= true then
      return true;
    end
    return AllowedFor(entry.Profile or EMPTY_PROFILE, { DesertOnly = true, DesertCount = held.DesertCount or 0 });
  end

  local nearbyOf = {};
  local metCache = {};
  local function MetAt(entry, plot)
    if plot == nil or not PlotAllowed(entry, plot) then
      return false;
    end
    local key = tostring(entry.ListIndex) .. ":" .. tostring(plot:GetIndex());
    if metCache[key] == nil then
      local plotIndex = plot:GetIndex();
      if nearbyOf[plotIndex] == nil then
        nearbyOf[plotIndex] = CollectWithin(plot, TERRAIN_RANGE);
      end
      local flags = EvaluatePlot(entry.Profile or EMPTY_PROFILE, plot, nearbyOf[plotIndex]);
      local met = TiersMet(flags, entry.Enforced or {});
      metCache[key] = met;
    end
    return metCache[key];
  end

  -- Plots in the order a seeker tries them: those held by a civilization
  -- with nothing to meet first, then by one whose own plot fails it, then
  -- by a satisfied one; the most fertile first within each group, then
  -- plot index. A plot's fertility is the plain ring value its pick
  -- recorded, without the picker's own tile bonus, which another
  -- civilization would not get there.
  local function RingOf(plot)
    local entry = holder[plot:GetIndex()];
    if entry ~= nil and entry.Fertility ~= nil then
      return entry.Fertility - (entry.Bonus or 0);
    end
    return 0;
  end
  local function HolderRank(plot)
    local entry = holder[plot:GetIndex()];
    if entry == nil or #entry.Enforced == 0 then
      return 0;
    elseif not MetAt(entry, plot) then
      return 1;
    end
    return 2;
  end
  table.sort(plots, function(a, b)
    local ra = HolderRank(a);
    local rb = HolderRank(b);
    if ra ~= rb then
      return ra < rb;
    end
    local fa = RingOf(a);
    local fb = RingOf(b);
    if fa ~= fb then
      return fa > fb;
    end
    return a:GetIndex() < b:GetIndex();
  end);

  local owner = {};
  local matched = {};
  for n = 1, #entries do
    local entry = entries[n];
    if #entry.Enforced > 0 and entry.OwnPlot ~= nil and MetAt(entry, entry.OwnPlot) then
      owner[entry.OwnPlot:GetIndex()] = entry;
      matched[entry.ListIndex] = entry.OwnPlot;
    end
  end
  local function Augment(entry, seen)
    for n = 1, #plots do
      local plot = plots[n];
      local plotIndex = plot:GetIndex();
      if seen[plotIndex] ~= true and MetAt(entry, plot) then
        seen[plotIndex] = true;
        if owner[plotIndex] == nil or Augment(owner[plotIndex], seen) then
          owner[plotIndex] = entry;
          matched[entry.ListIndex] = plot;
          return true;
        end
      end
    end
    return false;
  end
  -- A civilization holding a plot above the stock desert cap keeps it:
  -- freed, that plot could only go to a civilization the cap refuses it to.
  for n = 1, #entries do
    local entry = entries[n];
    if #entry.Enforced > 0 and entry.OwnPlot ~= nil and matched[entry.ListIndex] == nil and entry.DesertOnly ~= true then
      Augment(entry, {});
    end
  end

  -- Final plots: matched civilizations take their matched plot; the others
  -- keep their own when free, else take the leftovers, best fertility
  -- first (plot index on a tie).
  local finalPlot = {};
  local taken = {};
  for n = 1, #entries do
    local entry = entries[n];
    local plot = matched[entry.ListIndex];
    if plot ~= nil then
      finalPlot[entry.ListIndex] = plot;
      taken[plot:GetIndex()] = true;
    end
  end
  for n = 1, #entries do
    local entry = entries[n];
    if finalPlot[entry.ListIndex] == nil and entry.OwnPlot ~= nil and taken[entry.OwnPlot:GetIndex()] ~= true then
      finalPlot[entry.ListIndex] = entry.OwnPlot;
      taken[entry.OwnPlot:GetIndex()] = true;
    end
  end
  local leftovers = {};
  for n = 1, #plots do
    if taken[plots[n]:GetIndex()] ~= true then
      leftovers[#leftovers + 1] = plots[n];
    end
  end
  table.sort(leftovers, function(a, b)
    local fa = RingOf(a);
    local fb = RingOf(b);
    if fa ~= fb then
      return fa > fb;
    end
    return a:GetIndex() < b:GetIndex();
  end);
  local leftoverTaken = {};
  for n = 1, #entries do
    local entry = entries[n];
    if finalPlot[entry.ListIndex] == nil and entry.OwnPlot ~= nil then
      -- The best leftover this civilization may hold; the first free one
      -- when none is allowed, so nobody is left without a plot.
      local chosen = nil;
      for k = 1, #leftovers do
        if leftoverTaken[k] ~= true and PlotAllowed(entry, leftovers[k]) then
          chosen = k;
          break;
        end
      end
      if chosen == nil then
        for k = 1, #leftovers do
          if leftoverTaken[k] ~= true then
            chosen = k;
            print("RBS_BIAS_LEFTOVER_DISALLOWED player=" .. tostring(entry.PlayerID)
              .. " plot=" .. tostring(leftovers[k]:GetIndex()));
            break;
          end
        end
      end
      if chosen ~= nil then
        leftoverTaken[chosen] = true;
        finalPlot[entry.ListIndex] = leftovers[chosen];
      end
    end
  end

  for n = 1, #entries do
    local entry = entries[n];
    local plot = finalPlot[entry.ListIndex];
    entry.FinalPlot = plot;
    entry.Rematched = false;
    if #entry.Enforced > 0 then
      entry.Satisfied = MetAt(entry, plot);
    end
    if plot ~= nil and entry.OwnPlot ~= nil and plot:GetIndex() ~= entry.OwnPlot:GetIndex() then
      entry.Rematched = true;
      print(
        "RBS_BIAS_REMATCH player=" .. tostring(entry.PlayerID)
        .. " civ=" .. tostring(entry.CivType)
        .. " from=" .. tostring(entry.OwnPlot:GetIndex())
        .. " to=" .. tostring(plot:GetIndex())
        .. " satisfied=" .. YesNo(entry.Satisfied)
        .. " fertility=" .. tostring(RingOf(plot))
      );
    end
  end

  return finalPlot;
end

-- Replaces AssignStartingPlots.__InitStartBias for majors: each civilization
-- gets the plot picked for it, after the final re-matching. The stock safety
-- net is kept: a start the plan did not assign goes to a civilization left
-- without one. Minors keep the stock matching.
local function RoseInitStartBias(self, minor)
  if minor == true or not ENFORCE_START_BIASES or self.noStartBiases or self.RoseStartPlan == nil then
    return BaseInitStartBias(self, minor);
  end

  local plan = self.RoseStartPlan;
  local assigned = {};
  local checksum = 17;
  local satisfiedCount = 0;
  local enforcedCount = 0;
  local unmetCount = 0;
  local baseCount = 0;

  local finalPlot = RematchStarts(self, plan);
  local rematchedCount = 0;
  local onFallbackCount = 0;

  -- The plots the stock pick chose (regions where no candidate kept the
  -- stock distance, so the stock pick ran: usually its fallback plot, which
  -- fails a validity check): whoever ends on one is counted, since the
  -- re-matching may hand such a plot to another civilization.
  local fallbackPlots = {};
  for listIndex = 1, self.iNumMajorCivs do
    local entry = plan.ByListIndex[listIndex];
    if entry ~= nil and entry.Mode == "BASE" and entry.BasePlot ~= nil then
      fallbackPlots[entry.BasePlot:GetIndex()] = true;
    end
  end

  self.playerStarts = {};
  for listIndex = 1, self.iNumMajorCivs do
    local entry = plan.ByListIndex[listIndex];
    local plot = finalPlot[listIndex];
    self.playerStarts[listIndex] = {};
    if plot ~= nil then
      self.playerStarts[listIndex][1] = plot;
      assigned[plot:GetIndex()] = true;
      if fallbackPlots[plot:GetIndex()] == true then
        onFallbackCount = onFallbackCount + 1;
      end
    end
    if entry ~= nil then
      if entry.Mode == "BASE" then
        baseCount = baseCount + 1;
      end
      if #entry.Enforced > 0 then
        enforcedCount = enforcedCount + 1;
        if entry.Satisfied then
          satisfiedCount = satisfiedCount + 1;
        else
          unmetCount = unmetCount + 1;
        end
      end
      if entry.Rematched then
        rematchedCount = rematchedCount + 1;
      end
    end
  end

  local leftovers = {};
  for n = 1, #self.majorCopy do
    local plot = self.majorCopy[n];
    if assigned[plot:GetIndex()] ~= true then
      leftovers[#leftovers + 1] = plot;
    end
  end
  local leftoverNumber = 0;
  for listIndex = 1, self.iNumMajorCivs do
    if #self.playerStarts[listIndex] == 0 then
      leftoverNumber = leftoverNumber + 1;
      local plot = leftovers[leftoverNumber];
      if plot ~= nil then
        self.playerStarts[listIndex][1] = plot;
        print(
          "RBS_BIAS_LEFTOVER player=" .. tostring(self.majorList[listIndex])
          .. " plot=" .. tostring(plot:GetIndex())
        );
      else
        print(
          "RBS_BIAS_UNPLACED player=" .. tostring(self.majorList[listIndex])
        );
      end
    end
  end

  for listIndex = 1, self.iNumMajorCivs do
    local plot = self.playerStarts[listIndex][1];
    local plotIndex = -1;
    if plot ~= nil then
      plotIndex = plot:GetIndex();
    end
    local entry = plan.ByListIndex[listIndex];
    local satisfied = 0;
    if entry ~= nil and entry.Satisfied then
      satisfied = 1;
    end
    checksum = AddChecksum(checksum, self.majorList[listIndex] + 1);
    checksum = AddChecksum(checksum, plotIndex + 1);
    checksum = AddChecksum(checksum, satisfied);
  end

  RoseBetterStarts.BiasChecksum = checksum;
  print(
    "RBS_BIAS_END version=" .. tostring(BIAS_VERSION)
    .. " enforced=" .. tostring(enforcedCount)
    .. " satisfied=" .. tostring(satisfiedCount)
    .. " unmet=" .. tostring(unmetCount)
    .. " base=" .. tostring(baseCount)
    .. " rematched=" .. tostring(rematchedCount)
    .. " on_fallback=" .. tostring(onFallbackCount)
    .. " checksum=" .. tostring(checksum)
  );
end

function RoseBetterStarts.InstallStartBias()
  if RoseBetterStarts.StartBiasInstalled then
    return;
  end
  if AssignStartingPlots == nil
    or AssignStartingPlots.__SetStartMajor == nil
    or AssignStartingPlots.__InitStartBias == nil then
    error("Rose Better Starts could not find the AssignStartingPlots methods to override");
  end

  RoseBetterStarts.StartBiasInstalled = true;
  RoseBetterStarts.StartBiasEnabled = ENFORCE_START_BIASES;
  RoseBetterStarts.StartBiasVersion = BIAS_VERSION;
  BaseSetStartMajor = AssignStartingPlots.__SetStartMajor;
  BaseInitStartBias = AssignStartingPlots.__InitStartBias;
  AssignStartingPlots.__SetStartMajor = RoseSetStartMajor;
  AssignStartingPlots.__InitStartBias = RoseInitStartBias;
end
