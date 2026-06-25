# handy-menu-dashboard

[![CI](https://github.com/wojd0/handy-menu-dashboard/actions/workflows/ci.yml/badge.svg)](https://github.com/wojd0/handy-menu-dashboard/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

A macOS menu bar app that tracks coding-agent usage at a glance: Cursor team spend and GitHub Copilot premium requests.

## Features

- **Cursor** — Shows your current billing-period spend against your team per-user monthly limit, fetched from Cursor dashboard APIs.
- **Menu bar summary** — Compact `$spent/limit` or percentage labels (toggle to percent view in settings).
- **Secure credentials** — Session cookies and PATs are stored in the macOS Keychain; the app runs sandboxed with outbound network only.
- **GitHub Copilot** — Tracks premium request usage for the current month against a configurable entitlement. (not yet implemented)

## Requirements

- macOS 26.3 or later
- Xcode 26.4 (Swift 6 concurrency, Swift Testing)

## Build and run

### Xcode

```bash
open handy-menu-dashboard.xcodeproj
```

Select the **handy-menu-dashboard** scheme and press **Cmd+R**.

### Command line

```bash
make build        # Release build (unsigned)
make install-dev  # Build and replace the app in ~/Applications
make test         # Run unit tests (unsigned)
make lint         # SwiftLint (optional, advisory)
```

Or run the scripts directly:

```bash
./build.sh
./install-dev.sh
./test.sh
./lint.sh
```

## Configuration

Open **Settings** from the dashboard popover (gear icon).

### Cursor

1. Open the **Cursor** tab and sign in via the embedded WebView.
2. After login, session cookies are saved to Keychain and used for API calls.
3. Toggle **Enabled** to include or exclude Cursor from the menu bar and refresh loop.

### GitHub Copilot

1. Create a [fine-grained personal access token](https://github.com/settings/tokens?type=beta) with read access to **Account** (billing/usage).
2. Enter your GitHub username and PAT on the **Copilot** tab.
3. Set your monthly premium-request entitlement (default **300**).
4. Toggle **Enabled** to include or exclude Copilot from the menu bar.

## Security

- Credentials never leave your machine except in authenticated HTTPS calls to Cursor and GitHub.
- Keychain keys are prefixed with `com.wojd0.dashboard.*`.
- App Sandbox is enabled with `com.apple.security.network.client` only.

## Contributing

Issues and pull requests are welcome on [GitHub](https://github.com/wojd0/handy-menu-dashboard).

## License

[Apache License 2.0](LICENSE)
