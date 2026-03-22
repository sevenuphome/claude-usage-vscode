#!/bin/bash
# Fetch Claude Code usage via OAuth API (macOS Keychain)
# Uses shared cache at ~/.claude/.usage-cache.json (60s TTL)

CACHE_FILE="$HOME/.claude/.usage-cache.json"
CACHE_TTL=60  # seconds

# Check cache first
if [ -f "$CACHE_FILE" ]; then
  CACHE_AGE=$(python3 -c "
import json, time
try:
    c = json.load(open('$CACHE_FILE'))
    print(int(time.time() * 1000 - c['timestamp']))
except: print(999999999)
")
  if [ "$CACHE_AGE" -lt "$((CACHE_TTL * 1000))" ]; then
    RESPONSE=$(python3 -c "import json; print(json.dumps(json.load(open('$CACHE_FILE'))['data']))")
    SOURCE="cache"
  fi
fi

# Fetch from API if no cache hit
if [ -z "$RESPONSE" ]; then
  TOKEN=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['claudeAiOauth']['accessToken'])" 2>/dev/null)

  if [ -z "$TOKEN" ]; then
    echo "Error: Could not retrieve OAuth token from Keychain" >&2
    exit 1
  fi

  RESPONSE=$(curl -s https://api.anthropic.com/api/oauth/usage \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -H "anthropic-beta: oauth-2025-04-20")

  # Check for errors
  if echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if 'error' in d else 1)" 2>/dev/null; then
    echo "API error: $RESPONSE" >&2
    exit 1
  fi

  # Write cache
  python3 -c "
import json, time
data = json.loads('''$RESPONSE''')
with open('$CACHE_FILE', 'w') as f:
    json.dump({'timestamp': int(time.time() * 1000), 'data': data}, f, indent=2)
"
  SOURCE="api"
fi

# Pretty print
python3 -c "
import json
from datetime import datetime, timezone

data = json.loads('''$RESPONSE''')

def fmt_reset(ts):
    if not ts: return '-'
    dt = datetime.fromisoformat(ts)
    now = datetime.now(timezone.utc)
    diff = dt - now
    hours = int(diff.total_seconds() // 3600)
    mins = int((diff.total_seconds() % 3600) // 60)
    return f'{dt:%b %d %H:%M UTC} (in {hours}h {mins}m)'

def fmt_util(u):
    if u is None: return '-'
    bar_len = 20
    filled = int(u / 100 * bar_len)
    bar = '█' * filled + '░' * (bar_len - filled)
    return f'{bar} {u:.0f}%'

print()
rows = [
    ('5-hour', data.get('five_hour')),
    ('7-day total', data.get('seven_day')),
    ('7-day Opus', data.get('seven_day_opus')),
    ('7-day Sonnet', data.get('seven_day_sonnet')),
]

for name, bucket in rows:
    if bucket is None: continue
    print(f'  {name:14s} {fmt_util(bucket.get(\"utilization\")):30s} resets {fmt_reset(bucket.get(\"resets_at\"))}')

extra = data.get('extra_usage', {})
if extra.get('is_enabled'):
    print(f'  {\"Extra usage\":14s} {fmt_util(extra.get(\"utilization\")):30s} limit: \${extra.get(\"monthly_limit\", \"?\")}')
print(f'  (source: $SOURCE)')
print()
"
