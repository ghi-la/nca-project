#!/usr/bin/env python3
"""Inter-rater agreement and final task selection (stdlib only).

Usage:  python kappa.py rating_matteo.csv rating_sasha.csv
Writes: selection_<a>_vs_<b>.csv (both ratings + decision), agreement_<a>_vs_<b>.md (numbers for the report)

Decision per task: keep = both raters <= 1 on both scores; drop = both raters >= 2 on the same
score; discuss = everything else (resolve together, then edit the 'final' column by hand).
"""
import csv
import sys
from collections import Counter
from pathlib import Path

SCORES = ("spec_score", "tests_score")


def load(path):
    rows = {}
    for r in csv.DictReader(open(path)):
        vals = [r[s].strip() for s in SCORES]
        if all(v != "" for v in vals):
            rows[r["instance_id"]] = {s: int(v) for s, v in zip(SCORES, vals)}
    return rows


def cohen_kappa(a, b, weights=None, cats=range(4)):
    cats = list(cats)
    n = len(a)
    if n == 0:
        return float("nan")
    k = len(cats)
    w = [[(i - j) ** 2 / (k - 1) ** 2 if weights == "quadratic" else float(i != j) for j in cats] for i in cats]
    obs = Counter(zip(a, b))
    pa, pb = Counter(a), Counter(b)
    num = sum(w[i][j] * obs[(i, j)] / n for i in cats for j in cats)
    den = sum(w[i][j] * (pa[i] / n) * (pb[j] / n) for i in cats for j in cats)
    return 1.0 if den == 0 else 1 - num / den


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    ra, rb = load(sys.argv[1]), load(sys.argv[2])
    ids = sorted(set(ra) & set(rb))
    missing = sorted(set(ra) ^ set(rb))
    out = Path(sys.argv[1]).resolve().parent
    name_a, name_b = Path(sys.argv[1]).stem, Path(sys.argv[2]).stem
    pair = f"{name_a.removeprefix('rating_')}_vs_{name_b.removeprefix('rating_')}"

    lines = [f"# Inter-rater agreement ({name_a} vs {name_b})", "", f"Tasks rated by both: {len(ids)}"]
    if missing:
        lines.append(f"Rated by only one rater (ignored): {', '.join(missing)}")
    lines += ["", "| score | exact agreement | Cohen's kappa | quadratic-weighted kappa | keep-boundary agreement (<=1 vs >=2) |",
              "|---|---|---|---|---|"]
    for s in SCORES:
        a, b = [ra[i][s] for i in ids], [rb[i][s] for i in ids]
        exact = sum(x == y for x, y in zip(a, b)) / len(ids) if ids else float("nan")
        ba, bb = [int(x >= 2) for x in a], [int(y >= 2) for y in b]
        bound = sum(x == y for x, y in zip(ba, bb)) / len(ids) if ids else float("nan")
        lines.append(f"| {s} | {exact:.2f} | {cohen_kappa(a, b):.2f} | {cohen_kappa(a, b, 'quadratic'):.2f} | {bound:.2f} |")

    dec = Counter()
    with open(out / f"selection_{pair}.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["instance_id", f"spec_{name_a}", f"spec_{name_b}", f"tests_{name_a}", f"tests_{name_b}", "decision", "final"])
        for i in ids:
            vals = [ra[i]["spec_score"], rb[i]["spec_score"], ra[i]["tests_score"], rb[i]["tests_score"]]
            if max(vals) <= 1:
                d = "keep"
            elif min(vals[:2]) >= 2 or min(vals[2:]) >= 2:
                d = "drop"
            else:
                d = "discuss"
            dec[d] += 1
            w.writerow([i, *vals, d, d if d != "discuss" else ""])
    dist = {s: Counter(max(ra[i][s], rb[i][s]) for i in ids) for s in SCORES}
    lines += ["", f"Decisions: keep={dec['keep']}, drop={dec['drop']}, discuss={dec['discuss']}",
              "", "Distribution of the worse of the two ratings (0/1/2/3):"]
    for s in SCORES:
        lines.append(f"- {s}: " + " / ".join(str(dist[s][k]) for k in range(4)))
    (out / f"agreement_{pair}.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))
    print(f"\nwritten: selection_{pair}.csv, agreement_{pair}.md in {out}")


if __name__ == "__main__":
    main()
