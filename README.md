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

## Tools (31)

| Area | Read-only | Actions (logged) |
|---|---|---|
| UI tree | `list_apps`, `frontmost`, `get_tree`, `find`, `get_element`, `read_text`, `wait_for` | `press`, `find_and_press`, `batch`, `set_value`, `focus`, `perform_action` |
| Input | | `type_text`, `key` (e.g. `cmd+shift+t`), `click`, `scroll` |
| Apps, menus, windows | `menu` with `list: true` | `open_app` (optional `url`), `activate`, `menu` ("File > Export…"), `window` (move, resize, minimize, fullscreen, close) |
| Events | `watch` (app events, or `"notifications"` for banner text), `unwatch`, `get_events` (long-poll) | |
| System | `clipboard_get`, `browser_tabs` | `clipboard_set`, `run_script` (AppleScript / JXA), `browser_js` (JavaScript in your real signed-in browser) |
| Fallback | `ocr` (text + click coordinates for apps with no tree) | |

- **Ids** are `pid:child.index.path`. They go stale when the UI changes; run `find` / `wait_for` again after navigation.
- **Chromium/Electron apps** (Chrome, Brave, VS Code, Slack, WhatsApp desktop) only build their tree when asked; the helper sets `AXManualAccessibility` automatically the first time it touches an app.
- **Events**: requests run on a worker queue while the main run loop delivers AX observer, NSWorkspace (app launched/quit/activated) and notification-banner events into a 500-event buffer. Banners on macOS 27 live inside Notification Center's existing window, so they are polled once a second.
- **browser_js** needs "Allow JavaScript from Apple Events" in the browser (Brave/Chrome: View > Developer; Safari: Develop menu).
- **ocr** needs Screen Recording permission for the launching app.

## Safety

- Every action tool call is appended to `~/Library/Logs/mac-agent/actions.jsonl`.
- `MAC_AGENT_READONLY=1` in the server's environment refuses all action tools.
- The server's MCP instructions tell Claude to ask before sending, posting, paying or deleting. Claude Code's own permission prompts still apply to every tool call.

## Limits

Apps that draw their own UI (games, canvas apps, some cross-platform toolkits) expose little or no tree; use `click` with coordinates there. Elements in other Spaces or minimised windows may not be listed.

## Next

- Remote access from the iPhone (Tailscale + small control server) so the Mac can be kept awake, put to sleep or driven while away.
