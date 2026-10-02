; Internal Window Hotkeys module. Launch ..\window-hotkeys.ahk instead.
; Included into the same script; functions share the existing global state.

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
    "Caps + Win + H    Toggle this help`n"
    "`n"
    "CAPSLOCK LAYER REQUIRED`n"
    "Keep capslock-layer.ahk running with Window Hotkeys.`n"
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
    "Caps + Win + Arrow    Start / move spatial focus"
    )

    help_text .= (
        "`n"
        "`n"
        "STEAM`n"
        "Caps + G              Cycle running Steam games"
    )

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
            . FormatHelpShortcutLine(
                "Ctrl + Alt + Arrow",
                "Move between FancyZones"
            )
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

FormatHelpShortcutLine(shortcut, description)
{
    padding := ""
    padding_length := Max(4, 24 - StrLen(shortcut))

    Loop padding_length
        padding .= " "

    return shortcut . padding . description
}

; =============================================================================
; startup shortcut
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
