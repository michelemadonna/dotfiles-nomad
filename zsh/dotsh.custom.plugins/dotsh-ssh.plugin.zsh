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
#	typeset -g _ZQS_SSH_KEYS=
#	typeset -gi _ZQS_SSH_KEYS_STATUS=2
#	typeset -gi _ZQS_SSH_KEYS_VALID=0
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
#	_ZQS_SSH_KEYS=$agent_keys
#	_ZQS_SSH_KEYS_STATUS=$agent_status
#	(( agent_status == 0 )) && _ZQS_SSH_KEYS_VALID=1
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
#			_ZQS_SSH_KEYS=$agent_keys
#			_ZQS_SSH_KEYS_STATUS=$agent_status
#			(( agent_status == 0 )) && _ZQS_SSH_KEYS_VALID=1
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
#				_ZQS_SSH_KEYS_VALID=0
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
#	if (( ${_ZQS_SSH_KEYS_VALID:-0} )) && (( ${_ZQS_SSH_KEYS_STATUS:-2} == 0 )); then
#		print -r -- "$_ZQS_SSH_KEYS"
#	else
#		ssh-add -l
#	fi
#	print
#fi
#unset _ZQS_SSH_KEYS _ZQS_SSH_KEYS_STATUS _ZQS_SSH_KEYS_VALID
#

# 2. SSH-AGENT UNIVERSALE (macOS Keychain, Linux Desktop Keyring/KWallet, Server SSH)
# Oh My Zsh's ssh-agent plugin is loaded standalone through Antidote, so define
# the host key that Oh My Zsh normally prepares in its full framework startup.
: "${SHORT_HOST:=${HOST%%.*}}"

if [[ -z "$SSH_CONNECTION" && -n "$DISPLAY$WAYLAND_DISPLAY" ]]; then
  for _s in "${XDG_RUNTIME_DIR}/keyring/ssh" "${XDG_RUNTIME_DIR}/gcr/ssh" "${XDG_RUNTIME_DIR}/ssh-agent.socket"; do
    [[ -S "$_s" ]] && export SSH_AUTH_SOCK="$_s" && break
  done; unset _s
  for _ask in ksshaskpass seahorse-ssh-askpass gnome-ssh-askpass; do
    (( $+commands[$_ask] )) && export SSH_ASKPASS="${commands[$_ask]}" SSH_ASKPASS_REQUIRE=prefer && break
  done; unset _ask
fi

# 2.1 Stampa le chiavi SSH in memoria
ssh-ids() {
  print '\nCurrent SSH Keys:'
  if [[ ! -S ${SSH_AUTH_SOCK-} ]] || ! ssh-add -l 2>/dev/null; then
    print -P "%F{yellow}Nessuna chiave SSH in memoria (caricamento lazy).%f"
  fi
}

# 2.2 Forza il caricamento immediato delle chiavi nel Portachiavi
ssh-load() {
  if [[ "$OSTYPE" == darwin* ]]; then
    ssh-add --apple-load-keychain 2>/dev/null || ssh-add --apple-use-keychain 2>/dev/null || ssh-add -A 2>/dev/null
  else
    ssh-add
  fi
  ssh-ids
}

# 2.3 Stampa automatica all'avvio (disattivabile con: zstyle ':dotsh:ssh-local' show-ids no)
if zstyle -T ':dotsh:ssh-local' show-ids; then
  ssh-ids
fi