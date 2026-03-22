const vscode = require("vscode");
const { execSync } = require("child_process");
const https = require("https");
const fs = require("fs");
const path = require("path");
const os = require("os");

const CACHE_PATH = path.join(os.homedir(), ".claude", ".usage-cache.json");
const CACHE_TTL_MS = 60 * 1000; // 60 seconds

let statusBarItem;
let refreshInterval;
let retryTimeout;
let isFetching = false;
let rateLimitedUntil = 0;
let lastGoodText = "$(sync~spin) Claude: loading...";
let lastData = null;

function activate(context) {
  statusBarItem = vscode.window.createStatusBarItem(
    vscode.StatusBarAlignment.Right,
    50
  );
  statusBarItem.command = "claudeUsage.show";
  statusBarItem.tooltip = "Click to refresh";
  statusBarItem.show();
  context.subscriptions.push(statusBarItem);

  const showCmd = vscode.commands.registerCommand("claudeUsage.show", () => {
    showUsageDialog();
  });

  const refreshCmd = vscode.commands.registerCommand(
    "claudeUsage.refresh",
    () => {
      fetchFromApi();
    }
  );

  context.subscriptions.push(showCmd, refreshCmd);

  fetchUsage();
  startAutoRefresh();

  context.subscriptions.push(
    vscode.workspace.onDidChangeConfiguration((e) => {
      if (e.affectsConfiguration("claudeUsage.refreshIntervalMinutes")) {
        startAutoRefresh();
      }
    })
  );
}

function startAutoRefresh() {
  if (refreshInterval) clearInterval(refreshInterval);
  const minutes = vscode.workspace
    .getConfiguration("claudeUsage")
    .get("refreshIntervalMinutes", 5);
  refreshInterval = setInterval(fetchUsage, minutes * 60 * 1000);
}

function getToken() {
  try {
    const raw = execSync(
      'security find-generic-password -s "Claude Code-credentials" -w',
      { encoding: "utf-8", timeout: 5000 }
    );
    return JSON.parse(raw).claudeAiOauth.accessToken;
  } catch {
    return null;
  }
}

function readCache() {
  try {
    const raw = fs.readFileSync(CACHE_PATH, "utf-8");
    const cache = JSON.parse(raw);
    if (Date.now() - cache.timestamp < CACHE_TTL_MS) {
      return cache.data;
    }
  } catch {}
  return null;
}

function writeCache(data) {
  try {
    fs.writeFileSync(
      CACHE_PATH,
      JSON.stringify({ timestamp: Date.now(), data }, null, 2)
    );
  } catch {}
}

function formatResetShort(ts) {
  if (!ts) return "";
  const reset = new Date(ts);
  const now = new Date();
  const diffMs = reset - now;
  if (diffMs <= 0) return "resets now";
  const hours = Math.floor(diffMs / 3600000);
  const mins = Math.floor((diffMs % 3600000) / 60000);
  return `resets in ${hours}h ${mins}m`;
}

function showUsageDialog() {
  // Click just triggers a silent background refresh
  fetchUsage();
}

// fetchUsage: uses cache, for auto-refresh and initial load
function fetchUsage() {
  const cached = readCache();
  if (cached) {
    lastData = cached;
    updateStatusBar(cached);
    return;
  }
  fetchFromApi();
}

// fetchFromApi: always hits the API, for click refresh
function fetchFromApi(callback) {
  if (isFetching) return;
  if (Date.now() < rateLimitedUntil) {
    if (callback) callback();
    return;
  }
  isFetching = true;

  const token = getToken();
  if (!token) {
    statusBarItem.text = "$(warning) Claude: no token";
    statusBarItem.tooltip = "Could not read OAuth token from Keychain";
    isFetching = false;
    if (callback) callback();
    return;
  }

  statusBarItem.text = "$(sync~spin) Claude: refreshing...";

  const options = {
    hostname: "api.anthropic.com",
    path: "/api/oauth/usage",
    method: "GET",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      "anthropic-beta": "oauth-2025-04-20",
    },
  };

  const req = https.request(options, (res) => {
    let body = "";
    res.on("data", (chunk) => (body += chunk));
    res.on("end", () => {
      isFetching = false;
      try {
        if (res.statusCode === 429) {
          const retryAfter = Math.max(
            parseInt(res.headers["retry-after"] || "300", 10),
            30
          );
          rateLimitedUntil = Date.now() + retryAfter * 1000;
          statusBarItem.text = lastGoodText;
          if (retryTimeout) clearTimeout(retryTimeout);
          retryTimeout = setTimeout(fetchUsage, (retryAfter + 1) * 1000);
          if (callback) callback();
          return;
        }
        if (res.statusCode !== 200) {
          statusBarItem.text = "$(error) Claude: API " + res.statusCode;
          if (callback) callback();
          return;
        }
        const data = JSON.parse(body);
        lastData = data;
        writeCache(data);
        updateStatusBar(data);
        if (callback) callback();
      } catch {
        statusBarItem.text = "$(error) Claude: parse error";
        if (callback) callback();
      }
    });
  });

  req.on("error", () => {
    isFetching = false;
    statusBarItem.text = "$(error) Claude: offline";
    if (callback) callback();
  });

  req.setTimeout(10000, () => {
    req.destroy();
    isFetching = false;
    statusBarItem.text = "$(error) Claude: timeout";
    if (callback) callback();
  });

  req.end();
}

function updateStatusBar(data) {
  const fiveHour = data.five_hour?.utilization;
  const sevenDay = data.seven_day?.utilization;

  if (fiveHour == null && sevenDay == null) {
    statusBarItem.text = "$(error) Claude: no data";
    return;
  }

  const icon = getIcon(Math.max(fiveHour || 0, sevenDay || 0));
  const text = `${icon} Claude: 5h ${fiveHour ?? "?"}% | 7d ${sevenDay ?? "?"}%`;
  statusBarItem.text = text;
  lastGoodText = text;

  const buckets = [
    ["5-hour", data.five_hour],
    ["7-day total", data.seven_day],
    ["7-day Opus", data.seven_day_opus],
    ["7-day Sonnet", data.seven_day_sonnet],
  ];
  const rows = [];
  for (const [name, bucket] of buckets) {
    if (!bucket) continue;
    const u = bucket.utilization ?? 0;
    const reset = formatResetShort(bucket.resets_at);
    rows.push(`| ${name} | ${u}% | ${reset} |`);
  }
  const table = [
    "**Claude Code Usage**",
    "",
    "| Window | Usage | Resets |",
    "|--------|-------|--------|",
    ...rows,
    "",
    "_Click to refresh_",
  ].join("\n");
  const md = new vscode.MarkdownString(table, true);
  md.isTrusted = true;
  md.supportHtml = true;
  statusBarItem.tooltip = md;

  if ((fiveHour || 0) >= 90 || (sevenDay || 0) >= 90) {
    statusBarItem.backgroundColor = new vscode.ThemeColor(
      "statusBarItem.errorBackground"
    );
  } else if ((fiveHour || 0) >= 70 || (sevenDay || 0) >= 70) {
    statusBarItem.backgroundColor = new vscode.ThemeColor(
      "statusBarItem.warningBackground"
    );
  } else {
    statusBarItem.backgroundColor = undefined;
  }
}

function getIcon(utilization) {
  if (utilization >= 90) return "$(flame)";
  if (utilization >= 70) return "$(warning)";
  if (utilization >= 40) return "$(dashboard)";
  return "$(check)";
}

function deactivate() {
  if (refreshInterval) clearInterval(refreshInterval);
}

module.exports = { activate, deactivate };
