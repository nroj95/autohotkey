; Internal Window Hotkeys module. Launch ..\window-hotkeys.ahk instead.
; Included into the same script; functions share the existing global state.

; =============================================================================
; Steam command and cycle state
; =============================================================================

HandleSteamGameCycleMessage(*)
{
    DebugLog(
        "Steam cycle command received."
        . " | ahk-active=" DebugDescribeWindow(WinExist("A"))
        . " | foreground="
        . DebugDescribeWindow(
            DllCall("GetForegroundWindow", "ptr")
        )
    )

    CycleSteamGames()

    DebugSteamGameState("Steam cycle command complete")
}

CycleSteamGames()
{
    global steam_game_cycle, last_steam_game_hwnd
    global steam_return_hwnd

    RefreshSteamGameCycle()
    DebugSteamGameState("Steam cycle refreshed")

    if steam_game_cycle.Length = 0 {
        DebugLog("Steam cycle stopped: no game windows detected.")
        last_steam_game_hwnd := 0
        return
    }

    active_hwnd := WinExist("A")
    active_index := FindWindowIndex(
        steam_game_cycle,
        active_hwnd
    )

    DebugLog(
        "Steam cycle active selection."
        . " | active-index=" active_index
        . " | active=" DebugDescribeWindow(active_hwnd)
    )

    if active_index {
        last_steam_game_hwnd := active_hwnd

        if steam_game_cycle.Length = 1 {
            DebugLog("Steam cycle branch: minimize single game.")

            if !IsSteamReturnWindow(
                steam_return_hwnd,
                active_hwnd
            ) {
                DebugLog(
                    "Saved return window is unavailable."
                    . " | saved="
                    . DebugDescribeWindow(steam_return_hwnd)
                )

                steam_return_hwnd :=
                    FindSteamReturnWindow(active_hwnd)
            }

            DebugLog(
                "Return window before minimize."
                . " | return="
                . DebugDescribeWindow(steam_return_hwnd)
            )

            minimize_succeeded :=
                MinimizeSteamGameWindow(active_hwnd)

            DebugLog(
                "Game minimize finished."
                . " | success=" minimize_succeeded
                . " | foreground="
                . DebugDescribeWindow(
                    DllCall("GetForegroundWindow", "ptr")
                )
            )

            if steam_return_hwnd {
                activation_succeeded :=
                    ActivateWindowReliably(
                        steam_return_hwnd
                    )

                DebugLog(
                    "Return-window activation finished."
                    . " | success=" activation_succeeded
                    . " | requested="
                    . DebugDescribeWindow(steam_return_hwnd)
                    . " | foreground="
                    . DebugDescribeWindow(
                        DllCall("GetForegroundWindow", "ptr")
                    )
                )
            }

            return
        }

        next_index := (
            active_index = steam_game_cycle.Length
            ? 1
            : active_index + 1
        )

        next_hwnd := steam_game_cycle[next_index]

        DebugLog(
            "Steam cycle branch: next game."
            . " | from=" DebugDescribeWindow(active_hwnd)
            . " | to=" DebugDescribeWindow(next_hwnd)
        )

        MinimizeSteamGameWindow(active_hwnd)

        if ActivateSteamGameWindow(next_hwnd)
            last_steam_game_hwnd := next_hwnd

        return
    }

    ; This is the important path when another application was clicked before
    ; Caps+G. Record exactly what Window Hotkeys believes that application is.
    if IsSteamReturnWindow(active_hwnd, 0) {
        steam_return_hwnd := active_hwnd

        DebugLog(
            "Recorded current non-game return window."
            . " | return="
            . DebugDescribeWindow(steam_return_hwnd)
        )
    } else {
        DebugLog(
            "Current active window was not accepted as return window."
            . " | active="
            . DebugDescribeWindow(active_hwnd)
        )
    }

    target_hwnd := 0

    if last_steam_game_hwnd
        && FindWindowIndex(
            steam_game_cycle,
            last_steam_game_hwnd
        )
    {
        target_hwnd := last_steam_game_hwnd
        DebugLog("Selected previous Steam game.")
    } else {
        target_hwnd := steam_game_cycle[1]
        DebugLog("Selected first Steam game.")
    }

    DebugLog(
        "Attempting Steam game restore."
        . " | target=" DebugDescribeWindow(target_hwnd)
    )

    activation_succeeded :=
        ActivateSteamGameWindow(target_hwnd)

    DebugLog(
        "Steam game restore finished."
        . " | success=" activation_succeeded
        . " | target=" DebugDescribeWindow(target_hwnd)
        . " | foreground="
        . DebugDescribeWindow(
            DllCall("GetForegroundWindow", "ptr")
        )
    )

    if activation_succeeded
        last_steam_game_hwnd := target_hwnd
}

