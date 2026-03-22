# Claude Code Usage

Monitor your Claude Code API usage from VS Code, macOS menu bar, or the terminal.

All tools share a cache at `~/.claude/.usage-cache.json` (60s TTL) to avoid hitting the API rate limit (~6 requests per 5 minutes).

## Requirements

- macOS (reads OAuth token from Keychain)
- Active Claude Code session (for OAuth token)

---

## VS Code Extension

Shows usage in the status bar. Hover for details, click to refresh.

### Features

- **Status bar** shows 5-hour and 7-day utilization
- **Hover tooltip** with detailed breakdown and reset times
- **Click to refresh** from API
- **Auto-refresh** every 5 minutes (configurable)
- **Rate limit protection** with automatic retry
- Color-coded: yellow at 70%, red at 90%

### Install

```bash
git clone https://github.com/sevenuphome/claude-usage-vscode.git
ln -sf "$(pwd)/claude-usage-vscode" ~/.vscode/extensions/claude-usage-vscode-0.1.0
```

Reload VS Code.

### Settings

| Setting | Default | Description |
|---------|---------|-------------|
| `claudeUsage.refreshIntervalMinutes` | 5 | Auto-refresh interval in minutes |

---

## macOS Menu Bar (SwiftBar)

Shows usage in the macOS menu bar with SF Symbols, color-coded progress dots, and reset times.

### Install

1. Install SwiftBar:

```bash
brew install --cask swiftbar
```

2. Set plugin directory and copy the plugin:

```bash
mkdir -p ~/Library/Application\ Support/SwiftBar/Plugins
cp swiftbar-plugin/claude-usage.5m.sh ~/Library/Application\ Support/SwiftBar/Plugins/
chmod +x ~/Library/Application\ Support/SwiftBar/Plugins/claude-usage.5m.sh
```

3. Launch SwiftBar. If prompted for a plugin directory, select `~/Library/Application Support/SwiftBar/Plugins`.

### What you see

- Menu bar: `🟢 5h:17% 7d:68%` (color changes by severity)
- Click to expand: detailed view with progress bars and reset times
- Auto-refreshes every 5 minutes

---

## CLI Script

```bash
./claude-usage.sh
```

Output:

```
  5-hour         ███░░░░░░░░░░░░░░░░░ 17%       resets Mar 22 14:00 UTC (in 2h 0m)
  7-day total    █████████████░░░░░░░ 68%       resets Mar 22 22:00 UTC (in 10h 0m)
  7-day Sonnet   ░░░░░░░░░░░░░░░░░░░░ 2%        resets Mar 23 18:00 UTC (in 30h 0m)
  (source: cache)
```

Shows `(source: api)` or `(source: cache)` so you know if it hit the API.

---

## How it works

All tools call `GET https://api.anthropic.com/api/oauth/usage` using the OAuth token from macOS Keychain (`security find-generic-password -s "Claude Code-credentials" -w`). Results are cached at `~/.claude/.usage-cache.json` for 60 seconds. The API rate limit is ~6 requests per 5-minute window, with a 5-minute cooldown on 429.
