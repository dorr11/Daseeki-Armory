# Changelog

## Unreleased
Correctness fixes — the stats panel now matches in-game values.

- **The gear-swap engine has been rebuilt from the ground up.** Equipping sets
  behaves exactly as before — your saved sets, their slots, key bindings and
  macros are all untouched, and `/run ArmEquip("name")` still works the same way.
  The rewrite is internal: the engine now takes a single indexed snapshot of your
  bags and worn gear, plans the whole swap up front, and re-checks each step as it
  runs. Two small swap bugs fell out of that work — a ring/trinket exchange could
  briefly leave the displaced item on the cursor, and a paired swap could undo
  itself when one move already satisfied the other slot. Both are fixed.
- Equipping into an occupied slot now reliably puts the item that came off back
  into the bag slot the new item came from, instead of leaving it on the cursor.

- **Melee and Ranged Damage** no longer read high. The game already bakes your
  physical damage bonus and percent modifier into the numbers it reports; Armory
  was applying both a second time, so the range was inflated (a true 100-150 with
  +5 damage and a x1.1 modifier displayed as 116-171). Both rows now show the same
  range as Blizzard's own character sheet.
- **Mana regen** is rebuilt from scratch. The two rows previously printed the same
  number, because the client reports the same value for both. There are now two
  correct and distinct rows — **MP5 Casting** and **MP5 Not Casting** — that
  include MP5 from your gear and enchants (with the client's one-point-per-item
  under-report corrected), Blessing of Wisdom / Greater Blessing of Wisdom / Mana
  Spring Totem / Mageblood / Nightfin Soup, Paladin *Improved Blessing of Wisdom*
  scaling, the *Meditation* / *Arcane Meditation* / *Reflection* casting fractions,
  Mage Armor, and the Druid/Priest 3-piece tier bonus. Also stops flashing 0
  after a gear swap.
- **Spell Crit** now includes talent crit the client does not report: Mage
  *Arcane Instability* and *Critical Mass*, Priest *Holy Specialization* and
  *Force of Will* (plus Benediction), Warlock *Devastation*, Shaman *Call of
  Thunder* and *Tidal Mastery*. Previously understated by up to 9-12% for those
  classes.
- **Ranged block** gained the missing **Hit** row (including the +3% from a ranged
  scope), and now shows an em-dash instead of meaningless numbers when you have no
  ranged weapon equipped. Ranged Attack Power also reads as not-applicable with a
  wand.
- **Defense** is read from your Defense skill line rather than the client call that
  does not report the full value; the old call remains as a fallback.
- **Block Value** now includes Strength/20, the Battlegear of Might 3-piece bonus
  and warrior Zul'Gurub head/leg enchants, on top of the block value on your gear.
  A new Stats option switches back to the client's raw figure if you prefer it.
- **Queued gear swaps survive death.** Dying drops you out of combat, which used to
  consume a pending trinket or set swap against your corpse and silently lose it.
  The queue is now held while you are dead and drains when you are back up
  (resurrect or release). Requests made while dead are queued instead of failing.
  Feigning hunters are treated as alive and swap immediately.
- **No more login error without Daseeki Core.** With the attached stats panel
  enabled and Core disabled, the panel now cleanly does nothing instead of throwing
  a Lua error, and `/darmory stats` toggles the setting without needing the options
  window.

## 1.2.0
- Settings rebuilt on the new Daseeki Core 2.0 interface (requires Daseeki Core 2.0.0+).
- Sets: side-by-side layout — set list and management on the left, Set Builder on the
  right with a centered paper-doll; buttons aligned on a consistent grid.
- Set Swapper options now live inside the Sets tab (compact single-row layouts).
- Character Window: flyout options arranged in two columns mirroring the in-game
  character pane, with labeled Direction / Per row columns and a Weapons group.
## 1.1.0
- Gear-goal picker now hides other-class set pieces while offline, using a bundled
  itemID to allowable-class bitmask table (no cached tooltip required).
- Expanded the item-name database with Tier 3 (Naxxramas), C'Thun/AQ, dungeon,
  PvP, Zul'Gurub, and Arathi Basin class-set items.
- Arathi Basin "Highlander's"/"Defiler's" reputation set pieces are correctly
  treated as unrestricted (armor-type gated only) so they show for every eligible class.
- Added per-slot flyout direction and per-row defaults.
- Added hover-to-open flyout with item tooltips.
- Made the flyout configuration list scrollable.

## 1.0.0
- Initial CurseForge release.
