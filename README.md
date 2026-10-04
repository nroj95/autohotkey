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
- owns the companion-command namespace used by Window Cascade

open the tray menu and choose **How to use** for the CapsLock Layer help page.

registered commands can override a base layer key in a specific context. in Windows Terminal, the layer includes commands for clearing the terminal buffer and copying the full buffer as a Markdown code block.

the one-shot indicator appears where the mouse pointer was when the layer was armed and stays fixed until the layer is consumed or expires. it is hidden in maximized and fullscreen windows.

### `pause-command-mode.ahk`

uses Pause as a second command layer for text and utility shortcuts.

it supports both held chords and the same 1.4-second one-shot behavior as the CapsLock layer.

`Pause + H` toggles the Pause Command Mode help page.

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
- adopting and re-slotting existing windows, including drag-and-drop
- rotating stacked windows and cycling slot layers
- moving managed windows across monitors
- minimizing and restoring one or all cascades
- closing the current layer or all layers on a monitor
- pausing automatic placement
- checking for conflicting Windows or PowerToys settings

focus tabs show at most one clickable marker per slot. clicking an inactive slot focuses its exposed window; clicking the active slot cycles to the next layer in that stack. holding, dragging, or releasing a focus tab adds no extra action.

windows can also be dragged near an existing cascade slot to snap or adopt them. dragging a managed window away from the cascade releases it on mouse-up.

new-window placement includes guarded foreground recovery for taskbar launches where Windows briefly hands focus back to the shell, including Shift + taskbar launches.

focus-tab colors can be configured from the tray separately for the active and inactive slots.

`Caps + H` toggles the Window Cascade help page.

Window Cascade runs as its own process but requires `capslock-layer.ahk` for its keyboard command bindings.

### `win-key-overhaul.ahk`

replaces selected native Win-key shortcuts with predictable custom window management.

features include:

- quarter- and half-width side and corner layout cycles
- centered and offset top/bottom layouts
- restore-to-normal and minimize shortcuts
- collision-aware horizontal stretching
- full-height vertical stretching
- borderless fullscreen
- clockwise and counter-clockwise window swapping
- spatial focus navigation
- Windows accent-color focus indicators
- isolate and minimize/restore-all behavior
- cycling running Steam games
- optional FancyZones compatibility
- optional ScreenGrid recommendation

`Ctrl + Win + H` toggles the Win Key Overhaul help page.

Win Key Overhaul is fully standalone and does not depend on the other root-level AutoHotkey scripts in this repository.

## requirements

- Windows 11
- AutoHotkey v2

## usage

run root-level `.ahk` launchers rather than module files inside `window-cascade/` or `win-key-overhaul/`.

start `capslock-layer.ahk` before `window-cascade.ahk`. Win Key Overhaul and the other utilities can run independently unless their own documentation says otherwise.

each main script provides a tray menu with its own controls and a **Run at startup** option where applicable.

from the repository root, run `./validate.ps1` after changes to validate the root scripts and their include trees.

## icon attribution

the included tray icons use artwork from the FatCow Farm-Fresh Web Icons 3.9.2 set.

see [`icons/ATTRIBUTION.md`](icons/ATTRIBUTION.md) for source artwork and license details.
