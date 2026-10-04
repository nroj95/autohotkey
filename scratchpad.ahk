#Requires AutoHotkey v2.0 64-bit
#SingleInstance Force
#Warn

; =============================================================================
; Scratchpad - a persistent, keyboard-driven Notepad++ drawer
; =============================================================================
; responsibilities
; - own one dedicated Notepad++ instance, not the user's ordinary editor windows.
; - slide the window down from the active monitor's work-area top, then back up.
; - create timestamped pages in D:\toolbox\scratch and remember the current page.
; - save before hiding or switching; never dismiss a save/overwrite dialog.
; - expose registered commands to capslock-layer.ahk without requiring it to run.
;
; controls supplied by the accompanying CapsLock Layer
;   Caps + B       toggle                 Caps + N       new page
;   Caps + J       previous page          Caps + L       next page
;   tap Caps, then B / N / J / L works too.
;
; while the scratch editor has focus
;   Escape         hide (completion/calltip popups get Escape first)
;   Ctrl + N       new page
;   Ctrl + PgUp    previous page          Ctrl + PgDn    next page
;
; configuration and lifecycle
; - settings: %LOCALAPPDATA%\Scratchpad\settings.ini (created on first run).
; - Notepad++ profile: %LOCALAPPDATA%\Scratchpad\Notepad++.
; - the tray menu can enable standalone F12 and optional Windows startup.
; - CapsLock Layer can launch this companion on demand; startup is not required.
; - exiting this script reveals the editor instead of killing its process.
;
; design boundaries
; - page switches close the old tab: undo history does not survive page switches.
; - caret, scroll and selected built-in language are remembered in memory.
; - rename an OPEN page through Notepad++ File > Rename, not Explorer.
; - pages are local plaintext, not encrypted notes or a versioned backup system.
; =============================================================================

Persistent
DetectHiddenWindows True
SetTitleMatchMode 2
SetWinDelay -1
SetControlDelay -1

A_IconTip := "Scratchpad"
try TraySetIcon(A_ScriptDir "\icons\scratchpad.ico")

try scratchpad := ScratchpadController()
catch as startup_failure {
    MsgBox startup_failure.Message, "Scratchpad startup", "Iconx"
    ExitApp
}

#HotIf ScratchpadEditorFocused()

$Esc::
{
    scratchpad.HandleEscape()
    KeyWait "Escape"
}

$^n::
{
    scratchpad.QueueCommand("new")
    KeyWait "n"
}

$^PgUp::
{
    scratchpad.QueueCommand("previous")
    KeyWait "PgUp"
}

$^PgDn::
{
    scratchpad.QueueCommand("next")
    KeyWait "PgDn"
}

#HotIf IsSet(scratchpad) && scratchpad.enable_f12

$F12::
{
    scratchpad.QueueCommand("toggle")
    KeyWait "F12"
}

#HotIf

ScratchpadEditorFocused()
{
    global scratchpad

    if !IsSet(scratchpad) || !scratchpad.HasWindow()
        return false
    if !WinActive("ahk_id " scratchpad.window_hwnd)
        return false

    ; An editor may keep keyboard focus while a native menu is open.
    thread_info := Buffer(72, 0) ; GUITHREADINFO, 64-bit
    NumPut("uint", thread_info.Size, thread_info)
    if DllCall("GetGUIThreadInfo", "uint", 0, "ptr", thread_info, "int")
        && (NumGet(thread_info, 4, "uint") & 0x1E)
        return false

    ; Find/Replace dialogs and other controls retain their normal keys.
    try return InStr(ControlGetFocus("ahk_id " scratchpad.window_hwnd), "Scintilla") = 1
    catch
        return false
}


class ScratchpadController
{
    ; =========================================================================
    ; startup, configuration and command routing
    ; =========================================================================

    __New()
    {
        this.window_hwnd := 0
        this.bridge := 0
        this.busy := false
        this.autosave_paused := false
        this.command_queue := []
        this.page_views := Map()
        this.page_views.CaseSense := "Off"
        this.current_path := ""
        this.disk_stamp := ""
        this.persisted_path := ""
        this.persisted_stamp := ""
        this.previous_window := 0
        this.last_bounds := 0
        this.window_marker := "nroj.Scratchpad.NotepadWindow"
        this.cascade_ignore_marker := "nroj.WindowCascade.Ignore"
        this.controller_title := "nroj.Scratchpad.Controller"
        this.data_directory := EnvGet("LOCALAPPDATA") "\Scratchpad"
        this.settings_path := this.data_directory "\settings.ini"
        this.state_path := this.data_directory "\state.ini"
        this.profile_directory := this.data_directory "\Notepad++"
        this.startup_shortcut := A_Startup "\Scratchpad.lnk"
        this.mutex_handle := 0

        ; The named mutex also protects against running differently named copies.
        this.mutex_handle := DllCall("CreateMutexW", "ptr", 0, "int", false,
            "str", "Local\nroj.Scratchpad.Controller", "ptr")
        mutex_error := A_LastError
        if !this.mutex_handle
            throw OSError(mutex_error, "CreateMutexW")
        if mutex_error = 183 {
            DllCall("CloseHandle", "ptr", this.mutex_handle)
            this.mutex_handle := 0
            MsgBox "Scratchpad is already running. Use its tray menu to exit before running another copy.",
                "Scratchpad", "Iconi"
            ExitApp
        }

        DirCreate this.data_directory
        DirCreate this.profile_directory
        this.CreateEditorProfile()
        this.CreateDefaultSettings()
        this.scratch_directory := RTrim(IniRead(this.settings_path, "Paths",
            "ScratchDirectory", "D:\toolbox\scratch"), "\/")
        if !RegExMatch(this.scratch_directory, "i)^(?:[a-z]:\\|\\\\)")
            throw Error("ScratchDirectory must be an absolute Windows path.")
        DirCreate this.scratch_directory

        this.width_percent := this.ReadNumber("Window", "WidthPercent", 75, 30, 100)
        this.height_percent := this.ReadNumber("Window", "HeightPercent", 60, 20, 100)
        this.animation_ms := this.ReadNumber("Window", "AnimationDurationMs", 180, 0, 1000)
        this.always_on_top := this.ReadNumber("Window", "AlwaysOnTop", 1, 0, 1)
        this.autosave_ms := this.ReadNumber("Saving", "AutosaveIntervalMs", 2000, 500, 60000)
        this.enable_f12 := this.ReadNumber("Controls", "EnableF12", 0, 0, 1)
        this.allowed_extensions := "|md|txt|ps1|psm1|psd1|py|pyw|ahk|lua|js|ts|jsx|tsx|"
            . "json|jsonc|yaml|yml|xml|html|htm|css|scss|ini|cfg|conf|toml|log|"
            . "sh|bash|bat|cmd|sql|c|cpp|h|hpp|cs|rs|go|java|rb|php|csv|tsv|"

        this.process_commands_callback := ObjBindMethod(this, "ProcessCommands")
        this.autosave_callback := ObjBindMethod(this, "Autosave")
        this.exit_callback := ObjBindMethod(this, "OnScriptExit")
        OnExit this.exit_callback
        this.BuildTrayMenu()

        ; Register before exposing the ready window, so the first command is safe.
        this.message_callbacks := []
        for command, message_name in Map(
            "toggle", "nroj.Scratchpad.Toggle",
            "new", "nroj.Scratchpad.New",
            "previous", "nroj.Scratchpad.Previous",
            "next", "nroj.Scratchpad.Next"
        ) {
            message_id := DllCall("RegisterWindowMessageW", "str", message_name, "uint")
            if !message_id
                throw OSError(A_LastError, "RegisterWindowMessageW")
            callback := ObjBindMethod(this, "ReceiveCommand", command)
            this.message_callbacks.Push(callback)
            OnMessage message_id, callback
        }
        this.controller_window := Gui("+ToolWindow", "nroj.Scratchpad.Starting")
        this.controller_window.Title := this.controller_title
        SetTimer this.autosave_callback, this.autosave_ms
    }

