# Benchmark statistics

Valid tasks: 25

| Repository | Tasks | Source files | Gold lines | F2P | P2P | Issue words | Import error | Resolved |
|---|---|---|---|---|---|---|---|---|
| psf/black | 7 | 2 (2–3) | 69 (51–135) | 2 (1–3) | 232 (166–264) | 238 (59–645) | 0 | 0 |
| PrefectHQ/fastmcp | 5 | 4 (2–7) | 73 (57–163) | 15 (9–86) | 90 (3–257) | 308 (171–376) | 1 | 0 |
| celery/celery | 5 | 2 (2–4) | 95 (20–121) | 8 (6–175) | 78 (0–295) | 133 (38–981) | 1 | 1 |
| modelcontextprotocol/python-sdk | 4 | 4 (3–9) | 116 (25–903) | 13 (1–98) | 23.5 (15–52) | 328.5 (80–599) | 2 | 0 |
| scrapy/scrapy | 4 | 3 (2–7) | 51 (33–78) | 7 (6–113) | 44.5 (0–54) | 33.5 (20–376) | 1 | 0 |
| All | 25 | 3 (2–9) | 73 (20–903) | 8 (1–175) | 78 (0–295) | 267 (20–981) | 5 | 1 |

## SWE-bench Verified comparison (same definitions)

| Set | Tasks | Source files (median) | Gold lines (median) |
|---|---|---|---|
| Ours | 25 | 3 | 73 |
| Verified sample (>= 2 source files, seed 42) | 40 | 2 | 34 |
| Verified, all | 500 | 1 | 7 |

### Gold lines by Verified difficulty label

| Label | Tasks | Median gold lines | Our tasks above this median |
|---|---|---|---|
| <15 min fix | 194 | 4 | 25 / 25 |
| 15 min - 1 hour | 261 | 9 | 25 / 25 |
| 1-4 hours | 42 | 34.5 | 22 / 25 |
| >4 hours | 3 | 123 | 4 / 25 |

## Per-task figures

Source files and lines refer to the gold patch. *Import error*: the tests import a name that only the fix introduces. *Rating*: decision of the two authors before discussion (keep = both rated <= 1 on both questions, drop = both rated >= 2 on one question, discuss = they disagree). *GPT-6 Luna*: outcome at L0.

| Task | Source files | Gold lines | Test files | FAIL_TO_PASS | PASS_TO_PASS | Issue words | Import error | Rating | GPT-6 Luna |
|---|---|---|---|---|---|---|---|---|---|
| celery__celery-10598 | 2 | 103 | 1 | 175 | 0 | 685 | yes | drop | not resolved |
| celery__celery-10605 | 2 | 72 | 1 | 7 | 91 | 981 |  | discuss | not resolved |
| celery__celery-10606 | 3 | 95 | 1 | 8 | 78 | 38 |  | discuss | not resolved |
| celery__celery-10668 | 4 | 121 | 6 | 9 | 295 | 83 |  | drop | not resolved |
| celery__celery-10714 | 2 | 20 | 2 | 6 | 36 | 133 |  | keep | resolved |
| modelcontextprotocol__python-sdk-3485 | 9 | 903 | 5 | 98 | 21 | 80 | yes | drop | not resolved |
| modelcontextprotocol__python-sdk-3600 | 4 | 118 | 3 | 12 | 52 | 346 |  | drop | not resolved |
| modelcontextprotocol__python-sdk-3620 | 4 | 114 | 3 | 14 | 26 | 599 | yes | drop | not resolved |
| modelcontextprotocol__python-sdk-3622 | 3 | 25 | 1 | 1 | 15 | 311 |  | drop | not resolved |
| PrefectHQ__fastmcp-6077 | 4 | 163 | 5 | 25 | 154 | 376 |  | drop | not resolved |
| PrefectHQ__fastmcp-6100 | 7 | 62 | 4 | 12 | 90 | 286 |  | drop | not resolved |
| PrefectHQ__fastmcp-6147 | 5 | 126 | 1 | 9 | 3 | 369 |  | discuss | not resolved |
| PrefectHQ__fastmcp-6180 | 2 | 57 | 2 | 86 | 23 | 171 | yes | drop | not resolved |
| PrefectHQ__fastmcp-6187 | 2 | 73 | 2 | 15 | 257 | 308 |  | discuss | not resolved |
| psf__black-5259 | 3 | 135 | 4 | 3 | 264 | 112 |  | drop | not resolved |
| psf__black-5297 | 2 | 53 | 2 | 2 | 244 | 392 |  | discuss | empty patch |
| psf__black-5304 | 2 | 80 | 1 | 1 | 232 | 140 |  | discuss | empty patch |
| psf__black-5386 | 2 | 69 | 1 | 1 | 172 | 645 |  | discuss | not resolved |
| psf__black-5408 | 2 | 51 | 1 | 2 | 170 | 267 |  | discuss | not resolved |
| psf__black-5411 | 2 | 56 | 1 | 3 | 166 | 238 |  | keep | not resolved |
| psf__black-5416 | 2 | 97 | 1 | 1 | 244 | 59 |  | discuss | not resolved |
| scrapy__scrapy-8189 | 3 | 35 | 1 | 113 | 0 | 20 | yes | drop | empty patch |
| scrapy__scrapy-8193 | 2 | 33 | 1 | 8 | 54 | 39 |  | discuss | not resolved |
| scrapy__scrapy-8204 | 7 | 67 | 5 | 6 | 53 | 28 |  | discuss | not resolved |
| scrapy__scrapy-8224 | 3 | 78 | 1 | 6 | 36 | 376 |  | discuss | not resolved |
