# Inter-rater agreement (rating_sasha vs rating_claude)

Tasks rated by both: 25

| score | exact agreement | Cohen's kappa | quadratic-weighted kappa | keep-boundary agreement (<=1 vs >=2) |
|---|---|---|---|---|
| spec_score | 0.72 | 0.57 | 0.78 | 0.96 |
| tests_score | 0.64 | 0.32 | 0.69 | 1.00 |

Decisions: keep=2, drop=23, discuss=0

Distribution of the worse of the two ratings (0/1/2/3):
- spec_score: 4 / 14 / 5 / 2
- tests_score: 1 / 1 / 3 / 20
