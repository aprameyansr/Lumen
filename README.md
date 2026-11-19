# Lumen

**A Hyprland desktop on Arch Linux, built around a single morphing "pill" written in Quickshell.**

![Lumen desktop](screenshots/desktop.png)

The whole desktop lives in one pill at the top of the screen. At rest it's a
clock; hover it for an icon row; click an icon and the pill morphs into that
page. Everything recolours itself from your wallpaper.

| At rest | On hover |
|---|---|
| ![Resting pill](screenshots/pill-rest.png) | ![Hover row](screenshots/pill-hover.png) |

A personal fork of [Ricelin](https://github.com/Gakuseei/Ricelin), with my own
pages, fixes and styling on top.

## Features

- **Pages:** launcher, clipboard, emoji, mixer, sound (EQ, AutoEQ, per-app volume), media, calendar with weather, clock (stopwatch, timer, world clock), keep awake, recorder, system monitor, Wi-Fi, Bluetooth, battery, power, wallpaper picker, settings
- **Colours from your wallpaper** for the pill, Hyprland, lock screen, kitty, fish, starship, Spotify and (optionally) GTK apps
- **Frosted glass** GTK and Zen Browser styling
- **Keyboard first:** every page works with the arrow keys, Enter and Esc

**Stack:** Hyprland (Lua) · Quickshell · kitty + fish + starship · PipeWire · awww + mpvpaper · hyprlock + hypridle

## Installation

You'll need Arch Linux with a `sudo` user and an AUR helper (paru or yay).
Keep **bash** as your login shell; kitty runs fish for you.

**1. Get the files**

```sh
git clone https://github.com/aprameyansr/Lumen.git ~/lumen-dotfiles
cd ~/lumen-dotfiles
```

**2. Back up** anything in `~/.config` you want to keep.

**3. Install the packages** from [`packages.txt`](packages.txt) (remove any apps
you don't want first):

```sh
paru -S --needed $(grep -vE '^\s*(#|$)' packages.txt | awk '{print $1}')
```

**4. Copy the configs**

```sh
cp -a .config/. ~/.config/
mkdir -p ~/.local/bin && cp -a .local/bin/. ~/.local/bin/
chmod +x ~/.local/bin/* ~/.config/hypr/scripts/*.sh
xdg-user-dirs-update
```

**5. Enable the services**

```sh
sudo systemctl enable --now NetworkManager bluetooth
systemctl --user enable --now pipewire pipewire-pulse wireplumber
systemctl --user enable hypridle hyprsunset hyprpolkitagent
```

**6. Boot straight into Hyprland** (no display manager). Auto-login on tty1:

```sh
sudo systemctl edit getty@tty1.service
```

```ini
[Service]
ExecStart=
ExecStart=-/sbin/agetty --skip-login --nonewline --noissue --autologin yourname --noreset --noclear - ${TERM}
```

Then start Hyprland on that login by adding this to the end of `/etc/bash.bashrc`:

```sh
#Start Hyprland automatically on TTY1
if [[ "$(tty)" == "/dev/tty1" ]]; then
	exec start-hyprland >/dev/null 2>&1
fi
```

The lock screen still asks for your password on every boot.

**7. Monitor:** edit `~/.config/hypr/modules/monitors.lua` to match your screen
(`hyprctl monitors` lists them).

**8. Cursor:** download a cursor theme you like (e.g.
[Bibata](https://github.com/ful1e5/Bibata_Cursor/releases)), extract it into
`~/.local/share/icons`, and pick it in **Settings → Input → Cursor**. Set the
same name as `gtk-cursor-theme-name` in `~/.config/gtk-3.0/settings.ini` and
`~/.config/gtk-4.0/settings.ini`.

**9. Wallpapers:** none are included. Download some and put them in
`~/Pictures/Wallpapers` (videos work too).

**10. Reboot.** Log in at the lock screen, press **Super + C** and pick a
wallpaper.

## Optional

**GTK glass**

```sh
gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3-dark
gsettings set org.gnome.desktop.interface color-scheme prefer-dark
```

Turn on **Settings → Appearance → App theme** to tint GTK apps from your wallpaper.

**Zen Browser:** copy the styling into your profile folder (see `about:profiles`):

```sh
cp ".config/zen/<profile>/user.js" ~/.config/zen/<your-profile>/
mkdir -p ~/.config/zen/<your-profile>/chrome && cp ".config/zen/<profile>/chrome/"* ~/.config/zen/<your-profile>/chrome/
```

Glass tooltips (needs root, kept across Zen updates by a pacman hook):

```sh
sudo install -Dm644 etc/zen-autoconfig/autoconfig.js etc/zen-autoconfig/mozilla.cfg -t /etc/zen-autoconfig/
sudo install -Dm644 etc/pacman.d/hooks/zen-autoconfig.hook /etc/pacman.d/hooks/zen-autoconfig.hook
sudo install -Dm644 /etc/zen-autoconfig/autoconfig.js /opt/zen-browser-bin/defaults/pref/autoconfig.js
sudo install -Dm644 /etc/zen-autoconfig/mozilla.cfg /opt/zen-browser-bin/mozilla.cfg
```

**Spotify:** install `spicetify-cli`, open Spotify once, then:

```sh
sudo chmod a+wr /opt/spotify /opt/spotify/Apps -R
spicetify backup apply
```

Set `prefs_path` in `~/.config/spicetify/config-xpui.ini` to your own home folder first.

**Weather:** click the town name in the calendar to set your location.

## Keybinds

| Keys | Action | Keys | Action |
|---|---|---|---|
| `Super + Space` | Launcher | `Super + Q` | Close window |
| `Super + V` | Clipboard | `Super + F` | Toggle floating |
| `Super + .` | Emoji | `Super + D` | Maximize |
| `Super + C` | Wallpaper picker | `Super + Shift + D` | Fullscreen |
| `Super + B` | Random wallpaper | `Super + J` | Toggle split |
| `Super + U` | Mixer | `Alt + Tab` | Cycle windows |
| `Super + A` | Network | `Super + 1` … `0` | Workspace 1 … 10 |
| `Super + I` | Settings | `Super + Ctrl + 1` … `0` | Send window to workspace |
| `Super + R` | Screen recorder | `Super + Left / Right` | Previous / next workspace |
| `Super + X` | Power menu | `Super + P` / `Super + S` | Private / stash workspace |
| `Super + H` | Do Not Disturb | `Super + L` | Lock |
| `Super + Return` | Terminal | `Super + W` | Browser |
| `Super + E` | Files | `Super + N` | Obsidian |
| `Super + M` | Spotify | `Ctrl + Shift + Esc` | Task manager |
| `Print` | Screenshot | `Super + Shift + C` | Colour picker |

Change them in `~/.config/hypr/modules/binds.lua` or **Settings → Keybinds**.

## The `lumen` command

| Command         | Does                                                |
| --------------- | --------------------------------------------------- |
| `lumen status`  | Is the pill running                                 |
| `lumen restart` | Restart the pill                                    |
| `lumen log`     | Follow the pill's log                               |
| `lumen sync`    | Copy your live configs back into `~/lumen-dotfiles` |

To update: `git pull` in `~/lumen-dotfiles`, copy the configs again (step 4) and
`lumen restart`.

## Troubleshooting

- **Boots to a TTY:** check the getty override and the `/etc/bash.bashrc` block, and that your login shell is bash.
- **No pill:** `lumen log` shows the error.
- **No sound:** install `sof-firmware` (Intel laptops) and reboot.
- **Kanji show as boxes:** install `ttf-zen-kakugothic-new` and run `fc-cache -f`.
- **Chinese/Korean text shows as boxes:** install `noto-fonts-cjk`.
- **GUI apps never ask for a password:** `systemctl --user enable --now hyprpolkitagent`.

## Credits

Built on [Ricelin](https://github.com/Gakuseei/Ricelin) by Gakuseei. Licensed under [LICENSE](LICENSE).
