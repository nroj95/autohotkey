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
; - keep focus/swap/close controls local while minimize scopes can span one or all monitors.
; - compact holes forward across slots and layers after managed windows disappear.
; - rotate one slot across layers or rotate every slot to expose the next layer.
; - focus and swap current-layer windows by physical top-to-bottom order.
; - let manually moved windows relinquish their old slot automatically.
; - move, auto-adopt, and smart-sort windows across monitors with Caps + Alt + Left/Right.
; - reject obvious child/helper windows before queueing placement.
; - forget destroyed window handles so recycled hwnd values remain safe.
; - optionally accept slot/layer/monitor commands from CapsLock Layer.
; - remain fully functional when CapsLock Layer is not installed or running.
; =============================================================================


Persistent

A_IconTip := "Window Cascade"
try TraySetIcon(A_ScriptDir "\icons\window-cascade.ico")

; Use virtual-screen coordinates so multi-monitor mouse positions match MonitorGet().
CoordMode "Mouse", "Screen"


; =============================================================================
; debug
; =============================================================================

debug_enabled := true
debug_log_path := A_ScriptDir "\window-cascade-debug.log"

InitializeDebugLogging()

OnExit(HandleScriptExit)


; Defaults and shared state must be ready before any startup callbacks run.
#Include "%A_ScriptDir%\window-cascade\settings.ahk"


; =============================================================================
; startup
; =============================================================================

BuildTrayMenu()

RegisterIntegrationMessages()

SeedStartupWindows()

StartWindowHooks()

SetTimer(WatchForMissedWindows, missed_window_poll_ms)

; Window events normally keep focus tabs aligned. Keep a slow timer only as
; insurance for an event that Windows may occasionally fail to deliver.
OnMessage(0x0202, HandleFocusCornerClick) ; WM_LBUTTONUP
SetTimer(UpdateFocusCornerOverlays, focus_corner_fallback_ms)

; FancyZones can directly compete with new-window placement.
SetTimer(CheckCompatibilitySettings, -500)


; =============================================================================
; internal modules
; =============================================================================
; These files are parts of this script, not separate scripts to launch.
; Keep all includes here; feature modules do not include each other.

#Include "%A_ScriptDir%\window-cascade\controls.ahk"
#Include "%A_ScriptDir%\window-cascade\discovery.ahk"
#Include "%A_ScriptDir%\window-cascade\layout.ahk"
#Include "%A_ScriptDir%\window-cascade\navigation.ahk"
#Include "%A_ScriptDir%\window-cascade\placement.ahk"
#Include "%A_ScriptDir%\window-cascade\commands.ahk"
#Include "%A_ScriptDir%\window-cascade\focus-corners.ahk"
#Include "%A_ScriptDir%\window-cascade\windows.ahk"
#Include "%A_ScriptDir%\window-cascade\interface.ahk"
#Include "%A_ScriptDir%\window-cascade\debug.ahk"


; =============================================================================
; script cleanup
; =============================================================================

HandleScriptExit(exit_reason, exit_code)
{
    StopWindowHooks()
}
