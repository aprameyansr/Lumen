local mod = "SUPER"

-- ============================================================================
-- Window Management
-- ============================================================================

hl.bind(mod .. " + Q", hl.dsp.window.close()) -- Close window
hl.bind(mod .. " + F", hl.dsp.window.float({ action = "toggle" })) -- Toggle float
hl.bind(mod .. " + D", hl.dsp.window.fullscreen({ mode = 1 })) -- Maximize
hl.bind(mod .. " + SHIFT + D", hl.dsp.window.fullscreen()) -- True fullscreen

hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true }) -- Move
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true }) -- Resize

hl.bind("SUPER + J", hl.dsp.layout("togglesplit")) -- Toggle split
hl.bind("ALT + Tab", hl.dsp.window.cycle_next()) -- Cycle windows


-- ============================================================================
-- Quickshell — Pill Surfaces
-- ============================================================================

hl.bind(mod .. " + Space", hl.dsp.exec_cmd('qs ipc call pill launcher ""')) -- Launcher
hl.bind(mod .. " + V", hl.dsp.exec_cmd('qs ipc call pill clipboard ""')) -- Clipboard
hl.bind(mod .. " + C", hl.dsp.exec_cmd('qs ipc call pill wallpaper ""')) -- Wallpaper
hl.bind(mod .. " + G", hl.dsp.exec_cmd('qs ipc call pill gameMode ""')) -- Game mode

hl.bind(mod .. " + X", hl.dsp.exec_cmd('qs ipc call pill power ""')) -- Power
hl.bind(mod .. " + A", hl.dsp.exec_cmd('qs ipc call pill link ""')) -- Network
hl.bind(mod .. " + U", hl.dsp.exec_cmd('qs ipc call pill mixer ""')) -- Audio mixer
hl.bind(mod .. " + I", hl.dsp.exec_cmd('qs ipc call pill settings ""')) -- Settings
hl.bind(mod .. " + R", hl.dsp.exec_cmd('qs ipc call pill screenrec ""')) -- Screen recorder


-- ============================================================================
-- Applications
-- ============================================================================

hl.bind(mod .. " + Return", hl.dsp.exec_cmd("kitty")) -- Terminal
hl.bind("f23", hl.dsp.exec_cmd("kitty")) -- Alternate terminal
hl.bind(mod .. " + W", hl.dsp.exec_cmd("firefox")) -- Browser
hl.bind(mod .. " + E", hl.dsp.exec_cmd("nautilus -w")) -- File manager
hl.bind("CTRL + SHIFT + escape", hl.dsp.exec_cmd("resources")) -- Task Manager
hl.bind(
	mod .. " + N",
	hl.dsp.exec_cmd("obsidian --enable-platform=WaylandWindowDecorations,EnableOzonePlatform --ozone-platform=wayland")
) -- Notes
hl.bind(
	mod .. " + M",
	hl.dsp.exec_cmd("spotify --ozone-platform=wayland --enable-features=UseOzonePlatform,WaylandWindowDecorations")
) -- Music


-- ============================================================================
-- Workspaces
-- ============================================================================

-- Switch workspace
hl.bind(mod .. " + 1", hl.dsp.focus({ workspace = 1 }))
hl.bind(mod .. " + 2", hl.dsp.focus({ workspace = 2 }))
hl.bind(mod .. " + 3", hl.dsp.focus({ workspace = 3 }))
hl.bind(mod .. " + 4", hl.dsp.focus({ workspace = 4 }))
hl.bind(mod .. " + 5", hl.dsp.focus({ workspace = 5 }))
hl.bind(mod .. " + 6", hl.dsp.focus({ workspace = 6 }))
hl.bind(mod .. " + 7", hl.dsp.focus({ workspace = 7 }))
hl.bind(mod .. " + 8", hl.dsp.focus({ workspace = 8 }))
hl.bind(mod .. " + 9", hl.dsp.focus({ workspace = 9 }))
hl.bind(mod .. " + 0", hl.dsp.focus({ workspace = 10 }))

-- Move window to workspace
hl.bind(mod .. " + CTRL + 1", hl.dsp.window.move({ workspace = 1, follow = false }))
hl.bind(mod .. " + CTRL + 2", hl.dsp.window.move({ workspace = 2, follow = false }))
hl.bind(mod .. " + CTRL + 3", hl.dsp.window.move({ workspace = 3, follow = false }))
hl.bind(mod .. " + CTRL + 4", hl.dsp.window.move({ workspace = 4, follow = false }))
hl.bind(mod .. " + CTRL + 5", hl.dsp.window.move({ workspace = 5, follow = false }))
hl.bind(mod .. " + CTRL + 6", hl.dsp.window.move({ workspace = 6, follow = false }))
hl.bind(mod .. " + CTRL + 7", hl.dsp.window.move({ workspace = 7, follow = false }))
hl.bind(mod .. " + CTRL + 8", hl.dsp.window.move({ workspace = 8, follow = false }))
hl.bind(mod .. " + CTRL + 9", hl.dsp.window.move({ workspace = 9, follow = false }))
hl.bind(mod .. " + CTRL + 0", hl.dsp.window.move({ workspace = 10, follow = false }))

-- Previous / next workspace
hl.bind(mod .. " + Left", hl.dsp.focus({ workspace = "r-1" }))
hl.bind(mod .. " + Right", hl.dsp.focus({ workspace = "r+1" }))
hl.bind(mod .. " + mouse_up", hl.dsp.focus({ workspace = "r-1" }))
hl.bind(mod .. " + mouse_down", hl.dsp.focus({ workspace = "r+1" }))

-- Special workspaces
hl.bind(mod .. " + P", hl.dsp.workspace.toggle_special("private"))
hl.bind(
	mod .. " + SHIFT + P",
	hl.dsp.exec_cmd(os.getenv("HOME") .. "/.config/hypr/scripts/special-toggle.sh private")
)

-- Stash workspace is currently disabled
-- hl.bind(mod .. " + S", hl.dsp.workspace.toggle_special("stash"))
-- hl.bind(mod .. " + SHIFT + S", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.config/hypr/scripts/special-toggle.sh stash"))


-- ============================================================================
-- Screenshots & Color Tools
-- ============================================================================

hl.bind(mod .. " + SHIFT + S", hl.dsp.exec_cmd("hyprshot -m region"))
hl.bind(mod .. " + SHIFT + C", hl.dsp.exec_cmd("hyprpicker -a"))


-- ============================================================================
-- Hardware Controls
-- ============================================================================

hl.bind(
	"XF86AudioRaiseVolume",
	hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"),
	{ locked = true, repeating = true }
)

hl.bind(
	"XF86AudioLowerVolume",
	hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),
	{ locked = true, repeating = true }
)

hl.bind(
	"XF86AudioMute",
	hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),
	{ locked = true }
)

hl.bind(
	"XF86MonBrightnessUp",
	hl.dsp.exec_cmd("brightnessctl set 5%+"),
	{ locked = true, repeating = true }
)

hl.bind(
	"XF86MonBrightnessDown",
	hl.dsp.exec_cmd("brightnessctl set 5%-"),
	{ locked = true, repeating = true }
)


-- ============================================================================
-- Media Controls
-- ============================================================================

hl.bind("XF86AudioPlay", hl.dsp.global("quickshell:mediaToggle"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.global("quickshell:mediaNext"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.global("quickshell:mediaPrev"), { locked = true })