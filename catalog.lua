--[==[
    Daseeki Armory — THE SHIPPED ITEM CATALOG.

    GENERATED FILE. Built by dev/gen-catalog.lua; regenerate rather than
    hand-edit. It has no policy in it at all — every judgement call about what
    a player may be offered lives in restrictions.lua, which IS hand-editable.

    WHY THIS FILE EXISTS. Classic Era is a frozen client, so the set of
    equippable items it holds is a constant — the same on every account, every
    realm and every login. Until 1.3.1 the goal picker measured that constant
    itself: a minute-long walk of 32 000 item ids, once per account, behind a
    first-login timer and a "Rescan Items" button, with the private answer
    persisted to SavedVariables. A frozen fact does not need measuring by the
    person reading it. It needs shipping.

    So the picker now arrives COMPLETE. A brand-new account, first login, no
    scan, no wait: open a slot and the whole list is there.

    THE CONTRACT the rest of the addon depends on:

      Addon.StaticCatalogRaw    one long string, one line per item:

                                    <itemID> <quality> <name>

                                ids ascending; quality is the client's own
                                0..6; the name runs to end of line and is
                                verbatim from the client.

      Addon.StaticCatalogCount  how many lines that string holds, as a literal,
                                so counting never costs a parse.

      Read it through Scan.CatalogEach(fn) in itemScan.lua — the parser lives
      there, with the rest of the pure layer, where the harness can pin it.

    WHY A STRING AND NOT A TABLE. Both consumers stream this once and never
    look again, so a table would be 1.1 MB of permanent hash nodes to serve two
    linear walks. The string is 240 KB resident. Five formats were built and
    measured on this exact payload; the numbers are in dev/gen-catalog.lua.

    WHAT IS NOT HERE. equipLoc, icon, classID and subclassID — GetItemInfoInstant
    answers all four offline for any id the client holds, so they are re-derived
    at index time and cannot go stale. That also makes the catalog self-limiting:
    an id this catalog names but the running client does not have is dropped, so
    a build mismatch quietly shrinks the list instead of offering phantoms.

    BLIZZARD'S SCAFFOLDING IS ALREADY GONE. Placeholders, creature-equipment
    art, designer test gear and retired duplicates were removed at generation
    time by Scan.IsInternalName — the same function, from the same file, that
    the addon would have used at runtime. They are not facts a user needs, so
    they are not shipped. Items that are real but that no player can obtain
    (Ashbringer, the Warglaives, the GM stones) ARE still here, and are hidden
    by Addon.StaticUnobtainable at runtime — that list is policy, and policy
    must stay editable in one line.
--]==]

local _, Addon = ...

-- 9240 items · 166220 bytes of names · quality census:
--     0 Poor         393
--     1 Common      1146
--     2 Uncommon    4086
--     3 Rare        2284
--     4 Epic        1310
--     5 Legendary     11
--     6 Artifact      10
-- Generated from a completed scan of build 68940 over ids 1-32000.
-- 1264 of the client's 10504 equippable records were withheld as Blizzard's own
-- scaffolding (dev/gen-catalog.lua bakes the denylist in; see itemScan.lua).

Addon.StaticCatalogCount = 9240

Addon.StaticCatalogRaw = [==[
25 1 Worn Shortsword
35 1 Bent Staff
36 1 Worn Mace
37 1 Worn Axe
38 1 Recruit's Shirt
39 0 Recruit's Pants
40 1 Recruit's Boots
43 1 Squire's Boots
44 0 Squire's Pants
45 1 Squire's Shirt
47 1 Footpad's Shoes
48 0 Footpad's Pants
49 1 Footpad's Shirt
51 1 Neophyte's Boots
52 0 Neophyte's Pants
53 1 Neophyte's Shirt
55 1 Apprentice's Boots
56 0 Apprentice's Robe
57 0 Acolyte's Robe
59 1 Acolyte's Shoes
60 1 Layered Tunic
61 1 Dwarven Leather Pants
79 1 Dwarven Cloth Britches
80 1 Soft Fur-lined Shoes
85 1 Dirty Leather Vest
120 0 Thug Pants
121 1 Thug Boots
127 1 Trapper's Shirt
129 1 Rugged Trapper's Boots
139 0 Brawler's Pants
140 1 Brawler's Boots
147 0 Rugged Trapper's Pants
148 1 Rugged Trapper's Shirt
153 0 Primitive Kilt
154 1 Primitive Mantle
193 1 Tattered Cloth Vest
194 1 Tattered Cloth Pants
195 1 Tattered Cloth Boots
200 1 Thick Cloth Vest
201 1 Thick Cloth Pants
202 1 Thick Cloth Shoes
203 1 Thick Cloth Gloves
209 1 Dirty Leather Pants
210 1 Dirty Leather Boots
236 1 Cured Leather Armor
237 1 Cured Leather Pants
238 1 Cured Leather Boots
239 1 Cured Leather Gloves
285 1 Scalemail Vest
286 1 Scalemail Pants
287 1 Scalemail Boots
647 4 Destiny
710 1 Bracers of the People's Militia
711 1 Tattered Cloth Gloves
714 1 Dirty Leather Gloves
718 1 Scalemail Gloves
719 1 Rabbit Handler Gloves
720 3 Brawler Gloves
727 2 Notched Shortsword
744 2 Thunderbrew's Boot Flask
753 2 Dragonmaw Shortsword
754 3 Shortsword of Vengeance
756 2 Tunnel Pick
763 1 Ice-covered Bracers
766 1 Flanged Mace
767 1 Long Bo Staff
768 1 Lumberjack Axe
776 3 Vendetta
778 1 Kobold Excavation Pick
781 1 Stone Gnoll Hammer
789 2 Stout Battlehammer
790 2 Forester's Axe
791 3 Gnarled Ash Staff
792 1 Knitted Sandals
793 1 Knitted Gloves
794 1 Knitted Pants
795 1 Knitted Tunic
796 1 Rough Leather Boots
797 1 Rough Leather Gloves
798 1 Rough Leather Pants
799 1 Rough Leather Vest
809 4 Bloodrazor
810 4 Hammer of the Northern Wind
811 4 Axe of the Deep Woods
812 4 Glowing Brightwood Staff
816 2 Small Hand Blade
820 2 Slicer Blade
821 2 Riverpaw Leather Vest
826 2 Brutish Riverpaw Axe
827 2 Wicked Blackjack
832 2 Silver Defias Belt
833 4 Lifestone
837 1 Heavy Weave Armor
838 1 Heavy Weave Pants
839 1 Heavy Weave Gloves
840 1 Heavy Weave Shoes
843 1 Tanned Leather Boots
844 1 Tanned Leather Gloves
845 1 Tanned Leather Pants
846 1 Tanned Leather Jerkin
847 1 Chainmail Armor
848 1 Chainmail Pants
849 1 Chainmail Boots
850 1 Chainmail Gloves
851 1 Cutlass
852 1 Mace
853 1 Hatchet
854 1 Quarter Staff
859 1 Fine Cloth Shirt
860 1 Cavalier's Boots
862 3 Runed Ring
863 2 Gloom Reaper
864 2 Knightly Longsword
865 2 Leaden Mace
866 2 Monk's Staff
867 4 Gloves of Holy Might
868 4 Ardent Custodian
869 4 Dazzling Longsword
870 4 Fiery War Axe
871 4 Flurry Axe
872 2 Rockslicer
873 4 Staff of Jordan
876 0 Worn Wooden Buckler
880 2 Staff of Horrors
885 2 Black Metal Axe
886 2 Black Metal Shortsword
888 3 Naga Battle Gloves
890 3 Twisted Chanter's Staff
892 2 Gnoll Casting Gloves
897 2 Madwolf Bracers
899 2 Venom Web Fang
911 2 Ironwood Treebranch
913 2 Huge Ogre Sword
914 2 Large Ogre Chain Armor
920 2 Wicked Spiked Mace
922 1 Dacian Falx
923 1 Longsword
924 1 Maul
925 1 Flail
926 1 Battle Axe
927 1 Double Axe
928 1 Long Staff
934 3 Stalvan's Reaper
935 3 Night Watch Shortsword
936 3 Midnight Mace
937 3 Black Duskwood Staff
940 4 Robes of Insight
942 4 Freezing Band
943 4 Warden Staff
944 4 Elemental Mage Staff
945 1 Shadow Sword
948 1 Nature Sword
983 1 Red Linen Sash
997 1 Fire Sword of Crippling
1008 1 Well-used Sword
1009 2 Compact Hammer
1010 1 Gnarled Short Staff
1011 1 Sharp Axe
1076 2 Defias Renegade Ring
1077 2 Defias Mage Ring
1116 2 Ring of Pure Silver
1121 3 Feet of the Lynx
1131 2 Totem of Infliction
1154 1 Belt of the People's Militia
1155 3 Rod of the Sleepwalker
1156 3 Lavishly Jeweled Ring
1158 1 Solid Metal Club
1159 1 Militia Quarterstaff
1161 1 Militia Shortsword
1166 1 Dented Buckler
1167 1 Small Targe
1168 4 Skullflame Shield
1169 4 Blackskull Shield
1171 1 Well-stitched Robe
1172 2 Grayson's Torch
1173 1 Weather-worn Boots
1182 1 Brass-studded Bracers
1183 1 Elastic Wristguards
1189 2 Overseer's Ring
1190 2 Overseer's Cloak
1193 1 Banded Buckler
1194 1 Bastard Sword
1195 1 Kobold Mining Shovel
1196 1 Tabar
1197 1 Giant Mace
1198 1 Claymore
1200 1 Large Wooden Shield
1201 1 Dull Heater Shield
1202 1 Wall Shield
1203 3 Aegis of Stormwind
1204 4 The Green Tower
1207 2 Murphstar
1211 2 Gnoll War Harness
1213 1 Gnoll Kindred Bracers
1214 2 Gnoll Punisher
1215 2 Support Girdle
1216 2 Frost Bracers
1218 2 Heavy Gnoll War Club
1219 2 Redridge Machete
1220 2 Lupine Axe
1254 1 Lesser Firestone
1263 4 Brain Hacker
1264 2 Headbasher
1265 3 Scorpion Sting
1270 2 Finely Woven Cloak
1273 2 Forest Chain
1275 2 Deputy Chain Coat
1276 2 Fire Hardened Buckler
1280 2 Cloaked Hood
1282 2 Sparkmetal Coif
1287 2 Giant Tarantula Fang
1292 3 Butcher's Cleaver
1296 2 Blackrock Mace
1297 2 Robes of the Shadowcaster
1299 2 Lesser Belt of the Spire
1300 2 Lesser Staff of the Spire
1302 2 Black Whelp Gloves
1303 2 Bridgeworker's Gloves
1304 2 Riding Gloves
1306 2 Wolfmane Wristguards
1310 2 Smith's Trousers
1314 2 Ghoul Fingers
1315 4 Lei of Lilies
1317 2 Hardened Root Staff
1318 3 Night Reaver
1319 2 Ring of Iron Will
1351 2 Fingerbone Bracers
1355 2 Buckskin Cape
1359 1 Lion-stamped Gloves
1360 1 Stormwind Chain Gloves
1364 0 Ragged Leather Vest
1366 0 Ragged Leather Pants
1367 0 Ragged Leather Boots
1368 0 Ragged Leather Gloves
1369 0 Ragged Leather Belt
1370 0 Ragged Leather Bracers
1372 0 Ragged Cloak
1374 0 Frayed Shoes
1376 0 Frayed Cloak
1377 0 Frayed Gloves
1378 0 Frayed Pants
1380 0 Frayed Robe
1382 1 Rock Mace
1383 1 Stone Tomahawk
1384 1 Dull Blade
1386 1 Thistlewood Axe
1387 2 Ghoulfang
1388 1 Crooked Staff
1389 1 Kobold Mining Mallet
1391 2 Riverpaw Mystic Staff
1394 2 Driftwood Club
1395 0 Apprentice's Pants
1396 0 Acolyte's Pants
1404 2 Tidal Charm
1405 2 Foamspittle Staff
1406 2 Pearl-encrusted Spear
1411 0 Withered Staff
1412 0 Crude Bastard Sword
1413 0 Feeble Sword
1414 0 Cracked Sledge
1415 0 Carpenter's Mallet
1416 0 Rusty Hatchet
1417 0 Beaten Battle Axe
1418 0 Worn Leather Belt
1419 0 Worn Leather Boots
1420 0 Worn Leather Bracers
1421 0 Worn Hide Cloak
1422 0 Worn Leather Gloves
1423 0 Worn Leather Pants
1425 0 Worn Leather Vest
1427 0 Patchwork Shoes
1429 0 Patchwork Cloak
1430 0 Patchwork Gloves
1431 0 Patchwork Pants
1433 0 Patchwork Armor
1436 2 Frontier Britches
1438 1 Warrior's Shield
1440 2 Gnoll Skull Basher
1443 4 Jeweled Amulet of Cainwyn
1445 1 Blackrock Pauldrons
1446 2 Blackrock Boots
1447 4 Ring of Saviors
1448 2 Blackrock Gauntlets
1449 2 Minor Channeling Ring
1454 3 Axe of the Enforcer
1455 2 Blackrock Champion's Axe
1457 2 Shadowhide Mace
1458 2 Shadowhide Maul
1459 2 Shadowhide Scalper
1460 2 Shadowhide Two-handed Sword
1461 2 Slayer's Battle Axe
1462 2 Ring of the Shadow
1465 2 Tigerbane
1469 2 Scimitar of Atun
1473 2 Riverside Staff
1479 1 Salma's Oven Mitts
1480 2 Fist of the People's Militia
1481 3 Grimclaw
1482 3 Shadowfang
1483 3 Face Smasher
1484 3 Witching Stave
1485 0 Pitchfork
1486 3 Tree Bark Jacket
1488 3 Avenger's Armor
1489 3 Gloomshroud Armor
1490 2 Guardian Talisman
1491 3 Ring of Precision
1493 3 Heavy Marauder Scimitar
1495 0 Calico Shoes
1497 0 Calico Cloak
1498 0 Calico Gloves
1499 0 Calico Pants
1501 0 Calico Tunic
1502 0 Warped Leather Belt
1503 0 Warped Leather Boots
1504 0 Warped Leather Bracers
1505 0 Warped Cloak
1506 0 Warped Leather Gloves
1507 0 Warped Leather Pants
1509 0 Warped Leather Vest
1510 0 Heavy Hammer
1511 0 Commoner's Sword
1512 0 Crude Battle Axe
1513 0 Old Greatsword
1514 0 Rusty Warhammer
1515 0 Rough Wooden Staff
1516 0 Worn Hatchet
1521 2 Lumbering Ogre Axe
1522 2 Headhunting Spear
1523 2 Huge Stone Club
1539 2 Gnarled Hermit's Staff
1547 2 Shield of the Faith
1557 2 Buckler of the Seas
1560 2 Bluegill Sandals
1561 2 Harvester's Robe
1566 2 Edge of the People's Militia
1602 3 Sickle Axe
1604 2 Chromatic Sword
1607 3 Soulkeeper
1608 2 Skullcrusher Mace
1613 2 Spiritchaser Staff
1624 2 Skullsplitter Helm
1625 2 Exquisite Flamberge
1639 2 Grinning Axe
1640 2 Monstrous War Axe
1659 2 Engineering Gloves
1664 2 Spellforce Rod
1677 2 Drake-scale Vest
1678 3 Black Ogre Kickers
1679 2 Korg Bat
1680 2 Headchopper
1713 3 Ankh of Life
1714 3 Necklace of Calisea
1715 3 Polished Jazeraint Armor
1716 3 Robe of the Magi
1717 3 Double Link Tunic
1718 3 Basilisk Hide Pants
1720 3 Tanglewood Staff
1721 3 Viking Warhammer
1722 3 Thornstone Sledgehammer
1726 3 Poison-tipped Bone Spear
1727 3 Sword of Decay
1728 4 Teebu's Blazing Longsword
1730 0 Worn Mail Belt
1731 0 Worn Mail Boots
1732 0 Worn Mail Bracers
1733 0 Worn Cloak
1734 0 Worn Mail Gloves
1735 0 Worn Mail Pants
1737 0 Worn Mail Vest
1738 0 Laced Mail Belt
1739 0 Laced Mail Boots
1740 0 Laced Mail Bracers
1741 0 Laced Cloak
1742 0 Laced Mail Gloves
1743 0 Laced Mail Pants
1744 0 Laced Mail Shoulderpads
1745 0 Laced Mail Vest
1746 0 Linked Chain Belt
1747 0 Linked Chain Boots
1748 0 Linked Chain Bracers
1749 0 Linked Chain Cloak
1750 0 Linked Chain Gloves
1751 0 Linked Chain Pants
1752 0 Linked Chain Shoulderpads
1753 0 Linked Chain Vest
1754 0 Reinforced Chain Belt
1755 0 Reinforced Chain Boots
1756 0 Reinforced Chain Bracers
1757 0 Reinforced Chain Cloak
1758 0 Reinforced Chain Gloves
1759 0 Reinforced Chain Pants
1760 0 Reinforced Chain Shoulderpads
1761 0 Reinforced Chain Vest
1764 0 Canvas Shoes
1766 0 Canvas Cloak
1767 0 Canvas Gloves
1768 0 Canvas Pants
1769 0 Canvas Shoulderpads
1770 0 Canvas Vest
1772 0 Brocade Shoes
1774 0 Brocade Cloak
1775 0 Brocade Gloves
1776 0 Brocade Pants
1777 0 Brocade Shoulderpads
1778 0 Brocade Vest
1780 0 Cross-stitched Sandals
1782 0 Cross-stitched Cloak
1783 0 Cross-stitched Gloves
1784 0 Cross-stitched Pants
1785 0 Cross-stitched Shoulderpads
1786 0 Cross-stitched Vest
1787 0 Patched Leather Belt
1788 0 Patched Leather Boots
1789 0 Patched Leather Bracers
1790 0 Patched Cloak
1791 0 Patched Leather Gloves
1792 0 Patched Leather Pants
1793 0 Patched Leather Shoulderpads
1794 0 Patched Leather Jerkin
1795 0 Rawhide Belt
1796 0 Rawhide Boots
1797 0 Rawhide Bracers
1798 0 Rawhide Cloak
1799 0 Rawhide Gloves
1800 0 Rawhide Pants
1801 0 Rawhide Shoulderpads
1802 0 Rawhide Tunic
1803 0 Tough Leather Belt
1804 0 Tough Leather Boots
1805 0 Tough Leather Bracers
1806 0 Tough Cloak
1807 0 Tough Leather Gloves
1808 0 Tough Leather Pants
1809 0 Tough Leather Shoulderpads
1810 0 Tough Leather Armor
1811 0 Blunt Claymore
1812 0 Short-handled Battle Axe
1813 0 Chipped Quarterstaff
1814 0 Battered Mallet
1815 0 Ornamental Mace
1816 0 Unbalanced Axe
1817 0 Stock Shortsword
1818 0 Standard Claymore
1819 0 Gouging Pick
1820 0 Wooden Maul
1821 0 Warped Blade
1822 0 Cedar Walking Stick
1823 0 Bludgeoning Cudgel
1824 0 Shiny War Axe
1825 0 Bulky Bludgeon
1826 0 Rock Maul
1827 0 Meat Cleaver
1828 0 Stone War Axe
1829 0 Short Cutlass
1830 0 Long Bastard Sword
1831 0 Oaken War Staff
1832 2 Lucky Trousers
1835 1 Dirty Leather Belt
1836 1 Dirty Leather Bracers
1839 1 Rough Leather Belt
1840 1 Rough Leather Bracers
1843 1 Tanned Leather Belt
1844 1 Tanned Leather Bracers
1845 1 Chainmail Belt
1846 1 Chainmail Bracers
1849 1 Cured Leather Belt
1850 1 Cured Leather Bracers
1852 1 Scalemail Bracers
1853 1 Scalemail Belt
1893 2 Miner's Revenge
1913 1 Studded Blackjack
1917 2 Jeweled Dagger
1925 2 Defias Rapier
1926 2 Weighted Sap
1927 2 Deadmines Cleaver
1928 2 Defias Mage Staff
1929 2 Silk-threaded Trousers
1930 2 Stonemason Cloak
1933 2 Staff of Conjuring
1934 2 Stonemason Trousers
1935 3 Assassin's Blade
1936 2 Goblin Screwdriver
1937 2 Buzz Saw
1938 2 Block Mallet
1943 2 Goblin Mail Leggings
1944 2 Metalworking Gloves
1945 2 Woodworking Gloves
1951 2 Blackwater Cutlass
1955 2 Dragonmaw Chain Boots
1958 2 Petrified Shinbone
1959 2 Cold Iron Pick
1965 1 White Wolf Gloves
1973 3 Orb of Deception
1974 3 Mindthrust Bracers
1975 3 Pysan's Old Greatsword
1976 3 Slaghammer
1978 3 Wolfclaw Gloves
1979 4 Wall of the Dead
1980 4 Underworld Band
1981 4 Icemail Jerkin
1982 4 Nightblade
1986 2 Gutrender
1988 2 Chief Brigadier Gauntlets
1990 2 Ballast Maul
1991 2 Goblin Power Shovel
1992 3 Swampchill Fetish
1993 2 Ogremind Ring
1994 2 Ebonclaw Reaver
1996 2 Voodoo Band
1997 2 Pressed Felt Robe
1998 2 Bloodscalp Channeling Staff
2000 2 Archeus
2011 3 Twisted Sabre
2013 2 Cryptbone Staff
2014 2 Black Metal Greatsword
2015 2 Black Metal War Axe
2016 2 Dusty Chain Armor
2017 2 Glowing Leather Bracers
2018 2 Skeletal Longsword
2020 2 Hollowfang Blade
2021 2 Green Carapace Shield
2024 1 Espadon
2025 1 Bearded Axe
2026 1 Rock Hammer
2027 1 Scimitar
2028 1 Hammer
2029 1 Cleaver
2030 1 Gnarled Staff
2032 2 Gallan Cuffs
2033 2 Ambassador's Boots
2034 2 Scholarly Robes
2035 2 Sword of the Night Sky
2036 2 Dusty Mining Gloves
2037 2 Tunneler's Boots
2039 3 Plains Ring
2040 3 Troll Protector
2041 3 Tunic of Westfall
2042 3 Staff of Westfall
2043 2 Ring of Forlorn Spirits
2044 2 Crescent of Forlorn Spirits
2046 2 Bluegill Kukri
2047 1 Anvilmar Hand Axe
2048 1 Anvilmar Hammer
2054 1 Trogg Hand Axe
2055 1 Small Wooden Hammer
2056 0 The Velvet Hammer
2057 1 Pitted Defias Shortsword
2058 2 Kazon's Maul
2059 3 Sentry Cloak
2064 1 Trogg Club
2065 1 Rockjaw Blade
2066 1 Skull Hatchet
2067 1 Frostbit Staff
2069 1 Black Bear Hide Vest
2072 2 Dwarven Magestaff
2073 2 Dwarven Hatchet
2074 2 Solid Shortblade
2075 2 Priest's Mace
2077 2 Magician Staff
2078 2 Northern Shortsword
2079 2 Sergeant's Warhammer
2080 2 Hillborne Axe
2084 2 Darksteel Bastard Sword
2087 2 Hard Crawler Carapace
2088 2 Long Crawler Limb
2089 2 Scrimshaw Dagger
2092 1 Worn Dagger
2098 3 Double-barreled Shotgun
2099 4 Dwarven Hand Cannon
2100 4 Precisely Calibrated Boomstick
2105 1 Thug Shirt
2108 1 Frostmane Leather Vest
2109 1 Frostmane Chain Vest
2110 1 Light Magesmith Robe
2112 1 Lumberjack Jerkin
2114 1 Snowy Robe
2117 1 Thin Cloth Shoes
2119 1 Thin Cloth Gloves
2120 1 Thin Cloth Pants
2121 1 Thin Cloth Armor
2122 1 Cracked Leather Belt
2123 1 Cracked Leather Boots
2124 1 Cracked Leather Bracers
2125 1 Cracked Leather Gloves
2126 1 Cracked Leather Pants
2127 1 Cracked Leather Vest
2128 1 Scratched Claymore
2129 1 Large Round Shield
2130 1 Club
2131 1 Shortsword
2132 1 Short Staff
2133 1 Small Shield
2134 1 Hand Axe
2137 1 Whittling Knife
2138 0 Sharpened Letter Opener
2139 1 Dirk
2140 2 Carving Knife
2141 1 Cuirboulli Vest
2142 1 Cuirboulli Belt
2143 1 Cuirboulli Boots
2144 1 Cuirboulli Bracers
2145 1 Cuirboulli Gloves
2146 1 Cuirboulli Pants
2148 1 Polished Scale Belt
2149 1 Polished Scale Boots
2150 1 Polished Scale Bracers
2151 1 Polished Scale Gloves
2152 1 Polished Scale Leggings
2153 1 Polished Scale Vest
2156 1 Padded Boots
2158 1 Padded Gloves
2159 1 Padded Pants
2160 1 Padded Armor
2163 4 Shadowblade
2164 4 Gut Ripper
2165 1 Old Blanchy's Blanket
2166 2 Foreman's Leggings
2167 2 Foreman's Gloves
2168 2 Foreman's Boots
2169 1 Buzzer Blade
2172 1 Rustic Belt
2173 1 Old Leather Belt
2175 2 Shadowhide Battle Axe
2186 1 Outfitter Belt
2194 3 Diamond Hammer
2195 1 Anvilmar Knife
2203 2 Brashclaw's Chopper
2204 2 Brashclaw's Skewer
2205 3 Duskbringer
2207 1 Jambiya
2208 1 Poniard
2209 1 Kris
2210 0 Battered Buckler
2211 0 Bent Large Shield
2212 0 Cracked Buckler
2213 0 Worn Large Shield
2214 0 Wooden Buckler
2215 0 Wooden Shield
2216 0 Simple Buckler
2217 0 Rectangular Shield
2218 2 Craftsman's Dagger
2219 0 Small Round Shield
2220 0 Box Shield
2221 0 Targe Shield
2222 0 Tower Shield
2224 1 Militia Dagger
2225 1 Sharp Kitchen Knife
2226 2 Ogremage Staff
2227 2 Heavy Ogre War Axe
2230 2 Gloves of Brawn
2231 2 Inferno Robe
2232 2 Dark Runner Boots
2233 2 Shadow Weaver Leggings
2234 2 Nightwalker Armor
2235 2 Brackclaw
2236 3 Blackfang
2237 1 Patched Pants
2238 1 Urchin's Pants
2240 1 Rugged Cape
2241 2 Desperado Cape
2243 4 Hand of Edward the Odd
2244 4 Krol Blade
2245 4 Helm of Narv
2246 4 Myrmidon's Signet
2249 1 Militia Buckler
2254 2 Icepane Warhammer
2256 3 Skeletal Club
2257 1 Frostmane Staff
2258 1 Frostmane Shortsword
2259 1 Frostmane Club
2260 1 Frostmane Hand Axe
2262 3 Mark of Kern
2263 2 Phytoblade
2264 3 Mantle of Thieves
2265 2 Stonesplinter Axe
2266 2 Stonesplinter Dagger
2267 2 Stonesplinter Mace
2268 1 Stonesplinter Blade
2271 3 Staff of the Blessed Seer
2273 2 Guerrilla Armor
2274 2 Sapper's Gloves
2276 3 Swampwalker Boots
2277 3 Necromancer Leggings
2278 3 Forest Tracker Epaulets
2280 2 Kam's Walking Stick
2281 2 Rodentia Flint Axe
2282 1 Rodentia Shortsword
2283 2 Rat Cloth Belt
2284 2 Rat Cloth Cloak
2291 4 Kang the Decapitator
2292 3 Necrology Robes
2299 3 Burning War Axe
2300 2 Embossed Leather Vest
2302 1 Handstitched Leather Boots
2303 1 Handstitched Leather Pants
2307 1 Fine Leather Boots
2308 2 Fine Leather Cloak
2309 2 Embossed Leather Boots
2310 1 Embossed Leather Cloak
2311 1 White Leather Jerkin
2312 2 Fine Leather Gloves
2314 1 Toughened Leather Armor
2315 1 Dark Leather Boots
2316 1 Dark Leather Cloak
2317 2 Dark Leather Tunic
2326 1 Ivy-weave Bracers
2327 1 Sturdy Leather Bracers
2361 1 Battleworn Hammer
2362 0 Worn Wooden Shield
2364 1 Woven Vest
2366 1 Woven Pants
2367 1 Woven Boots
2369 1 Woven Gloves
2370 1 Battered Leather Harness
2371 1 Battered Leather Belt
2372 1 Battered Leather Pants
2373 1 Battered Leather Boots
2374 1 Battered Leather Bracers
2375 1 Battered Leather Gloves
2376 1 Worn Heater Shield
2377 1 Round Buckler
2379 1 Tarnished Chain Vest
2380 1 Tarnished Chain Belt
2381 1 Tarnished Chain Leggings
2383 1 Tarnished Chain Boots
2384 1 Tarnished Chain Bracers
2385 1 Tarnished Chain Gloves
2386 1 Rusted Chain Vest
2387 1 Rusted Chain Belt
2388 1 Rusted Chain Leggings
2389 1 Rusted Chain Boots
2390 1 Rusted Chain Bracers
2391 1 Rusted Chain Gloves
2392 1 Light Mail Armor
2393 1 Light Mail Belt
2394 1 Light Mail Leggings
2395 1 Light Mail Boots
2396 1 Light Mail Bracers
2397 1 Light Mail Gloves
2398 1 Light Chain Armor
2399 1 Light Chain Belt
2400 1 Light Chain Leggings
2401 1 Light Chain Boots
2402 1 Light Chain Bracers
2403 1 Light Chain Gloves
2410 1 Smoky Torch
2417 1 Augmented Chain Vest
2418 1 Augmented Chain Leggings
2419 1 Augmented Chain Belt
2420 1 Augmented Chain Boots
2421 1 Augmented Chain Bracers
2422 1 Augmented Chain Gloves
2423 1 Brigandine Vest
2424 1 Brigandine Belt
2425 1 Brigandine Leggings
2426 1 Brigandine Boots
2427 1 Brigandine Bracers
2428 1 Brigandine Gloves
2429 1 Russet Vest
2431 1 Russet Pants
2432 1 Russet Boots
2434 1 Russet Gloves
2435 1 Embroidered Armor
2437 1 Embroidered Pants
2438 1 Embroidered Boots
2440 1 Embroidered Gloves
2441 1 Ringed Buckler
2442 1 Reinforced Targe
2443 1 Metal Buckler
2444 1 Ornate Buckler
2445 1 Large Metal Shield
2446 1 Kite Shield
2448 1 Heavy Pavise
2451 1 Crested Heater Shield
2463 1 Studded Doublet
2464 1 Studded Belt
2465 1 Studded Pants
2467 1 Studded Boots
2468 1 Studded Bracers
2469 1 Studded Gloves
2470 1 Reinforced Leather Vest
2471 1 Reinforced Leather Belt
2472 1 Reinforced Leather Pants
2473 1 Reinforced Leather Boots
2474 1 Reinforced Leather Bracers
2475 1 Reinforced Leather Gloves
2479 1 Broad Axe
2480 1 Large Club
2481 1 Peon Sword
2482 1 Inferior Tomahawk
2483 1 Rough Broad Axe
2484 1 Small Knife
2485 1 Splintered Board
2486 1 Large Stone Mace
2487 1 Acolyte Staff
2488 1 Gladius
2489 1 Two-handed Sword
2490 1 Tomahawk
2491 1 Large Axe
2492 1 Cudgel
2493 1 Wooden Mallet
2494 1 Stiletto
2495 1 Walking Stick
2496 1 Raider Shortsword
2497 1 Rusted Claymore
2498 1 Small Tomahawk
2499 1 Double-bladed Axe
2500 1 Light Hammer
2501 1 Wooden Warhammer
2502 1 Scuffed Dagger
2503 1 Adept Short Staff
2504 1 Worn Shortbow
2505 1 Polished Shortbow
2506 1 Hornwood Recurve Bow
2507 1 Laminated Recurve Bow
2508 1 Old Blunderbuss
2509 1 Ornate Blunderbuss
2510 1 Solid Blunderbuss
2511 1 Hunter's Boomstick
2520 1 Broadsword
2521 1 Flamberge
2522 1 Crescent Axe
2523 1 Bullova
2524 1 Truncheon
2525 1 War Hammer
2526 1 Main Gauche
2527 1 Battle Staff
2528 1 Falchion
2529 1 Zweihander
2530 1 Francisca
2531 1 Great Axe
2532 1 Morning Star
2533 1 War Maul
2534 1 Rondel
2535 1 War Staff
2545 2 Malleable Chain Leggings
2546 1 Royal Frostmane Girdle
2547 1 Boar Handler Gloves
2549 3 Staff of the Shade
2562 1 Bouquet of Scarlet Begonias
2564 3 Elven Spirit Claws
2565 3 Rod of Molten Fire
2566 2 Sacrificial Robes
2567 3 Evocator's Blade
2568 1 Brown Linen Vest
2569 1 Linen Boots
2570 1 Linen Cloak
2571 1 Viny Wrappings
2572 2 Red Linen Robe
2575 1 Red Linen Shirt
2576 1 White Linen Shirt
2577 1 Blue Linen Shirt
2578 2 Barbaric Linen Vest
2579 1 Green Linen Shirt
2580 1 Reinforced Linen Cape
2582 1 Green Woolen Vest
2583 2 Woolen Boots
2584 1 Woolen Cape
2585 2 Gray Woolen Robe
2586 1 Gamemaster's Robe
2587 1 Gray Woolen Shirt
2612 1 Plain Robe
2613 1 Double-stitched Robes
2614 1 Robe of Apprenticeship
2615 1 Chromatic Robe
2616 1 Shimmering Silk Robes
2617 1 Burning Robes
2618 1 Silver Dress Robes
2620 2 Augural Shroud
2621 2 Cowl of Necromancy
2622 2 Nimar's Tribal Headdress
2623 2 Holy Diadem
2624 2 Thinking Cap
2632 2 Curved Dagger
2635 0 Loose Chain Belt
2642 0 Loose Chain Boots
2643 0 Loose Chain Bracers
2644 0 Loose Chain Cloak
2645 0 Loose Chain Gloves
2646 0 Loose Chain Pants
2648 0 Loose Chain Vest
2649 0 Flimsy Chain Belt
2650 0 Flimsy Chain Boots
2651 0 Flimsy Chain Bracers
2652 0 Flimsy Chain Cloak
2653 0 Flimsy Chain Gloves
2654 0 Flimsy Chain Pants
2656 0 Flimsy Chain Vest
2664 2 Spinner Fang
2690 1 Latched Belt
2691 1 Outfitter Boots
2694 2 Settler's Leggings
2721 3 Holy Shroud
2754 1 Tarnished Bastard Sword
2763 0 Fisherman Knife
2764 0 Small Dagger
2765 0 Hunting Knife
2766 0 Deft Stiletto
2773 0 Cracked Shortbow
2774 0 Rust-covered Blunderbuss
2777 0 Feeble Shortbow
2778 0 Cheap Blunderbuss
2780 0 Light Hunting Bow
2781 0 Dirty Blunderbuss
2782 0 Mishandled Recurve Bow
2783 0 Shoddy Blunderbuss
2785 0 Stiff Recurve Bow
2786 0 Oiled Blunderbuss
2787 1 Trogg Dagger
2800 3 Black Velvet Robes
2801 4 Blade of Hanna
2802 3 Blazing Emblem
2805 2 Yeti Fur Cloak
2807 3 Guillotine Axe
2808 1 Torch of Flame
2815 3 Curve-bladed Ripper
2816 3 Death Speaker Scepter
2817 2 Soft Leather Tunic
2818 2 Stretched Leather Trousers
2819 2 Cross Dagger
2820 2 Nifty Stopwatch
2821 2 Mo'grosh Masher
2822 2 Mo'grosh Toothpick
2823 2 Mo'grosh Can Opener
2824 4 Hurricane
2825 4 Bow of Searing Arrows
2844 1 Copper Mace
2845 1 Copper Axe
2847 1 Copper Shortsword
2848 1 Bronze Mace
2849 1 Bronze Axe
2850 1 Bronze Shortsword
2851 1 Copper Chain Belt
2852 1 Copper Chain Pants
2853 1 Copper Bracers
2854 1 Runed Copper Bracers
2857 1 Runed Copper Belt
2864 2 Runed Copper Breastplate
2865 2 Rough Bronze Leggings
2866 1 Rough Bronze Cuirass
2867 2 Rough Bronze Bracers
2868 2 Patterned Bronze Bracers
2869 2 Silvered Bronze Breastplate
2870 3 Shining Silver Breastplate
2877 3 Combatant Claymore
2878 3 Bearded Boneaxe
2879 3 Antipodean Rod
2898 1 Mountaineer Chestpiece
2899 2 Wendigo Collar
2900 1 Stone Buckler
2901 1 Mining Pick
2902 2 Cloak of the Faith
2903 2 Daryl's Hunting Bow
2904 2 Daryl's Hunting Rifle
2905 1 Goat Fur Cloak
2906 2 Darkshire Mail Leggings
2907 2 Dwarven Tree Chopper
2908 2 Thornblade
2910 2 Gold Militia Boots
2911 3 Keller's Girdle
2912 3 Claw of the Shadowmancer
2913 2 Silk Mantle of Gamn
2915 4 Taran Icebreaker
2916 2 Gold Lion Shield
2917 2 Tranquil Ring
2919 1 Relic of the Ancients
2920 1 Sacred Relic
2921 1 Blessed Relic
2922 1 Spirit Relic
2923 1 Relic of Righteousness
2933 3 Seal of Wrynn
2941 3 Prison Shank
2942 3 Iron Knuckles
2943 2 Eye of Paleth
2944 2 Cursed Eye of Paleth
2946 1 Balanced Throwing Dagger
2947 1 Small Throwing Knife
2949 2 Mariner Boots
2950 2 Icicle Rod
2951 3 Ring of the Underwood
2953 2 Watch Master's Cloak
2954 2 Night Watch Pantaloons
2955 2 First Mate Hat
2957 2 Journeyman's Vest
2958 2 Journeyman's Pants
2959 1 Journeyman's Boots
2960 1 Journeyman's Gloves
2961 2 Burnt Leather Vest
2962 2 Burnt Leather Breeches
2963 1 Burnt Leather Boots
2964 1 Burnt Leather Gloves
2965 2 Warrior's Tunic
2966 2 Warrior's Pants
2967 1 Warrior's Boots
2968 1 Warrior's Gloves
2969 2 Spellbinder Vest
2970 2 Spellbinder Pants
2971 1 Spellbinder Boots
2972 1 Spellbinder Gloves
2973 2 Hunting Tunic
2974 2 Hunting Pants
2975 1 Hunting Boots
2976 2 Hunting Gloves
2977 2 Veteran Armor
2978 2 Veteran Leggings
2979 1 Veteran Boots
2980 2 Veteran Gloves
2981 2 Seer's Robe
2982 2 Seer's Pants
2983 2 Seer's Boots
2984 2 Seer's Gloves
2985 2 Inscribed Leather Breastplate
2986 2 Inscribed Leather Pants
2987 2 Inscribed Leather Boots
2988 2 Inscribed Leather Gloves
2989 2 Burnished Tunic
2990 2 Burnished Leggings
2991 2 Burnished Boots
2992 2 Burnished Gloves
3000 2 Brood Mother Carapace
3002 1 Relic Horn of Justice
3003 1 Relic of the Eye
3004 1 Relic of the Dead
3005 1 Relic of Truth
3006 1 Holy Relic Shard
3008 1 Wendigo Fur Cloak
3011 2 Feathered Headdress
3018 2 Hide of Lupos
3019 2 Noble's Robe
3020 3 Enduring Cap
3021 3 Ranger Bow
3022 2 Bluegill Breeches
3023 1 Large Bore Blunderbuss
3024 1 BKP 2700 "Enforcer"
3025 1 BKP 42 "Ultra"
3026 1 Reinforced Bow
3027 1 Heavy Recurve Bow
3028 1 Longbow
3036 2 Heavy Shortbow
3037 2 Whipwood Recurve Bow
3039 2 Short Ash Bow
3040 2 Hunter's Muzzle Loader
3041 2 "Mage-Eye" Blunderbuss
3042 2 BKP "Sparrow" Smallbore
3045 2 Lambent Scale Boots
3047 2 Lambent Scale Gloves
3048 2 Lambent Scale Legguards
3049 2 Lambent Scale Breastplate
3053 2 Humbert's Chestpiece
3055 2 Forest Leather Chestpiece
3056 2 Forest Leather Pants
3057 2 Forest Leather Boots
3058 2 Forest Leather Gloves
3065 2 Bright Boots
3066 2 Bright Gloves
3067 2 Bright Pants
3069 2 Bright Robe
3070 1 Ensign Cloak
3071 1 Striking Hatchet
3072 2 Smoldering Robe
3073 2 Smoldering Pants
3074 2 Smoldering Gloves
3075 4 Eye of Flame
3076 2 Smoldering Boots
3078 2 Naga Heartpiercer
3079 2 Skorn's Rifle
3103 2 Coldridge Hammer
3107 1 Keen Throwing Knife
3108 1 Heavy Throwing Dagger
3111 1 Crude Throwing Axe
3131 1 Weighted Throwing Axe
3135 1 Sharp Throwing Axe
3137 1 Deadly Throwing Axe
3151 1 Siege Brigade Vest
3152 1 Driving Gloves
3153 1 Oil-stained Cloak
3154 2 Thelsamar Axe
3158 1 Burnt Hide Bracers
3160 2 Ironplate Buckler
3161 2 Robe of the Keeper
3166 2 Ironheart Chain
3184 2 Hook Dagger
3185 2 Acrobatic Staff
3186 2 Viking Sword
3187 2 Sacrificial Kris
3188 2 Coral Claymore
3189 1 Wood Chopper
3190 1 Beatstick
3191 2 Arced War Axe
3192 2 Short Bastard Sword
3193 2 Oak Mallet
3194 3 Black Malice
3195 2 Barbaric Battle Axe
3196 2 Edged Bastard Sword
3197 2 Stonecutter Claymore
3198 2 Battering Hammer
3199 2 Battle Slayer
3200 1 Burnt Leather Bracers
3201 2 Barbarian War Axe
3202 2 Forest Leather Bracers
3203 3 Dense Triangle Mace
3204 2 Deepwood Bracers
3205 2 Inscribed Leather Bracers
3206 2 Cavalier Two-hander
3207 1 Hunting Bracers
3208 2 Conk Hammer
3209 2 Ancient War Sword
3210 2 Brutal War Axe
3211 2 Burnished Bracers
3212 2 Lambent Scale Bracers
3213 1 Veteran Bracers
3214 1 Warrior's Bracers
3216 1 Warm Winter Robe
3217 2 Foreman Belt
3222 2 Wicked Dagger
3223 2 Frostmane Scepter
3224 1 Silver-lined Bracers
3225 1 Bloodstained Knife
3227 2 Nightbane Staff
3228 3 Jimmied Handcuffs
3229 2 Tarantula Silk Sash
3230 2 Black Wolf Bracers
3231 2 Cutthroat Pauldrons
3235 2 Ring of Scorn
3260 1 Scarlet Initiate Robes
3261 1 Webbed Cloak
3262 1 Putrid Wooden Hammer
3263 1 Webbed Pants
3267 1 Forsaken Shortsword
3268 1 Forsaken Dagger
3269 1 Forsaken Maul
3270 1 Flax Vest
3272 1 Zombie Skin Leggings
3273 1 Rugged Mail Vest
3274 1 Flax Boots
3275 1 Flax Gloves
3276 1 Deathguard Buckler
3277 1 Executor Staff
3278 0 Aura Proc Damage Sword
3279 1 Battle Chain Boots
3280 1 Battle Chain Bracers
3281 1 Battle Chain Gloves
3282 2 Battle Chain Pants
3283 2 Battle Chain Tunic
3284 1 Tribal Boots
3285 1 Tribal Bracers
3286 1 Tribal Gloves
3287 2 Tribal Pants
3288 2 Tribal Vest
3289 1 Ancestral Boots
3290 1 Ancestral Gloves
3291 2 Ancestral Woollies
3292 2 Ancestral Tunic
3293 1 Deadman Cleaver
3294 1 Deadman Club
3295 1 Deadman Blade
3296 1 Deadman Dagger
3302 2 Brackwater Boots
3303 1 Brackwater Bracers
3304 1 Brackwater Gauntlets
3305 2 Brackwater Leggings
3306 2 Brackwater Vest
3307 2 Barbaric Cloth Boots
3308 2 Barbaric Cloth Gloves
3309 2 Barbaric Loincloth
3310 2 Barbaric Cloth Vest
3311 1 Ceremonial Leather Ankleguards
3312 1 Ceremonial Leather Bracers
3313 2 Ceremonial Leather Harness
3314 2 Ceremonial Leather Gloves
3315 2 Ceremonial Leather Loincloth
3319 1 Short Sabre
3320 1 Bonecaster Sash
3321 1 Gray Fur Booties
3322 1 Wispy Cloak
3323 1 Ghostly Bracers
3324 2 Ghostly Mantle
3325 1 Vile Fin Battle Axe
3327 1 Vile Fin Oracle Staff
3328 1 Spider Web Robe
3329 1 Spiked Wooden Plank
3330 2 Dargol's Hauberk
3331 1 Melrache's Cape
3332 1 Perrine's Boots
3334 1 Farmer's Shovel
3335 1 Farmer's Broom
3336 2 Flesh Piercer
3341 2 Gauntlets of Ogre Strength
3342 1 Captain Sander's Shirt
3344 2 Captain Sander's Sash
3345 2 Silk Wizard Hat
3360 1 Stitches' Femur
3363 0 Frayed Belt
3365 0 Frayed Bracers
3370 0 Patchwork Belt
3373 0 Patchwork Bracers
3374 0 Calico Belt
3375 0 Calico Bracers
3376 0 Canvas Belt
3377 0 Canvas Bracers
3378 0 Brocade Belt
3379 0 Brocade Bracers
3380 0 Cross-stitched Belt
3381 0 Cross-stitched Bracers
3392 2 Ringed Helm
3400 2 Lucine Longsword
3413 3 Doomspike
3414 3 Crested Scepter
3415 3 Staff of the Friar
3416 3 Martyr's Chain
3417 3 Onyx Claymore
3419 1 Red Rose
3420 1 Black Rose
3421 1 Simple Wildflowers
3422 1 Beautiful Wildflowers
3423 1 Bouquet of White Roses
3424 1 Bouquet of Black Roses
3426 1 Bold Yellow Shirt
3427 1 Stylish Black Shirt
3428 1 Common Gray Shirt
3429 2 Guardsman Belt
3430 2 Sniper Rifle
3431 2 Bone-studded Leather
3435 1 Zombie Skin Bracers
3437 1 Clasped Belt
3439 1 Zombie Skin Boots
3440 2 Bonecracker
3442 1 Apprentice Sash
3443 1 Ceremonial Tomahawk
3444 1 Tiller's Vest
3445 1 Ceremonial Knife
3446 2 Darkwood Staff
3447 1 Cryptwalker Boots
3449 2 Mystic Shawl
3450 2 Faerleia's Shield
3451 2 Nightglow Concoction
3452 2 Ceranium Rod
3453 1 Quilted Bracers
3454 1 Reconnaissance Boots
3455 1 Deathstalker Shortsword
3457 2 Stamped Trousers
3458 2 Rugged Mail Gloves
3461 2 High Robe of the Adjudicator
3462 2 Talonstrike
3463 2 Silver Star
3469 1 Copper Chain Boots
3471 2 Copper Chain Vest
3472 1 Runed Copper Gauntlets
3473 2 Runed Copper Pants
3474 2 Gemmed Copper Gauntlets
3475 4 Cloak of Flames
3480 1 Rough Bronze Shoulders
3481 2 Silvered Bronze Shoulders
3482 2 Silvered Bronze Boots
3483 2 Silvered Bronze Gauntlets
3484 2 Green Iron Boots
3485 2 Green Iron Gauntlets
3487 2 Heavy Copper Broadsword
3488 2 Copper Battle Axe
3489 2 Thick War Axe
3490 2 Deadly Bronze Poniard
3491 2 Heavy Bronze Mace
3492 2 Mighty Iron Hammer
3493 2 Raptor's End
3511 2 Cloak of the People's Militia
3522 1 Black Night Elf Breastplate
3526 1 Black Night Elf Gloves
3527 1 White Night Elf Breastplate
3529 1 Black Night Elf Helm
3536 1 Demon Hunter Blindfold
3555 2 Robe of Solomon
3556 2 Dread Mage Hat
3558 2 Fen Keeper Robe
3559 2 Night Watch Gauntlets
3560 2 Mantle of Honor
3561 2 Resilient Poncho
3562 2 Belt of Vindication
3563 2 Seafarer's Pantaloons
3565 2 Beerstained Gloves
3566 2 Raptorbane Armor
3567 2 Dwarven Fishing Pole
3569 2 Vicar's Robe
3570 2 Bonegrinding Pestle
3571 2 Trogg Beater
3572 2 Daryl's Shortsword
3578 2 Harvester's Pants
3581 2 Serrated Knife
3582 2 Acidproof Cloak
3583 1 Weathered Belt
3585 2 Camouflaged Tunic
3586 2 Logsplitter
3587 1 Embroidered Belt
3588 1 Embroidered Bracers
3589 1 Heavy Weave Belt
3590 1 Heavy Weave Bracers
3591 1 Padded Belt
3592 1 Padded Bracers
3593 1 Russet Belt
3594 1 Russet Bracers
3595 1 Tattered Cloth Belt
3596 1 Tattered Cloth Bracers
3597 1 Thick Cloth Belt
3598 1 Thick Cloth Bracers
3599 1 Thin Cloth Belt
3600 1 Thin Cloth Bracers
3602 1 Knitted Belt
3603 1 Knitted Bracers
3606 1 Woven Belt
3607 1 Woven Bracers
3641 1 Journeyman's Bracers
3642 1 Ancestral Bracers
3643 1 Spellbinder Bracers
3644 1 Barbaric Cloth Bracers
3645 2 Seer's Cuffs
3647 2 Bright Bracers
3648 1 Warrior's Buckler
3649 1 Tribal Buckler
3650 1 Battle Shield
3651 2 Veteran Shield
3652 2 Hunting Buckler
3653 2 Ceremonial Buckler
3654 2 Brackwater Shield
3655 2 Burnished Shield
3656 2 Lambent Scale Shield
3661 1 Handcrafted Staff
3675 0 Burnt Out Torch
3719 1 Hillman's Cloak
3732 1 Hooded Cowl
3733 2 Orcish War Chain
3738 2 Brewing Rod
3739 2 Skull Ring
3740 2 Decapitating Sword
3741 2 Stomping Boots
3742 2 Bow of Plunder
3743 2 Sentry Buckler
3747 2 Meditative Sash
3748 3 Feline Mantle
3749 2 High Apothecary Cloak
3750 2 Ribbed Breastplate
3751 2 Mercenary Leggings
3752 2 Grunt Vest
3753 2 Shepherd's Girdle
3754 2 Shepherd's Gloves
3755 2 Fish Gutter
3758 2 Crusader Belt
3759 2 Insulated Sage Gloves
3760 2 Band of the Undercity
3761 2 Deadskull Shield
3763 2 Lunar Buckler
3764 2 Mantis Boots
3765 2 Brigand's Pauldrons
3778 0 Taut Compound Bow
3779 0 Hefty War Axe
3780 0 Long-barreled Musket
3781 0 Broad Claymore
3782 0 Large War Club
3783 0 Light Scimitar
3784 0 Metal Stave
3785 0 Keen Axe
3786 0 Shiny Dirk
3787 0 Stone Club
3788 1 Soul Crystal Relic
3789 1 Relic Stone of Piety
3790 1 Consecrated Relic Parchment
3791 1 Relic of the Light
3792 0 Interlaced Belt
3793 0 Interlaced Boots
3794 0 Interlaced Bracers
3795 0 Interlaced Cloak
3796 0 Interlaced Gloves
3797 0 Interlaced Pants
3798 0 Interlaced Shoulderpads
3799 0 Interlaced Vest
3800 0 Hardened Leather Belt
3801 0 Hardened Leather Boots
3802 0 Hardened Leather Bracers
3803 0 Hardened Cloak
3804 0 Hardened Leather Gloves
3805 0 Hardened Leather Pants
3806 0 Hardened Leather Shoulderpads
3807 0 Hardened Leather Tunic
3808 0 Double Mail Belt
3809 0 Double Mail Boots
3810 0 Double Mail Bracers
3811 0 Double-stitched Cloak
3812 0 Double Mail Gloves
3813 0 Double Mail Pants
3814 0 Double Mail Shoulderpads
3815 0 Double Mail Vest
3816 0 Reflective Heater
3817 0 Reinforced Buckler
3822 2 Runic Darkblade
3833 1 Adept's Cloak
3834 1 Sturdy Cloth Trousers
3835 1 Green Iron Bracers
3836 2 Green Iron Helm
3837 2 Golden Scale Coif
3840 2 Green Iron Shoulders
3841 2 Golden Scale Shoulders
3842 2 Green Iron Leggings
3843 2 Golden Scale Leggings
3844 3 Green Iron Hauberk
3845 2 Golden Scale Cuirass
3846 2 Polished Steel Boots
3847 2 Golden Scale Boots
3848 2 Big Bronze Knife
3849 2 Hardened Iron Shortsword
3850 2 Jade Serpentblade
3851 2 Solid Iron Maul
3852 2 Golden Iron Destroyer
3853 2 Moonsteel Broadsword
3854 2 Frost Tiger Blade
3855 2 Massive Iron Axe
3856 2 Shadow Crescent Axe
3889 1 Russet Hat
3890 1 Studded Hat
3891 1 Augmented Chain Helm
3892 1 Embroidered Hat
3893 1 Reinforced Leather Cap
3894 1 Brigandine Helm
3902 2 Staff of Nobles
3935 1 Smotts' Cutlass
3936 0 Crochet Belt
3937 0 Crochet Boots
3938 0 Crochet Bracers
3939 0 Crochet Cloak
3940 0 Crochet Gloves
3941 0 Crochet Pants
3942 0 Crochet Shoulderpads
3943 0 Crochet Vest
3944 0 Twill Belt
3945 0 Twill Boots
3946 0 Twill Bracers
3947 0 Twill Cloak
3948 0 Twill Gloves
3949 0 Twill Pants
3950 0 Twill Shoulderpads
3951 0 Twill Vest
3952 0 Mesh Belt
3953 0 Mesh Boots
3954 0 Mesh Bracers
3955 0 Mesh Cloak
3956 0 Mesh Gloves
3957 0 Mesh Pants
3958 0 Mesh Mantle
3959 0 Mesh Armor
3961 0 Thick Leather Belt
3962 0 Thick Leather Boots
3963 0 Thick Leather Bracers
3964 0 Thick Cloak
3965 0 Thick Leather Gloves
3966 0 Thick Leather Pants
3967 0 Thick Leather Shoulderpads
3968 0 Thick Leather Tunic
3969 0 Smooth Leather Belt
3970 0 Smooth Leather Boots
3971 0 Smooth Leather Bracers
3972 0 Smooth Cloak
3973 0 Smooth Leather Gloves
3974 0 Smooth Leather Pants
3975 0 Smooth Leather Shoulderpads
3976 0 Smooth Leather Armor
3977 0 Strapped Belt
3978 0 Strapped Boots
3979 0 Strapped Bracers
3980 0 Strapped Cloak
3981 0 Strapped Gloves
3982 0 Strapped Pants
3983 0 Strapped Shoulderpads
3984 0 Strapped Armor
3985 2 Monogrammed Sash
3986 0 Protective Pavise
3987 0 Deflecting Tower
3988 0 Plate Wall Shield
3989 0 Blocking Targe
3990 0 Crested Buckler
3991 0 Plated Buckler
3992 0 Laminated Scale Belt
3993 0 Laminated Scale Boots
3994 0 Laminated Scale Bracers
3995 0 Laminated Scale Cloak
3996 0 Laminated Scale Gloves
3997 0 Laminated Scale Pants
3998 0 Laminated Scale Shoulderpads
3999 0 Laminated Scale Armor
4000 0 Overlinked Chain Belt
4001 0 Overlinked Chain Boots
4002 0 Overlinked Chain Bracers
4003 0 Overlinked Chain Cloak
4004 0 Overlinked Chain Gloves
4005 0 Overlinked Chain Pants
4006 0 Overlinked Chain Shoulderpads
4007 0 Overlinked Chain Armor
4008 0 Sterling Chain Belt
4009 0 Sterling Chain Boots
4010 0 Sterling Chain Bracers
4011 0 Sterling Chain Cloak
4012 0 Sterling Chain Gloves
4013 0 Sterling Chain Pants
4014 0 Sterling Chain Shoulderpads
4015 0 Sterling Chain Armor
4017 0 Sharp Shortsword
4018 0 Whetted Claymore
4019 0 Heavy Flint Axe
4020 0 Splintering Battle Axe
4021 0 Blunting Mace
4022 0 Crushing Maul
4023 0 Fine Pointed Dagger
4024 0 Heavy War Staff
4025 0 Balanced Long Bow
4026 0 Sentinel Musket
4030 1 Holy Relic Water
4031 1 Hallowed Relic Charm
4032 1 Radiant Relic Hammer
4033 1 Dawn's Glow
4035 2 Silver-thread Robe
4036 2 Silver-thread Cuffs
4037 2 Silver-thread Pants
4038 2 Nightsky Robe
4039 2 Nightsky Cowl
4040 2 Nightsky Gloves
4041 2 Aurora Cowl
4042 2 Aurora Gloves
4043 2 Aurora Bracers
4044 2 Aurora Pants
4045 2 Mistscape Bracers
4046 2 Mistscape Pants
4047 2 Mistscape Boots
4048 2 Emblazoned Hat
4049 2 Emblazoned Bracers
4050 2 Emblazoned Leggings
4051 2 Emblazoned Boots
4052 2 Insignia Cap
4054 2 Insignia Leggings
4055 2 Insignia Boots
4057 2 Insignia Chestguard
4058 2 Glyphed Breastplate
4059 2 Glyphed Bracers
4060 2 Glyphed Leggings
4061 2 Imperial Leather Bracers
4062 2 Imperial Leather Pants
4063 2 Imperial Leather Gloves
4064 2 Emblazoned Buckler
4065 2 Combat Shield
4066 2 Insignia Buckler
4067 2 Glyphed Buckler
4068 2 Chief Brigadier Shield
4069 2 Blackforge Buckler
4070 2 Jouster's Crest
4071 2 Glimmering Mail Breastplate
4072 2 Glimmering Mail Gauntlets
4073 2 Glimmering Mail Greaves
4074 2 Mail Combat Armor
4075 2 Mail Combat Gauntlets
4076 2 Mail Combat Boots
4077 2 Mail Combat Headguard
4078 2 Chief Brigadier Coif
4079 2 Chief Brigadier Leggings
4080 2 Blackforge Cowl
4082 2 Blackforge Breastplate
4083 2 Blackforge Gauntlets
4084 2 Blackforge Leggings
4086 2 Flash Rifle
4087 2 Trueshot Bow
4088 2 Dreadblade
4089 2 Ricochet Blunderbuss
4090 3 Mug O' Hurt
4091 3 Widowmaker
4107 2 Tiger Hunter Gloves
4108 2 Panther Hunter Leggings
4109 2 Excelsior Boots
4110 2 Master Hunter's Bow
4111 2 Master Hunter's Rifle
4112 2 Choker of the High Shaman
4113 2 Medicine Blanket
4114 2 Darktide Cape
4115 2 Grom'gol Buckler
4116 2 Olmann Sewar
4117 2 Scorching Sash
4118 2 Poobah's Nose Ring
4119 2 Raptor Hunter Tunic
4120 2 Robe of Crystal Waters
4121 2 Gemmed Gloves
4122 2 Bookmaker's Scepter
4123 2 Frost Metal Pauldrons
4124 2 Cap of Harmony
4125 2 Tranquil Orb
4126 2 Guerrilla Cleaver
4127 2 Shrapnel Blaster
4128 2 Silver Spade
4129 2 Collection Plate
4130 2 Smotts' Compass
4131 2 Belt of Corruption
4132 2 Darkspear Armsplints
4133 2 Darkspear Cuffs
4134 2 Nimboya's Mystical Staff
4135 2 Bloodbone Band
4136 2 Darkspear Boots
4137 2 Darkspear Shoes
4138 2 Blackwater Tunic
4139 2 Junglewalker Sandals
4140 2 Palm Frond Mantle
4190 1 Feathered Armor
4194 1 Feathered Bracers
4195 1 Feathered Boots
4196 3 Feathered Mantle
4197 3 Berylline Pads
4237 1 Handstitched Leather Belt
4239 1 Embossed Leather Gloves
4242 2 Embossed Leather Pants
4243 2 Fine Leather Tunic
4244 2 Hillman's Leather Vest
4246 1 Fine Leather Belt
4247 2 Hillman's Leather Gloves
4248 2 Dark Leather Gloves
4249 2 Dark Leather Belt
4250 2 Hillman's Belt
4251 2 Hillman's Shoulders
4252 2 Dark Leather Shoulders
4253 3 Toughened Leather Gloves
4254 2 Barbaric Gloves
4255 2 Green Leather Armor
4256 2 Guardian Armor
4257 2 Green Leather Belt
4258 2 Guardian Belt
4259 2 Green Leather Bracers
4260 2 Guardian Leather Bracers
4261 1 Solliden's Trousers
4262 3 Gem-studded Leather Belt
4263 1 Standard Issue Shield
4264 2 Barbaric Belt
4290 2 Dust Bowl
4302 1 Small Green Dagger
4303 2 Cranial Thumper
4307 1 Heavy Linen Gloves
4308 1 Green Linen Bracers
4309 2 Handstitched Linen Britches
4310 2 Heavy Woolen Gloves
4311 2 Heavy Woolen Cloak
4312 2 Soft-soled Linen Boots
4313 2 Red Woolen Boots
4314 1 Double-stitched Woolen Shoulders
4315 1 Reinforced Woolen Shoulders
4316 2 Heavy Woolen Pants
4317 2 Phoenix Pants
4318 2 Gloves of Meditation
4319 2 Azure Silk Gloves
4320 3 Spidersilk Boots
4321 2 Spider Silk Slippers
4322 2 Enchanter's Cowl
4323 2 Shadow Hood
4324 2 Azure Silk Vest
4325 2 Boots of the Enchanter
4326 2 Long Silken Cloak
4327 3 Icy Cloak
4328 2 Spider Belt
4329 2 Star Belt
4330 1 Stylish Red Shirt
4331 2 Phoenix Gloves
4332 1 Bright Yellow Shirt
4333 1 Dark Silk Shirt
4334 1 Formal White Shirt
4335 1 Rich Purple Silk Shirt
4336 1 Black Swashbuckler's Shirt
4343 1 Brown Linen Pants
4344 1 Brown Linen Shirt
4362 2 Rough Boomstick
4368 2 Flying Tiger Goggles
4369 2 Deadly Blunderbuss
4372 2 Lovingly Crafted Boomstick
4373 2 Shadow Goggles
4379 2 Silver-plated Shotgun
4381 2 Minor Recombobulator
4383 2 Moonsight Rifle
4385 2 Green Tinted Goggles
4393 2 Craftsman's Monocle
4396 1 Mechanical Dragonling
4397 1 Gnomish Cloaking Device
4430 2 Ethereal Talisman
4434 2 Scarecrow Trousers
4436 2 Jewel-encrusted Sash
4437 2 Channeler's Staff
4438 3 Pugilist Bracers
4439 2 Bruiser Club
4443 2 Grim Pauldrons
4444 2 Black Husk Shield
4445 2 Flesh Carver
4446 3 Blackvenom Blade
4447 2 Cloak of Night
4448 2 Husk of Naraxis
4449 2 Naraxis' Fang
4454 3 Talon of Vultros
4455 2 Raptor Hide Harness
4456 2 Raptor Hide Belt
4462 2 Cloak of Rot
4463 2 Beaded Raptor Collar
4464 2 Trouncing Boots
4465 2 Bonefist Gauntlets
4474 2 Ravenwood Bow
4476 2 Beastwalker Robe
4477 2 Nefarious Buckler
4478 2 Iridescent Scale Leggings
4491 1 Goggles of Gem Hunting
4504 2 Dwarven Guard Cloak
4505 2 Swampland Trousers
4507 2 Pit Fighter's Shield
4508 2 Blood-tinged Armor
4509 2 Seawolf Gloves
4511 2 Black Water Hammer
4534 2 Steel-clasped Bracers
4535 2 Ironforge Memorial Ring
4543 2 White Drakeskin Cap
4545 2 Radiant Silver Bracers
4547 2 Gnomish Zapper
4548 2 Servomechanic Sledgehammer
4549 2 Seafire Band
4550 2 Coldwater Ring
4560 1 Fine Scimitar
4561 2 Scalping Tomahawk
4562 2 Severing Axe
4563 1 Billy Club
4564 2 Spiked Club
4565 1 Simple Dagger
4566 2 Sturdy Quarterstaff
4567 2 Merc Sword
4568 2 Grunt Axe
4569 2 Staunch Hammer
4570 2 Birchwood Maul
4571 2 War Knife
4575 2 Medicine Staff
4576 2 Light Bow
4577 2 Compact Shotgun
4614 2 Pendant of Myzrael
4616 1 Ryedol's Lucky Pick
4643 2 Grimsteel Cape
4652 2 Salbac Shield
4653 2 Ironheel Boots
4658 1 Warrior's Cloak
4659 1 Warrior's Girdle
4660 2 Walking Boots
4661 2 Bright Mantle
4662 1 Journeyman's Cloak
4663 1 Journeyman's Belt
4665 1 Burnt Cloak
4666 1 Burnt Leather Belt
4668 1 Battle Chain Cloak
4669 1 Battle Chain Girdle
4671 1 Ancestral Cloak
4672 1 Ancestral Belt
4674 1 Tribal Cloak
4675 1 Tribal Belt
4676 2 Skeletal Gauntlets
4677 1 Veteran Cloak
4678 1 Veteran Girdle
4680 1 Brackwater Cloak
4681 1 Brackwater Girdle
4683 1 Spellbinder Cloak
4684 1 Spellbinder Belt
4686 1 Barbaric Cloth Cloak
4687 1 Barbaric Cloth Belt
4689 1 Hunting Cloak
4690 1 Hunting Belt
4692 1 Ceremonial Cloak
4693 1 Ceremonial Leather Belt
4694 1 Burnished Pauldrons
4695 2 Burnished Cloak
4696 3 Lapidis Tankard of Tidesippe
4697 2 Burnished Girdle
4698 1 Seer's Mantle
4699 2 Seer's Belt
4700 1 Inscribed Leather Spaulders
4701 2 Inscribed Cloak
4705 2 Lambent Scale Pauldrons
4706 2 Lambent Scale Cloak
4707 2 Lambent Scale Girdle
4708 2 Bright Belt
4709 2 Forest Leather Mantle
4710 2 Forest Cloak
4711 2 Glimmering Cloak
4712 2 Glimmering Mail Girdle
4713 2 Silver-thread Cloak
4714 2 Silver-thread Sash
4715 2 Emblazoned Cloak
4716 2 Combat Cloak
4717 2 Mail Combat Belt
4718 2 Nightsky Mantle
4719 2 Nightsky Cloak
4720 2 Nightsky Sash
4721 2 Insignia Mantle
4722 2 Insignia Cloak
4723 2 Humbert's Pants
4724 2 Humbert's Helm
4725 2 Chief Brigadier Pauldrons
4726 2 Chief Brigadier Cloak
4727 2 Chief Brigadier Girdle
4728 1 Twain's Shoulder
4729 2 Aurora Mantle
4731 2 Glyphed Epaulets
4732 2 Glyphed Cloak
4733 2 Blackforge Pauldrons
4734 2 Mistscape Mantle
4735 2 Mistscape Cloak
4736 2 Mistscape Sash
4737 2 Imperial Leather Spaulders
4738 2 Imperial Leather Belt
4741 2 Stromgarde Cavalry Leggings
4743 2 Pulsating Crystalline Shard
4744 2 Arcane Runed Bracers
4745 2 War Rider Bracers
4746 2 Doomsayer's Robe
4763 2 Blackwood Recurve Bow
4765 2 Enamelled Broadsword
4766 2 Feral Blade
4767 2 Coppercloth Gloves
4768 2 Adept's Gloves
4771 2 Harvest Cloak
4772 1 Warm Cloak
4777 2 Ironwood Maul
4778 2 Heavy Spiked Mace
4781 2 Whispering Vest
4782 2 Solstice Robe
4785 2 Brimstone Belt
4786 2 Wise Man's Belt
4788 2 Agile Boots
4789 2 Stable Boots
4790 2 Inferno Cloak
4792 2 Spirit Cloak
4793 2 Sylvan Cloak
4794 2 Wolf Bracers
4795 2 Bear Bracers
4796 2 Owl Bracers
4797 2 Fiery Cloak
4798 2 Heavy Runed Cloak
4799 2 Antiquated Cloak
4800 2 Mighty Chain Pants
4810 2 Boulder Pads
4816 2 Legionnaire's Leggings
4817 2 Blessed Claymore
4818 2 Executioner's Sword
4820 2 Guardian Buckler
4821 2 Bear Buckler
4822 2 Owl's Disk
4824 2 Blurred Axe
4825 2 Callous Axe
4826 2 Marauder Axe
4827 2 Wizard's Belt
4828 2 Nightwind Belt
4829 2 Dreamer's Belt
4830 2 Saber Leggings
4831 2 Stalking Pants
4832 2 Mystic Sarong
4833 2 Glorious Shoulders
4835 2 Elite Shoulders
4836 2 Fireproof Orb
4837 2 Strength of Will
4838 2 Orb of Power
4840 1 Long Bayonet
4854 1 Demon Scarred Cloak
4861 2 Sleek Feathered Tunic
4906 1 Rainwalker Boots
4907 1 Woodland Tunic
4908 1 Nomadic Bracers
4909 2 Kodo Hunter's Leggings
4910 1 Painted Chain Gloves
4911 1 Thick Bark Buckler
4913 1 Painted Chain Belt
4914 1 Battleworn Leather Gloves
4915 1 Soft Wool Boots
4916 1 Soft Wool Vest
4917 1 Battleworn Chain Leggings
4919 1 Soft Wool Belt
4920 1 Battleworn Cape
4921 1 Dust-covered Leggings
4922 1 Jagged Chain Vest
4923 1 Primitive Hatchet
4924 1 Primitive Club
4925 1 Primitive Hand Blade
4928 1 Sandrunner Wristguards
4929 1 Light Scorpid Armor
4931 1 Hickory Shortbow
4932 1 Harpy Wing Clipper
4933 1 Seasoned Fighter's Cloak
4935 1 Wide Metal Girdle
4936 1 Dirt-trodden Boots
4937 1 Charging Buckler
4938 1 Blemished Wooden Staff
4939 2 Steady Bastard Sword
4940 1 Veiled Grips
4942 1 Tiger Hide Boots
4944 1 Handsewn Cloak
4946 1 Lightweight Boots
4947 2 Jagged Dagger
4948 2 Stinging Mace
4949 2 Orcish Cleaver
4951 1 Squealer's Belt
4954 1 Nomadic Belt
4958 1 Sun-beaten Cloak
4959 1 Throwing Tomahawk
4961 1 Dreamwatcher Staff
4962 1 Double-layered Gloves
4963 1 Thunderhorn Cloak
4964 2 Goblin Smasher
4965 1 Bloodhoof Hand Axe
4967 1 Tribal Warrior's Shield
4968 1 Bound Harness
4969 1 Fortified Bindings
4970 1 Rough-hewn Kodo Leggings
4971 2 Skorn's Hammer
4972 1 Cliff Runner Boots
4973 1 Plains Hunter Wristguards
4974 2 Compact Fighting Knife
4975 2 Vigilant Buckler
4976 2 Mistspray Kilt
4977 2 Sword of Hammerfall
4978 2 Ryedol's Hammer
4979 2 Enchanted Stonecloth Bracers
4980 2 Prospector Gloves
4982 0 Ripped Prospector Belt
4983 2 Rock Pulverizer
4984 2 Skull of Impending Doom
4987 2 Dwarf Captain's Sword
4988 2 Burning Obsidian Band
4989 2 Mage Dragon Robe
4990 2 Scorched Bands
4998 2 Blood Ring
4999 2 Azora's Will
5000 2 Coral Band
5001 2 Heart Ring
5002 2 Glowing Green Talisman
5003 2 Crystal Starfire Medallion
5004 2 Mark of the Kirin Tor
5005 2 Emberspark Pendant
5007 2 Band of Thorns
5008 2 Quicksilver Ring
5009 2 Mindbender Loop
5010 2 Inscribed Gold Ring
5011 2 Welken Ring
5016 2 Artisan's Trousers
5028 2 Lord Sakrasis' Scepter
5029 2 Talisman of the Naga Lord
5040 1 Shadow Hunter Knife
5069 2 Fire Wand
5071 2 Shadow Wand
5079 2 Cold Basilisk Eye
5092 1 Charred Razormane Wand
5093 1 Razormane Backstabber
5094 1 Razormane War Shield
5107 1 Deckhand's Shirt
5108 1 Dark Iron Leather
5109 1 Stonesplinter Rags
5110 1 Dalaran Wizard's Robe
5111 2 Rathorian's Cape
5112 2 Ritual Blade
5180 2 Necklace of Harmony
5181 2 Vibrant Silk Cape
5182 2 Shiver Blade
5183 3 Pulsating Hydra Heart
5187 1 Rhahk'Zor's Hammer
5191 3 Cruel Barb
5192 2 Thief's Blade
5193 3 Cape of the Brotherhood
5194 3 Taskmaster Axe
5195 2 Gold-flecked Gloves
5196 2 Smite's Reaver
5197 2 Cookie's Tenderizer
5198 3 Cookie's Stirring Rod
5199 2 Smelting Pants
5200 2 Impaling Harpoon
5201 3 Emberstone Staff
5202 3 Corsair's Overshirt
5207 2 Opaque Wand
5208 1 Smoldering Wand
5209 1 Gloom Wand
5210 1 Burning Wand
5211 1 Dusk Wand
5212 2 Blazing Wand
5213 2 Scorching Wand
5214 2 Wand of Eventide
5215 2 Ember Wand
5216 2 Umbral Wand
5235 1 Alchemist's Wand
5236 1 Combustible Wand
5238 1 Pitchwood Wand
5239 1 Blackbone Wand
5240 2 Torchlight Wand
5241 2 Dwarven Flamestick
5242 2 Cinder Wand
5243 3 Firebelcher
5244 2 Consecrated Wand
5245 2 Summoner's Wand
5246 2 Excavation Rod
5247 2 Rod of Sorrow
5248 2 Flash Wand
5249 2 Burning Sliver
5250 2 Charred Wand
5252 2 Wand of Decay
5253 2 Goblin Igniter
5254 1 Rugged Spaulders
5255 2 Quilboar Tomahawk
5256 2 Kovork's Rattle
5257 3 Dark Hooded Cape
5266 3 Eye of Adaegus
5267 3 Scarlet Kris
5274 2 Rose Mantle
5275 2 Binding Girdle
5279 2 Harpy Skinner
5299 2 Gloves of the Moon
5302 2 Cobalt Buckler
5306 2 Wind Rider Staff
5309 2 Privateer Musket
5310 2 Sea Dog Britches
5311 2 Buckled Boots
5312 2 Riveted Gauntlets
5313 2 Totemic Clan Ring
5314 2 Boar Hunter's Cape
5315 2 Timberland Armguards
5316 2 Barkshell Tunic
5317 2 Dry Moss Tunic
5318 2 Zhovur Axe
5319 1 Bashing Pauldrons
5320 2 Padded Lamellar Boots
5321 2 Elegant Shortsword
5322 2 Demolition Hammer
5323 2 Everglow Lantern
5324 2 Engineer's Hammer
5325 2 Welding Shield
5326 2 Flaring Baton
5327 2 Greasy Tinker's Pants
5328 2 Cinched Belt
5337 2 Wayfaring Gloves
5340 2 Cauldron Stirrer
5341 2 Spore-covered Tunic
5343 2 Barkeeper's Cloak
5344 2 Pointed Axe
5345 2 Stonewood Hammer
5346 2 Orcish Battle Bow
5347 1 Pestilent Wand
5351 2 Bounty Hunter's Ring
5355 2 Beastmaster's Girdle
5356 2 Branding Rod
5357 2 Ward of the Vale
5379 0 Boot Knife
5387 2 Enchanted Moonstalker Cloak
5392 1 Thistlewood Dagger
5393 1 Thistlewood Staff
5394 1 Archery Training Gloves
5395 1 Woodland Shield
5398 1 Canopy Leggings
5399 1 Tracking Boots
5404 1 Serpent's Shoulders
5405 1 Draped Cloak
5419 1 Feral Bracers
5420 2 Banshee Armor
5422 2 Brambleweed Leggings
5423 3 Boahn's Fang
5425 2 Runescale Girdle
5426 3 Serpent's Kiss
5443 3 Gold-plated Buckler
5444 2 Miner's Cape
5458 1 Dirtwood Belt
5459 2 Defender Axe
5516 0 Threshadon Fang
5522 1 Spellstone
5540 2 Pearl-handled Dagger
5541 2 Iridescent Hammer
5542 2 Pearl-clasped Cloak
5579 1 Militia Warhammer
5580 1 Militia Hammer
5581 1 Smooth Walking Staff
5586 1 Thistlewood Blade
5587 2 Thornroot Club
5589 1 Moss-covered Gauntlets
5590 1 Cord Bracers
5591 1 Rain-spotted Cape
5592 1 Shackled Girdle
5593 1 Crag Buckler
5595 1 Thicket Hammer
5596 1 Ashwood Bow
5604 2 Elven Wand
5605 1 Pruning Knife
5606 1 Gardening Gloves
5608 2 Living Cowl
5609 2 Steadfast Cinch
5610 2 Gustweald Cloak
5611 2 Tear of Grief
5612 1 Ivy Cuffs
5613 2 Staff of the Purifier
5614 2 Seraph's Strike
5615 2 Woodsman Sword
5616 3 Gutwrencher
5617 2 Vagabond Leggings
5618 1 Scout's Cloak
5622 2 Clergy Ring
5624 2 Circlet of the Order
5626 2 Skullchipper
5627 2 Relic Blade
5629 2 Hammerfist Gloves
5630 2 Windfelt Gloves
5739 1 Barbaric Harness
5742 2 Gemstone Dagger
5743 2 Prismstone Ring
5744 2 Pale Skinner
5748 2 Centaur Longbow
5749 2 Scythe Axe
5750 2 Warchief's Girdle
5751 2 Webwing Cloak
5752 2 Wyvern Tailspike
5753 2 Ruffled Chaplet
5754 2 Wolfpack Medallion
5755 2 Onyx Shredder Plate
5756 3 Sliverblade
5757 2 Hardwood Cudgel
5761 1 Anvilmar Sledge
5766 2 Lesser Wizard's Robe
5767 1 Violet Robes
5770 2 Robes of Arcana
5776 1 Elder's Cane
5777 1 Brave's Axe
5778 1 Primitive Walking Stick
5779 1 Forsaken Bastard Sword
5780 2 Murloc Scale Belt
5781 2 Murloc Scale Breastplate
5782 2 Thick Murloc Armor
5783 2 Murloc Scale Bracers
5812 2 Robes of Antiquity
5813 2 Emil's Brand
5814 2 Snapbrook Armor
5815 2 Glacial Stone
5817 2 Lunaris Bow
5818 2 Moonbeam Wand
5819 3 Sunblaze Coif
5820 2 Faerie Mantle
5821 2 Darkstalker Boots
5822 2 Hedgeseed Gauntlets
5936 1 Animal Skin Belt
5939 1 Sewing Gloves
5940 1 Bone Buckler
5941 1 Brass Scale Pants
5943 2 Rift Bracers
5944 2 Greaves of the People's Militia
5956 1 Blacksmith Hammer
5957 1 Handstitched Leather Vest
5958 2 Fine Leather Pants
5961 2 Dark Leather Pants
5962 2 Guardian Pants
5963 2 Barbaric Leggings
5964 2 Barbaric Shoulders
5965 2 Guardian Cloak
5966 1 Guardian Gloves
5967 2 Girdle of Nobility
5968 2 Rugged Boots
5969 2 Regent's Cloak
5970 2 Serpent Gloves
5971 2 Feathered Cape
5975 2 Ruffian Belt
5976 1 Guild Tabard
6040 1 Golden Scale Bracers
6058 1 Blackened Leather Belt
6059 1 Nomadic Vest
6060 1 Flax Bracers
6061 1 Graystone Bracers
6062 1 Heavy Cord Bracers
6063 1 Cold Steel Gauntlets
6070 1 Wolfskin Bracers
6076 1 Tapered Pants
6078 1 Pikeman Shield
6084 2 Stormwind Guard Leggings
6085 2 Footman Tunic
6087 3 Chausses of Westfall
6092 2 Black Whelp Boots
6093 2 Orc Crusher
6094 2 Piercing Axe
6095 2 Wandering Boots
6096 1 Apprentice's Shirt
6097 1 Acolyte's Shirt
6098 0 Neophyte's Robe
6116 0 Apprentice's Robe
6117 1 Squire's Shirt
6118 0 Squire's Pants
6119 0 Neophyte's Robe
6120 1 Recruit's Shirt
6121 0 Recruit's Pants
6122 1 Recruit's Boots
6123 0 Novice's Robe
6124 0 Novice's Pants
6125 1 Brawler's Harness
6126 0 Trapper's Pants
6127 1 Trapper's Boots
6129 0 Acolyte's Robe
6130 1 Trapper's Shirt
6131 0 Trapper's Pants
6134 1 Primitive Mantle
6135 0 Primitive Kilt
6136 1 Thug Shirt
6137 0 Thug Pants
6138 1 Thug Boots
6139 0 Novice's Robe
6140 0 Apprentice's Robe
6144 0 Neophyte's Robe
6147 1 Ratty Old Belt
6148 1 Web-covered Boots
6171 1 Wolf Handler Gloves
6173 1 Snow Boots
6174 0 Twain Random Sword
6176 1 Dwarven Kite Shield
6177 1 Ironwrought Bracers
6179 2 Privateer's Cape
6180 2 Slarkskin
6182 1 Dim Torch
6185 1 Bear Shawl
6186 2 Trogg Slicer
6187 2 Dwarven Defender
6188 2 Mud Stompers
6189 1 Durable Chain Shoulders
6191 2 Kimbra Boots
6194 2 Barreling Reaper
6195 2 Wax-polished Armor
6196 0 Noboru's Cudgel
6197 2 Loch Croc Hide Vest
6198 2 Jurassic Wristguards
6199 2 Black Widow Band
6200 2 Garneg's War Belt
6201 1 Lithe Boots
6202 1 Fingerless Gloves
6203 1 Thuggish Shield
6204 2 Tribal Worg Helm
6205 2 Burrowing Shovel
6206 1 Rock Chipper
6214 1 Heavy Copper Maul
6215 2 Balanced Fighting Stick
6219 1 Arclight Spanner
6220 3 Meteor Shard
6223 2 Crest of Darkshire
6226 2 Bloody Apron
6238 2 Brown Linen Robe
6239 2 Red Linen Vest
6240 2 Blue Linen Vest
6241 2 White Linen Robe
6242 2 Blue Linen Robe
6243 2 Green Woolen Robe
6244 1 ggggfg
6256 1 Fishing Pole
6263 2 Blue Overalls
6264 2 Greater Adept's Robe
6266 2 Disciple's Vest
6267 2 Disciple's Pants
6268 2 Pioneer Tunic
6269 2 Pioneer Trousers
6282 2 Sacred Burial Trousers
6292 1 10 Pound Mud Snapper
6294 1 12 Pound Mud Snapper
6295 1 15 Pound Mud Snapper
6309 1 17 Pound Catfish
6310 1 19 Pound Catfish
6311 1 22 Pound Catfish
6314 2 Wolfmaster Cape
6315 2 Steelarrow Crossbow
6318 3 Odo's Ley Staff
6319 2 Girdle of the Blindwatcher
6320 3 Commander's Crest
6321 3 Silverlaine's Family Seal
6323 2 Baron's Scepter
6324 3 Robes of Arugal
6327 3 The Pacifier
6331 3 Howling Blade
6332 3 Black Pearl Ring
6333 2 Spikelash Dagger
6335 2 Grizzled Boots
6336 2 Infantry Tunic
6337 2 Infantry Leggings
6340 2 Fenrus' Hide
6341 2 Eerie Stable Lantern
6350 1 Rough Bronze Boots
6360 2 Steelscale Crushfish
6363 1 26 Pound Catfish
6364 1 32 Pound Catfish
6365 1 Strong Fishing Pole
6366 1 Darkwood Fishing Pole
6367 1 Big Iron Fishing Pole
6378 2 Seer's Cape
6379 2 Inscribed Leather Belt
6380 2 Inscribed Buckler
6381 2 Bright Cloak
6382 2 Forest Leather Belt
6383 2 Forest Buckler
6384 1 Stylish Blue Shirt
6385 1 Stylish Green Shirt
6386 2 Glimmering Mail Legguards
6387 2 Glimmering Mail Bracers
6388 2 Glimmering Mail Pauldrons
6389 2 Glimmering Mail Coif
6392 3 Belt of Arugal
6393 2 Silver-thread Gloves
6394 2 Silver-thread Boots
6395 2 Silver-thread Amice
6396 2 Emblazoned Chestpiece
6397 2 Emblazoned Gloves
6398 2 Emblazoned Belt
6399 2 Emblazoned Shoulders
6400 2 Glimmering Shield
6402 2 Mail Combat Leggings
6403 2 Mail Combat Armguards
6404 2 Mail Combat Spaulders
6405 2 Nightsky Trousers
6406 2 Nightsky Boots
6407 2 Nightsky Wristbands
6408 2 Insignia Gloves
6409 2 Insignia Belt
6410 2 Insignia Bracers
6411 2 Chief Brigadier Armor
6412 2 Chief Brigadier Boots
6413 2 Chief Brigadier Bracers
6414 3 Seal of Sylvanas
6415 2 Aurora Robe
6416 2 Aurora Boots
6417 2 Aurora Cloak
6418 2 Aurora Sash
6419 2 Glyphed Mitts
6420 2 Glyphed Boots
6421 2 Glyphed Belt
6422 2 Glyphed Helm
6423 2 Blackforge Greaves
6424 2 Blackforge Cape
6425 2 Blackforge Girdle
6426 2 Blackforge Bracers
6427 2 Mistscape Robe
6428 2 Mistscape Gloves
6429 2 Mistscape Wizard Hat
6430 2 Imperial Leather Breastplate
6431 2 Imperial Leather Boots
6432 2 Imperial Cloak
6433 2 Imperial Leather Helm
6440 3 Brainlash
6447 1 Worn Turtle Shell Shield
6448 2 Tail Spike
6449 3 Glowing Lizardscale Cloak
6459 2 Savage Trodders
6460 3 Cobrahn's Grasp
6461 3 Slime-encrusted Pads
6463 3 Deep Fathom Ring
6465 2 Robe of the Moccasin
6466 2 Deviate Scale Cloak
6467 2 Deviate Scale Gloves
6468 3 Deviate Scale Belt
6469 3 Venomstrike
6472 3 Stinging Viper
6473 2 Armor of the Fang
6477 2 Grassland Sash
6478 2 Rat Stompers
6480 2 Slick Deviate Leggings
6481 2 Dagmire Gauntlets
6482 2 Firewalker Boots
6502 2 Violet Scale Armor
6503 2 Harlequin Robes
6504 3 Wingblade
6505 3 Crescent Staff
6506 1 Infantry Boots
6507 1 Infantry Bracers
6508 1 Infantry Cloak
6509 1 Infantry Belt
6510 1 Infantry Gauntlets
6511 2 Journeyman's Robe
6512 2 Disciple's Robe
6513 1 Disciple's Sash
6514 1 Disciple's Cloak
6515 1 Disciple's Gloves
6517 1 Pioneer Belt
6518 1 Pioneer Boots
6519 1 Pioneer Bracers
6520 1 Pioneer Cloak
6521 1 Pioneer Gloves
6523 1 Buckled Harness
6524 1 Studded Leather Harness
6525 1 Grunt's Harness
6526 1 Battle Harness
6527 2 Ancestral Robe
6528 2 Spellbinder Robe
6531 2 Barbaric Cloth Robe
6536 2 Willow Vest
6537 2 Willow Boots
6538 2 Willow Robe
6539 2 Willow Belt
6540 2 Willow Pants
6541 2 Willow Gloves
6542 2 Willow Cape
6543 2 Willow Bracers
6545 2 Soldier's Armor
6546 2 Soldier's Leggings
6547 2 Soldier's Gauntlets
6548 2 Soldier's Girdle
6549 1 Soldier's Cloak
6550 2 Soldier's Wristguards
6551 2 Soldier's Boots
6552 2 Bard's Tunic
6553 2 Bard's Trousers
6554 2 Bard's Gloves
6555 1 Bard's Cloak
6556 2 Bard's Bracers
6557 2 Bard's Boots
6558 2 Bard's Belt
6559 2 Bard's Buckler
6560 2 Soldier's Shield
6561 2 Seer's Padded Armor
6562 2 Shimmering Boots
6563 2 Shimmering Bracers
6564 2 Shimmering Cloak
6565 2 Shimmering Gloves
6566 1 Shimmering Amice
6567 2 Shimmering Armor
6568 2 Shimmering Trousers
6569 2 Shimmering Robe
6570 2 Shimmering Sash
6571 2 Scouting Buckler
6572 2 Defender Shield
6573 2 Defender Boots
6574 2 Defender Bracers
6575 2 Defender Cloak
6576 2 Defender Girdle
6577 2 Defender Gauntlets
6578 2 Defender Leggings
6579 1 Defender Spaulders
6580 2 Defender Tunic
6581 2 Scouting Belt
6582 2 Scouting Boots
6583 2 Scouting Bracers
6584 2 Scouting Tunic
6585 2 Scouting Cloak
6586 2 Scouting Gloves
6587 2 Scouting Trousers
6588 1 Scouting Spaulders
6589 2 Viridian Band
6590 2 Battleforge Boots
6591 2 Battleforge Wristguards
6592 2 Battleforge Armor
6593 2 Battleforge Cloak
6594 2 Battleforge Girdle
6595 2 Battleforge Gauntlets
6596 2 Battleforge Legguards
6597 2 Battleforge Shoulderguards
6598 2 Dervish Buckler
6599 2 Battleforge Shield
6600 2 Dervish Belt
6601 2 Dervish Boots
6602 2 Dervish Bracers
6603 2 Dervish Tunic
6604 2 Dervish Cape
6605 2 Dervish Gloves
6607 2 Dervish Leggings
6608 2 Bright Armor
6609 2 Sage's Cloth
6610 2 Sage's Robe
6611 2 Sage's Sash
6612 2 Sage's Boots
6613 2 Sage's Bracers
6614 2 Sage's Cloak
6615 2 Sage's Gloves
6616 2 Sage's Pants
6617 2 Sage's Mantle
6622 3 Sword of Zeal
6627 3 Mutant Scale Breastplate
6628 2 Raven's Claws
6629 2 Sporid Cape
6630 3 Seedcloud Buckler
6631 3 Living Root
6632 2 Feyscale Cloak
6633 2 Butcher's Slicer
6641 2 Haunting Blade
6642 3 Phantom Armor
6651 1 Broken Wine Bottle
6653 1 Torch of the Dormant Flame
6654 1 Torch of the Eternal Flame
6659 2 Scarab Trousers
6660 3 Julie's Dagger
6664 2 Voodoo Mantle
6665 2 Hexed Bracers
6666 2 Dredge Boots
6667 2 Engineer's Cloak
6668 2 Draftsman Boots
6669 2 Sacred Band
6670 2 Panther Armor
6671 2 Juggernaut Leggings
6675 2 Tempered Bracers
6676 2 Constable Buckler
6677 2 Spellcrafter Wand
6678 2 Band of Elven Grace
6679 2 Armor Piercer
6681 1 Thornspike
6682 2 Death Speaker Robes
6685 2 Death Speaker Mantle
6686 2 Tusken Helm
6687 3 Corpsemaker
6688 2 Whisperwind Headdress
6689 3 Wind Spirit Staff
6690 2 Ferine Leggings
6691 3 Swinetusk Shank
6692 3 Pronged Reaver
6693 3 Agamaggan's Clutch
6694 3 Heart of Agamaggan
6695 3 Stygian Bone Amulet
6696 3 Nightstalker Bow
6697 3 Batwing Mantle
6698 6 Stone of Pierce
6707 6 Stone of Lapidis
6708 6 Stone of Goodman
6709 2 Moonglow Vest
6711 6 Stone of Kurtz
6713 1 Ripped Pants
6719 2 Windborne Belt
6720 2 Spirit Hunter Headdress
6721 2 Chestplate of Kor
6722 2 Beastial Manacles
6723 2 Medal of Courage
6724 6 Stone of Backus
6725 3 Marbled Buckler
6726 2 Razzeric's Customized Seatbelt
6727 2 Razzeric's Racing Grips
6728 6 Stone of Brownell
6729 2 Fizzle's Zippy Lighter
6730 2 Ironforge Chain
6731 2 Ironforge Breastplate
6732 2 Gnomish Mechanic's Gloves
6733 2 Ironforge Gauntlets
6737 2 Dryleaf Pants
6738 2 Bleeding Crescent
6739 2 Cliffrunner's Aim
6740 2 Azure Sash
6741 1 Orcish War Sword
6742 3 Stonefist Girdle
6743 2 Sustaining Ring
6744 2 Gloves of Kapelan
6745 2 Swiftrunner Cape
6746 2 Basalt Buckler
6747 2 Enforcer Pauldrons
6748 2 Monkey Ring
6749 2 Tiger Band
6750 2 Snake Hoop
6751 2 Mourning Shawl
6752 2 Lancer Boots
6757 2 Jaina's Signet Ring
6773 2 Gelkis Marauder Chain
6774 2 Uthek's Finger
6780 2 Lilac Sash
6784 2 Braced Handguards
6786 1 Simple Dress
6787 1 White Woolen Dress
6788 2 Magram Hunter's Belt
6789 2 Ceremonial Centaur Blanket
6790 2 Ring of Calm
6791 2 Hellion Boots
6792 2 Sanguine Pauldrons
6793 2 Auric Bracers
6794 2 Stormfire Gauntlets
6795 1 White Swashbuckler's Shirt
6796 1 Red Swashbuckler's Shirt
6797 2 Eyepoker
6798 2 Blasting Hackbut
6801 2 Baroque Apron
6802 3 Sword of Omen
6803 3 Prophetic Cane
6804 2 Windstorm Hammer
6806 2 Dancing Flame
6828 2 Visionary Buckler
6829 3 Sword of Serenity
6830 3 Bonebiter
6831 3 Black Menace
6832 2 Cloak of Blight
6833 1 White Tuxedo Shirt
6834 1 Black Tuxedo
6835 1 Black Tuxedo Pants
6836 1 Dress Shoes
6837 1 Wedding Dress
6898 2 Orb of Soran'ruk
6899 0 Warlock Orb 35
6900 3 Enchanted Gold Bloodrobe
6901 3 Glowing Thresher Cape
6902 2 Bands of Serra'kis
6903 2 Gaze Dreamer Pants
6904 3 Bite of Serra'kis
6905 2 Reef Axe
6906 3 Algae Fists
6907 3 Tortoise Armor
6908 2 Ghamoo-ra's Bind
6909 3 Strike of the Hydra
6910 3 Leech Pants
6911 3 Moss Cinch
6953 3 Verigan's Fist
6966 2 Elunite Axe
6967 2 Elunite Sword
6968 2 Elunite Hammer
6969 2 Elunite Dagger
6970 2 Furen's Favor
6971 2 Fire Hardened Coif
6972 3 Fire Hardened Hauberk
6973 2 Fire Hardened Leggings
6974 2 Fire Hardened Gauntlets
6975 3 Whirlwind Axe
6976 3 Whirlwind Warhammer
6977 3 Whirlwind Sword
6978 2 Umbral Axe
6979 2 Haggard's Axe
6980 2 Haggard's Dagger
6981 2 Umbral Dagger
6982 2 Umbral Mace
6983 2 Haggard's Hammer
6984 2 Umbral Sword
6985 2 Haggard's Sword
6998 2 Nimbus Boots
7000 2 Heartwood Girdle
7001 3 Gravestone Scepter
7002 3 Arctic Buckler
7003 2 Beetle Clasps
7004 2 Prelacy Cape
7005 1 Skinning Knife
7026 1 Linen Belt
7027 2 Boots of Darkness
7046 2 Azure Silk Pants
7047 2 Hands of Darkness
7048 1 Azure Silk Hood
7049 2 Truefaith Gloves
7050 1 Silk Headband
7051 2 Earthen Vest
7052 2 Azure Silk Belt
7053 2 Azure Silk Cloak
7054 3 Robe of Power
7055 2 Crimson Silk Belt
7056 2 Crimson Silk Cloak
7057 2 Green Silken Shoulders
7058 1 Crimson Silk Vest
7059 2 Crimson Silk Shoulders
7060 2 Azure Shoulders
7061 2 Earthen Silk Belt
7062 1 Crimson Silk Pantaloons
7063 2 Crimson Silk Robe
7064 2 Crimson Silk Gloves
7065 2 Green Silk Armor
7094 1 Driftwood Branch
7095 1 Bog Boots
7106 2 Zodiac Gloves
7107 2 Belt of the Stars
7108 2 Infantry Shield
7109 1 Pioneer Buckler
7110 2 Silver-thread Armor
7111 2 Nightsky Armor
7112 2 Aurora Armor
7113 2 Mistscape Armor
7115 2 Heirloom Axe
7116 2 Heirloom Dagger
7117 2 Heirloom Hammer
7118 2 Heirloom Sword
7120 2 Ruga's Bulwark
7129 2 Brutal Gauntlets
7130 2 Brutal Helm
7132 2 Brutal Legguards
7133 3 Brutal Hauberk
7148 1 Goblin Jumper Cables
7166 1 Copper Dagger
7187 2 VanCleef's Boots
7188 2 Stormwind Guard Shield
7189 2 Goblin Rocket Boots
7229 2 Explorer's Vest
7230 3 Smite's Mighty Hammer
7276 1 Handstitched Leather Cloak
7277 1 Handstitched Leather Bracers
7280 2 Rugged Leather Pants
7281 1 Light Leather Bracers
7282 2 Light Leather Pants
7283 2 Black Whelp Cloak
7284 2 Red Whelp Gloves
7285 2 Nimble Leather Gloves
7297 1 Morbent's Bane
7298 2 Blade of Cunning
7326 2 Thun'grim's Axe
7327 2 Thun'grim's Dagger
7328 2 Thun'grim's Mace
7329 2 Thun'grim's Sword
7330 2 Infiltrator Buckler
7331 2 Phalanx Shield
7332 2 Regal Armor
7334 2 Efflorescent Robe
7335 2 Grizzly Tunic
7336 2 Wildwood Chain
7337 1 The Rock
7338 1 Mood Ring
7339 1 Miniscule Diamond Ring
7340 1 Flawless Diamond Solitaire
7341 1 Cubic Zirconia Ring
7342 1 Silver Piffeny Band
7344 2 Torch of Holy Flame
7348 2 Fletcher's Gloves
7349 2 Herbalist's Gloves
7350 1 Disciple's Bracers
7351 1 Disciple's Boots
7352 2 Earthen Leather Shoulders
7353 2 Elder's Padded Armor
7354 2 Elder's Boots
7355 2 Elder's Bracers
7356 2 Elder's Cloak
7357 2 Elder's Hat
7358 2 Pilferer's Gloves
7359 2 Heavy Earthen Gloves
7366 2 Elder's Gloves
7367 2 Elder's Mantle
7368 2 Elder's Pants
7369 2 Elder's Robe
7370 2 Elder's Sash
7373 2 Dusky Leather Leggings
7374 2 Dusky Leather Armor
7375 2 Green Whelp Armor
7377 2 Frost Leather Cloak
7378 2 Dusky Bracers
7386 2 Green Whelp Bracers
7387 2 Dusky Belt
7390 2 Dusky Boots
7391 2 Swift Boots
7406 2 Infiltrator Cord
7407 2 Infiltrator Armor
7408 2 Infiltrator Shoulders
7409 2 Infiltrator Boots
7410 2 Infiltrator Bracers
7411 2 Infiltrator Cloak
7412 2 Infiltrator Gloves
7413 2 Infiltrator Cap
7414 2 Infiltrator Pants
7415 2 Dervish Spaulders
7416 2 Phalanx Bracers
7417 2 Phalanx Boots
7418 2 Phalanx Breastplate
7419 2 Phalanx Cloak
7420 2 Phalanx Headguard
7421 2 Phalanx Gauntlets
7422 2 Phalanx Girdle
7423 2 Phalanx Leggings
7424 2 Phalanx Spaulders
7426 2 Cerulean Ring
7427 2 Cerulean Talisman
7429 2 Twilight Armor
7430 2 Twilight Robe
7431 2 Twilight Pants
7432 2 Twilight Cowl
7433 2 Twilight Gloves
7434 2 Twilight Boots
7435 2 Twilight Mantle
7436 2 Twilight Cape
7437 2 Twilight Cuffs
7438 2 Twilight Belt
7439 2 Sentinel Breastplate
7440 2 Sentinel Trousers
7441 2 Sentinel Cap
7443 2 Sentinel Gloves
7444 2 Sentinel Boots
7445 2 Sentinel Shoulders
7446 2 Sentinel Cloak
7447 2 Sentinel Bracers
7448 2 Sentinel Girdle
7454 2 Knight's Breastplate
7455 2 Knight's Legguards
7456 2 Knight's Headguard
7457 2 Knight's Gauntlets
7458 2 Knight's Boots
7459 2 Knight's Pauldrons
7460 2 Knight's Cloak
7461 2 Knight's Bracers
7462 2 Knight's Girdle
7463 2 Sentinel Buckler
7465 2 Knight's Crest
7466 2 Vermilion Band
7467 2 Vermilion Necklace
7468 2 Regal Robe
7469 2 Regal Leggings
7470 2 Regal Wizard Hat
7471 2 Regal Gloves
7472 2 Regal Boots
7473 2 Regal Mantle
7474 2 Regal Cloak
7475 2 Regal Cuffs
7476 2 Regal Sash
7477 2 Ranger Tunic
7478 2 Ranger Leggings
7479 2 Ranger Helm
7480 2 Ranger Gloves
7481 2 Ranger Boots
7482 2 Ranger Shoulders
7483 2 Ranger Cloak
7484 2 Ranger Wristguards
7485 2 Ranger Cord
7486 2 Captain's Breastplate
7487 2 Captain's Leggings
7488 2 Captain's Circlet
7489 2 Captain's Gauntlets
7490 2 Captain's Boots
7491 2 Captain's Shoulderguards
7492 2 Captain's Cloak
7493 2 Captain's Bracers
7494 2 Captain's Waistguard
7495 2 Captain's Buckler
7496 2 Field Plate Shield
7497 2 Ivory Band
7506 2 Gnomish Universal Remote
7507 2 Arcane Orb
7508 2 Ley Orb
7509 2 Manaweave Robe
7510 2 Lesser Spellfire Robes
7511 2 Astral Knot Robe
7512 2 Nether-lace Robe
7513 3 Ragefire Wand
7514 3 Icefury Wand
7515 3 Celestial Orb
7517 2 Gossamer Tunic
7518 2 Gossamer Robe
7519 2 Gossamer Pants
7520 2 Gossamer Headpiece
7521 2 Gossamer Gloves
7522 2 Gossamer Boots
7523 2 Gossamer Shoulderpads
7524 2 Gossamer Cape
7525 2 Gossamer Bracers
7526 2 Gossamer Belt
7527 2 Cabalist Chestpiece
7528 2 Cabalist Leggings
7529 2 Cabalist Helm
7530 2 Cabalist Gloves
7531 2 Cabalist Boots
7532 2 Cabalist Spaulders
7533 2 Cabalist Cloak
7534 2 Cabalist Bracers
7535 2 Cabalist Belt
7536 2 Champion's Wall Shield
7537 2 Gothic Shield
7538 2 Champion's Armor
7539 2 Champion's Leggings
7540 2 Champion's Helmet
7541 2 Champion's Gauntlets
7542 2 Champion's Greaves
7543 2 Champion's Pauldrons
7544 2 Champion's Cape
7545 2 Champion's Bracers
7546 2 Champion's Girdle
7547 2 Onyx Ring
7548 2 Onyx Choker
7549 2 Fairy's Embrace
7550 2 Warrior's Honor
7551 2 Entwined Opaline Talisman
7552 2 Falcon's Hook
7553 2 Band of the Unicorn
7554 2 Willow Branch
7555 2 Regal Star
7556 2 Twilight Orb
7557 2 Gossamer Rod
7558 2 Shimmering Stave
7559 2 Runic Cane
7606 2 Polar Gauntlets
7607 2 Sable Wand
7608 2 Seer's Fine Stein
7609 2 Elder's Amber Stave
7610 2 Aurora Sphere
7611 2 Mistscape Stave
7673 3 Talvash's Enhancing Necklace
7682 3 Torturing Poker
7683 1 Bloody Brass Knuckles
7684 2 Bloodmage Mantle
7685 3 Orb of the Forgotten Seer
7686 3 Ironspine's Eye
7687 3 Ironspine's Fist
7688 3 Ironspine's Ribcage
7689 3 Morbid Dawn
7690 3 Ebon Vise
7691 3 Embalmed Shroud
7708 3 Necrotic Wand
7709 3 Blighted Leggings
7710 3 Loksey's Training Stick
7711 2 Robe of Doan
7712 2 Mantle of Doan
7713 3 Illusionary Rod
7714 3 Hypnotic Blade
7717 3 Ravager
7718 3 Herod's Shoulder
7719 3 Raging Berserker's Helm
7720 3 Whitemane's Chapeau
7721 3 Hand of Righteousness
7722 3 Triune Amulet
7723 3 Mograine's Might
7724 3 Gauntlets of Divinity
7726 3 Aegis of the Scarlet Commander
7727 3 Watchman Pauldrons
7728 3 Beguiler Robes
7729 3 Chesterfall Musket
7730 3 Cobalt Crusher
7731 3 Ghostshard Talisman
7734 3 Six Demon Bag
7736 3 Fight Club
7738 2 Evergreen Gloves
7739 2 Timberland Cape
7746 2 Explorers' League Commendation
7747 2 Vile Protector
7748 2 Forcestone Buckler
7749 2 Omega Orb
7750 2 Mantle of Woe
7751 2 Vorrel's Boots
7752 3 Dreamslayer
7753 3 Bloodspiller
7754 3 Harbinger Boots
7755 3 Flintrock Shoulders
7756 2 Dog Training Gloves
7757 3 Windweaver Staff
7758 3 Ruthless Shiv
7759 3 Archon Chestpiece
7760 3 Warchief Kilt
7761 3 Steelclaw Reaver
7786 3 Headsplitter
7787 3 Resplendent Guardian
7809 1 Easter Dress
7888 3 Jarkal's Enhancing Necklace
7913 2 Barbaric Iron Shoulders
7914 2 Barbaric Iron Breastplate
7915 2 Barbaric Iron Helm
7916 2 Barbaric Iron Boots
7917 2 Barbaric Iron Gloves
7918 2 Heavy Mithril Shoulder
7919 2 Heavy Mithril Gauntlet
7920 2 Mithril Scale Pants
7921 2 Heavy Mithril Pants
7922 1 Steel Plate Helm
7924 2 Mithril Scale Bracers
7925 2 Mithril Scale Gloves
7926 2 Ornate Mithril Pants
7927 2 Ornate Mithril Gloves
7928 2 Ornate Mithril Shoulder
7929 2 Orcish War Leggings
7930 2 Heavy Mithril Breastplate
7931 2 Mithril Coif
7932 2 Mithril Scale Shoulders
7933 2 Heavy Mithril Boots
7934 2 Heavy Mithril Helm
7935 2 Ornate Mithril Breastplate
7936 2 Ornate Mithril Boots
7937 2 Ornate Mithril Helm
7938 3 Truesilver Gauntlets
7939 3 Truesilver Breastplate
7941 2 Heavy Mithril Axe
7942 2 Blue Glittering Axe
7943 2 Wicked Mithril Blade
7944 2 Dazzling Mithril Rapier
7945 2 Big Black Mace
7946 2 Runed Mithril Hammer
7947 2 Ebon Shiv
7948 2 Girdle of Thero-shan
7949 2 Leggings of Thero-shan
7950 2 Armor of Thero-shan
7951 2 Hands of Thero-shan
7952 2 Boots of Thero-shan
7953 2 Mask of Thero-shan
7954 3 The Shatterer
7955 1 Copper Claymore
7956 1 Bronze Warhammer
7957 1 Bronze Greatsword
7958 1 Bronze Battle Axe
7959 3 Blight
7960 3 Truesilver Champion
7961 3 Phantom Blade
7963 2 Steel Breastplate
7996 1 Worn Fishing Hat
7997 0 Red Defias Mask
8006 3 The Ziggler
8071 2 Sizzle Stick
8080 0 Light Plate Chestpiece
8081 0 Light Plate Belt
8082 0 Light Plate Boots
8083 0 Light Plate Bracers
8084 0 Light Plate Gloves
8085 0 Light Plate Pants
8086 0 Light Plate Shoulderpads
8088 1 Platemail Belt
8089 1 Platemail Boots
8090 1 Platemail Bracers
8091 1 Platemail Gloves
8092 1 Platemail Helm
8093 1 Platemail Leggings
8094 1 Platemail Armor
8106 2 Hibernal Armor
8107 2 Hibernal Boots
8108 2 Hibernal Bracers
8109 2 Hibernal Cloak
8110 2 Hibernal Gloves
8111 2 Hibernal Mantle
8112 2 Hibernal Pants
8113 2 Hibernal Robe
8114 2 Hibernal Sash
8115 2 Hibernal Cowl
8116 2 Heraldic Belt
8117 2 Heraldic Boots
8118 2 Heraldic Bracers
8119 2 Heraldic Breastplate
8120 2 Heraldic Cloak
8121 2 Heraldic Gloves
8122 2 Heraldic Headpiece
8123 2 Heraldic Leggings
8124 2 Heraldic Spaulders
8125 2 Myrmidon's Bracers
8126 2 Myrmidon's Breastplate
8127 2 Myrmidon's Cape
8128 2 Myrmidon's Gauntlets
8129 2 Myrmidon's Girdle
8130 2 Myrmidon's Greaves
8131 2 Myrmidon's Helm
8132 2 Myrmidon's Leggings
8133 2 Myrmidon's Pauldrons
8134 2 Myrmidon's Defender
8135 2 Chromite Shield
8137 2 Chromite Bracers
8138 2 Chromite Chestplate
8139 2 Chromite Gauntlets
8140 2 Chromite Girdle
8141 2 Chromite Greaves
8142 2 Chromite Barbute
8143 2 Chromite Legplates
8144 2 Chromite Pauldrons
8156 2 Jouster's Wristguards
8157 2 Jouster's Chestplate
8158 2 Jouster's Gauntlets
8159 2 Jouster's Girdle
8160 2 Jouster's Greaves
8161 2 Jouster's Visor
8162 2 Jouster's Legplates
8163 2 Jouster's Pauldrons
8174 2 Comfortable Leather Hat
8175 2 Nightscape Tunic
8176 2 Nightscape Headband
8177 1 Practice Sword
8178 2 Training Sword
8179 1 Cadet's Bow
8180 2 Hunting Bow
8181 1 Hunting Rifle
8182 1 Pellet Rifle
8183 2 Precision Bow
8184 2 Firestarter
8185 2 Turtle Scale Leggings
8186 2 Dire Wand
8187 2 Turtle Scale Gloves
8188 2 Explosive Shotgun
8189 2 Turtle Scale Breastplate
8190 3 Hanzo Sword
8191 2 Turtle Scale Helm
8192 2 Nightscape Shoulders
8193 2 Nightscape Pants
8194 2 Goblin Nutcracker
8195 2 Nightscape Cloak
8196 2 Ebon Scimitar
8197 2 Nightscape Boots
8198 2 Turtle Scale Bracers
8199 2 Battlefield Destroyer
8200 2 Big Voodoo Robe
8201 2 Big Voodoo Mask
8202 2 Big Voodoo Pants
8203 2 Tough Scorpid Breastplate
8204 2 Tough Scorpid Gloves
8205 2 Tough Scorpid Bracers
8206 2 Tough Scorpid Leggings
8207 2 Tough Scorpid Shoulders
8208 2 Tough Scorpid Helm
8209 2 Tough Scorpid Boots
8210 2 Wild Leather Shoulders
8211 2 Wild Leather Vest
8212 2 Wild Leather Leggings
8213 2 Wild Leather Boots
8214 2 Wild Leather Helmet
8215 2 Wild Leather Cloak
8216 2 Big Voodoo Cloak
8223 3 Blade of the Basilisk
8224 2 Silithid Ripper
8225 3 Tainted Pierce
8226 3 The Butcher
8245 2 Imperial Red Tunic
8246 2 Imperial Red Boots
8247 2 Imperial Red Bracers
8248 2 Imperial Red Cloak
8249 2 Imperial Red Gloves
8250 2 Imperial Red Mantle
8251 2 Imperial Red Pants
8252 2 Imperial Red Robe
8253 2 Imperial Red Sash
8254 2 Imperial Red Circlet
8255 2 Serpentskin Girdle
8256 2 Serpentskin Boots
8257 2 Serpentskin Bracers
8258 2 Serpentskin Armor
8259 2 Serpentskin Cloak
8260 2 Serpentskin Gloves
8261 2 Serpentskin Helm
8262 2 Serpentskin Leggings
8263 2 Serpentskin Spaulders
8264 2 Ebonhold Wristguards
8265 2 Ebonhold Armor
8266 2 Ebonhold Cloak
8267 2 Ebonhold Gauntlets
8268 2 Ebonhold Girdle
8269 2 Ebonhold Boots
8270 2 Ebonhold Helmet
8271 2 Ebonhold Leggings
8272 2 Ebonhold Shoulderpads
8273 2 Valorous Wristguards
8274 2 Valorous Chestguard
8275 2 Ebonhold Buckler
8276 2 Valorous Gauntlets
8277 2 Valorous Girdle
8278 2 Valorous Greaves
8279 2 Valorous Helm
8280 2 Valorous Legguards
8281 2 Valorous Pauldrons
8282 2 Valorous Shield
8283 2 Arcane Armor
8284 2 Arcane Boots
8285 2 Arcane Bands
8286 2 Arcane Cloak
8287 2 Arcane Gloves
8288 2 Arcane Pads
8289 2 Arcane Leggings
8290 2 Arcane Robe
8291 2 Arcane Sash
8292 2 Arcane Cover
8293 2 Traveler's Belt
8294 2 Traveler's Boots
8295 2 Traveler's Bracers
8296 2 Traveler's Jerkin
8297 2 Traveler's Cloak
8298 2 Traveler's Gloves
8299 2 Traveler's Helm
8300 2 Traveler's Leggings
8301 2 Traveler's Spaulders
8302 2 Hero's Bracers
8303 2 Hero's Breastplate
8304 2 Hero's Cape
8305 2 Hero's Gauntlets
8306 2 Hero's Belt
8307 2 Hero's Boots
8308 2 Hero's Band
8309 2 Hero's Leggings
8310 2 Hero's Pauldrons
8311 2 Alabaster Plate Vambraces
8312 2 Alabaster Breastplate
8313 2 Hero's Buckler
8314 2 Alabaster Plate Gauntlets
8315 2 Alabaster Plate Girdle
8316 2 Alabaster Plate Greaves
8317 2 Alabaster Plate Helmet
8318 2 Alabaster Plate Leggings
8319 2 Alabaster Plate Pauldrons
8320 2 Alabaster Shield
8345 3 Wolfshead Helm
8346 3 Gauntlets of the Sea
8347 3 Dragonscale Gauntlets
8348 3 Helm of Fire
8349 3 Feathered Breastplate
8350 2 The 1 Ring
8367 3 Dragonscale Breastplate
8624 1 Red Sparkler
8625 1 White Sparkler
8626 1 Blue Sparkler
8663 2 Mithril Insignia
8703 2 Signet of Expertise
8708 4 Hammer of Expertise
8746 0 Interlaced Cowl
8747 0 Hardened Leather Helm
8748 0 Double Mail Coif
8749 0 Crochet Hat
8750 0 Thick Leather Hat
8751 0 Overlinked Coif
8752 0 Laminated Scale Circlet
8753 0 Smooth Leather Helmet
8754 0 Twill Cover
8755 0 Light Plate Helmet
9243 2 Shriveled Heart
9285 2 Field Plate Vambraces
9286 2 Field Plate Armor
9287 2 Field Plate Gauntlets
9288 2 Field Plate Girdle
9289 2 Field Plate Boots
9290 2 Field Plate Helmet
9291 2 Field Plate Leggings
9292 2 Field Plate Pauldrons
9333 0 Tarnished Silver Necklace
9359 3 Southsea Lamp
9362 2 Brilliant Gold Ring
9366 2 Golden Scale Gauntlets
9372 4 Sul'thraze the Lasher
9375 3 Expert Goldminer's Helmet
9378 3 Shovelphlange's Mining Axe
9379 3 Sang'thraze the Deflector
9380 3 Jang'thraze the Protector
9381 3 Earthen Rod
9382 2 Tromping Miner's Boots
9383 3 Obsidian Cleaver
9384 3 Stonevault Shiv
9385 3 Archaic Defender
9386 3 Excavator's Brand
9387 2 Revelosh's Boots
9388 2 Revelosh's Armguards
9389 2 Revelosh's Spaulders
9390 2 Revelosh's Gloves
9391 3 The Shoveler
9392 3 Annealed Blade
9393 3 Beacon of Hope
9394 3 Horned Viking Helmet
9395 3 Gloves of Old
9396 3 Legguards of the Vault
9397 3 Energy Cloak
9398 2 Worn Running Boots
9400 1 Baelog's Shortbow
9401 3 Nordic Longshank
9402 3 Earthborn Kilt
9403 1 Battered Viking Shield
9404 3 Olaf's All Purpose Shield
9405 3 Girdle of Golem Strength
9406 3 Spirewind Fetter
9407 3 Stoneweaver Leggings
9408 3 Ironshod Bludgeon
9409 3 Ironaya's Bracers
9410 3 Cragfists
9411 2 Rockshard Pauldrons
9412 3 Galgann's Fireblaster
9413 3 The Rockpounder
9414 2 Oilskin Leggings
9415 3 Grimlok's Tribal Vestments
9416 3 Grimlok's Charge
9417 3 Archaedic Shard
9418 3 Stoneslayer
9419 2 Galgann's Firehammer
9420 3 Adventurer's Pith Helmet
9422 3 Shadowforge Bushmaster
9423 3 The Jackhammer
9424 3 Ginn-su Sword
9425 3 Pendulum of Doom
9426 3 Monolithic Bow
9427 3 Stonevault Bonebreaker
9428 3 Unearthed Bands
9429 3 Miner's Hat of the Deep
9430 3 Spaulders of a Lost Age
9431 3 Papal Fez
9432 3 Skullplate Bracers
9433 3 Forgotten Wraps
9434 3 Elemental Raiment
9435 3 Reticulated Bone Gauntlets
9444 1 Techbot CPU Shell
9445 3 Grubbis Paws
9446 3 Electrocutioner Leg
9447 3 Electrocutioner Lagnut
9448 2 Spidertank Oilrag
9449 3 Manual Crowd Pummeler
9450 2 Gnomebot Operating Boots
9452 3 Hydrocane
9453 3 Toxic Revenger
9454 3 Acidic Walkers
9455 3 Emissary Cuffs
9456 3 Glass Shooter
9457 3 Royal Diplomatic Scepter
9458 3 Thermaplugg's Central Core
9459 3 Thermaplugg's Left Arm
9461 3 Charged Gear
9465 3 Digmaster 5000
9467 2 Gahz'rilla Fang
9469 3 Gahz'rilla Scale Armor
9470 3 Bad Mojo Mask
9473 3 Jinxed Hoodoo Skin
9474 3 Jinxed Hoodoo Kilt
9475 3 Diabolic Skiver
9476 3 Big Bad Pauldrons
9477 3 The Chief's Enforcer
9478 3 Ripsaw
9479 3 Embrace of the Lycan
9480 3 Eyegouger
9481 3 The Minotaur
9482 3 Witch Doctor's Cane
9483 3 Flaming Incinerator
9484 3 Spellshock Leggings
9485 3 Vibroblade
9486 3 Supercharger Battle Axe
9487 3 Hi-tech Supergun
9488 3 Oscillating Power Hammer
9489 2 Gyromatic Icemaker
9490 3 Gizmotron Megachopper
9491 3 Hotshot Pilot's Gloves
9492 3 Electromagnetic Gigaflux Reactivator
9508 3 Mechbuilder's Overalls
9509 3 Petrolspill Leggings
9510 3 Caverndeep Trudgers
9511 3 Bloodletter Scalpel
9512 3 Blackmetal Cape
9513 2 Ley Staff
9514 2 Arcane Staff
9515 2 Nether-lace Tunic
9516 2 Astral Knot Blouse
9517 3 Celestial Stave
9518 2 Mud's Crushers
9519 2 Durtfeet Stompers
9520 2 Silent Hunter
9521 2 Skullsplitter
9522 2 Energized Stone Circle
9527 2 Spellshifter Rod
9531 2 Gemshale Pauldrons
9533 3 Masons Fraternity Ring
9534 3 Engineer's Guild Headpiece
9535 2 Fire-welded Bracers
9536 2 Fairywing Mantle
9538 3 Talvash's Gold Ring
9588 3 Nogg's Gold Ring
9598 2 Sleeping Robes
9599 2 Barkmail Leggings
9600 1 Lace Pants
9601 1 Cushioned Boots
9602 2 Brushwood Blade
9603 2 Gritroot Staff
9604 2 Mechanic's Pipehammer
9605 2 Repairman's Cape
9607 2 Bastion of Stormwind
9608 2 Shoni's Disarming Tool
9609 2 Shilly Mitts
9622 2 Reedknot Ring
9623 3 Civinad Robes
9624 3 Triprunner Dungarees
9625 3 Dual Reinforced Leggings
9626 2 Dwarven Charge
9627 2 Explorer's League Lodestar
9630 2 Pratt's Handcrafted Boots
9631 2 Pratt's Handcrafted Gloves
9632 2 Jangdor's Handcrafted Gloves
9633 2 Jangdor's Handcrafted Boots
9634 2 Skilled Handling Gloves
9635 2 Master Apothecary Cape
9636 2 Swashbuckler Sash
9637 2 Shinkicker Boots
9638 2 Chelonian Cuffs
9639 3 The Hand of Antu'sul
9640 3 Vice Grips
9641 3 Lifeblood Amulet
9642 2 Band of the Great Tortoise
9643 2 Optomatic Deflector
9644 2 Thermotastic Egg Timer
9645 2 Gnomish Inventor Boots
9646 2 Gnomish Water Sinking Device
9647 2 Failed Flying Experiment
9648 2 Chainlink Towel
9649 2 Royal Highmark Vestments
9650 2 Honorguard Chestpiece
9651 2 Gryphon Rider's Stormhammer
9652 2 Gryphon Rider's Leggings
9653 2 Speedy Racer Goggles
9654 2 Cairnstone Sliver
9655 2 Seedtime Hoop
9656 2 Granite Grips
9657 2 Vinehedge Cinch
9658 2 Boots of the Maharishi
9660 2 Stargazer Cloak
9661 2 Earthclasp Barrier
9662 2 Rushridge Boots
9663 2 Dawnrider's Chestpiece
9664 2 Sentinel's Guard
9665 2 Wingcrest Gloves
9666 2 Stronghorn Girdle
9678 2 Tok'kar's Murloc Basher
9679 2 Tok'kar's Murloc Chopper
9680 2 Tok'kar's Murloc Shanker
9682 2 Leather Chef's Belt
9683 2 Strength of the Treant
9684 2 Force of the Hippogryph
9685 2 Will of the Mountain Giant
9686 2 Spirit of the Faerie Dragon
9687 2 Grappler's Belt
9698 2 Gloves of Insight
9699 2 Garrison Cloak
9703 2 Scorched Cape
9704 2 Rustler Gloves
9705 2 Tharg's Shoelace
9706 2 Tharg's Disk
9718 3 Reforged Blade of Heroes
9742 1 Simple Cord
9743 1 Simple Shoes
9744 1 Simple Bands
9745 1 Simple Cape
9746 1 Simple Gloves
9747 2 Simple Britches
9748 2 Simple Robe
9749 2 Simple Blouse
9750 1 Gypsy Sash
9751 1 Gypsy Sandals
9752 1 Gypsy Bands
9753 2 Gypsy Buckler
9754 1 Gypsy Cloak
9755 1 Gypsy Gloves
9756 2 Gypsy Trousers
9757 2 Gypsy Tunic
9758 1 Cadet Belt
9759 1 Cadet Boots
9760 1 Cadet Bracers
9761 1 Cadet Cloak
9762 1 Cadet Gauntlets
9763 2 Cadet Leggings
9764 2 Cadet Shield
9765 2 Cadet Vest
9766 2 Greenweave Sash
9767 2 Greenweave Sandals
9768 2 Greenweave Bracers
9769 2 Greenweave Branch
9770 2 Greenweave Cloak
9771 2 Greenweave Gloves
9772 2 Greenweave Leggings
9773 2 Greenweave Robe
9774 2 Greenweave Vest
9775 2 Bandit Cinch
9776 2 Bandit Boots
9777 2 Bandit Bracers
9778 2 Bandit Buckler
9779 2 Bandit Cloak
9780 2 Bandit Gloves
9781 2 Bandit Pants
9782 2 Bandit Jerkin
9783 2 Raider's Chestpiece
9784 2 Raider's Boots
9785 2 Raider's Bracers
9786 2 Raider's Cloak
9787 2 Raider's Gauntlets
9788 2 Raider's Belt
9789 2 Raider's Legguards
9790 2 Raider's Shield
9791 2 Ivycloth Tunic
9792 2 Ivycloth Boots
9793 2 Ivycloth Bracelets
9794 2 Ivycloth Cloak
9795 2 Ivycloth Gloves
9796 2 Ivycloth Mantle
9797 2 Ivycloth Pants
9798 2 Ivycloth Robe
9799 2 Ivycloth Sash
9800 2 Ivy Orb
9801 2 Superior Belt
9802 2 Superior Boots
9803 2 Superior Bracers
9804 2 Superior Buckler
9805 2 Superior Cloak
9806 2 Superior Gloves
9807 2 Superior Shoulders
9808 2 Superior Leggings
9809 2 Superior Tunic
9810 2 Fortified Boots
9811 2 Fortified Bracers
9812 2 Fortified Cloak
9813 2 Fortified Gauntlets
9814 2 Fortified Belt
9815 2 Fortified Leggings
9816 2 Fortified Shield
9817 2 Fortified Spaulders
9818 2 Fortified Chain
9819 2 Durable Tunic
9820 2 Durable Boots
9821 2 Durable Bracers
9822 2 Durable Cape
9823 2 Durable Gloves
9824 2 Durable Shoulders
9825 2 Durable Pants
9826 2 Durable Robe
9827 2 Scaled Leather Belt
9828 2 Scaled Leather Boots
9829 2 Scaled Leather Bracers
9830 2 Scaled Shield
9831 2 Scaled Cloak
9832 2 Scaled Leather Gloves
9833 2 Scaled Leather Leggings
9834 2 Scaled Leather Shoulders
9835 2 Scaled Leather Tunic
9836 2 Banded Armor
9837 2 Banded Bracers
9838 2 Banded Cloak
9839 2 Banded Gauntlets
9840 2 Banded Girdle
9841 2 Banded Leggings
9842 2 Banded Pauldrons
9843 2 Banded Shield
9844 2 Conjurer's Vest
9845 2 Conjurer's Shoes
9846 2 Conjurer's Bracers
9847 2 Conjurer's Cloak
9848 2 Conjurer's Gloves
9849 2 Conjurer's Hood
9850 2 Conjurer's Mantle
9851 2 Conjurer's Breeches
9852 2 Conjurer's Robe
9853 2 Conjurer's Cinch
9854 2 Archer's Jerkin
9855 2 Archer's Belt
9856 2 Archer's Boots
9857 2 Archer's Bracers
9858 2 Archer's Buckler
9859 2 Archer's Cap
9860 2 Archer's Cloak
9861 2 Archer's Gloves
9862 2 Archer's Trousers
9863 2 Archer's Shoulderpads
9864 2 Renegade Boots
9865 2 Renegade Bracers
9866 2 Renegade Chestguard
9867 2 Renegade Cloak
9868 2 Renegade Gauntlets
9869 2 Renegade Belt
9870 2 Renegade Circlet
9871 2 Renegade Leggings
9872 2 Renegade Pauldrons
9873 2 Renegade Shield
9874 2 Sorcerer Drape
9875 2 Sorcerer Sash
9876 2 Sorcerer Slippers
9877 2 Sorcerer Cloak
9878 2 Sorcerer Hat
9879 2 Sorcerer Bracelets
9880 2 Sorcerer Gloves
9881 2 Sorcerer Mantle
9882 2 Sorcerer Sphere
9883 2 Sorcerer Pants
9884 2 Sorcerer Robe
9885 2 Huntsman's Boots
9886 2 Huntsman's Bands
9887 2 Huntsman's Armor
9889 2 Huntsman's Cap
9890 2 Huntsman's Cape
9891 2 Huntsman's Belt
9892 2 Huntsman's Gloves
9893 2 Huntsman's Leggings
9894 2 Huntsman's Shoulders
9895 2 Jazeraint Boots
9896 2 Jazeraint Bracers
9897 2 Jazeraint Chestguard
9898 2 Jazeraint Cloak
9899 2 Jazeraint Shield
9900 2 Jazeraint Gauntlets
9901 2 Jazeraint Belt
9902 2 Jazeraint Helm
9903 2 Jazeraint Leggings
9904 2 Jazeraint Pauldrons
9905 2 Royal Blouse
9906 2 Royal Sash
9907 2 Royal Boots
9908 2 Royal Cape
9909 2 Royal Bands
9910 2 Royal Gloves
9911 2 Royal Trousers
9912 2 Royal Amice
9913 2 Royal Gown
9914 2 Royal Scepter
9915 2 Royal Headband
9916 2 Tracker's Belt
9917 2 Tracker's Boots
9918 2 Brigade Defender
9919 2 Tracker's Cloak
9920 2 Tracker's Gloves
9921 2 Tracker's Headband
9922 2 Tracker's Leggings
9923 2 Tracker's Shoulderpads
9924 2 Tracker's Tunic
9925 2 Tracker's Wristguards
9926 2 Brigade Boots
9927 2 Brigade Bracers
9928 2 Brigade Breastplate
9929 2 Brigade Cloak
9930 2 Brigade Gauntlets
9931 2 Brigade Girdle
9932 2 Brigade Circlet
9933 2 Brigade Leggings
9934 2 Brigade Pauldrons
9935 2 Embossed Plate Shield
9936 2 Abjurer's Boots
9937 2 Abjurer's Bands
9938 2 Abjurer's Cloak
9939 2 Abjurer's Gloves
9940 2 Abjurer's Hood
9941 2 Abjurer's Mantle
9942 2 Abjurer's Pants
9943 2 Abjurer's Robe
9944 2 Abjurer's Crystal
9945 2 Abjurer's Sash
9946 2 Abjurer's Tunic
9947 2 Chieftain's Belt
9948 2 Chieftain's Boots
9949 2 Chieftain's Bracers
9950 2 Chieftain's Breastplate
9951 2 Chieftain's Cloak
9952 2 Chieftain's Gloves
9953 2 Chieftain's Headdress
9954 2 Chieftain's Leggings
9955 2 Chieftain's Shoulders
9956 2 Warmonger's Bracers
9957 2 Warmonger's Chestpiece
9958 2 Warmonger's Buckler
9959 2 Warmonger's Cloak
9960 2 Warmonger's Gauntlets
9961 2 Warmonger's Belt
9962 2 Warmonger's Greaves
9963 2 Warmonger's Circlet
9964 2 Warmonger's Leggings
9965 2 Warmonger's Pauldrons
9966 2 Embossed Plate Armor
9967 2 Embossed Plate Gauntlets
9968 2 Embossed Plate Girdle
9969 2 Embossed Plate Helmet
9970 2 Embossed Plate Leggings
9971 2 Embossed Plate Pauldrons
9972 2 Embossed Plate Bracers
9973 2 Embossed Plate Boots
9974 2 Overlord's Shield
9978 1 Gahz'ridian Detector
9998 2 Black Mageweave Vest
9999 2 Black Mageweave Leggings
10001 2 Black Mageweave Robe
10002 2 Shadoweave Pants
10003 2 Black Mageweave Gloves
10004 2 Shadoweave Robe
10007 2 Red Mageweave Vest
10008 2 White Bandit Mask
10009 2 Red Mageweave Pants
10010 2 Stormcloth Pants
10011 2 Stormcloth Gloves
10018 2 Red Mageweave Gloves
10019 3 Dreamweave Gloves
10020 2 Stormcloth Vest
10021 3 Dreamweave Vest
10023 2 Shadoweave Gloves
10024 2 Black Mageweave Headband
10025 2 Shadoweave Mask
10026 2 Black Mageweave Boots
10027 2 Black Mageweave Shoulders
10028 2 Shadoweave Shoulders
10029 2 Red Mageweave Shoulders
10030 2 Admiral's Hat
10031 2 Shadoweave Boots
10032 2 Stormcloth Headband
10033 2 Red Mageweave Headband
10034 1 Tuxedo Shirt
10035 1 Tuxedo Pants
10036 1 Tuxedo Jacket
10038 2 Stormcloth Shoulders
10039 2 Stormcloth Boots
10040 1 White Wedding Dress
10041 3 Dreamweave Circlet
10042 2 Cindercloth Robe
10043 2 Pious Legwraps
10044 2 Cindercloth Boots
10045 1 Simple Linen Pants
10046 1 Simple Linen Boots
10047 1 Simple Kilt
10048 2 Colorful Kilt
10049 2 Diabolist's Blade
10052 1 Orange Martial Shirt
10053 1 Simple Black Dress
10054 1 Lavender Mageweave Shirt
10055 1 Pink Mageweave Shirt
10056 1 Orange Mageweave Shirt
10057 2 Duskwoven Tunic
10058 2 Duskwoven Sandals
10059 2 Duskwoven Bracers
10060 2 Duskwoven Cape
10061 2 Duskwoven Turban
10062 2 Duskwoven Gloves
10063 2 Duskwoven Amice
10064 2 Duskwoven Pants
10065 2 Duskwoven Robe
10066 2 Duskwoven Sash
10067 2 Righteous Waistguard
10068 2 Righteous Boots
10069 2 Righteous Bracers
10070 2 Righteous Armor
10071 2 Righteous Cloak
10072 2 Righteous Gloves
10073 2 Righteous Helmet
10074 2 Righteous Leggings
10075 2 Righteous Spaulders
10076 2 Lord's Armguards
10077 2 Lord's Breastplate
10078 2 Lord's Crest
10079 2 Lord's Cape
10080 2 Lord's Gauntlets
10081 2 Lord's Girdle
10082 2 Lord's Boots
10083 2 Lord's Crown
10084 2 Lord's Legguards
10085 2 Lord's Pauldrons
10086 2 Gothic Plate Armor
10087 2 Gothic Plate Gauntlets
10088 2 Gothic Plate Girdle
10089 2 Gothic Sabatons
10090 2 Gothic Plate Helmet
10091 2 Gothic Plate Leggings
10092 2 Gothic Plate Spaulders
10093 2 Revenant Deflector
10094 2 Gothic Plate Vambraces
10095 2 Councillor's Boots
10096 2 Councillor's Cuffs
10097 2 Councillor's Circlet
10098 2 Councillor's Cloak
10099 2 Councillor's Gloves
10100 2 Councillor's Shoulders
10101 2 Councillor's Pants
10102 2 Councillor's Robes
10103 2 Councillor's Sash
10104 2 Councillor's Tunic
10105 2 Wanderer's Armor
10106 2 Wanderer's Boots
10107 2 Wanderer's Bracers
10108 2 Wanderer's Cloak
10109 2 Wanderer's Belt
10110 2 Wanderer's Gloves
10111 2 Wanderer's Hat
10112 2 Wanderer's Leggings
10113 2 Wanderer's Shoulders
10118 2 Ornate Breastplate
10119 2 Ornate Greaves
10120 2 Ornate Cloak
10121 2 Ornate Gauntlets
10122 2 Ornate Girdle
10123 2 Ornate Circlet
10124 2 Ornate Legguards
10125 2 Ornate Pauldrons
10126 2 Ornate Bracers
10127 2 Revenant Bracers
10128 2 Revenant Chestplate
10129 2 Revenant Gauntlets
10130 2 Revenant Girdle
10131 2 Revenant Boots
10132 2 Revenant Helmet
10133 2 Revenant Leggings
10134 2 Revenant Shoulders
10135 2 High Councillor's Tunic
10136 2 High Councillor's Bracers
10137 2 High Councillor's Boots
10138 2 High Councillor's Cloak
10139 2 High Councillor's Circlet
10140 2 High Councillor's Gloves
10141 2 High Councillor's Pants
10142 2 High Councillor's Mantle
10143 2 High Councillor's Robe
10144 2 High Councillor's Sash
10145 2 Mighty Girdle
10146 2 Mighty Boots
10147 2 Mighty Armsplints
10148 2 Mighty Cloak
10149 2 Mighty Gauntlets
10150 2 Mighty Helmet
10151 2 Mighty Tunic
10152 2 Mighty Leggings
10153 2 Mighty Spaulders
10154 2 Mercurial Girdle
10155 2 Mercurial Greaves
10156 2 Mercurial Bracers
10157 2 Mercurial Breastplate
10158 2 Mercurial Guard
10159 2 Mercurial Cloak
10160 2 Mercurial Circlet
10161 2 Mercurial Gauntlets
10162 2 Mercurial Legguards
10163 2 Mercurial Pauldrons
10164 2 Templar Chestplate
10165 2 Templar Gauntlets
10166 2 Templar Girdle
10167 2 Templar Boots
10168 2 Templar Crown
10169 2 Templar Legplates
10170 2 Templar Pauldrons
10171 2 Templar Bracers
10172 2 Mystical Mantle
10173 2 Mystical Bracers
10174 2 Mystical Cape
10175 2 Mystical Headwrap
10176 2 Mystical Gloves
10177 2 Mystical Leggings
10178 2 Mystical Robe
10179 2 Mystical Boots
10180 2 Mystical Belt
10181 2 Mystical Armor
10182 2 Swashbuckler's Breastplate
10183 2 Swashbuckler's Boots
10184 2 Swashbuckler's Bracers
10185 2 Swashbuckler's Cape
10186 2 Swashbuckler's Gloves
10187 2 Swashbuckler's Eyepatch
10188 2 Swashbuckler's Leggings
10189 2 Swashbuckler's Shoulderpads
10190 2 Swashbuckler's Belt
10191 2 Crusader's Armguards
10192 2 Crusader's Boots
10193 2 Crusader's Armor
10194 2 Crusader's Cloak
10195 2 Crusader's Shield
10196 2 Crusader's Gauntlets
10197 2 Crusader's Belt
10198 2 Crusader's Helm
10199 2 Crusader's Leggings
10200 2 Crusader's Pauldrons
10201 2 Overlord's Greaves
10202 2 Overlord's Vambraces
10203 2 Overlord's Chestplate
10204 2 Heavy Lamellar Shield
10205 2 Overlord's Gauntlets
10206 2 Overlord's Girdle
10207 2 Overlord's Crown
10208 2 Overlord's Legplates
10209 2 Overlord's Spaulders
10210 2 Elegant Mantle
10211 2 Elegant Boots
10212 2 Elegant Cloak
10213 2 Elegant Bracers
10214 2 Elegant Gloves
10215 2 Elegant Robes
10216 2 Elegant Belt
10217 2 Elegant Leggings
10218 2 Elegant Tunic
10219 2 Elegant Circlet
10220 2 Nightshade Tunic
10221 2 Nightshade Girdle
10222 2 Nightshade Boots
10223 2 Nightshade Armguards
10224 2 Nightshade Cloak
10225 2 Nightshade Gloves
10226 2 Nightshade Helmet
10227 2 Nightshade Leggings
10228 2 Nightshade Spaulders
10229 2 Engraved Bracers
10230 2 Engraved Breastplate
10231 2 Engraved Cape
10232 2 Engraved Gauntlets
10233 2 Engraved Girdle
10234 2 Engraved Boots
10235 2 Engraved Helm
10236 2 Engraved Leggings
10237 2 Engraved Pauldrons
10238 2 Heavy Lamellar Boots
10239 2 Heavy Lamellar Vambraces
10240 2 Heavy Lamellar Chestpiece
10241 2 Heavy Lamellar Helm
10242 2 Heavy Lamellar Gauntlets
10243 2 Heavy Lamellar Girdle
10244 2 Heavy Lamellar Leggings
10245 2 Heavy Lamellar Pauldrons
10246 2 Master's Vest
10247 2 Master's Boots
10248 2 Master's Bracers
10249 2 Master's Cloak
10250 2 Master's Hat
10251 2 Master's Gloves
10252 2 Master's Leggings
10253 2 Master's Mantle
10254 2 Master's Robe
10255 2 Master's Belt
10256 2 Adventurer's Bracers
10257 2 Adventurer's Boots
10258 2 Adventurer's Cape
10259 2 Adventurer's Belt
10260 2 Adventurer's Gloves
10261 2 Adventurer's Bandana
10262 2 Adventurer's Legguards
10263 2 Adventurer's Shoulders
10264 2 Adventurer's Tunic
10265 2 Masterwork Bracers
10266 2 Masterwork Breastplate
10267 2 Masterwork Cape
10268 2 Masterwork Gauntlets
10269 2 Masterwork Girdle
10270 2 Masterwork Boots
10271 2 Masterwork Shield
10272 2 Masterwork Circlet
10273 2 Masterwork Legplates
10274 2 Masterwork Pauldrons
10275 2 Emerald Breastplate
10276 2 Emerald Sabatons
10277 2 Emerald Gauntlets
10278 2 Emerald Girdle
10279 2 Emerald Helm
10280 2 Emerald Legplates
10281 2 Emerald Pauldrons
10282 2 Emerald Vambraces
10287 2 Greenweave Mantle
10288 2 Sage's Circlet
10289 2 Durable Hat
10298 2 Gnomeregan Band
10299 2 Gnomeregan Amulet
10328 3 Scarlet Chestpiece
10329 2 Scarlet Belt
10330 3 Scarlet Leggings
10331 2 Scarlet Gauntlets
10332 3 Scarlet Boots
10333 2 Scarlet Wristguards
10358 2 Duracin Bracers
10359 2 Everlast Boots
10362 2 Ornate Shield
10363 2 Engraved Wall
10364 2 Templar Shield
10365 2 Emerald Shield
10366 2 Demon Guard
10367 2 Hyperion Shield
10368 2 Imbued Plate Armor
10369 2 Imbued Plate Gauntlets
10370 2 Imbued Plate Girdle
10371 2 Imbued Plate Greaves
10372 2 Imbued Plate Helmet
10373 2 Imbued Plate Leggings
10374 2 Imbued Plate Pauldrons
10375 2 Imbued Plate Vambraces
10376 2 Commander's Boots
10377 2 Commander's Vambraces
10378 2 Commander's Armor
10379 2 Commander's Helm
10380 2 Commander's Gauntlets
10381 2 Commander's Girdle
10382 2 Commander's Leggings
10383 2 Commander's Pauldrons
10384 2 Hyperion Armor
10385 2 Hyperion Greaves
10386 2 Hyperion Gauntlets
10387 2 Hyperion Girdle
10388 2 Hyperion Helm
10389 2 Hyperion Legplates
10390 2 Hyperion Pauldrons
10391 2 Hyperion Vambraces
10399 3 Blackened Defias Armor
10400 2 Blackened Defias Leggings
10401 2 Blackened Defias Gloves
10402 2 Blackened Defias Boots
10403 2 Blackened Defias Belt
10404 2 Durable Belt
10405 1 Bandit Shoulders
10406 2 Scaled Leather Headband
10407 1 Raider's Shoulderpads
10408 2 Banded Helm
10409 2 Banded Boots
10410 3 Leggings of the Fang
10411 2 Footpads of the Fang
10412 2 Belt of the Fang
10413 2 Gloves of the Fang
10418 2 Glimmering Mithril Insignia
10421 1 Rough Copper Vest
10423 2 Silvered Bronze Leggings
10455 2 Chained Essence of Eranikus
10461 2 Shadowy Bracers
10462 2 Shadowy Belt
10499 2 Bright-Eye Goggles
10500 2 Fire Goggles
10501 2 Catseye Ultra Goggles
10502 2 Spellpower Goggles Xtreme
10503 2 Rose Colored Goggles
10504 3 Green Lens
10506 2 Deepdive Helmet
10508 2 Mithril Blunderbuss
10510 2 Mithril Heavy-bore Rifle
10515 1 Torch of Retribution
10518 2 Parachute Cloak
10542 2 Goblin Mining Helmet
10543 2 Goblin Construction Helmet
10544 1 Thistlewood Maul
10545 2 Gnomish Goggles
10547 1 Camping Knife
10549 2 Rancher's Trousers
10550 1 Wooly Mittens
10553 2 Foreman Vest
10554 2 Foreman Pants
10567 3 Quillshooter
10570 3 Manslayer
10571 3 Ebony Boneclub
10572 3 Freezing Shard
10573 3 Boneslasher
10574 3 Corpseshroud
10576 1 Mithril Mechanical Dragonling
10577 1 Goblin Mortar
10578 3 Thoughtcast Boots
10581 3 Death's Head Vestment
10582 3 Briar Tredders
10583 3 Quillward Harness
10584 3 Stormgale Fists
10585 1 Goblin Radio
10587 1 Goblin Bomb Dispenser
10588 2 Goblin Rocket Helmet
10623 3 Winter's Bite
10624 3 Stinging Bow
10625 3 Stealthblade
10626 3 Ragehammer
10627 3 Bludgeon of the Grinning Dog
10628 3 Deathblow
10629 3 Mistwalker Boots
10630 3 Soulcatcher Halo
10631 3 Murkwater Gauntlets
10632 3 Slimescale Bracers
10633 3 Silvershell Leggings
10634 3 Mindseye Circle
10635 1 Painted Chain Leggings
10636 1 Nomadic Gloves
10637 2 Brewer's Gloves
10638 2 Long Draping Cape
10645 1 Gnomish Death Ray
10652 2 Will of the Mountain Giant
10653 2 Trailblazer Boots
10654 2 Jutebraid Gloves
10655 1 Sedgeweed Britches
10656 1 Barkmail Vest
10657 2 Talbar Mantle
10658 2 Quagmire Galoshes
10659 2 Shard of the Splithooves
10686 2 Aegis of Battle
10696 2 Enchanted Azsharite Felbane Sword
10697 2 Enchanted Azsharite Felbane Dagger
10698 2 Enchanted Azsharite Felbane Staff
10700 2 Encarmine Boots
10701 2 Boots of Zua'tec
10702 2 Enormous Ogre Boots
10703 2 Fiendish Skiv
10704 2 Chillnail Splinter
10705 2 Firwillow Wristbands
10706 2 Nightscale Girdle
10707 2 Steelsmith Greaves
10708 2 Skullspell Orb
10709 2 Pyrestone Orb
10710 3 Dragonclaw Ring
10711 3 Dragon's Blood Necklace
10716 1 Gnomish Shrink Ray
10720 1 Gnomish Net-o-Matic Projector
10721 2 Gnomish Harm Prevention Belt
10723 1 Gnomish Ham Radio
10724 2 Gnomish Rocket Boots
10725 1 Gnomish Battle Chicken
10726 2 Gnomish Mind Control Cap
10727 1 Goblin Dragon Gun
10739 2 Ring of Fortitude
10740 2 Centurion Legplates
10741 2 Lordrec Helmet
10742 2 Dragonflight Leggings
10743 2 Drakefire Headguard
10744 2 Axe of the Ebon Drake
10745 2 Kaylari Shoulders
10746 2 Runesteel Vambraces
10747 2 Teacher's Sash
10748 2 Wanderlust Boots
10749 3 Avenguard Helm
10750 3 Lifeforce Dirk
10751 3 Gemburst Circlet
10758 3 X'caliboar
10760 2 Swine Fists
10761 3 Coldrage Dagger
10762 3 Robes of the Lich
10763 3 Icemetal Barbute
10764 3 Deathchill Armor
10765 2 Bonefingers
10766 3 Plaguerot Sprig
10767 3 Savage Boar's Guard
10768 3 Boar Champion's Belt
10769 3 Glowing Eye of Mordresh
10770 3 Mordresh's Lifeless Skull
10771 3 Deathmage Sash
10772 2 Glutton's Cleaver
10774 3 Fleshhide Shoulders
10775 3 Carapace of Tuten'kash
10776 3 Silky Spider Cape
10777 3 Arachnid Gloves
10778 2 Necklace of Sanctuary
10779 2 Demon's Blood
10780 2 Mark of Hakkar
10781 2 Hakkari Breastplate
10782 2 Hakkari Shroud
10783 3 Atal'ai Spaulders
10784 3 Atal'ai Breastplate
10785 2 Atal'ai Leggings
10786 2 Atal'ai Boots
10787 3 Atal'ai Gloves
10788 2 Atal'ai Girdle
10795 3 Drakeclaw Band
10796 3 Drakestone
10797 3 Firebreather
10798 3 Atal'alarion's Tusk Ring
10799 3 Headspike
10800 3 Darkwater Bracers
10801 3 Slitherscale Boots
10802 2 Wingveil Cloak
10803 2 Blade of the Wretched
10804 2 Fist of the Damned
10805 2 Eater of the Dead
10806 3 Vestments of the Atal'ai Prophet
10807 3 Kilt of the Atal'ai Prophet
10808 3 Gloves of the Atal'ai Prophet
10820 2 Jackseed Belt
10821 2 Sower's Cloak
10823 3 Vanquisher's Sword
10824 3 Amberglow Talisman
10826 2 Staff of Lore
10827 2 Surveyor's Tunic
10828 3 Dire Nail
10829 3 Dragon's Eye
10833 3 Horns of Eranikus
10835 3 Crest of Supremacy
10836 3 Rod of Corrosion
10837 3 Tooth of Eranikus
10838 3 Might of Hakkar
10842 3 Windscale Sarong
10843 3 Featherskin Cape
10844 3 Spire of Hakkar
10845 3 Warrior's Embrace
10846 3 Bloodshot Greaves
10847 4 Dragon's Call
10919 2 Apothecary Gloves
11086 3 Jang'thraze the Protector
11118 3 Archaedic Stone
11120 2 Belgrom's Hammer
11121 2 Darkwater Talwar
11122 2 Carrot on a Stick
11123 3 Rainstrider Leggings
11124 3 Helm of Exile
11187 1 Stemleaf Bracers
11189 1 Woodland Robes
11190 1 Viny Gloves
11191 1 Farmer's Boots
11192 1 Outfitter Gloves
11193 2 Blazewind Breastplate
11194 2 Prismscale Hauberk
11195 2 Warforged Chestplate
11196 2 Mindburst Medallion
11199 1 Engineer's Shield 1
11200 1 Engineer's Shield 2
11201 1 Engineer's Shield 3
11229 2 Brightscale Girdle
11262 3 Orb of Lorica
11263 3 Nether Force Wand
11265 2 Cragwood Maul
11287 2 Lesser Magic Wand
11288 2 Greater Magic Wand
11289 2 Lesser Mystic Wand
11290 2 Greater Mystic Wand
11302 3 Uther's Strength
11303 2 Fine Shortbow
11304 2 Fine Longbow
11305 2 Dense Shortbow
11306 2 Sturdy Recurve
11307 2 Massive Longbow
11308 2 Sylvan Shortbow
11310 3 Flameseer Mantle
11311 2 Emberscale Cape
11364 1 Tabard of Stormwind
11411 0 Large Bear Bone
11469 2 Bloodband Bracers
11475 1 Wine-stained Cloak
11502 2 Loreskin Shoulders
11508 1 Gamemaster's Slippers
11522 1 Silver Totem of Aquementas
11603 3 Vilerend Slicer
11604 3 Dark Iron Plate
11605 2 Dark Iron Shoulders
11606 2 Dark Iron Mail
11607 3 Dark Iron Sunderer
11608 3 Dark Iron Pulverizer
11623 3 Spritecaster Cape
11624 3 Kentic Amice
11625 3 Enthralled Sphere
11626 3 Blackveil Cape
11627 3 Fleetfoot Greaves
11628 3 Houndmaster's Bow
11629 3 Houndmaster's Rifle
11631 3 Stoneshell Guard
11632 3 Earthslag Shoulders
11633 3 Spiderfang Carapace
11634 3 Silkweb Gloves
11635 3 Hookfang Shanker
11662 3 Ban'thok Sash
11665 3 Ogreseer Fists
11669 3 Naglering
11675 3 Shadefiend Boots
11677 3 Graverot Cape
11678 3 Carapace of Anub'shiah
11679 3 Rubicund Armguards
11684 4 Ironfoe
11685 3 Splinthide Shoulders
11686 3 Girdle of Beastial Fury
11702 3 Grizzle's Skinner
11703 3 Stonewall Girdle
11722 3 Dregmetal Spaulders
11726 4 Savage Gladiator Chain
11728 3 Savage Gladiator Leggings
11729 3 Savage Gladiator Helm
11730 3 Savage Gladiator Grips
11731 3 Savage Gladiator Greaves
11735 3 Ragefury Eyepatch
11743 2 Rockfist
11744 3 Bloodfist
11745 3 Fists of Phalanx
11746 3 Golem Skull Helm
11747 3 Flamestrider Robes
11748 3 Pyric Caduceus
11749 3 Searingscale Leggings
11750 3 Kindling Stave
11755 3 Verek's Collar
11764 3 Cinderhide Armsplints
11765 3 Pyremail Wristguards
11766 3 Flameweave Cuffs
11767 3 Emberplate Armguards
11768 2 Incendic Bracers
11782 3 Boreal Mantle
11783 3 Chillsteel Girdle
11784 3 Arbiter's Blade
11785 3 Rock Golem Bulwark
11786 3 Stone of the Earth
11787 3 Shalehusk Boots
11802 3 Lavacrest Leggings
11803 3 Force of Magma
11805 3 Rubidium Hammer
11807 3 Sash of the Burning Heart
11808 4 Circle of Flame
11809 3 Flame Wrath
11810 3 Force of Will
11811 3 Smoking Heart of the Mountain
11812 3 Cape of the Fire Salamander
11814 3 Molten Fists
11815 3 Hand of Justice
11816 3 Angerforge's Battle Axe
11817 3 Lord General's Sword
11819 3 Second Wind
11820 3 Royal Decorated Armor
11821 3 Warstrife Leggings
11822 3 Omnicast Boots
11823 3 Luminary Kilt
11824 3 Cyclopean Band
11832 3 Burst of Knowledge
11839 3 Chief Architect's Monocle
11840 1 Master Builder's Shirt
11841 3 Senior Designer's Pantaloons
11842 3 Lead Surveyor's Mantle
11847 1 Battered Cloak
11848 1 Flax Belt
11849 1 Rustmetal Bracers
11850 1 Short Duskbat Cape
11851 1 Scavenger Tunic
11852 1 Roamer's Leggings
11853 2 Rambling Boots
11854 2 Samophlange Screwdriver
11855 2 Tork Wrench
11856 2 Ceremonial Elven Blade
11857 2 Sanctimonial Rod
11858 2 Battlehard Cape
11859 2 Jademoon Orb
11860 2 Charged Lightning Rod
11861 2 Girdle of Reprisal
11862 2 White Bone Band
11863 2 White Bone Shredder
11864 2 White Bone Spear
11865 2 Rancor Boots
11866 3 Nagmara's Whipping Belt
11867 2 Maddening Gauntlets
11868 2 Choking Band
11869 2 Sha'ni's Ring
11870 2 Oblivion Orb
11871 2 Snarkshaw Spaulders
11872 2 Eschewal Greaves
11873 2 Ethereal Mist Cape
11874 2 Clouddrift Mantle
11875 2 Breezecloud Bracers
11876 2 Plainstalker Tunic
11882 2 Outrider Leggings
11884 2 Moonlit Amice
11888 2 Quintis' Research Gloves
11889 2 Bark Iron Pauldrons
11902 2 Linken's Sword of Mastery
11904 2 Spirit of Aquementas
11905 2 Linken's Boomerang
11906 2 Beastsmasher
11907 2 Beastslayer
11908 2 Archaeologist's Quarry Boots
11909 2 Excavator's Utility Belt
11910 2 Bejeweled Legguards
11911 2 Treetop Leggings
11913 2 Clayridge Helm
11915 2 Shizzle's Drizzle Blocker
11916 2 Shizzle's Muzzle
11917 2 Shizzle's Nozzle Wiper
11918 2 Grotslab Gloves
11919 2 Cragplate Greaves
11920 3 Wraith Scythe
11921 3 Impervious Giant
11922 3 Blood-etched Blade
11923 3 The Hammer of Grace
11924 3 Robes of the Royal Crown
11925 3 Ghostshroud
11926 3 Deathdealer Breastplate
11927 3 Legplates of the Eternal Guardian
11928 3 Thaurissan's Royal Scepter
11929 3 Haunting Specter Leggings
11930 3 The Emperor's New Cape
11931 3 Dreadforge Retaliator
11932 3 Guiding Stave of Wisdom
11933 3 Imperial Jewel
11934 3 Emperor's Seal
11935 3 Magmus Stone
11936 2 Relic Hunter Belt
11945 2 Dark Iron Ring
11946 2 Fire Opal Necklace
11962 3 Manacle Cuffs
11963 2 Penance Spaulders
11964 2 Swiftstrike Cudgel
11965 2 Quartz Ring
11967 2 Zircon Band
11968 2 Amber Hoop
11969 2 Jacinth Circle
11970 2 Spinel Ring
11971 2 Amethyst Band
11972 2 Carnelian Loop
11973 2 Hematite Link
11974 2 Aquamarine Ring
11975 2 Topaz Ring
11976 2 Sardonyx Knuckle
11977 2 Serpentine Loop
11978 2 Jasper Link
11979 2 Peridot Circle
11980 2 Opal Ring
11981 2 Lead Band
11982 2 Viridian Band
11983 2 Chrome Ring
11984 2 Cobalt Ring
11985 2 Cerulean Ring
11986 2 Thallium Hoop
11987 2 Iridium Circle
11988 2 Tellurium Band
11989 2 Vanadium Loop
11990 2 Selenium Loop
11991 2 Quicksilver Ring
11992 2 Vermilion Band
11993 2 Clay Ring
11994 2 Coral Band
11995 2 Ivory Band
11996 2 Basalt Ring
11997 2 Greenstone Circle
11998 2 Jet Loop
11999 2 Lodestone Hoop
12000 2 Limb Cleaver
12001 2 Onyx Ring
12002 2 Marble Circle
12004 2 Obsidian Band
12005 2 Granite Ring
12006 2 Meadow Ring
12007 2 Prairie Ring
12008 2 Savannah Ring
12009 2 Tundra Ring
12010 2 Fen Ring
12011 2 Forest Hoop
12012 2 Marsh Ring
12013 2 Desert Ring
12014 2 Arctic Ring
12015 2 Swamp Ring
12016 2 Jungle Ring
12017 2 Prismatic Band
12018 2 Conservator Helm
12019 2 Cerulean Talisman
12020 2 Thallium Choker
12021 2 Shieldplate Sabatons
12022 2 Iridium Chain
12023 2 Tellurium Necklace
12024 2 Vanadium Talisman
12025 2 Selenium Chain
12026 2 Quicksilver Pendant
12027 2 Vermilion Necklace
12028 2 Basalt Necklace
12029 2 Greenstone Talisman
12030 2 Jet Chain
12031 2 Lodestone Necklace
12032 2 Onyx Choker
12034 2 Marble Necklace
12035 2 Obsidian Pendant
12036 2 Granite Necklace
12038 2 Lagrave's Seal
12039 2 Tundra Necklace
12040 2 Forest Pendant
12041 2 Windshear Leggings
12042 2 Marsh Chain
12043 2 Desert Choker
12044 2 Arctic Pendant
12045 2 Swamp Pendant
12046 2 Jungle Necklace
12047 2 Spectral Necklace
12048 2 Prismatic Pendant
12049 2 Splintsteel Armor
12050 2 Hazecover Boots
12051 2 Brazen Gauntlets
12052 2 Ring of the Moon
12053 2 Volcanic Rock Ring
12054 2 Demon Band
12055 2 Stardust Band
12056 2 Ring of the Heavens
12057 2 Dragonscale Band
12058 2 Demonic Bone Ring
12059 3 Conqueror's Medallion
12061 2 Blade of Reckoning
12062 2 Skilled Fighting Blade
12064 1 Gamemaster Hood
12065 2 Ward of the Elements
12066 2 Shaleskin Cape
12082 2 Wyrmhide Spaulders
12083 2 Valconian Sash
12102 2 Ring of the Aristocrat
12103 3 Star of Mystaria
12104 2 Brindlethorn Tunic
12105 2 Pridemail Leggings
12106 2 Boulderskin Breastplate
12107 2 Whispersilk Leggings
12108 2 Basaltscale Armor
12109 2 Azure Moon Amice
12110 2 Raincaster Drape
12111 2 Lavaplate Gauntlets
12112 2 Crypt Demon Bracers
12113 2 Sunborne Cape
12114 2 Nightfall Gloves
12115 2 Stalwart Clutch
12185 2 Bloodsail Admiral's Hat
12225 1 Blump Family Fishing Pole
12243 3 Smoldering Claw
12247 2 Broad Bladed Knife
12248 2 Daring Dirk
12249 2 Merciless Axe
12250 2 Midnight Axe
12251 2 Big Stick
12252 2 Staff of Protection
12253 2 Brilliant Red Cloak
12254 2 Well Oiled Cloak
12255 2 Pale Leggings
12256 2 Cindercloth Leggings
12257 2 Heavy Notched Belt
12258 2 Serpent Clasp Belt
12259 2 Glinting Steel Dagger
12260 2 Searing Golden Blade
12282 1 Worn Battleaxe
12295 2 Leggings of the People's Militia
12296 2 Spark of the People's Militia
12299 1 Netted Gloves
12344 3 Seal of Ascension
12405 2 Thorium Armor
12406 2 Thorium Belt
12408 2 Thorium Bracers
12409 2 Thorium Boots
12410 2 Thorium Helm
12414 2 Thorium Leggings
12415 2 Radiant Breastplate
12416 2 Radiant Belt
12417 2 Radiant Circlet
12418 2 Radiant Gloves
12419 2 Radiant Boots
12420 2 Radiant Leggings
12422 2 Imperial Plate Chest
12424 2 Imperial Plate Belt
12425 2 Imperial Plate Bracers
12426 2 Imperial Plate Boots
12427 2 Imperial Plate Helm
12428 2 Imperial Plate Shoulders
12429 2 Imperial Plate Leggings
12446 1 Anvilmar Musket
12447 1 Thistlewood Bow
12448 1 Light Hunting Rifle
12449 1 Primitive Bow
12462 4 Embrace of the Wind Serpent
12463 3 Drakefang Butcher
12464 3 Bloodfire Talons
12465 3 Nightfall Drape
12466 3 Dawnspire Cord
12468 0 Chilton Wand
12469 3 Mutilator
12470 3 Sandstalker Ankleguards
12471 3 Desertwalker Cane
12522 2 Bingles' Flying Gloves
12527 3 Ribsplitter
12528 3 The Judge's Gavel
12531 3 Searing Needle
12532 3 Spire of the Stoneshaper
12535 3 Doomforged Straightedge
12542 3 Funeral Pyre Vestment
12543 3 Songstone of Ironforge
12544 3 Thrall's Resolve
12545 3 Eye of Orgrimmar
12546 3 Aristocratic Cuffs
12547 3 Mar Alom's Grip
12548 3 Magni's Will
12549 3 Braincage
12550 3 Runed Golem Shackles
12551 3 Stoneshield Cloak
12552 3 Blisterbane Wrap
12553 3 Swiftwalker Boots
12554 3 Hands of the Exalted Herald
12555 3 Battlechaser's Greaves
12556 3 High Priestess Boots
12557 3 Ebonsteel Spaulders
12582 3 Keris of Zul'Serak
12583 3 Blackhand Doomsaw
12584 4 Grand Marshal's Longsword
12587 3 Eye of Rend
12588 3 Bonespike Shoulder
12589 3 Dustfeather Sash
12590 4 Felstriker
12592 4 Blackblade of Shahram
12602 3 Draconian Deflector
12603 3 Nightbrace Tunic
12604 3 Starfire Tiara
12605 3 Serpentine Skuller
12606 3 Crystallized Girdle
12608 3 Butcher's Apron
12609 3 Polychromatic Visionwrap
12610 2 Runic Plate Shoulders
12611 2 Runic Plate Boots
12612 2 Runic Plate Helm
12613 2 Runic Breastplate
12614 2 Runic Plate Leggings
12615 2 Savage Mail Tunic
12616 2 Savage Mail Boots
12617 2 Savage Mail Shoulders
12618 3 Enchanted Thorium Breastplate
12619 3 Enchanted Thorium Leggings
12620 3 Enchanted Thorium Helm
12621 3 Demonfork
12624 3 Wildthorn Mail
12625 3 Dawnbringer Shoulders
12626 3 Funeral Cuffs
12628 3 Demon Forged Breastplate
12631 3 Fiery Plate Gauntlets
12632 3 Storm Gauntlets
12633 3 Whitesoul Helm
12634 3 Chiselbrand Girdle
12636 3 Helm of the Great Chief
12637 3 Backusarian Gauntlets
12639 4 Stronghold Gauntlets
12640 4 Lionheart Helm
12641 4 Invulnerable Mail
12651 3 Blackcrow
12653 3 Riphook
12709 3 Pip's Skinner
12752 4 Cap of the Scarlet Savant
12756 4 Leggings of Arcana
12757 4 Breastplate of Bloodthirst
12764 2 Thorium Greatsword
12769 3 Bleakwood Hew
12772 2 Inlaid Thorium Hammer
12773 2 Ornate Thorium Handaxe
12774 3 Dawn's Edge
12775 2 Huge Thorium Battleaxe
12776 3 Enchanted Battlehammer
12777 3 Blazing Rapier
12779 2 Rune Edge
12781 3 Serenity
12782 3 Corruption
12783 3 Heartseeker
12784 3 Arcanite Reaper
12790 3 Arcanite Champion
12791 3 Barman Shanker
12792 2 Volcanic Hammer
12793 3 Mixologist's Tunic
12794 3 Masterwork Stormhammer
12795 3 Blood Talon
12796 3 Hammer of the Titans
12797 3 Frostguard
12798 3 Annihilator
12802 3 Darkspear
12805 2 Orb of Fire
12846 1 Argent Dawn Commission
12895 4 Breastplate of the Chromatic Flight
12903 4 Legguards of the Chromatic Defier
12904 2 Shawn's Super Special Swami Hat
12905 3 Wildfire Cape
12926 3 Flaming Band
12927 3 Truestrike Shoulders
12929 3 Emberfury Talisman
12930 3 Briarwood Reed
12935 3 Warmaster Legguards
12936 3 Battleborn Armbraces
12939 3 Dal'Rend's Tribal Guardian
12940 3 Dal'Rend's Sacred Charge
12945 4 Legplates of the Chromatic Defier
12947 6 Alex's Ring of Audacity
12952 3 Gyth's Skull
12953 3 Dragoneye Coif
12960 3 Tribal War Feathers
12963 3 Blademaster Leggings
12964 3 Tristam Legguards
12965 3 Spiritshroud Leggings
12966 3 Blackmist Armguards
12967 3 Bloodmoon Cloak
12968 3 Frostweaver Cape
12969 3 Seeping Willow
12970 3 General's Ceremonial Plate
12974 3 The Black Knight
12975 3 Prospector Axe
12976 3 Ironpatch Blade
12977 3 Magefist Gloves
12978 3 Stormbringer Belt
12979 3 Firebane Cloak
12982 3 Silver-linked Footguards
12983 3 Rakzur Club
12984 3 Skycaller
12985 3 Ring of Defense
12987 3 Darkweave Breeches
12988 3 Starsight Tunic
12989 3 Gargoyle's Bite
12990 3 Razor's Edge
12992 3 Searing Blade
12994 3 Thorbia's Gauntlets
12996 3 Band of Purification
12997 3 Redbeard Crest
12998 3 Magician's Mantle
12999 3 Drakewing Bands
13000 3 Staff of Hale Magefire
13001 3 Maiden's Circle
13002 3 Lady Alizabeth's Pendant
13003 3 Lord Alexander's Battle Axe
13004 3 Torch of Austen
13005 3 Amy's Blanket
13006 3 Mass of McGowan
13007 3 Mageflame Cloak
13008 3 Dalewind Trousers
13009 3 Cow King's Hide
13010 3 Dreamsinger Legguards
13011 3 Silver-lined Belt
13012 3 Yorgen Bracers
13013 3 Elder Wizard's Mantle
13014 3 Axe of Rin'ji
13015 3 Serathil
13016 3 Killmaim
13017 3 Hellslayer Battle Axe
13018 3 Executioner's Cleaver
13019 3 Harpyclaw Short Bow
13020 3 Skystriker Bow
13021 3 Needle Threader
13022 3 Gryphonwing Long Bow
13023 3 Eaglehorn Long Bow
13024 3 Beazel's Basher
13025 3 Deadwood Sledge
13026 3 Heaven's Light
13027 3 Bonesnapper
13028 3 Bludstone Hammer
13029 3 Umbral Crystal
13030 3 Basilisk Bone
13031 3 Orb of Mistmantle
13032 3 Sword of Corruption
13033 3 Zealot Blade
13034 3 Speedsteel Rapier
13035 3 Serpent Slicer
13036 3 Assassination Blade
13037 3 Crystalpine Stinger
13038 3 Swiftwind
13039 3 Skull Splitting Crossbow
13040 3 Heartseeking Crossbow
13041 3 Guardian Blade
13042 3 Sword of the Magistrate
13043 3 Blade of the Titans
13044 3 Demonslayer
13045 3 Viscous Hammer
13046 3 Blanchard's Stout
13047 3 Twig of the World Tree
13048 3 Looming Gavel
13049 3 Deanship Claymore
13051 3 Witchfury
13052 3 Warmonger
13053 3 Doombringer
13054 3 Grim Reaper
13055 3 Bonechewer
13056 3 Frenzied Striker
13057 3 Bloodpike
13058 3 Khoo's Point
13059 3 Stoneraven
13060 3 The Needler
13062 3 Thunderwood
13063 3 Starfaller
13064 3 Jaina's Firestarter
13065 3 Wand of Allistarj
13066 3 Wyrmslayer Spaulders
13067 3 Hydralick Armor
13068 3 Obsidian Greaves
13070 3 Sapphiron's Scale Boots
13071 3 Plated Fist of Hakoo
13072 3 Stonegrip Gauntlets
13073 3 Mugthol's Helm
13074 3 Golem Shard Leggings
13075 3 Direwing Legguards
13076 3 Giantslayer Bracers
13077 3 Girdle of Uther
13079 3 Shield of Thorsen
13080 3 Widow's Clutch
13081 3 Skullance Shield
13082 3 Mountainside Buckler
13083 3 Garrett Family Crest
13084 3 Kaleidoscope Chain
13085 3 Horizon Choker
13087 3 River Pride Choker
13088 3 Gazlowe's Charm
13089 3 Skibi's Pendant
13090 3 Breastplate of the Chosen
13091 3 Medallion of Grand Marshal Morris
13093 3 Blush Ember Ring
13094 3 The Queen's Jewel
13095 3 Assault Band
13096 3 Band of the Hierophant
13097 3 Thunderbrow Ring
13098 3 Painweaver Band
13099 3 Moccasins of the White Hare
13100 3 Furen's Boots
13101 3 Wolfrunner Shoes
13102 3 Cassandra's Grace
13103 3 Pads of the Venom Spider
13105 3 Sutarn's Ring
13106 3 Glowing Magical Bracelets
13107 3 Magiskull Cuffs
13108 3 Tigerstrike Mantle
13109 3 Blackflame Cape
13110 3 Wolffear Harness
13111 3 Sandals of the Insurgent
13112 3 Winged Helm
13113 3 Feathermoon Headdress
13114 3 Troll's Bane Leggings
13115 3 Sheepshear Mantle
13116 3 Spaulders of the Unseen
13117 3 Ogron's Sash
13118 3 Serpentine Sash
13119 3 Enchanted Kodo Bracers
13120 3 Deepfury Bracers
13121 3 Wing of the Whelpling
13122 3 Dark Phantom Cape
13123 3 Dreamwalker Armor
13124 3 Ravasaur Scale Boots
13125 3 Elven Chain Boots
13126 3 Battlecaller Gauntlets
13127 3 Frostreaver Crown
13128 3 High Bergg Helm
13129 3 Firemane Leggings
13130 3 Windrunner Legguards
13131 3 Sparkleshell Mantle
13132 3 Skeletal Shoulders
13133 3 Drakesfire Epaulets
13134 3 Belt of the Gladiator
13135 3 Lordly Armguards
13136 3 Lil Timmy's Peashooter
13137 3 Ironweaver
13138 3 The Silencer
13139 3 Guttbuster
13141 3 Tooth of Gnarr
13142 3 Brigam Girdle
13143 4 Mark of the Dragon Lord
13144 3 Serenity Belt
13145 3 Enormous Ogre Belt
13146 3 Shell Launcher Shotgun
13148 3 Chillpike
13161 3 Trindlehaven Staff
13162 3 Reiver Claws
13163 3 Relentless Scythe
13164 3 Heart of the Scale
13166 3 Slamshot Shoulders
13167 3 Fist of Omokk
13168 3 Plate of the Shaman King
13169 3 Tressermane Leggings
13170 3 Skyshroud Leggings
13171 2 Smokey's Lighter
13173 3 Flightblade Throwing Axe
13175 2 Voone's Twitchbow
13177 3 Talisman of Evasion
13178 3 Rosewine Circle
13179 3 Brazecore Armguards
13181 3 Demonskin Gloves
13182 3 Phase Blade
13183 3 Venomspitter
13184 3 Fallbrush Handgrips
13185 3 Sunderseer Mantle
13198 3 Hurd Smasher
13199 3 Crushridge Bindings
13203 3 Armswake Cloak
13204 3 Bashguuder
13205 3 Rhombeard Protector
13206 3 Wolfshear Leggings
13208 3 Bleak Howler Armguards
13209 3 Seal of the Dawn
13210 3 Pads of the Dread Wolf
13211 3 Slashclaw Bracers
13212 3 Halycon's Spiked Collar
13213 3 Smolderweb's Eye
13216 2 Crown of the Penitent
13217 2 Band of the Penitent
13218 3 Fang of the Crystal Spider
13243 3 Argent Defender
13244 3 Gilded Gauntlets
13245 3 Kresh's Back
13246 3 Argent Avenger
13248 3 Burstshot Harquebus
13249 3 Argent Crusader
13252 3 Cloudrunner Girdle
13253 3 Hands of Power
13254 3 Astral Guard
13255 3 Trueaim Gauntlets
13257 3 Demonic Runed Spaulders
13258 3 Slaghide Gauntlets
13259 3 Ribsteel Footguards
13260 3 Wind Dancer Boots
13261 3 Globe of D'sak
13262 5 Ashbringer
13282 3 Ogreseer Tower Boots
13283 3 Magus Ring
13284 3 Swiftdart Battleboots
13285 3 The Blackrock Slicer
13286 3 Rivenspike
13289 1 Egan's Blaster
13314 4 Alanna's Embrace
13315 2 Testament of Hope
13340 3 Cape of the Black Baron
13344 3 Dracorian Gauntlets
13345 3 Seal of Rivendare
13346 3 Robes of the Exalted
13347 2 Crystal of Zin-Malor
13348 3 Demonshear
13349 3 Scepter of the Unholy
13353 4 Book of the Dead
13358 3 Wyrmtongue Shoulders
13359 3 Crown of Tyranny
13360 3 Gift of the Elven Magi
13361 3 Skullforge Reaver
13368 3 Bonescraper
13369 3 Fire Striders
13371 2 Father Flame
13372 3 Slavedriver's Cane
13373 3 Band of Flesh
13374 3 Soulstealer Mantle
13375 3 Crest of Retribution
13376 3 Royal Tribunal Cloak
13378 3 Songbird Blouse
13379 3 Piccolo of the Flaming Fire
13380 3 Willey's Portable Howitzer
13381 3 Master Cannoneer Boots
13382 3 Cannonball Runner
13383 3 Woollies of the Prancing Minstrel
13384 3 Rainbow Girdle
13385 3 Tome of Knowledge
13386 3 Archivist Cape
13387 3 Foresight Girdle
13388 3 The Postmaster's Tunic
13389 3 The Postmaster's Trousers
13390 3 The Postmaster's Band
13391 3 The Postmaster's Treads
13392 3 The Postmaster's Seal
13393 3 Malown's Slam
13394 3 Skul's Cold Embrace
13395 3 Skul's Fingerbone Claws
13396 3 Skul's Ghastly Touch
13397 3 Stoneskin Gargoyle Cape
13398 3 Boots of the Shrieker
13399 3 Gargoyle Shredder Talons
13400 3 Vambraces of the Sadist
13401 3 The Cruel Hand of Timmy
13402 3 Timmy's Galoshes
13403 3 Grimgore Noose
13404 3 Mask of the Unforgiven
13405 3 Wailing Nightbane Pauldrons
13408 3 Soul Breaker
13409 3 Tearfall Bracers
13473 2 Felstone Good Luck Charm
13474 2 Farmer Dalson's Shotgun
13475 2 Dalson Family Wedding Ring
13498 3 Handcrafted Mastersmith Leggings
13502 3 Handcrafted Mastersmith Girdle
13503 4 Alchemists' Stone
13505 4 Runeblade of Baron Rivendare
13515 3 Ramstein's Lightning Bolts
13524 3 Skull of Burning Shadows
13525 2 Darkbind Fingers
13526 2 Flamescarred Girdle
13527 2 Lavawalker Greaves
13528 2 Twilight Void Bracers
13529 3 Husk of Nerub'enkan
13530 2 Fangdrip Runners
13531 2 Crypt Stalker Leggings
13532 2 Darkspinner Claws
13533 2 Acid-etched Pauldrons
13534 3 Banshee Finger
13535 2 Coldtouch Phantom Wraps
13537 2 Chillhide Bracers
13538 2 Windshrieker Pauldrons
13539 2 Banshee's Touch
13544 2 Spectral Essence
13602 1 Greater Spellstone
13603 1 Major Spellstone
13699 1 Firestone
13700 1 Greater Firestone
13701 1 Major Firestone
13811 2 Necklace of the Dawn
13812 2 Ring of the Dawn
13816 0 Fine Longsword
13817 0 Tapered Greatsword
13818 0 Jagged Axe
13819 0 Balanced War Axe
13820 0 Clout Mace
13821 0 Bulky Maul
13822 0 Spiked Dagger
13823 0 Stout War Staff
13824 0 Recurve Long Bow
13825 0 Primed Musket
13842 1 Fall/Winter Morning
13843 1 Fall/Winter Afternoon
13844 1 Fall/Winter Evening
13845 1 Fall/Winter Night
13846 1 Spring/Summer Morning
13847 1 Spring/Summer Afternoon
13848 1 Spring/Summer Evening
13849 1 Spring/Summer Night
13856 2 Runecloth Belt
13857 2 Runecloth Tunic
13858 2 Runecloth Robe
13860 2 Runecloth Cloak
13863 2 Runecloth Gloves
13864 2 Runecloth Boots
13865 2 Runecloth Pants
13866 2 Runecloth Headband
13867 2 Runecloth Shoulders
13868 2 Frostweave Robe
13869 2 Frostweave Tunic
13870 2 Frostweave Gloves
13871 2 Frostweave Pants
13882 1 42 Pound Redgill
13883 1 45 Pound Redgill
13884 1 49 Pound Redgill
13885 1 34 Pound Redgill
13886 1 37 Pound Redgill
13887 1 52 Pound Redgill
13895 1 Formal Dangui
13896 1 Dark Green Wedding Hanbok
13897 1 White Traditional Hanbok
13898 1 Royal Dangui
13899 1 Red Traditional Hanbok
13900 1 Green Wedding Hanbok
13901 1 15 Pound Salmon
13902 1 18 Pound Salmon
13903 1 22 Pound Salmon
13904 1 25 Pound Salmon
13905 1 29 Pound Salmon
13906 1 32 Pound Salmon
13914 1 70 Pound Mightfish
13915 1 85 Pound Mightfish
13916 1 92 Pound Mightfish
13917 1 103 Pound Mightfish
13937 4 Headmaster's Charge
13938 3 Bonecreeper Stylus
13944 3 Tombstone Breastplate
13950 3 Detention Strap
13951 3 Vigorsteel Vambraces
13952 3 Iceblade Hacker
13953 3 Silent Fang
13954 3 Verdant Footpads
13955 3 Stoneform Shoulders
13956 3 Clutch of Andros
13957 3 Gargoyle Slashers
13958 3 Wyrmthalak's Shackles
13959 3 Omokk's Girth Restrainer
13960 3 Heart of the Fiend
13961 3 Halycon's Muzzle
13962 3 Vosh'gajin's Strand
13963 3 Voone's Vice Grips
13964 3 Witchblade
13965 3 Blackhand's Breadth
13966 3 Mark of Tyranny
13967 3 Windreaver Greaves
13968 3 Eye of the Beast
13969 3 Loomguard Armbraces
13982 3 Warblade of Caer Darrow
13983 3 Gravestone War Axe
13984 3 Darrowspike
13986 3 Crown of Caer Darrow
14002 3 Darrowshire Strongguard
14022 3 Barov Peasant Caller
14023 3 Barov Peasant Caller
14024 3 Frightalon
14025 2 Mystic's Belt
14042 2 Cindercloth Vest
14043 2 Cindercloth Gloves
14044 2 Cindercloth Cloak
14045 2 Cindercloth Pants
14083 1 Tyrande's Staff
14086 1 Beaded Sandals
14087 1 Beaded Cuffs
14088 1 Beaded Cloak
14089 1 Beaded Gloves
14090 2 Beaded Britches
14091 2 Beaded Robe
14093 1 Beaded Cord
14094 2 Beaded Wraps
14095 1 Native Bands
14096 2 Native Vest
14097 2 Native Pants
14098 1 Native Cloak
14099 1 Native Sash
14100 2 Brightcloth Robe
14101 2 Brightcloth Gloves
14102 1 Native Handwraps
14103 2 Brightcloth Cloak
14104 2 Brightcloth Pants
14106 2 Felcloth Robe
14107 2 Felcloth Pants
14108 2 Felcloth Boots
14109 2 Native Robe
14110 1 Native Sandals
14111 2 Felcloth Hood
14112 2 Felcloth Shoulders
14113 2 Aboriginal Sash
14114 2 Aboriginal Footwraps
14115 1 Aboriginal Bands
14116 1 Aboriginal Cape
14117 2 Aboriginal Gloves
14119 2 Aboriginal Loincloth
14120 2 Aboriginal Robe
14121 2 Aboriginal Vest
14122 2 Ritual Bands
14123 2 Ritual Cape
14124 2 Ritual Gloves
14125 2 Ritual Leggings
14126 1 Ritual Amice
14127 2 Ritual Shroud
14128 2 Wizardweave Robe
14129 2 Ritual Sandals
14130 2 Wizardweave Turban
14131 2 Ritual Belt
14132 2 Wizardweave Leggings
14133 2 Ritual Tunic
14134 3 Cloak of Fire
14136 3 Robe of Winter Night
14137 3 Mooncloth Leggings
14138 3 Mooncloth Vest
14139 3 Mooncloth Shoulders
14140 3 Mooncloth Circlet
14141 2 Ghostweave Vest
14142 2 Ghostweave Gloves
14143 2 Ghostweave Belt
14144 2 Ghostweave Pants
14145 2 Cursed Felblade
14146 4 Gloves of Spell Mastery
14147 2 Cavedweller Bracers
14148 2 Crystalline Cuffs
14149 2 Subterranean Cape
14150 2 Robe of Evocation
14151 2 Chanting Blade
14152 4 Robe of the Archmage
14153 4 Robe of the Void
14154 4 Truefaith Vestments
14157 1 Pagan Mantle
14158 2 Pagan Vest
14159 2 Pagan Shoes
14160 2 Pagan Bands
14161 2 Pagan Cape
14162 2 Pagan Mitts
14163 2 Pagan Wraps
14164 2 Pagan Belt
14165 2 Pagan Britches
14166 2 Buccaneer's Bracers
14167 2 Buccaneer's Cape
14168 2 Buccaneer's Gloves
14169 1 Aboriginal Shoulder Pads
14170 1 Buccaneer's Mantle
14171 2 Buccaneer's Pants
14172 2 Buccaneer's Robes
14173 2 Buccaneer's Cord
14174 2 Buccaneer's Boots
14175 2 Buccaneer's Vest
14176 2 Watcher's Boots
14177 2 Watcher's Cuffs
14178 2 Watcher's Cap
14179 2 Watcher's Cape
14180 2 Watcher's Jerkin
14181 2 Watcher's Handwraps
14182 2 Watcher's Mantle
14183 2 Watcher's Leggings
14184 2 Watcher's Robes
14185 2 Watcher's Cinch
14186 2 Raincaller Mantle
14187 2 Raincaller Cuffs
14188 2 Raincaller Cloak
14189 2 Raincaller Cap
14190 2 Raincaller Vest
14191 2 Raincaller Mitts
14192 2 Raincaller Robes
14193 2 Raincaller Pants
14194 2 Raincaller Cord
14195 2 Raincaller Boots
14196 2 Thistlefur Sandals
14197 2 Thistlefur Bands
14198 2 Thistlefur Cloak
14199 2 Thistlefur Gloves
14200 2 Thistlefur Cap
14201 2 Thistlefur Mantle
14202 2 Thistlefur Jerkin
14203 2 Thistlefur Pants
14204 2 Thistlefur Robe
14205 2 Thistlefur Belt
14206 2 Vital Bracelets
14207 2 Vital Leggings
14208 2 Vital Headband
14209 2 Vital Sash
14210 2 Vital Cape
14211 2 Vital Handwraps
14212 2 Vital Shoulders
14213 2 Vital Raiment
14214 2 Vital Boots
14215 2 Vital Tunic
14216 2 Geomancer's Jerkin
14217 2 Geomancer's Cord
14218 2 Geomancer's Boots
14219 2 Geomancer's Cloak
14220 2 Geomancer's Cap
14221 2 Geomancer's Bracers
14222 2 Geomancer's Gloves
14223 2 Geomancer's Spaulders
14224 2 Geomancer's Trousers
14225 2 Geomancer's Wraps
14226 2 Embersilk Bracelets
14228 2 Embersilk Coronet
14229 2 Embersilk Cloak
14230 2 Embersilk Tunic
14231 2 Embersilk Mitts
14232 2 Embersilk Mantle
14233 2 Embersilk Leggings
14234 2 Embersilk Robes
14235 2 Embersilk Cord
14236 2 Embersilk Boots
14237 2 Darkmist Armor
14238 2 Darkmist Boots
14239 2 Darkmist Cape
14240 2 Darkmist Bands
14241 2 Darkmist Handguards
14242 2 Darkmist Pants
14243 2 Darkmist Mantle
14244 2 Darkmist Wraps
14245 2 Darkmist Girdle
14246 2 Darkmist Wizard Hat
14247 2 Lunar Mantle
14248 2 Lunar Bindings
14249 2 Lunar Vest
14250 2 Lunar Slippers
14251 2 Lunar Cloak
14252 2 Lunar Coronet
14253 2 Lunar Handwraps
14254 2 Lunar Raiment
14255 2 Lunar Belt
14257 2 Lunar Leggings
14258 2 Bloodwoven Cord
14259 2 Bloodwoven Boots
14260 2 Bloodwoven Bracers
14261 2 Bloodwoven Cloak
14262 2 Bloodwoven Mitts
14263 2 Bloodwoven Mask
14264 2 Bloodwoven Pants
14265 2 Bloodwoven Wraps
14266 2 Bloodwoven Pads
14267 2 Bloodwoven Jerkin
14268 2 Gaea's Cuffs
14269 2 Gaea's Slippers
14270 2 Gaea's Cloak
14271 2 Gaea's Circlet
14272 2 Gaea's Handwraps
14273 2 Gaea's Amice
14274 2 Gaea's Leggings
14275 2 Gaea's Raiment
14276 2 Gaea's Belt
14277 2 Gaea's Tunic
14278 2 Opulent Mantle
14279 2 Opulent Bracers
14280 2 Opulent Cape
14281 2 Opulent Crown
14282 2 Opulent Gloves
14283 2 Opulent Leggings
14284 2 Opulent Robes
14285 2 Opulent Boots
14286 2 Opulent Belt
14287 2 Opulent Tunic
14288 2 Arachnidian Armor
14289 2 Arachnidian Girdle
14290 2 Arachnidian Footpads
14291 2 Arachnidian Bracelets
14292 2 Arachnidian Cape
14293 2 Arachnidian Circlet
14294 2 Arachnidian Gloves
14295 2 Arachnidian Legguards
14296 2 Arachnidian Pauldrons
14297 2 Arachnidian Robes
14298 2 Bonecaster's Spaulders
14299 2 Bonecaster's Boots
14300 2 Bonecaster's Cape
14301 2 Bonecaster's Bindings
14302 2 Bonecaster's Gloves
14303 2 Bonecaster's Shroud
14304 2 Bonecaster's Belt
14305 2 Bonecaster's Sarong
14306 2 Bonecaster's Vest
14307 2 Bonecaster's Crown
14308 2 Celestial Tunic
14309 2 Celestial Belt
14310 2 Celestial Slippers
14311 2 Celestial Bindings
14312 2 Celestial Crown
14313 2 Celestial Cape
14314 2 Celestial Handwraps
14315 2 Celestial Kilt
14316 2 Celestial Pauldrons
14317 2 Celestial Silk Robes
14318 2 Resplendent Tunic
14319 2 Resplendent Boots
14320 2 Resplendent Bracelets
14321 2 Resplendent Cloak
14322 2 Resplendent Circlet
14323 2 Resplendent Gauntlets
14324 2 Resplendent Sarong
14325 2 Resplendent Epaulets
14326 2 Resplendent Robes
14327 2 Resplendent Belt
14328 2 Eternal Chestguard
14329 2 Eternal Boots
14330 2 Eternal Bindings
14331 2 Eternal Cloak
14332 2 Eternal Crown
14333 2 Eternal Gloves
14334 2 Eternal Sarong
14335 2 Eternal Spaulders
14336 2 Eternal Wraps
14337 2 Eternal Cord
14340 3 Freezing Lich Robes
14364 2 Mystic's Slippers
14365 2 Mystic's Cape
14366 2 Mystic's Bracelets
14367 2 Mystic's Gloves
14368 1 Mystic's Shoulder Pads
14369 2 Mystic's Wrap
14370 2 Mystic's Woolies
14371 2 Mystic's Robe
14372 2 Sanguine Armor
14373 2 Sanguine Belt
14374 2 Sanguine Sandals
14375 2 Sanguine Cuffs
14376 2 Sanguine Cape
14377 2 Sanguine Handwraps
14378 2 Sanguine Mantle
14379 2 Sanguine Trousers
14380 2 Sanguine Robe
14382 1 Durability Chestpiece
14383 1 Durability Bracers
14384 1 Durability Boots
14385 1 Durability Cloak
14386 1 Durability Hat
14387 1 Durability Gloves
14388 1 Durability Leggings
14389 3 Durability Shoulderpads
14390 1 Durability Belt
14391 1 Durability Sword
14392 1 Durability Staff
14393 1 Durability Shield
14394 1 Durability Bow
14397 2 Resilient Mantle
14398 2 Resilient Tunic
14399 2 Resilient Boots
14400 2 Resilient Cape
14401 2 Resilient Cap
14402 2 Resilient Bands
14403 2 Resilient Handgrips
14404 2 Resilient Leggings
14405 2 Resilient Robe
14406 2 Resilient Cord
14407 2 Stonecloth Vest
14408 2 Stonecloth Boots
14409 2 Stonecloth Cape
14410 2 Stonecloth Circlet
14411 2 Stonecloth Gloves
14412 2 Stonecloth Epaulets
14413 2 Stonecloth Robe
14414 2 Stonecloth Belt
14415 2 Stonecloth Britches
14416 2 Stonecloth Bindings
14417 2 Silksand Tunic
14418 2 Silksand Boots
14419 2 Silksand Bracers
14420 2 Silksand Cape
14421 2 Silksand Circlet
14422 2 Silksand Gloves
14423 2 Silksand Shoulder Pads
14424 2 Silksand Legwraps
14425 2 Silksand Wraps
14426 2 Silksand Girdle
14427 2 Windchaser Wraps
14428 2 Windchaser Footpads
14429 2 Windchaser Cuffs
14430 2 Windchaser Cloak
14431 2 Windchaser Handguards
14432 2 Windchaser Amice
14433 2 Windchaser Woolies
14434 2 Windchaser Robes
14435 2 Windchaser Cinch
14436 2 Windchaser Coronet
14437 2 Venomshroud Vest
14438 2 Venomshroud Boots
14439 2 Venomshroud Armguards
14440 2 Venomshroud Cape
14441 2 Venomshroud Mask
14442 2 Venomshroud Mitts
14443 2 Venomshroud Mantle
14444 2 Venomshroud Leggings
14445 2 Venomshroud Silk Robes
14446 2 Venomshroud Belt
14447 2 Highborne Footpads
14448 2 Highborne Bracelets
14449 2 Highborne Crown
14450 2 Highborne Cloak
14451 2 Highborne Gloves
14452 2 Highborne Pauldrons
14453 2 Highborne Robes
14454 2 Highborne Cord
14455 2 Highborne Padded Armor
14456 2 Elunarian Vest
14457 2 Elunarian Cuffs
14458 2 Elunarian Boots
14459 2 Elunarian Cloak
14460 2 Elunarian Diadem
14461 2 Elunarian Handgrips
14462 2 Elunarian Sarong
14463 2 Elunarian Spaulders
14464 2 Elunarian Silk Robes
14465 2 Elunarian Belt
14487 3 Bonechill Hammer
14502 3 Frostbite Girdle
14503 3 Death's Clutch
14522 3 Maelstrom Leggings
14525 3 Boneclenched Gauntlets
14528 3 Rattlecage Buckler
14531 3 Frightskull Shaft
14536 3 Bonebrace Hauberk
14537 3 Corpselight Greaves
14538 3 Deadwalker Mantle
14539 3 Bone Ring Helm
14541 3 Barovian Family Sword
14543 3 Darkshade Gloves
14545 3 Ghostloom Leggings
14548 3 Royal Cap Spaulders
14549 4 Boots of Avoidance
14550 4 Bladebane Armguards
14551 4 Edgemaster's Handguards
14552 4 Stockade Pauldrons
14553 4 Sash of Mercy
14554 4 Cloudkeeper Legplates
14555 4 Alcor's Sunrazor
14557 4 The Lion Horn of Stormwind
14558 4 Lady Maye's Pendant
14559 2 Prospector's Sash
14560 2 Prospector's Boots
14561 2 Prospector's Cuffs
14562 2 Prospector's Chestpiece
14563 2 Prospector's Cloak
14564 2 Prospector's Mitts
14565 2 Prospector's Woolies
14566 2 Prospector's Pads
14567 2 Bristlebark Belt
14568 2 Bristlebark Boots
14569 2 Bristlebark Bindings
14570 2 Bristlebark Blouse
14571 2 Bristlebark Cape
14572 2 Bristlebark Gloves
14573 2 Bristlebark Amice
14574 2 Bristlebark Britches
14576 3 Ebon Hilt of Marduk
14577 3 Skullsmoke Pants
14578 2 Dokebi Cord
14579 2 Dokebi Boots
14580 2 Dokebi Bracers
14581 2 Dokebi Chestguard
14582 2 Dokebi Cape
14583 2 Dokebi Gloves
14584 2 Dokebi Hat
14585 2 Dokebi Leggings
14587 2 Dokebi Mantle
14588 2 Hawkeye's Cord
14589 2 Hawkeye's Shoes
14590 2 Hawkeye's Bracers
14591 2 Hawkeye's Helm
14592 2 Hawkeye's Tunic
14593 2 Hawkeye's Cloak
14594 2 Hawkeye's Gloves
14595 2 Hawkeye's Breeches
14596 2 Hawkeye's Epaulets
14598 2 Warden's Waistband
14599 2 Warden's Footpads
14600 2 Warden's Wristbands
14601 2 Warden's Wraps
14602 2 Warden's Cloak
14603 2 Warden's Mantle
14604 2 Warden's Wizard Hat
14605 2 Warden's Woolies
14606 2 Warden's Gloves
14607 2 Hawkeye's Buckler
14608 2 Dokebi Buckler
14611 3 Bloodmail Hauberk
14612 3 Bloodmail Legguards
14614 3 Bloodmail Belt
14615 3 Bloodmail Gauntlets
14616 3 Bloodmail Boots
14617 1 Sawbones Shirt
14620 3 Deathbone Girdle
14621 3 Deathbone Sabatons
14622 3 Deathbone Gauntlets
14623 3 Deathbone Legguards
14624 3 Deathbone Chestplate
14626 3 Necropile Robe
14629 3 Necropile Cuffs
14631 3 Necropile Boots
14632 3 Necropile Leggings
14633 3 Necropile Mantle
14636 3 Cadaverous Belt
14637 3 Cadaverous Armor
14638 3 Cadaverous Leggings
14640 3 Cadaverous Gloves
14641 3 Cadaverous Walkers
14652 2 Scorpashi Sash
14653 2 Scorpashi Slippers
14654 2 Scorpashi Wristbands
14655 2 Scorpashi Breastplate
14656 2 Scorpashi Cape
14657 2 Scorpashi Gloves
14658 2 Scorpashi Skullcap
14659 2 Scorpashi Leggings
14660 2 Scorpashi Shoulder Pads
14661 2 Keeper's Cord
14662 2 Keeper's Hooves
14663 2 Keeper's Bindings
14664 2 Keeper's Armor
14665 2 Keeper's Cloak
14666 2 Keeper's Gloves
14667 2 Keeper's Wreath
14668 2 Keeper's Woolies
14669 2 Keeper's Mantle
14670 2 Pridelord Armor
14671 2 Pridelord Boots
14672 2 Pridelord Bands
14673 2 Pridelord Cape
14674 2 Pridelord Girdle
14675 2 Pridelord Gloves
14676 2 Pridelord Halo
14677 2 Pridelord Pants
14678 2 Pridelord Pauldrons
14680 2 Indomitable Vest
14681 2 Indomitable Boots
14682 2 Indomitable Armguards
14683 2 Indomitable Cloak
14684 2 Indomitable Belt
14685 2 Indomitable Gauntlets
14686 2 Indomitable Headdress
14687 2 Indomitable Leggings
14688 2 Indomitable Epaulets
14722 2 War Paint Anklewraps
14723 2 War Paint Bindings
14724 2 War Paint Cloak
14725 2 War Paint Waistband
14726 2 War Paint Gloves
14727 2 War Paint Legguards
14728 1 War Paint Shoulder Pads
14729 2 War Paint Shield
14730 2 War Paint Chestpiece
14742 2 Hulking Boots
14743 2 Hulking Bands
14744 2 Hulking Chestguard
14745 2 Hulking Cloak
14746 2 Hulking Belt
14747 2 Hulking Gauntlets
14748 2 Hulking Leggings
14749 2 Hulking Spaulders
14750 2 Slayer's Cuffs
14751 2 Slayer's Surcoat
14752 2 Slayer's Cape
14753 2 Slayer's Skullcap
14754 2 Slayer's Gloves
14755 2 Slayer's Sash
14756 2 Slayer's Slippers
14757 2 Slayer's Pants
14758 2 Slayer's Shoulder Pads
14759 2 Enduring Bracers
14760 2 Enduring Breastplate
14761 2 Enduring Belt
14762 2 Enduring Boots
14763 2 Enduring Cape
14764 2 Enduring Gauntlets
14765 2 Enduring Circlet
14766 2 Enduring Breeches
14767 2 Enduring Pauldrons
14768 2 Ravager's Armor
14769 2 Ravager's Sandals
14770 2 Ravager's Armguards
14771 2 Ravager's Cloak
14772 2 Ravager's Handwraps
14773 2 Ravager's Cord
14774 2 Ravager's Crown
14775 2 Ravager's Woolies
14776 2 Ravager's Mantle
14777 2 Ravager's Shield
14778 2 Khan's Bindings
14779 2 Khan's Chestpiece
14780 2 Khan's Buckler
14781 2 Khan's Cloak
14782 2 Khan's Gloves
14783 2 Khan's Belt
14784 2 Khan's Greaves
14785 2 Khan's Helmet
14786 2 Khan's Legguards
14787 2 Khan's Mantle
14788 2 Protector Armguards
14789 2 Protector Breastplate
14790 2 Protector Buckler
14791 2 Protector Cape
14792 2 Protector Gauntlets
14793 2 Protector Waistband
14794 2 Protector Ankleguards
14795 2 Protector Helm
14796 2 Protector Legguards
14797 2 Protector Pads
14798 2 Bloodlust Breastplate
14799 2 Bloodlust Boots
14800 2 Bloodlust Buckler
14801 2 Bloodlust Cape
14802 2 Bloodlust Gauntlets
14803 2 Bloodlust Belt
14804 2 Bloodlust Helm
14805 2 Bloodlust Britches
14806 2 Bloodlust Epaulets
14807 2 Bloodlust Bracelets
14808 2 Warstrike Belt
14809 2 Warstrike Sabatons
14810 2 Warstrike Armsplints
14811 2 Warstrike Chestguard
14812 2 Warstrike Buckler
14813 2 Warstrike Cape
14814 2 Warstrike Helmet
14815 2 Warstrike Gauntlets
14816 2 Warstrike Legguards
14817 2 Warstrike Shoulder Pads
14821 2 Symbolic Breastplate
14825 2 Symbolic Crest
14826 2 Symbolic Gauntlets
14827 2 Symbolic Belt
14828 2 Symbolic Greaves
14829 2 Symbolic Legplates
14830 2 Symbolic Pauldrons
14831 2 Symbolic Crown
14832 2 Symbolic Vambraces
14833 2 Tyrant's Gauntlets
14834 2 Tyrant's Armguards
14835 2 Tyrant's Chestpiece
14838 2 Tyrant's Belt
14839 2 Tyrant's Greaves
14840 2 Tyrant's Legplates
14841 2 Tyrant's Epaulets
14842 2 Tyrant's Shield
14843 2 Tyrant's Helm
14844 2 Sunscale Chestguard
14846 2 Sunscale Gauntlets
14847 2 Sunscale Belt
14848 2 Sunscale Sabatons
14849 2 Sunscale Helmet
14850 2 Sunscale Legplates
14851 2 Sunscale Spaulders
14852 2 Sunscale Shield
14853 2 Sunscale Wristguards
14854 2 Vanguard Breastplate
14855 2 Vanguard Gauntlets
14856 2 Vanguard Girdle
14857 2 Vanguard Sabatons
14858 2 Vanguard Headdress
14859 2 Vanguard Legplates
14860 2 Vanguard Pauldrons
14861 2 Vanguard Vambraces
14862 2 Warleader's Breastplate
14863 2 Warleader's Gauntlets
14864 2 Warleader's Belt
14865 2 Warleader's Greaves
14866 2 Warleader's Crown
14867 2 Warleader's Leggings
14868 2 Warleader's Shoulders
14869 2 Warleader's Bracers
14895 2 Saltstone Surcoat
14896 2 Saltstone Sabatons
14897 2 Saltstone Gauntlets
14898 2 Saltstone Girdle
14899 2 Saltstone Helm
14900 2 Saltstone Legplates
14901 2 Saltstone Shoulder Pads
14902 2 Saltstone Shield
14903 2 Saltstone Armsplints
14904 2 Brutish Breastplate
14905 2 Brutish Gauntlets
14906 2 Brutish Belt
14907 2 Brutish Helmet
14908 2 Brutish Legguards
14909 2 Brutish Shoulders
14910 2 Brutish Armguards
14911 2 Brutish Boots
14912 2 Brutish Shield
14913 2 Jade Greaves
14914 2 Jade Bracers
14915 2 Jade Breastplate
14916 2 Jade Deflector
14917 2 Jade Gauntlets
14918 2 Jade Belt
14919 2 Jade Circlet
14920 2 Jade Legplates
14921 2 Jade Epaulets
14922 2 Lofty Sabatons
14923 2 Lofty Armguards
14924 2 Lofty Breastplate
14925 2 Lofty Helm
14926 2 Lofty Gauntlets
14927 2 Lofty Belt
14928 2 Lofty Legguards
14929 2 Lofty Shoulder Pads
14930 2 Lofty Shield
14931 2 Heroic Armor
14932 2 Heroic Greaves
14933 2 Heroic Gauntlets
14934 2 Heroic Girdle
14935 2 Heroic Skullcap
14936 2 Heroic Legplates
14937 2 Heroic Pauldrons
14938 2 Heroic Bracers
14939 2 Warbringer's Chestguard
14940 2 Warbringer's Sabatons 
14941 2 Warbringer's Armsplints
14942 2 Warbringer's Gauntlets
14943 2 Warbringer's Belt
14944 2 Warbringer's Crown
14945 2 Warbringer's Legguards
14946 2 Warbringer's Spaulders
14947 2 Warbringer's Shield
14948 2 Bloodforged Chestpiece
14949 2 Bloodforged Gauntlets
14950 2 Bloodforged Belt
14951 2 Bloodforged Sabatons
14952 2 Bloodforged Helmet
14953 2 Bloodforged Legplates
14954 2 Bloodforged Shield
14955 2 Bloodforged Shoulder Pads
14956 2 Bloodforged Bindings
14957 2 High Chief's Sabatons
14958 2 High Chief's Armor
14959 2 High Chief's Gauntlets
14960 2 High Chief's Belt
14961 2 High Chief's Crown
14962 2 High Chief's Legguards
14963 2 High Chief's Pauldrons
14964 2 High Chief's Shield
14965 2 High Chief's Bindings
14966 2 Glorious Breastplate
14967 2 Glorious Gauntlets
14968 2 Glorious Belt
14969 2 Glorious Headdress
14970 2 Glorious Legplates
14971 2 Glorious Shoulder Pads
14972 2 Glorious Sabatons
14973 2 Glorious Shield
14974 2 Glorious Bindings
14975 2 Exalted Harness
14976 2 Exalted Gauntlets
14977 2 Exalted Girdle
14978 2 Exalted Sabatons
14979 2 Exalted Helmet
14980 2 Exalted Legplates
14981 2 Exalted Epaulets
14982 2 Exalted Shield
14983 2 Exalted Armsplints
15003 1 Primal Belt
15004 1 Primal Boots
15005 1 Primal Bands
15006 1 Primal Buckler
15007 1 Primal Cape
15008 1 Primal Mitts
15009 2 Primal Leggings
15010 2 Primal Wraps
15011 2 Lupine Cord
15012 2 Lupine Slippers
15013 1 Lupine Cuffs
15014 2 Lupine Buckler
15015 1 Lupine Cloak
15016 2 Lupine Handwraps
15017 2 Lupine Leggings
15018 2 Lupine Vest
15019 1 Lupine Mantle
15045 3 Green Dragonscale Breastplate
15046 3 Green Dragonscale Leggings
15047 3 Red Dragonscale Breastplate
15048 3 Blue Dragonscale Breastplate
15049 3 Blue Dragonscale Shoulders
15050 3 Black Dragonscale Breastplate
15051 3 Black Dragonscale Shoulders
15052 3 Black Dragonscale Leggings
15053 2 Volcanic Breastplate
15054 2 Volcanic Leggings
15055 2 Volcanic Shoulders
15056 3 Stormshroud Armor
15057 3 Stormshroud Pants
15058 3 Stormshroud Shoulders
15059 3 Living Breastplate
15060 3 Living Leggings
15061 3 Living Shoulders
15062 3 Devilsaur Leggings
15063 3 Devilsaur Gauntlets
15064 3 Warbear Harness
15065 3 Warbear Woolies
15066 3 Ironfeather Breastplate
15067 3 Ironfeather Shoulders
15068 2 Frostsaber Tunic
15069 2 Frostsaber Leggings
15070 2 Frostsaber Gloves
15071 2 Frostsaber Boots
15072 2 Chimeric Leggings
15073 2 Chimeric Boots
15074 2 Chimeric Gloves
15075 2 Chimeric Vest
15076 2 Heavy Scorpid Vest
15077 2 Heavy Scorpid Bracers
15078 2 Heavy Scorpid Gauntlet
15079 2 Heavy Scorpid Leggings
15080 2 Heavy Scorpid Helm
15081 2 Heavy Scorpid Shoulders
15082 2 Heavy Scorpid Belt
15083 2 Wicked Leather Gauntlets
15084 2 Wicked Leather Bracers
15085 2 Wicked Leather Armor
15086 2 Wicked Leather Headband
15087 2 Wicked Leather Pants
15088 2 Wicked Leather Belt
15090 2 Runic Leather Armor
15091 2 Runic Leather Gauntlets
15092 2 Runic Leather Bracers
15093 2 Runic Leather Belt
15094 2 Runic Leather Headband
15095 2 Runic Leather Pants
15096 2 Runic Leather Shoulders
15104 2 Wingborne Boots
15105 2 Staff of Noh'Orahil
15106 2 Staff of Dar'Orahil
15107 3 Orb of Noh'Orahil
15108 3 Orb of Dar'Orahil
15109 2 Staff of Soran'ruk
15110 2 Rigid Belt
15111 2 Rigid Moccasins
15112 2 Rigid Bracelets
15113 2 Rigid Buckler
15114 2 Rigid Cape
15115 2 Rigid Gloves
15116 2 Rigid Shoulders
15117 2 Rigid Leggings
15118 2 Rigid Tunic
15119 2 Highborne Pants
15120 2 Robust Girdle
15121 2 Robust Boots
15122 2 Robust Bracers
15123 2 Robust Buckler
15124 2 Robust Cloak
15125 2 Robust Gloves
15126 2 Robust Leggings
15127 2 Robust Shoulders
15128 2 Robust Tunic
15129 2 Robust Helm
15130 2 Cutthroat's Vest
15131 2 Cutthroat's Boots
15132 2 Cutthroat's Armguards
15133 2 Cutthroat's Buckler
15134 2 Cutthroat's Hat
15135 2 Cutthroat's Cape
15136 2 Cutthroat's Belt
15137 2 Cutthroat's Mitts
15138 3 Onyxia Scale Cloak
15139 2 Cutthroat's Pants
15140 2 Cutthroat's Mantle
15141 4 Onyxia Scale Breastplate
15142 2 Ghostwalker Boots
15143 2 Ghostwalker Bindings
15144 2 Ghostwalker Rags
15145 2 Ghostwalker Buckler
15146 2 Ghostwalker Crown
15147 2 Ghostwalker Cloak
15148 2 Ghostwalker Belt
15149 2 Ghostwalker Gloves
15150 2 Ghostwalker Pads
15151 2 Ghostwalker Legguards
15152 2 Nocturnal Shoes
15153 2 Nocturnal Cloak
15154 2 Nocturnal Sash
15155 2 Nocturnal Gloves
15156 2 Nocturnal Cap
15157 2 Nocturnal Leggings
15158 2 Nocturnal Shoulder Pads
15159 2 Nocturnal Tunic
15160 2 Nocturnal Wristbands
15161 2 Imposing Belt
15162 2 Imposing Boots
15163 2 Imposing Bracers
15164 2 Imposing Vest
15165 2 Imposing Cape
15166 2 Imposing Gloves
15167 2 Imposing Bandana
15168 2 Imposing Pants
15169 2 Imposing Shoulders
15170 2 Potent Armor
15171 2 Potent Boots
15172 2 Potent Bands
15173 2 Potent Cape
15174 2 Potent Gloves
15175 2 Potent Helmet
15176 2 Potent Pants
15177 2 Potent Shoulders
15178 2 Potent Belt
15179 2 Praetorian Padded Armor
15180 2 Praetorian Girdle
15181 2 Praetorian Boots
15182 2 Praetorian Wristbands
15183 2 Praetorian Cloak
15184 2 Praetorian Gloves
15185 2 Praetorian Coif
15186 2 Praetorian Leggings
15187 2 Praetorian Pauldrons
15188 2 Grand Armguards
15189 2 Grand Boots
15190 2 Grand Cloak
15191 2 Grand Belt
15192 2 Grand Gauntlets
15193 2 Grand Crown
15194 2 Grand Legguards
15195 2 Grand Breastplate
15196 1 Private's Tabard
15197 1 Scout's Tabard
15198 1 Knight's Colors
15199 1 Stone Guard's Herald
15200 3 Senior Sergeant's Insignia
15202 2 Wildkeeper Leggings
15203 2 Guststorm Legguards
15204 2 Moonstone Wand
15205 2 Owlsight Rifle
15206 2 Jadefinger Baton
15207 2 Steelcap Shield
15210 2 Raider Shortsword
15211 2 Militant Shortsword
15212 2 Fighter Broadsword
15213 2 Mercenary Blade
15214 2 Nobles Brand
15215 2 Furious Falchion
15216 2 Rune Sword
15217 2 Widow Blade
15218 2 Crystal Sword
15219 2 Dimensional Blade
15220 2 Battlefell Sabre
15221 2 Holy War Sword
15222 2 Barbed Club
15223 2 Jagged Star
15224 2 Battlesmasher
15225 2 Sequoia Hammer
15226 2 Giant Club
15227 2 Diamond-Tip Bludgeon
15228 2 Smashing Star
15229 2 Blesswind Hammer
15230 2 Ridge Cleaver
15231 2 Splitting Hatchet
15232 2 Hacking Cleaver
15233 2 Savage Axe
15234 2 Greater Scythe
15235 2 Crescent Edge
15236 2 Moon Cleaver
15237 2 Corpse Harvester
15238 2 Warlord's Axe
15239 2 Felstone Reaver
15240 2 Demon's Claw
15241 2 Battle Knife
15242 2 Honed Stiletto
15243 2 Deadly Kris
15244 2 Razor Blade
15245 2 Vorpal Dagger
15246 2 Demon Blade
15247 2 Bloodstrike Dagger
15248 2 Gleaming Claymore
15249 2 Polished Zweihander
15250 2 Glimmering Flamberge
15251 2 Headstriker Sword
15252 2 Tusker Sword
15253 2 Beheading Blade
15254 2 Dark Espadon
15255 2 Gallant Flamberge
15256 2 Massacre Sword
15257 2 Shin Blade
15258 2 Divine Warblade
15259 2 Hefty Battlehammer
15260 2 Stone Hammer
15261 2 Sequoia Branch
15262 2 Greater Maul
15263 2 Royal Mallet
15264 2 Backbreaker
15265 2 Painbringer
15266 2 Fierce Mauler
15267 2 Brutehammer
15268 2 Twin-bladed Axe
15269 2 Massive Battle Axe
15270 2 Gigantic War Axe
15271 2 Colossal Great Axe
15272 2 Razor Axe
15273 2 Death Striker
15274 2 Diviner Long Staff
15275 2 Thaumaturgist Staff
15276 2 Magus Long Staff
15278 2 Solstice Staff
15279 2 Ivory Wand
15280 2 Wizard's Hand
15281 2 Glowstar Rod
15282 2 Dragon Finger
15283 2 Lunar Wand
15284 2 Long Battle Bow
15285 2 Archer's Longbow
15286 2 Long Redwood Bow
15287 2 Crusader Bow
15288 2 Blasthorn Bow
15289 2 Archstrike Bow
15291 2 Harpy Needler
15294 2 Siege Bow
15295 2 Quillfire Bow
15296 2 Hawkeye Bow
15297 1 Grizzly Bracers
15298 2 Grizzly Buckler
15299 1 Grizzly Cape
15300 1 Grizzly Gloves
15301 1 Grizzly Slippers
15302 1 Grizzly Belt
15303 2 Grizzly Pants
15304 2 Grizzly Jerkin
15305 2 Feral Shoes
15306 2 Feral Bindings
15307 2 Feral Buckler
15308 2 Feral Cord
15309 2 Feral Cloak
15310 2 Feral Gloves
15311 2 Feral Harness
15312 2 Feral Leggings
15313 1 Feral Shoulder Pads
15322 2 Smoothbore Gun
15323 2 Percussion Shotgun
15324 2 Burnside Rifle
15325 2 Sharpshooter Harquebus
15326 1 Gleaming Throwing Axe
15327 1 Wicked Throwing Dagger
15329 2 Wrangler's Belt
15330 2 Wrangler's Boots
15331 2 Wrangler's Wristbands
15332 2 Wrangler's Buckler
15333 2 Wrangler's Cloak
15334 2 Wrangler's Gloves
15335 2 Briarsteel Shortsword
15336 2 Wrangler's Leggings
15337 2 Wrangler's Wraps
15338 2 Wrangler's Mantle
15339 2 Pathfinder Hat
15340 2 Pathfinder Cloak
15341 2 Pathfinder Footpads
15342 2 Pathfinder Guard
15343 2 Pathfinder Gloves
15344 2 Pathfinder Pants
15345 2 Pathfinder Shoulder Pads
15346 2 Pathfinder Vest
15347 2 Pathfinder Belt
15348 2 Pathfinder Bracers
15349 2 Headhunter's Belt
15350 2 Headhunter's Slippers
15351 2 Headhunter's Bands
15352 2 Headhunter's Buckler
15353 2 Headhunter's Headdress
15354 2 Headhunter's Cloak
15355 2 Headhunter's Mitts
15356 2 Headhunter's Armor
15357 2 Headhunter's Spaulders
15358 2 Headhunter's Woolies
15359 2 Trickster's Vest
15360 2 Trickster's Bindings
15361 2 Trickster's Sash
15362 2 Trickster's Boots
15363 2 Trickster's Headdress
15364 2 Trickster's Cloak
15365 2 Trickster's Handwraps
15366 2 Trickster's Leggings
15367 2 Trickster's Protector
15368 2 Trickster's Pauldrons
15369 2 Wolf Rider's Belt
15370 2 Wolf Rider's Boots
15371 2 Wolf Rider's Cloak
15372 2 Wolf Rider's Gloves
15373 2 Wolf Rider's Headgear
15374 2 Wolf Rider's Leggings
15375 2 Wolf Rider's Shoulder Pads
15376 2 Wolf Rider's Padded Armor
15377 2 Wolf Rider's Wristbands
15378 2 Rageclaw Belt
15379 2 Rageclaw Boots
15380 2 Rageclaw Bracers
15381 2 Rageclaw Chestguard
15382 2 Rageclaw Cloak
15383 2 Rageclaw Gloves
15384 2 Rageclaw Helm
15385 2 Rageclaw Leggings
15386 2 Rageclaw Shoulder Pads
15387 2 Jadefire Bracelets
15388 2 Jadefire Belt
15389 2 Jadefire Sabatons
15390 2 Jadefire Chestguard
15391 2 Jadefire Cap
15392 2 Jadefire Cloak
15393 2 Jadefire Gloves
15394 2 Jadefire Pants
15395 2 Jadefire Epaulets
15396 2 Curvewood Dagger
15397 2 Oakthrush Staff
15398 1 Sandcomber Boots
15399 2 Dryweed Belt
15400 1 Clamshell Bracers
15401 1 Welldrip Gloves
15402 1 Noosegrip Gauntlets
15403 2 Ridgeback Bracers
15404 2 Breakwater Girdle
15405 2 Shucking Gloves
15406 2 Crustacean Boots
15411 3 Mark of Fordring
15413 3 Ornate Adamantium Breastplate
15418 3 Shimmering Platinum Warhammer
15421 3 Shroud of the Exile
15424 2 Axe of Orgrimmar
15425 2 Peerless Bracers
15426 2 Peerless Boots
15427 2 Peerless Cloak
15428 2 Peerless Belt
15429 2 Peerless Gloves
15430 2 Peerless Headband
15431 2 Peerless Leggings
15432 2 Peerless Shoulders
15433 2 Peerless Armor
15434 2 Supreme Sash
15435 2 Supreme Shoes
15436 2 Supreme Bracers
15437 2 Supreme Cape
15438 2 Supreme Gloves
15439 2 Supreme Crown
15440 2 Supreme Leggings
15441 2 Supreme Shoulders
15442 2 Supreme Breastplate
15443 2 Kris of Orgrimmar
15444 2 Staff of Orgrimmar
15445 2 Hammer of Orgrimmar
15449 2 Ghastly Trousers
15450 2 Dredgemire Leggings
15451 2 Gargoyle Leggings
15452 2 Featherbead Bracers
15453 2 Savannah Bracers
15455 2 Dustfall Robes
15456 2 Lightstep Leggings
15457 2 Desert Shoulders
15458 2 Tundra Boots
15459 2 Grimtoll Wristguards
15461 2 Lightheel Boots
15462 2 Loamflake Bracers
15463 2 Palestrider Gloves
15464 2 Brute Hammer
15465 2 Stingshot Wand
15466 2 Clink Shield
15467 2 Inventor's League Ring
15468 2 Windsong Drape
15469 2 Windsong Cinch
15470 2 Plainsguard Leggings
15471 2 Brawnhide Armor
15472 1 Charger's Belt
15473 1 Charger's Boots
15474 1 Charger's Bindings
15475 1 Charger's Cloak
15476 1 Charger's Handwraps
15477 2 Charger's Pants
15478 1 Charger's Shield
15479 2 Charger's Armor
15480 1 War Torn Girdle
15481 1 War Torn Greaves
15482 1 War Torn Bands
15483 1 War Torn Cape
15484 1 War Torn Handgrips
15485 2 War Torn Pants
15486 2 War Torn Shield
15487 2 War Torn Tunic
15488 2 Bloodspattered Surcoat
15489 2 Bloodspattered Sabatons
15490 1 Bloodspattered Cloak
15491 2 Bloodspattered Gloves
15492 2 Bloodspattered Sash
15493 2 Bloodspattered Loincloth
15494 2 Bloodspattered Shield
15495 2 Bloodspattered Wristbands
15496 1 Bloodspattered Shoulder Pads
15497 2 Outrunner's Cord
15498 2 Outrunner's Slippers
15499 2 Outrunner's Cuffs
15500 2 Outrunner's Chestguard
15501 2 Outrunner's Cloak
15502 2 Outrunner's Gloves
15503 2 Outrunner's Legguards
15504 2 Outrunner's Shield
15505 1 Outrunner's Pauldrons
15506 2 Grunt's AnkleWraps
15507 2 Grunt's Bracers
15508 2 Grunt's Cape
15509 2 Grunt's Handwraps
15510 2 Grunt's Belt
15511 2 Grunt's Legguards
15512 2 Grunt's Shield
15513 2 Grunt's Pauldrons
15514 2 Grunt's Chestpiece
15515 2 Spiked Chain Belt
15516 2 Spiked Chain Slippers
15517 2 Spiked Chain Wristbands
15518 2 Spiked Chain Breastplate
15519 2 Spiked Chain Cloak
15520 2 Spiked Chain Gauntlets
15521 2 Spiked Chain Leggings
15522 2 Spiked Chain Shield
15523 2 Spiked Chain Shoulder Pads
15524 2 Sentry's Surcoat
15525 2 Sentry's Slippers
15526 2 Sentry's Cape
15527 2 Sentry's Gloves
15528 2 Sentry's Sash
15529 2 Sentry's Leggings
15530 2 Sentry's Shield
15531 2 Sentry's Shoulderguards
15532 2 Sentry's Armsplints
15533 2 Sentry's Headdress
15534 2 Wicked Chain Boots
15535 2 Wicked Chain Bracers
15536 2 Wicked Chain Chestpiece
15537 2 Wicked Chain Cloak
15538 2 Wicked Chain Gauntlets
15539 2 Wicked Chain Waistband
15540 2 Wicked Chain Helmet
15541 2 Wicked Chain Legguards
15542 2 Wicked Chain Shoulder Pads
15543 2 Wicked Chain Shield
15544 2 Thick Scale Sabatons
15545 2 Thick Scale Bracelets
15546 2 Thick Scale Breastplate
15547 2 Thick Scale Cloak
15548 2 Thick Scale Gauntlets
15549 2 Thick Scale Belt
15550 2 Thick Scale Crown
15551 2 Thick Scale Legguards
15552 2 Thick Scale Shield
15553 2 Thick Scale Shoulder Pads
15554 2 Pillager's Girdle
15555 2 Pillager's Boots
15556 2 Pillager's Bracers
15557 2 Pillager's Chestguard
15558 2 Pillager's Crown
15559 2 Pillager's Cloak
15560 2 Pillager's Gloves
15561 2 Pillager's Leggings
15562 2 Pillager's Pauldrons
15563 2 Pillager's Shield
15565 2 Marauder's Boots
15566 2 Marauder's Bracers
15567 2 Marauder's Tunic
15568 2 Marauder's Cloak
15569 2 Marauder's Crest
15570 2 Marauder's Gauntlets
15571 2 Marauder's Belt
15572 2 Marauder's Circlet
15573 2 Marauder's Leggings
15574 2 Marauder's Shoulder Pads
15575 2 Sparkleshell Belt
15576 2 Sparkleshell Sabatons
15577 2 Sparkleshell Bracers
15578 2 Sparkleshell Breastplate
15579 2 Sparkleshell Cloak
15580 2 Sparkleshell Headwrap
15581 2 Sparkleshell Gauntlets
15582 2 Sparkleshell Legguards
15583 2 Sparkleshell Shoulder Pads
15584 2 Sparkleshell Shield
15585 2 Pardoc Grips
15587 2 Ringtail Girdle
15588 2 Bracesteel Belt
15589 2 Steadfast Stompers
15590 2 Steadfast Bracelets
15591 2 Steadfast Breastplate
15592 2 Steadfast Buckler
15593 2 Steadfast Coronet
15594 2 Steadfast Cloak
15595 2 Steadfast Gloves
15596 2 Steadfast Legplates
15597 2 Steadfast Shoulders
15598 2 Steadfast Girdle
15599 2 Ancient Greaves
15600 2 Ancient Vambraces
15601 2 Ancient Chestpiece
15602 2 Ancient Crown
15603 2 Ancient Cloak
15604 2 Ancient Defender
15605 2 Ancient Gauntlets
15606 2 Ancient Belt
15607 2 Ancient Legguards
15608 2 Ancient Pauldrons
15609 2 Bonelink Armor
15610 2 Bonelink Bracers
15611 2 Bonelink Cape
15612 2 Bonelink Gauntlets
15613 2 Bonelink Belt
15614 2 Bonelink Sabatons
15615 2 Bonelink Helmet
15616 2 Bonelink Legplates
15617 2 Bonelink Epaulets
15618 2 Bonelink Wall Shield
15619 2 Gryphon Mail Belt
15620 2 Gryphon Mail Bracelets
15621 2 Gryphon Mail Buckler
15622 2 Gryphon Mail Breastplate
15623 2 Gryphon Mail Crown
15624 2 Gryphon Cloak
15625 2 Gryphon Mail Gauntlets
15626 2 Gryphon Mail Greaves
15627 2 Gryphon Mail Legguards
15628 2 Gryphon Mail Pauldrons
15629 2 Formidable Bracers
15630 2 Formidable Sabatons
15631 2 Formidable Chestpiece
15632 2 Formidable Cape
15633 2 Formidable Crest
15634 2 Formidable Circlet
15635 2 Formidable Gauntlets
15636 2 Formidable Belt
15637 2 Formidable Legguards
15638 2 Formidable Shoulder Pads
15639 2 Ironhide Bracers
15640 2 Ironhide Breastplate
15641 2 Ironhide Belt
15642 2 Ironhide Greaves
15643 2 Ironhide Cloak
15644 2 Ironhide Gauntlets
15645 2 Ironhide Helmet
15646 2 Ironhide Legguards
15647 2 Ironhide Pauldrons
15648 2 Ironhide Shield
15649 2 Merciless Bracers
15650 2 Merciless Surcoat
15651 2 Merciless Crown
15652 2 Merciless Cloak
15653 2 Merciless Gauntlets
15654 2 Merciless Belt
15655 2 Merciless Legguards
15656 2 Merciless Epaulets
15657 2 Merciless Shield
15658 2 Impenetrable Sabatons
15659 2 Impenetrable Bindings
15660 2 Impenetrable Breastplate
15661 2 Impenetrable Cloak
15662 2 Impenetrable Gauntlets
15663 2 Impenetrable Belt
15664 2 Impenetrable Helmet
15665 2 Impenetrable Legguards
15666 2 Impenetrable Pauldrons
15667 2 Impenetrable Wall
15668 2 Magnificent Bracers
15669 2 Magnificent Breastplate
15670 2 Magnificent Helmet
15671 2 Magnificent Cloak
15672 2 Magnificent Gauntlets
15673 2 Magnificent Belt
15674 2 Magnificent Greaves
15675 2 Magnificent Guard
15676 2 Magnificent Leggings
15677 2 Magnificent Shoulders
15678 2 Triumphant Sabatons
15679 2 Triumphant Bracers
15680 2 Triumphant Chestpiece
15681 2 Triumphant Cloak
15682 2 Triumphant Gauntlets
15683 2 Triumphant Girdle
15684 2 Triumphant Skullcap
15685 2 Triumphant Legplates
15686 2 Triumphant Shoulder Pads
15687 2 Triumphant Shield
15689 2 Trader's Ring
15690 2 Kodobone Necklace
15691 2 Sidegunner Shottie
15692 2 Kodo Brander
15693 2 Grand Shoulders
15694 2 Merciless Greaves
15695 2 Studded Ring Shield
15697 2 Kodo Rustler Boots
15698 2 Wrangling Spaulders
15702 2 Chemist's Ring
15703 2 Chemist's Smock
15704 2 Hunter's Insignia Medal
15705 2 Tidecrest Blade
15706 2 Hunt Tracker Blade
15707 2 Brantwood Sash
15708 2 Blight Leather Gloves
15709 2 Gearforge Girdle
15782 2 Beaststalker Blade
15783 2 Beasthunter Dagger
15784 2 Crystal Breeze Mantle
15786 2 Fernpulse Jerkin
15787 2 Willow Band Hauberk
15789 2 Deep River Cloak
15791 2 Turquoise Sash
15792 2 Plow Wood Spaulders
15794 0 Ripped Ogre Loincloth
15795 2 Emerald Mist Gauntlets
15796 2 Seaspray Bracers
15797 2 Shining Armplates
15799 2 Heroic Commendation Medal
15800 2 Intrepid Shortsword
15801 2 Valiant Shortsword
15802 3 Mooncloth Boots
15804 2 Cerise Drape
15805 3 Penelope's Rose
15806 3 Mirah's Song
15807 1 Light Crossbow
15808 1 Fine Light Crossbow
15809 1 Heavy Crossbow
15810 1 Short Spear
15811 1 Heavy Spear
15812 2 Orchid Amice
15813 2 Gold Link Belt
15814 2 Hameya's Slayer
15815 2 Hameya's Cloak
15822 2 Shadowskin Spaulders
15823 2 Bricksteel Gauntlets
15824 2 Astoria Robes
15825 2 Traphook Jerkin
15827 2 Jadescale Breastplate
15853 3 Windreaper
15854 3 Dancing Sliver
15855 3 Ring of Protection
15856 3 Archlight Talisman
15857 3 Magebane Scion
15858 2 Freewind Gloves
15859 2 Seapost Girdle
15860 2 Blinkstrike Armguards
15861 2 Swiftfoot Treads
15862 2 Blitzcleaver
15863 2 Grave Scepter
15864 2 Condor Bracers
15865 2 Anchorhold Buckler
15866 2 Veildust Medicine Bag
15867 2 Prismcharm
15873 3 Ragged John's Neverending Cup
15887 2 Heroic Guard
15890 2 Vanguard Shield
15891 2 Hulking Shield
15892 2 Slayer's Shield
15893 2 Prospector's Buckler
15894 2 Bristlebark Buckler
15895 1 Burnt Buckler
15903 1 Right-Handed Claw
15904 1 Right-Handed Blades
15905 1 Right-Handed Brass Knuckles
15906 1 Left-Handed Brass Knuckles
15907 1 Left-Handed Claw
15909 1 Left-Handed Blades
15912 2 Buccaneer's Orb
15918 2 Conjurer's Sphere
15925 2 Journeyman's Stave
15926 2 Spellbinder Orb
15927 2 Bright Sphere
15928 2 Silver-thread Rod
15929 2 Nightsky Orb
15930 2 Imperial Red Scepter
15931 2 Arcane Star
15932 2 Disciple's Stein
15933 2 Simple Branch
15934 2 Sage's Stave
15935 2 Durable Rod
15936 2 Duskwoven Branch
15937 2 Hibernal Sphere
15938 2 Mystical Orb
15939 2 Councillor's Scepter
15940 2 Elegant Scepter
15941 2 High Councillor's Scepter
15942 2 Master's Rod
15943 2 Imbued Shield
15944 2 Ancestral Orb
15945 2 Runic Stave
15946 2 Mystic's Sphere
15947 2 Sanguine Star
15962 2 Satyr's Rod
15963 2 Stonecloth Branch
15964 2 Silksand Star
15965 2 Windchaser Orb
15966 2 Venomshroud Orb
15967 2 Highborne Star
15968 2 Elunarian Sphere
15969 2 Beaded Orb
15970 2 Native Branch
15971 2 Aboriginal Rod
15972 2 Ritual Stein
15973 2 Watcher's Star
15974 2 Pagan Rod
15975 2 Raincaller Scepter
15976 2 Thistlefur Branch
15977 2 Vital Orb
15978 2 Geomancer's Rod
15979 2 Embersilk Stave
15980 2 Darkmist Orb
15981 2 Lunar Sphere
15982 2 Bloodwoven Rod
15983 2 Gaea's Scepter
15984 2 Opulent Scepter
15985 2 Arachnidian Branch
15986 2 Bonecaster's Star
15987 2 Astral Orb
15988 2 Resplendent Orb
15989 2 Eternal Rod
15990 2 Enduring Shield
15991 2 Warleader's Shield
15995 2 Thorium Rifle
15999 2 Spellpower Goggles Xtreme Plus
16004 3 Dark Iron Rifle
16007 3 Flawless Arcanite Rifle
16008 2 Master Engineer's Goggles
16009 2 Voice Amplification Modulator
16022 3 Arcanite Dragonling
16039 3 Ta'Kierthan Songblade
16058 3 Fordring's Seal
16059 1 Common Brown Shirt
16060 1 Common White Shirt
16309 3 Drakefire Amulet
16315 3 Sergeant Major's Cape
16335 3 Senior Sergeant's Insignia
16336 3 Sergeant Major's Cape
16337 3 Sergeant Major's Cape
16341 3 Sergeant's Cloak
16342 3 Sergeant's Cape
16345 4 High Warlord's Blade
16367 3 Knight-Captain's Silk Sash
16369 3 Knight-Lieutenant's Silk Boots
16370 3 Knight-Captain's Silk Cuffs
16391 3 Knight-Lieutenant's Silk Gloves
16392 3 Knight-Lieutenant's Leather Boots
16393 3 Knight-Lieutenant's Dragonhide Footwraps
16394 3 Knight-Captain's Leather Bracers
16395 3 Knight-Captain's Dragonhide Armsplints
16396 3 Knight-Lieutenant's Leather Gauntlets
16397 3 Knight-Lieutenant's Dragonhide Gloves
16398 3 Knight-Captain's Leather Belt
16399 3 Knight-Captain's Dragonhide Girdle
16400 3 Knight-Captain's Chain Girdle
16401 3 Knight-Lieutenant's Chain Boots
16402 3 Knight-Captain's Chain Armguards
16403 3 Knight-Lieutenant's Chain Gauntlets
16404 3 Knight-Captain's Plate Wristguards
16405 3 Knight-Lieutenant's Plate Boots
16406 3 Knight-Lieutenant's Plate Gauntlets
16407 3 Knight-Captain's Plate Girdle
16409 3 Knight-Lieutenant's Lamellar Sabatons
16410 3 Knight-Lieutenant's Lamellar Gauntlets
16411 3 Knight-Captain's Lamellar Cinch
16412 3 Knight-Captain's Lamellar Armsplints
16413 3 Knight-Captain's Silk Raiment
16414 3 Knight-Captain's Silk Leggings
16415 3 Lieutenant Commander's Silk Spaulders
16416 3 Lieutenant Commander's Crown
16417 3 Knight-Captain's Leather Armor
16418 3 Lieutenant Commander's Leather Veil
16419 3 Knight-Captain's Leather Legguards
16420 3 Lieutenant Commander's Leather Spaulders
16421 3 Knight-Captain's Dragonhide Tunic
16422 3 Knight-Captain's Dragonhide Leggings
16423 3 Lieutenant Commander's Dragonhide Epaulets
16424 3 Lieutenant Commander's Dragonhide Shroud
16425 3 Knight-Captain's Chain Hauberk
16426 3 Knight-Captain's Chain Leggings
16427 3 Lieutenant Commander's Chain Pauldrons
16428 3 Lieutenant Commander's Chain Helmet
16429 3 Lieutenant Commander's Plate Helm
16430 3 Knight-Captain's Plate Chestguard
16431 3 Knight-Captain's Plate Leggings
16432 3 Lieutenant Commander's Plate Pauldrons
16433 3 Knight-Captain's Lamellar Breastplate
16434 3 Lieutenant Commander's Lamellar Headguard
16435 3 Knight-Captain's Lamellar Leggings
16436 3 Lieutenant Commander's Lamellar Shoulders
16437 4 Marshal's Silk Footwraps
16438 4 Marshal's Silk Bracers
16439 4 Marshal's Silk Sash
16440 4 Marshal's Silk Gloves
16441 4 Field Marshal's Coronet
16442 4 Marshal's Silk Leggings
16443 4 Field Marshal's Silk Vestments
16444 4 Field Marshal's Silk Spaulders
16445 4 Marshal's Dragonhide Bracers
16446 4 Marshal's Leather Footguards
16447 4 Marshal's Dragonhide Waistguard
16448 4 Marshal's Dragonhide Gauntlets
16449 4 Field Marshal's Dragonhide Spaulders
16450 4 Marshal's Dragonhide Legguards
16451 4 Field Marshal's Dragonhide Helmet
16452 4 Field Marshal's Dragonhide Breastplate
16453 4 Field Marshal's Leather Chestpiece
16454 4 Marshal's Leather Handgrips
16455 4 Field Marshal's Leather Mask
16456 4 Marshal's Leather Leggings
16457 4 Field Marshal's Leather Epaulets
16458 4 Marshal's Leather Cinch
16459 4 Marshal's Dragonhide Boots
16460 4 Marshal's Leather Armsplints
16461 4 Marshal's Chain Bracers
16462 4 Marshal's Chain Boots
16463 4 Marshal's Chain Grips
16464 4 Marshal's Chain Girdle
16465 4 Field Marshal's Chain Helm
16466 4 Field Marshal's Chain Breastplate
16467 4 Marshal's Chain Legguards
16468 4 Field Marshal's Chain Spaulders
16469 4 Marshal's Lamellar Armguards
16470 4 Marshal's Lamellar Belt
16471 4 Marshal's Lamellar Gloves
16472 4 Marshal's Lamellar Boots
16473 4 Field Marshal's Lamellar Chestplate
16474 4 Field Marshal's Lamellar Faceguard
16475 4 Marshal's Lamellar Legplates
16476 4 Field Marshal's Lamellar Pauldrons
16477 4 Field Marshal's Plate Armor
16478 4 Field Marshal's Plate Helm
16479 4 Marshal's Plate Legguards
16480 4 Field Marshal's Plate Shoulderguards
16481 4 Marshal's Plate Bracers
16482 4 Marshal's Plate Girdle
16483 4 Marshal's Plate Boots
16484 4 Marshal's Plate Gauntlets
16485 3 Blood Guard's Silk Footwraps
16486 3 First Sergeant's Silk Cuffs
16487 3 Blood Guard's Silk Gloves
16488 3 Legionnaire's Silk Belt
16489 3 Champion's Silk Hood
16490 3 Legionnaire's Silk Pants
16491 3 Legionnaire's Silk Robes
16492 3 Champion's Silk Shoulderpads
16493 3 Legionnaire's Dragonhide Armguards
16494 3 Blood Guard's Dragonhide Boots
16495 3 Legionnaire's Dragonhide Waistband
16496 3 Blood Guard's Dragonhide Gauntlets
16497 3 First Sergeant's Leather Armguards
16498 3 Blood Guard's Leather Treads
16499 3 Blood Guard's Leather Vices
16500 3 Legionnaire's Leather Girdle
16501 3 Champion's Dragonhide Spaulders
16502 3 Legionnaire's Dragonhide Trousers
16503 3 Champion's Dragonhide Helm
16504 3 Legionnaire's Dragonhide Breastplate
16505 3 Legionnaire's Leather Hauberk
16506 3 Champion's Leather Headguard
16507 3 Champion's Leather Mantle
16508 3 Legionnaire's Leather Leggings
16509 3 Blood Guard's Plate Boots
16510 3 Blood Guard's Plate Gloves
16511 3 Legionnaire's Plate Cinch
16512 3 Legionnaire's Plate Bracers
16513 3 Legionnaire's Plate Armor
16514 3 Champion's Plate Headguard
16515 3 Legionnaire's Plate Legguards
16516 3 Champion's Plate Pauldrons
16517 3 Legionnaire's Chain Bracers
16518 3 Blood Guard's Mail Walkers
16519 3 Blood Guard's Mail Grips
16520 3 Legionnaire's Mail Cinch
16521 3 Champion's Mail Helm
16522 3 Legionnaire's Mail Chestpiece
16523 3 Legionnaire's Mail Leggings
16524 3 Champion's Mail Shoulders
16525 3 Legionnaire's Chain Breastplate
16526 3 Champion's Chain Headguard
16527 3 Legionnaire's Chain Leggings
16528 3 Champion's Chain Pauldrons
16529 3 Legionnaire's Chain Girdle
16530 3 Blood Guard's Chain Gauntlets
16531 3 Blood Guard's Chain Boots
16532 3 First Sergeant's Mail Wristguards
16533 4 Warlord's Silk Cowl
16534 4 General's Silk Trousers
16535 4 Warlord's Silk Raiment
16536 4 Warlord's Silk Amice
16537 4 General's Silk Sash
16538 4 General's Silk Cuffs
16539 4 General's Silk Boots
16540 4 General's Silk Handguards
16541 4 Warlord's Plate Armor
16542 4 Warlord's Plate Headpiece
16543 4 General's Plate Leggings
16544 4 Warlord's Plate Shoulders
16545 4 General's Plate Boots
16546 4 General's Plate Armguards
16547 4 General's Plate Girdle
16548 4 General's Plate Gauntlets
16549 4 Warlord's Dragonhide Hauberk
16550 4 Warlord's Dragonhide Helmet
16551 4 Warlord's Dragonhide Epaulets
16552 4 General's Dragonhide Leggings
16553 4 General's Dragonhide Bracers
16554 4 General's Dragonhide Boots
16555 4 General's Dragonhide Gloves
16556 4 General's Dragonhide Belt
16557 4 General's Leather Girdle
16558 4 General's Leather Treads
16559 4 General's Leather Armsplints
16560 4 General's Leather Mitts
16561 4 Warlord's Leather Helm
16562 4 Warlord's Leather Spaulders
16563 4 Warlord's Leather Breastplate
16564 4 General's Leather Legguards
16565 4 Warlord's Chain Chestpiece
16566 4 Warlord's Chain Helmet
16567 4 General's Chain Legguards
16568 4 Warlord's Chain Shoulders
16569 4 General's Chain Sabatons
16570 4 General's Chain Wristguards
16571 4 General's Chain Gloves
16572 4 General's Chain Girdle
16573 4 General's Mail Boots
16574 4 General's Mail Gauntlets
16575 4 General's Mail Waistband
16576 4 General's Mail Bracers
16577 4 Warlord's Mail Armor
16578 4 Warlord's Mail Helm
16579 4 General's Mail Leggings
16580 4 Warlord's Mail Spaulders
16604 2 Moon Robes of Elune
16605 2 Friar's Robes of the Light
16606 2 Juju Hex Robes
16607 2 Acolyte's Sacrificial Robes
16608 2 Aquarius Belt
16622 2 Thornflinger
16623 2 Opaline Medallion
16658 2 Wildhunter Cloak
16659 2 Deftkin Belt
16660 2 Driftmire Shield
16661 2 Soft Willow Cape
16664 2 Ornate Bracers
16666 3 Vest of Elements
16667 3 Coif of Elements
16668 3 Kilt of Elements
16669 3 Pauldrons of Elements
16670 3 Boots of Elements
16671 3 Bindings of Elements
16672 3 Gauntlets of Elements
16673 3 Cord of Elements
16674 3 Beaststalker's Tunic
16675 3 Beaststalker's Boots
16676 3 Beaststalker's Gloves
16677 3 Beaststalker's Cap
16678 3 Beaststalker's Pants
16679 3 Beaststalker's Mantle
16680 3 Beaststalker's Belt
16681 3 Beaststalker's Bindings
16682 3 Magister's Boots
16683 3 Magister's Bindings
16684 3 Magister's Gloves
16685 3 Magister's Belt
16686 3 Magister's Crown
16687 3 Magister's Leggings
16688 3 Magister's Robes
16689 3 Magister's Mantle
16690 3 Devout Robe
16691 3 Devout Sandals
16692 3 Devout Gloves
16693 3 Devout Crown
16694 3 Devout Skirt
16695 3 Devout Mantle
16696 3 Devout Belt
16697 3 Devout Bracers
16698 3 Dreadmist Mask
16699 3 Dreadmist Leggings
16700 3 Dreadmist Robe
16701 3 Dreadmist Mantle
16702 3 Dreadmist Belt
16703 3 Dreadmist Bracers
16704 3 Dreadmist Sandals
16705 3 Dreadmist Wraps
16706 3 Wildheart Vest
16707 3 Shadowcraft Cap
16708 3 Shadowcraft Spaulders
16709 3 Shadowcraft Pants
16710 3 Shadowcraft Bracers
16711 3 Shadowcraft Boots
16712 3 Shadowcraft Gloves
16713 3 Shadowcraft Belt
16714 3 Wildheart Bracers
16715 3 Wildheart Boots
16716 3 Wildheart Belt
16717 3 Wildheart Gloves
16718 3 Wildheart Spaulders
16719 3 Wildheart Kilt
16720 3 Wildheart Cowl
16721 3 Shadowcraft Tunic
16722 3 Lightforge Bracers
16723 3 Lightforge Belt
16724 3 Lightforge Gauntlets
16725 3 Lightforge Boots
16726 3 Lightforge Breastplate
16727 3 Lightforge Helm
16728 3 Lightforge Legplates
16729 3 Lightforge Spaulders
16730 3 Breastplate of Valor
16731 3 Helm of Valor
16732 3 Legplates of Valor
16733 3 Spaulders of Valor
16734 3 Boots of Valor
16735 3 Bracers of Valor
16736 3 Belt of Valor
16737 3 Gauntlets of Valor
16738 2 Witherseed Gloves
16739 2 Rugwood Mantle
16740 2 Shredder Operating Gloves
16741 2 Oilrag Handwraps
16768 2 Furbolg Medicine Pouch
16769 2 Furbolg Medicine Totem
16787 1 Amulet of Draconic Subversion
16788 2 Captain Rackmore's Wheel
16789 2 Captain Rackmore's Tiller
16791 2 Silkstream Cuffs
16792 2 Giant Club
16793 2 Arcmetal Shoulders
16794 2 Gripsteel Wristguards
16795 4 Arcanist Crown
16796 4 Arcanist Leggings
16797 4 Arcanist Mantle
16798 4 Arcanist Robes
16799 4 Arcanist Bindings
16800 4 Arcanist Boots
16801 4 Arcanist Gloves
16802 4 Arcanist Belt
16803 4 Felheart Slippers
16804 4 Felheart Bracers
16805 4 Felheart Gloves
16806 4 Felheart Belt
16807 4 Felheart Shoulder Pads
16808 4 Felheart Horns
16809 4 Felheart Robes
16810 4 Felheart Pants
16811 4 Boots of Prophecy
16812 4 Gloves of Prophecy
16813 4 Circlet of Prophecy
16814 4 Pants of Prophecy
16815 4 Robes of Prophecy
16816 4 Mantle of Prophecy
16817 4 Girdle of Prophecy
16818 4 Netherwind Belt
16819 4 Vambraces of Prophecy
16820 4 Nightslayer Chestpiece
16821 4 Nightslayer Cover
16822 4 Nightslayer Pants
16823 4 Nightslayer Shoulder Pads
16824 4 Nightslayer Boots
16825 4 Nightslayer Bracelets
16826 4 Nightslayer Gloves
16827 4 Nightslayer Belt
16828 4 Cenarion Belt
16829 4 Cenarion Boots
16830 4 Cenarion Bracers
16831 4 Cenarion Gloves
16832 4 Bloodfang Spaulders
16833 4 Cenarion Vestments
16834 4 Cenarion Helm
16835 4 Cenarion Leggings
16836 4 Cenarion Spaulders
16837 4 Earthfury Boots
16838 4 Earthfury Belt
16839 4 Earthfury Gauntlets
16840 4 Earthfury Bracers
16841 4 Earthfury Vestments
16842 4 Earthfury Helmet
16843 4 Earthfury Legguards
16844 4 Earthfury Epaulets
16845 4 Giantstalker's Breastplate
16846 4 Giantstalker's Helmet
16847 4 Giantstalker's Leggings
16848 4 Giantstalker's Epaulets
16849 4 Giantstalker's Boots
16850 4 Giantstalker's Bracers
16851 4 Giantstalker's Belt
16852 4 Giantstalker's Gloves
16853 4 Lawbringer Chestguard
16854 4 Lawbringer Helm
16855 4 Lawbringer Legplates
16856 4 Lawbringer Spaulders
16857 4 Lawbringer Bracers
16858 4 Lawbringer Belt
16859 4 Lawbringer Boots
16860 4 Lawbringer Gauntlets
16861 4 Bracers of Might
16862 4 Sabatons of Might
16863 4 Gauntlets of Might
16864 4 Belt of Might
16865 4 Breastplate of Might
16866 4 Helm of Might
16867 4 Legplates of Might
16868 4 Pauldrons of Might
16873 2 Braidfur Gloves
16886 3 Outlaw Sabre
16887 3 Witch's Finger
16889 2 Polished Walking Staff
16890 2 Slatemetal Cutlass
16891 2 Claystone Shortsword
16894 2 Clear Crystal Rod
16897 4 Stormrage Chestguard
16898 4 Stormrage Boots
16899 4 Stormrage Handguards
16900 4 Stormrage Cover
16901 4 Stormrage Legguards
16902 4 Stormrage Pauldrons
16903 4 Stormrage Belt
16904 4 Stormrage Bracers
16905 4 Bloodfang Chestpiece
16906 4 Bloodfang Boots
16907 4 Bloodfang Gloves
16908 4 Bloodfang Hood
16909 4 Bloodfang Pants
16910 4 Bloodfang Belt
16911 4 Bloodfang Bracers
16912 4 Netherwind Boots
16913 4 Netherwind Gloves
16914 4 Netherwind Crown
16915 4 Netherwind Pants
16916 4 Netherwind Robes
16917 4 Netherwind Mantle
16918 4 Netherwind Bindings
16919 4 Boots of Transcendence
16920 4 Handguards of Transcendence
16921 4 Halo of Transcendence
16922 4 Leggings of Transcendence
16923 4 Robes of Transcendence
16924 4 Pauldrons of Transcendence
16925 4 Belt of Transcendence
16926 4 Bindings of Transcendence
16927 4 Nemesis Boots
16928 4 Nemesis Gloves
16929 4 Nemesis Skullcap
16930 4 Nemesis Leggings
16931 4 Nemesis Robes
16932 4 Nemesis Spaulders
16933 4 Nemesis Belt
16934 4 Nemesis Bracers
16935 4 Dragonstalker's Bracers
16936 4 Dragonstalker's Belt
16937 4 Dragonstalker's Spaulders
16938 4 Dragonstalker's Legguards
16939 4 Dragonstalker's Helm
16940 4 Dragonstalker's Gauntlets
16941 4 Dragonstalker's Greaves
16942 4 Dragonstalker's Breastplate
16943 4 Bracers of Ten Storms
16944 4 Belt of Ten Storms
16945 4 Epaulets of Ten Storms
16946 4 Legplates of Ten Storms
16947 4 Helmet of Ten Storms
16948 4 Gauntlets of Ten Storms
16949 4 Greaves of Ten Storms
16950 4 Breastplate of Ten Storms
16951 4 Judgement Bindings
16952 4 Judgement Belt
16953 4 Judgement Spaulders
16954 4 Judgement Legplates
16955 4 Judgement Crown
16956 4 Judgement Gauntlets
16957 4 Judgement Sabatons
16958 4 Judgement Breastplate
16959 4 Bracelets of Wrath
16960 4 Waistband of Wrath
16961 4 Pauldrons of Wrath
16962 4 Legplates of Wrath
16963 4 Helm of Wrath
16964 4 Gauntlets of Wrath
16965 4 Sabatons of Wrath
16966 4 Breastplate of Wrath
16967 1 Feralas Ahi
16975 3 Warsong Sash
16977 3 Warsong Boots
16978 3 Warsong Gauntlets
16979 4 Flarecore Gloves
16980 4 Flarecore Mantle
16981 2 Owlbeard Bracers
16982 4 Corehound Boots
16983 4 Molten Helm
16984 4 Black Dragonscale Boots
16985 2 Windseeker Boots
16986 2 Sandspire Gloves
16987 2 Screecher Belt
16988 4 Fiery Chain Shoulders
16989 4 Fiery Chain Girdle
16990 2 Spritekin Cloak
16992 2 Smokey's Explosive Launcher
16993 2 Smokey's Fireshooter
16994 2 Duskwing Gloves
16995 2 Duskwing Mantle
16996 3 Gorewood Bow
16997 3 Stormrager
16998 3 Sacred Protector
16999 3 Royal Seal of Alexis
17000 2 Band of the Wraith
17001 2 Elemental Circle
17002 2 Ichor Spitter
17003 2 Skullstone Hammer
17004 2 Sarah's Guide
17005 2 Boorguard Tunic
17006 2 Cobalt Legguards
17007 4 Stonerender Gauntlets
17013 4 Dark Iron Leggings
17014 4 Dark Iron Bracers
17015 3 Dark Iron Reaver
17016 3 Dark Iron Destroyer
17039 2 Skullbreaker
17042 2 Nail Spitter
17043 2 Zealot's Robe
17044 3 Will of the Martyr
17045 3 Blood of the Martyr
17046 2 Gutterblade
17047 2 Luminescent Amice
17050 3 Chan's Imperial Robes
17054 3 Joonho's Mercy
17055 3 Changuk Smasher
17061 3 Juno's Shadow
17063 4 Band of Accuria
17064 4 Shard of the Scale
17065 4 Medallion of Steadfast Might
17066 4 Drillborer Disk
17067 4 Ancient Cornerstone Grimoire
17068 4 Deathbringer
17069 4 Striker's Mark
17070 4 Fang of the Mystics
17071 4 Gutgore Ripper
17072 4 Blastershot Launcher
17073 4 Earthshaker
17074 4 Shadowstrike
17075 4 Vis'kag the Bloodletter
17076 4 Bonereaver's Edge
17077 4 Crimson Shocker
17078 4 Sapphiron Drape
17082 4 Shard of the Flame
17102 4 Cloak of the Shrouded Mists
17103 4 Azuresong Mageblade
17104 4 Spinal Reaper
17105 4 Aurastone Hammer
17106 4 Malistar's Defender
17107 4 Dragon's Blood Cape
17108 4 Mark of Deflection
17109 4 Choker of Enlightenment
17110 4 Seal of the Archmagus
17111 4 Blazefury Medallion
17112 4 Empyrean Demolisher
17113 4 Amberseal Keeper
17142 5 Shard of the Defiler
17182 5 Sulfuras, Hand of Ragnaros
17183 1 Dented Buckler
17184 1 Small Shield
17185 1 Round Buckler
17186 1 Small Targe
17187 1 Banded Buckler
17188 1 Ringed Buckler
17189 1 Metal Buckler
17190 1 Ornate Buckler
17192 1 Reinforced Targe
17193 4 Sulfuron Hammer
17223 4 Thunderstrike
17508 2 Forcestone Buckler
17523 2 Smokey's Drape
17562 3 Knight-Lieutenant's Dreadweave Boots
17563 3 Knight-Captain's Dreadweave Bracers
17564 3 Knight-Lieutenant's Dreadweave Gloves
17565 3 Knight-Captain's Dreadweave Belt
17566 3 Lieutenant Commander's Headguard
17567 3 Knight-Captain's Dreadweave Leggings
17568 3 Knight-Captain's Dreadweave Robe
17569 3 Lieutenant Commander's Dreadweave Mantle
17570 3 Champion's Dreadweave Hood
17571 3 Legionnaire's Dreadweave Leggings
17572 3 Legionnaire's Dreadweave Robe
17573 3 Champion's Dreadweave Shoulders
17574 3 Legionnaire's Dreadweave Belt
17575 3 Legionnaire's Dreadweave Bracers
17576 3 Blood Guard's Dreadweave Boots
17577 3 Blood Guard's Dreadweave Gloves
17578 4 Field Marshal's Coronal
17579 4 Marshal's Dreadweave Leggings
17580 4 Field Marshal's Dreadweave Shoulders
17581 4 Field Marshal's Dreadweave Robe
17582 4 Marshal's Dreadweave Cuffs
17583 4 Marshal's Dreadweave Boots
17584 4 Marshal's Dreadweave Gloves
17585 4 Marshal's Dreadweave Sash
17586 4 General's Dreadweave Boots
17587 4 General's Dreadweave Bracers
17588 4 General's Dreadweave Gloves
17589 4 General's Dreadweave Belt
17590 4 Warlord's Dreadweave Mantle
17591 4 Warlord's Dreadweave Hood
17592 4 Warlord's Dreadweave Robe
17593 4 General's Dreadweave Pants
17594 3 Knight-Lieutenant's Satin Boots
17595 3 Knight-Captain's Satin Cuffs
17596 3 Knight-Lieutenant's Satin Gloves
17597 3 Knight-Captain's Satin Cord
17598 3 Lieutenant Commander's Diadem
17599 3 Knight-Captain's Satin Leggings
17600 3 Knight-Captain's Satin Robes
17601 3 Lieutenant Commander's Satin Amice
17602 4 Field Marshal's Headdress
17603 4 Marshal's Satin Pants
17604 4 Field Marshal's Satin Mantle
17605 4 Field Marshal's Satin Vestments
17606 4 Marshal's Satin Bracers
17607 4 Marshal's Satin Sandals
17608 4 Marshal's Satin Gloves
17609 4 Marshal's Satin Sash
17610 3 Champion's Satin Cowl
17611 3 Legionnaire's Satin Trousers
17612 3 Legionnaire's Satin Vestments
17613 3 Champion's Satin Shoulderpads
17614 3 Legionnaire's Satin Sash
17615 3 Legionnaire's Satin Cuffs
17616 3 Blood Guard's Satin Boots
17617 3 Blood Guard's Satin Gloves
17618 4 General's Satin Boots
17619 4 General's Satin Bracers
17620 4 General's Satin Gloves
17621 4 General's Satin Cinch
17622 4 Warlord's Satin Mantle
17623 4 Warlord's Satin Cowl
17624 4 Warlord's Satin Robes
17625 4 General's Satin Leggings
17686 2 Master Hunter's Bow
17687 2 Master Hunter's Rifle
17688 2 Jungle Boots
17690 2 Frostwolf Insignia Rank 1
17691 2 Stormpike Insignia Rank 1
17692 2 Horn Ring
17694 2 Band of the Fist
17695 2 Chestnut Mantle
17704 2 Edge of Winter
17705 3 Thrash Blade
17707 3 Gemshard Heart
17710 3 Charstone Dirk
17711 3 Elemental Rockridge Leggings
17713 3 Blackstone Ring
17714 3 Bracers of the Stone Princess
17715 3 Eye of Theradras
17717 3 Megashot Rifle
17718 3 Gizlock's Hypertech Buckler
17719 3 Inventor's Focal Sword
17721 2 Gloves of the Greatfather
17723 1 Green Holiday Shirt
17728 3 Albino Crocscale Boots
17730 3 Gatorbite Axe
17732 3 Rotgrip Mantle
17733 3 Fist of Stone
17734 3 Helm of the Mountain
17736 3 Rockgrip Gauntlets
17737 3 Cloud Stone
17738 3 Claw of Celebras
17739 3 Grovekeeper's Drape
17740 3 Soothsayer's Headdress
17741 3 Nature's Embrace
17742 3 Fungus Shroud Armor
17743 3 Resurgence Rod
17744 3 Heart of Noxxion
17745 3 Noxious Shooter
17746 3 Noxxion's Shackles
17748 3 Vinerot Sandals
17749 3 Phytoskin Spaulders
17750 2 Chloromesh Girdle
17751 2 Brusslehide Leggings
17752 3 Satyr's Lash
17753 3 Verdant Keeper's Aim
17754 3 Infernal Trickster Leggings
17755 3 Satyrmane Sash
17759 2 Mark of Resolution
17766 3 Princess Theradras' Scepter
17767 3 Bloomsprout Headpiece
17768 2 Woodseed Hoop
17769 2 Sagebrush Spaulders
17770 2 Branchclaw Gauntlets
17772 2 Zealous Shadowshard Pendant
17773 2 Prodigious Shadowshard Pendant
17774 2 Mark of the Chosen
17775 2 Acumen Robes
17776 2 Sprightring Helm
17777 2 Relentless Chain
17778 2 Sagebrush Girdle
17779 2 Hulkstone Pauldrons
17780 4 Blade of Eternal Darkness
17782 5 Talisman of Binding Shard
17783 5 Talisman of Binding Fragment
17900 2 Stormpike Insignia Rank 2
17901 2 Stormpike Insignia Rank 3
17902 3 Stormpike Insignia Rank 4
17903 3 Stormpike Insignia Rank 5
17904 4 Stormpike Insignia Rank 6
17905 2 Frostwolf Insignia Rank 2
17906 2 Frostwolf Insignia Rank 3
17907 3 Frostwolf Insignia Rank 4
17908 3 Frostwolf Insignia Rank 5
17909 4 Frostwolf Insignia Rank 6
17922 2 Lionfur Armor
17943 3 Fist of Stone
17982 3 Ragnaros Core
18022 3 Royal Seal of Alexis
18023 3 Blood Ruby Pendant
18043 3 Coal Miner Boots
18044 3 Hurley's Tankard
18047 3 Flame Walkers
18048 3 Mastersmith's Hammer
18082 3 Zum'rah's Vexing Cane
18083 3 Jumanza Grips
18102 3 Dragonrider Boots
18103 3 Band of Rumination
18104 3 Feralsurge Girdle
18168 4 Force Reactive Disk
18202 4 Eskhandar's Left Claw
18203 4 Eskhandar's Right Claw
18204 4 Eskhandar's Pelt
18205 4 Eskhandar's Collar
18208 4 Drape of Benediction
18231 0 Sleeveless T-Shirt
18238 3 Shadowskin Gloves
18263 4 Flarecore Wraps
18282 4 Core Marksman Rifle
18289 3 Barbed Thorn Necklace
18295 3 Phasing Boots
18296 3 Marksman Bands
18298 3 Unbridled Leggings
18301 2 Lethtendris's Wand
18302 2 Band of Vigor
18303 2 Nimble Buckler
18304 2 Greenroot Mail
18305 2 Breakwater Legguards
18306 2 Gloves of Shadowy Mist
18307 2 Riptide Shoes
18308 2 Clever Hat
18309 3 Gloves of Restoration
18310 3 Fiendish Machete
18311 3 Quel'dorai Channeling Rod
18312 3 Energized Chestplate
18313 3 Helm of Awareness
18314 3 Ring of Demonic Guile
18315 3 Ring of Demonic Potency
18316 3 Obsidian Bauble
18317 3 Tempest Talisman
18318 3 Merciful Greaves
18319 3 Fervent Helm
18320 3 Demonheart Spaulders
18321 3 Energetic Rod
18322 3 Waterspout Boots
18323 3 Satyr's Bow
18324 3 Waveslicer
18325 3 Felhide Cap
18326 3 Razor Gauntlets
18327 3 Whipvine Cord
18328 3 Shadewood Cloak
18337 2 Orphic Bracers
18338 3 Wand of Arcane Potency
18339 2 Eidolon Cloak
18340 3 Eidolon Talisman
18341 2 Quel'dorai Sash
18342 3 Quel'dorai Guard
18343 2 Petrified Band
18344 3 Stonebark Gauntlets
18345 2 Murmuring Ring
18346 2 Threadbare Trousers
18347 2 Well Balanced Axe
18348 4 Quel'Serrar
18349 2 Gauntlets of Accuracy
18350 2 Amplifying Cloak
18351 2 Magically Sealed Bracers
18352 2 Petrified Bark Shield
18353 2 Stoneflower Staff
18354 3 Pimgib's Collar
18355 3 Ferra's Collar
18366 3 Gordok's Handguards
18367 3 Gordok's Gauntlets
18368 3 Gordok's Gloves
18369 3 Gordok's Handwraps
18370 3 Vigilance Charm
18371 3 Mindtap Talisman
18372 3 Blade of the New Moon
18373 3 Chestplate of Tranquility
18374 3 Flamescarred Shoulders
18375 3 Bracers of the Eclipse
18376 3 Timeworn Mace
18377 3 Quickdraw Gloves
18378 3 Silvermoon Leggings
18379 3 Odious Greaves
18380 3 Eldritch Reinforced Legplates
18381 3 Evil Eye Pendant
18382 3 Fluctuating Cloak
18383 3 Force Imbued Gauntlets
18384 3 Bile-etched Spaulders
18385 3 Robe of Everlasting Night
18386 3 Padre's Trousers
18387 3 Brightspark Gloves
18388 3 Stoneshatter
18389 3 Cloak of the Cosmos
18390 3 Tanglemoss Leggings
18391 3 Eyestalk Cord
18392 3 Distracting Dagger
18393 3 Warpwood Binding
18394 3 Demon Howl Wristguards
18395 3 Emerald Flame Ring
18396 3 Mind Carver
18397 3 Elder Magus Pendant
18398 3 Tidal Loop
18399 3 Ocean's Breeze
18400 2 Ring of Living Stone
18402 2 Glowing Crystal Ring
18403 4 Dragonslayer's Signet
18404 4 Onyxia Tooth Pendant
18405 4 Belt of the Archmage
18406 4 Onyxia Blood Talisman
18407 3 Felcloth Gloves
18408 3 Inferno Gloves
18409 3 Mooncloth Gloves
18410 2 Sprinter's Sword
18411 2 Spry Boots
18413 3 Cloak of Warding
18420 3 Bonecrusher
18421 3 Backwood Helm
18424 3 Sedge Boots
18425 2 Kreeg's Mug
18427 3 Sergeant's Cloak
18428 3 Senior Sergeant's Insignia
18429 3 First Sergeant's Plate Bracers
18430 3 First Sergeant's Plate Bracers
18432 3 First Sergeant's Mail Wristguards
18434 3 First Sergeant's Dragonhide Armguards
18435 3 First Sergeant's Leather Armguards
18436 3 First Sergeant's Dragonhide Armguards
18437 3 First Sergeant's Silk Cuffs
18438 3 Sergeant's Mark
18440 3 Sergeant's Cape
18441 3 Sergeant's Cape
18442 3 Master Sergeant's Insignia
18443 3 Master Sergeant's Insignia
18444 3 Master Sergeant's Insignia
18445 3 Sergeant Major's Plate Wristguards
18447 3 Sergeant Major's Plate Wristguards
18448 3 Sergeant Major's Chain Armguards
18449 3 Sergeant Major's Chain Armguards
18450 2 Robe of Combustion
18451 2 Hyena Hide Belt
18452 3 Sergeant Major's Leather Armsplints
18453 3 Sergeant Major's Leather Armsplints
18454 3 Sergeant Major's Dragonhide Armsplints
18455 3 Sergeant Major's Dragonhide Armsplints
18456 3 Sergeant Major's Silk Cuffs
18457 3 Sergeant Major's Silk Cuffs
18458 2 Modest Armguards
18459 2 Gallant's Wristguards
18460 2 Unsophisticated Hand Cannon
18461 3 Sergeant's Cloak
18462 2 Jagged Bone Fist
18463 2 Ogre Pocket Knife
18464 2 Gordok Nose Ring
18465 3 Royal Seal of Eldre'Thalas
18466 3 Royal Seal of Eldre'Thalas
18467 3 Royal Seal of Eldre'Thalas
18468 3 Royal Seal of Eldre'Thalas
18469 3 Royal Seal of Eldre'Thalas
18470 3 Royal Seal of Eldre'Thalas
18471 3 Royal Seal of Eldre'Thalas
18472 3 Royal Seal of Eldre'Thalas
18473 3 Royal Seal of Eldre'Thalas
18475 2 Oddly Magical Belt
18476 2 Mud Stained Boots
18477 2 Shaggy Leggings
18478 2 Hyena Hide Jerkin
18479 2 Carrion Scorpid Helm
18480 2 Scarab Plate Helm
18481 2 Skullcracking Mace
18482 2 Ogre Toothpick Shooter
18483 3 Mana Channeling Wand
18484 3 Cho'Rush's Blade
18485 3 Observer's Shield
18486 3 Mooncloth Robe
18490 3 Insightful Hood
18491 3 Lorespinner
18493 3 Bulky Iron Spaulders
18494 3 Denwatcher's Shoulders
18495 3 Redoubt Cloak
18496 3 Heliotrope Cloak
18497 3 Sublime Wristguards
18498 3 Hedgecutter
18499 3 Barrier Shield
18500 3 Tarnished Elven Ring
18502 3 Monstrous Glaive
18503 3 Kromcrush's Chestplate
18504 3 Girdle of Insight
18505 3 Mugger's Belt
18506 3 Mongoose Boots
18507 3 Boots of the Full Moon
18508 3 Swift Flight Bracers
18509 4 Chromatic Cloak
18510 4 Hide of the Wild
18511 4 Shifting Cloak
18520 3 Barbarous Blade
18521 3 Grimy Metal Boots
18522 3 Band of the Ogre King
18523 3 Brightly Glowing Stone
18524 3 Leggings of Destruction
18525 3 Bracers of Prosperity
18526 3 Crown of the Ogre King
18527 3 Harmonious Gauntlets
18528 3 Cyclone Spaulders
18529 3 Elemental Plate Girdle
18530 3 Ogre Forged Hauberk
18531 3 Unyielding Maul
18532 3 Mindsurge Robe
18533 3 Gordok Bracers of Power
18534 3 Rod of the Ogre Magi
18535 3 Milli's Shield
18536 3 Milli's Lexicon
18537 3 Counterattack Lodestone
18538 4 Treant's Bane
18541 4 Puissant Cape
18542 4 Typhoon
18543 4 Ring of Entropy
18544 4 Doomhide Gauntlets
18545 4 Leggings of Arcane Supremacy
18546 4 Infernal Headcage
18547 4 Unmelting Ice Girdle
18582 6 The Twin Blades of Azzinoth
18583 6 Warglaive of Azzinoth (Right)
18584 6 Warglaive of Azzinoth (Left)
18585 3 Band of Allegiance
18586 3 Lonetree's Circle
18587 1 Goblin Jumper Cables XL
18602 3 Tome of Sacrifice
18608 4 Benediction
18609 4 Anathema
18610 1 Keen Machete
18611 1 Gnarlpine Leggings
18612 1 Bloody Chain Boots
18634 3 Gyrofreeze Ice Reflector
18637 2 Major Recombobulator
18638 3 Hyper-Radiant Flame Reflector
18639 3 Ultra-Flash Shadow Reflector
18646 4 The Eye of Divinity
18665 4 The Eye of Shadow
18671 3 Baron Charr's Sceptre
18672 2 Elemental Ember
18673 3 Avalanchion's Stony Hide
18674 2 Hardened Stone Band
18676 3 Sash of the Windreaver
18677 2 Zephyr Cloak
18678 3 Tempestria's Frozen Necklace
18679 2 Frigid Ring
18680 3 Ancient Bone Bow
18681 3 Burial Shawl
18682 3 Ghoul Skin Leggings
18683 3 Hammer of the Vesper
18684 3 Dimly Opalescent Ring
18686 3 Bone Golem Shoulders
18689 3 Phantasmal Cloak
18690 3 Wraithplate Leggings
18691 3 Dark Advisor's Pendant
18692 3 Death Knight Sabatons
18693 3 Shivery Handwraps
18694 3 Shadowy Mail Greaves
18695 3 Spellbound Tome
18696 3 Intricately Runed Shield
18697 3 Coldstone Slippers
18698 3 Tattered Leather Hood
18699 3 Icy Tomb Spaulders
18700 3 Malefic Bracers
18701 3 Innervating Band
18702 3 Belt of the Ordained
18706 2 Arena Master
18709 3 Arena Wristguards
18710 3 Arena Bracers
18711 3 Arena Bands
18712 3 Arena Vambraces
18713 4 Rhok'delar, Longbow of the Ancient Keepers
18715 4 Lok'delar, Stave of the Ancient Keepers
18716 3 Ash Covered Boots
18717 3 Hammer of the Grand Crusader
18718 3 Grand Crusader's Helm
18720 3 Shroud of the Nathrezim
18721 3 Barrage Girdle
18722 3 Death Grips
18723 3 Animated Chain Necklace
18725 3 Peacemaker
18726 3 Magistrate's Cuffs
18727 3 Crimson Felt Hat
18728 3 Anastari Heirloom
18729 3 Screeching Bow
18730 3 Shadowy Laced Handwraps
18734 3 Pale Moon Cloak
18735 3 Maleki's Footwraps
18736 3 Plaguehound Leggings
18737 3 Bone Slicing Hatchet
18738 3 Carapace Spine Crossbow
18739 3 Chitinous Plate Legguards
18740 3 Thuzadin Sash
18741 3 Morlune's Bracer
18742 3 Stratholme Militia Shoulderguard
18743 3 Gracious Cape
18744 3 Plaguebat Fur Gloves
18745 3 Sacred Cloth Leggings
18754 3 Fel Hardened Bracers
18755 3 Xorothian Firestick
18756 3 Dreadguard's Protector
18757 3 Diabolic Mantle
18758 3 Specter's Blade
18759 3 Malicious Axe
18760 3 Necromantic Band
18761 3 Oblivion's Touch
18762 3 Shard of the Green Flame
18803 4 Hyperthermically Insulated Lava Dredger
18805 4 Core Hound Tooth
18806 4 Core Forged Greaves
18807 3 Helm of Latent Power
18808 4 Gloves of the Hypnotic Flame
18809 4 Sash of Whispered Secrets
18810 4 Wild Growth Spaulders
18811 4 Fireproof Cloak
18812 4 Wristguards of True Flight
18813 4 Ring of Binding
18814 4 Choker of the Fire Lord
18815 4 Essence of the Pure Flame
18816 4 Perdition's Blade
18817 4 Crown of Destruction
18820 4 Talisman of Ephemeral Power
18821 4 Quick Strike Ring
18822 4 Obsidian Edged Blade
18823 4 Aged Core Leather Gloves
18824 4 Magma Tempered Boots
18825 4 Grand Marshal's Aegis
18826 4 High Warlord's Shield Wall
18827 4 Grand Marshal's Handaxe
18828 4 High Warlord's Cleaver
18829 4 Deep Earth Spaulders
18830 4 Grand Marshal's Sunderer
18831 4 High Warlord's Battle Axe
18832 4 Brutality Blade
18833 4 Grand Marshal's Bullseye
18834 3 Insignia of the Horde
18835 4 High Warlord's Recurve
18836 4 Grand Marshal's Repeater
18837 4 High Warlord's Crossbow
18838 4 Grand Marshal's Dirk
18840 4 High Warlord's Razor
18842 4 Staff of Dominance
18843 4 Grand Marshal's Right Hand Blade
18844 4 High Warlord's Right Claw
18845 3 Insignia of the Horde
18846 3 Insignia of the Horde
18847 4 Grand Marshal's Left Hand Blade
18848 4 High Warlord's Left Claw
18849 3 Insignia of the Horde
18850 3 Insignia of the Horde
18851 3 Insignia of the Horde
18852 3 Insignia of the Horde
18853 3 Insignia of the Horde
18854 3 Insignia of the Alliance
18855 4 Grand Marshal's Hand Cannon
18856 3 Insignia of the Alliance
18857 3 Insignia of the Alliance
18858 3 Insignia of the Alliance
18859 3 Insignia of the Alliance
18860 4 High Warlord's Street Sweeper
18861 4 Flamewaker Legplates
18862 3 Insignia of the Alliance
18863 3 Insignia of the Alliance
18864 3 Insignia of the Alliance
18865 4 Grand Marshal's Punisher
18866 4 High Warlord's Bludgeon
18867 4 Grand Marshal's Battle Hammer
18868 4 High Warlord's Pulverizer
18869 4 Grand Marshal's Glaive
18870 4 Helm of the Lifegiver
18871 4 High Warlord's Pig Sticker
18872 4 Manastorm Leggings
18873 4 Grand Marshal's Stave
18874 4 High Warlord's War Staff
18875 4 Salamander Scale Pants
18876 4 Grand Marshal's Claymore
18877 4 High Warlord's Greatsword
18878 4 Sorcerous Dagger
18879 4 Heavy Dark Iron Ring
18948 3 Barbaric Bracers
18951 2 Evonice's Landin' Pilla
18957 2 Brushwood Blade
18984 2 Dimensional Ripper - Everlook
18986 2 Ultrasafe Transporter: Gadgetzan
19019 5 Thunderfury, Blessed Blade of the Windseeker
19022 2 Nat Pagle's Extreme Angler FC-5000
19024 3 Arena Grand Master
19028 1 Elegant Dress
19031 1 Frostwolf Battle Tabard
19032 1 Stormpike Battle Tabard
19037 2 Emerald Peak Spaulders
19038 2 Ring of Subtlety
19039 2 Zorbin's Water Resistant Hat
19040 2 Zorbin's Mega-Slicer
19041 2 Pratt's Handcrafted Tunic
19042 2 Jangdor's Handcrafted Tunic
19043 3 Heavy Timbermaw Belt
19044 3 Might of the Timbermaw
19047 3 Wisdom of the Timbermaw
19048 3 Heavy Timbermaw Boots
19049 3 Timbermaw Brawlers
19050 3 Mantle of the Timbermaw
19051 3 Girdle of the Dawn
19052 3 Dawn Treaders
19056 3 Argent Boots
19057 3 Gloves of the Dawn
19058 3 Golden Mantle of the Dawn
19059 3 Argent Shoulders
19065 3 Emerald Circle
19083 3 Frostwolf Legionnaire's Cloak
19084 3 Stormpike Soldier's Cloak
19085 3 Frostwolf Advisor's Cloak
19086 3 Stormpike Sage's Cloak
19087 3 Frostwolf Plate Belt
19088 3 Frostwolf Mail Belt
19089 3 Frostwolf Leather Belt
19090 3 Frostwolf Cloth Belt
19091 3 Stormpike Plate Girdle
19092 3 Stormpike Mail Girdle
19093 3 Stormpike Leather Girdle
19094 3 Stormpike Cloth Girdle
19095 3 Frostwolf Legionnaire's Pendant
19096 3 Frostwolf Advisor's Pendant
19097 3 Stormpike Soldier's Pendant
19098 3 Stormpike Sage's Pendant
19099 3 Glacial Blade
19100 3 Electrified Dagger
19101 3 Whiteout Staff
19102 3 Crackling Staff
19103 3 Frostbite
19104 3 Stormstrike Hammer
19105 3 Frost Runed Headdress
19106 3 Ice Barbed Spear
19107 3 Bloodseeker
19108 3 Wand of Biting Cold
19109 3 Deep Rooted Ring
19110 3 Cold Forged Blade
19111 3 Winteraxe Epaulets
19112 3 Frozen Steel Vambraces
19113 3 Yeti Hide Bracers
19114 2 Highland Bow
19115 2 Flask of Forest Mojo
19116 2 Greenleaf Handwraps
19117 2 Laquered Wooden Plate Legplates
19118 2 Nature's Breath
19119 2 Owlbeast Hide Gloves
19120 2 Rune of the Guard Captain
19121 3 Deep Woodlands Cloak
19123 2 Everwarm Handwraps
19124 2 Slagplate Leggings
19125 2 Seared Mail Girdle
19126 2 Slagplate Gauntlets
19127 2 Charred Leather Tunic
19128 2 Seared Mail Vest
19129 2 Everglowing Robe
19130 4 Cold Snap
19131 4 Snowblind Shoes
19132 4 Crystal Adorned Crown
19133 4 Fel Infused Leggings
19134 4 Flayed Doomguard Belt
19135 4 Blacklight Bracer
19136 4 Mana Igniting Cord
19137 4 Onslaught Girdle
19138 4 Band of Sulfuras
19139 4 Fireguard Shoulders
19140 4 Cauterizing Band
19141 2 Luffa
19142 4 Fire Runed Grimoire
19143 4 Flameguard Gauntlets
19144 4 Sabatons of the Flamewalker
19145 4 Robe of Volatile Power
19146 4 Wristguards of Stability
19147 4 Ring of Spell Power
19148 4 Dark Iron Helm
19149 4 Lava Belt
19156 4 Flarecore Robe
19157 4 Chromatic Gauntlets
19159 3 Woven Ivy Necklace
19160 1 Contest Winner's Tabard
19162 4 Corehound Belt
19163 4 Molten Belt
19164 4 Dark Iron Gauntlets
19165 4 Flarecore Leggings
19166 4 Black Amnesty
19167 4 Blackfury
19168 4 Blackguard
19169 4 Nightfall
19170 4 Ebon Hand
19287 4 Darkmoon Card: Heroism
19288 4 Darkmoon Card: Blue Dragon
19289 4 Darkmoon Card: Maelstrom
19290 4 Darkmoon Card: Twisting Nether
19292 1 Last Month's Mutton
19293 1 Last Year's Mutton
19295 1 Darkmoon Flower
19302 3 Darkmoon Ring
19303 3 Darkmoon Necklace
19308 4 Tome of Arcane Domination
19309 4 Tome of Shadow Force
19310 4 Tome of the Ice Lord
19311 4 Tome of Fiery Arcana
19312 4 Lei of the Lifegiver
19315 4 Therazane's Touch
19321 4 The Immovable Object
19323 4 The Unstoppable Force
19324 4 The Lobotomizer
19325 4 Don Julio's Band
19334 4 The Untamed Blade
19335 4 Spineshatter
19336 4 Arcane Infused Gem
19337 4 The Black Book
19339 4 Mind Quickening Gem
19340 4 Rune of Metamorphosis
19341 4 Lifegiving Gem
19342 4 Venomous Totem
19343 4 Scrolls of Blinding Light
19344 4 Natural Alignment Crystal
19345 4 Aegis of Preservation
19346 4 Dragonfang Blade
19347 4 Claw of Chromaggus
19348 4 Red Dragonscale Protector
19349 4 Elementium Reinforced Bulwark
19350 4 Heartstriker
19351 4 Maladath, Runed Blade of the Black Flight
19352 4 Chromatically Tempered Sword
19353 4 Drake Talon Cleaver
19354 4 Draconic Avenger
19355 4 Shadow Wing Focus Staff
19356 4 Staff of the Shadow Flame
19357 4 Herald of Woe
19358 4 Draconic Maul
19360 4 Lok'amir il Romathis
19361 4 Ashjre'thul, Crossbow of Smiting
19362 4 Doom's Edge
19363 4 Crul'shorukh, Edge of Chaos
19364 4 Ashkandi, Greatsword of the Brotherhood
19365 4 Claw of the Black Drake
19366 4 Master Dragonslayer's Orb
19367 4 Dragon's Touch
19368 4 Dragonbreath Hand Cannon
19369 4 Gloves of Rapid Evolution
19370 4 Mantle of the Blackwing Cabal
19371 4 Pendant of the Fallen Dragon
19372 4 Helm of Endless Rage
19373 4 Black Brood Pauldrons
19374 4 Bracers of Arcane Accuracy
19375 4 Mish'undare, Circlet of the Mind Flayer
19376 4 Archimtiros' Ring of Reckoning
19377 4 Prestor's Talisman of Connivery
19378 4 Cloak of the Brood Lord
19379 4 Neltharion's Tear
19380 4 Therazane's Link
19381 4 Boots of the Shadow Flame
19382 4 Pure Elementium Band
19383 4 Master Dragonslayer's Medallion
19384 4 Master Dragonslayer's Ring
19385 4 Empowered Leggings
19386 4 Elementium Threaded Cloak
19387 4 Chromatic Boots
19388 4 Angelista's Grasp
19389 4 Taut Dragonhide Shoulderpads
19390 4 Taut Dragonhide Gloves
19391 4 Shimmering Geta
19392 4 Girdle of the Fallen Crusader
19393 4 Primalist's Linked Waistguard
19394 4 Drake Talon Pauldrons
19395 4 Rejuvenating Gem
19396 4 Taut Dragonhide Belt
19397 4 Ring of Blackrock
19398 4 Cloak of Firemaw
19399 4 Black Ash Robe
19400 4 Firemaw's Clutch
19401 4 Primalist's Linked Legguards
19402 4 Legguards of the Fallen Crusader
19403 4 Band of Forced Concentration
19405 4 Malfurion's Blessed Bulwark
19406 4 Drake Fang Talisman
19407 4 Ebony Flame Gloves
19426 4 Orb of the Darkmoon
19430 4 Shroud of Pure Thought
19431 4 Styleen's Impeding Scarab
19432 4 Circle of Applied Force
19433 4 Emberweave Leggings
19434 4 Band of Dark Dominion
19435 4 Essence Gatherer
19436 4 Cloak of Draconic Might
19437 4 Boots of Pure Thought
19438 4 Ringo's Blizzard Boots
19439 4 Interlaced Shadow Jerkin
19491 4 Amulet of the Darkmoon
19505 1 Warsong Battle Tabard
19506 1 Silverwing Battle Tabard
19507 2 Inquisitor's Shawl
19508 2 Branded Leather Bracers
19509 2 Dusty Mail Boots
19510 3 Legionnaire's Band
19511 3 Legionnaire's Band
19512 3 Legionnaire's Band
19513 3 Legionnaire's Band
19514 3 Protector's Band
19515 3 Protector's Band
19516 3 Protector's Band
19517 3 Protector's Band
19518 3 Advisor's Ring
19519 3 Advisor's Ring
19520 3 Advisor's Ring
19521 3 Advisor's Ring
19522 3 Lorekeeper's Ring
19523 3 Lorekeeper's Ring
19524 3 Lorekeeper's Ring
19525 3 Lorekeeper's Ring
19526 3 Battle Healer's Cloak
19527 3 Battle Healer's Cloak
19528 3 Battle Healer's Cloak
19529 3 Battle Healer's Cloak
19530 3 Caretaker's Cape
19531 3 Caretaker's Cape
19532 3 Caretaker's Cape
19533 3 Caretaker's Cape
19534 3 Scout's Medallion
19535 3 Scout's Medallion
19536 3 Scout's Medallion
19537 3 Scout's Medallion
19538 3 Sentinel's Medallion
19539 3 Sentinel's Medallion
19540 3 Sentinel's Medallion
19541 3 Sentinel's Medallion
19542 3 Scout's Blade
19543 3 Scout's Blade
19544 3 Scout's Blade
19545 3 Scout's Blade
19546 3 Sentinel's Blade
19547 3 Sentinel's Blade
19548 3 Sentinel's Blade
19549 3 Sentinel's Blade
19550 3 Legionnaire's Sword
19551 3 Legionnaire's Sword
19552 3 Legionnaire's Sword
19553 3 Legionnaire's Sword
19554 3 Protector's Sword
19555 3 Protector's Sword
19556 3 Protector's Sword
19557 3 Protector's Sword
19558 3 Outrider's Bow
19559 3 Outrider's Bow
19560 3 Outrider's Bow
19561 3 Outrider's Bow
19562 3 Outrunner's Bow
19563 3 Outrunner's Bow
19564 3 Outrunner's Bow
19565 3 Outrunner's Bow
19566 3 Advisor's Gnarled Staff
19567 3 Advisor's Gnarled Staff
19568 3 Advisor's Gnarled Staff
19569 3 Advisor's Gnarled Staff
19570 3 Lorekeeper's Staff
19571 3 Lorekeeper's Staff
19572 3 Lorekeeper's Staff
19573 3 Lorekeeper's Staff
19574 2 Strength of Mugamba
19575 3 Strength of Mugamba
19576 3 Strength of Mugamba
19577 4 Rage of Mugamba
19578 4 Berserker Bracers
19579 2 Heathen's Brand
19580 4 Berserker Bracers
19581 4 Berserker Bracers
19582 4 Windtalker's Wristguards
19583 4 Windtalker's Wristguards
19584 4 Windtalker's Wristguards
19585 3 Heathen's Brand
19586 3 Heathen's Brand
19587 4 Forest Stalker's Bracers
19588 4 Hero's Brand
19589 4 Forest Stalker's Bracers
19590 4 Forest Stalker's Bracers
19591 2 The Eye of Zuldazar
19592 3 The Eye of Zuldazar
19593 3 The Eye of Zuldazar
19594 4 The All-Seeing Eye of Zuldazar
19595 4 Dryad's Wrist Bindings
19596 4 Dryad's Wrist Bindings
19597 4 Dryad's Wrist Bindings
19598 2 Pebble of Kajaro
19599 3 Pebble of Kajaro
19600 3 Pebble of Kajaro
19601 4 Jewel of Kajaro
19602 2 Kezan's Taint
19603 3 Kezan's Taint
19604 3 Kezan's Taint
19605 4 Kezan's Unstoppable Taint
19606 2 Vision of Voodress
19607 3 Vision of Voodress
19608 3 Vision of Voodress
19609 4 Unmarred Vision of Voodress
19610 2 Enchanted South Seas Kelp
19611 3 Enchanted South Seas Kelp
19612 3 Enchanted South Seas Kelp
19613 4 Pristine Enchanted South Seas Kelp
19614 2 Zandalarian Shadow Talisman
19615 3 Zandalarian Shadow Talisman
19616 3 Zandalarian Shadow Talisman
19617 4 Zandalarian Shadow Mastery Talisman
19618 2 Maelstrom's Tendril
19619 3 Maelstrom's Tendril
19620 3 Maelstrom's Tendril
19621 4 Maelstrom's Wrath
19682 3 Bloodvine Vest
19683 3 Bloodvine Leggings
19684 3 Bloodvine Boots
19685 3 Primal Batskin Jerkin
19686 3 Primal Batskin Gloves
19687 3 Primal Batskin Bracers
19688 3 Blood Tiger Breastplate
19689 3 Blood Tiger Shoulders
19690 3 Bloodsoul Breastplate
19691 3 Bloodsoul Shoulders
19692 3 Bloodsoul Gauntlets
19693 3 Darksoul Breastplate
19694 3 Darksoul Leggings
19695 3 Darksoul Shoulders
19808 2 Rockhide Strongfish
19812 3 Rune of the Dawn
19822 4 Zandalar Vindicator's Breastplate
19823 4 Zandalar Vindicator's Belt
19824 4 Zandalar Vindicator's Armguards
19825 4 Zandalar Freethinker's Breastplate
19826 4 Zandalar Freethinker's Belt
19827 4 Zandalar Freethinker's Armguards
19828 4 Zandalar Augur's Hauberk
19829 4 Zandalar Augur's Belt
19830 4 Zandalar Augur's Bracers
19831 4 Zandalar Predator's Mantle
19832 4 Zandalar Predator's Belt
19833 4 Zandalar Predator's Bracers
19834 4 Zandalar Madcap's Tunic
19835 4 Zandalar Madcap's Mantle
19836 4 Zandalar Madcap's Bracers
19838 4 Zandalar Haruspex's Tunic
19839 4 Zandalar Haruspex's Belt
19840 4 Zandalar Haruspex's Bracers
19841 4 Zandalar Confessor's Mantle
19842 4 Zandalar Confessor's Bindings
19843 4 Zandalar Confessor's Wraps
19845 4 Zandalar Illusionist's Mantle
19846 4 Zandalar Illusionist's Wraps
19848 4 Zandalar Demoniac's Wraps
19849 4 Zandalar Demoniac's Mantle
19852 4 Ancient Hakkari Manslayer
19853 4 Gurubashi Dwarf Destroyer
19854 4 Zin'rokh, Destroyer of Worlds
19855 4 Bloodsoaked Legplates
19856 4 The Eye of Hakkar
19857 4 Cloak of Consumption
19859 4 Fang of the Faceless
19861 4 Touch of Chaos
19862 4 Aegis of the Blood God
19863 3 Primalist's Seal
19864 4 Bloodcaller
19865 4 Warblade of the Hakkari
19866 4 Warblade of the Hakkari
19867 4 Bloodlord's Defender
19869 3 Blooddrenched Grips
19870 3 Hakkari Loa Cloak
19871 3 Talisman of Protection
19873 3 Overlord's Crimson Band
19874 4 Halberd of Smiting
19875 3 Bloodstained Coif
19876 4 Soul Corrupter's Necklace
19877 3 Animist's Leggings
19878 3 Bloodsoaked Pauldrons
19884 4 Jin'do's Judgement
19885 4 Jin'do's Evil Eye
19886 3 The Hexxer's Cover
19887 3 Bloodstained Legplates
19888 3 Overlord's Embrace
19889 3 Blooddrenched Leggings
19890 4 Jin'do's Hexxer
19891 4 Jin'do's Bag of Whammies
19892 3 Animist's Boots
19893 3 Zanzil's Seal
19894 3 Bloodsoaked Gauntlets
19895 3 Bloodtinged Kilt
19896 4 Thekal's Grasp
19897 4 Betrayer's Boots
19898 3 Seal of Jin
19899 3 Ritualistic Legguards
19900 3 Zulian Stone Axe
19901 3 Zulian Slicer
19903 4 Fang of Venoxis
19904 4 Runed Bloodstained Hauberk
19905 3 Zanzil's Band
19906 3 Blooddrenched Footpads
19907 3 Zulian Tigerhide Cloak
19908 3 Sceptre of Smiting
19909 4 Will of Arlokk
19910 4 Arlokk's Grasp
19912 3 Overlord's Onyx Band
19913 3 Bloodsoaked Greaves
19915 3 Zulian Defender
19918 4 Jeklik's Crusher
19919 3 Bloodstained Greaves
19920 3 Primalist's Band
19921 3 Zulian Hacker
19922 3 Arlokk's Hoodoo Stick
19923 3 Jeklik's Opaline Talisman
19925 3 Band of Jin
19927 4 Mar'li's Touch
19928 3 Animist's Spaulders
19929 3 Bloodtinged Gloves
19930 3 Mar'li's Eye
19944 4 Nat Pagle's Fish Terminator
19945 4 Lizardscale Eyepatch
19946 3 Tigule's Harpoon
19947 3 Nat Pagle's Broken Reel
19948 4 Zandalarian Hero Badge
19949 4 Zandalarian Hero Medallion
19950 4 Zandalarian Hero Charm
19951 4 Gri'lek's Charm of Might
19952 4 Gri'lek's Charm of Valor
19953 4 Renataki's Charm of Beasts
19954 4 Renataki's Charm of Trickery
19955 4 Wushoolay's Charm of Nature
19956 4 Wushoolay's Charm of Spirits
19957 4 Hazza'rah's Charm of Destruction
19958 4 Hazza'rah's Charm of Healing
19959 4 Hazza'rah's Charm of Magic
19961 3 Gri'lek's Grinder
19962 3 Gri'lek's Carver
19963 3 Pitchfork of Madness
19964 3 Renataki's Soul Conduit
19965 3 Wushoolay's Poker
19967 3 Thoughtblighter
19968 3 Fiery Retributer
19969 2 Nat Pagle's Extreme Anglin' Boots
19970 3 Arcanite Fishing Pole
19972 2 Lucky Fishing Hat
19979 3 Hook of the Master Angler
19982 3 Duskbat Drape
19984 3 Ebon Mask
19986 3 Pirate's Eye Patch
19989 3 Tome of Devouring Shadows
19990 3 Blessed Prayer Beads
19991 3 Devilsaur Eye
19992 3 Devilsaur Tooth
19993 3 Hoodoo Hunting Bow
19998 3 Bloodvine Lens
19999 3 Bloodvine Goggles
20003 3 Devilsaur Claws
20005 3 Devilsaur Claws
20006 3 Circle of Hope
20032 4 Flowing Ritual Robes
20033 4 Zandalar Demoniac's Robe
20034 4 Zandalar Illusionist's Robe
20035 3 Glacial Spike
20036 3 Fire Ruby
20037 3 Arcane Crystal Pendant
20038 4 Mandokir's Sting
20039 4 Dark Iron Boots
20041 3 Highlander's Plate Girdle
20042 3 Highlander's Lamellar Girdle
20043 3 Highlander's Chain Girdle
20044 3 Highlander's Mail Girdle
20045 3 Highlander's Leather Girdle
20046 3 Highlander's Lizardhide Girdle
20047 3 Highlander's Cloth Girdle
20048 3 Highlander's Plate Greaves
20049 3 Highlander's Lamellar Greaves
20050 3 Highlander's Chain Greaves
20051 3 Highlander's Mail Greaves
20052 3 Highlander's Leather Boots
20053 3 Highlander's Lizardhide Boots
20054 3 Highlander's Cloth Boots
20055 4 Highlander's Chain Pauldrons
20056 4 Highlander's Mail Pauldrons
20057 4 Highlander's Plate Spaulders
20058 4 Highlander's Lamellar Spaulders
20059 4 Highlander's Leather Shoulders
20060 4 Highlander's Lizardhide Shoulders
20061 4 Highlander's Epaulets
20068 4 Deathguard's Cloak
20069 4 Ironbark Staff
20070 4 Sageclaw
20071 3 Talisman of Arathor
20072 3 Defiler's Talisman
20073 4 Cloak of the Honor Guard
20082 3 Woestave
20083 3 Hunting Spear
20084 3 Hunting Net
20086 2 Dusksteel Throwing Knife
20088 3 Highlander's Chain Girdle
20089 3 Highlander's Chain Girdle
20090 3 Highlander's Chain Girdle
20091 3 Highlander's Chain Greaves
20092 3 Highlander's Chain Greaves
20093 3 Highlander's Chain Greaves
20094 3 Highlander's Cloth Boots
20095 3 Highlander's Cloth Boots
20096 3 Highlander's Cloth Boots
20097 3 Highlander's Cloth Girdle
20098 3 Highlander's Cloth Girdle
20099 3 Highlander's Cloth Girdle
20100 3 Highlander's Lizardhide Boots
20101 3 Highlander's Lizardhide Boots
20102 3 Highlander's Lizardhide Boots
20103 3 Highlander's Lizardhide Girdle
20104 3 Highlander's Lizardhide Girdle
20105 3 Highlander's Lizardhide Girdle
20106 3 Highlander's Lamellar Girdle
20107 3 Highlander's Lamellar Girdle
20108 3 Highlander's Lamellar Girdle
20109 3 Highlander's Lamellar Greaves
20110 3 Highlander's Lamellar Greaves
20111 3 Highlander's Lamellar Greaves
20112 3 Highlander's Leather Boots
20113 3 Highlander's Leather Boots
20114 3 Highlander's Leather Boots
20115 3 Highlander's Leather Girdle
20116 3 Highlander's Leather Girdle
20117 3 Highlander's Leather Girdle
20118 3 Highlander's Mail Girdle
20119 3 Highlander's Mail Girdle
20120 3 Highlander's Mail Girdle
20121 3 Highlander's Mail Greaves
20122 3 Highlander's Mail Greaves
20123 3 Highlander's Mail Greaves
20124 3 Highlander's Plate Girdle
20125 3 Highlander's Plate Girdle
20126 3 Highlander's Plate Girdle
20127 3 Highlander's Plate Greaves
20128 3 Highlander's Plate Greaves
20129 3 Highlander's Plate Greaves
20130 3 Diamond Flask
20131 1 Battle Tabard of the Defilers
20132 1 Arathor Battle Tabard
20134 4 Skyfury Helm
20150 3 Defiler's Chain Girdle
20151 3 Defiler's Chain Girdle
20152 3 Defiler's Chain Girdle
20153 3 Defiler's Chain Girdle
20154 3 Defiler's Chain Greaves
20155 3 Defiler's Chain Greaves
20156 3 Defiler's Chain Greaves
20157 3 Defiler's Chain Greaves
20158 4 Defiler's Chain Pauldrons
20159 3 Defiler's Cloth Boots
20160 3 Defiler's Cloth Boots
20161 3 Defiler's Cloth Boots
20162 3 Defiler's Cloth Boots
20163 3 Defiler's Cloth Girdle
20164 3 Defiler's Cloth Girdle
20165 3 Defiler's Cloth Girdle
20166 3 Defiler's Cloth Girdle
20167 3 Defiler's Lizardhide Boots
20168 3 Defiler's Lizardhide Boots
20169 3 Defiler's Lizardhide Boots
20170 3 Defiler's Lizardhide Boots
20171 3 Defiler's Lizardhide Girdle
20172 3 Defiler's Lizardhide Girdle
20173 3 Defiler's Lizardhide Girdle
20174 3 Defiler's Lizardhide Girdle
20175 4 Defiler's Lizardhide Shoulders
20176 4 Defiler's Epaulets
20177 3 Defiler's Lamellar Girdle
20178 3 Defiler's Lamellar Girdle
20179 3 Defiler's Lamellar Girdle
20180 3 Defiler's Lamellar Girdle
20181 3 Defiler's Lamellar Greaves
20182 3 Defiler's Lamellar Greaves
20183 3 Defiler's Lamellar Greaves
20184 4 Defiler's Lamellar Spaulders
20185 3 Defiler's Lamellar Greaves
20186 3 Defiler's Leather Boots
20187 3 Defiler's Leather Boots
20188 3 Defiler's Leather Boots
20189 3 Defiler's Leather Boots
20190 3 Defiler's Leather Girdle
20191 3 Defiler's Leather Girdle
20192 3 Defiler's Leather Girdle
20193 3 Defiler's Leather Girdle
20194 4 Defiler's Leather Shoulders
20195 3 Defiler's Mail Girdle
20196 3 Defiler's Mail Girdle
20197 3 Defiler's Mail Girdle
20198 3 Defiler's Mail Girdle
20199 3 Defiler's Mail Greaves
20200 3 Defiler's Mail Greaves
20201 3 Defiler's Mail Greaves
20202 3 Defiler's Mail Greaves
20203 4 Defiler's Mail Pauldrons
20204 3 Defiler's Plate Girdle
20205 3 Defiler's Plate Girdle
20206 3 Defiler's Plate Girdle
20207 3 Defiler's Plate Girdle
20208 3 Defiler's Plate Greaves
20209 3 Defiler's Plate Greaves
20210 3 Defiler's Plate Greaves
20211 3 Defiler's Plate Greaves
20212 4 Defiler's Plate Spaulders
20213 3 Belt of Shrunken Heads
20214 4 Mindfang
20215 3 Belt of Shriveled Heads
20216 3 Belt of Preserved Heads
20217 3 Belt of Tiny Heads
20218 3 Faded Hakkari Cloak
20219 3 Tattered Hakkari Cape
20220 4 Ironbark Staff
20255 3 Whisperwalk Boots
20257 4 Seafury Gauntlets
20258 3 Zulian Ceremonial Staff
20259 3 Shadow Panther Hide Gloves
20260 3 Seafury Leggings
20261 3 Shadow Panther Hide Belt
20262 3 Seafury Boots
20263 3 Gurubashi Helm
20264 4 Peacekeeper Gauntlets
20265 3 Peacekeeper Boots
20266 3 Peacekeeper Leggings
20295 3 Blue Dragonscale Leggings
20296 3 Green Dragonscale Gauntlets
20337 1 Gnome Head on a Stick
20368 3 Bland Bow of Steadiness
20369 3 Azurite Fists
20380 4 Dreamscale Breastplate
20391 1 Flimsy Male Gnome Mask
20392 1 Flimsy Female Gnome Mask
20406 2 Twilight Cultist Mantle
20407 2 Twilight Cultist Robe
20408 2 Twilight Cultist Cowl
20422 1 Twilight Cultist Medallion of Station
20425 3 Advisor's Gnarled Staff
20426 3 Advisor's Ring
20427 3 Battle Healer's Cloak
20428 3 Caretaker's Cape
20429 3 Legionnaire's Band
20430 3 Legionnaire's Sword
20431 3 Lorekeeper's Ring
20434 3 Lorekeeper's Staff
20437 3 Outrider's Bow
20438 3 Outrunner's Bow
20439 3 Protector's Band
20440 3 Protector's Sword
20441 3 Scout's Blade
20442 3 Scout's Medallion
20443 3 Sentinel's Blade
20444 3 Sentinel's Medallion
20451 1 Twilight Cultist Ring of Lordship
20476 3 Sandstalker Bracers
20477 3 Sandstalker Gauntlets
20478 3 Sandstalker Breastplate
20479 3 Spitfire Breastplate
20480 3 Spitfire Gauntlets
20481 3 Spitfire Bracers
20502 3 Ironbark Shield
20503 3 Enamored Water Spirit
20504 3 Lightforged Blade
20505 3 Chivalrous Signet
20512 3 Sanctified Orb
20517 3 Razorsteel Shoulders
20521 3 Fury Visor
20522 3 Feral Staff
20524 3 Shadowhide Leggings
20525 3 Earthen Sigil
20530 3 Robes of Servitude
20534 3 Abyss Shard
20536 3 Soul Harvester
20537 3 Runed Stygian Boots
20538 3 Runed Stygian Leggings
20539 3 Runed Stygian Belt
20549 3 Darkrune Gauntlets
20550 3 Darkrune Breastplate
20551 3 Darkrune Helm
20556 3 Wildstaff
20561 1 Flimsy Male Dwarf Mask
20562 1 Flimsy Female Dwarf Mask
20563 1 Flimsy Female Nightelf Mask
20564 1 Flimsy Male Nightelf Mask
20565 1 Flimsy Female Human Mask
20566 1 Flimsy Male Human Mask
20567 1 Flimsy Female Troll Mask
20568 1 Flimsy Male Troll Mask
20569 1 Flimsy Female Orc Mask
20570 1 Flimsy Male Orc Mask
20571 1 Flimsy Female Tauren Mask
20572 1 Flimsy Male Tauren Mask
20573 1 Flimsy Male Undead Mask
20574 1 Flimsy Female Undead Mask
20575 2 Black Whelp Tunic
20577 4 Nightmare Blade
20578 4 Emerald Dragonfang
20579 4 Green Dragonskin Cloak
20580 4 Hammer of Bestial Fury
20581 4 Staff of Rampant Growth
20582 4 Trance Stone
20583 2 Sturdy Female Dwarf Mask
20584 2 Sturdy Female Gnome Mask
20585 2 Sturdy Female Human Mask
20586 2 Sturdy Female Nightelf Mask
20587 2 Sturdy Female Orc Mask
20588 2 Sturdy Female Tauren Mask
20589 2 Sturdy Female Troll Mask
20590 2 Sturdy Female Undead Mask
20591 2 Sturdy Male Dwarf Mask
20592 2 Sturdy Male Gnome Mask
20593 2 Sturdy Male Human Mask
20594 2 Sturdy Male Nightelf Mask
20595 2 Sturdy Male Orc Mask
20596 2 Sturdy Male Tauren Mask
20597 2 Sturdy Male Troll Mask
20598 2 Sturdy Male Undead Mask
20599 4 Polished Ironwood Crossbow
20600 4 Malfurion's Signet Ring
20615 4 Dragonspur Wraps
20616 4 Dragonbone Wristguards
20617 4 Ancient Corroded Leggings
20618 4 Gloves of Delusional Power
20619 4 Acid Inscribed Greaves
20621 4 Boots of the Endless Moor
20622 4 Dragonheart Necklace
20623 4 Circlet of Restless Dreams
20624 4 Ring of the Unliving
20625 4 Belt of the Dark Bog
20626 4 Black Bark Wristbands
20627 4 Dark Heart Pants
20628 4 Deviate Growth Cap
20629 4 Malignant Footguards
20630 4 Gauntlets of the Shining Light
20631 4 Mendicant's Slippers
20632 4 Mindtear Band
20633 4 Unnatural Leather Spaulders
20634 4 Boots of Fright
20635 4 Jade Inlaid Vestments
20636 4 Hibernation Crystal
20637 4 Acid Inscribed Pauldrons
20638 4 Leggings of the Demented Mind
20639 4 Strangely Glyphed Legplates
20640 2 Southsea Head Bucket
20641 2 Southsea Mojo Boots
20642 2 Antiquated Nobleman's Tunic
20643 2 Undercity Reservist's Cap
20645 2 Nature's Whisper
20646 2 Sandstrider's Mark
20647 2 Black Crystal Dagger
20648 3 Cold Forged Hammer
20649 2 Sunprism Pendant
20650 2 Desert Wind Gauntlets
20652 2 Abyssal Cloth Slippers
20653 2 Abyssal Plate Gauntlets
20654 3 Amethyst War Staff
20655 2 Abyssal Cloth Handwraps
20656 2 Abyssal Mail Sabatons
20657 3 Crystal Tipped Stiletto
20658 2 Abyssal Leather Boots
20659 2 Abyssal Mail Handguards
20660 3 Stonecutting Glaive
20661 2 Abyssal Leather Gloves
20662 2 Abyssal Plate Greaves
20663 3 Deep Strike Bow
20664 2 Abyssal Cloth Sash
20665 3 Abyssal Leather Leggings
20666 3 Hardened Steel Warhammer
20667 2 Abyssal Leather Belt
20668 3 Abyssal Mail Legguards
20669 3 Darkstone Claymore
20670 2 Abyssal Mail Clutch
20671 3 Abyssal Plate Legplates
20672 3 Sparkling Crystal Wand
20673 2 Abyssal Plate Girdle
20674 3 Abyssal Cloth Pants
20675 3 Soulrender
20680 3 Abyssal Mail Pauldrons
20681 3 Abyssal Leather Bracers
20682 4 Elemental Focus Band
20683 3 Abyssal Plate Epaulets
20684 3 Abyssal Mail Armguards
20685 4 Wavefront Necklace
20686 3 Abyssal Cloth Amice
20687 3 Abyssal Plate Vambraces
20688 4 Earthen Guard
20689 3 Abyssal Leather Shoulders
20690 3 Abyssal Cloth Wristbands
20691 4 Windshear Cape
20692 2 Multicolored Band
20693 2 Weighted Cloak
20694 2 Glowing Black Orb
20695 3 Abyssal War Beads
20696 3 Crystal Spiked Maul
20697 3 Crystalline Threaded Cape
20698 4 Elemental Attuned Blade
20699 3 Cenarion Reservist's Legplates
20700 3 Cenarion Reservist's Legplates
20701 3 Cenarion Reservist's Legguards
20702 3 Cenarion Reservist's Legguards
20703 3 Cenarion Reservist's Leggings
20704 3 Cenarion Reservist's Leggings
20705 3 Cenarion Reservist's Pants
20706 3 Cenarion Reservist's Pants
20707 3 Cenarion Reservist's Pants
20710 3 Crystal Encrusted Greaves
20711 3 Crystal Lined Greaves
20712 3 Wastewalker's Gauntlets
20713 3 Desertstalkers's Gauntlets
20714 3 Sandstorm Boots
20715 3 Dunestalker's Boots
20716 3 Sandworm Skin Gloves
20717 3 Desert Bloom Gloves
20720 3 Dark Whisper Blade
20721 3 Band of the Cultist
20722 3 Crystal Slugthrower
20723 2 Brann's Trusty Pick
20724 2 Corrupted Blackwood Staff
20814 1 Master's Throwing Dagger
21040 1 Narain's Robe
21115 3 Defiler's Talisman
21116 3 Defiler's Talisman
21117 3 Talisman of Arathor
21118 3 Talisman of Arathor
21119 3 Talisman of Arathor
21120 3 Defiler's Talisman
21126 4 Death's Sting
21128 4 Staff of the Qiraji Prophets
21134 4 Dark Edge of Insanity
21135 3 Assassin's Throwing Axe
21154 1 Festival Dress
21157 1 Festive Green Dress
21178 3 Gloves of Earthen Power
21179 3 Band of Earthen Wrath
21180 4 Earthstrike
21181 3 Grace of Earth
21182 3 Band of Earthen Might
21183 3 Earthpower Vest
21184 4 Deeprock Bracers
21185 4 Earthcalm Orb
21186 4 Rockfury Bracers
21187 3 Earthweave Cloak
21188 4 Fist of Cenarius
21189 4 Might of Cenarius
21190 4 Wrath of Cenarius
21196 4 Signet Ring of the Bronze Dragonflight
21197 4 Signet Ring of the Bronze Dragonflight
21198 4 Signet Ring of the Bronze Dragonflight
21199 4 Signet Ring of the Bronze Dragonflight
21200 4 Signet Ring of the Bronze Dragonflight
21201 4 Signet Ring of the Bronze Dragonflight
21202 4 Signet Ring of the Bronze Dragonflight
21203 4 Signet Ring of the Bronze Dragonflight
21204 4 Signet Ring of the Bronze Dragonflight
21205 4 Signet Ring of the Bronze Dragonflight
21206 4 Signet Ring of the Bronze Dragonflight
21207 4 Signet Ring of the Bronze Dragonflight
21208 4 Signet Ring of the Bronze Dragonflight
21209 4 Signet Ring of the Bronze Dragonflight
21210 4 Signet Ring of the Bronze Dragonflight
21242 4 Blessed Qiraji War Axe
21244 4 Blessed Qiraji Pugio
21268 4 Blessed Qiraji War Hammer
21269 4 Blessed Qiraji Bulwark
21272 4 Blessed Qiraji Musket
21273 4 Blessed Qiraji Acolyte Staff
21275 4 Blessed Qiraji Augur Staff
21278 3 Stormshroud Gloves
21311 2 Earth Warder's Vest
21312 2 Belt of the Den Watcher
21316 2 Leggings of the Ursa
21317 2 Helm of the Pathfinder
21318 2 Earth Warder's Gloves
21319 2 Gloves of the Pathfinder
21320 2 Vest of the Den Watcher
21322 2 Ursa's Embrace
21326 4 Defender of the Timbermaw
21329 4 Conqueror's Crown
21330 4 Conqueror's Spaulders
21331 4 Conqueror's Breastplate
21332 4 Conqueror's Legguards
21333 4 Conqueror's Greaves
21334 4 Doomcaller's Robes
21335 4 Doomcaller's Mantle
21336 4 Doomcaller's Trousers
21337 4 Doomcaller's Circlet
21338 4 Doomcaller's Footwraps
21343 4 Enigma Robes
21344 4 Enigma Boots
21345 4 Enigma Shoulderpads
21346 4 Enigma Leggings
21347 4 Enigma Circlet
21348 4 Tiara of the Oracle
21349 4 Footwraps of the Oracle
21350 4 Mantle of the Oracle
21351 4 Vestments of the Oracle
21352 4 Trousers of the Oracle
21353 4 Genesis Helm
21354 4 Genesis Shoulderpads
21355 4 Genesis Boots
21356 4 Genesis Trousers
21357 4 Genesis Vest
21359 4 Deathdealer's Boots
21360 4 Deathdealer's Helm
21361 4 Deathdealer's Spaulders
21362 4 Deathdealer's Leggings
21364 4 Deathdealer's Vest
21365 4 Striker's Footguards
21366 4 Striker's Diadem
21367 4 Striker's Pauldrons
21368 4 Striker's Leggings
21370 4 Striker's Hauberk
21372 4 Stormcaller's Diadem
21373 4 Stormcaller's Footguards
21374 4 Stormcaller's Hauberk
21375 4 Stormcaller's Leggings
21376 4 Stormcaller's Pauldrons
21387 4 Avenger's Crown
21388 4 Avenger's Greaves
21389 4 Avenger's Breastplate
21390 4 Avenger's Legguards
21391 4 Avenger's Pauldrons
21392 4 Sickle of Unyielding Strength
21393 4 Signet of Unyielding Strength
21394 4 Drape of Unyielding Strength
21395 4 Blade of Eternal Justice
21396 4 Ring of Eternal Justice
21397 4 Cape of Eternal Justice
21398 4 Hammer of the Gathering Storm
21399 4 Ring of the Gathering Storm
21400 4 Cloak of the Gathering Storm
21401 4 Scythe of the Unseen Path
21402 4 Signet of the Unseen Path
21403 4 Cloak of the Unseen Path
21404 4 Dagger of Veiled Shadows
21405 4 Band of Veiled Shadows
21406 4 Cloak of Veiled Shadows
21407 4 Mace of Unending Life
21408 4 Band of Unending Life
21409 4 Cloak of Unending Life
21410 4 Gavel of Infinite Wisdom
21411 4 Ring of Infinite Wisdom
21412 4 Shroud of Infinite Wisdom
21413 4 Blade of Vaulted Secrets
21414 4 Band of Vaulted Secrets
21415 4 Drape of Vaulted Secrets
21416 4 Kris of Unspoken Names
21417 4 Ring of Unspoken Names
21418 4 Shroud of Unspoken Names
21452 4 Staff of the Ruins
21453 4 Mantle of the Horusath
21454 4 Runic Stone Shoulders
21455 3 Southwind Helm
21456 4 Sandstorm Cloak
21457 4 Bracers of Brutality
21458 4 Gauntlets of New Life
21459 4 Crossbow of Imminent Doom
21460 4 Helm of Domination
21461 4 Leggings of the Black Blizzard
21462 4 Gloves of Dark Wisdom
21463 4 Ossirian's Binding
21464 4 Shackles of the Unscarred
21466 4 Stinger of Ayamiss
21467 4 Thick Silithid Chestguard
21468 3 Mantle of Maz'Nadir
21469 3 Gauntlets of Southwind
21470 3 Cloak of the Savior
21471 4 Talon of Furious Concentration
21472 4 Dustwind Turban
21473 3 Eye of Moam
21474 3 Chitinous Shoulderguards
21475 3 Legplates of the Destroyer
21476 3 Obsidian Scaled Leggings
21477 3 Ring of Fury
21478 4 Bow of Taut Sinew
21479 4 Gauntlets of the Immovable
21480 3 Scaled Silithid Gauntlets
21481 3 Boots of the Desert Protector
21482 3 Boots of the Fiery Sands
21483 3 Ring of the Desert Winds
21484 3 Helm of Regrowth
21485 4 Buru's Skull Fragment
21486 4 Gloves of the Swarm
21487 4 Slimy Scaled Gauntlets
21488 3 Fetish of Chitinous Spikes
21489 3 Quicksand Waders
21490 3 Slime Kickers
21491 3 Scaled Bracers of the Gorger
21492 4 Manslayer of the Qiraji
21493 4 Boots of the Vanguard
21494 3 Southwind's Grasp
21495 3 Legplates of the Qiraji Command
21496 3 Bracers of Qiraji Command
21497 3 Boots of the Qiraji General
21498 4 Qiraji Sacrificial Dagger
21499 4 Vestments of the Shifting Sands
21500 3 Belt of the Inquisition
21501 3 Toughened Silithid Hide Gloves
21502 3 Sand Reaver Wristguards
21503 3 Belt of the Sand Reaver
21504 4 Charm of the Shifting Sands
21505 4 Choker of the Shifting Sands
21506 4 Pendant of the Shifting Sands
21507 4 Amulet of the Shifting Sands
21517 4 Gnomish Turban of Psychic Might
21520 4 Ravencrest's Legacy
21521 4 Runesword of the Red
21522 4 Shadowsong's Sorrow
21523 4 Fang of Korialstrasz
21524 2 Red Winter Hat
21525 2 Green Winter Hat
21526 4 Band of Icy Depths
21527 4 Darkwater Robes
21529 4 Amulet of Shadow Shielding
21530 4 Onyx Embedded Leggings
21531 4 Drake Tooth Necklace
21532 4 Drudge Boots
21538 1 Festive Pink Dress
21539 1 Festive Purple Dress
21541 1 Festive Black Pant Suit
21542 1 Festival Suit
21543 1 Festive Teal Pant Suit
21544 1 Festive Blue Pant Suit
21563 4 Don Rodrigo's Band
21565 3 Rune of Perfection
21566 3 Rune of Perfection
21567 3 Rune of Duty
21568 3 Rune of Duty
21579 4 Vanquished Tentacle of C'Thun
21581 4 Gauntlets of Annihilation
21582 4 Grasp of the Old God
21583 4 Cloak of Clarity
21584 4 Bracers of Eternal Reckoning
21585 4 Dark Storm Gauntlets
21586 4 Belt of Never-ending Agony
21587 4 Wristguards of Castigation
21588 4 Wristguards of Elemental Fury
21594 4 Bracers of the Fallen Son
21596 4 Ring of the Godslayer
21597 4 Royal Scepter of Vek'lor
21598 4 Royal Qiraji Belt
21599 4 Vek'lor's Gloves of Devastation
21600 4 Boots of Epiphany
21601 4 Ring of Emperor Vek'lor
21602 4 Qiraji Execution Bracers
21603 4 Wand of Qiraji Nobility
21604 4 Bracelets of Royal Redemption
21605 4 Gloves of the Hidden Temple
21606 4 Belt of the Fallen Emperor
21607 4 Grasp of the Fallen Emperor
21608 4 Amulet of Vek'nilash
21609 4 Regenerating Belt of Vek'nilash
21610 4 Wormscale Blocker
21611 4 Burrower Bracers
21612 4 Wormscale Stompers
21613 4 Wormhide Boots
21614 4 Wormhide Protector
21615 4 Don Rigoberto's Lost Hat
21616 4 Huhuran's Stinger
21617 4 Wasphide Gauntlets
21618 4 Hive Defiler Wristguards
21619 4 Gloves of the Messiah
21620 4 Ring of the Martyr
21621 4 Cloak of the Golden Hive
21622 4 Sharpened Silithid Femur
21623 4 Gauntlets of the Righteous Champion
21624 4 Gauntlets of Kalimdor
21625 4 Scarab Brooch
21626 4 Slime-coated Leggings
21627 4 Cloak of Untold Secrets
21635 4 Barb of the Sand Reaver
21639 4 Pauldrons of the Unrelenting
21645 4 Hive Tunneler's Boots
21647 4 Fetish of the Sand Reaver
21648 4 Recomposed Boots
21650 4 Ancient Qiraji Ripper
21651 4 Scaled Sand Reaver Leggings
21652 4 Silithid Carapace Chestguard
21663 4 Robes of the Guardian Saint
21664 4 Barbed Choker
21665 4 Mantle of Wicked Revenge
21666 4 Sartura's Might
21667 4 Legplates of Blazing Light
21668 4 Scaled Leggings of Qiraji Fury
21669 4 Creeping Vine Helm
21670 4 Badge of the Swarmguard
21671 4 Robes of the Battleguard
21672 4 Gloves of Enforcement
21673 4 Silithid Claw
21674 4 Gauntlets of Steadfast Determination
21675 4 Thick Qirajihide Belt
21676 4 Leggings of the Festering Swarm
21677 4 Ring of the Qiraji Fury
21678 4 Necklace of Purity
21679 4 Kalimdor's Revenge
21680 4 Vest of Swift Execution
21681 4 Ring of the Devoured
21682 4 Bile-Covered Gauntlets
21683 4 Mantle of the Desert Crusade
21684 4 Mantle of the Desert's Fury
21685 4 Petrified Scarab
21686 4 Mantle of Phrenic Power
21687 4 Ukko's Ring of Darkness
21688 4 Boots of the Fallen Hero
21689 4 Gloves of Ebru
21690 4 Angelista's Charm
21691 4 Ooze-ridden Gauntlets
21692 4 Triad Girdle
21693 4 Guise of the Devourer
21694 4 Ternary Mantle
21695 4 Angelista's Touch
21696 4 Robes of the Triumvirate
21697 4 Cape of the Trinity
21698 4 Leggings of Immersion
21699 4 Barrage Shoulders
21700 4 Pendant of the Qiraji Guardian
21701 4 Cloak of Concentrated Hatred
21702 4 Amulet of Foul Warding
21703 4 Hammer of Ji'zhi
21704 4 Boots of the Redeemed Prophecy
21705 4 Boots of the Fallen Prophet
21706 4 Boots of the Unwavering Will
21707 4 Ring of Swarming Thought
21708 4 Beetle Scaled Wristguards
21709 4 Ring of the Fallen God
21710 4 Cloak of the Fallen God
21712 4 Amulet of the Fallen God
21715 4 Sand Polished Hammer
21800 3 Silithid Husked Launcher
21801 3 Antenna of Invigoration
21802 3 The Lost Kris of Zedd
21803 3 Helm of the Holy Avenger
21804 3 Coif of Elemental Fury
21805 3 Polished Obsidian Pauldrons
21806 3 Gavel of Qiraji Authority
21809 3 Fury of the Forgotten Swarm
21810 3 Treads of the Wandering Nomad
21814 4 Breastplate of Annihilation
21836 4 Ritssyn's Ring of Chaos
21837 4 Anubisath Warhammer
21838 4 Garb of Royal Ascension
21839 4 Scepter of the False Prophet
21856 4 Neretzek, The Blood Drinker
21888 4 Gloves of the Immortal
21889 4 Gloves of the Redeemed Prophecy
21890 4 Gloves of the Fallen Prophet
21891 4 Shard of the Fallen Star
21994 3 Belt of Heroism
21995 4 Boots of Heroism
21996 3 Bracers of Heroism
21997 4 Breastplate of Heroism
21998 4 Gauntlets of Heroism
21999 4 Helm of Heroism
22000 3 Legplates of Heroism
22001 3 Spaulders of Heroism
22002 3 Darkmantle Belt
22003 4 Darkmantle Boots
22004 3 Darkmantle Bracers
22005 4 Darkmantle Cap
22006 4 Darkmantle Gloves
22007 3 Darkmantle Pants
22008 3 Darkmantle Spaulders
22009 4 Darkmantle Tunic
22010 3 Beastmaster's Belt
22011 3 Beastmaster's Bindings
22013 4 Beastmaster's Cap
22015 4 Beastmaster's Gloves
22016 3 Beastmaster's Mantle
22017 3 Beastmaster's Pants
22060 4 Beastmaster's Tunic
22061 4 Beastmaster's Boots
22062 3 Sorcerer's Belt
22063 3 Sorcerer's Bindings
22064 4 Sorcerer's Boots
22065 4 Sorcerer's Crown
22066 4 Sorcerer's Gloves
22067 3 Sorcerer's Leggings
22068 3 Sorcerer's Mantle
22069 4 Sorcerer's Robes
22070 3 Deathmist Belt
22071 3 Deathmist Bracers
22072 3 Deathmist Leggings
22073 3 Deathmist Mantle
22074 4 Deathmist Mask
22075 4 Deathmist Robe
22076 4 Deathmist Sandals
22077 4 Deathmist Wraps
22078 3 Virtuous Belt
22079 3 Virtuous Bracers
22080 4 Virtuous Crown
22081 4 Virtuous Gloves
22082 3 Virtuous Mantle
22083 4 Virtuous Robe
22084 4 Virtuous Sandals
22085 3 Virtuous Skirt
22086 3 Soulforge Belt
22087 4 Soulforge Boots
22088 3 Soulforge Bracers
22089 4 Soulforge Breastplate
22090 4 Soulforge Gauntlets
22091 4 Soulforge Helm
22092 3 Soulforge Legplates
22093 3 Soulforge Spaulders
22095 3 Bindings of The Five Thunders
22096 4 Boots of The Five Thunders
22097 4 Coif of The Five Thunders
22098 3 Cord of The Five Thunders
22099 4 Gauntlets of The Five Thunders
22100 3 Kilt of The Five Thunders
22101 3 Pauldrons of The Five Thunders
22102 4 Vest of The Five Thunders
22106 3 Feralheart Belt
22107 4 Feralheart Boots
22108 3 Feralheart Bracers
22109 4 Feralheart Cowl
22110 4 Feralheart Gloves
22111 3 Feralheart Kilt
22112 3 Feralheart Spaulders
22113 4 Feralheart Vest
22149 3 Beads of Ogre Mojo
22150 3 Beads of Ogre Might
22191 4 Obsidian Mail Tunic
22194 4 Black Grasp of the Destroyer
22195 3 Light Obsidian Belt
22196 4 Thick Obsidian Breastplate
22197 3 Heavy Obsidian Belt
22198 4 Jagged Obsidian Shield
22204 3 Wristguards of Renown
22205 3 Black Steel Bindings
22206 2 Bouquet of Red Roses
22207 3 Sash of the Grand Hunt
22208 3 Lavastone Hammer
22212 3 Golem Fitted Pauldrons
22223 3 Foreman's Head Protector
22225 3 Dragonskin Cowl
22230 3 Frightmaw Hide
22231 3 Kayser's Boots of Precision
22232 3 Marksman's Girdle
22234 3 Mantle of Lost Hope
22240 3 Greaves of Withering Despair
22241 3 Dark Warder's Pauldrons
22242 3 Verek's Leash
22245 3 Soot Encrusted Footwear
22247 3 Faith Healer's Boots
22253 3 Tome of the Lost
22254 3 Wand of Eternal Light
22255 3 Magma Forged Band
22256 3 Mana Shaping Handwraps
22257 3 Bloodclot Band
22266 3 Flarethorn
22267 3 Spellweaver's Turban
22268 3 Draconic Infused Emblem
22269 3 Shadow Prowler's Cloak
22270 3 Entrenching Boots
22271 3 Leggings of Frenzied Magic
22272 3 Forest's Embrace
22273 3 Moonshadow Hood
22274 3 Grizzled Pelt
22275 3 Firemoss Boots
22276 1 Lovely Red Dress
22277 1 Red Dinner Suit
22278 1 Lovely Blue Dress
22279 1 Lovely Black Dress
22280 1 Lovely Purple Dress
22281 1 Blue Dinner Suit
22282 1 Purple Dinner Suit
22301 3 Ironweave Robe
22302 3 Ironweave Cowl
22303 3 Ironweave Pants
22304 3 Ironweave Gloves
22305 3 Ironweave Mantle
22306 3 Ironweave Belt
22311 3 Ironweave Boots
22313 3 Ironweave Bracers
22314 3 Huntsman's Harpoon
22315 3 Hammer of Revitalization
22317 3 Lefty's Brass Knuckle
22318 3 Malgen's Long Bow
22319 3 Tome of Divine Right
22321 3 Heart of Wyrmthalak
22322 3 The Jaw Breaker
22325 3 Belt of the Trickster
22326 3 Amalgam's Band
22327 3 Amulet of the Redeemed
22328 3 Legplates of Vigilance
22329 3 Scepter of Interminable Focus
22330 3 Shroud of Arcane Mastery
22331 3 Band of the Steadfast Hero
22332 3 Blade of Necromancy
22333 3 Hammer of Divine Might
22334 3 Band of Mending
22335 3 Lord Valthalak's Staff of Command
22336 3 Draconian Aegis of the Legion
22337 3 Shroud of Domination
22339 3 Rune Band of Wizardry
22340 3 Pendant of Celerity
22342 3 Leggings of Torment
22343 3 Handguards of Savagery
22345 3 Totem of Rebirth
22347 3 Fahrad's Reloading Repeater
22348 3 Doomulus Prime
22377 3 The Thunderwood Poker
22378 3 Ravenholdt Slicer
22379 3 Shivsprocket's Shiv
22380 3 Simone's Cultivating Hammer
22383 4 Sageblade
22384 4 Persuader
22385 4 Titanic Leggings
22394 3 Staff of Metanoia
22395 3 Totem of Rage
22396 4 Totem of Life
22397 3 Idol of Ferocity
22398 3 Idol of Rejuvenation
22399 4 Idol of Health
22400 3 Libram of Truth
22401 3 Libram of Hope
22402 4 Libram of Grace
22403 3 Nacreous Shell Necklace
22404 3 Willey's Back Scratcher
22405 3 Mantle of the Scarlet Crusade
22406 3 Redemption
22407 3 Helm of the New Moon
22408 3 Ritssyn's Wand of Bad Mojo
22409 3 Tunic of the Crescent Moon
22410 3 Gauntlets of Deftness
22411 3 Helm of the Executioner
22412 3 Thuzadin Mantle
22416 4 Dreadnaught Breastplate
22417 4 Dreadnaught Legplates
22418 4 Dreadnaught Helmet
22419 4 Dreadnaught Pauldrons
22420 4 Dreadnaught Sabatons
22421 4 Dreadnaught Gauntlets
22422 4 Dreadnaught Waistguard
22423 4 Dreadnaught Bracers
22424 4 Redemption Wristguards
22425 4 Redemption Tunic
22426 4 Redemption Handguards
22427 4 Redemption Legguards
22428 4 Redemption Headpiece
22429 4 Redemption Spaulders
22430 4 Redemption Boots
22431 4 Redemption Girdle
22433 3 Don Mauricio's Band of Domination
22436 4 Cryptstalker Tunic
22437 4 Cryptstalker Legguards
22438 4 Cryptstalker Headpiece
22439 4 Cryptstalker Spaulders
22440 4 Cryptstalker Boots
22441 4 Cryptstalker Handguards
22442 4 Cryptstalker Girdle
22443 4 Cryptstalker Wristguards
22458 3 Moonshadow Stave
22464 4 Earthshatter Tunic
22465 4 Earthshatter Legguards
22466 4 Earthshatter Headpiece
22467 4 Earthshatter Spaulders
22468 4 Earthshatter Boots
22469 4 Earthshatter Handguards
22470 4 Earthshatter Girdle
22471 4 Earthshatter Wristguards
22472 3 Boots of Ferocity
22476 4 Bonescythe Breastplate
22477 4 Bonescythe Legplates
22478 4 Bonescythe Helmet
22479 4 Bonescythe Pauldrons
22480 4 Bonescythe Sabatons
22481 4 Bonescythe Gauntlets
22482 4 Bonescythe Waistguard
22483 4 Bonescythe Bracers
22488 4 Dreamwalker Tunic
22489 4 Dreamwalker Legguards
22490 4 Dreamwalker Headpiece
22491 4 Dreamwalker Spaulders
22492 4 Dreamwalker Boots
22493 4 Dreamwalker Handguards
22494 4 Dreamwalker Girdle
22495 4 Dreamwalker Wristguards
22496 4 Frostfire Robe
22497 4 Frostfire Leggings
22498 4 Frostfire Circlet
22499 4 Frostfire Shoulderpads
22500 4 Frostfire Sandals
22501 4 Frostfire Gloves
22502 4 Frostfire Belt
22503 4 Frostfire Bindings
22504 4 Plagueheart Robe
22505 4 Plagueheart Leggings
22506 4 Plagueheart Circlet
22507 4 Plagueheart Shoulderpads
22508 4 Plagueheart Sandals
22509 4 Plagueheart Gloves
22510 4 Plagueheart Belt
22511 4 Plagueheart Bindings
22512 4 Robe of Faith
22513 4 Leggings of Faith
22514 4 Circlet of Faith
22515 4 Shoulderpads of Faith
22516 4 Sandals of Faith
22517 4 Gloves of Faith
22518 4 Belt of Faith
22519 4 Bindings of Faith
22589 5 Atiesh, Greatstaff of the Guardian
22630 5 Atiesh, Greatstaff of the Guardian
22631 5 Atiesh, Greatstaff of the Guardian
22632 5 Atiesh, Greatstaff of the Guardian
22651 4 Outrider's Plate Legguards
22652 4 Glacial Vest
22654 4 Glacial Gloves
22655 4 Glacial Wrists
22656 4 The Purifier
22657 4 Amulet of the Dawn
22658 4 Glacial Cloak
22659 4 Medallion of the Dawn
22660 3 Gaea's Embrace
22661 4 Polar Tunic
22662 4 Polar Gloves
22663 4 Polar Bracers
22664 4 Icy Scale Breastplate
22665 4 Icy Scale Bracers
22666 4 Icy Scale Gauntlets
22667 4 Bracers of Hope
22668 4 Bracers of Subterfuge
22669 4 Icebane Breastplate
22670 4 Icebane Gauntlets
22671 4 Icebane Bracers
22672 4 Sentinel's Plate Legguards
22673 4 Outrider's Chain Leggings
22676 4 Outrider's Mail Leggings
22678 4 Talisman of Ascendance
22680 3 Band of Resolution
22681 3 Band of Piety
22688 3 Verimonde's Last Resort
22689 3 Sanctified Leather Helm
22690 3 Leggings of the Plague Hunter
22691 4 Corrupted Ashbringer
22699 4 Icebane Leggings
22700 4 Glacial Leggings
22701 4 Polar Leggings
22702 4 Icy Scale Leggings
22707 4 Ramaladni's Icy Grasp
22711 3 Cloak of the Hakkari Worshipers
22712 3 Might of the Tribe
22713 3 Zulian Scepter of Rites
22714 3 Sacrificial Gauntlets
22715 3 Gloves of the Tormented
22716 3 Belt of Untapped Power
22718 3 Blooddrenched Mask
22720 3 Zulian Headdress
22721 4 Band of Servitude
22722 4 Seal of the Gurubashi Berserker
22725 3 Band of Cenarius
22730 4 Eyestalk Waist Cord
22731 4 Cloak of the Devoured
22732 4 Mark of C'Thun
22736 5 Andonisus, Reaper of Souls
22740 4 Outrider's Leather Pants
22741 4 Outrider's Lizardhide Pants
22742 1 Bloodsail Shirt
22743 1 Bloodsail Sash
22744 1 Bloodsail Boots
22745 1 Bloodsail Pants
22747 4 Outrider's Silk Leggings
22748 4 Sentinel's Chain Leggings
22749 4 Sentinel's Leather Pants
22750 4 Sentinel's Lizardhide Pants
22752 4 Sentinel's Silk Leggings
22753 4 Sentinel's Lamellar Legguards
22756 3 Sylvan Vest
22757 3 Sylvan Crown
22758 3 Sylvan Shoulders
22759 3 Bramblewood Helm
22760 3 Bramblewood Boots
22761 3 Bramblewood Belt
22762 3 Ironvine Breastplate
22763 3 Ironvine Gloves
22764 3 Ironvine Belt
22798 4 Might of Menethil
22799 4 Soulseeker
22800 4 Brimstone Staff
22801 4 Spire of Twilight
22802 4 Kingsfall
22803 4 Midnight Haze
22804 4 Maexxna's Fang
22806 4 Widow's Remorse
22807 4 Wraith Blade
22808 4 The Castigator
22809 4 Maul of the Redeemed Crusader
22810 4 Toxin Injector
22811 4 Soulstring
22812 4 Nerubian Slavemaker
22813 4 Claymore of Unholy Might
22815 4 Severance
22816 4 Hatchet of Sundered Bone
22818 4 The Plague Bearer
22819 4 Shield of Condemnation
22820 4 Wand of Fates
22821 4 Doomfinger
22843 3 Blood Guard's Chain Greaves
22852 3 Blood Guard's Dragonhide Treads
22855 3 Blood Guard's Dreadweave Walkers
22856 3 Blood Guard's Leather Walkers
22857 3 Blood Guard's Mail Greaves
22858 3 Blood Guard's Plate Greaves
22859 3 Blood Guard's Satin Walkers
22860 3 Blood Guard's Silk Walkers
22862 3 Blood Guard's Chain Vices
22863 3 Blood Guard's Dragonhide Grips
22864 3 Blood Guard's Leather Grips
22865 3 Blood Guard's Dreadweave Handwraps
22867 3 Blood Guard's Mail Vices
22868 3 Blood Guard's Plate Gauntlets
22869 3 Blood Guard's Satin Handwraps
22870 3 Blood Guard's Silk Handwraps
22872 3 Legionnaire's Plate Hauberk
22873 3 Legionnaire's Plate Leggings
22874 3 Legionnaire's Chain Hauberk
22875 3 Legionnaire's Chain Legguards
22876 3 Legionnaire's Mail Hauberk
22877 3 Legionnaire's Dragonhide Chestpiece
22878 3 Legionnaire's Dragonhide Leggings
22879 3 Legionnaire's Leather Chestpiece
22880 3 Legionnaire's Leather Legguards
22881 3 Legionnaire's Dreadweave Legguards
22882 3 Legionnaire's Satin Legguards
22883 3 Legionnaire's Silk Legguards
22884 3 Legionnaire's Dreadweave Tunic
22885 3 Legionnaire's Satin Tunic
22886 3 Legionnaire's Silk Tunic
22887 3 Legionnaire's Mail Legguards
22935 4 Touch of Frost
22936 4 Wristguards of Vengeance
22937 4 Gem of Nerubis
22938 4 Cryptfiend Silk Cloak
22939 4 Band of Unanswered Prayers
22940 4 Icebane Pauldrons
22941 4 Polar Shoulder Pads
22942 4 The Widow's Embrace
22943 4 Malice Stone Pendant
22947 4 Pendant of Forgotten Names
22954 4 Kiss of the Spider
22960 4 Cloak of Suturing
22961 4 Band of Reanimation
22967 4 Icy Scale Spaulders
22968 4 Glacial Mantle
22981 4 Gluth's Missing Collar
22983 4 Rime Covered Mantle
22988 4 The End of Dreams
22994 4 Digested Hand of Power
22999 1 Tabard of the Argent Dawn
23000 4 Plated Abomination Ribcage
23001 4 Eye of Diminution
23004 4 Idol of Longevity
23005 4 Totem of Flowing Water
23006 4 Libram of Light
23009 4 Wand of the Whispering Dead
23014 4 Iblis, Blade of the Fallen Seraph
23017 4 Veil of Eclipse
23018 4 Signet of the Fallen Defender
23019 4 Icebane Helmet
23020 4 Polar Helmet
23021 4 The Soul Harvester's Bindings
23023 4 Sadist's Collar
23025 4 Seal of the Damned
23027 4 Warmth of Forgiveness
23028 4 Hailstone Band
23029 4 Noth's Frigid Heart
23030 4 Cloak of the Scourge
23031 4 Band of the Inevitable
23032 4 Glacial Headdress
23033 4 Icy Scale Coif
23035 4 Preceptor's Hat
23036 4 Necklace of Necropsy
23037 4 Ring of Spiritual Fervor
23038 4 Band of Unnatural Forces
23039 4 The Eye of Nerub
23040 4 Glyph of Deflection
23041 4 Slayer's Crest
23042 4 Loatheb's Reflection
23043 4 The Face of Death
23044 4 Harbinger of Doom
23045 4 Shroud of Dominion
23046 4 The Restrained Essence of Sapphiron
23047 4 Eye of the Dead
23048 4 Sapphiron's Right Eye
23049 4 Sapphiron's Left Eye
23050 4 Cloak of the Necropolis
23053 4 Stormrage's Talisman of Seething
23054 4 Gressil, Dawn of Ruin
23056 4 Hammer of the Twisting Nether
23057 4 Gem of Trapped Innocents
23058 4 Life Channeling Necklace
23059 4 Ring of the Dreadnaught
23060 4 Bonescythe Ring
23061 4 Ring of Faith
23062 4 Frostfire Ring
23063 4 Plagueheart Ring
23064 4 Ring of the Dreamwalker
23065 4 Ring of the Earthshatterer
23066 4 Ring of Redemption
23067 4 Ring of the Cryptstalker
23068 4 Legplates of Carnage
23069 4 Necro-Knight's Garb
23070 4 Leggings of Polarity
23071 4 Leggings of Apocalypse
23072 4 Fists of the Unrelenting
23073 4 Boots of Displacement
23075 4 Death's Bargain
23078 3 Gauntlets of Undead Slaying
23081 3 Handwraps of Undead Slaying
23082 3 Handguards of Undead Slaying
23084 3 Gloves of Undead Cleansing
23085 3 Robe of Undead Cleansing
23087 3 Breastplate of Undead Slaying
23088 3 Chestguard of Undead Slaying
23089 3 Tunic of Undead Slaying
23090 3 Bracers of Undead Slaying
23091 3 Bracers of Undead Cleansing
23092 3 Wristguards of Undead Slaying
23093 3 Wristwraps of Undead Slaying
23124 3 Staff of Balzaphon
23125 3 Chains of the Lich
23126 3 Waistband of Balzaphon
23127 3 Cloak of Revanchion
23128 3 The Shadow's Grasp
23129 3 Bracers of Mending
23132 3 Lord Blackwood's Blade
23139 3 Lord Blackwood's Buckler
23156 3 Blackwood's Thigh
23168 3 Scorn's Focal Dagger
23169 3 Scorn's Icy Choker
23170 3 The Frozen Clutch
23171 3 The Axe of Severing
23173 3 Abomination Skin Leggings
23177 3 Lady Falther'ess' Finger
23178 3 Mantle of Lady Falther'ess
23192 1 Tabard of the Scarlet Crusade
23197 3 Idol of the Moon
23198 3 Idol of Brutality
23199 3 Totem of the Storm
23200 3 Totem of Sustaining
23201 3 Libram of Divinity
23203 3 Libram of Fervor
23206 4 Mark of the Champion
23207 4 Mark of the Champion
23219 4 Girdle of the Mentor
23220 4 Crystal Webbed Robe
23221 4 Misplaced Servo Arm
23226 4 Ghoul Skin Tunic
23237 4 Ring of the Eternal Flame
23238 4 Stygian Buckler
23242 4 Claw of the Frost Wyrm
23243 3 Champion's Plate Shoulders
23244 3 Champion's Plate Helm
23251 3 Champion's Chain Helm
23252 3 Champion's Chain Shoulders
23253 3 Champion's Dragonhide Headguard
23254 3 Champion's Dragonhide Shoulders
23255 3 Champion's Dreadweave Cowl
23256 3 Champion's Dreadweave Spaulders
23257 3 Champion's Leather Helm
23258 3 Champion's Leather Shoulders
23259 3 Champion's Mail Headguard
23260 3 Champion's Mail Pauldrons
23261 3 Champion's Satin Hood
23262 3 Champion's Satin Mantle
23263 3 Champion's Silk Cowl
23264 3 Champion's Silk Mantle
23272 3 Knight-Captain's Lamellar Breastplate
23273 3 Knight-Captain's Lamellar Leggings
23274 3 Knight-Lieutenant's Lamellar Gauntlets
23275 3 Knight-Lieutenant's Lamellar Sabatons
23276 3 Lieutenant Commander's Lamellar Headguard
23277 3 Lieutenant Commander's Lamellar Shoulders
23278 3 Knight-Lieutenant's Chain Greaves
23279 3 Knight-Lieutenant's Chain Vices
23280 3 Knight-Lieutenant's Dragonhide Grips
23281 3 Knight-Lieutenant's Dragonhide Treads
23282 3 Knight-Lieutenant's Dreadweave Handwraps
23283 3 Knight-Lieutenant's Dreadweave Walkers
23284 3 Knight-Lieutenant's Leather Grips
23285 3 Knight-Lieutenant's Leather Walkers
23286 3 Knight-Lieutenant's Plate Gauntlets
23287 3 Knight-Lieutenant's Plate Greaves
23288 3 Knight-Lieutenant's Satin Handwraps
23289 3 Knight-Lieutenant's Satin Walkers
23290 3 Knight-Lieutenant's Silk Handwraps
23291 3 Knight-Lieutenant's Silk Walkers
23292 3 Knight-Captain's Chain Hauberk
23293 3 Knight-Captain's Chain Legguards
23294 3 Knight-Captain's Dragonhide Chestpiece
23295 3 Knight-Captain's Dragonhide Leggings
23296 3 Knight-Captain's Dreadweave Legguards
23297 3 Knight-Captain's Dreadweave Tunic
23298 3 Knight-Captain's Leather Chestpiece
23299 3 Knight-Captain's Leather Legguards
23300 3 Knight-Captain's Plate Hauberk
23301 3 Knight-Captain's Plate Leggings
23302 3 Knight-Captain's Satin Legguards
23303 3 Knight-Captain's Satin Tunic
23304 3 Knight-Captain's Silk Legguards
23305 3 Knight-Captain's Silk Tunic
23306 3 Lieutenant Commander's Chain Helm
23307 3 Lieutenant Commander's Chain Shoulders
23308 3 Lieutenant Commander's Dragonhide Headguard
23309 3 Lieutenant Commander's Dragonhide Shoulders
23310 3 Lieutenant Commander's Dreadweave Cowl
23311 3 Lieutenant Commander's Dreadweave Spaulders
23312 3 Lieutenant Commander's Leather Helm
23313 3 Lieutenant Commander's Leather Shoulders
23314 3 Lieutenant Commander's Plate Helm
23315 3 Lieutenant Commander's Plate Shoulders
23316 3 Lieutenant Commander's Satin Hood
23317 3 Lieutenant Commander's Satin Mantle
23318 3 Lieutenant Commander's Silk Cowl
23319 3 Lieutenant Commander's Silk Mantle
23323 1 Crown of the Fire Festival
23324 1 Mantle of the Fire Festival
23451 4 Grand Marshal's Mageblade
23452 4 Grand Marshal's Tome of Power
23453 4 Grand Marshal's Tome of Restoration
23454 4 Grand Marshal's Warhammer
23455 4 Grand Marshal's Demolisher
23456 4 Grand Marshal's Swiftblade
23464 4 High Warlord's Battle Mace
23465 4 High Warlord's Destroyer
23466 4 High Warlord's Spellblade
23467 4 High Warlord's Quickblade
23468 4 High Warlord's Tome of Destruction
23469 4 High Warlord's Tome of Mending
23557 4 Larvae of the Great Worm
23558 4 The Burrower's Shell
23570 4 Jom Gabbar
23577 4 The Hungering Cold
23663 4 Girdle of Elemental Fury
23664 4 Pauldrons of Elemental Fury
23665 4 Leggings of Elemental Fury
23666 4 Belt of the Grand Crusader
23667 4 Spaulders of the Grand Crusader
23668 4 Leggings of the Grand Crusader
23705 4 Tabard of Flame
23709 1 Tabard of Frost
23710 1 Upperdeck Tabard #3
23714 1 Perpetual Purple Firework
23716 1 Carved Ogre Idol
24071 3 Bland Dagger
24222 3 The Shadowfoot Stabber
]==]
