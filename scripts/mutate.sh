#!/usr/bin/env bash
# usage: scripts/mutate.sh <file> <make-target> <sed-expr>...
# Applies each sed expression to <file> one at a time and runs `make <target>`.
# The original file is always restored on exit.
set -u
file=$1; target=$2; shift 2
orig=$(mktemp)
cp "$file" "$orig"
trap 'cp "$orig" "$file"; rm -f "$orig"' EXIT
caught=0; bad=0
for m in "$@"; do
  cp "$orig" "$file"
  sed -i "$m" "$file"
  if cmp -s "$orig" "$file"; then
    echo "!! NOT APPLIED:  $m"; bad=$((bad+1)); continue
  fi
  out=$(make "$target" 2>&1); rc=$?
  if [ $rc -eq 0 ]; then
    echo "SURVIVED:        $m"; bad=$((bad+1))
  elif echo "$out" | grep -qiE "assertion error|AssertionError"; then
    echo "caught:          $m"; caught=$((caught+1))
  else
    echo "OTHER FAILURE (compile error?): $m"; bad=$((bad+1))
  fi
done
echo "caught=$caught   needs-attention=$bad"
