# `.dbq` query files

SQL with a comment frontmatter the app and the CLI understand:

```sql
-- db: dev-local
-- limit: 200
select id, email, created_at
from users
where active
order by created_at desc;
```

`-- db:` names a connection from `.cockpit/databases.json` (`cockpit db list`);
`-- limit:` caps the rows. The app shows the file as a query tab with the
result grid and re-runs it on every save; `cockpit db run <file.dbq>` runs it
from a terminal (one JSON line). Connections are read-only for agents by
default; see cockpit-db. Comment lines use `--` (the editor's `⌘/` does it).
