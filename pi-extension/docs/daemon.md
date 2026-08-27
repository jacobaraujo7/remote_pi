# Daemon mode — troubleshooting

Companion to the README's [Daemon mode](../README.md#daemon-mode) section.
Each scenario starts with the symptom you'd actually observe, followed by
likely causes and how to fix.

---

## 1. `remote-pi install` fails

### "supervisor script not found"

```
[remote-pi] install failed: Error: supervisor script not found at
/Users/x/dist/bin/supervisord.js. Run `pnpm build` (dev) or
`npm install -g @hk_net/remote-pi` (prod) first.
```

You're running `remote-pi install` from a dev clone where `dist/` doesn't
exist yet, or from a partial install.

```bash
# Dev clone:
cd pi-extension && pnpm build

# Production install:
npm install -g @hk_net/remote-pi      # or pnpm install -g @hk_net/remote-pi
which pi-supervisord          # confirm bin is on PATH
remote-pi install
```

### "launchctl: bootstrap … already running"

A previous install left a stale entry. The fix is built into `install` —
re-run it and the supervisor unloads the old entry before bootstrapping
the new one. If it still fails:

```bash
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/dev.remotepi.supervisord.plist
launchctl unload ~/Library/LaunchAgents/dev.remotepi.supervisord.plist 2>/dev/null
rm ~/Library/LaunchAgents/dev.remotepi.supervisord.plist
remote-pi install
```

### "systemctl --user … No such file or directory"

Linux without a logged-in graphical session (headless server). On most
distros `systemctl --user` requires `loginctl enable-linger <user>` so
the unit survives logout:

```bash
loginctl enable-linger $USER
systemctl --user daemon-reload
remote-pi install
```

---

## 2. Supervisor doesn't start at login

### Check the service status

```bash
# Linux
systemctl --user status remote-pi-supervisord
journalctl --user -u remote-pi-supervisord -n 50

# macOS
launchctl list | grep remotepi
tail -100 ~/.pi/remote/supervisord.log
```

### Common failures

- **`pi: command not found`** in the log — Pi's binary isn't on the
  PATH that the unit inherited. `remote-pi install` captures
  `process.env.PATH` at install time; if you installed Pi *after*
  running install, re-run `remote-pi install` to refresh.
- **`Cannot find module …`** — the path baked into the unit doesn't
  match where `dist/bin/supervisord.js` actually lives. Happens if you
  uninstalled then reinstalled the package to a different location.
  Fix: `remote-pi uninstall && remote-pi install`.
- **Permission denied on UDS** — `~/.pi/remote/` exists with wrong
  perms (rare; only happens if you ran `pi` as `sudo` once). Delete
  the dir and let it re-create: `rm -rf ~/.pi/remote && remote-pi install`.

### Run the supervisor in the foreground for debugging

Bypass systemd/launchd and run it directly so you can see startup
errors live:

```bash
pi-supervisord
# or: node /path/to/remote-pi/dist/bin/supervisord.js
```

Ctrl-C to stop. If that works but the service doesn't, the problem is
in the unit/plist environment (PATH, HOME) — re-run `remote-pi install`.

---

## 3. A specific daemon stays `crashed`

`remote-pi daemon status` shows one row with `state=crashed` and a
restart count near 4 (the supervisor gives up after exponential
backoff: 1s, 5s, 30s, 5min).

### Step 1 — read the daemon's stderr

The supervisor forwards each daemon's stderr with a `[<cwd>]` prefix:

```bash
# Linux
journalctl --user -u remote-pi-supervisord -f | grep '\[/Users/x/Movies\]'

# macOS
tail -f ~/.pi/remote/supervisord.log | grep '\[/Users/x/Movies\]'
```

### Step 2 — run that daemon manually

Reproduce the failure with full visibility:

```bash
cd /Users/x/Movies
REMOTE_PI_DAEMON=1 pi --mode rpc -e $(npm root -g)/@hk_net/remote-pi/dist/extension.js
```

Common reasons a daemon won't start:

- **Local config missing.** `cd` into the daemon's folder and check
  `.pi/remote-pi/config.json` exists with `auto_start_relay: true`.
  Recreate via `remote-pi create <cwd>` (it provisions a default config
  when missing).
