# Handy Menu Dashboard

[![CI](https://github.com/wojd0/handy-menu-dashboard/actions/workflows/ci.yml/badge.svg)](https://github.com/wojd0/handy-menu-dashboard/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

A macOS menu bar app that tracks coding-agent usage at a glance.

## Features

- **Cursor** — Current billing-period spend against your team per-user monthly limit.
- **Claude** — Claude.ai usage across two pools: usage limit (General) and Claude Code & Cowork credit. Pick a baseline (General / Code and Cowork / Combined) and dollars or percent.
- **GitHub Copilot** — Premium request usage for the month against a configurable entitlement (feature flagged for now).
- **Menu bar summary** — Compact per-service labels; drag to reorder, toggle dollars/percent per service.
- **Secure & sandboxed** — Cookies and PATs live in the macOS Keychain; outbound network only.

## Requirements

- macOS 26.3 or later
- Xcode 26.4 (Swift 6 concurrency, Swift Testing)

## Build and run

In Xcode, open `handy-menu-dashboard.xcodeproj`, select the **handy-menu-dashboard** scheme, and press **Cmd+R**.

Or from the command line:

```bash
make build        # Release build (unsigned)
make install      # Build and install to ~/Applications (prompts to replace)
make install-dev  # Build and install to /Applications and ~/Applications
make test         # Run unit tests
make lint         # SwiftLint (optional, advisory)
```

## Configuration

Open **Settings** from the dashboard popover (gear icon). Each service has its own login/credentials, an **Enabled** toggle, and a dollars/percent switch.

- **Cursor / Claude** — Sign in via the embedded WebView; cookies are saved to Keychain. Claude also lets you pick a baseline (General / Code and Cowork / Combined).
- **GitHub Copilot** — Enter your username and a [fine-grained PAT](https://github.com/settings/tokens?type=beta) with read access to **Account** billing/usage, plus a monthly entitlement (default **300**).

GitHub Copilot is hidden by default — to enable it locally, copy `.env.example` to `.env`, set `SHOW_GITHUB_SETTINGS=true`, and rebuild. See [CLAUDE.md](CLAUDE.md) for details.

## Security

Sign-in happens in an embedded WebView that loads the provider's own login page — you authenticate directly with the provider, and the app never sees your username or password. After login, it reads only that provider's session cookies from the WebView and stores them in the Keychain.

Credentials never leave your machine except in authenticated HTTPS calls to providers. Keychain keys are prefixed `com.wojd0.dashboard.*`, and the App Sandbox allows `com.apple.security.network.client` only.

## Contributing

Issues are welcome on [GitHub](https://github.com/wojd0/handy-menu-dashboard).

This is mostly vibe-coded so don't bother writing any PRs, I'll prompt it myself ;P.

## License

[Apache License 2.0](LICENSE)
