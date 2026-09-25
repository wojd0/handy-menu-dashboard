# 3. Browser cookie harvest requires user consent

## Status

Accepted.

## Context

Sessions were established only through a `WKWebView` sign-in that had to be repeated by hand
whenever a provider's cookie expired. The user's browser already holds a live session for each
provider, so the app can read those cookies directly. Reading another application's cookie store
is indistinguishable, at the system-call level, from what credential-stealing malware does, so the
capability must never run silently.

## Decision

The app reads the browser only after the user approves a specific harvest.

- **Pending update** is `isEnabled && !isAuthenticated`, computed from state the services already
  expose — never a stored flag. It covers expired and discarded credentials, and providers the user
  turned on but never connected.
- **Providers are off until they have a session.** An unset enabled preference used to mean on,
  which would make every provider an existing user never connected pending forever. Now an unset
  preference means off, a stored credential turns it on at launch, and any sign-in turns it on.
- A pending provider shows a warning in three places (menu bar, popover, Settings card) and
  triggers **one** notification. The notification is **edge-triggered**: `notified` tracks the
  providers already announced, so Skip does not re-notify and a fresh push arrives only when a new
  provider becomes pending.
- Clicking the notification or the menu-bar slot opens a dialog that lists the providers, names the
  browser and the domains it will read, and offers **Approve** / **Skip**. Only Approve reads the
  browser, and only one harvest runs at a time. A Settings card opens the same dialog for its own
  provider, even when that provider is off.
- The manual fallback clears the clipboard as soon as it is imported: for Chromium it carries the
  browser's Safe Storage key.
- **Sign Out also disables the provider** (`isEnabled = false`). Otherwise signing out would make
  the warning and consent flow reappear immediately. Re-enabling makes it pending again.
- **The App Sandbox stays on.** The installed build is unsigned so the sandbox is not enforced
  there, but the Xcode run is sandboxed and Safari always needs Full Disk Access (TCC). When a
  direct read is refused (`accessDenied`/`keyDenied`), the dialog falls back to a copy-run-paste
  Terminal command ending in `| pbcopy`, which the user runs themselves. No sandbox exception is
  requested.
- Credentials are read as data and handed to the same per-provider adopt path as the WebView
  sign-in. Copilot and ChatGPT still validate before persisting; Cursor and Claude still persist
  then refresh. The credential policy in `SessionTransition` is unchanged.

## Consequences

- The reader, the notifier and the coordinator sit behind seams (`BrowserCookieReading`,
  `SessionUpdateNotifying`) with disabled adapters on the test host, so the suite never touches a
  real browser store or posts a real notification.
- Cookies harvested from a non-Safari browser are sent with the app's Safari user agent
  (`BrowserIdentity`). Cloudflare's `cf_clearance` is bound to the user agent, so Cursor and Claude
  may see a 403 the dialog surfaces as a failure. A per-browser user agent is the follow-up if that
  happens in practice.
