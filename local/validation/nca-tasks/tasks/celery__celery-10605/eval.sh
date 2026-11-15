#!/bin/bash
set -uxo pipefail
cd /testbed
git config --global --add safe.directory /testbed
git status
git -c core.fileMode=false diff 05e0ea4233c89d26465c1330c285f93859ff1b7e
git checkout 05e0ea4233c89d26465c1330c285f93859ff1b7e -- t/unit/backends/test_database.py
git apply -v - <<'EOF_NCA_TEST_PATCH_7f3a'
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
EOF_NCA_TEST_PATCH_7f3a
: '>>>>> Start Test Output'
pytest -rA --color=no -p no:cacheprovider --continue-on-collection-errors t/unit/backends/test_database.py
: '>>>>> End Test Output'
git checkout 05e0ea4233c89d26465c1330c285f93859ff1b7e -- t/unit/backends/test_database.py
