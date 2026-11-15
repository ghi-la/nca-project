Two callables sharing __name__ in one module collapse into one registered task, silently, and the two registration paths disagree about which survives
## Summary

A task's registered name is `f"{fun.__module__}.{fun.__name__}"` — `__qualname__` is never consulted. Two distinct callables that share `__name__` within one module therefore collapse into a single registered task, and a caller invoking the second one receives `SUCCESS` and the **first function's result**.

The two registration paths resolve the collision in **opposite directions**, and both are silent.

## Where

`celery/app/base.py`, `_task_from_fun`:

```python
name = name or self.gen_task_name(fun.__name__, fun.__module__)
...
if name not in self._tasks:
    ...
else:
    task = self._tasks[name]      # silently returns the other function's task
```

`celery/utils/imports.py`, `gen_task_name`:

```python
return '.'.join(p for p in (module_name, name) if p)
```

`celery/app/registry.py`, `TaskRegistry.register`: a plain `self[task.name] = task`, no membership check.

## Reproduction

```python
from celery import Celery
app = Celery('repro', broker='memory://', backend='cache+memory://')
app.conf.task_always_eager = True

def make_scaler(factor):
    @app.task
    def scale(x):
        return x * factor
    return scale

double = make_scaler(2)
triple = make_scaler(3)

r = triple.delay(10)
print(double.name, triple.name)       # repro.scale repro.scale
print(double is triple)               # False  -- two distinct proxy objects
print(r.status, r.get())              # SUCCESS 20   expected 30
```

Observed on Celery 5.6.2 (`e48dc8e`):

```
repro.scale repro.scale
False
SUCCESS 20        expected 30
warnings raised during registration: []
```

Not an artefact of eager mode — the same through a real worker over the memory broker:

```
registered names ending .scale: ['wp.scale']
worker path: result=20 (expected 30)
```

A second form, without closures — two classes in one module with same-named methods:

```
Alpha.handler.name = repro.handler
Beta.handler.name  = repro.handler
Beta.handler.delay(1) = 'alpha:1'    expected 'beta:1'
__qualname__ differs: Alpha.handler != Beta.handler
```

## The two paths disagree

```python
class T1(Task):
    name = 'dup'
    def run(self, x): return 'first'

class T2(Task):
    name = 'dup'
    def run(self, x): return 'second'

app.register_task(T1()); app.register_task(T2())
app.tasks['dup'].delay(0).get()      # 'second'
```

The decorator path keeps the **first**; `register_task` keeps the **last**. Which function actually runs under a colliding name depends on which API registered it. Neither announces anything.

## Negative controls

```
# A: explicit name= -> correct pairing
t3.delay(10) = 30    correct

# B: distinct __name__ -> correct pairing (near miss)
scale_b.delay(10) = 30    correct
```

Control B is the near miss: identical factory shape, only `__name__` differs, and it correctly does not trigger — so the failure is attributable to the name key, not to closures.

## The silence

- `warnings.simplefilter('always')` with `catch_warnings(record=True)` around both registrations: `[]`
- `logging.basicConfig(level=DEBUG)` over the whole run: 68 lines, none matching `duplic|collis|overwrit|already|conflict`
- exit code 0, `r.status == 'SUCCESS'`
- the returned proxy is a *distinct object* from the first task while dispatching to its body, so an identity check by the caller does not reveal it either

## What the docs say

`docs/userguide/tasks.rst`:

> Every task class has a unique name, and this name is referenced in messages
>
> **Every task must have a unique name.**
>
> A best practice is to use the module name as a name-space, this way names won't collide if there's already a task with that name defined in another module.

Uniqueness is stated as a requirement of the system. The remedy offered addresses collisions *across* modules; the within-module case cannot be fixed by module namespacing and is silently mis-paired.

## Note

`celery/exceptions.py` defines a public, exported, documented exception for exactly this condition:

```python
class AlreadyRegistered(Exception):
    """The task is already registered."""   # XXX Unused
```

It is never raised anywhere in the tree.

`_task_from_fun` also copies `fun.__qualname__` onto the task object about twenty lines after computing the name without it, so the disambiguating information is present at the point where it would be needed.

## Scope

The collision requires two same-named callables in one module. That arises in practice with task factories, decorated methods on multiple classes, and generated or plugin task modules — it is not exotic, but it is not the common case either.

I have not checked whether this has been discussed before; a pointer to an existing issue is welcome and I am happy to close this in favour of one.

## Version

Celery 5.6.2, source at `e48dc8e`, Python 3.12, `memory://` broker, `cache+memory://` backend.

