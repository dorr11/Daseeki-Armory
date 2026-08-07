# Changelog

## Unreleased

### Internal

*Nothing in this section changes anything you can see in the game. It changes what
the tests are allowed to believe.*

- **The gear-swap test world now behaves like the real client, and the gear-swap
  engine fails against it.** Armory's headless test harness had a make-believe
  inventory in which every item move happened instantly, inside the line of code
  that asked for it, and no slot was ever locked. The real client does not work
  like that: it releases a slot's *lock* first and rewrites the slot's *contents*
  a moment later, and anything that reads the world in between reads the world as
  it was *before* the move. That gap is where a whole family of bugs lives — the
  same one that produced Daseeki Bags' "Internal Bag Error" gear ping-pong.

  The test world now models the gap: moves lock the slots they touch, locks
  release on their own tick, contents publish on a later one, an operation aimed
  at a locked slot is refused and counted, and re-asking the server to apply a
  move it has already applied raises the client's real error. With that in place,
  six known defects in the equip engine became visible for the first time and are
  now recorded, by name, as deliberately-failing tests: a three-way ring exchange
  finishes with the wrong ring and still marks the set as worn; a two-hander swap
  leaves your off hand stranded on the cursor; two swaps queued during combat
  drain as one; and an equip can hang forever on a lock it did not set.

  Those tests are quarantined, not silenced — the suite prints them loudly on
  every run, names the defect each one proves, and still passes so the rest of
  the gate keeps working. Repairing the engine is the next piece of work; this
  one exists so that repair can be proved rather than hoped for.

- **That repair has landed, and the quarantine is gone with it.** All six defects
  above now pass, so the debt ledger and the machinery that tolerated it have been
  deleted: every check in the suite gates again, and a settle bug can only ever
  come back as a red run. Five new gate suites hold the line — the same
  convergence scenarios run at four different client timings (including the one
  where the old, wrong rule would also have passed, so the fix cannot be an
  accident of tuning); a mutation gate puts the old "unlocked means finished" rule
  back and requires the suite to go red; and the combat queue is walked round by
  round to prove a refused action is still queued afterwards rather than gone.
  The whole body is 1,703 checks.

### Fixed

- **Gear sets now equip correctly, completely, and once.** Swapping a set could
  put the wrong item in a slot, leave an item stuck on your cursor, silently drop
  half of what you queued during a fight, or leave the addon convinced a swap was
  still running until you reloaded — and it would mark the set as the one you were
  wearing either way.

  All of it was one mistake, made in several places. Moving an item is a
  conversation with the server, not an instruction: the client greys the slot out,
  asks, and only writes the new contents in when the answer comes back. The engine
  did not wait for the answer. It planned the whole swap, fired every move in a
  single instant, and decided what to do next by re-reading slots that were still
  showing what they held *before* the swap started. So the second move was planned
  against a world the first move had already changed — which is how a three-way
  ring exchange ended up undoing itself — and when the engine looked again to see
  whether it was finished, it read "nothing is locked" as "everything has landed"
  and re-sent moves the server had already carried out. The client's answer to
  that is the same "Internal Bag Error" that plagued Daseeki Bags, and the visible
  result was gear ping-ponging and items left dangling on the cursor with nothing
  in the addon able to put them back.

  The engine now converges the way the swap actually happens. It does one round
  at a time: it works out what still needs to change, sends only the moves that
  touch entirely separate slots, and then *waits until those slots are showing the
  items it asked for* — not until they stop being greyed out, which is the earlier
  and misleading signal. Then it looks at the character afresh and works out the
  next round from what is really there. Nothing is ever re-sent because the addon
  read the world too early.

  Everything that could hang now has a floor under it. If another addon, or the
  server, is sitting on a slot the set needs, the swap waits for it, and gives up
  and tells you if it never frees — rather than leaving the "swap in progress"
  state set until your next reload. Every path that gives up puts anything left on
  your cursor back where it came from first, including the ones that used to have
  no recovery at all. Your own cursor is not touched if the swap refused before it
  moved anything.

  Swaps queued during combat drain the same careful way. They used to be emptied
  out of the queue before they were attempted, so the second one — refused because
  the first was still in flight — was simply gone; queue two trinkets in a fight
  and one of them arrived. Now an action leaves the queue only once it has actually
  been sent, anything refused is retried on the next round, and actions that depend
  on each other are ordered so they cannot steal each other's item. A whole set
  queued behind them waits for them to land before it plans, so it plans against
  the character you will actually have.

  And a set is only marked as the one you are wearing when a fresh look at your
  character confirms it — never merely because a swap was attempted.

