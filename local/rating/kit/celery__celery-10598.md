# celery__celery-10598

- repo: `celery/celery`, created: 2026-09-10, base_commit: `1a3ea2eb8b4e`
- PR: https://github.com/celery/celery/pull/10598
- issue: https://github.com/celery/celery/issues/10576
- FAIL_TO_PASS: 175 tests, PASS_TO_PASS: 0 tests, collection_error: **yes**

## 1. Issue (what the agent sees)

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

## 2. Gold patch

```diff
diff --git a/celery/app/base.py b/celery/app/base.py
index ff056fff74b..63b3e36a3f1 100644
--- a/celery/app/base.py
+++ b/celery/app/base.py
@@ -28,14 +28,14 @@
 from celery import platforms, signals
 from celery._state import (_announce_app_finalized, _deregister_app, _register_app, _set_current_app, _task_stack,
                            connect_on_app_finalize, get_current_app, get_current_worker_task, set_default_app)
-from celery.exceptions import AlwaysEagerIgnored, ImproperlyConfigured, OperationalError
+from celery.exceptions import AlwaysEagerIgnored, DuplicateTaskNameWarning, ImproperlyConfigured, OperationalError
 from celery.loaders import get_loader_cls
 from celery.local import PromiseProxy, maybe_evaluate
 from celery.utils import abstract
 from celery.utils.collections import AttributeDictMixin
 from celery.utils.dispatch import Signal
 from celery.utils.functional import first, head_from_fun, maybe_list
-from celery.utils.imports import gen_task_name, instantiate, symbol_by_name
+from celery.utils.imports import gen_task_name, instantiate, qualname, symbol_by_name
 from celery.utils.log import get_logger
 from celery.utils.objects import FallbackContext, mro_lookup
 from celery.utils.time import maybe_make_aware, timezone, to_utc
@@ -99,6 +99,44 @@ def _get_annotations(fun):
 """
 
 
+W_DUPTASK = """\
+Task name {0!r} is already registered to a different callable.
+
+Existing: {1}
+New:      {2}
+
+{3}
+
+Every task must have a unique name. Pass an explicit name= to the task \
+decorator, or rename one of the callables.\
+"""
+
+
+def frame_is_celery(frame):
+    """Return true if *frame* is executing Celery's own code."""
+    module = frame.f_globals.get('__name__', '')
+    return module == 'celery' or module.startswith('celery.')
+
+
+def caller_stacklevel():
+    """Depth of the first frame outside Celery, for :func:`warnings.warn`.
+
+    A task can be registered straight from the decorator or later, when a
+    :class:`~celery.local.PromiseProxy` is first evaluated, and those two
+    paths sit at different depths -- so the level is found rather than
+    assumed. Only reached when a warning is actually emitted.
+    """
+    frame, level = sys._getframe(1), 1
+    while frame is not None and frame_is_celery(frame):
+        frame, level = frame.f_back, level + 1
+    return level
+
+
+def task_callable_qualname(task):
+    """Name the callable behind *task*, decorated or class-based."""
+    return qualname(getattr(task, '_decorated_fun', None) or type(task))
+
+
 def app_has_custom(app, attr):
     """Return true if app has customized method `attr`.
 
@@ -388,6 +426,7 @@ def __init__(self, main=None, loader=None, backend=None,
         self.finalized = False
         self._finalize_mutex = threading.RLock()
         self._pending = deque()
+        self._duplicate_task_names_warned = set()
         self._tasks = tasks
         if not isinstance(self._tasks, TaskRegistry):
             self._tasks = self.registry_cls(self._tasks or {})
@@ -609,6 +648,10 @@ def _task_from_fun(
     ):
         if not self.finalized and not self.autofinalize:
             raise RuntimeError('Contract breach: app not finalized')
+        # the callable as the caller passed it, kept before the pydantic
+        # rebind below and before ``run`` turns it into a descriptor, so
+        # that a re-registration can be recognised by identity.
+        decorated_fun = fun
         name = name or self.gen_task_name(fun.__name__, fun.__module__)
         base = base or self.Task
 
@@ -626,7 +669,8 @@ def _task_from_fun(
                 '__module__': fun.__module__,
                 '__annotations__': _get_annotations(fun),
                 '__header__': self.type_checker(fun, bound=bind),
-                '__wrapped__': run}, **options))()
+                '__wrapped__': run,
+                '_decorated_fun': staticmethod(decorated_fun)}, **options))()
             # for some reason __qualname__ cannot be set in type()
             # so we have to set it here.
             try:
@@ -638,6 +682,7 @@ def _task_from_fun(
             add_autoretry_behaviour(task, **options)
         else:
             task = self._tasks[name]
+            self._warn_if_duplicate_task_name(task, decorated_fun, name)
         return task
 
     def register_task(self, task, **options):
@@ -653,12 +698,56 @@ def register_task(self, task, **options):
             task_cls = type(task)
             task.name = self.gen_task_name(
                 task_cls.__name__, task_cls.__module__)
+        existing = self.tasks.get(task.name)
+        if existing is not None and existing is not task:
+            self._warn_duplicate_task_name(
+                task.name, task_callable_qualname(existing),
+                task_callable_qualname(task),
+                'The new callable replaced the existing one; calls under this '
+                'name now reach the new callable.',
+            )
         add_autoretry_behaviour(task, **options)
         self.tasks[task.name] = task
         task._app = self
         task.bind(self)
         return task
 
+    def _warn_if_duplicate_task_name(self, task, fun, name):
+        """Warn when *name* is taken by a callable other than *fun*.
+
+        A module imported twice hands the same function object back, so
+        identity -- not the name -- is what tells a re-registration apart
+        from two distinct callables colliding under one generated name.
+        The comparison uses the callable as the caller passed it, since
+        ``__wrapped__`` holds ``run``, which is a bound method under
+        ``bind=True`` and the wrapper under ``pydantic=True``.
+        """
+        existing_fun = getattr(task, '_decorated_fun', None)
+        if existing_fun is None or existing_fun is fun:
+            return
+        self._warn_duplicate_task_name(
+            name, qualname(existing_fun), qualname(fun),
+            'The new callable was not registered; calls under this name '
+            'reach the callable registered first.',
+        )
+
+    def _warn_duplicate_task_name(self, name, existing, new, consequence):
+        # One warning per name. A colliding name is a single mistake, and
+        # a module or test suite that trips it repeatedly should not bury
+        # everything else in output. The set only grows, and a concurrent
+        # registration could race on this check and warn twice; both are
+        # accepted, as registration is an import-time, single-threaded
+        # activity and the cost of either is one extra line of output.
+        if name in self._duplicate_task_names_warned:
+            return
+        self._duplicate_task_names_warned.add(name)
+        warnings.warn(
+            DuplicateTaskNameWarning(
+                W_DUPTASK.format(name, existing, new, consequence),
+            ),
+            stacklevel=caller_stacklevel(),
+        )
+
     def gen_task_name(self, name, module):
         return gen_task_name(self, name, module)
 
diff --git a/celery/exceptions.py b/celery/exceptions.py
index 3203e9f49ea..9055cc0c272 100644
--- a/celery/exceptions.py
+++ b/celery/exceptions.py
@@ -42,6 +42,7 @@
     - :class:`~celery.exceptions.CeleryWarning`
         - :class:`~celery.exceptions.AlwaysEagerIgnored`
         - :class:`~celery.exceptions.DuplicateNodenameWarning`
+        - :class:`~celery.exceptions.DuplicateTaskNameWarning`
         - :class:`~celery.exceptions.FixupWarning`
         - :class:`~celery.exceptions.NotConfigured`
         - :class:`~celery.exceptions.SecurityWarning`
@@ -62,7 +63,8 @@
     # Warnings
     'CeleryWarning',
     'AlwaysEagerIgnored', 'DuplicateNodenameWarning',
-    'FixupWarning', 'NotConfigured', 'SecurityWarning',
+    'DuplicateTaskNameWarning', 'FixupWarning', 'NotConfigured',
+    'SecurityWarning',
 
     # Core errors
     'CeleryError',
@@ -122,6 +124,10 @@ class DuplicateNodenameWarning(CeleryWarning):
     """Multiple workers are using the same nodename."""
 
 
+class DuplicateTaskNameWarning(CeleryWarning):
+    """Multiple callables are registered under the same task name."""
+
+
 class FixupWarning(CeleryWarning):
     """Fixup related warning."""
```

