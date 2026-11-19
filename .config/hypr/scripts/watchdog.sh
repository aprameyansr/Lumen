#!/bin/sh
# Keeps the pill alive for this Hyprland session: runs quickshell in the
# foreground and restarts it a second after it exits, until Hyprland is gone.
run="${XDG_RUNTIME_DIR:-/tmp}"
exec 9>"$run/lumen-${HYPRLAND_INSTANCE_SIGNATURE}-watchdog.lock"
flock -n 9 || exit 0

while :; do
    qs 9>&- >/dev/null 2>&1
    [ -S "$run/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket.sock" ] || exit 0
    sleep 1
done
