#!/usr/bin/env python3
"""Draw the SWE-bench Verified comparison sample with the same difficulty filter as our tasks.

Filter: gold patch touches >= 2 non-test .py source files (same rule as mining/prefilter.py).
Sample: fixed seed, shuffled; the first --pilot ids are used for the midway pilot.

Run inside the SWE-bench venv (needs `datasets`):
    python make_verified_sample.py                     # 40 tasks, seed 42, pilot = first 10
Writes:
    verified_sample.csv     instance_id, repo, n_src_files, difficulty, in_pilot
    verified_filter.txt     regex for run_luna.sh FILTER (pilot ids)
    verified_pull.sh        docker pull of the pilot images (pull them before running the agent)
"""
import argparse
import collections
import csv
import random
import re
from pathlib import Path

from datasets import load_dataset

HERE = Path(__file__).resolve().parent
SKIP = ("docs/", "doc/", "examples/", "example/", "scripts/", "benchmarks/", ".github/")


def is_test(p: str) -> bool:
    q = p.lower()
    name = q.rsplit("/", 1)[-1]
    return "/tests/" in "/" + q or "/test/" in "/" + q or name.startswith("test_") or name.endswith("_test.py")


def n_src(patch: str) -> int:
    files = re.findall(r"^diff --git a/(\S+)", patch, re.M)
    return len([f for f in files if f.endswith(".py") and not is_test(f) and not f.startswith(SKIP)])


def image(iid: str) -> str:
    return f"swebench/sweb.eval.x86_64.{iid.replace('__', '_1776_')}:latest".lower()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=40)
    ap.add_argument("--pilot", type=int, default=10)
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--min-src", type=int, default=2)
    ap.add_argument("--dataset", default="princeton-nlp/SWE-Bench_Verified")
    a = ap.parse_args()

    ds = load_dataset(a.dataset, split="test")
    rows = [dict(instance_id=x["instance_id"], repo=x["repo"], n_src_files=n_src(x["patch"]),
                 difficulty=x.get("difficulty", "")) for x in ds]
    eligible = sorted((r for r in rows if r["n_src_files"] >= a.min_src), key=lambda r: r["instance_id"])
    random.Random(a.seed).shuffle(eligible)
    sample = eligible[: a.n]
    for i, r in enumerate(sample):
        r["in_pilot"] = int(i < a.pilot)

    with open(HERE / "verified_sample.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["instance_id", "repo", "n_src_files", "difficulty", "in_pilot"])
        w.writeheader()
        w.writerows(sample)
    pilot = [r["instance_id"] for r in sample if r["in_pilot"]]
    regex = "^(" + "|".join(re.escape(i) for i in pilot) + ")$"
    (HERE / "verified_filter.txt").write_text(regex + "\n")
    (HERE / "verified_pull.sh").write_text("#!/bin/bash\n" + "".join(f"docker pull {image(i)}\n" for i in pilot))

    print(f"Verified: {len(rows)} tasks, {len(eligible)} with >= {a.min_src} source files "
          f"({len(eligible) / len(rows):.0%}); sample {len(sample)} (seed {a.seed}), pilot {len(pilot)}")
    print("sample per repo:", dict(collections.Counter(r["repo"] for r in sample).most_common()))
    print("sample difficulty:", dict(collections.Counter(r["difficulty"] for r in sample).most_common()))
    print(f"\npilot FILTER (also in verified_filter.txt):\n{regex}")


if __name__ == "__main__":
    main()
