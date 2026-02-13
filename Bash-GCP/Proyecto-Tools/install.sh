#!/usr/bin/env bash
set -euo pipefail

# Usage: ./install.sh [prefix]
PREFIX=${1:-"${HOME}/.gnp-tools"}
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ALIAS_CONF_SRC="$HERE/tools/aliases.conf"
ALIAS_CONF_DST="$PREFIX/aliases.conf"
ALIAS_SH="$PREFIX/aliases.sh"
BIN_DIR="$PREFIX/bin"
LOCAL_BIN="${HOME}/.local/bin"
# Candidate rc files; include zshrc if present or if SHELL contains zsh
SHELL_RC_FILES=("${HOME}/.bash_aliases" "${HOME}/.bashrc" "${HOME}/.profile")
if [ -n "${ZSH_VERSION-}" ] || echo "${SHELL-}" | grep -q "zsh"; then
  SHELL_RC_FILES=("${HOME}/.zshrc" "${HOME}/.bashrc" "${HOME}/.profile")
else
  # also include zshrc as fallback
  SHELL_RC_FILES+=("${HOME}/.zshrc")
fi

echo "Installing Proyecto-Tools to: $PREFIX"
mkdir -p "$PREFIX"

if [ -f "$ALIAS_CONF_SRC" ]; then
  cp -f "$ALIAS_CONF_SRC" "$ALIAS_CONF_DST"
  echo "Copied aliases.conf to $ALIAS_CONF_DST"
else
  echo "Warning: no $ALIAS_CONF_SRC found - creating an empty aliases.conf"
  : > "$ALIAS_CONF_DST"
fi

echo "Generating $ALIAS_SH and placing binaries in $BIN_DIR"
mkdir -p "$BIN_DIR"
mkdir -p "$LOCAL_BIN"

# write atomically to a temp file then move into place to avoid partial writes
TMP_ALIASES="$(mktemp --tmpdir aliases.sh.XXXXXX)"
chmod 600 "$TMP_ALIASES"


