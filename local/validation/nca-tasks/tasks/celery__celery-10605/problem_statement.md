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

