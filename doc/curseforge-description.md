<!-- CurseForge project description. CurseForge renders BBCode, so convert
     this markdown before pasting. Keep in sync with README.md: update it
     whenever a README change affects functionality, tunables, or
     integrations. -->

NotWorthIt is a passive addon for WoW Forever (1.60.1) that tells you when an
item is worth more to a vendor than on the auction house.

No settings UI, no slash commands, nothing saved to disk. Install it and it
works: hover an item and its tooltip gains a verdict line. To change how it
judges items, edit the tunables at the top of `NotWorthIt.lua` and reload.

## What it does

- Reads the current auction price from Auctionator's price database and the
  vendor sell price from the game's own item data.
- Compares them per unit, accounting for the auction house's sales cut and
  the listing deposit you lose if the auction fails to sell.
- Adds one line to the item tooltip:

  ```text
  NotWorthIt        14c more at vendor          <- vendor wins (red)
  ~~Not~~WorthIt    37c more on AH              <- auction wins (green)
  ```

- Holding Shift while hovering adds a calculation line spelling out the
  numbers behind the verdict: auction net, margin, vendor price, and the
  vendor bar. It updates the moment Shift is pressed or released.
- With Baganator installed, flagged items get the junk coin and sort with
  the trash.

It stays quiet about anything it cannot judge: soulbound, quest-bound, or
otherwise unsellable items, and items with no vendor value. When the
auction price is older than the freshness limit, the tooltip shows an
"Auction data outdated" note instead of a verdict.

## How it decides

```text
auction net = AH price * (1 - AH cut) - deposit
vendor bar  = vendor sell price * threshold

vendor wins when: auction net < vendor bar
```

The default threshold of 1.02 means the auction has to beat the vendor by
at least 2% before the item is considered worth listing.

Two extra costs can be folded into the comparison:

- **Undercut scam guard.** Bots briefly list a single unit at a crash price
  to bait matching tools, then buy it back. When the current price collapses
  far below the recent market in Auctionator's price history, the outlier is
  ignored and the verdict uses the typical price instead.
- **Bank alt mode** (off by default). Mailing loot to a bank alt to auction
  costs a fee per item stack, which eats into small profits fast at low
  levels. When enabled, the auction net also pays a per-unit share of that
  fee.

## Integrations

- **Auctionator** (required) supplies the auction prices and their
  freshness. If it is missing or disabled, NotWorthIt stays silent rather
  than guessing.
- **Baganator** (optional) receives the verdict through its junk plugin
  system. Baganator runs one junk detector at a time, so while NotWorthIt is
  the selected detector it also covers the standard cases itself: greys are
  always junk, useful items (recent consumables, equipment set pieces) are
  never junk.
- **Dejunk** (optional) keeps applying its own rules: NotWorthIt consults
  its public `DejunkApi:IsJunk` rather than reimplementing them.

All integrations are read-only and degrade gracefully: a missing or changed
API means silence or fallback, never an error.

## Configuration

There is no configuration UI. The tunables are constants at the top of
`NotWorthIt.lua`; edit and `/reload`. The main ones:

| Constant | Default | Meaning |
| -------- | ------- | ------- |
| `NWC_THRESHOLD` | `1.02` | The auction must beat the vendor price by this factor (1.02 = 2%). |
| `NWC_FRESHNESS_DAYS` | `2` | Ignore auction prices older than this many days. |
| `NWC_INCLUDE_DEPOSIT` | `true` | Subtract the listing deposit from the auction value. |
| `NWC_AUCTION_DURATION` | `8` | Deposit basis in hours: 2, 8 or 24. |
| `NWC_AUCTION_CUT` | `0.05` | The share the auction house keeps from a successful sale. |
| `NWC_SCAM_GUARD` | `true` | Ignore single bait listings that crash the current price. |
| `NWC_BANK_ALT_MODE` | `false` | Charge the auction net a per-unit share of the bank alt mail fee. |
| `NWC_DEBUG` | `false` | Print one chat line per hovered item explaining its verdict. |

The rest live in the same file with comments explaining each.

## Notes and limits

- Built for WoW Forever only (`## Interface: 16001`). Retail support is
  planned but not implemented.
- Nothing is saved to disk; caches live for the current session only.
- The addon never posts, cancels, or sells anything. It only reads data and
  writes tooltip text and Baganator's junk flags, so the most a wrong
  verdict can cost is coin.

## AI Advisory / Warranty

While a human is responsible for the design, overall architecture, and
testing of this project, AI was used to produce the codebase. This is a
hobby addon offered as-is, with no warranty: the whole addon is one short
Lua file, so read it before you trust it, and hold Shift to see the numbers
before acting on anything that matters. Unofficial, not affiliated with or
endorsed by Blizzard Entertainment.
