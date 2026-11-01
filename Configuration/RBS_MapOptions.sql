-- Map options of Rose Better Starts. Map-group options are part of the
-- lobby's map settings, so every machine generates with the same value.

-- Larger Pangaea: the stock Pangaea land generation with less water
-- (Maps/RBS_LargerPangaea.lua). Off by default.
INSERT INTO Parameters (Key1, Key2, ParameterId, Name, Description, Domain, DefaultValue, ConfigurationGroup, ConfigurationId, GroupId, SortIndex)
VALUES ('Map', 'RBS_Pangaea.lua', 'RBSLargerPangaea', 'LOC_RBS_LARGER_PANGAEA_NAME', 'LOC_RBS_LARGER_PANGAEA_DESCRIPTION', 'bool', 0, 'Map', 'RBSLargerPangaea', 'MapOptions', 265);
