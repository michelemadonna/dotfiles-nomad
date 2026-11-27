# >>> lig pre >>>
#eval "$("/Users/michele/.local/bin/lig" init zsh pre)"
# <<< lig pre <<<
# Interactive Zsh startup. Load the helpers and query SSH first, then prepare
# the cache, search paths, and plugin styles before loading the Antidote bundle.
# Zephyr initializes completions before the first prompt. The editor finishes
# its setup when ZLE starts, before it processes the first key.

# Remove write permission for other users on files created by interactive
# shells. Load zprof early when its marker file exists to measure startup.
if [[ -o interactive && -t 1 ]]; then
    zmodload zsh/terminfo
    echoti cup $(( LINES - 1 )) 0
fi


[[ ! -o interactive ]] || umask o-w
if [[ -f ${HOME}/.dotsh-zprof-enabled ]]; then
  zmodload zsh/zprof
fi

# Shared cache root for Mise, completions and other Zsh plugins.
typeset -g ZSH_CACHE_DIR="${ZSH_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/zsh}"
typeset -g ZSH_COMP_CACHE_DIR="${ZSH_CACHE_DIR}/completions"
[[ ! -d "$ZSH_CACHE_DIR" ]] && mkdir -p "$ZSH_CACHE_DIR"
[[ ! -d "$ZSH_COMP_CACHE_DIR" ]] && mkdir -p "$ZSH_COMP_CACHE_DIR"

# Cache results produced by completion functions under the shared cache root.
zstyle ':completion:*' use-cache yes
zstyle ':completion:*' cache-path "$ZSH_CACHE_DIR/zcompcache"
# Reuse Zephyr's completion dump and audit it only when the cache expires or
# the completion search path changes.
zstyle ':zephyr:plugin:completion' use-cache yes
zstyle ':zephyr:plugin:color' use-cache yes

builtin source "$DOTFILES_DIR/zsh/helpers/zsh-fast-startup.zsh"

