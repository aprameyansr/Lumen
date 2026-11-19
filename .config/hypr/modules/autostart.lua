hl.on("hyprland.start", function()
	hl.exec_cmd("hyprlock")
	hl.exec_cmd(os.getenv("HOME") .. "/.config/hypr/scripts/cliphist-watch.sh")
	hl.exec_cmd(os.getenv("HOME") .. "/.config/hypr/scripts/wallpaper.sh init")
	hl.exec_cmd("systemctl --user start hyprland-session.target")
	hl.exec_cmd(os.getenv("HOME") .. "/.config/hypr/scripts/watchdog.sh")
	-- warm the page cache so a user's first fastfetch run doesn't stall on cold pacman db reads
	hl.exec_cmd("fastfetch")
end)
