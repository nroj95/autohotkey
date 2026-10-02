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
^#h::ToggleWindowHotkeysHelp()

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

; Move focus spatially without moving windows.
!#Left::FocusNearestWindow("left")
!#Right::FocusNearestWindow("right")
!#Up::FocusNearestWindow("up")
!#Down::FocusNearestWindow("down")

; A mouse click means the user has deliberately moved on from the window that
; Win+Down most recently minimized.
~LButton::ForgetLastMinimizedWindow()
~RButton::ForgetLastMinimizedWindow()
~MButton::ForgetLastMinimizedWindow()

; =============================================================================
; CapsLock Layer presence
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
