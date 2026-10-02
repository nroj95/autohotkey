# Window Hotkeys internals

launch `../window-hotkeys.ahk`, not the files in this directory. the root launcher
owns the script identity, startup sequence, registered message, tray menu, and
exit callback. these modules are included into that one AutoHotkey v2 process.

Window Hotkeys remains independent of Window Cascade. CapsLock Layer is optional
here: it supplies the existing `Caps + G` Steam-cycle command. this refactor does
not add a CapsLock Layer requirement, change any bindings, or add a command mode.

## module map

| file | responsibility |
| --- | --- |
| `settings.ahk` | existing defaults, runtime globals, Steam exclusions, paths, and debug settings. |
| `controls.ahk` | the complete original hotkey block, including FancyZones `#HotIf` scope and mouse bindings; CapsLock Layer presence lookup. |
| `window-state.ahk` | Win+Home/Win+M group toggles, last-minimized target selection, maximize, minimize, and restore commands. |
| `layouts.ahk` | side-layout cycling, third/half tiles, center tiles, matching, and placement preparation. |
| `swapping.ahk` | clockwise window ordering, candidate selection, and rectangle swapping. |
| `focus.ahk` | spatial focus, temporary highlight GUIs, session expiry, and accent color. |
| `steam.ahk` | Steam message handler, game cycle/discovery, game minimize/activation, and return-window selection. |
| `borderless.ahk` | borderless entry/restoration, Steam suspension/resume, and the existing exit/reload cleanup. |
| `fancyzones.ahk` | startup checks, compatibility prompts, settings access, shortcut formatting, and the internal PowerShell bridge. |
| `windows.ahk` | shared window filters, frame/monitor geometry, native placement snapshots, frame refresh, reliable activation, and list lookup. |
| `interface.ahk` | help text, shortcut-line formatting, and startup shortcut management. |
| `debug.ahk` | log initialization/reset, error handling, and window/Steam diagnostics. |

## initialization and boundaries

all includes are explicit in the root launcher and anchored to `A_ScriptDir`.
modules do not include each other. `settings.ahk` still initializes globals at
top level, before logging and callbacks; no assignments were moved into a
function with a different scope. the startup statement order is unchanged.

all 75 existing top-level function definitions, including their signatures,
internal comments, nested callbacks, and embedded PowerShell strings, are
unchanged. the 25 hotkey definitions retain their order and `#HotIf` contexts.
only source organization, section comments, and this documentation change.

these are internal modules, not independent libraries. do not include Window
Cascade's similarly named modules here: each root script has its own globals
and helper functions and must remain a separate process.

## preserved behavior and paths

existing shortcuts, exclusions, window-state rules, delays, retry limits, and
FancyZones confirmation prompts remain as supplied. the existing
`OnExit RestoreAllBorderlessWindows` callback is registered in the same order.

`WindowHotkeys.CycleSteamGames`, `WindowDebug.ResetLogs`, and the CapsLock Layer
presence-mutex name are unchanged. so are the paths for
`icons/window-hotkeys.ico`, `window-hotkeys-debug.log`, the startup shortcut,
FancyZones settings, the PowerShell executable, and temporary files.

errors from moved functions will now report the module's source filename and
line number. this is an expected consequence of the split, not a behavior fix.

## applying the update

prefer the supplied Git patch from the repository root. it replaces only
`window-hotkeys.ahk` and adds this new directory. it does not delete any existing
modules or modify `capslock-layer.ahk`, `window-cascade.ahk`, `window-cascade/`,
`validate.ps1`, icons, or other scripts.

when using the ZIP instead, merge its root file and directory into the existing
repository. do not replace the repository or delete existing directories. the
ZIP contains this Window Hotkeys update, not a complete copy of the repository.

## validation and regression checks

from the repository root, run `./validate.ps1` to validate the root scripts and
their includes. do not validate or launch modules separately. only reload
`window-hotkeys.ahk` for this change; its existing borderless cleanup will run.

check Win+Up/Down/Backspace from normal, maximized, minimized, and borderless
states; Win+Home and Win+M restore sets; left/right layout cycles and tiles;
Win+Enter clockwise swapping; Alt+Win+Arrow focus/highlight expiry; and the
FancyZones shortcuts/help. where Steam games are available, check Caps+G with
one and multiple games and a return window, including borderless minimize/resume.
use test windows without unsaved work when checking exit/reload behavior.

this is an organizational refactor, not a performance optimization. syntax/load
checks do not substitute for Windows desktop behavior testing.

## reference

AutoHotkey's official documentation describes `#Include` as textual inclusion
at its position and distinguishes loading from the auto-execute thread:

- [include semantics](https://www.autohotkey.com/docs/v2/lib/_Include.htm)
- [script startup and command-line switches](https://www.autohotkey.com/docs/v2/Scripts.htm)
