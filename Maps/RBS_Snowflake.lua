------------------------------------------------------------------------------
--	FILE:	 RBS_Snowflake.lua
--	PURPOSE: Rose Snowflake. Six arms around a central hub, generated with
--	         six-fold rotational symmetry: the map is built on one 60-degree
--	         wedge and every plot of the wedge is copied to the five other
--	         rotations, so each player's arm, the city-state islands beside
--	         it and its share of the hub are the same land, rivers and bonus
--	         resources. Only the luxuries differ (arms alternate sets A/B/C,
--	         the six city-state islands D/E/F, the hub holds G and H), and
--	         the natural wonders in the hub (random, at evenly spaced sites).
--	         The details (coastline, hills, woods, rivers, island shapes,
--	         resource spots, which luxuries make up each set) are random each
--	         game; the symmetry is not.
--
--	Each arm, from the hub out: a short desert with a floodplain river, then
--	woods on one side, rainforest on the other and a few mountains between
--	them, then the start near the tip, between a tundra corner and a hilly
--	corner with mountains, each two hexes thick. Five rivers, three of every
--	strategic resource. Each gap between two arms holds an island about
--	three hexes thick with two coastal city-states and a mountain. The hub
--	is one round landmass around a lake, with a river in every sixth and
--	the natural wonder sites inside it.
--
--	Spectator slots (leader LEADER_SPECTATOR or civilization
--	CIVILIZATION_SPECTATOR, e.g. Better Spectator Mod) never take an arm:
--	each gets a small snow islet in a corner of the grid, outside the
--	symmetric area. Map generation only; randomness comes from
--	TerrainBuilder.GetRandomNumber in a fixed order, so every machine in a
--	multiplayer game builds the same map (RBS_SNOWFLAKE_FINGERPRINT).
------------------------------------------------------------------------------

include "MapEnums"
include "NaturalWonderGenerator"   -- the stock multi-tile placement helpers (fallback only)

local LOG = "RBS_SNOWFLAKE";
local VERSION = 3;

local RADIUS = 30;                 -- hex distance from the centre to the symmetric edge
local GRID = 2 * RADIUS + 4;       -- square grid, even width and height
local CX = RADIUS + 1;             -- centre plot
local CY = RADIUS + 1;

local NUM_ARMS = 6;
local START_Q, START_R = 24, 0;    -- arm 0 start (axial): near the back, on the arm's axis
-- The hub: land within this squared distance of the centre, measured in hex
-- widths (q*q + q*r + r*r, a round shape), plus each wonder site's
-- neighbours; the lake is the centre and ring 1.
local HUB_E2 = 52;
local ISLAND_SIGMA_FIRST = 15;     -- island 0 runs along the 30-degree bisector,
local ISLAND_SIGMA_LAST = 27;      -- sigma = q + r is the distance along it
local ISLAND_CLEARANCE = 3;        -- island land at least this far from the mainland
local CS_INNER_SIGMA = 18;
local CS_OUTER_SIGMA = 26;
-- Wonder sites on the 30-degree bisectors, inside the hub. With the
-- start on the arm's axis every arm has the same distances to the sites
-- (the arm is symmetric about its axis), and neighbouring sites are 8 apart,
-- the engine's minimum between natural wonders (MinDistanceNW).
local WONDER_SITE_Q, WONDER_SITE_R = 4, 4;
-- The hub luxury slots G and H (axial, canonical).
local HUB_LUX = { {4, -1}, {3, 1} };

------------------------------------------------------------------------------
-- Hex geometry. Civ VI uses an odd-r offset grid (odd rows shifted east,
-- y = 0 the south row). Axial: q = x - floor(y / 2), r = y; neighbours
-- E (1,0), NE (0,1), NW (-1,1), W (-1,0), SW (0,-1), SE (1,-1).
------------------------------------------------------------------------------
local DIRS = { {1, 0}, {0, 1}, {-1, 1}, {-1, 0}, {0, -1}, {1, -1} };

local function Floor2(v)
	return math.floor(v / 2);
end

local function ToAxial(x, y)
	return (x - Floor2(y)) - (CX - Floor2(CY)), y - CY;
end

local function ToOffset(q, r)
	local y = r + CY;
	return q + (CX - Floor2(CY)) + Floor2(y), y;
end

local function HexDist(q, r)
	return (math.abs(q) + math.abs(r) + math.abs(q + r)) / 2;
end

local function Dist(q1, r1, q2, r2)
	return HexDist(q1 - q2, r1 - r2);
end

-- 60 degrees anticlockwise about the centre.
local function Rot(q, r)
	return -r, q + r;
end

local function RotN(q, r, n)
	for _ = 1, n % 6 do
		q, r = Rot(q, r);
	end
	return q, r;
end

-- The fundamental wedge: angles in [-30, 30) degrees around arm 0 (east).
-- Exactly one hex of every rotation orbit (other than the centre) is in it.
local function IsCanonical(q, r)
	if q == 0 and r == 0 then
		return false;
	end
	if r > 0 then
		return q > r;
	end
	return q >= -2 * r;
end

-- Returns the canonical hex of (q, r)'s orbit and m with canon = Rot^m(q, r).
local function Canon(q, r)
	if q == 0 and r == 0 then
		return 0, 0, 0;
	end
	for m = 0, 5 do
		if IsCanonical(q, r) then
			return q, r, m;
		end
		q, r = Rot(q, r);
	end
	error(LOG .. ": no canonical rotation");
end

local function Key(q, r)
	return (q + 64) * 128 + (r + 64);
end

local function KeyQR(k)
	return math.floor(k / 128) - 64, (k % 128) - 64;
end

local function CKey(q, r)
	local cq, cr, m = Canon(q, r);
	return Key(cq, cr), m;
end

local function InRadius(q, r)
	return HexDist(q, r) <= RADIUS;
end

local function PlotAt(q, r)
	local x, y = ToOffset(q, r);
	return Map.GetPlot(x, y);
end

------------------------------------------------------------------------------
-- Random numbers (the synchronised map generator only).
------------------------------------------------------------------------------
local function Rand(n, tag)
	if n <= 1 then
		return 0;
	end
	return TerrainBuilder.GetRandomNumber(n, tag or "RBS Snowflake");
end

local function Chance(percent, tag)
	return Rand(100, tag) < percent;
end

local function Shuffle(list, tag)
	for i = #list, 2, -1 do
		local j = Rand(i, tag) + 1;
		list[i], list[j] = list[j], list[i];
	end
	return list;
end

------------------------------------------------------------------------------
-- Game data lookups.
------------------------------------------------------------------------------
local TERRAIN = {};
local FEATURE = {};
local MAKE = {};          -- MAKE[base][relief]: base G, P, D, T or S; relief 0 flat, 1 hills, 2 mountain
local BASE_OF = {};
local RELIEF_OF = {};

local function RowIndex(tableName, typeName)
	local t = GameInfo[tableName];
	if t == nil then
		return -1;
	end
	local row = t[typeName];
	if row == nil then
		return -1;
	end
	return row.Index;
end

local function InitTypes()
	TERRAIN.GRASS = RowIndex("Terrains", "TERRAIN_GRASS");
	TERRAIN.GRASS_HILLS = RowIndex("Terrains", "TERRAIN_GRASS_HILLS");
	TERRAIN.GRASS_MOUNTAIN = RowIndex("Terrains", "TERRAIN_GRASS_MOUNTAIN");
	TERRAIN.PLAINS = RowIndex("Terrains", "TERRAIN_PLAINS");
	TERRAIN.PLAINS_HILLS = RowIndex("Terrains", "TERRAIN_PLAINS_HILLS");
	TERRAIN.PLAINS_MOUNTAIN = RowIndex("Terrains", "TERRAIN_PLAINS_MOUNTAIN");
	TERRAIN.SNOW = RowIndex("Terrains", "TERRAIN_SNOW");
	TERRAIN.SNOW_HILLS = RowIndex("Terrains", "TERRAIN_SNOW_HILLS");
	TERRAIN.SNOW_MOUNTAIN = RowIndex("Terrains", "TERRAIN_SNOW_MOUNTAIN");
	TERRAIN.DESERT = RowIndex("Terrains", "TERRAIN_DESERT");
	TERRAIN.DESERT_HILLS = RowIndex("Terrains", "TERRAIN_DESERT_HILLS");
	TERRAIN.DESERT_MOUNTAIN = RowIndex("Terrains", "TERRAIN_DESERT_MOUNTAIN");
	TERRAIN.TUNDRA = RowIndex("Terrains", "TERRAIN_TUNDRA");
	TERRAIN.TUNDRA_HILLS = RowIndex("Terrains", "TERRAIN_TUNDRA_HILLS");
	TERRAIN.TUNDRA_MOUNTAIN = RowIndex("Terrains", "TERRAIN_TUNDRA_MOUNTAIN");
	TERRAIN.COAST = RowIndex("Terrains", "TERRAIN_COAST");
	TERRAIN.OCEAN = RowIndex("Terrains", "TERRAIN_OCEAN");
	FEATURE.FOREST = RowIndex("Features", "FEATURE_FOREST");
	FEATURE.JUNGLE = RowIndex("Features", "FEATURE_JUNGLE");
	FEATURE.MARSH = RowIndex("Features", "FEATURE_MARSH");
	FEATURE.VOLCANO = RowIndex("Features", "FEATURE_VOLCANO");
	FEATURE.FLOODPLAINS = RowIndex("Features", "FEATURE_FLOODPLAINS");
	FEATURE.FLOODPLAINS_GRASSLAND = RowIndex("Features", "FEATURE_FLOODPLAINS_GRASSLAND");
	FEATURE.FLOODPLAINS_PLAINS = RowIndex("Features", "FEATURE_FLOODPLAINS_PLAINS");

	MAKE.G = { [0] = TERRAIN.GRASS, [1] = TERRAIN.GRASS_HILLS, [2] = TERRAIN.GRASS_MOUNTAIN };
	MAKE.P = { [0] = TERRAIN.PLAINS, [1] = TERRAIN.PLAINS_HILLS, [2] = TERRAIN.PLAINS_MOUNTAIN };
	MAKE.S = { [0] = TERRAIN.SNOW, [1] = TERRAIN.SNOW_HILLS, [2] = TERRAIN.SNOW_MOUNTAIN };
	MAKE.D = { [0] = TERRAIN.DESERT, [1] = TERRAIN.DESERT_HILLS, [2] = TERRAIN.DESERT_MOUNTAIN };
	MAKE.T = { [0] = TERRAIN.TUNDRA, [1] = TERRAIN.TUNDRA_HILLS, [2] = TERRAIN.TUNDRA_MOUNTAIN };
	for base, row in pairs(MAKE) do
		for relief = 0, 2 do
			BASE_OF[row[relief]] = base;
			RELIEF_OF[row[relief]] = relief;
		end
	end
end

------------------------------------------------------------------------------
-- The wedge model. Every table is keyed by the canonical hex; reading or
-- writing any hex goes through its canonical key, so the model is six-fold
-- symmetric by construction. The centre hex (Key(0, 0)) is its own orbit.
------------------------------------------------------------------------------
local CENTER_KEY = Key(0, 0);
local g_Order = {};       -- canonical keys in a fixed order (the order of every random draw)
local g_Land = {};
local g_Zone = {};        -- LAKE, HUB, DESERT, WOODS, MIDDLE, JUNGLE, START, TUNDRA, DRYLAND, ISLAND
local g_Terrain = {};     -- land only
local g_Feature = {};
local g_Res = {};         -- [key] = resource type name (same on every copy)
local g_Lux = {};         -- [key] = { group = "ARM"|"ISLAND"|"HUB", slot = j, m = m }
local g_IslandStrat = {}; -- [key] = { m = m }: the island's own strategic (by island set)
local g_Reserved = {};    -- [key] = reason; no second slot, feature change or resource
local g_Goody = {};       -- [key] = true
local g_Rivers = {};      -- list of vertex paths (arm 0 coordinates)
local g_CSSlots = {};     -- island 0 city-state hexes (world coordinates), inner first
local g_Stats = {};

local function KeyOf(q, r)
	if q == 0 and r == 0 then
		return CENTER_KEY, 0;
	end
	return CKey(q, r);
end

local function IsLand(q, r)
	if not InRadius(q, r) then
		return false;
	end
	return g_Land[(KeyOf(q, r))] == true;
end

local function ZoneAt(q, r)
	if not InRadius(q, r) then
		return nil;
	end
	return g_Zone[(KeyOf(q, r))];
end

local function TerrainAt(q, r)
	return g_Terrain[(KeyOf(q, r))];
end

local function CountLandNeighbours(q, r)
	local n = 0;
	for d = 1, 6 do
		if IsLand(q + DIRS[d][1], r + DIRS[d][2]) then
			n = n + 1;
		end
	end
	return n;
end

