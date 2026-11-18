# celery__celery-10605

- repo: `celery/celery`, created: 2026-09-12, base_commit: `05e0ea4233c8`
- PR: https://github.com/celery/celery/pull/10605
- issue: https://github.com/celery/celery/issues/8887
- FAIL_TO_PASS: 7 tests, PASS_TO_PASS: 91 tests, collection_error: **no**

## 1. Issue (what the agent sees)

Stamping doesn't work with database result backend
<!--
Please fill this template entirely and do not erase parts of it.
We reserve the right to close without a response
bug reports which are incomplete.
-->
# Checklist
<!--
To check an item on the list replace [ ] with [x].
-->
- [x] I have verified that the issue exists against the `main` branch of Celery.
- [ ] This has already been asked to the [discussions forum](https://github.com/celery/celery/discussions) first.
- [x] I have read the relevant section in the
  [contribution guide](https://docs.celeryq.dev/en/main/contributing.html#other-bugs)
  on reporting bugs.
- [x] I have checked the [issues list](https://github.com/celery/celery/issues?q=is%3Aissue+label%3A%22Issue+Type%3A+Bug+Report%22+-label%3A%22Category%3A+Documentation%22)
  for similar or identical bug reports.
- [x] I have checked the [pull requests list](https://github.com/celery/celery/pulls?q=is%3Apr+label%3A%22PR+Type%3A+Bugfix%22+-label%3A%22Category%3A+Documentation%22)
  for existing proposed fixes.
- [ ] I have checked the [commit log](https://github.com/celery/celery/commits/main)
  to find out if the bug was already fixed in the main branch.
- [x] I have included all related issues and possible duplicate issues
  in this issue (If there are none, check this box anyway).

## Mandatory Debugging Information

- [x] I have included the output of ``celery -A proj report`` in the issue.
    (if you are not able to do this, then at least specify the Celery
     version affected).
- [x] I have verified that the issue exists against the `main` branch of Celery.
- [x] I have included the contents of ``pip freeze`` in the issue.
- [x] I have included all the versions of all the external dependencies required
  to reproduce this bug.

## Optional Debugging Information
<!--
Try some of the below if you think they are relevant.
It will help us figure out the scope of the bug and how many users it affects.
-->
- [ ] I have tried reproducing the issue on more than one Python version
  and/or implementation.
- [x] I have tried reproducing the issue on more than one message broker and/or
  result backend.
- [ ] I have tried reproducing the issue on more than one version of the message
  broker and/or result backend.
- [ ] I have tried reproducing the issue on more than one operating system.
- [ ] I have tried reproducing the issue on more than one workers pool.
- [ ] I have tried reproducing the issue with autoscaling, retries,
  ETA/Countdown & rate limits disabled.
- [ ] I have tried reproducing the issue after downgrading
  and/or upgrading Celery and its dependencies.

## Related Issues and Possible Duplicates
<!--
Please make sure to search and mention any related issues
or possible duplicates to this issue as requested by the checklist above.

This may or may not include issues in other repositories that the Celery project
maintains or other repositories that are dependencies of Celery.

If you don't know how to mention issues, please refer to Github's documentation
on the subject: https://help.github.com/en/articles/autolinked-references-and-urls#issues-and-pull-requests
-->

#### Related Issues

- None

#### Possible Duplicates

- None

## Environment & Settings
<!-- Include the contents of celery --version below -->
**Celery version**: 5.3.6, 5.4.0rc1 (opalescent)
<!-- Include the output of celery -A proj report below -->
<details>
<summary><b><code>celery report</code> Output:</b></summary>
<p>

```
software -> celery:5.4.0rc1 (opalescent) kombu:5.3.5 py:3.11.4
            billiard:4.2.0 py-amqp:5.2.0
platform -> system:Darwin arch:64bit
            kernel version:23.1.0 imp:CPython
loader   -> celery.loaders.app.AppLoader
settings -> transport:amqp results:db+postgresql:///stamp_issue

broker_url: 'amqp://guest:********@localhost:5672//'
deprecated_settings: None
task_default_queue: 'stamp_issue_queue'
result_extended: True
result_backend: 'db+postgresql:///stamp_issue'
```

</p>
</details>

# Steps to Reproduce

## Required Dependencies
<!-- Please fill the required dependencies to reproduce this issue -->
- **Minimal Python Version**: N/A or Unknown
- **Minimal Celery Version**: N/A or Unknown
- **Minimal Kombu Version**: N/A or Unknown
- **Minimal Broker Version**: N/A or Unknown
- **Minimal Result Backend Version**: N/A or Unknown
- **Minimal OS and/or Kernel Version**: N/A or Unknown
- **Minimal Broker Client Version**: N/A or Unknown
- **Minimal Result Backend Client Version**: N/A or Unknown

### Python Packages
<!-- Please fill the contents of pip freeze below -->
<details>
<summary><b><code>pip freeze</code> Output:</b></summary>
<p>

```
amqp==5.2.0
async-timeout==4.0.3
billiard==4.2.0
celery @ git+https://github.com/celery/celery.git@9edeab6b4526a59bf699df10f1b48ac65809eaea
click==8.1.7
click-didyoumean==0.3.0
click-plugins==1.1.1
click-repl==0.3.0
greenlet==3.0.3
kombu==5.3.5
prompt-toolkit==3.0.43
psycopg2==2.9.9
python-dateutil==2.9.0.post0
redis==5.0.2
six==1.16.0
SQLAlchemy==2.0.27
typing_extensions==4.10.0
tzdata==2024.1
vine==5.1.0
wcwidth==0.2.13
```

</p>
</details>

### Other Dependencies
<!--
Please provide system dependencies, configuration files
and other dependency information if applicable
-->
<details>
<p>
PostgreSQL database:

```
createdb stamp_issue
```

</p>
</details>

## Minimally Reproducible Test Case
<!--
Please provide a reproducible test case.
Refer to the Reporting Bugs section in our contribution guide.

We prefer submitting test cases in the form of a PR to our integration test suite.
If you can provide one, please mention the PR number below.
If not, please attach the most minimal code example required to reproduce the issue below.
If the test case is too large, please include a link to a gist or a repository below.
-->

<details>
<p>

Stamping works with the redis result backend, but not with the database backend or the rpc backend. (The rpc backend is not suitable for me, but I tested it for completeness).

`stamp_issue.py`:
```python
from celery import Celery
from celery.canvas import group

app = Celery("stamp_issue", broker="amqp://guest@localhost:5672/")
app.conf.task_default_queue = "stamp_issue_queue"
app.conf.result_extended = True
# app.conf.result_backend = "rpc://"                       # doesn't work
# app.conf.result_backend = "redis://localhost/0"          # works
app.conf.result_backend = "db+postgresql:///stamp_issue"   # doesn't work


@app.task
def add(x, y):
    return x + y


if __name__ == "__main__":
    sig1 = add.si(2, 2)
    sig1_res = sig1.freeze()
    g = group(sig1, add.si(3, 3))
    g.stamp(stamp="your_custom_stamp")
    res = g.apply_async()
    print(res.get())
    print(sig1_res._get_task_meta()["stamp"])
```

1. Start worker: `celery -A stamp_issue worker --loglevel=INFO --hostname stamp_issue`
2. Run example: `python stamp_issue.py`

</p>
</details>

# Expected Behavior
The output

```
[4, 6]
your_custom_stamp
```

# Actual Behavior
<!--
Describe in detail what actually happened.
Please include a backtrace and surround it with triple backticks (```).
In addition, include the Celery daemon logs, the broker logs,
the result backend logs and system logs below if they will help us debug
the issue.
-->
```
[4, 6]
Traceback (most recent call last):
  File "/Users/.../stamp_issue.py", line 24, in <module>
    print(sig1_res._get_task_meta()["stamp"])
          ~~~~~~~~~~~~~~~~~~~~~~~~~^^^^^^^^^
KeyError: 'stamp'
```

## 2. Gold patch

```diff
diff --git a/celery/backends/database/__init__.py b/celery/backends/database/__init__.py
index d2a50fe2a09..81a41f4efbc 100644
--- a/celery/backends/database/__init__.py
+++ b/celery/backends/database/__init__.py
@@ -17,6 +17,7 @@
 
 try:
     from sqlalchemy.exc import DatabaseError, InterfaceError, InvalidRequestError
+    from sqlalchemy.orm import defer
     from sqlalchemy.orm.exc import StaleDataError
 except ImportError:
     raise ImproperlyConfigured(
@@ -137,21 +138,26 @@ def ResultSession(self, session_manager=None):
             **self.engine_options)
 
     def _query_task(self, session, task_id):
-        """Query task by id, falling back to deferring children if missing from database."""
+        """Query task by id, falling back to deferring missing columns from database."""
         try:
             tasks = list(session.query(self.task_cls).filter(self.task_cls.task_id == task_id))
             return tasks and tasks[0]
         except DatabaseError as exc:
-            if 'children' in str(exc).lower():
-                from sqlalchemy.orm import defer
-                tasks = list(session.query(self.task_cls).options(
-                    defer(self.task_cls.children)
-                ).filter(self.task_cls.task_id == task_id))
+            exc_str = str(exc).lower()
+            defers = []
+            if 'children' in exc_str and hasattr(self.task_cls, 'children'):
+                defers.append(defer(self.task_cls.children))
+            if 'stamps' in exc_str and hasattr(self.task_cls, 'stamps'):
+                defers.append(defer(self.task_cls.stamps))
+            if defers:
+                tasks = list(session.query(self.task_cls).options(*defers).filter(
+                    self.task_cls.task_id == task_id
+                ))
                 return tasks and tasks[0]
             raise
 
-    def _store_result(self, task_id, result, state,
-                      traceback=None, request=None, **kwargs):
+    def _store_result(self, task_id, result, state, traceback=None,
+                      request=None, **kwargs):
         """Store return value and state of an executed task."""
         session = self.ResultSession()
         with session_cleanup(session):
@@ -172,10 +178,10 @@ def _update_result(self, task, result, state, traceback=None,
                                      traceback=traceback, request=request,
                                      format_date=False, encode=True)
 
-        # Exclude the primary key id, task_id, and children columns
-        # as we should not set it None or handle children separately
+        # Exclude the primary key id, task_id, children, and stamps columns
+        # as we should not set it None or handle them separately
         columns = [column.name for column in self.task_cls.__table__.columns
-                   if column.name not in {'id', 'task_id', 'children'}]
+                   if column.name not in {'id', 'task_id', 'children', 'stamps'}]
 
         # Iterate through the columns name of the table
         # to set the value from meta.
@@ -191,6 +197,20 @@ def _update_result(self, task, result, state, traceback=None,
             else:
                 setattr(task, 'children', None)
 
+        if hasattr(task, 'stamps') and 'stamps' in self.task_cls.__table__.columns:
+            stamped_headers = meta.get('stamped_headers')
+            if stamped_headers:
+                stamps_data = {
+                    h: meta.get(h) for h in stamped_headers if h in meta
+                }
+                stamps_info = {
+                    'stamped_headers': stamped_headers,
+                    'stamps': stamps_data,
+                }
+                setattr(task, 'stamps', ensure_bytes(self.encode(stamps_info)))
+            elif getattr(task, 'stamps', None) is None:
+                setattr(task, 'stamps', None)
+
     def _get_task_meta_for(self, task_id):
         """Get task meta-data for a task by id."""
         session = self.ResultSession()
@@ -208,6 +228,17 @@ def _get_task_meta_for(self, task_id):
                 data['kwargs'] = self.decode(data['kwargs'])
             if data.get('children', None) is not None:
                 data['children'] = self.decode(data['children'])
+            raw_stamps = data.pop('stamps', None)
+            if raw_stamps is not None:
+                try:
+                    stamps_info = self.decode(raw_stamps)
+                    if isinstance(stamps_info, dict):
+                        if 'stamped_headers' in stamps_info:
+                            data['stamped_headers'] = stamps_info['stamped_headers']
+                        if 'stamps' in stamps_info and isinstance(stamps_info['stamps'], dict):
+                            data.update(stamps_info['stamps'])
+                except Exception:
+                    pass
             return self.meta_from_decoded(data)
 
     def _decode_stored_result(self, payload):
diff --git a/celery/backends/database/models.py b/celery/backends/database/models.py
index 4bcf90ef8dd..3c6e0fc9969 100644
--- a/celery/backends/database/models.py
+++ b/celery/backends/database/models.py
@@ -78,9 +78,14 @@ class TaskExtended(Task):
     worker = sa.Column(sa.String(155), nullable=True)
     retries = sa.Column(sa.Integer, nullable=True)
     queue = sa.Column(sa.String(155), nullable=True)
+    stamps = sa.Column(sa.LargeBinary, nullable=True)
 
     def to_dict(self):
         task_dict = super().to_dict()
+        try:
+            stamps = self.stamps
+        except Exception:
+            stamps = None
         task_dict.update({
             'name': self.name,
             'args': self.args,
@@ -88,6 +93,7 @@ def to_dict(self):
             'worker': self.worker,
             'retries': self.retries,
             'queue': self.queue,
+            'stamps': stamps,
         })
         return task_dict
 
diff --git a/docs/userguide/configuration.rst b/docs/userguide/configuration.rst
index 5c18241ae71..e4d4cbb548d 100644
--- a/docs/userguide/configuration.rst
+++ b/docs/userguide/configuration.rst
@@ -1003,7 +1003,18 @@ and client first and turn the setting on afterwards.
 Default: ``False``
 
 Enables extended task result attributes (name, args, kwargs, worker,
-retries, queue) to be written to backend.
+retries, queue, stamps) to be written to backend.
+
+.. versionadded:: 5.7
+    Added storing task stamping metadata (``stamps``) in the database backend.
+
+.. note::
+
+    When using the database backend with :setting:`result_extended` set to ``True``,
+    task stamping metadata is stored in a ``stamps`` column. For existing database deployments
+    upgrading with an already-created ``celery_taskmeta`` table, operators must execute the
+    appropriate DDL migration to add the column before upgrading (e.g., ``ALTER TABLE celery_taskmeta ADD COLUMN stamps BLOB;``
+    or ``BYTEA`` on PostgreSQL); this migration is required as result writes will otherwise fail.
 
 .. setting:: result_expires
```

## 3. Test patch

```diff
diff --git a/t/unit/backends/test_database.py b/t/unit/backends/test_database.py
index 3c45aa3cd83..e404d01c3fc 100644
--- a/t/unit/backends/test_database.py
+++ b/t/unit/backends/test_database.py
@@ -5,6 +5,7 @@
 from unittest.mock import Mock, patch
 
 import pytest
+from kombu.utils.encoding import ensure_bytes
 
 from celery import states, uuid
 from celery.app.task import Context
@@ -937,6 +938,207 @@ def test_store_none_result(self, result_serializer, args, kwargs):
         assert meta['retries'] == 2
         assert meta['worker'] == "celery@worker_1"
 
+    @pytest.mark.parametrize(
+        'result_serializer',
+        ['pickle', 'json'],
+        ids=['using pickle', 'using json']
+    )
+    def test_store_result_with_stamps(self, result_serializer):
+        self.app.conf.result_serializer = result_serializer
+        tb = DatabaseBackend(self.uri, app=self.app)
+        tid = uuid()
+
+        request = Context(args=(1, 2), kwargs={'foo': 'bar'},
+                          task='mytask', retries=2,
+                          hostname='celery@worker_1',
+                          delivery_info={'routing_key': 'celery'},
+                          stamped_headers=['stamp1', 'stamp2'],
+                          stamps={'stamp1': ['val1'], 'stamp2': 'val2'})
+
+        tb.store_result(tid, {'fizz': 'buzz'}, states.SUCCESS, request=request)
+        meta = tb.get_task_meta(tid)
+
+        assert meta['result'] == {'fizz': 'buzz'}
+        assert meta['stamped_headers'] == ['stamp1', 'stamp2']
+        assert meta['stamp1'] == ['val1']
+        assert meta['stamp2'] == 'val2'
+        # Matches BaseBackend: stamps are flattened, and 'stamps' key is never leaked
+        assert 'stamps' not in meta
+
+    def test_store_result_without_stamps(self):
+        tb = DatabaseBackend(self.uri, app=self.app)
+        tid = uuid()
+
+        request = Context(args=(1, 2), kwargs={'foo': 'bar'},
+                          task='mytask', retries=2,
+                          hostname='celery@worker_1',
+                          delivery_info={'routing_key': 'celery'})
+
+        tb.store_result(tid, {'fizz': 'buzz'}, states.SUCCESS, request=request)
+        meta = tb.get_task_meta(tid)
+
+        assert meta['result'] == {'fizz': 'buzz'}
+        assert 'stamps' not in meta
+        assert 'stamped_headers' not in meta
+
+    def test_store_result_stamps_header_missing_from_meta(self):
+        tb = DatabaseBackend(self.uri, app=self.app)
+        tid = uuid()
+        request = Context(args=(), kwargs={}, task='mytask',
+                          stamped_headers=['stamp1', 'stamp_missing'],
+                          stamps={'stamp1': 'val1'})
+        tb.store_result(tid, 'res', states.SUCCESS, request=request)
+        meta = tb.get_task_meta(tid)
+        assert meta['stamp1'] == 'val1'
+        assert 'stamp_missing' not in meta
+        assert meta['stamped_headers'] == ['stamp1', 'stamp_missing']
+        assert 'stamps' not in meta
+
+    def test_store_result_stamps_corrupt_non_dict_payload(self):
+        tb = DatabaseBackend(self.uri, app=self.app)
+        tid = uuid()
+        request = Context(args=(), kwargs={}, task='mytask',
+                          stamped_headers=['stamp1'],
+                          stamps={'stamp1': 'val1'})
+        tb.store_result(tid, 'res', states.SUCCESS, request=request)
+        session = tb.ResultSession()
+        task = session.query(tb.task_cls).filter(tb.task_cls.task_id == tid).first()
+        task.stamps = ensure_bytes(tb.encode("not-a-dict"))
+        session.commit()
+        session.close()
+        tb._cache.clear()
+        meta = tb.get_task_meta(tid)
+        assert meta['result'] == 'res'
+        # Corrupt / non-dict payload fails closed and never leaks raw bytes into meta
+        assert 'stamps' not in meta
+
+    def test_store_result_stamps_only_stamps_without_headers(self):
+        tb = DatabaseBackend(self.uri, app=self.app)
+        tid = uuid()
+        request = Context(args=(), kwargs={}, task='mytask')
+        tb.store_result(tid, 'res', states.SUCCESS, request=request)
+        session = tb.ResultSession()
+        task = session.query(tb.task_cls).filter(tb.task_cls.task_id == tid).first()
+        task.stamps = ensure_bytes(tb.encode({'stamps': {'only_stamps': 'value'}}))
+        session.commit()
+        session.close()
+        tb._cache.clear()
+        meta = tb.get_task_meta(tid)
+        assert meta['only_stamps'] == 'value'
+        assert 'stamped_headers' not in meta
+        assert 'stamps' not in meta
+
+    def test_store_result_stamps_only_headers_without_stamps(self):
+        tb = DatabaseBackend(self.uri, app=self.app)
+        tid = uuid()
+        request = Context(args=(), kwargs={}, task='mytask')
+        tb.store_result(tid, 'res', states.SUCCESS, request=request)
+        session = tb.ResultSession()
+        task = session.query(tb.task_cls).filter(tb.task_cls.task_id == tid).first()
+        task.stamps = ensure_bytes(tb.encode({'stamped_headers': ['only_header']}))
+        session.commit()
+        session.close()
+        tb._cache.clear()
+        meta = tb.get_task_meta(tid)
+        assert meta['stamped_headers'] == ['only_header']
+        assert 'stamps' not in meta
+
+    def test_store_result_stamps_disabled_when_result_extended_false(self):
+        self.app.conf.result_extended = False
+        tb = DatabaseBackend(self.uri, app=self.app)
+        assert tb.task_cls is Task
+        assert not hasattr(Task, 'stamps')
+        tid = uuid()
+        request = Context(stamped_headers=['stamp1'], stamps={'stamp1': 'val1'})
+        tb.store_result(tid, 'res', states.SUCCESS, request=request)
+        meta = tb.get_task_meta(tid)
+        assert 'stamp1' not in meta
+        assert 'stamped_headers' not in meta
+        assert 'stamps' not in meta
+
+    def test_store_result_stamps_missing_column_graceful_fallback(self):
+        from sqlalchemy.exc import DatabaseError
+        tb = DatabaseBackend(self.uri, app=self.app)
+        tid = uuid()
+        tb.store_result(tid, 'res', states.SUCCESS)
+
+        session = tb.ResultSession()
+
+        # When DatabaseError occurs with 'stamps', _query_task defers the column
+        with patch.object(session, 'query') as mock_query:
+            first_mock = Mock()
+            first_mock.filter.side_effect = DatabaseError(
+                "SELECT celery_taskmeta.stamps", None, Exception("no such column: celery_taskmeta.stamps")
+            )
+            second_mock = Mock()
+            second_filter = Mock()
+            second_filter.return_value = [tb.task_cls(tid)]
+            second_mock.filter = second_filter
+            first_mock.options.side_effect = lambda opt: second_mock
+
+            mock_query.return_value = first_mock
+            task = tb._query_task(session, tid)
+            assert task is not None
+            assert task.task_id == tid
+
+    def test_stamped_signature_roundtrip_with_async_result(self):
+        from celery.canvas import signature
+        from celery.result import AsyncResult
+
+        tb = DatabaseBackend(self.uri, app=self.app)
+        sig = signature('mytask')
+        sig.stamp(stamp_key='stamp_value', custom_run_id=123)
+
+        tid = uuid()
+        request = Context(
+            task='mytask',
+            stamped_headers=sig.options['stamped_headers'],
+            stamps={h: sig.options[h] for h in sig.options['stamped_headers'] if h in sig.options}
+        )
+
+        tb.store_result(tid, {'status': 'completed'}, states.SUCCESS, request=request)
+        async_res = AsyncResult(tid, backend=tb)
+        assert async_res.result == {'status': 'completed'}
+        assert async_res.state == states.SUCCESS
+
+        meta = tb.get_task_meta(tid)
+        assert meta['stamp_key'] == 'stamp_value'
+        assert meta['custom_run_id'] == 123
+        assert set(meta['stamped_headers']) == {'stamp_key', 'custom_run_id'}
+        assert 'stamps' not in meta
+
+    def test_store_result_stamps_corrupt_unpicklable_decode_error(self):
+        tb = DatabaseBackend(self.uri, app=self.app)
+        tid = uuid()
+        request = Context(args=(), kwargs={}, task='mytask')
+        tb.store_result(tid, 'res', states.SUCCESS, request=request)
+        session = tb.ResultSession()
+        task = session.query(tb.task_cls).filter(tb.task_cls.task_id == tid).first()
+        task.stamps = b'corrupt-unpicklable-blob'
+        session.commit()
+        session.close()
+        tb._cache.clear()
+        meta = tb.get_task_meta(tid)
+        assert meta['result'] == 'res'
+        assert 'stamps' not in meta
+
+    def test_task_extended_to_dict_tolerant_of_stamps_error(self):
+        from unittest.mock import PropertyMock
+
+        from celery.backends.database.models import TaskExtended
+        task = TaskExtended('test-task')
+        with patch.object(TaskExtended, 'stamps', new_callable=PropertyMock, side_effect=Exception("error")):
+            d = task.to_dict()
+            assert d['stamps'] is None
+
+    def test_query_task_unrelated_database_error_raises(self):
+        from sqlalchemy.exc import DatabaseError
+        tb = DatabaseBackend(self.uri, app=self.app)
+        session = Mock()
+        session.query.side_effect = DatabaseError("SELECT", {}, Exception("unrelated connection lost"))
+        with pytest.raises(DatabaseError):
+            tb._query_task(session, 'some-id')
+
     @pytest.mark.parametrize(
         'result_serializer, args, kwargs',
         [
```

## 4. FAIL_TO_PASS tests

- `t/unit/backends/test_database.py::test_DatabaseBackend_result_extended::test_stamped_signature_roundtrip_with_async_result`
- `t/unit/backends/test_database.py::test_DatabaseBackend_result_extended::test_store_result_stamps_header_missing_from_meta`
- `t/unit/backends/test_database.py::test_DatabaseBackend_result_extended::test_store_result_stamps_missing_column_graceful_fallback`
- `t/unit/backends/test_database.py::test_DatabaseBackend_result_extended::test_store_result_stamps_only_headers_without_stamps`
- `t/unit/backends/test_database.py::test_DatabaseBackend_result_extended::test_store_result_stamps_only_stamps_without_headers`
- `t/unit/backends/test_database.py::test_DatabaseBackend_result_extended::test_store_result_with_stamps[using`
- `t/unit/backends/test_database.py::test_DatabaseBackend_result_extended::test_task_extended_to_dict_tolerant_of_stamps_error`
