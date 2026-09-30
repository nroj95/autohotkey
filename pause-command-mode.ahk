#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn

A_IconTip := "Pause Command Mode"
try TraySetIcon(A_ScriptDir "\icons\pause-command-mode.ico")

startup_shortcut_path := A_Startup "\Pause Command Mode.lnk"
pause_help_gui := 0

pause_layer_armed := false
pause_layer_arm_window_ms := 3000

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
; mission:
; - use Pause as a held modifier for personal text, speaker wake,
;   system sleep, and small utilities.
; - allow tapping Pause to arm one discrete command for a few seconds.
; - keep held Pause chords available as the normal modifier behavior.
; =============================================================================

speaker_wake_file := "C:\Windows\Media\Windows Balloon.wav"

; Hold Pause for normal chords, or tap it to arm one command.
Pause::ArmPauseLayer()

Pause & h::
{
    ShowHelp()
    KeyWait "h"
}

Pause & s::
{
    Send "ß"
    KeyWait "s"
}

Pause & -::
{
    Send "–"
    KeyWait "-"
}

Pause & '::
{
    Send "’"
    KeyWait "'"
}

Pause & n::
{
    SendText "&nbsp;"
    KeyWait "n"
}

Pause & t::
{
    SendText FormatTime(, "yyyyMMdd-HHmmss")
    KeyWait "t"
}

Pause & w::
{
    WakeSpeaker()
    KeyWait "w"
}

Pause & Esc::SleepComputer()


; =============================================================================
; tapped Pause layer
; =============================================================================

#HotIf pause_layer_armed

h::
{
    SetTimer DisarmPauseLayer, 0

    try {
        ShowHelp()
        KeyWait "h"
    }
    finally {
        DisarmPauseLayer()
    }
}

s::
{
    SetTimer DisarmPauseLayer, 0

    try {
        Send "ß"
        KeyWait "s"
    }
    finally {
        DisarmPauseLayer()
    }
}

-::
{
    SetTimer DisarmPauseLayer, 0

    try {
        Send "–"
        KeyWait "-"
    }
    finally {
        DisarmPauseLayer()
    }
}

'::
{
    SetTimer DisarmPauseLayer, 0

    try {
        Send "’"
        KeyWait "'"
    }
    finally {
        DisarmPauseLayer()
    }
}

n::
{
    SetTimer DisarmPauseLayer, 0

    try {
        SendText "&nbsp;"
        KeyWait "n"
    }
    finally {
        DisarmPauseLayer()
    }
}

t::
{
    SetTimer DisarmPauseLayer, 0

    try {
        SendText FormatTime(, "yyyyMMdd-HHmmss")
        KeyWait "t"
    }
    finally {
        DisarmPauseLayer()
    }
}

w::
{
    SetTimer DisarmPauseLayer, 0

    try {
        WakeSpeaker()
        KeyWait "w"
    }
    finally {
        DisarmPauseLayer()
    }
}

Esc::
{
    DisarmPauseLayer()
    SleepComputer()
}

#HotIf


ArmPauseLayer() {
    global pause_layer_armed, pause_layer_arm_window_ms

    pause_layer_armed := true

    ; Refresh the one-shot timeout on every tap.
    SetTimer DisarmPauseLayer, 0
    SetTimer DisarmPauseLayer, -pause_layer_arm_window_ms
}

DisarmPauseLayer() {
    global pause_layer_armed

    pause_layer_armed := false
    SetTimer DisarmPauseLayer, 0
}

SleepComputer() {
    Tip("sleep")

    ; false = sleep rather than hibernate; keep wake events enabled.
    DllCall(
        "PowrProf\SetSuspendState",
        "Int", 0,
        "Int", 0,
        "Int", 0
    )
}

HandlePowerBroadcast(w_param, *) {
    ; PBT_APMRESUMEAUTOMATIC is sent after every system resume.
    if w_param = 0x12
        SetTimer ReloadAfterResume, -500
}

ReloadAfterResume() {
    Reload
}

WakeSpeaker() {
    global speaker_wake_file

    if !FileExist(speaker_wake_file) {
        Tip("speaker wake: missing file")
        return
    }

    original_volume := SoundGetVolume()
    wake_volume := 16

    try {
        ; briefly raise quiet systems enough for the wake sound to matter.
        if original_volume < wake_volume {
            SoundSetVolume wake_volume
            Sleep 100
        }

        Tip("speaker wake")
        SoundPlay speaker_wake_file, true
    }
    finally {
        SoundSetVolume original_volume
    }
}

ShowHelp(*) {
    global pause_help_gui

    if pause_help_gui {
        CloseHelp()
        return
    }

    pause_help_gui := Gui("+AlwaysOnTop", "Pause Command Mode")
    pause_help_gui.SetFont("s10", "Cascadia Mono")

    help_text :=
    (
    "Hold Pause + key    Run a command normally`n"
    "Tap Pause, then key   One-shot command for 3 seconds`n"
    "`n"
    "Pause + H          Toggle this help`n"
    "`n"
    "TEXT`n"
    "Pause + S          Insert ß`n"
    "Pause + -          Insert –`n"
    "Pause + '          Insert ’`n"
    "Pause + N          Insert &nbsp;`n"
    "`n"
    "UTILITIES`n"
    "Pause + T          Insert timestamp`n"
    "Pause + W          Wake speakers`n"
    "Pause + Esc        Sleep PC"
    )

    pause_help_gui.AddText("w510", help_text)

    pause_help_gui.OnEvent("Close", CloseHelp)
    pause_help_gui.OnEvent("Escape", CloseHelp)
    pause_help_gui.Show()
}

CloseHelp(*) {
    global pause_help_gui

    if !pause_help_gui
        return

    try pause_help_gui.Destroy()
    pause_help_gui := 0
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

Tip(message, duration_ms := 2000) {
    ToolTip message

    ; replace any previous clear timer so a stale timer cannot erase a new tip.
    SetTimer ClearTip, 0
    SetTimer ClearTip, -duration_ms
}

ClearTip() {
    ToolTip
}
