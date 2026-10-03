; Internal Window Cascade module. Launch ..\window-cascade.ahk instead.
; Included into the same script; functions share the existing global state.

; =============================================================================
; tray menu and settings
; =============================================================================

BuildTrayMenu()
{
    global rotate_key_menu

    A_TrayMenu.Delete()

    A_TrayMenu.Add("How to use", ToggleWindowCascadeHelp)
    A_TrayMenu.Add()
    A_TrayMenu.Add("Pause cascading", ToggleCascading)
    A_TrayMenu.Add("Show focus tabs", ToggleFocusCornerVisibility)
    A_TrayMenu.Add("Check compatibility", CheckCompatibilitySettings)

    rotate_key_menu := Menu()
    rotate_key_menu.Add("Space", SetRotateKey.Bind("Space"))
    rotate_key_menu.Add("Tab", SetRotateKey.Bind("Tab"))
    A_TrayMenu.Add("Rotate layers key", rotate_key_menu)

    A_TrayMenu.Add()
    A_TrayMenu.Add("Run at startup", ToggleStartup)
    A_TrayMenu.Add()
    A_TrayMenu.AddStandard()

    UpdateTrayMenu()
}

SetRotateKey(new_rotate_key, *)
{
    global settings_directory, settings_path, rotate_key

    if new_rotate_key != "Space" && new_rotate_key != "Tab"
        return

    try {
        DirCreate(settings_directory)
        IniWrite(new_rotate_key, settings_path, "Controls", "RotateKey")
    }
    catch Error as err {
        MsgBox(
            "Could not save the Cascade rotate key.`n`n"
            . err.Message,
            "Window Cascade",
            "Iconx"
        )
        return
    }

    rotate_key := new_rotate_key
    UpdateTrayMenu()
}

ToggleCascading(*)
{
    global placement_enabled

    placement_enabled := !placement_enabled
    UpdateTrayMenu()
}

ToggleStartup(*)
{
    global startup_shortcut_path

    try {
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

        UpdateTrayMenu()
    }
    catch Error as err {
        MsgBox(
            "Could not update the startup shortcut.`n`n"
            . err.Message,
            "Window Cascade",
            "Iconx"
        )
    }
}

UpdateTrayMenu()
{
    global placement_enabled, startup_shortcut_path
    global focus_corner_visible
    global rotate_key, rotate_key_menu

    if placement_enabled
        A_TrayMenu.Uncheck("Pause cascading")
    else
        A_TrayMenu.Check("Pause cascading")

    if focus_corner_visible
        A_TrayMenu.Check("Show focus tabs")
    else
        A_TrayMenu.Uncheck("Show focus tabs")

    if IsObject(rotate_key_menu) {
        rotate_key_menu.Uncheck("Space")
        rotate_key_menu.Uncheck("Tab")
        rotate_key_menu.Check(rotate_key)
    }

    if FileExist(startup_shortcut_path)
        A_TrayMenu.Check("Run at startup")
    else
        A_TrayMenu.Uncheck("Run at startup")
}


; =============================================================================
; help
; =============================================================================

ToggleWindowCascadeHelp(*)
{
    static help_gui := 0

    if help_gui {
        try help_gui.Destroy()
        help_gui := 0
        return
    }

    help_gui := Gui("+AlwaysOnTop", "Window Cascade")
    help_gui.SetFont("s10", "Cascadia Mono")

    help_text :=
    (
    "Caps + H             Toggle this help`n"
    "Caps + P             Pause / resume automatic cascading`n"
    "`n"
    "CAPSLOCK LAYER REQUIRED`n"
    "Keep capslock-layer.ahk running with Window Cascade.`n"
    "`n"
    "HINTS`n"
    "Hold Caps + key      Run a command normally`n"
    "Tap Caps, then key   One-shot command for 1.4 seconds (plain keys only)`n"
    "`n"
    "CONTROLS`n"
    "Caps + Up / Down              Swap visible window up / down`n"
    "Caps + Left / Right           Previous / next layer in this slot`n"
    "Caps + PgUp / PgDn            Focus visible window up / down`n"
    "Caps + Insert                 Adopt / re-slot active window`n"
    "Caps + Space / Tab            Next layer`n"
    "Caps + Alt + Space / Tab      Previous layer`n"
    "Caps + M                      Minimize / restore all layers on monitor`n"
    "Caps + F4                     Close current layer`n"
    "Caps + Delete                 Close active window`n"
    "Caps + Home                   Bring this monitor's cascade to front`n"
    "Caps + Alt + M                Minimize / restore cascades on all monitors`n"
    "Caps + Alt + F4               Close all layers on monitor`n"
    "Caps + Alt + F7               Gather other monitors' cascades here`n"
    "Caps + Alt + Left / Right     Move to adjacent monitor + smart sort`n"
    "`n"
    "NOTES`n"
    "Alt commands require held Caps.`n"
    "Space / Tab for layer rotation is selected from the tray menu.`n"
    "Window-management commands are disabled while the active window is maximized or fullscreen.`n"
    "If CapsLock Layer stops, Window Cascade exits after a short reload grace period.`n"
    "`n"
    "FOCUS TABS`n"
    "Click a window's left-edge focus tab to focus that cascade window.`n"
    "Use Show focus tabs in the tray to show or hide them.`n"
    "`n"
    "TRAY`n"
    "Pause cascading      Pause automatic placement`n"
    "Show focus tabs      Show / hide the faint focus tabs`n"
    "Check compatibility  Check conflicting settings"
    )

    help_gui.AddText("w780", help_text)

    help_gui.OnEvent("Close", CloseHelp)
    help_gui.OnEvent("Escape", CloseHelp)
    help_gui.Show()

    CloseHelp(*) {
        try help_gui.Destroy()
        help_gui := 0
    }
}


; =============================================================================
; compatibility checks
; =============================================================================

CheckCompatibilitySettings(*)
{
    try {
        warnings := []

        fancyzones_settings_path :=
            EnvGet("LOCALAPPDATA") "\Microsoft\PowerToys\FancyZones\settings.json"


        if FileExist(fancyzones_settings_path) {
            fancyzones_settings := FileRead(
                fancyzones_settings_path,
                "UTF-8"
            )

            if RegExMatch(
                fancyzones_settings,
                '"fancyzones_appLastZone_moveWindows"\s*:\s*\{\s*"value"\s*:\s*true'
            ) {
                warnings.Push(
                    'FancyZones: "Move newly created windows to the last known zone" '
                    . "is enabled."
                )
            }
        }

        if warnings.Length = 0 {
            return
        }

        message :=
            "This setting may compete with Window Cascade:`n`n"

        for warning in warnings
            message .= "• " warning "`n`n"

        message .= "Window Cascade will not change PowerToys settings automatically."

        MsgBox(message, "Window Cascade", "Icon!")
    }
    catch {
        return
    }
}
