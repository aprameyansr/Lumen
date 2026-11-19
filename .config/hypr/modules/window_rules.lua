hl.window_rule({
    name           = "suppress-maximize",
    match          = { class = ".*" },
    suppress_event = "maximize",
})

hl.window_rule({
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },
    no_focus = true,
})

hl.window_rule({
    name  = "float-system-dialogs",
    match = { class = "(pavucontrol|nm-connection-editor|blueman-manager|org.kde.polkit-kde-authentication-agent-1|xdg-desktop-portal-gtk)" },
    float = true,
})

hl.window_rule({
    name  = "float-file-pickers",
    match = { title = "(Open File|Save File|Save As|Choose Files|Open Folder)" },
    float = true,
})

hl.window_rule({

    name  = "spotify-transparency",

    match = { class = "^spotify$" },

    opacity = 0.8,
    
    xray = false,

})

hl.window_rule({
    name         = "idle-inhibit-fullscreen",
    match        = { class = ".*" },
    idle_inhibit = "fullscreen",
})

-- Keep the pill from fading when the session lock hides and restores its layer,
-- so it never pops back in out of sync with the shot the lock morph collapses onto.
hl.layer_rule({
    name    = "pill-no-fade",
    match   = { namespace = "pill" },
    no_anim = true,
})

local ok, stashApps = pcall(require, "modules.stash-apps")
if ok and type(stashApps) == "table" then
    for _, cls in ipairs(stashApps) do
        hl.window_rule({
            name      = "stash-" .. cls,
            match     = { class = cls },
            workspace = "special:stash",
        })
    end
end
