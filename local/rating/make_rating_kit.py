#!/usr/bin/env python3
"""Build the rating kit for the validated tasks (stdlib only).

Reads validation/nca-tasks/dataset/test.jsonl (+ validation_report.csv) and writes:
  kit/<instance_id>.md   one sheet per task: issue, links, gold patch, test patch, tests
  rating_template.csv    copy it to rating_<name>.csv and fill it in (one file per rater)
  RUBRIC.md              the two 0-3 scales (SWE-bench Verified annotation protocol)

Usage:  python make_rating_kit.py [--dataset ../validation/nca-tasks/dataset/test.jsonl]
"""
import argparse
import csv
import json
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent

RUBRIC = """# Rating rubric (SWE-bench Verified annotation protocol, two questions)

Rate every task **independently** (do not discuss before both files are complete).
Read the issue first as if you had to solve it, then look at the gold patch and the tests.

## spec_score: is the issue well specified?
How clear is it, from the issue text alone, what a successful solution looks like?
- **0**: well specified; it is clear what a successful solution must do.
- **1**: some blanks to fill in, but there is a sensible interpretation of what is required.
- **2**: vague; room for ambiguity, unclear what a successful solution would look like.
- **3**: almost impossible to understand what to do without more information.

## tests_score: are the tests valid?
Would the FAIL_TO_PASS tests accept every reasonable solution of the issue?
- **0**: the tests accept all reasonable solutions.
- **1**: the tests accept the majority of correct solutions; some unusual ones may fail.
- **2**: the tests work, but some perfectly reasonable solutions may fail
  (e.g. they rely on a function/argument name, message text or detail not stated in the issue).
- **3**: the tests are too narrow/broad or check something different from the issue.

Hint: tasks marked `collection_error: yes` import something that only exists after the fix.
If the issue does not name it, the agent cannot guess it -> usually tests_score >= 2.

## Selection rule
A task is kept if **both raters give <= 1 on both scores**. Disagreements across the
1/2 boundary are discussed and resolved together (record the final decision in the notes).
Agreement is reported with Cohen's kappa (computed by `kappa.py`).
"""


def fence(text: str, lang: str = "") -> str:
    return f"```{lang}\n{text.rstrip()}\n```"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dataset", default=str(HERE.parent / "validation" / "nca-tasks" / "dataset" / "test.jsonl"))
    ap.add_argument("--report", default=str(HERE.parent / "validation" / "nca-tasks" / "validation_report.csv"))
    ap.add_argument("--max-patch-lines", type=int, default=400)
    a = ap.parse_args()

    report = {}
    if Path(a.report).exists():
        report = {r["instance_id"]: r for r in csv.DictReader(open(a.report))}
    tasks = sorted((json.loads(l) for l in open(a.dataset)), key=lambda t: t["instance_id"])

    kit = HERE / "kit"
    kit.mkdir(exist_ok=True)
    for t in tasks:
        iid, repo = t["instance_id"], t["repo"]
        f2p, p2p = json.loads(t["FAIL_TO_PASS"]), json.loads(t["PASS_TO_PASS"])
        issues = json.loads(t["issue_numbers"]) if isinstance(t["issue_numbers"], str) else t["issue_numbers"]
        ce = report.get(iid, {}).get("collection_error") or ""
        if ce not in ("yes", "no"):  # older report rows: look at the validation log
            log = Path(a.report).parent / "_logs" / iid / "before_1.log"
            ce = "?" if not log.exists() else (
                "yes" if re.search(r"errors? during collection|ImportError while importing test module",
                                   log.read_text(errors="replace")) else "no")

        def clip(patch):
            lines = patch.rstrip().splitlines()
            if len(lines) <= a.max_patch_lines:
                return patch
            return "\n".join(lines[: a.max_patch_lines]) + f"\n... ({len(lines) - a.max_patch_lines} more lines, see the PR)"

        links = [f"PR: https://github.com/{repo}/pull/{t['pull_number']}"]
        links += [f"issue: https://github.com/{repo}/issues/{n}" for n in issues]
        md = [
            f"# {iid}",
            "",
            f"- repo: `{repo}`, created: {t['created_at'][:10]}, base_commit: `{t['base_commit'][:12]}`",
            *[f"- {l}" for l in links],
            f"- FAIL_TO_PASS: {len(f2p)} tests, PASS_TO_PASS: {len(p2p)} tests, collection_error: **{ce}**",
            "",
            "## 1. Issue (what the agent sees)",
            "",
            t["problem_statement"].rstrip(),
            "",
            "## 2. Gold patch",
            "",
            fence(clip(t["patch"]), "diff"),
            "",
            "## 3. Test patch",
            "",
            fence(clip(t["test_patch"]), "diff"),
            "",
            "## 4. FAIL_TO_PASS tests" + (" (first 40)" if len(f2p) > 40 else ""),
            "",
            *[f"- `{x}`" for x in f2p[:40]],
            "",
        ]
        (kit / f"{iid}.md").write_text("\n".join(md))

    with open(HERE / "rating_template.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["instance_id", "spec_score", "tests_score", "notes"])
        for t in tasks:
            w.writerow([t["instance_id"], "", "", ""])
    (HERE / "RUBRIC.md").write_text(RUBRIC)
    print(f"{len(tasks)} sheets in {kit}/, template: rating_template.csv, rubric: RUBRIC.md")


if __name__ == "__main__":
    main()
