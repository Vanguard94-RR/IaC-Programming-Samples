#!/usr/bin/env bash
set -euo pipefail

# Usage: ./uninstall.sh [prefix]
PREFIX=${1:-"${HOME}/.gnp-tools"}
ALIAS_SH="$PREFIX/aliases.sh"
BIN_DIR="$PREFIX/bin"

echo "Uninstalling Proyecto-Tools from: $PREFIX"

# Remove aliases.sh and config
if [ -f "$ALIAS_SH" ]; then
  rm -f "$ALIAS_SH"
  echo "Removed $ALIAS_SH"
fi

if [ -f "$PREFIX/aliases.conf" ]; then
  rm -f "$PREFIX/aliases.conf"
  echo "Removed $PREFIX/aliases.conf"
fi

# Remove installed binaries and symlinks
if [ -d "$BIN_DIR" ]; then
  for f in "$BIN_DIR"/*; do
    [ -e "$f" ] || continue
    rm -f "$f"
    echo "Removed $f"
    rm -f "${HOME}/.local/bin/$(basename "$f")" || true
  done
  rmdir --ignore-fail-on-non-empty "$BIN_DIR" 2>/dev/null || true
fi

# attempt to remove PREFIX root if empty
rmdir --ignore-fail-on-non-empty "$PREFIX" 2>/dev/null || true

# Remove Proyecto-Tools marker blocks from rc files
RC_FILES=("${HOME}/.bash_aliases" "${HOME}/.bashrc" "${HOME}/.profile" "${HOME}/.zshrc")
MARKER_START="# >>> Proyecto-Tools start >>>"
MARKER_END="# <<< Proyecto-Tools end <<<"
for rc in "${RC_FILES[@]}"; do
  if [ -f "$rc" ]; then
    cp -n "$rc" "$rc.proyecto_tools.uninstall.bak" 2>/dev/null || true
    # delete the block between markers inclusive
    awk -v s="$MARKER_START" -v e="$MARKER_END" 'BEGIN{inside=0} {if(index($0,s)==1){inside=1; next} if(index($0,e)==1){inside=0; next} if(!inside) print $0}' "$rc" > "$rc.tmp" && mv "$rc.tmp" "$rc"
  # also remove any single-line source entries referencing aliases.sh
  awk '!/aliases\.sh/' "$rc" > "$rc.tmp" && mv "$rc.tmp" "$rc"
  # and remove stray Proyecto-Tools comment lines
  awk '!/Proyecto-Tools: load custom aliases/' "$rc" > "$rc.tmp" && mv "$rc.tmp" "$rc"
    echo "Cleaned $rc"
  fi
done

echo "Uninstall complete. You may want to restart your shell or source your rc file."