    CreateEditorProfile()
    {
        profile_path := this.profile_directory "\config.xml"
        if FileExist(profile_path)
            return
        ; Only seed the dedicated profile. Disabling session snapshots makes a
        ; native editor close use its normal save prompt, not an unsaved session.
        profile := '<?xml version="1.0" encoding="UTF-8"?>`n'
            . '<NotepadPlus><GUIConfigs>`n'
            . '<GUIConfig name="RememberLastSession">no</GUIConfig>`n'
            . '<GUIConfig name="Backup" action="0" useCustumDir="no" dir=""'
            . ' isSnapshotMode="no" snapshotBackupTiming="7000" />`n'
            . '<GUIConfig name="NewDocDefaultSettings" format="2" encoding="4"'
            . ' lang="0" codepage="-1" openAnsiAsUTF8="yes" />`n'
            . '</GUIConfigs></NotepadPlus>`n'
        FileAppend profile, profile_path, "UTF-8-RAW"
    }

    CreateDefaultSettings()
    {
        if FileExist(this.settings_path)
            return
        settings := "[Paths]`nScratchDirectory=D:\toolbox\scratch`nNotepadExecutable=`n"
            . "`n[Window]`nWidthPercent=75`nHeightPercent=60`nAnimationDurationMs=180`nAlwaysOnTop=1`n"
            . "`n[Saving]`nAutosaveIntervalMs=2000`n"
            . "`n[Controls]`nEnableF12=0`n"
        FileAppend settings, this.settings_path, "UTF-16"
    }

    ReadNumber(section, key, fallback, minimum, maximum)
    {
        value := IniRead(this.settings_path, section, key, fallback)
        if !IsNumber(value)
            return fallback
        return Min(maximum, Max(minimum, Round(value)))
    }

    ReceiveCommand(command, w_param, l_param, message, receiving_hwnd)
    {
        ; Broadcasts also reach the script's own window: handle each command once.
        if receiving_hwnd = this.controller_window.Hwnd
            this.QueueCommand(command)
    }

    QueueCommand(command, *)
    {
        if this.command_queue.Length >= 8
            return
        this.command_queue.Push({name: command, source_window: WinExist("A")})
        SetTimer this.process_commands_callback, -1
    }

    ProcessCommands(*)
    {
        if this.busy
            return
        this.busy := true
        previous_dpi_context := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
        try {
            while this.command_queue.Length {
                request := this.command_queue.RemoveAt(1)
                try this.ExecuteCommand(request)
                catch as failure {
                    this.command_queue := []
                    this.autosave_paused := true
                    this.RevealAfterError(request.source_window)
                    MsgBox failure.Message, "Scratchpad", "Iconx 4096"
                }
            }
        }
        finally {
            if previous_dpi_context
                DllCall("SetThreadDpiAwarenessContext", "ptr", previous_dpi_context, "ptr")
            this.busy := false
            if this.command_queue.Length
                SetTimer this.process_commands_callback, -1
        }
    }

    ExecuteCommand(request)
    {
        if request.name = "hide" {
            if this.HasWindow() && this.IsVisible()
                this.HideWindow()
            return
        }

        initial_page_was_created := this.EnsureWindow(request.source_window)
        if request.name = "toggle" && this.IsVisible() {
            this.HideWindow()
            return
        }

        this.ShowWindow(request.source_window)
        switch request.name {
            case "new":
                ; An empty folder already received its first page during launch.
                if !initial_page_was_created {
                    this.SaveCurrentPage()
                    this.SwitchPage(this.CreatePage(), true)
                }
            case "previous", "next":
                this.SaveCurrentPage()
                pages := this.ListPages()
                if !pages.Length
                    throw Error("No supported scratch files remain in the scratch directory.")
                current_index := 0
                for index, path in pages {
                    if path = this.current_path {
                        current_index := index
                        break
                    }
                }
                if !current_index
                    throw Error("The current page is no longer in the scratch folder. Resolve its rename or move in Notepad++ first.")
                direction := request.name = "next" ? 1 : -1
                next_index := Mod(current_index - 1 + direction + pages.Length, pages.Length) + 1
                this.SwitchPage(pages[next_index])
        }
    }


    ; =========================================================================
    ; editor ownership and startup
    ; =========================================================================

    HasWindow()
    {
        return this.window_hwnd
            && DllCall("IsWindow", "ptr", this.window_hwnd, "int")
            && DllCall("GetPropW", "ptr", this.window_hwnd, "str", this.window_marker, "ptr")
    }

