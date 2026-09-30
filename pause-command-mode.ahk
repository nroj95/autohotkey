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
    HidePauseLayerTip()
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
    HidePauseLayerTip()
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
    HidePauseLayerTip()
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
    HidePauseLayerTip()
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
    HidePauseLayerTip()
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
    HidePauseLayerTip()
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
    HidePauseLayerTip()
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

    ShowPauseLayerTip()
    SetTimer ShowPauseLayerTip, 50

    ; Refresh the one-shot timeout on every tap.
    SetTimer DisarmPauseLayer, 0
    SetTimer DisarmPauseLayer, -pause_layer_arm_window_ms
}

DisarmPauseLayer() {
    global pause_layer_armed

    pause_layer_armed := false
    SetTimer DisarmPauseLayer, 0
    HidePauseLayerTip()
}

ShowPauseLayerTip() {
    global pause_layer_armed

    if !pause_layer_armed {
        HidePauseLayerTip()
        return
    }

    if ActiveWindowBlocksLayerTip() {
        ToolTip , , , 2
        return
    }

    CoordMode "Mouse", "Screen"
    CoordMode "ToolTip", "Screen"
    MouseGetPos &mouse_x, &mouse_y
    ToolTip "pause mode", mouse_x + 14, mouse_y + 18, 2
}

HidePauseLayerTip() {
    SetTimer ShowPauseLayerTip, 0
    ToolTip , , , 2
}

ActiveWindowBlocksLayerTip() {
    active_hwnd := WinExist("A")
    if !active_hwnd
        return false

    ; Maximized windows do not need the armed-layer indicator.
    if WinGetMinMax("ahk_id " active_hwnd) = 1
        return true

    try WinGetPos(
        &window_x,
        &window_y,
        &window_width,
        &window_height,
        "ahk_id " active_hwnd
    )
    catch
        return false

    window_right := window_x + window_width
    window_bottom := window_y + window_height
    tolerance_px := 2

    ; Borderless fullscreen windows normally cover one monitor exactly.
    loop MonitorGetCount()
    {
        MonitorGet(
            A_Index,
            &monitor_left,
            &monitor_top,
            &monitor_right,
            &monitor_bottom
        )

        if Abs(window_x - monitor_left) <= tolerance_px
            && Abs(window_y - monitor_top) <= tolerance_px
            && Abs(window_right - monitor_right) <= tolerance_px
            && Abs(window_bottom - monitor_bottom) <= tolerance_px
        {
            return true
        }
    }

    return false
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
    "Pause + H          Toggle this help`n"
    "`n"
    "MODES`n"
    "Hold Pause + key   Run a command normally`n"
    "Tap Pause, then key`n"
    "                   One-shot command for 3 seconds`n"
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
