# Claude Code Usage - VS Code Extension

Shows your Claude Code API usage in the VS Code status bar.

## Features

- **Status bar** shows 5-hour and 7-day utilization at a glance
- **Hover tooltip** shows detailed breakdown with reset times
- **Click to refresh** fetches latest data from API
- **Auto-refresh** every 5 minutes (configurable)
- **Shared cache** (`~/.claude/.usage-cache.json`) prevents rate limiting across extension, CLI, and scripts
- **Rate limit protection** with automatic retry after cooldown
- Color-coded: yellow at 70%, red at 90%

## Installation

### From source (symlink)

```bash
ln -sf /path/to/claude-usage-vscode ~/.vscode/extensions/claude-usage-vscode-0.1.0
```

Then reload VS Code.

## Requirements

- macOS (reads OAuth token from Keychain)
- Active Claude Code session (for OAuth token)

## Settings

| Setting | Default | Description |
|---------|---------|-------------|
| `claudeUsage.refreshIntervalMinutes` | 5 | Auto-refresh interval in minutes |

## How it works

Calls `GET https://api.anthropic.com/api/oauth/usage` using your Claude Code OAuth token from macOS Keychain. Results are cached for 60 seconds at `~/.claude/.usage-cache.json` to stay within the API rate limit (~6 requests per 5 minutes).
