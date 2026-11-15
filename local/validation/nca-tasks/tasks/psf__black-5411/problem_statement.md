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

