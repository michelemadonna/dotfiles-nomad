# >>> lig pre >>>
if [[ -x "$HOME/.local/bin/lig" ]]; then
  path=("$HOME/.local/bin" $path)
fi
if [[ -o interactive && ! -v ZSH_EXECUTION_STRING && -z ${LIG_DISABLE-} &&
      ${LIG_TTY-} != "$TTY" && -t 0 && -t 1 &&
      "$TERM" != dumb && -z ${INSIDE_EMACS-} ]] && (( $+commands[lig] )); then
  source "$DOTFILES_DIR/zsh/helpers/lig-init.zsh"
  _dotsh_lig_source_init pre
fi
#<<< lig pre <<<
# Interactive-shell defaults and optional startup profiling.
[[ ! -o interactive ]] || umask o-w
if [[ -f ${HOME}/.dotsh-zprof-enabled ]]; then
  zmodload zsh/zprof
fi

#0 Carica zstat una sola volta (builtin in C, costo ~0 ms)
zmodload -F zsh/stat b:zstat 2>/dev/null

# Compila un file .zsh in .zwc solo se il .zwc manca o è più vecchio del sorgente
function _zcompile_if_needed() {
  local src="$1"
  [[ -r "$src" ]] || return 1
  local zwc="${src}.zwc"
  if [[ ! -s $zwc || $src -nt $zwc ]]; then
    { zcompile -R "$zwc" "$src" 2>/dev/null } &!
  fi
}

