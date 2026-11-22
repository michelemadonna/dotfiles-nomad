#!/bin/sh
# Build the pinned Lig with the local startup cursor fix.
set -eu

dotfiles_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
packages="$dotfiles_dir/zsh/vendor/packages"
commit=e2afb2899161df8e0d2127ec5bfafcb503b9c137
checksum=82746f16a9d94768265aec2bd2cbea29c0d52f10ac59aa84d77225e0abae1d48
build="$packages/.lig-build"
[ -n "${HOME:-}" ] || { printf 'Error: HOME is not set.\n' >&2; exit 1; }
target="$HOME/.local/bin/lig"
mkdir -p "$build"

stage=$(mktemp -d "$build/stage.XXXXXXXX")
publish=
trap 'rm -rf -- "$stage"; if [ -n "$publish" ]; then rm -f -- "$publish"; fi' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

archive="$build/$commit.tar.gz"
verify_archive() {
    printf '%s  %s\n' "$checksum" "$1" | shasum -a 256 -c - >/dev/null
}
if [ ! -r "$archive" ] || ! verify_archive "$archive"; then
    curl --fail --location --silent --show-error --retry 2 \
        "https://codeload.github.com/KevenGoncalves/lig/tar.gz/$commit" \
        --output "$stage/lig.tar.gz"
    verify_archive "$stage/lig.tar.gz"
    mv -f "$stage/lig.tar.gz" "$archive"
fi
mkdir "$stage/source"
tar -xzf "$archive" -C "$stage/source" --strip-components=1
(
    cd "$stage/source"
    # Apply paths relative to Lig's sources, outside the dotfiles Git index.
    export GIT_CEILING_DIRECTORIES="$stage"
    git apply --check "$dotfiles_dir/zsh/vendor/patches/lig-1.4.0-startup-cursor.patch"
    git apply "$dotfiles_dir/zsh/vendor/patches/lig-1.4.0-startup-cursor.patch"
    CARGO_HOME="$build/cargo" CARGO_TARGET_DIR="$build/target" \
        cargo build --locked --release
)

candidate="$build/target/release/lig"
[ "$("$candidate" --version)" = 'lig 1.4.0' ]
for part in pre post; do
    "$candidate" init zsh "$part" > "$stage/$part.zsh"
    zsh -fn "$stage/$part.zsh"
done
mkdir -p "${target%/*}"
publish=$(mktemp "${target%/*}/.lig.XXXXXXXX")
install -m 755 "$candidate" "$publish"
mv -f "$publish" "$target"
printf 'Installed %s\n' "$target"
