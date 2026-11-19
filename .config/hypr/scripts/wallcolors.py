#!/usr/bin/env python3

"""
Generate the Lumen colour set from a wallpaper and fan it out to the consumers.

One histogram pass, read in OKLCH, yields the mean lightness, the area-dominant
colour family (base) and the most salient vivid colour (accent), so a small
bright highlight can lead the accent without taking over the surfaces.

The mean lightness drives the pill's whole tone:
- bright wallpaper -> light pill with dark text
- dark wallpaper -> near-black pill with light text

Surfaces are tinted from the base, the accent from the accent, and every text
tone and the accent are lifted until they meet a contrast floor on the body.
Settings' palette vibrancy (0 muted, 0.5 natural, 1 vivid) scales the chroma.
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
import math
import os
import re
import subprocess
import sys
from pathlib import Path


CACHE = Path.home() / ".cache" / "lumen"


HIST_LINE = re.compile(r"\s*(\d+):\s*\([^)]*\)\s*#([0-9A-Fa-f]{6})")
SURF_NAMES = ["surface", "surface_container_low", "surface_container",
              "surface_container_high", "surface_container_highest", "outline_variant"]
DARK_STEPS = [0.0, 0.012, 0.028, 0.045, 0.070, 0.130]
LIGHT_STEPS = [0.0, -0.018, -0.032, -0.048, -0.070, -0.160]
TEXT_KEYS = ["cream", "bright", "subtle", "dim", "faint", "icon_dim", "tick_rest"]
DARK_TEXT = [0.90, 0.97, 0.76, 0.62, 0.52, 0.83, 0.79]
LIGHT_TEXT = [0.27, 0.18, 0.42, 0.53, 0.62, 0.34, 0.40]
TEXT_MIN = [4.5, 4.5, 4.5, 3.0, 1.8, 4.5, 3.0]
NEUTRAL = {"mean_l": 0.0, "base": None, "accent": None}


def clamp(x, lo=0.0, hi=1.0):
    return max(lo, min(hi, x))


def lerp(x, x0, x1, y0, y1):
    return y0 + clamp((x - x0) / (x1 - x0)) * (y1 - y0)


def to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def to_gamma(c):
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def oklch(rgb):
    r, g, b = map(to_linear, rgb)
    l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ** (1 / 3)
    m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ** (1 / 3)
    s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ** (1 / 3)
    L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
    a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
    bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    return L, math.hypot(a, bb), math.degrees(math.atan2(bb, a)) % 360


def _lch_linear(L, C, h):
    a, b = C * math.cos(math.radians(h)), C * math.sin(math.radians(h))
    l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3
    m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3
    s = (L - 0.0894841775 * a - 1.2914855480 * b) ** 3
    return (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)


def lch(L, C, h):
    """OKLCH to sRGB hex, keeping lightness and hue and giving up chroma until it fits the gamut."""
    L = clamp(L)
    fits = lambda c: all(-1e-7 <= x <= 1 + 1e-7 for x in _lch_linear(L, c, h))
    if not fits(C):
        lo, hi = 0.0, C
        for _ in range(20):
            mid = (lo + hi) / 2
            lo, hi = (mid, hi) if fits(mid) else (lo, mid)
        C = lo
    return "#%02x%02x%02x" % tuple(round(clamp(to_gamma(clamp(x))) * 255) for x in _lch_linear(L, C, h))


def rgb(hex_str):
    return tuple(int(hex_str[i:i + 2], 16) / 255 for i in (1, 3, 5))


def luminance(hex_str):
    r, g, b = map(to_linear, rgb(hex_str))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(x, y):
    hi, lo = sorted((luminance(x), luminance(y)), reverse=True)
    return (hi + 0.05) / (lo + 0.05)


def hue_dist(a, b):
    return abs((a - b + 180) % 360 - 180)


def circ_mean(pairs):
    x = sum(w * math.cos(math.radians(h)) for w, h in pairs)
    y = sum(w * math.sin(math.radians(h)) for w, h in pairs)
    return math.degrees(math.atan2(y, x)) % 360


def percentile(pairs, q):
    pairs = sorted(pairs)
    goal, run = q * sum(w for _, w in pairs), 0.0
    for value, w in pairs:
        run += w
        if run >= goal:
            return value
    return pairs[-1][0] if pairs else 0.0


def smooth(bins):
    return [sum(bins[(i + k) % 72] * math.exp(-k * k / 8) for k in range(-6, 7)) for i in range(72)]


def _base(px, total):
    weight = lambda n, L, C: n * clamp((C - 0.012) / 0.05) * (1.0 if 0.1 < L < 0.95 else 0.3)
    bins = [0.0] * 72
    for n, L, C, h in px:
        bins[int(h // 5) % 72] += weight(n, L, C)
    if sum(bins) < 0.06 * total:
        return None
    sm = smooth(bins)
    peak = max(range(72), key=sm.__getitem__) * 5 + 2.5
    fam = [(n, L, C, h) for n, L, C, h in px if C >= 0.012 and hue_dist(h, peak) <= 30]
    hue = circ_mean([(weight(n, L, C), h) for n, L, C, h in fam])
    return [round(hue, 2), round(percentile([(C, n) for n, L, C, h in fam], 0.7), 4)]


def _families(px, total):
    """Vivid colour families, a 45 degree hue window per bin: (salience, hue, area, mean chroma, lightness, centre)."""
    vivid = [(n, L, C, h) for n, L, C, h in px if C >= 0.04 and 0.2 < L < 0.96]
    sums = [[0.0] * 5 for _ in range(72)]
    for n, L, C, h in vivid:
        s, w = sums[int(h // 5) % 72], n * C * C
        s[0] += n
        s[1] += n * C
        s[2] += n * C * L
        s[3] += w * math.cos(math.radians(h))
        s[4] += w * math.sin(math.radians(h))
    fams = []
    for i in range(72):
        area, cw, lw, x, y = (sum(sums[(i + k) % 72][j] for k in range(-4, 5)) for j in range(5))
        if area < 0.004 * total:
            continue
        mean_c, lit = cw / area, lw / cw
        hue = math.degrees(math.atan2(y, x)) % 360
        fams.append(((area / total) ** 0.4 * mean_c ** 2.5 * (1.0 if 0.3 < lit < 0.92 else 0.6),
                     hue, area / total, mean_c, lit, i * 5 + 2.5))
    return vivid, fams


def _accent(px, total, base):
    """The most salient vivid family, preferring a real highlight outside the base hue over a stronger base."""
    vivid, fams = _families(px, total)
    if not fams:
        return None
    far = [f for f in fams if base and hue_dist(f[1], base[0]) > 50
           and f[3] >= max(0.055, 0.5 * base[1]) and f[2] >= 0.006]
    _, hue, _, _, lit, centre = max(far or fams)
    mem = [(n, L, C, h) for n, L, C, h in vivid if hue_dist(h, centre) <= 22.5]
    return [round(hue, 2), round(percentile([(C, n) for n, L, C, h in mem], 0.8), 4), round(lit, 4)]


def features(histogram):
    """Mean lightness, area-dominant family (base) and most salient vivid colour (accent) of a magick histogram."""
    px, total, hls = [], 0, 0.0
    for line in histogram.splitlines():
        m = HIST_LINE.match(line)
        if not m:
            continue
        n, col = int(m.group(1)), tuple(int(m.group(2)[i:i + 2], 16) / 255 for i in (0, 2, 4))
        total += n
        hls += n * (max(col) + min(col)) / 2
        px.append((n, *oklch(col)))
    if not total:
        return None
    base = _base(px, total)
    return {"mean_l": round(hls / total, 4), "base": base, "accent": _accent(px, total, base)}


def manual_features(hue_deg, light, sat):
    """The Manual hue editor's HSL hue as features, so the pill matches the swatch the strip shows."""
    h = oklch(colorsys.hls_to_rgb((hue_deg % 360) / 360, 0.5, 0.75))[2]
    chromatic = sat > 0.02
    return {"mean_l": 0.85 if light else 0.12, "base": [h, 0.09] if chromatic else None,
            "accent": [h, 0.15, 0.70] if chromatic else None}


