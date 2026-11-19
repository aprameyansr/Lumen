#!/bin/sh

exec 9>"${XDG_RUNTIME_DIR:-/tmp}/lumen-watchdog.lock"
flock -n 9 || exit 0

launch() {
  qs -d 9>&- 2>/dev/null
}

while true; do
  qs ipc show >/dev/null 2>&1 || launch
  sleep 5
done
