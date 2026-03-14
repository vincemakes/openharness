# OpenHarness install module

oh_install() {
  local platform="${1:-}"

  case "$platform" in
    claude-code)
      oh_install_claude_code
      ;;
    codex)
      oh_install_codex
      ;;
    --help|-h|"")
      echo "Usage: openharness install <claude-code|codex>"
      ;;
    *)
      echo "openharness install: unknown platform '$platform'" >&2
      echo "Supported: claude-code, codex" >&2
      exit 1
      ;;
  esac
}

oh_install_claude_code() {
  local claude_dir="$HOME/.claude"

  echo "Installing OpenHarness for Claude Code..."
  echo ""
  echo "OpenHarness hooks are configured per-project via .claude/settings.local.json."
  echo "Run 'openharness init' in each project to set up hooks automatically."
  echo ""

  # Add openharness to PATH hint
  local bin_dir="$OPENHARNESS_ROOT/bin"
  echo "To use the 'openharness' command globally, add to your shell profile:"
  echo ""
  echo "  export PATH=\"$bin_dir:\$PATH\""
  echo ""
  echo "Then restart your shell and Claude Code."
}

oh_install_codex() {
  local codex_dir="$HOME/.codex/openharness"

  echo "Installing OpenHarness for Codex..."

  mkdir -p "$HOME/.codex"

  if [ -L "$codex_dir" ]; then
    rm "$codex_dir"
  elif [ -d "$codex_dir" ]; then
    echo "Warning: $codex_dir already exists as a directory." >&2
    echo "Remove it manually and re-run install if needed." >&2
    return 1
  fi

  ln -s "$OPENHARNESS_ROOT" "$codex_dir"

  echo "Installed: $codex_dir -> $OPENHARNESS_ROOT"
  echo ""
  echo "Next steps:"
  echo "  1. Restart Codex"
  echo "  2. cd into your project and run: openharness init"
}
