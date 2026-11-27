# Helpers for .zshrc. Sourcing this file defines the functions. The caller
# chooses when to initialize the cache, start the SSH query, and load colors.

# Cache the Zsh code printed by the command and arguments passed to this helper.
# Reuse the file while it is younger than CACHED_EVAL_TTL (86,400 seconds by
# default). On a miss, replace it only after the command succeeds, then compile
# and source it in the current shell. Use this for trusted commands such as
# dircolors that are expected to print shell code.
_cached_eval() {
  zmodload -F zsh/stat b:zstat 2>/dev/null
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

  # Refresh a missing or expired cache.
  if [[ ! -f $cache ]] ||
     ! zstat -A mtime +mtime -- "$cache" ||
     (( now - mtime[1] >= ttl )); then

    mkdir -p -- "$dir" || return 1
    tmp="${cache}.$$"

    # Generate into a temporary file and publish it only on success.
    if "$@" >| "$tmp"; then
      mv -f -- "$tmp" "$cache" || return 1

      # Compile the refreshed cache for subsequent reads.
      zcompile "$compiled" "$cache" 2>/dev/null
    else
      rm -f -- "$tmp"
      return 1
    fi
  fi

  # Also compile a valid cache if its wordcode is missing or older.
  if [[ ! -f $compiled || $cache -nt $compiled ]]; then
    zcompile "$compiled" "$cache" 2>/dev/null
  fi

  # Zsh automatically uses the adjacent .zwc when it is current.
  source "$cache"
}

# Lig PRE Must BE HERE
# >>> lig pre >>>
if (( $+commands[lig] )); then
  _cached_eval "$commands[lig]" init zsh pre
fi
# <<< lig pre <<<

# Schedule compilation of the readable Zsh source passed as $1 when its adjacent
# .zwc is missing, empty, or older than the source. The disowned job keeps the
# current shell from waiting for compilation. Later shells can load the bytecode.
_zcompile_if_needed() {
  local src="$1"
  [[ -r "$src" ]] || return 1
  local zwc="${src}.zwc"
  if [[ ! -s $zwc || $src -nt $zwc ]]; then
	#print -u2 "Compiling $src -> $zwc"
    { zcompile -R "$zwc" "$src" 2>/dev/null } &!
  fi
}

