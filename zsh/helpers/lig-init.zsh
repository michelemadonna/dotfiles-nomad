# Cache the integration emitted by the installed executable. Keep the
# generated code intact so Lig can update its own PTY and ZLE protocol.
_dotsh_lig_source_init() {
  emulate -L zsh
  local part=$1 binary=${commands[lig]}
  [[ -n $binary && -x $binary ]] || return 1

  local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
  local cache="$cache_dir/lig-init-$part.zsh"
  local header expected tmp init
  local -A binary_stat
  if zmodload -F zsh/stat b:zstat &&
      zstat -H binary_stat -- "$binary"; then
    expected="# dotsh-lig-init-v1 ${ZSH_VERSION} ${binary:A} ${binary_stat[device]} ${binary_stat[inode]} ${binary_stat[mtime]} ${binary_stat[size]}"
    if [[ -r $cache && -s $cache ]] &&
        IFS= read -r header < "$cache" && [[ $header == "$expected" ]]; then
      source "$cache"
      return
    fi
  fi

  init=$(command "$binary" init zsh "$part") || return
  [[ -n $init ]] || return 1
  if [[ -n $expected ]] &&
      { [[ -d $cache_dir ]] || command mkdir -p -- "$cache_dir"; } &&
      tmp=$(command mktemp "$cache.XXXXXXXX"); then
    {
      if print -rl -- "$expected" "$init" >| "$tmp" &&
          command zsh -f -n "$tmp" &&
          command mv -f -- "$tmp" "$cache"; then
        source "$cache"
        return
      fi
    } always {
      [[ ! -e $tmp ]] || command rm -f -- "$tmp"
    }
  fi
  eval "$init"
}

_dotsh_lig_finish_init() {
  _dotsh_lig_source_init post || return
  # This runs during the first ZLE session, after the first precmd. Seed Lig's
  # context and buffer here without calling the other prompt hooks again.
  (( ! $+functions[_lig_precmd] )) || _lig_precmd
  (( ! $+functions[_lig_report] )) || _lig_report
}
