#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn

A_IconTip := "Window Hotkeys"
try TraySetIcon(A_ScriptDir "\icons\window-hotkeys.ico")

last_minimized_hwnd := 0
home_minimized_windows := []
home_active_hwnd := 0
all_minimized_windows := []
all_active_hwnd := 0
borderless_windows := Map()
suspended_borderless_windows := Map()

steam_game_cycle := []
last_steam_game_hwnd := 0
steam_return_hwnd := 0

; Steam also distributes normal applications and tools. Their install path is
; indistinguishable from a game's path, so keep known non-game executables out
; of Caps+G explicitly instead of guessing from window behavior.
steam_game_excluded_executables := Map(
    "aseprite.exe", true
)

focus_highlight_guis := []
focus_highlight_duration_ms := 1500
focus_highlight_thickness := 12
focus_highlight_overlap := 2
focus_navigation_active := false
focus_navigation_hwnd := 0

startup_shortcut_path := A_Startup "\Window Hotkeys.lnk"
fancyzones_override_snap_disabled := false
fancyzones_hotkey_conflict := false


; =============================================================================
; debug
; =============================================================================

debug_enabled := true
debug_log_path := A_ScriptDir "\window-hotkeys-debug.log"

InitializeDebugLogging()

OnExit RestoreAllBorderlessWindows


steam_game_cycle_message := DllCall(
    "RegisterWindowMessage",
    "str", "WindowHotkeys.CycleSteamGames",
    "uint"
)

OnMessage(
    steam_game_cycle_message,
    HandleSteamGameCycleMessage
)

; =============================================================================
; mission
; =============================================================================
; - provide predictable win-key window management independent of Windows Snap.
; - maximize, minimize, restore, and place windows with simple win-key shortcuts.
; - toggle maximized windows into true borderless fullscreen with win+up.
; - cycle common half/third layouts with win+left and win+right.
; - provide direct quarter-screen placement from the navigation-key cluster.
; - move the active window clockwise by swapping geometry with nearby windows.
; - move focus spatially between nearby windows without moving them.
; - briefly highlight spatially focused windows with the Windows accent color.
; - cycle running Steam games while preserving their window state.
; - remember a just-minimized window until the user clicks elsewhere.
; - toggle all eligible windows minimized/restored with win+m.
; - remain a single-file standalone AutoHotkey v2 script.
; =============================================================================


; =============================================================================
; tray menu
; =============================================================================

A_TrayMenu.Delete()
A_TrayMenu.Add("How to use", ToggleWindowHotkeysHelp)
A_TrayMenu.Add()
A_TrayMenu.Add("Run at startup", ToggleStartup)
A_TrayMenu.Add()
A_TrayMenu.AddStandard()

UpdateStartupMenu()
SetTimer(CheckFancyZonesStartup, 1000)
CheckFancyZonesStartup()


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


