# psf__black-5297

- repo: `psf/black`, created: 2026-08-07, base_commit: `2b96e280653f`
- PR: https://github.com/psf/black/pull/5297
- issue: https://github.com/psf/black/issues/3869
- FAIL_TO_PASS: 2 tests, PASS_TO_PASS: 244 tests, collection_error: **no**

## 1. Issue (what the agent sees)

Failure to consistently format inline type comments on a multi-line attribute access
<!--
Please make sure that the bug is not already fixed either in newer versions or the
current development version. To confirm this, you have three options:

1. Update Black's version if a newer release exists: `pip install -U black`
2. Use the online formatter at <https://black.vercel.app/?version=main>, which will use
   the latest main branch.
3. Or run _Black_ on your machine:
   - create a new virtualenv (make sure it's the same Python version);
   - clone this repository;
   - run `pip install -e .[d]`;
   - run `pip install -r test_requirements.txt`
   - make sure it's sane by running `python -m pytest`; and
   - run `black` like you did last time.
-->

**Describe the bug**

<!-- A clear and concise description of what the bug is. -->
Black fails to format code containing inline type comments within a multi-line attribute access consistently (the formatting moves the type comments to the end of line in trying to collapse the attribute access, changing meaning and triggering the `INTERNAL ERROR` check).

**To Reproduce**

<!--
Minimal steps to reproduce the behavior with source code and Black's configuration.
-->

For example, take this code:

```sh-session
❯ cat /tmp/foo.py

def _get_light_style(app: sphinx.application.Sphinx) -> Style:
    return (
        app  # type: ignore[no-any-return]
            .builder
            .highlighter # type: ignore[attr-defined]
            .formatter_args["style"]
        )

```

And run it with these arguments:

```sh
❯ black /tmp/foo.py
```

The resulting error is:

> error: cannot format /tmp/foo.py: INTERNAL ERROR: Black produced code that is not equivalent to the source.  Please report a bug on https://github.com/psf/black/issues.  This diff might be helpful: /var/folders/y1/j465wvf92vs938kmgqh63bj80000gn/T/blk_3otrtpyx.log

**Expected behavior**

<!-- A clear and concise description of what you expected to happen. -->
Black preserves the inline comments between attribute accesses.

**Environment**

<!-- Please complete the following information: -->

- Black's version: 23.9.0
- OS and Python version: 3.11.0

**Additional context**

<!-- Add any other context about the problem here. -->


```sh-session
❯ cat /var/folders/y1/j465wvf92vs938kmgqh63bj80000gn/T/blk_3otrtpyx.log
--- src
+++ dst
@@ -106,8 +106,6 @@
         None,  # NoneType
     )  # /FunctionDef
   type_ignores=
     TypeIgnore(
     )  # /TypeIgnore
-    TypeIgnore(
-    )  # /TypeIgnore
 )  # /Module
\ No newline at end of file
```

```sh-session
❯ black --fast /tmp/foo.py         
reformatted /tmp/foo.py

All done! ✨ 🍰 ✨
1 file reformatted.

❯ cat /tmp/foo.py
def _get_light_style(app: sphinx.application.Sphinx) -> Style:
    return app.builder.highlighter.formatter_args[  # type: ignore[no-any-return]  # type: ignore[attr-defined]
        "style"
    ]
```

## 2. Gold patch

```diff
diff --git a/CHANGES.md b/CHANGES.md
index 5e5ba2aa285..ce6d559756d 100644
--- a/CHANGES.md
+++ b/CHANGES.md
@@ -73,6 +73,8 @@
   `from x import (  # fmt: skip`) when a standalone comment is among the bracket's
   contents: the whole statement is now preserved instead of being reformatted (and
   previously crashing) (#5161)
+- Fix an AST safety error when separate `type: ignore` comments in a parenthesized
+  attribute chain were merged onto one physical line (#5297)
 - Preserve comments and blank lines outside requested ranges when formatting with
   `--line-ranges` (#5175)
 - Fix crash when `# fmt: skip` is used on one-line `async def`, `async with`, and
diff --git a/src/black/linegen.py b/src/black/linegen.py
index b6a0ddf66a3..463018f2f84 100644
--- a/src/black/linegen.py
+++ b/src/black/linegen.py
@@ -825,6 +825,7 @@ def transform_line(
                     string_paren_strip,
                     string_split,
                     delimiter_split,
+                    type_ignore_comment_split,
                     standalone_comment_split,
                     string_paren_wrap,
                     right_hand_split_with_omits,
@@ -841,6 +842,7 @@ def transform_line(
             if line.inside_brackets:
                 transformers = [
                     delimiter_split,
+                    type_ignore_comment_split,
                     standalone_comment_split,
                     right_hand_split_with_omits,
                 ]
@@ -1620,6 +1622,34 @@ def append_to_line(leaf: Leaf) -> Iterator[Line]:
         yield current_line
 
 
+@dont_increase_indentation
+def type_ignore_comment_split(
+    line: Line, features: Collection[Feature], mode: Mode
+) -> Iterator[Line]:
+    """Keep multiple type ignores on their original physical lines."""
+    if not line.contains_multiple_type_ignores_at_current_depth() or not any(
+        leaf.type == token.DOT for leaf in line.leaves
+    ):
+        raise CannotSplit("Line does not have multiple type ignore comments")
+
+    current_line = Line(
+        mode=line.mode, depth=line.depth, inside_brackets=line.inside_brackets
+    )
+    for leaf in line.leaves:
+        current_line.append(leaf, preformatted=True)
+        comments = line.comments_after(leaf)
+        for comment in comments:
+            current_line.append(comment, preformatted=True)
+        if any(is_type_ignore_comment(comment, mode=mode) for comment in comments):
+            yield current_line
+            current_line = Line(
+                mode=line.mode, depth=line.depth, inside_brackets=line.inside_brackets
+            )
+
+    if current_line:
+        yield current_line
+
+
 def _force_standalone_comment_split(line: Line) -> Iterator[Line]:
     """Last-resort split at every standalone-comment boundary."""
     current_line = Line(
diff --git a/src/black/lines.py b/src/black/lines.py
index b71de49e705..028d868d5fd 100644
--- a/src/black/lines.py
+++ b/src/black/lines.py
@@ -313,6 +313,18 @@ def contains_uncollapsable_type_comments(self) -> bool:
 
         return False
 
+    def contains_multiple_type_ignores_at_current_depth(self) -> bool:
+        count = 0
+        for leaf in self.leaves:
+            if leaf.bracket_depth != 0:
+                continue
+            for comment in self.comments_after(leaf):
+                if is_type_ignore_comment(comment, mode=self.mode):
+                    count += 1
+                    if count > 1:
+                        return True
+        return False
+
     def contains_unsplittable_type_ignore(self) -> bool:
         if not self.leaves:
             return False
@@ -1532,6 +1544,15 @@ def can_omit_invisible_parens(
     """
     line = rhs.body
 
+    # Multiple type ignores must stay on separate physical lines. Keeping the
+    # optional parens gives the line transformer a safe place to split them.
+    if (
+        line.contains_multiple_type_ignores_at_current_depth()
+        and not line.bracket_tracker.delimiters
+        and any(leaf.type == token.DOT for leaf in line.leaves)
+    ):
+        return False
+
     # Don't omit optional parens when the opening paren carries an inline comment.
     # Omitting them re-parents the comment onto a different leaf after the next
     # parse, which can make the RHS splitter choose a different shape on each
```

## 3. Test patch

```diff
diff --git a/tests/data/cases/type_ignore_attribute_chain.py b/tests/data/cases/type_ignore_attribute_chain.py
new file mode 100644
index 00000000000..c6d636c5fcc
--- /dev/null
+++ b/tests/data/cases/type_ignore_attribute_chain.py
@@ -0,0 +1,18 @@
+def _get_light_style(app: sphinx.application.Sphinx) -> Style:
+    return (
+        app  # type: ignore[no-any-return]
+            .builder
+            .highlighter  # type: ignore[attr-defined]
+            .formatter_args["style"]
+        )
+
+
+# output
+
+
+def _get_light_style(app: sphinx.application.Sphinx) -> Style:
+    return (
+        app  # type: ignore[no-any-return]
+        .builder.highlighter  # type: ignore[attr-defined]
+        .formatter_args["style"]
+    )
diff --git a/tests/data/cases/type_ignore_attribute_chain_unstable.py b/tests/data/cases/type_ignore_attribute_chain_unstable.py
new file mode 100644
index 00000000000..12e7eaa1c46
--- /dev/null
+++ b/tests/data/cases/type_ignore_attribute_chain_unstable.py
@@ -0,0 +1,21 @@
+# flags: --unstable
+
+
+def _get_light_style(app: sphinx.application.Sphinx) -> Style:
+    return (
+        app  # type: ignore[no-any-return]
+            .builder
+            .highlighter  # type: ignore[attr-defined]
+            .formatter_args["style"]
+        )
+
+
+# output
+
+
+def _get_light_style(app: sphinx.application.Sphinx) -> Style:
+    return (
+        app  # type: ignore[no-any-return]
+        .builder.highlighter  # type: ignore[attr-defined]
+        .formatter_args["style"]
+    )
```

## 4. FAIL_TO_PASS tests

- `tests/test_format.py::test_simple_format[type_ignore_attribute_chain]`
- `tests/test_format.py::test_simple_format[type_ignore_attribute_chain_unstable]`
