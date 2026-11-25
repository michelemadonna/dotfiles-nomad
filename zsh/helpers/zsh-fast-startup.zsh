#0 Carica zstat una sola volta (builtin in C, costo ~0 ms)
zmodload -F zsh/stat b:zstat 2>/dev/null

# Compila un file .zsh in .zwc solo se il .zwc manca o è più vecchio del sorgente
function _zcompile_if_needed() {
  local src="$1"
  [[ -r "$src" ]] || return 1
  local zwc="${src}.zwc"
  if [[ ! -s $zwc || $src -nt $zwc ]]; then
	#print -u2 "Compiling $src -> $zwc"
    { zcompile -R "$zwc" "$src" 2>/dev/null } &!
  fi
}

# Auto-compila .zshenv e .zshrc in background se modificati
_zcompile_if_needed "${ZDOTDIR:-$HOME}/.zshenv"
_zcompile_if_needed "${ZDOTDIR:-$HOME}/.zshrc"
#_zcompile_if_needed  "$DOTFILES_DIR/zsh/helpers/lig-init.zsh"
_zcompile_if_needed  "$DOTFILES_DIR/zsh/helpers/zsh-fast-startup.zsh"
# Compile every custom plugin when its source changes.
for _custom_plugin in "${DOTFILES_DIR}/zsh/dotsh.custom.plugins"/*.zsh(N); do
  _zcompile_if_needed "$_custom_plugin"
done
unset _custom_plugin

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
  #print -r -- "source $_init_source" >> "$_init_cache"
  zcompile -R "${_init_cache}.zwc" "$_init_cache" 2>/dev/null
fi

source "$_init_cache"
unset _init_cache _init_source _env_source _package_manager_mode _expected_cache_header
unset _need_rebuild _cache_header _cache_stat _bin_stat _bin

function zsh-update() {

  local _cache_base="${XDG_CACHE_HOME:-$HOME/.cache}"
  local _zsh_cache_dir="$_cache_base/zsh"
  local _zsh_eval_cache_dir="$_cache_base/zsh/eval"
  local _sc_dir="${ZSH_SMARTCACHE_DIR:-$_cache_base/zsh-smartcache}"
  local _omp_cache_dir="$_cache_base/oh-my-posh"
  local _lig_cache_dir="$_cache_base/lig"
  local _zdotdir="${ZDOTDIR:-$HOME}"
  local _dotfiles_zsh_dir="${DOTFILES_DIR:-$HOME/.dotfiles}/zsh"

  # 1. Rimuove le cache di startup e Mise. Zephyr e Oh My Posh verificano
  # autonomamente se le rispettive cache sono obsolete.
  rm -f \
    "$_zsh_cache_dir"/init-tools.zsh*(N) \
    "$_zsh_cache_dir"/mise-activate-lazy.zsh*(N) \
    "$_zsh_cache_dir"/lig-init-{pre,post}.zsh*(N)
  [[ -d "$_sc_dir" ]] && rm -rf "${_sc_dir:?}"/*(N)
  [[ -d "$_zsh_eval_cache_dir" ]] && rm -rf "${_zsh_eval_cache_dir:?}"/*(N)

  # 2. Rimuove le vecchie cache per-sessione di Oh My Posh.
  [[ -d "$_omp_cache_dir" ]] && rm -f \
    "$_omp_cache_dir"/*(N)  
  
  #[[ -d "$_lig_cache_dir" ]] && rm -f "$_lig_cache_dir"/*(N)

  # 3. Rimuove il bundle statico Antidote per forzare la rigenerazione
  rm -f "$_zdotdir/.zsh_plugins.zsh"(N) \
    "${ZSH_CACHE_DIR:-$_zsh_cache_dir}"/antidote-bundle-no-precmd.zsh*(N)

  # Remove every compiled Zsh file under the active dotfiles and ZDOTDIR trees.
  rm -f \
    "$_zsh_cache_dir"/**/.zcompdump*(N.) \
    "$_zdotdir"/**/*.zwc(N.) \
    "$_zdotdir"/**/.*.zwc(N.) \
    "$_dotfiles_zsh_dir"/**/*.zwc(N.) \
    "$_dotfiles_zsh_dir"/**/.*.zwc(N.)

  exec zsh -l
}

