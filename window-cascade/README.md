# Window Cascade internals

launch `../window-cascade.ahk`, not the files in this directory. the launcher owns the process, icon, logging setup, startup sequence, registered command handler, and exit callback. these files are explicitly included into that same AutoHotkey v2 script. they are not separate running scripts or independently reusable libraries.

`capslock-layer.ahk` remains a separate, self-contained script and does not require Window Cascade. the dependency is one-way: Window Cascade requires CapsLock Layer for its keyboard command bindings and does not provide standalone keyboard fallbacks.

## where to make changes

| file | responsibility |
| --- | --- |
| `settings.ahk` | defaults, persisted rotate-key and focus-tab color selections, shared runtime state, debug settings, and CapsLock Layer command IDs. |
| `controls.ahk` | focus-tab mouse bindings, ordinary desktop-click handling, required CapsLock Layer presence/watch logic, and registered-message dispatch. |
| `discovery.ahk` | desktop monitor hints, the startup window snapshot, discovery polling, placement queueing, Windows event hooks, and destroyed-window cleanup. |
| `window-drag.ahk` | native mouse-drag tracking, release-time snap/adopt/release decisions, and deferred-layout recovery. |
| `layout.ahk` | managed history, canonical slot geometry, occupancy, stacks, exposed layers, compaction, and Z-order sorting. |
| `navigation.ahk` | focusing, guarded new-window foreground recovery, swapping, slot/layer rotation, spatial navigation, and bringing a cascade forward. |
| `placement.ahk` | explicit placement, identity-checked readiness retries, new-window placement, and bounded asynchronous stabilization. |
| `commands.ahk` | adoption and one-shot adoption undo, gathering, cross-monitor moves, monitor-wide close commands, restore settling, and membership cleanup. |
| `suspension.ahk` | the global Caps + M disable/resume state, identity-checked restore set, activity cancellation, and disabled-time lifecycle bookkeeping. |
| `focus-corners.ahk` | one visible tab per slot, overlay lifetime and position, representative handoff, and active-slot coloring. |
| `focus-tab-clicks.ahk` | instant press-to-focus/cycle, live target validation, mouse-release pairing, and missed-release recovery. |
| `windows.ahk` | window filtering, visible/raw frame geometry, monitor lookup, and monitor-selection policy. |
| `dpi.ahk` | scoped physical-pixel API calls, per-monitor DPI probes, and display snapshots. |
| `display.ahk` | coalesced live display refresh, runtime slot preservation, and deferred geometry updates without reload. |
| `interface.ahk` | tray menu, help and its custom icon, startup shortcut, rotate-key and focus-tab color persistence, and compatibility checks. |
| `debug.ahk` | logging, log-reset messages, error reporting, and diagnostic window descriptions. |

## initialization and dependencies

only `settings.ahk` contains top-level state initialization. the launcher includes it before building the tray menu, registering the command handler, seeding existing windows, installing window hooks, and starting timers.

the remaining modules primarily contain function definitions and event/message entry points. all includes are explicit in the launcher; modules do not include each other. the launcher anchors include paths to `A_ScriptDir` so they do not depend on the shell's current directory.

keyboard commands are owned by CapsLock Layer and delivered to Window Cascade through the registered command interface. keep that separation intact when adding or moving shortcuts.

## integration contracts and paths

keep the `cascade_command_*` IDs in `settings.ahk` synchronized with the matching constants in `capslock-layer.ahk`. they intentionally remain duplicated so CapsLock Layer has no include dependency on Window Cascade.

`WindowCascade.Command`, the CapsLock Layer presence mutex, and the registered-message parameter contract form the cross-process integration surface. cross-monitor commands pass the original active window handle through that message path so the intended window remains the move target.

`WindowCascade.RotateKeyChanged` broadcasts the committed rotate-key setting: `wParam = 1` means Space, `wParam = 2` means Tab, and `lParam = 0`. Window Cascade announces it at startup and after a successful tray-menu change. CapsLock Layer reads the persisted setting at startup, then uses this notification so its `#HotIf` predicate stays memory-only. reload both scripts after editing the INI externally; tray changes apply without a reload. the existing command IDs are unchanged.

the launcher remains at the repository root. startup shortcuts and `icons/window-cascade.ico` keep their existing paths. Window Cascade stores `settings.ini` and `window-cascade-debug.log` under `%LOCALAPPDATA%\Window Cascade`.

