# Changelog

## 1.3.1 — 2026-08-04

### Fixed

- **The Goal picker no longer offers you items that do not exist.** 1.3.0 taught Armory
  to read your client's own item list, which was a real improvement — but your client
  also stores Blizzard's working records alongside the game's actual items: art
  placeholders (`[PH] Brilliant Dawn Cap`), the gear worn by creatures
  (`Monster - Sword, Katana`), designer test pieces (`Test Glaive A`,
  `90 Epic Warrior Helm`) and retired duplicates (`Deprecated Dented Skullcap`). About
  one in eight of everything the scan found is of that kind, and none of it can be
  obtained by anyone. Armory now recognises those records and keeps them out of the
  picker entirely.

  They are **not** revealed by **Show unusable**, deliberately: that tick box is for
  items *some other character* could equip, and these are not items at all. The name
  rules were derived by reading a full scan of a live Era client — 10,504 equippable
  items — and were checked against every one of the 9,241 real items that survive, so
  nothing you can actually go and earn is hidden. Real gear whose name looks suspicious
  is safe: *Testament of Hope*, *Contest Winner's Tabard*, *Old Blunderbuss*,
  *Adept's Cloak*, *103 Pound Mightfish* and *Doomcaller's Footwraps* all still appear.

  **You do not need to rescan.** The next time you log in, Armory re-reads the names
  already in its cache and marks them; it takes a few hundredths of a second. If a
  future update improves the rules, that too applies at the next login rather than
  asking for another scan. The chat line at the end of a scan now also tells you how
  many internal records it set aside.

### Unchanged, and deliberately so

- **An empty search box still lists the whole slot.** That is not a bug and it has
  worked that way since 1.0.0 — the box filters a list you can browse, it is not a
  search term you are required to type. The reason an "empty" picker looked wrong in
  1.3.0 is simply that the rows at the top of that list were placeholders, which is what
  the fix above removes.

## 1.3.0 — 2026-08-03
The largest Armory release so far. Three new things you can *do* — search your whole
client for a gear goal, swap weapons in the middle of a fight, and read a trinket's
cooldown straight off its slot — plus a full character stat panel, the suite's quality
glow and font on every surface, and a rebuilt gear-swap engine underneath all of it.

### New

- **The Goal picker can now search every equippable item in the game.** It used to
  search one bundled list of item names. That list was a snapshot: it missed items
  outright (Corehound Belt among them), it carried no rarity information, and it knew
  almost nothing about which class or faction an item is locked to. Armory now builds
  its own list by walking your client's item space, keeping everything that fits a gear
  slot it manages, and recording each item's real name, rarity and class/faction locks.

  **What you will see the first time you log in after updating:** about fifteen seconds
  after you land, Armory says in chat that it is building the item database, and starts.
  It runs once **per account** — not per character — takes about a minute, and is
  deliberately throttled so it never competes with the game; you can keep playing right
  through it. A second chat line tells you when it has finished and how many items it
  found. There is a **Rescan Items** button at the bottom of the picker if you ever want
  to redo it, and while a scan is running the picker's counter shows its progress. The
  bundled list stays in place as a fallback until the first scan finishes, so nothing is
  ever *worse* than before, and shift-clicking an item link into the search box still
  picks that item directly.

- **The Goal picker hides items your character can never equip.** Atiesh used to show up
  when picking a goal for a warrior; Alliance PvP rank pieces showed up on Horde
  characters, and vice versa. Armory now reads each item's class lock ("Classes: Mage")
  and faction lock off the item itself during the scan and filters the list against
  whoever has the picker open — class lock, faction lock, and whether your class can wear
  that armour or wield that weapon at all. A **Show unusable** tick box in the picker's
  footer turns the filter off when you want to set a goal outside those rules; it is off
  by default and remembered per character. Requirements you can still go and *earn* —
  reputation, a profession, a level — are deliberately not filtered, because those are
  exactly what a goal is for.

- **Goal picker results are coloured by rarity and sorted properly.** Every result row is
  now tinted by the item's quality, using the same colour chain as the quality glow on
  your character window — with one deliberate difference: a grey item's name is drawn in
  a readable grey rather than the near-black used for the glow wash, which on a dark
  panel would be invisible. Items the game has not loaded yet start in the plain text
  colour and re-colour themselves the moment the data arrives. Results are also sorted by
  item level *before* the 500-row cap is applied, so "highest item level first" is now
  true on broad searches instead of being an arbitrary 500 matches sorted after the fact.

