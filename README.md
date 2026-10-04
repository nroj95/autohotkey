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

### `scratchpad.ahk`

turns a dedicated Notepad3 window into a persistent, top-edge scratch drawer for temporary notes and code.

Scratchpad is standalone. run `scratchpad.ahk` directly or enable **Run at startup** from its tray menu. it requires **64-bit AutoHotkey v2** and Notepad3. if Notepad3 cannot be located automatically, select its `Notepad3.exe` when prompted.

#### controls

| shortcut | action |
|---|---|
| Win+F12 | show or hide the scratchpad (default global toggle) |
| Escape, inside the editor | hide the scratchpad |
| Ctrl+N, inside the editor | create a new scratch page |
| Ctrl+S, inside the editor | save the current page |
| Win+Left / Win+PgDn or Win+Right / Win+PgUp, inside the editor | previous / next page |

the global toggle is configurable from the Scratchpad tray menu. presets include `Win+F12`, `F12`, several F12 modifier combinations, `Win+F10` and `Ctrl+Alt+Space`; **Custom...** accepts another keyboard combination, and **Disabled** turns the global toggle off. non-F-key custom shortcuts require at least one modifier.

#### window behavior

the drawer uses 75% of the selected monitor's work-area width and 60% of its height, centered horizontally at the top. the monitor is selected from the window active when the drawer is opened.

the default motion is a 180 ms eased slide down/up. Windows' disabled-animation setting is respected. the drawer stays on top by default, and hiding it attempts to restore focus to the previous application.

Scratchpad marks its editor with `nroj.WindowCascade.Ignore`, so Window Cascade leaves the drawer alone.

hiding does not close Notepad3. **Reload** keeps the editor and reattaches to it. **Exit** saves the current page, closes the owned Notepad3 window and exits Scratchpad.

#### pages and saving

pages live directly inside `D:\toolbox\scratch\` by default. the remembered page is reopened on the next scratch command, or the newest existing page when that path no longer exists.

new pages are named `scratch-yyyyMMdd-HHmmss.md`, use UTF-8 without BOM and LF line endings, and never overwrite an existing file. same-second collisions receive `-02`, `-03`, and so on.

page rotation is ordered by file creation time, with filename breaking ties. subdirectories are not scanned. common text, code and configuration extensions are accepted, including `.md`, `.txt`, `.ps1`, `.py`, `.ahk`, `.lua`, `.json` and `.ini`; see `allowed_extensions` in the script for the full list.

visible pages are autosaved every two seconds and explicitly saved before hiding, switching or exiting. failed saves or detected disk conflicts stop the operation instead of overwriting uncertain data.

page switching reuses the same Notepad3 window. **undo history survives hiding and Scratchpad reloads, but not switching pages**. caret, selection and scroll position are remembered during the script session.

use Notepad3's **File > Save As** to give an open page a useful name inside the scratch folder. closed pages can be renamed normally in Explorer. externally moving, renaming or deleting the open page, or changing it concurrently on disk, pauses automatic saving until the conflict is resolved.

#### isolation and settings

Scratchpad uses a dedicated Notepad3 configuration file, so ordinary Notepad3 settings are not reused.

controller configuration is created at:

```text
%LOCALAPPDATA%\Scratchpad\settings.ini
```

```ini
[Paths]
ScratchDirectory=D:\toolbox\scratch
Notepad3Executable=

[Window]
WidthPercent=75
HeightPercent=60
AnimationDurationMs=180
AlwaysOnTop=1

[Saving]
AutosaveIntervalMs=2000

[Controls]
ToggleHotkey=Win+F12
```

leave `Notepad3Executable` blank for automatic detection, or enter the full path without surrounding quotes. `ToggleHotkey` stores the friendly shortcut name, for example `Win+F12` or `Ctrl+Shift+Space`. edit the settings through the tray menu, then reload. `AnimationDurationMs=0` disables motion and `AlwaysOnTop=0` allows ordinary windows to cover the drawer.

the current-page record is stored in `%LOCALAPPDATA%\Scratchpad\state.ini`, the dedicated editor configuration is stored in `%LOCALAPPDATA%\Scratchpad\Notepad3.ini`, and errors are logged to `%LOCALAPPDATA%\Scratchpad\errors.log`.

#### recovery and implementation

if a command reports a save conflict, timeout or editor dialog, resolve it in Notepad3 before retrying. Scratchpad does not automatically confirm overwrite prompts or kill editor processes.

the bridge uses standard Windows messages, Notepad3's `WM_COPYDATA` file-loading path and integer-only Scintilla messages. it does not swap the clipboard, inject save keystrokes, allocate memory inside Notepad3 or interfere with normal Notepad++ instances.

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
- minimizing/restoring all cascades across monitors and disabling/resuming cascade activity with `Caps + M`
- closing all layers on the current monitor with `Caps + F4`
- checking for conflicting Windows or PowerToys settings

focus tabs show at most one clickable marker per slot. clicking an inactive slot focuses its exposed window; clicking the active slot cycles to the next layer in that stack. holding, dragging, or releasing a focus tab adds no extra action.

windows can also be dragged near an existing cascade slot to snap or adopt them. dragging a managed window away from the cascade releases it on mouse-up.

new-window placement includes guarded foreground recovery for taskbar launches where Windows briefly hands focus back to the shell, including Shift + taskbar launches.

focus-tab colors can be configured from the tray separately for the active and inactive slots.

`Caps + H` toggles the Window Cascade help page, which uses the custom cascade icon. while the cascade is disabled, `Caps + M` remains available to resume; windows opened during the disabled period stay unmanaged.

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
- `scratchpad.ahk`: 64-bit AutoHotkey v2 and Notepad3

## usage

run root-level `.ahk` launchers rather than module files inside `window-cascade/` or `win-key-overhaul/`.

start `capslock-layer.ahk` before `window-cascade.ahk`. Scratchpad, Win Key Overhaul and the other utilities run independently unless their own documentation says otherwise.

each main script provides a tray menu with its own controls and a **Run at startup** option where applicable.

from the repository root, run `./validate.ps1` after changes to validate the root scripts and their include trees.

## icon attribution

the included tray icons use artwork from the FatCow Farm-Fresh Web Icons 3.9.2 set.

see [`icons/ATTRIBUTION.md`](icons/ATTRIBUTION.md) for source artwork and license details.