## focus-tab clicks

each monitor/slot shows at most one focus tab. an inactive slot represents its exposed window; the active slot represents the next layer below the foreground window. a focused single-layer slot has no tab. deeper layers remain managed but their tabs stay hidden, so opacity no longer indicates stack depth. the full-height marker follows the highest slot regardless of which layer represents it.

pressing an inactive slot's tab focuses its exposed window immediately. pressing the active slot's tab rotates the foreground window to the back of that slot's stack and focuses the next layer. repeated clicks visit every layer in order (A -> B -> C -> A), rather than alternating between the first two windows.

all actions happen once on mouse-down. the pressed tab is hidden immediately; the renderer selects the new representative without waiting for mouse-up. holding, dragging, and releasing add no action. there is no swipe preview, temporary opacity/topmost override, or focus-tab Escape binding; keyboard slot/layer rotation is unchanged.

the renderer hides the old representative before showing its replacement. geometry queries stay interruptible; the selection and hide/show handoff run together, and stale foreground or click-generation snapshots are retried.

`controls.ahk` pairs mouse-down and mouse-up through AutoHotkey's mouse hook. hit-testing captures the overlay, target HWND, and foreground HWND before the press handler resolves live slot membership. stale targets are skipped rather than retargeted. even a skipped click owns its matching release outside the tab or after its target closes; ordinary application clicks and drags retain their native behavior. `focus_tab_release_poll_ms` controls a temporary missed-release guard that only clears mouse ownership and never performs a focus/cycle action. reload/exit stops that guard.

focus-tab colors are selected separately for the active and inactive slots from the tray. the selections persist under `[FocusTabs]` in `%LOCALAPPDATA%\Window Cascade\settings.ini`; defaults are Green for the active slot and Grey for inactive slots.

### appearance diagnostics

focus-tab GUIs are created per-monitor DPI-aware with `-DPIScale`. their anchor coordinates and full-height bounds use physical pixels; thickness, overlap, and short-marker height are 96-DPI UI dimensions scaled once for the target monitor. cloaked target windows are excluded from rendering and live click activation, without discarding their managed membership. an overlay pass with no visible slot candidates skips the global Z-order enumeration.

normal tab rendering changes native opacity only when the desired value changes and repaints changed or newly shown overlays. the opacity cache is updated only after a successful native operation. overlay operations use pure HWNDs so hidden-window lookup does not depend on `DetectHiddenWindows`. the configured opacity values remain unchanged, and deeper tabs do not contribute additional opacity.

**Verbose debug logging** in the tray toggles `debug_verbose_enabled` for the current run only and defaults to off after every restart. when verbose logging is enabled, `Focus-tab appearance.` entries are written only when the observed state changes. they include the active window, active-slot window count, click ownership, tab role, color, cached base alpha, native alpha, visibility, topmost state, Z-order predecessor, and rectangle. clicks do not override opacity. compare entries from a faint and a clear state when investigating intermittent appearance changes.

## global disable and resume

`Caps + M` is one toggle for **all managed layers on all monitors**. the first press minimizes the currently visible managed windows, hides every focus tab, and disables cascade commands, mouse bindings, automatic placement, drag/drop snapping, compaction, and placement/focus recovery. it also disables an empty cascade. closing all saved windows does not implicitly resume the script.

while disabled, `Caps + M` remains available from any foreground window, including a maximized/fullscreen application. other cascade keyboard commands are ignored. the tray's **Disable cascade** item invokes the same toggle, not a second pause setting. CapsLock Layer's unrelated extra-key mappings, Terminal macros, and Caps Lock gesture remain available.

on resume, only still-minimized windows from this toggle's saved HWND/PID set are restored, in saved Z-order. independently minimized windows are not restored. closing a saved window or manually restoring it while disabled removes it from that restore set. windows opened while disabled remain unmanaged after resume; focusing them later does not adopt them. use `Caps + Insert` for explicit adoption.

the receiver and minimal window-lifetime bookkeeping remain alive so resume and closed-window cleanup still work. periodic cascade activity stops; pending placement requests and stabilization generations are invalidated so delayed callbacks cannot replay old work. full-process `Pause` is not used. the existing dependency watcher still exits safely if CapsLock Layer remains unavailable beyond its reload grace period.

