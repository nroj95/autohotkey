# Window Cascade internals

launch `../window-cascade.ahk`, not the files in this directory. the launcher owns the process, icon, logging setup, startup sequence, registered command handler, and exit callback. these files are explicitly included into that same AutoHotkey v2 script. they are not separate running scripts or independently reusable libraries.

`capslock-layer.ahk` remains a separate, self-contained script and does not require Window Cascade. the dependency is one-way: Window Cascade requires CapsLock Layer for its keyboard command bindings and does not provide standalone keyboard fallbacks.

## where to make changes

| file | responsibility |
| --- | --- |
| `settings.ahk` | defaults, persisted rotate-key and focus-tab color selections, shared runtime state, and CapsLock Layer command IDs. |
| `controls.ahk` | focus-tab mouse bindings, ordinary desktop-click handling, required CapsLock Layer presence/watch logic, and registered-message dispatch. |
| `discovery.ahk` | desktop monitor hints, the startup window snapshot, discovery polling, placement queueing, Windows event hooks, and destroyed-window cleanup. |
| `window-drag.ahk` | native mouse-drag tracking, release-time snap/adopt/release decisions, and deferred-layout recovery. |
| `layout.ahk` | managed history, canonical slot geometry, occupancy, stacks, exposed layers, compaction, and Z-order sorting. |
| `navigation.ahk` | focusing, guarded new-window foreground recovery, swapping, slot/layer rotation, spatial navigation, and bringing a cascade forward. |
| `placement.ahk` | explicit placement, identity-checked readiness retries, new-window placement, and bounded asynchronous stabilization. |
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

all actions happen once on mouse-down. the pressed tab is hidden immediately; the renderer selects the new representative without waiting for mouse-up. holding, dragging, and releasing add no action. there is no swipe preview, temporary opacity/topmost override, or focus-tab Escape binding; keyboard slot/layer rotation is unchanged.

the renderer hides the old representative before showing its replacement. geometry queries stay interruptible; the selection and hide/show handoff run together, and stale foreground or click-generation snapshots are retried.

`controls.ahk` pairs mouse-down and mouse-up through AutoHotkey's mouse hook. hit-testing captures the overlay, target HWND, and foreground HWND before the press handler resolves live slot membership. stale targets are skipped rather than retargeted. even a skipped click owns its matching release outside the tab or after its target closes; ordinary application clicks and drags retain their native behavior. `focus_tab_release_poll_ms` controls a temporary missed-release guard that only clears mouse ownership and never performs a focus/cycle action. reload/exit stops that guard.

focus-tab colors are selected separately for the active and inactive slots from the tray. the selections persist under `[FocusTabs]` in `%LOCALAPPDATA%\Window Cascade\settings.ini`; defaults are Green for the active slot and Grey for inactive slots.

### appearance diagnostics

normal tab rendering changes native opacity only when the desired value changes and repaints changed or newly shown overlays. the opacity cache is updated only after a successful native operation. overlay operations use pure HWNDs so hidden-window lookup does not depend on `DetectHiddenWindows`. the configured opacity values remain unchanged, and deeper tabs do not contribute additional opacity.

when both `debug_enabled` and `debug_verbose_enabled` are enabled, `Focus-tab appearance.` entries are written only when the observed state changes. they include the active window, active-slot window count, click ownership, tab role, color, cached base alpha, native alpha, visibility, topmost state, Z-order predecessor, and rectangle. clicks do not override opacity. compare entries from a faint and a clear state when investigating intermittent appearance changes.

## minimize and restore compaction

`Caps + M` and `Caps + Alt + M` still let newly opened windows form a visible cascade while the saved windows remain minimized. restoring combines those windows into the same slot-preserving compaction plan, filling the exposed layer before retaining surplus background layers.

the shared restore path registers all saved targets before sending restore requests. membership is protected and compaction is deferred while the requests run and the restored windows settle. a temporary watcher checks normal/visible state, actual slot proximity, and unchanged native/DWM rectangles, then queues compaction from the current history; it does not replay an old layout. `cascade_restore_poll_ms`, `cascade_restore_settle_ms`, and `cascade_restore_timeout_ms` default to 50, 200, and 5000 ms. the timeout releases the compaction gate rather than leaving a failed restore permanently blocking the monitor. native restore notifications start the same check for late or individually restored managed windows.

duplicate notifications for the same restore target do not restart the batch deadline. the existing one-second discovery fallback also detects missed minimized-to-restored transitions and re-arms eligible queued compaction. membership scans keep live windows after a failed geometry query and cannot replace newer membership with an older snapshot. a saved minimized set no longer suppresses layout work for newly opened visible windows on that monitor.

independently minimized windows are not restored. closed, moved-out, re-minimized, or manually dragged targets stop holding the restore batch; cleanup stops the watcher when no targets remain. `Cascade restore reconciliation.` debug entries report completion or timeout. drop-slot preferences and the single drag/drop tolerance are unchanged.