    IsVisible()
    {
        return this.HasWindow()
            && DllCall("IsWindowVisible", "ptr", this.window_hwnd, "int")
            && !DllCall("IsIconic", "ptr", this.window_hwnd, "int")
    }

    EnsureWindow(source_window)
    {
        if this.HasWindow() {
            if !this.bridge || this.bridge.tainted
                this.ConnectBridge()
            return false
        }

        this.window_hwnd := 0
        this.bridge := 0
        ; A window property survives script reloads without adopting normal windows.
        for candidate in WinGetList("ahk_class Notepad++") {
            if DllCall("GetPropW", "ptr", candidate, "str", this.window_marker, "ptr") {
                this.window_hwnd := candidate
                if !DllCall("SetPropW", "ptr", candidate, "str", this.cascade_ignore_marker, "ptr", 1, "int")
                    throw OSError(A_LastError, "SetPropW")
                this.ConnectBridge()
                path := this.bridge.GetCurrentPath()
                saved_path := IniRead(this.state_path, "CurrentPage", "Path", "")
                if path = saved_path {
                    this.current_path := path
                    this.disk_stamp := IniRead(this.state_path, "CurrentPage", "DiskStamp", "")
                }
                return false
            }
        }

        notepad_executable := this.FindNotepadExecutable()
        if notepad_executable = ""
            throw Error("Notepad++ was not selected. Run the scratchpad command again when its executable is available.")

        initial_path := IniRead(this.state_path, "CurrentPage", "Path", "")
        new_page := false
        if !this.IsScratchPath(initial_path) || !FileExist(initial_path) {
            pages := this.ListPages()
            if pages.Length
                initial_path := pages[pages.Length]
            else {
                initial_path := this.CreatePage()
                new_page := true
            }
        }

        ; A separate profile prevents session/settings writes to ordinary Notepad++.
        ; Tray startup avoids showing the editor before the drawer is positioned.
        command_line := '"' notepad_executable '" -multiInst -nosession -noPlugin'
            . ' -notabbar -systemtray -settingsDir="' this.profile_directory '"'
            . ' -titleAdd="scratchpad" "' initial_path '"'
        Run command_line, this.scratch_directory, "Hide", &notepad_pid
        candidate := WinWait("ahk_class Notepad++ ahk_pid " notepad_pid, , 12)
        if !candidate
            throw Error("Notepad++ did not create its scratch window. Check for a startup/error dialog, then try again.")

        this.window_hwnd := candidate
        if !DllCall("SetPropW", "ptr", candidate, "str", this.window_marker, "ptr", 1, "int")
            throw OSError(A_LastError, "SetPropW")
        if !DllCall("SetPropW", "ptr", candidate, "str", this.cascade_ignore_marker, "ptr", 1, "int")
            throw OSError(A_LastError, "SetPropW")
        this.current_path := ""
        this.disk_stamp := ""
        this.ConnectBridge()
        if this.bridge.GetCurrentPath() != initial_path
            throw Error("Notepad++ did not open the requested scratch page. No existing tabs were closed.")
        this.bridge.Send(2094, 0, true) ; NPPM_HIDETOOLBAR
        this.AcceptCurrentPath(initial_path)
        if new_page
            this.ConfigureNewPage()
        this.last_bounds := this.GetBounds(source_window)
        return new_page
    }

    ConnectBridge()
    {
        this.bridge := 0
        this.bridge := NotepadBridge(this.window_hwnd)
        if !this.bridge.Send(2074) ; NPPM_GETNPPVERSION
            throw Error("The dedicated Notepad++ window is not ready. Try the command again.")
    }

    FindNotepadExecutable()
    {
        configured := IniRead(this.settings_path, "Paths", "NotepadExecutable", "")
        if configured != "" {
            if FileExist(configured)
                return configured
            throw Error("NotepadExecutable does not exist:`n" configured
                . "`n`nCorrect the path in the scratchpad settings.ini, then reload the script.")
        }

        candidates := []
        for root in ["HKCU", "HKLM"] {
            try candidates.Push(RegRead(root "\Software\Microsoft\Windows\CurrentVersion\App Paths\notepad++.exe"))
        }
        for variable in ["ProgramW6432", "ProgramFiles", "ProgramFiles(x86)"] {
            directory := EnvGet(variable)
            if directory != ""
                candidates.Push(directory "\Notepad++\notepad++.exe")
        }
        for candidate in WinGetList("ahk_exe notepad++.exe") {
            try candidates.Push(WinGetProcessPath("ahk_id " candidate))
        }
        for candidate in candidates {
            if FileExist(candidate)
                return candidate
        }

        selected := FileSelect(1, , "Locate notepad++.exe (installed or portable)", "Notepad++ (notepad++.exe)")
        if selected != "" {
            SplitPath selected, &file_name
            if file_name != "notepad++.exe"
                throw Error("Select notepad++.exe, not the installer or a shortcut.")
            IniWrite selected, this.settings_path, "Paths", "NotepadExecutable"
        }
        return selected
    }


    ; =========================================================================
    ; persistent pages and checked saves
    ; =========================================================================

    IsScratchPath(path)
    {
        if path = ""
            return false
        SplitPath path, , &parent_directory, &extension
        return RTrim(parent_directory, "\/") = this.scratch_directory
            && InStr(this.allowed_extensions, "|" StrLower(extension) "|")
    }