def mix(x, y):
    """Theme.textFaint's channel average of two colours."""
    return "#%02x%02x%02x" % tuple(round((a + b) / 2 * 255) for a, b in zip(rgb(x), rgb(y)))


def _readable(L, C, h, backs, ratio, step):
    while True:
        out = lch(L, C, h)
        if min(contrast(out, b) for b in backs) >= ratio or not 0.0 < L < 1.0:
            return out
        L += step


def palette(feat, light=None, vibrancy=0.5):
    """Pill colours from features, tone and strength (0 muted, 0.5 natural, 1 vivid), contrast-checked on the body."""
    v = clamp(vibrancy)
    light = feat["mean_l"] >= 0.40 if light is None else light
    base, acc = feat.get("base"), feat.get("accent")
    if base:
        bh, bc = base
        cap = (0.010 + 0.050 * v) if light else (0.012 + 0.058 * v)
        sc = min(max(bc * (0.18 + 0.50 * v), 0.004 + 0.014 * v), cap)
    else:
        bh, bc, sc = (acc[0] if acc else 60.0), 0.0, 0.0
    if acc:
        ah, ac, al = acc[0], acc[1] * (1.0 if base else 0.5), acc[2]
    else:
        ah, ac, al = bh, max(bc * 1.5, 0.08) if base else 0.0, None
    if base or acc:
        ac = min(max(ac * (0.45 + 0.75 * v), 0.02 + 0.06 * v), 0.10 + 0.14 * v)
    else:
        ac = 0.012
    m = feat["mean_l"]
    if light:
        sl, steps, text, sign = lerp(m, 0.40, 0.75, 0.950, 0.975), LIGHT_STEPS, LIGHT_TEXT, -1
        acc_l = clamp(0.50 + 0.3 * ((al or 0.6) - 0.6), 0.42, 0.58)
        deep_l, glow_l, outline_d = 0.38, 0.66, -0.40
    else:
        sl, steps, text, sign = lerp(m, 0.0, 0.40, 0.17, 0.25), DARK_STEPS, DARK_TEXT, 1
        acc_l = clamp(0.74 + 0.3 * ((al or 0.7) - 0.7) + 0.09 * clamp(1 - hue_dist(ah, 105) / 45), 0.66, 0.88)
        deep_l, glow_l, outline_d = 0.40, 0.88, 0.30
    p = {name: lch(sl + st, sc * (1.25 if name == "outline_variant" else 1.0), bh)
         for name, st in zip(SURF_NAMES, steps)}
    body = [p["surface"], p["surface_container_low"], p["surface_container_high"]]
    p["primary"] = _readable(acc_l, ac, ah, body, 3.2, sign * 0.01)
    p["primary_container"] = lch(deep_l, ac * 0.8, ah)
    p["on_primary_container"] = lch(glow_l, ac * (0.85 if light else 0.45), ah)
    p["outline"] = lch(sl + outline_d, sc, bh)
    tc = min(0.006 + sc * 0.45, 0.028) if base or acc else 0.0
    for key, lit, need in zip(TEXT_KEYS, text, TEXT_MIN):
        p[key] = _readable(lit, tc * (1.5 if key == "tick_rest" else 1.0), bh, body, need + 0.1, sign * 0.01)
    lit = text[TEXT_KEYS.index("faint")]
    while min(contrast(mix(p["faint"], p["subtle"]), b) for b in body) < 4.6 and 0.0 < lit < 1.0:
        lit += sign * 0.01
        p["faint"] = lch(lit, tc, bh)
    return p



