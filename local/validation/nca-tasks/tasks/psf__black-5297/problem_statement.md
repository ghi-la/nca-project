Failure to consistently format inline type comments on a multi-line attribute access
<!--
Please make sure that the bug is not already fixed either in newer versions or the
current development version. To confirm this, you have three options:

1. Update Black's version if a newer release exists: `pip install -U black`
2. Use the online formatter at <https://black.vercel.app/?version=main>, which will use
   the latest main branch.
3. Or run _Black_ on your machine:
   - create a new virtualenv (make sure it's the same Python version);
   - clone this repository;
   - run `pip install -e .[d]`;
   - run `pip install -r test_requirements.txt`
   - make sure it's sane by running `python -m pytest`; and
   - run `black` like you did last time.
-->

**Describe the bug**

<!-- A clear and concise description of what the bug is. -->
Black fails to format code containing inline type comments within a multi-line attribute access consistently (the formatting moves the type comments to the end of line in trying to collapse the attribute access, changing meaning and triggering the `INTERNAL ERROR` check).

**To Reproduce**

<!--
Minimal steps to reproduce the behavior with source code and Black's configuration.
-->

For example, take this code:

```sh-session
❯ cat /tmp/foo.py

def _get_light_style(app: sphinx.application.Sphinx) -> Style:
    return (
        app  # type: ignore[no-any-return]
            .builder
            .highlighter # type: ignore[attr-defined]
            .formatter_args["style"]
        )

```

And run it with these arguments:

```sh
❯ black /tmp/foo.py
```

The resulting error is:

> error: cannot format /tmp/foo.py: INTERNAL ERROR: Black produced code that is not equivalent to the source.  Please report a bug on https://github.com/psf/black/issues.  This diff might be helpful: /var/folders/y1/j465wvf92vs938kmgqh63bj80000gn/T/blk_3otrtpyx.log

**Expected behavior**

<!-- A clear and concise description of what you expected to happen. -->
Black preserves the inline comments between attribute accesses.

**Environment**

<!-- Please complete the following information: -->

- Black's version: 23.9.0
- OS and Python version: 3.11.0

**Additional context**

<!-- Add any other context about the problem here. -->


```sh-session
❯ cat /var/folders/y1/j465wvf92vs938kmgqh63bj80000gn/T/blk_3otrtpyx.log
--- src
+++ dst
@@ -106,8 +106,6 @@
         None,  # NoneType
     )  # /FunctionDef
   type_ignores=
     TypeIgnore(
     )  # /TypeIgnore
-    TypeIgnore(
-    )  # /TypeIgnore
 )  # /Module
\ No newline at end of file
```

```sh-session
❯ black --fast /tmp/foo.py         
reformatted /tmp/foo.py

All done! ✨ 🍰 ✨
1 file reformatted.

❯ cat /tmp/foo.py
def _get_light_style(app: sphinx.application.Sphinx) -> Style:
    return app.builder.highlighter.formatter_args[  # type: ignore[no-any-return]  # type: ignore[attr-defined]
        "style"
    ]
```