- **Weapons can now be swapped in the middle of a fight.** Give a set a key binding, and
  pressing that key during combat swaps its main hand, off hand and ranged weapon
  *immediately*; everything else in the set still waits for combat to end, as before.
  This works because the key binding runs the game's own secure equip command, which is
  the only thing allowed to change gear in combat — so it applies to a set's key binding
  only, not to clicking the set in the options window or on the radial widget. The
  binding's contents are kept up to date automatically whenever you edit the set.

- **A set can now require a slot to be EMPTY.** Previously a slot was either "the set puts
  this item here" or "the set ignores this slot" — there was no way to say "take off
  whatever is in here". In the set builder, **shift-click a slot** to mark it
  must-be-empty; the slot shows its plain silhouette with a small red X, and
  shift-clicking again removes the marker. Equipping the set moves whatever is worn there
  into a free bag slot, and tells you if there is no room. Useful for a fishing set, a
  shield-off two-hander swap, or dropping a tabard. Existing sets are completely
  unaffected — no set saved before this version can contain the marker, and re-saving a
  set over itself keeps any markers you set deliberately without inventing new ones for
  slots that merely happen to be bare.

- **Trinket cooldowns now read straight off the slot.** Both trinket slots — on the
  character pane *and* on their detached popout buttons — show the cooldown sweep plus a
  countdown that reads in seconds under a minute, minutes under an hour, and hours above
  that. A cooldown that starts under three seconds is not drawn at all (that is almost
  always the global cooldown, and it was just flicker), but a real countdown ticking down
  through 3, 2, 1 still shows. Two switches live under **Character Window** in the
  options: *Trinket cooldown readouts* (on) and *Large trinket cooldown numbers* (on —
  large gold numbers in the middle of the slot, or smaller white ones along the bottom
  edge). Armory draws these numbers itself and asks OmniCC-style addons to leave the
  trinket slots alone, so you never get two countdowns stacked on one icon.

