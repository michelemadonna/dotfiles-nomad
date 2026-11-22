#!/usr/bin/env zsh

# Standalone fzf binary only. Installation is explicit; shell startup never
# downloads or builds anything, and this plugin does not configure keybindings.

dotsh-fzf-install() {
  emulate -L zsh

  local version=0.74.5 os arch asset checksum url stage archive candidate target
  os=$(command uname -s) || return 1
  arch=$(command uname -m) || return 1

  case "$os:$arch" in
    Darwin:x86_64|Darwin:amd64)
      asset="fzf-$version-darwin_amd64.tar.gz"
      checksum=aca6cab692e6c069e724a43070a448e18586c7c0fdd1139f6d487ec1680599ed
      ;;
    Darwin:arm64|Darwin:aarch64)
      asset="fzf-$version-darwin_arm64.tar.gz"
      checksum=ada808c7401b9949ce8842274ac16a6b6193fd32dcada396884a6a9a89e5985a
      ;;
    Linux:x86_64|Linux:amd64)
      asset="fzf-$version-linux_amd64.tar.gz"
      checksum=d47d7f882972c7d674dbbba998ffa4116e68379616ffac7695d0671e9a722c5f
      ;;
    Linux:aarch64|Linux:arm64)
      asset="fzf-$version-linux_arm64.tar.gz"
      checksum=cf058001da21724a469b714a29cf4aab9cbe860d218a0d6c1b5b661efad7784c
      ;;
    *)
      print -ru2 -- "dotsh-fzf: unsupported platform: $os $arch"
      return 1
      ;;
  esac

  (( $+commands[curl] )) || {
    print -ru2 -- 'dotsh-fzf: curl is required to download fzf.'
    return 1
  }
  (( $+commands[tar] )) || {
    print -ru2 -- 'dotsh-fzf: tar is required to unpack fzf.'
    return 1
  }

  stage=$(command mktemp -d "${TMPDIR:-/tmp}/dotsh-fzf.XXXXXXXX") || return 1
  {
    archive="$stage/$asset"
    url="https://github.com/junegunn/fzf/releases/download/v$version/$asset"
    command curl --fail --location --silent --show-error --retry 2 \
      "$url" --output "$archive" || return 1

    if (( $+commands[sha256sum] )); then
      print -r -- "$checksum  $archive" | command sha256sum -c - >/dev/null 2>&1 || {
        print -ru2 -- 'dotsh-fzf: downloaded archive failed SHA-256 verification.'
        return 1
      }
    elif (( $+commands[shasum] )); then
      print -r -- "$checksum  $archive" | command shasum -a 256 -c - >/dev/null 2>&1 || {
        print -ru2 -- 'dotsh-fzf: downloaded archive failed SHA-256 verification.'
        return 1
      }
    else
      print -ru2 -- 'dotsh-fzf: sha256sum or shasum is required to verify fzf.'
      return 1
    fi

    command tar -xzf "$archive" -C "$stage" fzf || return 1
    candidate="$stage/fzf"
    [[ -x $candidate ]] || {
      print -ru2 -- 'dotsh-fzf: release archive has no executable fzf binary.'
      return 1
    }
    case $("$candidate" --version) in
      "$version ("*) ;;
      *)
        print -ru2 -- 'dotsh-fzf: downloaded binary has an unexpected version.'
        return 1
        ;;
    esac

    target="$HOME/.local/bin/fzf"
    command mkdir -p "${target:h}" || return 1
    command cp "$candidate" "$target.tmp.$$" || return 1
    command chmod 755 "$target.tmp.$$" || return 1
    command mv -f "$target.tmp.$$" "$target" || return 1
  } always {
    command rm -rf -- "$stage"
  }

  rehash
  print -r -- "Installed fzf $version at $target"
}

# ~/.local/bin is added by .zshenv. Rehash when this deferred plugin runs so the
# command table also sees a binary installed during the current shell session.
(( $+commands[fzf] )) || rehash