# Auto-compila .zshenv e .zshrc in background se modificati
_zcompile_if_needed "${ZDOTDIR:-$HOME}/.zshenv"
_zcompile_if_needed "${ZDOTDIR:-$HOME}/.zshrc"
_zcompile_if_needed  "$DOTFILES_DIR/zsh/helpers/lig-init.zsh"
# Compile every custom plugin when its source changes.
for _custom_plugin in "${DOTFILES_DIR}/zsh/dotsh.custom.plugins"/*.zsh(N); do
  _zcompile_if_needed "$_custom_plugin"
done
unset _custom_plugin

# 1. FPATH BASE (Prima di Antidote affinché compinit trovi le completion del package manager)
typeset -gU fpath FPATH

local -a _fn_candidates=()
if [[ $OSTYPE == darwin* ]]; then
  if [[ $CPUTYPE == x86_64 && $DOTFILES_INTEL_PACKAGE_MANAGER != homebrew ]]; then
    _fn_candidates=(/opt/local/share/zsh/site-functions)
  else
    _fn_candidates=(/opt/homebrew/share/zsh/site-functions /usr/local/share/zsh/site-functions)
  fi
elif [[ $OSTYPE == linux* ]]; then
  _fn_candidates=(
    /home/linuxbrew/.linuxbrew/share/zsh/site-functions
    /usr/local/share/zsh/site-functions
    /usr/share/zsh/site-functions
    /usr/share/zsh/vendor-completions
  )
fi

for _fn_dir in $_fn_candidates; do
  [[ -d "$_fn_dir" ]] && fpath=("$_fn_dir" $fpath)
done
unset _fn_candidates _fn_dir

# 3. CACHE STATICA CON AUTO-INVALIDAZIONE VIA ZSTAT (MTIME)
local _init_cache="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/init-tools.zsh"
local _init_source="${ZDOTDIR:-$HOME}/.zshrc"
local _env_source="${ZDOTDIR:-$HOME}/.zshenv"
local _package_manager_mode=homebrew
if [[ $OSTYPE == darwin* && $CPUTYPE == x86_64 && \
      ${DOTFILES_INTEL_PACKAGE_MANAGER:-homebrew} != homebrew ]]; then
  _package_manager_mode=macports
fi
local _expected_cache_header="# dotsh-init-tools-v3:${_package_manager_mode}"
local _need_rebuild=0
local _cache_header
local -A _cache_stat _bin_stat

if ! zstat -H _cache_stat "$_init_cache" 2>/dev/null || \
   [[ "$_init_source" -nt "$_init_cache" || "$_env_source" -nt "$_init_cache" ]]; then
  _need_rebuild=1
else
  if ! IFS= read -r _cache_header < "$_init_cache" || \
     [[ $_cache_header != $_expected_cache_header ]]; then
    _need_rebuild=1
  fi
  if [[ $_package_manager_mode == homebrew ]]; then
    for _bin in "${commands[brew]}"; do
      if [[ -n "$_bin" ]] && zstat -H _bin_stat "$_bin" 2>/dev/null; then
        (( _bin_stat[mtime] > _cache_stat[mtime] )) && _need_rebuild=1 && break
      fi
    done
  fi
fi

if (( _need_rebuild )); then
  mkdir -p "${_init_cache:h}"
  {
    print -r -- "$_expected_cache_header"
    if [[ $_package_manager_mode == homebrew ]] && (( $+commands[brew] )); then
      brew shellenv
    fi
  } >| "$_init_cache"
  zcompile -R "${_init_cache}.zwc" "$_init_cache" 2>/dev/null
fi

source "$_init_cache"
unset _init_cache _init_source _env_source _package_manager_mode _expected_cache_header
unset _need_rebuild _cache_header _cache_stat _bin_stat _bin
path=("$HOME/.local/bin" $path)

# Shared cache root for Mise, completions and other Zsh plugins.
typeset -g ZSH_CACHE_DIR="${ZSH_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/zsh}"

# Reuse Zephyr's completion dump and audit it only when the cache expires or
# the completion search path changes.
zstyle ':zephyr:plugin:completion' use-cache yes

# 4. ANTIDOTE (Auto-install + Bundle statico)
for _antidote_dir in \
  /opt/homebrew/opt/antidote/share/antidote \
  /usr/local/opt/antidote/share/antidote \
  /opt/local/share/antidote \
  "${ZDOTDIR:-$HOME}/.antidote"; do
  if [[ -d "$_antidote_dir" ]]; then
    ANTIDOTE_HOME="$_antidote_dir"
    break
  fi
done
unset _antidote_dir

: "${ANTIDOTE_HOME:=${ZDOTDIR:-$HOME}/.antidote}"
[[ -d "$ANTIDOTE_HOME" ]] || git clone --depth=1 https://github.com/mattmc3/antidote.git "$ANTIDOTE_HOME" 2>/dev/null
source "${ANTIDOTE_HOME}/antidote.zsh"
# Use a new static bundle so existing generated files cannot retain the old
# defer options. None of the deferred plugins need to rerun precmd on load.
zstyle ':antidote:bundle:*' defer-options '-m'
zstyle ':antidote:static' file "$ZSH_CACHE_DIR/antidote-bundle-no-precmd.zsh"
antidote load

# 5. OH MY POSH
if (( $+commands[oh-my-posh] )); then
  if [[ -f "$DOTSH_OH_MY_POSH_CONFIG" ]]; then
    if (( $+functions[dotsh-init-oh-my-posh] )); then
      dotsh-init-oh-my-posh
    else
      eval "$(oh-my-posh init zsh --config "$DOTSH_OH_MY_POSH_CONFIG")"
    fi
  else
    eval "$(oh-my-posh init zsh)"
  fi
else
  PROMPT='%F{cyan}%n@%m%f %F{blue}%~%f %# '
fi

# 6. KEYBINDING FRECCE & UPDATE ALL-IN-ONE
zsh-defer -m bindkey "${terminfo[kcuu1]}" history-substring-search-up
zsh-defer -m bindkey "${terminfo[kcud1]}" history-substring-search-down

# Add flags to existing aliases.
#alias ls="${aliases[ls]:-ls} -A"
ZSH_AUTOSUGGEST_CLEAR_WIDGETS+=(bracketed-paste)
(( $+commands[python3] )) && alias python='command python3'
# GPG / PINENTRY
[[ -t 0 && -n $TTY ]] && export GPG_TTY=$TTY
## Long running processes should return time after they complete. Specified
## in seconds.
REPORTTIME=${REPORTTIME:-2}

TIMEFMT="%U user %S system %P cpu %*Es total"

print -n $'\e[9999;1H'

if [[ -f ${HOME}/.dotsh-zprof-enabled ]]; then
  zprof
fi

function zsh-update() {
  antidote update

  local _cache_base="${XDG_CACHE_HOME:-$HOME/.cache}"
  local _zsh_cache_dir="$_cache_base/zsh"
  local _sc_dir="${ZSH_SMARTCACHE_DIR:-$_cache_base/zsh-smartcache}"
  local _omp_cache_dir="$_cache_base/oh-my-posh"
  local _zdotdir="${ZDOTDIR:-$HOME}"
  local _dotfiles_zsh_dir="${DOTFILES_DIR:-$HOME/.dotfiles}/zsh"

  # 1. Rimuove le cache di startup e Mise. Zephyr e Oh My Posh verificano
  # autonomamente se le rispettive cache sono obsolete.
  rm -f \
    "$_zsh_cache_dir"/init-tools.zsh*(N) \
    "$_zsh_cache_dir"/mise-activate-lazy.zsh*(N) \
    "$_zsh_cache_dir"/lig-init-{pre,post}.zsh*(N)
  [[ -d "$_sc_dir" ]] && rm -rf "${_sc_dir:?}"/*(N)

  # 2. Rimuove le vecchie cache per-sessione di Oh My Posh.
  [[ -d "$_omp_cache_dir" ]] && rm -f \
    "$_omp_cache_dir"/zsh.*.omp.cache(N) \
    "$_omp_cache_dir"/.cache-*.tmp(N)

  # 3. Rimuove il bundle statico Antidote per forzare la rigenerazione
  rm -f "$_zdotdir/.zsh_plugins.zsh"(N) \
    "${ZSH_CACHE_DIR:-$_zsh_cache_dir}"/antidote-bundle-no-precmd.zsh*(N)

  # Remove every compiled Zsh file under the active dotfiles and ZDOTDIR trees.
  rm -f \
    "$_zdotdir"/**/*.zwc(N.) \
    "$_zdotdir"/**/.*.zwc(N.) \
    "$_dotfiles_zsh_dir"/**/*.zwc(N.) \
    "$_dotfiles_zsh_dir"/**/.*.zwc(N.)

  exec zsh -l
}
# >>> lig post >>>
if [[ -o interactive && ! -v ZSH_EXECUTION_STRING && -z ${LIG_DISABLE-} &&
      -n ${LIG_TTY-} && "$LIG_TTY" == "$TTY" ]] && (( $+commands[lig] )); then
  source "$DOTFILES_DIR/zsh/helpers/lig-init.zsh"
  # Antidote queues autosuggestions and highlighting before Lig's ZLE hooks.
  zsh-defer -m -p _dotsh_lig_finish_init
fi
# <<< lig post <<<

# Autosuggestions otherwise waits for the next real precmd to bind widgets.
# Its dependencies and Lig's widget hooks have run when this task executes.
if (( $+functions[zsh-defer] )); then
  zsh-defer -m -p -c '(( ! $+functions[_zsh_autosuggest_start] )) || _zsh_autosuggest_start'
fi
