# Neural Code Analysis - Project

> Authors: Ghilardini Matteo, Toscano Sasha

*Trust by Evidence, Not by Authorship: Auditing a New Issue-Solving Benchmark with PatchDiff*

## Midway report: data and code

- **Benchmark statistics**, including the per-task table: [local/analysis/benchmark_stats.md](local/analysis/benchmark_stats.md) (CSV: [benchmark_tasks.csv](local/analysis/benchmark_tasks.csv))
- **Report**: [local/report/Ghilardini_Toscano_Midway_report.pdf](local/report/Ghilardini_Toscano_Midway_report.pdf)

| Folder | Content |
|---|---|
| `local/mining/` | Repository selection (`find_repos.py`), SWE-bench collection output, pre-filter (`prefilter.py`) |
| `local/validation/` | Validation tool (`validate_tasks.py`), per-repository install specs (`repo_specs.yaml`), the validated tasks in SWE-bench format (`nca-tasks/`) |
| `local/rating/` | Rubric, rating kit, the two authors' ratings, agreement (`kappa.py`) |
| `local/runs/` | mini-SWE-agent runs with GPT-6 Luna (L0 results) |
| `local/analysis/` | Verified sample (`make_verified_sample.py`), run summary, benchmark statistics (`benchmark_stats.py`) |

To regenerate the benchmark statistics (needs the SWE-bench environment and the SWE-bench Verified dataset):

```bash
cd local
python analysis/benchmark_stats.py
```

## Quick Start

- Enable USI-VPN
- Connect to the server via SSH:

```bash
ssh <short>@usi.ch@bre.usi.ch
```

- Ask Sasha to access folder (Matteo has no access to it):

```bash
/scratch/nca-course/toscas/
```

- Sync local folder with home folder on server:

```bash
rsync -avz --exclude .git --exclude .venv ./scratch/ <user>@usi.ch@bre.usi.ch:~/scratch/
```

- Sync local folder with actual scratch folder on server:

```bash
rsync -avz --exclude .git --exclude .venv ./scratch/ <user>@usi.ch@bre.usi.ch:/scratch/nca-course/$USER
```

- Load the OpenAI API key (server or client, as you need):
```bash
echo 'export OPENAI_API_KEY=<your_api_key>' > ~/.nca_openai
chmod 600 ~/.nca_openai
source ~/.nca_openai
```
