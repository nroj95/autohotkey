# AutoHotkey

personal AutoHotkey v2 scripts for keyboard layers, window management, and small Windows utilities.

## scripts

### `capslock-layer.ahk`

turns CapsLock into an extra left-hand modifier layer.

- `Caps + Q/W/E/R` → F13–F16
- `Caps + A/S/D/F` → F17–F20
- `Caps + Z/X/C/V` → F21–F24
- `Caps + 0–9` → Numpad 0–9
- tap CapsLock to arm the layer for one keypress
- the one-shot layer expires after 1.4 seconds
- double-tap Left Shift to toggle normal CapsLock
- owns the companion-command namespace used by Window Cascade and Window Hotkeys

registered commands can override a base layer key in a specific context. in Windows Terminal, the layer includes commands for clearing the terminal buffer and copying the full buffer as a Markdown code block.

the one-shot indicator appears where the mouse pointer was when the layer was armed and stays fixed until the layer is consumed or expires. it is hidden in maximized and fullscreen windows.

### `pause-command-mode.ahk`

uses Pause as a second command layer for text and utility shortcuts.

it supports both held chords and the same 1.4-second one-shot behavior as the CapsLock layer.

included commands cover:

- text characters and snippets
- timestamps
- speaker wake
- system sleep
- built-in help

the CapsLock and Pause one-shot layers are mutually exclusive, so arming one automatically disarms the other.

### `shell-folders.ahk`

a small tray utility for opening useful Windows shell and hidden folders without remembering their paths.

it provides quick access to locations such as:

- Startup
- SendTo
- AppData
- ProgramData
- Temp
- Recycle Bin

### `window-cascade.ahk`

automatically arranges ordinary windows into a cascading layout.

it includes controls for:

- moving through cascade windows
- adopting an existing window and undoing the most recent adoption
- rotating stacked windows
- moving managed windows across monitors
- minimizing and restoring the cascade
- resetting automatic placement
- pausing cascading
- checking for conflicting Windows or PowerToys settings

Window Cascade runs as its own process but requires `capslock-layer.ahk` for its keyboard command bindings.

### `window-hotkeys.ahk`

custom Win-key window management intended to be more predictable than the default Windows Snap behavior.

features include:

- maximize, minimize, and restore behavior
- half, third, and quarter-screen layouts
- horizontal and vertical window stretching
- borderless fullscreen
- spatial window movement and focus
- Windows accent-color focus indicators
- minimize/restore-all behavior
- cycling running Steam games

Window Hotkeys runs independently of Window Cascade and does not require `capslock-layer.ahk`. when CapsLock Layer is running, it adds companion controls for spatial focus and Steam cycling.

## requirements

- Windows 11
- AutoHotkey v2

## usage

run root-level `.ahk` launchers rather than module files inside `window-cascade/` or `window-hotkeys/`.

start `capslock-layer.ahk` before `window-cascade.ahk`. Window Hotkeys and the other utilities can run independently unless their own documentation says otherwise.

each main script provides a tray menu with its own controls and a **Run at startup** option where applicable.

from the repository root, run `./validate.ps1` after changes to validate the root scripts and their include trees.

## icon attribution

the included tray icons use artwork from the FatCow Farm-Fresh Web Icons 3.9.2 set.

see [`icons/ATTRIBUTION.md`](icons/ATTRIBUTION.md) for source artwork and license details.
