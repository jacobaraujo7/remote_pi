#!/usr/bin/env bash
# Keep this fork in sync with upstream and rebase the programmatic-rename branch on top.
# Safe to re-run: fast-forward for main, force-with-lease for the fix branch.
set -euo pipefail

UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/jacobaraujo7/remote_pi.git}"
BRANCH="${LOCAL_BRANCH:-feat/programmatic-rename-api}"

cd "$(dirname "$0")/.."

if ! git remote get-url upstream >/dev/null 2>&1; then
	git remote add upstream "$UPSTREAM_URL"
fi
git fetch upstream

if [ -n "$(git status --porcelain)" ]; then
	echo "error: working tree is dirty; commit or stash first" >&2
	exit 1
fi

# Mirror main to upstream (fast-forward only; fails if the fork diverged).
git checkout -B main upstream/main
git push origin main

# Re-apply local fixes; commits that upstream already merged are dropped.
git checkout "$BRANCH"
git rebase --empty=drop upstream/main
git push --force-with-lease origin "$BRANCH"
