#!/usr/bin/env zsh
# Apply Eza/Exa aliases after the runtime defaults.
#TODO Add to dotfiles-next
if (( $+commands[eza] )); then
  unalias ls 2>/dev/null

  _zqs_eza_ls() {
    local arg char chars
    local -a eza_args
    local -i reverse_sort=0 time_sort=0

    for arg in "$@"; do
      if [[ $arg == -[[:alnum:]]* && $arg != --* ]]; then
        chars=${arg#-}

        for char in ${(s::)chars}; do
          case $char in
            l) eza_args+=(--long) ;;
            a) eza_args+=(--all) ;;
            A) eza_args+=(--almost-all) ;;
            r) reverse_sort=1 ;;
            t) time_sort=1 ;;
            *) eza_args+=("-$char") ;;
          esac
        done
      else
        eza_args+=("$arg")
      fi
    done

    (( time_sort )) && eza_args+=(--sort modified)
    (( reverse_sort )) && eza_args+=(--reverse)

    command eza -A --icons --git --group \
      --time-style=long-iso \
      --group-directories-first \
      --color-scale=all "${eza_args[@]}"
  }

  alias ls=_zqs_eza_ls
  alias lls='eza -A --icons --git --group --time-style=long-iso --group-directories-first --color-scale -bghHliS@Z --time-style=long-iso'
  alias ll='eza -A --icons --git --group --time-style=long-iso --group-directories-first --color-scale -las modified'
elif (( $+commands[exa] )); then
  alias ls='exa -A --icons --git --group --time-style=long-iso --group-directories-first --color-scale'
  alias lls='exa -A --icons --git --group --time-style=long-iso --group-directories-first --color-scale -bghHliS@Z --time-style=long-iso'
  alias ll='exa -A --icons --git --group --time-style=long-iso --group-directories-first --color-scale -las modified'
fi

