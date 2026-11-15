Remove redundant parentheses from generator expression inside function call
**Describe the style change**

I think that redundant parentheses should be removed from generators or at least be allowed to stick to next/previous parenthesis. Consider the following source example:

```python
any((
    this_very_long_method_name(obj) or another_long_method_name(obj)
    for obj in this_iterable
))
```
**Examples in the current _Black_ style**

Now black (22.1.0) formats it to

```python
any(
    (
        this_very_long_method_name(obj) or another_long_method_name(obj)
        for obj in this_iterable
    )
)
```
I think that added extra indentation level here makes source look worse.

**Desired style**

```python
any(
    this_very_long_method_name(obj) or another_long_method_name(obj)
    for obj in this_iterable
) 
```

Or at least

```python
any((
    this_very_long_method_name(obj) or another_long_method_name(obj)
    for obj in this_iterable
))
```

I would prefer the first approach (since AST of both results is the same), because this parenthesis are redundant and can be safely removed.

Related issue: #2522 
