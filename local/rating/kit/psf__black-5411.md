# psf__black-5411

- repo: `psf/black`, created: 2026-09-17, base_commit: `acd6198877ce`
- PR: https://github.com/psf/black/pull/5411
- issue: https://github.com/psf/black/issues/2516
- FAIL_TO_PASS: 3 tests, PASS_TO_PASS: 166 tests, collection_error: **no**

## 1. Issue (what the agent sees)

Running in Jupyter Notebook raises 'OutStream' object has no attribute 'buffer'
**Describe the bug**

When running the function `reformat_code` (and code provided as a string) inside a Jupyter Notebook (or `ipython`), it raises the following exception:

```python
Traceback (most recent call last):
  File "C:\Python37-32\lib\site-packages\black\__init__.py", line 585, in reformat_code
    content=content, fast=fast, write_back=write_back, mode=mode
  File "C:\Python37-32\lib\site-packages\black\__init__.py", line 843, in format_stdin_to_stdout
    sys.stdout.buffer, encoding=encoding, newline=newline, write_through=True
AttributeError: 'OutStream' object has no attribute 'buffer'
error: cannot format <string>: 'OutStream' object has no attribute 'buffer'
```

We can find many similar issue on Github, including [this one](https://github.com/Yelp/mrjob/issues/1441#issuecomment-249267658), which 
contains the following analysis:

> looks like stdout and stderr are ipykernel.iostream.OutStream objects, which don't have a buffer attribute, but which seem perfectly happy to accept bytes as well as unicode.

This function works perfectly fine on a regular Python file.


**To Reproduce**

You can check the following notebook:
https://colab.research.google.com/gist/jfthuong/f8732badb0e19b2109e6e05346ca3b1b/formatting-code-with-black.ipynb

Or create a new one, with:
1. `from black import WriteBack, Report, Mode, reformat_code, TargetVersion, reformat_one`
2. Create a string with some source code
3. Create `WriteBack`, `Report`, and `Mode` objects
4. Call the function `reformat_code`

```python
reformat_code(
    content=code, fast=True, write_back=write_back, mode=mode, report=report
)
```

**Expected behavior**

Reformatted code. But error is raised.

**Environment:**

- Version: black-21.9b0
- OS and Python version: Jupyter on Windows / Linux (Python 3.7)

**Does this bug also happen on main?**

Yes.

(installed with `!pip install -q git+https://github.com/psf/black/`).

**Additional context**

Inside Jupyter Notebook / ipython. OK from "regular" python `.py` file.

## 2. Gold patch

```diff
diff --git a/CHANGES.md b/CHANGES.md
index ed7e1c3931d..07fe66f5610 100644
--- a/CHANGES.md
+++ b/CHANGES.md
@@ -200,6 +200,8 @@
 <!-- Changes to Black's terminal output and error messages -->
 
 - Report parser failures using editor-friendly `path:line:column` locations (#5237)
+- Fix crash when writing formatted code or diffs to a `sys.stdout` that has no `buffer`
+  attribute, such as in Jupyter notebooks (#5411)
 
 ### _Blackd_
 
diff --git a/src/black/__init__.py b/src/black/__init__.py
index 8e834ed8315..db118f42d69 100644
--- a/src/black/__init__.py
+++ b/src/black/__init__.py
@@ -1023,15 +1023,12 @@ def format_file_in_place(
             diff_contents = color_diff(diff_contents)
 
         with lock or nullcontext():
-            f = io.TextIOWrapper(
-                sys.stdout.buffer,
+            _write_to_stdout(
+                diff_contents,
                 encoding=encoding,
                 newline=newline,
-                write_through=True,
+                wrap_for_windows=True,
             )
-            f = wrap_stream_for_windows(f)
-            f.write(diff_contents)
-            f.detach()
 
     return True
 
@@ -1068,14 +1065,11 @@ def format_stdin_to_stdout(
         return False
 
     finally:
-        f = io.TextIOWrapper(
-            sys.stdout.buffer, encoding=encoding, newline=newline, write_through=True
-        )
         if write_back == WriteBack.YES:
             # Make sure there's a newline after the content
             if dst and dst[-1] != "\n" and dst[-1] != "\r":
                 dst += newline
-            f.write(dst)
+            _write_to_stdout(dst, encoding=encoding, newline=newline)
         elif write_back in (WriteBack.DIFF, WriteBack.COLOR_DIFF):
             now = datetime.now(timezone.utc)
             src_name = f"STDIN\t{then}"
@@ -1083,9 +1077,36 @@ def format_stdin_to_stdout(
             d = diff(src, dst, src_name, dst_name)
             if write_back == WriteBack.COLOR_DIFF:
                 d = color_diff(d)
-                f = wrap_stream_for_windows(f)
-            f.write(d)
-        f.detach()
+            _write_to_stdout(
+                d,
+                encoding=encoding,
+                newline=newline,
+                wrap_for_windows=write_back == WriteBack.COLOR_DIFF,
+            )
+
+
+def _write_to_stdout(
+    content: str, *, encoding: str, newline: str, wrap_for_windows: bool = False
+) -> None:
+    """Write `content` to stdout with the given encoding and newline translation.
+
+    `sys.stdout` isn't required to expose the underlying binary `buffer` (for
+    example ipykernel's `OutStream` in Jupyter doesn't). In that case the stream
+    only accepts text, so the newline translation that `io.TextIOWrapper` would do
+    is applied here and the encoding is left to the stream itself.
+    """
+    buffer = getattr(sys.stdout, "buffer", None)
+    if buffer is None:
+        if newline != "\n":
+            content = content.replace("\n", newline)
+        stream = wrap_stream_for_windows(sys.stdout) if wrap_for_windows else sys.stdout
+        stream.write(content)
+        return
+
+    f = io.TextIOWrapper(buffer, encoding=encoding, newline=newline, write_through=True)
+    wrapped = wrap_stream_for_windows(f) if wrap_for_windows else f
+    wrapped.write(content)
+    f.detach()
 
 
 def check_stability_and_equivalence(
diff --git a/src/black/files.py b/src/black/files.py
index cdc93b3a947..0e2d077b519 100644
--- a/src/black/files.py
+++ b/src/black/files.py
@@ -1,11 +1,10 @@
-import io
 import os
 import sys
 from collections.abc import Iterable, Iterator, Sequence
 from functools import lru_cache
 from pathlib import Path
 from re import Pattern
-from typing import TYPE_CHECKING, Any, Union
+from typing import TYPE_CHECKING, Any, TextIO, Union
 
 from mypy_extensions import mypyc_attr
 from packaging.specifiers import InvalidSpecifier, Specifier, SpecifierSet
@@ -415,8 +414,8 @@ def gen_python_files(
 
 
 def wrap_stream_for_windows(
-    f: io.TextIOWrapper,
-) -> Union[io.TextIOWrapper, "colorama.AnsiToWin32"]:
+    f: TextIO,
+) -> Union[TextIO, "colorama.AnsiToWin32"]:
     """
     Wrap stream with colorama's wrap_stream so colors are shown on Windows.
```

## 3. Test patch

```diff
diff --git a/tests/test_black.py b/tests/test_black.py
index 06fc3d455c6..7ea3e78d02a 100644
--- a/tests/test_black.py
+++ b/tests/test_black.py
@@ -1473,6 +1473,73 @@ def get_output(*args: Any, **kwargs: Any) -> io.StringIO | io.TextIOWrapper:
                     output.getvalue() == expected
                 ), f"incorrect formatting of {repr(content)}"
 
+    def test_format_stdin_to_stdout_without_buffer(self) -> None:
+        # Text streams aren't required to expose `.buffer` (e.g. ipykernel's
+        # OutStream in Jupyter), see #2516.
+        src = "print ( 'hello' )"
+        for write_back, expected in (
+            (black.WriteBack.YES, 'print("hello")\n'),
+            (black.WriteBack.CHECK, ""),
+            (black.WriteBack.NO, ""),
+        ):
+            output = io.StringIO()
+            assert not hasattr(output, "buffer")
+            with patch("sys.stdout", output):
+                changed = black.format_stdin_to_stdout(
+                    fast=True, content=src, write_back=write_back, mode=DEFAULT_MODE
+                )
+            self.assertTrue(changed)
+            self.assertEqual(output.getvalue(), expected)
+            self.assertFalse(output.closed)
+
+        for write_back in (black.WriteBack.DIFF, black.WriteBack.COLOR_DIFF):
+            output = io.StringIO()
+            with patch("sys.stdout", output):
+                black.format_stdin_to_stdout(
+                    fast=True, content=src, write_back=write_back, mode=DEFAULT_MODE
+                )
+            actual = unstyle(output.getvalue())
+            self.assertIn("-print ( 'hello' )\n", actual)
+            self.assertIn('+print("hello")\n', actual)
+            self.assertFalse(output.closed)
+
+    def test_reformat_code_without_stdout_buffer(self) -> None:
+        output = io.StringIO()
+        report = MagicMock()
+        with patch("sys.stdout", output):
+            black.reformat_code(
+                "x = ( 1 )",
+                fast=True,
+                write_back=black.WriteBack.YES,
+                mode=DEFAULT_MODE,
+                report=report,
+            )
+        self.assertEqual(output.getvalue(), "x = 1\n")
+        report.failed.assert_not_called()
+
+    def test_format_file_in_place_diff_without_stdout_buffer(self) -> None:
+        for nl in ("\n", "\r\n"):
+            with TemporaryDirectory() as workspace:
+                test_file = Path(workspace) / "test.py"
+                test_file.write_bytes(f"x = ( 1 ){nl}".encode())
+                output = io.StringIO(newline="")
+                with patch("sys.stdout", output):
+                    changed = black.format_file_in_place(
+                        test_file,
+                        fast=True,
+                        mode=DEFAULT_MODE,
+                        write_back=black.WriteBack.DIFF,
+                    )
+                self.assertTrue(changed)
+                actual = output.getvalue()
+                self.assertIn(f"-x = ( 1 ){nl}", actual)
+                self.assertIn(f"+x = 1{nl}", actual)
+                if nl == "\n":
+                    self.assertNotIn("\r\n", actual)
+                self.assertFalse(output.closed)
+                # The file itself is left untouched.
+                self.assertEqual(test_file.read_bytes(), f"x = ( 1 ){nl}".encode())
+
     def test_cli_unstable(self) -> None:
         self.invokeBlack(["--unstable", "-c", "0"], exit_code=0)
         self.invokeBlack(["--preview", "-c", "0"], exit_code=0)
```

## 4. FAIL_TO_PASS tests

- `tests/test_black.py::BlackTestCase::test_format_file_in_place_diff_without_stdout_buffer`
- `tests/test_black.py::BlackTestCase::test_format_stdin_to_stdout_without_buffer`
- `tests/test_black.py::BlackTestCase::test_reformat_code_without_stdout_buffer`