    ListPages()
    {
        sortable_pages := ""
        Loop Files this.scratch_directory "\*", "F" {
            if this.IsScratchPath(A_LoopFileFullPath)
                sortable_pages .= A_LoopFileTimeCreated "`t" A_LoopFileName "`n"
        }
        pages := []
        ; Creation time is stable when a page is renamed; names break time ties.
        Loop Parse Sort(sortable_pages), "`n", "`r" {
            if A_LoopField != ""
                pages.Push(this.scratch_directory "\" SubStr(A_LoopField, 16))
        }
        return pages
    }

    CreatePage()
    {
        base_name := "scratch-" FormatTime(, "yyyyMMdd-HHmmss")
        loop {
            suffix := A_Index = 1 ? "" : "-" Format("{:02}", A_Index)
            path := this.scratch_directory "\" base_name suffix ".md"
            ; CREATE_NEW is atomic: even rapid presses cannot overwrite a page.
            file_handle := DllCall("CreateFileW", "str", path, "uint", 0x40000000,
                "uint", 7, "ptr", 0, "uint", 1, "uint", 0x80, "ptr", 0, "ptr")
            if file_handle != -1 {
                DllCall("CloseHandle", "ptr", file_handle)
                return path
            }
            file_error := A_LastError
            if file_error != 80 && file_error != 183
                throw OSError(file_error, "CreateFileW", path)
        }
    }

    EnsureSingleScratchPage()
    {
        if !DllCall("IsWindowEnabled", "ptr", this.window_hwnd, "int")
            throw Error("Finish or cancel the open Notepad++ dialog before using a scratchpad command.")
        if this.bridge.OpenBufferCount() != 1 {
            this.bridge.Send(2075, 0, false) ; NPPM_HIDETABBAR
            throw Error("The scratch window contains extra tabs. Close those tabs manually first; the scratchpad will not close or save unrelated documents.")
        }
        path := this.bridge.GetCurrentPath()
        if !this.IsScratchPath(path)
            throw Error("The current tab is not a supported file directly inside:`n"
                . this.scratch_directory "`n`nReturn to a scratch page before switching or hiding.")
        if !FileExist(path)
            throw Error("The open page was renamed, moved or deleted outside Notepad++:`n" path
                . "`n`nResolve it in Notepad++ first. The scratchpad will not recreate the old name automatically.")
        if path != this.current_path {
            if this.current_path != "" && this.page_views.Has(this.current_path)
                this.page_views[path] := this.page_views[this.current_path]
            this.AcceptCurrentPath(path)
        }
        return path
    }

    AcceptCurrentPath(path)
    {
        this.current_path := path
        this.disk_stamp := ScratchpadFileStamp(path)
        this.PersistCurrentState()
    }

    PersistCurrentState()
    {
        if this.current_path = this.persisted_path && this.disk_stamp = this.persisted_stamp
            return
        IniWrite "Path=" this.current_path "`nDiskStamp=" this.disk_stamp,
            this.state_path, "CurrentPage"
        this.persisted_path := this.current_path
        this.persisted_stamp := this.disk_stamp
    }

    SaveCurrentPage()
    {
        path := this.EnsureSingleScratchPage()
        current_disk_stamp := ScratchpadFileStamp(path)
        dirty := this.bridge.IsDirty()

        if this.disk_stamp != "" && current_disk_stamp != this.disk_stamp {
            if dirty
                throw Error("The file changed on disk while this editor also has unsaved changes.`n`n"
                    . "Use File > Save As to preserve the editor version under a new scratch name,"
                    . " or File > Reload from Disk to keep the disk version. No automatic overwrite was attempted.")
            ; Ctrl+S and Notepad++'s own reload can also change the disk stamp.
            ; Avoid a redundant reload (and lost undo) when text already matches.
            if !this.EditorMatchesDisk(path) {
                this.RememberPageView(path)
                if !this.bridge.PathMessage(2060, path) ; NPPM_RELOADFILE
                    throw Error("The externally changed page could not be reloaded.")
                this.RestorePageView(path)
            }
            this.disk_stamp := ScratchpadFileStamp(path)
        }

        if this.bridge.IsDirty() {
            if !this.bridge.Send(2062) || this.bridge.IsDirty() ; NPPM_SAVECURRENTFILE
                throw Error("Notepad++ could not save the current page. The page will stay open. Check its save dialog, file permissions or disk space.")
            if !FileExist(path)
                throw Error("The save could not be verified on disk. The page will stay open.")
            this.disk_stamp := ScratchpadFileStamp(path)
        }
        this.autosave_paused := false
        A_IconTip := "Scratchpad"
        this.bridge.Send(2075, 0, true) ; Hide the tab bar again after recovery.
        this.PersistCurrentState()
    }

    EditorMatchesDisk(path)
    {
        ; Notepad++ represents Unicode documents as UTF-8 in Scintilla.
        buffer_id := this.bridge.Send(2084)
        encoding := this.bridge.Send(2090, buffer_id) ; NPPM_GETBUFFERENCODING
        if encoding = 1 || encoding = 4 || encoding = 5
            disk_text := FileRead(path, "UTF-8")
        else if encoding = 3
            disk_text := FileRead(path, "UTF-16")
        else
            return false
        return disk_text == this.bridge.DocumentText()
    }

    ConfigureNewPage()
    {
        ; Only new scratch pages are normalized; existing files keep their format.
        this.bridge.MenuCommand(45010) ; IDM_FORMAT_CONV2_AS_UTF_8 (without BOM)
        this.bridge.MenuCommand(45002) ; IDM_FORMAT_TOUNIX
        this.bridge.Scintilla(2031, 2) ; SCI_SETEOLMODE / SC_EOL_LF
        this.SaveCurrentPage()
    }

    SwitchPage(next_path, new_page := false)
    {
        if next_path = this.current_path
            return
        this.SaveCurrentPage()
        old_path := this.current_path
        old_buffer_id := this.bridge.Send(2084) ; NPPM_GETCURRENTBUFFERID
        this.RememberPageView(old_path)

        ; Open the destination first. If opening fails, the old page is untouched.
        if !this.bridge.PathMessage(2101, next_path) ; NPPM_DOOPEN
            throw Error("Notepad++ could not open:`n" next_path)
        if this.bridge.GetCurrentPath() != next_path
            throw Error("Notepad++ did not activate the requested page. No tabs were closed.")
        new_buffer_id := this.bridge.Send(2084)

        old_position := this.bridge.Send(2081, old_buffer_id, 0) ; NPPM_GETPOSFROMBUFFERID
        if old_position = 0xFFFFFFFF || old_position < 0
            throw Error("The previous tab could not be located. No tabs were closed.")
        old_view := old_position >> 30
        old_index := old_position & 0x3FFFFFFF
        this.bridge.Send(2052, old_view, old_index) ; NPPM_ACTIVATEDOC
        if this.bridge.Send(2084) != old_buffer_id
            throw Error("The previous tab could not be identified safely. No tabs were closed.")
        if this.bridge.IsDirty()
            throw Error("The previous page changed during switching. Both tabs have been kept open.")
        this.bridge.MenuCommand(41003) ; IDM_FILE_CLOSE -- never Close All.

        if this.bridge.OpenBufferCount() != 1
            throw Error("The old tab was not closed. Resolve any Notepad++ dialog; both pages have been kept.")
        if this.bridge.Send(2084) != new_buffer_id
            throw Error("The new page was not retained as expected. Inspect the open tab before continuing.")
        this.AcceptCurrentPath(next_path)
        if new_page
            this.ConfigureNewPage()
        else
            this.RestorePageView(next_path)
        this.FocusEditor()
    }

    RememberPageView(path)
    {
        this.page_views[path] := {
            caret: this.bridge.Scintilla(2008),     ; SCI_GETCURRENTPOS
            anchor: this.bridge.Scintilla(2009),    ; SCI_GETANCHOR
            first_line: this.bridge.Scintilla(2152),
            horizontal_scroll: this.bridge.Scintilla(2398),
            language: this.bridge.ReadInteger(2029) ; NPPM_GETCURRENTLANGTYPE
        }
    }

    RestorePageView(path)
    {
        if !this.page_views.Has(path)
            return
        view := this.page_views[path]
        length := this.bridge.Scintilla(2006) ; SCI_GETLENGTH
        this.bridge.Send(2030, 0, view.language) ; NPPM_SETCURRENTLANGTYPE
        this.bridge.Scintilla(2160, Min(length, view.anchor), Min(length, view.caret)) ; SCI_SETSEL
        this.bridge.Scintilla(2613, view.first_line) ; SCI_SETFIRSTVISIBLELINE
        this.bridge.Scintilla(2397, view.horizontal_scroll) ; SCI_SETXOFFSET
    }

    Autosave(*)
    {
        if this.busy || this.autosave_paused || !this.IsVisible()
            return
        if !DllCall("IsWindowEnabled", "ptr", this.window_hwnd, "int")
            return
        this.busy := true
        try {
            if !this.bridge || this.bridge.tainted
                this.ConnectBridge()
            this.SaveCurrentPage()
        }
        catch as failure {
            this.autosave_paused := true
            A_IconTip := "Scratchpad - autosave paused"
            TrayTip failure.Message, "Scratchpad - autosave paused", 2
        }
        finally {
            this.busy := false
            if this.command_queue.Length
                SetTimer this.process_commands_callback, -1
        }
    }


    ; =========================================================================
    ; monitor placement, focus and animation
    ; =========================================================================

    GetBounds(source_window)
    {
        if !source_window || !DllCall("IsWindow", "ptr", source_window, "int") {
            MouseGetPos , , &source_window
            if !source_window
                source_window := DllCall("GetDesktopWindow", "ptr")
        }
        monitor := DllCall("MonitorFromWindow", "ptr", source_window, "uint", 2, "ptr")
        monitor_info := Buffer(40, 0)
        NumPut("uint", 40, monitor_info)
        if !DllCall("GetMonitorInfoW", "ptr", monitor, "ptr", monitor_info, "int")
            throw OSError(A_LastError, "GetMonitorInfoW")
        left := NumGet(monitor_info, 20, "int")
        top := NumGet(monitor_info, 24, "int")
        work_width := NumGet(monitor_info, 28, "int") - left
        work_height := NumGet(monitor_info, 32, "int") - top
        width := Min(work_width, Max(320, Round(work_width * this.width_percent / 100)))
        height := Min(work_height, Max(180, Round(work_height * this.height_percent / 100)))
        return {x: left + Round((work_width - width) / 2), y: top, w: width, h: height}
    }

    ShowWindow(source_window, animate := true)
    {
        if this.IsVisible() {
            this.FocusEditor()
            return
        }
        if source_window && source_window != this.window_hwnd
            this.previous_window := source_window
        this.last_bounds := this.GetBounds(source_window)
        bounds := this.last_bounds

        ; Start with an empty region so restoring a minimized window cannot flash.
        this.SetClip(1, 1, 1)
        if WinGetMinMax("ahk_id " this.window_hwnd) != 0
            WinRestore "ahk_id " this.window_hwnd
        WinHide "ahk_id " this.window_hwnd
        WinMove bounds.x, bounds.y, bounds.w, bounds.h, "ahk_id " this.window_hwnd
        ; Some window styles impose a minimum size; animate the actual dimensions.
        WinGetPos , , &actual_width, &actual_height, "ahk_id " this.window_hwnd
        bounds.w := actual_width
        bounds.h := actual_height
        WinSetAlwaysOnTop this.always_on_top, "ahk_id " this.window_hwnd
        this.AnimateWindow(true, bounds, animate)
        this.FocusEditor()
    }

    HideWindow()
    {
        if !this.bridge || this.bridge.tainted
            this.ConnectBridge()
        this.SaveCurrentPage()
        was_active := !!WinActive("ahk_id " this.window_hwnd)
        bounds := this.GetBounds(this.window_hwnd)
        WinGetPos &window_x, &window_y, &window_width, &window_height, "ahk_id " this.window_hwnd
        bounds.x := window_x
        bounds.w := window_width
        bounds.h := window_height
        bounds.start_y := window_y
        this.last_bounds := bounds
        this.AnimateWindow(false, bounds)
        if was_active && this.previous_window
            && DllCall("IsWindowVisible", "ptr", this.previous_window, "int")
            && !DllCall("IsIconic", "ptr", this.previous_window, "int")
        {
            try WinActivate "ahk_id " this.previous_window
        }
    }

    AnimateWindow(showing, bounds, animate := true)
    {
        duration := animate ? this.animation_ms : 0
        animation_setting := Buffer(4, 0)
        if DllCall("SystemParametersInfoW", "uint", 0x1042, "uint", 0,
            "ptr", animation_setting, "uint", 0, "int") && !NumGet(animation_setting, 0, "int")
            duration := 0

        start_y := showing ? bounds.y - bounds.h : bounds.start_y
        end_y := showing ? bounds.y : bounds.y - bounds.h
        try {
            if showing {
                this.PlaceAnimationFrame(bounds, start_y)
                DllCall("ShowWindow", "ptr", this.window_hwnd, "int", 4) ; SW_SHOWNOACTIVATE
            }
            started := ScratchpadClockMs()
            loop {
                progress := duration ? Min(1, (ScratchpadClockMs() - started) / duration) : 1
                eased := 1 - (1 - progress) ** 3
                current_y := Round(start_y + (end_y - start_y) * eased)
                this.PlaceAnimationFrame(bounds, current_y)
                if progress >= 1
                    break
                ; Frame pacing follows desktop composition, without a permanent
                ; high-resolution timer request or a CPU-spinning wait loop.
                frame_wait_started := ScratchpadClockMs()
                if DllCall("dwmapi\DwmFlush", "int") != 0
                    Sleep 8
                else if ScratchpadClockMs() - frame_wait_started < 1
                    Sleep 1
                Sleep -1
            }
            if !showing
                WinHide "ahk_id " this.window_hwnd
        }
        finally {
            ; Never strand a live editor partly clipped after an animation error.
            DllCall("SetWindowRgn", "ptr", this.window_hwnd, "ptr", 0, "int", true)
            WinMove bounds.x, bounds.y, bounds.w, bounds.h, "ahk_id " this.window_hwnd
        }
    }

    PlaceAnimationFrame(bounds, current_y)
    {
        ; Clip at the chosen work-area top: no spill onto a monitor above it.
        clip_top := Min(bounds.h, Max(0, bounds.y - current_y))
        this.SetClip(bounds.w, bounds.h, clip_top)
        if !DllCall("SetWindowPos", "ptr", this.window_hwnd, "ptr", 0,
            "int", bounds.x, "int", current_y, "int", 0, "int", 0,
            "uint", 0x215, "int") ; NOSIZE | NOZORDER | NOACTIVATE | NOOWNERZORDER
            throw OSError(A_LastError, "SetWindowPos")
    }

    SetClip(width, height, top)
    {
        region := DllCall("gdi32\CreateRectRgn", "int", 0, "int", top,
            "int", width, "int", height, "ptr")
        if !region
            throw OSError(A_LastError, "CreateRectRgn")
        if !DllCall("SetWindowRgn", "ptr", this.window_hwnd, "ptr", region, "int", true, "int") {
            DllCall("gdi32\DeleteObject", "ptr", region)
            throw OSError(A_LastError, "SetWindowRgn")
        }
        ; Windows owns the region after success; deleting it here would be wrong.
    }

    FocusEditor()
    {
        popup := DllCall("GetLastActivePopup", "ptr", this.window_hwnd, "ptr")
        if popup && popup != this.window_hwnd
            && DllCall("IsWindowVisible", "ptr", popup, "int")
        {
            WinActivate "ahk_id " popup
            return
        }
        WinActivate "ahk_id " this.window_hwnd
        if this.bridge && !this.bridge.tainted {
            try ControlFocus this.bridge.ScintillaHwnd(), "ahk_id " this.window_hwnd
        }
    }

    HandleEscape()
    {
        if this.busy
            return
        this.busy := true
        pass_escape := true
        try pass_escape := this.bridge.Scintilla(2102) || this.bridge.Scintilla(2202)
        catch {
            ; Preserve native Escape if the editor state cannot be inspected.
            pass_escape := true
        }
        finally {
            this.busy := false
            if this.command_queue.Length
                SetTimer this.process_commands_callback, -1
        }
        if pass_escape
            Send "{Escape}" ; Completion/calltip gets Escape before the drawer.
        else
            this.QueueCommand("hide")
    }

    RevealAfterError(source_window)
    {
        if !this.HasWindow()
            return
        try {
            DllCall("SetWindowRgn", "ptr", this.window_hwnd, "ptr", 0, "int", true)
            bounds := this.GetBounds(source_window)
            if WinGetMinMax("ahk_id " this.window_hwnd) != 0
                WinRestore "ahk_id " this.window_hwnd
            WinMove bounds.x, bounds.y, bounds.w, bounds.h, "ahk_id " this.window_hwnd
            WinShow "ahk_id " this.window_hwnd
            this.FocusEditor()
            if this.bridge && !this.bridge.tainted && this.bridge.OpenBufferCount() != 1
                this.bridge.Send(2075, 0, false)
        }
    }


    ; =========================================================================
    ; tray menu and shutdown
    ; =========================================================================

    BuildTrayMenu()
    {
        A_TrayMenu.Delete()
        A_TrayMenu.Add("Toggle scratchpad", ObjBindMethod(this, "QueueCommand", "toggle"))
        A_TrayMenu.Default := "Toggle scratchpad"
        A_TrayMenu.Add("New page", ObjBindMethod(this, "QueueCommand", "new"))
        A_TrayMenu.Add("Previous page", ObjBindMethod(this, "QueueCommand", "previous"))
        A_TrayMenu.Add("Next page", ObjBindMethod(this, "QueueCommand", "next"))
        A_TrayMenu.Add()
        A_TrayMenu.Add("Open scratch folder", (*) => Run('explorer.exe "' this.scratch_directory '"'))
        A_TrayMenu.Add("Open settings", (*) => Run('notepad.exe "' this.settings_path '"'))
        A_TrayMenu.Add("How to use", ObjBindMethod(this, "ShowHelp"))
        A_TrayMenu.Add()
        A_TrayMenu.Add("Enable standalone F12", ObjBindMethod(this, "ToggleF12"))
        A_TrayMenu.Add("Run at startup", ObjBindMethod(this, "ToggleStartup"))
        A_TrayMenu.Add()
        A_TrayMenu.Add("Reload", (*) => Reload())
        A_TrayMenu.Add("Exit (keep editor open)", (*) => ExitApp())
        this.UpdateTrayChecks()
    }

    ToggleF12(*)
    {
        this.enable_f12 := !this.enable_f12
        IniWrite this.enable_f12, this.settings_path, "Controls", "EnableF12"
        this.UpdateTrayChecks()
    }

    ToggleStartup(*)
    {
        if FileExist(this.startup_shortcut)
            FileDelete this.startup_shortcut
        else if A_IsCompiled
            FileCreateShortcut A_ScriptFullPath, this.startup_shortcut, A_ScriptDir
        else
            FileCreateShortcut A_AhkPath, this.startup_shortcut, A_ScriptDir, '"' A_ScriptFullPath '"'
        this.UpdateTrayChecks()
    }

    UpdateTrayChecks()
    {
        if this.enable_f12
            A_TrayMenu.Check("Enable standalone F12")
        else
            A_TrayMenu.Uncheck("Enable standalone F12")
        if FileExist(this.startup_shortcut)
            A_TrayMenu.Check("Run at startup")
        else
            A_TrayMenu.Uncheck("Run at startup")
    }

    ShowHelp(*)
    {
        static help_gui := 0
        static help_icons := []

        if help_gui {
            CloseHelp()
            return
        }

        help_gui := Gui("+AlwaysOnTop", "Scratchpad")
        help_icons := SetScratchpadHelpIcons(help_gui)
        help_gui.SetFont("s10", "Cascadia Mono")

        help_text :=
        (
        "SHORTCUTS`n"
        "Caps + B                Toggle scratchpad`n"
        "Caps + N                New page`n"
        "Caps + J / L            Previous / next page`n"
        "Tap Caps, then key      One-shot command`n"
        "`n"
        "INSIDE THE EDITOR`n"
        "Escape                  Hide scratchpad`n"
        "Ctrl + N                New page`n"
        "Ctrl + PgUp / PgDn      Previous / next page`n"
        "`n"
        "PAGES`n"
        "New pages are named automatically.`n"
        "Pages persist across Windows restarts.`n"
        "The last used page reopens on startup.`n"
        "Rename an open page through Notepad++ File > Rename.`n"
        "`n"
        "SAVING`n"
        "Visible pages are autosaved every two seconds.`n"
        "Pages are also saved before hiding or switching.`n"
        "Undo history survives hiding, but not switching pages.`n"
        "`n"
        "WINDOW`n"
        "F12 is optional and disabled by default.`n"
        "Window size and animation can be changed in settings.ini.`n"
        "`n"
        "SCRATCH FOLDER`n"
        )

        help_text .= this.scratch_directory

        help_gui.AddText("w610", help_text)

        help_gui.OnEvent("Close", CloseHelp)
        help_gui.OnEvent("Escape", CloseHelp)
        help_gui.Show()

        CloseHelp(*) {
            try help_gui.Destroy()
            help_gui := 0

            for icon_handle in help_icons
                DllCall("DestroyIcon", "ptr", icon_handle, "int")

            help_icons := []
        }
    }

    OnScriptExit(exit_reason, exit_code)
    {
        SetTimer this.autosave_callback, 0
        if this.HasWindow() {
            try {
                if !this.bridge || this.bridge.tainted
                    this.ConnectBridge()
                this.SaveCurrentPage()
            }
            ; Finish any partially completed animation, including during reload.
            try {
                DllCall("SetWindowRgn", "ptr", this.window_hwnd, "ptr", 0, "int", true)
                bounds := this.last_bounds ? this.last_bounds : this.GetBounds(this.window_hwnd)
                WinMove bounds.x, bounds.y, bounds.w, bounds.h, "ahk_id " this.window_hwnd
            }
            ; Keep ownership for reattachment, but never leave a hidden orphan
            ; after an ordinary exit. Shutdown/logoff are managed by Windows.
            if exit_reason != "Reload" && exit_reason != "Single"
                && exit_reason != "Shutdown" && exit_reason != "Logoff"
            {
                try {
                    DllCall("SetWindowRgn", "ptr", this.window_hwnd, "ptr", 0, "int", true)
                    bounds := this.GetBounds(this.window_hwnd)
                    WinMove bounds.x, bounds.y, bounds.w, bounds.h, "ahk_id " this.window_hwnd
                    WinSetAlwaysOnTop false, "ahk_id " this.window_hwnd
                    WinShow "ahk_id " this.window_hwnd
                }
            }
        }
        this.bridge := 0
        if this.mutex_handle {
            DllCall("CloseHandle", "ptr", this.mutex_handle)
            this.mutex_handle := 0
        }
        return 0
    }
}


; =============================================================================
; Notepad++ / Scintilla message bridge
; =============================================================================
; Notepad++ custom messages are above WM_USER. Windows does not marshal their
; pointers between processes. String/integer output buffers must therefore live
; in Notepad++'s address space, not in an ordinary local AHK Buffer.
;
; Only read/write data memory is allocated. No code or plugins are injected.
; The 64-bit requirement keeps pointers valid with both 32-bit and 64-bit editors.
; =============================================================================

class NotepadBridge
{
    __New(window_hwnd)
    {
        this.window_hwnd := window_hwnd
        this.process_handle := 0
        this.remote_pointer := 0
        this.buffer_bytes := 65536
        this.tainted := false
        process_id := WinGetPID("ahk_id " window_hwnd)
        this.process_handle := DllCall("OpenProcess", "uint", 0x1038, "int", false,
            "uint", process_id, "ptr") ; QUERY_LIMITED_INFORMATION | VM_OPERATION | VM_READ | VM_WRITE
        if !this.process_handle
            throw Error("Cannot communicate with Notepad++. Run it and AutoHotkey at the same privilege level, normally without administrator rights.")
        this.remote_pointer := DllCall("VirtualAllocEx", "ptr", this.process_handle,
            "ptr", 0, "uptr", this.buffer_bytes, "uint", 0x3000, "uint", 4, "ptr")
        if !this.remote_pointer
            throw OSError(A_LastError, "VirtualAllocEx")
    }