## scoped close batching

`Caps + F4` and `Caps + Alt + F4` register their full close scope before sending any `WinClose` requests. destroy events remove windows from that batch, while layout compaction for the affected monitor stays deferred. the final destroyed target releases the batch and allows one queued compaction, so the cascade does not repeatedly reflow between individual closes.

## window drag and drop

`cascade_slot_tolerance` is the single membership/drop tolerance, defaulting to 56 screen-coordinate pixels on each axis. the old separate release tolerance is removed. slot proximity is measured from the window's visible top-left corner, not the pointer. among eligible canonical positions, the nearest position by squared distance wins; equal distances prefer the earlier slot.

a native mouse drag preserves its starting cascade membership and logical slot until the move loop finishes and the mouse button is released. passing outside the tolerance while still holding does not remove the window. focus tabs for the dragged window are hidden, compaction is deferred, and old placement corrections are cancelled so they cannot fight the drag.

on release near a slot, the window snaps to that exact canonical position and the normal monitor-relative cascade size. this can move an existing member, re-adopt a released window, or adopt another eligible normal application window. the destination monitor must already have a visible cascade; the last managed window can also return to its own cascade. dropping elsewhere leaves the window unmanaged at the dropped position. ordinary clicks, content drags and edge resizes do not adopt windows; Escape retains native cancellation behavior.

a successful drop queues slot-preserving compaction on the affected cascades after the drag finishes. existing windows stay in their slots wherever possible; surplus background windows fill holes and balance the layers instead of the whole cascade being flattened and reassigned. the most recent dropped window has priority in the destination monitor's queued compaction, even if focus changes or compaction waits for a close batch. later manual drops and keyboard commands can still rearrange windows; this is not a permanent per-window pin.

with at least one full layer of managed windows, the dropped window stays in the selected slot. with fewer windows than slots, only the first N canonical positions are retained for N managed windows: a drop into that range stays there, while a drop beyond it moves inward to keep the cascade compact. minimized members still count toward that total and are not restored just to fill visible gaps. later compactions preserve each slot's front windows and move only surplus layers as needed.

placement correction follows each window's final destination. dropped-out windows stay known/handled, so merely focusing or showing them again does not auto-adopt them.

`Caps + Insert` remains available for explicit adoption and re-slotting, and newly opened windows still use normal automatic placement. pause still controls automatic new-window placement; intentional drag/drop remains a manual operation. keyboard cascade commands are held off during a native move/resize interaction. the temporary drag watcher stops on completion, cancellation, destruction, or script exit.

## foreground recovery and performance

new-window placement remains non-activating. discovery retains focus context when a new window is already foreground or appears within `new_window_focus_timeout_ms` (3000 ms) of a taskbar mouse press. taskbar correlation is a recent-input heuristic, not proof of which process the taskbar launched. background launches without that context or observed foreground ownership are not activated.

SHOW and FOREGROUND WinEvents can arrive in either order. a foreground event for a pending placement records ownership on that request and starts recovery immediately, without waiting for placement to finish. `context.recovery_started` prevents the later placement call from restarting recovery, including after user interaction has cancelled it. the watcher accepts the same live HWND/PID while it is pending placement or managed.

the watcher polls at `new_window_focus_poll_ms` (100 ms). the shell-settle period is bounded by `new_window_shell_settle_ms` (5000 ms), measured from recovery start rather than added after the ordinary timeout. reclaiming focus during that period requires prior foreground ownership and a current shell/taskbar foreground window. switching to any real application, including the original launch source, cancels recovery. mouse clicks, Caps commands, window drags, focus-tab clicks, closed/minimized targets, and identity changes also cancel it. mouse buttons, Ctrl, Alt, and Win modifiers block activation attempts; Shift alone does not postpone recovery.

the shell-settle path tries `SetForegroundWindow` first. after three consecutive denials, it may call AutoHotkey's `WinActivate` once per request. ordinary attempts may continue until the settle deadline, but the stronger fallback is not repeated. `WinActivate` performs its own short retries and may synthesize Alt as part of its built-in workaround; it is not a modifier-free call. keep it in this guarded recovery path rather than adding startup key injection or relying on a close command to make later activation work. the script does not add input-queue attachment, fake focus messages, permanent topmost overrides, or foreground-lock registry changes. recovery logs report the attempted method and observed focus state, not a guarantee that Windows always permits activation.

`Caps + Delete` closes the active window with `WinClose("A")`, without sending Alt+F4. application-specific close handling still applies. a foreground target's stale marker is hidden immediately; the overlay renderer still selects the next layer's tab independently. an active-slot tab for a deeper layer remains intentional and does not by itself indicate failed focus.

