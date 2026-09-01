#!/bin/bash
# Snapshot this repo's GitHub traffic into tracking/traffic.csv.
#
# GitHub keeps only 14 days of traffic data and nothing accumulates it for you,
# so this has to run regularly or the history is gone for good.
#
# Safe to rerun and safe to miss days: each run rewrites every day in the window
# it can see, so any gap shorter than 14 days heals itself.
#
# Runs in CI (see .github/workflows/traffic.yml) and locally. Needs gh, and the
# traffic API needs push access to the repo.

set -euo pipefail

REPO="${REPO:-1507078/openwrt-one-skills}"
CSV="${CSV:-$(cd "$(dirname "$0")" && pwd)/traffic.csv}"

command -v gh >/dev/null || { echo "gh not found" >&2; exit 1; }

VIEWS=$(gh api "repos/$REPO/traffic/views")
CLONES=$(gh api "repos/$REPO/traffic/clones")
REPOINFO=$(gh api "repos/$REPO")
ISSUES=$(gh api "repos/$REPO/issues?state=all&per_page=100" --jq 'length')

VIEWS="$VIEWS" CLONES="$CLONES" REPOINFO="$REPOINFO" ISSUES="$ISSUES" CSV="$CSV" \
python3 <<'PY'
import csv, json, os
from datetime import datetime, timezone

views  = json.loads(os.environ["VIEWS"])
clones = json.loads(os.environ["CLONES"])
info   = json.loads(os.environ["REPOINFO"])
issues = int(os.environ["ISSUES"])
csv_path = os.environ["CSV"]

HEADER = ["date", "views", "unique_visitors", "clones",
          "unique_cloners", "stars", "forks", "issues"]

def by_day(payload, key):
    return {r["timestamp"][:10]: (r["count"], r["uniques"])
            for r in payload.get(key, [])}

v, c = by_day(views, "views"), by_day(clones, "clones")

rows = {}
if os.path.exists(csv_path):
    with open(csv_path, newline="", encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            if row.get("date"):
                rows[row["date"]] = row

for day in sorted(set(v) | set(c)):
    vc, vu = v.get(day, (0, 0))
    cc, cu = c.get(day, (0, 0))
    prev = rows.get(day, {})
    rows[day] = {
        "date": day,
        "views": vc, "unique_visitors": vu,
        "clones": cc, "unique_cloners": cu,
        # Point-in-time counts stay on the day they were observed.
        "stars":  prev.get("stars", ""),
        "forks":  prev.get("forks", ""),
        "issues": prev.get("issues", ""),
    }

today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
row = rows.setdefault(today, {"date": today, "views": 0, "unique_visitors": 0,
                              "clones": 0, "unique_cloners": 0})
row["stars"]  = info.get("stargazers_count", 0)
row["forks"]  = info.get("forks_count", 0)
row["issues"] = issues

with open(csv_path, "w", newline="", encoding="utf-8") as fh:
    w = csv.DictWriter(fh, fieldnames=HEADER)
    w.writeheader()
    for day in sorted(rows):
        w.writerow({k: rows[day].get(k, "") for k in HEADER})

print(f"{len(rows)} day(s) recorded; today stars={row['stars']} "
      f"forks={row['forks']} issues={row['issues']}")
PY
