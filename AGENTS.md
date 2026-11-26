# AGENTS.md

Agent-facing guidance for working on NotWorthIt. User-facing documentation
lives in README.md; do not duplicate it here.

## Project layout

- `NotWorthIt.lua` - the entire addon: tunables at the top, then derived
  constants, verdict logic, tooltip rendering, Baganator integration.
- `NotWorthIt.toc` - Forever manifest (Interface 16001).
- `README.md` - user-facing docs (functionality, tunables, integrations).
- `doc/` - README screenshots and `doc/curseforge-description.md`, the
  CurseForge listing (markdown, paste-ready as-is; CurseForge projects can
  use markdown descriptions).

## Design invariants

The addon is deliberately passive. Do not add settings UI, slash commands,
SavedVariables, or automation of any kind. Tunables are hand-edited constants
at the top of `NotWorthIt.lua`; the user edits their own working copy (for
example flipping `NWC_DEBUG`), so never revert or "clean up" their local
edits unasked.

- The tooltip verdict answers "what is the best way to sell this": both
  verdict lines show the addon's name on the left and the winning margin on
  the right (`more on AH` / `more at vendor`). The flagged line's margin is
  the shortfall against the vendor bar (vendor price times the threshold),
  which is what the verdict acts on.
- Holding Shift adds a calculation line under either verdict line: the
  auction net, the same margin figure the verdict line shows, the vendor
  price, and the vendor bar (vendor price times the threshold) in
  parentheses. It renders when the tooltip is built and re-renders live on
  Shift changes via `RefreshData` (guarded, silent when the build lacks
  it).
- The Baganator junk label answers "is this trash": the guards (greys, useful
  items, equipment sets) shape only the label, never the tooltip verdict.
- Dejunk is delegated to via its public `DejunkApi:IsJunk`, never
  reimplemented locally.
- A stale auction price shows the "outdated" tooltip note and never flags
  the item as junk.
- Nothing is saved to disk; caches (measured deposits) are session-only.
- The addon never posts, cancels, or sells anything.

## Verification loop

There is no test suite, and the game client cannot be launched from here.
After every change to the Lua source, run both static checks:

- Syntax: `luac -p NotWorthIt.lua`.
- ASCII: the source must stay pure ASCII (0-127); scan for any byte outside
  that range. In-game display text uses escape sequences instead
  (`|cff...|r` colours, `|T...|t` textures).

Runtime behaviour is tested by the user in game; static review against the
integration targets (below) is the agent's substitute.

## Integration discipline

Auctionator, Baganator and Dejunk are read-only integrations:

- Only public APIs and in-memory reads. Never write to, hook, or modify
  another addon's files or internals. Our own tooltip fields (`__NWC*`) and
  secure hooks on Blizzard tooltip methods are the only side effects outside
  our namespace.
- Every integration is guarded and degrades gracefully: a missing, disabled,
  or changed API means silence or fallback, never an error.
- New dependencies go in `OptionalDeps` with an `ADDON_LOADED` fallback for
  changed load order.

API contracts can be verified statically: the author's machine has sibling
installs of both client flavors under the game directory
(`_forever_\Interface\AddOns\...` and `_retail_\Interface\AddOns\...`),
including Auctionator, Baganator and Dejunk. Read those sources to confirm
an API exists and behaves as expected before relying on it.

## Environment notes

- Forever (1.60.1) is Blizzard's official vanilla-flavoured server (launched
  November 2026), not a private server, built on the modern retail engine:
  Interface 16001, game type `camelot` (`WOW_PROJECT_ID` equals
  `WOW_PROJECT_CAMELOT`), classic-style auction house with modern APIs.
- Retail (12.x) support is planned but not implemented (see the README
  Roadmap). Do not implement it unasked.
- Keep README.md in sync with behaviour changes, and keep it lightweight.
- Keep `doc/curseforge-description.md` in sync with README changes: it is
  the CurseForge listing, so whenever a README change affects functionality,
  tunables, or integrations, apply the same change there. That file is
  exempt from the 80-column markdown wrapping: keep each paragraph and list
  item on a single long line, because mid-line breaks cause formatting
  problems when the description is pasted into CurseForge.
