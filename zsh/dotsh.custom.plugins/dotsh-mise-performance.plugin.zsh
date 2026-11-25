#!/usr/bin/env zsh
# Mise startup and completion optimizations loaded by dotsh-mise.plugin.zsh.

# Cache mise's static activation script. The sourced script still installs the
# normal precmd/chpwd hook, so hook-env keeps running when the environment may
# have changed.
local mise_command=$_ZQS_MISE_COMMAND
local mise_binary=${commands[$mise_command]}
local mise_cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
local mise_activate_cache="$mise_cache_dir/${mise_command}-activate-lazy.zsh"
local mise_activate_tmp="$mise_activate_cache.${$}.tmp"
local mise_activate_raw_tmp="$mise_activate_cache.${$}.raw"
local mise_initial_hook_deferred=0
local -i mise_context_active=0
local -a mise_path_before_activation=($path)
local mise_path_before_rehash=$PATH

_zqs_mise_tool_versions_active() {
  emulate -L zsh
  local file=$1 line
  local -a fields

  [[ -r $file ]] || return 1
  while IFS= read -r line; do
    line=${line%%\#*}
    fields=(${=line})
    (( $#fields == 0 )) && continue
    (( $#fields == 2 && $fields[2] == system )) || return 0
  done < "$file"
  return 1
}

_zqs_mise_config_needs_activation() {
  emulate -L zsh
  setopt extended_glob
  local file=$1 line value
  local in_tools=0 saw_tool=0

  [[ -r $file ]] || return 1
  while IFS= read -r line; do
    line=${line%%"#"*}
    line=${${line##[[:space:]]#}%%[[:space:]]#}
    [[ -n $line ]] || continue

    if [[ $line == '[tools]' ]]; then
      in_tools=1
      continue
    fi
    [[ $line != \[*\] ]] || return 0
    (( in_tools )) || return 0
    [[ $line == *'='* ]] || return 0

    value=${line#*=}
    value=${${value##[[:space:]]#}%%[[:space:]]#}
    (( saw_tool = 1 ))
    [[ $value == '"system"' || $value == "'system'" || $value == system ]] || return 0
  done < "$file"
  (( saw_tool )) && return 1
  return 1
}

_zqs_mise_context_needs_activation() {
  emulate -L zsh
  local context_dir=$PWD file
  local global_config=${MISE_GLOBAL_CONFIG_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/mise/config.toml}
  local -a local_files=(
    .mise.toml
    mise.toml
    mise.local.toml
    .node-version
    .nvmrc
    .ruby-version
    .python-version
    .java-version
    .go-version
    .terraform-version
  )

  while [[ -n $context_dir ]]; do
    for file in ${local_files[@]}; do
      [[ -f $context_dir/$file ]] && return 0
    done
    if [[ -f $context_dir/.tool-versions ]] &&
       _zqs_mise_tool_versions_active "$context_dir/.tool-versions"; then
      return 0
    fi
    [[ $context_dir == / ]] && break
    context_dir=${context_dir:h}
  done

  [[ -n ${MISE_CONFIG_FILE:-} || -n ${MISE_ENV:-} ||
     -n ${MISE_DEFAULT_CONFIG_FILENAME:-} ||
     -n ${MISE_OVERRIDE_CONFIG_FILENAMES:-} ]] && return 0
  _zqs_mise_config_needs_activation "$global_config" && return 0
  _zqs_mise_tool_versions_active "$HOME/.tool-versions"
}

if [[ ! -s $mise_activate_cache || $mise_binary -nt $mise_activate_cache ]]; then
  [[ -d $mise_cache_dir ]] || command mkdir -p "$mise_cache_dir"
  if command "$mise_binary" --quiet activate zsh >| "$mise_activate_raw_tmp"; then
    while IFS= read -r line; do
      # Keep the hook function and its precmd/chpwd registration, but defer
      # the initial hook-env call until the first prompt.
      [[ $line == _mise_hook ]] && continue
      print -r -- "$line"
    done < "$mise_activate_raw_tmp" >| "$mise_activate_tmp"
    command mv -f "$mise_activate_tmp" "$mise_activate_cache"
    command rm -f "$mise_activate_raw_tmp"
  else
    command rm -f "$mise_activate_tmp"
    command rm -f "$mise_activate_raw_tmp"
  fi
fi

if [[ -s $mise_activate_cache ]]; then
  source "$mise_activate_cache"
  mise_initial_hook_deferred=1
  if _zqs_mise_context_needs_activation; then
    mise_context_active=1
  else
    mise_initial_hook_deferred=0
  fi
else
  eval "$(command "$mise_binary" --quiet activate zsh)"
  _zqs_mise_context_needs_activation && mise_context_active=1
fi
typeset -gi _ZQS_MISE_CONTEXT_ACTIVE=$mise_context_active

# `mise activate` embeds the PATH from cache-generation time. Keep its shims
# first, but do not let a cache prepared by the installer discard paths added
# later by shell startup (notably ~/.local/bin and Homebrew on macOS).
path=(${path:|mise_path_before_activation} $mise_path_before_activation)
typeset -gU path PATH
[[ $PATH == $mise_path_before_rehash ]] || rehash
unset mise_path_before_rehash

typeset -ga precmd_functions chpwd_functions
if (( $+functions[_mise_hook_precmd] && $+functions[_mise_hook_chpwd] )); then
  # Current Mise already prevents chpwd from being followed by a duplicate
  # precmd refresh. Use its hooks directly instead of adding a second pair.
  precmd_functions=(${precmd_functions:#_zqs_mise_precmd_hook})
  chpwd_functions=(${chpwd_functions:#_zqs_mise_chpwd_hook})
  unfunction _zqs_mise_precmd_hook _zqs_mise_chpwd_hook 2>/dev/null

  # The cached activation omits Mise's initial hook-env call. Its generated
  # first-prompt fast path assumes that call already happened, so bypass that
  # fast path once and let the native hook initialize the environment.
  (( mise_initial_hook_deferred )) && typeset -gx __MISE_ZSH_PRECMD_RUN=1

  # Avoid starting Mise for every prompt when nothing relevant changed. Keep
  # chpwd immediate, refresh after every Mise command, detect PATH changes,
  # and retain a short periodic check for externally edited configs or env.
  zmodload zsh/datetime
  local mise_refresh_seconds=${DOTSH_MISE_REFRESH_SECONDS:-5}
  [[ $mise_refresh_seconds == <-> ]] || mise_refresh_seconds=5
  typeset -gi _ZQS_MISE_REFRESH_SECONDS=$mise_refresh_seconds
  typeset -gi _ZQS_MISE_REFRESH_REQUIRED=$mise_initial_hook_deferred
  typeset -gF _ZQS_MISE_LAST_REFRESH=$EPOCHREALTIME
  typeset -g _ZQS_MISE_LAST_PATH=$PATH

  _zqs_mise_precmd_hook() {
    emulate -L zsh
    local -F now=$EPOCHREALTIME

    if [[ ${__MISE_ZSH_CHPWD_RAN:-0} == 1 ]]; then
      # Let Mise consume its chpwd marker without invoking hook-env twice.
      _mise_hook_precmd || return
      if _zqs_mise_context_needs_activation; then
        typeset -gi _ZQS_MISE_CONTEXT_ACTIVE=1
      else
        typeset -gi _ZQS_MISE_CONTEXT_ACTIVE=0
      fi
    else
      if (( ! ${_ZQS_MISE_REFRESH_REQUIRED:-0} )) &&
         [[ $PATH == ${_ZQS_MISE_LAST_PATH:-} ]]; then
        if (( ${_ZQS_MISE_REFRESH_SECONDS:-5} > 0 )) &&
           (( now - ${_ZQS_MISE_LAST_REFRESH:-0} <
                ${_ZQS_MISE_REFRESH_SECONDS:-5} )); then
          return 0
        fi

        # Outside a Mise context, avoid spawning `mise hook-env` on the
        # periodic refresh. Recheck the lightweight config/path predicate so
        # a newly added config still activates on the next refresh interval.
        if ! _zqs_mise_context_needs_activation &&
           (( ! ${_ZQS_MISE_CONTEXT_ACTIVE:-0} )); then
          typeset -gF _ZQS_MISE_LAST_REFRESH=$now
          return 0
        fi
      fi

      _mise_hook_precmd || return
      if _zqs_mise_context_needs_activation; then
        typeset -gi _ZQS_MISE_CONTEXT_ACTIVE=1
      else
        typeset -gi _ZQS_MISE_CONTEXT_ACTIVE=0
      fi
    fi

    typeset -g _ZQS_MISE_LAST_PATH=$PATH
    typeset -gF _ZQS_MISE_LAST_REFRESH=$EPOCHREALTIME
    typeset -gi _ZQS_MISE_REFRESH_REQUIRED=0
  }

  precmd_functions=(${precmd_functions/_mise_hook_precmd/_zqs_mise_precmd_hook})
else
  # Compatibility fallback for older activation scripts that register the
  # same `_mise_hook` function for chpwd and precmd.
  _zqs_mise_chpwd_hook() {
    _mise_hook || return
    typeset -g _ZQS_MISE_CHPWD_PWD=$PWD
    typeset -gi _ZQS_MISE_SKIP_NEXT_PRECMD=1
  }

  _zqs_mise_precmd_hook() {
    if (( ${_ZQS_MISE_SKIP_NEXT_PRECMD:-0} )) &&
        [[ ${_ZQS_MISE_CHPWD_PWD:-} == $PWD ]]; then
      unset _ZQS_MISE_SKIP_NEXT_PRECMD _ZQS_MISE_CHPWD_PWD
      return 0
    fi

    unset _ZQS_MISE_SKIP_NEXT_PRECMD _ZQS_MISE_CHPWD_PWD
    _mise_hook
  }

  precmd_functions=(
    _zqs_mise_precmd_hook
    ${precmd_functions:#_mise_hook}
  )
  chpwd_functions=(
    _zqs_mise_chpwd_hook
    ${chpwd_functions:#_mise_hook}
  )
fi

unset mise_binary mise_cache_dir mise_activate_cache mise_activate_tmp mise_activate_raw_tmp
unset mise_initial_hook_deferred mise_refresh_seconds mise_path_before_activation
unset mise_command mise_context_active

_dotsh_mise_prepare_completion_cache() {
  local mise_command=$1 mise_completion_file=$2
  local mise_completion_dir=${mise_completion_file:h}
  local mise_completion_tmp="$mise_completion_file.${$}.tmp"
  local mise_completion_binary=${commands[$mise_command]}

  if [[ ! -s $mise_completion_file || $mise_completion_binary -nt $mise_completion_file ]]; then
    [[ -d $mise_completion_dir ]] || command mkdir -p "$mise_completion_dir"
    if command "$mise_completion_binary" --quiet completion zsh >| "$mise_completion_tmp"; then
      command mv -f "$mise_completion_tmp" "$mise_completion_file"
    else
      command rm -f "$mise_completion_tmp"
    fi
  fi
}

# Load the generated completion after Zephyr initializes compdef at the first
# prompt. Sourcing it during startup can delay the prompt.
_dotsh_mise_defer_completion() {
  if (( $+functions[zsh-defer] )); then
    zsh-defer -m -p _dotsh_mise_init_completion
  else
    _dotsh_mise_init_completion
  fi
}
