# CHANGELOG

## Table of Contents

- [Version 1.1.0](#version-110---2026-11-25)
- [Version 1.0.1](#version-101---2026-11-25)
- [Version 1.0.0](#version-100---2026-11-25)

## Version 1.1.0 - 2026-11-25

### Added - 1.1.0

- Holding Shift while hovering adds a calculation line under either verdict
  line - the auction net, the margin figure the verdict line shows, the
  vendor price, and the threshold-adjusted vendor bar in parentheses - and
  the tooltip updates while Shift is pressed or released.

### Changed - 1.1.0

- Both verdict lines share one shape: the addon's name on the left and the
  winning margin on the right - `<amount> more on AH` when auctioning wins,
  `<amount> more at vendor` when vendoring wins. The flagged line's figure
  is the shortfall against the vendor's threshold bar, so it stays correct
  even when the raw vendor price sits below the auction net.

## Version 1.0.1 - 2026-11-25

### Fixed - 1.0.1

- The red verdict line states its reason instead of a bare inequality: the
  auction net and the `NWC_THRESHOLD` percent it fell under, for example
  `AH 6s11c is under 2% threshold`, so near-threshold items no longer display
  false inequalities such as `vendor 6s > AH 6s11c`.

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
