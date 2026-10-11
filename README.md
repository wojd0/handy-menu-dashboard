# Handy Menu Dashboard

[![CI](https://github.com/wojd0/handy-menu-dashboard/actions/workflows/ci.yml/badge.svg)](https://github.com/wojd0/handy-menu-dashboard/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

A macOS menu bar app that tracks coding-agent usage at a glance.

## Features

- **Cursor** — Current billing-period spend against your team per-user monthly limit.
- **Claude** — Claude.ai usage across five pools: the 5-hour session and weekly windows, usage limit (General), credit and Combined. Pick a baseline from the pools your plan has and dollars, % used, or % remaining.
- **ChatGPT** — Monthly credit usage against the effective spend-control limit for the currently selected ChatGPT account.
- **GitHub Copilot** — Current credit usage against the quota reported by your Copilot plan.
- **Menu bar summary** — Compact per-service labels; drag to reorder and show monetary units, % used, or % remaining per service.
- **Secure & sandboxed** — Session cookies live in the macOS Keychain; outbound network only.

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

Open **Settings** from the dashboard popover (gear icon). Each service has its own login/credentials, an **Enabled** toggle, and a menu-bar display selector for monetary units, % used, or % remaining.

- **Cursor / Claude / ChatGPT** — Sign in via the embedded WebView; cookies are saved to Keychain. Claude also lets you pick a baseline from the pools your plan has. ChatGPT tracks the account selected during sign-in and can show credits, % used, or % remaining in the menu bar.
- **GitHub Copilot** — Sign in through the embedded GitHub browser to fetch your used, total, and remaining credits automatically.

The Copilot integration uses GitHub's undocumented web entitlement endpoint. GitHub may change this endpoint or its response without notice.

## Security

Sign-in happens in an embedded WebView that loads the provider's own login page — you authenticate directly with the provider, and the app never sees your username or password. After login, it reads only that provider's session cookies from the WebView and stores them in the Keychain.

Credentials never leave your machine except in authenticated HTTPS calls to providers. Keychain keys are prefixed `com.wojd0.dashboard.*`, and the App Sandbox allows `com.apple.security.network.client` only.

## Contributing

Issues are welcome on [GitHub](https://github.com/wojd0/handy-menu-dashboard).

This is mostly vibe-coded so don't bother writing any PRs, I'll prompt it myself ;P.

## License

[Apache License 2.0](LICENSE)

*System check weapons. Initiate HMD visor.*
<img width="640" height="360" alt="Battlefield 3_ Campaign_Going_Hunting" src="https://github.com/user-attachments/assets/af445b68-ca83-4ac6-9b6a-f08505113d0a" />
