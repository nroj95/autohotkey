; Internal Window Cascade module. Launch ..\window-cascade.ahk instead.
; Included into the same script; functions share the existing global state.

; =============================================================================
; standalone hotkeys
; =============================================================================
; Left Ctrl + Left Alt keeps the standalone layer away from common Alt-only
; app shortcuts and avoids treating Right Alt / AltGr as a cascade modifier.

#HotIf !IsCapsLockLayerRunning() && !ActiveWindowBlocksCascadeHotkeys()

<^<!Up::SwapActiveCascadeWindow(-1)
<^<!Down::SwapActiveCascadeWindow(1)
<^<!Left::RotateCurrentCascadeSlot(-1)
<^<!Right::RotateCurrentCascadeSlot(1)
<^<!PgUp::FocusCascadeLayerWindow(-1)
<^<!PgDn::FocusCascadeLayerWindow(1)

<^<!Backspace::
{
    AdoptActiveWindow()
    KeyWait "Backspace"
}

<^<!Home::
{
    BringCommandMonitorCascadeForward()
    KeyWait "Home"
}

<^<!m::
{
    ToggleCommandMonitorCascadeMinimize()
    KeyWait "m"
}

<^<!F4::
{
    CloseCurrentCascadeLayer()
    KeyWait "F4"
}

<^<!h::
{
    ToggleWindowCascadeHelp()
    KeyWait "h"
}

<^<!+m::
{
    ToggleAllCascadesMinimize()
    KeyWait "m"
}

<^<!+F4::
{
    CloseCommandMonitorCascade()
    KeyWait "F4"
}

<^<!+F7::
{
    GatherCascadesToCommandMonitor()
    KeyWait "F7"
}

#HotIf !IsCapsLockLayerRunning() && !ActiveWindowBlocksCascadeHotkeys() && rotate_key = "Space"
<^<!Space::
{
    RotateCascadeLayers(1)
    KeyWait "Space"
}

#HotIf !IsCapsLockLayerRunning() && !ActiveWindowBlocksCascadeHotkeys() && rotate_key = "Tab"
<^<!Tab::
{
    RotateCascadeLayers(1)
    KeyWait "Tab"
}

#HotIf


; =============================================================================
; desktop monitor selection
; =============================================================================

; Do not rely on foreground timing here. Windows may keep Progman focused while
; the user clicks between monitors, or may update foreground focus after the
; mouse-up event. Inspect the actual window under the cursor instead.
~LButton Up::CaptureDesktopMonitorHint()


; =============================================================================
; standalone hotkey availability
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

    DllCall("CloseHandle", "ptr", mutex_handle)
    return true
}

ActiveWindowBlocksCascadeHotkeys()
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

    ; HWND_BROADCAST also reaches script-owned GUIs. Run each command only
    ; once through AutoHotkey's hidden main window.
    if target_hwnd != A_ScriptHwnd
        return

    if ActiveWindowBlocksCascadeHotkeys()
        return

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
            RotateCascadeLayers(1)

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
