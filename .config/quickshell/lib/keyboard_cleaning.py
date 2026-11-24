"""Keep Hyprland keyboards disabled while Quickshell holds this process open."""

import select
import signal
import subprocess
import sys


DISABLE_KEYBOARDS = """
local cleaning = _G.lumen_keyboard_cleaning
if not cleaning then
    cleaning = { names = {}, ticks = 0 }
    cleaning.watchdog = hl.timer(function()
        cleaning.ticks = cleaning.ticks - 1
        if cleaning.ticks <= 0 then
            hl.dispatch(hl.dsp.reload_config())
        end
    end, { timeout = 1000, type = "repeat" })
    _G.lumen_keyboard_cleaning = cleaning
end
cleaning.ticks = 7

local changed = false
for _, device in ipairs(hl.get_devices()) do
    if device.type == "keyboard" and not cleaning.names[device.name] then
        hl.device({ name = device.name, enabled = false })
        cleaning.names[device.name] = true
        changed = true
    end
end
if changed then
    hl.exec_scheduled_prop_refresh_immediately()
end
"""

# Reloading restores the configured state, including intentionally disabled devices.
RESTORE_KEYBOARDS = """
if _G.lumen_keyboard_cleaning then
    hl.dispatch(hl.dsp.reload_config())
end
"""


def evaluate(code):
    result = subprocess.run(
        ["hyprctl", "eval", code],
        check=True,
        stdin=subprocess.DEVNULL,
        capture_output=True,
        text=True,
        timeout=3,
    )
    if result.stdout.strip() != "ok":
        raise RuntimeError(result.stdout.strip() or result.stderr.strip())


def stop_on_signal(*_):
    raise SystemExit(0)


def main():
    signal.signal(signal.SIGTERM, stop_on_signal)
    signal.signal(signal.SIGHUP, stop_on_signal)
    active = False
    status = 0
    try:
        while True:
            evaluate(DISABLE_KEYBOARDS)
            if not active:
                active = True
                print("active", flush=True)

            ready, _, _ = select.select([sys.stdin], [], [], 1)
            if ready:
                # The stop message and a closed pipe both end the cleaning session.
                break
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(error, file=sys.stderr)
        message = "Cleaning mode stopped unexpectedly." if active else "Could not disable keyboards in Hyprland."
        print(f"error: {message}", flush=True)
        status = 1
    finally:
        try:
            evaluate(RESTORE_KEYBOARDS)
        except (OSError, RuntimeError, subprocess.SubprocessError) as error:
            print(error, file=sys.stderr)
            if active:
                print("error: Hyprland did not respond. Keyboard restoration will be retried.", flush=True)
            status = 1
    return status


if __name__ == "__main__":
    sys.exit(main())
