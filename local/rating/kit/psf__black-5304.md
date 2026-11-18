# psf__black-5304

- repo: `psf/black`, created: 2026-08-12, base_commit: `74371e2041a3`
- PR: https://github.com/psf/black/pull/5304
- issue: https://github.com/psf/black/issues/2943
- FAIL_TO_PASS: 1 tests, PASS_TO_PASS: 232 tests, collection_error: **no**

## 1. Issue (what the agent sees)

Remove redundant parentheses from generator expression inside function call
**Describe the style change**

I think that redundant parentheses should be removed from generators or at least be allowed to stick to next/previous parenthesis. Consider the following source example:

```python
any((
    this_very_long_method_name(obj) or another_long_method_name(obj)
    for obj in this_iterable
))
```
**Examples in the current _Black_ style**

Now black (22.1.0) formats it to

```python
any(
    (
        this_very_long_method_name(obj) or another_long_method_name(obj)
        for obj in this_iterable
    )
)
```
I think that added extra indentation level here makes source look worse.

**Desired style**

```python
any(
    this_very_long_method_name(obj) or another_long_method_name(obj)
    for obj in this_iterable
) 
```

Or at least

```python
any((
    this_very_long_method_name(obj) or another_long_method_name(obj)
    for obj in this_iterable
))
```

I would prefer the first approach (since AST of both results is the same), because this parenthesis are redundant and can be safely removed.

Related issue: #2522

## 2. Gold patch

```diff
diff --git a/CHANGES.md b/CHANGES.md
index 14fcc56680f..35377597b40 100644
--- a/CHANGES.md
+++ b/CHANGES.md
@@ -58,6 +58,7 @@
 
 <!-- Changes that affect Black's preview style -->
 
+- Remove redundant parentheses around generator expressions (#5304)
 - Preserve two blank lines before a top-level class starting inside a `# fmt: off` block
   after an import (#5238)
 - Fix unnecessary parentheses around short RHS expressions in indexed assignments like
diff --git a/docs/the_black_code_style/future_style.md b/docs/the_black_code_style/future_style.md
index 4d098aa8888..b02694c5cbc 100644
--- a/docs/the_black_code_style/future_style.md
+++ b/docs/the_black_code_style/future_style.md
@@ -45,6 +45,34 @@ Currently, the following features are included in the preview style:
   statements.
 - `fmt_off_class_blank_lines`: Preserve two blank lines before a top-level class whose
   definition starts inside a `# fmt: off` block after an import.
+- `remove_redundant_generator_parentheses`: Remove redundant parentheses around
+  generator expressions. ([see below](labels/remove-redundant-generator-parentheses))
+
+(labels/remove-redundant-generator-parentheses)=
+
+### Redundant generator parentheses
+
+Black removes extra parentheses around generator expressions. When a generator
+expression is the sole argument to a call, the call's parentheses are sufficient:
+
+```python
+# Before
+any((item.is_valid() for item in items))
+
+# After (with --preview)
+any(item.is_valid() for item in items)
+```
+
+In other contexts, Black keeps the parentheses required by Python syntax while removing
+any additional pair:
+
+```python
+# Before
+[((item for item in items)), fallback]
+
+# After (with --preview)
+[(item for item in items), fallback]
+```
 
 (labels/wrap-comprehension-in)=
 
diff --git a/src/black/linegen.py b/src/black/linegen.py
index a1177023dd7..c779580b706 100644
--- a/src/black/linegen.py
+++ b/src/black/linegen.py
@@ -377,6 +377,23 @@ def visit_power(self, node: Node) -> Iterator[Line]:
             ):
                 wrap_in_parentheses(node, leaf)
 
