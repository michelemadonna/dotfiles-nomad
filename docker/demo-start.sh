#!/bin/sh

set -eu

generate_demo_key() {
  key_type=$1
  passphrase=$2
  key_path="$HOME/.ssh/id_$key_type"

  if [ -e "$key_path" ] || [ -L "$key_path" ] ||
     [ -e "$key_path.pub" ] || [ -L "$key_path.pub" ]; then
    return 0
  fi

  ssh-keygen -q -t "$key_type" -N "$passphrase" \
    -C "dotfiles-demo-$key_type" -f "$key_path"
}

cd "$HOME/.dotfiles"
test -f ./install.sh
sh ./install.sh
cd "$HOME"

# The wizard also exits successfully when the user quits without installing.
if [ -f "$HOME/.zshenv" ]; then
  generate_demo_key ed25519 ''
  generate_demo_key ecdsa ''
  generate_demo_key rsa '123'
fi

printf '\n\033[1;33m%s\n%s\n%s\n%s\033[0m\n\n' \
  '+----------------------------------------------------------+' \
  '| KNOWN DOCKER PREVIEW BUG                                 |' \
  '| Press Ctrl-P twice to cycle the preview layout.          |' \
  '+----------------------------------------------------------+'
exec zsh -l
