# NotWorthIt

A passive addon for World of Warcraft: Forever (1.60.1) that tells you when an
item is worth more to a vendor than on the auction house.

No settings UI, no slash commands. Install it and it works. To change how it
judges items, edit the tunables at the top of `NotWorthIt.lua` and reload.

## Table of Contents

- [What it does](#what-it-does)
- [How it decides](#how-it-decides)
- [Tunables](#tunables)
- [Integrations](#integrations)
- [Notes and limits](#notes-and-limits)
- [Roadmap](#roadmap)

## What it does

- Reads the current auction price for an item from Auctionator's price
  database, and the vendor sell price from the game's own item data.
- Compares them, accounting for the auction house sales cut and the listing
  deposit you would lose if the auction failed to sell.
- When the vendor wins, the item tooltip gains a red line:

```text
NotWorthIt - vendor pays more        vendor 1g23s > AH 97s
```

![NotWorthIt's red "NotWorthIt - vendor pays more" verdict line on a Sharp Claw tooltip, with the vendor-versus-auction net comparison on the right, alongside ATT item details and Dejunk's sections, with Baganator's sorted bag view behind and the offending stack circled in green](doc/not-worth-it.png)

*Not worth it: Sharp Claw vendors for more than its auction net after the
house cut and deposit, so the red line appears.*

- When the auction wins instead, the tooltip gains a green signature line -
  the addon's own name, with "Not" struck out in red and "WorthIt" in green,
  so the line reads as "worth it", plus how much more the auction nets than
  the vendor:

```text
~~Not~~WorthIt        47s more on AH
```

![NotWorthIt's green "~~Not~~WorthIt" signature line on a Stringy Wolf Meat tooltip, with the amount the auction nets above vendoring on the right, alongside ATT item details and Dejunk's sections, with Baganator's sorted bag view behind](doc/worth-it.png)

*Worth it: Stringy Wolf Meat nets more on the auction house than at the
vendor, so the green signature line appears - the addon's own name with its
"Not" struck out.*

- With Baganator installed, the same verdict feeds its junk plugin system, so
  flagged items show the junk coin and sort with the trash. Baganator runs
  only one junk detector at a time, so NotWorthIt also covers the standard
  cases itself: greys are always junk, useful items (level-appropriate
  consumables, equipment set pieces) are never junk, and Dejunk's own rules
  keep applying when Dejunk is installed.

Items it stays quiet about: anything soulbound, quest-bound, or otherwise
unsellable on the auction house, and anything with no vendor value. When an
auction price exists but is older than the freshness limit, the tooltip shows
`NotWorthIt: Auction data outdated` instead of a verdict or silence.

## How it decides

Per item unit:

```text
auction net = AH price * (1 - AH cut) - deposit
vendor bar  = vendor sell price * threshold

vendor wins when: auction net < vendor bar
```

The default threshold of 1.02 means the auction has to beat the vendor by at
least 2% before the item is considered worth listing.

**Undercut scam guard.** Bots briefly list a single unit at a crash price to
bait auto-matching tools, then buy it back - which makes the stored "current
minimum" nosedive for a few seconds. Auctionator's public API only exposes
that minimum, but its database also keeps day-bucketed price history
(highest minimum seen each day, plus the previous days' minimums), which
NotWorthIt reads in memory to build a typical-price baseline. When the
current price collapses below `NWC_SCAM_RATIO` of that baseline, the outlier
is ignored and the verdict uses the baseline instead. A genuine price crash
can resemble bait; the guard errs toward trusting the recent market, which
in that case only risks a missing warning, never a false one.

## Tunables

All tunables live at the top of `NotWorthIt.lua`.

| Constant | Default | Meaning |
| -------- | ------- | ------- |
| `NWC_THRESHOLD` | `1.02` | The auction must beat the vendor price by this factor (1.02 = 2%). |
| `NWC_FRESHNESS_DAYS` | `2` | Ignore Auctionator prices older than this many days (2 days = a 48 hour threshold). Auctionator stores prices in day buckets: 0 means seen today, 1 means today or yesterday. A price older than the limit is not a verdict: the tooltip shows an "Auction data outdated" note instead. |
| `NWC_INCLUDE_DEPOSIT` | `true` | Subtract the listing deposit from the auction value. If the auction fails to sell, the deposit is gone and you may have made more at the vendor. |
| `NWC_AUCTION_DURATION` | `8` | Deposit basis in hours: 2, 8 or 24 (Forever's auction durations). Deposits run roughly 5% / 20% / 60% of the vendor price. |
| `NWC_AUCTION_CUT` | `0.05` | The share the auction house keeps from a successful sale. |
| `NWC_SCAM_GUARD` | `true` | Ignore single bait listings: when the current price collapses far below the recent market, the verdict uses the typical price instead. |
| `NWC_SCAM_DAYS` | `7` | Days of price history used to build the typical-price baseline. |
| `NWC_SCAM_RATIO` | `0.5` | A current price below this fraction of the baseline counts as bait. |
| `NWC_JUNK_POOR_QUALITY` | `true` | Grey (poor quality) items with a vendor price are always junk: they cannot be auctioned, so the vendor is their only buyer. |
| `NWC_JUNK_IGNORE_CONSUMABLES` | `true` | Never label useful consumables (food, potions, bandages) as junk, even when the vendor pays more. |
| `NWC_JUNK_CONSUMABLE_LEVELS` | `15` | How far below your level a consumable's required level may be while still counting as useful for the guard above. Consumable tiers are spaced 10 levels apart, so 15 protects the current tier plus one back while levelling, and survives the level cap (a 10-level band would misclassify requirement-45 endgame consumables at 60). Older consumables are left to Dejunk's rules and the vendor-versus-auction verdict. Consumables with no required level always count as useful. |
| `NWC_JUNK_IGNORE_EQUIPMENT_SETS` | `true` | Never label items kept in one of your equipment sets as junk. Silently skipped if the game's equipment set API is unavailable. |
| `NWC_JUNK_USE_DEJUNK` | `true` | Pass Dejunk's own junk answer through when it is installed, so its quality toggles, user lists and other rules keep working while NotWorthIt is Baganator's detector. |
| `NWC_DEBUG` | `false` | Print one chat line per hovered item explaining its verdict (why it was flagged, or why it stayed silent). Flip to `true` while diagnosing. |

## Integrations

**Auctionator** - supplies the auction prices and price freshness. No
configuration needed; if it is missing or disabled, NotWorthIt stays silent
rather than guessing. Two levels of access are used:

- The official `Auctionator.API.v1` functions supply the current minimum
  price and how long ago it was seen (freshness). This is all the addon
  needs for verdicts when no history is available.
- The undercut scam guard additionally reads Auctionator's in-memory price
  database to build a typical-price baseline from its day-bucketed history
  (the highest minimum seen today, and the previous days' minimums). This
  is a read-only look at data Auctionator already keeps for its own
  tooltips: nothing is written, hooked, or modified.

The in-memory read is deliberately defensive. If Auctionator updates its
database format, or the database is not loaded, the scam guard quietly steps
aside and verdicts continue using the public API values alone - the same
graceful degradation every integration follows.

**Baganator** - registers a junk plugin named NotWorthIt. Flagged items get
the junk coin and sort into the junk group. Baganator only runs one junk
plugin at a time, so while NotWorthIt is the selected detector it also covers
the standard cases that would otherwise come from Dejunk or Baganator's own
poor quality option:

- Grey (poor quality) items with a vendor price are always junk - they cannot
  be auctioned, so the vendor is their only buyer.
- Useful items are never junk, even when the vendor pays more: consumables
  that are not far below your level, and items kept in one of your equipment
  sets.
- With Dejunk installed, Dejunk's own junk rules (quality toggles, user
  lists, item level and price filters) also apply, exactly as configured in
  Dejunk.

These guards shape only the bag label; the tooltip verdict keeps reporting
the plain vendor-versus-auction comparison. Without Auctionator the plugin is
not registered at all, so no dead option appears in the menu.

**Dejunk** - optional. While NotWorthIt is Baganator's selected junk
detector, its callback consults Dejunk's public `DejunkApi:IsJunk` so
Dejunk's rules keep working without switching detectors, and a listener asks
Baganator to refresh when Dejunk's settings change - the same pattern
Baganator itself uses for its native Dejunk integration. The call is
read-only and guarded: if Dejunk is missing, disabled, or its API changes,
NotWorthIt quietly falls back to its own rules and verdict.

**Deposits** - while the auction house window is open, the addon asks the
game for the exact deposit of items you look at and remembers it for the
session. Everywhere else it estimates from the vendor price using the classic
rates above. The estimate assumes a faction city auction house; neutral
houses charge more, and the exact path handles those automatically.

## Notes and limits

- Built for WoW Forever only (`## Interface: 16001`), on its modern-era addon
  API. Retail support is not yet implemented (see Roadmap).
- Price freshness follows Auctionator's day-bucket storage, so the freshness
  setting works in whole days, not minutes.
- Nothing is saved to disk; the deposit cache lives for the current session
  only.
- The green line's strikethrough is a hand-positioned texture, because
  Blizzard's text rendering has no native strikethrough. It hides whenever
  the tooltip is rebuilt and redraws on the next refresh.
- The addon never posts, cancels, or sells anything. It only reads data and
  writes tooltip text and Baganator's junk flags.

## Roadmap

- Retail (12.x) support - not yet implemented. The addon is already written
  against the retail-era addon APIs, and the integrations (Auctionator,
  Baganator, Dejunk) ship retail versions with the same interfaces, so the
  expected work is small: a multi-version `## Interface` line, plus
  recalibrating the deposit and auction-duration tunables, which currently
  encode Forever's auction rules and are untested on retail.