local function BuildOrder()
	for r = -RADIUS, RADIUS do
		for q = -RADIUS, RADIUS do
			if InRadius(q, r) and IsCanonical(q, r) then
				g_Order[#g_Order + 1] = Key(q, r);
			end
		end
	end
end

------------------------------------------------------------------------------
-- Mainland. Arm frame for arm 0: A = 2q + r (half hexes along the arm from
-- the centre), V = r (rows across it). Regions, hub outwards: a short
-- desert (a river with floodplains), then woods (V >= 2), a centre with a
-- few mountains, and rainforest (V <= -2), then the start area at the back,
-- with a tundra corner (V >= 2) and a desert corner (V <= -2), both two
-- rows thick; the desert corner has a river with floodplains and two
-- mountains at its far end.
------------------------------------------------------------------------------
local function Set(...)
	local s = {};
	for _, v in ipairs({ ... }) do
		s[v] = true;
	end
	return s;
end

local DESERT_END = 21;             -- A of the last desert half-hex (the gate desert)
local BACK_START = 42;             -- A where the back corners begin

-- The hub: a round area around the lake that holds every wonder site with
-- all six of its neighbours (a site is 48 from the centre on this scale).
local function InHub(q, r)
	if q * q + q * r + r * r <= HUB_E2 then
		return true;
	end
	for n = 0, 5 do
		local sq, sr = RotN(WONDER_SITE_Q, WONDER_SITE_R, n);
		if Dist(q, r, sq, sr) <= 1 then
			return true;
		end
	end
	return false;
end

-- The arm's half-width in rows. The back (A >= BACK_START) has a fixed
-- coast at its half-width, so the tundra and desert corners beside the
-- start are two rows thick.
local function ArmMaxRow(A)
	if A < 10 then return -1; end
	if A <= 14 then return 1; end
	if A <= DESERT_END then return 2; end
	if A <= 51 then return 3; end
	if A == 52 then return 2; end
	if A == 53 then return 1; end
	return -1;
end

local function ArmZone(A, V)
	if A <= DESERT_END then
		return "DESERT";
	end
	if A < BACK_START then
		if V >= 2 then return "WOODS"; end
		if V <= -2 then return "JUNGLE"; end
		return "MIDDLE";
	end
	if V >= 2 then return "TUNDRA"; end
	if V <= -2 then return "DRYLAND"; end
	return "START";
end

local function MainlandZone(q, r)
	if InHub(q, r) then
		return "HUB";
	end
	local A, V = 2 * q + r, r;
	local m = ArmMaxRow(A);
	if m >= 0 and math.abs(V) <= m + 1 then
		return ArmZone(A, V);
	end
	return "HUB";
end

local function GenerateMainland()
	for _, k in ipairs(g_Order) do
		local q, r = KeyQR(k);
		local d = HexDist(q, r);
		if d <= 1 then
			g_Zone[k] = "LAKE";
		elseif InHub(q, r) then
			g_Land[k] = true;
			g_Zone[k] = "HUB";
		else
			local A, V = 2 * q + r, r;
			local m = ArmMaxRow(A);
			local av = math.abs(V);
			local land = false;
			if m >= 0 then
				if av < m or (av == m and A >= BACK_START) then
					land = true;
				elseif av == m then
					land = Chance(75, "Snowflake coast");
				elseif av == m + 1 and A >= 16 and A < BACK_START then
					land = Chance(20, "Snowflake coast");
				end
			end
			if land then
				g_Land[k] = true;
				g_Zone[k] = MainlandZone(q, r);
			end
		end
	end
	g_Zone[CENTER_KEY] = "LAKE";

	-- Smooth the coastline: drop land spits, fill one-hex inlets, except the
	-- bays beside the hub (the hub rivers' mouths).
	for _ = 1, 2 do
		for _, k in ipairs(g_Order) do
			local q, r = KeyQR(k);
			if g_Zone[k] ~= "LAKE" and HexDist(q, r) <= RADIUS - 2 then
				local n = CountLandNeighbours(q, r);
				if g_Land[k] and g_Zone[k] ~= "HUB" and n <= 1 then
					g_Land[k] = nil;
					g_Zone[k] = nil;
				elseif not g_Land[k] and n >= 5 and q * q + q * r + r * r > 64 then
					g_Land[k] = true;
					g_Zone[k] = MainlandZone(q, r);
				end
			end
		end
	end
end

-- Distance from every in-radius hex to the nearest land hex (world keys).
local function LandDistance(onlyMainland)
	local dist = {};
	local queue = {};
	for r = -RADIUS, RADIUS do
		for q = -RADIUS, RADIUS do
			if InRadius(q, r) and IsLand(q, r) and (not onlyMainland or ZoneAt(q, r) ~= "ISLAND") then
				dist[Key(q, r)] = 0;
				queue[#queue + 1] = Key(q, r);
			end
		end
	end
	local head = 1;
	while head <= #queue do
		local k = queue[head];
		head = head + 1;
		local q, r = KeyQR(k);
		for d = 1, 6 do
			local nq, nr = q + DIRS[d][1], r + DIRS[d][2];
			local nk = Key(nq, nr);
			if InRadius(nq, nr) and dist[nk] == nil then
				dist[nk] = dist[k] + 1;
				queue[#queue + 1] = nk;
			end
		end
	end
	return dist;
end

------------------------------------------------------------------------------
-- City-state islands. Island 0 lies on the bisector between arm 0 and arm 1;
-- sigma = q + r runs along it, tau = r - q across it (tau / 2 hexes). A
-- meandering spine, then the spine's neighbours, so the island is about
-- three hexes thick.
------------------------------------------------------------------------------
local g_IslandHexes = {};          -- island 0, world coordinates

local function GenerateIslands()
	local mainland = LandDistance(true);
	local island = {};
	local path = {};

	local function OK(q, r, tauMax)
		if HexDist(q, r) > RADIUS - 2 or island[Key(q, r)] then
			return false;
		end
		if math.abs(r - q) > tauMax then
			return false;
		end
		local d = mainland[Key(q, r)];
		return d ~= nil and d >= ISLAND_CLEARANCE;
	end

	local firstChoices = {};
	for tau = -2, 2 do
		if (ISLAND_SIGMA_FIRST + tau) % 2 == 0 then
			local r = Floor2(ISLAND_SIGMA_FIRST + tau);
			local q = ISLAND_SIGMA_FIRST - r;
			if OK(q, r, 3) then
				firstChoices[#firstChoices + 1] = { q, r };
			end
		end
	end
	if #firstChoices == 0 then
		print(LOG .. "_ISLAND_FAILED reason=no_first_hex");
		return;
	end
	local first = firstChoices[Rand(#firstChoices, "Snowflake island start") + 1];
	local cq, cr = first[1], first[2];
	island[Key(cq, cr)] = true;
	path[1] = { cq, cr };

	-- Spine: every step moves E (tau - 1) or NE (tau + 1).
	local drift = (Rand(2, "Snowflake island drift") == 0) and -1 or 1;
	while cq + cr < ISLAND_SIGMA_LAST do
		local tau = cr - cq;
		if tau >= 3 then
			drift = -1;
		elseif tau <= -3 then
			drift = 1;
		end
		local preferred, other;
		if drift > 0 then
			preferred, other = { cq, cr + 1 }, { cq + 1, cr };
		else
			preferred, other = { cq + 1, cr }, { cq, cr + 1 };
		end
		local pick = nil;
		local first2, second2 = preferred, other;
		if not Chance(70, "Snowflake island step") then
			first2, second2 = other, preferred;
		end
		if OK(first2[1], first2[2], 3) then
			pick = first2;
		elseif OK(second2[1], second2[2], 3) then
			pick = second2;
		end
		if pick == nil then
			break;
		end
		cq, cr = pick[1], pick[2];
		island[Key(cq, cr)] = true;
		path[#path + 1] = { cq, cr };
		if Chance(30, "Snowflake island turn") then
			drift = -drift;
		end
	end

	-- Body: most of the spine's neighbours, then a few bulges one ring further.
	local hexes = {};
	for i = 1, #path do
		hexes[#hexes + 1] = path[i];
	end
	local ring1 = {};
	for i = 1, #path do
		for d = 1, 6 do
			local nq, nr = path[i][1] + DIRS[d][1], path[i][2] + DIRS[d][2];
			if OK(nq, nr, 6) and Chance(85, "Snowflake island body") then
				island[Key(nq, nr)] = true;
				hexes[#hexes + 1] = { nq, nr };
				ring1[#ring1 + 1] = { nq, nr };
			end
		end
	end
	for i = 1, #ring1 do
		if Chance(12, "Snowflake island bulge") then
			local d = Rand(6, "Snowflake island bulge dir") + 1;
			local nq, nr = ring1[i][1] + DIRS[d][1], ring1[i][2] + DIRS[d][2];
			if OK(nq, nr, 7) then
				island[Key(nq, nr)] = true;
				hexes[#hexes + 1] = { nq, nr };
			end
		end
	end
	-- Drop hexes left with at most one island neighbour.
	local kept = {};
	for _, h in ipairs(hexes) do
		local n = 0;
		for d = 1, 6 do
			if island[Key(h[1] + DIRS[d][1], h[2] + DIRS[d][2])] then
				n = n + 1;
			end
		end
		if n >= 2 then
			kept[#kept + 1] = h;
		else
			island[Key(h[1], h[2])] = nil;
		end
	end
	-- Fill one-hex holes, so every water hex touching the island is open sea.
	local holes = {};
	for _, h in ipairs(kept) do
		for d = 1, 6 do
			local nq, nr = h[1] + DIRS[d][1], h[2] + DIRS[d][2];
			if not island[Key(nq, nr)] and InRadius(nq, nr) then
				local enclosed = true;
				for d2 = 1, 6 do
					if not island[Key(nq + DIRS[d2][1], nr + DIRS[d2][2])] then
						enclosed = false;
						break;
					end
				end
				if enclosed then
					island[Key(nq, nr)] = true;
					holes[#holes + 1] = { nq, nr };
				end
			end
		end
	end
	for _, h in ipairs(holes) do
		kept[#kept + 1] = h;
	end
	g_IslandHexes = kept;
	for _, h in ipairs(kept) do
		local k = CKey(h[1], h[2]);
		g_Land[k] = true;
		g_Zone[k] = "ISLAND";
	end

	-- City-state hexes: around each target distance along the island, the
	-- coastal hex farthest from every major start (all six), then the one
	-- nearest the target; the two kept at least 6 apart.
	local function NearestStart(q, r)
		local best = nil;
		for n = 0, NUM_ARMS - 1 do
			local sq, sr = RotN(START_Q, START_R, n);
			local d = Dist(q, r, sq, sr);
			if best == nil or d < best then
				best = d;
			end
		end
		return best;
	end
	-- City-states stand on the coast: a hex with a water neighbour.
	local function Coastal(q, r)
		for d = 1, 6 do
			if not island[Key(q + DIRS[d][1], r + DIRS[d][2])] then
				return true;
			end
		end
		return false;
	end
	local function PathAt(sigma, lo, hi, avoid)
		local best, bestKey = nil, nil;
		for i = 1, #kept do
			local q, r = kept[i][1], kept[i][2];
			local s = q + r;
			if Coastal(q, r) and s >= lo and s <= hi
				and (avoid == nil or Dist(q, r, avoid[1], avoid[2]) >= 6) then
				local key = { NearestStart(q, r), -math.abs(s - sigma), -i };
				local better = bestKey == nil;
				if not better then
					for j = 1, 3 do
						if key[j] ~= bestKey[j] then
							better = key[j] > bestKey[j];
							break;
						end
					end
				end
				if better then
					best, bestKey = kept[i], key;
				end
			end
		end
		return best;
	end
	local inner = PathAt(CS_INNER_SIGMA, ISLAND_SIGMA_FIRST, CS_INNER_SIGMA + 3, nil)
		or PathAt(CS_INNER_SIGMA, ISLAND_SIGMA_FIRST, ISLAND_SIGMA_LAST, nil);
	local outer = inner and (PathAt(CS_OUTER_SIGMA, CS_OUTER_SIGMA - 3, ISLAND_SIGMA_LAST, inner)
		or PathAt(CS_OUTER_SIGMA, ISLAND_SIGMA_FIRST, ISLAND_SIGMA_LAST, inner)) or nil;
	if inner ~= nil then
		g_CSSlots[#g_CSSlots + 1] = { inner[1], inner[2] };
		g_Reserved[(CKey(inner[1], inner[2]))] = "CS";
	end
	if outer ~= nil then
		g_CSSlots[#g_CSSlots + 1] = { outer[1], outer[2] };
		g_Reserved[(CKey(outer[1], outer[2]))] = "CS";
	end
	g_Stats.islandPlots = #kept;
	print(LOG .. "_ISLAND spine=" .. #path .. " plots=" .. #kept .. " cs=" .. #g_CSSlots
		.. " last_sigma=" .. (cq + cr));
end

-- Land per zone in one arm's share (the wedge): hub and islands counted per sixth.
local ZONE_NAMES = { "HUB", "DESERT", "WOODS", "MIDDLE", "JUNGLE", "START", "TUNDRA", "DRYLAND", "ISLAND" };

local function LogLand()
	local count = {};
	for _, k in ipairs(g_Order) do
		if g_Land[k] then
			count[g_Zone[k]] = (count[g_Zone[k]] or 0) + 1;
		end
	end
	local parts = {};
	for _, z in ipairs(ZONE_NAMES) do
		parts[#parts + 1] = string.lower(z) .. "=" .. (count[z] or 0);
	end
	print(LOG .. "_LAND per_arm " .. table.concat(parts, " "));
end

------------------------------------------------------------------------------
-- Terrain and relief.
------------------------------------------------------------------------------
local TERRAIN_MIX = {
	HUB      = { {"P", 0, 40}, {"G", 0, 35}, {"P", 1, 15}, {"G", 1, 10} },
	DESERT   = { {"D", 0, 65}, {"D", 1, 35} },
	WOODS    = { {"G", 0, 40}, {"P", 0, 25}, {"G", 1, 20}, {"P", 1, 15} },
	MIDDLE   = { {"G", 0, 40}, {"P", 0, 35}, {"G", 1, 13}, {"P", 1, 12} },
	JUNGLE   = { {"P", 0, 40}, {"G", 0, 35}, {"P", 1, 15}, {"G", 1, 10} },
	START    = { {"P", 0, 40}, {"G", 0, 40}, {"P", 1, 12}, {"G", 1, 8} },
	TUNDRA   = { {"T", 0, 62}, {"T", 1, 38} },
	DRYLAND  = { {"D", 0, 62}, {"D", 1, 38} },
	ISLAND   = { {"G", 0, 35}, {"P", 0, 35}, {"P", 1, 15}, {"G", 1, 15} },
};
-- Percent of woods, rainforest and (on flat grassland) marsh per zone.
local FEATURE_MIX = {
	HUB = { 20, 0, 0 }, DESERT = { 0, 0, 0 }, WOODS = { 65, 0, 0 }, MIDDLE = { 12, 0, 0 },
	JUNGLE = { 0, 62, 8 }, START = { 10, 0, 0 }, TUNDRA = { 35, 0, 0 }, DRYLAND = { 0, 0, 0 },
	ISLAND = { 30, 20, 0 },
};

local function RollTerrain(zone)
	local mix = TERRAIN_MIX[zone] or TERRAIN_MIX.MIDDLE;
	local roll = Rand(100, "Snowflake terrain");
	local acc = 0;
	for _, entry in ipairs(mix) do
		acc = acc + entry[3];
		if roll < acc then
			return MAKE[entry[1]][entry[2]];
		end
	end
	return MAKE[mix[1][1]][mix[1][2]];
end

local function SetTerrainKey(k, base, relief)
	g_Terrain[k] = MAKE[base][relief];
end

local function BaseOf(k)
	return BASE_OF[g_Terrain[k]] or "G";
end

local function ReliefOf(k)
	return RELIEF_OF[g_Terrain[k]] or 0;
end

local function IsMountainKey(k)
	return ReliefOf(k) == 2;
end

local function WonderSiteKeys()
	local keys = {};
	keys[(CKey(WONDER_SITE_Q, WONDER_SITE_R))] = true;
	return keys;
end

local function NearWonderSite(q, r)
	for n = 0, 5 do
		local sq, sr = RotN(WONDER_SITE_Q, WONDER_SITE_R, n);
		if Dist(q, r, sq, sr) <= 1 then
			return true;
		end
	end
	return false;
end

local function NearCS(q, r)
	for _, slot in ipairs(g_CSSlots) do
		for n = 0, 5 do
			local sq, sr = RotN(slot[1], slot[2], n);
			if Dist(q, r, sq, sr) <= 1 then
				return true;
			end
		end
	end
	return false;
end

-- A small mountain group: a centre among `centres` (canonical keys), then up
-- to size - 1 neighbours accepted by `grow`. Returns the number made.
local function MountainGroup(centres, size, grow, tag)
	if #centres == 0 then
		return 0;
	end
	local k = centres[Rand(#centres, tag) + 1];
	SetTerrainKey(k, BaseOf(k), 2);
	local made = 1;
	local q, r = KeyQR(k);
	local dirs = Shuffle({ 1, 2, 3, 4, 5, 6 }, tag);
	for _, d in ipairs(dirs) do
		if made >= size then
			break;
		end
		local nq, nr = q + DIRS[d][1], r + DIRS[d][2];
		local nk = KeyOf(nq, nr);
		if g_Land[nk] and not IsMountainKey(nk) and g_Reserved[nk] == nil and grow(nk, nq, nr) then
			SetTerrainKey(nk, BaseOf(nk), 2);
			made = made + 1;
		end
	end
	return made;
end

local function Candidates(filter)
	local list = {};
	for _, k in ipairs(g_Order) do
		if g_Land[k] and g_Reserved[k] == nil and not IsMountainKey(k) then
			local q, r = KeyQR(k);
			if filter(k, q, r) then
				list[#list + 1] = k;
			end
		end
	end
	return list;
end

local function AssignTerrain()
	for _, k in ipairs(g_Order) do
		if g_Land[k] then
			g_Terrain[k] = RollTerrain(g_Zone[k]);
		end
	end

	-- Reserved hexes: the start, the wonder sites, the city-states.
	local startKey = CKey(START_Q, START_R);
	g_Reserved[startKey] = "START";
	for k in pairs(WonderSiteKeys()) do
		g_Reserved[k] = "WONDER";
		SetTerrainKey(k, "P", 0);
	end
	for _, slot in ipairs(g_CSSlots) do
		local k = CKey(slot[1], slot[2]);
		SetTerrainKey(k, (BaseOf(k) == "P") and "P" or "G", 0);
	end

	local mountains = 0;
	local function AwayFromStart(q, r)
		return Dist(q, r, START_Q, START_R) >= 2;
	end
	-- A few mountains in the middle of the arm, for district adjacency.
	mountains = mountains + MountainGroup(Candidates(function(k, q, r)
		local A = 2 * q + r;
		return g_Zone[k] == "MIDDLE" and A >= 28 and A <= 38 and math.abs(r) <= 1 and CountLandNeighbours(q, r) == 6;
	end), 3, function(nk, nq, nr)
		return g_Zone[nk] == "MIDDLE" and CountLandNeighbours(nq, nr) >= 5;
	end, "Snowflake middle mountains");
	-- Two mountains at the far end of the desert corner.
	local function CornerEnd(q, r)
		return 2 * q + r >= 47 and r <= -3;
	end
	mountains = mountains + MountainGroup(Candidates(function(k, q, r)
		return g_Zone[k] == "DRYLAND" and CornerEnd(q, r) and CountLandNeighbours(q, r) >= 4 and AwayFromStart(q, r);
	end), 2, function(nk, nq, nr)
		return g_Zone[nk] == "DRYLAND" and 2 * nq + nr >= 45 and AwayFromStart(nq, nr);
	end, "Snowflake corner mountains");
	-- One in the wedge's part of the hub, away from the lake and the wonder sites.
	mountains = mountains + MountainGroup(Candidates(function(k, q, r)
		local d = HexDist(q, r);
		return g_Zone[k] == "HUB" and d >= 3 and d <= 5 and not NearWonderSite(q, r)
			and not (q == HUB_LUX[1][1] and r == HUB_LUX[1][2]) and not (q == HUB_LUX[2][1] and r == HUB_LUX[2][2]);
	end), 1, nil, "Snowflake hub mountain");
	-- One inside each island, not beside a city-state.
	local islandCentres = {};
	for _, h in ipairs(g_IslandHexes) do
		local k = CKey(h[1], h[2]);
		if g_Reserved[k] == nil and not NearCS(h[1], h[2]) and CountLandNeighbours(h[1], h[2]) == 6 then
			islandCentres[#islandCentres + 1] = k;
		end
	end
	mountains = mountains + MountainGroup(islandCentres, 1, nil, "Snowflake island mountain");
	g_Stats.mountains = mountains;

	-- The start: flat, no mountain beside it, at least one hill beside it.
	SetTerrainKey(startKey, (Rand(2, "Snowflake start base") == 0) and "P" or "G", 0);
	local hills = 0;
	local ring = {};
	for d = 1, 6 do
		local nk = CKey(START_Q + DIRS[d][1], START_R + DIRS[d][2]);
		if g_Land[nk] then
			if IsMountainKey(nk) then
				SetTerrainKey(nk, BaseOf(nk), 1);
			end
			if ReliefOf(nk) == 1 then
				hills = hills + 1;
			end
			ring[#ring + 1] = nk;
		end
	end
	if hills == 0 and #ring > 0 then
		local nk = ring[Rand(#ring, "Snowflake start hill") + 1];
		SetTerrainKey(nk, BaseOf(nk), 1);
	end
end

------------------------------------------------------------------------------
-- Rivers. A river is a path of hex corners. Corner coordinates: a hex centre
-- is (2q + r, 3r); its corners are the centre plus (1,1) NE, (0,2) N,
-- (-1,1) NW, (-1,-1) SW, (0,-2) S, (1,-1) SE. Every point is integral and
-- a 60-degree rotation is (X, Y) -> ((X - Y) / 2, (3X + Y) / 2).
------------------------------------------------------------------------------
local CORNER = { {1, 1}, {0, 2}, {-1, 1}, {-1, -1}, {0, -2}, {1, -1} };

local function VKey(X, Y)
	return (X + 256) * 1024 + (Y + 512);
end

local function RotV(X, Y)
	return (X - Y) / 2, (3 * X + Y) / 2;
end

local function CenterQR(X, Y)
	local r = Y / 3;
	return (X - r) / 2, r;
end

-- The three hexes (axial) sharing corner (X, Y).
local function CornerHexes(X, Y)
	if Y % 3 == 2 then
		-- North corner of the hex below it.
		local q1, r1 = CenterQR(X, Y - 2);
		local q2, r2 = CenterQR(X - 1, Y + 1);
		local q3, r3 = CenterQR(X + 1, Y + 1);
		return { {q1, r1}, {q2, r2}, {q3, r3} };
	end
	local q1, r1 = CenterQR(X, Y + 2);
	local q2, r2 = CenterQR(X - 1, Y - 1);
	local q3, r3 = CenterQR(X + 1, Y - 1);
	return { {q1, r1}, {q2, r2}, {q3, r3} };
end

local function CornerNeighbours(X, Y)
	if Y % 3 == 2 then
		return { {X + 1, Y - 1}, {X - 1, Y - 1}, {X, Y + 2} };
	end
	return { {X + 1, Y + 1}, {X - 1, Y + 1}, {X, Y - 2} };
end

-- The two hexes on either side of the edge between two adjacent corners.
local function EdgeHexes(X1, Y1, X2, Y2)
	local a = CornerHexes(X1, Y1);
	local b = CornerHexes(X2, Y2);
	local found = {};
	for i = 1, 3 do
		for j = 1, 3 do
			if a[i][1] == b[j][1] and a[i][2] == b[j][2] then
				found[#found + 1] = a[i];
			end
		end
	end
	return found[1], found[2];
end

local function CornerTouchesWater(X, Y)
	for _, h in ipairs(CornerHexes(X, Y)) do
		if not IsLand(h[1], h[2]) then
			return true;
		end
	end
	return false;
end

-- A river edge needs land on both sides and stays out of the hub: the
-- single-tile natural wonders refuse a river beside them (NoRiver), and a
-- river copied to all six arms would empty every wonder site at once.
local function EdgeIsLand(X1, Y1, X2, Y2)
	local a, b = EdgeHexes(X1, Y1, X2, Y2);
	return a ~= nil and b ~= nil and IsLand(a[1], a[2]) and IsLand(b[1], b[2])
		and ZoneAt(a[1], a[2]) ~= "HUB" and ZoneAt(b[1], b[2]) ~= "HUB";
end

-- A hub river edge: hub (or, at the bay, gate desert) land on both sides,
-- both hexes in this sixth's own wedge (so the six copies never share an
-- edge or a corner), and neither hex a wonder site or its neighbour: the
-- engine refuses every NoRiver wonder (all single-tile ones) on a site
-- whose neighbour has a river edge.
local function HubEdgeOK(X1, Y1, X2, Y2)
	local a, b = EdgeHexes(X1, Y1, X2, Y2);
	if a == nil or b == nil then
		return false;
	end
	for _, h in ipairs({ a, b }) do
		local zone = ZoneAt(h[1], h[2]);
		if not IsLand(h[1], h[2]) or (zone ~= "HUB" and zone ~= "DESERT") or not IsCanonical(h[1], h[2])
			or NearWonderSite(h[1], h[2]) then
			return false;
		end
	end
	return true;
end

local function DistSq(X1, Y1, X2, Y2)
	local dx, dy = X1 - X2, Y1 - Y2;
	return 3 * dx * dx + dy * dy;
end

-- Walks from corner (X, Y) towards target (TX, TY) along land edges, never
-- reusing a corner in `used`. Downstream walks end at the first corner that
-- touches water (the mouth); upstream walks never touch water and end when
-- `goal` accepts a corner. Mostly greedy, sometimes the second-best corner.
local function Walk(X, Y, TX, TY, used, downstream, goal, maxSteps, tag, mouthOK, edgeOK)
	edgeOK = edgeOK or EdgeIsLand;
	local path = { {X, Y} };
	local visited = { [VKey(X, Y)] = true };
	local cx, cy = X, Y;
	for _ = 1, maxSteps do
		local options = {};
		for _, nb in ipairs(CornerNeighbours(cx, cy)) do
			local nk = VKey(nb[1], nb[2]);
			if not visited[nk] and not used[nk] and edgeOK(cx, cy, nb[1], nb[2]) then
				local wet = CornerTouchesWater(nb[1], nb[2]);
				if (downstream and (not wet or mouthOK == nil or mouthOK(nb[1], nb[2]))) or not wet then
					options[#options + 1] = { nb[1], nb[2], DistSq(nb[1], nb[2], TX, TY), wet };
				end
			end
		end
		if #options == 0 then
			return nil;
		end
		table.sort(options, function(a, b)
			if a[3] ~= b[3] then return a[3] < b[3]; end
			if a[1] ~= b[1] then return a[1] < b[1]; end
			return a[2] < b[2];
		end);
		local roll = Rand(100, tag);
		local pick = options[1];
		if roll >= 70 and #options >= 2 then
			pick = options[2];
		end
		cx, cy = pick[1], pick[2];
		visited[VKey(cx, cy)] = true;
		path[#path + 1] = { cx, cy };
		if downstream and pick[4] then
			return path;
		end
		if not downstream and goal(cx, cy) then
			return path;
		end
	end
	return nil;
end

local function TryWalk(X, Y, TX, TY, used, downstream, goal, maxSteps, tag, mouthOK, edgeOK, tries)
	for _ = 1, tries or 8 do
		local path = Walk(X, Y, TX, TY, used, downstream, goal, maxSteps, tag, mouthOK, edgeOK);
		if path ~= nil then
			return path;
		end
	end
	return nil;
end

local function MarkUsed(used, path)
	for _, v in ipairs(path) do
		used[VKey(v[1], v[2])] = true;
	end
end

-- A dry, unused corner of a land hex in `zones` near (TX, TY), among the
-- four nearest.
local function SourceCorner(TX, TY, used, zones, tag)
	local options = {};
	for _, k in ipairs(g_Order) do
		local q, r = KeyQR(k);
		if g_Land[k] and zones[g_Zone[k]] then
			for c = 1, 6 do
				local X, Y = 2 * q + r + CORNER[c][1], 3 * r + CORNER[c][2];
				if not used[VKey(X, Y)] and not CornerTouchesWater(X, Y) then
					local d = DistSq(X, Y, TX, TY);
					if d <= 60 then
						options[#options + 1] = { X, Y, d };
					end
				end
			end
		end
	end
	if #options == 0 then
		return nil;
	end
	table.sort(options, function(a, b)
		if a[3] ~= b[3] then return a[3] < b[3]; end
		if a[1] ~= b[1] then return a[1] < b[1]; end
		return a[2] < b[2];
	end);
	local pick = options[Rand(math.min(4, #options), tag) + 1];
	return pick[1], pick[2];
end

local g_ArmRivers = 0;             -- the first g_ArmRivers entries of g_Rivers are in the arm

local function GenerateRivers()
	local used = {};
	local made = {};
	local missed = {};

	-- 1: past a corner of the start (fresh water), from the middle of the arm
	-- to the tip. The corners are tried in a fixed order.
	local cx0, cy0 = 2 * START_Q + START_R, 3 * START_R;
	local mainMade = false;
	for c = 1, 6 do
		local sX, sY = cx0 + CORNER[c][1], cy0 + CORNER[c][2];
		local up = TryWalk(sX, sY, 38, 0, used, false, function(X, Y)
			return X <= 40;
		end, 30, "Snowflake river up");
		if up ~= nil then
			local tmp = {};
			MarkUsed(tmp, up);
			local down = TryWalk(sX, sY, 56, 0, tmp, true, nil, 16, "Snowflake river down");
			if down ~= nil then
				local river = {};
				for i = #up, 1, -1 do
					river[#river + 1] = up[i];
				end
				for i = 2, #down do
					river[#river + 1] = down[i];
				end
				MarkUsed(used, river);
				made[#made + 1] = river;
				mainMade = true;
				break;
			end
		end
	end
	if not mainMade then
		missed[#missed + 1] = "start";
	end

	-- 2: the desert river, from the centre of the arm through the desert
	-- to the coast beside the hub; 3 and 4 to the woods and rainforest coasts.
	-- The desert river may only reach the sea in the desert (its mouth's
	-- X, which is A, at most DESERT_END - 2); it tries other sources if
	-- needed. The corner river runs along the desert corner.
	-- The hub river (5) ends in the bay on one side of the desert, drawn
	-- here; the desert river heads for the bay on the other side, so it runs
	-- the length of the desert.
	local side = (Rand(2, "Snowflake hub river side") == 0) and 1 or -1;
	local function DesertMouth(X, Y)
		return X <= DESERT_END - 2;
	end
	local function CornerMouth(X, Y)
		return X >= BACK_START and Y <= -3;
	end
	local specs = {
		{ "desert", { {26, -3 * side}, {24, 0}, {23, 3 * side} }, 15, -9 * side, Set("MIDDLE", "JUNGLE", "WOODS", "DESERT"), 4, DesertMouth },
		{ "woods", { {35, 0} }, 33, 15, Set("MIDDLE", "WOODS"), 2, nil },
		{ "rainforest", { {36, 0} }, 37, -15, Set("MIDDLE", "JUNGLE"), 2, nil },
		{ "corner", { {40, -6}, {42, -6}, {44, -3}, {46, -3} }, 54, -10, Set("START", "DRYLAND", "MIDDLE", "JUNGLE"), 3, CornerMouth },
	};
	for _, spec in ipairs(specs) do
		local river = nil;
		for _, src in ipairs(spec[2]) do
			local X, Y = SourceCorner(src[1], src[2], used, spec[5], "Snowflake river source");
			if X ~= nil then
				river = TryWalk(X, Y, spec[3], spec[4], used, true, nil, 30, "Snowflake river " .. spec[1], spec[7]);
			end
			if river ~= nil and #river - 1 >= spec[6] then
				break;
			end
			river = nil;
		end
		if river ~= nil then
			MarkUsed(used, river);
			made[#made + 1] = river;
		else
			missed[#missed + 1] = spec[1];
		end
	end
	g_ArmRivers = #made;

	-- 5: a hub river in every sixth, from the far side of the sixth, past the
	-- lake, to the bay between the arm's desert and a wonder site. Which side
	-- it starts on is drawn each game (Y -> -Y mirrors it across the arm's axis).
	-- If it cannot reach the bay it runs into the lake instead.
	local hubRiver = nil;
	local bayQ, bayR = CenterQR(15, side * 9);
	local function BayMouth(X, Y)
		for _, h in ipairs(CornerHexes(X, Y)) do
			if h[1] == bayQ and h[2] == bayR then
				return true;
			end
		end
		return false;
	end
	for _, goal in ipairs({ { 15, side * 9, 5, BayMouth }, { 0, 0, 3, nil } }) do
		for _, src in ipairs({ {8, -6}, {9, -3}, {10, -6} }) do
			local X, Y = SourceCorner(src[1], side * src[2], used, Set("HUB"), "Snowflake hub river source");
			if X ~= nil then
				hubRiver = TryWalk(X, Y, goal[1], goal[2], used, true, nil, 30, "Snowflake hub river", goal[4], HubEdgeOK, 24);
			end
			if hubRiver ~= nil and #hubRiver - 1 >= goal[3] then
				break;
			end
			hubRiver = nil;
		end
		if hubRiver ~= nil then
			break;
		end
	end
	if hubRiver ~= nil then
		MarkUsed(used, hubRiver);
		made[#made + 1] = hubRiver;
	else
		missed[#missed + 1] = "hub";
	end

	g_Rivers = made;
	local lengths = {};
	for i, river in ipairs(made) do
		lengths[i] = tostring(#river - 1);
	end
	print(LOG .. "_RIVERS count=" .. #made .. " arm=" .. g_ArmRivers .. " edges=" .. table.concat(lengths, ",")
		.. ((#missed > 0) and (" missed=" .. table.concat(missed, ",")) or ""));
	if not mainMade then
		print(LOG .. "_RIVER_MISSED main river (the start has no river)");
	end
end

------------------------------------------------------------------------------
-- Woods, rainforest, marsh and floodplains.
------------------------------------------------------------------------------
local function AddFeatures()
	for _, k in ipairs(g_Order) do
		if g_Land[k] and g_Reserved[k] == nil and not IsMountainKey(k) then
			local mix = FEATURE_MIX[g_Zone[k]] or { 0, 0, 0 };
			local roll = Rand(100, "Snowflake features");
			local base, relief = BaseOf(k), ReliefOf(k);
			if roll < mix[1] then
				if base ~= "D" then
					g_Feature[k] = FEATURE.FOREST;
				end
			elseif roll < mix[1] + mix[2] then
				if base == "G" or base == "P" then
					g_Feature[k] = FEATURE.JUNGLE;
				end
			elseif roll < mix[1] + mix[2] + mix[3] then
				if base == "G" and relief == 0 then
					g_Feature[k] = FEATURE.MARSH;
				end
			end
		end
	end
	g_Feature[(CKey(START_Q, START_R))] = nil;
	-- At most two wooded or rainforest hexes beside the start.
	local cover = 0;
	for d = 1, 6 do
		local nk = CKey(START_Q + DIRS[d][1], START_R + DIRS[d][2]);
		if g_Feature[nk] ~= nil then
			cover = cover + 1;
			if cover > 2 then
				g_Feature[nk] = nil;
			end
		end
	end
end

-- Canonical keys of the hexes along a river, in order, without repeats.
local function RiverHexKeys(river)
	local keys, seen = {}, {};
	for i = 1, #river - 1 do
		local a, b = EdgeHexes(river[i][1], river[i][2], river[i + 1][1], river[i + 1][2]);
		for _, h in ipairs({ a, b }) do
			if h ~= nil and InRadius(h[1], h[2]) then
				local k = KeyOf(h[1], h[2]);
				if not seen[k] then
					seen[k] = true;
					keys[#keys + 1] = k;
				end
			end
		end
	end
	return keys;
end

local MAX_DESERT_FLOODPLAINS = { DESERT = 5, DRYLAND = 3 };   -- per arm, the gate and the corner
local MAX_OTHER_FLOODPLAINS = 3;

local function AddFloodplains()
	local desert, other = { DESERT = 0, DRYLAND = 0 }, 0;
	for i = 1, g_ArmRivers do
		for _, k in ipairs(RiverHexKeys(g_Rivers[i])) do
			-- A desert river runs in a flat valley: its desert hills become flat.
			local dz = g_Zone[k];
			if g_Land[k] and g_Reserved[k] == nil and (dz == "DESERT" or dz == "DRYLAND") and BaseOf(k) == "D"
				and ReliefOf(k) == 1 and desert[dz] < MAX_DESERT_FLOODPLAINS[dz] then
				SetTerrainKey(k, "D", 0);
			end
			if g_Land[k] and g_Reserved[k] == nil and g_Feature[k] == nil and ReliefOf(k) == 0 then
				local zone, base = g_Zone[k], BaseOf(k);
				if (zone == "DESERT" or zone == "DRYLAND") and base == "D" then
					if desert[zone] < MAX_DESERT_FLOODPLAINS[zone] then
						g_Feature[k] = FEATURE.FLOODPLAINS;
						desert[zone] = desert[zone] + 1;
					end
				elseif zone ~= "DESERT" and zone ~= "DRYLAND" and zone ~= "HUB" and (base == "G" or base == "P")
					and other < MAX_OTHER_FLOODPLAINS and Chance(35, "Snowflake floodplains") then
					g_Feature[k] = (base == "G") and FEATURE.FLOODPLAINS_GRASSLAND or FEATURE.FLOODPLAINS_PLAINS;
					other = other + 1;
				end
			end
		end
	end
	g_Stats.floodplains = desert.DESERT .. "+" .. desert.DRYLAND .. "+" .. other;
end

------------------------------------------------------------------------------
-- Luxury and resource slots.
------------------------------------------------------------------------------
local function DistToStart(k)
	local q, r = KeyQR(k);
	return Dist(q, r, START_Q, START_R);
end

local function NextToSlot(q, r)
	for d = 1, 6 do
		local nq, nr = q + DIRS[d][1], r + DIRS[d][2];
		if InRadius(nq, nr) then
			local why = g_Reserved[(KeyOf(nq, nr))];
			if why == "LUX" or why == "RESOURCE" or why == "STRATEGIC" or why == "GOODY" then
				return true;
			end
		end
	end
	return false;
end

-- Picks one canonical land key among `zones` within [dmin, dmax] of the
-- start (nil = any), free and not beside another slot. When nothing fits,
-- it allows a neighbouring slot, then two more rings.
local RELAX = { { adjacent = false, widen = 0 }, { adjacent = true, widen = 0 }, { adjacent = true, widen = 2 } };

local function PickLand(zones, dmin, dmax, tag, extra)
	for _, relax in ipairs(RELAX) do
		local options = {};
		local hi = dmax and (dmax + relax.widen) or nil;
		for _, k in ipairs(g_Order) do
			if g_Land[k] and zones[g_Zone[k]] and g_Reserved[k] == nil and not IsMountainKey(k) then
				local q, r = KeyQR(k);
				local d = DistToStart(k);
				if (dmin == nil or d >= dmin) and (hi == nil or d <= hi)
					and (relax.adjacent or not NextToSlot(q, r))
					and (extra == nil or extra(k, q, r)) then
					options[#options + 1] = k;
				end
			end
		end
		if #options > 0 then
			return options[Rand(#options, tag) + 1];
		end
	end
	return nil;
end

-- Picks one canonical coast key next to land of `zones`, relaxing as PickLand.
local function PickWater(zones, dmin, dmax, tag, extra)
	for _, relax in ipairs(RELAX) do
		local options = {};
		local hi = dmax and (dmax + relax.widen) or nil;
		for _, k in ipairs(g_Order) do
			local q, r = KeyQR(k);
			if not g_Land[k] and g_Zone[k] ~= "LAKE" and g_Reserved[k] == nil and HexDist(q, r) <= RADIUS - 1 then
				local touches = false;
				for d = 1, 6 do
					local nq, nr = q + DIRS[d][1], r + DIRS[d][2];
					if IsLand(nq, nr) and zones[ZoneAt(nq, nr)] then
						touches = true;
					end
				end
				local dist = DistToStart(k);
				if touches and (dmin == nil or dist >= dmin) and (hi == nil or dist <= hi)
					and (relax.adjacent or not NextToSlot(q, r)) and (extra == nil or extra(k, q, r)) then
					options[#options + 1] = k;
				end
			end
		end
		if #options > 0 then
			return options[Rand(#options, tag) + 1];
		end
	end
	return nil;
end

-- Shapes the slot's plot so its resource can stand there, keeping the
-- region's character where the resource allows it.
local function GP(k)
	local base = BaseOf(k);
	return (base == "G" or base == "P") and base or "P";
end

local SHAPES = {
	OPEN          = function(k) SetTerrainKey(k, GP(k), 0); g_Feature[k] = nil; end,
	GRASS         = function(k) SetTerrainKey(k, "G", 0); g_Feature[k] = nil; end,
	PLAINS        = function(k) SetTerrainKey(k, "P", 0); g_Feature[k] = nil; end,
	GRASS_HILLS   = function(k) SetTerrainKey(k, "G", 1); g_Feature[k] = nil; end,
	HILLS         = function(k) SetTerrainKey(k, BaseOf(k), 1); g_Feature[k] = nil; end,
	GP_HILLS      = function(k) SetTerrainKey(k, GP(k), 1); g_Feature[k] = nil; end,
	FOREST        = function(k) SetTerrainKey(k, GP(k), 0); g_Feature[k] = FEATURE.FOREST; end,
	JUNGLE        = function(k) SetTerrainKey(k, GP(k), 0); g_Feature[k] = FEATURE.JUNGLE; end,
	MARSH         = function(k) SetTerrainKey(k, "G", 0); g_Feature[k] = FEATURE.MARSH; end,
	DESERT_FLAT   = function(k) SetTerrainKey(k, "D", 0); g_Feature[k] = nil; end,
	DESERT_HILLS  = function(k) SetTerrainKey(k, "D", 1); g_Feature[k] = nil; end,
	TUNDRA_FLAT   = function(k) SetTerrainKey(k, "T", 0); g_Feature[k] = nil; end,
	TUNDRA_FOREST = function(k) SetTerrainKey(k, "T", 0); g_Feature[k] = FEATURE.FOREST; end,
	KEEP          = function(k) end,
	WATER         = function(k) end,
};

local function Exists(resourceName)
	return GameInfo.Resources[resourceName] ~= nil;
end

local function PutResource(k, name, shape, why)
	if k == nil or not Exists(name) then
		g_Stats.missedSlots = (g_Stats.missedSlots or 0) + 1;
		print(LOG .. "_SLOT_MISSED resource=" .. name);
		return false;
	end
	SHAPES[shape](k);
	g_Res[k] = name;
	g_Reserved[k] = why or "RESOURCE";
	return true;
end

local function PutLux(k, group, slot, shape, m)
	if k == nil then
		g_Stats.missedSlots = (g_Stats.missedSlots or 0) + 1;
		print(LOG .. "_SLOT_MISSED luxury=" .. group .. slot);
		return false;
	end
	SHAPES[shape](k);
	g_Lux[k] = { group = group, slot = slot, m = m or 0 };
	g_Reserved[k] = "LUX";
	return true;
end

local ARM_ZONES = Set("DESERT", "WOODS", "MIDDLE", "JUNGLE", "START", "TUNDRA", "DRYLAND");
local HUB = Set("HUB");

-- A free hex of `zone`, else of any arm region; never beside the start
-- (its guaranteed hill and food stay) and never on a floodplain.
local function PickIn(zone, tag, extra)
	local function Fits(k, q, r)
		return DistToStart(k) >= 2 and g_Feature[k] ~= FEATURE.FLOODPLAINS
			and g_Feature[k] ~= FEATURE.FLOODPLAINS_GRASSLAND and g_Feature[k] ~= FEATURE.FLOODPLAINS_PLAINS
			and (extra == nil or extra(k, q, r));
	end
	return PickLand(Set(zone), nil, nil, tag, Fits) or PickLand(ARM_ZONES, nil, nil, tag, Fits);
end

-- Three of every strategic resource per arm, each where its region suits it.
local STRATEGIC_SPOTS = {
	{ "RESOURCE_HORSES",   { {"START", "OPEN"}, {"MIDDLE", "OPEN"}, {"WOODS", "OPEN"} } },
	{ "RESOURCE_IRON",     { {"DRYLAND", "DESERT_HILLS"}, {"MIDDLE", "HILLS"}, {"START", "HILLS"} } },
	{ "RESOURCE_NITER",    { {"DESERT", "DESERT_FLAT"}, {"TUNDRA", "TUNDRA_FLAT"}, {"MIDDLE", "OPEN"} } },
	{ "RESOURCE_COAL",     { {"WOODS", "FOREST"}, {"MIDDLE", "GP_HILLS"}, {"WOODS", "GP_HILLS"} } },
	{ "RESOURCE_OIL",      { {"DESERT", "DESERT_FLAT"}, {"TUNDRA", "TUNDRA_FLAT"}, {"JUNGLE", "MARSH"} } },
	{ "RESOURCE_ALUMINUM", { {"DRYLAND", "DESERT_HILLS"}, {"JUNGLE", "JUNGLE"}, {"MIDDLE", "PLAINS"} } },
	{ "RESOURCE_URANIUM",  { {"TUNDRA", "TUNDRA_FOREST"}, {"WOODS", "FOREST"}, {"DRYLAND", "DESERT_FLAT"} } },
};

local BONUS_SPOTS = {
	{ "RESOURCE_WHEAT", "DESERT", "FLOODPLAIN" }, { "RESOURCE_SHEEP", "DESERT", "DESERT_HILLS" },
	{ "RESOURCE_DEER", "TUNDRA", "TUNDRA_FLAT" }, { "RESOURCE_DEER", "WOODS", "FOREST" },
	{ "RESOURCE_BANANAS", "JUNGLE", "JUNGLE" }, { "RESOURCE_BANANAS", "JUNGLE", "JUNGLE" },
	{ "RESOURCE_COPPER", "MIDDLE", "HILLS" }, { "RESOURCE_STONE", "MIDDLE", "GRASS" },
	{ "RESOURCE_SHEEP", "DRYLAND", "DESERT_HILLS" }, { "RESOURCE_COPPER", "START", "HILLS" },
	{ "RESOURCE_CATTLE", "START", "GRASS" }, { "RESOURCE_CATTLE", "MIDDLE", "GRASS" },
	{ "RESOURCE_RICE", "JUNGLE", "MARSH" },
};

local function PlaceArmSlots()
	local ARMS = ARM_ZONES;
	-- Luxuries: slot 1 open grassland (one beside the start, one mid-arm),
	-- slot 2 in the woods, slot 3 in the rainforest.
	-- Picks around the start stay out of the tundra and desert corners.
	local NEAR_START = Set("START", "MIDDLE");
	PutLux(PickLand(NEAR_START, 2, 3, "Snowflake lux"), "ARM", 1, "GRASS");
	PutLux(PickIn("MIDDLE", "Snowflake lux"), "ARM", 1, "GRASS");
	PutLux(PickIn("WOODS", "Snowflake lux"), "ARM", 2, "FOREST");
	PutLux(PickIn("WOODS", "Snowflake lux"), "ARM", 2, "FOREST");
	PutLux(PickIn("JUNGLE", "Snowflake lux"), "ARM", 3, "JUNGLE");
	PutLux(PickIn("JUNGLE", "Snowflake lux"), "ARM", 3, "JUNGLE");

	-- Food and production around the start.
	local food1 = (Rand(2, "Snowflake food") == 0) and "RESOURCE_WHEAT" or "RESOURCE_CATTLE";
	PutResource(PickLand(ARMS, 1, 1, "Snowflake food", function(k)
		return ReliefOf(k) == 0;
	end), food1, (food1 == "RESOURCE_WHEAT") and "PLAINS" or "GRASS");
	local food2 = (food1 == "RESOURCE_WHEAT") and "RESOURCE_CATTLE" or "RESOURCE_WHEAT";
	PutResource(PickLand(NEAR_START, 2, 2, "Snowflake food"), food2, (food2 == "RESOURCE_WHEAT") and "PLAINS" or "GRASS");
	local prod = (Rand(2, "Snowflake production") == 0) and "RESOURCE_STONE" or "RESOURCE_SHEEP";
	PutResource(PickLand(NEAR_START, 2, 2, "Snowflake production"), prod, (prod == "RESOURCE_STONE") and "GRASS" or "HILLS");

	-- Strategics.
	for _, entry in ipairs(STRATEGIC_SPOTS) do
		for _, spot in ipairs(entry[2]) do
			PutResource(PickIn(spot[1], "Snowflake strategic"), entry[1], spot[2], "STRATEGIC");
		end
	end

	-- Bonuses by region (wheat on a desert floodplain when there is one).
	for _, spot in ipairs(BONUS_SPOTS) do
		local name, zone, shape = spot[1], spot[2], spot[3];
		if Exists(name) then
			local k;
			if shape == "FLOODPLAIN" then
				k = PickLand(Set(zone), nil, nil, "Snowflake bonus", function(kk)
					return g_Feature[kk] == FEATURE.FLOODPLAINS;
				end);
				shape = "KEEP";
				if k == nil then
					k = PickIn(zone, "Snowflake bonus");
					shape = "PLAINS";
				end
			else
				k = PickIn(zone, "Snowflake bonus");
			end
			PutResource(k, name, shape);
		end
	end

	-- Sea: two fish within reach of the start, fish off each region, crabs.
	PutResource(PickWater(ARMS, 1, 4, "Snowflake fish"), "RESOURCE_FISH", "WATER");
	PutResource(PickWater(ARMS, 1, 4, "Snowflake fish"), "RESOURCE_FISH", "WATER");
	for _, zone in ipairs({ "DESERT", "WOODS", "JUNGLE", "TUNDRA", "DRYLAND" }) do
		PutResource(PickWater(Set(zone), nil, nil, "Snowflake fish") or PickWater(ARMS, nil, nil, "Snowflake fish"),
			"RESOURCE_FISH", "WATER");
	end
	-- Four offshore oil fields per arm.
	for _, zone in ipairs({ "DESERT", "WOODS", "JUNGLE", "TUNDRA" }) do
		PutResource(PickWater(Set(zone), nil, nil, "Snowflake offshore oil") or PickWater(ARMS, nil, nil, "Snowflake offshore oil"),
			"RESOURCE_OIL", "WATER", "STRATEGIC");
	end
	PutResource(PickWater(Set("WOODS", "MIDDLE"), nil, nil, "Snowflake crabs"), "RESOURCE_CRABS", "WATER");
	PutResource(PickWater(Set("JUNGLE", "MIDDLE"), nil, nil, "Snowflake crabs"), "RESOURCE_CRABS", "WATER");

	-- Goody huts: one mid-arm, one in the desert.
	for _, zone in ipairs({ "MIDDLE", "DESERT" }) do
		local hut = PickIn(zone, "Snowflake goody");
		if hut ~= nil then
			g_Goody[hut] = true;
			g_Reserved[hut] = "GOODY";
			if g_Feature[hut] == FEATURE.FOREST or g_Feature[hut] == FEATURE.JUNGLE then
				g_Feature[hut] = nil;
			end
		end
	end
end

local HUB_SLOT_SHAPES = { "PLAINS", "GRASS", "FOREST", "JUNGLE" };
local HUB_STRATEGIC_SHAPE = {
	RESOURCE_HORSES = "OPEN", RESOURCE_IRON = "HILLS", RESOURCE_NITER = "OPEN", RESOURCE_COAL = "GP_HILLS",
	RESOURCE_OIL = "MARSH", RESOURCE_ALUMINUM = "PLAINS", RESOURCE_URANIUM = "OPEN",
};

local function PlaceHubSlots()
	local shapes = Shuffle({ 1, 2, 3, 4 }, "Snowflake hub shapes");
	PutLux(CKey(HUB_LUX[1][1], HUB_LUX[1][2]), "HUB", 1, HUB_SLOT_SHAPES[shapes[1]]);
	PutLux(CKey(HUB_LUX[2][1], HUB_LUX[2][2]), "HUB", 2, HUB_SLOT_SHAPES[shapes[2]]);
	local function HubFree(k, q, r)
		return HexDist(q, r) >= 2;
	end
	-- Three strategic types, drawn each game, in every sixth of the hub.
	local types = {};
	for _, entry in ipairs(STRATEGIC_SPOTS) do
		types[#types + 1] = entry[1];
	end
	Shuffle(types, "Snowflake hub strategics");
	local picked = {};
	for i = 1, 3 do
		PutResource(PickLand(HUB, nil, nil, "Snowflake hub strategic", HubFree), types[i],
			HUB_STRATEGIC_SHAPE[types[i]], "STRATEGIC");
		picked[#picked + 1] = string.gsub(types[i], "RESOURCE_", "");
	end
	g_Stats.hubStrategics = table.concat(picked, ",");
	local bonuses = { "RESOURCE_WHEAT", "RESOURCE_CATTLE", "RESOURCE_STONE", "RESOURCE_SHEEP" };
	local bonusShape = { RESOURCE_WHEAT = "PLAINS", RESOURCE_CATTLE = "GRASS", RESOURCE_STONE = "GRASS", RESOURCE_SHEEP = "HILLS" };
	-- Two different bonuses per sixth.
	Shuffle(bonuses, "Snowflake hub bonus");
	for i = 1, 2 do
		local name = bonuses[i];
		PutResource(PickLand(HUB, nil, nil, "Snowflake hub bonus", function(k, q, r)
			return HexDist(q, r) >= 3 and not NearWonderSite(q, r);
		end), name, bonusShape[name]);
	end
	PutResource(PickWater(HUB, nil, nil, "Snowflake hub fish", function(k, q, r)
		return HexDist(q, r) > 1;
	end), "RESOURCE_FISH", "WATER");
end

local function PlaceIslandSlots()
	if #g_CSSlots == 0 then
		return;
	end
	local inner = g_CSSlots[1];
	local outer = g_CSSlots[2] or g_CSSlots[1];

	-- World hexes of island 0 near a city-state, canonical key and m;
	-- relaxed like PickLand when nothing fits.
	local function Near(slot, wantLand, dmin, dmax, tag)
		for _, relax in ipairs(RELAX) do
			local options = {};
			local hi = dmax + relax.widen;
			for r = slot[2] - hi, slot[2] + hi do
				for q = slot[1] - hi, slot[1] + hi do
					local d = Dist(q, r, slot[1], slot[2]);
					if d >= dmin and d <= hi and HexDist(q, r) <= RADIUS - 1 then
						local k, m = CKey(q, r);
						local ok = g_Reserved[k] == nil and (relax.adjacent or not NextToSlot(q, r));
						if wantLand then
							ok = ok and g_Land[k] and g_Zone[k] == "ISLAND" and not IsMountainKey(k);
						else
							ok = ok and not g_Land[k] and g_Zone[k] ~= "LAKE" and CountLandNeighbours(q, r) > 0;
							if ok then
								-- Only water touching this island, not the mainland.
								for dd = 1, 6 do
									local nq, nr = q + DIRS[dd][1], r + DIRS[dd][2];
									if IsLand(nq, nr) and ZoneAt(nq, nr) ~= "ISLAND" then
										ok = false;
									end
								end
							end
						end
						if ok then
							options[#options + 1] = { k, m };
						end
					end
				end
			end
			if #options > 0 then
				local pick = options[Rand(#options, tag) + 1];
				return pick[1], pick[2];
			end
		end
		return nil, 0;
	end

	local k, m = Near(inner, true, 1, 2, "Snowflake island lux");
	PutLux(k, "ISLAND", 1, "PLAINS", m);
	k, m = Near(outer, false, 1, 2, "Snowflake island lux");
	PutLux(k, "ISLAND", 2, "WATER", m);
	PutResource((Near(inner, false, 1, 2, "Snowflake island fish")), "RESOURCE_FISH", "WATER");
	PutResource((Near(outer, false, 1, 3, "Snowflake island fish")), "RESOURCE_FISH", "WATER");
	PutResource((Near(inner, false, 2, 4, "Snowflake island fish")), "RESOURCE_CRABS", "WATER");
	local bonus1 = (Rand(2, "Snowflake island bonus") == 0) and "RESOURCE_WHEAT" or "RESOURCE_CATTLE";
	PutResource((Near(outer, true, 1, 2, "Snowflake island bonus")), bonus1,
		(bonus1 == "RESOURCE_WHEAT") and "PLAINS" or "GRASS");
	PutResource((Near(inner, true, 1, 3, "Snowflake island bonus")), "RESOURCE_SHEEP", "HILLS");

	-- Two coal per island, in its woods.
	PutResource((Near(inner, true, 1, 3, "Snowflake island coal")), "RESOURCE_COAL", "FOREST", "STRATEGIC");
	PutResource((Near(outer, true, 1, 3, "Snowflake island coal")), "RESOURCE_COAL", "FOREST", "STRATEGIC");
	-- Two deposits of the island's strategic, which alternates by island
	-- (sets A, B, C: oil, uranium, aluminium); flat desert suits all three,
	-- so the islands' land stays the same.
	for i = 1, 2 do
		local slot = (i == 1) and inner or outer;
		local k2, m2 = Near(slot, true, 1, 3, "Snowflake island strategic");
		if k2 ~= nil then
			SHAPES.DESERT_FLAT(k2);
			g_IslandStrat[k2] = { m = m2 };
			g_Reserved[k2] = "STRATEGIC";
		else
			g_Stats.missedSlots = (g_Stats.missedSlots or 0) + 1;
			print(LOG .. "_SLOT_MISSED island_strategic");
		end
	end
end

------------------------------------------------------------------------------
-- Writing the model to the map.
------------------------------------------------------------------------------
local g_CoastDist = nil;

local function WaterTerrain(q, r)
	if g_Zone[(KeyOf(q, r))] == "LAKE" then
		return TERRAIN.COAST;
	end
	local d = g_CoastDist[Key(q, r)];
	if d ~= nil and d <= 2 then
		return TERRAIN.COAST;
	end
	return TERRAIN.OCEAN;
end

local function WriteTerrain()
	g_CoastDist = LandDistance(false);
	for y = 0, GRID - 1 do
		for x = 0, GRID - 1 do
			local plot = Map.GetPlot(x, y);
			local q, r = ToAxial(x, y);
			if InRadius(q, r) then
				local k = KeyOf(q, r);
				if g_Land[k] then
					TerrainBuilder.SetTerrainType(plot, g_Terrain[k]);
				else
					TerrainBuilder.SetTerrainType(plot, WaterTerrain(q, r));
				end
			else
				TerrainBuilder.SetTerrainType(plot, TERRAIN.OCEAN);
			end
		end
	end
	for y = 0, GRID - 1 do
		for x = 0, GRID - 1 do
			local q, r = ToAxial(x, y);
			if InRadius(q, r) then
				local k = KeyOf(q, r);
				if g_Land[k] and g_Feature[k] ~= nil and g_Feature[k] >= 0 then
					TerrainBuilder.SetFeatureType(Map.GetPlot(x, y), g_Feature[k]);
				end
			end
		end
	end
end

-- Flow index by corner step: NE, N, NW, SW, S, SE.
local FLOW_STEPS = { {1, 1}, {0, 2}, {-1, 1}, {-1, -1}, {0, -2}, {1, -1} };
local FLOW_NAMES = { "FLOWDIRECTION_NORTHEAST", "FLOWDIRECTION_NORTH", "FLOWDIRECTION_NORTHWEST",
	"FLOWDIRECTION_SOUTHWEST", "FLOWDIRECTION_SOUTH", "FLOWDIRECTION_SOUTHEAST" };

local function FlowOf(dX, dY)
	for i = 1, 6 do
		if FLOW_STEPS[i][1] == dX and FLOW_STEPS[i][2] == dY then
			return FlowDirectionTypes[FLOW_NAMES[i]];
		end
	end
	return nil;
end

-- Sets the river on the edge between hexes a and b. A plot owns its east
-- (WOfRiver), south-east (NWOfRiver) and south-west (NEOfRiver) edges.
local function SetRiverEdge(a, b, flow, riverID)
	local dq, dr = b[1] - a[1], b[2] - a[2];
	local owner, edge;
	if dq == 1 and dr == 0 then owner, edge = a, "E";
	elseif dq == 1 and dr == -1 then owner, edge = a, "SE";
	elseif dq == 0 and dr == -1 then owner, edge = a, "SW";
	elseif dq == -1 and dr == 0 then owner, edge = b, "E";
	elseif dq == -1 and dr == 1 then owner, edge = b, "SE";
	elseif dq == 0 and dr == 1 then owner, edge = b, "SW";
	else
		return false;
	end
	local plot = PlotAt(owner[1], owner[2]);
	if plot == nil then
		return false;
	end
	if edge == "E" then
		TerrainBuilder.SetWOfRiver(plot, true, flow, riverID);
	elseif edge == "SE" then
		TerrainBuilder.SetNWOfRiver(plot, true, flow, riverID);
	else
		TerrainBuilder.SetNEOfRiver(plot, true, flow, riverID);
	end
	return true;
end

local function WriteRivers()
	local riverID = 0;
	local edges = 0;
	for _, river in ipairs(g_Rivers) do
		for rot = 0, NUM_ARMS - 1 do
			local pts = {};
			for i, v in ipairs(river) do
				local X, Y = v[1], v[2];
				for _ = 1, rot do
					X, Y = RotV(X, Y);
				end
				pts[i] = { X, Y };
			end
			for i = 1, #pts - 1 do
				local a, b = EdgeHexes(pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2]);
				local flow = FlowOf(pts[i + 1][1] - pts[i][1], pts[i + 1][2] - pts[i][2]);
				if a ~= nil and b ~= nil and flow ~= nil and SetRiverEdge(a, b, flow, riverID) then
					edges = edges + 1;
				end
			end
			riverID = riverID + 1;
		end
	end
	g_Stats.riverEdges = edges;
end

------------------------------------------------------------------------------
-- Natural wonders at evenly spaced hub sites (multi-tile ones with three).
------------------------------------------------------------------------------
local function ResetToFlat(plot)
	local t = plot:GetTerrainType();
	if t == TERRAIN.SNOW_HILLS or t == TERRAIN.SNOW_MOUNTAIN then
		TerrainBuilder.SetTerrainType(plot, TERRAIN.SNOW);
	elseif t == TERRAIN.DESERT_HILLS or t == TERRAIN.DESERT_MOUNTAIN then
		TerrainBuilder.SetTerrainType(plot, TERRAIN.DESERT);
	elseif t == TERRAIN.PLAINS_HILLS or t == TERRAIN.PLAINS_MOUNTAIN then
		TerrainBuilder.SetTerrainType(plot, TERRAIN.PLAINS);
	elseif t == TERRAIN.GRASS_HILLS or t == TERRAIN.GRASS_MOUNTAIN then
		TerrainBuilder.SetTerrainType(plot, TERRAIN.GRASS);
	elseif t == TERRAIN.TUNDRA_HILLS or t == TERRAIN.TUNDRA_MOUNTAIN then
		TerrainBuilder.SetTerrainType(plot, TERRAIN.TUNDRA);
	end
end

-- Natural wonders the map may use: not excluded in the advanced setup, not
-- volcanic (Gathering Storm volcanoes would erupt beside one arm only).
-- Single-tile land wonders carry the terrains they accept (a site takes
-- one of them); multi-tile ones are placed as the stock generator does, the
-- custom-placement ones only when its helpers are loaded.
local function WonderCandidates(withMulti)
	local excluded = {};
	local config = GameConfiguration.GetValue("EXCLUDE_NATURAL_WONDERS");
	if config ~= nil and type(config) == "table" then
		for _, v in ipairs(config) do
			excluded[v] = true;
		end
	end
	if GameInfo.Features_XP2 ~= nil then
		for row in GameInfo.Features_XP2() do
			if row.Volcano then
				excluded[row.FeatureType] = true;
			end
		end
	end
	local list = {};
	for row in GameInfo.Features() do
		if row.NaturalWonder and excluded[row.FeatureType] ~= true then
			local custom = row.CustomPlacement ~= nil;
			local multi = custom or (row.Tiles ~= nil and row.Tiles > 1);
			if multi then
				if withMulti and (not custom or CustomCanHaveFeature ~= nil) then
					list[#list + 1] = { index = row.Index, type = row.FeatureType, multi = true, custom = custom };
				end
			else
				local terrains = {};
				for vt in GameInfo.Feature_ValidTerrains() do
					if vt.FeatureType == row.FeatureType then
						local t = RowIndex("Terrains", vt.TerrainType);
						if t >= 0 and t ~= TERRAIN.COAST and t ~= TERRAIN.OCEAN then
							terrains[#terrains + 1] = t;
						end
					end
				end
				if #terrains > 0 then
					list[#list + 1] = { index = row.Index, type = row.FeatureType, terrains = terrains };
				end
			end
		end
	end
	return list;
end

-- A tile a wonder may cover: hub land or water (never an arm, so no gate is
-- blocked) and no planned slot (luxury, resource, goody), so the symmetric
-- resources still all fit. The even sites themselves are allowed.
local function WonderTileFree(plot)
	local q, r = ToAxial(plot:GetX(), plot:GetY());
	if not InRadius(q, r) then
		return true;
	end
	local k = KeyOf(q, r);
	if g_Land[k] and g_Zone[k] ~= "HUB" then
		return false;
	end
	return (g_Reserved[k] == nil or g_Reserved[k] == "WONDER") and g_Res[k] == nil and g_Lux[k] == nil
		and not g_Goody[k];
end

-- The plots within three tiles of `plot` (a wonder's whole reach) and their
-- terrain and feature, so a placement can be undone.
local function WonderArea(plot)
	local area = { plots = {}, saved = {} };
	local q, r = ToAxial(plot:GetX(), plot:GetY());
	for dr = -3, 3 do
		for dq = -3, 3 do
			if HexDist(dq, dr) <= 3 then
				local other = PlotAt(q + dq, r + dr);
				if other ~= nil then
					area.plots[#area.plots + 1] = other;
					area.saved[#area.saved + 1] = { other:GetTerrainType(), other:GetFeatureType() };
				end
			end
		end
	end
	return area;
end

-- Restores the area: removes the wonder, puts back terrain and features,
-- and clears cliffs (this script makes none; the stock custom placement
-- adds them toward water).
local function RestoreWonderArea(area, index)
	for i, o in ipairs(area.plots) do
		if o:GetFeatureType() == index then
			TerrainBuilder.SetFeatureType(o, -1);
		end
		if o:GetTerrainType() ~= area.saved[i][1] then
			TerrainBuilder.SetTerrainType(o, area.saved[i][1]);
		end
		if o:GetFeatureType() ~= area.saved[i][2] then
			TerrainBuilder.SetFeatureType(o, area.saved[i][2]);
		end
		if TerrainBuilder.SetWOfCliff ~= nil then
			TerrainBuilder.SetWOfCliff(o, false);
			TerrainBuilder.SetNWOfCliff(o, false);
			TerrainBuilder.SetNEOfCliff(o, false);
		end
	end
end

-- A single-tile wonder at plot, giving the plot a terrain it accepts if
-- needed. Restores the terrain on failure.
local function TryWonderAt(plot, wonder)
	local saved = plot:GetTerrainType();
	local function Place()
		TerrainBuilder.SetFeatureType(plot, wonder.index);
		ResetToFlat(plot);
		return true;
	end
	if TerrainBuilder.CanHaveFeature(plot, wonder.index, false) then
		return Place();
	end
	for _, t in ipairs(wonder.terrains or {}) do
		TerrainBuilder.SetTerrainType(plot, t);
		if TerrainBuilder.CanHaveFeature(plot, wonder.index, false) then
			return Place();
		end
	end
	TerrainBuilder.SetTerrainType(plot, saved);
	return false;
end

-- A multi-tile wonder anchored at plot, as the stock generator places it,
-- only if every tile it covers is free (WonderTileFree). A custom
-- placement's tiles are known first; the engine spreads the others itself,
-- so those are checked after placing and undone from `area`.
local function TryMultiWonderAt(plot, wonder, area)
	if wonder.custom then
		local aPlots = {};
		if not CustomGetMultiTileFeaturePlotList(plot, wonder.index, aPlots) then
			return false;
		end
		for _, i in ipairs(aPlots) do
			if not WonderTileFree(Map.GetPlotByIndex(i)) then
				return false;
			end
		end
		-- The stock generator's final check before a custom placement.
		if not TerrainBuilder.CanHaveFeature(plot, wonder.index) then
			return false;
		end
		CustomSetFeatureType(plot, wonder.index);
		return true;
	end
	if not TerrainBuilder.CanHaveFeature(plot, wonder.index, false) then
		return false;
	end
	TerrainBuilder.SetFeatureType(plot, wonder.index);
	for _, o in ipairs(area.plots) do
		if o:GetFeatureType() == wonder.index and not WonderTileFree(o) then
			RestoreWonderArea(area, wonder.index);
			return false;
		end
	end
	-- Every tile it covers is flattened, as the stock generator does.
	for _, o in ipairs(area.plots) do
		if o:GetFeatureType() == wonder.index then
			ResetToFlat(o);
		end
	end
	return true;
end

local function TryAnyWonderAt(plot, wonder, area)
	if wonder.multi then
		return TryMultiWonderAt(plot, wonder, area);
	end
	return TryWonderAt(plot, wonder);
end

-- The even placement: a wonder at each site (all six, or alternate ones),
-- each site drawing its own. With three, multi-tile wonders may be drawn too,
-- anchored on the site (every arm has the same distance to the anchor; the
-- shape is uneven, as these wonders are by design). With six, single-tile
-- only: neighbouring sites are exactly MinDistanceNW apart, so a wonder
-- spreading toward the next site would void it.
local function PlaceWonders(count)
	if count <= 0 then
		print(LOG .. "_WONDERS count=0");
		return {};
	end
	local step = (count >= 6) and 1 or 2;
	local candidates = Shuffle(WonderCandidates(count < 6), "Snowflake wonders");
	local placed = {};
	local undo = {};
	local nextCandidate = 1;
	local complete = true;
	for rot = 0, NUM_ARMS - 1, step do
		local q, r = RotN(WONDER_SITE_Q, WONDER_SITE_R, rot);
		local plot = PlotAt(q, r);
		local area = WonderArea(plot);
		local done = false;
		while not done and nextCandidate <= #candidates do
			local wonder = candidates[nextCandidate];
			nextCandidate = nextCandidate + 1;
			if TryAnyWonderAt(plot, wonder, area) then
				placed[#placed + 1] = wonder.type .. "@" .. plot:GetX() .. "," .. plot:GetY();
				undo[#undo + 1] = { area, wonder.index };
				done = true;
			end
		end
		if not done then
			-- Why the site refused every candidate, for the log.
			local riverNear = 0;
			for d = 0, 5 do
				local a = Map.GetAdjacentPlot(plot:GetX(), plot:GetY(), d);
				if a ~= nil and a:IsRiver() then
					riverNear = riverNear + 1;
				end
			end
			print(LOG .. "_WONDER_SITE_FAILED site=" .. plot:GetX() .. "," .. plot:GetY() .. " candidates=" .. #candidates
				.. " river=" .. tostring(plot:IsRiver()) .. " river_neighbours=" .. riverNear
				.. " coastal=" .. tostring(plot:IsCoastalLand()) .. " feature=" .. plot:GetFeatureType()
				.. " resource=" .. plot:GetResourceType());
			complete = false;
			break;
		end
	end
	-- All sites or none, so every arm has the same distances.
	if not complete then
		for _, entry in ipairs(undo) do
			RestoreWonderArea(entry[1], entry[2]);
		end
		print(LOG .. "_WONDERS count=" .. count .. " placed=0 reason=incomplete tried=" .. table.concat(placed, " "));
		g_Stats.wonders = 0;
		return {};
	end
	g_Stats.wonders = #placed;
	print(LOG .. "_WONDERS count=" .. count .. " placed=" .. table.concat(placed, " "));
	return placed;
end

-- Fallback when the even placement fails (uneven wonders in the hub are
-- acceptable, multi-tile and coastal ones included): up to `count` wonders
-- of any kind, each anchored within 9 hex widths of the centre on a free
-- tile and covering only free tiles (WonderTileFree). Wonders in a drawn
-- order, each at a drawn valid tile; the engine keeps them MinDistanceNW
-- apart.
local function PlaceHubWondersAnyhow(count)
	local wonders = Shuffle(WonderCandidates(true), "Snowflake hub wonders anyhow");
	local tiles = {};
	for i = 0, Map.GetPlotCount() - 1 do
		local plot = Map.GetPlotByIndex(i);
		local q, r = ToAxial(plot:GetX(), plot:GetY());
		if q * q + q * r + r * r <= 81 and HexDist(q, r) >= 2 and WonderTileFree(plot) then
			tiles[#tiles + 1] = plot;
		end
	end
	local placed = {};
	for _, wonder in ipairs(wonders) do
		if #placed >= count then
			break;
		end
		local valid = {};
		for _, plot in ipairs(tiles) do
			local ok;
			if wonder.custom then
				ok = CustomCanHaveFeature(plot, wonder.index);
			else
				ok = TerrainBuilder.CanHaveFeature(plot, wonder.index, false);
			end
			if ok then
				valid[#valid + 1] = plot;
			end
		end
		Shuffle(valid, "Snowflake hub wonder tile");
		for _, plot in ipairs(valid) do
			local placedHere;
			if wonder.multi then
				placedHere = TryMultiWonderAt(plot, wonder, WonderArea(plot));
			else
				TerrainBuilder.SetFeatureType(plot, wonder.index);
				ResetToFlat(plot);
				placedHere = true;
			end
			if placedHere then
				placed[#placed + 1] = wonder.type .. "@" .. plot:GetX() .. "," .. plot:GetY();
				break;
			end
		end
	end
	g_Stats.wonders = #placed;
	g_Stats.wondersUneven = true;
	print(LOG .. "_WONDERS uneven count=" .. count .. " placed=" .. #placed .. " " .. table.concat(placed, " "));
	return placed;
end

------------------------------------------------------------------------------
-- Coastal lowlands (Gathering Storm sea level rise): the stock scoring, but
-- ranked per rotation orbit with a total order so all six copies match.
------------------------------------------------------------------------------
local function LowlandScore(plot)
	if not plot:IsCoastalLand() or plot:IsHills() or plot:IsMountain() or plot:IsNaturalWonder() then
		return 0;
	end
	local feature = plot:GetFeatureType();
	local x, y = plot:GetX(), plot:GetY();
	local score = 500;
	for dir = 0, 5 do
		local adj = Map.GetAdjacentPlot(x, y, dir);
		if adj ~= nil then
			if adj:GetFeatureType() == FEATURE.VOLCANO and FEATURE.VOLCANO >= 0 then
				return 0;
			end
			if adj:IsLake() then
				return 0;
			end
		end
	end
	if feature == FEATURE.MARSH then
		return 1000;
	end
	if feature >= 0 and (feature == FEATURE.FLOODPLAINS or feature == FEATURE.FLOODPLAINS_GRASSLAND
		or feature == FEATURE.FLOODPLAINS_PLAINS) then
		return 0;
	end
	if plot:IsRiver() then
		score = score + 200;
	end
	for dir = 0, 5 do
		local adj = Map.GetAdjacentPlot(x, y, dir);
		if adj ~= nil then
			local f = adj:GetFeatureType();
			if f >= 0 and (f == FEATURE.MARSH or f == FEATURE.FLOODPLAINS
				or f == FEATURE.FLOODPLAINS_GRASSLAND or f == FEATURE.FLOODPLAINS_PLAINS) then
				score = score + 50;
			end
			if adj:IsHills() or adj:IsMountain() then
				score = score - 50;
			end
			if adj:IsWater() then
				if adj:IsNaturalWonder() then
					return 0;
				end
				score = score + 50;
			end
		end
	end
	return score;
end

local function MarkLowlands()
	if TerrainBuilder.AddCoastalLowland == nil then
		return;
	end
	local percent = 35;
	if GlobalParameters ~= nil and GlobalParameters.CLIMATE_CHANGE_PERCENT_COASTAL_LOWLANDS ~= nil then
		percent = GlobalParameters.CLIMATE_CHANGE_PERCENT_COASTAL_LOWLANDS;
	end
	local scored = {};
	for _, k in ipairs(g_Order) do
		if g_Land[k] then
			local q, r = KeyQR(k);
			local s = LowlandScore(PlotAt(q, r));
			if s > 0 then
				scored[#scored + 1] = { k = k, s = s };
			end
		end
	end
	table.sort(scored, function(a, b)
		if a.s ~= b.s then return a.s > b.s; end
		return a.k < b.k;
	end);
	local toMark = math.floor(#scored * percent / 100);
	local marked = 0;
	for i = 1, toMark do
		local elevation = 2;
		if i <= toMark / 3 then
			elevation = 0;
		elseif i <= (toMark * 2) / 3 then
			elevation = 1;
		end
		local q, r = KeyQR(scored[i].k);
		for rot = 0, NUM_ARMS - 1 do
			local tq, tr = RotN(q, r, rot);
			local plot = PlotAt(tq, tr);
			-- Never a natural wonder (a multi-tile or fallback wonder can sit
			-- off the scored orbit's pattern).
			if not plot:IsNaturalWonder() then
				TerrainBuilder.AddCoastalLowland(plot:GetIndex(), elevation);
				marked = marked + 1;
			end
		end
	end
	g_Stats.lowlands = marked;
end

------------------------------------------------------------------------------
-- Resources.
------------------------------------------------------------------------------
local SET_LETTERS = { "A", "B", "C", "D", "E", "F", "G", "H" };

-- Type-slot index (1-17) of a luxury hex copied with rotation rot.
-- 1-9: arm sets A, B, C with three slots each; 10-15: island sets D, E, F
-- with two slots each; 16 G, 17 H.
local function TypeSlot(lux, rot)
	if lux.group == "ARM" then
		local set = ((rot + lux.m) % NUM_ARMS) % 3;
		return set * 3 + lux.slot;
	elseif lux.group == "ISLAND" then
		local set = ((rot + lux.m) % NUM_ARMS) % 3;
		return 9 + set * 2 + lux.slot;
	end
	return 15 + lux.slot;
end

local function TypeSlotName(slot)
	if slot <= 9 then
		return SET_LETTERS[math.floor((slot - 1) / 3) + 1] .. tostring((slot - 1) % 3 + 1);
	elseif slot <= 15 then
		return SET_LETTERS[math.floor((slot - 10) / 2) + 4] .. tostring((slot - 10) % 2 + 1);
	end
	return SET_LETTERS[slot - 9];
end

local function PlaceFixedResources()
	local placed, failed = 0, 0;
	for _, k in ipairs(g_Order) do
		local name = g_Res[k];
		if name ~= nil then
			local index = RowIndex("Resources", name);
			local q, r = KeyQR(k);
			for rot = 0, NUM_ARMS - 1 do
				local tq, tr = RotN(q, r, rot);
				local plot = PlotAt(tq, tr);
				if index >= 0 and ResourceBuilder.CanHaveResource(plot, index) then
					ResourceBuilder.SetResourceType(plot, index, 1);
					placed = placed + 1;
				else
					failed = failed + 1;
					print(LOG .. "_RESOURCE_FAIL resource=" .. name .. " plot=" .. plot:GetX() .. "," .. plot:GetY());
				end
			end
		end
	end
	g_Stats.resources = placed;
	g_Stats.resourceFails = failed;
end

-- The island strategics: island (rot + m) mod 6 takes set (island mod 3).
local ISLAND_STRATEGICS = { "RESOURCE_OIL", "RESOURCE_URANIUM", "RESOURCE_ALUMINUM" };

local function PlaceIslandStrategics()
	local placed, failed = 0, 0;
	for _, k in ipairs(g_Order) do
		local entry = g_IslandStrat[k];
		if entry ~= nil then
			local q, r = KeyQR(k);
			for rot = 0, NUM_ARMS - 1 do
				local island = (rot + entry.m) % NUM_ARMS;
				local name = ISLAND_STRATEGICS[(island % 3) + 1];
				local index = RowIndex("Resources", name);
				local tq, tr = RotN(q, r, rot);
				local plot = PlotAt(tq, tr);
				if index >= 0 and ResourceBuilder.CanHaveResource(plot, index) then
					ResourceBuilder.SetResourceType(plot, index, 1);
					placed = placed + 1;
				else
					failed = failed + 1;
					print(LOG .. "_RESOURCE_FAIL resource=" .. name .. " plot=" .. plot:GetX() .. "," .. plot:GetY());
				end
			end
		end
	end
	g_Stats.resources = (g_Stats.resources or 0) + placed;
	g_Stats.resourceFails = (g_Stats.resourceFails or 0) + failed;
	g_Stats.islandStrategics = "A=OIL,B=URANIUM,C=ALUMINUM:" .. placed;
end

local function PlaceLuxuries()
	-- Plots of every type-slot.
	local plots = {};
	for slot = 1, 17 do
		plots[slot] = {};
	end
	for _, k in ipairs(g_Order) do
		local lux = g_Lux[k];
		if lux ~= nil then
			local q, r = KeyQR(k);
			for rot = 0, NUM_ARMS - 1 do
				local tq, tr = RotN(q, r, rot);
				local list = plots[TypeSlot(lux, rot)];
				list[#list + 1] = PlotAt(tq, tr);
			end
		end
	end

	-- Luxuries that fit every plot of a type-slot.
	local pool = {};
	for row in GameInfo.Resources() do
		if row.ResourceClassType == "RESOURCECLASS_LUXURY"
			and ((row.Frequency or 0) > 0 or (row.SeaFrequency or 0) > 0) then
			pool[#pool + 1] = row.Index;
		end
	end
	Shuffle(pool, "Snowflake luxury pool");
	local candidates = {};
	for slot = 1, 17 do
		candidates[slot] = {};
		if #plots[slot] > 0 then
			for _, index in ipairs(pool) do
				local fits = true;
				for _, plot in ipairs(plots[slot]) do
					if not ResourceBuilder.CanHaveResource(plot, index) then
						fits = false;
						break;
					end
				end
				if fits then
					candidates[slot][#candidates[slot] + 1] = index;
				end
			end
		end
	end

	-- Every type-slot gets a different luxury (bipartite matching, augmenting paths).
	local owner = {};     -- luxury index -> type-slot
	local chosen = {};    -- type-slot -> luxury index
	local function Assign(slot, seen)
		for _, index in ipairs(candidates[slot]) do
			if not seen[index] then
				seen[index] = true;
				if owner[index] == nil or Assign(owner[index], seen) then
					owner[index] = slot;
					chosen[slot] = index;
					return true;
				end
			end
		end
		return false;
	end
	local shared = 0;
	for slot = 1, 17 do
		if #plots[slot] > 0 and not Assign(slot, {}) then
			-- Not enough distinct luxuries fit: reuse the first fitting one.
			if #candidates[slot] > 0 then
				chosen[slot] = candidates[slot][1];
				shared = shared + 1;
			end
		end
	end

	local placed, failed = 0, 0;
	local summary = {};
	for slot = 1, 17 do
		local index = chosen[slot];
		local name = index and GameInfo.Resources[index].ResourceType or "none";
		summary[#summary + 1] = TypeSlotName(slot) .. "=" .. string.gsub(name, "RESOURCE_", "");
		for _, plot in ipairs(plots[slot]) do
			if index ~= nil and ResourceBuilder.CanHaveResource(plot, index) then
				ResourceBuilder.SetResourceType(plot, index, 1);
				placed = placed + 1;
			else
				failed = failed + 1;
			end
		end
	end
	g_Stats.luxuries = placed;
	g_Stats.luxuryFails = failed;
	print(LOG .. "_LUXURIES placed=" .. placed .. " failed=" .. failed .. " shared=" .. shared
		.. " " .. table.concat(summary, " "));
end

------------------------------------------------------------------------------
-- Players.
------------------------------------------------------------------------------
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

-- Which of the six slots to use for n players, spread evenly.
local SPREAD = {
	[1] = { 0 }, [2] = { 0, 3 }, [3] = { 0, 2, 4 }, [4] = { 0, 1, 3, 4 },
	[5] = { 0, 1, 2, 3, 4 }, [6] = { 0, 1, 2, 3, 4, 5 },
};

local function SpreadSlots(n, offset)
	local list = {};
	local base = SPREAD[math.min(n, 6)] or {};
	for _, s in ipairs(base) do
		list[#list + 1] = (s + offset) % NUM_ARMS;
	end
	return list;
end

-- Small snow islets in the grid corners, outside the symmetric area.
local function IsletSites()
	local sites = {};
	local corners = { {0, 0}, {GRID - 1, 0}, {0, GRID - 1}, {GRID - 1, GRID - 1} };
	local offsets = { {3, 3}, {8, 3}, {3, 8}, {13, 3}, {3, 13} };
	for _, off in ipairs(offsets) do
		for _, c in ipairs(corners) do
			local x = (c[1] == 0) and off[1] or (GRID - 1 - off[1]);
			local y = (c[2] == 0) and off[2] or (GRID - 1 - off[2]);
			local q, r = ToAxial(x, y);
			if HexDist(q, r) >= RADIUS + 4 then
				sites[#sites + 1] = { x, y };
			end
		end
	end
	return sites;
end

local function MakeIslet(site)
	local plot = Map.GetPlot(site[1], site[2]);
	TerrainBuilder.SetTerrainType(plot, TERRAIN.SNOW);
	for _, dir in ipairs({ DirectionTypes.DIRECTION_EAST, DirectionTypes.DIRECTION_WEST,
		DirectionTypes.DIRECTION_NORTHEAST }) do
		local adj = Map.GetAdjacentPlot(site[1], site[2], dir);
		if adj ~= nil then
			TerrainBuilder.SetTerrainType(adj, TERRAIN.SNOW);
		end
	end
	for dir = 0, 5 do
		local adj = Map.GetAdjacentPlot(site[1], site[2], dir);
		if adj ~= nil then
			for dir2 = 0, 5 do
				local adj2 = Map.GetAdjacentPlot(adj:GetX(), adj:GetY(), dir2);
				if adj2 ~= nil and adj2:GetTerrainType() == TERRAIN.OCEAN then
					TerrainBuilder.SetTerrainType(adj2, TERRAIN.COAST);
				end
			end
		end
	end
	return plot;
end

-- Builds the start plan before AreaBuilder runs (the islets are terrain).
local g_Plan = nil;

local function PlanPlayers()
	local plan = { majors = {}, minors = {}, islets = {} };
	local majorIDs = PlayerManager.GetAliveMajorIDs();
	local majorCount = PlayerManager.GetAliveMajorsCount();
	local real, spectators = {}, {};
	for i = 1, majorCount do
		local id = majorIDs[i];
		if IsSpectator(id) then
			spectators[#spectators + 1] = id;
		else
			real[#real + 1] = id;
		end
	end
	local minorIDs = PlayerManager.GetAliveMinorIDs();
	local minorCount = PlayerManager.GetAliveMinorsCount();
	local minors = {};
	for i = 1, minorCount do
		minors[#minors + 1] = minorIDs[i];
	end

	-- Majors: an even spread of arms, rotated at random, players shuffled.
	Shuffle(real, "Snowflake major order");
	local armOffset = Rand(NUM_ARMS, "Snowflake arm offset");
	local arms = SpreadSlots(math.min(#real, NUM_ARMS), armOffset);
	local overflow = {};
	for i, id in ipairs(real) do
		if i <= #arms then
			plan.majors[#plan.majors + 1] = { id = id, arm = arms[i] };
		else
			overflow[#overflow + 1] = id;
		end
	end

	-- City-states: inner slots first (spread), then outer slots (spread).
	Shuffle(minors, "Snowflake minor order");
	local islandOffset = Rand(NUM_ARMS, "Snowflake island offset");
	local slots = {};
	local innerCount = math.min(#minors, NUM_ARMS);
	for _, island in ipairs(SpreadSlots(innerCount, islandOffset)) do
		slots[#slots + 1] = { island = island, which = 1 };
	end
	if #g_CSSlots >= 2 and #minors > NUM_ARMS then
		local outerCount = math.min(#minors - NUM_ARMS, NUM_ARMS);
		for _, island in ipairs(SpreadSlots(outerCount, islandOffset + 1)) do
			slots[#slots + 1] = { island = island, which = 2 };
		end
	end
	for i, id in ipairs(minors) do
		if i <= #slots and g_CSSlots[slots[i].which] ~= nil then
			plan.minors[#plan.minors + 1] = { id = id, island = slots[i].island, which = slots[i].which };
		else
			overflow[#overflow + 1] = id;
		end
	end

	-- Spectators (and any player without a slot) get an islet each.
	local sites = IsletSites();
	local needIslets = {};
	for _, id in ipairs(spectators) do
		needIslets[#needIslets + 1] = { id = id, spectator = true };
	end
	for _, id in ipairs(overflow) do
		needIslets[#needIslets + 1] = { id = id, spectator = false };
	end
	for i, entry in ipairs(needIslets) do
		local site = sites[((i - 1) % math.max(#sites, 1)) + 1];
		if site ~= nil then
			plan.islets[#plan.islets + 1] = { id = entry.id, site = site, spectator = entry.spectator };
		end
	end
	plan.real = #real;
	plan.spectators = #spectators;
	plan.overflow = #overflow;
	plan.armOffset = armOffset;
	g_Plan = plan;
end

local function AssignStarts()
	local plan = g_Plan;
	local lines = {};
	for _, entry in ipairs(plan.majors) do
		local q, r = RotN(START_Q, START_R, entry.arm);
		local plot = PlotAt(q, r);
		Players[entry.id]:SetStartingPlot(plot);
		local set = SET_LETTERS[(entry.arm % 3) + 1];
		lines[#lines + 1] = "p" .. entry.id .. ":arm" .. entry.arm .. ":set" .. set .. "@" .. plot:GetX() .. "," .. plot:GetY();
	end
	print(LOG .. "_MAJORS real=" .. plan.real .. " " .. table.concat(lines, " "));
	lines = {};
	for _, entry in ipairs(plan.minors) do
		local slot = g_CSSlots[entry.which];
		local q, r = RotN(slot[1], slot[2], entry.island);
		local plot = PlotAt(q, r);
		Players[entry.id]:SetStartingPlot(plot);
		lines[#lines + 1] = "p" .. entry.id .. ":island" .. entry.island .. "." .. entry.which .. "@" .. plot:GetX() .. "," .. plot:GetY();
	end
	print(LOG .. "_MINORS count=" .. #plan.minors .. " " .. table.concat(lines, " "));
	for _, entry in ipairs(plan.islets) do
		local plot = Map.GetPlot(entry.site[1], entry.site[2]);
		Players[entry.id]:SetStartingPlot(plot);
		print(LOG .. "_ISLET player=" .. entry.id .. " spectator=" .. tostring(entry.spectator)
			.. " plot=" .. plot:GetX() .. "," .. plot:GetY());
		if not entry.spectator then
			print(LOG .. "_OVERFLOW player=" .. entry.id .. " (no arm or island slot left; this map has 6 arms and 12 city-state slots)");
		end
	end
end

local function PlaceGoodies()
	if GameConfiguration.GetValue("GAME_NO_GOODY_HUTS") == true then
		print(LOG .. "_GOODIES disabled");
		return;
	end
	local hut = GameInfo.Improvements["IMPROVEMENT_GOODY_HUT"];
	if hut == nil then
		return;
	end
	local count = 0;
	for _, k in ipairs(g_Order) do
		if g_Goody[k] then
			local q, r = KeyQR(k);
			for rot = 0, NUM_ARMS - 1 do
				local tq, tr = RotN(q, r, rot);
				local plot = PlotAt(tq, tr);
				if ImprovementBuilder.CanHaveImprovement(plot, hut.Index, -1) then
					ImprovementBuilder.SetImprovementType(plot, hut.Index, -1);
					count = count + 1;
				end
			end
		end
	end
	g_Stats.goodies = count;
end

------------------------------------------------------------------------------
-- Fingerprint: one checksum over the finished map and the starts, for
-- comparing multiplayer peers.
------------------------------------------------------------------------------
local function Fingerprint()
	local h = 7;
	local function Mix(v)
		h = (h * 31 + (v + 1000)) % 2147483647;
	end
	for i = 0, Map.GetPlotCount() - 1 do
		local plot = Map.GetPlotByIndex(i);
		Mix(plot:GetTerrainType());
		Mix(plot:GetFeatureType());
		Mix(plot:GetResourceType());
		Mix(plot:IsRiver() and 1 or 0);
	end
	for _, entry in ipairs(g_Plan.majors) do
		Mix(entry.id);
		Mix(entry.arm);
	end
	for _, entry in ipairs(g_Plan.minors) do
		Mix(entry.id);
		Mix(entry.island * 2 + entry.which);
	end
	print(LOG .. "_FINGERPRINT version=" .. VERSION .. " checksum=" .. h
		.. " grid=" .. GRID .. "x" .. GRID
		.. " majors=" .. #g_Plan.majors .. " minors=" .. #g_Plan.minors
		.. " spectators=" .. g_Plan.spectators .. " overflow=" .. g_Plan.overflow
		.. " rivers=" .. #g_Rivers .. " river_edges=" .. tostring(g_Stats.riverEdges)
		.. " resources=" .. tostring(g_Stats.resources) .. " resource_fails=" .. tostring(g_Stats.resourceFails)
		.. " luxuries=" .. tostring(g_Stats.luxuries) .. " luxury_fails=" .. tostring(g_Stats.luxuryFails)
		.. " missed_slots=" .. tostring(g_Stats.missedSlots or 0)
		.. " wonders=" .. tostring(g_Stats.wonders or 0) .. (g_Stats.wondersUneven and "(uneven)" or "")
		.. " floodplains=" .. tostring(g_Stats.floodplains) .. " hub_strategics=" .. tostring(g_Stats.hubStrategics)
		.. " island_strategics=" .. tostring(g_Stats.islandStrategics)
		.. " lowlands=" .. tostring(g_Stats.lowlands) .. " goodies=" .. tostring(g_Stats.goodies));
end

------------------------------------------------------------------------------
-- Entry points.
------------------------------------------------------------------------------
function GetMapInitData(MapSize)
	return { Width = GRID, Height = GRID, WrapX = false, WrapY = false };
end

local function WondersOption()
	local value = MapConfiguration.GetValue("RBSSnowflakeWonders");
	value = tonumber(value);
	if value == nil then
		return 3;
	end
	if value <= 0 then return 0; end
	if value >= 6 then return 6; end
	return 3;
end

function GenerateMap()
	print(LOG .. "_BEGIN version=" .. VERSION .. " grid=" .. GRID .. "x" .. GRID .. " radius=" .. RADIUS);
	InitTypes();
	BuildOrder();

	GenerateMainland();
	GenerateIslands();
	LogLand();
	AssignTerrain();
	GenerateRivers();
	AddFeatures();
	AddFloodplains();
	PlaceHubSlots();
	PlaceArmSlots();
	PlaceIslandSlots();

	WriteTerrain();
	WriteRivers();
	PlanPlayers();
	for _, entry in ipairs(g_Plan.islets) do
		MakeIslet(entry.site);
	end

	AreaBuilder.Recalculate();
	TerrainBuilder.AnalyzeChokepoints();
	local wanted = WondersOption();
	local wonders = PlaceWonders(wanted);
	if wanted == 6 and #wonders == 0 then
		-- Neighbouring sites are exactly the engine minimum apart; if the
		-- engine refuses that, alternate sites (12 apart) keep the map equal.
		wonders = PlaceWonders(3);
	end
	if wanted > 0 and #wonders == 0 then
		PlaceHubWondersAnyhow(math.min(wanted, 3));
	end
	AreaBuilder.Recalculate();
	TerrainBuilder.AnalyzeChokepoints();
	TerrainBuilder.StampContinents();
	MarkLowlands();

	PlaceFixedResources();
	PlaceIslandStrategics();
	PlaceLuxuries();
	AssignStarts();
	PlaceGoodies();
	Fingerprint();
end
