#!/bin/bash
set -uxo pipefail
cd /testbed
git config --global --add safe.directory /testbed
git status
git -c core.fileMode=false diff beef13ac9996b49ecc4aa9c7363cc0dd20db3da3
git checkout beef13ac9996b49ecc4aa9c7363cc0dd20db3da3 -- t/integration/test_inspect.py t/unit/utils/test_collections.py t/unit/worker/test_consumer.py t/unit/worker/test_control.py t/unit/worker/test_state.py
git apply -v - <<'EOF_NCA_TEST_PATCH_7f3a'
diff --git a/t/integration/test_inspect.py b/t/integration/test_inspect.py
index 8bd7012cc43..7993be27224 100644
--- a/t/integration/test_inspect.py
+++ b/t/integration/test_inspect.py
@@ -1,12 +1,14 @@
 import os
 import re
 from datetime import datetime, timedelta, timezone
-from time import sleep
+from time import monotonic, sleep
 from unittest.mock import ANY
 
 import pytest
 
+from celery import uuid
 from celery.utils.nodenames import anon_nodename
+from celery.worker import state as worker_state
 
 from .tasks import add, sleeping
 
@@ -253,6 +255,31 @@ def test_revoked(self, inspect):
         assert len(ret) == 1
         assert result.task_id in ret[NODENAME]
 
+    @flaky
+    def test_hello_stamps_received_revoked_ids_locally(self, inspect):
+        """The revoked ids of another worker are taken as ids, stamped here."""
+        # Stamps ahead of the local clock, as from a host with a longer
+        # uptime: taken as they are, they would never expire (#4300).
+        ahead = monotonic() + 10 ** 6
+        received = [uuid() for _ in range(2)]
+        try:
+            ret = inspect.hello(
+                'other@host',
+                revoked={task_id: [ahead, seq, task_id] for seq, task_id in enumerate(received)},
+            )
+            assert len(ret) == 1
+            # The session worker runs in this process: its set is right here.
+            stamps = worker_state.revoked.as_dict()
+            for task_id in received:
+                assert stamps[task_id] <= monotonic()
+            # The reply carries the ids alone.
+            reply = ret[NODENAME]['revoked']
+            assert isinstance(reply, list)
+            assert set(received) <= set(reply)
+        finally:
+            for task_id in received:
+                worker_state.revoked.discard(task_id)
+
     @flaky
     def test_conf(self, inspect):
         """Tests getting configuration"""