## 3. Test patch

```diff
diff --git a/t/unit/app/test_app.py b/t/unit/app/test_app.py
index ec102844dd1..cac475028ce 100644
--- a/t/unit/app/test_app.py
+++ b/t/unit/app/test_app.py
@@ -7,6 +7,7 @@
 import sys
 import typing
 import uuid
+import warnings
 from copy import deepcopy
 from datetime import datetime, timedelta
 from datetime import timezone as datetime_timezone
@@ -18,7 +19,9 @@
 import pytest
 from kombu import Exchange, Queue
 from kombu.exceptions import LimitExceeded
-from pydantic import BaseModel, ValidationInfo, model_validator
+from pydantic import BaseModel
+from pydantic import BaseModel as PydanticBaseModel
+from pydantic import ValidationInfo, model_validator
 from vine import promise
 
 from celery import Celery, _state
@@ -29,7 +32,7 @@
 from celery.app.amqp import AMQP
 from celery.backends.base import Backend
 from celery.contrib.testing.mocks import ContextMock
-from celery.exceptions import ImproperlyConfigured, OperationalError
+from celery.exceptions import DuplicateTaskNameWarning, ImproperlyConfigured, OperationalError
 from celery.loaders.base import unconfigured
 from celery.platforms import pyimplementation
 from celery.utils.collections import DictAttribute
@@ -147,6 +150,220 @@ def test_setup_security(self, setup_security):
             {'json'}, 'key', None, 'cert', 'store', 'digest', 'serializer',
             app=self.app)
 
+    def test_duplicate_task_name_warns__closure(self):
+        """Two closures share __name__, __qualname__ and __code__."""
+        def make_scaler(factor):
+            @self.app.task(shared=False)
+            def scale(x):
+                return x * factor
+            return scale
+
+        with pytest.warns(DuplicateTaskNameWarning) as w:
+            double, triple = make_scaler(2), make_scaler(3)
+            assert double.name == triple.name
+
+        assert double.name in str(w[0].message)
+
+    def test_duplicate_task_name_warns__same_method_name(self):
+        with pytest.warns(DuplicateTaskNameWarning):
+            class Alpha:
+                @staticmethod
+                @self.app.task(shared=False)
+                def handler(x):
+                    return 'alpha'
+
+            class Beta:
+                @staticmethod
+                @self.app.task(shared=False)
+                def handler(x):
+                    return 'beta'
+
+            assert Alpha.handler.name == Beta.handler.name
+
+    def test_duplicate_task_name_warns__register_task(self):
+        from celery.app.task import Task
+
+        class T1(Task):
+            name = 'dup'
+
+            def run(self, x):
+                return 'first'
+
+        class T2(Task):
+            name = 'dup'
+
+            def run(self, x):
+                return 'second'
+
+        self.app.register_task(T1())
+        with pytest.warns(DuplicateTaskNameWarning) as w:
+            self.app.register_task(T2())
+        assert 'replaced' in str(w[0].message)
+
+    def test_duplicate_task_name_warns_once_per_name(self):
+        """A third callable under the same name must not warn again."""
+        def make_scaler(factor):
+            @self.app.task(shared=False)
+            def scale(x):
+                return x * factor
+            return scale
+
+        with pytest.warns(DuplicateTaskNameWarning) as w:
+            first, second = make_scaler(2), make_scaler(3)
+            assert first.name == second.name
+
+        with warnings.catch_warnings(record=True) as again:
+            warnings.simplefilter('always')
+            third = make_scaler(4)
+            assert third.name == first.name
+        assert len(w) == 1
+        assert not [x for x in again
+                    if isinstance(x.message, DuplicateTaskNameWarning)]
+
+    def test_duplicate_task_name_silent__no_recorded_callable(self):
+        """A task registered by class carries no callable to compare."""
+        from celery.app.task import Task
+
+        class T(Task):
+            name = 'shared.name'
+
+            def run(self, x):
+                return x
+
+        self.app.register_task(T())
+
+        def other(x):
+            return x
+
+        with warnings.catch_warnings(record=True) as w:
+            warnings.simplefilter('always')
+            task = self.app._task_from_fun(other, name='shared.name')
+            assert task.name == 'shared.name'
+        assert not [x for x in w
+                    if isinstance(x.message, DuplicateTaskNameWarning)]
+
+    def test_duplicate_task_name_register_task_names_the_function(self):
+        """register_task reports a decorated task by its function."""
+        @self.app.task(name='taken.name', shared=False)
+        def decorated(x):
+            return x
+
+        assert decorated.name == 'taken.name'
+
+        from celery.app.task import Task
+
+        class T(Task):
+            name = 'taken.name'
+
+            def run(self, x):
+                return x
+
+        with pytest.warns(DuplicateTaskNameWarning) as w:
+            self.app.register_task(T())
+        assert 'decorated' in str(w[0].message)
+
+    def test_duplicate_task_name_silent__explicit_names(self):
+        """Negative control: distinct explicit names must not warn."""
+        def make_scaler(factor):
+            @self.app.task(name=f'scale{factor}', shared=False)
+            def scale(x):
+                return x * factor
+            return scale
+
+        with warnings.catch_warnings(record=True) as w:
+            warnings.simplefilter('always')
+            double, triple = make_scaler(2), make_scaler(3)
+            assert double.name != triple.name
+        assert not [x for x in w
+                    if isinstance(x.message, DuplicateTaskNameWarning)]
+
+    def test_duplicate_task_name_silent__distinct_names(self):
+        """Negative control (near miss): only __name__ differs."""
+        with warnings.catch_warnings(record=True) as w:
+            warnings.simplefilter('always')
+
+            @self.app.task(shared=False)
+            def scale_a(x):
+                return x * 2
+
+            @self.app.task(shared=False)
+            def scale_b(x):
+                return x * 3
+
+            assert scale_a.name != scale_b.name
+        assert not [x for x in w
+                    if isinstance(x.message, DuplicateTaskNameWarning)]
+
+    def test_duplicate_task_name_silent__same_function_twice_bound(self):
+        """Negative control: ``run`` is a bound method under bind=True."""
+        def plain(x):
+            return x
+
+        with warnings.catch_warnings(record=True) as w:
+            warnings.simplefilter('always')
+            first = self.app._task_from_fun(plain, bind=True)
+            second = self.app._task_from_fun(plain, bind=True)
+            assert first is second
+        assert not [x for x in w
+                    if isinstance(x.message, DuplicateTaskNameWarning)]
+
+    def test_duplicate_task_name_silent__same_function_twice_pydantic(self):
+        """Negative control: ``fun`` is rebound by the pydantic wrapper."""
+        class Args(PydanticBaseModel):
+            x: int
+
+        def pydantic_fun(args: Args):
+            return args.x
+
+        with warnings.catch_warnings(record=True) as w:
+            warnings.simplefilter('always')
+            first = self.app._task_from_fun(pydantic_fun, pydantic=True)
+            second = self.app._task_from_fun(pydantic_fun, pydantic=True)
+            assert first is second
+        assert not [x for x in w
+                    if isinstance(x.message, DuplicateTaskNameWarning)]
+
+    def test_duplicate_task_name_warns__bound_closures(self):
+        """bind=True must still detect two distinct callables."""
+        def make_scaler(factor):
+            @self.app.task(shared=False, bind=True)
+            def scale(self, x):
+                return x * factor
+            return scale
+
+        with pytest.warns(DuplicateTaskNameWarning):
+            double, triple = make_scaler(2), make_scaler(3)
+            assert double.name == triple.name
+
+    def test_duplicate_task_name_warning_points_at_the_caller(self):
+        """The warning must name the caller's frame, not celery's."""
+        def make_scaler(factor):
+            @self.app.task(shared=False)
+            def scale(x):
+                return x * factor
+            return scale
+
+        with pytest.warns(DuplicateTaskNameWarning) as w:
+            double, triple = make_scaler(2), make_scaler(3)
+            assert double.name == triple.name
+
+        assert not w[0].filename.endswith(
+            os.path.join('celery', 'app', 'base.py'))
+        assert w[0].filename == __file__
+
+    def test_duplicate_task_name_silent__same_function_twice(self):
+        """Negative control: a re-imported module yields the same object."""
+        def plain(x):
+            return x
+
+        with warnings.catch_warnings(record=True) as w:
+            warnings.simplefilter('always')
+            first = self.app._task_from_fun(plain)
+            second = self.app._task_from_fun(plain)
+            assert first is second
+        assert not [x for x in w
+                    if isinstance(x.message, DuplicateTaskNameWarning)]
+
     def test_task_autofinalize_disabled(self):
         with self.Celery('xyzibari', autofinalize=False) as app:
             @app.task
```

