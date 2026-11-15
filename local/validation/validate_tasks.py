#!/usr/bin/env python3
"""Turn SWE-bench candidate tasks into validated, executable tasks (step 3).

For every candidate (from mining/candidates.jsonl) and its repo spec (repo_specs.yaml):
  1. writes a task folder in the swe-bench-tasks format: task.yaml, Dockerfile, eval.sh,
     gold.patch, test.patch, problem_statement.md, hints.md
  2. builds the Docker image: python:<v>-slim + repo at base_commit in /testbed + deps
  3. runs the tests of the test patch N times WITHOUT the gold patch ("before") and
     N times WITH it ("after"), using the eval.sh the SWE-bench harness will run
  4. FAIL_TO_PASS = fail in every "before" run and pass in every "after" run
     PASS_TO_PASS = pass in every run; tests that change status between runs are flaky
     and dropped. Tasks without FAIL_TO_PASS are rejected.
     collection_error=yes in the report: without the gold patch a test file does not even import
     (the tests use a name the fix introduces) -> check that the issue mentions that name.
  5. valid tasks go to <out>/tasks/<id>/ (+ tests.json), rejected ones to <out>/_rejected/<id>/;
     logs in <out>/_logs/<id>/, summary in <out>/validation_report.csv
  6. exports <out>/dataset/test.jsonl (with image_name) for mini-swe-agent (--subset <out>/dataset)

The output folder is a SWE-bench task repo, so the official harness can use it directly:
    swebench dataset check <out>
    swebench eval <out> --gold --task-repo <out> -r gold-nca          # every task must be resolved

Run inside the SWE-bench venv (it provides pyyaml, unidiff and the SWE-bench log parser):
    python validate_tasks.py --repos psf/black --limit-per-repo 2          # first try
    python validate_tasks.py --repos psf/black scrapy/scrapy celery/celery --limit-per-repo 5
    python validate_tasks.py --ids psf__black-5012 --force                 # redo one task
    python validate_tasks.py --dry-run --repos psf/black --limit-per-repo 1 # only write files
    python validate_tasks.py --export-only                                 # rebuild dataset/test.jsonl
"""
from __future__ import annotations

import argparse
import concurrent.futures as cf
import csv
import hashlib
import json
import re
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path

import yaml
from unidiff import PatchSet

HERE = Path(__file__).resolve().parent
START, END = ">>>>> Start Test Output", ">>>>> End Test Output"
DATASET_NAME = "nca/nca-bench"
LOG_PARSER = "parse_log_pytest"
PASS = {"PASSED", "XFAIL"}  # same as the SWE-bench grader
_print_lock = threading.Lock()


def say(*a):
    with _print_lock:
        print(*a, flush=True)


# --------------------------------------------------------------------------- parsing
try:  # the exact parser the harness will use
    from swebench.harness.log_parsers import PARSER_REGISTRY

    def parse_log(log: str) -> dict[str, str]:
        return PARSER_REGISTRY[LOG_PARSER](log, None)

except Exception:  # pragma: no cover - fallback with the same logic
    _SKIP = re.compile(r"^\[\d+\]$")
    _STATUSES = ("FAILED", "PASSED", "SKIPPED", "ERROR", "XFAIL")

    def parse_log(log: str) -> dict[str, str]:
        out = {}
        for line in log.split("\n"):
            if line.startswith(_STATUSES):
                if line.startswith("FAILED"):
                    line = line.replace(" - ", " ")
                parts = line.split()
                if len(parts) <= 1 or (parts[0] == "SKIPPED" and _SKIP.match(parts[1])):
                    continue
                out[parts[1]] = parts[0]
        return out


def test_section(log: str) -> str | None:
    """The part of the log between the harness markers, or None if the tests never ran."""
    s, e = log.find(START), log.rfind(END)
    if s == -1 or e == -1 or e < s:
        return None
    return log[s:e]


# --------------------------------------------------------------------------- helpers
def image_name(instance_id: str) -> str:
    """Same naming convention as `swebench dataset check` expects."""
    return f"swebench/sweb.eval.x86_64.{instance_id}:latest".lower().replace("__", "_1776_")