diff --git a/t/smoke/tests/test_revoked_sync.py b/t/smoke/tests/test_revoked_sync.py
new file mode 100644
index 00000000000..8e3f6e58563
--- /dev/null
+++ b/t/smoke/tests/test_revoked_sync.py
@@ -0,0 +1,116 @@
+"""Revoked ids received from another worker, on mingle or through ``hello``.
+
+They are stamped with the receiving worker's own clock, whatever stamps
+they come with (#4300): a set filled with stamps ahead of the local clock
+would otherwise purge every id revoked from then on the moment it is
+added, and the task would run.
+"""
+from __future__ import annotations
+
+from time import monotonic
+
+import pytest
+from pytest_celery import (CeleryBrokerCluster, CeleryTestSetup, CeleryTestWorker, CeleryWorkerCluster,
+                           RedisTestBroker)
+from tenacity import retry, stop_after_attempt, wait_fixed
+
+from celery import uuid
+from t.smoke.tasks import noop
+
+REVOKES_MAX = 3
+
+
+def revoked_ids(setup: CeleryTestSetup, worker: CeleryTestWorker) -> list[str]:
+    reply = setup.app.control.inspect(
+        destination=[worker.hostname()], timeout=5,
+    ).revoked() or {}
+    return reply.get(worker.hostname(), [])
+
+
+@retry(stop=stop_after_attempt(60), wait=wait_fixed(1), reraise=True)
+def assert_revoked(setup: CeleryTestSetup, worker: CeleryTestWorker, task_id: str) -> None:
+    assert task_id in revoked_ids(setup, worker), f"{task_id} is not revoked on {worker.hostname()}"
+
+
+class test_hello:
+    @pytest.fixture
+    def default_worker_env(self, default_worker_env: dict) -> dict:
+        # A set this small is full after one hello.
+        default_worker_env.update({"CELERY_WORKER_REVOKES_MAX": str(REVOKES_MAX)})
+        return default_worker_env
+
+    def test_received_ids_are_stamped_locally(self, celery_setup: CeleryTestSetup):
+        app = celery_setup.app
+        worker = celery_setup.worker
+
+        # Play a worker on a host with a longer uptime: its stamps are ahead
+        # of the clock of the worker under test.
+        ahead = monotonic() + 10 ** 6
+        received = [uuid() for _ in range(REVOKES_MAX)]
+        reply = app.control.inspect(
+            destination=[worker.hostname()], timeout=5,
+        ).hello(
+            "neighbour@elsewhere",
+            revoked={task_id: [ahead, seq, task_id] for seq, task_id in enumerate(received)},
+        )
+
+        # The set is full: an id revoked now must stay, the received ids
+        # being the oldest by the local clock -- or the newest, as sent.
+        revoked = uuid()
+        app.control.revoke(revoked, destination=[worker.hostname()])
+        assert_revoked(celery_setup, worker, revoked)
+
+        # And a task with an ETA revoked while the worker holds it is
+        # discarded rather than run.
+        result = noop.s().apply_async(queue=worker.worker_queue, countdown=10)
+        worker.assert_log_exists(f"noop[{result.id}] received")
+        result.revoke()
+        worker.assert_log_exists(f"Discarding revoked task: t.smoke.tasks.noop[{result.id}]")
+        worker.assert_log_does_not_exist(f"noop[{result.id}] succeeded", timeout=5)
+
+        # The reply to the hello carried the ids alone.
+        ours = reply[worker.hostname()]["revoked"]
+        assert isinstance(ours, list)
+        assert set(received) <= set(ours)
+
+
+class test_mingle:
+    @pytest.fixture
+    def celery_broker_cluster(self, celery_redis_broker: RedisTestBroker) -> CeleryBrokerCluster:
+        # The last release cannot mingle on RabbitMQ 4.3, which refuses
+        # its transient non-exclusive pidbox reply queue.
+        cluster = CeleryBrokerCluster(celery_redis_broker)
+        yield cluster
+        cluster.teardown()
+
+    @pytest.fixture
+    def celery_worker_cluster(
+        self,
+        celery_worker: CeleryTestWorker,
+        celery_latest_worker: CeleryTestWorker,
+    ) -> CeleryWorkerCluster:
+        # The last release and the current source in one cluster: each
+        # side receives the other's format on mingle.
+        cluster = CeleryWorkerCluster(celery_worker, celery_latest_worker)
+        yield cluster
+        cluster.teardown()
+
+    def test_sync_with_another_version(self, celery_setup: CeleryTestSetup):
+        app = celery_setup.app
+        dev, latest = celery_setup.worker_cluster
+
+        # A worker restarting takes the revoked ids of its neighbour.
+        revoked_on_dev = uuid()
+        app.control.revoke(revoked_on_dev, destination=[dev.hostname()])
+        assert_revoked(celery_setup, dev, revoked_on_dev)
+        latest.restart()
+        assert_revoked(celery_setup, latest, revoked_on_dev)
+
+        revoked_on_latest = uuid()
+        app.control.revoke(revoked_on_latest, destination=[latest.hostname()])
+        assert_revoked(celery_setup, latest, revoked_on_latest)
+        dev.restart()
+        assert_revoked(celery_setup, dev, revoked_on_latest)
+        # ...and gets back the id it had revoked before its restart, which
+        # the other release took on its own.
+        assert_revoked(celery_setup, dev, revoked_on_dev)
diff --git a/t/unit/utils/test_collections.py b/t/unit/utils/test_collections.py
index b4a9acbe15e..7934a8bc396 100644
--- a/t/unit/utils/test_collections.py
+++ b/t/unit/utils/test_collections.py
@@ -341,6 +341,42 @@ def test_purge(self):
         assert len(s._heap) <= s.maxlen * (
             100. + s.max_heap_percent_overload) / 100
 
