Revoked task still executes?
This issue is a continuation of issues https://github.com/celery/celery/issues/4295 (see for Celery details) and https://github.com/celery/celery/issues/4299.

I am trying to [cancel a scheduled task](http://docs.celeryproject.org/en/latest/faq.html#can-i-cancel-the-execution-of-a-task) using [revoke()](http://docs.celeryproject.org/en/latest/reference/celery.result.html#celery.result.AsyncResult.revoke), but the task still executes. Here’s the Celery log:


```
[2017-09-28 17:52:18,811: INFO/MainProcess] Received task: app.tasks._do_singlething[0e4f0131-b4e6-4209-865e-e91b73e92f28]  ETA:[2017-09-28 07:53:18.766382+00:00] 
[2017-09-28 17:52:32,091: INFO/MainProcess] Tasks flagged as revoked: 0e4f0131b4e64209865ee91b73e92f28
[2017-09-28 17:53:18,831: WARNING/ForkPoolWorker-1] Hello from executing task 0e4f0131-b4e6-4209-865e-e91b73e92f28
[2017-09-28 17:53:18,841: INFO/ForkPoolWorker-1] Task app.tasks._do_singlething[0e4f0131-b4e6-4209-865e-e91b73e92f28] succeeded in 0.06189309403998777s: None
```

Code snippet that revokes is the same as in issue https://github.com/celery/celery/issues/4299.


