#!/usr/bin/env python3

"""
Generate the Lumen colour set from a wallpaper and fan it out to the consumers.

One histogram pass yields both the area-dominant chromatic hue (binned by hue
family so a small vivid accent never hijacks the theme) and the mean lightness.

The mean lightness drives the pill's whole tone:
- bright wallpaper -> light pill with dark text
- dark wallpaper -> near-black pill with light text

The dominant hue tints every tier in HSL.
An achromatic wallpaper gets a neutral grey ramp.

Consumers:
- Quickshell: ~/.cache/lumen/colors.json
- Hyprland: ~/.cache/lumen/hypr-colors.lua
- Kitty: ~/.cache/lumen/kitty-colors.conf
- Starship: ~/.config/starship.toml
- Fastfetch: ~/.config/fastfetch/config.jsonc

Matugen is intentionally NOT used.
"""

import colorsys
import json
import re
import subprocess
import sys
from pathlib import Path


CACHE = Path.home() / ".cache" / "lumen"


SURF_NAMES = [
    "surface",
    "surface_container_low",
    "surface_container",
    "surface_container_high",
    "surface_container_highest",
    "outline_variant",
]

DARK_STEPS = [
    0.0,
    0.022,
    0.038,
    0.065,
    0.100,
    0.225,
]

LIGHT_STEPS = [
    0.0,
    -0.045,
    -0.075,
    -0.115,
    -0.160,
    -0.340,
]

TEXT_KEYS = [
    "cream",
    "bright",
    "subtle",
    "dim",
    "faint",
    "icon_dim",
    "tick_rest",
]

DARK_TEXT = [
    (0.90, 0.05),
    (0.97, 0.03),
    (0.73, 0.07),
    (0.54, 0.06),
    (0.44, 0.05),
    (0.81, 0.07),
    (0.75, 0.08),
]

LIGHT_TEXT = [
    (0.20, 0.18),
    (0.10, 0.20),
    (0.36, 0.14),
    (0.48, 0.10),
    (0.56, 0.08),
    (0.28, 0.12),
    (0.34, 0.12),
]


