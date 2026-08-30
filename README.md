
# Ricelin

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

The Quickshell interface also has its own manually tuned visual styling,
built around warm vermilion and muted cream tones.

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

This repository is based on [Ricelin](https://github.com/Gakuseei/Ricelin)
and contains my personal modifications and configuration changes.
