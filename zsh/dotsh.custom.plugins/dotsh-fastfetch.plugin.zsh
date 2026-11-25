_dotsh_show_fastfetch() {
    [[ -o interactive &&
       ${DOTSH_SHOW_FASTFETCH:-false} != false &&
       -z ${DOTSH_FASTFETCH_SHOWN:-} ]] || return 0

    export DOTSH_FASTFETCH_SHOWN=1

    if (( ! $+commands[fastfetch] )); then
        print -u2 "fastfetch not found. See $DOTFILES_DIR/Readme.md"
        return 0
    fi

    emulate -L zsh
    local parent_cmd tty_list tty first_tty
    local -a terminals

    if [[ $DOTSH_SHOW_FASTFETCH == first ]]; then
        [[ -t 0 && -n $TTY ]] || return 0
        # Count allocated PTYs directly. On macOS the static ttys0–ttys9
        # nodes also exist without a session, so only count dynamic names.
        case $OSTYPE:$TTY in
            darwin*:/dev/ttys[0-9][0-9]<->)
                terminals=(/dev/ttys[0-9][0-9]<->(N%c))
                ;;
            linux*:/dev/pts/<->)
                terminals=(/dev/pts/<->(N%c))
                ;;
            *)
                # Keep the process-based check for other terminal types.
                tty_list=$(ps -axo tty= 2>/dev/null) || return 0
                for tty in ${(u)=tty_list}; do
                    case $tty in
                        ttys<->|pts/<->|s<->)
                            [[ -z $first_tty ]] || return 0
                            first_tty=$tty
                            ;;
                    esac
                done
                ;;
        esac
        (( ${#terminals} <= 1 )) || return 0
    fi

    parent_cmd=$(ps -o comm= -p "$PPID" 2>/dev/null)
    case ${parent_cmd:l} in
        *zed*|*code*|*micro*|*nvim*|*vim*|*idea*|\
        *clion*|*goland*|*phpstorm*|*pycharm*|\
        *tmux*|*fresh*|*helix*|*terminal*)
            return 0
            ;;
    esac

    fastfetch --pipe false
}

_dotsh_show_fastfetch
