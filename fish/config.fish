if status is-interactive # Commands to run in interactive sessions can go here
    # No greeting
    set fish_greeting
    # Use starship
    starship init fish | source
    # Aliases
    alias ls 'eza --icons'
end