def is_test_module(path: str) -> bool:
    name = path.rsplit("/", 1)[-1]
    return name.endswith(".py") and (name.startswith("test_") or name.endswith("_test.py"))


def analyse_test_patch(test_patch: str):
    """-> (test modules to run, files to reset with git checkout, touches non-module files)"""
    modules, existing, other = [], [], False
    for pf in PatchSet(test_patch):
        path = pf.path
        if not pf.is_added_file:
            existing.append(path)
        if pf.is_removed_file:
            continue
        if is_test_module(path):
            modules.append(path)
        elif not path.endswith(("conftest.py", "__init__.py")):
            other = True
    return modules, existing, other


def spec_version(spec: dict) -> str:
    blob = json.dumps(spec, sort_keys=True).encode()
    return "spec-" + hashlib.sha256(blob).hexdigest()[:8]


def ensure_nl(s: str) -> str:
    return s if s.endswith("\n") else s + "\n"


# --------------------------------------------------------------------------- rendering
def render_dockerfile(task: dict, spec: dict) -> str:
    apt = " ".join(["git", "patch", "build-essential", "ca-certificates", "curl", *spec.get("apt", [])])
    exclude_newer = '"$(git log -1 --format=%cI)"'  # committer date of base_commit, evaluated at build time
    install = [c.strip().format(exclude_newer=exclude_newer) for c in spec["install"]]
    env = {"PIP_DISABLE_PIP_VERSION_CHECK": "1", "UV_LINK_MODE": "copy", **spec.get("env", {})}
    env_lines = "\n".join(f'ENV {k}="{v}"' for k, v in env.items())
    install_block = " && \\\n    ".join(install)
    return f"""FROM --platform=linux/amd64 python:{spec['python']}-slim

ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC
RUN apt-get update && apt-get install -y --no-install-recommends {apt} \\
    && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir uv
RUN git config --global --add safe.directory /testbed \\
    && git config --global user.email "nca@localhost" && git config --global user.name "nca"
{env_lines}

# repo at base_commit only: no remote, no later history (the agent cannot peek at the fix)
RUN git init -q /testbed && cd /testbed \\
    && git remote add origin https://github.com/{task['repo']}.git \\
    && git fetch -q --depth 1 origin {task['base_commit']} \\
    && git checkout -q FETCH_HEAD \\
    && git remote remove origin && rm -f .git/FETCH_HEAD
WORKDIR /testbed

RUN {install_block} \\
    && rm -rf /root/.cache

# build artifacts (egg-info, generated version files, ...) must not end up in patches
RUN git status --porcelain --untracked-files=all | sed -n 's/^?? //p' >> .git/info/exclude \\
    && git status --short
"""


def render_eval_sh(task: dict, spec: dict) -> tuple[str | None, str]:
    modules, existing, other = analyse_test_patch(task["test_patch"])
    tests = list(modules)
    if spec.get("default_tests") and (other or not tests):
        tests += [t for t in spec["default_tests"] if t not in tests]
    if not tests:
        return None, "test patch has no test module and the spec has no default_tests"
    base = task["base_commit"]
    reset = f"git checkout {base} -- {' '.join(existing)}" if existing else ": no existing test files to reset"
    script = f"""#!/bin/bash
set -uxo pipefail
cd /testbed
git config --global --add safe.directory /testbed
git status
git -c core.fileMode=false diff {base}
{reset}
git apply -v - <<'EOF_NCA_TEST_PATCH_7f3a'
{ensure_nl(task['test_patch'])}EOF_NCA_TEST_PATCH_7f3a
: '{START}'
{spec['test_cmd']} {' '.join(tests)}
: '{END}'
{reset}
"""
    return script, ""


def gold_prefix(task: dict) -> str:
    return f"""cat > /tmp/gold.patch <<'EOF_NCA_GOLD_PATCH_9c1e'
{ensure_nl(task['patch'])}EOF_NCA_GOLD_PATCH_9c1e
cd /testbed && git apply -v /tmp/gold.patch || {{ echo 'NCA_GOLD_PATCH_FAILED'; exit 97; }}
"""


