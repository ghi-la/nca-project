# psf__black-5416

- repo: `psf/black`, created: 2026-09-19, base_commit: `2b96e280653f`
- PR: https://github.com/psf/black/pull/5416
- issue: https://github.com/psf/black/issues/3080
- FAIL_TO_PASS: 1 tests, PASS_TO_PASS: 244 tests, collection_error: **no**

## 1. Issue (what the agent sees)

unnecessary parentheses in unpacking aren't removed
**Describe the style change**

Replace `(foo)` with `foo` when unpacking, where `foo` is an expression.

**Examples in the current _Black_ style**

```python
points = [(1, 2), (3, 4)]
for (x), (y) in points:
    print(x, y)
```

**Desired style**

```python
points = [(1, 2), (3, 4)]
for x, y in points:
    print(x, y)
```

## 2. Gold patch

```diff
diff --git a/CHANGES.md b/CHANGES.md
index 5e5ba2aa285..970177905f6 100644
--- a/CHANGES.md
+++ b/CHANGES.md
@@ -82,6 +82,8 @@
 
 <!-- Changes that affect Black's preview style -->
 
+- Remove redundant parentheses around individual variables in unpacking targets (for
+  example `for (x), (y) in points:` becomes `for x, y in points:`) (#5416)
 - Normalize uppercase `T` prefixes on t-strings to lowercase under `--preview` (#5425)
 - Remove redundant parentheses around generator expressions (#5304, #5369)
 - Preserve two blank lines before a top-level class starting inside a `# fmt: off` block
diff --git a/docs/the_black_code_style/future_style.md b/docs/the_black_code_style/future_style.md
index f36d1e2c0f5..9e9f16ecb1b 100644
--- a/docs/the_black_code_style/future_style.md
+++ b/docs/the_black_code_style/future_style.md
@@ -49,6 +49,30 @@ Currently, the following features are included in the preview style:
   definition starts inside a `# fmt: off` block after an import.
 - `remove_redundant_generator_parentheses`: Remove redundant parentheses around
   generator expressions. ([see below](labels/remove-redundant-generator-parentheses))
+- `remove_redundant_unpacking_parentheses`: Remove redundant parentheses around
+  individual variables in unpacking targets.
+  ([see below](labels/remove-redundant-unpacking-parentheses))
+
+(labels/remove-redundant-unpacking-parentheses)=
+
+### Redundant unpacking parentheses
+
+Black removes extra parentheses around individual variables in unpacking targets, such
+as in assignments, `for` loops, `with` statements, and `del` statements:
+
+```python
+# Before
+for (x), (y) in points:
+    pass
+
+(x), (y) = point
+
+# After (with --preview)
+for x, y in points:
+    pass
+
+x, y = point
+```
 
 (labels/remove-redundant-generator-parentheses)=
 
diff --git a/src/black/linegen.py b/src/black/linegen.py
index b6a0ddf66a3..50cbe65b3a5 100644
--- a/src/black/linegen.py
+++ b/src/black/linegen.py
@@ -705,6 +705,13 @@ def visit_tstring(self, node: Node) -> Iterator[Line]:
         # yield from self.visit_default(node)
 
     def visit_comp_for(self, node: Node) -> Iterator[Line]:
+        if (
+            Preview.remove_redundant_unpacking_parentheses in self.mode
+            and len(node.children) > 1
+        ):
+            _normalize_unpacking_targets(
+                node.children[1], mode=self.mode, features=self.features
+            )
         if Preview.wrap_comprehension_in in self.mode:
             normalize_invisible_parens(
                 node, parens_after={"in"}, mode=self.mode, features=self.features
@@ -1679,6 +1686,38 @@ def _has_redundant_generator_parentheses(node: LN) -> bool:
     return is_generator(middle) or _has_redundant_generator_parentheses(middle)
 
 
+def _normalize_unpacking_targets(
+    node: LN,
+    mode: Mode,
+    features: Collection[Feature],
+) -> None:
+    """Remove redundant parentheses from individual elements in unpacking targets."""
+    if not isinstance(node, Node):
+        return
+
+    if node.type in (
+        syms.exprlist,
+        syms.testlist_star_expr,
+        syms.testlist_gexp,
+        syms.testlist,
+        syms.listmaker,
+        syms.star_expr,
+    ):
+        for child in node.children:
+            if child.type == syms.atom and not _is_atom_multiline(child):
+                maybe_make_parens_invisible_in_atom(
+                    child,
+                    parent=node,
+                    mode=mode,
+                    features=features,
+                )
+            _normalize_unpacking_targets(child, mode=mode, features=features)
+    elif node.type == syms.atom:
+        for child in node.children:
+            if isinstance(child, Node):
+                _normalize_unpacking_targets(child, mode=mode, features=features)
+
+
 def normalize_invisible_parens(
     node: Node, parens_after: set[str], *, mode: Mode, features: Collection[Feature]
 ) -> None:
@@ -1695,6 +1734,34 @@ def normalize_invisible_parens(
             # This `node` has a prefix with `# fmt: off`, don't mess with parens.
             return
 
+    if Preview.remove_redundant_unpacking_parentheses in mode:
+        if node.type in (syms.for_stmt, syms.comp_for, syms.old_comp_for):
+            if len(node.children) > 1:
+                _normalize_unpacking_targets(
+                    node.children[1], mode=mode, features=features
+                )
+        elif node.type == syms.expr_stmt:
+            equal_indices = [
+                i for i, child in enumerate(node.children) if child.type == token.EQUAL
+            ]
+            if equal_indices:
+                for child in node.children[: equal_indices[-1]]:
+                    if child.type != token.EQUAL:
+                        _normalize_unpacking_targets(
+                            child, mode=mode, features=features
+                        )
+        elif node.type == syms.del_stmt:
+            if len(node.children) > 1:
+                _normalize_unpacking_targets(
+                    node.children[1], mode=mode, features=features
+                )
+        elif node.type == syms.with_stmt:
+            for child in node.children:
+                if child.type == syms.asexpr_test and len(child.children) > 2:
+                    _normalize_unpacking_targets(
+                        child.children[2], mode=mode, features=features
+                    )
+
     # The multiple context managers grammar has a different pattern, thus this is
     # separate from the for-loop below. This possibly wraps them in invisible parens,
     # and later will be removed in remove_with_parens when needed.
diff --git a/src/black/mode.py b/src/black/mode.py
index e5e62415790..242842d8b73 100644
--- a/src/black/mode.py
+++ b/src/black/mode.py
@@ -266,6 +266,7 @@ class Preview(Enum):
     fmt_off_class_blank_lines = auto()
     remove_redundant_generator_parentheses = auto()
     normalize_tstring_prefix = auto()
+    remove_redundant_unpacking_parentheses = auto()
 
 
 UNSTABLE_FEATURES: set[Preview] = {
diff --git a/src/black/resources/black.schema.json b/src/black/resources/black.schema.json
index 155ead0ef22..d6fcd7eb848 100644
--- a/src/black/resources/black.schema.json
+++ b/src/black/resources/black.schema.json
@@ -95,7 +95,8 @@
           "parenthesize_tuple_in_yield",
           "fmt_off_class_blank_lines",
           "remove_redundant_generator_parentheses",
-          "normalize_tstring_prefix"
+          "normalize_tstring_prefix",
+          "remove_redundant_unpacking_parentheses"
         ]
       },
       "description": "Enable specific features included in the `--unstable` style. Requires `--preview`. No compatibility guarantees are provided on the behavior or existence of any unstable features."
```

## 3. Test patch

```diff
diff --git a/tests/data/cases/preview_unpacking_parens.py b/tests/data/cases/preview_unpacking_parens.py
new file mode 100644
index 00000000000..589d2733fed
--- /dev/null
+++ b/tests/data/cases/preview_unpacking_parens.py
@@ -0,0 +1,174 @@
+# flags: --preview
+# Unnecessary parentheses in unpacking should be removed.
+
+# For loop unpacking
+points = [(1, 2), (3, 4)]
+for (x), (y) in points:
+    print(x, y)
+
+for (x), y in points:
+    pass
+
+for x, (y) in points:
+    pass
+
+for ((a), (b)) in points:
+    pass
+
+for ((a), b) in points:
+    pass
+
+for (a, (b)) in points:
+    pass
+
+for (((a)), ((b))) in points:
+    pass
+
+for a, (b, c) in points:
+    pass
+
+for a, (b,) in points:
+    pass
+
+for a, [b, c] in points:
+    pass
+
+for a, ((b, c)) in points:
+    pass
+
+for a, ((b)) in points:
+    pass
+
+# Assignment unpacking
+(a), (b) = 1, 2
+a, (b) = 1, 2
+[(a), (b)] = [1, 2]
+((a), (b)) = 1, 2
+((a), b) = 1, 2
+(a, (b)) = 1, 2
+(((a)), ((b))) = 1, 2
+a, (b, (c)) = 1, (2, 3)
+(a), (b) = (c), (d) = 1, 2
+((a), (b)) = ((c), (d)) = 1, 2
+
+# Comprehensions
+[x for (a), (b) in points]
+[x for ((a), (b)) in points]
+{k: v for (a), (b) in points}
+(x for (a), (b) in points)
+{x for (a), (b) in points}
+
+# With statement
+with lock as ((a), (b)):
+    pass
+
+with c1 as ((a), (b)), c2 as ((c), (d)):
+    pass
+
+with lock as ((a), b):
+    pass
+
+with lock as (a, (b)):
+    pass
+
+# Delete statement
+del (a), (b)
+del ((a), (b))
+del ((a), b)
+del (a, (b))
+del (((a)), ((b)))
+
+# Star expression unpacking
+*(a), (b) = 1, 2
+*((a)), (b) = 1, 2
+*(((a))), ((b)) = 1, 2
+(*((a)), (b)) = 1, 2
+(*((a)), ((b))) = 1, 2
+
+# output
+
+# Unnecessary parentheses in unpacking should be removed.
+
+# For loop unpacking
+points = [(1, 2), (3, 4)]
+for x, y in points:
+    print(x, y)
+
+for x, y in points:
+    pass
+
+for x, y in points:
+    pass
+
+for a, b in points:
+    pass
+
+for a, b in points:
+    pass
+
+for a, b in points:
+    pass
+
+for a, b in points:
+    pass
+
+for a, (b, c) in points:
+    pass
+
+for a, (b,) in points:
+    pass
+
+for a, [b, c] in points:
+    pass
+
+for a, (b, c) in points:
+    pass
+
+for a, b in points:
+    pass
+
+# Assignment unpacking
+a, b = 1, 2
+a, b = 1, 2
+[a, b] = [1, 2]
+a, b = 1, 2
+a, b = 1, 2
+a, b = 1, 2
+a, b = 1, 2
+a, (b, c) = 1, (2, 3)
+a, b = c, d = 1, 2
+a, b = (c, d) = 1, 2
+
+# Comprehensions
+[x for a, b in points]
+[x for (a, b) in points]
+{k: v for a, b in points}
+(x for a, b in points)
+{x for a, b in points}
+
+# With statement
+with lock as (a, b):
+    pass
+
+with c1 as (a, b), c2 as (c, d):
+    pass
+
+with lock as (a, b):
+    pass
+
+with lock as (a, b):
+    pass
+
+# Delete statement
+del a, b
+del (a, b)
+del (a, b)
+del (a, b)
+del (a, b)
+
+# Star expression unpacking
+*a, b = 1, 2
+*a, b = 1, 2
+*a, b = 1, 2
+*a, b = 1, 2
+*a, b = 1, 2
```

## 4. FAIL_TO_PASS tests

- `tests/test_format.py::test_simple_format[preview_unpacking_parens]`
