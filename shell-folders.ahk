#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn

; =============================================================================
; Shell Folders - on-demand access to Windows shell and hidden folders
; =============================================================================
; - keep existing folder destinations and the default folder-opening association.
; - resolve Local and LocalLow through Windows, including redirected profiles.
; - report launch failures without stopping the tray utility.
; - no polling, background scans or startup-time folder creation.
; =============================================================================

Persistent
startup_shortcut_path := A_Startup "\Shell Folders.lnk"
ConfigureTray()

; =============================================================================
; notification area
; =============================================================================

ConfigureTray()
{
    A_IconTip := "Shell Folders"
    try TraySetIcon(A_WinDir "\explorer.exe")

    A_TrayMenu.Delete()
    A_TrayMenu.Add("Startup", OpenFolder.Bind("shell:startup"))
    A_TrayMenu.Add("SendTo", OpenFolder.Bind("shell:sendto"))

    programs_menu := Menu()
    programs_menu.Add("User", OpenFolder.Bind("shell:Programs"))
    programs_menu.Add("All Users", OpenFolder.Bind("shell:Common Programs"))
    A_TrayMenu.Add("Programs", programs_menu)
    A_TrayMenu.Add()

    appdata_menu := Menu()
    appdata_menu.Add("Roaming", OpenFolder.Bind(A_AppData))
    ; FOLDERID_LocalAppData and FOLDERID_LocalAppDataLow, resolved only on click.
    appdata_menu.Add("Local", OpenFolder.Bind("{F1B32785-6FBA-4FCF-9D55-7B8E7F157091}"))
    appdata_menu.Add("LocalLow", OpenFolder.Bind("{A520A1A4-1780-4FF6-BD18-167343C5AF16}"))
    A_TrayMenu.Add("AppData", appdata_menu)
    A_TrayMenu.Add()

    A_TrayMenu.Add("Temp", OpenFolder.Bind(A_Temp))
    A_TrayMenu.Add("Recycle Bin", OpenFolder.Bind("shell:RecycleBinFolder"))
    A_TrayMenu.Add()
    A_TrayMenu.Add("Run at startup", ToggleStartup)
    A_TrayMenu.Add()
    A_TrayMenu.Add("Reload", (*) => Reload())
    A_TrayMenu.Add("Exit", (*) => ExitApp())
    UpdateStartupMenu()
}

; =============================================================================
; folder resolution and launch
; =============================================================================

OpenFolder(target, *)
{
    try {
        ; GUID targets must be resolved by Windows, not guessed from another
        ; AppData path. Missing optional folders must not prevent script startup.
        if SubStr(target, 1, 1) = "{"
            target := GetKnownFolderPath(target)

        if target = "shell:RecycleBinFolder" {
            ; Keep the existing Explorer-specific handling for this virtual folder.
            Run('"' A_WinDir '\explorer.exe" ' target)
        } else if SubStr(target, 1, 6) = "shell:" {
            Run(target)
        } else {
            if !DirExist(target)
                throw Error("The folder does not exist:`n" target)
            ; Quote physical paths, but retain the user's default folder handler.
            Run('"' target '"')
        }
    }
    catch as failure {
        MsgBox("Could not open the folder.`n`n" failure.Message, "Shell Folders", "Iconx")
    }
}

GetKnownFolderPath(folder_id)
{
    folder_guid := Buffer(16, 0)
    DllCall("ole32\CLSIDFromString", "wstr", folder_id, "ptr", folder_guid, "hresult")

    path_pointer := 0
    try {
        ; Flags 0 requests the current path and does not create a missing folder.
        DllCall("shell32\SHGetKnownFolderPath", "ptr", folder_guid, "uint", 0,
            "ptr", 0, "ptr*", &path_pointer, "hresult")
        if !path_pointer
            throw Error("Windows did not return a path for this known folder.")
        return StrGet(path_pointer, "UTF-16")
    }
    finally {
        ; Windows requires this allocation to be freed even on a failed lookup.
        if path_pointer
            DllCall("ole32\CoTaskMemFree", "ptr", path_pointer)
    }
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
