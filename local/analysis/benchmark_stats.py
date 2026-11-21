#!/usr/bin/env python3
"""Benchmark statistics reported in the midway report (Table 1, Appendix, and the Verified comparison).

Run from local/:
    HF_DATASETS_OFFLINE=1 <SWE-bench venv>/bin/python analysis/benchmark_stats.py

Definitions (same for our tasks and for SWE-bench Verified):
  - source files: non-test .py files in the gold patch (same rule as mining/prefilter.py)
  - lines:        added + removed lines in the whole gold patch
  - issue words:  whitespace-separated words of the problem statement
  - import error: the test patch imports a name that only the gold patch introduces,
                  so the test module cannot be collected without the fix (from the rating kit)

Outputs:
  analysis/benchmark_tasks.csv   one row per valid task
  analysis/benchmark_stats.md    per-repository medians/ranges and the Verified comparison
"""
import collections
import csv
import json
import pathlib
import re
import statistics as st
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from make_verified_sample import SKIP, is_test  # noqa: E402
from datasets import load_dataset  # noqa: E402

TASKS = pathlib.Path("validation/nca-tasks/tasks")
REPORT = pathlib.Path("validation/nca-tasks/validation_report.csv")
KIT = pathlib.Path("rating/kit")
RUN = pathlib.Path("runs/luna_nca")
SAMPLE = pathlib.Path("analysis/verified_sample.csv")
SELECTION = pathlib.Path("rating/selection_matteo_vs_sasha.csv")
OUT_CSV = pathlib.Path("analysis/benchmark_tasks.csv")
OUT_MD = pathlib.Path("analysis/benchmark_stats.md")


def patch_stats(patch: str) -> tuple[int, int]:
    files = re.findall(r"^diff --git a/(\S+)", patch, re.M)
    lines = sum(1 for l in patch.splitlines() if l[:1] in "+-" and not l.startswith(("+++", "---")))
    src = [f for f in files if f.endswith(".py") and not is_test(f) and not f.startswith(SKIP)]
    return len(src), lines


def fmt(xs) -> str:
    return f"{st.median(xs):g} ({min(xs)}–{max(xs)})"


def main() -> None:
    report = {r["instance_id"]: r for r in csv.DictReader(REPORT.open())}
    results = sorted(RUN.glob("results_*.json"), key=lambda p: p.stat().st_mtime)
    resolved = set(json.loads(results[-1].read_text()).get("resolved_ids", [])) if results else set()
    preds = json.loads((RUN / "preds.json").read_text())
    empty = {k for k, v in preds.items() if not (v.get("model_patch") or "").strip()}
    rating = {r["instance_id"]: r["decision"] for r in csv.DictReader(SELECTION.open())}

    rows = []
    for d in sorted(TASKS.iterdir()):
        iid = d.name
        if report.get(iid, {}).get("status") != "valid":
            continue
        src, lines = patch_stats((d / "gold.patch").read_text())
        test_files = len(re.findall(r"^diff --git", (d / "test.patch").read_text(), re.M))
        kit = KIT / f"{iid}.md"
        import_error = bool(kit.exists() and re.search(r"collection_error: \*\*yes\*\*", kit.read_text()))
        rows.append(dict(
            instance_id=iid, repo=report[iid]["repo"], src_files=src, gold_lines=lines, test_files=test_files,
            f2p=int(report[iid]["f2p"]), p2p=int(report[iid]["p2p"]),
            issue_words=len((d / "problem_statement.md").read_text().split()),
            import_error=int(import_error), rating=rating.get(iid, ""),
            luna="resolved" if iid in resolved else "empty patch" if iid in empty else "not resolved",
            resolved_luna=int(iid in resolved)))

    with OUT_CSV.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)

    md = ["# Benchmark statistics", "", f"Valid tasks: {len(rows)}", "",
          "| Repository | Tasks | Source files | Gold lines | F2P | P2P | Issue words | Import error | Resolved |",
          "|---|---|---|---|---|---|---|---|---|"]
    by = collections.defaultdict(list)
    for r in rows:
        by[r["repo"]].append(r)
    for repo, rs in sorted(by.items(), key=lambda kv: -len(kv[1])) + [("All", rows)]:
        md.append(f"| {repo} | {len(rs)} | " + " | ".join(fmt([r[k] for r in rs]) for k in
                  ["src_files", "gold_lines", "f2p", "p2p", "issue_words"])
                  + f" | {sum(r['import_error'] for r in rs)} | {sum(r['resolved_luna'] for r in rs)} |")

    ds = list(load_dataset("princeton-nlp/SWE-Bench_Verified", split="test"))
    v = {x["instance_id"]: (*patch_stats(x["patch"]), x["difficulty"]) for x in ds}
    sample = [r["instance_id"] for r in csv.DictReader(SAMPLE.open())]
    md += ["", "## SWE-bench Verified comparison (same definitions)", "",
           "| Set | Tasks | Source files (median) | Gold lines (median) |", "|---|---|---|---|",
           f"| Ours | {len(rows)} | {st.median(r['src_files'] for r in rows):g} | {st.median(r['gold_lines'] for r in rows):g} |",
           f"| Verified sample (>= 2 source files, seed 42) | {len(sample)} | {st.median(v[i][0] for i in sample):g} | {st.median(v[i][1] for i in sample):g} |",
           f"| Verified, all | {len(v)} | {st.median(x[0] for x in v.values()):g} | {st.median(x[1] for x in v.values()):g} |",
           "", "### Gold lines by Verified difficulty label", "",
           "| Label | Tasks | Median gold lines | Our tasks above this median |", "|---|---|---|---|"]
    by_diff = collections.defaultdict(list)
    for _, lines, diff in v.values():
        by_diff[diff].append(lines)
    for diff in ["<15 min fix", "15 min - 1 hour", "1-4 hours", ">4 hours"]:
        m = st.median(by_diff[diff])
        md.append(f"| {diff} | {len(by_diff[diff])} | {m:g} | {sum(r['gold_lines'] > m for r in rows)} / {len(rows)} |")

    md += ["", "## Per-task figures", "",
           "Source files and lines refer to the gold patch. *Import error*: the tests import a name that only the "
           "fix introduces. *Rating*: decision of the two authors before discussion (keep = both rated <= 1 on both "
           "questions, drop = both rated >= 2 on one question, discuss = they disagree). *GPT-6 Luna*: outcome at L0.", "",
           "| Task | Source files | Gold lines | Test files | FAIL_TO_PASS | PASS_TO_PASS | Issue words | Import error | Rating | GPT-6 Luna |",
           "|---|---|---|---|---|---|---|---|---|---|"]
    for r in sorted(rows, key=lambda r: (r["repo"].lower(), r["instance_id"])):
        md.append(f"| {r['instance_id']} | {r['src_files']} | {r['gold_lines']} | {r['test_files']} | {r['f2p']} | "
                  f"{r['p2p']} | {r['issue_words']} | {'yes' if r['import_error'] else ''} | {r['rating']} | {r['luna']} |")

    OUT_MD.write_text("\n".join(md) + "\n")
    print("\n".join(md))


if __name__ == "__main__":
    main()
