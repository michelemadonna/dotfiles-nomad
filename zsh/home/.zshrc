# Interactive-shell defaults and optional startup profiling.
[[ ! -o interactive ]] || umask o-w
if [[ -f ${HOME}/.dotsh-zprof-enabled ]]; then
  zmodload zsh/zprof
fi
export DOTSH_MISE_REFRESH_SECONDS=${DOTSH_MISE_REFRESH_SECONDS:=5} #0 checks every prompt
export DOTSH_USE_MISE=${DOTSH_USE_MISE:=true} #true/false
export HISTFILE="$HOME/.local/state/zsh/history"
export HISTORY_IGNORE="(cd ..|l[s]#( *)#|pwd *|exit *|date *|* --help)"
export ZSH_COMPDUMP=${ZSH_COMPDUMP:="$XDG_CACHE_HOME/zsh/.zcompdump-${HOST}-${ZSH_VERSION}"}
export DOTSH_OH_MY_POSH_CONFIG="$DOTFILES_DIR/oh-my-posh/custom.omp.json"
if [[ -z ${INTELLIJ_ENVIRONMENT_READER:-} ]]; then
  export POWERLEVEL9K_INSTANT_PROMPT='quiet'
fi

#0 Carica zstat una sola volta (builtin in C, costo ~0 ms)
zmodload -F zsh/stat b:zstat 2>/dev/null

# Compila un file .zsh in .zwc solo se il .zwc manca o è più vecchio del sorgente
function _zcompile_if_needed() {
  local src="$1"
  [[ -r "$src" ]] || return 1
  local zwc="${src}.zwc"
  local -A src_stat zwc_stat

  zstat -H src_stat "$src" 2>/dev/null || return 1
  if ! zstat -H zwc_stat "$zwc" 2>/dev/null || (( src_stat[mtime] > zwc_stat[mtime] )); then
    zcompile -R "$zwc" "$src" 2>/dev/null
  fi
}

# Auto-compila .zshenv e .zshrc in background se modificati
_zcompile_if_needed "${ZDOTDIR:-$HOME}/.zshenv" &!
_zcompile_if_needed "${ZDOTDIR:-$HOME}/.zshrc" &!

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

# 2. SSH-AGENT UNIVERSALE (macOS Keychain, Linux Desktop Keyring/KWallet, Server SSH)
# Oh My Zsh's ssh-agent plugin is loaded standalone through Antidote, so define
# the host key that Oh My Zsh normally prepares in its full framework startup.
: "${SHORT_HOST:=${HOST%%.*}}"
zstyle :omz:plugins:ssh-agent honor-existing yes
zstyle :omz:plugins:ssh-agent lazy yes
zstyle :omz:plugins:ssh-agent quiet yes
if [[ -z "$SSH_CONNECTION" && -n "$DISPLAY$WAYLAND_DISPLAY" ]]; then
  for _s in "${XDG_RUNTIME_DIR}/keyring/ssh" "${XDG_RUNTIME_DIR}/gcr/ssh" "${XDG_RUNTIME_DIR}/ssh-agent.socket"; do
    [[ -S "$_s" ]] && export SSH_AUTH_SOCK="$_s" && break
  done; unset _s
  for _ask in ksshaskpass seahorse-ssh-askpass gnome-ssh-askpass; do
    (( $+commands[$_ask] )) && export SSH_ASKPASS="${commands[$_ask]}" SSH_ASKPASS_REQUIRE=prefer && break
  done; unset _ask
fi

# 2.1 Stampa le chiavi SSH in memoria
ssh-ids() {
  print '\nCurrent SSH Keys:'
  if ! ssh-add -l 2>/dev/null; then
    print -P "%F{yellow}Nessuna chiave SSH in memoria (caricamento lazy).%f"
  fi
}

# 2.2 Forza il caricamento immediato delle chiavi nel Portachiavi
ssh-load() {
  if [[ "$OSTYPE" == darwin* ]]; then
    ssh-add --apple-load-keychain 2>/dev/null || ssh-add --apple-use-keychain 2>/dev/null || ssh-add -A 2>/dev/null
  else
    ssh-add
  fi
  ssh-ids
}

# 2.3 Stampa automatica all'avvio (disattivabile con: zstyle ':zim:ssh-local' show-ids no)
if zstyle -T ':zim:ssh-local' show-ids; then
  ssh-ids
fi

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
zsh-defer bindkey "${terminfo[kcuu1]}" history-substring-search-up
zsh-defer bindkey "${terminfo[kcud1]}" history-substring-search-down

# Add flags to existing aliases.
#alias ls="${aliases[ls]:-ls} -A"
ZSH_AUTOSUGGEST_CLEAR_WIDGETS+=(bracketed-paste)
(( $+commands[python3] )) && alias python='command python3'
# GPG / PINENTRY
export GPG_TTY=$(tty)
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
    "$_zsh_cache_dir"/mise-activate-lazy.zsh*(N)
  [[ -d "$_sc_dir" ]] && rm -rf "${_sc_dir:?}"/*(N)

  # 2. Rimuove le vecchie cache per-sessione di Oh My Posh.
  [[ -d "$_omp_cache_dir" ]] && rm -f \
    "$_omp_cache_dir"/zsh.*.omp.cache(N) \
    "$_omp_cache_dir"/.cache-*.tmp(N)

  # 3. Rimuove il bundle statico Antidote per forzare la rigenerazione
  rm -f "$_zdotdir/.zsh_plugins.zsh"(N)

  # Remove every compiled Zsh file under the active dotfiles and ZDOTDIR trees.
  rm -f \
    "$_zdotdir"/**/*.zwc(N.) \
    "$_zdotdir"/**/.*.zwc(N.) \
    "$_dotfiles_zsh_dir"/**/*.zwc(N.) \
    "$_dotfiles_zsh_dir"/**/.*.zwc(N.)

  exec zsh -l
}