IsWindowToggleCandidate(hwnd)
{
    if !hwnd
        return false

    if !DllCall("IsWindowVisible", "ptr", hwnd, "int")
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
        if WinGetMinMax("ahk_id " hwnd) = -1
            return false

        style := WinGetStyle("ahk_id " hwnd)
        ex_style := WinGetExStyle("ahk_id " hwnd)
        title := WinGetTitle("ahk_id " hwnd)
        class_name := WinGetClass("ahk_id " hwnd)
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

    if DllCall("GetWindow", "ptr", hwnd, "uint", 4, "ptr") ; GW_OWNER
        return false

    if IsWindowHotkeysShellClass(class_name)
        return false

    if IsWindowHotkeysCloaked(hwnd)
        return false

    return true
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


; =============================================================================
; FancyZones integration
; =============================================================================

CheckFancyZonesStartup(*)
{
    static attempts := 0

    attempts += 1

    if IsFancyZonesRunning() {
        SetTimer(CheckFancyZonesStartup, 0)
        CheckFancyZonesIntegration()
        return
    }

    if attempts >= 15
        SetTimer(CheckFancyZonesStartup, 0)
}


CheckFancyZonesIntegration(*)
{
    global fancyzones_override_snap_disabled
    global fancyzones_hotkey_conflict

    fancyzones_override_snap_disabled := false
    fancyzones_hotkey_conflict := false

    if !IsFancyZonesRunning()
        return

    state := GetFancyZonesIntegrationState()

    if !state
        return

    fancyzones_override_snap_disabled := !state.override_snap_enabled
    fancyzones_hotkey_conflict := state.hotkey_conflict

    if fancyzones_override_snap_disabled {
        response := MsgBox(
            "FancyZones' Override Windows Snap setting is disabled.`n`n"
            . "Window Hotkeys requires it for Ctrl + Alt + Arrow navigation.`n`n"
            . "Enable Override Windows Snap?",
            "Window Hotkeys",
            "YesNo Icon!"
        )

        if response = "Yes" {
            if EnableFancyZonesOverrideSnap() {
                state := GetFancyZonesIntegrationState()

                if state {
                    fancyzones_override_snap_disabled :=
                        !state.override_snap_enabled

                    fancyzones_hotkey_conflict :=
                        state.hotkey_conflict
                }
            }
            else {
                MsgBox(
                    "Window Hotkeys could not enable Override Windows Snap. "
                    . "You can enable it manually in PowerToys.",
                    "Window Hotkeys",
                    "Icon!"
                )
            }
        }
    }

    if !fancyzones_hotkey_conflict
        return

    response := MsgBox(
        "FancyZones is using Win + PgUp or Win + PgDn for window switching, "
        . "which conflicts with Window Hotkeys' tile shortcuts.`n`n"
        . "Change the conflicting FancyZones shortcuts to their "
        . "Ctrl + Win versions?`n`n"
        . "Yes: use Ctrl + Win + PgUp/PgDn`n"
        . "No: leave FancyZones unchanged",
        "Window Hotkeys",
        "YesNo Icon!"
    )

    if response != "Yes"
        return

    if RemapConflictingFancyZonesHotkeys() {
        state := GetFancyZonesIntegrationState()

        if state {
            fancyzones_override_snap_disabled :=
                !state.override_snap_enabled

            fancyzones_hotkey_conflict :=
                state.hotkey_conflict
        }

        return
    }

    MsgBox(
        "Window Hotkeys could not update the FancyZones shortcuts. "
        . "You can change them manually in PowerToys.",
        "Window Hotkeys",
        "Icon!"
    )
}


IsFancyZonesRunning()
{
    return !!ProcessExist("PowerToys.FancyZones.exe")
}


FormatFancyZonesHotkey(hotkey)
{
    parts := []

    if hotkey.ctrl
        parts.Push("Ctrl")

    if hotkey.alt
        parts.Push("Alt")

    if hotkey.shift
        parts.Push("Shift")

    if hotkey.win
        parts.Push("Win")

    key_name := GetKeyName(Format("vk{:02X}", hotkey.code))

    if key_name = ""
        key_name := Format("VK{:02X}", hotkey.code)

    parts.Push(key_name)

    hotkey_text := ""

    for part in parts {
        if hotkey_text != ""
            hotkey_text .= " + "

        hotkey_text .= part
    }

    return hotkey_text
}


FormatHelpShortcutLine(shortcut, description)
{
    padding := ""
    padding_length := Max(4, 24 - StrLen(shortcut))

    Loop padding_length
        padding .= " "

    return shortcut . padding . description
}


GetFancyZonesIntegrationState()
{
    settings_path := FindFancyZonesSettingsPath()

    if settings_path = ""
        return false

    result_path := (
        A_Temp
        . "\window-hotkeys-fancyzones-"
        . DllCall("GetCurrentProcessId", "uint")
        . "-"
        . A_TickCount
        . ".txt"
    )

    previous_settings_path := EnvGet("WINDOW_HOTKEYS_FANCYZONES_SETTINGS")
    previous_result_path := EnvGet("WINDOW_HOTKEYS_RESULT_PATH")

    EnvSet("WINDOW_HOTKEYS_FANCYZONES_SETTINGS", settings_path)
    EnvSet("WINDOW_HOTKEYS_RESULT_PATH", result_path)

    script_text :=
    (
    "$ErrorActionPreference = 'Stop'; "
    "$path = $env:WINDOW_HOTKEYS_FANCYZONES_SETTINGS; "
    "$settings = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json; "
    "$properties = $settings.properties; "
    "function Test-Conflict($hotkey) { "
    "if ($null -eq $hotkey) { return $false }; "
    "return ([bool]$hotkey.win -and -not [bool]$hotkey.ctrl "
    "-and -not [bool]$hotkey.alt -and -not [bool]$hotkey.shift "
    "-and ([int]$hotkey.code -eq 33 -or [int]$hotkey.code -eq 34)) "
    "}; "
    "$override = [bool]$properties.fancyzones_overrideSnapHotkeys.value; "
    "$switching = [bool]$properties.fancyzones_windowSwitching.value; "
    "$next = $properties.fancyzones_nextTab_hotkey.value; "
    "$previous = $properties.fancyzones_prevTab_hotkey.value; "
    "$conflict = $switching -and "
    "((Test-Conflict $previous) -or (Test-Conflict $next)); "
    "$fields = @( "
    "[int]$override, [int]$switching, [int]$conflict, "
    "[int][bool]$next.win, [int][bool]$next.ctrl, "
    "[int][bool]$next.alt, [int][bool]$next.shift, [int]$next.code, "
    "[int][bool]$previous.win, [int][bool]$previous.ctrl, "
    "[int][bool]$previous.alt, [int][bool]$previous.shift, "
    "[int]$previous.code "
    "); "
    "$result = $fields -join ','; "
    "[IO.File]::WriteAllText($env:WINDOW_HOTKEYS_RESULT_PATH, $result);"
    )

    try {
        exit_code := RunHiddenPowerShell(script_text)
    }
    finally {
        EnvSet(
            "WINDOW_HOTKEYS_FANCYZONES_SETTINGS",
            previous_settings_path
        )
        EnvSet("WINDOW_HOTKEYS_RESULT_PATH", previous_result_path)
    }

    if exit_code != 0 || !FileExist(result_path) {
        DebugLog(
            "FancyZones integration state check failed."
            . " | exit-code=" exit_code
        )
        try FileDelete(result_path)
        return false
    }

    try {
        result := Trim(FileRead(result_path, "UTF-8"))
        fields := StrSplit(result, ",")

        if fields.Length != 13
            return false

        return {
            override_snap_enabled: fields[1] = "1",
            window_switching_enabled: fields[2] = "1",
            hotkey_conflict: fields[3] = "1",
            next_hotkey: {
                win: fields[4] = "1",
                ctrl: fields[5] = "1",
                alt: fields[6] = "1",
                shift: fields[7] = "1",
                code: fields[8] + 0
            },
            previous_hotkey: {
                win: fields[9] = "1",
                ctrl: fields[10] = "1",
                alt: fields[11] = "1",
                shift: fields[12] = "1",
                code: fields[13] + 0
            }
        }
    }
    catch Error as err {
        DebugError("Read FancyZones integration state", err)
        return false
    }
    finally {
        try FileDelete(result_path)
    }
}


EnableFancyZonesOverrideSnap()
{
    settings_path := FindFancyZonesSettingsPath()

    if settings_path = ""
        return false

    previous_settings_path := EnvGet("WINDOW_HOTKEYS_FANCYZONES_SETTINGS")
    EnvSet("WINDOW_HOTKEYS_FANCYZONES_SETTINGS", settings_path)

    ; Edit only the required toggle so every unrelated FancyZones setting stays
    ; exactly as the user configured it.
    script_text :=
    (
    "$ErrorActionPreference = 'Stop'; "
    "$path = $env:WINDOW_HOTKEYS_FANCYZONES_SETTINGS; "
    "$settings = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json; "
    "$settings.properties.fancyzones_overrideSnapHotkeys.value = $true; "
    "$json = $settings | ConvertTo-Json -Depth 20 -Compress; "
    "$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false; "
    "[IO.File]::WriteAllText($path, $json, $utf8);"
    )

    try {
        exit_code := RunHiddenPowerShell(script_text)

        if exit_code != 0 {
            DebugLog(
                "Enable FancyZones Override Windows Snap failed."
                . " | exit-code=" exit_code
            )
            return false
        }

        return true
    }
    finally {
        EnvSet(
            "WINDOW_HOTKEYS_FANCYZONES_SETTINGS",
            previous_settings_path
        )
    }
}


RemapConflictingFancyZonesHotkeys()
{
    settings_path := FindFancyZonesSettingsPath()

    if settings_path = ""
        return false

    previous_settings_path := EnvGet("WINDOW_HOTKEYS_FANCYZONES_SETTINGS")
    EnvSet("WINDOW_HOTKEYS_FANCYZONES_SETTINGS", settings_path)

    ; Edit only the two conflicting hotkey objects. Custom non-conflicting
    ; shortcuts and every unrelated FancyZones setting stay untouched.
    script_text :=
    (
    "$ErrorActionPreference = 'Stop'; "
    "$path = $env:WINDOW_HOTKEYS_FANCYZONES_SETTINGS; "
    "$settings = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json; "
    "$properties = $settings.properties; "
    "function Test-Conflict($hotkey) { "
    "if ($null -eq $hotkey) { return $false }; "
    "return ([bool]$hotkey.win -and -not [bool]$hotkey.ctrl "
    "-and -not [bool]$hotkey.alt -and -not [bool]$hotkey.shift "
    "-and ([int]$hotkey.code -eq 33 -or [int]$hotkey.code -eq 34)) "
    "}; "
    "$changed = $false; "
    "$previous = $properties.fancyzones_prevTab_hotkey.value; "
    "if (Test-Conflict $previous) { "
    "$previous.ctrl = $true; $changed = $true "
    "}; "
    "$next = $properties.fancyzones_nextTab_hotkey.value; "
    "if (Test-Conflict $next) { "
    "$next.ctrl = $true; $changed = $true "
    "}; "
    "if (-not $changed) { exit 0 }; "
    "$json = $settings | ConvertTo-Json -Depth 20 -Compress; "
    "$utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false; "
    "[IO.File]::WriteAllText($path, $json, $utf8);"
    )

    try {
        exit_code := RunHiddenPowerShell(script_text)

        if exit_code != 0 {
            DebugLog(
                "FancyZones shortcut remap failed."
                . " | exit-code=" exit_code
            )
            return false
        }

        return true
    }
    finally {
        EnvSet(
            "WINDOW_HOTKEYS_FANCYZONES_SETTINGS",
            previous_settings_path
        )
    }
}


FindFancyZonesSettingsPath()
{
    local_app_data := EnvGet("LOCALAPPDATA")

    if local_app_data = ""
        return ""

    settings_path := (
        local_app_data
        . "\Microsoft\PowerToys\FancyZones\settings.json"
    )

    if FileExist(settings_path)
        return settings_path

    return ""
}

RunHiddenPowerShell(script_text)
{
    powershell_path := (
        A_WinDir
        . "\System32\WindowsPowerShell\v1.0\powershell.exe"
    )

    if !FileExist(powershell_path)
        return -1

    ; Keep the -Command payload on one line so CreateProcess receives one
    ; predictable argument. These internal commands intentionally use only
    ; single-quoted PowerShell string literals.
    script_text := StrReplace(script_text, "`r", " ")
    script_text := StrReplace(script_text, "`n", " ")

    command := (
        '"' powershell_path '"'
        . " -NoLogo -NoProfile -NonInteractive"
        . " -WindowStyle Hidden -Command "
        . '"' script_text '"'
    )

    try return RunWait(command, , "Hide")
    catch Error as err {
        DebugError("Run PowerShell", err)
        return -1
    }
}

; =============================================================================
; help
; =============================================================================

ToggleWindowHotkeysHelp(*)
{
    global fancyzones_override_snap_disabled
    global fancyzones_hotkey_conflict
    static help_gui := 0

    if help_gui {
        try help_gui.Destroy()
        help_gui := 0
        return
    }

    help_gui := Gui("+AlwaysOnTop", "Window Hotkeys")

    help_text :=
    (
    "Ctrl + Win + H    Toggle this help`n"
    "`n"
    "WINDOW STATE`n"
    "Win + Up          Maximize / borderless fullscreen`n"
    "Win + Down        Minimize`n"
    "Win + Backspace   Restore to normal window`n"
    "Win + Home        Isolate active window / restore others`n"
    "Win + M           Minimize all / restore all`n"
    "`n"
    "SIDE LAYOUTS`n"
    "Win + Left        Cycle left layouts`n"
    "Win + Right       Cycle right layouts`n"
    "`n"
    "TILES`n"
    "Win + Insert      Top-left 1/3 <-> 1/2`n"
    "Win + Delete      Bottom-left 1/3 <-> 1/2`n"
    "Win + End         Top/bottom center 1/3`n"
    "Win + PgUp        Top-right 1/3 <-> 1/2`n"
    "Win + PgDn        Bottom-right 1/3 <-> 1/2`n"
    "`n"
    "WINDOW ARRANGEMENT`n"
    "Win + Enter       Swap with next window clockwise`n"
    "`n"
    "WINDOW FOCUS`n"
    "Alt + Win + Arrow     Start / move spatial focus"
    )

    if IsCapsLockLayerRunning() {
        help_text .= (
            "`n"
            "`n"
            "STEAM`n"
            "Caps + G              Cycle running Steam games"
        )
    }

    if IsFancyZonesRunning() {
        fancyzones_state := GetFancyZonesIntegrationState()

        if fancyzones_state {
            fancyzones_override_snap_disabled :=
                !fancyzones_state.override_snap_enabled

            fancyzones_hotkey_conflict :=
                fancyzones_state.hotkey_conflict
        }

        help_text .= (
            "`n"
            "`n"
            "FANCYZONES`n"
            "Ctrl + Alt + Arrow    Move between FancyZones"
        )

        if fancyzones_state
            && fancyzones_state.window_switching_enabled
        {
            if fancyzones_state.next_hotkey.code {
                next_hotkey_text :=
                    FormatFancyZonesHotkey(fancyzones_state.next_hotkey)

                help_text .= (
                    "`n"
                    . FormatHelpShortcutLine(
                        next_hotkey_text,
                        "Next window in current zone"
                    )
                )
            }

            if fancyzones_state.previous_hotkey.code {
                previous_hotkey_text :=
                    FormatFancyZonesHotkey(
                        fancyzones_state.previous_hotkey
                    )

                help_text .= (
                    "`n"
                    . FormatHelpShortcutLine(
                        previous_hotkey_text,
                        "Previous window in current zone"
                    )
                )
            }
        }

        if fancyzones_override_snap_disabled
            || fancyzones_hotkey_conflict
        {
            help_text .= (
                "`n"
                "`n"
                "WARNING"
            )

            if fancyzones_override_snap_disabled {
                help_text .= (
                    "`n"
                    "FancyZones Override Windows Snap is disabled."
                )
            }

            if fancyzones_hotkey_conflict {
                help_text .= (
                    "`n"
                    "FancyZones Win + PgUp/PgDn conflict with the tile shortcuts above."
                )
            }
        }
    }

    help_gui.SetFont("s10", "Cascadia Mono")
    help_gui.AddText("w550", help_text)

    help_gui.OnEvent("Close", CloseHelp)
    help_gui.OnEvent("Escape", CloseHelp)
    help_gui.Show()

    CloseHelp(*)
    {
        help_gui.Destroy()
        help_gui := 0
    }
}


; =============================================================================
; directional focus
; =============================================================================

FocusNearestWindow(direction)
{
    global focus_navigation_active, focus_navigation_hwnd

    active_hwnd := WinExist("A")

    if !active_hwnd
        return

    ; The first directional-focus press starts on the current window instead
    ; of immediately leaving it. A manual focus change also starts a new
    ; session from that newly focused window.
    if !focus_navigation_active
        || active_hwnd != focus_navigation_hwnd
    {
        ForgetLastMinimizedWindow()
        focus_navigation_active := true
        focus_navigation_hwnd := active_hwnd
        HighlightFocusedWindow(active_hwnd)
        return
    }

    try {
        WinGetPos(
            &active_x,
            &active_y,
            &active_width,
            &active_height,
            "ahk_id " active_hwnd
        )
    }
    catch {
        return
    }

    active_center_x := active_x + active_width / 2
    active_center_y := active_y + active_height / 2

    target_hwnd := 0
    best_score := 0

    for hwnd in WinGetList() {
        if hwnd = active_hwnd
            continue

        if !IsWindowToggleCandidate(hwnd)
            continue

        try {
            WinGetPos(
                &candidate_x,
                &candidate_y,
                &candidate_width,
                &candidate_height,
                "ahk_id " hwnd
            )
        }
        catch {
            continue
        }

        candidate_center_x :=
            candidate_x + candidate_width / 2

        candidate_center_y :=
            candidate_y + candidate_height / 2

        delta_x := candidate_center_x - active_center_x
        delta_y := candidate_center_y - active_center_y

        switch direction {
            case "left":
                if delta_x >= 0
                    continue

                primary_distance := -delta_x
                perpendicular_distance := Abs(delta_y)

            case "right":
                if delta_x <= 0
                    continue

                primary_distance := delta_x
                perpendicular_distance := Abs(delta_y)

            case "up":
                if delta_y >= 0
                    continue

                primary_distance := -delta_y
                perpendicular_distance := Abs(delta_x)

            case "down":
                if delta_y <= 0
                    continue

                primary_distance := delta_y
                perpendicular_distance := Abs(delta_x)

            default:
                return
        }

        ; Prefer nearby windows while strongly favoring alignment with the
        ; requested direction.
        score :=
            primary_distance
            + perpendicular_distance * 2

        if !target_hwnd || score < best_score {
            target_hwnd := hwnd
            best_score := score
        }
    }

    if !target_hwnd
        return

    ForgetLastMinimizedWindow()

    try {
        WinActivate("ahk_id " target_hwnd)
        focus_navigation_hwnd := target_hwnd
        HighlightFocusedWindow(target_hwnd)
    }
}


HighlightFocusedWindow(hwnd)
{
    global focus_highlight_guis
    global focus_highlight_duration_ms
    global focus_highlight_thickness
    global focus_highlight_overlap

    ; Refresh the focus-navigation session timeout on every focused window.
    SetTimer EndFocusNavigationSession, 0
    ClearFocusHighlight()

    if !hwnd || !WinExist("ahk_id " hwnd) {
        EndFocusNavigationSession()
        return
    }

    if !GetVisibleWindowBounds(
        hwnd,
        &window_x,
        &window_y,
        &window_width,
        &window_height
    ) {
        EndFocusNavigationSession()
        return
    }

    thickness := focus_highlight_thickness
    overlap := focus_highlight_overlap
    outside := thickness - overlap

    if window_width <= thickness * 2
        || window_height <= thickness * 2
    {
        EndFocusNavigationSession()
        return
    }

    accent_color := GetWindowsAccentHexColor()

    ; Keep most of the highlight outside the visible frame, but overlap the
    ; window slightly so Windows' frame/shadow boundary cannot leave a gap.
    border_rects := [
        [
            window_x - outside,
            window_y - outside,
            window_width + outside * 2,
            thickness
        ],
        [
            window_x - outside,
            window_y + window_height - overlap,
            window_width + outside * 2,
            thickness
        ],
        [
            window_x - outside,
            window_y,
            thickness,
            window_height
        ],
        [
            window_x + window_width - overlap,
            window_y,
            thickness,
            window_height
        ]
    ]

    for rect in border_rects {
        highlight_gui := Gui(
            "+AlwaysOnTop -Caption +ToolWindow +E0x20 +E0x08000000"
        )

        highlight_gui.BackColor := accent_color

        show_options :=
            "NA"
            . " x" rect[1]
            . " y" rect[2]
            . " w" rect[3]
            . " h" rect[4]

        highlight_gui.Show(show_options)
        focus_highlight_guis.Push(highlight_gui)
    }

    SetTimer(
        EndFocusNavigationSession,
        -focus_highlight_duration_ms
    )
}


EndFocusNavigationSession()
{
    global focus_navigation_active, focus_navigation_hwnd

    focus_navigation_active := false
    focus_navigation_hwnd := 0
    ClearFocusHighlight()
}


ClearFocusHighlight()
{
    global focus_highlight_guis

    for highlight_gui in focus_highlight_guis {
        try highlight_gui.Destroy()
    }

    focus_highlight_guis := []
}


GetVisibleWindowBounds(
    hwnd,
    &x,
    &y,
    &width,
    &height
)
{
    static DWMWA_EXTENDED_FRAME_BOUNDS := 9

    frame := Buffer(16, 0)

    result := DllCall(
        "dwmapi\DwmGetWindowAttribute",
        "ptr", hwnd,
        "uint", DWMWA_EXTENDED_FRAME_BOUNDS,
        "ptr", frame,
        "uint", frame.Size,
        "int"
    )

    if result != 0
        return false

    left := NumGet(frame, 0, "int")
    top := NumGet(frame, 4, "int")
    right := NumGet(frame, 8, "int")
    bottom := NumGet(frame, 12, "int")

    x := left
    y := top
    width := right - left
    height := bottom - top

    return width > 0 && height > 0
}


GetWindowsAccentHexColor()
{
    colorization_color := 0
    opaque_blend := 0

    result := DllCall(
        "dwmapi\DwmGetColorizationColor",
        "uint*", &colorization_color,
        "int*", &opaque_blend,
        "int"
    )

    if result != 0
        return "0078D4"

    red := (colorization_color >> 16) & 0xFF
    green := (colorization_color >> 8) & 0xFF
    blue := colorization_color & 0xFF

    return Format(
        "{:02X}{:02X}{:02X}",
        red,
        green,
        blue
    )
}


; =============================================================================
; steam game cycling
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


ActivateWindowReliably(hwnd)
{
    if !hwnd || !DllCall("IsWindow", "ptr", hwnd, "int")
        return false

    DebugLog(
        "ActivateWindowReliably begin."
        . " | target=" DebugDescribeWindow(hwnd)
    )

    try {
        if WinGetMinMax(hwnd) = -1
            WinRestore(hwnd)
    }

    Loop 6 {
        attempt := A_Index

        try WinActivate(hwnd)

        set_foreground_result := DllCall(
            "SetForegroundWindow",
            "ptr", hwnd,
            "int"
        )

        Sleep 50

        foreground_hwnd :=
            DllCall("GetForegroundWindow", "ptr")

        DebugLog(
            "Normal-window activation attempt."
            . " | attempt=" attempt
            . " | SetForegroundWindow="
            . set_foreground_result
            . " | requested=" DebugDescribeWindow(hwnd)
            . " | foreground="
            . DebugDescribeWindow(foreground_hwnd)
        )

        if foreground_hwnd = hwnd
            return true
    }

    return false
}


FindWindowIndex(windows, target_hwnd)
{
    if !target_hwnd
        return 0

    for index, hwnd in windows {
        if hwnd = target_hwnd
            return index
    }

    return 0
}


; =============================================================================
; debug helpers
; =============================================================================

InitializeDebugLogging()
{
    global debug_enabled

    if !debug_enabled
        return

    reset_message := DllCall(
        "RegisterWindowMessage",
        "str", "WindowDebug.ResetLogs",
        "uint"
    )

    if reset_message {
        OnMessage(
            reset_message,
            HandleDebugResetLogsMessage
        )
    }

    OnError(LogWindowHotkeysUnhandledError)

    DebugLogSession("started")
}


HandleDebugResetLogsMessage(*)
{
    ResetDebugLog()
}


ResetDebugLog()
{
    global debug_enabled, debug_log_path

    if !debug_enabled
        return

    try {
        if FileExist(debug_log_path)
            FileDelete(debug_log_path)
    }
    catch Error as err {
        DebugLog(
            "Debug log reset failed."
            . " | message=" err.Message
        )
        return
    }

    DebugLogSession("reset")
}


DebugLogSession(reason)
{
    process_id := DllCall(
        "GetCurrentProcessId",
        "uint"
    )

    DebugLog(
        "Debug session " reason "."
        . " | pid=" process_id
        . " | ahk=" A_AhkVersion
        . ' | script="' A_ScriptFullPath '"'
    )
}


DebugLog(message)
{
    global debug_enabled, debug_log_path

    if !debug_enabled
        return

    timestamp := FormatTime(
        ,
        "yyyy-MM-dd HH:mm:ss"
    )

    try FileAppend(
        timestamp
        . " | tick=" A_TickCount
        . " | " message
        . "`n",
        debug_log_path,
        "UTF-8-RAW"
    )
}

DebugError(context, err)
{
    DebugLog(
        "ERROR in " context
        . " | message=" err.Message
        . " | what=" err.What
        . " | file=" err.File
        . " | line=" err.Line
    )

    if err.Stack != ""
        DebugLog(
            "STACK | "
            . StrReplace(
                StrReplace(err.Stack, "`r", ""),
                "`n",
                " | "
            )
        )
}


LogWindowHotkeysUnhandledError(err, mode)
{
    DebugError(
        "Unhandled error, mode=" mode,
        err
    )

    return 0
}


DebugDescribeWindow(hwnd)
{
    if !hwnd
        return "hwnd=0"

    if !DllCall("IsWindow", "ptr", hwnd, "int")
        return "hwnd=" hwnd " [invalid]"

    title := ""
    class_name := ""
    process_name := ""
    process_path := ""
    min_max := "?"
    style := "?"
    ex_style := "?"
    x := "?"
    y := "?"
    width := "?"
    height := "?"

    try title := WinGetTitle(hwnd)
    try class_name := WinGetClass(hwnd)
    try process_name := WinGetProcessName(hwnd)
    try process_path := WinGetProcessPath(hwnd)
    try min_max := WinGetMinMax(hwnd)
    try style := WinGetStyle(hwnd)
    try ex_style := WinGetExStyle(hwnd)

    try WinGetPos(
        &x,
        &y,
        &width,
        &height,
        hwnd
    )

    title := StrReplace(
        StrReplace(title, "`r", " "),
        "`n",
        " "
    )

    visible :=
        DllCall(
            "IsWindowVisible",
            "ptr", hwnd,
            "int"
        )

    iconic :=
        DllCall(
            "IsIconic",
            "ptr", hwnd,
            "int"
        )

    owner :=
        DllCall(
            "GetWindow",
            "ptr", hwnd,
            "uint", 4,
            "ptr"
        )

    cloaked := false

    try cloaked :=
        IsWindowHotkeysCloaked(hwnd)

    return (
        "hwnd=" hwnd
        . ' exe="' process_name '"'
        . ' class="' class_name '"'
        . ' title="' title '"'
        . " minmax=" min_max
        . " visible=" visible
        . " iconic=" iconic
        . " cloaked=" cloaked
        . " owner=" owner
        . " style=" style
        . " exstyle=" ex_style
        . " rect=(" x "," y " "
        . width "x" height ")"
        . ' path="' process_path '"'
    )
}


DebugSteamGameState(label)
{
    global steam_game_cycle
    global last_steam_game_hwnd
    global steam_return_hwnd

    DebugLog(
        label
        . " | cycle-count=" steam_game_cycle.Length
        . " | last="
        . DebugDescribeWindow(last_steam_game_hwnd)
        . " | return="
        . DebugDescribeWindow(steam_return_hwnd)
        . " | foreground="
        . DebugDescribeWindow(
            DllCall("GetForegroundWindow", "ptr")
        )
    )

    for index, hwnd in steam_game_cycle {
        DebugLog(
            "Steam cycle entry."
            . " | index=" index
            . " | " DebugDescribeWindow(hwnd)
        )
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


; =============================================================================
; side-layout cycle
; =============================================================================

CycleWindowSnap(side)
{
    global last_minimized_hwnd
    global borderless_windows

    ; Special states start a fresh side cycle even if restoring them happens
    ; to put the window on coordinates that match an existing layout.
    fresh_cycle_entry := !!last_minimized_hwnd

    hwnd := GetWindowControlTarget()

    if !hwnd
        return

    window := "ahk_id " hwnd

    try {
        if borderless_windows.Has(hwnd)
            fresh_cycle_entry := true
        else if WinGetMinMax(window) = 1
            fresh_cycle_entry := true

        PrepareWindowForPlacement(hwnd)

        GetWindowMonitorWorkArea(
            hwnd,
            &left,
            &top,
            &right,
            &bottom
        )

        work_width := right - left
        work_height := bottom - top

        half_width := Floor(work_width / 2)
        third_width := Floor(work_width / 3)
        two_thirds_width := Floor(work_width * 2 / 3)

        center_third_x :=
            left + Floor((work_width - third_width) / 2)

        center_third := [
            center_third_x,
            top,
            third_width,
            work_height
        ]

        left_layouts := [
            [left, top, half_width, work_height],
            [left, top, third_width, work_height],
            center_third,
            [left, top, two_thirds_width, work_height]
        ]

        right_layouts := [
            [right - half_width, top, half_width, work_height],
            [right - third_width, top, third_width, work_height],
            center_third,
            [
                right - two_thirds_width,
                top,
                two_thirds_width,
                work_height
            ]
        ]

        if side = "left" {
            layouts := left_layouts
            opposite_layouts := right_layouts
        } else {
            layouts := right_layouts
            opposite_layouts := left_layouts
        }

        if !fresh_cycle_entry {
            ; If the window already belongs to this arrow's cycle, advance one
            ; step. The center third acts as the junction before the two-thirds
            ; layout on either side.
            matched_index := FindMatchingLayoutIndex(
                window,
                layouts
            )

            if matched_index {
                next_index := (
                    matched_index = layouts.Length
                    ? 1
                    : matched_index + 1
                )

                target := layouts[next_index]
            } else {
                ; Pressing the opposite arrow walks backward through the side
                ; the window currently occupies instead of jumping across.
                opposite_index := FindMatchingLayoutIndex(
                    window,
                    opposite_layouts
                )

                if opposite_index {
                    previous_index := (
                        opposite_index = 1
                        ? opposite_layouts.Length
                        : opposite_index - 1
                    )

                    target := opposite_layouts[previous_index]
                } else {
                    fresh_cycle_entry := true
                }
            }
        }

        if fresh_cycle_entry {
            ; Every fresh side-cycle entry starts at two-thirds.
            target := layouts[4]
        }

        WinMove(
            target[1],
            target[2],
            target[3],
            target[4],
            window
        )
    }
}

FindMatchingLayoutIndex(window, layouts, tolerance := 8)
{
    WinGetPos(
        &x,
        &y,
        &width,
        &height,
        window
    )

    for layout_index, layout in layouts {
        if Abs(x - layout[1]) > tolerance
            continue

        if Abs(y - layout[2]) > tolerance
            continue

        if Abs(width - layout[3]) > tolerance
            continue

        if Abs(height - layout[4]) > tolerance
            continue

        return layout_index
    }

    return 0
}


; =============================================================================
; quarter placement
; =============================================================================

PlaceWindowQuarter(position)
{
    hwnd := GetWindowControlTarget()

    if !hwnd
        return

    window := "ahk_id " hwnd

    try {
        PrepareWindowForPlacement(hwnd)

        third_layout := GetQuarterLayout(
            hwnd,
            position,
            "third"
        )

        half_layout := GetQuarterLayout(
            hwnd,
            position,
            "half"
        )

        ; Arbitrary positions enter at the smaller third-width tile.
        ; Repeating the same shortcut toggles between third and half width.
        if WindowMatchesLayout(window, third_layout)
            target := half_layout
        else
            target := third_layout

        WinMove(
            target[1],
            target[2],
            target[3],
            target[4],
            window
        )
    }
}

ToggleCenterQuarter()
{
    hwnd := GetWindowControlTarget()

    if !hwnd
        return

    window := "ahk_id " hwnd

    try {
        PrepareWindowForPlacement(hwnd)

        top_layout := GetQuarterLayout(hwnd, "top-center", "third")
        bottom_layout := GetQuarterLayout(hwnd, "bottom-center", "third")

        if WindowMatchesLayout(window, top_layout)
            target := bottom_layout
        else
            target := top_layout

        WinMove(
            target[1],
            target[2],
            target[3],
            target[4],
            window
        )
    }
}


GetQuarterLayout(hwnd, position, width_mode := "half")
{
    GetWindowMonitorWorkArea(
        hwnd,
        &left,
        &top,
        &right,
        &bottom
    )

    work_width := right - left
    work_height := bottom - top

    tile_width := (
        width_mode = "third"
        ? Floor(work_width / 3)
        : Floor(work_width / 2)
    )

    half_height := Floor(work_height / 2)

    switch position {
        case "top-left", "bottom-left":
            target_x := left
        case "top-center", "bottom-center":
            target_x := left + Floor((work_width - tile_width) / 2)
        case "top-right", "bottom-right":
            target_x := right - tile_width
        default:
            throw Error("Unknown quarter position: " position)
    }

    is_top := InStr(position, "top-") = 1
    target_y := is_top ? top : top + half_height

    ; The bottom tile receives any leftover pixel from an odd work-area height.
    tile_height := is_top ? half_height : bottom - target_y

    return [target_x, target_y, tile_width, tile_height]
}


WindowMatchesLayout(window, layout, tolerance := 8)
{
    return FindMatchingLayoutIndex(window, [layout], tolerance) = 1
}


; =============================================================================
; clockwise window swapping
; =============================================================================

SwapWindowClockwise()
{
    hwnd := GetWindowControlTarget()

    if !hwnd
        return

    window := "ahk_id " hwnd

    try {
        PrepareWindowForPlacement(hwnd)

        monitor_handle := DllCall(
            "MonitorFromWindow",
            "ptr", hwnd,
            "uint", 2, ; MONITOR_DEFAULTTONEAREST
            "ptr"
        )

        GetWindowMonitorWorkArea(
            hwnd,
            &work_left,
            &work_top,
            &work_right,
            &work_bottom
        )

        monitor_center_x :=
            work_left + (work_right - work_left) / 2

        monitor_center_y :=
            work_top + (work_bottom - work_top) / 2

        windows := GetClockwiseWindowOrder(
            monitor_handle,
            monitor_center_x,
            monitor_center_y
        )

        if windows.Length < 2
            return

        active_index := 0

        for index, item in windows {
            if item["hwnd"] = hwnd {
                active_index := index
                break
            }
        }

        if !active_index
            return

        next_index := (
            active_index = windows.Length
            ? 1
            : active_index + 1
        )

        target_hwnd := windows[next_index]["hwnd"]

        SwapWindowRectangles(hwnd, target_hwnd)

        WinActivate(window)
    }
}


GetClockwiseWindowOrder(
    monitor_handle,
    monitor_center_x,
    monitor_center_y
)
{
    items := []

    for hwnd in WinGetList() {
        if !IsClockwiseSwapCandidate(hwnd, monitor_handle)
            continue

        try {
            WinGetPos(
                &x,
                &y,
                &width,
                &height,
                "ahk_id " hwnd
            )
        }
        catch {
            continue
        }

        center_x := x + width / 2
        center_y := y + height / 2

        angle := GetClockwiseAngleFromTop(
            center_x - monitor_center_x,
            center_y - monitor_center_y
        )

        item := Map(
            "hwnd", hwnd,
            "angle", angle
        )

        insert_index := items.Length + 1

        Loop items.Length {
            if angle < items[A_Index]["angle"] {
                insert_index := A_Index
                break
            }
        }

        items.InsertAt(insert_index, item)
    }

    return items
}


GetClockwiseAngleFromTop(delta_x, delta_y)
{
    static two_pi := 6.283185307179586

    ; atan2(dx, -dy) makes 0 point upward and increases clockwise.
    angle := DllCall(
        "msvcrt\atan2",
        "double", delta_x,
        "double", -delta_y,
        "cdecl double"
    )

    if angle < 0
        angle += two_pi

    return angle
}


IsClockwiseSwapCandidate(hwnd, monitor_handle)
{
    global borderless_windows

    if !hwnd
        return false

    if borderless_windows.Has(hwnd)
        return false

    if !DllCall("IsWindowVisible", "ptr", hwnd, "int")
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
        if WinGetMinMax("ahk_id " hwnd) != 0
            return false

        style := WinGetStyle("ahk_id " hwnd)
        ex_style := WinGetExStyle("ahk_id " hwnd)
        title := WinGetTitle("ahk_id " hwnd)
        class_name := WinGetClass("ahk_id " hwnd)
    }
    catch {
        return false
    }

    if title = ""
        return false

    if style & 0x40000000 ; WS_CHILD
        return false

    if !(style & 0x00C00000) ; normal caption
        return false

    if !(style & 0x00040000) ; resizable
        return false

    if ex_style & 0x00000080 ; WS_EX_TOOLWINDOW
        return false

    if ex_style & 0x08000000 ; WS_EX_NOACTIVATE
        return false

    if DllCall("GetWindow", "ptr", hwnd, "uint", 4, "ptr") ; GW_OWNER
        return false

    if IsWindowHotkeysShellClass(class_name)
        return false

    if IsWindowHotkeysCloaked(hwnd)
        return false

    candidate_monitor := DllCall(
        "MonitorFromWindow",
        "ptr", hwnd,
        "uint", 2,
        "ptr"
    )

    return candidate_monitor = monitor_handle
}


SwapWindowRectangles(first_hwnd, second_hwnd)
{
    first_window := "ahk_id " first_hwnd
    second_window := "ahk_id " second_hwnd

    WinGetPos(
        &first_x,
        &first_y,
        &first_width,
        &first_height,
        first_window
    )

    WinGetPos(
        &second_x,
        &second_y,
        &second_width,
        &second_height,
        second_window
    )

    WinMove(
        second_x,
        second_y,
        second_width,
        second_height,
        first_window
    )

    try {
        WinMove(
            first_x,
            first_y,
            first_width,
            first_height,
            second_window
        )
    }
    catch {
        ; Do not leave the active window displaced if the other window cannot
        ; be controlled, such as an elevated application.
        try WinMove(
            first_x,
            first_y,
            first_width,
            first_height,
            first_window
        )

        throw
    }
}


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


PrepareWindowForPlacement(hwnd)
{
    global borderless_windows

    window := "ahk_id " hwnd

    if borderless_windows.Has(hwnd) {
        RestoreBorderlessWindow(hwnd, false, true)
        return
    }

    if WinGetMinMax(window) != 0
        WinRestore(window)
}


CaptureWindowPlacement(hwnd)
{
    placement := Buffer(44, 0)
    NumPut("uint", placement.Size, placement, 0)

    if !DllCall(
        "GetWindowPlacement",
        "ptr", hwnd,
        "ptr", placement,
        "int"
    ) {
        throw OSError()
    }

    return placement
}


ApplyWindowPlacement(hwnd, placement, show_command := unset)
{
    original_show_command := NumGet(
        placement,
        8,
        "uint"
    )

    try {
        if IsSet(show_command)
            NumPut(
                "uint",
                show_command,
                placement,
                8
            )

        if !DllCall(
            "SetWindowPlacement",
            "ptr", hwnd,
            "ptr", placement,
            "int"
        ) {
            throw OSError()
        }
    }
    finally {
        if IsSet(show_command)
            NumPut(
                "uint",
                original_show_command,
                placement,
                8
            )
    }
}


RefreshWindowFrame(hwnd)
{
    static SWP_NOSIZE := 0x0001
    static SWP_NOMOVE := 0x0002
    static SWP_NOZORDER := 0x0004
    static SWP_NOACTIVATE := 0x0010
    static SWP_FRAMECHANGED := 0x0020

    DllCall(
        "SetWindowPos",
        "ptr", hwnd,
        "ptr", 0,
        "int", 0,
        "int", 0,
        "int", 0,
        "int", 0,
        "uint",
        SWP_NOSIZE
        | SWP_NOMOVE
        | SWP_NOZORDER
        | SWP_NOACTIVATE
        | SWP_FRAMECHANGED
    )
}


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

; =============================================================================
; monitor helpers
; =============================================================================

GetWindowMonitorBounds(hwnd, &left, &top, &right, &bottom)
{
    monitor_info := GetWindowMonitorInfo(hwnd)

    ; rcMonitor includes the taskbar area.
    left := NumGet(monitor_info, 4, "int")
    top := NumGet(monitor_info, 8, "int")
    right := NumGet(monitor_info, 12, "int")
    bottom := NumGet(monitor_info, 16, "int")
}


GetWindowMonitorWorkArea(hwnd, &left, &top, &right, &bottom)
{
    monitor_info := GetWindowMonitorInfo(hwnd)

    ; rcWork excludes the taskbar.
    left := NumGet(monitor_info, 20, "int")
    top := NumGet(monitor_info, 24, "int")
    right := NumGet(monitor_info, 28, "int")
    bottom := NumGet(monitor_info, 32, "int")
}


GetWindowMonitorInfo(hwnd)
{
    monitor_handle := DllCall(
        "MonitorFromWindow",
        "ptr", hwnd,
        "uint", 2, ; MONITOR_DEFAULTTONEAREST
        "ptr"
    )

    monitor_info := Buffer(40, 0)
    NumPut("uint", monitor_info.Size, monitor_info, 0)

    if !DllCall(
        "GetMonitorInfo",
        "ptr", monitor_handle,
        "ptr", monitor_info
    ) {
        throw OSError()
    }

    return monitor_info
}


IsWindowHotkeysCloaked(hwnd)
{
    cloaked := 0

    result := DllCall(
        "dwmapi\DwmGetWindowAttribute",
        "ptr", hwnd,
        "uint", 14, ; DWMWA_CLOAKED
        "uint*", &cloaked,
        "uint", 4,
        "int"
    )

    return result = 0 && cloaked != 0
}


IsWindowHotkeysShellClass(class_name)
{
    return (
        class_name = "Shell_TrayWnd"
        || class_name = "Shell_SecondaryTrayWnd"
        || class_name = "Progman"
        || class_name = "WorkerW"
        || class_name = "NotifyIconOverflowWindow"
        || class_name = "tooltips_class32"
    )
}


; =============================================================================
; startup
; =============================================================================

ToggleStartup(*)
{
    global startup_shortcut_path

    if FileExist(startup_shortcut_path) {
        FileDelete(startup_shortcut_path)
    } else if A_IsCompiled {
        FileCreateShortcut(
            A_ScriptFullPath,
            startup_shortcut_path,
            A_ScriptDir
        )
    } else {
        FileCreateShortcut(
            A_AhkPath,
            startup_shortcut_path,
            A_ScriptDir,
            '"' A_ScriptFullPath '"'
        )
    }

    UpdateStartupMenu()
}


UpdateStartupMenu()
{
    global startup_shortcut_path

    if FileExist(startup_shortcut_path)
        A_TrayMenu.Check("Run at startup")
    else
        A_TrayMenu.Uncheck("Run at startup")
}
