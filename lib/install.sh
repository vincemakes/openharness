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
  local plugins_dir="$claude_dir/plugins"
  local cache_dir="$plugins_dir/cache/openharness-local/openharness/0.1.0"
  local registry="$plugins_dir/installed_plugins.json"
  local settings="$claude_dir/settings.json"
  local plugin_key="openharness@openharness-local"

  echo "Installing OpenHarness for Claude Code..."

  # Create cache directory
  mkdir -p "$cache_dir"

  # Symlink the openharness source into the cache location
  # Remove existing if present
  if [ -L "$cache_dir" ]; then
    rm "$cache_dir"
    mkdir -p "$(dirname "$cache_dir")"
  elif [ -d "$cache_dir" ]; then
    rm -rf "$cache_dir"
  fi

  ln -s "$OPENHARNESS_ROOT" "$cache_dir"

  echo "  Cached: $cache_dir -> $OPENHARNESS_ROOT"

  # Update installed_plugins.json
  mkdir -p "$plugins_dir"
  local now
  now="$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")"
  local git_sha
  git_sha="$(cd "$OPENHARNESS_ROOT" && git rev-parse HEAD 2>/dev/null || echo "local")"

  if [ -f "$registry" ]; then
    # Check if already registered
    if grep -q "$plugin_key" "$registry" 2>/dev/null; then
      echo "  Registry: already registered"
    else
      # Append to existing plugins object — insert before the closing braces
      # This is fragile but avoids jq dependency
      local entry
      entry="\"$plugin_key\":[{\"scope\":\"user\",\"installPath\":\"$cache_dir\",\"version\":\"0.1.0\",\"installedAt\":\"$now\",\"lastUpdated\":\"$now\",\"gitCommitSha\":\"$git_sha\"}]"

      # Use sed to insert before the last closing brace of "plugins"
      # Find the line with the second-to-last } and add a comma + entry
      sed -i.bak "s|\"plugins\"[[:space:]]*:[[:space:]]*{|\"plugins\":{$entry,|" "$registry"
      rm -f "${registry}.bak"
      echo "  Registry: updated $registry"
    fi
  else
    cat > "$registry" <<EOJSON
{
  "version": 2,
  "plugins": {
    "$plugin_key": [
      {
        "scope": "user",
        "installPath": "$cache_dir",
        "version": "0.1.0",
        "installedAt": "$now",
        "lastUpdated": "$now",
        "gitCommitSha": "$git_sha"
      }
    ]
  }
}
EOJSON
    echo "  Registry: created $registry"
  fi

  # Update settings.json to enable the plugin
  if [ -f "$settings" ]; then
    if grep -q "$plugin_key" "$settings" 2>/dev/null; then
      echo "  Settings: already enabled"
    else
      if grep -q '"enabledPlugins"' "$settings" 2>/dev/null; then
        # Add to existing enabledPlugins
        sed -i.bak "s|\"enabledPlugins\"[[:space:]]*:[[:space:]]*{|\"enabledPlugins\":{\"$plugin_key\":true,|" "$settings"
        rm -f "${settings}.bak"
      else
        # Add enabledPlugins section before last }
        sed -i.bak "s|}$|,\"enabledPlugins\":{\"$plugin_key\":true}}|" "$settings"
        rm -f "${settings}.bak"
      fi
      echo "  Settings: enabled in $settings"
    fi
  else
    cat > "$settings" <<EOJSON
{
  "enabledPlugins": {
    "$plugin_key": true
  }
}
EOJSON
    echo "  Settings: created $settings"
  fi

  echo ""
  echo "Installed. Restart Claude Code to activate."
  echo "Then: cd into your project and run 'openharness init'"
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
