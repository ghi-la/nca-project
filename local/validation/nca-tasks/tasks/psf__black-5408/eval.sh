#!/bin/bash
set -uxo pipefail
cd /testbed
git config --global --add safe.directory /testbed
git status
git -c core.fileMode=false diff b5b1eb6f60ce9febc473c6cb49f935954d108678
git checkout b5b1eb6f60ce9febc473c6cb49f935954d108678 -- tests/test_black.py
git apply -v - <<'EOF_NCA_TEST_PATCH_7f3a'
diff --git a/tests/test_black.py b/tests/test_black.py
index cd54765292e..efccb8452b2 100644
--- a/tests/test_black.py
+++ b/tests/test_black.py
@@ -743,6 +743,50 @@ def err(msg: str, **kwargs: Any) -> None:
                 " files would fail to reformat.",
             )
 
+    def test_report_write_github_outputs(self) -> None:
+        with TemporaryDirectory() as workspace:
+            output_file = Path(workspace) / "github_output"
+            report = Report()
+            report.done(Path("f1"), black.Changed.NO)
+            report.write_github_outputs(output_file)
+            content = output_file.read_text(encoding="utf-8")
+            self.assertIn("is_formatted=false\n", content)
+            self.assertIn("change_count=0\n", content)
+            self.assertIn("same_count=1\n", content)
+            self.assertIn("failure_count=0\n", content)
+
+            output_file.unlink()
+            report_quiet = Report(quiet=True)
+            report_quiet.done(Path("f2"), black.Changed.YES)
+            report_quiet.write_github_outputs(output_file)
+            content_quiet = output_file.read_text(encoding="utf-8")
+            self.assertIn("is_formatted=true\n", content_quiet)
+            self.assertIn("change_count=1\n", content_quiet)
+
+    def test_github_output_in_cli(self) -> None:
+        with TemporaryDirectory() as workspace:
+            output_file = Path(workspace) / "github_output"
+            src = Path(workspace) / "test.py"
+            src.write_text("x = 1\n", encoding="utf-8")
+            with patch.dict(os.environ, {"GITHUB_OUTPUT": str(output_file)}):
+                self.invokeBlack([str(src)])
+            content = output_file.read_text(encoding="utf-8")
+            self.assertIn("is_formatted=false\n", content)
+
+            output_file.unlink()
+            src.write_text("x =   1\n", encoding="utf-8")
+            with patch.dict(os.environ, {"GITHUB_OUTPUT": str(output_file)}):
+                self.invokeBlack([str(src), "--quiet"])
+            content = output_file.read_text(encoding="utf-8")
+            self.assertIn("is_formatted=true\n", content)
+
+            output_file.unlink()
+            src.write_text("x =   1\n", encoding="utf-8")
+            with patch.dict(os.environ, {"GITHUB_OUTPUT": str(output_file)}):
+                self.invokeBlack([str(src), "--check"], exit_code=1)
+            content = output_file.read_text(encoding="utf-8")
+            self.assertIn("is_formatted=true\n", content)
+
     def test_report_normal(self) -> None:
         report = black.Report()
         out_lines = []
EOF_NCA_TEST_PATCH_7f3a
: '>>>>> Start Test Output'
pytest -rA --color=no -p no:cacheprovider --run-optional no_jupyter tests/test_black.py
: '>>>>> End Test Output'
git checkout b5b1eb6f60ce9febc473c6cb49f935954d108678 -- tests/test_black.py
