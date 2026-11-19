#!/usr/bin/env bash

name="$1" icon="$2" wd="$3"
shift 3
window=5
cap=65536

tmp="$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/launch-guard.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
[ -n "$wd" ] && cd "$wd" 2>/dev/null || :

SECONDS=0
"$@" 2>&1 >/dev/null | { head -c "$cap" >"$tmp"; cat >/dev/null; }
rc=${PIPESTATUS[0]}
[ "$rc" -ne 0 ] && [ "$SECONDS" -lt "$window" ] || exit 0

err="$(cat "$tmp")"
[ -n "$err" ] || err="(no output)"
tail3="$(printf '%s\n' "$err" | grep -v '^[[:space:]]*$' | tail -n 3)"

picked="$(notify-send -u critical -a Ricelin ${icon:+-i "$icon"} -A copy=Copy \
       "$name failed (exit $rc)" "$tail3")"
[ "$picked" = "copy" ] && printf '%s: exit %s\n%s\n' "$name" "$rc" "$err" | wl-copy
