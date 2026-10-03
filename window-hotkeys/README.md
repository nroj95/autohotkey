# Window Hotkeys internals

launch `../window-hotkeys.ahk`, not the files in this directory. the root launcher owns the script identity, startup sequence, registered message, tray menu, and exit callback. these modules are included into that one AutoHotkey v2 process.

Window Hotkeys remains independent of Window Cascade, but CapsLock Layer is a required companion. it owns the companion-control namespace, including `Caps + Win + H`, `Caps + Win + Arrow`, and `Caps + G`. Window Hotkeys intentionally has no standalone fallback for those controls.

## module map

| file | responsibility |
| --- | --- |
| `settings.ahk` | defaults, runtime globals, Steam exclusions, paths, and debug settings. |
| `controls.ahk` | direct Win/FancyZones hotkeys, mouse bindings, required CapsLock Layer presence/watch logic, and `WindowHotkeys.Command` dispatch. |
| `window-state.ahk` | Win+Home/Win+M group toggles, last-minimized target selection, maximize, minimize, and restore commands. |
| `layouts.ahk` | horizontal and vertical stretch state, side-layout cycling, third/half tiles, center tiles, matching, and placement preparation. |
| `swapping.ahk` | clockwise window ordering, candidate selection, and rectangle swapping. |
| `focus.ahk` | spatial focus, temporary highlight GUIs, session expiry, and accent color. |
| `steam.ahk` | Steam message handler, game cycle/discovery, game minimize/activation, and return-window selection. |
| `borderless.ahk` | borderless entry/restoration, Steam suspension/resume, and exit/reload cleanup. |
| `fancyzones.ahk` | startup checks, compatibility prompts, settings access, shortcut formatting, and the internal PowerShell bridge. |
| `windows.ahk` | shared window filters, frame/monitor geometry, native placement snapshots, frame refresh, reliable activation, and list lookup. |
| `interface.ahk` | help text, shortcut-line formatting, and startup shortcut management. |
| `debug.ahk` | log initialization/reset, error handling, and window/Steam diagnostics. |

## initialization and boundaries

all includes are explicit in the root launcher and anchored to `A_ScriptDir`. modules do not include each other. `settings.ahk` initializes shared globals before logging, callbacks, and the rest of startup.

the module split keeps feature boundaries explicit while CapsLock Layer owns companion commands that would otherwise consume more global shortcut space. ordinary Win-key window-management shortcuts and FancyZones integration remain direct Window Hotkeys bindings.

these are internal modules, not independent libraries. do not include Window Cascade's similarly named modules here: each root script has its own globals and helper functions and must remain a separate process.

## integration contracts and paths

`WindowHotkeys.Command`, `WindowHotkeys.CycleSteamGames`, `WindowDebug.ResetLogs`, and the CapsLock Layer presence-mutex name form the cross-process integration surface. keep command identifiers and message handling synchronized with `capslock-layer.ahk` when companion controls change.

paths for `icons/window-hotkeys.ico`, `window-hotkeys-debug.log`, the startup shortcut, FancyZones settings, the PowerShell executable, and temporary files are intentionally resolved from the root script or their existing system locations.

errors raised inside a module report that module's source filename and line number.

## validation and regression checks

from the repository root, run:

````powershell
./validate.ps1
````

this validates the root scripts and their include trees. do not validate or launch the module files separately.

for Window Hotkeys changes, check:

- Win+Up/Down/Backspace from normal, maximized, minimized, and borderless states
- Win+Home and Win+M minimize/restore sets
- left/right layout cycles and third/half/center tiles
- Win+Enter clockwise swapping
- Shift+Win+Left/Right horizontal stretch and reset behavior
- Shift+Win+Up/Down vertical stretch and reset behavior
- Caps+Win+Arrow spatial focus and highlight expiry
- Caps+Win+H help
- FancyZones shortcuts, compatibility checks, and help text
- Caps+G with one and multiple Steam games and a return window, including borderless minimize/resume
- required CapsLock Layer behavior during startup, quick reloads, and a sustained dependency loss

syntax validation does not replace Windows desktop behavior testing.

## reference

AutoHotkey's official documentation describes `#Include` as textual inclusion at its position and distinguishes loading from the auto-execute thread:

- [include semantics](https://www.autohotkey.com/docs/v2/lib/_Include.htm)
- [script startup and command-line switches](https://www.autohotkey.com/docs/v2/Scripts.htm)
