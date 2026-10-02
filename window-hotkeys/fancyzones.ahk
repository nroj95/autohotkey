; Internal Window Hotkeys module. Launch ..\window-hotkeys.ahk instead.
; Included into the same script; functions share the existing global state.

; =============================================================================
; FancyZones startup and compatibility checks
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
        . "Ctrl + Alt versions?`n`n"
        . "Yes: use Ctrl + Alt + PgUp/PgDn`n"
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

; =============================================================================
; FancyZones shortcut display
; =============================================================================

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

; =============================================================================
; FancyZones settings access
; =============================================================================

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
    "$previous.win = $false; $previous.ctrl = $true; "
    "$previous.alt = $true; $changed = $true "
    "}; "
    "$next = $properties.fancyzones_nextTab_hotkey.value; "
    "if (Test-Conflict $next) { "
    "$next.win = $false; $next.ctrl = $true; "
    "$next.alt = $true; $changed = $true "
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

; =============================================================================
; internal PowerShell bridge
; =============================================================================

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
