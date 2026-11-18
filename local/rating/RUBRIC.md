# Rating rubric (SWE-bench Verified annotation protocol, two questions)

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
