; Internal Window Hotkeys module. Launch ..\window-hotkeys.ahk instead.
; Included into the same script; functions share the existing global state.

; =============================================================================
; hotkeys
; =============================================================================

; Leave Win+Arrow to CapsLock Layer only while that companion is running and
; CapsLock is physically held. This keeps Caps+Win+Arrow order-independent
; without changing standalone Window Hotkeys behavior.
#HotIf !CapsLockLayerOwnsWinArrow()

#Up::MaximizeWindowTarget()
#Down::MinimizeActiveWindow()
#Left::CycleWindowSnap("left")
#Right::CycleWindowSnap("right")

; Deterministic Shift+Win stretch controls.
+#Up::StretchWindowVertically()
+#Down::ResetWindowStretch()
+#Left::ToggleHorizontalStretch("left")
+#Right::ToggleHorizontalStretch("right")

#HotIf

^#h::ToggleWindowHotkeysHelp()

#Backspace::RestoreWindowTarget()
#Home::ToggleOtherWindows()
#m::ToggleAllWindows()

#Insert::PlaceWindowQuarter("top-left")
#Delete::PlaceWindowQuarter("bottom-left")
#End::ToggleCenterQuarter()
#PgUp::PlaceWindowQuarter("top-right")
#PgDn::PlaceWindowQuarter("bottom-right")

#Enter::SwapWindowClockwise()

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
; optional CapsLock Layer integration and command dispatch
; =============================================================================

CapsLockLayerOwnsWinArrow()
{
    return (
        GetKeyState("CapsLock", "P")
        && IsCapsLockLayerRunning()
    )
}

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

HandleWindowHotkeysCommandMessage(command_id, parameter, message_id, target_hwnd)
{
    global window_hotkeys_command_focus_left, window_hotkeys_command_focus_right
    global window_hotkeys_command_focus_up, window_hotkeys_command_focus_down

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
    }
}
