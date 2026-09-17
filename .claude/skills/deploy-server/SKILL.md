---
name: deploy-server
description: Release the standalone cockpit-server zips for Linux hosts (VPS). Use when the user asks to deploy, release or "criar a tag" of the server, publish the cockpit-server zip, or watch/diagnose the cockpit-server-release GitHub Action. Pushes the cockpit-server-v<version> tag (version must equal cockpit/pubspec.yaml) and follows the workflow until the x86_64 and arm64 zips are on the GitHub Release.
---

# deploy-server

Release of `cockpit-server` as standalone zips, the thing
`https://remote-pi.jacobmoura.work/cockpit-server.sh` downloads. Trigger: tag
`cockpit-server-v<version>`, workflow
`.github/workflows/cockpit-server-release.yml`. Two native Linux jobs
(ubuntu-24.04 and ubuntu-24.04-arm), no Flutter build, a few minutes each.
Output: GitHub Release `cockpit-server-v<version>` with
`cockpit-server-<version>-linux-x86_64.zip`,
`cockpit-server-<version>-linux-arm64.zip` and `SHA256SUMS`.

Rules that always apply:
- Work on `main`. Never create a branch for a release.
- The tag version MUST equal `version:` in `cockpit/pubspec.yaml` (the meta
  job fails otherwise). Client and server are the same version by design:
  the mobile app refuses a different server version.
- This skill publishes the server only. It does not bump `pubspec.yaml` and
  does not tag or release the app. It releases the server for the version
  currently in `pubspec.yaml`; if that version already has a server release,
  see the note in pre-flight.
- Never kill any user process. No em-dashes in commit messages.

## 1. Pre-flight

```bash
cd cockpit
git status --short && git pull --ff-only
VERSION=$(sed -n 's/^version: *\([0-9][0-9.]*\).*/\1/p' pubspec.yaml); echo $VERSION
( cd packages/cockpit_server && dart analyze && dart test )   # Linux-only cases skip on macOS
bash -n packages/cockpit_server/install.sh tool/build-server-zip.sh install-server.sh
git tag -l "cockpit-server-v$VERSION"    # empty = not released yet
```

If the tag already exists and has a published release, ask the user whether
they really want to re-release the same version (it overwrites the zips with
`--clobber`). A new version number comes from the app's own release flow,
not from this skill.

## 2. Tag and watch

```bash
git tag cockpit-server-v$VERSION
git push origin cockpit-server-v$VERSION
sleep 20
RUN=$(gh run list --workflow cockpit-server-release.yml --limit 1 --json databaseId --jq '.[0].databaseId')
```

Watch in the background (5 to 10 minutes):

```bash
gh run watch $RUN --exit-status >/dev/null 2>&1; echo "exit=$?"
gh run view $RUN --json conclusion,jobs --jq '.conclusion, (.jobs[] | "\(.name): \(.conclusion)")'
```

Jobs: `Valida tag ↔ pubspec`, `zip (x86_64)`, `zip (arm64)`, `GitHub
Release`. Each zip job runs the server tests, builds the bundle
(`tool/build-server-zip.sh`: dart build cli + libcockpit_pty.so + Rust CLI,
manifest, smoke, `--version` check) and then installs the zip on the runner
with the shipped `install.sh` (idempotence and `~/.local/bin` link checked).

## 3. On failure

```bash
gh run view $RUN --json jobs --jq '.jobs[] | select(.conclusion=="failure") | "\(.databaseId) \(.name): " + ([.steps[] | select(.conclusion=="failure") | .name] | join(", "))'
gh run view --job <jobId> --log-failed | tail -80
```

Fix on `main`, push, then move the tag and rerun. Moving the tag is
acceptable here ONLY while the `GitHub Release` job has not published (the
zips are not consumed by any auto-updater; the curl installer reads the
release at install time):

```bash
git tag -f cockpit-server-v$VERSION && git push -f origin cockpit-server-v$VERSION
```

If the release was already published, re-running overwrites the assets
(`--clobber`), which is fine for a same-version fix but tell the user.
Known past causes: `subosito/flutter-action` has no Linux arm64 SDK (the
workflow clones Flutter via git on arm64), `exit()` dropping unflushed stdout
in `--version`.

## 4. After success

```bash
gh release view cockpit-server-v$VERSION --json assets -q '.assets[].name'
```

Report the version, run id and assets, and give the user the install line
for a host:

```bash
curl -fsSL https://remote-pi.jacobmoura.work/cockpit-server.sh | bash            # on demand
curl -fsSL https://remote-pi.jacobmoura.work/cockpit-server.sh | bash -s -- --service   # + systemd --user
```

Docs live in `site/src/app/cockpit/docs/page.tsx` (section "Remote hosts &
VPS") and `cockpit/README.md`; the packaging runbook in
`cockpit/packaging/README.md`.
