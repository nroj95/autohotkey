; Internal Window Hotkeys module. Launch ..\window-hotkeys.ahk instead.
; Included into the same script; functions share the existing global state.

; =============================================================================
; borderless fullscreen
; =============================================================================

EnterBorderlessFullscreen(hwnd)
{
    global borderless_windows

    if borderless_windows.Has(hwnd)
        return

    window := "ahk_id " hwnd

    placement := CaptureWindowPlacement(hwnd)
    original_style := WinGetStyle(window)
    was_topmost := !!(WinGetExStyle(window) & 0x8)

    borderless_windows[hwnd] := Map(
        "style", original_style,
        "placement", placement,
        "was_topmost", was_topmost
    )

    try {
        GetWindowMonitorBounds(
            hwnd,
            &left,
            &top,
            &right,
            &bottom
        )

        ; Borderless mode itself is an ordinary window whose frame has been
        ; removed and whose rectangle fills the physical monitor.
        if WinGetMinMax(window) != 0
            WinRestore(window)

        WinSetStyle("-0xC40000", window)
        RefreshWindowFrame(hwnd)

        WinMove(
            left,
            top,
            right - left,
            bottom - top,
            window
        )

        WinSetAlwaysOnTop 1, window
        WinActivate(window)
    }
    catch {
        try RestoreBorderlessWindow(hwnd, false)

        throw
    }
}

RestoreBorderlessWindow(
    hwnd,
    restore_maximized := true,
    force_normal := false
)
{
    global borderless_windows

    if !borderless_windows.Has(hwnd)
        return

    saved := borderless_windows[hwnd]
    window := "ahk_id " hwnd

    if !WinExist(window) {
        borderless_windows.Delete(hwnd)
        return
    }

    restore_succeeded := false

    try {
        if !saved["was_topmost"]
            WinSetAlwaysOnTop 0, window

        WinSetStyle(saved["style"], window)
        RefreshWindowFrame(hwnd)

        if force_normal {
            ApplyWindowPlacement(
                hwnd,
                saved["placement"],
                1 ; SW_SHOWNORMAL
            )
        } else {
            ApplyWindowPlacement(
                hwnd,
                saved["placement"]
            )

            if restore_maximized
                WinMaximize(window)
        }

        if saved["was_topmost"]
            WinSetAlwaysOnTop 1, window

        restore_succeeded := true
    }
    finally {
        if restore_succeeded
            borderless_windows.Delete(hwnd)
    }
}

; =============================================================================
; Steam borderless suspension and resume
; =============================================================================

SuspendBorderlessSteamWindow(hwnd)
{
    global borderless_windows
    global suspended_borderless_windows

    static WPF_RESTORETOMAXIMIZED := 0x0002
    static SW_SHOWMINNOACTIVE := 7

    if !borderless_windows.Has(hwnd)
        return true

    if !DllCall("IsWindow", "ptr", hwnd, "int") {
        borderless_windows.Delete(hwnd)
        return true
    }

    if !DllCall("IsIconic", "ptr", hwnd, "int")
        return false

    saved := borderless_windows[hwnd]
    window := "ahk_id " hwnd

    process_id := 0

    try process_id := WinGetPID(hwnd)

    try {
        if !saved["was_topmost"]
            WinSetAlwaysOnTop 0, window

        ; The window stays minimized, but no longer owns our temporary
        ; borderless frame or fullscreen placement.
        WinSetStyle(saved["style"], window)
        RefreshWindowFrame(hwnd)

        placement := saved["placement"]

        original_flags := NumGet(
            placement,
            4,
            "uint"
        )

        try {
            ; Do not leave a minimized borderless window carrying a
            ; restore-to-maximized request. Its on-disk/application-facing
            ; state should be an ordinary minimized window.
            NumPut(
                "uint",
                original_flags & ~WPF_RESTORETOMAXIMIZED,
                placement,
                4
            )

            ApplyWindowPlacement(
                hwnd,
                placement,
                SW_SHOWMINNOACTIVE
            )
        }
        finally {
            NumPut(
                "uint",
                original_flags,
                placement,
                4
            )
        }

        if saved["was_topmost"]
            WinSetAlwaysOnTop 1, window

        if !DllCall(
            "IsIconic",
            "ptr", hwnd,
            "int"
        ) {
            throw Error(
                "Window left minimized state during borderless suspension."
            )
        }

        suspended_borderless_windows[hwnd] := Map(
            "state", saved,
            "pid", process_id
        )

        borderless_windows.Delete(hwnd)

        DebugLog(
            "Borderless Steam window suspended while minimized."
            . " | pid=" process_id
            . " | target=" DebugDescribeWindow(hwnd)
        )

        return true
    }
    catch Error as err {
        DebugError(
            "SuspendBorderlessSteamWindow hwnd=" hwnd,
            err
        )

        return false
    }
}