- **Dragging a set to reorder it will keep dropping where you point, whatever the
  settings window is scaled to.** Nothing changes for you today: at the scale every
  install runs at right now, the drop bar already sits under the pointer, and it still
  will. This is a repair to the arithmetic behind it, made before it could ever be
  seen.

  The window measured your cursor against the set list using the *screen's* scale
  rather than the *list's*. Those are the same number today, so the sum came out
  right — but they stop being the same number the moment anything in the chain above
  the list is scaled, and then the error is not a fixed few pixels: it grows the
  further up the list you drag, so the bar drifts away from the mouse and sets land
  several rows from where the bar said they would. Daseeki Raid Prep shipped this
  exact shape and a player hit it the week a list-scale slider arrived (Raid Prep
  1.3.1, with a screenshot). Armory had the same latent sum in its set list; it now
  measures the cursor against the list at the list's own scale, so the answer is right
  at any scale, including the one you are using.

## 1.3.1 — 2026-08-05

### Changed

- **The Goal picker now ships its entire item database. There is no scan, ever.**
  Every equippable item in Classic Era — all 9,240 of them, by name and rarity — is
  built into the addon. Open a slot on a brand-new account, seconds after your first
  login, and the whole list is already there.

  What this replaces: Armory used to build that list on your machine. A one-time walk
  of 32,000 item ids, started by a timer fifteen seconds after you logged in, announced
  in chat, taking about a minute, saved to your account, and repeatable through a
  **Rescan Items** button in the picker when something looked wrong. All of that is
  gone — the button, the timer, the progress readout, the "(unscanned)" warning on the
  count line, and the once-per-account wait.

  The reason is simply that it never needed to be a question. Classic Era is a frozen
  game: the set of equippable items in it is identical on every account, on every realm,
  on every login, and it has not changed in years. Asking every player to measure that
  constant for themselves — and then storing their private copy of the answer — was the
  last piece of the old design still doing work that a shipped file does better. It is
  the same reasoning that moved the class and faction locks into the addon earlier in
  this release, applied to the list those locks are read against.

  **Nothing is asked of you and nothing is lost.** Your existing item cache is left
  alone on disk, untouched and unread; the picker no longer consults it. There is no
  migration, no rebuild and no first-login message. Items your client does not have are
  quietly skipped, so a future game patch can only ever make the list shorter, never
  wrong.

  It is also **lighter**. The old bundled name list cost about 970 KB of memory at
  login for roughly 5,300 names; the new catalog carries nearly twice as many items for
  about 240 KB, because it is stored as text and read once rather than kept as a table
  forever. The download grows by about 32 KB.

  `/darmory scanstatus` has become **`/darmory data`**, and it is now three counts:
  how many items, how many class and faction locks, and how many retired items this
  build carries. The old name still works. Every question it used to answer — is a scan
  running, how far along, when did it last finish, is anything still owed — no longer
  has anything to refer to.

### Fixed

- **The legendaries are back in the Goal picker.**
  *Thunderfury* had gone missing from the list. Nothing had hidden it — it carries no
  class lock, it is not on the retired-items list, no placeholder filter touches its
  name, and the picker's own rules answer "usable" for it on a warrior. It was being
  **sorted off the end of the list**.

  The list is ordered by item level, and item level is not something your client knows
  on its own: it has to come from the server, and it has not arrived yet for anything
  when you first open the picker. Every row therefore ranked as level 0, the order fell
  back to plain alphabetical, and only the first 500 names survived — which is roughly
  the letters A to C. That is why some legendaries were fine and others were not:
  *Atiesh* and the *Corrupted Ashbringer* sort early enough to make the cut, while
  *Sulfuras* and *Thunderfury* sit at 87% and 90% of the way down the alphabet and never
  did. The list now falls back to **rarity** while item levels are still unknown, so
  legendaries lead every slot and no cap can reach them; once the levels arrive, item
  level leads the order again exactly as before.

  This is pinned by a sweep over every legendary and artifact-quality item in a real
  client — *Thunderfury*, *Sulfuras*, the *Corrupted Ashbringer*, all four *Atiesh* and
  the rest — which now asserts, per item, that it is offered to exactly the classes that
  can wield it and that it survives into the visible list.

