---
name: deploy-cockpit
description: Release the Cockpit desktop/mobile app. Use when the user asks to deploy, release, publish or "criar a tag" of Cockpit, bump its version, or watch/diagnose the cockpit-release GitHub Action. Bumps cockpit/pubspec.yaml and CHANGELOG.md, commits on main, pushes the cockpit-v<version> tag and follows the workflow until every job finishes, fixing and re-tagging on failure.
---

# deploy-cockpit

Release of the Cockpit app (`cockpit/`). Trigger: tag `cockpit-v<version>` on
the repo root, workflow `.github/workflows/cockpit-release.yml`. It produces
macOS dmg, Windows exe, Linux deb/rpm (x64 + arm64), Android apk + aab,
SHA256SUMS, latest.json and the Sparkle appcasts, and publishes latest.json to
rp-s3 automatically. Tag = publication, there is no manual gate.

Rules that always apply:
- Work on `main`. Never create a branch for a release.
- Never kill Cockpit or any user process while releasing.
- Every 1.x release is a beta of 2.0.0 (changelog sections say so).
- No em-dashes in commit messages or changelog text.
- Report the per-job result to the user; if a job fails, say which and why.

## 1. Pre-flight

```bash
cd cockpit
git status --short            # must be clean, or only the files you are about to commit
git pull --ff-only
flutter analyze && flutter test   # only if code changed since the last green run
grep '^version:' pubspec.yaml     # x.y.z+n
awk '/^## /{print; exit}' CHANGELOG.md
```

The workflow's `meta` job fails when the tag version differs from
`pubspec.yaml` or when the first `## ` section of `CHANGELOG.md` is not the
version being released. Both must be updated before tagging.

## 2. Bump

Patch bump unless the user says otherwise: `1.28.32+95` -> `1.28.33+96`
(version and build number both increase).

1. `pubspec.yaml`: `version: x.y.z+n`.
2. `CHANGELOG.md`: add `## [x.y.z] - YYYY-MM-DD` at the top, in English,
   starting with the beta sentence, then `### Added` / `### Fixed` /
   `### Changed` lists derived from `git log <last-tag>..HEAD -- cockpit/`.
   Keep the first ~20 non-empty lines meaningful on their own (the download
   page shows only those). No `## [Unreleased]`.
3. Commit and push:

```bash
git add pubspec.yaml CHANGELOG.md
git commit -m "chore(cockpit): bump x.y.z+n"
git push
```

This skill publishes the app only. It never tags or releases
`cockpit-server`; that is the `deploy-server` skill, run only when the user
asks for it.

## 3. Tag and watch

```bash
git tag cockpit-vx.y.z
git push origin cockpit-vx.y.z
sleep 20
RUN=$(gh run list --workflow cockpit-release.yml --limit 1 --json databaseId --jq '.[0].databaseId')
```

Watch in the background so the conversation stays free (the run takes
15 to 25 minutes, macOS is the slowest):

```bash
gh run watch $RUN --exit-status >/dev/null 2>&1; echo "exit=$?"
gh run view $RUN --json conclusion,jobs --jq '.conclusion, (.jobs[] | "\(.name): \(.conclusion)")'
```

Jobs: `Valida tag ↔ pubspec`, `cockpit-server (fatia x86_64)`, `macOS dmg`,
`Windows exe`, `Linux deb+rpm (amd64)`, `Linux deb+rpm (arm64)`,
`Android apk + aab`, `GitHub Release + latest.json`. All eight must be
`success`.

## 4. On failure

```bash
gh run view $RUN --json jobs --jq '.jobs[] | select(.conclusion=="failure") | "\(.databaseId) \(.name): " + ([.steps[] | select(.conclusion=="failure") | .name] | join(", "))'
gh run view --job <jobId> --log-failed | tail -80
```

Fix the cause in code or workflow, commit on `main`, then release a NEW patch
version (bump again, new tag). Do not force-move a `cockpit-v*` tag that
already produced a GitHub Release or a latest.json: the auto-updater may
already have seen it. Known past causes: a Linux-only test compiled on
Windows, `dart build cli --target-os` needing a newer Flutter, Zig cross-link
rejecting a Rust linker flag, a missing artifact making the 8-asset check
fail.

## 5. After success

Report the version, the run id and the asset list:

```bash
gh release view cockpit-vx.y.z --json assets -q '.assets[].name'
```

Mention what the user should test in this build, and remind that
`latest.json` is served with a 5 minute cache, so the in-app updater offers
the release shortly after.
