_dotsh_fastfetch_skip_parent() {
    case ${1:l} in
        *zed*|*code*|*micro*|*nvim*|*vim*|*idea*|\
        *clion*|*goland*|*phpstorm*|*pycharm*|\
        *tmux*|*fresh*|*helix*) return 0 ;;
    esac
    return 1
}

_dotsh_fastfetch_is_first_pty() {
    local shell_pid=$1 process_table pid parent tty name owner
    local -A parents process_ttys process_names frontend_ttys

    process_table=$(command ps -axo pid=,ppid=,tty=,comm= 2>/dev/null) || return 1
    while IFS=$' \t' read -r pid parent tty name; do
        [[ -n $pid ]] || continue
        parents[$pid]=$parent
        process_names[$pid]=${name:t}
        case $tty in
            s<->|ttys<->|pts/<->|tty<->) process_ttys[$pid]=$tty ;;
        esac
    done <<< "$process_table"

    # Walk through the shell and any PTY wrappers to the terminal process.
    pid=$shell_pid
    [[ -n ${process_ttys[$pid]-} ]] || return 1
    while [[ -n ${process_ttys[$pid]-} ]]; do
        _dotsh_fastfetch_skip_parent "${process_names[$pid]}" && return 1
        parent=${parents[$pid]-}
        [[ -n $parent && $parent != "$pid" ]] || return 1
        pid=$parent
    done
    owner=$pid
    (( owner > 1 )) && [[ -n ${process_names[$owner]-} ]] || return 1
    _dotsh_fastfetch_skip_parent "${process_names[$owner]}" && return 1

    # The terminal owns the outer PTY of each session. Inner PTYs, such as
    # Lig's PTY for Zsh, belong to descendants of that session.
    for pid in ${(k)process_ttys}; do
        if [[ ${parents[$pid]} == "$owner" ]]; then
            tty=${process_ttys[$pid]}
            frontend_ttys[$tty]=1
        fi
    done
    (( ${#frontend_ttys} == 1 ))
}

_dotsh_show_fastfetch() {
    local mode=${DOTSH_SHOW_FASTFETCH:-never}
    [[ $mode != never && -o interactive && -z ${DOTSH_FASTFETCH_SHOWN:-} ]] || return 0
    if (( ! $+commands[fastfetch] )); then
        print -u2 "fastfetch not found. See $DOTFILES_DIR/Readme.md"
        return 0
    fi

    emulate -L zsh
    if [[ $mode == first-pty ]]; then
        [[ -t 0 && -n $TTY ]] || return 0
        _dotsh_fastfetch_is_first_pty "$$" || return 0
    else
        local parent_cmd
        parent_cmd=$(command ps -o comm= -p "$PPID" 2>/dev/null)
        [[ ${parent_cmd:l} == *terminal* ]] && return 0
        _dotsh_fastfetch_skip_parent "$parent_cmd" && return 0
    fi

    print
    print
    fastfetch --pipe false && export DOTSH_FASTFETCH_SHOWN=1
}

_dotsh_show_fastfetch
