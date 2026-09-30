#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn

Persistent

startup_shortcut_path := A_Startup "\Shell Folders.lnk"

; =============================================================================
; mission:
; - provide quick access to useful windows shell and hidden folders.
; - keep rarely remembered paths available from the notification area.
; =============================================================================


; =============================================================================
; notification area
; =============================================================================

ConfigureTray()

ConfigureTray()
{
    A_IconTip := "Shell Folders"

    ; use windows' own file explorer icon.
    try TraySetIcon(A_WinDir "\explorer.exe")

    A_TrayMenu.Delete()

    A_TrayMenu.Add("Startup", (*) => Run("shell:startup"))
    A_TrayMenu.Add("SendTo", (*) => Run("shell:sendto"))

    programs_menu := Menu()
    programs_menu.Add("User", (*) => Run("shell:Programs"))
    programs_menu.Add("All Users", (*) => Run("shell:Common Programs"))

    A_TrayMenu.Add("Programs", programs_menu)

    A_TrayMenu.Add()

    appdata_menu := Menu()
    appdata_menu.Add("Roaming", (*) => Run(A_AppData))
    appdata_menu.Add("Local", (*) => Run(EnvGet("LOCALAPPDATA")))
    appdata_menu.Add("LocalLow", (*) => Run(GetLocalLowPath()))

    A_TrayMenu.Add("AppData", appdata_menu)

    A_TrayMenu.Add()

    A_TrayMenu.Add("Temp", (*) => Run(A_Temp))
    A_TrayMenu.Add("Recycle Bin", (*) => Run("explorer.exe shell:RecycleBinFolder"))

    A_TrayMenu.Add()
    A_TrayMenu.Add("Run at startup", ToggleStartup)

    UpdateStartupMenu()
}


; =============================================================================
; startup
; =============================================================================

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

        UpdateStartupMenu()
    }
    catch Error as err {
        MsgBox(
            "Could not update the startup shortcut.`n`n"
            . err.Message,
            "Shell Folders",
            "Iconx"
        )
    }
}


UpdateStartupMenu()
{
    global startup_shortcut_path

    if FileExist(startup_shortcut_path)
        A_TrayMenu.Check("Run at startup")
    else
        A_TrayMenu.Uncheck("Run at startup")
}

; =============================================================================
; helpers
; =============================================================================

GetLocalLowPath()
{
    local_appdata := EnvGet("LOCALAPPDATA")
    return RegExReplace(local_appdata, "\\Local$", "\LocalLow")
}