- **Class and faction locks are now built into Armory, and the machinery that tried to
  work them out on your machine is gone.** *Classes: Rogue* on Bonescythe is a fact about
  a game that stopped changing years ago — but Armory was working it out fresh on every
  account, by asking the game for each item's tooltip while it scanned. That question is
  answered differently depending on whether your client happens to be holding the item at
  that moment, so the answer was never dependable, and four rounds of increasingly
  elaborate scaffolding were built to make it so: retries, then a check on whether the
  item had really loaded, then a background repair pass, then stamps and per-session
  locks governing when that pass was allowed to run. They got in each other's way. All
  eight Tier 3 sets were *still* unlocked in a real cache, so rogue-only Bonescythe sat
  in a warrior's list, four copies of Atiesh sat there with it, and opening the picker to
  fix it could answer with nothing at all while `/darmory scanstatus` insisted a repair
  was owed.

  Armory now **ships** the locks — 910 items' worth, built from a completed scan of a
  real Era client, the bundled item table, and the Naxxramas sets and Atiesh variants by
  name. The picker looks the item up and that is the whole mechanism. Nothing is read
  from a tooltip, nothing is retried, nothing is repaired, nothing is owed, and every
  account on every character sees exactly the same answer the moment the picker opens.

  **There is nothing to do and nothing to wait for.** No repair pass, no minute of
  background traffic, no chat message. The next time you open the Goal picker, Tier 3
  and Atiesh are simply not in your warrior's list. `/darmory data` is shorter for the
  same reason: with no capture there is nothing to report about one, and it now just
  says how many locks this build carries.

  If an item ever turns out to be missing a lock, that is now a gap in a list that ships
  with the addon — the same gap for everyone, fixed in the next update — rather than
  something that went wrong on your account and has to heal itself there.

- **Items that can no longer be obtained by anyone are out of the picker.** Twelve of
  them. Five by history: the two Warglaives of Azzinoth, *The Twin Blades of Azzinoth*,
  the original *Ashbringer*, and *Andonisus, Reaper of Souls*. Seven more are the game
  masters' own toolkit, named after Blizzard staff and carried by the client at artifact
  rarity — the *Stone of Pierce*, *Lapidis*, *Goodman*, *Kurtz*, *Backus* and *Brownell*,
  and *Alex's Ring of Audacity*. None of them was ever placed in a loot table on any
  realm, in any event.

  They are real records in your client, which is why an earlier release deliberately left
  them in — but no character can end up owning one, so they are not goals. They are
  hidden the same way Blizzard's own placeholders are: **Show unusable** does not bring
  them back, because there is no character anywhere for whom they are merely unusable.
  This is a plain list inside the addon, so it can be changed or emptied in one line.

  With those seven added, **no artifact-quality item is offered at all**, which is
  correct: Classic Era does not contain one you can obtain. Hiding them by *name* would
  not have been safe — *Relic Stone of Piety* and *Stone of the Earth* are ordinary gear
  a player can wear — so each is listed by item id, and each id was checked against the
  client's own name for it before being written down.

  **Three items have come back off that list.** *Gressil, Dawn of Ruin*, *Iblis, Blade of
  the Fallen Seraph* and *Neretzek, The Blood Drinker* were listed on original-vanilla
  history — and that was the wrong yardstick. On Classic Era **Anniversary** realms the
  Scourge Invasion runs again and all three are genuine drops, so they are goals you can
  actually finish. They are back in the picker, offered to any class that can wield them
  and findable by name. *The Untamed Blade* was never on the list and is unaffected. The
  rule going forward is that "nobody can get one" is judged against Era **as it is played
  now**, event re-runs included, not against a 2006 loot table.

  *Andonisus* stays hidden for a different reason: it drops on Anniversary too, but it
  decays and destroys itself, so it is not something you can still own once you have it.

  **The *Corrupted* Ashbringer is not on that list and never will be.** It drops in
  Naxxramas on a live Era realm, so it is a goal you can actually finish — it stays in
  the picker, it still answers a search for "ashbringer", and only its unobtainable
  namesake is gone.

- **The Goal picker no longer offers items from other expansions.** Armory used to carry
  a bundled name list, taken from a source that reaches well past this game, and merge it
  into the picker. So Wrath and Cataclysm gear that no Era character can ever hold sat in
  the list: *Wrathful Gladiator's Tabard*, *Tabard of the Argent Crusade*, *Gilneas
  Tabard*, the Exodar and Silvermoon City tabards, *Hallowed Helm*, *Swift Brewfest Ram*,
  and a long tail of AtlasLoot's own section headings ("Warrior", "Rogue", "Mage") parked
  on ids that mean nothing here. Measured against a real client, that is **1,889 entries
  it has never heard of**, 95 of them past the end of the item range entirely.

  That list is not shipped any more at all — the built-in catalog replaced it, and the
  catalog is a census of what an Era client actually contains, so it cannot hold that
  kind of entry in the first place. Nothing real is lost: *Kingsfall*, *Might of
  Menethil*, Atiesh and the rest of Naxxramas are all in it.

  One thing this cannot reach: items that genuinely exist in the client but can no longer
  be obtained by anyone. They are removed by the retired-items list above instead.

