# Preserve the native macOS Git completion, which includes grouped refs,
# recent commits and descriptions that Homebrew's Bash-backed completion omits.
if (( $+commands[git] )); then
	if [[ $OSTYPE == darwin* ]]; then
  		typeset _dotsh_native_git_completion="/usr/share/zsh/$ZSH_VERSION/functions/_git"
  		typeset _dotsh_completion_dir="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/completions"

  		if [[ -r $_dotsh_native_git_completion ]]; then
  		  mkdir -p "$_dotsh_completion_dir"
  		  ln -sf "$_dotsh_native_git_completion" "$_dotsh_completion_dir/_git"
  		fi

  		unset _dotsh_native_git_completion _dotsh_completion_dir
	fi

	zstyle ':completion:*:*:git-checkout:*:*' group-order local-branches remote-branches tags
	zstyle ':completion:*:local-branches' list-colors '=*=38;5;78'
	zstyle ':completion:*:local-branches' sort false
	zstyle ':completion:*:remote-branches' list-colors '=*=38;5;141'
	zstyle ':completion:*:commits' sort false
	zstyle ':completion:*:tags' list-colors '=*=38;5;214'

	zstyle ':completion:*:*:git*:*:descriptions' \
	  format '%F{yellow}[%d]%f'
	zstyle ':completion:*:git-checkout:*' sort false
	# Colore delle opzioni e dei riferimenti Git
	zstyle ':completion:*:*:git*:*' list-colors \
	  '=(#b)(--*)=0=36' \
	  '=(#b)(-*)=0=36' \
	  '=(#b)(origin/*)=0=35' \
	  '=(#b)(upstream/*)=0=33' \
	  '=(#b)(HEAD*)=0=31' \
	  '=(#b)(*)=0=32'

	## Restore the full Git candidate set after runtime initialization.
	#zstyle -d ':completion:*:git-*:argument-rest:heads' ignored-patterns
	#zstyle -d ':completion:*:git-*:argument-rest:heads-local' ignored-patterns
	#zstyle -d ':completion:*:git-*:argument-rest:heads-remote' ignored-patterns
	#zstyle -d ':completion:*:git-*:argument-rest:commits' ignored-patterns
	#zstyle -d ':completion:*:git-*:argument-rest:commit-objects' ignored-patterns
	#zstyle -d ':completion:*:git-*:argument-rest:recent-branches' ignored-patterns
fi