def analyze(wallpaper):
    out = subprocess.run(
        ["magick", wallpaper, "-alpha", "off", "-resize", "128x128", "-depth", "8",
         "-format", "%c", "histogram:info:-"],
        capture_output=True, text=True).stdout
    return features(out)



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
        Uses a very dark version of the wallpaper hue.

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



def render_hyprlock(pill, light):
    """
    Generate Hyprlock colours from the same Lumen palette.
    """

    def rgba(hex_color, alpha=1.0):
        hex_color = hex_color.lstrip("#")
        r = int(hex_color[0:2], 16)
        g = int(hex_color[2:4], 16)
        b = int(hex_color[4:6], 16)

        return f"rgba({r}, {g}, {b}, {alpha})"

    text = pill["bright"]
    secondary = pill["subtle"]
    accent = pill["primary"]

    field_bg = pill["surface"]
    field_border = pill["outline"]

    (CACHE / "hyprlock-colors.conf").write_text(
        "# Generated by wallcolors.py — do not edit manually.\n"
        f"$hyprlock_text = {rgba(text, 0.95)}\n"
        f"$hyprlock_secondary = {rgba(secondary, 0.90)}\n"
        f"$hyprlock_accent = {rgba(accent, 1.00)}\n"
        f"$hyprlock_field_bg = {rgba(field_bg, 0.15)}\n"
        f"$hyprlock_field_border = {rgba(field_border, 0.30)}\n"
    )