# Trace a fresh interactive startup only when explicitly requested.
zsh-startup-trace() {
  emulate -L zsh
  local threshold_ms=${1-}
  if (( $# != 1 )) || [[ $threshold_ms != <-> && $threshold_ms != <->.<-> ]]; then
    printf 'Uso: zsh-startup-trace <soglia_ms>\n' >&2
    return 2
  fi

  local dir
  dir=$(command mktemp -d "${TMPDIR:-/tmp}/zsh-trace.XXXXXXXX") || return 1
  : >"$dir/zshrc.ms"
  : >"$dir/antidote.ms"
  : >"$dir/antidote.trace"

  local startup_status=0
  ZDOTDIR="${ZDOTDIR:-$HOME}" PS4='+TRACE|%D{%s.%6.}|%e|%N|%x:%I| ' \
    command zsh -ixc ': __DOTSH_ZSHRC_END__' 2>"$dir/startup.trace" || startup_status=$?

  LC_ALL=C command awk -F'|' -v dir="$dir" '
    /^[+]+TRACE[|]/ {
      if (!rc) {
        if ($4 !~ /(^|\/)\.zshrc$/) next
        rc = $4
        depth = $3
      }

      now = $2 + 0
      if (previous && now >= previous) {
        ms = (now - previous) * 1000
        printf "%9.2f ms  %s\n", ms, command >> (dir "/zshrc.ms")
        if (in_load)
          printf "%9.2f ms  %s\n", ms, command >> (dir "/antidote.ms")
      }

      if ($6 == " : __DOTSH_ZSHRC_END__") exit

      if ($4 == rc && $3 == depth)
        in_load = ($6 ~ /^ *antidote +load( |$)/)
      if (in_load)
        print >> (dir "/antidote.trace")

      previous = now
      command = $0
    }
  ' "$dir/startup.trace"

  printf '\n=== .zshrc (oltre %s ms) ===\n' "$threshold_ms"
  LC_ALL=C command awk -v threshold="$threshold_ms" '$1 + 0 > threshold' "$dir/zshrc.ms" |
    LC_ALL=C command sort -nr | command head -30
  printf '\n=== antidote load (oltre %s ms) ===\n' "$threshold_ms"
  LC_ALL=C command awk -v threshold="$threshold_ms" '$1 + 0 > threshold' "$dir/antidote.ms" |
    LC_ALL=C command sort -nr | command head -30
  printf '\nTrace e tempi di ogni riga in %s\n' "$dir"
  return $startup_status
}

_cached_eval() {
  emulate -L zsh
  setopt local_options no_aliases

  local dir="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/eval"
  local ttl=${CACHED_EVAL_TTL:-86400}
  local key="${(j: :)${(q)@}}"
  local cache="$dir/${key//[^a-zA-Z0-9]/_}.zsh"
  local compiled="${cache}.zwc"
  local now=${(%):-%D{%s}}
  local tmp
  local -a mtime

  (( $# )) || return 1

  # Verifica la validità della cache
  if [[ ! -f $cache ]] ||
     ! zstat -A mtime +mtime -- "$cache" ||
     (( now - mtime[1] >= ttl )); then

    mkdir -p -- "$dir" || return 1
    tmp="${cache}.$$"

    # Genera l'output e aggiorna la cache
    if "$@" >| "$tmp"; then
      mv -f -- "$tmp" "$cache" || return 1

      # Compila la cache aggiornata
      zcompile "$compiled" "$cache" 2>/dev/null
    else
      rm -f -- "$tmp"
      return 1
    fi
  fi

  # Compila anche una cache valida ma non ancora compilata
  if [[ ! -f $compiled || $cache -nt $compiled ]]; then
    zcompile "$compiled" "$cache" 2>/dev/null
  fi

  # Zsh usa automaticamente il .zwc se è aggiornato
  source "$cache"
}



_cache_cli_completion() {
  emulate -L zsh
  setopt no_aliases

  (( $# >= 2 )) || return 1

  local cache_file="${ZSH_COMP_CACHE_DIR}/$1"
  shift

  local binary
  binary=$(whence -p -- "$1") || return 1
  [[ -n $binary ]] || return 1

  # Return immediately if the cache is valid
  [[ -s $cache_file && ! $binary -nt $cache_file ]] && return 0

  [[ -d $ZSH_COMP_CACHE_DIR ]] ||
    mkdir -p -- "$ZSH_COMP_CACHE_DIR" || return 1

  local tmp_file="${cache_file}.$$.tmp"

  if [[ ! -s $cache_file ]]; then
    # Synchronous generation
    if "$@" >| "$tmp_file" 2>/dev/null && [[ -s $tmp_file ]]; then
      mv -f -- "$tmp_file" "$cache_file"
    else
      rm -f -- "$tmp_file"
      return 1
    fi
  else
    # Asynchronous refresh
    (
      if "$@" >| "$tmp_file" 2>/dev/null && [[ -s $tmp_file ]]; then
        mv -f -- "$tmp_file" "$cache_file"
      else
        rm -f -- "$tmp_file"
      fi
    ) &!
  fi
}


completion-source() {
  local func=${_comps[$1]}

  if [[ -z $func ]]; then
    echo "No completion registered for $1"
    return 1
  fi

  autoload +X "$func" 2>/dev/null
  print -r -- "${functions_source[$func]}"
  print
  for dir in $fpath; do
    [[ -f "$dir/$func" ]] && print -r -- "$dir/$func"
  done
}
