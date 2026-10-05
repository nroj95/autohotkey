# AutoHotkey

small Windows 11 tools for window management, scratch notes, keyboard layers, and other things Windows should do better.

**AutoHotkey v2** · **Windows 11** · [latest release](https://github.com/nroj95/autohotkey/releases/latest)

## start here

| tool | what it does |
|---|---|
| **Scratchpad** | a fast top-edge scratch drawer for temporary notes and code, backed by Notepad3 |
| **Window Cascade** | automatically arranges ordinary windows into a layered cascade with clickable focus tabs and drag-and-drop placement |
| **Win Key Overhaul** | replaces selected Windows window-management shortcuts with predictable layouts, focus movement, swapping, stretching, and borderless fullscreen |

## Scratchpad

`scratchpad.ahk`

a persistent scratch drawer that slides down from the top of the current monitor when you need it and gets out of the way when you do not.

- `Win+F12` toggles it by default
- pages are plain files in `D:\toolbox\scratch\`
- autosaves while visible and performs stricter checked saves before hiding, switching, reloading, or exiting
- remembers the current page, caret, selection, and scroll position
- supports quick page creation and keyboard page navigation
- tracks native **Save As** renames inside the scratch folder
- protects the active page from accidental external deletion or replacement
- uses normal Z-order by default, but can temporarily rise above fullscreen applications
- file-operation and error dialogs are allowed above the drawer
- includes first-run setup, tray controls, startup support, and built-in help

Scratchpad uses its own Notepad3 configuration, separate from your normal Notepad3 setup. if Notepad3 is missing, setup can install it with WinGet or let you select an installed or portable copy.

<details>
<summary><strong>controls and settings</strong></summary>

| shortcut | action |
|---|---|
| `Win+F12` | show or hide Scratchpad |
| `Escape` | hide Scratchpad |
| `Ctrl+N` | create a new page |
| `Ctrl+S` | save the current page |
| `Win+Left` / `Win+PgDn` | previous page |
| `Win+Right` / `Win+PgUp` | next page |

the global toggle is configurable from the tray menu, including several presets, a custom shortcut, or fully disabled.

controller settings live at:

```text
%LOCALAPPDATA%\Scratchpad\settings.ini
```

defaults:

```ini
[Paths]
ScratchDirectory=D:\toolbox\scratch
Notepad3Executable=

[Window]
WidthPercent=75
HeightPercent=40
AnimationDurationMs=180
AlwaysOnTop=0

[Saving]
AutosaveIntervalMs=10000

[Controls]
ToggleHotkey=Win+F12
```

Scratchpad requires **64-bit AutoHotkey v2** and Notepad3.

</details>

## Window Cascade

`window-cascade.ahk` + `window-cascade/`

turns ordinary desktop windows into a compact cascading workspace instead of letting them pile up randomly.

- automatically places new windows into cascade slots
- stacks multiple windows per slot without losing access to deeper layers
- shows small clickable focus tabs for exposed windows
- lets you drag windows between slots or monitors to re-slot or adopt them
- supports keyboard focus movement, layer rotation, gathering, closing, and monitor moves
- preserves minimized windows and handles multi-monitor cascades
- ignores dialogs, transient prompts, Scratchpad, and other windows that should not become cascade members
- can be disabled and resumed globally with `Caps + M`

Window Cascade runs as its own process and uses `capslock-layer.ahk` for its keyboard command bindings.

for implementation details and the full behavior reference, see [`window-cascade/README.md`](window-cascade/README.md).

## Win Key Overhaul

`win-key-overhaul.ahk` + `win-key-overhaul/`

replaces selected native Win-key window shortcuts with a system built around predictable geometry instead of Windows' inconsistent snap behavior.

- side and corner layout cycles
- centered and offset layouts
- restore-to-normal and minimize shortcuts
- horizontal and vertical stretching
- borderless fullscreen
- clockwise and counter-clockwise window swapping
- spatial focus navigation
- Windows accent-color focus indicators
- isolate and minimize/restore-all behavior
- cycling running Steam games
- optional FancyZones compatibility
- optional ScreenGrid recommendation

`Ctrl + Win + H` opens its built-in help.

Win Key Overhaul is standalone. for the full behavior reference, see [`win-key-overhaul/README.md`](win-key-overhaul/README.md).

## smaller utilities

| script | purpose |
|---|---|
| `capslock-layer.ahk` | turns CapsLock into an extra left-hand modifier layer with F13–F24, numpad mappings, one-shot mode, and companion commands |
| `pause-command-mode.ahk` | uses Pause as a second command layer for text snippets, timestamps, speaker wake, system sleep, and other utility actions |
| `shell-folders.ahk` | tray shortcuts for useful Windows shell and hidden folders such as Startup, SendTo, AppData, ProgramData, Temp, and Recycle Bin |

CapsLock Layer and Pause Command Mode share the same 1.4-second one-shot idea. arming one disarms the other.

## install

grab the newest files from [Releases](https://github.com/nroj95/autohotkey/releases/latest).

the standalone scripts can be run directly with AutoHotkey v2:

- `capslock-layer.ahk`
- `pause-command-mode.ahk`
- `scratchpad.ahk`
- `shell-folders.ahk`

extract these before running their root launcher:

- `window-cascade.zip`
- `win-key-overhaul.zip`

most main scripts provide a tray menu with **Run at startup**.

Window Cascade expects CapsLock Layer to be running first. Scratchpad additionally requires 64-bit AutoHotkey v2 and Notepad3.

## development

root-level `.ahk` files are the launchers. do not run module files inside `window-cascade/` or `win-key-overhaul/` directly.

after changes:

```powershell
./validate.ps1
git diff --check
```

`validate.ps1` loads every root script and its include tree through AutoHotkey v2.

## icon attribution

the included tray icons use artwork from the FatCow Farm-Fresh Web Icons 3.9.2 set.

see [`icons/ATTRIBUTION.md`](icons/ATTRIBUTION.md) for source artwork and license details.
