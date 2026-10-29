# CONTEXT

Domain language for handy-menu-dashboard. Architecture reviews and new code should use these
terms exactly.

## Domain

**Provider** — one coding-agent account whose usage the app tracks: Cursor, GitHub Copilot,
Claude, ChatGPT. Modelled as an enum. It is a value: `Codable` + `Transferable`
(the drag payload for reordering), `Hashable` (the `cardHeights` key), and the `ForEach`
identity in the dashboard and settings. It carries per-provider facts, never behaviour.

**Usage reading** — what one provider reports at a point in time: used, limit, whether the
account is unlimited. Always expressed in **dollars or credits, never cents**. The reading owns
percent-used, percent-remaining, over-limit and the strings derived from them.

**Pool** — one metered bucket within a provider. Claude is the only provider with more than one:
**spend** (the general usage limit), **credit** (a monthly dollar pool with its own reset date) and the
two subscription windows, **session** (`five_hour`) and **weekly** (`seven_day`). The windows report
percent only, with a reset time. The credit pool key is obfuscated and changes (`cinder_cove`,
`iguana_necktie`). The decoder takes `cinder_cove` first, then the first other object that has `limit_dollars`.

**Usage pool** — which Claude pool the menu bar reports: General, Credit, Combined, Session or
Weekly. Claude-only; no other provider has one. Settings lists only the usage pools that have data.
Combined needs both spend and credit. If the chosen pool has no data, the menu bar uses Session
(then Weekly) instead. This is `resolvedUsagePool`.

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
established either by harvesting the user's browser (with consent) or through a WebView sign-in,
never a password.

**Pending update** — a provider that `isEnabled && !isAuthenticated`: turned on but never connected,
expired, or rejected. Computed, never stored. `SessionUpdateCoordinator.pending` lists them in
provider order. A pending provider shows a warning in the menu bar, the popover and its Settings card.

**Enabled** — a provider is off until it has a session. A stored credential with no saved choice
turns it on at launch, and so does any sign-in. A provider the user never connected is off, so it is
never pending.

**Consent** — the app never reads the browser on its own. A pending provider raises the warnings
and one edge-triggered notification; the user opens a dialog and **approves** a named harvest, or
**skips** it (the warnings stay). Signing out also disables the provider so the warning does not
return at once.

**Cookie source** — which browser the harvest reads: the default browser (`.automatic`) or a
chosen one. Stored under `browserCookieSource`.

**Harvest result** — the outcome of one provider's harvest: `updated`, `notSignedInBrowser` (no
session in the browser), `rejected` (validation failed), `accessDenied`/`keyDenied` (the sandbox or
TCC blocked the read, so the manual clipboard fallback is offered), or `failed`.

**Harvest** — the rule that decides when a sign-in WebView has produced a usable session: which
host, which path, which cookie names. Per provider, expressed as data.

**Credential policy** — two orthogonal per-provider facts, deliberately not one flag:
`clearsCredentialOnAuthExpiry` (Copilot and ChatGPT discard on 401/403; Cursor and Claude retain,
so a transient Cloudflare 403 self-heals on the next refresh) and whether it validates before persisting
(Copilot and ChatGPT prove the session works before writing to the Keychain; Cursor and Claude
currently do not).

## Modules

**UsageReading** — the single definition of percent, over-limit, the menu-bar fragment and the
dashboard detail string. A plain value type. Formatting varies along two independent
axes: **AmountStyle** (menu bar) and **DetailStyle** (dashboard). They are not diagonal — Cursor
and Claude share an amount style but not a detail style.

**UsageSession** — owns the refresh envelope (`run(load:apply:unexpected:)`: the cookie preamble, the
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
