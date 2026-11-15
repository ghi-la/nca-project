unnecessary parentheses in unpacking aren't removed
**Describe the style change**

Replace `(foo)` with `foo` when unpacking, where `foo` is an expression.

**Examples in the current _Black_ style**

```python
points = [(1, 2), (3, 4)]
for (x), (y) in points:
    print(x, y)
```

**Desired style**

```python
points = [(1, 2), (3, 4)]
for x, y in points:
    print(x, y)
```

