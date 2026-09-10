# 0001 — "% Remaining" is the signed complement, for every provider

Status: accepted
Date: 2026-09-10

## Context

The menu bar offers a per-provider "% Remaining" display mode. It meant two different things.

Copilot computed it from GitHub's own reported figure:

    UsageMath.percentUsed(used: creditsRemaining, limit: creditsTotal)

where `creditsRemaining` came from `response.quotas.remaining.premiumInteractions`, falling back
to `max(0, total - used)`. Because that figure floors at zero, Copilot's "% Remaining" could
never go negative.

Cursor, Claude and ChatGPT computed the signed complement, `100 - percentUsed`, which goes
negative when an account is over limit — pinned by assertions expecting `-25%` and `-150`.

One picker label covered both meanings. Nothing in the suite could detect the difference: both
Copilot fixtures are degenerate, satisfying `remaining == total - used` exactly, so `98%` and
`87.5` pass under either basis.

## Decision

"% Remaining" is the signed complement, `100 - percentUsed`, for every provider. Copilot's
reported `remaining` no longer drives the percentage.

`UsageReading` therefore has no `RemainingBasis` field and no `reportedRemaining` input to the
percent calculation. `creditsRemaining` is still decoded and still asserted, it simply no longer
determines what the menu bar shows.

## Consequences

- One label, one meaning. Over-limit reads negative everywhere.
- The app declines a figure GitHub actively sends — the payload even carries
  `premiumInteractionsPercentRemaining` that is not decoded.
- Copilot's displayed value changes for any account where GitHub's `remaining` differs from
  `total - used`. No existing test detects this, so a **non-degenerate Copilot fixture** —
  `remaining` deliberately disagreeing with `total - used` — is mandatory and must assert the
  complement. Without it this decision is unprotected and a future change could silently flip it
  back.

## Rejected

**Keep both, named** — a `remainingBasis` field, `.reported` for Copilot and `.complement` for
the rest. Zero behaviour change and the divergence becomes explicit rather than accidental. This
was the recommended option; it was rejected in favour of one honest meaning for one label.

**Unify on server-authoritative** — use a reported remaining wherever a provider supplies one.
Only Copilot does today, but Claude already stores a `creditRemainingDollars` that nothing reads,
so this would quietly change Claude the day someone wired it up.
