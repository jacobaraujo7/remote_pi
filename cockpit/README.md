# Remote Pi Cockpit

Desktop client for coding agents: terminals, agents, files, git, worktrees,
databases and tasks side by side, on macOS, Windows and Linux, with iPad and
Android clients for remote hosts.

- Site and docs: https://remote-pi.jacobmoura.work/cockpit
- Downloads (dmg, exe, deb, rpm, apk): https://github.com/jacobaraujo7/remote_pi/releases?q=cockpit-v
- Packaging and release runbook: [packaging/README.md](packaging/README.md)

## cockpit-server on a Linux host (VPS)

Remote workspaces run a small headless `cockpit-server` on the host, reached
over SSH. The desktop app installs and updates it by itself on first connect
when it ships that target (macOS and Linux arm64 clients ship Linux arm64;
Linux x86_64 ships Linux x86_64). Every other combination, and the mobile
apps (which carry no server), need the host prepared once with the installer
below. Both paths install to the same place and recognize each other. Linux
x86_64 and arm64 only, user space, no sudo.

```bash
curl -fsSL https://remote-pi.jacobmoura.work/cockpit-server.sh | bash
# same script straight from GitHub (the site URL redirects here):
curl -fsSL https://raw.githubusercontent.com/jacobaraujo7/remote_pi/main/cockpit/install-server.sh | bash
```

The script lives at [install-server.sh](install-server.sh). What it does, in order:

1. Checks that the host is Linux and maps `uname -m` to `x86_64` or `arm64`.
2. Resolves the version: `COCKPIT_VERSION=x.y.z` if set, otherwise the latest
   `cockpit-server-v*` release on GitHub. The server version must match the
   Cockpit app you connect from.
3. Downloads `cockpit-server-<version>-linux-<arch>.zip` and `SHA256SUMS` from
   that release and verifies the checksum.
4. Unzips to a temp folder (`unzip`, else `python3`, else installs `unzip`
   with the package manager when sudo is passwordless) and runs the
   `install.sh` shipped inside the zip,
   which verifies `bundle.manifest`, does a smoke start, swaps the folder into
   `~/.cockpit/server` atomically (previous install kept as backup until the
   smoke passes) and links `~/.local/bin/cockpit-server`.
5. With `--service` (`bash -s -- --service`), registers a `systemd --user`
   unit via `cockpit-server service install` so the server starts at boot.
   It may print one `sudo loginctl enable-linger` command for you to run once.

Re-running the script updates the install; the same version is a no-op.

Manual download, for a host without internet access or if you prefer to read
the files first:

- Releases: https://github.com/jacobaraujo7/remote_pi/releases?q=cockpit-server-v
- Then `unzip cockpit-server-<version>-linux-<arch>.zip && ./cockpit-server/install.sh`

Service commands, once installed:

```bash
cockpit-server service install     # systemd --user unit, starts at boot
cockpit-server service status
cockpit-server service uninstall
cockpit-server --version
```

Full page with troubleshooting: https://remote-pi.jacobmoura.work/cockpit/docs#remote

## Development

Prerequisites: Flutter (version pinned in `.github/workflows/cockpit-release.yml`),
Rust via rustup, Zig 0.16.0. See [CLAUDE.md](CLAUDE.md) for the architecture
and conventions.

```bash
flutter pub get
flutter run -d macos
flutter analyze && flutter test
```