- **Scrolling the Goal picker no longer jumps back to the top.** Any background refresh —
  item levels arriving from the server — rebuilt the list and sent you back to row one.
  Those refreshes arrive continuously while item data is streaming in,
  which made the list effectively unscrollable. Your position is now kept
  across every refresh you did not ask for, and adjusts if the list gets shorter under
  you. Typing in the search box, toggling **Show unusable**, or opening the picker still
  starts at the top, as they should.

- **The Goal picker shows the whole list again, in rarity colours.** 1.3.0 shipped the
  rarity tint with a one-line fault that stopped the row list dead: the picker asked the
  suite for a colour, got back only the red channel, and handing that to the game as a
  colour raised an error partway through drawing the very first row. Everything after it
  — the other eleven rows, every tint, and the "N items" line under the list — never ran.
  What you saw was a single uncoloured line that changed as you scrolled, with the items
  really there but never drawn. The list now fills all twelve rows, every row is tinted
  by rarity (grey through orange), and the count line updates again.
- **The picker no longer shows an item under the wrong name.** Armory used to merge your
  client's own item data with a bundled name list, the client winning where they
  disagreed. Dropping an entry as a Blizzard placeholder released its id back to the
  bundled list, which does not agree with your client about what every id is — so a
  placeholder that had just been filtered out reappeared under a stale name. That is why
  `Enchant Cloak - Resistance` (the name of an *enchantment*, not of anything wearable)
  turned up in the picker. Thirty-seven ids were doing this. There is no second list to
  disagree with any more, so this cannot recur: the built-in catalog *is* the client's
  own item data, and a name filtered out of it was never written into it in the first
  place.

- **Enchantment names are filtered out of the picker.** The old bundled list carried 123
  entries like `Enchant Cloak - Resistance` and `Enchant 2H Weapon - Agility`; those name
  an effect, not an item, and none of them can be worn. The *recipes* are real and are
  untouched — `Formula: Enchant Cloak - Greater Resistance` still appears — and so is
  every genuine item whose name merely starts similarly, such as *Enchanted Thorium Helm*
  and *Enchanter's Cowl*. One more Blizzard placeholder that had slipped through
  (`Nax PH Crit Plate Shoulders`) is filtered too.

- **The Goal picker no longer offers you items that do not exist.** 1.3.0 taught Armory
  to read your client's own item list, which was a real improvement — but your client
  also stores Blizzard's working records alongside the game's actual items: art
  placeholders (`[PH] Brilliant Dawn Cap`), the gear worn by creatures
  (`Monster - Sword, Katana`), designer test pieces (`Test Glaive A`,
  `90 Epic Warrior Helm`) and retired duplicates (`Deprecated Dented Skullcap`). About
  one in eight of everything the client holds is of that kind, and none of it can be
  obtained by anyone. Armory recognises those records and keeps them out of the picker
  entirely.

  They are **not** revealed by **Show unusable**, deliberately: that tick box is for
  items *some other character* could equip, and these are not items at all. The name
  rules were derived by reading a full census of a live Era client — 10,504 equippable
  items — and were checked against every one of the 9,240 real items that survive, so
  nothing you can actually go and earn is hidden. Real gear whose name looks suspicious
  is safe: *Testament of Hope*, *Contest Winner's Tabard*, *Old Blunderbuss*,
  *Adept's Cloak*, *103 Pound Mightfish* and *Doomcaller's Footwraps* all still appear.

  **None of it is in the download.** Those 1,264 records are filtered out when the
  catalog is built, so they never reach your machine at all — you are not shipped 12% of
  a list only for your own client to spend every login deciding it is junk. If a future
  update improves the rules, the improvement arrives with that update.

### New

- **`/darmory data` tells you what this build carries, whenever you ask.** Three counts,
  identical on every account: how many items the catalog holds, how many class and
  faction locks ship with it, and how many items it hides as no-longer-obtainable. If any
  of them reads zero, that file failed to load, which is the one item-database fault this
  design can still have — and now it is visible at a glance instead of showing up as a
  short picker. `/darmory scanstatus` still works as a name for it.

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
