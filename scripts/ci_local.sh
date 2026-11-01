#!/usr/bin/env bash
# Run the full regression on a fresh clone: only committed files are tested.
set -eu
repo=$(git rev-parse --show-toplevel)
if [ -n "$(git -C "$repo" status --short)" ]; then
  echo "WARNING: uncommitted changes exist and are NOT part of this test:"
  git -C "$repo" status --short
fi
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
git clone -q "$repo" "$tmp/repo"
cd "$tmp/repo"
if [ -x "$repo/.venv/bin/python" ]; then export PATH="$repo/.venv/bin:$PATH"; fi
make test
echo "CLEAN-CLONE REGRESSION PASSED"
