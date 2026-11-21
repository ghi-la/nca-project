---
title: "Trust by Evidence, Not by Authorship: Auditing a New Issue-Solving Benchmark with PatchDiff"
fontsize: 10pt
header-includes:
  - \usepackage{titling}
  - \setlength{\droptitle}{-7em}
  - \pretitle{\begin{center}\Large\bfseries}
  - \posttitle{\end{center}\vspace{-3.5em}}
  - \pagenumbering{gobble}
---

*Matteo Ghilardini, Sasha Toscano*

## Changes to the original plan

Following the feedback on the proposal, we narrowed the study in two ways. We evaluate exactly two models: GPT-6 Luna, a proprietary model queried through the OpenAI API with low reasoning effort, and Qwen3.8-27B, an open-weight model served with vLLM on the USI cluster. We also keep only recent, non-trivial tasks: pull requests created after 15 May 2026 whose gold patch modifies at least two non-test source files, a filter we also apply to our SWE-bench Verified sample. In addition, task validation and the agent sandbox run in local Docker, like the SWE-bench harness, while the cluster hosts vLLM and PatchDiff; the manual rating now also covers test validity; and the PatchDiff reproduction moved to 26 November, so that the benchmark and the pipeline came first.

## Status of the project

**From repositories to candidate tasks.** Since SEART-GHS was unavailable, we used the GitHub search API to find Python projects with at least 500 stars and a push after 15 May 2026. Of the 300 repositories returned, we inspected 24 by hand (installation, CI, need for databases or brokers) and kept 15 pure-Python projects tested with pytest. The SWE-bench collection pipeline produced 4,155 pull requests, of which 787 are linked to an issue and 690 also modify tests, the minimum for a task. After our filters (at least two source files, which alone removes 483; size and duplicate limits) we have **187 candidate tasks in 14 repositories**.

**Making the tasks runnable.** The public SWE-bench pipeline stops at this point, so we wrote our own validation tool. For every candidate it builds a Docker image from `python:3.12-slim` with the system packages the project needs and the repository at the task's base commit. Only that commit is fetched and the git remote is removed, so an agent in the container cannot recover the real fix from the history or from GitHub. Dependencies come from the project's lockfile or, when there is none, are resolved to the versions available at the base-commit date; the install commands come from each project's CI. The tool then runs the tests of the pull request three times on the original code and three times with the gold patch, without network: a test is FAIL_TO_PASS if it always fails without the fix and always passes with it, PASS_TO_PASS if it always passes, and flaky tests are discarded. Each task is stored in the official SWE-bench format, so the unmodified harness evaluates it exactly like a Verified task. On a first batch of 27 candidates from five repositories, **25 are valid** and the official harness resolves **all 25** with the gold patch; the two rejected ones have no failing-then-passing test.

**Table 1.** The 25 valid tasks per repository, median (range): non-test source files and lines (added plus removed) of the gold patch, tests found by our validation, issue length, and tasks resolved by GPT-6 Luna (L0). Per-task figures and the code are at <https://github.com/ghi-la/nca-project>.

| Repository | Tasks | Source files | Gold patch lines | FAIL_TO_\allowbreak{}PASS | PASS_TO_\allowbreak{}PASS | Issue words | Resolved |
| ---------------------- | ----- | -------- | -------------- | ---------- | ---------- | ------ | -------- |
| psf/black | 7 | 2 (2–3) | 69 (51–135) | 2 | 232 | 238 | 0 |
| PrefectHQ/fastmcp | 5 | 4 (2–7) | 73 (57–163) | 15 | 90 | 308 | 0 |
| celery/celery | 5 | 2 (2–4) | 95 (20–121) | 8 | 78 | 133 | 1 |
| scrapy/scrapy | 4 | 3 (2–7) | 51 (33–78) | 7 | 45 | 34 | 0 |
| modelcontextprotocol/\allowbreak{}python-sdk | 4 | 4 (3–9) | 116 (25–903) | 13 | 24 | 329 | 0 |
| **All** | **25** | **3 (2–9)** | **73 (20–903)** | **8** | **78** | **267** | **1** |