+        if Preview.remove_redundant_generator_parentheses in self.mode:
+            for child in node.children:
+                if (
+                    child.type == syms.trailer
+                    and len(child.children) == 3
+                    and is_lpar_token(child.children[0])
+                    and is_generator(child.children[1])
+                    and is_rpar_token(child.children[2])
+                ):
+                    maybe_make_parens_invisible_in_atom(
+                        child.children[1],
+                        parent=child,
+                        mode=self.mode,
+                        features=self.features,
+                        remove_generator_parens=True,
+                    )
+
         remove_await_parens(node, mode=self.mode, features=self.features)
 
         yield from self.visit_default(node)
@@ -568,6 +585,17 @@ def visit_NUMBER(self, leaf: Leaf) -> Iterator[Line]:
 
     def visit_atom(self, node: Node) -> Iterator[Line]:
         """Visit any atom"""
+        if (
+            Preview.remove_redundant_generator_parentheses in self.mode
+            and _has_redundant_generator_parentheses(node)
+        ):
+            maybe_make_parens_invisible_in_atom(
+                node,
+                parent=node.parent or node,
+                mode=self.mode,
+                features=self.features,
+            )
+
         if len(node.children) == 3:
             first = node.children[0]
             last = node.children[-1]
@@ -1614,6 +1642,20 @@ def _is_parenthesized_lambda_or_ternary(node: LN) -> bool:
     return False
 
 
+def _has_redundant_generator_parentheses(node: LN) -> bool:
+    """Whether `node` adds parentheses around a parenthesized generator."""
+    if (
+        node.type != syms.atom
+        or len(node.children) != 3
+        or not is_lpar_token(node.children[0])
+        or not is_rpar_token(node.children[-1])
+    ):
+        return False
+
+    middle = node.children[1]
+    return is_generator(middle) or _has_redundant_generator_parentheses(middle)
+
+
 def normalize_invisible_parens(
     node: Node, parens_after: set[str], *, mode: Mode, features: Collection[Feature]
 ) -> None:
@@ -1959,6 +2001,7 @@ def maybe_make_parens_invisible_in_atom(
     features: Collection[Feature],
     remove_brackets_around_comma: bool = False,
     allow_star_expr: bool = False,
+    remove_generator_parens: bool = False,
 ) -> bool:
     """If it's safe, make the parens in the atom `node` invisible, recursively.
     Additionally, remove repeated, adjacent invisible parens from the atom `node`
@@ -1966,6 +2009,7 @@ def maybe_make_parens_invisible_in_atom(
 
     Returns whether the node should itself be wrapped in invisible parentheses.
     """
