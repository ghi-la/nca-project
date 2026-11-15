Hey @aaronst :wave:,
Thank you for opening an issue. We will get back to you as soon as we can.
Also, check out our [Open Collective](https://opencollective.com/celery) and consider backing us - every little helps!

We also offer priority support for our sponsors.
If you require immediate assistance please consider sponsoring us.

I can't recall any reason behind it for not supporting it in database back end. would you mind doing some experiment to add that?
It looks like [`sqlalchemy.types.ARRAY`](https://docs.sqlalchemy.org/en/20/core/type_basics.html#sqlalchemy.types.ARRAY) is only supported with PostgreSQL, so it would have to be `PickleType` to be fully compatible.
@auvipy any extra help here would be much appreciated. Happy to keep working the PR, but want to make sure I'm on the right track.
OK sure
Hi @auvipy

Could you please assign this issue to me? I would like to implement task children storage for the database result backend.

### Context & Plan:
- I reviewed the previous attempt in #8338 and the revert in #8475.
- The `Task` and `TaskExtended` models currently do not store `children`, which causes `AsyncResult.children` to always return an empty list when using SQLAlchemy database backends.
- To avoid breaking existing databases without migrations:
  1. Add a serialized `children` column (`sa.LargeBinary`) to `TaskExtended` (or `Task` with safe inspection).
  2. In `_update_result` and `_get_task_meta_for`, use Celery's configured serializer to serialize/deserialize child task metadata, gracefully falling back to `None`/empty list if the column or data is absent.
  3. Add test cases in `t/unit/backends/test_database.py` with canvas workflows (chains/groups) verifying `AsyncResult.children`.

Could you please assign this to me? I will prepare the implementation and tests.
@VimalN2005 there is no need for assignment, please proceed with the PR and ping me there. thanks for your interest to fix this old problem. and I also saw your stamping related PR. thanks for that as well