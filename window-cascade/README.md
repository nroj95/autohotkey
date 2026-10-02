# Window Cascade internals

Launch `../window-cascade.ahk`, not the files in this directory. The launcher
owns the process, icon, logging setup, startup sequence, and exit callback.
These files are explicitly included into that same AutoHotkey v2 script.
They are not separate running scripts or independently reusable libraries.

`capslock-layer.ahk` remains a separate, self-contained script. It does not
include anything from this directory and does not require Window Cascade
in order to provide its own key layer.

## Where to make changes

| File | Responsibility |
| --- | --- |
| `settings.ahk` | Defaults, persisted rotate-key selection, shared runtime state, and the CapsLock Layer command IDs. |
| `controls.ahk` | Standalone hotkeys, the desktop-click binding, hotkey availability, and registered-message dispatch. |
| `discovery.ahk` | Desktop monitor hints, the startup window snapshot, discovery polling, placement queueing, Windows event hooks, and destroyed-window cleanup. |
| `layout.ahk` | Managed history, canonical slot geometry, occupancy, stacks, exposed layers, compaction, and Z-order sorting. |
| `navigation.ahk` | Focusing, swapping, slot/layer rotation, spatial navigation, and bringing a cascade forward. |
| `placement.ahk` | Explicit placement, readiness retries, new-window placement, and asynchronous stabilization. |
| `commands.ahk` | Adoption, gathering, cross-monitor moves, close commands, minimize/restore operations, and minimize-state cleanup. |
| `focus-corners.ahk` | Focus overlays, their lifetime and position, click handling, visibility, and accent color. |
| `windows.ahk` | Window filtering, visible/raw frame geometry, monitor lookup, and monitor-selection policy. |
| `interface.ahk` | Tray menu, help, startup shortcut, rotate-key persistence, and compatibility checks. |
| `debug.ahk` | Logging, log-reset messages, error reporting, and diagnostic window descriptions. |

## Initialization and dependencies

Only `settings.ahk` contains top-level state initialization. The launcher
includes it at the same point in the startup sequence as the previous inline
settings, before building the tray menu, registering the command handler,
seeding existing windows, installing window hooks, and starting timers.

The other modules contain function definitions, with the hotkey definitions
concentrated in `controls.ahk`. All includes are explicit in the launcher;
modules do not include each other. The launcher anchors include paths to
`A_ScriptDir` so they do not depend on the shell's current directory.

This is a structural refactor. Functions still use their existing global
state and call one another directly across files. No classes, dynamic module
loader, new background processes, or alternate dispatch layer were added.
Function names and parameter lists are unchanged.

## Compatibility contracts

Keep the 16 `cascade_command_*` IDs in `settings.ahk` synchronized with the
same constants in the standalone `capslock-layer.ahk`. They intentionally
remain duplicated so the CapsLock script has no include dependency.

The `WindowCascade.Command` registered-message name, CapsLock presence mutex,
message parameters, hotkeys, and `#HotIf` contexts are unchanged. In particular,
the latest Caps + Alt + Left/Right commands still pass the original active
window handle through the existing message handler and monitor-move logic.

The launcher remains at the repository root. Existing startup shortcuts,
`icons/window-cascade.ico`, `window-cascade-debug.log`, and the settings file
under `%LOCALAPPDATA%\Window Cascade\settings.ini` keep their existing paths.
No icons, settings files, startup shortcuts, or companion scripts are replaced
by this refactor.

## Checking a change

Validate the root launcher rather than an individual module. AutoHotkey's
`/Validate` switch loads and validates a script without executing its startup
code; `/ErrorStdOut` sends load-time errors to stderr. Use the actual installed
AutoHotkey v2 executable. For a standard 64-bit installation, run this from
the repository root in PowerShell:

````powershell
$ahk = 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe'

if (-not (Test-Path -LiteralPath $ahk -PathType Leaf)) {
    throw 'Set $ahk to the path of your installed AutoHotkey v2 executable.'
}

foreach ($script in 'capslock-layer.ahk', 'window-cascade.ahk') {
    $path = (Resolve-Path -LiteralPath $script).Path
    & $ahk /ErrorStdOut=UTF-8 /Validate $path | Out-Host

    if ($LASTEXITCODE -ne 0) {
        throw "AutoHotkey validation failed for $script."
    }

    Write-Host "Validated: $script"
}
````

Reload only the two root scripts after applying and validating the changes.
Normal script reload behavior still applies: Window Cascade seeds the windows
already open at startup instead of automatically adopting them. Test placement
with newly opened windows, or explicitly adopt an existing window as before.

Check new-window placement, delayed window startup, focus markers, slot swaps,
slot/layer rotation, minimize/restore, and Caps + Alt + Left/Right across monitors.
Check standalone shortcuts with CapsLock Layer exited. Check the tray help and
rotate-key selection. Avoid close-scope tests with unsaved work.

Syntax validation does not replace these Windows desktop behavior checks.

## AutoHotkey documentation

- [Include semantics](https://www.autohotkey.com/docs/v2/lib/_Include.htm)
- [Script startup and validation switches](https://www.autohotkey.com/docs/v2/Scripts.htm)
