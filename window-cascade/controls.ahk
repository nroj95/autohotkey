; Internal Window Cascade module. Launch ..\window-cascade.ahk instead.
; Included into the same script; functions share the existing global state.

; =============================================================================
; focus-tab gestures and ordinary mouse clicks
; =============================================================================

; Consume both halves of a tab click. The release still belongs to the tab
; after the pointer leaves it, including after a cancelled swipe.
#HotIf CanStartFocusTabGesture()
*LButton::BeginFocusTabGesture()

#HotIf CanFinishFocusTabGesture()
*LButton Up::FinishFocusTabGesture()
#HotIf HasFocusTabGesture()
*Escape::CancelFocusTabGesture()
#HotIf

; Any ordinary mouse click commits a just-adopted window. Wildcards make this
; apply even while modifier keys are held; tilde preserves the native click.
~*LButton::CancelPendingAdoptionUndo()
~*RButton::CancelPendingAdoptionUndo()
~*MButton::CancelPendingAdoptionUndo()
~*XButton1::CancelPendingAdoptionUndo()
~*XButton2::CancelPendingAdoptionUndo()

; Do not rely on foreground timing here. Windows may keep Progman focused while
; the user clicks between monitors, or may update foreground focus after the
; mouse-up event. Inspect the actual window under the cursor instead.
; Match the wildcard release above so its contextual variant takes priority.
~*LButton Up::CaptureDesktopMonitorHint()


; =============================================================================
; required CapsLock Layer dependency
; =============================================================================

IsCapsLockLayerRunning()
{
    static SYNCHRONIZE := 0x00100000

    mutex_handle := DllCall(
        "OpenMutex",
        "uint", SYNCHRONIZE,
        "int", false,
        "str", "Local\WindowCascade.CapsLockLayer",
        "ptr"
    )

    if !mutex_handle
        return false

    ; Do not retain our own handle: that would keep the presence signal alive
    ; after CapsLock Layer exits.
    DllCall("CloseHandle", "ptr", mutex_handle)
    return true
}

RequireCapsLockLayer()
{
    global caps_layer_startup_wait_ms

    wait_start := A_TickCount

    while !IsCapsLockLayerRunning() {
        ; The mask also handles the 32-bit tick counter wrapping on long uptimes.
        if ((A_TickCount - wait_start) & 0xFFFFFFFF) >= caps_layer_startup_wait_ms {
            DebugLog("Startup refused: CapsLock Layer is not running.")
            MsgBox(
                "Window Cascade requires CapsLock Layer.`n`n"
                . "Start capslock-layer.ahk, then launch window-cascade.ahk.",
                "Window Cascade",
                "Iconx"
            )
            ExitApp 1
        }

        Sleep 100
    }
}

WatchCapsLockLayer()
{
    global caps_layer_missing_since, caps_layer_reload_grace_ms
    global caps_layer_dependency_lost

    if IsCapsLockLayerRunning() {
        caps_layer_missing_since := 0
        return
    }

    ; A quick CapsLock Layer reload must not throw away the current cascade.
    if !caps_layer_missing_since {
        caps_layer_missing_since := A_TickCount
        return
    }

    if ((A_TickCount - caps_layer_missing_since) & 0xFFFFFFFF) < caps_layer_reload_grace_ms
        return

    caps_layer_dependency_lost := true
    DebugLog("Stopping: CapsLock Layer remained unavailable after the reload grace period.")
    ExitApp 1
}

RestoreCascadeWindowsAfterDependencyLoss()
{
    global layer_minimized_windows_by_monitor
    global monitor_minimized_windows_by_monitor

    seen := Map()

    ; Only restore windows minimized by this script, not independently minimized
    ; applications. Do not resize or reposition windows already on screen.
    for window_lists in [layer_minimized_windows_by_monitor, monitor_minimized_windows_by_monitor] {
        for monitor_index, windows in window_lists {
            for hwnd in windows {
                if seen.Has(hwnd)
                    continue

                seen[hwnd] := true
                try {
                    if WinGetMinMax("ahk_id " hwnd) = -1
                        WinRestore("ahk_id " hwnd)
                }
                catch Error as err {
                    DebugError("Dependency-loss window restore", err)
                }
            }
        }
    }
}


; =============================================================================
; command availability
; =============================================================================