a native mouse drag or an unfinished focus-tab click must finish before the toggle is accepted. the disabled state is runtime-only, not a persisted setting. reload/exit restores any still-minimized windows owned by this toggle before discarding its state, without recascading unrelated windows.

### restore settling and compaction

the shared restore path registers all saved targets across monitors before sending any restore requests. membership is protected and compaction is deferred while the requests run and the restored windows settle. the existing watcher checks normal/visible state, actual slot proximity, and unchanged native/DWM rectangles, then queues compaction from current membership rather than replaying an old layout. `cascade_restore_poll_ms`, `cascade_restore_settle_ms`, and `cascade_restore_timeout_ms` remain 50, 200, and 5000 ms.

closed, moved-out, re-minimized, or manually dragged targets stop holding a restore batch. the timeout releases the compaction gate instead of leaving a failed restore permanently blocking a monitor. the discovery fallback still reconciles missed restore notifications when enabled. drop-slot preferences and the shared drag/drop tolerance remain unchanged.

## scoped close batching

`Caps + F4` closes all managed layers on the command monitor, using the former full-monitor close scope. it registers that whole HWND/PID scope before sending any `WinClose` requests. the former current-layer close command and the Alt variant are removed. destroy events remove windows from that batch, while layout compaction for the affected monitor stays deferred. the final destroyed target releases the batch and allows one queued compaction, so the cascade does not repeatedly reflow between individual closes.

if a close is cancelled, ignored, or fails, `cascade_close_timeout_ms` releases the remaining batch after 5000 ms from the end of request dispatch. this is only a compaction grace period: it never dismisses a save prompt, retries the close, or kills an application. a still-open save prompt does not keep compaction blocked indefinitely. stale expiration callbacks cannot clear a newer batch. disabling the cascade also clears old close-batch gates, and an interrupted close loop sends no further requests once it observes the disabled state.

`Caps + F7` gathers the other monitors' cascades onto the command monitor. the former `Caps + Alt + F7` modifier is removed; the plain command is also available through the one-shot Caps layer.

## window drag and drop

`cascade_slot_tolerance` is the single membership/drop tolerance, defaulting to 56 screen-coordinate pixels on each axis. the old separate release tolerance is removed. slot proximity is measured from the window's visible top-left corner, not the pointer. among eligible canonical positions, the nearest position by squared distance wins; equal distances prefer the earlier slot.

a native mouse drag preserves its starting cascade membership and logical slot until the move loop finishes and the mouse button is released. passing outside the tolerance while still holding does not remove the window. focus tabs for the dragged window are hidden, compaction is deferred, and old placement corrections are cancelled so they cannot fight the drag.

on release near a slot, the window snaps to that exact canonical position and the normal monitor-relative cascade size. this can move an existing member, re-adopt a released window, or adopt another eligible normal application window. the destination monitor must already have a visible cascade; the last managed window can also return to its own cascade. dropping elsewhere leaves the window unmanaged at the dropped position. ordinary clicks, content drags and edge resizes do not adopt windows; Escape retains native cancellation behavior.

a successful drop queues slot-preserving compaction on the affected cascades after the drag finishes. existing windows stay in their slots wherever possible; surplus background windows fill holes and balance the layers instead of the whole cascade being flattened and reassigned. the most recent dropped window has priority in the destination monitor's queued compaction, even if focus changes or compaction waits for a close batch. later manual drops and keyboard commands can still rearrange windows; this is not a permanent per-window pin.

with at least one full layer of managed windows, the dropped window stays in the selected slot. with fewer windows than slots, only the first N canonical positions are retained for N managed windows: a drop into that range stays there, while a drop beyond it moves inward to keep the cascade compact. minimized members still count toward that total and are not restored just to fill visible gaps. later compactions preserve each slot's front windows and move only surplus layers as needed.

placement correction follows each window's final destination. dropped-out windows stay known/handled, so merely focusing or showing them again does not auto-adopt them.

`Caps + Insert` remains available for explicit adoption and re-slotting, and newly opened windows still use normal automatic placement. global disable stops both automatic new-window placement and intentional cascade drag/drop. keyboard cascade commands are held off during a native move/resize interaction. the temporary drag watcher stops on completion, cancellation, destruction, or script exit.

