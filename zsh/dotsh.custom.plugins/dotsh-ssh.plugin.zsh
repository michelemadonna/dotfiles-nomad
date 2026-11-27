## Start or reuse an SSH agent and load local private keys. Homebrew keychain is
## optional; when it isn't installed, keep the agent environment in ~/.ssh.
#function load-our-ssh-keys() {
#	emulate -L zsh
#	setopt local_options no_unset
#
#	local agent_file=$HOME/.ssh/ssh-agent
#	local agent_status agent_keys key fingerprint fingerprint_line
#	local -a ssh_add_options
#	local -a keys
#	typeset -g _DOTSH_SSH_KEYS=
#	typeset -gi _DOTSH_SSH_KEYS_STATUS=2
#	typeset -gi _DOTSH_SSH_KEYS_VALID=0
#
#	# A fake HOME must not reuse host agents or import keys from macOS Keychain.
#	if (( $+commands[keychain] )) && [[ ${DOTFILES_FAKE_HOME:-} != $HOME ]]; then
#		eval "$(keychain -q --eval)" || return
#		agent_keys=$(ssh-add -l 2>/dev/null)
#		agent_status=$?
#	else
#		mkdir -p -- "$HOME/.ssh" || return
#		chmod 700 -- "$HOME/.ssh" 2>/dev/null
#
#		agent_keys=$(ssh-add -l 2>/dev/null)
#		agent_status=$?
#		if (( agent_status == 2 )) && [[ -r $agent_file ]]; then
#			source "$agent_file"
#			agent_keys=$(ssh-add -l 2>/dev/null)
#			agent_status=$?
#		fi
#
#		if (( agent_status == 2 )); then
#			eval "$(ssh-agent -s)" >/dev/null || return
#			{
#				print -r -- "export SSH_AUTH_SOCK=${(q)SSH_AUTH_SOCK}"
#				print -r -- "export SSH_AGENT_PID=${(q)SSH_AGENT_PID}"
#			} >| "$agent_file"
#			chmod 600 -- "$agent_file" 2>/dev/null
#			agent_keys=
#			agent_status=1
#		fi
#	fi
#
#	(( agent_status == 2 )) && return 1
#	_DOTSH_SSH_KEYS=$agent_keys
#	_DOTSH_SSH_KEYS_STATUS=$agent_status
#	(( agent_status == 0 )) && _DOTSH_SSH_KEYS_VALID=1
#
#	if (( agent_status == 1 )); then
#		if [[ $OSTYPE == darwin* && ${DOTFILES_FAKE_HOME:-} != $HOME ]]; then
#			if (( $+commands[sw_vers] )) && (( ${$(sw_vers -productVersion)%%.*} >= 12 )); then
#				ssh-add --apple-load-keychain >/dev/null 2>&1
#			else
#				ssh-add -qA >/dev/null 2>&1
#			fi
#			agent_keys=$(ssh-add -l 2>/dev/null)
#			agent_status=$?
#			_DOTSH_SSH_KEYS=$agent_keys
#			_DOTSH_SSH_KEYS_STATUS=$agent_status
#			(( agent_status == 0 )) && _DOTSH_SSH_KEYS_VALID=1
#		fi
#
#		keys=(~/.ssh/**/*id_(rsa|dsa|ecdsa|ed25519)(N.))
#		for key in $keys; do
#			fingerprint_line=$(ssh-keygen -l -f "$key" 2>/dev/null) || continue
#			fingerprint=${${(z)fingerprint_line}[2]}
#			[[ -n $fingerprint ]] || continue
#			ssh_add_options=(-q)
#			if [[ $OSTYPE == darwin* ]]; then
#				if (( $+commands[sw_vers] )) && (( ${$(sw_vers -productVersion)%%.*} >= 12 )); then
#					ssh_add_options+=(--apple-use-keychain)
#				else
#					ssh_add_options+=(-K)
#				fi
#			fi
#			if [[ $agent_keys != *"$fingerprint"* ]] && ssh-add $ssh_add_options -- "$key"; then
#				agent_keys+=$'\n'$fingerprint
#				_DOTSH_SSH_KEYS_VALID=0
#			fi
#		done
#	fi
#}
#
#if [[ -o interactive && -z ${SSH_CLIENT-} && -z ${SSH_CONNECTION-} &&
#      ${DOTSH_SSH_LOAD_KEY:-true} != false ]]; then
#	[[ ${DOTSH_SSH_ASKPASS_REQUIRE:-false} != true ]] || export SSH_ASKPASS_REQUIRE=force
#	load-our-ssh-keys
#fi
#
#if [[ ${DOTSH_SSH_SHOW_KEY:-false} == true ]]; then
#	print
#	print 'Current SSH Keys:'
#	if (( ${_DOTSH_SSH_KEYS_VALID:-0} )) && (( ${_DOTSH_SSH_KEYS_STATUS:-2} == 0 )); then
#		print -r -- "$_DOTSH_SSH_KEYS"
#	else
#		ssh-add -l
#	fi
#	print
#fi
#unset _DOTSH_SSH_KEYS _DOTSH_SSH_KEYS_STATUS _DOTSH_SSH_KEYS_VALID
#

