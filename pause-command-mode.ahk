#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn

; =============================================================================
; Pause Command Mode - held shortcuts and a single-use tapped layer
; =============================================================================
; - hold Pause for text, help and sleep commands.
; - tap Pause to arm one command for 1.4 seconds; tap again to wake speakers.
; - consume the tapped layer before running a command, while suppressing repeats
;   of that command key until release. Other keys do not inherit the armed layer.
; - coordinate with CapsLock Layer through the existing registered messages.
; - remain event-driven: only the arm timeout and resume reload use one-shot timers.
; =============================================================================

A_IconTip := "Pause Command Mode"
try TraySetIcon(A_ScriptDir "\icons\pause-command-mode.ico")

startup_shortcut_path := A_Startup "\Pause Command Mode.lnk"
pause_layer_armed := false
pause_layer_arm_window_ms := 1400
pause_command_keys_down := Map()
speaker_wake_file := A_WinDir "\Media\Windows Balloon.wav"
speaker_volume_restore := 0

caps_layer_disarm_message := RegisterCommandMessage("nroj.CapsLockLayer.Disarm")
pause_layer_disarm_message := RegisterCommandMessage("nroj.PauseCommandMode.Disarm")
OnMessage(pause_layer_disarm_message, HandlePauseLayerDisarm)
OnExit CleanupPauseMode

A_TrayMenu.Delete()
A_TrayMenu.Add("How to use", ShowHelp)
A_TrayMenu.Add()
A_TrayMenu.Add("Run at startup", ToggleStartup)
A_TrayMenu.Add()
A_TrayMenu.AddStandard()
UpdateStartupMenu()

; Rebuild AutoHotkey's keyboard hook after Windows resumes from sleep.
OnMessage(0x0218, HandlePowerBroadcast)

; =============================================================================
; held Pause shortcuts
; =============================================================================

; A custom combination's unused prefix fires its own hotkey on release.
Pause::ArmPauseLayer()
Pause & h::RunPauseCommand("h")
Pause & s::RunPauseCommand("s")
Pause & -::RunPauseCommand("-")
Pause & '::RunPauseCommand("'")
Pause & n::RunPauseCommand("n")
Pause & t::RunPauseCommand("t")
Pause & Esc::RunPauseCommand("Escape")

; =============================================================================
; tapped Pause shortcuts
; =============================================================================
; Keep only the consumed key intercepted until release, not the entire layer.
; This prevents both repeat characters and a second one-shot command while the
; first key is still down. $ also keeps generated text out of these hotkeys.

#HotIf pause_layer_armed || pause_command_keys_down.Has("Pause")
$Pause::RunPauseCommand("Pause", true)

#HotIf pause_layer_armed || pause_command_keys_down.Has("h")
$h::RunPauseCommand("h", true)

#HotIf pause_layer_armed || pause_command_keys_down.Has("s")
$s::RunPauseCommand("s", true)

#HotIf pause_layer_armed || pause_command_keys_down.Has("-")
$-::RunPauseCommand("-", true)

#HotIf pause_layer_armed || pause_command_keys_down.Has("'")
$'::RunPauseCommand("'", true)

#HotIf pause_layer_armed || pause_command_keys_down.Has("n")
$n::RunPauseCommand("n", true)

#HotIf pause_layer_armed || pause_command_keys_down.Has("t")
$t::RunPauseCommand("t", true)

#HotIf pause_layer_armed || pause_command_keys_down.Has("Escape")
$Esc::RunPauseCommand("Escape", true)
#HotIf

RunPauseCommand(command_key, one_shot := false) {
    global pause_layer_armed, pause_command_keys_down

    ; Claim the key and consume the layer together. Never keep Critical enabled
    ; during sound playback, key waits or the command itself.
    previous_critical := A_IsCritical
    Critical "On"
    try {
        if pause_command_keys_down.Has(command_key)
            || (one_shot && !pause_layer_armed)
            return

        pause_command_keys_down[command_key] := true
        DisarmPauseLayer()
    }
    finally {
        Critical previous_critical
    }

    try {
        switch command_key {
            case "h": ShowHelp()
            case "s": SendText "ß"
            case "-": SendText "–"
            case "'": SendText "’"
            case "n": SendText "&nbsp;"
            case "t": SendText FormatTime(, "yyyyMMdd-HHmmss")
            case "Pause": WakeSpeaker()
            case "Escape":
                ; Finish the physical shortcut before sleeping, so a held key
                ; cannot keep retriggering the command immediately after resume.
                KeyWait "Escape"
                KeyWait "Pause"
                SleepComputer()
        }
    }
    catch as failure {
        TrayTip failure.Message, "Pause Command Mode", 2
    }
    finally {
        try KeyWait command_key
        finally pause_command_keys_down.Delete(command_key)
        ; Do not disarm here: a new Pause tap may have armed a fresh command
        ; while this key was still held.
    }
}

