# Claude Usage Bar

A tiny native macOS **menu bar app** that shows your Claude subscription limits
at a glance — how much of your current **5-hour session** and **weekly** limit
you've used, and when each resets — without opening anything.

```
  ⛽ 45%          ← lives in your menu bar

  ┌──────────────────────────────────┐
  │ ▮ Claude Usage   Updated 11:04 PM │
  │ ┌──────────────────────────────┐  │
  │ │ Current session         45%  │  │
  │ │ 5-hour limit                 │  │
  │ │ ▰▰▰▰▰▱▱▱▱▱▱▱▱▱▱▱▱▱          │  │
  │ │ 🕐 Resets in 2h 14m · 6:59AM │  │
  │ └──────────────────────────────┘  │
  │ ┌──────────────────────────────┐  │
  │ │ This week               25%  │  │
  │ │ ▰▰▰▱▱▱▱▱▱▱  Resets 2d 22h    │  │
  │ └──────────────────────────────┘  │
  └──────────────────────────────────┘
```

## How it works

It calls the same endpoint Claude's `/usage` uses
(`https://api.anthropic.com/api/oauth/usage`), reusing the OAuth token that
**Claude Code already stores in your macOS Keychain** — so there's no separate
login. The response is the authoritative limit percentage and reset time,
straight from Anthropic (not an estimate).

The endpoint is a **metadata call**: it returns no model output, consumes no
tokens, and does not count against any limit — so the widget refreshes for free
(once a minute; reset countdowns tick every second locally in between).

## Features

- **Session (5h) and weekly (7d) limits** with exact percentages and reset times.
- **Opus-specific weekly limit** too, when your plan has one.
- **Menu bar percentage** at a glance, color-coded green → yellow → orange → red.
- **Zero configuration** — reuses your existing Claude Code login.
- **Free & instant** — one tiny metadata request, no token cost, no log scanning.

## Requirements

- macOS 14+
- Logged into Claude Code (so the token is in your Keychain)
- Swift toolchain to build (Xcode or Command Line Tools: `xcode-select --install`)

## Build, run & install

```sh
scripts/build-app.sh                    # build dist/ClaudeUsageBar.app
cp -R dist/ClaudeUsageBar.app /Applications/
open /Applications/ClaudeUsageBar.app
scripts/install-login-item.sh           # optional: launch at login
```

The first time it reads your token, macOS shows a **Keychain prompt** — click
**Always Allow** and it never asks again (as long as you don't rebuild the app;
the ad-hoc signature changes on each build).

## The CLI

The same engine ships as a headless CLI:

```sh
swift run usagectl            # session + weekly limits (from Anthropic)
swift run usagectl --json     # machine-readable
swift run usagectl --tokens   # bonus: token usage computed from local logs
```

## Architecture

```
Sources/
  ClaudeUsageKit/            # UI-free core, shared by the app and CLI
    Limits/                  #   the product: usage limits
      KeychainTokenReader    #     read the Claude Code OAuth token
      LimitsClient           #     fetch + decode the usage endpoint
      UsageLimits            #     session / week / opus-week models
    Parsing/ Analytics/      #   bonus: token stats parsed from ~/.claude logs
    Formatting.swift
  ClaudeUsageBar/            # the menu bar app (SwiftUI MenuBarExtra)
  usagectl/                  # the CLI
Tests/                       # XCTest suite for the core (run with `swift test`)
```

## If the login expires

Rare, since Claude Code keeps its token fresh. If it happens, the popover says
so — run any Claude Code command to refresh the token and the widget picks it up
on the next fetch.

## Running the tests

```sh
swift test
```

> `swift test` needs XCTest, which ships with **Xcode**. With only the Command
> Line Tools, the app and CLI build fine but the test target won't run locally —
> CI (GitHub's macOS runners) has Xcode and runs them.

## Privacy

Everything stays on your Mac. The only network call is to Anthropic's own usage
endpoint, authenticated with your existing Claude Code token. No third parties,
no telemetry.

## License

MIT — see [LICENSE](LICENSE).
