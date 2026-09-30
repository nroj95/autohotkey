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
- integrates with `window-cascade.ahk` and `window-hotkeys.ahk`

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
- adopting an existing window
- rotating stacked windows
- minimizing and restoring the cascade
- resetting automatic placement
- pausing cascading
- checking for conflicting Windows or PowerToys settings

it can run independently, with additional shortcuts available when `capslock-layer.ahk` is running.

### `window-hotkeys.ahk`

custom Win-key window management intended to be more predictable than the default Windows Snap behavior.

features include:

- maximize, minimize, and restore behavior
- half, third, and quarter-screen layouts
- borderless fullscreen
- spatial window movement and focus
- Windows accent-color focus indicators
- minimize/restore-all behavior
- cycling running Steam games

## requirements

- Windows 11
- AutoHotkey v2

## usage

run whichever `.ahk` scripts you want.

each main script provides a tray menu with its own controls and a **Run at startup** option where applicable.

the scripts are designed to remain useful independently, while some features integrate automatically when companion scripts are running.
