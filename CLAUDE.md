# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

This is a **macOS-only** SwiftUI menu bar app (not iOS). `SUPPORTED_PLATFORMS = macosx`.

- **Open in Xcode:** `open "wojciech little dashboard.xcodeproj"` then Cmd+R
- **Build from CLI:** `xcodebuild -project "wojciech little dashboard.xcodeproj" -scheme "wojciech little dashboard" build`

Scheme name: `wojciech little dashboard`

## Project Configuration

- Xcode 26.4, macOS deployment target 26.3
- Swift 5 language version with **Swift 6 concurrency mode**: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES`. All types are implicitly `@MainActor` unless opted out.
- `LSUIElement = YES` — menu bar only, no Dock icon.
- Uses `PBXFileSystemSynchronizedRootGroup` — Xcode auto-manages file references; new Swift files added to the `wojciech little dashboard/` folder are automatically included in the build.
- App Sandbox enabled with `com.apple.security.network.client` entitlement.

## Architecture

Menu bar app using `MenuBarExtra` with `.window` style showing coding agent usage statistics.

### Data Flow

Services (`CursorService`, `CopilotService`) are `@Observable` classes created as `@State` in the `App` struct and passed as parameters to views — not via `@Environment`. Both services auto-refresh every 3 minutes via background `Task` loops and store credentials in Keychain.

### Services
- **CursorService** — Fetches Cursor IDE team spend via `cursor.com/api/dashboard/get-team-spend`. Cookie-based auth (WebView login flow). Extracts `team_id` from cookies to call the team spend endpoint, then finds the current user's entry by email.
- **CopilotService** — Fetches GitHub Copilot premium request usage via GitHub API. Fine-grained PAT auth. User-configurable monthly entitlement (default 300).
- **KeychainService** — Enum with static helpers wrapping macOS Security framework (`SecItem*` APIs) for credential storage. All keys prefixed `com.wojd0.dashboard.*`.

### Views
- **wojciech_little_dashboardApp** — App entry point. `MenuBarExtra` shows usage summary; separate `Window("Settings", id: "settings")` opened via `openWindow`.
- **DashboardView** — Main popover with usage cards for each service, settings gear, and quit button.
- **UsageCardView** — Reusable card showing service name, percentage, detail text, and progress bar.
- **UsageProgressBar** — Gradient progress bar (green→yellow→orange→red based on usage).
- **SettingsView** — `TabView` with tabs for Cursor (WebView login) and Copilot (PAT entry + entitlement).
- **CursorLoginView** — `WKWebView` wrapper for Cursor OAuth login and cookie extraction.