; =============================================================================
; arming, indicators and companion messages
; =============================================================================

ArmPauseLayer() {
    global pause_layer_armed, pause_layer_arm_window_ms
    global caps_layer_disarm_message

    previous_critical := A_IsCritical
    Critical "On"
    try {
        ; Only one one-shot command layer should remain armed at a time.
        PostRegisteredCommand(caps_layer_disarm_message)
        pause_layer_armed := true

        ; Set the safety timeout before touching optional UI. Updating this
        ; one-shot timer also restarts its countdown; no second reset is needed.
        SetTimer DisarmPauseLayer, -pause_layer_arm_window_ms
        try ShowPauseLayerTip()
    }
    finally {
        Critical previous_critical
    }
}

DisarmPauseLayer() {
    global pause_layer_armed

    previous_critical := A_IsCritical
    Critical "On"
    try {
        pause_layer_armed := false
        SetTimer DisarmPauseLayer, 0
        try HidePauseLayerTip()
    }
    finally {
        Critical previous_critical
    }
}

HandlePauseLayerDisarm(*) {
    DisarmPauseLayer()
}

ShowPauseLayerTip() {
    if ActiveWindowBlocksLayerTip()
        return

    CoordMode "Mouse", "Screen"
    CoordMode "ToolTip", "Screen"
    MouseGetPos &mouse_x, &mouse_y

    ; Capture the cursor position once instead of following it.
    ToolTip "pause mode", mouse_x + 14, mouse_y + 18, 2
}

HidePauseLayerTip() {
    ToolTip , , , 2
}

ActiveWindowBlocksLayerTip() {
    active_hwnd := WinExist("A")
    if !active_hwnd
        return false

    previous_dpi_context := 0
    try {
        ; The foreground window can close between these calls.
        if WinGetMinMax("ahk_id " active_hwnd) = 1
            return true

        ; Compare physical rectangles on mixed-DPI desktops. Only the window's
        ; nearest monitor can be an exact fullscreen match; do not scan them all.
        previous_dpi_context := DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")
        window_rect := Buffer(16, 0)
        if !DllCall("GetWindowRect", "ptr", active_hwnd, "ptr", window_rect, "int")
            return false

        monitor := DllCall("MonitorFromWindow", "ptr", active_hwnd, "uint", 2, "ptr")
        monitor_info := Buffer(40, 0)
        NumPut("uint", monitor_info.Size, monitor_info)
        if !DllCall("GetMonitorInfoW", "ptr", monitor, "ptr", monitor_info, "int")
            return false

        tolerance_px := 2
        return Abs(NumGet(window_rect, 0, "int") - NumGet(monitor_info, 4, "int")) <= tolerance_px
            && Abs(NumGet(window_rect, 4, "int") - NumGet(monitor_info, 8, "int")) <= tolerance_px
            && Abs(NumGet(window_rect, 8, "int") - NumGet(monitor_info, 12, "int")) <= tolerance_px
            && Abs(NumGet(window_rect, 12, "int") - NumGet(monitor_info, 16, "int")) <= tolerance_px
    }
    catch {
        return false
    }
    finally {
        if previous_dpi_context
            DllCall("SetThreadDpiAwarenessContext", "ptr", previous_dpi_context, "ptr")
    }
}

RegisterCommandMessage(message_name) {
    message_id := DllCall("RegisterWindowMessageW", "str", message_name, "uint")
    if !message_id
        throw OSError(A_LastError, "RegisterWindowMessageW", message_name)
    return message_id
}

PostRegisteredCommand(message_id) {
    ; Best effort: the companion script does not have to be running.
    return DllCall(
        "PostMessageW",
        "ptr", 0xFFFF, ; HWND_BROADCAST
        "uint", message_id,
        "uptr", 0,
        "ptr", 0,
        "int"
    )
}

; =============================================================================
; sleep, resume and temporary speaker volume
; =============================================================================

SleepComputer() {
    DisarmPauseLayer()
    RestoreSpeakerVolume()

    ; BOOLEAN is one byte. Keep wake events enabled and report rejected requests.
    if !DllCall("PowrProf\SetSuspendState", "uchar", 0, "uchar", 0, "uchar", 0, "uchar")
        throw OSError(A_LastError, "SetSuspendState", "Windows could not enter sleep.")
}

