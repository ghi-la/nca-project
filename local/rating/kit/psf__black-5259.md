# psf__black-5259

- repo: `psf/black`, created: 2026-07-25, base_commit: `364941e1c299`
- PR: https://github.com/psf/black/pull/5259
- issue: https://github.com/psf/black/issues/260
- FAIL_TO_PASS: 3 tests, PASS_TO_PASS: 264 tests, collection_error: **no**

## 1. Issue (what the agent sees)

List concatenation, multiple lines
Probably not a bug, but I was wondering if the code below shouldn't be formatted more like call chains are.
I did not expect black to change anything other than quotes in this example.
Aligned brackets feel much more readable.

```
# before
-    search_fields = (
-        ['file__%s' % field for field in FileAdmin.search_fields] +
-        ['resource__%s' % field for field in ResourceAdmin.search_fields]
-    )
# black output
+    search_fields = ["file__%s" % field for field in FileAdmin.search_fields] + [
+        "resource__%s" % field for field in ResourceAdmin.search_fields
+    ]
```

Operating system: OSX 10.11.6
Python version: 3.6.5
Black version: 18.5b0
Does also happen on master: yes

## 2. Gold patch

```diff
diff --git a/CHANGES.md b/CHANGES.md
index 1871c688ee0..c5e4152e5b4 100644
--- a/CHANGES.md
+++ b/CHANGES.md
@@ -17,6 +17,9 @@
 
 <!-- Changes that affect Black's preview style -->
 
+- Format long binary operations between collection displays symmetrically when both
+  operands fit on their own delimiter-split line (#5259)
+
 ### Configuration
 
 <!-- Changes to how Black can be configured -->
diff --git a/docs/the_black_code_style/future_style.md b/docs/the_black_code_style/future_style.md
index 2435209702c..a3dea90d492 100644
--- a/docs/the_black_code_style/future_style.md
+++ b/docs/the_black_code_style/future_style.md
@@ -51,6 +51,9 @@ Currently, the following features are included in the preview style:
   definition starts inside a `# fmt: off` block after an import.
 - `remove_redundant_generator_parentheses`: Remove redundant parentheses around
   generator expressions. ([see below](labels/remove-redundant-generator-parentheses))
+- `symmetric_collection_operations`: Keep optional parentheses around long binary
+  operations between collection displays when both operands fit on their own
+  delimiter-split line. ([see below](labels/symmetric-collection-operations))
 - `remove_redundant_unpacking_parentheses`: Remove redundant parentheses around
   individual variables in unpacking targets.
   ([see below](labels/remove-redundant-unpacking-parentheses))