- **Pi extension config drift.** Pi's own settings (model, API keys)
  reset → daemon fails to authenticate to the provider. Run
  `cd <cwd> && pi` interactively to fix.
- **Port/UDS collision.** Another Pi process is already running in
  that cwd. The cwd-lock should reject the second one, but stale UDS
  sockets sometimes linger; check `lsof ~/.pi/remote/locks/<roomId>.sock`.

### Step 3 — force a re-spawn

After fixing the underlying problem, kick the supervisor:

```bash
remote-pi daemon restart      # bounces every daemon
```

---

## 4. `daemon send` says "daemon not running"

The supervisor has the registry entry but no live child for that id.
Most common cause: the daemon never started OR it crashed past the
retry budget.

```bash
remote-pi daemon status       # is state running?
remote-pi daemon start        # spawn any that aren't running
# Then retry send.
```

If `daemon start` shows `started=0, already_running=N`, the supervisor
isn't actually spawning. Possible reasons:
- Registry empty: `remote-pi daemons` to verify.
- Child crashes faster than the status check: `daemon status` immediately
  after start may still show `running` for a few seconds before the
  exit event marks it crashed. Re-check 2-3 seconds later.

---

## 5. Mobile app doesn't connect to a daemon

The daemon is up but the app doesn't see it.

### Confirm the daemon is paired

`pair_request` must have happened **before** the folder became a daemon
(daemons don't show QRs themselves):

```bash
cd <daemon-cwd>
pi
> /remote-pi devices         # confirm the device is listed
> /remote-pi stop            # stop interactive session — daemon takes over
remote-pi daemon restart
```

### Confirm the relay URL matches

The daemon uses the cwd's local config (`<cwd>/.pi/remote-pi/config.json`
agent_name + `~/.pi/remote/config.json` relay). Verify with:

```bash
cd <daemon-cwd>
pi
> /remote-pi status
```

The relay line should match what the mobile app is connecting to. If
not, update the relay URL and bounce the daemon:

```bash
remote-pi set-relay https://relay.example.tld
remote-pi daemon restart
```

---

## 6. Registry corrupted / partial

Symptom: `remote-pi daemons` errors out or shows nothing despite
having created entries.

```bash
cat ~/.pi/remote/daemons.json    # inspect
```

The file should be:

```json
{
  "daemons": [
    { "cwd": "/Users/x/Movies" },
    { "cwd": "/Users/x/Projects/backend" }
  ]
}
```

Fix manually if needed (it's a JSON list of `{cwd}` entries), or wipe
and re-create:

```bash
rm ~/.pi/remote/daemons.json
remote-pi create ~/Movies --name "Video Editor"
remote-pi create ~/Projects/backend --name "Backend"
remote-pi daemon restart
```

---

## 7. Uninstall cleanly + re-install from scratch

When you suspect everything is misconfigured:

```bash
remote-pi uninstall              # removes service, keeps registry
rm -rf ~/.pi/remote               # nukes registry + paired devices + keys
npm uninstall -g @hk_net/remote-pi
npm install -g @hk_net/remote-pi
remote-pi install
# Then re-pair + re-create daemons from scratch.
```

This is the "nuke everything" path. After this, the only state left is
each cwd's `<cwd>/.pi/remote-pi/config.json` — which you can either
keep (re-create restores the daemon) or delete (full reset).

---

## 8. Diagnostic commands cheat-sheet

```bash
# Where is the supervisor's UDS?
ls -la ~/.pi/remote/supervisor.sock

# Talk to the supervisor manually (raw JSONL):
echo '{"op":"list"}' | nc -U ~/.pi/remote/supervisor.sock

# Where are the daemon configs?
find ~/Projects -name "config.json" -path "*/.pi/remote-pi/*" 2>/dev/null

# Where are the cwd locks?
ls ~/.pi/remote/locks/

# Where are the paired devices?
cat ~/.pi/remote/peers.json

# What Pi binary is the supervisor about to spawn?
remote-pi install --dry-run      # (not implemented; check ~/Library/LaunchAgents or systemd unit manually)

# Quick liveness check
remote-pi daemon status
```

If after walking the list you're still stuck, file an issue with the
output of `remote-pi daemon status`, the recent supervisor log, and
the contents of `~/.pi/remote/daemons.json`.
