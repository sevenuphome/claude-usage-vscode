#!/bin/bash
# <bitbar.title>Claude Code Usage</bitbar.title>
# <bitbar.version>v0.4</bitbar.version>
# <bitbar.author>sevenuphome</bitbar.author>
# <bitbar.desc>Shows Claude Code API usage in the menu bar</bitbar.desc>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
# <swiftbar.hideSwiftBar>true</swiftbar.hideSwiftBar>

VERSION="0.4"
PLUGIN_URL="https://raw.githubusercontent.com/sevenuphome/claude-usage-vscode/main/swiftbar-plugin/claude-usage.5m.sh"
PLUGIN_PATH="$HOME/Library/Application Support/SwiftBar/Plugins/claude-usage.5m.sh"

# Handle --update flag
if [ "$1" = "--update" ]; then
  REMOTE=$(curl -sL "$PLUGIN_URL")
  REMOTE_VER=$(echo "$REMOTE" | grep '^VERSION=' | head -1 | cut -d'"' -f2)
  if [ "$VERSION" = "$REMOTE_VER" ]; then
    osascript -e "display dialog \"You are on the latest version (v$VERSION)\" with title \"Claude Usage\" buttons {\"OK\"} default button \"OK\" with icon note"
  else
    echo "$REMOTE" > "$PLUGIN_PATH"
    chmod +x "$PLUGIN_PATH"
    osascript -e "display dialog \"Updated from v$VERSION to v$REMOTE_VER\" with title \"Claude Usage\" buttons {\"OK\"} default button \"OK\" with icon note"
  fi
  exit 0
fi

CACHE_FILE="$HOME/.claude/.usage-cache.json"
CACHE_TTL=60  # seconds

get_data() {
  if [ -f "$CACHE_FILE" ]; then
    CACHE_AGE=$(python3 -c "
import json, time
try:
    c = json.load(open('$CACHE_FILE'))
    print(int(time.time() * 1000 - c['timestamp']))
except: print(999999999)
" 2>/dev/null)
    if [ "$CACHE_AGE" -lt "$((CACHE_TTL * 1000))" ]; then
      python3 -c "import sys,json; print(json.dumps(json.load(open('$CACHE_FILE'))['data']))" 2>/dev/null
      return
    fi
  fi

  TOKEN=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['claudeAiOauth']['accessToken'])" 2>/dev/null)
  if [ -z "$TOKEN" ]; then return; fi

  RESPONSE=$(curl -s --max-time 10 https://api.anthropic.com/api/oauth/usage \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -H "anthropic-beta: oauth-2025-04-20")

  if echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if 'error' in d else 1)" 2>/dev/null; then
    if [ -f "$CACHE_FILE" ]; then
      python3 -c "import sys,json; print(json.dumps(json.load(open('$CACHE_FILE'))['data']))" 2>/dev/null
    fi
    return
  fi

  python3 -c "
import json, time
data = json.loads('''$RESPONSE''')
with open('$CACHE_FILE', 'w') as f:
    json.dump({'timestamp': int(time.time() * 1000), 'data': data}, f, indent=2)
" 2>/dev/null

  echo "$RESPONSE"
}

DATA=$(get_data)

if [ -z "$DATA" ]; then
  echo "⚠ Claude | size=13"
  echo "---"
  echo "No usage data available | color=#999999 size=12"
  echo "Check that Claude Code is signed in | color=#666666 size=11"
  exit 0
fi

CLAUDE_USAGE_DATA="$DATA" python3 << 'PYEOF'
import json, os
from datetime import datetime, timezone

data = json.loads(os.environ["CLAUDE_USAGE_DATA"])

five = data.get('five_hour') or {}
seven = data.get('seven_day') or {}
five_u = five.get('utilization') or 0
seven_u = seven.get('utilization') or 0
max_u = max(five_u, seven_u)

# ── Menu bar title ──
print(f"☁ {five_u:.0f}% | size=12")
print("---")

def fmt_reset(ts):
    if not ts:
        return ''
    dt = datetime.fromisoformat(ts)
    now = datetime.now(timezone.utc)
    diff = dt - now
    if diff.total_seconds() <= 0:
        return 'resets now'
    hours = int(diff.total_seconds() // 3600)
    mins = int((diff.total_seconds() % 3600) // 60)
    if hours > 0:
        return f'{hours}h {mins}m until reset'
    return f'{mins}m until reset'

buckets = [
    ('5-hour', data.get('five_hour')),
    ('7-day', data.get('seven_day')),
    ('7-day Opus', data.get('seven_day_opus')),
    ('7-day Sonnet', data.get('seven_day_sonnet')),
]

# ── Header row like Battery: "Claude Code Usage     9%" ──
# Use 7-day as the main number (most important limit)
print(f"Claude Code Usage \t{seven_u:.0f}% | size=14")

# ── Subtitle info ──
active = [(n, b) for n, b in buckets if b is not None]
if active:
    main_name, main_bucket = active[0]
    reset = fmt_reset(main_bucket.get('resets_at'))
    print(f"5-hour: {five_u:.0f}%  ·  7-day: {seven_u:.0f}% | size=12 color=gray")
    if reset:
        print(f"{reset} | size=12 color=gray")

print("---")

# ── Usage Windows (like Energy Mode section) ──
print("Usage Windows | size=13 disabled=true")

for name, bucket in buckets:
    if bucket is None:
        continue
    u = bucket.get('utilization') or 0
    reset = fmt_reset(bucket.get('resets_at'))
    r = reset if reset else ''
    print(f"{name}\t{u:.0f}% | size=13")
    if r:
        print(f"--{r} | size=12 color=gray")

print("---")
print("Refresh | refresh=true size=13")

print("Check for Updates… | bash=$0 param1=--update terminal=false refresh=true size=13")
print("---")
print("Quit Claude Usage | bash=/bin/bash param1=-c param2='osascript -e \"tell application \\\"SwiftBar\\\" to quit\"' terminal=false size=13")
PYEOF