A typical task edits three source files with a 73-line gold patch. To put this in context, we computed the same two measures on the gold patches of SWE-bench Verified: our 40-task Verified sample has a median of 2 files and 34 lines, and Verified as a whole 1 file and 7 lines. Verified also labels each task with the time a developer would need to fix it; the tasks labelled "1 to 4 hours" have a median gold patch of 35 lines, and 22 of our 25 tasks are larger, which, with patch size as a rough proxy, suggests they are also harder. Scrapy issues are very short (a median of 34 words), a first hint that some issues leave a lot unsaid. In five tasks the new tests import a function that only exists after the fix, so an agent can pass them only by guessing its exact name.

**Rating the issues and the tests.** Passing tests does not make a task fair: the issue may not say what has to be done, or the tests may reject correct solutions that differ from the gold patch. SWE-bench Verified was built to remove such tasks: developers answered two questions per task on a 0–3 scale, how well the issue specifies a correct solution (0 = clear, 3 = almost impossible to know) and whether the tests accept every reasonable solution (0 = yes, 3 = they test something else). Tasks rated 2 or 3 on either question were removed. We applied the same protocol, both to remove unfair tasks and to test whether Verified's criteria can be applied reproducibly to a new benchmark. Both of us rated the 25 tasks independently with a short rubric, and measured agreement with Cohen's kappa (1 = perfect, 0 = no better than chance); its weighted version, suited to ordinal scales, penalises a 0-versus-3 disagreement more than a 1-versus-2 one. On issue specification we agree moderately (weighted Cohen's kappa 0.47, same keep/remove decision on 76% of tasks), but on test validity our agreement is close to chance (0.11, 52%). The split is systematic: one of us accepted tests that rely on a detail absent from the issue, such as a new function name, while the other did not. Only 2 tasks are kept by both, 11 are removed by both and 12 need discussion. An LLM rater (Claude, kept separate) sides with the stricter author (kappa 0.69). Even the lenient rater, however, found tests that a reasonable fix could fail in 11 of 25 tasks.

**First results.** We ran mini-SWE-agent with GPT-6 Luna (75 steps, $0.30 per task) and evaluated the patches with the official harness on the pull request's tests (level L0). Exactly one task is resolved on each side: 1 of our 25 (4%, 95% CI 1–20%) and 1 of 10 Verified tasks (10%, 2–40%), so the two benchmarks cannot yet be compared. Neither sample is balanced: our resolved task comes from celery and 7 of our tasks are from black, while the 10 Verified tasks are 6 from django (django alone has 231 of Verified's 500 tasks), 2 from pytest, 1 from matplotlib and 1 from sphinx, and the resolved one is from pytest. We see two explanations for the failures. First, the agent stops early and edits too little: it never used more than 16 of its 75 steps, its median patch changes 13 lines against 73 for the gold patch, it touched all gold-patch files in only 2 of 25 tasks, and 3 patches were empty after it reverted its own edits. In black-5297, for example, the fix is not where the crash shows: the agent edited one of the two right files, saw no change, reverted and gave up after 13 steps. Our hypothesis is that at low reasoning effort the model fixes the most visible symptom and submits, while the multi-file filter requires exploring further; we will test this by rerunning at medium effort. Second, some tasks are defective: the agent failed all five tasks whose tests import a new name, which both raters had removed, and the one resolved task is one of the two that both raters kept. The total API spend is $0.10 of our $10 budget. PatchDiff (L2), validation on the full test suite (L1) and the open-model runs are not done yet.

## Detailed schedule until the project deadline (16 December 2026)

| Period | Activity | Feasibility |
| ------------ | ---------------------------------------------- | -------------------------------- |
| 19–25 Nov | Discuss the 12 disputed tasks and re-rate with an extended rubric; validate the remaining candidates and 2–3 new repositories, aiming at 20–30 tasks kept by both raters. GPT-6 Luna on all tasks and the 40 Verified tasks, at low and medium effort. | Validation is automatic (1–4 min per task) and rating takes about 5 min per task; a full Luna run costs under $1. |
| 26 Nov–2 Dec | Qwen3.8-27B with vLLM on the cluster on both benchmarks; PatchDiff set-up and reproduction on 3–5 Verified tasks. | About 70 tasks × 5 min fit in 1–2 jobs of 4 h; PatchDiff code is public. |
| 3–9 Dec | L1 (full developer suite) and L2 (PatchDiff) on every plausible patch; manual inspection of 30–40 suspicious patches; failure taxonomy (Wang et al.). | L1 reuses our validation images and test runner. |
| 10–16 Dec | RQ1–RQ3 analysis, final report, replication package. | Scripts written during the runs. |