while IFS= read -r line; do
  # strip whitespace
  line_trimmed=$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  # skip comments and empty
  if [[ -z "$line_trimmed" || "$line_trimmed" == \#* ]]; then
    continue
  fi
  if [[ "$line_trimmed" != *=* ]]; then
    echo "Skipping invalid line in aliases.conf: $line_trimmed"
    continue
  fi
  name=${line_trimmed%%=*}
  path=${line_trimmed#*=}
  # If path is relative, resolve relative to the tools directory first
  if [[ "$path" != /* ]]; then
    candidate="$HERE/$path"
  else
    candidate="$path"
  fi

  if [ ! -e "$candidate" ]; then
    # try relative to tools/ directory
    candidate="$HERE/tools/$path"
  fi

  if [ ! -e "$candidate" ]; then
    echo "Warning: target not found for $name -> $path (tried $candidate). Skipping." >&2
    continue
  fi

  # copy to PREFIX/bin to make installation portable
  bin_name=$(basename "$candidate")
  dst="$BIN_DIR/$bin_name"
  if [ ! -e "$dst" ] || ! cmp -s "$candidate" "$dst"; then
    cp -f "$candidate" "$dst"
    chmod +x "$dst"
    echo "Installed $dst"
  fi

  # create function that calls the copied binary
  cat >> "$TMP_ALIASES" <<EOF
$name() {
  "$dst" "\$@"
}
EOF
done < "$ALIAS_CONF_DST"

# Also install all executables found in the project's bin/ directory
PROJECT_BIN="$HERE/bin"
if [ -d "$PROJECT_BIN" ]; then
  for f in "$PROJECT_BIN"/*; do
    [ -e "$f" ] || continue
    if [ -f "$f" ] && [ -x "$f" ]; then
      base=$(basename "$f")
      # strip single .sh extension for alias name convenience
      if [[ "$base" == *.sh ]]; then
        name="${base%.sh}"
      else
        name="$base"
      fi
      dst="$BIN_DIR/$base"
      if [ ! -e "$dst" ] || ! cmp -s "$f" "$dst"; then
        cp -f "$f" "$dst"
        chmod +x "$dst"
        echo "Installed $dst from project bin"
      fi

      # avoid duplicate alias names in the generated aliases file
      if ! grep -Fq "$name() {" "$TMP_ALIASES"; then
        cat >> "$TMP_ALIASES" <<EOF
$name() {
  "$dst" "\$@"
}
EOF
      else
        echo "Alias $name already defined; skipping project bin entry"
      fi
    fi
  done
fi
# move temp aliases into place atomically
mv "$TMP_ALIASES" "$ALIAS_SH"
chmod 644 "$ALIAS_SH"

echo "Ensuring shell rc sources $ALIAS_SH and that $LOCAL_BIN is in PATH"
MARKER_START="# >>> Proyecto-Tools start >>>"
MARKER_END="# <<< Proyecto-Tools end <<<"
SOURCE_BLOCK="$MARKER_START\n# Load Proyecto-Tools aliases\nif [ -f \"$ALIAS_SH\" ]; then . \"$ALIAS_SH\"; fi\nMARKER_END"

for rc in "${SHELL_RC_FILES[@]}"; do
  if [ -f "$rc" ]; then
    RC_USED="$rc"
    # create a backup first (only if not already backed up in this run)
    cp -n "$rc" "$rc.proyecto_tools.bak" 2>/dev/null || true
    # remove any previous single-line source referencing the aliases file to avoid duplicates
    if grep -Fq "$ALIAS_SH" "$rc"; then
      cp -n "$rc" "$rc.proyecto_tools.bak" 2>/dev/null || true
      awk -v a="$ALIAS_SH" 'index($0,a)==0 {print}' "$rc" > "$rc.tmp" && mv "$rc.tmp" "$rc"
      echo "Removed legacy single-line source from $rc"
    fi

    # also remove stray Proyecto-Tools comment lines that might have been left behind
    if grep -Fq "Proyecto-Tools: load custom aliases" "$rc"; then
      cp -n "$rc" "$rc.proyecto_tools.bak" 2>/dev/null || true
      awk '!/Proyecto-Tools: load custom aliases/' "$rc" > "$rc.tmp" && mv "$rc.tmp" "$rc"
      echo "Removed stray Proyecto-Tools comment lines from $rc"
    fi

    if ! grep -Fq "$MARKER_START" "$rc"; then
      # append marker block
      printf "\n%s\n# Proyecto-Tools: load custom aliases\nif [ -f \"%s\" ]; then . \"%s\"; fi\n%s\n" "$MARKER_START" "$ALIAS_SH" "$ALIAS_SH" "$MARKER_END" >> "$rc"
      echo "Appended Proyecto-Tools block to $rc"
    else
      echo "Proyecto-Tools block already present in $rc"
    fi
    break
  fi
done

# Ensure $LOCAL_BIN is in PATH via ~/.profile if not present
if ! echo "$PATH" | tr ':' '\n' | grep -Fxq "$LOCAL_BIN"; then
  if [ -f "${HOME}/.profile" ]; then
    cp -n "${HOME}/.profile" "${HOME}/.profile.proyecto_tools.bak" 2>/dev/null || true
    if ! grep -Fq "$LOCAL_BIN" "${HOME}/.profile"; then
      printf "\n# Proyecto-Tools: add local bin to PATH\nexport PATH=\"%s:\$PATH\"\n" "$LOCAL_BIN" >> "${HOME}/.profile"
      echo "Added $LOCAL_BIN to PATH in ~/.profile"
    fi
  fi
fi

# Also create a symlink for each installed bin into ~/.local/bin so user can call directly
for f in "$BIN_DIR"/*; do
  [ -e "$f" ] || continue
  ln -sf "$f" "$LOCAL_BIN/$(basename "$f")"
done

# If the script is being sourced, source the rc file in the current shell so aliases are
# immediately available. If it's executed, try to open a new shell (interactive) to pick
# up changes, unless NO_SHELL is set (used for non-interactive runs/tests).
is_sourced=0
if [ "${BASH_SOURCE[0]:-}" != "$0" ]; then
  is_sourced=1
fi

if [ "$is_sourced" -eq 1 ]; then
  # we're in the user's shell; source the rc used (preferred) or aliases.sh
  if [ -n "${RC_USED-}" ] && [ -f "$RC_USED" ]; then
    echo "Sourcing $RC_USED in current shell..."
    # shellcheck source=/dev/null
    . "$RC_USED"
  else
    echo "Sourcing $ALIAS_SH in current shell..."
    # shellcheck source=/dev/null
    . "$ALIAS_SH"
  fi
else
  # Not sourced. If interactive and allowed, replace the process with user's shell so the
  # new shell will load updated rc files. If NO_SHELL is set, skip this behavior.
  if [ -t 1 ] && [ -z "${NO_SHELL-}" ]; then
    # Do NOT exec the user's shell automatically; that will cause their rc files
    # to run and may produce errors if those rc files source missing files.
    echo "Note: installer will NOT open a new shell automatically to avoid running your shell rc files."
    echo "To activate aliases in your current shell, run:" 
    echo "  source '$ALIAS_SH'"
    echo "Or, to start a clean interactive shell that only loads the generated aliases (safer):"
    echo "  bash --noprofile --norc -i -c '. '$ALIAS_SH'; exec bash -i'"
  else
    echo "To activate aliases in your current shell run: source '$ALIAS_SH' or restart your shell."
  fi
fi

echo "Install complete. Please start a new shell or run: source $ALIAS_SH"
