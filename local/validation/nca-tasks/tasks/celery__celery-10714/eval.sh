#!/bin/bash
set -uxo pipefail
cd /testbed
git config --global --add safe.directory /testbed
git status
git -c core.fileMode=false diff d467a3783c4ac898fbaefda86bdcc609fd57870f
git checkout d467a3783c4ac898fbaefda86bdcc609fd57870f -- t/unit/backends/test_azureblockblob.py t/unit/backends/test_cosmosdbsql.py
git apply -v - <<'EOF_NCA_TEST_PATCH_7f3a'
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
EOF_NCA_TEST_PATCH_7f3a
: '>>>>> Start Test Output'
pytest -rA --color=no -p no:cacheprovider --continue-on-collection-errors t/unit/backends/test_azureblockblob.py t/unit/backends/test_cosmosdbsql.py
: '>>>>> End Test Output'
git checkout d467a3783c4ac898fbaefda86bdcc609fd57870f -- t/unit/backends/test_azureblockblob.py t/unit/backends/test_cosmosdbsql.py