def task_yaml(task: dict, spec: dict) -> dict:
    return {
        "instance_id": task["instance_id"],
        "repo": task["repo"],
        "version": spec_version(spec),
        "base_commit": task["base_commit"],
        "environment_setup_commit": task["base_commit"],
        "created_at": task["created_at"],
        "pull_number": task.get("pull_number"),
        "issue_numbers": task.get("issue_numbers", []),
        "split": "test",
        "datasets": [DATASET_NAME],
        "image": image_name(task["instance_id"]),
        "log_parser": LOG_PARSER,
        "eval_type": "pass_and_fail",
    }


def write_task_dir(d: Path, task: dict, spec: dict, eval_sh: str):
    d.mkdir(parents=True, exist_ok=True)
    (d / "Dockerfile").write_text(render_dockerfile(task, spec))
    (d / "eval.sh").write_text(eval_sh)
    (d / "gold.patch").write_text(ensure_nl(task["patch"]))
    (d / "test.patch").write_text(ensure_nl(task["test_patch"]))
    (d / "problem_statement.md").write_text(task["problem_statement"])
    if task.get("hints_text", "").strip():
        (d / "hints.md").write_text(task["hints_text"])
    (d / "task.yaml").write_text(yaml.safe_dump(task_yaml(task, spec), sort_keys=True, allow_unicode=True))


# --------------------------------------------------------------------------- docker
def sh(cmd: list[str], log: Path, stdin: str | None = None, timeout: int | None = None) -> tuple[int, str]:
    try:  # one stream, so the set -x markers stay in order with the test output
        p = subprocess.run(cmd, input=stdin, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           text=True, timeout=timeout, errors="replace")
        out, code = p.stdout, p.returncode
    except subprocess.TimeoutExpired as e:
        x = e.stdout
        out = x.decode(errors="replace") if isinstance(x, bytes) else (x or "")
        out, code = out + f"\nNCA_TIMEOUT after {timeout}s\n", 124
    log.write_text(f"$ {' '.join(cmd)}\n{out}")
    return code, out


def build(ctx: Path, image: str, logdir: Path, timeout: int) -> bool:
    code, _ = sh(["docker", "build", "--platform", "linux/amd64", "--progress=plain", "-t", image, str(ctx)],
                 logdir / "build.log", timeout=timeout)
    return code == 0


def run_tests(image: str, script: str, log: Path, timeout: int, network: bool):
    cmd = ["docker", "run", "--rm", "-i", "--platform", "linux/amd64"]
    if not network:
        cmd += ["--network", "none"]
    # stderr (set -x trace with the markers) and stdout (pytest) merged inside the container
    _, out = sh(cmd + [image, "bash", "-s"], log, stdin="exec 2>&1\n" + script, timeout=timeout)
    if "NCA_GOLD_PATCH_FAILED" in out or re.search(r"error: (patch failed|corrupt patch)", out):
        return None, out
    section = test_section(out)
    return (None if section is None else parse_log(section)), out


# --------------------------------------------------------------------------- validation
def classify(before: list[dict], after: list[dict]):
    names = set().union(*before, *after)
    f2p, p2p, flaky = [], [], []
    for t in sorted(names):
        b = [r.get(t) in PASS for r in before]
        a = [r.get(t) in PASS for r in after]
        if len(set(b)) > 1 or len(set(a)) > 1:
            flaky.append(t)
        elif not any(b) and all(a):
            f2p.append(t)
        elif all(b) and all(a):
            p2p.append(t)
    return f2p, p2p, flaky


