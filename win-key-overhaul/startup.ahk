; Internal Win Key Overhaul module. Launch ..\win-key-overhaul.ahk.

; =============================================================================
; safe transition from the old script name
; =============================================================================

EnsurePreviousLaunchersAreStopped()
{
    previous_setting := DetectHiddenWindows(true)

    try {
        for hwnd in WinGetList("ahk_class AutoHotkey") {
            if hwnd = A_ScriptHwnd
                continue

            title := StrLower(WinGetTitle(hwnd))

            if !InStr(title, "\windows-key-overhaul.ahk - autohotkey v")
                && !InStr(title, "\window-hotkeys.ahk - autohotkey v")
            {
                continue
            }

            MsgBox(
                "A previous Win-key window manager is still running.`n`n"
                . "Exit it from its tray menu, then launch win-key-overhaul.ahk "
                . "again. Running both would register conflicting shortcuts.",
                "Win Key Overhaul",
                "Icon!"
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
    try MigratePreviousStartupShortcuts()
    try MigratePreviousPreferences()
    try PromptToDisableNativeWindowsSnap()
    try RecommendScreenGrid()
    CheckFancyZonesStartup()
    SetTimer(CheckFancyZonesStartup, 5000)
}

MigratePreviousStartupShortcuts()
{
    global previous_startup_shortcut_paths

    shortcuts_to_replace := []

    for shortcut_path in previous_startup_shortcut_paths {
        if !FileExist(shortcut_path)
            continue

        try FileGetShortcut(shortcut_path, &target, , &arguments)
        catch
            continue

        if IsPreviousWinKeyOverhaulShortcut(target, arguments)
            shortcuts_to_replace.Push(shortcut_path)
    }

    if !shortcuts_to_replace.Length
        return

    response := MsgBox(
        "Replace this installation's previous startup shortcut with "
        . "Win Key Overhaul?`n`n"
        . "The new shortcut is created before the previous one is removed.",
        "Win Key Overhaul",
        "YesNo Default2 Icon?"
    )

    if response != "Yes"
        return

    CreateStartupShortcut()

    for shortcut_path in shortcuts_to_replace
        try FileDelete(shortcut_path)

    UpdateStartupMenu()
}

IsPreviousWinKeyOverhaulShortcut(target, arguments)
{
    target := StrLower(target)
    arguments := StrLower(Trim(arguments, ' "`t'))

    previous_launchers := [
        StrLower(A_ScriptDir "\windows-key-overhaul.ahk"),
        StrLower(A_ScriptDir "\windows-key-overhaul.exe"),
        StrLower(A_ScriptDir "\window-hotkeys.ahk"),
        StrLower(A_ScriptDir "\window-hotkeys.exe")
    ]

    for launcher_path in previous_launchers {
        if target = launcher_path || arguments = launcher_path
            return true
    }

    return false
}

MigratePreviousPreferences()
{
    global user_preferences_directory, user_preferences_path
    global previous_user_preferences_path

    if FileExist(user_preferences_path)
        return

    if !FileExist(previous_user_preferences_path)
        return

    DirCreate(user_preferences_directory)
    FileCopy(previous_user_preferences_path, user_preferences_path, false)
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
        "Win Key Overhaul", "YesNo Default2 Icon?"
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
            "Win Key Overhaul", "Icon!"
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
            . "Win Key Overhaul runs without it.`n`n"
            . "Open ScreenGrid's official GitHub releases page? Nothing will be "
            . "downloaded or installed automatically.`n`n"
            . "This recommendation is shown once. The GitHub link remains in the tray menu.",
            "Win Key Overhaul", "YesNo Default2 Icon?"
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
