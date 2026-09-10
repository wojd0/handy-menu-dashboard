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

Services (`CursorService`, `CopilotService`, `ClaudeService`, `ChatGPTService`) are `@Observable` classes created as `@State` in the `App` struct and passed as parameters to views — not via `@Environment`. All services auto-refresh every 3 minutes via background `Task` loops and store credentials in Keychain.

### Business Logic

**`UsageMath.swift`** contains all pure calculation and formatting functions and the JSON response structs. This is the right place for numeric/formatting logic — keep it side-effect free.

### Services
- **CursorService** — Fetches Cursor IDE team spend via `cursor.com/api/dashboard/get-team-spend`. Cookie-based auth (WebView login flow). Extracts `team_id` from cookies, fetches team spend, then identifies the current user by matching email from `/api/auth/me`.
- **CopilotService** — Fetches GitHub Copilot credit quota via the undocumented GitHub web entitlement endpoint (`/github-copilot/chat/entitlement`). Cookie-based auth (WebView login flow).
- **ClaudeService** — Fetches Claude.ai usage via `claude.ai/api/organizations/{orgId}/usage`. Cookie-based auth (WebView login). Org ID read from the `lastActiveOrg` cookie. Tracks two pools: **spend** (usage limit) and **cinder_cove** (Claude Code & Cowork credit). Supports three baselines (`usageLimit`, `credit`, `combined`) each with Dollars or Percent menu-bar display.
- **ChatGPTService** — Fetches monthly ChatGPT credits from the current account's spend-control endpoint. Cookie-based auth (WebView login); refreshes the bearer token through the ChatGPT session endpoint and verifies it against the selected `_account` cookie.
- **KeychainStoring** / **KeychainStore** — Protocol + production implementation wrapping macOS Security framework (`SecItem*` APIs). Injected into services; tests use `InMemoryKeychainStore`. All keys prefixed `com.wojd0.dashboard.*`. Includes automatic migration from legacy keychain format.

### Views
- **handy_menu_dashboardApp** — App entry point. `MenuBarExtra` shows usage summary; separate `Window("Settings", id: "settings")` opened via `openWindow`.
- **DashboardView** — Main popover with usage cards for each service, settings gear, and quit button.
- **UsageCardView** — Reusable card showing service name, percentage, detail text, and progress bar.
- **UsageProgressBar** — Gradient progress bar (green→yellow→orange→red based on usage).
- **SettingsView** — Settings window with per-service cards and WebView login flows. Each service has its own credits/dollars/percent menu-bar switch. Claude also has a 3-step baseline picker (Limit / Credit / Combined).
- **CursorLoginView** — `WKWebView` wrapper for Cursor OAuth login and cookie extraction.
- **CopilotLoginView** — `WKWebView` wrapper for GitHub login and session-cookie validation against the Copilot entitlement endpoint.
- **ClaudeLoginView** — `WKWebView` wrapper for Claude login. Extracts `claude.ai` cookies after the user signs in and navigates away from `/login`.
- **ChatGPTLoginView** — `WKWebView` wrapper for ChatGPT login. Extracts the split NextAuth session cookies and currently selected account cookie.