RefreshSteamGameCycle()
{
    global steam_game_cycle

    PruneSuspendedBorderlessSteamWindows()

    detected_windows := GetSteamGameWindows()
    detected_set := Map()

    for hwnd in detected_windows
        detected_set[hwnd] := true

    refreshed_cycle := []
    preserved_set := Map()

    for hwnd in steam_game_cycle {
        if !detected_set.Has(hwnd)
            continue

        refreshed_cycle.Push(hwnd)
        preserved_set[hwnd] := true
    }

    for hwnd in detected_windows {
        if preserved_set.Has(hwnd)
            continue

        refreshed_cycle.Push(hwnd)
    }

    steam_game_cycle := refreshed_cycle
}

; =============================================================================
; Steam game discovery
; =============================================================================

GetSteamGameWindows()
{
    windows := []

    previous_setting := DetectHiddenWindows(true)

    try {
        for hwnd in WinGetList() {
            if IsSteamGameWindow(hwnd)
                windows.Push(hwnd)
        }
    }
    finally {
        DetectHiddenWindows(previous_setting)
    }

    return windows
}

IsSteamGameWindow(hwnd)
{
    global steam_game_excluded_executables

    if !hwnd
        return false

    if !DllCall("IsWindow", "ptr", hwnd, "int")
        return false

    root_hwnd := DllCall(
        "GetAncestor",
        "ptr", hwnd,
        "uint", 2, ; GA_ROOT
        "ptr"
    )

    if root_hwnd != hwnd
        return false

    try {
        style := WinGetStyle(hwnd)
        ex_style := WinGetExStyle(hwnd)
        title := WinGetTitle(hwnd)
        class_name := WinGetClass(hwnd)
        process_path := WinGetProcessPath(hwnd)
        process_name := StrLower(WinGetProcessName(hwnd))

        WinGetPos(
            &window_x,
            &window_y,
            &width,
            &height,
            hwnd
        )
    }
    catch {
        return false
    }

    if title = ""
        return false

    if style & 0x40000000 ; WS_CHILD
        return false

    if ex_style & 0x00000080 ; WS_EX_TOOLWINDOW
        return false

    if ex_style & 0x08000000 ; WS_EX_NOACTIVATE
        return false

    if DllCall("GetWindow", "ptr", hwnd, "uint", 4, "ptr")
        return false

    if IsWindowHotkeysShellClass(class_name)
        return false

    if width < 1 || height < 1
        return false

    if steam_game_excluded_executables.Has(process_name) {
        DebugLog(
            "Steam cycle candidate excluded."
            . " | reason=non-game application"
            . " | " DebugDescribeWindow(hwnd)
        )

        return false
    }

    normalized_path := StrLower(
        StrReplace(process_path, "/", "\")
    )

    return InStr(
        normalized_path,
        "\steamapps\common\"
    ) > 0
}

; =============================================================================
; Steam window minimize and activation
; =============================================================================

MinimizeSteamGameWindow(hwnd)
{
    global borderless_windows

    if !hwnd || !DllCall("IsWindow", "ptr", hwnd, "int")
        return false

    was_borderless := borderless_windows.Has(hwnd)

    DebugLog(
        "MinimizeSteamGameWindow begin."
        . " | borderless=" was_borderless
        . " | target=" DebugDescribeWindow(hwnd)
    )

    if DllCall(
        "IsIconic",
        "ptr", hwnd,
        "int"
    ) {
        if was_borderless
            && !SuspendBorderlessSteamWindow(hwnd)
        {
            return false
        }

        DebugLog(
            "Minimize completed: window already iconic."
            . " | target=" DebugDescribeWindow(hwnd)
        )

        return true
    }

    try WinMinimize(hwnd)
    catch Error as err {
        DebugError("MinimizeSteamGameWindow", err)
        return false
    }

    Loop 30 {
        if !DllCall("IsWindow", "ptr", hwnd, "int") {
            if was_borderless
                && borderless_windows.Has(hwnd)
            {
                borderless_windows.Delete(hwnd)
            }

            DebugLog("Minimize completed: HWND disappeared.")
            return true
        }

        if DllCall(
            "IsIconic",
            "ptr", hwnd,
            "int"
        ) {
            if was_borderless
                && !SuspendBorderlessSteamWindow(hwnd)
            {
                DebugLog(
                    "Minimize reached iconic state, but borderless "
                    . "suspension failed."
                )

                return false
            }

            DebugLog(
                "Minimize completed: IsIconic=1."
                . " | target=" DebugDescribeWindow(hwnd)
            )

            return true
        }

        if !DllCall(
            "IsWindowVisible",
            "ptr", hwnd,
            "int"
        ) {
            if was_borderless {
                DebugLog(
                    "Minimize reached hidden non-iconic state while "
                    . "borderless."
                    . " | target=" DebugDescribeWindow(hwnd)
                )

                return false
            }

            DebugLog(
                "Minimize completed: window became hidden."
                . " | target=" DebugDescribeWindow(hwnd)
            )

            return true
        }

        Sleep 20
    }

    DebugLog(
        "Minimize wait timed out."
        . " | target=" DebugDescribeWindow(hwnd)
    )

    return false
}

ActivateSteamGameWindow(hwnd)
{
    global suspended_borderless_windows

    static WPF_RESTORETOMAXIMIZED := 0x0002
    static SW_MAXIMIZE := 3
    static SW_RESTORE := 9

    if !hwnd || !DllCall("IsWindow", "ptr", hwnd, "int")
        return false

    resume_borderless := suspended_borderless_windows.Has(hwnd)
    restore_maximized := false
    placement_flags := "?"
    placement_show_command := "?"

    ; WINDOWPLACEMENT survives a script restart. In particular,
    ; WPF_RESTORETOMAXIMIZED tells us that a minimized window should return
    ; maximized instead of falling back to its normal restore rectangle.
    try {
        placement := CaptureWindowPlacement(hwnd)

        placement_flags := NumGet(
            placement,
            4,
            "uint"
        )

        placement_show_command := NumGet(
            placement,
            8,
            "uint"
        )

        restore_maximized := !!(
            placement_flags
            & WPF_RESTORETOMAXIMIZED
        )
    }

    ; A runtime-suspended borderless window must first restore as an ordinary
    ; window. ResumeSuspendedBorderlessSteamWindow() will then put it back into
    ; borderless fullscreen.
    if resume_borderless
        restore_maximized := false

    DebugLog(
        "ActivateSteamGameWindow begin."
        . " | resume-borderless=" resume_borderless
        . " | restore-maximized=" restore_maximized
        . " | placement-flags=" placement_flags
        . " | placement-show-command=" placement_show_command
        . " | target=" DebugDescribeWindow(hwnd)
    )

    Loop 12 {
        attempt := A_Index

        iconic_before := DllCall(
            "IsIconic",
            "ptr", hwnd,
            "int"
        )

        if iconic_before {
            if restore_maximized {
                DllCall(
                    "ShowWindow",
                    "ptr", hwnd,
                    "int", SW_MAXIMIZE,
                    "int"
                )

                try WinMaximize(hwnd)
            } else {
                try WinRestore(hwnd)

                DllCall(
                    "ShowWindow",
                    "ptr", hwnd,
                    "int", SW_RESTORE,
                    "int"
                )
            }

            Sleep 50
        } else {
            try WinShow(hwnd)
        }

        resume_borderless_succeeded := true

        if !DllCall(
            "IsIconic",
            "ptr", hwnd,
            "int"
        ) {
            resume_borderless_succeeded :=
                ResumeSuspendedBorderlessSteamWindow(hwnd)
        }

        try WinActivate(hwnd)

        set_foreground_result := DllCall(
            "SetForegroundWindow",
            "ptr", hwnd,
            "int"
        )

        Sleep 50

        foreground_hwnd :=
            DllCall("GetForegroundWindow", "ptr")

        iconic_after := DllCall(
            "IsIconic",
            "ptr", hwnd,
            "int"
        )

        min_max_after := "?"

        try min_max_after := WinGetMinMax(hwnd)

        DebugLog(
            "Game activation attempt."
            . " | attempt=" attempt
            . " | restore-maximized=" restore_maximized
            . " | borderless-resume="
            . resume_borderless_succeeded
            . " | iconic-before=" iconic_before
            . " | iconic-after=" iconic_after
            . " | minmax-after=" min_max_after
            . " | SetForegroundWindow="
            . set_foreground_result
            . " | target=" DebugDescribeWindow(hwnd)
            . " | foreground="
            . DebugDescribeWindow(foreground_hwnd)
        )

        if foreground_hwnd = hwnd
            && !iconic_after
            && resume_borderless_succeeded
            && (
                !restore_maximized
                || min_max_after = 1
            )
        {
            return true
        }
    }

    DebugLog(
        "Game activation failed."
        . " | restore-maximized=" restore_maximized
        . " | target=" DebugDescribeWindow(hwnd)
    )

    return false
}

; =============================================================================
; returning to a non-game window
; =============================================================================

IsSteamReturnWindow(hwnd, excluded_game_hwnd)
{
    if !hwnd || hwnd = excluded_game_hwnd
        return false

    if !DllCall("IsWindow", "ptr", hwnd, "int")
        return false

    if IsSteamGameWindow(hwnd)
        return false

    return IsWindowToggleCandidate(hwnd)
}

FindSteamReturnWindow(excluded_game_hwnd)
{
    DebugLog(
        "Searching Z-order for return window."
        . " | excluded="
        . DebugDescribeWindow(excluded_game_hwnd)
    )

    for hwnd in WinGetList() {
        if hwnd = excluded_game_hwnd
            continue

        accepted :=
            IsSteamReturnWindow(
                hwnd,
                excluded_game_hwnd
            )

        DebugLog(
            "Return-window candidate."
            . " | accepted=" accepted
            . " | " DebugDescribeWindow(hwnd)
        )

        if accepted {
            DebugLog(
                "Selected return-window candidate."
                . " | " DebugDescribeWindow(hwnd)
            )
            return hwnd
        }
    }

    DebugLog("No return-window candidate found.")
    return 0
}
