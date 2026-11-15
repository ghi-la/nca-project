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

