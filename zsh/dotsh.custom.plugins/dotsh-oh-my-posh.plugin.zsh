#!/usr/bin/env zsh
# This plugin provides a fast-loading Oh My Posh integration for Zsh.
#TODO Copy on dotfiles-next also the config
if (( ! $+commands[oh-my-posh] )); then
  return
fi

typeset -g DOTSH_OMP_PLUGIN_FILE="${(%):-%x}"
typeset -gi _dotsh_omp_right_fd=${_dotsh_omp_right_fd:--1}
typeset -gi _dotsh_omp_first_right=${_dotsh_omp_first_right:-1}


_dotsh_omp_cancel_right() {
    if (( ${_dotsh_omp_right_fd:--1} >= 10 )); then
        zle -F "$_dotsh_omp_right_fd" 2>/dev/null
        { exec {_dotsh_omp_right_fd}<&- } 2>/dev/null
    fi

    typeset -gi _dotsh_omp_right_fd=-1
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
    #print -r -- 'zmodload zsh/datetime 2>/dev/null'
    #print -r -- "printf -v POSH_SESSION_ID '%08x-%04x-%04x-%04x-%04x%08x' \$(( (RANDOM << 16) | RANDOM )) \$RANDOM \$RANDOM \$RANDOM \$RANDOM \$(( (RANDOM << 16) | RANDOM ))"
    #print -r -- 'export POSH_SESSION_ID'
    #print -r -- "export POSH_CONFIG=${(qqq)config_file}"
    #print -r -- 'typeset -gi _dotsh_omp_first_right=1 _dotsh_omp_right_fd=-1'
    print -r -- 'if [[ -z ${_dotsh_omp_prestarted-} ]]; then'

    print -r -- "printf -v POSH_SESSION_ID '%08x-%04x-%04x-%04x-%04x%08x' \$(( (RANDOM << 16) | RANDOM )) \$RANDOM \$RANDOM \$RANDOM \$RANDOM \$(( (RANDOM << 16) | RANDOM ))"

    print -r -- 'fi'
    print -r -- 'export POSH_SESSION_ID'
    
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

_dotsh_omp_prepare_cache() {
    emulate -L zsh

    local omp_binary=${commands[oh-my-posh]}
    local config_file=$DOTSH_OH_MY_POSH_CONFIG
    local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/zsh"

    local config_key=${config_file:A}
    config_key=${config_key//\//_}
    config_key=${config_key//[^A-Za-z0-9_.-]/_}

    typeset -g _dotsh_omp_cache_file
    _dotsh_omp_cache_file="$cache_dir/oh-my-posh-init-${ZSH_VERSION}-${config_key}.zsh"

    local cache_file=$_dotsh_omp_cache_file

    if [[ ! -s $cache_file ||
          $omp_binary -nt $cache_file ||
          $config_file -nt $cache_file ||
          $DOTSH_OMP_PLUGIN_FILE -nt $cache_file ]]; then

        [[ -d $cache_dir ]] ||
            command mkdir -p -- "$cache_dir"

        _dotsh_omp_generate_init_cache \
            "$omp_binary" "$config_file" "$cache_file" ||
            return 1
    fi
    # Compile the cached initialization script when needed.
    if [[ ! -s "${cache_file}.zwc" ||
          $cache_file -nt "${cache_file}.zwc" ]]; then
        builtin zcompile -R "$cache_file" || true
    fi
    return 0
}

dotsh-init-oh-my-posh() {
    emulate -L zsh

    local omp_binary=${commands[oh-my-posh]}
    local config_file=$DOTSH_OH_MY_POSH_CONFIG

    if [[ ! -s ${_dotsh_omp_cache_file-} ]] &&
       ! _dotsh_omp_prepare_cache; then

        _dotsh_startup_omp_close

        eval "$(command "$omp_binary" init zsh \
            --config "$config_file")"
        return
    fi

    source "$_dotsh_omp_cache_file"

    if [[ -t 0 && -t 1 &&
          ${_omp_enable_streaming:-0} == 1 ]] &&
       (( $+functions[_omp_serve_start] )); then

        if [[ -n ${_dotsh_omp_prestarted-} ]] &&
           (( _omp_serve_fd_in >= 0 &&
              _omp_serve_fd_out >= 0 )) &&
           kill -0 "$_omp_serve_pid" 2>/dev/null; then

            # Attach to the already running daemon.
            if ! zle -F "$_omp_serve_fd_out" \
                _omp_serve_async_handler; then

                _omp_serve_start || true
            fi

        else
            _omp_serve_start || true
        fi

    elif [[ -n ${_dotsh_omp_prestarted-} ]]; then
        _dotsh_startup_omp_close
    fi

    unset _dotsh_omp_prestarted
    unset _dotsh_omp_cache_file

    return 0
}

_dotsh_startup_omp_open() {
    [[ -o interactive && -t 0 && -t 1 ]] || return 0
    [[ ${DOTSH_PROMPT:-} == ohmyposh ]] || return 0
    [[ ! -v POSH_DISABLE_STREAMING ]] || return 0
    [[ -f $DOTSH_OH_MY_POSH_CONFIG ]] || return 0

    (( $+commands[oh-my-posh] )) || return 0

    # Avoid replacing an existing daemon.
    (( ${_omp_serve_fd_in:--1} < 0 )) || return 0

    _dotsh_omp_prepare_cache || return 0

    setopt localoptions no_monitor

    typeset -g POSH_SESSION_ID
    typeset -g _dotsh_omp_prestarted
    typeset -gi _omp_serve_fd_in=-1
    typeset -gi _omp_serve_fd_out=-1
    typeset -gi _omp_serve_pid=0

    printf -v POSH_SESSION_ID \
        '%08x-%04x-%04x-%04x-%04x%08x' \
        $(( (RANDOM << 16) | RANDOM )) \
        $RANDOM $RANDOM $RANDOM $RANDOM \
        $(( (RANDOM << 16) | RANDOM ))

    export POSH_SESSION_ID
    export POSH_CONFIG="$DOTSH_OH_MY_POSH_CONFIG"
    export POSH_SHELL=zsh
    export POSH_SHELL_VERSION=$ZSH_VERSION

    coproc "$commands[oh-my-posh]" serve --shell=zsh 2>/dev/null

    (( $? == 0 )) || return 0

    _omp_serve_pid=$!

    {
        exec {_omp_serve_fd_out}<&p \
             {_omp_serve_fd_in}>&p
    } 2>/dev/null

    if (( _omp_serve_fd_in < 0 ||
          _omp_serve_fd_out < 0 )); then
        _dotsh_startup_omp_close
        return 0
    fi

    disown %+ 2>/dev/null

    _dotsh_omp_prestarted=1

    TRAPWINCH() {
      if zle; then
        _dotsh_omp_cancel_right
        zle omp_repaint_prompt
      fi

      return 0
    }

    return 0
}

_dotsh_startup_omp_close() {
    if [[ -n ${_dotsh_omp_prestarted-} ]] ||
       (( ${_omp_serve_fd_in:--1} >= 0 ||
          ${_omp_serve_fd_out:--1} >= 0 )); then

        if (( ${_omp_serve_fd_in:--1} >= 0 )); then
            exec {_omp_serve_fd_in}>&-
        fi

        if (( ${_omp_serve_fd_out:--1} >= 0 )); then
            exec {_omp_serve_fd_out}<&-
        fi

        typeset -gi _omp_serve_fd_in=-1
        typeset -gi _omp_serve_fd_out=-1
        typeset -gi _omp_serve_pid=0
    fi

    unset _dotsh_omp_prestarted

    return 0
}

