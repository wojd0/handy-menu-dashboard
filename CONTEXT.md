# CONTEXT

Domain language for handy-menu-dashboard. Architecture reviews and new code should use these
terms exactly. Terms marked *(planned)* name modules from the agreed deepening plan that do not
exist yet.

## Domain

**Provider** — one coding-agent account whose usage the app tracks: Cursor, GitHub Copilot,
Claude, ChatGPT. Modelled as a `nonisolated` enum. It is a value: `Codable` + `Transferable`
(the drag payload for reordering), `Hashable` (the `cardHeights` key), and the `ForEach`
identity in the dashboard and settings. It carries per-provider facts, never behaviour.

**Usage reading** — what one provider reports at a point in time: used, limit, whether the
account is unlimited. Always expressed in **dollars or credits, never cents**. The reading owns
percent-used, percent-remaining, over-limit and the strings derived from them.

**Pool** — one metered bucket within a provider. Claude is the only provider with more than one:
**spend** (the general usage limit) and **credit** (the Claude Code & Cowork pool, `cinder_cove`
in the payload).

**Baseline** — which Claude pool the menu bar reports: General, Code and Cowork, or Combined.
Claude-only; no other provider has one.

**Menu-bar fragment** — the short string one provider contributes to the menu-bar image, e.g.
`$150/100`, `5.3K/350K`, `98%`. Fragments are laid out into columns and rasterised through
`ImageRenderer`.

**Display mode** — the unit a fragment is rendered in: monetary, percent-used, percent-remaining.
Per provider.

**Percent remaining** — **the signed complement, `100 − percentUsed`, for every provider.** It
goes negative when an account is over limit. Copilot previously used GitHub's own reported
`remaining` figure, which floors at zero; that divergence was deliberately removed. See
`docs/adr/0001`.

**Unlimited** — an account with no enforced limit. An **explicit** field, set only where a
provider actually reports it (Cursor, Copilot). A zero limit means "nothing configured", which is
not the same thing and must not be conflated. See `docs/adr/0002`.

**Over limit** — `!isUnlimited && percentUsed > 100`. One definition, one place.

**Session** — an authenticated cookie header for one provider, plus everything that hangs off it:
the Keychain entry, whether the provider is enabled, and the refresh loop. Sessions are
established through a WebView sign-in, never a password.

**Harvest** — the rule that decides when a sign-in WebView has produced a usable session: which
host, which path, which cookie names. Per provider, expressed as data.

**Credential policy** — two orthogonal per-provider facts, deliberately not one flag:
`clearsCredentialOnAuthExpiry` (Copilot and ChatGPT discard on 401/403; Cursor and Claude retain,
so a transient Cloudflare 403 self-heals on the next tick) and `validatesBeforePersisting`
(Copilot and ChatGPT prove the session works before writing to the Keychain; Cursor and Claude
currently do not).

## Modules *(planned)*

**UsageReading** — the single definition of percent, over-limit, the menu-bar fragment and the
dashboard detail string. A `nonisolated Sendable` value. Formatting varies along two independent
axes: **AmountStyle** (menu bar) and **DetailStyle** (dashboard). They are not diagonal — Cursor
and Claude share an amount style but not a detail style.

**UsageSession** — owns the refresh envelope (`run(load:apply:fail:)`: the cookie preamble, the
loading flag, the staleness guard, the catch) and the credential lifecycle. Owns the enabled flag
and display mode via **ProviderPreferences**. Does *not* own the refresh loop — that would form a
retain cycle a `@MainActor deinit` cannot break.

**RefreshLoop** — the 180-second loop and its cancellation. Deliberately **not** `@Observable`:
the macro rewrites the stored task into a computed property, which makes `deinit` illegal.

**SessionTransition** — the failure-to-state rule as a pure reducer. Per-provider credential
policy is data, not a branch.

**UsageRequest / HTTPOutcome / BrowserIdentity / CookieHeader** — request construction and status
classification as pure values, behind one transport seam with two adapters: `URLSession` in
production, a closure in tests.

**CookieHarvest** — the four harvest rules as testable data, lifted out of the
`WKNavigationDelegate` callbacks no test can reach.

**LoginFlow** — the reentrancy guard, retry latch and clear-then-reload recovery, lifted out of
the WebView Coordinator. Its side effects are installed by the Coordinator, not injected at init.

**ProviderSettingsCard** — one generic settings card with a slot for provider-specific controls.
Generic over the concrete service type, because `@Bindable` needs `AnyObject & Observable` and
existentials do not self-conform.

**ServiceSet** — holds the four services and refreshes them together. Not observable; views track
the individual services they read.

## Vocabulary

Architecture discussion uses: **module, interface, implementation, depth, deep, shallow, seam,
adapter, leverage, locality**. Not: component, boundary, layer, wrapper.
