#!/bin/bash
set -uxo pipefail
cd /testbed
git config --global --add safe.directory /testbed
git status
git -c core.fileMode=false diff 74371e2041a3120a049ced8f1cab0e7a6bc8ecd3
: no existing test files to reset
git apply -v - <<'EOF_NCA_TEST_PATCH_7f3a'
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
EOF_NCA_TEST_PATCH_7f3a
: '>>>>> Start Test Output'
pytest -rA --color=no -p no:cacheprovider --run-optional no_jupyter tests/test_format.py
: '>>>>> End Test Output'
: no existing test files to reset