def render_fish(pill, hue, light):
    """
    Generate the dynamic Fish colours.
    """

    if light:
        command_l = 0.36
        param_l = 0.48
    else:
        command_l = 0.70
        param_l = 0.56

    command = tint(
        hue,
        0.70,
        command_l,
    )

    param = tint(
        hue,
        0.42,
        param_l,
    )

    fish_theme = Path.home() / ".cache" / "lumen" / "fish-colors.fish"

    fish_theme.write_text(
        "# Generated by wallcolors.py — dynamic Fish colours." + chr(10)
        + f"set --global fish_color_command '{command}'" + chr(10)
        + f"set --global fish_color_param '{param}'" + chr(10)
        + f"set --global fish_color_operator '{param}'" + chr(10)
        + f"set --global fish_pager_color_completion '{param}'" + chr(10)
        + f"set --global fish_pager_color_prefix '{command}'" + chr(10)
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
        f'tab_title_template "{{fmt.fg._{outline}}}'
        f'{{fmt.bg._{surface}}}'
        f'{{fmt.fg._{bright}}}'
        f'{{fmt.bg._{outline}}} '
        f'({{index}}) {{title}} '
        f'{{fmt.fg._{outline}}}'
        f'{{fmt.bg._{surface}}} "\n'

        f'active_tab_title_template '
        f'"{{fmt.fg._{primary}}}'
        f'{{fmt.bg._{surface}}}'
        f'{{fmt.fg._{bright}}}'
        f'{{fmt.bg._{primary}}} '
        f'({{index}}) {{title}} '
        f'{{fmt.fg._{primary}}}'
        f'{{fmt.bg._{surface}}} "\n'
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


def render_comfy(pill):
    """
    Update only the [Lumen] colour scheme in Comfy's color.ini.

    Existing Comfy schemes and all other theme files remain untouched.
    """

    color_ini = (
        Path.home()
        / ".config"
        / "spicetify"
        / "Themes"
        / "Comfy"
        / "color.ini"
    )

    if not color_ini.is_file():
        print(
            "wallcolors: Comfy color.ini missing, skipping Comfy recolour",
            file=sys.stderr,
        )
        return

    def comfy_hex(value):
        return value.lstrip("#").upper()

    lumen = {
        "text": pill["bright"],
        "subtext": pill["subtle"],
        "main": pill["surface"],
        "main-elevated": pill["surface_container_high"],
        "main-transition": pill["surface_container_low"],
        "highlight": pill["surface_container"],
        "highlight-elevated": pill["surface_container_highest"],
        "sidebar": pill["surface"],
        "player": pill["surface_container_high"],
        "card": pill["surface_container"],
        "shadow": pill["surface"],
        "selected-row": pill["cream"],
        "button": pill["primary"],
        "button-active": pill["primary_container"],
        "button-disabled": pill["outline"],
        "tab-active": pill["surface_container_high"],
        "notification": pill["primary"],
        "notification-error": "#D25050",
        "misc": pill["dim"],
        "play-button": pill["primary"],
        "play-button-active": pill["primary"],
        "progress-fg": pill["primary"],
        "progress-bg": pill["outline_variant"],
        "heart": pill["primary"],
        "pagelink-active": pill["primary"],
        "radio-btn-active": pill["primary"],
    }

    lines = color_ini.read_text().splitlines()

    start = None
    end = len(lines)

    for i, line in enumerate(lines):
        if line.strip() == "[Lumen]":
            start = i
            break

    scheme = ["[Lumen]"]
    scheme.extend(
        f"{key:<18} = {comfy_hex(value)}"
        for key, value in lumen.items()
    )

    if start is None:
        lines.extend(["", *scheme])
    else:
        for i in range(start + 1, len(lines)):
            if lines[i].startswith("["):
                end = i
                break

        lines[start:end] = scheme

    color_ini.write_text("\n".join(lines) + "\n")



def flags():
    path = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local" / "state") / "lumen" / "flags.json"
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return {}


def vibrancy():
    """Palette strength from Settings (0 muted, 0.5 natural, 1 vivid)."""
    try:
        return clamp(float(flags().get("paletteVibrancy", 0.5)))
    except (TypeError, ValueError):
        return 0.5


GLASS_ALPHA = re.compile(r"@define-color\s+(\w+)\s+rgba\([^)]*,\s*([\d.]+)\s*\)")


def render_gtk(pill, on):
    """
    GTK apps follow the pill palette (Settings > Appearance > App theme).
    Writes lumen-palette.css next to each glass.css, which gtk.css imports
    after it. Every colour glass.css makes translucent keeps that same alpha,
    so the frosted glass stays and only its tint changes. Off empties the file.
    """
    for gtk in ("gtk-3.0", "gtk-4.0"):
        d = Path.home() / ".config" / gtk
        if not d.is_dir():
            continue
        out = d / "lumen-palette.css"
        if not on:
            out.write_text("")
            continue
        try:
            alphas = dict(GLASS_ALPHA.findall((d / "glass.css").read_text()))
        except OSError:
            alphas = {}
        bg = {
            "window_bg_color": pill["surface_container_low"], "view_bg_color": pill["surface"],
            "headerbar_bg_color": pill["surface_container"], "headerbar_backdrop_color": pill["surface_container_low"],
            "sidebar_bg_color": pill["surface_container"], "sidebar_backdrop_color": pill["surface_container_low"],
            "secondary_sidebar_bg_color": pill["surface_container_low"],
            "secondary_sidebar_backdrop_color": pill["surface_container_low"],
            "popover_bg_color": pill["surface_container_high"], "dialog_bg_color": pill["surface_container_high"],
        }
        lines = ["/* Generated by wallcolors.py from the pill palette. Do not edit. */"]
        for name, color in bg.items():
            a = alphas.get(name)
            lines.append(f"@define-color {name} " + (f"alpha({color}, {a})" if a else color) + ";")
        accent_fg = max(pill["surface"], pill["bright"], key=lambda c: contrast(c, pill["primary"]))
        lines += [f"@define-color accent_bg_color {pill['primary']};",
                  f"@define-color accent_fg_color {accent_fg};",
                  f"@define-color accent_color {pill['primary']};"]
        for part in ("window", "view", "headerbar", "sidebar", "secondary_sidebar", "card", "dialog", "popover"):
            lines.append(f"@define-color {part}_fg_color {pill['cream']};")
        if gtk == "gtk-4.0":
            lines.append(":root { --accent-bg-color: @accent_bg_color; --accent-fg-color: @accent_fg_color; "
                         "--accent-color: @accent_color; }")
        out.write_text("\n".join(lines) + "\n")


def main():
    if len(sys.argv) < 2:
        return 1

    if sys.argv[1] == "--apps":
        try:
            pill = json.loads((CACHE / "colors.json").read_text())
        except (OSError, ValueError):
            return 1
        render_gtk(pill, sys.argv[2:3] != ["off"])
        return 0

    if sys.argv[1] == "--hue":
        light = (sys.argv[3] if len(sys.argv) > 3 else "dark") == "light"
        sat = clamp(float(sys.argv[4]) if len(sys.argv) > 4 else 0.5)
        feat = manual_features(float(sys.argv[2]), light, sat)
        pill = palette(feat, light, sat)
    else:
        wallpaper = sys.argv[1]
        if not Path(wallpaper).is_file():
            return 0
        feat = analyze(wallpaper) or NEUTRAL
        light = feat["mean_l"] >= 0.40
        pill = palette(feat, light, vibrancy())

    # The renderers tint in HSL from the wallpaper's base family (or accent).
    fam = feat.get("base") or feat.get("accent")
    chromatic = fam is not None
    hue = colorsys.rgb_to_hls(*rgb(lch(0.6, 0.1, fam[0])))[0] if chromatic else 0.0

    CACHE.mkdir(
        parents=True,
        exist_ok=True,
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

    render_hyprlock(
        pill,
        light,
    )

    render_fish(
        pill,
        hue,
        light,
    )

    render_kitty(pill)

    render_starship(pill)

    render_comfy(pill)

    render_gtk(pill, bool(flags().get("appTheme", False)))

    return 0


if __name__ == "__main__":
    sys.exit(main())