def analyze(wallpaper):
    out = subprocess.run(
        [
            "magick",
            wallpaper,
            "-alpha",
            "off",
            "-resize",
            "200x200",
            "-colors",
            "48",
            "-format",
            "%c",
            "histogram:info:-",
        ],
        capture_output=True,
        text=True,
    ).stdout

    buckets = {}
    total = 0
    lum = 0.0
    chroma = 0

    for line in out.splitlines():
        m = re.search(
            r"\s*(\d+):\s*\([^)]*\)\s*#([0-9A-Fa-f]{6})",
            line,
        )

        if not m:
            continue

        count = int(m.group(1))
        hex_str = m.group(2)

        r, g, b = (
            int(hex_str[i:i + 2], 16) / 255
            for i in (0, 2, 4)
        )

        h, l, s = colorsys.rgb_to_hls(r, g, b)

        total += count
        lum += count * l

        if s < 0.15 or l < 0.05 or l > 0.92:
            continue

        chroma += count

        bucket = buckets.setdefault(
            (int(h * 360) // 30) % 12,
            {
                "wsat": 0.0,
                "best": None,
            },
        )

        bucket["wsat"] += count * s

        score = count * s * (
            1 if 0.12 < l < 0.55 else 0.4
        )

        if (
            not bucket["best"]
            or score > bucket["best"][0]
        ):
            bucket["best"] = (
                score,
                h,
                s,
            )

    mean_l = lum / total if total else 0.0

    if not buckets or chroma < 0.08 * total:
        return None, 0.0, mean_l

    win = max(
        buckets.values(),
        key=lambda v: v["wsat"],
    )

    return (
        win["best"][1],
        win["best"][2],
        mean_l,
    )


def tint(hue, sat, light):
    r, g, b = colorsys.hls_to_rgb(
        hue % 1.0,
        max(0.0, min(1.0, light)),
        max(0.0, min(1.0, sat)),
    )

    return "#%02x%02x%02x" % (
        round(r * 255),
        round(g * 255),
        round(b * 255),
    )


def lerp(x, x0, x1, y0, y1):
    t = max(
        0.0,
        min(
            1.0,
            (x - x0) / (x1 - x0),
        ),
    )

    return y0 + t * (y1 - y0)


def render_fastfetch(pill):
    """
    Recolour the Fastfetch readout from the same pill palette.
    """

    ff = Path.home() / ".config" / "fastfetch"
    tmpl = ff / "config.jsonc.in"

    if not tmpl.is_file():
        print(
            "wallcolors: config.jsonc.in missing in "
            "~/.config/fastfetch, skipping fastfetch recolour",
            file=sys.stderr,
        )
        return

    def seq(h):
        return "%d;%d;%d" % tuple(
            int(h[i:i + 2], 16)
            for i in (1, 3, 5)
        )

    repl = {
        "__LANTERN__": str(ff / "lantern.txt"),
        "__KEYS__": seq(pill["primary"]),
        "__SEP__": seq(pill["dim"]),
        "__LOGO1__": seq(pill["primary"]),
        "__LOGO2__": seq(pill["on_primary_container"]),
        "__LOGO3__": seq(pill["surface_container"]),
        "__LOGO4__": seq(pill["surface_container_high"]),
        "__LOGO5__": seq(pill["subtle"]),
        "__LOGO6__": seq(pill["outline"]),
        "__LOGO7__": seq(pill["bright"]),
    }

    out = tmpl.read_text()

    for key, val in repl.items():
        out = out.replace(key, val)

    (
        ff / "config.jsonc"
    ).write_text(out)


def render_hypr(pill, hue, chromatic):
    """
    Generate Hyprland border colours directly.

    Active:
        Uses the wallpaper hue, but is deliberately muted.

    Inactive:
        Uses the wallpaper's surface hue at a very low lightness.

    Achromatic wallpapers get a neutral grey treatment.
    """

    if chromatic:
        active = tint(
            hue,
            0.25,
            0.54,
        )

        inactive = tint(
            hue,
            0.20,
            0.16,
        )
    else:
        active = "#85817c"
        inactive = "#292929"

    (
        CACHE / "hypr-colors.lua"
    ).write_text(
        'return {\n'
        '    active = "%s",\n'
        '    inactive = "%s",\n'
        '}\n'
        % (
            active,
            inactive,
        )
    )


def render_kitty(pill):
    """
    Kitty only needs the two tab title templates.

    No other Kitty colours are generated here.
    """

    def kitty_hex(value):
        return value.lstrip("#").upper()

    outline = kitty_hex(
        pill["outline_variant"]
    )

    surface = kitty_hex(
        pill["surface"]
    )

    bright = kitty_hex(
        pill["bright"]
    )

    primary = kitty_hex(
        pill["primary"]
    )

    kitty = (
        f'tab_title_template "{{{{fmt.fg._{outline}}}}}'
        f'{{{{fmt.bg._{surface}}}}}'
        f'{{{{fmt.fg._{bright}}}}}'
        f'{{{{fmt.bg._{outline}}}}} '
        f'({{{{index}}}}) {{{{title}}}} '
        f'{{{{fmt.fg._{outline}}}}}'
        f'{{{{fmt.bg._{surface}}}}} "\n'

        f'active_tab_title_template '
        f'"{{{{fmt.fg._{primary}}}}}'
        f'{{{{fmt.bg._{surface}}}}}'
        f'{{{{fmt.fg._{bright}}}}}'
        f'{{{{fmt.bg._{primary}}}}} '
        f'({{{{index}}}}) {{{{title}}}} '
        f'{{{{fmt.fg._{primary}}}}}'
        f'{{{{fmt.bg._{surface}}}}} "\n'
    )

    (
        CACHE / "kitty-colors.conf"
    ).write_text(kitty)


def render_starship(pill):
    """
    Preserve the user's complete Starship layout.

    Only the {{color}} placeholders are replaced.
    """

    template = r'''# No newline at start
add_newline = false

format = """
$cmd_duration 󰜥 $directory $python $git_branch
$character"""

# --------------------------
# CHARACTER (PROMPT SYMBOL)
# --------------------------
[character]
success_symbol = "[   ](bold fg:{{primary}})"
error_symbol   = "[   ](bold fg:{{outline}})"

# --------------------------
# GIT BRANCH
# --------------------------
[git_branch]
symbol = "󰘬"
style = "bg:{{outline}} fg:{{bright}}"
truncation_length = 12
format = "󰜥 [](bold fg:{{outline}})[$symbol $branch]($style)[ ](bold fg:{{outline}})"

# --------------------------
# DIRECTORY
# --------------------------
[directory]
home_symbol = "  "
read_only = "  "
style = "bg:{{surface_container_high}} fg:{{bright}}"
format = '[](bold fg:{{surface_container_high}})[󰉋 $path]($style)[](bold fg:{{surface_container_high}})'

[directory.substitutions]
"Desktop" = "  "
"Documents" = "  "
"Downloads" = "  "
"Music" = " 󰎈 "
"Pictures" = "  "
"Videos" = "  "
"GitHub" = " 󰊤 "

# --------------------------
# CMD DURATION
# --------------------------
[cmd_duration]
min_time = 0
style = "bg:{{primary}} fg:{{bright}}"
format = '[](bold fg:{{primary}})[󰪢 $duration]($style)[](bold fg:{{primary}})'

# --------------------------
# HOSTNAME
# --------------------------
[hostname]
style = "bg:{{outline_variant}} fg:{{bright}}"
format = "[](bold fg:{{outline_variant}})[•$hostname]($style)[](bold fg:{{outline_variant}})"
ssh_only = false
disabled = false

# --------------------------
# USERNAME
# --------------------------
[username]
style_user = "bold bg:{{surface_container}} fg:{{bright}}"
format = "[](bold fg:{{surface_container}})[$user]($style)[](bold fg:{{surface_container}})"
show_always = true

# --------------------------
# PACKAGE
# --------------------------
[package]
disabled = true

# --------------------------
# PYTHON VENV
# --------------------------
[python]
disabled = false
detect_extensions = []
detect_files = []
detect_folders = []
symbol = ""
style = "bg:{{primary_container}} fg:{{cream}}"
format = '[](bold fg:{{primary_container}})[$symbol ($virtualenv)]($style)[](bold fg:{{primary_container}})'
'''

    replacements = {
        "{{primary}}": pill["primary"],
        "{{outline}}": pill["outline"],
        "{{bright}}": pill["bright"],
        "{{surface_container_high}}": pill["surface_container_high"],
        "{{outline_variant}}": pill["outline_variant"],
        "{{surface_container}}": pill["surface_container"],
        "{{primary_container}}": pill["primary_container"],
        "{{cream}}": pill["cream"],
    }

    for key, value in replacements.items():
        template = template.replace(
            key,
            value,
        )

    (
        Path.home()
        / ".config"
        / "starship.toml"
    ).write_text(template)


def main():
    if len(sys.argv) < 2:
        return 1

    if sys.argv[1] == "--hue":
        hue = (
            float(sys.argv[2]) % 360
        ) / 360.0

        mode = (
            sys.argv[3]
            if len(sys.argv) > 3
            else "dark"
        )

        sat = (
            float(sys.argv[4])
            if len(sys.argv) > 4
            else 0.5
        )

        sat = max(
            0.0,
            min(1.0, sat),
        )

        mean_l = (
            0.85
            if mode == "light"
            else 0.12
        )

        chromatic = sat > 0.02

    else:
        wallpaper = sys.argv[1]

        if not Path(wallpaper).is_file():
            return 0

        hue, sat, mean_l = analyze(
            wallpaper
        )

        chromatic = hue is not None

        if not chromatic:
            hue = 0.0
            sat = 0.0

    CACHE.mkdir(
        parents=True,
        exist_ok=True,
    )

    light = mean_l >= 0.40

    surf_sat = (
        min(sat, 0.26)
        if light
        else min(
            max(
                sat,
                0.30 if chromatic else 0.0,
            ),
            0.45,
        )
    )

    acc_sat = (
        (
            min(
                sat + 0.18,
                0.85,
            )
            if light
            else min(
                max(sat, 0.30) + 0.12,
                0.82,
            )
        )
        if chromatic
        else 0.05
    )

    if light:
        base = lerp(
            mean_l,
            0.40,
            0.66,
            0.80,
            0.93,
        )

        steps = LIGHT_STEPS
        text = LIGHT_TEXT
        acc_l = 0.42
        deep_l = 0.30
        glow_l = 0.55

    else:
        base = lerp(
            mean_l,
            0.0,
            0.40,
            0.045,
            0.20,
        )

        steps = DARK_STEPS
        text = DARK_TEXT
        acc_l = 0.70
        deep_l = 0.34
        glow_l = 0.86

    pill = {
        name: tint(
            hue,
            surf_sat,
            base + step,
        )
        for name, step in zip(
            SURF_NAMES,
            steps,
        )
    }

    pill["primary"] = tint(
        hue,
        acc_sat,
        acc_l,
    )

    pill["primary_container"] = tint(
        hue,
        min(
            acc_sat + 0.08,
            0.90,
        ),
        deep_l,
    )

    pill["on_primary_container"] = tint(
        hue,
        min(
            acc_sat,
            0.45,
        ),
        glow_l,
    )

    pill["outline"] = tint(
        hue,
        surf_sat,
        base + (
            -0.35
            if light
            else 0.35
        ),
    )

    for key, (lit, st) in zip(
        TEXT_KEYS,
        text,
    ):
        pill[key] = tint(
            hue,
            st,
            lit,
        )

    (
        CACHE / "colors.json"
    ).write_text(
        json.dumps(
            pill,
            indent=2,
        ) + "\n"
    )

    render_fastfetch(pill)
    render_hypr(
        pill,
        hue,
        chromatic,
    )
    render_kitty(pill)
    render_starship(pill)

    return 0


if __name__ == "__main__":
    sys.exit(main())
