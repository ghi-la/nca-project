# psf__black-5386

- repo: `psf/black`, created: 2026-09-03, base_commit: `2b96e280653f`
- PR: https://github.com/psf/black/pull/5386
- issue: https://github.com/psf/black/issues/5422
- issue: https://github.com/psf/black/issues/5379
- FAIL_TO_PASS: 1 tests, PASS_TO_PASS: 172 tests, collection_error: **no**

## 1. Issue (what the agent sees)

Fix ValueError in find_project_root for files on multiple Windows drives (#5379)
Resolves #5379.

    **Description:**
    When passing sources located on completely different Windows drives (e.g., `black C:\app\a.py D:\tmp\b.py`), `find_project_root` computes the common parents of all input paths. Because paths on separate Windows drives have no common `Path` parent, the resulting set intersection is empty. Previously, passing this empty intersection to `max()` caused an unhandled `ValueError` crash.

    This PR fixes the crash by checking if the intersection is empty before calling `max()`. If there is no common base (as is the
  case with files on different drives), it gracefully falls back to using the resolved current working directory (`Path.cwd()`) as
  the base to search for configuration files like `pyproject.toml`.

    **Changes:**
    - Updated `src/black/files.py` to handle an empty parent intersection and fallback to `Path.cwd()`.
    - Added `test_find_project_root_multiple_drives` regression test in `tests/test_black.py` (skipped on non-Windows platforms).
`find_project_root` raises `ValueError` for sources on different Windows drives
<!--
Please make sure that the bug is not already fixed either in newer versions or the
current development version. To confirm this, you have three options:

1. Update Black's version if a newer release exists: `pip install -U black`
2. Install the latest `main` branch directly:
   `pip install "black @ git+https://github.com/psf/black.git"`
3. Or run _Black_ from source on your machine:
   - create a new virtualenv (make sure it's the same Python version);
   - clone this repository;
   - run `pip install -e .[d]`;
   - run `pip install --group tests`
   - make sure it's sane by running `python -m pytest -n auto`; and
   - run `black` like you did last time.
-->

**Describe the bug**

<!-- A clear and concise description of what the bug is. -->
Running Black with source files on different Windows drives fails during project-root detection. `find_project_root` computes the common parents of all input paths and passes the result to `max()`. Absolute POSIX paths always share `/`, but paths on separate Windows drives have no common `Path` parent. The intersection is therefore empty, and `max()` raises `ValueError` during CLI startup.

This appears unrelated to [#5160](https://github.com/psf/black/issues/5160), which involves the VS Code extension and `relpath` behavior with UNC and mapped drives. This failure occurs in `src/black/files.py` when selecting the longest common parent.

**To Reproduce**

On Windows, create or select two Python files on different drives and run:

```sh
pip install black
black C:\work\app\a.py D:\tmp\b.py
```

Observed:

```
Traceback (most recent call last):
 ...
  File "D:\Work\Lib\site-packages\black\__init__.py", line 126, in read_pyproject_toml
    value = find_pyproject_toml(
        ctx.params.get("src", ()), ctx.params.get("stdin_filename", None)
    )
  File "D:\Work\Lib\site-packages\black\files.py", line 102, in find_pyproject_toml
    path_project_root, _ = find_project_root(path_search_start, stdin_filename)
                           ~~~~~~~~~~~~~~~~~^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "D:\Work\Lib\site-packages\black\files.py", line 78, in find_project_root
    common_base = max(
        set.intersection(*(set(parents) for parents in src_parents)),
        key=lambda path: path.parts,
    )
ValueError: max() iterable argument is empty
```

For these paths, the parent sets are:

```
C:\work\app\a.py -> C:\work\app, C:\work, C:\
D:\tmp\b.py      -> D:\tmp, D:\
intersection     -> empty
```

**Expected behavior**

<!-- A clear and concise description of what you expected to happen. -->
Black should handle sources on different drives without exposing an internal `ValueError`. If a shared project root is required, it should report a clear, actionable CLI error. Formatting sources from a single drive should remain unchanged.

**Environment**

<!-- Please complete the following information: -->

- Black's version: 25.9.0 (compiled: no)
- OS and Python version: Windows / CPython 3.13.9 

**Additional context**

<!-- Add any other context about the problem here. -->
The failure occurs in `_find_project_root_cached` in `src/black/files.py`, which `find_project_root` calls after resolving each input path. On Windows, `Path.resolve()` preserves the drive letter, so paths on separate drives still have no common parent.

The immediate cause is the unguarded `max()` call:

```python
common = set.intersection(*(set(parents) for parents in src_parents))
common_base = max(common, key=lambda path: path.parts)
```

Handling the empty intersection explicitly would prevent the internal exception. Depending on the intended CLI behavior, Black could either return an appropriate fallback root or raise a user-facing error explaining that the inputs are on different drives.

## 2. Gold patch

```diff
diff --git a/CHANGES.md b/CHANGES.md
index 5e5ba2aa285..2724d76371f 100644
--- a/CHANGES.md
+++ b/CHANGES.md
@@ -112,6 +112,9 @@
 
 <!-- Changes to how Black can be configured -->
 
+- Fall back to the default configuration, with a warning, when the given sources share
+  no common project root (for example, they are on different drives on Windows) instead
+  of crashing (#5386)
 - Fix `find_project_root` returning a stale cached result when `--code` is used from
   different working directories in the same process. The CWD fallback (used when no
   `srcs` are given) is now resolved before the `lru_cache` key is computed, so each
diff --git a/src/black/__init__.py b/src/black/__init__.py
index e719f817f8f..8b830d869e1 100644
--- a/src/black/__init__.py
+++ b/src/black/__init__.py
@@ -618,6 +618,20 @@ def main(
     )
     ctx.obj["root"] = root
 
+    if (
+        code is None
+        and root is None
+        and not quiet
+        and ctx.get_parameter_source("config") != ParameterSource.COMMANDLINE
+    ):
+        err(
+            "No project root could be identified: the given sources share no"
+            " common parent directory (for example, they are on different"
+            " drives). Black will use its default configuration. Pass"
+            " --config to select a configuration file or --quiet to silence"
+            " this warning."
+        )
+
     if verbose:
         if root:
             out(
@@ -717,7 +731,6 @@ def main(
             lines=lines,
         )
     else:
-        assert root is not None  # root is only None if code is not None
         try:
             sources = get_sources(
                 root=root,
@@ -778,7 +791,7 @@ def main(
 
 def get_sources(
     *,
-    root: Path,
+    root: Path | None,
     src: tuple[str, ...],
     quiet: bool,
     verbose: bool,
@@ -792,7 +805,9 @@ def get_sources(
     """Compute the set of files to be formatted."""
     sources: set[Path] = set()
 
-    assert root.is_absolute(), f"INTERNAL ERROR: `root` must be absolute but is {root}"
+    assert (
+        root is None or root.is_absolute()
+    ), f"INTERNAL ERROR: `root` must be absolute but is {root}"
     using_default_exclude = exclude is None
     exclude = re_compile_maybe_verbose(DEFAULT_EXCLUDES) if exclude is None else exclude
     gitignore: dict[Path, GitIgnoreSpec] | None = None
@@ -812,14 +827,22 @@ def get_sources(
             path = Path(s)
             is_stdin = False
 
+        # When the sources share no common parent, there is no project root.
+        # Fall back to a per-source root so that exclusion, symlink, and
+        # gitignore handling still work for each source independently.
+        if root is None:
+            src_root = path.resolve() if path.is_dir() else path.resolve().parent
+        else:
+            src_root = root
+
         # Compare the logic here to the logic in `gen_python_files`.
         if is_stdin or path.is_file():
-            if resolves_outside_root_or_cannot_stat(path, root, report):
+            if resolves_outside_root_or_cannot_stat(path, src_root, report):
                 if verbose:
                     out(f'Skipping invalid source: "{path}"', fg="red")
                 continue
 
-            root_relative_path = best_effort_relative_path(path, root).as_posix()
+            root_relative_path = best_effort_relative_path(path, src_root).as_posix()
             root_relative_path = "/" + root_relative_path
 
             # Hard-exclude any files that matches the `--force-exclude` regex.
@@ -841,19 +864,19 @@ def get_sources(
                 out(f'Found input source: "{path}"', fg="blue")
             sources.add(path)
         elif path.is_dir():
-            path = root / (path.resolve().relative_to(root))
+            path = src_root / (path.resolve().relative_to(src_root))
             if verbose:
                 out(f'Found input source directory: "{path}"', fg="blue")
 
             if using_default_exclude:
                 gitignore = {
-                    root: root_gitignore,
+                    src_root: root_gitignore,
                     path: get_gitignore(path),
                 }
             sources.update(
                 gen_python_files(
                     path.iterdir(),
-                    root,
+                    src_root,
                     include,
                     exclude,
                     extend_exclude,
diff --git a/src/black/files.py b/src/black/files.py
index 0e2d077b519..71e23241cb8 100644
--- a/src/black/files.py
+++ b/src/black/files.py
@@ -44,7 +44,7 @@ def _cached_resolve(path: Path) -> Path:
 
 def find_project_root(
     srcs: Sequence[str | Path], stdin_filename: str | None = None
-) -> tuple[Path, str]:
+) -> tuple[Path | None, str | None]:
     """Return a directory containing .git, .hg, or pyproject.toml.
 
     pyproject.toml files are only considered if they contain a [tool.black]
@@ -56,6 +56,10 @@ def find_project_root(
     If no directory in the tree contains a marker that would specify it's the
     project root, the root of the file system is returned.
 
+    If the sources share no common parent at all (for example, they live on
+    different drives on Windows), there is no project root and
+    ``(None, None)`` is returned.
+
     Returns a two-tuple with the first element as the project root path and
     the second element as a string describing the method by which the
     project root was discovered.
@@ -74,7 +78,7 @@ def find_project_root(
 
 
 @lru_cache
-def _find_project_root_cached(srcs: tuple[str, ...]) -> tuple[Path, str]:
+def _find_project_root_cached(srcs: tuple[str, ...]) -> tuple[Path | None, str | None]:
     path_srcs = [Path(src) for src in srcs]
 
     # A list of lists of parents for each 'src'. 'src' is included as a
@@ -83,10 +87,10 @@ def _find_project_root_cached(srcs: tuple[str, ...]) -> tuple[Path, str]:
         list(path.parents) + ([path] if path.is_dir() else []) for path in path_srcs
     ]
 
-    common_base = max(
-        set.intersection(*(set(parents) for parents in src_parents)),
-        key=lambda path: path.parts,
-    )
+    common_parents = set.intersection(*(set(parents) for parents in src_parents))
+    if not common_parents:
+        return None, None
+    common_base = max(common_parents, key=lambda path: path.parts)
 
     for directory in (common_base, *common_base.parents):
         if (directory / ".git").exists():
@@ -108,9 +112,10 @@ def find_pyproject_toml(
 ) -> str | None:
     """Find the absolute filepath to a pyproject.toml if it exists"""
     path_project_root, _ = find_project_root(path_search_start, stdin_filename)
-    path_pyproject_toml = path_project_root / "pyproject.toml"
-    if path_pyproject_toml.is_file():
-        return str(path_pyproject_toml)
+    if path_project_root is not None:
+        path_pyproject_toml = path_project_root / "pyproject.toml"
+        if path_pyproject_toml.is_file():
+            return str(path_pyproject_toml)
 
     try:
         path_user_pyproject_toml = find_user_pyproject_toml()
@@ -246,8 +251,10 @@ def find_user_pyproject_toml() -> Path:
 
 
 @lru_cache
-def get_gitignore(root: Path) -> GitIgnoreSpec:
+def get_gitignore(root: Path | None) -> GitIgnoreSpec:
     """Return a GitIgnoreSpec matching gitignore content if present."""
+    if root is None:
+        return GitIgnoreSpec.from_lines([])
     gitignore = root / ".gitignore"
     lines: list[str] = []
     if gitignore.is_file():
```

## 3. Test patch

```diff
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
```

## 4. FAIL_TO_PASS tests

- `tests/test_black.py::BlackTestCase::test_no_common_parent_warns_and_formats`
