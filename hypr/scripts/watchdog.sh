#!/bin/sh

name="$1"

exec 9>"${XDG_RUNTIME_DIR:-/tmp}/${name}-watchdog.lock"
flock -n 9 || exit 0

# The pill is now the default Quickshell configuration.
qs_cmd() {
  qs "$@"
}

launch() {
  qs_cmd -d 9>&- 2>/dev/null

  i=0
  while [ "$i" -lt 30 ]; do
    qs_cmd ipc show >/dev/null 2>&1 && return
    sleep 1
    i=$((i + 1))
  done
}

while true; do
  qs_cmd ipc show >/dev/null 2>&1 || launch
  sleep 5
done
