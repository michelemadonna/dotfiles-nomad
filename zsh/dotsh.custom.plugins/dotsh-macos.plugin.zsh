#!/usr/bin/env zsh

# The Oh My Zsh macOS plugin defines macOS-specific commands and assumes the
# framework's open_command helper. Antidote loads individual plugins without
# the full Oh My Zsh framework, so provide that small helper when absent.
[[ $OSTYPE == darwin* ]] || return 0

if (( ! $+functions[open_command] )); then
  open_command() {
    command open "$@" &>/dev/null
  }
fi

local _omz_macos_plugin="${ANTIDOTE_HOME:-${ZDOTDIR:-$HOME}/.antidote}/github.com/ohmyzsh/ohmyzsh/plugins/macos/macos.plugin.zsh"
[[ -r $_omz_macos_plugin ]] || return 0
source "$_omz_macos_plugin"
unset _omz_macos_plugin