## foreground recovery and performance

bringing a cascade forward preserves each window's pre-existing always-on-top setting; only temporarily promoted normal windows are returned to the normal Z-order band.

new-window placement remains non-activating. discovery retains focus context when a new window is already foreground or appears within `new_window_focus_timeout_ms` (3000 ms) of a taskbar mouse press. taskbar correlation is a recent-input heuristic, not proof of which process the taskbar launched. background launches without that context or observed foreground ownership are not activated.

SHOW and FOREGROUND WinEvents can arrive in either order. a foreground event for a pending placement records ownership on that request and starts recovery immediately, without waiting for placement to finish. `context.recovery_started` prevents the later placement call from restarting recovery, including after user interaction has cancelled it. the watcher accepts the same live HWND/PID while it is pending placement or managed.

the watcher polls at `new_window_focus_poll_ms` (100 ms). the shell-settle period is bounded by `new_window_shell_settle_ms` (5000 ms), measured from recovery start rather than added after the ordinary timeout. reclaiming focus during that period requires prior foreground ownership and a current shell/taskbar foreground window. switching to any real application, including the original launch source, cancels recovery. mouse clicks, Caps commands, window drags, focus-tab clicks, closed/minimized targets, and identity changes also cancel it. mouse buttons, Ctrl, Alt, and Win modifiers block activation attempts; Shift alone does not postpone recovery.

the shell-settle path tries `SetForegroundWindow` first. after three consecutive denials, it may call AutoHotkey's `WinActivate` once per request. ordinary attempts may continue until the settle deadline, but the stronger fallback is not repeated. `WinActivate` performs its own short retries and may synthesize Alt as part of its built-in workaround; it is not a modifier-free call. keep it in this guarded recovery path rather than adding startup key injection or relying on a close command to make later activation work. the script does not add input-queue attachment, fake focus messages, permanent topmost overrides, or foreground-lock registry changes. recovery logs report the attempted method and observed focus state, not a guarantee that Windows always permits activation.

`Caps + Delete` closes the active window with `WinClose("A")`, without sending Alt+F4. application-specific close handling still applies. a foreground target's stale marker is hidden immediately; the overlay renderer still selects the next layer's tab independently. an active-slot tab for a deeper layer remains intentional and does not by itself indicate failed focus.

ordinary lifecycle/error logging stays enabled and writes to `%LOCALAPPDATA%\Window Cascade\window-cascade-debug.log`. focus recovery, placement, restore reconciliation, compaction, and destruction of pending/handled/managed windows remain visible in the normal log. **Verbose debug logging** in the tray toggles `debug_verbose_enabled` for the current run only and defaults to false after every restart; raw show/poll events, unrelated or repeated destroy events, and expensive title/appearance snapshots are opt-in. destruction is always processed even when its log entry is suppressed. foreground diagnostics retain the foreground HWND, thread-active HWND, keyboard-focus HWND/root, and process IDs, and skip native diagnostic queries when logging is disabled. the temporary placement `foreground-before` / `foreground-after` probes are removed.

`SetWinDelay 0` yields without AutoHotkey's default per-window 100 ms sleep; restore/placement watchers still decide readiness explicitly. a focus-tab pass uses one observed rectangle per candidate and one canonical geometry calculation per monitor. minimized overlays are cached/hidden rather than repeatedly destroyed, and unchanged opacity/Z-order operations are skipped. per-window placement requests retain object identity through retries so stale callbacks cannot target a later request for a recycled handle. placement confirmation stops after `placement_stabilize_confirmation_limit` (3) final checks instead of polling forever. no Windows desktop timing benchmark is implied by these source-level optimizations.

## physical pixels and live display changes

all monitor/work-area bounds, cursor positions, raw window rectangles, and external geometry changes use a short per-monitor DPI-aware context through `dpi.ahk`. DWM visible-frame bounds are already physical pixels. each wrapper restores the caller's previous DPI context in `finally`, including the native error code. this is not a process-wide awareness change: the normal help GUI stays system-DPI-aware. the DPI path requires Windows 10 version 1607 or later.

there are no per-percentage presets. window width/height remain the configured fraction of the physical work area. slot offsets, edge margins, minimum sizes, and the 56-pixel drop tolerance keep their existing physical-pixel meaning. only the focus-tab UI dimensions use `Round(value * dpi / 96)`. tab repaint caching includes DPI, even when the target rectangle has not changed.

