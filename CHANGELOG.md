# CHANGELOG

## Table of Contents

- [Version 1.0.0](#version-100---2026-11-25)

## Version 1.0.0 - 2026-11-25

### Added - 1.0.0

- Passive tooltip verdicts: a red `NotWorthIt - vendor pays more` line with the
  vendor-versus-auction comparison when vendoring wins, and a green
  `~~Not~~WorthIt` signature line with the auction margin when auctioning
  wins.
- Undercut scam guard: bait listings that crash the recorded minimum are
  valued at the recent market instead, read from Auctionator's day-bucketed
  price history.
- Stale auction prices show an `Auction data outdated` note instead of a
  verdict, and never flag an item as junk.
- Exact auction deposit measurement while the auction house is open, with a
  classic-rate estimate as fallback.
- Baganator junk plugin: grey items are always junk, useful-item guards keep
  level-appropriate consumables and equipment set pieces safe, Dejunk's rules
  pass through via `DejunkApi:IsJunk`, and junk markers refresh when prices or
  Dejunk settings change.
- Hand-edited tunables at the top of `NotWorthIt.lua`; no settings UI, no
  slash commands, nothing saved to disk.
