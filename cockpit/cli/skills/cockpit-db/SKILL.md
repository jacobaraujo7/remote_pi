---
name: cockpit-db
description: Query and inspect the workspace's databases from a Cockpit terminal: SQL (SQLite, Postgres, MySQL, MSSQL) through registered connections or `.dbq` files, Redis commands, MongoDB runCommand, listing connections and schemas, registering a connection in `.cockpit/databases.json`, and reaching a database through an SSH bastion. Use whenever the task mentions a database, a table, a query, a cache key, a collection, or a connection string.
---

# cockpit db / redis / mongo

The app executes every query for you: you never see credentials, and
**connections are read-only for agents by default**. Output is always **one
JSON line** (`{"ok": …}` or `{"error":{kind,message}}`, exit 1 on error).

Start with `cockpit db list` (names, engines, `access`). Prefer writing a
`.dbq` file when the human should see the result too: the app renders it as a
query tab and re-runs it on save (format in cockpit-design, `references/dbq.md`).

- `cockpit db <list|schema|query|run|execute>` — query the workspace's
  databases. Connections are registered in `.cockpit/databases.json` (Database
  panel); SQLite files in the repo are auto-detected. Output is **one JSON
  line**: `{"ok":{columns,rows,rowCount,truncated,elapsedMs}}` or
  `{"error":{kind,message}}` (exit 1). The app executes everything — you never
  see credentials. Examples:
  - `cockpit db list` — available connections (name, engine, target).
  - `cockpit db schema --db dev-local` / `… --db dev-local orders` — tables /
    columns of a table.
  - `cockpit db query --db dev-local --sql "SELECT …" [--limit N]` — rows are
    arrays (column order matches `columns`); `truncated: true` means the limit
    cut the cursor — raise `--limit` if you need more.
  - `cockpit db execute --db dev-local --sql "UPDATE …"` — returns
    `affectedRows`. **Connections are read-only for agents by default**: any
    write is rejected with kind `read_only_connection` until the human enables
    "Allow writes (agents)" on the connection in the Database panel — if you
    hit it, ask the human instead of working around it. `db list` shows each
    connection's `access` field (`read` | `readwrite`).
  - `cockpit db run <file.dbq>` — runs a `.dbq` file (SQL with `-- db:` /
    `-- limit:` comment frontmatter). Prefer writing a `.dbq` when the human
    should see the result too: the app shows it as a query tab and re-runs it
    every time you save the file.
  - Outside a Cockpit tab, add `--workspace <id|path>`.
- `cockpit redis --db <conn> <CMD> [args...]` — Redis/cache command. One
  JSON line reply. e.g. `cockpit redis --db cache HGETALL user:42`. Covers
  Redis/Valkey/KeyDB.
- `cockpit mongo --db <conn> [--database <name>] --command '<json>'` — MongoDB
  runCommand. The command is a runCommand document, e.g.
  `cockpit mongo --db app --command '{"find":"users","filter":{"active":true}}'`.
  Output: one JSON line `{"ok": <reply>}` / `{"error":{kind,message}}`.
  Documents use relaxed extended JSON (`{"$oid":…}`, `{"$date":…}`) both ways.
  - **Which database it runs against**: the one in the connection URL's path,
    if it has one; otherwise the one the human picked in the Database panel;
    otherwise the command fails and the error lists the databases available.
    `--database <name>` overrides all of it **for that call only** — it never
    changes what the human is looking at, so prefer it whenever you are not
    sure. Atlas URLs (`mongodb+srv://…/?…`) carry no database, so a connection
    can legitimately have none until someone picks one.
  - Discover databases with `--command '{"listDatabases":1}'` (routed to
    `admin` for you — that is the only database the server accepts it on), then
    collections with
    `--database <name> --command '{"listCollections":1,"nameOnly":true}'`.
    Running `listCollections` without knowing the database is the classic
    mistake: you get `system.users`/`system.roles`/`system.version` back, which
    is the `admin` database answering — not an empty deployment.
- **Browse commands open a view for the human — they return no data.** Use
  them to *show* what you found (after investigating with the commands above),
  not to query:
  - `cockpit redis browse --db <conn> [--pattern 'user:*']` — opens the
    editable Redis key table, pre-filtered. On an already-open table the
    pattern **replaces** the current filter.
  - `cockpit mongo browse --db <conn> [--database <name>] <collection>
    [--filter '<json>']` — here `--database` **does** change the connection's
    current database, because the tab you open becomes what the human sees —
    opens the Mongo collection browser (JSON document cards) pre-filtered.
    The filter lands in the visible filter bar, editable by the human.
- **Registering a connection** (`.cockpit/databases.json` at the workspace
  root — the file behind `cockpit db list` and the Database panel):

  ```json
  {
    "databases": [
      {"name": "dev-local", "url": "sqlite:./app.db", "savePassword": false},
      {"name": "app", "url": "postgres://user@localhost:5432/appdb", "savePassword": false},
      {"name": "cache", "url": "redis://localhost:6379/0", "savePassword": false},
      {"name": "docs", "url": "mongodb://localhost:27017/appdb", "savePassword": false}
    ]
  }
  ```

  The URL never carries the password — the human enters it in the Database
  panel (stored in the OS keychain when `savePassword` is on). A personal,
  gitignored overlay lives in `.cockpit/databases.local.json` (same shape,
  merged on top by name). The panel picks up edits on reload; `cockpit db
  list` confirms what's registered.
- **Connecting through a bastion (SSH tunnel)** — a connection may carry an
  optional `ssh` block. The app opens the tunnel and points the driver at a
  local port; every `cockpit db|redis|mongo` command works unchanged.

  ```json
  {
    "databases": [
      {
        "name": "prod",
        "url": "postgres://appuser@localhost:5432/appdb",
        "savePassword": true,
        "ssh": {
          "host": "bastion.acme.dev",
          "port": 22,
          "user": "deploy",
          "keyPath": "~/.ssh/id_ed25519",
          "savePassphrase": false
        }
      }
    ]
  }
  ```

  With a tunnel, the database `host`/`port` are resolved **from the SSH
  server** — `localhost` means the bastion itself, not your machine.
  Authentication is **key only**; the block never holds a secret (the
  passphrase, when the key has one, lives in the OS keychain).

  **Agents need the credential pre-saved.** If the key is passphrase-protected
  and the human hasn't enabled "Save passphrase" on the connection, your
  command fails fast with kind `ssh_credential_required` — there is no prompt
  on the CLI path. Ask the human to enable it rather than working around it.
  Other SSH failures come back as `ssh_host_key_unknown` (first connection
  must be approved once in the UI), `ssh_host_key_changed`, `ssh_auth_failed`,
  `ssh_key_missing` and `ssh_connect_failed`.

  **How the tunnel routes**, which matters when you read a failure: SQL engines
  and Redis go through a local **port forward** (they speak to one address).
  MongoDB goes through a local **SOCKS5 proxy** instead, because the driver
  discovers replica set members via `hello` and then dials the hostnames the
  server announces — a fixed local port would only ever reach the first node,
  and `mongodb+srv://` not even that. With SOCKS the driver picks each
  destination and the tunnel just routes, so Atlas/SRV and replica sets work
  unchanged. This requires a MongoDB driver built with SOCKS5 support; without
  it the driver rejects `proxyHost` loudly rather than connecting directly.

Outside a Cockpit tab, add `--workspace <id|path>` to any of these.