+    def test_add_orders_items_within_the_clock_resolution(self):
+        s = LimitedSet(maxlen=10)
+        s.add('b', now=1.0)
+        s.add(1, now=1.0)  # no comparison between the items themselves
+        s.add('a', now=1.0)
+        assert list(s) == ['b', 1, 'a']
+        assert s.pop() == 'b'
+
+    def test_add_at_time_zero(self):
+        s = LimitedSet(maxlen=10, expires=1)
+        s.add('foo', now=0)
+        assert s.as_dict()['foo'] == 0
+        assert pickle.loads(pickle.dumps(s)) == s
+        s.purge(now=2)
+        assert 'foo' not in s
+
+    def test_update_from_another_clock(self):
+        # The stamps of a set built on another host are not comparable
+        # with ours; merging its items stamps them with the local clock,
+        # merging the set or its dict keeps the stamps.
+        other = LimitedSet(maxlen=10)
+        other.add('foo', now=monotonic() + 10 ** 6)
+        s = LimitedSet(maxlen=10)
+        s.update(list(other))
+        assert s.as_dict()['foo'] <= monotonic()
+        s = LimitedSet(maxlen=10)
+        s.update(other)
+        assert s.as_dict()['foo'] == other.as_dict()['foo']
+
+    def test_eq(self):
+        s = LimitedSet(maxlen=2)
+        s.add('foo')
+        assert s == pickle.loads(pickle.dumps(s))
+        assert s != LimitedSet(maxlen=2)
+        assert s != {'foo'}
+
     def test_pickleable(self):
         s = LimitedSet(maxlen=2)
         s.add('foo')
diff --git a/t/unit/worker/test_consumer.py b/t/unit/worker/test_consumer.py
index d132b0c0271..b9ebfee743b 100644
--- a/t/unit/worker/test_consumer.py
+++ b/t/unit/worker/test_consumer.py
@@ -2,6 +2,7 @@
 import logging
 import socket
 from collections import deque
+from time import monotonic
 from types import SimpleNamespace
 from unittest.mock import MagicMock, Mock, call, patch
 
@@ -17,6 +18,7 @@
 from celery.utils.collections import LimitedSet
 from celery.utils.quorum_queues import detect_quorum_queues
 from celery.utils.time import utcoffset
+from celery.worker import state as worker_state
 from celery.worker.consumer.agent import Agent
 from celery.worker.consumer.consumer import (CANCEL_TASKS_BY_DEFAULT, CLOSE, COLLECT_SOCKET_TIMEOUT, TERMINATE,
                                              Consumer)
@@ -1647,6 +1649,7 @@ def test_start_no_replies(self):
         c = Mock()
         c.app.connection_for_read = _amqp_connection()
         mingle = Mingle(c)
+        c.controller.state.revoked = LimitedSet()
         I = c.app.control.inspect.return_value = Mock()
         I.hello.return_value = {}
         mingle.start(c)
@@ -1678,10 +1681,12 @@ def test_start(self):
             },
         }
 
-        our_revoked = c.controller.state.revoked = LimitedSet()
-
-        mingle.start(c)
-        I.hello.assert_called_with(c.hostname, our_revoked._data)
+        our_revoked = LimitedSet()
+        our_revoked.add('ours')
+        with patch.object(worker_state, 'revoked', our_revoked):
+            c.controller.state = worker_state
+            mingle.start(c)
+        I.hello.assert_called_with(c.hostname, ['ours'])
         c.app.clock.adjust.assert_has_calls([
             call(312), call(29),
         ], any_order=True)
@@ -1689,6 +1694,33 @@ def test_start(self):
         assert 'Aig-2' in our_revoked
         assert 'Big-1' in our_revoked
 
+    def test_start_stamps_received_revoked_items_locally(self):
+        # The stamps of a neighbour count from the boot of its host; taken
+        # as they are, the ones ahead of the local clock never expire and,
+        # once they fill the set, evict every id revoked here as the
+        # oldest one the moment it is added (#4300).
+        c = Mock()
+        c.app.connection_for_read = _amqp_connection()
+        mingle = Mingle(c)
+
+        Aig = LimitedSet()
+        Aig.add('Aig-1', now=monotonic() + 10 ** 6)
+        I = c.app.control.inspect.return_value = Mock()
+        I.hello.return_value = {
+            'A@example.com': {'clock': 312, 'revoked': Aig._data},
+        }
+
+        our_revoked = LimitedSet(maxlen=1, expires=3600)
+        with patch.object(worker_state, 'revoked', our_revoked):
+            c.controller.state = worker_state
+            mingle.start(c)
+        assert 'Aig-1' in our_revoked
+        assert our_revoked.as_dict()['Aig-1'] <= monotonic()
+
+        our_revoked.add('ours')
+        assert 'ours' in our_revoked
+        assert 'Aig-1' not in our_revoked
+
 
 def _amqp_connection():
     connection = ContextMock(name='Connection')
diff --git a/t/unit/worker/test_control.py b/t/unit/worker/test_control.py
index 9a0afd9a3f7..7df2e94db1a 100644
--- a/t/unit/worker/test_control.py
+++ b/t/unit/worker/test_control.py
@@ -283,6 +283,38 @@ def test_hello_does_not_send_expired_revoked_items(self):
         })
         assert 'expired_in_past' not in x['revoked']
 
