# Inter-rater agreement (rating_matteo vs rating_claude)

Tasks rated by both: 25

| score | exact agreement | Cohen's kappa | quadratic-weighted kappa | keep-boundary agreement (<=1 vs >=2) |
|---|---|---|---|---|
| spec_score | 0.52 | 0.24 | 0.54 | 0.80 |
| tests_score | 0.08 | -0.12 | 0.23 | 0.52 |

Decisions: keep=2, drop=11, discuss=12

Distribution of the worse of the two ratings (0/1/2/3):
- spec_score: 7 / 12 / 6 / 0
- tests_score: 0 / 2 / 9 / 14
