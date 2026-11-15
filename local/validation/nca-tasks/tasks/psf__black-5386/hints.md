

Reproduced on Windows against current main — no real second drive needed, `resolve()` doesn't touch the media:

```pycon
>>> from pathlib import Path
>>> from black.files import find_project_root
>>> find_project_root((Path('C:/work/app/a.py'), Path('D:/tmp/b.py')), None)
ValueError: max() iterable argument is empty    # files.py:78
```

The parent sets of `C:\work\app\a.py` and `D:\tmp\b.py` intersect to ∅, so the unguarded `max()` raises during CLI startup, as reported.

Before proposing a patch, one semantics question: when sources span drives there is no common parent, hence no root to search for a `pyproject.toml` from. I see two options:

1. **Fail fast** with a clear CLI error ("sources span multiple drives — pass `--config` explicitly"). One guard in `find_project_root` + a regression test; discovery behavior for same-drive inputs unchanged.
2. **Fall back to per-source discovery** (resolve a root per input path). More useful, but broadens discovery behavior for everyone.

#5380 tried using the first source's drive root as the common base — that would search `C:\` (or `D:\`) for a `pyproject.toml`, which feels arbitrary.

My instinct is (1), but happy to implement whichever the maintainers prefer.
I believe the project root is only used for finding a config file. I think the best option is to treat it as no config found, use the default config file, and probably warn that no project root was found and the default config was used. Passing `--config` with a file path manually should silence the warning, as well as passing `--silent`.
Alternatively, Black could just error with a clear message. If this route is chosen, passing `--config` should still allow formatting to continue.