#!/usr/bin/env python3
"""Find candidate Python repos via the GitHub API (replacement for SEART-GHS).

Usage:
    source ~/.nca_github
    python find_repos.py --since 2026-05-15 --min-stars 500 --max-repos 300 --out repos_candidates.csv

For each repo found it adds:
  - python_share: fraction of the code that is Python (skip C/C++-heavy repos)
  - has_build_file: pyproject.toml or setup.py at the root (pip-installable)
  - linked_prs: merged PRs since --since that are linked to an issue (~ SWE-bench candidates)
Output is sorted by linked_prs (most promising first).
"""
import argparse
import csv
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.github.com"
TOKEN = os.environ.get("GITHUB_TOKEN")
if not TOKEN:
    sys.exit("GITHUB_TOKEN missing: run `source ~/.nca_github` first")


def get(path, params=None, search=False):
    url = API + path + ("?" + urllib.parse.urlencode(params) if params else "")
    req = urllib.request.Request(url, headers={
        "Authorization": f"Bearer {TOKEN}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    })
    for attempt in range(5):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                if search:
                    time.sleep(2.1)  # search API: 30 requests/minute
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            if e.code in (403, 429):  # rate limit: wait until reset
                reset = int(e.headers.get("X-RateLimit-Reset", time.time() + 60))
                wait = max(reset - time.time(), 5) + 1
                print(f"  rate limit, waiting {wait:.0f}s", file=sys.stderr)
                time.sleep(wait)
                continue
            if e.code >= 500:
                time.sleep(5 * (attempt + 1))
                continue
            raise
        except urllib.error.URLError:
            time.sleep(5 * (attempt + 1))
    raise RuntimeError(f"giving up on {url}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", default="2026-05-15", help="last push / merged PRs after this date (YYYY-MM-DD)")
    ap.add_argument("--min-stars", type=int, default=500)
    ap.add_argument("--max-repos", type=int, default=300, help="max repos to inspect (search returns at most 1000)")
    ap.add_argument("--out", default="repos_candidates.csv")
    a = ap.parse_args()

    q = f"language:python stars:>={a.min_stars} pushed:>={a.since} fork:false archived:false"
    repos, page = [], 1
    while len(repos) < a.max_repos and page <= 10:
        res = get("/search/repositories", {"q": q, "sort": "stars", "order": "desc",
                                           "per_page": 100, "page": page}, search=True)
        items = res.get("items", [])
        if page == 1:
            print(f"search total_count={res.get('total_count')}", file=sys.stderr)
        if not items:
            break
        repos += items
        page += 1
    repos = repos[: a.max_repos]

    rows = []
    for i, r in enumerate(repos, 1):
        name = r["full_name"]
        langs = get(f"/repos/{name}/languages") or {}
        share = langs.get("Python", 0) / max(sum(langs.values()), 1)
        has_build = any(get(f"/repos/{name}/contents/{f}") is not None
                        for f in ("pyproject.toml", "setup.py"))
        linked = None
        if share >= 0.6 and has_build:  # only spend search calls on plausible repos
            res = get("/search/issues", {"q": f"repo:{name} is:pr is:merged linked:issue merged:>={a.since}",
                                         "per_page": 1}, search=True)
            linked = res.get("total_count", 0)
        rows.append({
            "name": name,
            "stars": r["stargazers_count"],
            "open_issues_and_prs": r["open_issues_count"],
            "created_at": r["created_at"][:10],
            "pushed_at": r["pushed_at"][:10],
            "python_share": round(share, 2),
            "has_build_file": has_build,
            "linked_prs": linked if linked is not None else "",
            "url": r["html_url"],
        })
        print(f"[{i}/{len(repos)}] {name} py={share:.2f} build={has_build} linked_prs={linked}", file=sys.stderr)

    rows.sort(key=lambda x: x["linked_prs"] if x["linked_prs"] != "" else -1, reverse=True)
    with open(a.out, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    print(f"wrote {len(rows)} repos to {a.out}", file=sys.stderr)


if __name__ == "__main__":
    main()
