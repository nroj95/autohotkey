#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn


; =============================================================================
; terminology
; =============================================================================
; - cascade: all managed cascade windows on one monitor.
; - slot: one canonical cascade position on that monitor.
; - stack: all windows currently sharing one slot.
; - layer: one depth across the slot stacks; depth 1 is the exposed layer.
; - slots and layers compact automatically so earlier positions stay filled.
; =============================================================================


; =============================================================================
; mission
; =============================================================================
; - detect new normal top-level windows through hooks and a polling fallback.
; - preserve the queued monitor through readiness retries and startup settling.
; - place them on the monitor where the user was already working.
; - detect desktop clicks from the window under the cursor, independent of foreground timing.
; - ignore the application's remembered position and size.
; - give managed windows a consistent monitor-relative size.
; - center the first managed window on each monitor.
; - define fixed cascade slots: center, then left/up, then right/down.
; - inspect actual window positions whenever a new window opens.
; - fill the least-used canonical slot so gaps are repaired before a new layer grows.
; - treat stack depth as layers: one window per slot at each depth.
; - keep focus/swap/close controls local; Caps + M minimizes/restores every monitor.
; - compact holes forward across slots and layers after managed windows disappear.
; - rotate one slot across layers or rotate every slot to expose the next layer.
; - focus and swap current-layer windows by physical top-to-bottom order.
; - resolve mouse drops once: snap/adopt near a slot, otherwise leave the cascade.
; - move, auto-adopt, and smart-sort windows across monitors with Caps + Alt + Left/Right.
; - reject obvious child/helper windows before queueing placement.
; - forget destroyed window handles so recycled hwnd values remain safe.
; - require the running CapsLock Layer for all keyboard controls.
; - offer no standalone keyboard bindings or persistent command mode.
; =============================================================================


Persistent

; Readiness watchers handle settling explicitly. Yield without the default
; 100 ms sleep after each window command; do not use a busy-looping -1 delay.
SetWinDelay 0

A_IconTip := "Window Cascade"
; Keep the custom icon while our own paused state suspends mouse hotkeys.
try TraySetIcon(A_ScriptDir "\icons\window-cascade.ico", , true)

; Use virtual-screen coordinates so multi-monitor mouse positions match MonitorGet().
CoordMode "Mouse", "Screen"


; Initialize shared settings/state before registering an exit handler or callbacks.
#Include "%A_ScriptDir%\window-cascade\settings.ahk"

InitializeDebugLogging()
OnExit(HandleScriptExit)


; =============================================================================
; startup
; =============================================================================

; Wait briefly for startup ordering, but never launch CapsLock Layer implicitly.
RequireCapsLockLayer()

BuildTrayMenu()

RegisterIntegrationMessages()

InitializeCascadeDisplays()

SeedStartupWindows()

StartWindowHooks()

SetTimer(WatchCapsLockLayer, caps_layer_check_ms)

; The hooks retain lightweight lifetime bookkeeping while paused. Work timers
; are shared with the resume path and start only while the cascade is enabled.
if IsCascadeEnabled() {
    StartCascadeActivity()
    SetTimer(CheckCompatibilitySettings, -500)
}


; =============================================================================
; internal modules
; =============================================================================
; These files are parts of this script, not separate scripts to launch.
; Keep all includes here; feature modules do not include each other.

#Include "%A_ScriptDir%\window-cascade\controls.ahk"
#Include "%A_ScriptDir%\window-cascade\discovery.ahk"
#Include "%A_ScriptDir%\window-cascade\window-drag.ahk"
#Include "%A_ScriptDir%\window-cascade\layout.ahk"
#Include "%A_ScriptDir%\window-cascade\navigation.ahk"
#Include "%A_ScriptDir%\window-cascade\placement.ahk"
#Include "%A_ScriptDir%\window-cascade\commands.ahk"
#Include "%A_ScriptDir%\window-cascade\suspension.ahk"
#Include "%A_ScriptDir%\window-cascade\focus-corners.ahk"
#Include "%A_ScriptDir%\window-cascade\focus-tab-clicks.ahk"
#Include "%A_ScriptDir%\window-cascade\windows.ahk"
#Include "%A_ScriptDir%\window-cascade\dpi.ahk"
#Include "%A_ScriptDir%\window-cascade\display.ahk"
#Include "%A_ScriptDir%\window-cascade\interface.ahk"
#Include "%A_ScriptDir%\window-cascade\debug.ahk"


; =============================================================================
; script cleanup
; =============================================================================

HandleScriptExit(exit_reason, exit_code)
{
    global caps_layer_dependency_lost, focus_corner_overlays

    SetTimer(WatchCapsLockLayer, 0)
    try StopFocusTabClick()
    try StopWindowHooks()
    try StopCascadeDisplays()

    ; Never strand script-hidden windows when their in-memory restore set is lost.
    ; This is a plain restore, not a final cascade layout or focus operation.
    RestoreMinimizedCascadeWindowsOnExit()

    if exit_reason = "Exit" && caps_layer_dependency_lost {
        for hwnd, overlay in focus_corner_overlays
            try overlay.gui.Hide()

        ; OnExit does not allow timers/hotkeys to resume while this notice is open.
        MsgBox(
            "Window Cascade stopped because CapsLock Layer is not running.`n`n"
            . "Any windows minimized by Caps + M were restored where possible.`n"
            . "Start capslock-layer.ahk, then relaunch window-cascade.ahk.",
            "Window Cascade",
            "Icon!"
        )
    }
}