@@ -287,6 +290,33 @@ any additional pair:
 [(item for item in items), fallback]
 ```
 
+(labels/symmetric-collection-operations)=
+
+### Symmetric display operations
+
+When a binary operation between two collection displays is too long for one line and
+both operands fit on their own delimiter-split line, Black keeps optional parentheses
+around the expression so that the operands can be split symmetrically. This applies to
+every arithmetic, bitwise, and symbolic comparison operator between collection displays.
+If either display needs an internal split, including when an active magic trailing comma
+forces it onto multiple lines, Black retains the existing formatting.
+
+```python
+# Before
+names = ["Alice", "Bob", "Charlie", "Diana", "Edward"] + [
+    "Fiona",
+    "George",
+    "Harriet",
+    "Isabelle",
+]
+
+# After (with --preview)
+names = (
+    ["Alice", "Bob", "Charlie", "Diana", "Edward"]
+    + ["Fiona", "George", "Harriet", "Isabelle"]
+)
+```
+
 (labels/wrap-comprehension-in)=
 
 ### Wrapping long comprehension `in` clauses
diff --git a/src/black/linegen.py b/src/black/linegen.py
index d50c94e8746..099d4262648 100644
--- a/src/black/linegen.py
+++ b/src/black/linegen.py
@@ -33,6 +33,7 @@
     can_be_split,
     can_omit_invisible_parens,
     is_line_short_enough,
+    is_symmetric_collection_binop,
     line_to_string,
 )
 from black.mode import Feature, Mode, Preview
@@ -1223,6 +1224,14 @@ def _maybe_split_omitting_optional_parens(
     features: Collection[Feature] = (),
     omit: Collection[LeafID] = (),
 ) -> Iterator[Line]:
+    split_symmetric_collection_binops = (
+        Preview.symmetric_collection_operations in mode
+        and rhs.opening_bracket.type == token.LPAR
+        and not rhs.opening_bracket.value
+        and rhs.closing_bracket.type == token.RPAR
+        and not rhs.closing_bracket.value
+        and is_symmetric_collection_binop(rhs.body, mode.line_length)
+    )
     if (
         Feature.FORCE_OPTIONAL_PARENTHESES not in features
         # the opening bracket is an optional paren
@@ -1288,6 +1297,8 @@ def _maybe_split_omitting_optional_parens(
 
     ensure_visible(rhs.opening_bracket)
     ensure_visible(rhs.closing_bracket)
+    if split_symmetric_collection_binops:
+        rhs.body.should_split_rhs = True
     for result in (rhs.head, rhs.body, rhs.tail):
         if result:
             yield result
diff --git a/src/black/lines.py b/src/black/lines.py
index c2593795f86..123b4894372 100644
--- a/src/black/lines.py
+++ b/src/black/lines.py
@@ -10,16 +10,20 @@
 from black.nodes import (
     BRACKETS,
     CLOSING_BRACKETS,
+    COMPARATORS,
+    MATH_OPERATORS,
     OPENING_BRACKETS,
     STANDALONE_COMMENT,
     TEST_DESCENDANTS,
     child_towards,
     first_leaf,
     is_docstring,
+    is_generator,
     is_import,
     is_multiline_string,
     is_one_sequence_between,
     is_one_tuple,
+    is_tuple,
     is_type_comment,
     is_type_ignore_comment,
     is_with_or_async_with_stmt,
@@ -1542,6 +1546,84 @@ def _is_annotated_assignment(head: Line) -> bool:
     return False
 
 
+def is_symmetric_collection_binop(line: Line, line_length: int) -> bool:
+    """Is `line` a binary operation between single-line collection displays?"""
+    if len(line.bracket_tracker.delimiters) != 1:
+        return False
+
+    # Delimiters is keyed by leaf ID, not line position.
+    delimiter_id = next(iter(line.bracket_tracker.delimiters))
+    try:
+        left_closing_index = next(
+            index for index, leaf in enumerate(line.leaves) if id(leaf) == delimiter_id
+        )
+    except StopIteration:
+        return False
+
+    # Math operators are split *before* the delimiter, so BracketTracker keys
+    # them by the preceding leaf.
+    delimiter_index = left_closing_index + 1
+    if delimiter_index >= len(line.leaves) - 1:
+        return False
+
+    first = line.leaves[0]
+    left_closing = line.leaves[left_closing_index]
+    delimiter = line.leaves[delimiter_index]
+    right_opening = line.leaves[delimiter_index + 1]
+    last = line.leaves[-1]
+
+    collection_display = {
+        (token.LSQB, token.RSQB),
+        (token.LPAR, token.RPAR),
+        (token.LBRACE, token.RBRACE),
+    }
+
+    def is_collection_display(opening: Leaf, closing: Leaf) -> bool:
+        if (opening.type, closing.type) not in collection_display:
+            return False
+        return opening.type != token.LPAR or (
+            opening.parent is not None
+            and is_tuple(opening.parent)
+            and not is_generator(opening.parent)
+        )
+
+    if (
+        not is_collection_display(first, left_closing)
+        or not is_collection_display(right_opening, last)
+        or delimiter.type not in MATH_OPERATORS | COMPARATORS
+        or left_closing.opening_bracket is not first
+        or last.opening_bracket is not right_opening
+    ):
+        return False
+
+    # Keep the existing asymmetric split when either display is already forced
+    # to split by a magic trailing comma.
+    if line.mode.magic_trailing_comma and (
+        line.leaves[left_closing_index - 1].type == token.COMMA
+        or line.leaves[-2].type == token.COMMA
+    ):
+        return False
+
+    def rendered_width(start: int, end: int) -> int | None:
+        leaves = line.leaves[start:end]
+        rendered = "    " * line.depth
+        # End-of-line comments do not determine whether the operand itself fits.
+        for index, leaf in enumerate(leaves):
+            rendered += leaf.value if index == 0 else str(leaf)
+        if "\n" in rendered:
+            return None
+        return str_width(rendered)
+
+    left_width = rendered_width(0, delimiter_index)
+    right_width = rendered_width(delimiter_index, len(line.leaves))
+    return (
+        left_width is not None
+        and right_width is not None
+        and left_width <= line_length
+        and right_width <= line_length
+    )
+
+
 def can_omit_invisible_parens(
     rhs: RHSResult,
     line_length: int,
@@ -1676,6 +1758,13 @@ def can_omit_invisible_parens(
             # the with statement. `rhs.head` is the `with (` part on the previous
             # line.
             return False
+        if (
+            Preview.symmetric_collection_operations in mode
+            and is_symmetric_collection_binop(line, line_length)
+        ):
+            # Retaining the optional parentheses lets the delimiter splitter put
+            # each display operand on its own line instead of exploding just one.
+            return False
         # Otherwise it may also read better, but we don't do it today and requires
         # careful considerations for all possible cases. See
         # https://github.com/psf/black/issues/2156.
diff --git a/src/black/mode.py b/src/black/mode.py
index cdcb6e713eb..4d22892fff3 100644
--- a/src/black/mode.py
+++ b/src/black/mode.py
@@ -265,6 +265,7 @@ class Preview(Enum):
     parenthesize_tuple_in_yield = auto()
     fmt_off_class_blank_lines = auto()
     remove_redundant_generator_parentheses = auto()
+    symmetric_collection_operations = auto()
     normalize_tstring_prefix = auto()
     remove_redundant_unpacking_parentheses = auto()
     fix_magic_trailing_comma_trailer_split = auto()
diff --git a/src/black/resources/black.schema.json b/src/black/resources/black.schema.json
index d17495205f7..e61000c6b23 100644
--- a/src/black/resources/black.schema.json
+++ b/src/black/resources/black.schema.json
@@ -95,6 +95,7 @@
           "parenthesize_tuple_in_yield",
           "fmt_off_class_blank_lines",
           "remove_redundant_generator_parentheses",
+          "symmetric_collection_operations",
           "normalize_tstring_prefix",
           "remove_redundant_unpacking_parentheses",
           "fix_magic_trailing_comma_trailer_split",
```

## 3. Test patch

```diff
diff --git a/tests/data/cases/preview_symmetric_list_concatenation.py b/tests/data/cases/preview_symmetric_list_concatenation.py
new file mode 100644
index 00000000000..96cd98cafa0
--- /dev/null
+++ b/tests/data/cases/preview_symmetric_list_concatenation.py
@@ -0,0 +1,249 @@
+# flags: --preview
+
+# Regression test for https://github.com/psf/black/issues/260.
+search_fields = (["file__%s" % field for field in FileAdmin.search_fields] + ["resource__%s" % field for field in ResourceAdmin.search_fields])
+
+# Plain list displays receive the same symmetric treatment.
+names = ["Alice", "Bob", "Charlie", "Diana", "Edward"] + ["Fiona", "George", "Harriet", "Isabelle"]
+
+# The matching tuple, dictionary, and set operations are also symmetric.
+tuple_values = ("first_long_value", "second_long_value") + ("third_long_value", "fourth_long_value")
+dictionary_values = {"first_long_key": first_long_value, "second_long_key": second_long_value} | {"third_long_key": third_long_value, "fourth_long_key": fourth_long_value}
+set_union = {"first_long_value", "second_long_value"} | {"third_long_value", "fourth_long_value"}
+set_intersection = {"first_long_value", "second_long_value"} & {"third_long_value", "fourth_long_value"}
+
+# Every arithmetic and bitwise binary operator gets the same treatment when both operands
+# are collections.
+collection_subtraction = ["first_long_value", "second_long_value"] - ["third_long_value", "fourth_long_value"]
+collection_product = ("first_long_value", "second_long_value") * ("third_long_value", "fourth_long_value")
+collection_division = {"first_long_value", "second_long_value"} / {"third_long_value", "fourth_long_value"}
+collection_floor_division = ["first_long_value", "second_long_value"] // ["third_long_value", "fourth_long_value"]
+collection_modulo = {"first_long_value", "second_long_value"} % {"third_long_value", "fourth_long_value"}
+collection_matrix = ["first_long_value", "second_long_value"] @ ["third_long_value", "fourth_long_value"]
+collection_power = ("first_long_value", "second_long_value") ** ("third_long_value", "fourth_long_value")
+collection_shift = {"first_long_value", "second_long_value"} << {"third_long_value", "fourth_long_value"}
+collection_right_shift = {"first_long_value", "second_long_value"} >> {"third_long_value", "fourth_long_value"}
+collection_xor = ["first_long_value", "second_long_value"] ^ ["third_long_value", "fourth_long_value"]
+mixed_collection_operands = ["first_long_value", "second_long_value"] + ("third_long_value", "fourth_long_value")
+
+# Symbolic comparisons between collection displays also split symmetrically.
+list_equality = ["first_long_value", "second_long_value"] == ["third_long_value", "fourth_long_value"]
+list_comprehension_equality = [item for item in source_items] == [first_value, second_value, third_value]
+
+# Parenthesized scalars and generator expressions are not collection displays.
+parenthesized_scalars = (first_function_with_a_really_long_name(first_argument)) + (second_function_with_a_really_long_name(second_argument))
+generator_operands = (first_item for first_item in first_collection_with_a_really_long_name) + (second_item for second_item in second_collection_with_a_really_long_name)
+
+# Comments on an operand stay attached and formatting remains stable.
+commented = (
+    ["first_long_value", "second_long_value", "third_long_value"]  # first list
+    + ["fourth_long_value", "fifth_long_value", "sixth_long_value"]
+)
+
+commented_left = (
+    ["first_value", "second_value", "third_value"]  # abc
+    + ["fourth_value", "fifth_value", "sixth_value"]
+)
+commented_right = (
+    ["first_value", "second_value", "third_value"]
+    + ["fourth_value", "fifth_value", "sixth_value"]  # abc
+)
+
+# Split symmetrically even when the RHS alone fits inside optional parentheses.
+values = [first_value, second_value, third_value] + [fourth_value, fifth_value, sixth_value]
+
+# Chained concatenations already use the normal delimiter split.
+chained = ["first_long_value", "second_long_value"] + ["third_long_value", "fourth_long_value"] + ["fifth_long_value", "sixth_long_value"]
+
+# Mixed operands are not symmetric list concatenations.
+mixed_left = ["first_long_value", "second_long_value", "third_long_value"] + tuple_with_a_very_long_name
+mixed_right = list_with_a_very_long_name + ["first_long_value", "second_long_value", "third_long_value"]
+
+# Short concatenations stay on one line.
+small = [1, 2] + [3, 4]
+
+# Lists that already require bracket splitting keep the existing formatting.
+long_left = ["first_value_with_an_extremely_long_name", "second_value_with_an_extremely_long_name", "third"] + ["short"]
+long_right = ["short"] + ["first_value_with_an_extremely_long_name", "second_value_with_an_extremely_long_name", "third"]
+both_long = ["first_value_with_an_extremely_long_name", "second_value_with_an_extremely_long_name", "third"] + ["fourth_value_with_an_extremely_long_name", "fifth_value_with_an_extremely_long_name", "sixth"]
+
+# Magic trailing commas also keep the existing formatting.
+magic_left = [
+    "first_long_value",
+    "second_long_value",
+] + ["third_long_value", "fourth_long_value"]
+magic_right = ["first_long_value", "second_long_value"] + [
+    "third_long_value",
+    "fourth_long_value",
+]
+
+# output
+
+# Regression test for https://github.com/psf/black/issues/260.
+search_fields = (
+    ["file__%s" % field for field in FileAdmin.search_fields]
+    + ["resource__%s" % field for field in ResourceAdmin.search_fields]
+)
+
+# Plain list displays receive the same symmetric treatment.
+names = (
+    ["Alice", "Bob", "Charlie", "Diana", "Edward"]
+    + ["Fiona", "George", "Harriet", "Isabelle"]
+)
+
+# The matching tuple, dictionary, and set operations are also symmetric.
+tuple_values = (
+    ("first_long_value", "second_long_value")
+    + ("third_long_value", "fourth_long_value")
+)
+dictionary_values = (
+    {"first_long_key": first_long_value, "second_long_key": second_long_value}
+    | {"third_long_key": third_long_value, "fourth_long_key": fourth_long_value}
+)
+set_union = (
+    {"first_long_value", "second_long_value"}
+    | {"third_long_value", "fourth_long_value"}
+)
+set_intersection = (
+    {"first_long_value", "second_long_value"}
+    & {"third_long_value", "fourth_long_value"}
+)
+
+# Every arithmetic and bitwise binary operator gets the same treatment when both operands
+# are collections.
+collection_subtraction = (
+    ["first_long_value", "second_long_value"]
+    - ["third_long_value", "fourth_long_value"]
+)
+collection_product = (
+    ("first_long_value", "second_long_value")
+    * ("third_long_value", "fourth_long_value")
+)
+collection_division = (
+    {"first_long_value", "second_long_value"}
+    / {"third_long_value", "fourth_long_value"}
+)
+collection_floor_division = (
+    ["first_long_value", "second_long_value"]
+    // ["third_long_value", "fourth_long_value"]
+)
+collection_modulo = (
+    {"first_long_value", "second_long_value"}
+    % {"third_long_value", "fourth_long_value"}
+)
+collection_matrix = (
+    ["first_long_value", "second_long_value"]
+    @ ["third_long_value", "fourth_long_value"]
+)
+collection_power = (
+    ("first_long_value", "second_long_value")
+    ** ("third_long_value", "fourth_long_value")
+)
+collection_shift = (
+    {"first_long_value", "second_long_value"}
+    << {"third_long_value", "fourth_long_value"}
+)
+collection_right_shift = (
+    {"first_long_value", "second_long_value"}
+    >> {"third_long_value", "fourth_long_value"}
+)
+collection_xor = (
+    ["first_long_value", "second_long_value"]
+    ^ ["third_long_value", "fourth_long_value"]
+)
+mixed_collection_operands = (
+    ["first_long_value", "second_long_value"]
+    + ("third_long_value", "fourth_long_value")
+)
+
+# Symbolic comparisons between collection displays also split symmetrically.
+list_equality = (
+    ["first_long_value", "second_long_value"]
+    == ["third_long_value", "fourth_long_value"]
+)
+list_comprehension_equality = (
+    [item for item in source_items]
+    == [first_value, second_value, third_value]
+)
+
+# Parenthesized scalars and generator expressions are not collection displays.
+parenthesized_scalars = (first_function_with_a_really_long_name(first_argument)) + (
+    second_function_with_a_really_long_name(second_argument)
+)
+generator_operands = (
+    first_item for first_item in first_collection_with_a_really_long_name
+) + (second_item for second_item in second_collection_with_a_really_long_name)
+
+# Comments on an operand stay attached and formatting remains stable.
+commented = (
+    ["first_long_value", "second_long_value", "third_long_value"]  # first list
+    + ["fourth_long_value", "fifth_long_value", "sixth_long_value"]
+)
+
+commented_left = (
+    ["first_value", "second_value", "third_value"]  # abc
+    + ["fourth_value", "fifth_value", "sixth_value"]
+)
+commented_right = (
+    ["first_value", "second_value", "third_value"]
+    + ["fourth_value", "fifth_value", "sixth_value"]  # abc
+)
+
+# Split symmetrically even when the RHS alone fits inside optional parentheses.
+values = (
+    [first_value, second_value, third_value]
+    + [fourth_value, fifth_value, sixth_value]
+)
+
+# Chained concatenations already use the normal delimiter split.
+chained = (
+    ["first_long_value", "second_long_value"]
+    + ["third_long_value", "fourth_long_value"]
+    + ["fifth_long_value", "sixth_long_value"]
+)
+
+# Mixed operands are not symmetric list concatenations.
+mixed_left = [
+    "first_long_value",
+    "second_long_value",
+    "third_long_value",
+] + tuple_with_a_very_long_name
+mixed_right = list_with_a_very_long_name + [
+    "first_long_value",
+    "second_long_value",
+    "third_long_value",
+]
+
+# Short concatenations stay on one line.
+small = [1, 2] + [3, 4]
+
+# Lists that already require bracket splitting keep the existing formatting.
+long_left = [
+    "first_value_with_an_extremely_long_name",
+    "second_value_with_an_extremely_long_name",
+    "third",
+] + ["short"]
+long_right = ["short"] + [
+    "first_value_with_an_extremely_long_name",
+    "second_value_with_an_extremely_long_name",
+    "third",
+]
+both_long = [
+    "first_value_with_an_extremely_long_name",
+    "second_value_with_an_extremely_long_name",
+    "third",
+] + [
+    "fourth_value_with_an_extremely_long_name",
+    "fifth_value_with_an_extremely_long_name",
+    "sixth",
+]
+
+# Magic trailing commas also keep the existing formatting.
+magic_left = [
+    "first_long_value",
+    "second_long_value",
+] + ["third_long_value", "fourth_long_value"]
+magic_right = ["first_long_value", "second_long_value"] + [
+    "third_long_value",
+    "fourth_long_value",
+]
diff --git a/tests/data/cases/preview_symmetric_list_concatenation_line_length.py b/tests/data/cases/preview_symmetric_list_concatenation_line_length.py
new file mode 100644
index 00000000000..c847e737490
--- /dev/null
+++ b/tests/data/cases/preview_symmetric_list_concatenation_line_length.py
@@ -0,0 +1,12 @@
+# flags: --preview --line-length=60
+
+values = [first_value, second_value] + [third_value, fourth_value]
+short_values = [first_value] + [second_value]
+
+# output
+
+values = (
+    [first_value, second_value]
+    + [third_value, fourth_value]
+)
+short_values = [first_value] + [second_value]
diff --git a/tests/data/cases/preview_symmetric_list_concatenation_skip_magic.py b/tests/data/cases/preview_symmetric_list_concatenation_skip_magic.py
new file mode 100644
index 00000000000..e2249ba52bb
--- /dev/null
+++ b/tests/data/cases/preview_symmetric_list_concatenation_skip_magic.py
@@ -0,0 +1,15 @@
+# flags: --preview --skip-magic-trailing-comma
+
+# Ignored trailing commas do not prevent symmetric formatting.
+values = [
+    "first_long_value",
+    "second_long_value",
+] + ["third_long_value", "fourth_long_value"]
+
+# output
+
+# Ignored trailing commas do not prevent symmetric formatting.
+values = (
+    ["first_long_value", "second_long_value"]
+    + ["third_long_value", "fourth_long_value"]
+)
diff --git a/tests/data/cases/stable_symmetric_list_concatenation.py b/tests/data/cases/stable_symmetric_list_concatenation.py
new file mode 100644
index 00000000000..7fc4963b167
--- /dev/null
+++ b/tests/data/cases/stable_symmetric_list_concatenation.py
@@ -0,0 +1,4 @@
+# Stable style must keep the existing asymmetric bracket split.
+search_fields = ["file__%s" % field for field in FileAdmin.search_fields] + [
+    "resource__%s" % field for field in ResourceAdmin.search_fields
+]
```

## 4. FAIL_TO_PASS tests

- `tests/test_format.py::test_simple_format[preview_symmetric_list_concatenation]`
- `tests/test_format.py::test_simple_format[preview_symmetric_list_concatenation_line_length]`
- `tests/test_format.py::test_simple_format[preview_symmetric_list_concatenation_skip_magic]`
