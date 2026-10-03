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
| `focus-corners.ahk` | one visible tab per slot, overlay lifetime and position, representative handoff, and active-slot coloring. |
| `focus-tab-clicks.ahk` | instant press-to-focus/cycle, live target validation, mouse-release pairing, and missed-release recovery. |
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

## focus-tab clicks

each monitor/slot shows at most one focus tab. an inactive slot represents its exposed window; the active slot represents the next layer below the foreground window. a focused single-layer slot has no tab. deeper layers remain managed but their tabs stay hidden, so opacity no longer indicates stack depth. the full-height marker follows the highest slot regardless of which layer represents it.

pressing an inactive slot's tab focuses its exposed window immediately. pressing the active slot's tab rotates the foreground window to the back of that slot's stack and focuses the next layer. repeated clicks visit every layer in order (A -> B -> C -> A), rather than alternating between the first two windows.

all actions happen once on mouse-down. the pressed tab is hidden immediately; the renderer selects the new representative without waiting for mouse-up. holding, dragging, and releasing add no action. there is no swipe preview, temporary opacity/topmost override, or Escape binding; keyboard slot/layer rotation is unchanged.

the renderer hides the old representative before showing its replacement. geometry queries stay interruptible; the selection and hide/show handoff run together, and stale foreground or click-generation snapshots are retried.

`controls.ahk` pairs mouse-down and mouse-up through AutoHotkey's mouse hook. hit-testing captures the overlay, target HWND, and foreground HWND before the press handler resolves live slot membership. stale targets are skipped rather than retargeted. even a skipped click owns its matching release outside the tab or after its target closes; ordinary application clicks and drags retain their native behavior. `focus_tab_release_poll_ms` controls a temporary missed-release guard that only clears mouse ownership and never performs a focus/cycle action. reload/exit stops that guard.

focus-tab colors are selected separately for the active and inactive slots from the tray. the selections persist under `[FocusTabs]` in `%LOCALAPPDATA%\Window Cascade\settings.ini`; defaults are Green for the active slot and Grey for inactive slots.

### appearance diagnostics

normal tab rendering reapplies opacity and repaints changed or newly shown overlays. overlay operations use pure HWNDs so hidden-window lookup does not depend on `DetectHiddenWindows`. the configured opacity values remain unchanged, and deeper tabs do not contribute additional opacity.

when debug logging is enabled, `Focus-tab appearance.` entries are written only when the observed state changes. they include the active window, active-slot window count, click ownership, tab role, color, cached base alpha, native alpha, visibility, topmost state, Z-order predecessor, and rectangle. clicks do not override opacity. compare entries from a faint and a clear state when investigating intermittent appearance changes.

## scoped close batching

`Caps + F4` and `Caps + Alt + F4` register their full close scope before sending any `WinClose` requests. destroy events remove windows from that batch, while layout compaction for the affected monitor stays deferred. the final destroyed target releases the batch and allows one queued compaction, so the cascade does not repeatedly reflow between individual closes.

## manual cascade release

a managed window dragged beyond `cascade_release_tolerance` is removed from cascade history immediately. that release is one-way: dragging the same window over another canonical slot does not re-adopt it. `Caps + Insert` is the explicit way to adopt or re-slot an existing window; newly opened windows still follow normal automatic placement.

## checking a change

from the repository root, run:

````powershell
./validate.ps1
````

this validates the root scripts and their include trees. do not validate or launch the module files separately.

Window Cascade seeds windows already open at startup for discovery but does not automatically adopt them into the managed cascade. test placement with newly opened windows or explicitly adopt an existing window.

for Window Cascade changes, check:

- new-window placement and delayed window startup
- focus tabs: at most one visible tab per monitor/slot, correct exposed/next-layer target, and stable opacity across stack depths
- focus-tab clicks: inactive slots focus without rotation; repeated active-slot clicks visit all layers in a three-or-more-window stack
- focus-tab handoff: no overlapping replacement, immediate single-layer tab disappearance, and full-height marker preserved after rotation
- holding/dragging/releasing: no preview or repeat action; release outside the tab or on another monitor is still consumed
- ordinary app clicks/drags and Escape retain native behavior; also test close/minimize/move, focus changes, and reload/exit while holding
- slot swaps, slot/layer rotation, and exposed-stack ordering
- scoped closes: current layer and full monitor close without intermediate compaction
- manual drag release: crossing the release boundary removes the window and dragging it over another slot does not re-adopt it
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