# SSH-AGENT (macOS Keychain, Linux Desktop Keyring/KWallet, Server SSH)
# Oh My Zsh's ssh-agent plugin is loaded standalone through Antidote, so define
# the host key that Oh My Zsh normally prepares in its full framework startup.
: "${SHORT_HOST:=${HOST%%.*}}"

if [[ -z "$SSH_CONNECTION" && -n "$DISPLAY$WAYLAND_DISPLAY" ]]; then
  for _s in "${XDG_RUNTIME_DIR}/keyring/ssh" "${XDG_RUNTIME_DIR}/gcr/ssh" "${XDG_RUNTIME_DIR}/ssh-agent.socket"; do
    [[ -S "$_s" ]] && export SSH_AUTH_SOCK="$_s" && break
  done; unset _s
  for _ask in ksshaskpass seahorse-ssh-askpass gnome-ssh-askpass; do
    if (( $+commands[$_ask] )); then
      export SSH_ASKPASS="${commands[$_ask]}"
      [[ ${SSH_ASKPASS_REQUIRE:-} == force ]] || export SSH_ASKPASS_REQUIRE=prefer
      break
    fi
  done; unset _ask
fi

# Print the current SSH keys in memory, and load any local private keys into the agent
ssh-ids() {
  print '\nCurrent SSH Keys:'
  if [[ -n ${_dotsh_startup_ssh_fd-} && -S ${SSH_AUTH_SOCK-} &&
        $SSH_AUTH_SOCK == $_dotsh_startup_ssh_socket ]]; then
    local reply
    IFS= read -r -d '' -u "$_dotsh_startup_ssh_fd" reply || :
    reply=${reply%$'\n'}
    case ${reply##*$'\n'} in
      0) print -r -- "${${reply%$'\n'*}%$'\n'}"; return 0 ;;
      <->) print -P "%F{yellow}No SSH Keys in memory (lazy loading).%f"; return 0 ;;
    esac
  fi
  if [[ ! -S ${SSH_AUTH_SOCK-} ]] || ! ssh-add -l 2>/dev/null; then
    print -P "%F{yellow}No SSH Keys in memory (lazy loading).%f"
  fi
}

# Force the SSH agent to load all local private keys, including those in macOS Keychain.
ssh-load() {
  if [[ "$OSTYPE" == darwin* ]]; then
    ssh-add --apple-load-keychain 2>/dev/null || ssh-add --apple-use-keychain 2>/dev/null || ssh-add -A 2>/dev/null
  else
    ssh-add
  fi
  ssh-ids
}

# On startup print the current SSH keys (disable with: zstyle ':dotsh:ssh-local' show-ids no)
if zstyle -T ':dotsh:ssh-local' show-ids; then
  ssh-ids
fi
