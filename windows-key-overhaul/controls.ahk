; Internal Windows Key Overhaul module. Launch ..\windows-key-overhaul.ahk.

; =============================================================================
; direct window-management shortcuts
; =============================================================================

; Preserve optional Caps+Win+Arrow aliases, including either modifier press order.
; The $ prefixes also keep forwarded FancyZones keystrokes out of our handlers.
#HotIf !CapsLockLayerOwnsWinArrow()

$#Up::MaximizeWindowTarget()
$#Down::RestoreWindowTarget()
$#Left::CycleWindowSnap("left")
$#Right::CycleWindowSnap("right")

$+#Up::StretchWindowVertically()
$+#Down::ResetWindowStretch()
$+#Left::ToggleHorizontalStretch("left")
$+#Right::ToggleHorizontalStretch("right")

#HotIf

^#h::ToggleWindowsKeyOverhaulHelp()
#Backspace::MinimizeActiveWindow()
+#Home::ToggleOtherWindows()
#m::ToggleAllWindows()

#Insert::PlaceCornerTile("top-left")
#Delete::PlaceCornerTile("bottom-left")
$#PgUp::PlaceCornerTile("top-right")
$#PgDn::PlaceCornerTile("bottom-right")
#Home::PlaceCenterTile("top")
#End::PlaceCenterTile("bottom")

#Enter::SwapWindow("clockwise")
+#Enter::SwapWindow("counter-clockwise")

; These controls no longer require CapsLock Layer.
$^#Left::FocusNearestWindow("left")
$^#Right::FocusNearestWindow("right")
$^#Up::FocusNearestWindow("up")
$^#Down::FocusNearestWindow("down")
+#g::CycleSteamGames()

; =============================================================================
; optional FancyZones navigation
; =============================================================================

#HotIf IsFancyZonesRunning()

$!#Left::MoveWindowThroughFancyZones("Left")
$!#Right::MoveWindowThroughFancyZones("Right")
$!#Up::MoveWindowThroughFancyZones("Up")
$!#Down::MoveWindowThroughFancyZones("Down")

; Alt+Win+PgUp/PgDn are registered by FancyZones itself. Registering them here
; as well would block its zone-window switching. Startup offers to configure it.
#HotIf

; A deliberate click abandons the window last minimized with Win+Backspace.
~LButton::ForgetLastMinimizedWindow()
~RButton::ForgetLastMinimizedWindow()
~MButton::ForgetLastMinimizedWindow()

; =============================================================================
; backwards-compatible CapsLock Layer command dispatch
; =============================================================================

CapsLockLayerOwnsWinArrow()
{
    return GetKeyState("CapsLock", "P") && IsCapsLockLayerRunning()
}

IsCapsLockLayerRunning()
{
    mutex_handle := DllCall(
        "OpenMutex", "uint", 0x00100000, "int", false,
        "str", "Local\WindowCascade.CapsLockLayer", "ptr"
    )
    if !mutex_handle
        return false

    DllCall("CloseHandle", "ptr", mutex_handle)
    return true
}

HandleWindowsKeyOverhaulCommandMessage(command_id, parameter, message_id, target_hwnd)
{
    global window_hotkeys_command_focus_left, window_hotkeys_command_focus_right
    global window_hotkeys_command_focus_up, window_hotkeys_command_focus_down

    ; Broadcasts also reach our help GUI. Handle each command only once.
    if target_hwnd != A_ScriptHwnd || !IsCapsLockLayerRunning()
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