def validate(task: dict, spec: dict, a) -> dict:
    iid = task["instance_id"]
    out = Path(a.out)
    final, rejected = out / "tasks" / iid, out / "_rejected" / iid
    work, logdir = out / "_work" / iid, out / "_logs" / iid
    row = {"instance_id": iid, "repo": task["repo"], "status": "", "f2p": 0, "p2p": 0, "flaky": 0,
           "collection_error": "no", "build_s": 0, "test_s": 0, "note": ""}

    eval_sh, why = render_eval_sh(task, spec)
    if eval_sh is None:
        row.update(status="rejected_no_tests", note=why)
        return row
    for d in (work, logdir):
        shutil.rmtree(d, ignore_errors=True)
        d.mkdir(parents=True)
    write_task_dir(work, task, spec, eval_sh)
    if a.dry_run:
        row.update(status="dry_run", note=str(work))
        return row

    image = image_name(iid)
    t0 = time.time()
    say(f"[{iid}] building {image}")
    ok = build(work, image, logdir, a.build_timeout)
    row["build_s"] = round(time.time() - t0)
    if not ok:
        row.update(status="rejected_build", note=f"see {logdir / 'build.log'}")
        return finish(row, work, rejected, image, a)

    t0 = time.time()
    before, after = [], []
    for r in range(1, a.runs + 1):
        say(f"[{iid}] run {r}/{a.runs}")
        b, b_out = run_tests(image, eval_sh, logdir / f"before_{r}.log", a.test_timeout, a.network)
        g, _ = run_tests(image, gold_prefix(task) + eval_sh, logdir / f"after_{r}.log", a.test_timeout, a.network)
        if r == 1 and re.search(r"errors? during collection|ImportError while importing test module", b_out):
            row["collection_error"] = "yes"
        if b is None or g is None:
            row.update(status="rejected_run", note=f"tests did not run or a patch failed, run {r}; see {logdir}")
            row["test_s"] = round(time.time() - t0)
            return finish(row, work, rejected, image, a)
        before.append(b)
        after.append(g)
    row["test_s"] = round(time.time() - t0)
    if not any(after):
        row.update(status="rejected_unparsed",
                   note="no test result parsed: check test_cmd (pytest -rA, plugins that hide the summary)")
        return finish(row, work, rejected, image, a)

    f2p, p2p, flaky = classify(before, after)
    row.update(f2p=len(f2p), p2p=len(p2p), flaky=len(flaky))
    (work / "tests.json").write_text(json.dumps({"FAIL_TO_PASS": f2p, "PASS_TO_PASS": p2p}, indent=2) + "\n")
    (logdir / "flaky.json").write_text(json.dumps(flaky, indent=2))
    if not f2p:
        row.update(status="rejected_no_f2p", note="no test goes from fail to pass with the gold patch")
        return finish(row, work, rejected, image, a)
    row["status"] = "valid"
    return finish(row, work, final, image, a)


def finish(row: dict, work: Path, dest: Path, image: str, a) -> dict:
    shutil.rmtree(dest, ignore_errors=True)
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(work), str(dest))
    if row["status"] != "valid" and not a.dry_run:
        subprocess.run(["docker", "image", "rm", "-f", image], capture_output=True)
    say(f"[{row['instance_id']}] {row['status']}  F2P={row['f2p']} P2P={row['p2p']} flaky={row['flaky']}  {row['note']}")
    return row


# --------------------------------------------------------------------------- outputs
def write_sweb_yaml(out: Path):
    out.mkdir(parents=True, exist_ok=True)
    p = out / "sweb.yaml"
    if not p.exists():
        p.write_text(yaml.safe_dump({"datasets": [DATASET_NAME], "splits": ["test"]}, sort_keys=False))


def export_dataset(out: Path) -> int:
    """tasks/ -> dataset/test.jsonl in the SWE-bench column format (+ image_name for mini-swe-agent)."""
    rows = []
    for d in sorted((out / "tasks").glob("*/")):
        if not (d / "tests.json").exists():
            continue
        meta = yaml.safe_load((d / "task.yaml").read_text())
        tests = json.loads((d / "tests.json").read_text())
        hints = d / "hints.md"
        rows.append({
            **meta,
            "problem_statement": (d / "problem_statement.md").read_text(),
            "hints_text": hints.read_text() if hints.exists() else "",
            "patch": (d / "gold.patch").read_text(),
            "test_patch": (d / "test.patch").read_text(),
            "FAIL_TO_PASS": json.dumps(tests["FAIL_TO_PASS"]),
            "PASS_TO_PASS": json.dumps(tests["PASS_TO_PASS"]),
            "image_name": meta["image"],
            "issue_numbers": json.dumps(meta.get("issue_numbers", [])),
        })
    ds = out / "dataset"
    ds.mkdir(parents=True, exist_ok=True)
    with open(ds / "test.jsonl", "w") as f:
        for r in rows:
            f.write(json.dumps(r) + "\n")
    return len(rows)


