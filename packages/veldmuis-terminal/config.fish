set -g fish_greeting

fish_add_path -g "$HOME/.local/bin"

function fish_prompt
    set -l path_parts (string split '/' -- $PWD)
    set -l directory $path_parts[-1]
    if test -z "$directory"
        set directory /
    end

    set_color '#f3d7a0'
    printf '%s ' "$directory"
    set_color '#f6b73c'
    printf '❯ '
    set_color normal
end

if status is-interactive; and type -q atuin
    atuin init fish --disable-up-arrow --disable-ai | source
end
