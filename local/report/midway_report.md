# Trust by Evidence, Not by Authorship: Auditing a New Issue-Solving Benchmark with PatchDiff

*Matteo Ghilardini, Sasha Toscano*

## Changes to the original plan

1. **Exactly two LLMs** (feedback): GPT-6 Luna (proprietary, OpenAI API, low reasoning effort) and Qwen3.8-27B (open-weight, vLLM on the USI cluster).
2. **Only recent, harder tasks** (feedback): PR created after 15 May 2026 and gold patch touching **>= 2 non-test source files**; the same filter is applied to the SWE-bench Verified comparison sample.
3. **Execution infrastructure**: environment construction, validation and the agent sandbox run locally in Docker (x86-64 images emulated on Apple Silicon), since the SWE-bench harness and images are Docker-based; we will use the Cluster for the next steps (vLLM, PatchDiff, L1/L2) and for the open-model runs.
4. **Rating extended to test validity** (second question of the SWE-bench Verified annotation), because many tests depend on names or details the issue does not state.
5. **PatchDiff reproduction moved after the midway** (week of 26 Nov): since we was a little late, we prioritised a working benchmark and an end-to-end L0 pipeline.

## Status of the project

**Repository selection and mining.** SEART-GHS being unavailable, we queried the GitHub API for Python repositories with >= 500 stars pushed after 15 May 2026 (300 repositories), inspected 24 by hand (installation, CI, tests, external services) and kept 15 pure-Python, pytest-based projects. The SWE-bench collection pipeline (cutoff 2026-05-15, 300 PRs per repository) gave **4, 155 PRs -> 3,152 merged -> 787 linked to an issue -> 690 task instances** with a test patch (one repository yielded none and was dropped).

**Pre-filtering.** Gold patch with >= 2 non-test source files, <= 15 files, <= 50 KB, <= 2 linked issues, one PR per issue: **187 candidates in 14 repositories** (483 dropped for touching one source file, 20 for size, issue count, duplicates or date).

**Execution-based validation.** SWE-bench does not publish this step, so we built it. For each candidate our tool builds a Docker image with the repository at `base_commit` only (no later history, no remote: the agent cannot look up the fix) and its dependencies (lockfile, or versions available at the base-commit date); it then runs the PR's tests 3× without and 3× with the gold patch. FAIL_TO_PASS = fails in every run without and passes in every run with the patch; PASS_TO_PASS = always passes; flaky tests are dropped. Tasks are stored in the official SWE-bench task-repository format, so the unmodified harness evaluates them. First batch, 5 repositories (black, celery, fastmcp, scrapy, python-sdk): **27 tried -> 25 valid** (the 2 rejections are refactorings without a fail-to-pass test); the official harness with the gold patches resolves **25/25**; no flaky test was observed.

**Issue and test rating.** Both authors independently rated the 25 tasks on the two SWE-bench Verified scales (0-3). Agreement is **low**: specification, weighted k = 0.47 (76% agreement on the keep/drop boundary); test validity, weighted k = 0.11 (52%). Disagreements are systematic: one rater judged tests that rely on names or details absent from the issue as acceptable (<= 1), the other as invalid (>= 2). Only **2 tasks** are kept by both raters, 11 are dropped by both, 12 need discussion. An LLM rater (Claude, reported separately) agrees with the stricter author (test validity: weighted k = 0.69, 100% boundary agreement). Even under the lenient reading, 11/25 tasks have tests that a reasonable fix may fail.

**Agent pipeline and first results.** mini-SWE-agent, GPT-6 Luna with low reasoning effort, 75 steps, $0.30 per-instance and global cost caps; L0 evaluation with the SWE-bench harness.

| Benchmark (filter: >= 2 source files)       | Tasks | Resolved (L0) | 95% Wilson CI | Cost   |
| ------------------------------------------- | ----- | ------------- | ------------- | ------ |
| Ours (validated)                            | 25    | 1 (4%)        | 1-20%         | $0.074 |
| SWE-bench Verified, random sample (seed 42) | 10    | 1 (10%)       | 2-40%         | $0.019 |

All patches applied. On our benchmark, 3 patches were empty (the agent reverted its own edits), 6 fix part of the FAIL_TO_PASS tests, 6 break PASS_TO_PASS tests, and 5 failures are on tasks whose tests import a name introduced by the fix. The only resolved task is one of the 2 tasks kept by both raters. Samples are too small to compare the two benchmarks yet. Total API spend: **$0.10 of $10**.

**Not done yet:** PatchDiff (L2), full developer-suite validation (L1), open-model runs, the complete Verified sample (40 tasks drawn, 10 run).

## Detailed schedule until the project deadline (16 December 2026)

| Period       | Activity                                                                                                                                                                                                                                                                                                 | Feasibility                                                                                                                                                       |
| ------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 19-25 Nov    | Joint discussion of the 12 disputed tasks and refinement of the rubric with calibration examples; re-rate. Validate the 68 untried candidates of the configured repositories and add 2-3 repositories (agentscope, prefect, supervision); rate the new tasks. Target: 20-30 tasks valid for both raters. | Validation is automatic (1-4 min/task, ~2 h per 25 tasks); a new repository needs one config entry; rating takes ~5 min/task.                                     |
| 19-25 Nov    | GPT-6 Luna on the full benchmark and the 40-task Verified sample.                                                                                                                                                                                                                                        | Scripts ready; ~$0.003/instance, a full run costs < $1.                                                                                                           |
| 26 Nov-2 Dec | Open model: Qwen3.8-27B with vLLM on the cluster (TA template), agent on both benchmarks.                                                                                                                                                                                                                | ~70 instances × ~5 min fit in 1-2 jobs of 4 h; the sandbox stays in local Docker via an SSH tunnel to the vLLM endpoint, or our images are pushed to the cluster. |
| 26 Nov-2 Dec | PatchDiff: set up and reproduce on 3-5 Verified tasks against the paper's released results.                                                                                                                                                                                                              | Public code; test generation with the open model (free) or gpt-4o-mini within <= $2.                                                                              |
| 3-9 Dec      | L1 (full developer suite, gold run as reference) and L2 (PatchDiff differentiating tests) on every plausible patch; manual inspection of <= 30-40 suspicious patches by both authors; failure taxonomy (Wang et al.).                                                                                    | L1 reuses our validation images and runner; ≈ 2 models × 70 tasks.                                                                                                |
| 10-16 Dec    | RQ1-RQ3 analysis (resolution rates with Wilson CIs per level, rankings per benchmark, incorrect patches caught by L0/L1/L2, effect of rating-based filtering), final report, replication artifact.                                                                                                       | Results are produced by scripts in the repository; analysis scripts are written during the runs.                                                                  |