# Run early from .zshrc, once ZSH_CACHE_DIR and its completion directory exist.
# Load zstat and schedule compilation of startup files and local plugins. Reuse
# the package manager environment unless the cache is missing or its mode,
# startup files, or Homebrew executable have changed. Source the resulting
# cache in the current shell so its exports affect plugin loading and commands.
_dotsh_init_startup_cache() {
  zmodload -F zsh/stat b:zstat 2>/dev/null

  # Schedule a background rebuild when a startup file has changed.
  _zcompile_if_needed "${ZDOTDIR:-$HOME}/.zshenv"
  _zcompile_if_needed "${ZDOTDIR:-$HOME}/.zshrc"
  #_zcompile_if_needed  "$DOTFILES_DIR/zsh/helpers/lig-init.zsh"
  _zcompile_if_needed  "$DOTFILES_DIR/zsh/helpers/zsh-fast-startup.zsh"
  # Compile every custom plugin when its source changes.
  local _custom_plugin
  for _custom_plugin in "${DOTFILES_DIR}/zsh/dotsh.custom.plugins"/*.zsh(N); do
    _zcompile_if_needed "$_custom_plugin"
  done

  # Validate the package manager cache with a format header and file timestamps.
  local _init_cache="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/init-tools.zsh"
  local _init_source="${ZDOTDIR:-$HOME}/.zshrc"
  local _env_source="${ZDOTDIR:-$HOME}/.zshenv"
  local _package_manager_mode=homebrew
  if [[ $OSTYPE == darwin* && $CPUTYPE == x86_64 && \
        ${DOTSH_INTEL_PACKAGE_MANAGER:-${DOTFILES_INTEL_PACKAGE_MANAGER:-homebrew}} != homebrew ]]; then
    _package_manager_mode=macports
  fi
  local _expected_cache_header="# dotsh-init-tools-v3:${_package_manager_mode}"
  local _need_rebuild=0
  local _cache_header _bin
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
}

# Start ssh-add -l before package manager setup and plugin loading so the query
# can overlap with startup. Only run for an interactive shell with an inherited
# agent socket, lazy key loading, and the SSH identity summary enabled. Save
# the socket and read descriptor for the startup reporter. With eager loading
# it queries the agent after the keys have been added instead.
_dotsh_startup_ssh_open() {
  if [[ -o interactive && -S ${SSH_AUTH_SOCK-} ]] &&
     zstyle -t :omz:plugins:ssh-agent lazy &&
     zstyle -T ':dotsh:ssh-local' show-ids; then
    typeset -g _dotsh_startup_ssh_socket=$SSH_AUTH_SOCK
    exec {_dotsh_startup_ssh_fd}< <(
      command ssh-add -l 2>/dev/null
      printf '\n%d\n' "$?"
    )
  fi
}

# Release the read descriptor once the startup report has run or been skipped.
_dotsh_startup_ssh_close() {
  if [[ -n ${_dotsh_startup_ssh_fd-} ]]; then
    exec {_dotsh_startup_ssh_fd}<&-
    unset _dotsh_startup_ssh_fd _dotsh_startup_ssh_socket
  fi
}

# Run after Antidote has populated fpath and generated its static bundle. Check
# the entry point, bundle, and selected vendor scripts for stale or missing
# bytecode. Compile alongside the installed sources in the background. Save the
# history search directory for the one-time editor setup at the first ZLE prompt.
_dotsh_compile_bundle_plugins() {
  local defer_dir=${fpath[(r)*/zsh-defer]} zephyr_plugin

  _zcompile_if_needed "$ANTIDOTE_HOME/antidote.zsh"
  _zcompile_if_needed "$ZSH_CACHE_DIR/antidote-bundle-no-precmd.zsh"
  if [[ -n $defer_dir ]]; then
    _zcompile_if_needed "$defer_dir/zsh-defer.plugin.zsh"
  fi
  for zephyr_plugin in editor environment color completion; do
    _zcompile_if_needed "$ZEPHYR_HOME/plugins/$zephyr_plugin/$zephyr_plugin.plugin.zsh"
  done

  # The first ZLE hook uses this directory to load history search.
  typeset -g _dotsh_history_dir=${fpath[(r)*/zsh-history-substring-search]}
  if [[ -n $_dotsh_history_dir ]]; then
    _zcompile_if_needed "$_dotsh_history_dir/zsh-history-substring-search.plugin.zsh"
    _zcompile_if_needed "$_dotsh_history_dir/zsh-history-substring-search.zsh"
  fi
}