+    can_remove_generator_parens = remove_generator_parens and is_generator(node)
     if (
         node.type not in (syms.atom, syms.expr)
         or is_empty_tuple(node)
@@ -1983,6 +2027,7 @@ def maybe_make_parens_invisible_in_atom(
             # and option to skip this check for `for` and `with` statements.
             not remove_brackets_around_comma
             and max_delimiter_priority_in_atom(node) >= COMMA_PRIORITY
+            and not can_remove_generator_parens
             # Remove parentheses around multiple exception types in except and
             # except* without as. See PEP 758 for details.
             and not (
@@ -2003,7 +2048,7 @@ def maybe_make_parens_invisible_in_atom(
         )
         or is_tuple_containing_walrus(node)
         or (not allow_star_expr and is_tuple_containing_star(node))
-        or is_generator(node)
+        or (not can_remove_generator_parens and is_generator(node))
     ):
         return False
 
diff --git a/src/black/mode.py b/src/black/mode.py
index 551e8f4cd68..4860274ea3e 100644
--- a/src/black/mode.py
+++ b/src/black/mode.py
@@ -264,6 +264,7 @@ class Preview(Enum):
     hug_comparator = auto()
     parenthesize_tuple_in_yield = auto()
     fmt_off_class_blank_lines = auto()
+    remove_redundant_generator_parentheses = auto()
 
 
 UNSTABLE_FEATURES: set[Preview] = {
diff --git a/src/black/resources/black.schema.json b/src/black/resources/black.schema.json
index 64db190152f..acf5bb0f62a 100644
--- a/src/black/resources/black.schema.json
+++ b/src/black/resources/black.schema.json
@@ -93,7 +93,8 @@
           "pyi_blank_line_after_function_docstring",
           "hug_comparator",
           "parenthesize_tuple_in_yield",
-          "fmt_off_class_blank_lines"
+          "fmt_off_class_blank_lines",
+          "remove_redundant_generator_parentheses"
         ]
       },
       "description": "Enable specific features included in the `--unstable` style. Requires `--preview`. No compatibility guarantees are provided on the behavior or existence of any unstable features."
```

## 3. Test patch

```diff
diff --git a/tests/data/cases/preview_redundant_generator_parentheses.py b/tests/data/cases/preview_redundant_generator_parentheses.py
new file mode 100644
index 00000000000..4def53930c4
--- /dev/null
+++ b/tests/data/cases/preview_redundant_generator_parentheses.py
@@ -0,0 +1,93 @@
+# flags: --preview
+
+any((x for x in items))
+service.consume((item for group in groups for item in group if item))
+factory((item for item in iterable))()
+
+((item.is_valid() for item in items))
+(((item.is_valid() for item in items)),)
+[((item.is_valid() for item in items)), ""]
+{"foo": ((item.is_valid() for item in items))}
+outer(inner(((item.is_valid() for item in items))))
+((result := transform(item) for item in items))
+((item async for item in stream()))
+next(((item for item in items)), None)
+consume(generator=((item for item in items)))
+consume(*((item for item in items)))
+
+# Power trailers still require the generator's own parentheses.
+((item for item in items)).send(None)
+((item for item in items))[0]
+((item for item in items)).attribute
+((item for item in items))()
+(item for item in items).send(None)
+(item for item in items)[0]
+(item for item in items).attribute
+(item for item in items)()
+
+any((
+    this_very_long_method_name(obj) or another_long_method_name(obj)
+    for obj in this_iterable
+))
+
+# Existing comment handling may keep the generator parentheses visible.
+any((
+    long_expression_that_exceeds_the_configured_line_length_limit_value  # inline comment
+    for item in iterable
+))
+
+# Parentheses are required when the generator is not the sole argument.
+next((item for item in iterable), None)
+enumerate((item for item in iterable), start=10)
+consume((item for item in iterable),)
+consume(*(item for item in iterable))
+consume(generator=(item for item in iterable))
+
+# output
+
+any(x for x in items)
+service.consume(item for group in groups for item in group if item)
+factory(item for item in iterable)()
+
+(item.is_valid() for item in items)
+((item.is_valid() for item in items),)
+[(item.is_valid() for item in items), ""]
+{"foo": (item.is_valid() for item in items)}
+outer(inner(item.is_valid() for item in items))
+(result := transform(item) for item in items)
+(item async for item in stream())
+next((item for item in items), None)
+consume(generator=(item for item in items))
+consume(*(item for item in items))
+
+# Power trailers still require the generator's own parentheses.
+(item for item in items).send(None)
+(item for item in items)[0]
+(item for item in items).attribute
+(item for item in items)()
+(item for item in items).send(None)
+(item for item in items)[0]
+(item for item in items).attribute
+(item for item in items)()
+
+any(
+    this_very_long_method_name(obj) or another_long_method_name(obj)
+    for obj in this_iterable
+)
+
+# Existing comment handling may keep the generator parentheses visible.
+any(
+    (
+        long_expression_that_exceeds_the_configured_line_length_limit_value  # inline comment
+        for item in iterable
+    )
+)
+
+# Parentheses are required when the generator is not the sole argument.
+next((item for item in iterable), None)
+enumerate((item for item in iterable), start=10)
+consume(
+    (item for item in iterable),
+)
+consume(*(item for item in iterable))
+consume(generator=(item for item in iterable))
```

## 4. FAIL_TO_PASS tests

- `tests/test_format.py::test_simple_format[preview_redundant_generator_parentheses]`
