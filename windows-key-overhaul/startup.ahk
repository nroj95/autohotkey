; Internal Windows Key Overhaul module. Launch ..\windows-key-overhaul.ahk.

; =============================================================================
; safe transition from the old script name
; =============================================================================

EnsureLegacyScriptIsStopped()
{
    previous_setting := DetectHiddenWindows(true)
    try {
        for hwnd in WinGetList("ahk_class AutoHotkey") {
            if hwnd = A_ScriptHwnd
                continue
            title := StrLower(WinGetTitle(hwnd))
            if !InStr(title, "\window-hotkeys.ahk - autohotkey v")
                continue
            MsgBox(
                "Window Hotkeys is still running.`n`n"
                . "Exit the old script from its tray menu, then launch "
                . "windows-key-overhaul.ahk again. Running both would register "
                . "conflicting shortcuts. The old process has not been closed.",
                "Windows Key Overhaul", "Icon!"
            )
            ExitApp()
        }
    }
    finally {
        DetectHiddenWindows(previous_setting)
    }
}

InitializeDesktopIntegration(*)
{
    try MigrateLegacyStartupShortcut()
    try PromptToDisableNativeWindowsSnap()
    try RecommendScreenGrid()
    CheckFancyZonesStartup()
    SetTimer(CheckFancyZonesStartup, 5000)
}

MigrateLegacyStartupShortcut()
{
    global legacy_startup_shortcut_path
    if !FileExist(legacy_startup_shortcut_path)
        return

    FileGetShortcut(legacy_startup_shortcut_path, &target, , &arguments)
    legacy_script := StrLower(A_ScriptDir "\window-hotkeys.ahk")
    legacy_executable := StrLower(A_ScriptDir "\window-hotkeys.exe")
    if StrLower(target) != legacy_script && StrLower(target) != legacy_executable
        && StrLower(Trim(arguments, ' "`t')) != legacy_script
    {
        ; A same-named shortcut may belong to another installation. Leave it alone.
        return
    }

    response := MsgBox(
        "Replace this installation's old Window Hotkeys startup shortcut "
        . "with Windows Key Overhaul?`n`n"
        . "Only the shortcut is replaced; the old script files remain unchanged.",
        "Windows Key Overhaul", "YesNo Default2 Icon?"
    )
    if response != "Yes"
        return

    ; Create the replacement first so a failure cannot silently disable startup.
    CreateStartupShortcut()
    FileDelete(legacy_startup_shortcut_path)
    UpdateStartupMenu()
}

; =============================================================================
; native Windows Snap
; =============================================================================

GetNativeWindowsSnapState()
{
    enabled := 0
    if !DllCall(
        "SystemParametersInfoW", "uint", 0x0082, "uint", 0,
        "int*", &enabled, "uint", 0, "int" ; SPI_GETWINARRANGING
    ) {
        return -1
    }
    return !!enabled
}

PromptToDisableNativeWindowsSnap()
{
    state := GetNativeWindowsSnapState()
    if state != 1 {
        if state = -1
            DebugLog("Could not query native Windows Snap state.")
        return
    }

    response := MsgBox(
        "Native Windows Snap is currently enabled.`n`n"
        . "Disabling it is recommended so Windows' own snapping does not "
        . "compete with these shortcuts or a drag-snapping tool.`n`n"
        . "Disable Windows Snap for your account now? This is a persistent "
        . "Windows preference; you can re-enable it in Settings > System > "
        . "Multitasking. Choosing No makes no change.`n`n"
        . "ScreenGrid is an optional companion for customizable Shift + drag layouts.",
        "Windows Key Overhaul", "YesNo Default2 Icon?"
    )
    if response != "Yes"
        return

    ; Use the documented API, not a collection of guessed registry switches.
    ; SPI_SETWINARRANGING; SPIF_UPDATEINIFILE | SPIF_SENDCHANGE.
    succeeded := DllCall(
        "SystemParametersInfoW", "uint", 0x0083, "uint", 0,
        "ptr", 0, "uint", 0x0003, "int"
    )
    if !succeeded || GetNativeWindowsSnapState() != 0 {
        MsgBox(
            "Windows Snap could not be disabled automatically.`n`n"
            . "Use the tray menu's Windows Snap settings command and turn off Snap windows.",
            "Windows Key Overhaul", "Icon!"
        )
    }
}

OpenWindowsSnapSettings(*)
{
    Run("ms-settings:multitasking")
}

; =============================================================================
; optional ScreenGrid recommendation
; =============================================================================

RecommendScreenGrid()
{
    global user_preferences_directory, user_preferences_path
    if IniRead(user_preferences_path, "Startup", "ScreenGridRecommendationSeen", "0") = "1"
        return

    if !IsScreenGridRunning() {
        response := MsgBox(
            "ScreenGrid is recommended as a companion to these keyboard shortcuts.`n`n"
            . "It adds customizable Shift + drag window layouts. It is optional; "
            . "Windows Key Overhaul runs without it.`n`n"
            . "Open ScreenGrid's official GitHub releases page? Nothing will be "
            . "downloaded or installed automatically.`n`n"
            . "This recommendation is shown once. The GitHub link remains in the tray menu.",
            "Windows Key Overhaul", "YesNo Default2 Icon?"
        )
        if response = "Yes"
            OpenScreenGridReleases()
    }

    DirCreate(user_preferences_directory)
    IniWrite(1, user_preferences_path, "Startup", "ScreenGridRecommendationSeen")
}

IsScreenGridRunning()
{
    for executable in ["ScreenGrid.exe", "ScreenGrid-standalone.exe", "ScreenGrid-small.exe"] {
        if ProcessExist(executable)
            return true
    }
    return false
}

OpenScreenGridReleases(*)
{
    global screengrid_releases_url
    Run(screengrid_releases_url)
}
