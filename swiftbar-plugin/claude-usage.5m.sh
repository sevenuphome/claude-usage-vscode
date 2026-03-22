#!/bin/bash
# <bitbar.title>Claude Code Usage</bitbar.title>
# <bitbar.version>v0.2</bitbar.version>
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
      cat "$CACHE_FILE" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin)['data']))" 2>/dev/null
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
      cat "$CACHE_FILE" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin)['data']))" 2>/dev/null
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
  echo "⬡ Claude | sfSymbol=exclamationmark.triangle size=13"
  echo "---"
  echo "No usage data available | color=#999999 size=12"
  echo "Check that Claude Code is signed in | color=#666666 size=11"
  exit 0
fi

python3 <<PYEOF
import json
from datetime import datetime, timezone

FONT = "SF Pro Text"
FONT_BOLD = "SF Pro Display-Semibold"
FONT_MONO = "Menlo-Bold"

data = json.loads('''$DATA''')

five = data.get('five_hour', {})
seven = data.get('seven_day', {})
five_u = five.get('utilization', 0) if five else 0
seven_u = seven.get('utilization', 0) if seven else 0
max_u = max(five_u or 0, seven_u or 0)

# Color palette
if max_u >= 90:
    accent = "#FF453A"    # red
    sf = "flame.fill"
elif max_u >= 70:
    accent = "#FFD60A"    # yellow
    sf = "exclamationmark.triangle.fill"
elif max_u >= 40:
    accent = "#FF9F0A"    # orange
    sf = "gauge.medium"
else:
    accent = "#30D158"    # green
    sf = "checkmark.circle.fill"

# ── Menu bar title ──
print(f":bolt.fill: {five_u:.0f}% | {seven_u:.0f}% | sfSymbol={sf} sfColor={accent} size=12 font={FONT}")
print("---")

# ── Header ──
print(f"Claude Code Usage | sfSymbol=sparkles size=15 font={FONT_BOLD} color=#FFFFFF")
print("---")

def fmt_reset(ts):
    if not ts: return ''
    dt = datetime.fromisoformat(ts)
    now = datetime.now(timezone.utc)
    diff = dt - now
    if diff.total_seconds() <= 0: return 'resets now'
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

def bar(u):
    total = 20
    filled = round(u / 100 * total)
    return '●' * filled + '○' * (total - filled)

def sf_for(u):
    if u >= 90: return "flame.fill"
    if u >= 70: return "exclamationmark.triangle.fill"
    if u >= 40: return "gauge.medium"
    return "checkmark.circle.fill"

buckets = [
    ('5-hour window', '5h', data.get('five_hour')),
    ('7-day rolling', '7d', data.get('seven_day')),
    ('7-day Opus', 'opus', data.get('seven_day_opus')),
    ('7-day Sonnet', 'sonnet', data.get('seven_day_sonnet')),
]

for name, short, bucket in buckets:
    if bucket is None:
        continue
    u = bucket.get('utilization', 0) or 0
    c = color_for(u)
    reset = fmt_reset(bucket.get('resets_at'))
    sym = sf_for(u)

    print(f"{name} | sfSymbol={sym} sfColor={c} size=13 font={FONT} color=#FFFFFF")
    print(f"{bar(u)}  {u:.0f}% | font={FONT_MONO} size=11 color={c}")
    if reset:
        print(f"  ⏱ {reset} | size=10 color=#8E8E93 font={FONT}")
    print("---")

# ── Footer ──
print(f"↻ Refresh | refresh=true sfSymbol=arrow.clockwise size=12 color=#8E8E93 font={FONT}")
PYEOF
