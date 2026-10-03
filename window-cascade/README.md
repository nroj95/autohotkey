# Window Cascade internals

launch `../window-cascade.ahk`, not the files in this directory. the launcher owns the process, icon, logging setup, startup sequence, registered command handler, and exit callback. these files are explicitly included into that same AutoHotkey v2 script. they are not separate running scripts or independently reusable libraries.

`capslock-layer.ahk` remains a separate, self-contained script and does not require Window Cascade. the dependency is one-way: Window Cascade requires CapsLock Layer for its keyboard command bindings and does not provide standalone keyboard fallbacks.

## where to make changes

| file | responsibility |
| --- | --- |
| `settings.ahk` | defaults, persisted rotate-key and focus-tab color selections, shared runtime state, and CapsLock Layer command IDs. |
| `controls.ahk` | focus-tab mouse bindings, ordinary desktop-click handling, required CapsLock Layer presence/watch logic, and registered-message dispatch. |
| `discovery.ahk` | desktop monitor hints, the startup window snapshot, discovery polling, placement queueing, Windows event hooks, and destroyed-window cleanup. |
| `layout.ahk` | managed history, canonical slot geometry, occupancy, stacks, exposed layers, compaction, and Z-order sorting. |
| `navigation.ahk` | focusing, swapping, slot/layer rotation, spatial navigation, and bringing a cascade forward. |
| `placement.ahk` | explicit placement, readiness retries, new-window placement, and asynchronous stabilization. |
| `commands.ahk` | adoption and one-shot adoption undo, gathering, cross-monitor moves, close commands, minimize/restore operations, and minimize-state cleanup. |
| `focus-corners.ahk` | focus overlays, their lifetime and position, held-tab visibility, and active-slot coloring. |
| `focus-tab-gestures.ahk` | instant press-to-focus, swipe tracking and preview, target validation, cancellation, and release cleanup. |
| `windows.ahk` | window filtering, visible/raw frame geometry, monitor lookup, and monitor-selection policy. |
| `interface.ahk` | tray menu, help, startup shortcut, rotate-key and focus-tab color persistence, and compatibility checks. |
| `debug.ahk` | logging, log-reset messages, error reporting, and diagnostic window descriptions. |

## initialization and dependencies

only `settings.ahk` contains top-level state initialization. the launcher includes it before building the tray menu, registering the command handler, seeding existing windows, installing window hooks, and starting timers.

the remaining modules primarily contain function definitions and event/message entry points. all includes are explicit in the launcher; modules do not include each other. the launcher anchors include paths to `A_ScriptDir` so they do not depend on the shell's current directory.

keyboard commands are owned by CapsLock Layer and delivered to Window Cascade through the registered command interface. keep that separation intact when adding or moving shortcuts.

## integration contracts and paths

keep the `cascade_command_*` IDs in `settings.ahk` synchronized with the matching constants in `capslock-layer.ahk`. they intentionally remain duplicated so CapsLock Layer has no include dependency on Window Cascade.

`WindowCascade.Command`, the CapsLock Layer presence mutex, and the registered-message parameter contract form the cross-process integration surface. cross-monitor commands pass the original active window handle through that message path so the intended window remains the move target.

the launcher remains at the repository root. startup shortcuts, `icons/window-cascade.ico`, `window-cascade-debug.log`, and the settings file under `%LOCALAPPDATA%\Window Cascade\settings.ini` keep their existing paths.

## focus-tab gestures

pressing a tab focuses its window immediately. while held, that tab stays visible and follows a small, bounded horizontal preview; the application window itself does not move. releasing after a deliberate left/right swipe rotates one previous/next layer in that slot. small movement, mostly vertical movement, or returning near the starting point is an ordinary focus click. a single-window slot does not rotate.

the default threshold is 36 screen-coordinate pixels, with horizontal travel at least 1.5 times the vertical travel. `focus_tab_*` settings control the threshold, preview, opacity, and gesture-only polling interval. no speed requirement or repeating rotation is applied.

`controls.ahk` pairs mouse-down and mouse-up through AutoHotkey's mouse hook, rather than relying on foreground-only mouse capture after another process has been activated. the press records the overlay, target HWND, monitor, and slot. release belongs to that gesture even outside the tab; ordinary clicks elsewhere retain their native behavior. cancelling with Escape, losing focus, or invalidating the target cancels rotation, but still consumes the matching release. reload/exit clears the preview and stops the gesture timer.

focus-tab colors are selected separately for the active and inactive slots from the tray. the selections persist under `[FocusTabs]` in `%LOCALAPPDATA%\Window Cascade\settings.ini`; defaults are Green for the active slot and Grey for inactive slots.

## checking a change

from the repository root, run:

````powershell
./validate.ps1
````

this validates the root scripts and their include trees. do not validate or launch the module files separately.

Window Cascade seeds windows already open at startup for discovery but does not automatically adopt them into the managed cascade. test placement with newly opened windows or explicitly adopt an existing window.

for Window Cascade changes, check:

- new-window placement and delayed window startup
- focus tabs: instant focus on press, visible held tab, and normal hiding on release
- swipes: left/right on release, one layer per gesture, small/vertical/back-to-start movement, and single-window slots
- release outside the tab or on another monitor; ordinary app clicks and drags must remain unaffected
- cancel with Escape, focus another app, close/minimize/move the target, and reload/exit while holding
- slot swaps, slot/layer rotation, and exposed-stack ordering
- minimize/restore and automatic placement reset
- adoption and the one-shot adoption undo path
- gathering and cross-monitor moves
- pause/resume behavior and compatibility checks
- tray help, rotate-key selection, and focus-tab color selection/persistence
- required CapsLock Layer behavior during startup, quick reloads, and a sustained dependency loss

avoid close-scope tests with unsaved work. syntax validation does not replace Windows desktop behavior testing.

## AutoHotkey documentation

- [Include semantics](https://www.autohotkey.com/docs/v2/lib/_Include.htm)
- [Script startup and validation switches](https://www.autohotkey.com/docs/v2/Scripts.htm)
