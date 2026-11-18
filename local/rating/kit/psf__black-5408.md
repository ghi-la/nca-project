# psf__black-5408

- repo: `psf/black`, created: 2026-09-16, base_commit: `b5b1eb6f60ce`
- PR: https://github.com/psf/black/pull/5408
- issue: https://github.com/psf/black/issues/3526
- FAIL_TO_PASS: 2 tests, PASS_TO_PASS: 170 tests, collection_error: **no**

## 1. Issue (what the agent sees)

Github action could return number of changed/formatted files
**Is your feature request related to a problem? Please describe.**

The official psf/black GitHub Action does not seem to return information on its run. Other related actions such as https://github.com/rickstaa/action-black returned an is_formatted flag which could be used by subsequent steps.

If you use an "open pull request" action after the formatting step, and if black did format any file, then you can automatically open a pull request and when approved the formatted code would be committed to the original branch.

Without such a parameter if you queue an "open a pull request" github action after a "format with black" action, you would ALWAYS have a pull request, even if no files had been changed

**Describe the solution you'd like**

Have psf/black return a status or a number of files it changed.

**Describe alternatives you've considered**

none

**Additional context**

Sample workflow in github actions:

```
name: Formatting

on:
  push:
    branches: [ "main" ]
  pull_request:
    branches: [ "main" ]

jobs:
  black:
    runs-on: ubuntu-latest
    name: Format python
    
    steps:
    - name: Check out
      uses: actions/checkout@v3

    - name: Set up Python 3.10
      uses: actions/setup-python@v4
      with:
        python-version: "3.10"

    - name: Install dependencies
      run: |
        python -m pip install --upgrade pip
        pip install black autopep8 isort
        if [ -f requirements.txt ]; then pip install -r requirements.txt; fi

    - name: Format with black
      id: action_black
      uses: psf/black@stable
      with:
        options: "--verbose"
        src: "./src"

    - name: Create Pull Request
      uses: peter-evans/create-pull-request@v4
      with:
        title: "Format Python code with psf/black push"
        commit-message: "Format Python code with psf/black"
        body: "Format Python code with psf/black"
        base: main
        branch: black-format-github-action
        delete-branch: true

```

## 2. Gold patch

```diff
diff --git a/CHANGES.md b/CHANGES.md
index 87449b2e1ca..e52875157bc 100644
--- a/CHANGES.md
+++ b/CHANGES.md
@@ -220,6 +220,8 @@
 
 - Support PEP 440 version specifiers in `tool.black.required-version` for the GitHub
   Action (#5399)
+- Add outputs (`is_formatted`, `change_count`, `same_count`, `failure_count`) to GitHub
+  Action runs (#5408)
 
 ### Documentation
 
diff --git a/action.yml b/action.yml
index 733fcbebac0..dc35ddaaaad 100644
--- a/action.yml
+++ b/action.yml
@@ -41,6 +41,19 @@ inputs:
       keeping GitHub Actions logs clean when using --diff or --check.
     required: false
     default: ""
+outputs:
+  is_formatted:
+    description: "Whether any files were reformatted or would be reformatted."
+    value: ${{ steps.black.outputs.is_formatted }}
+  change_count:
+    description: "Number of files that were reformatted or would be reformatted."
+    value: ${{ steps.black.outputs.change_count }}
+  same_count:
+    description: "Number of files that were left unchanged."
+    value: ${{ steps.black.outputs.same_count }}
+  failure_count:
+    description: "Number of files that failed to reformat."
+    value: ${{ steps.black.outputs.failure_count }}
 branding:
   color: "black"
   icon: "check-circle"
@@ -48,6 +61,7 @@ runs:
   using: composite
   steps:
     - name: black
+      id: black
       run: |
         # Even when black fails, do not close the shell
         set +e
diff --git a/docs/integrations/github_actions.md b/docs/integrations/github_actions.md
index 5f540e05741..dff2ec97bbe 100644
--- a/docs/integrations/github_actions.md
+++ b/docs/integrations/github_actions.md
@@ -114,3 +114,18 @@ Here's an example configuration:
     jupyter: true
     version: "21.5b1"
 ```
+
+### Outputs
+
+The action provides the following outputs:
+
+- `is_formatted`: Set to `"true"` if any files were reformatted (or in `--check` mode,
+  would be reformatted); `"false"` otherwise. This can be used to run subsequent steps
+  conditionally (for example, auto-committing formatted changes).
+- `change_count`: Number of files that were reformatted (or would be reformatted in
+  `--check` mode).
+- `same_count`: Number of files that were left unchanged.
+- `failure_count`: Number of files that failed to reformat.
+
+These outputs are only accessible if the action version as well as `with.version` are
+both 26.10+.
diff --git a/src/black/__init__.py b/src/black/__init__.py
index e719f817f8f..70554567054 100644
--- a/src/black/__init__.py
+++ b/src/black/__init__.py
@@ -1,5 +1,6 @@
 import io
 import json
+import os
 import platform
 import re
 import sys
@@ -739,6 +740,8 @@ def main(
                 out("No Python files are present to be formatted. Nothing to do 😴")
             if "-" in src:
                 sys.stdout.write(sys.stdin.read())
+            if "GITHUB_OUTPUT" in os.environ:
+                report.write_github_outputs(Path(os.environ["GITHUB_OUTPUT"]))
             ctx.exit(0)
 
         if len(sources) == 1:
@@ -773,6 +776,8 @@ def main(
         out(error_msg if report.return_code else "All done! ✨ 🍰 ✨")
         if code is None:
             click.echo(str(report), err=True)
+    if "GITHUB_OUTPUT" in os.environ:
+        report.write_github_outputs(Path(os.environ["GITHUB_OUTPUT"]))
     ctx.exit(report.return_code)
 
 
diff --git a/src/black/report.py b/src/black/report.py
index 2736529c8e1..777cb43361c 100644
--- a/src/black/report.py
+++ b/src/black/report.py
@@ -120,3 +120,18 @@ def __str__(self) -> str:
                 style_output(f"{self.failure_count} file{s} {failed}", fg="red")
             )
         return ", ".join(report) + "."
+
+    def write_github_outputs(self, output: Path) -> None:
+        is_formatted = "true" if self.change_count > 0 else "false"
+        _outputs = {
+            "is_formatted": is_formatted,
+            "change_count": str(self.change_count),
+            "same_count": str(self.same_count),
+            "failure_count": str(self.failure_count),
+        }
+        try:
+            with output.open("a", encoding="utf-8") as f:
+                for k, v in _outputs.items():
+                    f.write(f"{k}={v}\n")
+        except OSError:
+            pass
```

## 3. Test patch

```diff
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
```

## 4. FAIL_TO_PASS tests

- `tests/test_black.py::BlackTestCase::test_github_output_in_cli`
- `tests/test_black.py::BlackTestCase::test_report_write_github_outputs`