    __Delete()
    {
        ; A timed-out receiver may still touch its buffer. Keep that small
        ; allocation until the editor exits rather than risk a use-after-free.
        if this.remote_pointer && this.process_handle && !this.tainted
            DllCall("VirtualFreeEx", "ptr", this.process_handle, "ptr", this.remote_pointer,
                "uptr", 0, "uint", 0x8000)
        if this.process_handle
            DllCall("CloseHandle", "ptr", this.process_handle)
    }

    Send(message, w_param := 0, l_param := 0, target_hwnd := 0)
    {
        if this.tainted
            throw Error("Notepad++ did not respond. Resolve any editor dialog, then try the scratchpad command again.")
        if !target_hwnd
            target_hwnd := this.window_hwnd
        result := 0
        if !DllCall("SendMessageTimeoutW", "ptr", target_hwnd, "uint", message,
            "uptr", w_param, "ptr", l_param, "uint", 0x23, "uint", 3000,
            "uptr*", &result, "ptr")
        {
            this.tainted := true
            throw Error("Notepad++ did not respond within three seconds. No save or close was assumed successful. Resolve any editor dialog, then try again.")
        }
        return result
    }

    WriteRemoteText(text := "")
    {
        if this.tainted
            throw Error("The previous editor request is still unresolved. Try the scratchpad command again.")
        if (StrLen(text) + 1) * 2 > this.buffer_bytes
            throw Error("The file path is too long for the Notepad++ message buffer.")
        local_buffer := Buffer(this.buffer_bytes, 0)
        if text != ""
            StrPut text, local_buffer, "UTF-16"
        bytes_written := 0
        if !DllCall("WriteProcessMemory", "ptr", this.process_handle,
            "ptr", this.remote_pointer, "ptr", local_buffer, "uptr", local_buffer.Size,
            "uptr*", &bytes_written, "int") || bytes_written != local_buffer.Size
            throw OSError(A_LastError, "WriteProcessMemory")
    }

