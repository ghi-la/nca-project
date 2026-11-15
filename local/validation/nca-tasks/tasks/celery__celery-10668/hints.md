+1

Here some exemple of my code that I trying to run on background
Basic is to create multiple streams on twitter and disconnect when the task is revoke.
Another issue is how I keep the stream running after worker restart.

```
Python 3.6.2rc2
Celery 4.1.0 (latentcall)
  broker: rabbitmq:3.6.12
  backend: redis:3.2.10
```

```
import json

from tweepy import Stream
from tweepy import OAuthHandler
from tweepy.streaming import StreamListener

from celery import signals
from celery.result import AsyncResult

from ..worker import queue

__all__ = ['comsume', 'disconnect']


class TwitterStreamTask(queue.Task):
    
    def __init__(self):
        self.stream = None


class StdOutListener(StreamListener):
    
    def on_data(self, data):
        print(json.loads(data).get('id'))
        return True

    def on_error(self, status):
        print(status)


@queue.task(
    name='hermes.twitter.stream.consume',
    base=TwitterStreamTask,
    bind=True,
    ignore_result=True)
def comsume(self, **kargs):
    auth = OAuthHandler(kargs['consumer_token'], kargs['consumer_secret'])
    auth.set_access_token('token_key', 'token_secret')
    l = StdOutListener()
    
    self.stream = Stream(auth, l)
    self.stream.filter(track=['basketball'])
    self.update_state(state='RUNNING')


def on_task_revoked(request, **kargs):
    task = AsyncResult(request.id)
    task.stream.disconnect()

signals.task_revoked.connect(on_task_revoked, dispatch_uid='on_task_revoked')
```
could you check the latest master if the issue is fixed?
@auvipy, which change set is supposed to fix the issue? I’d like to review.
I am not sure actually. so requesting if anyone have time and scope to verify on master branch, we have a planned release of 4.2 within the first/2nd week of january
@auvipy any word on 4.2 release? we are experiencing this same issue. Thanks!
4.2 should be release by this week end as far I know
@auvipy, is this issue fixed with the 4.2 release? Celery’s mounting number of bugs and issues are seriously impacting productivity, and we’re already investigating alternatives (e.g. [dramatiq](https://github.com/Bogdanp/dramatiq)).
I don't know
@jenstroeger I have a pattern that has been working for me. I grab the task id from the task object that's returned after I initially execute the task using `apply_async` and persist the task id. If I need to cancel the task I use `celery.control.revoke(celery_task_id)` which may or may not be invoking a different version of the revoke method that I see you're using. Anyhow, it has been working for me.

If that still doesn't work you may be having an issue with persisting the revoke: http://docs.celeryproject.org/en/latest/userguide/workers.html#worker-persistent-revokes

@skeezus, I’ve implemented similar workarounds, including scouring the Redis store (i.e. Celery’s result backend) for task and group ids. However, these are poor attempts to deal with broken software.

The fact that @auvipy doesn’t investigate, let alone fix something as fundamental as revoking tasks is very worrisome to me. Certainly enough reason to dump Celery for something that actually works reliably: https://stackoverflow.com/questions/46517613/python-task-queue-alternatives-and-frameworks
@jenstroeger before making any statement keep in mind that we all work as volunteer and still have to look after many things. The way celery grown it's impossible to maintain it without atleast one full time maintainer. so it is not possible to investigate everything reported. If any of the core team member face the same issue reported then it is easier to get it fixed faster.
I just tried running 4.2.0rc4, and unfortunately it didn't help with processing revoked tasks.  Still just a massive stream in our logs of the revoked tasks being processed.

```
{"event": "celery.task_revoked", "timestamp": "2018-05-24T18:31:55.494003", "msg": "Tasks flagged as revoked: b12df8c0-39ae-46e1-b8a2-6eba7fac5b0a", "task_id": "b12df8c0-39ae-46e1-b8a2-6eba7fac5b0a", "environment": "prod", "app": "myapp", "level": "INFO"}
{"event": "celery.task_revoked", "timestamp": "2018-05-24T18:31:55.495576", "msg": "Tasks flagged as revoked: 1b2ea978-1463-45ff-a8dd-a8e591006e67", "task_id": "1b2ea978-1463-45ff-a8dd-a8e591006e67", "environment": "prod", "app": "myapp", "level": "INFO"}
{"event": "celery.task_revoked", "timestamp": "2018-05-24T18:31:55.497143", "msg": "Tasks flagged as revoked: c8dc2844-ad5c-4b30-a514-a361c57aa4b6", "task_id": "c8dc2844-ad5c-4b30-a514-a361c57aa4b6", "environment": "prod", "app": "myapp", "level": "INFO"}
{"event": "celery.task_revoked", "timestamp": "2018-05-24T18:31:55.498681", "msg": "Tasks flagged as revoked: 23f99bab-b019-488b-9e50-500d96bf747a", "task_id": "23f99bab-b019-488b-9e50-500d96bf747a", "environment": "prod", "app": "myapp", "level": "INFO"}
{"event": "celery.task_revoked", "timestamp": "2018-05-24T18:31:55.500246", "msg": "Tasks flagged as revoked: 698dbb4d-0b07-4710-8dc3-526178ccae78", "task_id": "698dbb4d-0b07-4710-8dc3-526178ccae78", "environment": "prod", "app": "myapp", "level": "INFO"}
````
@skeezus `AsyncResult.revoke` runs `control.revoke` internally, thus I see no difference in implementation there.

@mmrobins does this happen on individual tasks or you are using chain/group or some other Canvas workflow?
I tried to reproduce the issue:

```python
from celery import Celery, chain

app = Celery(broker='redis://', backend='redis://127.0.0.1/')

@app.task
def add(x, y):
    return x + y

def run():
    return (add.s(5,6) | add.s(10) | add.s(100)).apply_async()

def revoke_chain(last_result):
    print '[CALLER] Revoking: {}'.format(last_result.task_id)
    last_result.revoke()
    if last_result.parent is not None:
        revoke_chain(last_result.parent)
```

Started a worker with minimum concurrency to throttle task execution so that revocation is visible:

```bash
$ celery worker -A chain_tasks -l info -c 1
```

Running and revoking almost instantly:

```python
revoke_chain(run())
```

Although the output will not be the same always, due to timing issues, you can expect something like this:

```
[CALLER] Revoking: 401ee9cf-4934-47c9-bbf9-0736d061ab51
[2018-05-25 08:08:13,224: INFO/MainProcess] Received task: chain_tasks.add[1d22ff01-e8a5-4893-8511-77d22bcdf065]  
[CALLER] Revoking: 519acdef-6e7b-4111-b2d8-9d20e5b24a53
[2018-05-25 08:08:13,226: INFO/MainProcess] Tasks flagged as revoked: 401ee9cf-4934-47c9-bbf9-0736d061ab51
[CALLER] Revoking: 1d22ff01-e8a5-4893-8511-77d22bcdf065
[2018-05-25 08:08:13,227: INFO/MainProcess] Tasks flagged as revoked: 519acdef-6e7b-4111-b2d8-9d20e5b24a53
[2018-05-25 08:08:13,231: INFO/MainProcess] Tasks flagged as revoked: 1d22ff01-e8a5-4893-8511-77d22bcdf065
[2018-05-25 08:08:13,232: INFO/PoolWorker-1] Task chain_tasks.add[1d22ff01-e8a5-4893-8511-77d22bcdf065] succeeded in 0.00398159101314s: 11
[2018-05-25 08:08:13,233: INFO/MainProcess] Received task: chain_tasks.add[519acdef-6e7b-4111-b2d8-9d20e5b24a53]  
[2018-05-25 08:08:13,234: INFO/MainProcess] Discarding revoked task: chain_tasks.add[519acdef-6e7b-4111-b2d8-9d20e5b24a53]
```

As far as I understand `revoke` seems to be working properly, apart from the fact that we may need an additional option to also revoke all parent tasks (remains to be discussed). I would like to clarify also how `revoke` works to make sure that its usage can be better understood. `revoke` broadcasts a message to all **active** worker instances to dequeue and discard the task, it **does not delete the message from the queue**. I mentioned before that this may be a timing issue.

Looking forward to hearing your feedback and questions.
@georgepsarakis Are you not able to reproduce the issue with the examples from the [original posting](https://github.com/celery/celery/issues/4300#issue-261227025)? There should be a complete code example referenced.
@jenstroeger the principle seems the same. Also I wanted to make clear the `revoke` functionality.

I noticed this though on your code (https://github.com/celery/celery/issues/4299):
```python
result = _do_otherthing.AsyncResult(task_id)
```

Are you storing somewhere the task ID and retrieving it later for revoking the tasks conditionally? The newly built `AsyncResult` instance will surely not have the `parent` property populated, if that is what you are asking.

@georgepsarakis, I think that [the documentation for `revoke()`](http://docs.celeryproject.org/en/latest/reference/celery.result.html#celery.result.AsyncResult.revoke):

> Send revoke signal to all workers. Any worker receiving the task, or having reserved the task, _must_ ignore it.

or [the related FAQ](http://docs.celeryproject.org/en/latest/faq.html#can-i-cancel-the-execution-of-a-task):

> Can I cancel the execution of a task? Answer: Yes, Use result.revoke()

does not really say what you’re saying in your comment: _it does not delete the message from the queue._ That is a fine and important detail and really needs to be mentioned!

> Are you storing somewhere the task ID and retrieving it later for revoking the tasks conditionally? The newly built AsyncResult instance will surely not have the parent property populated, if that is what you are asking.

I’m using [GroupResult.restore()](http://docs.celeryproject.org/en/latest/reference/celery.result.html#celery.result.GroupResult.restore) and yes, that’s what I’m asking.
@jenstroeger generally you cannot delete messages from an AMQP broker. Celery tries to work around this, by providing the `revoke` functionality, which, as you can imagine, is not trivial to implement. If you think about it, this is the only solution to this problem; you need a mechanism for notifying your consumers (workers) that certain messages should be ignored/discarded (unprocessed but acknowledged).

Possible improvements:
1. Clarify `revoke` documentation entries.
2. Recursively revoke all tasks in Canvas workflows.
> Clarify revoke documentation entries.

Quite necessary, yes.

> Recursively revoke all tasks in Canvas workflows.

Which assumes that canvas relationships are being persisted (see https://github.com/celery/celery/issues/4299), which doesn’t seem to be the case, which should at least be documented—better yet, fixed.

I have a rather similar but peculiar case, related with this issue. I have a chain of tasks that also include a chords. So a sample would be something like

```python
workflow = task1.s() | task2.s() | task3.s() | group(task4.s() for i in range(n)) | callback.s() | clean_up.s()
```
When a user executes a workflow I store the workflow as a tuple inside redis and when a user wants to revoke the workflow I recreate the Async result using `result_from_tuple` method like so:

```python
res = workflow.apply_async()
store_worfklow(res.as_tuple())
# later when user wants to revoke()
res = result_from_tuple(get_workflow_tuple(), app=celery_app)
res.revoke()
parent = res.parent
while parent is not None:
    parent.revoke()
    parent = parent.parent
```
I start celery worker with autoscale and fair profile:
```shell
celery -A my_app worker --autoscale=1,0 -Ofair -l info
```
If I have a worflow consuming all workers, and start and revoke another workflow, then I see the following behaviour:

- task1 is received (Main Process)
- task1 is discarded before executing as expected. 

But when I start worker with:
```shell
celery -A my_app worker --autoscale=4,2 -Ofair -l info
```
then 

- task1 is received (Main process)
- task1 is executed normally when picked by worker
- task2 is discarded.
I thought revoke should broadcast revoke to the worker and task is not executed either when received or when picked for execution. But this is not the case. 
I also encountered this problem while running celery on kubernetes with like 5 workers in our production environment. I was exploring the cause and stumbled upon a discrepancy among the list of revoked tasks of each worker. 

One of the workers had only 150 ish revoked tasks in total and all other nodes were at their max capacity of **50K**. It maybe a subtle bug in the `LimitedSet`, but I was consistently seeing workers revoking the task id (in logs) and then executing it later. 
I restarted the node that had 150 revoked tasks, it was synced with others and had 50K entries, but the problem still persisted. Although the `revoked` set for all nodes were at their max capacity, they weren't being purged.

It was very late and I resumed my debugging the next day and the problem disappeared. I was monitoring the revoked tasks list for each node, started some tasks and revoked them, they started with around 49900 ish total revokes, increased a bit and then they were purged to around 8000. 

Maybe this leads to a clue, but overall I am still lost.

[EDIT 10-11-2021]

I have noticed that this happens when I perform a rolling restart of the deployment. My conjecture is that the `monotonic` clock of the new worker gets reset, any new value you add to LimitedSet will have the timestamp lower than the oldest element in the set. And hence by default the new entry is already the oldest element. And if the set is already full, the new element get's popped off during purging. Coupled with the fact if the previous oldest item hasn't expired, the purging stops.
This is worth investigating.
Also, maybe the limit should be configurable.
Just wanted to make a note that may save people some time. The docs mention that revoke is only supported by redis and rabbitmq at this time. If you're using another broker then you likely won't get any errors, the task will just not revoke. I spent a ton of time trying to figure out what I was doing wrong until I realized sqlite simply wasn't supported as a broker (what I'm using) for remote control actions (which is what revoke uses).
Is there any way I can use `revoke` or something similar if I am using SQS as a message broker?
I've just made a simple test with 5.3.6 (emerald-rush). I've sent the same task that sleeps for 60m 10 times to a queue. Backend is Redis, and I made worker that spawns only two worker processes (-c 2). Then I wrote a tiny script that just calls app.control.revoke(<task id>) and I gave it ID of the tasks that I know are in the queue (listed all entries in Redis). Repeated this multiple times, verified that the task is still in the queue... Does this mean that we have no safe (read "supported") way to remove tasks from the queue? Mind you, these tasks are not running yet.