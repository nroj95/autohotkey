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

turns a dedicated Notepad++ instance into a persistent, top-edge scratch drawer for temporary notes and code.

Scratchpad is launched on demand by `capslock-layer.ahk`; it does not need its own startup entry. it requires **64-bit AutoHotkey v2** and Notepad++. Notepad++ itself may be 32-bit or 64-bit. if Notepad++ cannot be located automatically, select its `notepad++.exe` when prompted.

#### controls

| shortcut | action |
|---|---|
| Caps+B | show or hide the scratchpad |
| Caps+N | create a new scratch page and show it |
| Caps+J / Caps+L | previous / next page, wrapping at the ends |
| Escape, inside the editor | hide; autocomplete/calltip popups get Escape first |
| Ctrl+N, inside the editor | create a new scratch page |
| Ctrl+PgUp / Ctrl+PgDn, inside the editor | previous / next page |

one-shot Caps works too: tap Caps, then B, N, J or L. editor-only shortcuts do not replace keys in ordinary Notepad++ windows, Find/Replace dialogs or native menus.

F12 is disabled by default. it can be enabled from the Scratchpad tray menu for standalone operation without CapsLock Layer.

#### window behavior

the drawer uses 75% of the selected monitor's work-area width and 60% of its height, centered horizontally at the top. the monitor is selected from the window active when the drawer is opened.

the default motion is a 180 ms eased slide down/up. Windows' disabled-animation setting is respected. the drawer stays on top by default, and hiding it attempts to restore focus to the previous application.

hiding does not close Notepad++. ordinary script exit reveals the editor instead of terminating it. a later script launch or reload can reattach to the marked scratch window; ordinary Notepad++ windows are not adopted.

#### pages and saving

pages live directly inside `D:\toolbox\scratch\`. restarting Windows does not create a new page: the remembered page is reopened, or the newest existing page when that path no longer exists.

new pages are named `scratch-yyyyMMdd-HHmmss.md`, use UTF-8 without BOM and LF line endings, and never overwrite an existing file. same-second collisions receive `-02`, `-03`, and so on.

page rotation is ordered by file creation time, with filename breaking ties. subdirectories are not scanned. common text, code and configuration extensions are accepted, including `.md`, `.txt`, `.ps1`, `.py`, `.ahk`, `.lua`, `.json` and `.ini`; see `allowed_extensions` in the script for the full list.

visible pages are autosaved every two seconds and explicitly saved before hiding or switching. a failed save prevents hiding or switching until the problem is resolved.

only one page remains open after a successful switch. extra manually opened tabs are not automatically saved or discarded; the tab bar is revealed so they can be resolved manually.

**undo history survives hiding, but not switching pages**, because switching closes the old document. caret, selection, scroll position and the selected built-in language are remembered during the script session, but not across script restarts.

rename an **open** page using Notepad++'s **File > Rename**. closed pages can be renamed normally in Explorer. externally renaming, moving or deleting the open page pauses scratch operations rather than recreating the old filename. simultaneous changes on disk and in the editor also stop automatic saving until resolved with Save As or Reload from Disk.

#### isolation and settings

Scratchpad starts Notepad++ with a separate settings directory, a separate instance, no restored session and no plugins. the dedicated instance hides its tab bar and toolbar, while ordinary Notepad++ settings and tabs are left alone.

configuration is created on first run at:

```text
%LOCALAPPDATA%\Scratchpad\settings.ini
```

```ini
[Paths]
ScratchDirectory=D:\toolbox\scratch
NotepadExecutable=

[Window]
WidthPercent=75
HeightPercent=60
AnimationDurationMs=180
AlwaysOnTop=1

[Saving]
AutosaveIntervalMs=2000

[Controls]
EnableF12=0
```

leave `NotepadExecutable` blank for automatic detection, or enter the full path without surrounding quotes. edit the settings through the tray menu, then reload. `AnimationDurationMs=0` disables motion and `AlwaysOnTop=0` allows ordinary windows to cover the drawer.

the current-page record is stored in `%LOCALAPPDATA%\Scratchpad\state.ini`, and the isolated Notepad++ profile is stored in `%LOCALAPPDATA%\Scratchpad\Notepad++\`. scratch notes remain outside the Git repository unless the configured scratch directory itself is inside one.

#### recovery and implementation

if a command reports a save conflict, timeout or extra tabs, inspect the visible editor and resolve the problem before retrying. the script does not confirm overwrite dialogs, send Close All or terminate the editor. **Exit (keep editor open)** in the tray menu releases the window for ordinary editing.

the bridge uses Notepad++ and Scintilla messages rather than clipboard replacement or simulated Save/Close keystrokes. pointer-bearing messages use buffers allocated in the editor process; no executable code is injected. the dropdown animation uses window positioning and clipping rather than `AnimateWindow`.

primary implementation references:

```text
https://github.com/notepad-plus-plus/npp-usermanual/blob/master/content/docs/command-prompt.md
https://github.com/notepad-plus-plus/notepad-plus-plus/blob/master/PowerEditor/src/MISC/PluginsManager/Notepad_plus_msgs.h
https://github.com/notepad-plus-plus/notepad-plus-plus/blob/master/PowerEditor/src/menuCmdID.h
https://www.scintilla.org/ScintillaDoc.html
https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-sendmessagetimeoutw
https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-animatewindow
```


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
- `scratchpad.ahk`: 64-bit AutoHotkey v2 and Notepad++

## usage

run root-level `.ahk` launchers rather than module files inside `window-cascade/` or `win-key-overhaul/`.

start `capslock-layer.ahk` before `window-cascade.ahk`. CapsLock Layer starts `scratchpad.ahk` on demand when a Scratchpad command is used, so Scratchpad does not need its own startup entry. Win Key Overhaul and the other utilities can run independently unless their own documentation says otherwise.

each main script provides a tray menu with its own controls and a **Run at startup** option where applicable.

from the repository root, run `./validate.ps1` after changes to validate the root scripts and their include trees.

## icon attribution

the included tray icons use artwork from the FatCow Farm-Fresh Web Icons 3.9.2 set.

see [`icons/ATTRIBUTION.md`](icons/ATTRIBUTION.md) for source artwork and license details.
