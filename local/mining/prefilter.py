#!/usr/bin/env python3
"""Pre-filter SWE-bench candidate task instances.

Reads tasks/*-task-instances.jsonl (output of `swebench dataset collect`) and writes
candidates.jsonl with the tasks that satisfy the project criteria:
  - PR created on/after --since
  - gold patch touches >= --min-src non-test .py source files (docs/examples/scripts/... excluded)
  - patch has <= --max-files files and <= --max-kb KB (drops "mega-PRs")
  - <= --max-issues linked issues
  - one task per (repo, issue set): the most recent PR wins
Prints a per-repo summary.

Usage (inside the SWE-bench venv, which provides unidiff):
    python prefilter.py
    python prefilter.py --since 2026-05-15 --min-src 2 --max-files 15 --max-kb 50 --max-issues 2 \
        --exclude openai/openai-agents-python --tasks-dir tasks --out candidates.jsonl
"""
import argparse
import collections
import glob
import json
import os

from unidiff import PatchSet

SKIP_DIRS = ("docs/", "doc/", "examples/", "example/", "scripts/", "benchmarks/", ".github/")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--tasks-dir", default="tasks", help="folder with *-task-instances.jsonl")
    ap.add_argument("--out", default="candidates.jsonl")
    ap.add_argument("--since", default="2026-05-15", help="keep PRs created on/after this date (YYYY-MM-DD)")
    ap.add_argument("--min-src", type=int, default=2, help="min non-test .py source files in the gold patch")
    ap.add_argument("--max-files", type=int, default=15, help="max files in the gold patch")
    ap.add_argument("--max-kb", type=int, default=50, help="max size of the gold patch in KB")
    ap.add_argument("--max-issues", type=int, default=2, help="max linked issues")
    ap.add_argument("--exclude", nargs="*", default=[], help="repos to skip (owner/name)")
    a = ap.parse_args()

    stats = collections.Counter()
    reasons = collections.Counter()
    best = {}
    files_in = sorted(glob.glob(os.path.join(a.tasks_dir, "*-task-instances.jsonl")))
    if not files_in:
        raise SystemExit(f"no *-task-instances.jsonl in {a.tasks_dir}")

    for path in files_in:
        for line in open(path):
            t = json.loads(line)
            repo = t["repo"]
            if repo in a.exclude:
                continue
            stats[repo, "candidates"] += 1
            files = [p.path for p in PatchSet(t["patch"])]
            src = [f for f in files if f.endswith(".py") and not f.startswith(SKIP_DIRS)]
            if t["created_at"][:10] < a.since:
                reasons["too old"] += 1
            elif len(src) < a.min_src:
                reasons[f"< {a.min_src} src files"] += 1
            elif len(files) > a.max_files:
                reasons[f"> {a.max_files} files"] += 1
            elif len(t["patch"]) > a.max_kb * 1024:
                reasons[f"> {a.max_kb} KB"] += 1
            elif len(t["issue_numbers"]) > a.max_issues:
                reasons[f"> {a.max_issues} issues"] += 1
            else:
                key = (repo, tuple(sorted(t["issue_numbers"])))
                if key in best:
                    reasons["duplicate issue"] += 1
                if key not in best or t["created_at"] > best[key]["created_at"]:
                    best[key] = t

    kept = sorted(best.values(), key=lambda t: (t["repo"], t["created_at"]))
    with open(a.out, "w") as out:
        for t in kept:
            out.write(json.dumps(t) + "\n")
            stats[t["repo"], "kept"] += 1

    print(f"{'repo':40s} {'candidates':>10s} {'kept':>5s}")
    for repo in sorted({r for r, _ in stats}):
        print(f"{repo:40s} {stats[repo, 'candidates']:10d} {stats[repo, 'kept']:5d}")
    print(f"\nTOTAL kept: {len(kept)} -> {a.out}")
    print("dropped:", ", ".join(f"{k}={v}" for k, v in reasons.most_common()))


if __name__ == "__main__":
    main()
