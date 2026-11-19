function lumen_reload_colors --on-signal SIGUSR1
    if test -f ~/.cache/lumen/fish-colors.fish
        source ~/.cache/lumen/fish-colors.fish
        commandline -f repaint
    end
end

if test -f ~/.cache/lumen/fish-colors.fish
    source ~/.cache/lumen/fish-colors.fish
end
