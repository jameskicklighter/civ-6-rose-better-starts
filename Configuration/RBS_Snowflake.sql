-- Rose Snowflake: a six-armed map generated with six-fold rotational symmetry
-- (Maps/RBS_Snowflake.lua). One arm per player, two city-states on each of
-- the six islands between the arms, a hub with natural wonders in the middle.
-- Spectator slots take no arm, so the player limit leaves room for them.

INSERT INTO Maps (Domain, File, Name, Description, Image, DisableWorldWrap, SortIndex)
VALUES ('StandardMaps', 'RBS_Snowflake.lua', 'LOC_RBS_SNOWFLAKE_NAME', 'LOC_RBS_SNOWFLAKE_DESCRIPTION', 'Map_6ArmedSnowflake', 1, 71);

-- The script sets its own grid (64x64); MAPSIZE_SMALL sets everything else
-- the size controls (costs, city targets).
INSERT INTO MapSizes (Domain, MapSizeType, Name, Description, MinPlayers, MaxPlayers, DefaultPlayers,
	MinCityStates, MaxCityStates, DefaultCityStates, SortIndex)
VALUES ('RBS_Snowflake.lua', 'MAPSIZE_SMALL', 'LOC_MAPSIZE_SMALL_NAME', 'LOC_RBS_SNOWFLAKE_SIZE_DESCRIPTION', 2, 12, 6,
	0, 12, 12, 10);

INSERT INTO MapDomainOverrides (Map, ParameterId, Domain)
VALUES ('RBS_Snowflake.lua', 'MapSize', 'RBS_Snowflake.lua');

-- Resources and start positions are fixed by the script.
INSERT INTO ParameterDependencies (ParameterId, ConfigurationGroup, ConfigurationId, Operator, ConfigurationValue)
VALUES ('Resources', 'Map', 'MAP_SCRIPT', 'NotEquals', 'RBS_Snowflake.lua'),
	('StartPosition', 'Map', 'MAP_SCRIPT', 'NotEquals', 'RBS_Snowflake.lua');

-- Natural wonders in the hub: none, three (between alternate arms) or six.
INSERT INTO Parameters (Key1, Key2, ParameterId, Name, Description, Domain, DefaultValue, ConfigurationGroup, ConfigurationId, GroupId, SortIndex)
VALUES ('Map', 'RBS_Snowflake.lua', 'RBSSnowflakeWonders', 'LOC_RBS_SNOWFLAKE_WONDERS_NAME', 'LOC_RBS_SNOWFLAKE_WONDERS_DESCRIPTION',
	'RBSSnowflakeWonders', 3, 'Map', 'RBSSnowflakeWonders', 'MapOptions', 266);

INSERT INTO DomainValues (Domain, Value, Name, Description, SortIndex)
VALUES ('RBSSnowflakeWonders', 0, 'LOC_RBS_SNOWFLAKE_WONDERS_0_NAME', 'LOC_RBS_SNOWFLAKE_WONDERS_0_DESCRIPTION', 10),
	('RBSSnowflakeWonders', 3, 'LOC_RBS_SNOWFLAKE_WONDERS_3_NAME', 'LOC_RBS_SNOWFLAKE_WONDERS_3_DESCRIPTION', 20),
	('RBSSnowflakeWonders', 6, 'LOC_RBS_SNOWFLAKE_WONDERS_6_NAME', 'LOC_RBS_SNOWFLAKE_WONDERS_6_DESCRIPTION', 30);
