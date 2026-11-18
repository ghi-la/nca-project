#!/usr/bin/env python3
"""One compact rating sheet with all tasks (stdlib only) -> RATING_SHEET.md

Per task: links, the issue, the files the gold patch touches (+/- lines), the FAIL_TO_PASS
test names; gold patch and test patch are folded (<details>) at the end of each task.
Open it in VS Code (Markdown preview: Cmd+Shift+V) or on GitHub. No scores are suggested.

Usage:  python3 make_compact_sheet.py
"""
import csv
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
DATASET = HERE.parent / "validation" / "nca-tasks" / "dataset" / "test.jsonl"
LOGS = HERE.parent / "validation" / "nca-tasks" / "_logs"


def file_stats(patch: str):
    stats, cur = [], None
    for line in patch.splitlines():
        m = re.match(r"^diff --git a/(\S+) b/", line)
        if m:
            cur = [m.group(1), 0, 0]
            stats.append(cur)
        elif cur and line.startswith("+") and not line.startswith("+++"):
            cur[1] += 1
        elif cur and line.startswith("-") and not line.startswith("---"):
            cur[2] += 1
    return stats


def collection_error(iid: str) -> bool:
    log = LOGS / iid / "before_1.log"
    return log.exists() and bool(re.search(r"errors? during collection|ImportError while importing test module",
                                           log.read_text(errors="replace")))


def main():
    tasks = sorted((json.loads(l) for l in open(DATASET)), key=lambda t: t["instance_id"])
    out = ["# Rating sheet (all tasks)", "",
           "Rubric: `RUBRIC.md`. Write the scores in your own `rating_<name>.csv`.", "",
           "Index: " + " · ".join(f"[{i + 1}](#{t['instance_id'].lower().replace('_', '').replace('.', '')})"
                                  for i, t in enumerate(tasks)), ""]
    for n, t in enumerate(tasks, 1):
        iid, repo = t["instance_id"], t["repo"]
        issues = json.loads(t["issue_numbers"]) if isinstance(t["issue_numbers"], str) else t["issue_numbers"]
        f2p = json.loads(t["FAIL_TO_PASS"])
        names = sorted({x.split("::")[-1].split("[")[0] for x in f2p})
        links = f"[PR](https://github.com/{repo}/pull/{t['pull_number']})" + "".join(
            f" · [issue #{i}](https://github.com/{repo}/issues/{i})" for i in issues)
        out += ["---", "", f"## {iid}", "",
                f"**{n}/{len(tasks)}** · {links} · {len(f2p)} FAIL_TO_PASS tests"
                + (" · ⚠️ **tests import a name introduced by the fix**" if collection_error(iid) else ""), "",
                "### Issue", "", t["problem_statement"].strip(), "",
                "### Files changed by the gold patch", ""]
        out += [f"- `{f}` (+{a} / -{d})" for f, a, d in file_stats(t["patch"])]
        out += ["", "### Tests that must pass (names, deduplicated)", ""]
        out += [f"- `{x}`" for x in names[:20]] + ([f"- … {len(names) - 20} more"] if len(names) > 20 else [])
        out += ["", "<details><summary>Gold patch</summary>", "", "```diff", t["patch"].rstrip(), "```", "</details>", "",
                "<details><summary>Test patch</summary>", "", "```diff", t["test_patch"].rstrip(), "```", "</details>", ""]
    (HERE / "RATING_SHEET.md").write_text("\n".join(out) + "\n")
    print(f"RATING_SHEET.md: {len(tasks)} tasks")


if __name__ == "__main__":
    main()