ResumeSuspendedBorderlessSteamWindow(hwnd)
{
    global borderless_windows
    global suspended_borderless_windows

    if !suspended_borderless_windows.Has(hwnd)
        return true

    entry := suspended_borderless_windows[hwnd]

    if !DllCall("IsWindow", "ptr", hwnd, "int") {
        suspended_borderless_windows.Delete(hwnd)
        return true
    }

    current_process_id := 0

    try current_process_id := WinGetPID(hwnd)
    catch {
        suspended_borderless_windows.Delete(hwnd)
        return true
    }

    if entry["pid"]
        && current_process_id != entry["pid"]
    {
        suspended_borderless_windows.Delete(hwnd)

        DebugLog(
            "Discarded suspended borderless state: PID changed."
            . " | hwnd=" hwnd
            . " | old-pid=" entry["pid"]
            . " | current-pid=" current_process_id
        )

        return true
    }

    if DllCall(
        "IsIconic",
        "ptr", hwnd,
        "int"
    ) {
        return false
    }

    try {
        ; Enter borderless using the currently restored ordinary window, then
        ; replace the temporary captured state with the original pre-borderless
        ; state so toggling borderless off later still restores correctly.
        EnterBorderlessFullscreen(hwnd)

        if !borderless_windows.Has(hwnd) {
            throw Error(
                "Borderless state was not established during resume."
            )
        }

        borderless_windows[hwnd] := entry["state"]
        suspended_borderless_windows.Delete(hwnd)

        DebugLog(
            "Borderless Steam window resumed."
            . " | target=" DebugDescribeWindow(hwnd)
        )

        return true
    }
    catch Error as err {
        DebugError(
            "ResumeSuspendedBorderlessSteamWindow hwnd=" hwnd,
            err
        )

        return false
    }
}

PruneSuspendedBorderlessSteamWindows()
{
    global suspended_borderless_windows

    stale_hwnds := []

    for hwnd, entry in suspended_borderless_windows {
        remove_entry := false

        if !DllCall("IsWindow", "ptr", hwnd, "int") {
            remove_entry := true
        } else {
            current_process_id := 0

            try current_process_id := WinGetPID(hwnd)
            catch {
                remove_entry := true
            }

            if !remove_entry
                && entry["pid"]
                && current_process_id != entry["pid"]
            {
                remove_entry := true
            }

            ; If something other than Caps+G already restored the window,
            ; borderless suspension no longer owns its next restore.
            if !remove_entry
                && !DllCall(
                    "IsIconic",
                    "ptr", hwnd,
                    "int"
                )
            {
                remove_entry := true
            }
        }

        if remove_entry
            stale_hwnds.Push(hwnd)
    }

    for hwnd in stale_hwnds {
        suspended_borderless_windows.Delete(hwnd)

        DebugLog(
            "Discarded stale suspended borderless state."
            . " | hwnd=" hwnd
        )
    }
}

; =============================================================================
; script exit and reload cleanup
; =============================================================================

RestoreAllBorderlessWindows(exit_reason, exit_code)
{
    global borderless_windows

    windows := []

    for hwnd in borderless_windows
        windows.Push(hwnd)

    for hwnd in windows {
        if !DllCall("IsWindow", "ptr", hwnd, "int")
            continue

        was_iconic := DllCall(
            "IsIconic",
            "ptr", hwnd,
            "int"
        )

        DebugLog(
            "Borderless exit cleanup begin."
            . " | iconic=" was_iconic
            . " | target=" DebugDescribeWindow(hwnd)
        )

        try {
            if was_iconic {
                saved := borderless_windows[hwnd]
                window := "ahk_id " hwnd

                if !saved["was_topmost"]
                    WinSetAlwaysOnTop 0, window

                ; Restore the frame while the window is still minimized.
                WinSetStyle(saved["style"], window)
                RefreshWindowFrame(hwnd)

                placement := saved["placement"]

                original_flags := NumGet(
                    placement,
                    4,
                    "uint"
                )

                try {
                    ; Reload is a clean restart. A window that was maximized
                    ; before entering borderless should restore as an ordinary
                    ; window after the script restart, not back to maximized.
                    NumPut(
                        "uint",
                        original_flags & ~0x0002,
                        placement,
                        4
                    )

                    ApplyWindowPlacement(
                        hwnd,
                        placement,
                        7 ; SW_SHOWMINNOACTIVE
                    )
                }
                finally {
                    NumPut(
                        "uint",
                        original_flags,
                        placement,
                        4
                    )
                }

                if saved["was_topmost"]
                    WinSetAlwaysOnTop 1, window

                borderless_windows.Delete(hwnd)
            } else {
                RestoreBorderlessWindow(hwnd, true)
            }

            DebugLog(
                "Borderless exit cleanup complete."
                . " | target=" DebugDescribeWindow(hwnd)
            )
        }
        catch Error as err {
            DebugError(
                "RestoreAllBorderlessWindows hwnd=" hwnd,
                err
            )
        }
    }
}
