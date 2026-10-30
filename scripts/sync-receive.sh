#!/usr/bin/env bash
# The Pi half of scripts/sync-to-pi.ps1 (do not run it by hand): replace ~/<dest> with the freshly
# unpacked copy in ~/<staging>, keeping what exists only on the Pi, so files deleted or renamed in
# the repo do not linger there.
#   kept:   ansible/inventory/group_vars/all/vault.yml (generated on the Pi, never in git)
#   merged: ansible/files/packages/ (packages downloaded on the Pi; a synced copy wins)
set -euo pipefail

[ $# -eq 2 ] || { echo "usage: $0 <staging dir> <dest dir>, both relative to \$HOME" >&2; exit 2; }
cd "$HOME"
stage=$1
dest=$2
# Both get rm -rf / mv below, so accept only the shapes sync-to-pi.ps1 sends: dest a plain name
# under $HOME starting with a letter or digit (never empty, ., .. or a path), stage under ~/.cache.
case $dest in
  '' | [!A-Za-z0-9]* | *[!A-Za-z0-9._-]*) echo "refusing destination '$dest'" >&2; exit 2 ;;
esac
case $stage in
  .cache/[A-Za-z0-9]*) ;;
  *) echo "refusing staging dir '$stage'" >&2; exit 2 ;;
esac
case $stage in
  */.* | *[!A-Za-z0-9./_-]*) echo "refusing staging dir '$stage'" >&2; exit 2 ;;
esac
keep=ansible/inventory/group_vars/all/vault.yml
merge=ansible/files/packages

[ -d "$stage/ansible" ] || { echo "$stage does not look like the repo" >&2; exit 1; }

if [ -d "$dest" ]; then
  if [ -e "$dest/$keep" ] && [ ! -e "$stage/$keep" ]; then
    mkdir -p "$(dirname "$stage/$keep")"
    cp -p "$dest/$keep" "$stage/$keep"
  fi
  if [ -d "$dest/$merge" ]; then
    mkdir -p "$stage/$merge"
    cp -pR --update=none "$dest/$merge/." "$stage/$merge/"
  fi
  rm -rf "$dest.old"
  mv "$dest" "$dest.old"
fi
mv "$stage" "$dest"
rm -rf "$dest.old"
echo "synced into ~/$dest"