a hidden, control-free per-monitor-aware probe on each monitor supplies that monitor's effective DPI. querying an external app's HWND directly would return 96 for an unaware app or the system DPI for a system-aware app, so it cannot reliably size our overlays. the same monitor-based reading distinguishes cross-DPI drag resizing from an ordinary edge resize. probes never adopt windows, receive focus deliberately, or appear in the taskbar.

`WM_DISPLAYCHANGE`, `WM_SETTINGCHANGE`, our own probes' `WM_DPICHANGED`, and resume notifications coalesce a refresh. messages sent to foreign applications are not received through our `OnMessage` handlers. the existing one-second discovery fallback checks the monitor snapshot too; there is no additional permanent fast display timer. live monitor checks before membership pruning also protect against a late notification.

**changing display scaling does not reload Window Cascade.** a DPI-only refresh leaves the history map and its arrays in place. a runtime HWND/PID slot record remembers each member's last intended slot while Windows is resizing applications. affected visible normal windows are moved asynchronously with no activation or Z-order change. minimized, hidden, or cloaked members retain their destination until they become visible again; the script does not restore them just to update geometry. disabled cascades keep their saved restore set and defer moves until resumed. drags and unfinished focus-tab clicks also defer reflow, and manual dragging takes ownership of its target.

monitor indices are remapped using the display device names in the current session. if a display disappears, its managed members use the current primary display; if fewer canonical slots fit, an old slot is clamped to the last available slot. this is not persistent monitor/EDID matching, and reconnecting a display does not automatically send windows back to their former screen. stale monitor-index batch gates are cleared on a topology remap, not on an ordinary DPI-only refresh.

cross-DPI placement can still be followed by the target application's own DPI resize. the existing generation-checked stabilization path permits up to three prompt corrections, then returns to its original bounded backoff. a DPI transfer needs a second matching check before its reservation is released. display changes invalidate superseded corrections and pending new-window requests resolve their saved monitor device again. no state is written to disk to support this behavior.

## checking a change

from the repository root, run:

````powershell
./validate.ps1
````

this validates the root scripts and their include trees. do not validate or launch the module files separately.

Window Cascade seeds windows already open at startup for discovery but does not automatically adopt them into the managed cascade. test placement with newly opened windows or explicitly adopt an existing window.

for Window Cascade changes, check:

