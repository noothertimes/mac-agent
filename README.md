# mac-agent

An MCP server that lets Claude read and control macOS apps through the **Accessibility tree** instead of screenshots. Every window, button, text field and label comes back as one line of text with an id, and actions target those ids.

```
[54607:0.0.0.1.0.5] Button desc="7" #Seven @424,715 48x48 actions=Press
[54607:0.0.0.1.0.1.0] StaticText value="42" desc="Edit field" @597,617 37x36
```

## Build and register

```sh
swift build -c release
swift test
claude mcp add --scope user mac-agent -- ~/mac-agent/.build/release/mac-agent
```

## Permission

macOS grants Accessibility permission to the *app that launches* the helper: the terminal or editor running Claude Code (currently VS Code). Turn it on under System Settings → Privacy & Security → Accessibility, then restart that app. The `check_permission` tool reports the status, and `prompt: true` opens the dialog.

## Tools

| Read-only | Actions (logged) |
|---|---|
| `check_permission`, `list_apps`, `frontmost` | `press`, `set_value`, `focus`, `perform_action` |
| `get_tree` (scope: focused_window / windows / menubar / all) | `type_text`, `key` (e.g. `cmd+shift+t`) |
| `find` (text + optional role) | `click` (coordinates or element centre), `scroll` |
| `get_element` (every attribute of one element) | `open_app`, `activate` |

- **Ids** are `pid:child.index.path`. They go stale when the UI changes; run `find` again after navigation.
- **Chromium/Electron apps** (Chrome, Brave, VS Code, Slack, WhatsApp desktop) only build their tree when asked; the helper sets `AXManualAccessibility` automatically the first time it touches an app.
- **Compact output** hides empty layout containers and empty labels, so a deep web page stays readable. Pass `compact: false` for everything.

## Safety

- Every action tool call is appended to `~/Library/Logs/mac-agent/actions.jsonl`.
- `MAC_AGENT_READONLY=1` in the server's environment refuses all action tools.
- The server's MCP instructions tell Claude to ask before sending, posting, paying or deleting. Claude Code's own permission prompts still apply to every tool call.

## Limits

Apps that draw their own UI (games, canvas apps, some cross-platform toolkits) expose little or no tree; use `click` with coordinates there. Elements in other Spaces or minimised windows may not be listed.

## Next

- `watch` tool: AXObserver notifications (window opened, value changed, new notification) pushed as events.
- `menu` tool: click a menu path like `File > Export…` in one call.
- Chrome DevTools Protocol bridge for full page DOM.