    ReadRemote(bytes := 0, remote_pointer := 0)
    {
        if !remote_pointer
            remote_pointer := this.remote_pointer
        if !bytes
            bytes := this.buffer_bytes
        local_buffer := Buffer(bytes, 0)
        bytes_read := 0
        if !DllCall("ReadProcessMemory", "ptr", this.process_handle,
            "ptr", remote_pointer, "ptr", local_buffer, "uptr", bytes,
            "uptr*", &bytes_read, "int") || bytes_read != bytes
            throw OSError(A_LastError, "ReadProcessMemory")
        return local_buffer
    }

    GetCurrentPath()
    {
        this.WriteRemoteText()
        if !this.Send(4025, this.buffer_bytes // 2, this.remote_pointer) ; NPPM_GETFULLCURRENTPATH
            throw Error("Could not read the active Notepad++ file path.")
        return StrGet(this.ReadRemote(), "UTF-16")
    }

    PathMessage(message, path)
    {
        this.WriteRemoteText(path)
        return this.Send(message, 0, this.remote_pointer)
    }

    ReadInteger(message)
    {
        this.WriteRemoteText()
        if !this.Send(message, 0, this.remote_pointer)
            throw Error("Could not read the requested Notepad++ editor state.")
        return NumGet(this.ReadRemote(4), 0, "int")
    }

    OpenBufferCount()
    {
        buffer_ids := Map()

        ; Notepad++ keeps a dummy document in the hidden view.
        ; Count buffers only in views that are actually exposed to the user.
        for view_info in [[0, 1], [1, 2]] {
            view_index := view_info[1]
            count_type := view_info[2]

            if this.Send(2047, 0, view_index) < 0 ; NPPM_GETCURRENTDOCINDEX
                continue

            file_count := this.Send(2031, 0, count_type) ; NPPM_GETNBOPENFILES

            Loop file_count {
                buffer_id := this.Send(
                    2083,           ; NPPM_GETBUFFERIDFROMPOS
                    A_Index - 1,
                    view_index
                )

                if buffer_id
                    buffer_ids[buffer_id] := true
            }
        }

        return buffer_ids.Count
    }

    ScintillaHwnd()
    {
        view_index := this.ReadInteger(2028) ; NPPM_GETCURRENTSCINTILLA
        return ControlGetHwnd("Scintilla" (view_index + 1), "ahk_id " this.window_hwnd)
    }

    Scintilla(message, w_param := 0, l_param := 0)
    {
        return this.Send(message, w_param, l_param, this.ScintillaHwnd())
    }

    IsDirty()
    {
        return this.Scintilla(2159) != 0 ; SCI_GETMODIFY
    }

    DocumentText()
    {
        scintilla_hwnd := this.ScintillaHwnd()
        text_bytes := this.Send(2006, 0, 0, scintilla_hwnd) + 1 ; SCI_GETLENGTH + NUL
        ; Do not grow the path buffer: subsequent tiny API reads would otherwise
        ; copy a whole large document's allocation on every autosave tick.
        text_pointer := DllCall("VirtualAllocEx", "ptr", this.process_handle,
            "ptr", 0, "uptr", text_bytes, "uint", 0x3000, "uint", 4, "ptr")
        if !text_pointer
            throw OSError(A_LastError, "VirtualAllocEx")
        try {
            this.Send(2182, text_bytes, text_pointer, scintilla_hwnd) ; SCI_GETTEXT
            return StrGet(this.ReadRemote(text_bytes, text_pointer), "UTF-8")
        }
        finally {
            ; A timed-out editor may still use this allocation; let process exit
            ; reclaim it instead of freeing memory while the receiver uses it.
            if !this.tainted
                DllCall("VirtualFreeEx", "ptr", this.process_handle, "ptr", text_pointer,
                    "uptr", 0, "uint", 0x8000)
        }
    }

    MenuCommand(command_id)
    {
        return this.Send(2072, 0, command_id) ; NPPM_MENUCOMMAND
    }
}

SetScratchpadHelpIcons(help_gui)
{
    icon_handles := []
    icon_path := A_ScriptDir "\icons\scratchpad.ico"

    if !FileExist(icon_path)
        return icon_handles

    try {
        for icon_index, size in [16, 32] {
            image_type := 0
            icon_handle := LoadPicture(
                icon_path,
                "Icon1 w" size " h" size,
                &image_type
            )

            if !icon_handle
                continue

            if image_type != 1 {
                DllCall(
                    image_type = 2 ? "DestroyCursor" : "DeleteObject",
                    "ptr",
                    icon_handle,
                    "int"
                )
                continue
            }

            icon_handles.Push(icon_handle)

            SendMessage(
                0x0080,
                icon_index - 1,
                icon_handle,
                ,
                help_gui.Hwnd
            )
        }
    }
    catch {
    }

    return icon_handles
}


ScratchpadFileStamp(path)
{
    attributes := Buffer(36, 0) ; WIN32_FILE_ATTRIBUTE_DATA
    if !DllCall("GetFileAttributesExW", "str", path, "int", 0, "ptr", attributes, "int")
        throw OSError(A_LastError, "GetFileAttributesExW", path)
    ; Preserve FILETIME precision, including same-size edits within one second.
    return Format("{:016X}:{:08X}{:08X}", NumGet(attributes, 20, "int64"),
        NumGet(attributes, 28, "uint"), NumGet(attributes, 32, "uint"))
}

ScratchpadClockMs()
{
    static frequency := 0
    if !frequency
        DllCall("QueryPerformanceFrequency", "int64*", &frequency)
    counter := 0
    DllCall("QueryPerformanceCounter", "int64*", &counter)
    return counter * 1000 / frequency
}
