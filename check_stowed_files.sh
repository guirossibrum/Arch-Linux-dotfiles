#!/bin/bash

# Check stowed files and folders from ~/dotfiles

STOW_DIR="$HOME/dotfiles"
cd "$STOW_DIR" || exit

# Scan all symlinks in HOME once and store in LINKS array
mapfile -t LINKS < <(find "$HOME" -type l 2>/dev/null | while read l; do
    t=$(readlink -f "$l")
    [[ "$t" == "$STOW_DIR"* ]] && echo "$l $t"
  done)

# Loop through packages
for pkg in *; do
  [ -d "$pkg" ] || continue
  echo "=== $pkg ==="
  found=0
  for entry in "${LINKS[@]}"; do
    link="${entry%% *}"
    target="${entry#* }"
    if [[ "$target" == "$STOW_DIR/$pkg"* ]]; then
      found=1
      [ -d "$link" ] && echo "  FOLDED: $link -> $target" || echo "  FILE: $link -> $target"
    fi
  done
  ((found==0)) && echo ""
  echo ""
  done