def write_report(out: Path, rows: list[dict]):
    p = out / "validation_report.csv"
    old = {}
    if p.exists():
        with open(p) as f:
            old = {r["instance_id"]: r for r in csv.DictReader(f)}
    for r in rows:
        old[r["instance_id"]] = r
    fields = ["instance_id", "repo", "status", "f2p", "p2p", "flaky", "collection_error", "build_s", "test_s", "note"]
    with open(p, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for r in sorted(old.values(), key=lambda r: r["instance_id"]):
            w.writerow({k: r.get(k, "") for k in fields})


# --------------------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--candidates", default=str(HERE.parent / "mining" / "candidates.jsonl"))
    ap.add_argument("--specs", default=str(HERE / "repo_specs.yaml"))
    ap.add_argument("--out", default=str(HERE / "nca-tasks"))
    ap.add_argument("--repos", nargs="*", help="only these repos (owner/name)")
    ap.add_argument("--ids", nargs="*", help="only these instance ids")
    ap.add_argument("--limit-per-repo", type=int, default=0, help="at most N new tasks per repo (0 = all)")
    ap.add_argument("--runs", type=int, default=3, help="repetitions before/after, for flaky tests")
    ap.add_argument("--jobs", type=int, default=2, help="tasks validated in parallel")
    ap.add_argument("--build-timeout", type=int, default=3600)
    ap.add_argument("--test-timeout", type=int, default=1800)
    ap.add_argument("--network", action="store_true", help="allow network during test runs (default: none)")
    ap.add_argument("--force", action="store_true", help="redo tasks already validated or rejected")
    ap.add_argument("--dry-run", action="store_true", help="only write task folders to <out>/_work, no docker")
    ap.add_argument("--export-only", action="store_true", help="only rebuild <out>/dataset/test.jsonl")
    a = ap.parse_args()

    out = Path(a.out)
    write_sweb_yaml(out)
    if a.export_only:
        print(f"dataset/test.jsonl: {export_dataset(out)} tasks")
        return

    specs = yaml.safe_load(open(a.specs))
    tasks = [json.loads(l) for l in open(a.candidates)]
    selected, per_repo, skipped_nospec = [], {}, set()
    for t in tasks:
        iid, repo = t["instance_id"], t["repo"]
        if a.ids and iid not in a.ids:
            continue
        if a.repos and repo not in a.repos:
            continue
        if repo not in specs:
            skipped_nospec.add(repo)
            continue
        done = (out / "tasks" / iid).exists() or (out / "_rejected" / iid).exists()
        if done and not a.force:
            continue
        if a.limit_per_repo and per_repo.get(repo, 0) >= a.limit_per_repo:
            continue
        per_repo[repo] = per_repo.get(repo, 0) + 1
        selected.append(t)
    if skipped_nospec and not a.ids:
        print(f"no spec in {a.specs} for: {', '.join(sorted(skipped_nospec))} (skipped)")
    if a.ids:
        missing = set(a.ids) - {t["instance_id"] for t in selected}
        if missing:
            print(f"not selected (unknown id, no spec, or already done without --force): {' '.join(sorted(missing))}")
    print(f"{len(selected)} task(s) to validate: " + ", ".join(f"{r}={n}" for r, n in sorted(per_repo.items())))
    if not selected:
        return

    rows = []
    with cf.ThreadPoolExecutor(max_workers=a.jobs) as ex:
        futs = {ex.submit(validate, t, specs[t["repo"]], a): t for t in selected}
        for fut in cf.as_completed(futs):
            try:
                rows.append(fut.result())
            except Exception as e:  # keep going on unexpected errors
                t = futs[fut]
                say(f"[{t['instance_id']}] ERROR {e!r}")
                rows.append({"instance_id": t["instance_id"], "repo": t["repo"], "status": "error", "note": repr(e)})

    if not a.dry_run:
        write_report(out, rows)
        n = export_dataset(out)
        print(f"\nreport: {out / 'validation_report.csv'}\ndataset for mini-swe-agent: {out / 'dataset/test.jsonl'} ({n} valid tasks)")
    counts = {}
    for r in rows:
        counts[r["status"]] = counts.get(r["status"], 0) + 1
    print("summary:", ", ".join(f"{k}={v}" for k, v in sorted(counts.items())))


if __name__ == "__main__":
    main()
