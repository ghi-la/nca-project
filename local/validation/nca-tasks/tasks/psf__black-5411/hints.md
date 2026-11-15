I tried making the same change suggested in the linked PR (`getattr(sys.stdout, 'buffer', sys.stdout)` instead of `sys.stdout.buffer`), but this gives

```python-traceback
Traceback (most recent call last):
  File "/Users/marcogorelli/black-dev/src/black/__init__.py", line 596, in reformat_code
    if format_stdin_to_stdout(
  File "/Users/marcogorelli/black-dev/src/black/__init__.py", line 870, in format_stdin_to_stdout
    f.write(dst)
  File "/Users/marcogorelli/.local/share/virtualenvs/black-dev-ei5accMa/lib/python3.9/site-packages/ipykernel/iostream.py", line 511, in write
    raise TypeError(
TypeError: write() argument must be str, not <class 'bytes'>
error: cannot format <string>: write() argument must be str, not <class 'bytes'>
```

I'd like to suggest that this should be fixed in `ipykernel`
> inside a Jupyter Notebook (or ipython)

I can only reproduce the error in the former. With the latter (`ipython`), it works fine:

```python
(black-dev) marcogorelli@OVMG025 black-dev % ipython
Python 3.9.6 (default, Jun 29 2021, 05:25:02) 
Type 'copyright', 'credits' or 'license' for more information
IPython 7.25.0 -- An enhanced Interactive Python. Type '?' for help.

   ...: # !pip install -q git+https://github.com/psf/black/
   ...: 
   ...: from pathlib import Path
   ...: from black import WriteBack, Report, Mode, reformat_code, TargetVersion, reformat_one
   ...: 
   ...: code = '''
   ...: file =Path("..") / "unpackai" / "utils.py"
   ...: file=Path("..") /"toto.py"
   ...: 
   ...: def iter_root_elements(
   ...:     file_path:Path
   ...: ) -> Generator[str, None, None]:
   ...:     """Extract elements at the root"""
   ...:     parsed = ast.parse(file.read_text())
   ...:     for node in ast.walk(parsed):
   ...:         if getattr(node, "col_offset", None) == 0 and any(hasattr(node, n) for n in ["name", "id"]):
   ...:             name_id = getattr(node,"name",getattr(node, "id", None))
   ...:             yield      name_id
   ...: '''
WARNING: You are using pip version 21.1.2; however, version 21.3 is available.
You should consider upgrading via the '/Users/marcogorelli/.local/share/virtualenvs/black-dev-ei5accMa/bin/python -m pip install --upgrade pip' command.

In [2]: check = False
   ...: diff = False
   ...: 
   ...: write_back = WriteBack.from_configuration(check=check, diff=diff, color=True)
   ...: report = Report(check=check, diff=diff, quiet=False, verbose=True)
   ...: mode = Mode(
   ...:     target_versions={TargetVersion.PY37},
   ...:     line_length=90,
   ...:     is_pyi=False,
   ...:     is_ipynb=False,
   ...:     string_normalization=True,
   ...:     magic_trailing_comma=False,
   ...:     experimental_string_processing=False,
   ...: )
   ...: 

In [3]: reformat_code(
   ...:     content=code, fast=True, write_back=write_back, mode=mode, report=report
   ...: )
file = Path("..") / "unpackai" / "utils.py"
file = Path("..") / "toto.py"


def iter_root_elements(file_path: Path) -> Generator[str, None, None]:
    """Extract elements at the root"""
    parsed = ast.parse(file.read_text())
    for node in ast.walk(parsed):
        if getattr(node, "col_offset", None) == 0 and any(
            hasattr(node, n) for n in ["name", "id"]
        ):
            name_id = getattr(node, "name", getattr(node, "id", None))
            yield name_id
reformatted <string>
```
@MarcoGorelli On a related topic (but not related to the issue): is there a way to get the formatted code as a string rather than printed (like `reformat_code` does)?
> @MarcoGorelli On a related topic (but not related to the issue): is there a way to get the formatted code as a string rather than printed (like `reformat_code` does)?

Does `format_file_contents` do what you want?
```python
>>> from black import Mode, format_file_contents
>>> src = '2 +2'
>>> format_file_contents(src, mode=Mode(), fast=False)
'2 + 2\n'
```
That does look like the function I'm looking for!
> That does look like the function I'm looking for!

awesome - is this all you need then, or do you have a separate use-case for running `reformat_code` inside a notebook?
OK, this is probably a bug / shortcoming of Black's code since TextIOBase is not guaranteed to have the [buffer attribute as noted in the docs](https://docs.python.org/3/library/io.html#io.TextIOBase.buffer):

> The underlying binary buffer (a BufferedIOBase instance) that TextIOBase deals with. This is not part of the TextIOBase API and may not exist in some implementations.