- **A character stat panel.** A read-only breakdown of your character — Attributes,
  Melee, Ranged, Spell, Defense and Resistances — available as a **Stats** section in the
  Daseeki hub and, if you want it, as a compact panel attached to the side of the
  character window (*Attach a compact stats panel to the character window*, or
  `/darmory stats` if you would rather not open the options). It updates live as your
  gear, buffs and talents change. The numbers are computed to agree with the game rather
  than repeated from it:

  - **Melee and Ranged Damage** show the same range as Blizzard's own character sheet —
    the client already bakes in your physical damage bonus and percent modifier, so
    Armory does not apply them a second time.
  - **MP5 Casting** and **MP5 Not Casting** are two genuinely different numbers, and
    include gear and enchant MP5 (with the client's one-point-per-item under-report
    corrected), Blessing of Wisdom / Greater Blessing of Wisdom / Mana Spring Totem /
    Mageblood / Nightfin Soup, Paladin *Improved Blessing of Wisdom* scaling, the
    *Meditation* / *Arcane Meditation* / *Reflection* casting fractions, Mage Armor, and
    the Druid/Priest 3-piece tier bonus.
  - **Spell Crit** includes the talent crit the client does not report: Mage *Arcane
    Instability* and *Critical Mass*, Priest *Holy Specialization* and *Force of Will*
    (plus Benediction), Warlock *Devastation*, Shaman *Call of Thunder* and *Tidal
    Mastery* — worth up to 9-12% for those classes.
  - **Ranged** carries a **Hit** row including the +3% from a scope, and shows an em-dash
    rather than meaningless numbers when you have no ranged weapon; Ranged Attack Power
    reads as not-applicable with a wand.
  - **Defense** is read from your Defense skill line rather than the client call that
    under-reports it, and **Block Value** adds Strength/20, the Battlegear of Might
    3-piece bonus and the warrior Zul'Gurub head/leg enchants on top of the block value
    on your gear (a Stats option switches back to the client's raw figure if you prefer).

### Look and feel

- **Equipped gear now carries the same quality glow as Daseeki Bags.** Your equipped
  slots on the character pane, and the entries in the hover flyout, are washed with a
  soft quality-coloured halo — the identical treatment Bags draws over your bag icons:
  same width, same softness, same colours, centred, and scaled to whatever size the
  button is. On the character sheet *everything* you are wearing is glowed, including a
  plain white item and a grey, so a worn item and an empty slot never look the same;
  empty slots stay dark. The hover flyout glows Uncommon and above, which is the right
  rule for a list of items rather than a set of worn slots. The halo sits *underneath*
  everything else drawn on a slot, so trinket countdowns and the "will be equipped after
  combat" markers read cleanly over the top and a bright glow cannot bleed over the
  slot next to it. One switch turns it all off, under **Character Window**.

- **Every Armory surface now wears the suite's Field Ledger look and your Core font.**
  Hard-coded gold highlights, gold keylines, black backings and bluish list stripes are
  gone in favour of the suite's live theme tokens, so Armory matches the rest of your
  Daseeki addons and follows the theme you pick in Daseeki Core. Typography went with it:
  window titles are ceremonial, stat values and trinket countdowns are on the numeral
  face, and the body text that had been left behind — set names in the gear flyout, item
  names in the Goal picker, the icon and set counters, and the "No sets" / "No items" /
  "Esc to cancel" lines — now follows your picked font and changes with it live. Without
  Daseeki Core installed, everything looks exactly as it did before.

- **The Set Swapper's Type, Direction and Sets Per Row settings now sit side by side.**
  They were three stacked rows down the settings page; they are now one row of three
  columns — each with its caption above its dropdown — lined up with the Open On /
  Display Mode / Tooltips row directly above them. The settings themselves, and when each
  one appears, are unchanged.

### Fixed

- **Logging out during the first fifteen seconds no longer cancels the item scan for
  good.** Armory marked the one-time scan as "already attempted" the moment you logged
  in, fifteen seconds before it actually started — so if you reloaded, disconnected or
  logged out inside that window, the scan never ran and never offered to run again. It is
  now marked only when the scan really starts, so an interrupted login simply tries again
  next time.

- **A goal you have already achieved now shows its green tick.** The tick on a set slot
  only ever appeared if the goal item happened to be sitting loose in a bag at the moment
  the addon looked. Gear you looted and put straight on, gear you were already wearing
  when you set the goal, and gear picked up in a session where that check never ran all
  counted as "not obtained" — so the slot stayed blank even though the item was plainly
  yours. Armory now also counts the item being *worn in that slot*, and re-checks
  whenever your equipment changes, not just when your bags do. Separately, a set that had
  goals but no gear in it used to stop every other set from being checked at all.

- **The set builder's preview now shows the set you are looking at, not what you are
  wearing.** The preview was re-binding the model to your character on every refresh,
  which re-dressed it in your live gear a moment after the set had been put on it. It now
  dresses the set only. Weapons are handled properly too: they go on last, main hand
  before off hand, each told which hand it belongs in — previously both weapons were
  handed to the game with no hand specified, so they both landed in the main hand and
  only the last one survived, which is why a single off-hand weapon showed up in the main
  hand. Slots the set strips or ignores stay bare, and the ranged weapon is still left
  off the model so it cannot replace your melee weapons.

- **Two gear-swap bugs are fixed.** A ring or trinket exchange could briefly leave the
  displaced item stuck on your cursor instead of putting it back into the bag slot the
  new item came from; and a paired swap could undo itself when one move had already
  satisfied the other slot. Both came out of a ground-up rebuild of the swap engine,
  which now takes a single snapshot of your bags and worn gear, plans the whole swap up
  front, and re-checks each step as it runs. Everything you can see is unchanged — your
  saved sets, their slots, key bindings and macros are all untouched, and
  `/run ArmEquip("name")` still works exactly the same way.

- **Queued gear swaps survive death.** Dying drops you out of combat, which used to
  consume a pending trinket or set swap against your corpse and silently lose it. The
  queue is now held while you are dead and drains when you are back up, whether you
  resurrect or release, and a swap requested while dead is queued rather than failing.
  Feigning hunters are treated as alive and swap immediately.

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