## 4. FAIL_TO_PASS tests (first 40)

- `t/unit/app/test_app.py::test_App::test_AsyncResult`
- `t/unit/app/test_app.py::test_App::test_Beat`
- `t/unit/app/test_app.py::test_App::test_Windows_log_color_disabled`
- `t/unit/app/test_app.py::test_App::test_WorkController`
- `t/unit/app/test_app.py::test_App::test_Worker`
- `t/unit/app/test_app.py::test_App::test_acquire_connection_raises_on_pool_exhaustion`
- `t/unit/app/test_app.py::test_App::test_acquire_connection_success_with_pool`
- `t/unit/app/test_app.py::test_App::test_acquire_connection_without_pool`
- `t/unit/app/test_app.py::test_App::test_acquire_producer_raises_on_pool_exhaustion`
- `t/unit/app/test_app.py::test_App::test_acquire_producer_success`
- `t/unit/app/test_app.py::test_App::test_add_defaults`
- `t/unit/app/test_app.py::test_App::test_add_periodic_task`
- `t/unit/app/test_app.py::test_App::test_add_periodic_task_expected_override`
- `t/unit/app/test_app.py::test_App::test_add_periodic_task_unexpected_override`
- `t/unit/app/test_app.py::test_App::test_after_fork`
- `t/unit/app/test_app.py::test_App::test_after_fork_cleanup_app__raises`
- `t/unit/app/test_app.py::test_App::test_amqp_failover_strategy_selection`
- `t/unit/app/test_app.py::test_App::test_amqp_get_broker_info[pyamqp://-expected_fields0]`
- `t/unit/app/test_app.py::test_App::test_amqp_get_broker_info[pyamqp:////value-expected_fields2]`
- `t/unit/app/test_app.py::test_App::test_amqp_get_broker_info[pyamqp://:1978/foo-expected_fields1]`
- `t/unit/app/test_app.py::test_App::test_annotate_decorator`
- `t/unit/app/test_app.py::test_App::test_app_pickler_accepts_legacy_arg_count`
- `t/unit/app/test_app.py::test_App::test_apply_async_adds_children`
- `t/unit/app/test_app.py::test_App::test_autodiscover_tasks__no_packages`
- `t/unit/app/test_app.py::test_App::test_autodiscover_tasks_force`
- `t/unit/app/test_app.py::test_App::test_autodiscover_tasks_force_fixup_fallback`
- `t/unit/app/test_app.py::test_App::test_autodiscover_tasks_lazy`
- `t/unit/app/test_app.py::test_App::test_backend`
- `t/unit/app/test_app.py::test_App::test_broker_pool_acquire_timeout_default`
- `t/unit/app/test_app.py::test_App::test_bugreport`
- `t/unit/app/test_app.py::test_App::test_can_get_type_hints_for_tasks`
- `t/unit/app/test_app.py::test_App::test_canvas`
- `t/unit/app/test_app.py::test_App::test_compat_on_configure`
- `t/unit/app/test_app.py::test_App::test_config_form_object__module_attr_does_not_exist`
- `t/unit/app/test_app.py::test_App::test_config_from_cmdline`
- `t/unit/app/test_app.py::test_App::test_config_from_envvar`
- `t/unit/app/test_app.py::test_App::test_config_from_envvar_more`
- `t/unit/app/test_app.py::test_App::test_config_from_object__can_add_defaults_after_silent_reload_failure`
- `t/unit/app/test_app.py::test_App::test_config_from_object__compat`
- `t/unit/app/test_app.py::test_App::test_config_from_object__force`
