# celery__celery-10714

- repo: `celery/celery`, created: 2026-09-27, base_commit: `d467a3783c4a`
- PR: https://github.com/celery/celery/pull/10714
- issue: https://github.com/celery/celery/issues/10713
- FAIL_TO_PASS: 6 tests, PASS_TO_PASS: 36 tests, collection_error: **no**

## 1. Issue (what the agent sees)

forget() is not idempotent on azureblockblob and cosmosdb result backends
### Summary

`result.forget()` on a missing result should be a no-op on every KV result backend. PR #10697 made `forget()` idempotent for the Elasticsearch and CouchDB backends (matching the existing `DocumentNotFoundException` handling in `couchbase.py` and the no-op behavior of Redis, cache, DynamoDB, ArangoDB, and S3's non-raising `delete_object`). Two backends still let a missing-key error through:

- `celery/backends/azureblockblob.py`: `blob_client.delete_blob()` raises `azure.core.exceptions.ResourceNotFoundError` for a missing blob.
- `celery/backends/cosmosdbsql.py`: `DeleteDocument()` raises `azure.cosmos.exceptions.HTTPFailure` (or the legacy `HTTPFailure`) with status 404 for a missing document.

(`gcs.py` checks `blob.exists()` first, so it already behaves as a no-op.)

### Suggested fix

Catch the missing-key exception in each backend's `delete()` (mirroring #10697), so `forget()` behaves consistently across KV backends.

Found during review of #10697 — filing separately per the reviewer's suggestion.

## 2. Gold patch

```diff
diff --git a/celery/backends/azureblockblob.py b/celery/backends/azureblockblob.py
index 071c4d2c78a..3ab0a9fc8e6 100644
--- a/celery/backends/azureblockblob.py
+++ b/celery/backends/azureblockblob.py
@@ -174,7 +174,12 @@ def delete(self, key):
             blob=f'{self.base_path}{key}',
         )
 
-        blob_client.delete_blob()
+        try:
+            blob_client.delete_blob()
+        except ResourceNotFoundError:
+            # deleting an already-expired, already-forgotten or never-stored
+            # result must keep forget() idempotent, like the other KV backends
+            pass
 
     def as_uri(self, include_password=False):
         if include_password:
diff --git a/celery/backends/cosmosdbsql.py b/celery/backends/cosmosdbsql.py
index e32b13f2e78..01d625c1349 100644
--- a/celery/backends/cosmosdbsql.py
+++ b/celery/backends/cosmosdbsql.py
@@ -213,6 +213,13 @@ def delete(self, key):
         LOGGER.debug("Deleting CosmosDB document %s/%s/%s",
                      self._database_name, self._collection_name, key)
 
-        self._client.DeleteDocument(
-            self._get_document_link(key),
-            self._get_partition_key(key))
+        try:
+            self._client.DeleteDocument(
+                self._get_document_link(key),
+                self._get_partition_key(key))
+        except HTTPFailure as ex:
+            if ex.status_code != ERROR_NOT_FOUND:
+                raise
+            # deleting an already-expired, already-forgotten or never-stored
+            # result must keep forget() idempotent, like the other KV backends
+            return
```

## 3. Test patch

```diff
diff --git a/t/unit/backends/test_azureblockblob.py b/t/unit/backends/test_azureblockblob.py
index af1523a6c89..a5b1ecbae80 100644
--- a/t/unit/backends/test_azureblockblob.py
+++ b/t/unit/backends/test_azureblockblob.py
@@ -187,6 +187,25 @@ def test_delete(self, mock_client, base_path):
         mock_client.get_blob_client.return_value \
             .delete_blob.assert_called_once()
 
+    @patch(MODULE_TO_MOCK + ".AzureBlockBlobBackend._blob_service_client")
+    def test_forget_missing_task_is_noop(self, mock_client, base_path):
+        self.backend.base_path = base_path
+        mock_client.get_blob_client.return_value \
+            .delete_blob.side_effect = azureblockblob.ResourceNotFoundError
+
+        # forget() on a result that was expired, already forgotten or never
+        # stored must not raise ResourceNotFoundError
+        self.backend.delete(b"mykey")
+
+    @patch(MODULE_TO_MOCK + ".AzureBlockBlobBackend._blob_service_client")
+    def test_forget_twice_is_noop(self, mock_client, base_path):
+        self.backend.base_path = base_path
+        mock_client.get_blob_client.return_value \
+            .delete_blob.side_effect = [None, azureblockblob.ResourceNotFoundError]
+
+        self.backend.delete(b"mykey")
+        self.backend.delete(b"mykey")
+
     def test_base_path_conf(self, base_path):
         self.app.conf.azureblockblob_base_path = base_path
         backend = AzureBlockBlobBackend(
diff --git a/t/unit/backends/test_cosmosdbsql.py b/t/unit/backends/test_cosmosdbsql.py
index bfd0d0d1e1f..34766cc9056 100644
--- a/t/unit/backends/test_cosmosdbsql.py
+++ b/t/unit/backends/test_cosmosdbsql.py
@@ -137,3 +137,30 @@ def test_delete(self, mock_client):
         mock_client.DeleteDocument.assert_called_once_with(
             "dbs/celerydb/colls/celerycol/docs/mykey",
             {"partitionKey": "mykey"})
+
+    @patch(MODULE_TO_MOCK + ".CosmosDBSQLBackend._client")
+    def test_forget_missing_task_is_noop(self, mock_client):
+        mock_client.DeleteDocument.side_effect = \
+            cosmosdbsql.HTTPFailure(cosmosdbsql.ERROR_NOT_FOUND)
+
+        # forget() on a result that was expired, already forgotten or never
+        # stored must not raise HTTPFailure
+        self.backend.delete(b"mykey")
+
+    @patch(MODULE_TO_MOCK + ".CosmosDBSQLBackend._client")
+    def test_forget_twice_is_noop(self, mock_client):
+        mock_client.DeleteDocument.side_effect = [
+            None,
+            cosmosdbsql.HTTPFailure(cosmosdbsql.ERROR_NOT_FOUND),
+        ]
+
+        self.backend.delete(b"mykey")
+        self.backend.delete(b"mykey")
+
+    @patch(MODULE_TO_MOCK + ".CosmosDBSQLBackend._client")
+    def test_delete_reraises_other_http_failures(self, mock_client):
+        mock_client.DeleteDocument.side_effect = \
+            cosmosdbsql.HTTPFailure(500)
+
+        with pytest.raises(cosmosdbsql.HTTPFailure):
+            self.backend.delete(b"mykey")
```

## 4. FAIL_TO_PASS tests

- `t/unit/backends/test_azureblockblob.py::test_AzureBlockBlobBackend::test_forget_missing_task_is_noop[]`
- `t/unit/backends/test_azureblockblob.py::test_AzureBlockBlobBackend::test_forget_missing_task_is_noop[my_folder/]`
- `t/unit/backends/test_azureblockblob.py::test_AzureBlockBlobBackend::test_forget_twice_is_noop[]`
- `t/unit/backends/test_azureblockblob.py::test_AzureBlockBlobBackend::test_forget_twice_is_noop[my_folder/]`
- `t/unit/backends/test_cosmosdbsql.py::test_DocumentDBBackend::test_forget_missing_task_is_noop`
- `t/unit/backends/test_cosmosdbsql.py::test_DocumentDBBackend::test_forget_twice_is_noop`
