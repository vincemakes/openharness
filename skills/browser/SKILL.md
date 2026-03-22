---
name: browser
description: Use when performing browser-based verification or testing. Provides a self-contained headless browser via the $B command variable. Supports navigation, interaction, screenshots, accessibility snapshots, and more.
---

# Browser — Self-Contained Headless Browser

You have access to a fast headless Chromium browser via the `$B` variable. Each command runs in ~100ms. The browser persists across commands within a session.

## Setup Check

Before first use, verify the binary exists:

```bash
if [ ! -f "$B" ]; then
  echo "Building browse binary..."
  (cd "$(dirname "$B")/.." && ./setup)
fi
```

The `$B` variable is set by OpenHarness and points to `browse/dist/browse`.

## Command Reference

### Navigation
```bash
$B goto <url>              # Navigate to URL
$B back                    # History back
$B forward                 # History forward
$B reload                  # Reload page
$B url                     # Print current URL
```

### Reading Page Content
```bash
$B text                    # Cleaned page text (no scripts/styles)
$B html [selector]         # innerHTML of selector, or full page
$B links                   # All links as "text → href"
$B forms                   # Form fields as JSON
$B accessibility           # Full ARIA tree
```

### Interaction
```bash
$B click <sel>             # Click element (CSS selector or @ref)
$B fill <sel> <value>      # Fill input field
$B select <sel> <value>    # Select dropdown option
$B hover <sel>             # Hover element
$B type <text>             # Type into focused element
$B press <key>             # Press key (Enter, Tab, Escape, etc.)
$B scroll [sel]            # Scroll element into view, or to bottom
$B wait <sel>              # Wait for element to appear (15s timeout)
$B wait --networkidle      # Wait for network idle
$B viewport <WxH>          # Set viewport (e.g., 375x812)
$B upload <sel> <file>     # Upload file to input
```

### Inspection
```bash
$B js <expr>               # Run JavaScript, return result
$B eval <file>             # Run JS from file
$B css <sel> <prop>        # Get computed CSS value
$B attrs <sel>             # Element attributes as JSON
$B is <prop> <sel>         # Check: visible|hidden|enabled|disabled|checked|editable|focused
$B console [--errors]      # Console messages (--errors for errors only)
$B network [--clear]       # Network requests
$B cookies                 # All cookies as JSON
$B storage [set k v]       # localStorage + sessionStorage
$B perf                    # Page load timings
```

### Visual Capture
```bash
$B screenshot [path]                    # Full page screenshot
$B screenshot --viewport [path]         # Viewport only
$B screenshot --clip x,y,w,h [path]     # Clip region
$B screenshot @e3 [path]                # Element screenshot
$B pdf [path]                           # Save as PDF
$B responsive [prefix]                  # Mobile + tablet + desktop screenshots
```

### Accessibility Snapshot (Key Command)
```bash
$B snapshot                # Full accessibility tree with @e refs
$B snapshot -i             # Interactive elements only (buttons, links, inputs)
$B snapshot -c             # Compact (no empty structural nodes)
$B snapshot -d <N>         # Limit depth
$B snapshot -s <sel>       # Scope to CSS selector
$B snapshot -D             # Diff against previous snapshot
$B snapshot -a             # Annotated screenshot with ref labels
$B snapshot -C             # Find cursor:pointer clickable elements (@c refs)
```

After `snapshot`, use `@e1`, `@e2`, etc. as selectors:
```bash
$B snapshot -i             # Get interactive elements
$B click @e3               # Click the 3rd element
$B fill @e4 "hello"        # Fill the 4th element
```

### Tabs
```bash
$B tabs                    # List open tabs
$B tab <id>                # Switch to tab
$B newtab [url]            # Open new tab
$B closetab [id]           # Close tab
```

### Server Control
```bash
$B status                  # Health check
$B stop                    # Shutdown server
$B restart                 # Restart server
$B handoff [message]       # Open visible Chrome for user
$B resume                  # Return control from user
```

### Multi-step
```bash
echo '[["goto","https://example.com"],["text"]]' | $B chain
```

## QA Workflow Example

```bash
# 1. Navigate to the page
$B goto http://localhost:3000

# 2. Take a snapshot to see interactive elements
$B snapshot -i

# 3. Fill a form
$B fill @e2 "test@example.com"
$B fill @e3 "password123"
$B click @e4

# 4. Verify the result
$B snapshot -i
$B screenshot /tmp/after-login.png

# 5. Check for console errors
$B console --errors
```

## Important Notes

- The browse server auto-shuts down after 30 minutes of idle
- Refs (`@e1`, `@c1`) become stale after navigation — re-run `snapshot`
- Screenshots default to `/tmp/browse-screenshot.png`
- State directory: `.openharness-browse/` (auto-added to .gitignore)
- Cloud metadata endpoints (169.254.169.254) are blocked for security