HandlePowerBroadcast(w_param, *) {
    if w_param = 0x4 ; PBT_APMSUSPEND
        DisarmPauseLayer()
    else if w_param = 0x12 { ; PBT_APMRESUMEAUTOMATIC
        DisarmPauseLayer()
        SetTimer ReloadAfterResume, -500
    }
}

ReloadAfterResume() {
    Reload
}

WakeSpeaker() {
    global speaker_wake_file, speaker_volume_restore

    if !FileExist(speaker_wake_file)
        throw Error("The speaker wake sound was not found:`n" speaker_wake_file)

    ; Bind volume restoration to this endpoint, not whichever device happens
    ; to become the default during playback. ComValue releases the interface.
    endpoint_pointer := SoundGetInterface("{5CDF2C82-841E-4546-9722-0CF74078229A}")
    if !endpoint_pointer
        throw Error("The playback device does not expose endpoint volume control.")
    endpoint := ComValue(13, endpoint_pointer) ; IAudioEndpointVolume
    ComCall 9, endpoint, "float*", &original_volume := 0 ; GetMasterVolumeLevelScalar
    wake_volume := 0.16

    try {
        if original_volume < wake_volume {
            ; Keep the boost and its cleanup record together. In particular, a
            ; sleep hotkey must not restore halfway through publishing this state.
            previous_critical := A_IsCritical
            Critical "On"
            try {
                ; Publish first so Reload/Exit can undo an interrupted boost.
                speaker_volume_restore := {
                    endpoint: endpoint,
                    original_volume: original_volume,
                    boosted_volume: wake_volume
                }
                ComCall 7, endpoint, "float", wake_volume, "ptr", 0 ; SetMasterVolumeLevelScalar
                ComCall 9, endpoint, "float*", &applied_volume := 0
                speaker_volume_restore.boosted_volume := applied_volume
            }
            finally {
                Critical previous_critical
            }
            Sleep 100
        }

        SoundPlay speaker_wake_file, true
    }
    finally {
        RestoreSpeakerVolume()
    }
}

RestoreSpeakerVolume() {
    global speaker_volume_restore

    restoration := speaker_volume_restore
    if !restoration
        return

    ComCall 9, restoration.endpoint, "float*", &current_volume := 0
    ; Leave a different user-selected level alone; restore only our own boost.
    if Abs(current_volume - restoration.boosted_volume) < 0.0001
        ComCall 7, restoration.endpoint, "float", restoration.original_volume, "ptr", 0

    ; Forget the cleanup record only after the endpoint check/restoration succeeds.
    speaker_volume_restore := 0
}

CleanupPauseMode(*) {
    DisarmPauseLayer()
    try RestoreSpeakerVolume()
}

; =============================================================================
; help and startup
; =============================================================================

ShowHelp(*) {
    static help_gui := 0

    if help_gui {
        try help_gui.Destroy()
        help_gui := 0
        return
    }

    help_gui := Gui("+AlwaysOnTop", "Pause Command Mode")
    help_gui.SetFont("s10", "Cascadia Mono")

    help_text :=
    (
    "Pause + H            Toggle this help`n"
    "`n"
    "HINTS`n"
    "Hold Pause + key     Run a command normally`n"
    "Tap Pause, then key  One-shot command for 1.4 seconds`n"
    "`n"
    "TEXT`n"
    "Pause + S            Insert ß`n"
    "Pause + -            Insert –`n"
    "Pause + '            Insert ’`n"
    "Pause + N            Insert &nbsp;`n"
    "`n"
    "UTILITIES`n"
    "Pause + T            Insert timestamp`n"
    "Pause, then Pause    Wake speakers`n"
    "Pause + Esc          Sleep PC after releasing the keys"
    )

    ; SS_NOPREFIX keeps the ampersand in &nbsp; visible instead of a mnemonic.
    help_gui.AddText("w510 +0x80", help_text)

    help_gui.OnEvent("Close", CloseHelp)
    help_gui.OnEvent("Escape", CloseHelp)
    help_gui.Show()

    CloseHelp(*) {
        try help_gui.Destroy()
        help_gui := 0
    }
}

ToggleStartup(*) {
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
            "Pause Command Mode",
            "Iconx"
        )
    }
}

UpdateStartupMenu() {
    global startup_shortcut_path

    if FileExist(startup_shortcut_path)
        A_TrayMenu.Check("Run at startup")
    else
        A_TrayMenu.Uncheck("Run at startup")
}