# Configure SSH behavior before the asynchronous startup query and before the
# Oh My Zsh ssh-agent plugin is sourced from the Antidote bundle.
zstyle :omz:plugins:ssh-agent honor-existing yes
if [[ ${DOTSH_SSH_LOAD_KEY:-false} == true ]]; then
  local key header
  local -a identities
  for key in ~/.ssh/*(N.); do
    IFS= read -r header < "$key" || continue
    [[ $header == '-----BEGIN '*PRIVATE\ KEY----- ]] &&
      identities+=("$key")
  done
  zstyle ':omz:plugins:ssh-agent' identities "${identities[@]}"
  zstyle :omz:plugins:ssh-agent lazy no
else
  zstyle :omz:plugins:ssh-agent lazy yes
fi
zstyle :omz:plugins:ssh-agent quiet yes
if [[ ${DOTSH_SSH_SHOW_KEY:-false} == true ]]; then
  zstyle ':dotsh:ssh-local' show-ids yes
else
  zstyle ':dotsh:ssh-local' show-ids no
fi
[[ ${DOTSH_SSH_ASKPASS_REQUIRE:-false} != true ]] || export SSH_ASKPASS_REQUIRE=force

# Start the inherited SSH agent query early so the startup summary can reuse it.
_dotsh_startup_ssh_open

## Move the cursor to the bottom of the terminal before printing the prompt.
#print -n $'\e[9999;1H'

_dotsh_init_startup_cache
builtin source "$DOTFILES_DIR/zsh/dotsh.custom.plugins/dotsh-misc.plugin.zsh"


# Add package manager completion directories before Antidote loads, when
# compinit has yet to build its completion table. Keep the first occurrence of
# each path so a duplicate entry cannot change the search order.
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

local -a _fn_dirs=()
for _fn_dir in "${_fn_candidates[@]}"; do
  [[ -d $_fn_dir && ! -L $_fn_dir ]] && _fn_dirs+=("$_fn_dir")
done
fpath=("${_fn_dirs[@]}" "${fpath[@]}")
unset _fn_candidates _fn_dirs _fn_dir

path=("$HOME/.local/bin" $path)

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

# Prefer an installed copy of Antidote and fall back to a checkout in ZDOTDIR.
# Antidote generates a static bundle from the manifest and reuses it on startup.
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
typeset -g ZSH_AUTOSUGGEST_MANUAL_REBIND=1
antidote load
#if [[ -o interactive && -t 1 ]]; then
#    zmodload zsh/terminfo
#    echoti cup $(( LINES - 1 )) 0
#fi

# Use Zsh prompt escapes for the current time and terminal without starting external commands.
#[[ -t 0 ]] && LC_ALL=C builtin print -rP -- 'Last login: %D{%a %b %e %H:%M:%S} on %y'
#print -r

_dotsh_use_warm_compdump
_dotsh_compile_bundle_plugins

#fpath=("$ZSH_COMP_CACHE_DIR" $fpath)

# Initialize colors here when the first ZLE hook cannot do it.
if [[ ! -o zle || ! -t 0 || -v ZSH_EXECUTION_STRING ]]; then
  _dotsh_init_colors
fi

# Older generated .zshenv files may still use the boolean prompt setting.
if [[ ${DOTSH_PROMPT:-} == ohmyposh ]] && (( $+commands[oh-my-posh] )); then
  local omp_plugin="$DOTFILES_DIR/zsh/dotsh.custom.plugins/dotsh-oh-my-posh.plugin.zsh"
  if [[ -f $DOTSH_OH_MY_POSH_CONFIG ]]; then
    if [[ -r $omp_plugin ]] &&
       builtin source "$omp_plugin" &&
       (( $+functions[dotsh-init-oh-my-posh] )); then
      dotsh-init-oh-my-posh
    else
      eval "$(command oh-my-posh init zsh --config "$DOTSH_OH_MY_POSH_CONFIG")"
    fi
  else
    eval "$(command oh-my-posh init zsh)"
  fi
else
  #TODO improve with git_status and git_prompt_info
  PROMPT='%F{cyan}%n@%m%f %F{blue}%~%f %# '
fi

# Clear the completion list shown before menu selection starts. The redraw
# keeps the current command line. In vi insert mode, also keep Escape's
# normal transition to vi command mode.
_dotsh_dismiss_completion_list() {
  zle -R -c
  if [[ $WIDGET == _dotsh_dismiss_completion_list_vi ]]; then
    zle vi-cmd-mode
  fi
}

# Run once when ZLE begins editing its first line. Draw the prompt, then load
# Zephyr's editor, colors if still pending, and history search before reading
# input. Bind both arrow-key sequences, run the newly installed line-init
# widget for this first line, and make Mise completion ready for the first Tab.
_dotsh_init_first_zle_line() {
  add-zle-hook-widget -d line-init _dotsh_init_first_zle_line
  zle -R
  [[ ! -r $ZEPHYR_HOME/plugins/editor/editor.plugin.zsh ]] ||
    builtin source "$ZEPHYR_HOME/plugins/editor/editor.plugin.zsh"
  (( ! $+functions[_dotsh_init_colors] )) || _dotsh_init_colors
  if [[ -n $_dotsh_history_dir ]]; then
    builtin source "$_dotsh_history_dir/zsh-history-substring-search.plugin.zsh"
  fi
  unset _dotsh_history_dir
  zmodload zsh/terminfo
  [[ -z ${terminfo[kcuu1]} ]] || bindkey "${terminfo[kcuu1]}" history-substring-search-up
  [[ -z ${terminfo[kcud1]} ]] || bindkey "${terminfo[kcud1]}" history-substring-search-down
  # The prompt can be visible before application keypad mode is enabled.
  bindkey $'\e[A' history-substring-search-up
  bindkey $'\e[B' history-substring-search-down
  if zmodload -e zsh/complist; then
    # An unselected list uses the editor keymap. Active selection and paged
    # lists use their own keymaps and already know how to handle send-break.
    zle -N _dotsh_dismiss_completion_list
    zle -N _dotsh_dismiss_completion_list_vi _dotsh_dismiss_completion_list
    bindkey -M emacs '^[' _dotsh_dismiss_completion_list
    bindkey -M viins '^[' _dotsh_dismiss_completion_list_vi
    bindkey -M vicmd '^[' _dotsh_dismiss_completion_list
    bindkey -M menuselect '^[' send-break
    bindkey -M listscroll '^[' send-break
  fi
  if [[ $widgets[zle-line-init] == user:zle-line-init ]]; then
    zle zle-line-init
  fi
  if (( $+functions[_dotsh_mise_init_completion] && $+functions[compdef] )); then
    _dotsh_mise_init_completion
  fi
}
autoload -Uz add-zle-hook-widget
add-zle-hook-widget line-init _dotsh_init_first_zle_line

(( $+commands[python3] )) && alias python='command python3'

# Bracketed paste on: multi-line pastes do NOT auto-run
set zle_bracketed_paste
ZSH_AUTOSUGGEST_CLEAR_WIDGETS+=(bracketed-paste)

# Disable spelling correction for command names and arguments.
unsetopt CORRECT CORRECT_ALL

# GPG / PINENTRY
[[ -t 0 && -n $TTY ]] && export GPG_TTY=$TTY

## Long running processes should return time after they complete. Specified
## in seconds.
REPORTTIME=${REPORTTIME:-2}
TIMEFMT="%U user %S system %P cpu %*Es total"



# On startup print the current SSH keys (disable with: zstyle ':dotsh:ssh-local' show-ids no)
if zstyle -T ':dotsh:ssh-local' show-ids; then
  ssh-ids
  print
fi


_dotsh_startup_ssh_close

# >>> lig post >>>
#eval "$("/Users/michele/.local/bin/lig" init zsh post)"
# <<< lig post <<<
# Autosuggestions otherwise waits for the next real precmd to bind widgets.
# Its dependencies and Lig's widget hooks have run when this task executes.
if (( $+functions[zsh-defer] )); then
  zsh-defer -m -p -c '(( ! $+functions[_zsh_autosuggest_start] )) || _zsh_autosuggest_start'
fi

if [[ -f ${HOME}/.dotsh-zprof-enabled ]]; then
  zprof
fi
#LIG POST Must BE HERE
# >>> ligss post >>>
if [[ -o interactive && ! -v ZSH_EXECUTION_STRING && -z ${LIG_DISABLE-} &&
      -n ${LIG_TTY-} && "$LIG_TTY" == "$TTY" ]] && (( $+commands[lig] && $+functions[zsh-defer] )); then
  # Antidote queues autosuggestions and highlighting before Lig's ZLE hooks.
  zsh-defer -m -p _cached_eval "$commands[lig]" init zsh post
fi
# <<< ligss post <<<




