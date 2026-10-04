# Claude Dash

A macOS menu bar app that shows your Claude usage at a glance.

The menu bar shows `session% · weekly%`. Click it to see:

- **Limits**: the current 5-hour session and the weekly limit, each with a progress bar and its reset time. Model-specific weekly limits (Opus/Sonnet) appear if your plan has them.
- **Weekly breakdown** by surface (Claude Code, Chats, Cowork).
- **Today**: tokens and messages for each model.
- **Last 7 days**: a chart and per-model totals. You can switch between all tokens, tokens without cache reads, or output only.

## Getting started

### Requirements

- macOS 14 (Sonoma) or later
- Xcode or the Xcode Command Line Tools (`xcode-select --install`)
- [Claude Code](https://claude.com/claude-code), logged in with a Claude subscription (Pro/Max/Team)

### Install

1. Log in to Claude Code once if you haven't already:

       claude    # then follow the /login prompts

2. Clone and build:

       git clone <this-repo> claude-dash
       cd claude-dash
       ./build.sh install

   This builds `ClaudeDash.app`, copies it to `~/Applications` and launches it. A gauge icon appears in the menu bar.

3. Optional: tick **Open at login** at the bottom of the dropdown.

To update, pull the latest changes and run `./build.sh install` again. To uninstall, quit the app and delete `~/Applications/ClaudeDash.app`.

## How it works

The app uses whichever account is **logged into Claude Code on this Mac**.

| Data | Source | Scope | Refresh |
|---|---|---|---|
| Limits and reset times | `api.anthropic.com/api/oauth/usage` (the endpoint behind Claude Code's `/usage`) | Whole account, all devices and apps | every 5 min |
| Token counts per day/model | Claude Code transcripts in `~/.claude/projects` | Claude Code on this Mac only | every 60 s |

- The login token is read from the macOS Keychain (`Claude Code-credentials`) through `/usr/bin/security`, so no Keychain prompt appears. The app never refreshes or stores the token itself.
- The usage endpoint is undocumented and could change.

## Troubleshooting

- **"Login token expired"**: run `claude` once to refresh the login, then click refresh in the dropdown.
- **"No Claude Code login found"**: log in to Claude Code with a subscription account. API-key logins have no plan limits to show; the local token counts still work.
- **Debugging**: `~/Applications/ClaudeDash.app/Contents/MacOS/ClaudeDash --dump` prints the parsed data to the terminal.

## Project layout

```
Sources/ClaudeDash/
  App.swift            app entry, menu bar label, refresh timers
  UsageAPI.swift       live limits from the usage endpoint
  LocalUsage.swift     token totals from local transcripts
  DashboardView.swift  the dropdown UI
Resources/Info.plist   menu-bar-only app bundle settings
build.sh               build (and optionally install) the .app
```
