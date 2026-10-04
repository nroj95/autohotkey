; Internal Win Key Overhaul module. Launch ..\win-key-overhaul.ahk.

; =============================================================================
; direct window-management shortcuts
; =============================================================================

; The $ prefixes keep forwarded FancyZones keystrokes out of our handlers.
$#Up::MaximizeWindowTarget()
$#Down::RestoreWindowTarget()

#HotIf !IsScratchpadWindowActive()
$#Left::CycleWindowSnap("left")
$#Right::CycleWindowSnap("right")
#HotIf

$+#Up::StretchWindowVertically()
$+#Down::ResetWindowStretch()
$+#Left::ToggleHorizontalStretch("left")
$+#Right::ToggleHorizontalStretch("right")

^#h::ToggleWinKeyOverhaulHelp()
#Backspace::MinimizeActiveWindow()
+#Home::ToggleOtherWindows()
#m::ToggleAllWindows()

#Insert::PlaceCornerTile("top-left")
#Delete::PlaceCornerTile("bottom-left")

#HotIf !IsScratchpadWindowActive()
$#PgUp::PlaceCornerTile("top-right")
$#PgDn::PlaceCornerTile("bottom-right")
#HotIf

#Home::PlaceCenterTile("top")
#End::PlaceCenterTile("bottom")

#Enter::SwapWindow("clockwise")
+#Enter::SwapWindow("counter-clockwise")

; Standalone spatial focus and Steam cycling.
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

IsScratchpadWindowActive()
{
    hwnd := WinExist("A")
    return hwnd
        && DllCall(
            "GetPropW",
            "ptr", hwnd,
            "str", "nroj.Scratchpad.Notepad3Window",
            "ptr"
        )
}
