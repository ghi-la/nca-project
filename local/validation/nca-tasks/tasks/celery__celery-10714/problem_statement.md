forget() is not idempotent on azureblockblob and cosmosdb result backends
### Summary

`result.forget()` on a missing result should be a no-op on every KV result backend. PR #10697 made `forget()` idempotent for the Elasticsearch and CouchDB backends (matching the existing `DocumentNotFoundException` handling in `couchbase.py` and the no-op behavior of Redis, cache, DynamoDB, ArangoDB, and S3's non-raising `delete_object`). Two backends still let a missing-key error through:

- `celery/backends/azureblockblob.py`: `blob_client.delete_blob()` raises `azure.core.exceptions.ResourceNotFoundError` for a missing blob.
- `celery/backends/cosmosdbsql.py`: `DeleteDocument()` raises `azure.cosmos.exceptions.HTTPFailure` (or the legacy `HTTPFailure`) with status 404 for a missing document.

(`gcs.py` checks `blob.exists()` first, so it already behaves as a no-op.)

### Suggested fix

Catch the missing-key exception in each backend's `delete()` (mirroring #10697), so `forget()` behaves consistently across KV backends.

Found during review of #10697 — filing separately per the reviewer's suggestion.

