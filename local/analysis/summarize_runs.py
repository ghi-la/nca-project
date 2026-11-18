#!/usr/bin/env python3
"""Summarise agent runs (local/runs/<run>/) into tables for the report (stdlib only).

For each run: instances, submitted patches, resolved (L0, SWE-bench harness), cost, API calls.
Reads <run>/*/*.traj.json (mini-SWE-agent) and the latest <run>/results_*.json (harness).

Usage:  python summarize_runs.py [run names ...]      (default: every run in local/runs)
Writes: runs_summary.md, runs_instances.csv (next to this script)
"""
import csv
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
RUNS = HERE.parent / "runs"


def wilson(k: int, n: int, z: float = 1.96):
    if n == 0:
        return (float("nan"), float("nan"))
    p = k / n
    d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * ((p * (1 - p) / n + z * z / (4 * n * n)) ** 0.5) / d
    return (max(0.0, c - h), min(1.0, c + h))


def summarize(run_dir: Path):
    trajs = sorted(run_dir.glob("*/*.traj.json")) + sorted(run_dir.glob("iter_*/*/*.traj.json"))
    inst = {}
    for f in trajs:
        info = json.loads(f.read_text()).get("info", {})
        st = info.get("model_stats", {})
        inst[f.parent.name] = {"cost": st.get("instance_cost", 0.0), "calls": st.get("api_calls", 0),
                               "exit": info.get("exit_status", ""), "resolved": None}
    res_files = sorted(run_dir.glob("results_*.json"), key=lambda p: p.stat().st_mtime)
    if res_files:
        res = json.loads(res_files[-1].read_text())
        # the harness lists the whole dataset as "incomplete": only instances the agent ran count
        for i in set(res.get("submitted_ids", [])) - set(inst):
            inst[i] = {"cost": 0.0, "calls": 0, "exit": "", "resolved": None}
        resolved = set(res.get("resolved_ids", []))
        for i, v in inst.items():
            v["resolved"] = i in resolved
    return inst, bool(res_files)


def main():
    names = sys.argv[1:] or sorted(p.name for p in RUNS.iterdir() if p.is_dir())
    lines = ["| run | instances | submitted | resolved (L0) | rate [95% Wilson CI] | total cost | mean cost | mean API calls |",
             "|---|---|---|---|---|---|---|---|"]
    rows = []
    for name in names:
        inst, evaluated = summarize(RUNS / name)
        if not inst:
            continue
        n = len(inst)
        sub = sum(1 for v in inst.values() if v["exit"] == "Submitted")
        res = sum(1 for v in inst.values() if v["resolved"])
        cost = sum(v["cost"] for v in inst.values())
        calls = sum(v["calls"] for v in inst.values()) / n
        lo, hi = wilson(res, n)
        rate = f"{res / n:.0%} [{lo:.0%}, {hi:.0%}]" if evaluated else "not evaluated"
        lines.append(f"| {name} | {n} | {sub} | {res if evaluated else '-'} | {rate} | ${cost:.4f} | ${cost / n:.4f} | {calls:.1f} |")
        for iid, v in sorted(inst.items()):
            rows.append({"run": name, "instance_id": iid, **v})
    (HERE / "runs_summary.md").write_text("\n".join(lines) + "\n")
    with open(HERE / "runs_instances.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["run", "instance_id", "resolved", "exit", "cost", "calls"])
        w.writeheader()
        w.writerows(rows)
    print("\n".join(lines))
    print(f"\nwritten: {HERE / 'runs_summary.md'}, {HERE / 'runs_instances.csv'}")


if __name__ == "__main__":
    main()
