---
name: harmonyos-automation
description: Use when automating UI interactions on a HarmonyOS/OpenHarmony device via hdc, including clicking deeply nested components (Scroll/List/Toggle) that uinput cannot reliably reach
---

# HarmonyOS Device Automation

## Overview

Use `uitest dumpLayout` to extract exact UI element bounds from the rendered hierarchy, then click with `uitest uiInput`. This penetrates deeply nested components that absolute-coordinate `uinput -T -c` cannot reach.

## When to Use

- Need to click a specific UI element on a HarmonyOS device via hdc
- `uinput -T -c <x> <y>` coordinates miss the target (especially in Scroll/List/Swiper)
- Need to verify what's on-screen before clicking
- Writing automated test scripts for HarmonyOS apps

## Core Workflow

```
1. Dump UI tree
   hdc shell "uitest dumpLayout -p /data/local/tmp/layout.xml -b <bundleName>"

2. Pull layout to local
   hdc file recv /data/local/tmp/layout.xml <localPath>

3. Parse JSON, find target element by:
   - type: "Toggle", "Text", "Button", "ListItem" ...
   - text: partial match on garbled UTF-8 text or "originalText"
   - bounds: "[left,top][right,bottom]" format

4. Calculate center:
   x = (left + right) / 2
   y = (top + bottom) / 2

5. Click or interact:
   hdc shell "uitest uiInput click <x> <y>"          # tap
   hdc shell "uitest uiInput swipe <x1> <y1> <x2> <y2> <velocity>"  # scroll
   hdc shell "uitest uiInput longClick <x> <y>"      # long press

6. Verify result:
   - Preferences: hdc shell "cat <prefsPath>"
   - Port:        hdc shell "netstat -tlnp" | Select-String "8088"
   - Windows:     hdc shell "hidumper -s WindowManagerService -a '-a'"
   - Logs:        hdc shell "hilog -x -e StateRestore"
```

## Key Commands

| Command | Purpose |
|---|---|
| `uitest dumpLayout -p <path> -b <bundle>` | Export UI hierarchy as JSON |
| `uitest uiInput click <x> <y>` | Tap at coordinates |
| `uitest uiInput swipe <x1> <y1> <x2> <y2> [vel]` | Swipe/scroll |
| `uitest uiInput longClick <x> <y>` | Long press |
| `uitest uiInput doubleClick <x> <y>` | Double tap |
| `uitest uiInput keyEvent Back` | Press Back key |
| `snapshot_display` | Take screenshot (saves to /data/local/tmp/) |
| `aa start -a <ability> -b <bundle>` | Launch app |
| `aa force-stop <bundle>` | Kill app |
| `bm dump -n <bundle>` | Get app info (UID, paths) |

## Finding Elements

### By Tab Selection

TabBar children have `"selected":"true"` on the active tab. Tab bar is typically at bottom:
```
bounds: "[0,2149][1084,2412]" → type="TabBar"
  → child with "selected":"true" → clickable bounds
```

### By Toggle State

Toggle elements have `"type":"Toggle"` and `"checked":"true/false"`:
```json
{
  "type": "Toggle",
  "bounds": "[835,1712][943,1772]",
  "checked": "true",
  "clickable": "true"
}
```

### By Text (garbled UTF-8 OK)

Text nodes have `"type":"Text"` with text content. HarmonyOS layout dumps often produce garbled UTF-8 for Chinese text - use partial matches or position context.

## Common Mistakes

1. **Using uinput instead of uitest** - `uinput -T -c` uses absolute screen coordinates but Scroll/List components consume touches. Always prefer `uitest dumpLayout` + `uitest uiInput`.

2. **Not re-dumping after navigation** - UI tree becomes stale after tab switches or page transitions. Re-dump before each interaction.

3. **Forgetting to sleep after `aa start`** - App needs ~5 seconds to fully render. Use `Start-Sleep -Seconds 5` after launch.

4. **Clicking invisible elements** - Only click elements with `"visible":"true"`. Scrolled-off elements have `"visible":"false"` or bounds outside viewport.

## Verification Commands

```powershell
# Preferences file
hdc shell "cat /data/app/el2/100/base/<bundle>/haps/main/preferences/SP_HARMONY_UTILS_PREFERENCES"

# Port check
hdc shell "netstat -tlnp 2>/dev/null" | Select-String "8088"

# Window check
hdc shell "hidumper -s WindowManagerService -a '-a'" | Select-String "Float|supertools"

# Log check
hdc shell "hilog -x -e StateRestore"

# Screenshot (saves to /data/local/tmp/)
hdc shell "snapshot_display"
hdc file recv "/data/local/tmp/snapshot_*.jpeg" "<localPath>"
```
