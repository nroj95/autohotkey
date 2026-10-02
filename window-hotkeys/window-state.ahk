; Internal Window Hotkeys module. Launch ..\window-hotkeys.ahk instead.
; Included into the same script; functions share the existing global state.

; =============================================================================
; minimize / restore window groups
; =============================================================================

ToggleOtherWindows()
{
    global home_minimized_windows, home_active_hwnd

    ToggleMinimizedWindowGroup(
        &home_minimized_windows,
        &home_active_hwnd,
        true
    )
}

ToggleAllWindows()
{
    global all_minimized_windows, all_active_hwnd

    ToggleMinimizedWindowGroup(&all_minimized_windows, &all_active_hwnd)
}

ToggleMinimizedWindowGroup(
    &minimized_windows,
    &saved_active_hwnd,
    keep_active_window := false
)
{
    ; Each toggle restores only its own saved group. Windows already minimized
    ; before that toggle stay untouched.
    if minimized_windows.Length {
        windows_to_restore := minimized_windows
        restore_focus_hwnd := saved_active_hwnd

        minimized_windows := []
        saved_active_hwnd := 0

        ; Preserve the existing order: Win+Home restores front-to-back;
        ; Win+M restores back-to-front before returning focus.
        Loop windows_to_restore.Length {
            index := (
                keep_active_window
                ? A_Index
                : windows_to_restore.Length - A_Index + 1
            )
            hwnd := windows_to_restore[index]

            if !WinExist("ahk_id " hwnd)
                continue

            try {
                if WinGetMinMax("ahk_id " hwnd) = -1
                    WinRestore("ahk_id " hwnd)
            }
        }

        if restore_focus_hwnd
            && WinExist("ahk_id " restore_focus_hwnd)
        {
            try WinActivate("ahk_id " restore_focus_hwnd)
        }

        return
    }

    active_hwnd := WinExist("A")

    if keep_active_window && !active_hwnd
        return

    saved_active_hwnd := active_hwnd
    windows_to_minimize := []

    ; Snapshot before minimizing anything, because minimization changes focus
    ; and window order.
    for hwnd in WinGetList() {
        if keep_active_window && hwnd = active_hwnd
            continue

        if !IsWindowToggleCandidate(hwnd)
            continue

        windows_to_minimize.Push(hwnd)
    }

    for hwnd in windows_to_minimize {
        try {
            WinMinimize("ahk_id " hwnd)
            minimized_windows.Push(hwnd)
        }
    }
}

; =============================================================================
; target selection
; =============================================================================

GetWindowControlTarget(restore_minimized := true)
{
    global last_minimized_hwnd

    if last_minimized_hwnd {
        hwnd := last_minimized_hwnd
        last_minimized_hwnd := 0

        if WinExist("ahk_id " hwnd) {
            if !restore_minimized
                return hwnd

            try {
                if WinGetMinMax("ahk_id " hwnd) = -1
                    WinRestore("ahk_id " hwnd)

                WinActivate("ahk_id " hwnd)
                return hwnd
            }
        }
    }

    return WinExist("A")
}

ForgetLastMinimizedWindow()
{
    global last_minimized_hwnd
    last_minimized_hwnd := 0
}

; =============================================================================
; maximize / minimize / restore
; =============================================================================

MaximizeWindowTarget()
{
    global borderless_windows

    ; Leave a just-minimized window minimized until this command decides its
    ; next state. WinMaximize can promote it directly to maximized.
    hwnd := GetWindowControlTarget(false)

    if !hwnd
        return

    window := "ahk_id " hwnd

    try {
        if borderless_windows.Has(hwnd) {
            RestoreBorderlessWindow(hwnd, true)
            WinActivate(window)
            return
        }

        if WinGetMinMax(window) = 1 {
            EnterBorderlessFullscreen(hwnd)
            return
        }

        WinMaximize(window)
    }
}

MinimizeActiveWindow()
{
    global last_minimized_hwnd
    global borderless_windows

    hwnd := WinExist("A")

    if !hwnd
        return

    try {
        if borderless_windows.Has(hwnd)
            RestoreBorderlessWindow(hwnd, false, true)

        WinMinimize("ahk_id " hwnd)
        last_minimized_hwnd := hwnd
    }
}

RestoreWindowTarget()
{
    global borderless_windows

    hwnd := GetWindowControlTarget()

    if !hwnd
        return

    window := "ahk_id " hwnd

    try {
        if borderless_windows.Has(hwnd) {
            RestoreBorderlessWindow(hwnd, false, true)
            WinActivate(window)
            return
        }

        WinRestore(window)

        ; A window minimized while maximized can return to maximized first.
        ; Win+Backspace always means ordinary windowed state.
        if WinGetMinMax(window) = 1
            WinRestore(window)

        WinActivate(window)
    }
}
