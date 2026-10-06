; Internal Window Cascade module. Launch ..\window-cascade.ahk instead.
; Included into the same script; functions share the existing global state.

; =============================================================================
; focus-tab clicks and ordinary mouse clicks
; =============================================================================

; Act once on press and consume the matching release, even outside the tab.
; Holding the button never repeats the action or moves a window/tab.
#HotIf CanStartFocusTabClick()
*LButton::BeginFocusTabClick()

#HotIf HasFocusTabClick()
*LButton Up::FinishFocusTabClick()
#HotIf

; Any ordinary mouse click commits a just-adopted window. Wildcards make this
; apply even while modifier keys are held; tilde preserves the native click.
~*LButton::CaptureCascadeMousePress()
~*RButton::CancelCascadePendingMouseActions()
~*MButton::CancelCascadePendingMouseActions()
~*XButton1::CancelCascadePendingMouseActions()
~*XButton2::CancelCascadePendingMouseActions()

; Do not rely on foreground timing here. Windows may keep Progman focused while
; the user clicks between monitors, or may update foreground focus after the
; mouse-up event. Inspect the actual window under the cursor instead.
; Match the wildcard release above so its contextual variant takes priority.
~*LButton Up::CaptureCascadeMouseRelease()

; Observe native drag cancellation without consuming Escape from the app.
#HotIf HasCascadeWindowDrag()
~*Escape::CancelCascadeWindowDrop()
#HotIf

; Some preview/quick-look tools reuse an existing managed HWND instead of
; creating a new window. Observe plain Space in Explorer as a short-lived user
; intent; the first managed re-show must still pass identity and foreground checks.
#HotIf IsExplorerSpaceReshowIntentContext()
~*Space::CaptureExplorerSpaceReshowIntent()
#HotIf

IsExplorerSpaceReshowIntentContext()
{
    if !IsCascadeEnabled()
        return false

    hwnd := WinExist("A")
    if !hwnd || IsShellSurfaceWindow(hwnd)
        return false

    try return WinGetProcessName("ahk_id " hwnd) = "explorer.exe"
    catch
        return false
}

CaptureExplorerSpaceReshowIntent()
{
    global explorer_space_reshow_hint
    global debug_enabled, debug_verbose_enabled

    ; Modifier/Caps chords belong to Explorer, another app, or CapsLock Layer.
    ; Only the native plain-Space action may become a re-show intent.
    for modifier in ["CapsLock", "Shift", "Ctrl", "Alt", "LWin", "RWin"] {
        if GetKeyState(modifier, "P")
            return
    }

    source_hwnd := WinExist("A")
    if !source_hwnd || !IsExplorerSpaceReshowIntentContext()
        return

    try source_pid := WinGetPID("ahk_id " source_hwnd)
    catch
        return

    monitor := GetMonitorForWindow(source_hwnd)
    if !monitor
        return

    explorer_space_reshow_hint := {
        tick: A_TickCount,
        source_hwnd: source_hwnd,
        source_pid: source_pid,
        monitor: monitor,
        monitor_device: GetCascadeMonitorDevice(monitor)
    }

    if debug_enabled && debug_verbose_enabled {
        DebugLog(
            "Explorer Space re-show intent captured."
            . " | monitor=" monitor
            . " | source=" DebugDescribeWindow(source_hwnd)
        )
    }
}


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

; =============================================================================
; command availability
; =============================================================================

ActiveWindowBlocksCascadeCommands()
{
    ; Do not rotate, gather or reposition windows underneath a native drag.
    if HasCascadeWindowDrag() || IsCascadeDisplayTransition()
        return true
    command_monitor := GetCommandMonitor()
    if command_monitor && (CascadeMonitorNeedsRefresh(command_monitor)
        || HasPendingCascadeDisplayLayout(command_monitor))
        return true

    active_hwnd := WinExist("A")

    if !active_hwnd || IsShellSurfaceWindow(active_hwnd)
        return false

    try {
        ; Maximized windows are intentionally outside cascade management.
        if WinGetMinMax("ahk_id " active_hwnd) = 1
            return true

        WinGetPosPixels(
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
        MonitorGetPixels(
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
    global cascade_command_message, cascade_rotate_key_message

    cascade_command_message := DllCall(
        "RegisterWindowMessage", "str", "WindowCascade.Command", "uint"
    )
    cascade_rotate_key_message := DllCall(
        "RegisterWindowMessage", "str", "WindowCascade.RotateKeyChanged", "uint"
    )
    if !cascade_command_message || !cascade_rotate_key_message
        throw OSError(A_LastError, "RegisterIntegrationMessages")

    OnMessage(cascade_command_message, HandleCascadeCommandMessage)
    BroadcastCascadeRotateKey()
}

BroadcastCascadeRotateKey()
{
    global cascade_rotate_key_message, rotate_key

    if !cascade_rotate_key_message
        return
    DllCall(
        "PostMessage", "ptr", 0xFFFF, ; HWND_BROADCAST
        "uint", cascade_rotate_key_message,
        "uptr", rotate_key = "Tab" ? 2 : 1,
        "ptr", 0, "int"
    )
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
    global cascade_disabled, cascade_toggle_in_progress

    ; HWND_BROADCAST also reaches script-owned GUIs. Run each command only
    ; once through AutoHotkey's hidden main window.
    if target_hwnd != A_ScriptHwnd
        return

    if !IsCapsLockLayerRunning()
        return
    if cascade_toggle_in_progress
        return

    ; Caps + M must be able to wake the cascade from any foreground window.
    ; It is the only keyboard command accepted while the cascade is disabled.
    if command_id = cascade_command_toggle_minimize {
        ToggleCascadeDisabled()
        return
    }
    if cascade_disabled
        return

    CancelNewWindowFocus()

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

        case cascade_command_bring_forward:
            BringCommandMonitorCascadeForward()

        case cascade_command_close_active:
            ; Close without synthetic modifiers. Foreground recovery has its own
            ; guarded fallback and must not depend on this close command.
            try WinClose("A")

        case cascade_command_close_scope:
            CloseCommandMonitorCascade()

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


CancelCascadePendingMouseActions(*)
{
    if !IsCascadeEnabled()
        return

    CancelPendingAdoptionUndo()
    CancelNewWindowFocus()
}
