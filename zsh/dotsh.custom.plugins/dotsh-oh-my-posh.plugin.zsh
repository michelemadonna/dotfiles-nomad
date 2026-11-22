#!/usr/bin/env zsh

if (( ! $+commands[oh-my-posh] )); then
  return
fi



typeset -g DOTSH_OMP_PLUGIN_FILE="${(%):-%x}"

_dotsh_omp_cancel_right() {
  if (( _dotsh_omp_right_fd >= 0 )); then
    zle -F "$_dotsh_omp_right_fd" 2>/dev/null
    exec {_dotsh_omp_right_fd}<&-
    _dotsh_omp_right_fd=-1
  fi
  return 0
}

_dotsh_omp_right_ready() {
  local fd=$1 text
  (( fd == _dotsh_omp_right_fd )) || return 0
  if IFS= read -r -d '' -u "$fd" text; then
    RPROMPT=$text
    zle reset-prompt
  fi
  _dotsh_omp_cancel_right
}

_dotsh_omp_render_right() {
  local text
  if (( _dotsh_omp_first_right )) && [[ -t 0 && -t 1 ]]; then
    _dotsh_omp_first_right=0
    if { exec {_dotsh_omp_right_fd}< <(
      # The first left renderer owns the session cache. Only read it here.
      text=$(_omp_get_prompt right --save-cache=false </dev/null 2>/dev/null) &&
        print -rn -- "$text"$'\0'
    ) } 2>/dev/null &&
        zle -F "$_dotsh_omp_right_fd" _dotsh_omp_right_ready; then
      RPROMPT=''
      return
    fi
    _dotsh_omp_cancel_right
  fi
  RPROMPT=$(_omp_get_prompt right)
}

_dotsh_omp_generate_init_cache() {
  emulate -L zsh
  setopt local_options err_return

  local omp_binary=$1
  local config_file=$2
  local cache_file=$3
  local cache_tmp="${cache_file}.${$}.tmp"
  local init_command init_file secondary_eval line tips_json tip
  local -a tips
  local -i secondary=0 right=0 precmd=0 preexec=0 exit_hook=0 fallback=0 tooltip=0

  init_command=$(command "$omp_binary" init zsh --config "$config_file") || return
  if [[ $init_command != *'source '* ]]; then
    print -u2 -r -- "oh-my-posh: unsupported init output; using the standard loader"
    return 1
  fi

  init_file=${(Q)${init_command##*source }}
  [[ -r $init_file ]] || return 1
  secondary_eval=$(command "$omp_binary" print secondary --shell=zsh --eval --config "$config_file") || return
  # For a theme with inherited tooltips, let Oh My Posh resolve the keywords.
  if (( $+commands[jq] )) &&
      tips_json=$(command jq -er '
        if has("extends") then error("inherited tooltips") else
          [.tooltips[]?.tips[]?] | unique |
          if all(.[]; type == "string" and test("^[[:alnum:]_./+:-]+$"))
          then join("\n") else error("unsupported tooltips") end
        end' "$config_file" 2>/dev/null); then
    tips=(${(f)tips_json})
  else
    tips_json=
  fi

  {
    print -r -- 'zmodload zsh/datetime 2>/dev/null'
    print -r -- "printf -v POSH_SESSION_ID '%08x-%04x-%04x-%04x-%04x%08x' \$(( (RANDOM << 16) | RANDOM )) \$RANDOM \$RANDOM \$RANDOM \$RANDOM \$(( (RANDOM << 16) | RANDOM ))"
    print -r -- 'export POSH_SESSION_ID'
    print -r -- "export POSH_CONFIG=${(qqq)config_file}"
    print -r -- 'typeset -gi _dotsh_omp_first_right=1 _dotsh_omp_right_fd=-1'
    if [[ -n $tips_json ]]; then
      print -r -- 'typeset -gA _dotsh_omp_tips=()'
      for tip in "${tips[@]}"; do
        print -r -- "_dotsh_omp_tips[${(q)tip}]=1"
      done
    fi

    while IFS= read -r line || [[ -n $line ]]; do
      case $line in
        'eval "$($_omp_executable print secondary --shell=zsh --eval)"')
          print -r -- "$secondary_eval"
          (( ++secondary ))
          ;;
        '    RPROMPT=$(_omp_get_prompt right)')
          print -r -- '    _dotsh_omp_render_right'
          (( ++right ))
          ;;
        '  _omp_pipestatus=(${pipestatus[@]})')
          # Preserve the status captured by the generator before cancelling.
          print -rl -- "$line" '  _dotsh_omp_cancel_right'
          (( ++precmd ))
          ;;
        'function _omp_preexec() {')
          print -rl -- "$line" '  _dotsh_omp_cancel_right'
          (( ++preexec ))
          ;;
        'function _omp_exit_handler() {')
          print -rl -- "$line" '  _dotsh_omp_cancel_right'
          (( ++exit_hook ))
          ;;
        '  # === FALLBACK PATH ===')
          print -rl -- "$line" '  _dotsh_omp_cancel_right'
          (( ++fallback ))
          ;;
        '  _omp_tooltip_command="$tooltip_command"')
          if [[ -n $tips_json ]]; then
            print -r -- '  [[ -n $_omp_tooltip_command || -n ${_dotsh_omp_tips[$tooltip_command]-} ]] || return 0'
          fi
          print -rl -- '  _dotsh_omp_cancel_right' "$line"
          (( ++tooltip ))
          ;;
        *)
          print -r -- "$line"
          ;;
      esac
    done < "$init_file"
  } >| "$cache_tmp" || {
    command rm -f -- "$cache_tmp"
    return 1
  }

  if (( secondary != 1 || right != 1 || precmd != 1 || preexec != 1 ||
        exit_hook != 1 || fallback != 1 || tooltip != 1 )) ||
      ! command zsh -f -n "$cache_tmp"; then
    command rm -f -- "$cache_tmp"
    return 1
  fi

  command mv -f -- "$cache_tmp" "$cache_file"
}

dotsh-init-oh-my-posh() {
  emulate -L zsh

  local omp_binary=${commands[oh-my-posh]}
  local config_file=$DOTSH_OH_MY_POSH_CONFIG
  local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
  local config_key=${config_file:A}
  config_key=${config_key//\//_}
  config_key=${config_key//[^A-Za-z0-9_.-]/_}
  local cache_file="$cache_dir/oh-my-posh-init-${ZSH_VERSION}-${config_key}.zsh"
  local rebuild=false

  if [[ ! -s $cache_file || $omp_binary -nt $cache_file || \
        $config_file -nt $cache_file || $DOTSH_OMP_PLUGIN_FILE -nt $cache_file ]]; then
    rebuild=true
  fi

  if [[ $rebuild == true ]]; then
    [[ -d $cache_dir ]] || command mkdir -p -- "$cache_dir"
    _dotsh_omp_generate_init_cache "$omp_binary" "$config_file" "$cache_file" || {
      eval "$(command "$omp_binary" init zsh --config "$config_file")"
      return
    }
  fi

  source "$cache_file"
  if [[ -t 0 && -t 1 && ${_omp_enable_streaming:-0} == 1 ]] &&
      (( $+functions[_omp_serve_start] )); then
    _omp_serve_start || true
  fi
}