# Install a wrapper around Zephyr's completion setup after the bundle loads.
# Keep a copy of the original function so Zephyr can handle explicit arguments,
# stale caches, and completion directory security audits. The wrapper runs at
# Zephyr's normal point before the first prompt.
_dotsh_use_warm_compdump() {
  (( $+functions[run_compinit] )) || return 0
  functions -c run_compinit _dotsh_zephyr_run_compinit
  # Use compinit -C when the compiled dump is current and under 20 hours old,
  # the ordered list of live directories still matches the saved fpath, and no
  # directory is newer than the dump. Delegate every other case to Zephyr.
  run_compinit() {
    emulate -L zsh
    setopt extended_glob
    local dump=$ZSH_COMPDUMP
    if (( ! $# )) && zstyle -t ':zephyr:plugin:completion' use-cache &&
       [[ -n $dump && -s $dump.zwc && ! $dump -nt $dump.zwc &&
          -r $dump.fpath && -n $dump(#qNmh-20) ]]; then
      local -aU live=()
      local dir
      for dir in "${fpath[@]}"; do
        [[ ! -d $dir ]] || live+=("$dir")
      done
      if [[ "$live" == "$(<$dump.fpath)" ]]; then
        for dir in "${live[@]}"; do
          [[ ! $dir -nt $dump ]] || break
        done
        if [[ -z $dir || ! $dir -nt $dump ]]; then
          local flag=-i
          zstyle -t ':zephyr:plugin:completion' disable-compfix && flag=-u
          autoload -Uz compinit
          compinit -C "$flag" -d "$dump"
          return $?
        fi
      fi
    fi
    _dotsh_zephyr_run_compinit "$@"
  }
}

# Clear generated startup, completion, Mise, Lig, and Oh My Posh caches and
# remove compiled Zsh files under the active configuration directories. Then
# replace this process with a login shell so the regular startup code rebuilds
# the files it needs. Run this explicitly after changing configuration or tools.
function zsh-update() {

  local _cache_base="${XDG_CACHE_HOME:-$HOME/.cache}"
  local _zsh_cache_dir="$_cache_base/zsh"
  local _zsh_eval_cache_dir="$_cache_base/zsh/eval"
  local _sc_dir="${ZSH_SMARTCACHE_DIR:-$_cache_base/zsh-smartcache}"
  local _omp_cache_dir="$_cache_base/oh-my-posh"
  local _lig_cache_dir="$_cache_base/lig"
  local _zdotdir="${ZDOTDIR:-$HOME}"
  local _dotfiles_zsh_dir="${DOTFILES_DIR:-$HOME/.dotfiles}/zsh"

  # Remove startup and Mise caches. Zephyr and Oh My Posh also check cache age
  # themselves during normal shell startup.
  rm -f \
    "$_zsh_cache_dir"/init-tools.zsh*(N) \
    "$_zsh_cache_dir"/mise-activate-lazy.zsh*(N) \
    "$_zsh_cache_dir"/lig-init-{pre,post}.zsh*(N)
  [[ -d "$_sc_dir" ]] && rm -rf "${_sc_dir:?}"/*(N)
  [[ -d "$_zsh_eval_cache_dir" ]] && rm -rf "${_zsh_eval_cache_dir:?}"/*(N)

  # Remove saved Oh My Posh session files.
  [[ -d "$_omp_cache_dir" ]] && rm -f \
    "$_omp_cache_dir"/*(N)  
  
  #[[ -d "$_lig_cache_dir" ]] && rm -f "$_lig_cache_dir"/*(N)

  # Remove the static Antidote bundle so it is regenerated on the next startup.
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

# Trace a fresh interactive shell through the end of .zshrc using one required
# threshold in milliseconds. Save the full trace and timing files in a new
# temporary directory and print separate top-30 lists for .zshrc and Antidote.
# The times are gaps between trace entries. Work deferred until ZLE is idle is
# outside this report because the child runs a marker command and exits.
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

# Set up terminal colors and the ls alias once. Preserve an existing LS_COLORS
# or fill it from dircolors or gdircolors, caching the command output for each
# TERM for up to 20 hours. Load Zephyr's color defaults, then add -A to ls.
# .zshrc calls this directly when the first ZLE hook cannot run. Otherwise
# the first ZLE hook calls it before processing input, regardless of the prompt.
_dotsh_init_colors() {
  if [[ -z $LS_COLORS ]]; then
    local dircolors_bin=${commands[dircolors]:-${commands[gdircolors]}}
    if [[ -n $dircolors_bin ]]; then
      CACHED_EVAL_TTL=72000 _cached_eval env "TERM=$TERM" "$dircolors_bin" --sh
    fi
  fi
  [[ ! -r $ZEPHYR_HOME/plugins/color/color.plugin.zsh ]] ||
    builtin source "$ZEPHYR_HOME/plugins/color/color.plugin.zsh"
  alias ls="${aliases[ls]:-ls} -A"
  unfunction _dotsh_init_colors
}

# Cache a CLI-generated completion in ZSH_COMP_CACHE_DIR. Pass the completion
# filename first, then the executable and its generation arguments. Generate
# synchronously if the file is missing or empty. If the executable is newer,
# keep serving the old completion while a background job refreshes it. Replace
# the cache only when generation succeeds and produces a nonempty file.
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


# Report where the completion for the command passed as $1 comes from. Look it
# up in compinit's _comps table, resolve the autoloaded function without calling
# it, and print its source file followed by matching files in fpath order. Return
# with status 1 when the command has no registered completion.
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
