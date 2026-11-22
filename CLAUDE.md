# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

This is a **macOS-only** SwiftUI menu bar app (not iOS). `SUPPORTED_PLATFORMS = macosx`.

- **Open in Xcode:** `open "handy-menu-dashboard.xcodeproj"` then Cmd+R
- **Build:** `make build`
- **Install while iterating:** `make install-dev` builds Release and replaces `~/Applications/handy-menu-dashboard.app`
- **Run tests:** `make test`
- **Lint:** `make lint` (requires swiftlint; non-fatal if missing)

Scheme name: `handy-menu-dashboard`

## Project Configuration

- Xcode 26.4, macOS deployment target 26.3
- Swift 5 language version with **Swift 6 concurrency mode**: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES`. All types are implicitly `@MainActor` unless opted out.
- `LSUIElement = YES` — menu bar only, no Dock icon.
- Uses `PBXFileSystemSynchronizedRootGroup` — Xcode auto-manages file references; new Swift files added to the `handy-menu-dashboard/` folder are automatically included in the build.
- App Sandbox enabled with `com.apple.security.network.client` entitlement.
- Tests use the **Swift Testing** framework (not XCTest).

## Architecture

Menu bar app using `MenuBarExtra` with `.window` style showing coding agent usage statistics.

### Data Flow

The five `@Observable` services (`CursorService`, `CopilotService`, `ClaudeService`, `ChatGPTService`,
`AntigravityService`) are held in a `ServiceSet` created as `@State` in the `App` struct and passed as one parameter to views — not via
`@Environment`. Each service is a thin shell: it decodes its provider's payload and applies it. Everything
shared sits behind modules the shell depends on.

Per-provider facts — display name, icon, accent, keychain key, error noun, preference keys, monetary label,
credential policy, cookie harvest rule — are data on the `Provider` enum, not branches at
call sites. `ServiceSet`'s subscript is the single dispatch point from a `Provider` to its service.

See `CONTEXT.md` for the domain glossary and `docs/adr/` for decisions that should not be re-litigated.

### Shared modules

- **`UsageSession`** — Owns the refresh envelope (`run(load:apply:unexpected:)`: the cookie preamble, the
  loading flag, the staleness guard, the catch) and the credential lifecycle. Also owns `isEnabled` and
  `menuBarDisplayMode`. A provider is off until it has a session: a stored credential with no saved
  choice, or any sign-in (`persist`), turns it on. Deliberately does **not** own the refresh loop — that would form a retain cycle a
  `@MainActor deinit` cannot break.
- **`RefreshLoop`** — The 180-second loop and its cancellation. Deliberately **not** `@Observable`: the macro
  rewrites the stored task into a computed property, which makes `deinit` illegal.
- **`UsageTransport` / `UsageRequest` / `HTTPOutcome` / `BrowserIdentity` / `CookieHeader`** — Request
  construction and status classification as pure values, behind one seam with two adapters: `URLSession` in
  production (`DefaultDataLoader.live`), a closure in tests. `AuthExpiredPolicy.github` adds 404 and the
  `/login` path; every other provider uses `.standard`.
- **`SessionTransition` / `UsageFailure`** — The failure-to-state rule as a pure reducer. Whether a provider
  discards its credential on auth expiry is data on `Provider`, not a branch.
- **`UsageReading` / `AmountStyle` / `DetailStyle`** — The single definition of percent, over-limit, the
  menu-bar fragment and the dashboard detail string. Always dollars or credits, never cents.
- **`UsageMath`** — Leaf formatting and generic percent maths only. It must not learn provider names again;
  it still holds the five `Decodable` response structs.
- **`ProviderPreferences`** — The only owner of the `<provider>Enabled` and `<provider>MenuBarShowPercent`
  keys, derived from `Provider.rawValue`. `ProviderPreferencesTests` pins the derived strings against the
  literals that shipped — a one-character drift would silently reset every user's saved settings.
- **`CookieHarvest`** — The five sign-in harvest rules as testable data: start URL, path gate, domain match,
  session-cookie rule, website-data domains.
- **`LoginFlow`** — The reentrancy guard, retry latch and clear-then-reload recovery, lifted out of the
  WebView coordinator. Its side effects are installed by the coordinator in `makeNSView`, not injected at init.
- **Browser harvest** — Reading the user's browser cookie stores, only after consent. `Browser`
  carries per-browser facts (bundle IDs, profile paths, Safe Storage names) as data, like `Provider`.
  `BrowserCookieReading` is the seam with `LiveBrowserCookieReader` (production) and
  `DisabledBrowserCookieReader` (test host). Engines: `GeckoCookieStore` (Firefox/Zen SQLite),
  `ChromiumCookieStore` + `ChromiumCookieCipher` (Chrome/Brave/Edge/Arc/Vivaldi/Chromium, key from
  the Keychain), `SafariBinaryCookies` (Safari `binarycookies`). `SQLiteSnapshot` copies the locked
  DB before reading. `ManualCookieImport` builds the copy-run-paste Terminal fallback for the
  sandbox/TCC case. Nothing runs until `SessionUpdateCoordinator.approve`.
- **`SessionUpdateCoordinator`** — Owns `pending`, the consent `phase` (one harvest at a time), the
  edge-triggered notification (`SessionUpdateNotifying`) and the harvest. Held in `ServiceSet`.
  `adoptBrowserCookies` on each service routes harvested cookies through the same adopt path as the
  WebView sign-in. Sign Out disables the provider so its warning does not return immediately.
  `UserNotificationsNotifier` is the notification-center delegate; a click calls `onNotificationOpened`,
  which `MenuBarLabel` wires to open Settings and call `requestConsent`. Settings presents
  `consentRequest` as a sheet: `SessionUpdateSheet` hosts `SessionUpdateDialog` and shows
  `ProviderLoginSheet` for the web-view fallback; Settings opens it for a single provider.
- **`KeychainStoring` / `KeychainStore`** — Protocol + production implementation wrapping `SecItem*`. Tests
  use `InMemoryKeychainStore`. Credentials share the `com.wojd0.dashboard.credentials` entry, cached per
  store instance. Users upgrading from per-provider storage authenticate again.
- **`PreferenceStoring`** — Same pattern for `UserDefaults`. Tests use `InMemoryPreferenceStore` so the suite
  neither reads nor writes real user preferences.

### Services

- **CursorService** — Fetches usage via `cursor.com/api/usage-summary`, then resolves the display name once
  from `/api/auth/me`. Stores cents; `reading` normalises to dollars.
- **CopilotService** — Fetches credit quota via the undocumented GitHub web entitlement endpoint
  (`/github-copilot/chat/entitlement`). Validates before persisting; an account with no quota is rejected.
- **ClaudeService** — Fetches `claude.ai/api/organizations/{orgId}/usage`. Org ID comes from the
  `lastActiveOrg` cookie, falling back to `/api/organizations`. Tracks four pools: **spend** (usage limit),
  **credit** (monthly dollar pool; the payload key is obfuscated and changes, so
  `ClaudeUsageResponse` takes `cinder_cove` or the first other object with `limit_dollars`), and the
  subscription windows **session** (`five_hour`) and **weekly** (`seven_day`), which report percent only.
  Five usage pools (`usageLimit`, `credit`, `combined`, `session`, `weekly`). Each refresh replaces all pools, so
  a pool that leaves the payload clears. `resolvedUsagePool` falls back to session, then weekly, when the chosen pool is empty.
- **ChatGPTService** — Fetches monthly credits from the account's spend-control endpoint. Refreshes the bearer
  token through the session endpoint and verifies its account claim against the `_account` cookie.
- **AntigravityService** — Fetches the Google Antigravity quota through a `POST` to
  `JetskiRemoteAgentProxyService/GetUserQuotaSummary` on `aicode.clients6.google.com`. The body is
  `application/json+protobuf`: positional arrays, not keyed objects. `AntigravityQuotaResponse` decodes them.
  Each model group has a 5-hour window and a weekly window, as a remaining fraction with a reset time.
  `applyQuota` puts the session window first, then the weekly window, as Claude does.
  Each refresh builds two lists from the payload: the pool types (Most Used plus one for each group) and the pool
  time ranges (Most Used plus each window period of the resolved pool type). The menu bar shows the window with
  the highest percent used in both. `resolvedUsagePool` matches the saved group by window ID, then by name;
  `resolvedPoolRange` needs the saved period in the pool type. Both fall back to Most Used.
  `GoogleSessionAuthorization` signs each request
  with `SAPISIDHASH`: the SHA-1 of the timestamp, the `SAPISID` cookie and the `antigravity.google.com` origin.
  The session keeps only the `google.com` cookies that a browser sends to the quota host.

Cursor and Claude **retain** their stored cookie through a 401/403 so a transient block self-heals on the next
tick; Copilot, ChatGPT and Antigravity **discard** it. This is deliberate and pinned by `SessionTransitionTests` — see
`Provider.clearsCredentialOnAuthExpiry`.

### Views

- **handy_menu_dashboardApp** — App entry point. `MenuBarExtra` shows the usage summary; a separate
  `Window("Settings", id: "settings")` is opened via `openWindow`. `MenuBarLabel` rasterises the fragments
  through `ImageRenderer` — it reads `menuBarText` and `sessionUpdates.pending` (for the trailing
  warning icon), never `isLoading`, or every 3-minute refresh re-renders the whole image.
- **DashboardView** — Popover with a usage card per active provider, settings gear and quit button.
- **UsageCardView** / **ClaudeUsageCardView** / **AntigravityUsageCardView** — One headline percentage plus a
  bar, versus pool rows: Claude's rows are gated on its `has*` flags, Antigravity's rows are grouped by model
  group. Both pool cards use **UsagePoolRow**.
- **UsageProgressBar** — Gradient progress bar (green→yellow→orange→red).
- **SettingsView** — Reorderable provider cards plus the General section. Each card is one generic
  `ProviderSettingsCard<Service, Extra>`; the Claude and Antigravity usage pool pickers pass through the `Extra`
  slot. Antigravity shows two segmented pickers under one "Menu Bar Usage Pool" label: pool type, then pool time range.
  The pool type picker sizes its segments to their titles, and each segment shows its title as a tooltip. The card is
  **generic, not existential** — `@Bindable var service: any UsageDisplaying` does not compile.
- **CursorLoginView** / **ClaudeLoginView** — Simple `WKWebView` sheets that harvest cookies and persist them
  without validating. Both use `Provider.harvest`; Claude's rule gates on host only, not on leaving `/login`.
- **ValidatingLoginView** / **ValidatingWebView** — One login sheet serving Copilot, ChatGPT and Antigravity: validates the
  session before persisting, with an error banner, retry, and clear-then-reload recovery.

**No test in the target touches `SettingsView`, `ProviderSettingsCard` or `ProviderDropDelegate`.** Changes to
the settings layout or the drag-reorder loop can only be verified by running the app.
