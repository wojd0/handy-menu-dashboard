# 0002 — "Unlimited" is an explicit field, never derived from a zero limit

Status: accepted
Date: 2026-09-10

## Context

Only Cursor and Copilot set `isUnlimited`; both read it from a real signal in their payloads.
Claude and ChatGPT never set it.

Every percent function guards `limit > 0` and returns `0`, so an account with no configured limit
displays a confident "0%" rather than an infinity symbol. Deriving `isUnlimited` from
`limit == 0` would make those accounts show "∞%" instead.

## Decision

`isUnlimited` stays an explicit stored field, set only where a provider actually reports it.
A zero limit is not treated as unlimited.

## Consequences

- An unconfigured Claude or ChatGPT account keeps showing "0%".
- "The server told us nothing" stays distinguishable from "this account has no limit". Conflating
  them is a semantic loss that cannot be undone downstream.
- Whether a provider is unlimited remains a product decision driven by payload data, rather than
  something that emerges from a refactor.
- Four assertions that pin this deliberate behaviour stay green.

## Revisit when

An actual unlimited flag is found in the Claude or ChatGPT responses. Then decode it into the
explicit field — do not derive it.
