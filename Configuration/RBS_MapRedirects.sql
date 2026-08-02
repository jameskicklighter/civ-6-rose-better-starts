-- Rose Better Starts keeps the stock map names and options, but points the
-- selected map at a uniquely named wrapper. Each wrapper includes the original
-- Firaxis script and installs the one-time strategic-resource normalizer.

UPDATE Maps SET File = 'RBS_Continents.lua'          WHERE File = 'Continents.lua';
UPDATE Maps SET File = 'RBS_Fractal.lua'             WHERE File = 'Fractal.lua';
UPDATE Maps SET File = 'RBS_InlandSea.lua'           WHERE File = 'InlandSea.lua';
UPDATE Maps SET File = 'RBS_Island_Plates.lua'       WHERE File = 'Island_Plates.lua';
UPDATE Maps SET File = 'RBS_Lakes.lua'               WHERE File = 'Lakes.lua';
UPDATE Maps SET File = 'RBS_Pangaea.lua'             WHERE File = 'Pangaea.lua';
UPDATE Maps SET File = 'RBS_Seven_Seas.lua'          WHERE File = 'Seven_Seas.lua';
UPDATE Maps SET File = 'RBS_Shuffle.lua'             WHERE File = 'Shuffle.lua';
UPDATE Maps SET File = 'RBS_Small_Continents.lua'    WHERE File = 'Small_Continents.lua';
UPDATE Maps SET File = 'RBS_Terra.lua'               WHERE File = 'Terra.lua';
UPDATE Maps SET File = 'RBS_Archipelago_XP2.lua'     WHERE File = 'Archipelago_XP2.lua';
UPDATE Maps SET File = 'RBS_Continents_Islands.lua'  WHERE File = 'Continents_Islands.lua';
UPDATE Maps SET File = 'RBS_Primordial.lua'          WHERE File = 'Primordial.lua';
UPDATE Maps SET File = 'RBS_Splintered_Fractal.lua'  WHERE File = 'Splintered_Fractal.lua';
UPDATE Maps SET File = 'RBS_Tilted_Axis.lua'         WHERE File = 'Tilted_Axis.lua';
UPDATE Maps SET File = 'RBS_Highlands_XP2.lua'       WHERE File = 'Highlands_XP2.lua';
UPDATE Maps SET File = 'RBS_Wetlands_XP2.lua'        WHERE File = 'Wetlands_XP2.lua';

UPDATE Parameters SET Key2 = 'RBS_Continents.lua'          WHERE Key1 = 'Map' AND Key2 = 'Continents.lua';
UPDATE Parameters SET Key2 = 'RBS_Fractal.lua'             WHERE Key1 = 'Map' AND Key2 = 'Fractal.lua';
UPDATE Parameters SET Key2 = 'RBS_InlandSea.lua'           WHERE Key1 = 'Map' AND Key2 = 'InlandSea.lua';
UPDATE Parameters SET Key2 = 'RBS_Island_Plates.lua'       WHERE Key1 = 'Map' AND Key2 = 'Island_Plates.lua';
UPDATE Parameters SET Key2 = 'RBS_Lakes.lua'               WHERE Key1 = 'Map' AND Key2 = 'Lakes.lua';
UPDATE Parameters SET Key2 = 'RBS_Pangaea.lua'             WHERE Key1 = 'Map' AND Key2 = 'Pangaea.lua';
UPDATE Parameters SET Key2 = 'RBS_Seven_Seas.lua'          WHERE Key1 = 'Map' AND Key2 = 'Seven_Seas.lua';
UPDATE Parameters SET Key2 = 'RBS_Shuffle.lua'             WHERE Key1 = 'Map' AND Key2 = 'Shuffle.lua';
UPDATE Parameters SET Key2 = 'RBS_Small_Continents.lua'    WHERE Key1 = 'Map' AND Key2 = 'Small_Continents.lua';
UPDATE Parameters SET Key2 = 'RBS_Terra.lua'               WHERE Key1 = 'Map' AND Key2 = 'Terra.lua';
UPDATE Parameters SET Key2 = 'RBS_Archipelago_XP2.lua'     WHERE Key1 = 'Map' AND Key2 = 'Archipelago_XP2.lua';
UPDATE Parameters SET Key2 = 'RBS_Continents_Islands.lua'  WHERE Key1 = 'Map' AND Key2 = 'Continents_Islands.lua';
UPDATE Parameters SET Key2 = 'RBS_Primordial.lua'          WHERE Key1 = 'Map' AND Key2 = 'Primordial.lua';
UPDATE Parameters SET Key2 = 'RBS_Splintered_Fractal.lua'  WHERE Key1 = 'Map' AND Key2 = 'Splintered_Fractal.lua';
UPDATE Parameters SET Key2 = 'RBS_Tilted_Axis.lua'         WHERE Key1 = 'Map' AND Key2 = 'Tilted_Axis.lua';
UPDATE Parameters SET Key2 = 'RBS_Highlands_XP2.lua'       WHERE Key1 = 'Map' AND Key2 = 'Highlands_XP2.lua';
UPDATE Parameters SET Key2 = 'RBS_Wetlands_XP2.lua'        WHERE Key1 = 'Map' AND Key2 = 'Wetlands_XP2.lua';

-- Preserve the normal single-player and multiplayer default-map behavior.
UPDATE Parameters SET DefaultValue = 'RBS_Continents.lua' WHERE ParameterId = 'Map' AND DefaultValue = 'Continents.lua';
UPDATE Parameters SET DefaultValue = 'RBS_Pangaea.lua'    WHERE ParameterId = 'Map' AND DefaultValue = 'Pangaea.lua';
