#!/bin/bash
set -uxo pipefail
cd /testbed
git config --global --add safe.directory /testbed
git status
git -c core.fileMode=false diff 2b96e280653fd79f593c942191d8614ca6ce39e6
: no existing test files to reset
git apply -v - <<'EOF_NCA_TEST_PATCH_7f3a'
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
EOF_NCA_TEST_PATCH_7f3a
: '>>>>> Start Test Output'
pytest -rA --color=no -p no:cacheprovider --run-optional no_jupyter tests/test_format.py
: '>>>>> End Test Output'
: no existing test files to reset