+    def test_hello_stamps_received_revoked_items_locally(self):
+        # The set of the other worker comes with its own monotonic stamps,
+        # counting from the boot of its host.  Merged as they are, stamps
+        # ahead of the local clock would never expire, and once they fill
+        # the set every id revoked here would be purged as the oldest one
+        # the moment it is added (#4300).
+        consumer = Consumer(self.app)
+        panel = self.create_panel(consumer=consumer)
+        panel.state.hostname = 'elaine@vandelay.com'
+        ahead = time.monotonic() + 10 ** 6
+        try:
+            panel.handle('hello', {
+                'from_node': 'george@vandelay.com',
+                'revoked': {
+                    'ahead1': [ahead, 0, 'ahead1'],
+                    'ahead2': [ahead, 1, 'ahead2'],
+                },
+            })
+            assert 'ahead1' in worker_state.revoked
+            assert 'ahead2' in worker_state.revoked
+            stamps = worker_state.revoked.as_dict()
+            assert stamps['ahead1'] <= time.monotonic()
+            assert stamps['ahead2'] <= time.monotonic()
+            worker_state.revoked.purge(
+                now=time.monotonic() + REVOKE_EXPIRES + 1
+            )
+            assert 'ahead1' not in worker_state.revoked
+            assert 'ahead2' not in worker_state.revoked
+        finally:
+            worker_state.revoked.discard('ahead1')
+            worker_state.revoked.discard('ahead2')
+
     def test_conf(self):
         consumer = Consumer(self.app)
         panel = self.create_panel(consumer=consumer)
diff --git a/t/unit/worker/test_state.py b/t/unit/worker/test_state.py
index e89af815001..193cbd50a5a 100644
--- a/t/unit/worker/test_state.py
+++ b/t/unit/worker/test_state.py
@@ -2,7 +2,7 @@
 import pickle
 import sys
 from importlib import import_module
-from time import time
+from time import monotonic, time
 from unittest.mock import Mock, patch
 
 import pytest
@@ -89,6 +89,28 @@ def test_should_terminate(self, should_stop):
 
 
 @pytest.mark.usefixtures('reset_state')
+class test_merge_revoked:
+
+    def test_nothing(self):
+        size = len(state.revoked)
+        state.merge_revoked(None)
+        state.merge_revoked([])
+        state.merge_revoked({})
+        assert len(state.revoked) == size
+
+    def test_ids_only(self):
+        ahead = monotonic() + 10 ** 6
+        try:
+            state.merge_revoked({'from-dict': [ahead, 0, 'from-dict']})
+            state.merge_revoked(['from-list'])
+            stamps = state.revoked.as_dict()
+            assert stamps['from-dict'] <= monotonic()
+            assert stamps['from-list'] <= monotonic()
+        finally:
+            state.revoked.discard('from-dict')
+            state.revoked.discard('from-list')
+
+
 class test_Persistent:
 
     @pytest.fixture
@@ -119,6 +141,17 @@ def test_merge(self, p, data=['foo', 'bar', 'baz']):
         for item in data:
             assert item in state.revoked
 
+    def test_merge_stamps_saved_items_locally(self, p):
+        # The stamps in the state db count from the boot of the host the
+        # worker ran on; after a reboot they are ahead of the clock.
+        saved = LimitedSet()
+        saved.add('rebooted', now=monotonic() + 10 ** 6)
+        p.db['zrevoked'] = p.compress(p._dumps(saved))
+        p.merge()
+        assert 'rebooted' in state.revoked
+        assert state.revoked.as_dict()['rebooted'] <= monotonic()
+        state.revoked.discard('rebooted')
+
     def test_merge_dict(self, p):
         p.clock = Mock()
         p.clock.adjust.return_value = 626
EOF_NCA_TEST_PATCH_7f3a
: '>>>>> Start Test Output'
pytest -rA --color=no -p no:cacheprovider --continue-on-collection-errors t/integration/test_inspect.py t/smoke/tests/test_revoked_sync.py t/unit/utils/test_collections.py t/unit/worker/test_consumer.py t/unit/worker/test_control.py t/unit/worker/test_state.py
: '>>>>> End Test Output'
git checkout beef13ac9996b49ecc4aa9c7363cc0dd20db3da3 -- t/integration/test_inspect.py t/unit/utils/test_collections.py t/unit/worker/test_consumer.py t/unit/worker/test_control.py t/unit/worker/test_state.py
