#!/bin/bash
set -uxo pipefail
cd /testbed
git config --global --add safe.directory /testbed
git status
git -c core.fileMode=false diff 2b96e280653fd79f593c942191d8614ca6ce39e6
git checkout 2b96e280653fd79f593c942191d8614ca6ce39e6 -- tests/test_black.py
git apply -v - <<'EOF_NCA_TEST_PATCH_7f3a'
diff --git a/tests/test_black.py b/tests/test_black.py
index cd54765292e..8ea00a8542d 100644
--- a/tests/test_black.py
+++ b/tests/test_black.py
@@ -1925,6 +1925,98 @@ def test_find_project_root(self) -> None:
                 (src_dir.resolve(), "pyproject.toml"),
             )
 
+    @pytest.mark.incompatible_with_mypyc
+    def test_find_project_root_no_common_parent(self) -> None:
+        # Absolute vs relative paths share no parents on any platform. That is
+        # the same empty-intersection situation as C:\... and D:\... on Windows.
+        cases: list[tuple[str, ...]] = [("/work/app/a.py", "tmp/b.py")]
+        if sys.platform == "win32":
+            cases.append((r"C:\work\app\a.py", r"D:\tmp\b.py"))
+
+        for srcs in cases:
+            parents = [set(Path(src).parents) for src in srcs]
+            self.assertFalse(set.intersection(*parents))
+            with self.subTest(srcs=srcs):
+                self.assertEqual(
+                    black.files._find_project_root_cached(srcs), (None, None)
+                )
+
+        if sys.platform == "win32":
+            self.assertEqual(
+                black.find_project_root((r"C:\work\app\a.py", r"D:\tmp\b.py")),
+                (None, None),
+            )
+
+    @pytest.mark.incompatible_with_mypyc
+    @patch("black.files.find_user_pyproject_toml")
+    def test_find_pyproject_toml_no_common_parent(
+        self, find_user_pyproject_toml: MagicMock
+    ) -> None:
+        if system() != "Windows":
+            return
+
+        with TemporaryDirectory() as workspace:
+            user_config = Path(workspace) / "user-pyproject.toml"
+            user_config.write_text("[tool.black]", encoding="utf-8")
+            find_user_pyproject_toml.return_value = user_config
+
+            # Sources on different drives share no project root, so the
+            # project-level config is skipped and the user-level config
+            # applies, same as when the project root has no pyproject.toml.
+            result = black.files.find_pyproject_toml(
+                (r"C:\work\app\a.py", r"D:\tmp\b.py")
+            )
+            self.assertEqual(result, str(user_config))
+
+    @pytest.mark.incompatible_with_mypyc
+    @patch("black.files.find_user_pyproject_toml")
+    @patch("black.files.find_project_root")
+    @patch("black.find_project_root")
+    def test_no_common_parent_warns_and_formats(
+        self,
+        find_project_root: MagicMock,
+        files_find_project_root: MagicMock,
+        find_user_pyproject_toml: MagicMock,
+    ) -> None:
+        find_project_root.return_value = (None, None)
+        files_find_project_root.return_value = (None, None)
+        find_user_pyproject_toml.return_value = Path("does-not-exist")
+
+        runner = BlackRunner()
+        with TemporaryDirectory() as workspace:
+            root = Path(workspace)
+            project1 = root / "project1"
+            project2 = root / "project2"
+            project1.mkdir()
+            project2.mkdir()
+            (project1 / "a.py").write_text("x=1\n", encoding="utf-8")
+            (project2 / "b.py").write_text("y=2\n", encoding="utf-8")
+
+            def invoke(args: list[str]) -> tuple[int, str]:
+                for path in (project1 / "a.py", project2 / "b.py"):
+                    path.write_text("x=1\n", encoding="utf-8")
+                result = runner.invoke(
+                    black.main,
+                    [str(project1), str(project2), *args],
+                    catch_exceptions=False,
+                )
+                return result.exit_code, result.output
+
+            exit_code, output = invoke([])
+            assert exit_code == 0, output
+            assert "No project root could be identified" in output
+            assert "reformatted" in output
+            assert "a.py" in output and "b.py" in output
+
+            exit_code, output = invoke(["--quiet"])
+            assert exit_code == 0, output
+            assert "No project root could be identified" not in output
+
+            exit_code, output = invoke(["--config", str(THIS_DIR / "empty.toml")])
+            assert exit_code == 0, output
+            assert "No project root could be identified" not in output
+            assert "reformatted" in output
+
     @patch(
         "black.files.find_user_pyproject_toml",
     )
EOF_NCA_TEST_PATCH_7f3a
: '>>>>> Start Test Output'
pytest -rA --color=no -p no:cacheprovider --run-optional no_jupyter tests/test_black.py
: '>>>>> End Test Output'
git checkout 2b96e280653fd79f593c942191d8614ca6ce39e6 -- tests/test_black.py
