
# Lumen

**My personal Hyprland setup on Arch Linux, built around a custom Quickshell interface.**

This repository contains my personal Linux configuration files. I use
Hyprland as my window manager, Quickshell for my desktop shell, and fish as
my interactive shell.

The configuration has evolved over time as I have changed and refined my
setup.

## Stack

- **WM:** Hyprland, configured in Lua
- **Shell UI:** Quickshell
- **Terminal:** Kitty
- **Shell:** fish
- **Editor:** Neovim
- **Font:** JetBrains Mono Nerd Font
- **Theming:** matugen
- **System:** Arch Linux
- **Audio:** PipeWire / WirePlumber
- **Screenshot:** hyprshot
- **Color picker:** hyprpicker

## Quickshell

The desktop shell is built with Quickshell.

The main interface is a single pill-style shell containing various surfaces
for different parts of the desktop.

It includes:

- Application launcher
- Clipboard history
- Wallpaper selection
- Power menu
- Network controls
- Audio mixer
- Settings
- Screen recording
- Media controls
- Workspaces
- Battery and system information
- Bluetooth controls
- Game mode

The shell is designed around opening these surfaces on demand rather than
keeping separate applications or menus open on the desktop.

## Theming

I use `matugen` to generate colors from wallpapers.

The generated palette is used throughout the desktop, including the shell,
terminal and other parts of the configuration.

<<<<<<< HEAD
The Quickshell interface also has its own manually tuned visual styling,
built around warm vermilion and muted cream tones.
=======
`install.sh` is a thin bootstrap: it detects your distro (Arch, Debian, Fedora,
openSUSE or Gentoo), makes sure git and python3 are there, clones the rice into
`~/.local/share/ricelin`, then hands off to the guided Python installer. That part
walks you through a short wizard, picks the right package names for your distro,
pulls the deps and copies the configs into `~/.config`, backing up anything it
replaces. The monitor layout and GPU env are swapped for portable defaults so it
boots on any hardware; my own layout is kept next to it as `monitors.lua.example`.
Then start `Hyprland` from a TTY.

Skip the wizard with flags, passed straight through the pipe:

```sh
curl -fsSL https://raw.githubusercontent.com/Gakuseei/Ricelin/main/install.sh | bash -s -- --quickstart
```

```
--quickstart  core defaults, no questions
--full        also install the daily apps (dolphin, keepassxc, zathura, imv, rnote)
--sddm        also install the torii SDDM login theme
--no-deps     skip the package step, just deploy the configs
--dry-run     walk the whole flow and change nothing
```

Ricelin is a Hyprland shell. On Niri, Sway or anything else only rishot (the
screenshot tool) makes sense; grab it from [rishot](https://github.com/Gakuseei/rishot)'s own installer.
>>>>>>> upstream/main

## Keybinds

### Window Management

| Key | Action |
|---|---|
| `Super + Q` | Close window |
| `Super + F` | Toggle floating |
| `Super + D` | Maximize |
| `Super + Shift + D` | True fullscreen |
| `Super + J` | Toggle split |
| `Alt + Tab` | Cycle windows |
| `Super + Left` | Previous workspace |
| `Super + Right` | Next workspace |
| `Super + Mouse Left` | Move window |
| `Super + Mouse Right` | Resize window |

### Quickshell

| Key | Action |
|---|---|
| `Super + Space` | Application launcher |
| `Super + V` | Clipboard |
| `Super + C` | Wallpaper picker |
| `Super + G` | Game mode |
| `Super + X` | Power menu |
| `Super + A` | Network |
| `Super + U` | Audio mixer |
| `Super + I` | Settings |
| `Super + R` | Screen recorder |
| `Super + H` | Do Not Disturb Toggle |

### Applications

| Key | Action |
|---|---|
| `Super + Return` | Kitty terminal |
| `F23` | Kitty terminal |
| `Super + W` | Firefox |
| `Super + E` | Nautilus |
| `Super + N` | Obsidian |
| `Super + M` | Spotify |
| `Ctrl + Shift + Escape` | Resources |

### Workspaces

| Key | Action |
|---|---|
| `Super + 1` – `9` | Switch to workspace 1–9 |
| `Super + 0` | Switch to workspace 10 |
| `Super + Ctrl + 1` – `9` | Move window to workspace 1–9 |
| `Super + Ctrl + 0` | Move window to workspace 10 |
| `Super + Mouse Wheel Up` | Previous workspace |
| `Super + Mouse Wheel Down` | Next workspace |

## Repository Structure

```text
bin/            Personal command-line scripts
fastfetch/      Fastfetch configuration
fish/           Fish shell configuration
fontconfig/     Font configuration
hypr/           Hyprland configuration and scripts
kitty/          Kitty terminal configuration
matugen/        Matugen configuration
mimeapps.list   Default application associations
nvim/           Neovim configuration
nvim-qt/        Neovim-Qt configuration
quickshell/     Quickshell shell and surfaces
```

## Notes

These are my personal configurations, built around the way I use my system.

They are not intended to be a universal configuration or a one-command
installation. Some settings, paths, applications and hardware-specific
choices may need to be changed for another system.

Feel free to use anything here as a reference or starting point for your own
setup.

## Credits

This repository is based on the upstream [Ricelin] project(https://github.com/Gakuseei/Ricelin)
and contains my personal modifications and configuration changes.

## Frosted-glass styling (GTK + Zen)

Translucent backgrounds that Hyprland blurs behind. Blur itself comes from
`hypr/modules/decoration.lua` (`blur.popups = true` covers menus and popovers).

**GTK** (needs the `adw-gtk-theme` package, with `adw-gtk3-dark` selected):

```sh
cp gtk-3.0/gtk.css ~/.config/gtk-3.0/
rm -f ~/.config/gtk-4.0/gtk.css   # nwg-look makes this a symlink
cp gtk-4.0/gtk.css gtk-4.0/glass.css ~/.config/gtk-4.0/
```

GTK 4.24+ only gets blurred because `glass.css` sets `backdrop-filter` on
windows. Re-applying a theme in nwg-look replaces `~/.config/gtk-4.0/gtk.css`,
so copy it back afterwards.

**Zen Browser:** copy into the profile folder (find it in `about:profiles`),
then fully restart Zen:

```sh
cp zen/user.js <profile>/
mkdir -p <profile>/chrome && cp zen/chrome/*.css zen/chrome/*.svg <profile>/chrome/
```

**Zen glass tooltips (optional, needs root):** Zen's space/Library button
tooltips use Firefox's built-in tooltip, which userChrome.css can't reach.
`zen/autoconfig/mozilla.cfg` gives them a stylable tooltip. It's loaded via
Firefox autoconfig from the install folder, and a pacman hook puts it back
after every `zen-browser-bin` update:

```sh
sudo install -Dm644 zen/autoconfig/autoconfig.js zen/autoconfig/mozilla.cfg -t /etc/zen-autoconfig/
sudo install -Dm644 zen/autoconfig/zen-autoconfig.hook /etc/pacman.d/hooks/zen-autoconfig.hook
sudo install -Dm644 /etc/zen-autoconfig/autoconfig.js /opt/zen-browser-bin/defaults/pref/autoconfig.js
sudo install -Dm644 /etc/zen-autoconfig/mozilla.cfg /opt/zen-browser-bin/mozilla.cfg
```
