#!/bin/bash
# One-command update: pull the latest release of this repo, then re-run the idempotent
# installer, which refreshes the profile (config, skills, hooks), the sandbox policy and the
# sandbox image. Keeps your .env, your model choice, and the sandboxed terminal if you set it up.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

if [ -d .git ]; then
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "  ✗ you have local changes in $REPO_ROOT; commit or stash them, then re-run" >&2
    exit 1
  fi
  git pull --ff-only || { echo "  ✗ git pull failed; resolve it, then re-run" >&2; exit 1; }
fi

exec ./scripts/install.sh "$@"
