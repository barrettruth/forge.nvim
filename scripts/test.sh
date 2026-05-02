#!/bin/sh
set -eu

jobs=${FORGE_TEST_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 4)}
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT HUP INT TERM

if [ "$#" -gt 0 ]; then
  list=$tmpdir/files
  : >"$list"
  for file do
    printf '%s\n' "$file" >>"$list"
  done
else
  list=$tmpdir/files
  find spec -name '*_spec.lua' -print | sort >"$list"
fi

if [ ! -s "$list" ]; then
  printf '%s\n' 'no spec files found' >&2
  exit 1
fi

export tmpdir

run_file() {
  file=$1
  id=$(printf '%s' "$file" | cksum | awk '{print $1}')
  out=$tmpdir/$id.out
  status=$tmpdir/$id.status
  if busted "$file" >"$out" 2>&1; then
    printf 'ok %s\n' "$file" >"$status"
  else
    printf 'not ok %s\n' "$file" >"$status"
    return 1
  fi
}

wait_batch() {
  batch_failed=0
  while IFS= read -r pid; do
    if ! wait "$pid"; then
      batch_failed=1
    fi
  done <"$pids"
  : >"$pids"
  return "$batch_failed"
}

run_failed=0
pids=$tmpdir/pids
: >"$pids"
running=0
while IFS= read -r file; do
  run_file "$file" &
  printf '%s\n' "$!" >>"$pids"
  running=$((running + 1))
  if [ "$running" -ge "$jobs" ]; then
    if ! wait_batch; then
      run_failed=1
    fi
    running=0
  fi
done <"$list"

if [ "$running" -gt 0 ]; then
  if ! wait_batch; then
    run_failed=1
  fi
fi

failed=0
while IFS= read -r file; do
  id=$(printf '%s' "$file" | cksum | awk '{print $1}')
  status_file=$tmpdir/$id.status
  out_file=$tmpdir/$id.out
  if [ -f "$status_file" ]; then
    cat "$status_file"
    if grep -q '^not ok ' "$status_file"; then
      failed=1
      cat "$out_file"
    fi
  else
    failed=1
    printf 'not ok %s\n' "$file"
    if [ -f "$out_file" ]; then
      cat "$out_file"
    fi
  fi
done <"$list"

[ "$failed" -eq 0 ] && [ "$run_failed" -eq 0 ]