- new-window placement and delayed window startup; duplicate discovery and cancelled/recycled-HWND retries
- disable with Caps + M, launch one to three windows, and verify no automatic placement or cascade drag snapping
- Shift + taskbar launch: keep Shift held for several seconds, verify the new window remains typeable and its single-layer tab stays hidden; switching/clicking elsewhere must cancel recovery
- fresh-process focus recovery: reload Window Cascade, test the first launch before using any close command, then repeat after both Alt + F4 and Caps + Delete
- deny/delay activation and inspect the foreground diagnostic; background launches must not steal focus
- focus tabs: at most one visible tab per monitor/slot, correct exposed/next-layer target, and stable opacity across stack depths
- focus-tab clicks: inactive slots focus without rotation; repeated active-slot clicks visit all layers in a three-or-more-window stack
- focus-tab handoff: no overlapping replacement, immediate single-layer tab disappearance, and full-height marker preserved after rotation
- holding/dragging/releasing: no preview or repeat action; release outside the tab or on another monitor is still consumed
- ordinary app clicks/drags and Escape retain native behavior; also test close/minimize/move, focus changes, and reload/exit while holding
- slot swaps, slot/layer rotation, and exposed-stack ordering
- bring a mixed normal/always-on-top cascade forward; existing topmost windows must remain topmost and normal windows must return to the normal band
- Caps + F4: all layers on the current monitor close without intermediate compaction; other monitors stay untouched
- drop-slot preservation: exactly one full layer and multiple layers; other windows fill gaps without moving the dropped window
- partial layer: drops within the first N slots stay put; drops beyond that range compact inward
- deferred drops: change focus, close other windows, or finish a close batch before compaction; minimized members stay hidden
- mouse drops: 14/15/55/56 px offsets all snap with the same tolerance; outside every slot releases only on mouse-up
- drag away and back while still held; drag to another slot/monitor; no mid-drag pruning, reflow, or corrective move
- adopt an unmanaged window by dropping near an existing cascade; outside/empty-monitor drops remain unmanaged
- cancelled drags, edge resizing, rapid successive drags, target closure, and delayed new-window placement during a drag
- Caps + M from multiple monitors and from an empty cascade: disable remains latched until explicitly resumed
- disable a partial/full multi-monitor cascade, open new windows, resume: only saved cascade windows restore and disabled-time launches remain unmanaged
- close or manually restore a saved window while disabled; it must not be revived/re-restored on resume; independently minimized windows stay hidden
- slow restores, rapid re-minimize, drag during restore, and close-batch deferral: no lost membership or permanent compaction lock
- missed restore notifications and interrupted queued work: the existing slow fallback recovers the pending merge
- unchanged layouts/tabs should not keep issuing opacity writes or restarting placement corrections
- adoption and the one-shot adoption undo path
- Caps + F7 gathering and cross-monitor moves
- while disabled: Caps + M resumes; every other cascade shortcut is inert, tabs stay absent, and Win Key Overhaul/Terminal/extra-key controls remain independent
- removed Caps + P, Caps + Alt + M, Caps + Alt + F4, and Caps + Alt + F7 do not invoke cascade commands
- tray help displays icons/window-cascade.ico in its caption/Alt+Tab; Escape and the hotkey both close it without leaking icon handles
- tray Disable cascade mirrors Caps + M; rotate-key and focus-tab color preferences survive disable/resume
- required CapsLock Layer behavior during startup, quick reloads, and a sustained dependency loss
- cancel a save prompt after Caps + F4; verify compaction resumes after the close grace period without forcing the window closed
- overlap close attempts, then disable/resume; an older expiration must not release a newer batch or retain an old gate
- switch virtual desktops; hidden/cloaked targets must not leave clickable tabs behind
- test 100/100, 100/125, and 100/150 monitor pairs: first-window centering, physical 80% sizing, tab alignment, click targets, and cross-monitor keyboard moves/drops
- launch an app on the 100% display and let Cascade place it on the 125%/150% display; test the reverse direction too, including an app that scales itself after the move
- change scaling live with existing multi-layer cascades, without reloading; membership, slots, focus, and internal Z-order should survive once the transition settles
- repeat a live scaling change with an independently minimized member and with Caps + M disabled; neither should be restored merely to update geometry
- change resolution or disconnect a display; check the documented primary-display fallback and slot clamping, then verify fresh launches still work
- change Space/Tab from the Cascade tray with the Caps help GUI open, then reload Caps; the selection must stay synchronized
- hold Caps + Q, add W, release Q while holding W: F13 must release independently of F14; also release Caps first and reload while held
- tap Caps, hold Q, then press W: only Q consumes the one-shot; W stays ordinary and Q does not leak repeat characters
- type uppercase letters using separate left-Shift presses; ordinary shifted typing must not toggle Caps Lock, while a bare double-tap still does
- re-arm Caps while an older consumed key is held; releasing the old key must not cancel the new one-shot
- start a Terminal copy/clear chord, switch apps before releasing it, and verify the new app receives no macro shortcuts
- test normal and failed Terminal copies; a failed copy restores the previous clipboard only while the script's cleared clipboard is unchanged

avoid close-scope tests with unsaved work. syntax validation does not replace Windows desktop behavior testing. wait for the validation process and inspect its actual exit code; a previously printed success line is not a substitute for loading the updated launcher.

## AutoHotkey documentation

- [Include semantics](https://www.autohotkey.com/docs/v2/lib/_Include.htm)
- [Script startup and validation switches](https://www.autohotkey.com/docs/v2/Scripts.htm)
- [WinActivate retries and modifier workaround](https://www.autohotkey.com/docs/v2/lib/WinActivate.htm)
- [WinClose behavior](https://www.autohotkey.com/docs/v2/lib/WinClose.htm)
- [AutoHotkey DPI contexts and GUI scaling](https://www.autohotkey.com/docs/v2/misc/DPIScaling.htm)
- [GetDpiForWindow awareness-dependent results](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getdpiforwindow)
- [WM_DPICHANGED](https://learn.microsoft.com/en-us/windows/win32/hidpi/wm-dpichanged)