ordinary lifecycle/error logging stays enabled. focus recovery, placement, restore reconciliation, compaction, and destruction of pending/handled/managed windows remain visible in the normal log. `debug_verbose_enabled` defaults to false; raw show/poll events, unrelated or repeated destroy events, and expensive title/appearance snapshots are opt-in. destruction is always processed even when its log entry is suppressed. foreground diagnostics retain the foreground HWND, thread-active HWND, keyboard-focus HWND/root, and process IDs, and skip native diagnostic queries when logging is disabled. the temporary placement `foreground-before` / `foreground-after` probes are removed.

`SetWinDelay 0` yields without AutoHotkey's default per-window 100 ms sleep; restore/placement watchers still decide readiness explicitly. a focus-tab pass uses one observed rectangle per candidate and one canonical geometry calculation per monitor. minimized overlays are cached/hidden rather than repeatedly destroyed, and unchanged opacity/Z-order operations are skipped. per-window placement requests retain object identity through retries so stale callbacks cannot target a later request for a recycled handle. placement confirmation stops after `placement_stabilize_confirmation_limit` (3) final checks instead of polling forever. no Windows desktop timing benchmark is implied by these source-level optimizations.

## checking a change

from the repository root, run:

````powershell
./validate.ps1
````

this validates the root scripts and their include trees. do not validate or launch the module files separately.

Window Cascade seeds windows already open at startup for discovery but does not automatically adopt them into the managed cascade. test placement with newly opened windows or explicitly adopt an existing window.

for Window Cascade changes, check:

- new-window placement and delayed window startup; duplicate discovery and cancelled/recycled-HWND retries
- minimize the cascade, then launch one to three windows beside unrelated/FancyZones windows
- Shift + taskbar launch: keep Shift held for several seconds, verify the new window remains typeable and its single-layer tab stays hidden; switching/clicking elsewhere must cancel recovery
- fresh-process focus recovery: reload Window Cascade, test the first launch before using any close command, then repeat after both Alt + F4 and Caps + Delete
- deny/delay activation and inspect the foreground diagnostic; background launches must not steal focus
- focus tabs: at most one visible tab per monitor/slot, correct exposed/next-layer target, and stable opacity across stack depths
- focus-tab clicks: inactive slots focus without rotation; repeated active-slot clicks visit all layers in a three-or-more-window stack
- focus-tab handoff: no overlapping replacement, immediate single-layer tab disappearance, and full-height marker preserved after rotation
- holding/dragging/releasing: no preview or repeat action; release outside the tab or on another monitor is still consumed
- ordinary app clicks/drags and Escape retain native behavior; also test close/minimize/move, focus changes, and reload/exit while holding
- slot swaps, slot/layer rotation, and exposed-stack ordering
- scoped closes: current layer and full monitor close without intermediate compaction
- drop-slot preservation: exactly one full layer and multiple layers; other windows fill gaps without moving the dropped window
- partial layer: drops within the first N slots stay put; drops beyond that range compact inward
- deferred drops: change focus, close other windows, or finish a close batch before compaction; minimized members stay hidden
- mouse drops: 14/15/55/56 px offsets all snap with the same tolerance; outside every slot releases only on mouse-up
- drag away and back while still held; drag to another slot/monitor; no mid-drag pruning, reflow, or corrective move
- adopt an unmanaged window by dropping near an existing cascade; outside/empty-monitor drops remain unmanaged
- cancelled drags, edge resizing, rapid successive drags, target closure, and delayed new-window placement during a drag
- minimize/restore and automatic placement reset
- hide a partial/full cascade with Caps + M, open new windows, restore: earlier slots/layers fill before surplus layers remain
- repeat with Caps + Alt + M across monitors; closed or independently minimized windows must not be revived
- slow restores, rapid re-minimize, drag during restore, and close-batch deferral: no lost membership or permanent compaction lock
- missed restore notifications and interrupted queued work: the existing slow fallback recovers the pending merge
- unchanged layouts/tabs should not keep issuing opacity writes or restarting placement corrections
- adoption and the one-shot adoption undo path
- gathering and cross-monitor moves
- pause/resume behavior and compatibility checks
- tray help, rotate-key selection, and focus-tab color selection/persistence
- required CapsLock Layer behavior during startup, quick reloads, and a sustained dependency loss

avoid close-scope tests with unsaved work. syntax validation does not replace Windows desktop behavior testing.

## AutoHotkey documentation

- [Include semantics](https://www.autohotkey.com/docs/v2/lib/_Include.htm)
- [Script startup and validation switches](https://www.autohotkey.com/docs/v2/Scripts.htm)
- [WinActivate retries and modifier workaround](https://www.autohotkey.com/docs/v2/lib/WinActivate.htm)
- [WinClose behavior](https://www.autohotkey.com/docs/v2/lib/WinClose.htm)
