-- ===========================================================================
-- Rose Better Starts
-- Equal-area regions: one region per major civilization, each with about the
-- same number of usable land plots. Deterministic, map generation only; no
-- tile is changed and nothing draws from the random stream.
-- ===========================================================================
--
-- The engine divides the land into one region per major civilization by a
-- measure of its own, so a region of poor land (tundra, desert) can be twice
-- the size of a fertile one. On the maps listed in EQUAL_AREA_MAPS the stock
-- division still runs (the engine's state stays as it expects), and then
-- StartPositioner.GetMajorCivStartPlots returns these regions instead, for
-- the duration of AssignStartingPlots.Create, so the stock loop, the
-- start-bias plan and the city-state zones all see the same lists.
--
-- Rules:
--   * Region land: on the landmass with the most counted plots (counted:
--     passable land that is not snow), the piece connected over passable
--     land (mountains separate it like water) with the most counted plots.
--     When that piece holds less than MAIN_SHARE_PERCENT of the landmass's
--     counted plots (a mountain range cuts it in two), the engine's regions
--     are used. Snow is attached to a region but not counted; impassable
--     plots, pockets behind mountains and other landmasses stay outside
--     every region.
--   * Seeds: farthest-point selection over the counted plots in the rows a
--     major may start in (the map's START_MIN_Y and START_MAX_Y), from the
--     one farthest from the lowest-indexed one; each next seed is the one
--     farthest from every seed so far (lowest index on a tie), so no region
--     is anchored in the polar rows.
--   * Growth: one plot at a time, the region with the fewest counted plots
--     (lowest region on a tie) among those that can still grow claims its
--     free passable plot nearest its seed (lowest plot index on a tie), so
--     the regions stay level until every reachable plot is taken; a region
--     that is walled in stops early. Plots no region can reach over
--     passable land (enclosed by mountains) go to the region with the
--     nearest seed ("unreached" in the log).
--   * Re-centring: RECENTRE_ROUNDS times, each seed moves to its region's
--     counted plot in those rows nearest the region's centre (any counted
--     plot when it has none there), and the growth is redone.
--   * Levelling: neighbouring regions two or more counted plots apart
--     trade border plots, the largest gap first, without cutting the donor
--     region apart (Balance).
--   * Regions are numbered by their final seed's plot index.
--   * The engine's regions are used, as without this module, when the
--     region land holds fewer than MIN_COUNTED_PER_REGION counted plots per
--     region, when the levelled regions still differ by more than
--     max(SPREAD_MIN, SPREAD_PERCENT of the mean) counted plots, when the
--     engine divided fewer regions than there are civilizations, or when
--     the engine refuses the replacement.

RoseBetterStarts = RoseBetterStarts or {};

local EQUAL_AREA_MAPS = {
  ["Pangaea.lua"] = true
};
local MIN_COUNTED_PER_REGION = 20;
local RECENTRE_ROUNDS = 5;
local MAIN_SHARE_PERCENT = 85;
local SPREAD_MIN = 3;
local SPREAD_PERCENT = 10;
local CHECKSUM_MODULUS = 2147483647;

local function AddChecksum(checksum, value)
  return (checksum * 31 + value) % CHECKSUM_MODULUS;
end

local function IsPassableLand(plot)
  return plot ~= nil and plot:IsWater() ~= true and plot:IsImpassable() ~= true;
end

local function IsCounted(plot)
  if not IsPassableLand(plot) then
    return false;
  end
  local terrain = plot:GetTerrainType();
  return terrain ~= g_TERRAIN_TYPE_SNOW and terrain ~= g_TERRAIN_TYPE_SNOW_HILLS;
end

local function Neighbours(plot)
  local list = {};
  local x = plot:GetX();
  local y = plot:GetY();
  for direction = 0, 5 do
    local other = Map.GetAdjacentPlot(x, y, direction);
    if other ~= nil then
      list[#list + 1] = other;
    end
  end
  return list;
end

-- Connected pieces of the plots for which isPart is true (adjacency over
-- such plots, limited to within when given), scanning plots by index; each
-- piece lists its plot indices in the order found. Returns the pieces and
-- each one's counted plots.
local function Pieces(isPart, within)
  local plotCount = Map.GetPlotCount();
  local seen = {};
  local pieces = {};
  local countedOf = {};
  for start = 0, plotCount - 1 do
    local plot = Map.GetPlotByIndex(start);
    if plot ~= nil and seen[start] == nil and (within == nil or within[start] == true) and isPart(plot) then
      local members = {};
      local queue = { plot };
      seen[start] = true;
      local head = 1;
      local counted = 0;
      while head <= #queue do
        local current = queue[head];
        head = head + 1;
        members[#members + 1] = current:GetIndex();
        if IsCounted(current) then
          counted = counted + 1;
        end
        local adjacent = Neighbours(current);
        for n = 1, #adjacent do
          local other = adjacent[n];
          local otherIndex = other:GetIndex();
          if seen[otherIndex] == nil and (within == nil or within[otherIndex] == true) and isPart(other) then
            seen[otherIndex] = true;
            queue[#queue + 1] = other;
          end
        end
      end
      pieces[#pieces + 1] = members;
      countedOf[#pieces] = counted;
    end
  end
  return pieces, countedOf;
end

-- The piece with the most counted plots; the first found on a tie.
local function Biggest(pieces, countedOf)
  local best = nil;
  for n = 1, #pieces do
    if best == nil or countedOf[n] > countedOf[best] then
      best = n;
    end
  end
  return best;
end

local function IsLand(plot)
  return plot:IsWater() ~= true;
end

-- The region land (see the header): membership by plot index, its counted
-- plots in index order, and the landmass's counted total; nil membership
-- when there is no land.
local function MainLand()
  local lands, landCounted = Pieces(IsLand, nil);
  local land = Biggest(lands, landCounted);
  if land == nil then
    return nil, {}, 0;
  end
  local onLand = {};
  for n = 1, #lands[land] do
    onLand[lands[land][n]] = true;
  end
  local pieces, piecesCounted = Pieces(IsPassableLand, onLand);
  local main = Biggest(pieces, piecesCounted);
  if main == nil then
    return nil, {}, landCounted[land];
  end
  local plots = pieces[main];
  table.sort(plots);
  local isMember = {};
  local countedPlots = {};
  for n = 1, #plots do
    isMember[plots[n]] = true;
    if IsCounted(Map.GetPlotByIndex(plots[n])) then
      countedPlots[#countedPlots + 1] = plots[n];
    end
  end
  return isMember, countedPlots, landCounted[land];
end

-- The stock row limit of a major start (AssignStartingPlots
-- __GetValidAdjacent); with both limits 0 every row is open here.
local function InStartRows(y, minPercent, maxPercent)
  local _, gridHeight = Map.GetGridSize();
  local maxRows = math.ceil(gridHeight * (maxPercent or 0) / 100);
  local minRows = math.ceil(gridHeight * (minPercent or 0) / 100);
  if maxRows == 0 and minRows == 0 then
    return true;
  end
  return y > minRows and y <= gridHeight - maxRows;
end

local function FarthestPointSeeds(countedPlots, count)
  local seeds = {};
  if #countedPlots == 0 or count <= 0 then
    return seeds;
  end
  local origin = countedPlots[1];
  local first = origin;
  local firstDistance = -1;
  for n = 1, #countedPlots do
    local distance = Map.GetPlotDistance(origin, countedPlots[n]);
    if distance > firstDistance then
      first = countedPlots[n];
      firstDistance = distance;
    end
  end
  seeds[1] = first;
  local nearest = {};
  for n = 1, #countedPlots do
    nearest[n] = Map.GetPlotDistance(first, countedPlots[n]);
  end
  while #seeds < count do
    local chosen = nil;
    local chosenDistance = -1;
    for n = 1, #countedPlots do
      if nearest[n] > chosenDistance then
        chosen = n;
        chosenDistance = nearest[n];
      end
    end
    if chosen == nil or chosenDistance <= 0 then
      break;
    end
    local seed = countedPlots[chosen];
    seeds[#seeds + 1] = seed;
    for n = 1, #countedPlots do
      local distance = Map.GetPlotDistance(seed, countedPlots[n]);
      if distance < nearest[n] then
        nearest[n] = distance;
      end
    end
  end
  return seeds;
end

-- A binary min-heap of {distance, plot index}, ordered by distance, then
-- plot index.
local function HeapLess(a, b)
  if a[1] ~= b[1] then
    return a[1] < b[1];
  end
  return a[2] < b[2];
end

local function HeapPush(heap, entry)
  local n = #heap + 1;
  heap[n] = entry;
  while n > 1 do
    local parent = math.floor(n / 2);
    if HeapLess(heap[n], heap[parent]) then
      heap[n], heap[parent] = heap[parent], heap[n];
      n = parent;
    else
      break;
    end
  end
end

local function HeapPop(heap)
  local size = #heap;
  if size == 0 then
    return nil;
  end
  local top = heap[1];
  heap[1] = heap[size];
  heap[size] = nil;
  size = size - 1;
  local n = 1;
  while true do
    local left = 2 * n;
    local right = left + 1;
    local smallest = n;
    if left <= size and HeapLess(heap[left], heap[smallest]) then
      smallest = left;
    end
    if right <= size and HeapLess(heap[right], heap[smallest]) then
      smallest = right;
    end
    if smallest == n then
      break;
    end
    heap[n], heap[smallest] = heap[smallest], heap[n];
    n = smallest;
  end
  return top;
end

-- One growth from the seeds: one plot at a time, the region with the
-- fewest counted plots (lowest region on a tie) among those that can still
-- grow claims its free passable plot nearest its seed (lowest plot index
-- on a tie). Returns the owner of each plot (region number, 1-based), each
-- region's counted size, and the number of plots no region could reach
-- over passable land (given to the region with the nearest seed).
local function Grow(seeds, isMember)
  local regionCount = #seeds;
  local owner = {};
  local sizes = {};
  local heaps = {};

  local function PushNeighbours(r, plot)
    local adjacent = Neighbours(plot);
    for k = 1, #adjacent do
      local other = adjacent[k];
      local otherIndex = other:GetIndex();
      if owner[otherIndex] == nil and isMember[otherIndex] == true and IsPassableLand(other) then
        HeapPush(heaps[r], { Map.GetPlotDistance(seeds[r], otherIndex), otherIndex });
      end
    end
  end

  for r = 1, regionCount do
    owner[seeds[r]] = r;
    sizes[r] = 1;
    heaps[r] = {};
  end
  for r = 1, regionCount do
    PushNeighbours(r, Map.GetPlotByIndex(seeds[r]));
  end

  while true do
    -- Drop claimed plots from the top of each heap, then pick the region.
    local chosen = nil;
    for r = 1, regionCount do
      local heap = heaps[r];
      while #heap > 0 and owner[heap[1][2]] ~= nil do
        HeapPop(heap);
      end
      if #heap > 0 and (chosen == nil or sizes[r] < sizes[chosen]) then
        chosen = r;
      end
    end
    if chosen == nil then
      break;
    end
    local entry = HeapPop(heaps[chosen]);
    local plot = Map.GetPlotByIndex(entry[2]);
    owner[entry[2]] = chosen;
    if IsCounted(plot) then
      sizes[chosen] = sizes[chosen] + 1;
    end
    PushNeighbours(chosen, plot);
  end

  -- Plots no region can reach over passable land (enclosed by mountains):
  -- the region with the nearest seed.
  local unreached = 0;
  local plotCount = Map.GetPlotCount();
  for plotIndex = 0, plotCount - 1 do
    if isMember[plotIndex] == true and owner[plotIndex] == nil then
      local plot = Map.GetPlotByIndex(plotIndex);
      if IsPassableLand(plot) then
        local chosen = 1;
        local chosenDistance = nil;
        for r = 1, regionCount do
          local distance = Map.GetPlotDistance(seeds[r], plotIndex);
          if chosenDistance == nil or distance < chosenDistance then
            chosen = r;
            chosenDistance = distance;
          end
        end
        owner[plotIndex] = chosen;
        if IsCounted(plot) then
          sizes[chosen] = sizes[chosen] + 1;
        end
        unreached = unreached + 1;
      end
    end
  end
  return owner, sizes, unreached;
end

-- Levels the regions after the growth: while two neighbouring regions
-- differ by two counted plots or more, the pair with the largest difference
-- (then the larger donor, then the lower region numbers) moves one counted
-- plot of the donor next to the receiver: the one farthest from the
-- donor's seed (lowest plot index on a tie) whose loss leaves every plot
-- the donor's seed reached still reachable. A pair with no such plot is
-- skipped until the next move. Every move narrows a gap of two or more, so
-- the pass ends; MAX_BALANCE_MOVES bounds it anyway. Returns the moves.
local MAX_BALANCE_MOVES = 4000;

local function Balance(seeds, owner, sizes)
  local plotCount = Map.GetPlotCount();
  local plots = {};
  local adjacent = {};
  local counted = {};
  for plotIndex = 0, plotCount - 1 do
    if owner[plotIndex] ~= nil then
      plots[#plots + 1] = plotIndex;
      local plot = Map.GetPlotByIndex(plotIndex);
      counted[plotIndex] = IsCounted(plot);
      local list = {};
      local neighbours = Neighbours(plot);
      for k = 1, #neighbours do
        local otherIndex = neighbours[k]:GetIndex();
        if owner[otherIndex] ~= nil then
          list[#list + 1] = otherIndex;
        end
      end
      adjacent[plotIndex] = list;
    end
  end

  -- The plots of region r reachable from its seed through its own plots,
  -- without the plot skipped.
  local function Reached(r, skipped)
    local seen = {};
    local seed = seeds[r];
    if seed == skipped then
      return seen;
    end
    seen[seed] = true;
    local queue = { seed };
    local head = 1;
    while head <= #queue do
      local current = queue[head];
      head = head + 1;
      local list = adjacent[current];
      for k = 1, #list do
        local other = list[k];
        if seen[other] ~= true and other ~= skipped and owner[other] == r then
          seen[other] = true;
          queue[#queue + 1] = other;
        end
      end
    end
    return seen;
  end

  local moves = 0;
  local skippedPairs = {};
  while moves < MAX_BALANCE_MOVES do
    local donor = nil;
    local receiver = nil;
    local bestDiff = nil;
    for n = 1, #plots do
      local plotIndex = plots[n];
      if counted[plotIndex] then
        local a = owner[plotIndex];
        local list = adjacent[plotIndex];
        for k = 1, #list do
          local b = owner[list[k]];
          if b ~= a and skippedPairs[a * 1000 + b] ~= true then
            local diff = sizes[a] - sizes[b];
            if diff >= 2 then
              local better = false;
              if bestDiff == nil or diff > bestDiff then
                better = true;
              elseif diff == bestDiff then
                if sizes[a] ~= sizes[donor] then
                  better = sizes[a] > sizes[donor];
                elseif a ~= donor then
                  better = a < donor;
                else
                  better = b < receiver;
                end
              end
              if better then
                donor = a;
                receiver = b;
                bestDiff = diff;
              end
            end
          end
        end
      end
    end
    if donor == nil then
      break;
    end

    local candidates = {};
    for n = 1, #plots do
      local plotIndex = plots[n];
      if owner[plotIndex] == donor and counted[plotIndex] and plotIndex ~= seeds[donor] then
        local list = adjacent[plotIndex];
        for k = 1, #list do
          if owner[list[k]] == receiver then
            candidates[#candidates + 1] = { Map.GetPlotDistance(seeds[donor], plotIndex), plotIndex };
            break;
          end
        end
      end
    end
    table.sort(candidates, function(left, right)
      if left[1] ~= right[1] then
        return left[1] > right[1];
      end
      return left[2] < right[2];
    end);

    local before = Reached(donor, nil);
    local moved = false;
    for n = 1, #candidates do
      local plotIndex = candidates[n][2];
      local after = Reached(donor, plotIndex);
      local intact = true;
      -- Order-independent: any plot lost makes the move invalid.
      for other, _ in pairs(before) do
        if other ~= plotIndex and after[other] ~= true then
          intact = false;
          break;
        end
      end
      if intact then
        owner[plotIndex] = receiver;
        sizes[donor] = sizes[donor] - 1;
        sizes[receiver] = sizes[receiver] + 1;
        moved = true;
        break;
      end
    end
    if moved then
      moves = moves + 1;
      skippedPairs = {};
    else
      skippedPairs[donor * 1000 + receiver] = true;
    end
  end
  return moves;
end

local function WrapsX()
  local width, _ = Map.GetGridSize();
  if width < 3 then
    return false;
  end
  local west = Map.GetPlot(0, 0);
  local east = Map.GetPlot(width - 1, 0);
  return west ~= nil and east ~= nil and Map.GetPlotDistance(west:GetIndex(), east:GetIndex()) == 1;
end

-- Each seed moves to its region's counted plot nearest the region's centre
-- (x taken relative to the seed, across the wrap where the map wraps),
-- among the plots in the start rows when the region has any there.
-- Returns the new seeds and whether any moved.
local function Recentre(seeds, owner, countedPlots, isSeedable)
  local width, height = Map.GetGridSize();
  local wraps = WrapsX();
  local regionCount = #seeds;
  local sumX = {};
  local sumY = {};
  local count = {};
  local seedX = {};
  for r = 1, regionCount do
    sumX[r] = 0;
    sumY[r] = 0;
    count[r] = 0;
    seedX[r] = Map.GetPlotByIndex(seeds[r]):GetX();
  end
  for n = 1, #countedPlots do
    local plotIndex = countedPlots[n];
    local r = owner[plotIndex];
    if r ~= nil then
      local plot = Map.GetPlotByIndex(plotIndex);
      local dx = plot:GetX() - seedX[r];
      if wraps then
        if dx > width / 2 then
          dx = dx - width;
        elseif dx < -width / 2 then
          dx = dx + width;
        end
      end
      sumX[r] = sumX[r] + dx;
      sumY[r] = sumY[r] + plot:GetY();
      count[r] = count[r] + 1;
    end
  end

  local moved = false;
  local result = {};
  for r = 1, regionCount do
    result[r] = seeds[r];
    if count[r] > 0 then
      local targetX = math.floor(seedX[r] + sumX[r] / count[r] + 0.5);
      if wraps then
        targetX = targetX % width;
      elseif targetX < 0 then
        targetX = 0;
      elseif targetX > width - 1 then
        targetX = width - 1;
      end
      local targetY = math.floor(sumY[r] / count[r] + 0.5);
      if targetY < 0 then
        targetY = 0;
      elseif targetY > height - 1 then
        targetY = height - 1;
      end
      local target = Map.GetPlot(targetX, targetY);
      if target ~= nil then
        local targetIndex = target:GetIndex();
        local best = nil;
        local bestDistance = nil;
        local bestInRows = false;
        for n = 1, #countedPlots do
          local plotIndex = countedPlots[n];
          if owner[plotIndex] == r then
            local inRows = (isSeedable[plotIndex] == true);
            local distance = Map.GetPlotDistance(targetIndex, plotIndex);
            if best == nil or (inRows and not bestInRows)
              or (inRows == bestInRows and distance < bestDistance) then
              best = plotIndex;
              bestDistance = distance;
              bestInRows = inRows;
            end
          end
        end
        if best ~= nil and best ~= seeds[r] then
          result[r] = best;
          moved = true;
        end
      end
    end
  end
  return result, moved;
end

-- The regions for regionCount civilizations, as engine-style lists (index
-- 0 to regionCount - 1, each the sorted plot indices of its passable
-- plots), or nil with the reason when the map cannot carry them.
local function BuildEqualRegions(regionCount, startMinY, startMaxY)
  if regionCount == nil or regionCount < 1 then
    return nil, "no_majors";
  end
  local isMember, countedPlots, landCounted = MainLand();
  if isMember == nil then
    return nil, "no_land", 0;
  end
  if #countedPlots * 100 < landCounted * MAIN_SHARE_PERCENT then
    return nil, "split", #countedPlots;
  end
  if #countedPlots < regionCount * MIN_COUNTED_PER_REGION then
    return nil, "too_small", #countedPlots;
  end
  local seedable = {};
  local isSeedable = {};
  for n = 1, #countedPlots do
    local plotIndex = countedPlots[n];
    if InStartRows(Map.GetPlotByIndex(plotIndex):GetY(), startMinY, startMaxY) then
      seedable[#seedable + 1] = plotIndex;
      isSeedable[plotIndex] = true;
    end
  end
  local seeds = FarthestPointSeeds(seedable, regionCount);
  if #seeds < regionCount then
    return nil, "too_few_seeds", #countedPlots;
  end

  local owner, sizes, unreached = Grow(seeds, isMember);
  local rounds = 0;
  for round = 1, RECENTRE_ROUNDS do
    local moved;
    seeds, moved = Recentre(seeds, owner, countedPlots, isSeedable);
    if not moved then
      break;
    end
    rounds = round;
    owner, sizes, unreached = Grow(seeds, isMember);
  end
  local moves = Balance(seeds, owner, sizes);
  local smallest = nil;
  local largest = nil;
  for r = 1, regionCount do
    if smallest == nil or sizes[r] < smallest then
      smallest = sizes[r];
    end
    if largest == nil or sizes[r] > largest then
      largest = sizes[r];
    end
  end
  local allowed = math.max(SPREAD_MIN, math.floor(#countedPlots * SPREAD_PERCENT / (100 * regionCount)));
  if largest - smallest > allowed then
    return nil, "spread", #countedPlots;
  end

  -- Number the regions by their seed's plot index.
  local order = {};
  for r = 1, regionCount do
    order[r] = r;
  end
  table.sort(order, function(a, b) return seeds[a] < seeds[b]; end);
  local numberOf = {};
  for n = 1, regionCount do
    numberOf[order[n]] = n - 1;
  end

  local regions = {};
  for n = 0, regionCount - 1 do
    regions[n] = {};
  end
  local plotCount = Map.GetPlotCount();
  for plotIndex = 0, plotCount - 1 do
    local r = owner[plotIndex];
    if r ~= nil then
      local list = regions[numberOf[r]];
      list[#list + 1] = plotIndex;
    end
  end

  local info = {
    Counted = #countedPlots,
    Rounds = rounds,
    Unreached = unreached,
    Moves = moves,
    Sizes = {},
    Seeds = {},
    Min = nil,
    Max = nil
  };
  local checksum = 17;
  for n = 0, regionCount - 1 do
    local r = order[n + 1];
    info.Sizes[n] = sizes[r];
    info.Seeds[n] = seeds[r];
    if info.Min == nil or sizes[r] < info.Min then
      info.Min = sizes[r];
    end
    if info.Max == nil or sizes[r] > info.Max then
      info.Max = sizes[r];
    end
    checksum = AddChecksum(checksum, n + 1);
    local list = regions[n];
    for k = 1, #list do
      checksum = AddChecksum(checksum, list[k] + 1);
    end
  end
  info.Checksum = checksum;
  return regions, "ok", info;
end

RoseBetterStarts.BuildEqualRegions = BuildEqualRegions;

local function CopyList(list)
  local copy = {};
  for n = 1, #list do
    copy[n] = list[n];
  end
  return copy;
end

-- Installs the replacement for one AssignStartingPlots.Create and returns
-- the function that restores the engine's functions. Sets
-- RoseBetterStarts.RegionsMode ("engine" on maps not listed, "equal" when
-- the regions were used, "fallback" when the map could not carry them,
-- "refused" when the engine kept its own functions) and
-- RoseBetterStarts.RegionsChecksum.
function RoseBetterStarts.InstallEqualRegions(baseMapFile, args)
  RoseBetterStarts.RegionsMode = "engine";
  RoseBetterStarts.RegionsChecksum = 0;
  if EQUAL_AREA_MAPS[baseMapFile] ~= true then
    return function() end;
  end
  if type(StartPositioner) ~= "table"
    or StartPositioner.DivideMapIntoMajorRegions == nil
    or StartPositioner.GetMajorCivStartPlots == nil then
    RoseBetterStarts.RegionsMode = "refused";
    print("RBS_REGIONS mode=refused applied=no reason=no_start_positioner");
    return function() end;
  end

  local baseDivide = StartPositioner.DivideMapIntoMajorRegions;
  local baseGet = StartPositioner.GetMajorCivStartPlots;
  local regions = nil;

  local function Divide(regionCount, minMajorFertility, minMinorFertility, largestOnly)
    local result = baseDivide(regionCount, minMajorFertility, minMinorFertility, largestOnly);
    -- An error here leaves the engine's regions, never a failed generation.
    local startMinY = 0;
    local startMaxY = 0;
    if args ~= nil then
      startMinY = args.START_MIN_Y or 0;
      startMaxY = args.START_MAX_Y or 0;
    end
    local okBuild, built, reason, info = pcall(BuildEqualRegions, regionCount, startMinY, startMaxY);
    if okBuild and built ~= nil and StartPositioner.GetNumMajorCivStarts ~= nil then
      -- Regions the engine did not make would be marked used and queried.
      local okCount, engineCount = pcall(StartPositioner.GetNumMajorCivStarts);
      if okCount and type(engineCount) == "number" and engineCount < regionCount then
        built = nil;
        reason = "engine_count";
        info = engineCount;
      end
    end
    if not okBuild then
      print("RBS_REGIONS_ERROR " .. tostring(built));
      reason = "error";
      info = nil;
      built = nil;
    end
    if built ~= nil then
      regions = built;
      RoseBetterStarts.RegionsMode = "equal";
      RoseBetterStarts.RegionsChecksum = info.Checksum;
      print(
        "RBS_REGIONS mode=equal applied=yes regions=" .. tostring(regionCount)
        .. " counted=" .. tostring(info.Counted)
        .. " min=" .. tostring(info.Min)
        .. " max=" .. tostring(info.Max)
        .. " rounds=" .. tostring(info.Rounds)
        .. " unreached=" .. tostring(info.Unreached)
        .. " moves=" .. tostring(info.Moves)
        .. " checksum=" .. tostring(info.Checksum)
      );
      for n = 0, regionCount - 1 do
        print(
          "RBS_REGION index=" .. tostring(n)
          .. " counted=" .. tostring(info.Sizes[n])
          .. " plots=" .. tostring(#built[n])
          .. " seed=" .. tostring(info.Seeds[n])
        );
      end
    else
      regions = nil;
      RoseBetterStarts.RegionsMode = "fallback";
      print(
        "RBS_REGIONS mode=fallback applied=yes regions=" .. tostring(regionCount)
        .. " reason=" .. tostring(reason)
        .. " counted=" .. tostring(type(info) == "number" and info or 0)
      );
    end
    return result;
  end

  local function GetPlots(regionIndex)
    if regions ~= nil and regions[regionIndex] ~= nil then
      return CopyList(regions[regionIndex]);
    end
    return baseGet(regionIndex);
  end

  local okInstall = pcall(function()
    StartPositioner.DivideMapIntoMajorRegions = Divide;
    StartPositioner.GetMajorCivStartPlots = GetPlots;
  end);
  local function Restore()
    pcall(function()
      StartPositioner.DivideMapIntoMajorRegions = baseDivide;
      StartPositioner.GetMajorCivStartPlots = baseGet;
    end);
  end
  if not okInstall
    or StartPositioner.DivideMapIntoMajorRegions ~= Divide
    or StartPositioner.GetMajorCivStartPlots ~= GetPlots then
    Restore();
    RoseBetterStarts.RegionsMode = "refused";
    print("RBS_REGIONS mode=refused applied=no reason=assignment");
    return function() end;
  end
  return Restore;
end
