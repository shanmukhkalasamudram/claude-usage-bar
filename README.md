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

## Install

### Option A — download the app (no toolchain needed)

1. Download `ClaudeUsageBar-x.y.z.zip` from the [Releases](../../releases) page and unzip it.
2. This app is **open-source and not notarized** (no paid Apple Developer
   certificate — see [Why it's unsigned](#why-its-unsigned)). macOS quarantines
   downloaded unsigned apps, so clear the quarantine flag once:
   ```sh
   xattr -dr com.apple.quarantine ~/Downloads/ClaudeUsageBar.app
   ```
   *(Or, without the terminal: right-click the app → **Open** → **Open** in the
   dialog. You only do this once.)*
3. Move it to Applications and launch it:
   ```sh
   mv ~/Downloads/ClaudeUsageBar.app /Applications/
   open /Applications/ClaudeUsageBar.app
   ```
4. The first time it reads your usage, macOS shows a **Keychain prompt**
   (*"…wants to use information stored in Claude Code-credentials"*). Click
   **Always Allow**. It never asks again.

**Verify your download** (optional): each release lists a SHA-256. Check it with
`shasum -a 256 ClaudeUsageBar-x.y.z.zip`.

### Option B — build from source

```sh
git clone <this repo> && cd claude-usage-bar
swift scripts/make-icon.swift           # generate the app icon (once)
scripts/build-app.sh                    # build dist/ClaudeUsageBar.app
cp -R dist/ClaudeUsageBar.app /Applications/
open /Applications/ClaudeUsageBar.app
scripts/install-login-item.sh           # optional: launch at login
```

Building it yourself is the most trustworthy path — you run exactly the source
you can read here.

### Why it's unsigned

Distributing a *notarized* Mac app requires a paid Apple Developer membership.
This project skips that on purpose and ships the source plus a downloadable
build instead, so the one-time quarantine step above is the trade-off. Because
the ad-hoc signature changes on every rebuild, the Keychain "Always Allow" grant
is tied to a specific build — reinstalling a new build re-prompts once. A stable
installed copy in `/Applications` that you don't rebuild only ever asks once.

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

## Privacy & security

Your data stays on your machine. Specifically:

- **One network destination, and it's Anthropic's own.** The app's only outbound
  request is a GET to `https://api.anthropic.com/api/oauth/usage` — the same
  server Claude Code already talks to — to read *your* usage numbers. The host is
  verified before every request; the client will not contact any other host.
- **No third parties.** No analytics, no telemetry, no crash reporting, no ad or
  tracking SDKs, no "phone home." The app has zero dependencies beyond Apple's
  own frameworks.
- **Your token never leaves your Mac except to Anthropic.** It's read from the
  macOS Keychain per request, sent only to the verified Anthropic host, and is
  never written to disk or logs. HTTP redirects are refused, so the credential
  can't be replayed to another host.
- **Nothing is persisted.** The network layer uses an ephemeral session (no disk
  cache, no cookies). The app stores no files, no history, no config.
- **The `--tokens` CLI mode is fully offline** — it only reads your local
  `~/.claude` transcripts and makes no network calls at all.

In short: the widget reads your own usage from Anthropic with your own
credentials, and does nothing else. The source here is the whole story — audit
`Sources/ClaudeUsageKit/Limits/` to confirm it.

## License

MIT — see [LICENSE](LICENSE).
