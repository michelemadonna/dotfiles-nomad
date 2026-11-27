_dotsh_show_fastfetch() {
    [[ $DOTSH_SHOW_FASTFETCH != never && -o interactive && -z ${DOTSH_FASTFETCH_SHOWN:-} ]] || return 0

    local mode=${DOTSH_SHOW_FASTFETCH:-never}

    
    if (( ! $+commands[fastfetch] )); then
        print -u2 "fastfetch not found. See $DOTFILES_DIR/Readme.md"

    else
        emulate -L zsh
        
        local parent_cmd tty_list tty
        local -a terminals
        local -i expected_ptys=1
        
        parent_cmd=$(ps -o comm= -p "$PPID" 2>/dev/null)
        
        case ${parent_cmd:l} in
            *zed*|*code*|*micro*|*nvim*|*vim*|*idea*|\
            *clion*|*goland*|*phpstorm*|*pycharm*|\
            *tmux*|*fresh*|*helix*|*terminal*)
                return 0
                ;;
        esac
        
        if [[ $mode == first-pty ]]; then
            [[ -t 0 && -n $TTY ]] || return 0
        
            # Lig allocates an additional PTY for the child shell.
            [[ ${parent_cmd:t} == lig ]] && expected_ptys=2
        
            # Count allocated PTYs directly.
            case $OSTYPE:$TTY in
                darwin*:/dev/ttys[0-9][0-9]<->)
                    # Exclude static macOS TTY device nodes.
                    terminals=(/dev/ttys[0-9][0-9]<->(N%c))
                    ;;
                linux*:/dev/pts/<->)
                    terminals=(/dev/pts/<->(N%c))
                    ;;
                *)
                    # Process-based fallback for other terminal types.
                    tty_list=$(ps -axo tty= 2>/dev/null) || return 0
        
                    for tty in ${(u)=tty_list}; do
                        case $tty in
                            ttys<->|pts/<->|s<->)
                                terminals+=("$tty")
                                ;;
                        esac
                    done
                    ;;
            esac
        
            (( ${#terminals} <= expected_ptys )) || return 0
        fi
        print
        print
        fastfetch --pipe false && export DOTSH_FASTFETCH_SHOWN=1
    fi

    
}

_dotsh_show_fastfetch
