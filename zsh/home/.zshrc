# Interactive-shell defaults and optional startup profiling.
[[ ! -o interactive ]] || umask o-w
if [[ -f ${HOME}/.dotsh-zprof-enabled ]]; then
  zmodload zsh/zprof
fi

#TODO uncomment
#[[ -t 0 ]] && printf 'Last login: %s on %s\n' "$(LC_ALL=C date '+%a %b %e %H:%M:%S')" "$(tty | sed 's|^/dev/||')"
#move the cursor at the bottom of the terminal to avoid scrolling when the prompt is printed
print -n $'\e[9999;1H'
# Shared cache root for Mise, completions and other Zsh plugins.
typeset -g ZSH_CACHE_DIR="${ZSH_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/zsh}"
typeset -g ZSH_COMP_CACHE_DIR="${ZSH_CACHE_DIR}/completions"

if [[ ! -d "$ZSH_CACHE_DIR" ]]; then
  mkdir -p "$ZSH_CACHE_DIR"
fi
if [[ ! -d "$ZSH_COMP_CACHE_DIR" ]]; then
  mkdir -p "$ZSH_COMP_CACHE_DIR"
fi

builtin source "$DOTFILES_DIR/zsh/helpers/zsh-fast-startup.zsh"
builtin source "$DOTFILES_DIR/zsh/dotsh.custom.plugins/dotsh-misc.plugin.zsh"

# ZSH Completion Cache
zstyle ':completion:*' use-cache yes
zstyle ':completion:*' cache-path "$ZSH_CACHE_DIR/zcompcache"

# FPATH BASE (Before Antidote so compinit can find the completion functions of the package manager)
typeset -gU fpath FPATH

local -a _fn_candidates=()

if [[ $OSTYPE == darwin* ]]; then
  # Keep Homebrew's and Macports's completions available in every installation mode.
  _fn_candidates+=(
    /opt/local/share/zsh/site-functions
    /opt/homebrew/share/zsh/site-functions
    /usr/local/share/zsh/site-functions
  )
elif [[ $OSTYPE == linux* ]]; then
  _fn_candidates+=(
    /home/linuxbrew/.linuxbrew/share/zsh/site-functions
    /usr/local/share/zsh/site-functions
    /usr/share/zsh/site-functions
    /usr/share/zsh/vendor-completions
  )
fi

fpath=(${^_fn_candidates}(N/) $fpath)

unset _fn_candidates

path=("$HOME/.local/bin" $path)




# Lig PRE Must BE HERE
# >>> lig pre >>>
#_cached_eval "/Users/michele/Developer/michelemadonna@github/lig/target/release/lig" init zsh pre
# <<< lig pre <<<

# Reuse Zephyr's completion dump and audit it only when the cache expires or
# the completion search path changes.
zstyle ':zephyr:plugin:completion' use-cache yes

# Completion styles
# Matching
#zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'm:{a-zA-Z}={A-Za-z} r:|[-_.]=* r:|=*' DA VERIFICARE
# Menu
zstyle ':completion:*' show-ambiguity '1;38;5;214'
# Groups
zstyle ':completion:*' group-order directories files
zstyle ':completion:*' list-grouped false
# Colors
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
# Files and directories
zstyle ':completion:*' list-dirs-first true
# Editors and file viewers
zstyle ":completion:*:*:(bat|micro|nano|vim|${EDITOR:t}):*" file-sort modification
# Options
zstyle ':completion:*:options' list-colors '=--*=38;5;81' '=-*=38;5;114'


#TODO Add every key in in .ssh using the parameter indentities
zstyle :omz:plugins:ssh-agent honor-existing yes
zstyle :omz:plugins:ssh-agent lazy yes
zstyle :omz:plugins:ssh-agent quiet yes

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

#fpath=("$ZSH_COMP_CACHE_DIR" $fpath)

# OH MY POSH
if (( $+commands[oh-my-posh1] )); then
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
  #TODO improve with git_status and git_prompt_info
  PROMPT='%F{cyan}%n@%m%f %F{blue}%~%f %# '
fi

# 6. KEYBINDING FRECCE & UPDATE ALL-IN-ONE
zsh-defer -m bindkey "${terminfo[kcuu1]}" history-substring-search-up
zsh-defer -m bindkey "${terminfo[kcud1]}" history-substring-search-down

# Add flags to existing aliases.
alias ls="${aliases[ls]:-ls} -A"
(( $+commands[python3] )) && alias python='command python3'

# Bracketed paste on: multi-line pastes do NOT auto-run
set zle_bracketed_paste
ZSH_AUTOSUGGEST_CLEAR_WIDGETS+=(bracketed-paste)

# Don't beep, don't autocorrect agent commands into garbage
unsetopt CORRECT CORRECT_ALL


# GPG / PINENTRY
[[ -t 0 && -n $TTY ]] && export GPG_TTY=$TTY

## Long running processes should return time after they complete. Specified
## in seconds.
REPORTTIME=${REPORTTIME:-2}
TIMEFMT="%U user %S system %P cpu %*Es total"



if [[ -f ${HOME}/.dotsh-zprof-enabled ]]; then
  zprof
fi


## >>> lig post >>>
#if [[ -o interactive && ! -v ZSH_EXECUTION_STRING && -z ${LIG_DISABLE-} &&
#      -n ${LIG_TTY-} && "$LIG_TTY" == "$TTY" ]] && (( $+commands[lig] )); then
#  source "$DOTFILES_DIR/zsh/helpers/lig-init.zsh"
#  # Antidote queues autosuggestions and highlighting before Lig's ZLE hooks.
#  zsh-defer -m -p _dotsh_lig_finish_init
#fi
## <<< lig post <<<

#LIG POST Must BE HERE
# >>> lig post >>>
#zsh-defer -m -p _cached_eval "/Users/michele/Developer/michelemadonna@github/lig/target/release/lig" init zsh post
# <<< lig post <<<
# Autosuggestions otherwise waits for the next real precmd to bind widgets.
# Its dependencies and Lig's widget hooks have run when this task executes.
if (( $+functions[zsh-defer] )); then
  zsh-defer -m -p -c '(( ! $+functions[_zsh_autosuggest_start] )) || _zsh_autosuggest_start'
fi

## >>> lig post >>>
## zsh-defer -m -p -c _lig_load_init post
## <<< lig post <<<

