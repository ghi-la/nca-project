One thing to note is that the brackets around the generator are required if the function has more than one argument
```python
>>> next(x for x in range(10))
0
>>> next(x for x in range(10), None)
  File "<stdin>", line 1
    next(x for x in range(10), None)
         ^
SyntaxError: Generator expression must be parenthesized
>>> next((x for x in range(10)), None)
0
>>> enumerate(x for x in range(10))
<enumerate object at 0x10bd7df40>
>>> enumerate(x for x in range(10), start=10)
  File "<stdin>", line 1
    enumerate(x for x in range(10), start=10)
              ^
SyntaxError: Generator expression must be parenthesized
>>> enumerate((x for x in range(10)), start=10)
<enumerate object at 0x10bd82280>
```