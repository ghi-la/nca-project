#!/bin/bash
set -uxo pipefail
cd /testbed
git config --global --add safe.directory /testbed
git status
git -c core.fileMode=false diff 1a3ea2eb8b4e83085754ac4b0de397ef4cbfa31b
git checkout 1a3ea2eb8b4e83085754ac4b0de397ef4cbfa31b -- t/unit/backends/test_database.py
git apply -v - <<'EOF_NCA_TEST_PATCH_7f3a'
diff --git a/t/unit/backends/test_database.py b/t/unit/backends/test_database.py
index 7bf1b3f89f6..3c45aa3cd83 100644
--- a/t/unit/backends/test_database.py
+++ b/t/unit/backends/test_database.py
@@ -9,6 +9,7 @@
 from celery import states, uuid
 from celery.app.task import Context
 from celery.exceptions import ImproperlyConfigured
+from celery.result import result_from_tuple
 
 pytest.importorskip('sqlalchemy')
 
@@ -593,6 +594,165 @@ def test_result_decode_does_not_unpickle_non_pickle_garbage(self):
         with pytest.raises(Exception):
             tb.get_task_meta(tid)
 
+    @pytest.mark.parametrize(
+        'result_serializer',
+        ['pickle', 'json'],
+        ids=['using pickle', 'using json']
+    )
+    def test_store_result_with_children(self, result_serializer):
+        self.app.conf.result_serializer = result_serializer
+        tb = DatabaseBackend(self.uri, app=self.app)
+        tid = uuid()
+        child1 = self.app.AsyncResult(uuid())
+        child2 = self.app.AsyncResult(uuid())
+
+        request = Context()
+        request.children.extend([child1, child2])
+        tb.store_result(tid, 42, states.SUCCESS, request=request)
+        meta = tb.get_task_meta(tid)
+
+        assert meta['result'] == 42
+        assert len(meta['children']) == 2
+        deserialized = [result_from_tuple(c, self.app) for c in meta['children']]
+        assert [c.id for c in deserialized] == [child1.id, child2.id]
+
+    def test_async_result_children(self):
+        tb = DatabaseBackend(self.uri, app=self.app)
+        tid = uuid()
+        child_id = uuid()
+        child = self.app.AsyncResult(child_id)
+
+        request = Context()
+        request.children.append(child)
+        tb.store_result(tid, 42, states.SUCCESS, request=request)
+
+        result = self.app.AsyncResult(tid, backend=tb)
+        children = result.children
+        assert children is not None
+        assert len(children) == 1
+        assert children[0].id == child_id
+
+    def test_store_result_no_children(self):
+        tb = DatabaseBackend(self.uri, app=self.app)
+        tid = uuid()
+        tb.store_result(tid, 42, states.SUCCESS)
+        meta = tb.get_task_meta(tid)
+        assert meta['children'] is None
+        result = self.app.AsyncResult(tid)
+        assert result.children is None
+
+    def test_migrate_missing_columns(self):
+        import sqlalchemy as sa
+        engine = sa.create_engine('sqlite:///:memory:')
+        metadata = sa.MetaData()
+        sa.Table(
+            'celery_taskmeta', metadata,
+            sa.Column('id', sa.Integer, primary_key=True),
+            sa.Column('task_id', sa.String(155), unique=True),
+            sa.Column('status', sa.String(50)),
+            sa.Column('result', sa.LargeBinary, nullable=True),
+            sa.Column('date_done', sa.DateTime, nullable=True),
+            sa.Column('traceback', sa.Text, nullable=True),
+        )
+        metadata.create_all(engine)
+
+        session_mgr = SessionManager()
+        session_mgr.prepare_models(engine)
+
+        from sqlalchemy import inspect
+        inspector = inspect(engine)
+        cols = {c['name'] for c in inspector.get_columns('celery_taskmeta')}
+        assert 'children' in cols
+
+    def test_store_result_task_without_children_attribute(self):
+        tb = DatabaseBackend(self.uri, app=self.app)
+
+        class TaskWithoutChildren:
+            pass
+
+        dummy = TaskWithoutChildren()
+        tb._update_result(dummy, 42, states.SUCCESS)
+        assert not hasattr(dummy, 'children')
+
+    def test_migrate_missing_columns_failure_logs_warning_and_degrades_gracefully(self):
+        import sqlalchemy as sa
+        engine = sa.create_engine('sqlite:///:memory:')
+        metadata = sa.MetaData()
+        sa.Table(
+            'celery_taskmeta', metadata,
+            sa.Column('id', sa.Integer, primary_key=True),
+            sa.Column('task_id', sa.String(155), unique=True),
+            sa.Column('status', sa.String(50)),
+            sa.Column('result', sa.LargeBinary, nullable=True),
+            sa.Column('date_done', sa.DateTime, nullable=True),
+            sa.Column('traceback', sa.Text, nullable=True),
+        ).create(engine)
+
+        session_mgr = SessionManager()
+        failing_conn = Mock()
+        failing_conn.execute.side_effect = Exception("permission denied: ALTER TABLE")
+
+        class FailingBegin:
+            def __enter__(self):
+                return failing_conn
+
+            def __exit__(self, *args):
+                pass
+
+        with patch.object(engine, 'begin', return_value=FailingBegin()):
+            with patch('celery.backends.database.session.logger.warning') as mock_warn:
+                session_mgr.prepare_models(engine)
+                assert mock_warn.called
+                logged_msg = mock_warn.call_args[0][0]
+                assert "Failed to add missing column" in logged_msg
+
+        # Test backend tolerant read path on this database:
+        tb = DatabaseBackend('sqlite:///:memory:', app=self.app)
+        with engine.begin() as conn:
+            conn.execute(sa.text(
+                "INSERT INTO celery_taskmeta (task_id, status, result) VALUES ('test-tid', 'SUCCESS', :res)"
+            ), {'res': tb.encode(42)})
+
+        tb.session_manager.session_factory = lambda *a, **kw: sa.orm.sessionmaker(bind=engine)()
+        meta = tb.get_task_meta('test-tid')
+        assert meta['result'] == 42
+        assert meta['children'] is None
+
+    def test_query_task_fallback_on_operational_error(self):
+        tb = DatabaseBackend(self.uri, app=self.app)
+        tid = uuid()
+        session = Mock()
+
+        # Simulate first query failing with 'no such column: celery_taskmeta.children'
+        from sqlalchemy.exc import DatabaseError
+        err = DatabaseError("SELECT", {}, Exception("no such column: celery_taskmeta.children"))
+        query_mock = Mock()
+        query_mock.filter.side_effect = [err, [Mock(task_id=tid, to_dict=lambda: {'task_id': tid})]]
+        query_mock.options.return_value = query_mock
+        session.query.return_value = query_mock
+
+        res = tb._query_task(session, tid)
+        assert res.task_id == tid
+        assert query_mock.options.called
+
+    def test_migrate_missing_columns_ignores_exceptions(self):
+        session_mgr = SessionManager()
+        mock_engine = Mock()
+        with patch('celery.backends.database.session.inspect', side_effect=Exception("inspect error")):
+            with patch('celery.backends.database.session.logger.warning') as mock_warn:
+                # Must not raise and must log warning
+                session_mgr._migrate_missing_columns(mock_engine)
+                assert mock_warn.called
+
+    def test_migrate_missing_columns_when_table_not_exists(self):
+        session_mgr = SessionManager()
+        mock_engine = Mock()
+        mock_inspector = Mock()
+        mock_inspector.has_table.return_value = False
+        with patch('celery.backends.database.session.inspect', return_value=mock_inspector):
+            session_mgr._migrate_missing_columns(mock_engine)
+        mock_inspector.get_columns.assert_not_called()
+
     def test_mark_as_started(self):
         tb = DatabaseBackend(self.uri, app=self.app)
         tid = uuid()
EOF_NCA_TEST_PATCH_7f3a
: '>>>>> Start Test Output'
pytest -rA --color=no -p no:cacheprovider --continue-on-collection-errors t/unit/backends/test_database.py
: '>>>>> End Test Output'
git checkout 1a3ea2eb8b4e83085754ac4b0de397ef4cbfa31b -- t/unit/backends/test_database.py
