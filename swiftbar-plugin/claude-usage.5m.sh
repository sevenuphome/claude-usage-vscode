#!/bin/bash
# <bitbar.title>Claude Code Usage</bitbar.title>
# <bitbar.version>v0.3</bitbar.version>
# <bitbar.author>sevenuphome</bitbar.author>
# <bitbar.desc>Shows Claude Code API usage in the menu bar</bitbar.desc>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
# <swiftbar.hideSwiftBar>true</swiftbar.hideSwiftBar>

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

# Status emoji for menu bar
if max_u >= 90:
    icon = "🔴"
elif max_u >= 70:
    icon = "🟡"
elif max_u >= 40:
    icon = "🟠"
else:
    icon = "🟢"

# ── Menu bar title (keep simple — no SF Symbols for compatibility) ──
print(f"{icon} {five_u:.0f}% | {seven_u:.0f}% | size=12")
print("---")

# ── Header ──
print("☁ Claude Code Usage | size=15 color=#FFFFFF")
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
        return f'resets in {hours}h {mins}m'
    return f'resets in {mins}m'

def color_for(u):
    if u >= 90: return "#FF453A"
    if u >= 70: return "#FFD60A"
    if u >= 40: return "#FF9F0A"
    return "#30D158"

def icon_for(u):
    if u >= 90: return "🔥"
    if u >= 70: return "⚠️"
    if u >= 40: return "📊"
    return "✅"

def bar(u):
    total = 20
    filled = round(u / 100 * total)
    return '●' * filled + '○' * (total - filled)

buckets = [
    ('5-hour window', data.get('five_hour')),
    ('7-day rolling', data.get('seven_day')),
    ('7-day Opus', data.get('seven_day_opus')),
    ('7-day Sonnet', data.get('seven_day_sonnet')),
]

for name, bucket in buckets:
    if bucket is None:
        continue
    u = bucket.get('utilization') or 0
    c = color_for(u)
    reset = fmt_reset(bucket.get('resets_at'))

    print(f"{icon_for(u)} {name} | size=13 color=#FFFFFF")
    print(f"  {bar(u)}  {u:.0f}% | font=Menlo size=12 color={c}")
    if reset:
        print(f"  ⏱ {reset} | size=11 color=#8E8E93")
    print("---")

# ── Footer ──
print("↻ Refresh | refresh=true size=12 color=#8E8E93")

update_url = "https://raw.githubusercontent.com/sevenuphome/claude-usage-vscode/main/swiftbar-plugin/claude-usage.5m.sh"
plugin_path = "$HOME/Library/Application Support/SwiftBar/Plugins/claude-usage.5m.sh"
update_cmd = f'curl -sL {update_url} -o "{plugin_path}" && chmod +x "{plugin_path}"'
print(f"↓ Update plugin | bash=/bin/bash param1=-c param2={update_cmd!r} terminal=false refresh=true size=12 color=#8E8E93")
PYEOF