ActiveWindowBlocksCascadeCommands()
{
    active_hwnd := WinExist("A")

    if !active_hwnd || IsShellSurfaceWindow(active_hwnd)
        return false

    try {
        ; Maximized windows are intentionally outside cascade management.
        if WinGetMinMax("ahk_id " active_hwnd) = 1
            return true

        WinGetPos(
            &window_x,
            &window_y,
            &window_width,
            &window_height,
            "ahk_id " active_hwnd
        )
    }
    catch {
        return false
    }

    window_right := window_x + window_width
    window_bottom := window_y + window_height
    tolerance_px := 2

    ; Borderless/exclusive fullscreen normally covers one monitor exactly.
    Loop MonitorGetCount() {
        MonitorGet(
            A_Index,
            &monitor_left,
            &monitor_top,
            &monitor_right,
            &monitor_bottom
        )

        if Abs(window_x - monitor_left) <= tolerance_px
            && Abs(window_y - monitor_top) <= tolerance_px
            && Abs(window_right - monitor_right) <= tolerance_px
            && Abs(window_bottom - monitor_bottom) <= tolerance_px
        {
            return true
        }
    }

    return false
}


; =============================================================================
; CapsLock Layer messages
; =============================================================================

RegisterIntegrationMessages()
{
    global cascade_command_message

    cascade_command_message := DllCall(
        "RegisterWindowMessage",
        "str", "WindowCascade.Command",
        "uint"
    )

    if !cascade_command_message
        throw OSError(A_LastError, "RegisterIntegrationMessages")

    OnMessage(cascade_command_message, HandleCascadeCommandMessage)
}

HandleCascadeCommandMessage(command_id, parameter, message_id, target_hwnd)
{
    global cascade_command_focus_previous, cascade_command_focus_next
    global cascade_command_rotate_slot_previous, cascade_command_rotate_slot_next
    global cascade_command_swap_window_up, cascade_command_swap_window_down
    global cascade_command_adopt_active, cascade_command_rotate_layers
    global cascade_command_toggle_minimize, cascade_command_bring_forward
    global cascade_command_close_active, cascade_command_close_scope
    global cascade_command_gather_to_monitor, cascade_command_show_help
    global cascade_command_move_monitor_left, cascade_command_move_monitor_right
    global cascade_command_toggle_cascading

    ; HWND_BROADCAST also reaches script-owned GUIs. Run each command only
    ; once through AutoHotkey's hidden main window.
    if target_hwnd != A_ScriptHwnd
        return

    if !IsCapsLockLayerRunning()
        return

    ; Script-level pause stays available even when window-management commands
    ; are blocked by a maximized or fullscreen active window.
    if command_id = cascade_command_toggle_cascading {
        CancelPendingAdoptionUndo()
        ToggleCascading()
        return
    }

    if ActiveWindowBlocksCascadeCommands()
        return

    if command_id != cascade_command_adopt_active
        CancelPendingAdoptionUndo()

    switch command_id {
        case cascade_command_focus_previous:
            FocusCascadeLayerWindow(-1)

        case cascade_command_focus_next:
            FocusCascadeLayerWindow(1)

        case cascade_command_rotate_slot_previous:
            RotateCurrentCascadeSlot(-1)

        case cascade_command_rotate_slot_next:
            RotateCurrentCascadeSlot(1)

        case cascade_command_swap_window_up:
            SwapActiveCascadeWindow(-1)

        case cascade_command_swap_window_down:
            SwapActiveCascadeWindow(1)

        case cascade_command_adopt_active:
            AdoptActiveWindow()

        case cascade_command_rotate_layers:
            ; OnMessage exposes -1 as 0xFFFFFFFF in a 32-bit receiver.
            ; Zero remains forward so the existing one-shot sender still works.
            direction := (parameter = -1 || parameter = 0xFFFFFFFF) ? -1 : 1
            RotateCascadeLayers(direction)

        case cascade_command_toggle_minimize:
            if parameter
                ToggleAllCascadesMinimize()
            else
                ToggleCommandMonitorCascadeMinimize()

        case cascade_command_bring_forward:
            BringCommandMonitorCascadeForward()

        case cascade_command_close_active:
            Send "!{F4}"

        case cascade_command_close_scope:
            if parameter
                CloseCommandMonitorCascade()
            else
                CloseCurrentCascadeLayer()

        case cascade_command_gather_to_monitor:
            GatherCascadesToCommandMonitor()

        case cascade_command_show_help:
            ToggleWindowCascadeHelp()

        case cascade_command_move_monitor_left:
            MoveCascadeWindowAcrossMonitor(parameter, "Left")

        case cascade_command_move_monitor_right:
            MoveCascadeWindowAcrossMonitor(parameter, "Right")
    }
}
