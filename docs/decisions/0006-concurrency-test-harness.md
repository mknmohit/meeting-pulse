# Decision 0006: Database concurrency harness

The concurrency test runs only against the local test database using the
`supabase_admin` connection supplied by the local CLI. It opens two dblink
sessions and uses `dblink_send_query` so registration and claim operations
actually overlap.

The dblink execute grants are created inside the pgTAP helper session only.
They are not migrations and are not present in the production schema. CI runs
the database suite with the local superuser test URL, not the client role.
