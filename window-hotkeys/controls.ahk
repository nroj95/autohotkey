; Internal Window Hotkeys module. Launch ..\window-hotkeys.ahk instead.
; Included into the same script; functions share the existing global state.

; =============================================================================
; hotkeys
; =============================================================================

#Up::MaximizeWindowTarget()
#Down::MinimizeActiveWindow()
#Left::CycleWindowSnap("left")
#Right::CycleWindowSnap("right")
#Backspace::RestoreWindowTarget()
#Home::ToggleOtherWindows()
#m::ToggleAllWindows()

#Insert::PlaceWindowQuarter("top-left")
#Delete::PlaceWindowQuarter("bottom-left")
#End::ToggleCenterQuarter()
#PgUp::PlaceWindowQuarter("top-right")
#PgDn::PlaceWindowQuarter("bottom-right")

#Enter::SwapWindowClockwise()

; Deterministic Shift+Win stretch controls.
+#Up::StretchWindowVertically()
+#Down::ResetWindowStretch()
+#Left::ToggleHorizontalStretch("left")
+#Right::ToggleHorizontalStretch("right")

; FancyZones relative-position navigation.
#HotIf IsFancyZonesRunning()

^!Left::
{
    Send "{Ctrl up}{Alt up}#{Left}"
}

^!Right::
{
    Send "{Ctrl up}{Alt up}#{Right}"
}

^!Up::
{
    Send "{Ctrl up}{Alt up}#{Up}"
}

^!Down::
{
    Send "{Ctrl up}{Alt up}#{Down}"
}

#HotIf

; A mouse click means the user has deliberately moved on from the window that
; Win+Down most recently minimized.
~LButton::ForgetLastMinimizedWindow()
~RButton::ForgetLastMinimizedWindow()
~MButton::ForgetLastMinimizedWindow()

; =============================================================================
; CapsLock Layer dependency and command dispatch
; =============================================================================

IsCapsLockLayerRunning()
{
    mutex_handle := DllCall(
        "OpenMutex",
        "uint", 0x00100000, ; SYNCHRONIZE
        "int", false,
        "str", "Local\WindowCascade.CapsLockLayer",
        "ptr"
    )

    if !mutex_handle
        return false

    DllCall("CloseHandle", "ptr", mutex_handle)
    return true
}

RequireCapsLockLayer()
{
    global caps_layer_startup_wait_ms

    wait_start := A_TickCount

    while !IsCapsLockLayerRunning() {
        if ((A_TickCount - wait_start) & 0xFFFFFFFF) >= caps_layer_startup_wait_ms {
            DebugLog("Startup refused: CapsLock Layer is not running.")

            MsgBox(
                "Window Hotkeys requires CapsLock Layer.`n`n"
                . "Start capslock-layer.ahk, then launch window-hotkeys.ahk.",
                "Window Hotkeys",
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

    ; A quick CapsLock Layer reload must not tear down Window Hotkeys.
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

HandleWindowHotkeysCommandMessage(command_id, parameter, message_id, target_hwnd)
{
    global window_hotkeys_command_focus_left, window_hotkeys_command_focus_right
    global window_hotkeys_command_focus_up, window_hotkeys_command_focus_down
    global window_hotkeys_command_show_help

    ; HWND_BROADCAST also reaches script-owned GUIs. Execute once through the
    ; AutoHotkey hidden main window.
    if target_hwnd != A_ScriptHwnd
        return

    if !IsCapsLockLayerRunning()
        return

    switch command_id {
        case window_hotkeys_command_focus_left:
            FocusNearestWindow("left")

        case window_hotkeys_command_focus_right:
            FocusNearestWindow("right")

        case window_hotkeys_command_focus_up:
            FocusNearestWindow("up")

        case window_hotkeys_command_focus_down:
            FocusNearestWindow("down")

        case window_hotkeys_command_show_help:
            ToggleWindowHotkeysHelp()
    }
}
