hl.env("XCURSOR_THEME", "Bibata-Original-Classic-Right")
hl.env("XCURSOR_SIZE", "24")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
hl.env("EDITOR", "/usr/bin/nvim")
hl.env("HYPRSHOT_DIR", os.getenv("HOME") .. "/Pictures/Screenshots")

-- No NVIDIA GPU: load only the Intel/AMD (Mesa) graphics driver, saving ~100 MB in every GPU-drawn app.
-- Skipped automatically on machines with an NVIDIA GPU (PCI vendor 0x10de), so they keep working.
-- If the check can't run, assume NVIDIA and leave things as they were.
local ok, has_nvidia = pcall(function()
	local nv = io.popen("grep -qs 0x10de /sys/bus/pci/devices/*/vendor && echo y")
	local found = nv:read("*l") == "y"
	nv:close()
	return found
end)
if ok and not has_nvidia then
	hl.env("__EGL_VENDOR_LIBRARY_FILENAMES", "/usr/share/glvnd/egl_vendor.d/50_mesa.json")
end
