#!/bin/sh

set -eu
DOTFILES_REF=${DOTFILES_REF:-main}
DOTFILES_REPO_URL=${DOTFILES_REPO_URL:-https://github.com/michelemadonna/dotfiles-nomad.git}

usage() {
  printf 'Usage: %s [remote [branch]|local]\n' "$0" >&2
}

source_mode=${1:-remote}
image_name=${DOCKER_IMAGE:-dotfiles-nomad-demo}

case $source_mode in
  remote)
    [ "$#" -le 2 ] || { usage; exit 2; }
    DOTFILES_REF=${2:-$DOTFILES_REF}
    docker build \
      --no-cache-filter dotfiles-remote \
      --build-arg "DOTFILES_REF=$DOTFILES_REF" \
      --build-arg "DOTFILES_REPO_URL=$DOTFILES_REPO_URL" \
      -t "$image_name" .
    ;;
  local)
    [ "$#" -le 1 ] || { usage; exit 2; }
    docker build \
      --build-arg DOTFILES_SOURCE=local \
      -t "$image_name" .
    ;;
  *)
    usage
    exit 2
    ;;
esac
exec docker run --rm -it "$image_name"
