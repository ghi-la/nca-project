#!/bin/bash
set -uxo pipefail
cd /testbed
git config --global --add safe.directory /testbed
git status
git -c core.fileMode=false diff 2b96e280653fd79f593c942191d8614ca6ce39e6
: no existing test files to reset
git apply -v - <<'EOF_NCA_TEST_PATCH_7f3a'
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
EOF_NCA_TEST_PATCH_7f3a
: '>>>>> Start Test Output'
pytest -rA --color=no -p no:cacheprovider --run-optional no_jupyter tests/test_format.py
: '>>>>> End Test Output'
: no existing test files to reset
