#!/usr/bin/env bash
set -euo pipefail
umask 077

if (( $# != 3 )); then
  echo 'Usage: verify_first_frame.sh EXECUTABLE WINDOW_TITLE LOG_FILE' >&2
  exit 64
fi
binary=$1
title=$2
log_file=$3
[[ -x "$binary" && -n "$title" ]] || {
  echo 'An executable and a nonempty window title are required.' >&2
  exit 66
}
for command in xwininfo timeout; do
  command -v "$command" >/dev/null || {
    echo "Missing first-frame verification command: $command" >&2
    exit 69
  }
done

"$binary" >"$log_file" 2>&1 &
pid=$!
cleanup() {
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 70' TERM INT

fail_launch() {
  echo "$1" >&2
  tail -n 60 "$log_file" >&2
  exit 70
}

fatal_pattern='Unhandled[[:space:]]+exception|EXCEPTION CAUGHT BY|Could not prepare isolate|Could not create root isolate|Error initializing Dart VM'
viewable=false
for ((sample = 0; sample < 60; sample++)); do
  kill -0 "$pid" 2>/dev/null || fail_launch 'The application exited during startup observation.'
  if grep -Eiq "$fatal_pattern" "$log_file"; then
    fail_launch 'The application reported a startup exception.'
  fi
  viewable=false
  if timeout 1s xwininfo -name "$title" -stats 2>/dev/null \
    | grep -Fq 'Map State: IsViewable'; then
    viewable=true
  fi
  sleep 0.25
done
kill -0 "$pid" 2>/dev/null || fail_launch 'The application exited during startup observation.'
if grep -Eiq "$fatal_pattern" "$log_file"; then
  fail_launch 'The application reported a startup exception.'
fi
[[ "$viewable" == true ]] || fail_launch 'No visible Flutter first frame was observed.'
printf 'Verified visible Flutter first frame: %s\n' "$title"
