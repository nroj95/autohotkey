#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn

A_IconTip := "CapsLock Layer"
try TraySetIcon(A_ScriptDir "\icons\capslock-layer.ico")

caps_layer_presence_mutex := DllCall(
    "CreateMutex",
    "ptr", 0,
    "int", false,
    "str", "Local\WindowCascade.CapsLockLayer",
    "ptr"
)

; Window Cascade and Window Hotkeys use this handle as their dependency signal.
if !caps_layer_presence_mutex
    throw OSError(A_LastError, "CreateMutex", "Could not announce CapsLock Layer.")

last_left_shift_release_ms := 0
double_tap_window_ms := 180

caps_layer_armed := false
caps_layer_arm_window_ms := 1400

startup_shortcut_path := A_Startup "\CapsLock Layer.lnk"
window_cascade_settings_path := EnvGet("LOCALAPPDATA") "\Window Cascade\settings.ini"

window_cascade_command_message := DllCall(
    "RegisterWindowMessage",
    "str", "WindowCascade.Command",
    "uint"
)

; Keep these command IDs in sync with window-cascade\settings.ahk.
cascade_command_focus_previous := 1
cascade_command_focus_next := 2
cascade_command_rotate_slot_previous := 3
cascade_command_rotate_slot_next := 4
cascade_command_swap_window_up := 5
cascade_command_swap_window_down := 6
cascade_command_adopt_active := 7
cascade_command_rotate_layers := 8
cascade_command_toggle_minimize := 9
cascade_command_bring_forward := 10
cascade_command_close_active := 11
cascade_command_close_scope := 12
cascade_command_gather_to_monitor := 13
cascade_command_show_help := 14
cascade_command_move_monitor_left := 15
cascade_command_move_monitor_right := 16

window_hotkeys_command_message := DllCall(
    "RegisterWindowMessage",
    "str", "WindowHotkeys.Command",
    "uint"
)

; Keep these command IDs in sync with window-hotkeys\settings.ahk.
window_hotkeys_command_focus_left := 1
window_hotkeys_command_focus_right := 2
window_hotkeys_command_focus_up := 3
window_hotkeys_command_focus_down := 4
window_hotkeys_command_show_help := 5

window_hotkeys_cycle_steam_message := DllCall(
    "RegisterWindowMessage",
    "str", "WindowHotkeys.CycleSteamGames",
    "uint"
)

debug_reset_logs_message := DllCall(
    "RegisterWindowMessage",
    "str", "WindowDebug.ResetLogs",
    "uint"
)

caps_layer_disarm_message := DllCall(
    "RegisterWindowMessage",
    "str", "nroj.CapsLockLayer.Disarm",
    "uint"
)

pause_layer_disarm_message := DllCall(
    "RegisterWindowMessage",
    "str", "nroj.PauseCommandMode.Disarm",
    "uint"
)

OnMessage(caps_layer_disarm_message, HandleCapsLayerDisarm)

; Start with Caps Lock off, but allow the Shift gesture to toggle it.
SetCapsLockState "Off"


; =============================================================================
; mission
; =============================================================================
; - use caps lock as a left-hand modifier layer producing f13-f24.
; - allow tapping caps lock to arm one discrete keypress for a few seconds.
; - hold virtual keys only while both caps lock and the mapped key are held.
; - keep caps lock itself from toggling capitalization.
; - toggle actual caps lock with a very fast double-tap of left shift.
; - expose f13-f24 as universal extra keys for apps and app-specific macros.
; - provide numpad 0-9 through caps lock on keyboards without a numpad.
; - provide Window Cascade and Window Hotkeys companion controls.
; - provide a tray-menu toggle for launching the script with Windows.
; =============================================================================


; =============================================================================
; tray menu
; =============================================================================

A_TrayMenu.Delete()
A_TrayMenu.Add("How to use", ShowCapsLockLayerHelp)
A_TrayMenu.Add("Run at startup", ToggleStartup)
A_TrayMenu.Add()
A_TrayMenu.AddStandard()

UpdateStartupMenu()



; =============================================================================
; caps lock modifier
; =============================================================================

; Hold Caps Lock for normal chords, or tap it to arm one mapped key.
; Modified Caps presses are swallowed without arming the one-shot layer.
*CapsLock::
{
    if GetKeyState("LWin", "P") || GetKeyState("RWin", "P") {
        SuppressStartMenu()
        return
    }

    if (
        GetKeyState("Shift", "P")
        || GetKeyState("Ctrl", "P")
        || GetKeyState("Alt", "P")
    ) {
        return
    }

    ArmCapsLayer()
}

; Win is part of the Caps layer here, not a standalone Start-menu press.
CapsLock & LWin::SuppressStartMenu()
CapsLock & RWin::SuppressStartMenu()


; Top row.
CapsLock & q::HoldVirtualKey("F13", "q")
CapsLock & w::HoldVirtualKey("F14", "w")
CapsLock & e::HoldVirtualKey("F15", "e")
CapsLock & r::HoldVirtualKey("F16", "r")

; Home row.
CapsLock & a::HoldVirtualKey("F17", "a")
CapsLock & s::HoldVirtualKey("F18", "s")
CapsLock & d::HoldVirtualKey("F19", "d")
CapsLock & f::HoldVirtualKey("F20", "f")

; Bottom row.
CapsLock & z::HoldVirtualKey("F21", "z")
CapsLock & x::HoldVirtualKey("F22", "x")
CapsLock & c::HoldVirtualKey("F23", "c")
CapsLock & v::HoldVirtualKey("F24", "v")

; Terminal-only personal macro trigger.
; Shift+F19 keeps this separate from the normal Caps + D -> F19 mapping.
#HotIf WinActive("ahk_exe WindowsTerminal.exe")
CapsLock & k::HoldModifiedVirtualKey("F19", "Shift", "k")
#HotIf
CapsLock & k::return

; Number row.
CapsLock & 0::HoldVirtualKey("Numpad0", "0")
CapsLock & 1::HoldVirtualKey("Numpad1", "1")
CapsLock & 2::HoldVirtualKey("Numpad2", "2")
CapsLock & 3::HoldVirtualKey("Numpad3", "3")
CapsLock & 4::HoldVirtualKey("Numpad4", "4")
CapsLock & 5::HoldVirtualKey("Numpad5", "5")
CapsLock & 6::HoldVirtualKey("Numpad6", "6")
CapsLock & 7::HoldVirtualKey("Numpad7", "7")
CapsLock & 8::HoldVirtualKey("Numpad8", "8")
CapsLock & 9::HoldVirtualKey("Numpad9", "9")

; Companion window controls.
; Win routes arrows to Window Hotkeys. Otherwise Caps remains Cascade-local,
; while Alt keeps its wider Window Cascade scope.
CapsLock & Up::
{
    if WindowHotkeysModifierHeld() {
        PostWindowHotkeysCommand(window_hotkeys_command_focus_up)
        KeyWait "Up"
        return
    }

    PostPlainWindowCascadeCommand(cascade_command_swap_window_up)
}

CapsLock & Down::
{
    if WindowHotkeysModifierHeld() {
        PostWindowHotkeysCommand(window_hotkeys_command_focus_down)
        KeyWait "Down"
        return
    }

    PostPlainWindowCascadeCommand(cascade_command_swap_window_down)
}

CapsLock & Left::
{
    if WindowHotkeysModifierHeld() {
        PostWindowHotkeysCommand(window_hotkeys_command_focus_left)
        KeyWait "Left"
        return
    }

    if GetKeyState("Alt", "P") {
        PostWindowCascadeCommand(
            cascade_command_move_monitor_left,
            WinExist("A")
        )
        KeyWait "Left"
        return
    }

    if !GetKeyState("Shift", "P")
        PostWindowCascadeCommand(cascade_command_rotate_slot_previous)
}

CapsLock & Right::
{
    if WindowHotkeysModifierHeld() {
        PostWindowHotkeysCommand(window_hotkeys_command_focus_right)
        KeyWait "Right"
        return
    }

    if GetKeyState("Alt", "P") {
        PostWindowCascadeCommand(
            cascade_command_move_monitor_right,
            WinExist("A")
        )
        KeyWait "Right"
        return
    }

    if !GetKeyState("Shift", "P")
        PostWindowCascadeCommand(cascade_command_rotate_slot_next)
}
CapsLock & PgUp::PostPlainWindowCascadeCommand(cascade_command_focus_previous)
CapsLock & PgDn::PostPlainWindowCascadeCommand(cascade_command_focus_next)
CapsLock & Backspace::PostPlainWindowCascadeCommandOnce(
    cascade_command_adopt_active,
    "Backspace"
)
#HotIf WindowCascadeRotateKeyIs("Space")
CapsLock & Space::PostWindowCascadeRotateCommandOnce("Space")

#HotIf WindowCascadeRotateKeyIs("Tab")
CapsLock & Tab::PostWindowCascadeRotateCommandOnce("Tab")
#HotIf
CapsLock & Home::PostPlainWindowCascadeCommandOnce(
    cascade_command_bring_forward,
    "Home"
)
CapsLock & m::PostWindowCascadeCommandOnce(
    cascade_command_toggle_minimize,
    "m",
    GetKeyState("Alt", "P")
)
CapsLock & F4::PostWindowCascadeCommandOnce(
    cascade_command_close_scope,
    "F4",
    GetKeyState("Alt", "P")
)
CapsLock & F7::PostAltOnlyWindowCascadeCommandOnce(
    cascade_command_gather_to_monitor,
    "F7"
)
CapsLock & Delete::PostPlainWindowCascadeCommandOnce(
    cascade_command_close_active,
    "Delete"
)

CapsLock & h::
{
    if WindowHotkeysModifierHeld() {
        PostWindowHotkeysCommand(window_hotkeys_command_show_help)
        KeyWait "h"
        return
    }

    PostPlainWindowCascadeCommand(cascade_command_show_help)
    KeyWait "h"
}

; Window Hotkeys.
CapsLock & g::PostRegisteredCommand(window_hotkeys_cycle_steam_message)

; Diagnostics.
CapsLock & F5::PostRegisteredCommand(debug_reset_logs_message)


; =============================================================================
; tapped caps lock layer
; =============================================================================

#HotIf CapsLayerOneShotReady()

; Top row.
q::UseArmedVirtualKey("F13", "q")
w::UseArmedVirtualKey("F14", "w")
e::UseArmedVirtualKey("F15", "e")
r::UseArmedVirtualKey("F16", "r")

; Home row.
a::UseArmedVirtualKey("F17", "a")
s::UseArmedVirtualKey("F18", "s")
d::UseArmedVirtualKey("F19", "d")
f::UseArmedVirtualKey("F20", "f")

; Bottom row.
z::UseArmedVirtualKey("F21", "z")
x::UseArmedVirtualKey("F22", "x")
c::UseArmedVirtualKey("F23", "c")
v::UseArmedVirtualKey("F24", "v")

; Terminal-only personal macro trigger.
#HotIf CapsLayerOneShotReady() && WinActive("ahk_exe WindowsTerminal.exe")
k::UseArmedModifiedVirtualKey("F19", "Shift", "k")

#HotIf CapsLayerOneShotReady()
k::UseArmedNoOpKey("k")

; Number row.
0::UseArmedVirtualKey("Numpad0", "0")
1::UseArmedVirtualKey("Numpad1", "1")
2::UseArmedVirtualKey("Numpad2", "2")
3::UseArmedVirtualKey("Numpad3", "3")
4::UseArmedVirtualKey("Numpad4", "4")
5::UseArmedVirtualKey("Numpad5", "5")
6::UseArmedVirtualKey("Numpad6", "6")
7::UseArmedVirtualKey("Numpad7", "7")
8::UseArmedVirtualKey("Numpad8", "8")
9::UseArmedVirtualKey("Numpad9", "9")

; Optional Window Cascade controls.
; One-shot Caps exposes only unmodified slot/layer-local commands.
Up::UseArmedWindowCascadeCommand(cascade_command_swap_window_up, "Up")
Down::UseArmedWindowCascadeCommand(cascade_command_swap_window_down, "Down")
Left::UseArmedWindowCascadeCommand(cascade_command_rotate_slot_previous, "Left")
Right::UseArmedWindowCascadeCommand(cascade_command_rotate_slot_next, "Right")
PgUp::UseArmedWindowCascadeCommand(cascade_command_focus_previous, "PgUp")
PgDn::UseArmedWindowCascadeCommand(cascade_command_focus_next, "PgDn")
Backspace::UseArmedWindowCascadeCommand(cascade_command_adopt_active, "Backspace")

#HotIf CapsLayerOneShotReady() && WindowCascadeRotateKeyIs("Space")
Space::UseArmedWindowCascadeCommand(cascade_command_rotate_layers, "Space")

#HotIf CapsLayerOneShotReady() && WindowCascadeRotateKeyIs("Tab")
Tab::UseArmedWindowCascadeCommand(cascade_command_rotate_layers, "Tab")

#HotIf CapsLayerOneShotReady()
Home::UseArmedWindowCascadeCommand(cascade_command_bring_forward, "Home")
m::UseArmedWindowCascadeCommand(cascade_command_toggle_minimize, "m")
F4::UseArmedWindowCascadeCommand(cascade_command_close_scope, "F4")
Delete::UseArmedWindowCascadeCommand(cascade_command_close_active, "Delete")
h::UseArmedWindowCascadeCommand(cascade_command_show_help, "h")

; Window Hotkeys.
g::UseArmedRegisteredCommand(window_hotkeys_cycle_steam_message, "g")

; Diagnostics.
F5::UseArmedRegisteredCommand(debug_reset_logs_message, "F5")

#HotIf


; =============================================================================
; caps lock toggle
; =============================================================================

; A very fast double-tap of left Shift toggles actual Caps Lock.
; Normal Shift behavior passes through unchanged.
~LShift Up::
{
    global last_left_shift_release_ms, double_tap_window_ms

    current_time_ms := A_TickCount

    if last_left_shift_release_ms
        && current_time_ms - last_left_shift_release_ms <= double_tap_window_ms
    {
        SetCapsLockState GetKeyState("CapsLock", "T") ? "Off" : "On"
        last_left_shift_release_ms := 0
        return
    }

    last_left_shift_release_ms := current_time_ms
}


; =============================================================================
; one-shot layer state
; =============================================================================

CapsLayerOneShotReady()
{
    global caps_layer_armed

    return (
        caps_layer_armed
        && !GetKeyState("Shift", "P")
        && !GetKeyState("Ctrl", "P")
        && !GetKeyState("Alt", "P")
        && !GetKeyState("LWin", "P")
        && !GetKeyState("RWin", "P")
    )
}

SuppressStartMenu()
{
    ; vkE8 is an unassigned virtual key used only to make Windows treat the
    ; physically held Win key as part of a chord instead of opening Start.
    Send "{Blind}{vkE8}"
}


ArmCapsLayer()
{
    global caps_layer_armed, caps_layer_arm_window_ms
    global pause_layer_disarm_message

    ; Only one one-shot command layer should remain armed at a time.
    PostRegisteredCommand(pause_layer_disarm_message)

    caps_layer_armed := true

    ShowCapsLayerTip()

    ; Refresh the one-shot timeout on every tap.
    SetTimer DisarmCapsLayer, 0
    SetTimer DisarmCapsLayer, -caps_layer_arm_window_ms
}

DisarmCapsLayer()
{
    global caps_layer_armed

    caps_layer_armed := false
    SetTimer DisarmCapsLayer, 0
    HideCapsLayerTip()
}

HandleCapsLayerDisarm(*)
{
    DisarmCapsLayer()
}


; =============================================================================
; one-shot key and command dispatch
; =============================================================================

UseArmedVirtualKey(virtual_key, physical_key)
{
    ; The one-shot has been consumed, so hide its indicator immediately.
    HideCapsLayerTip()
    SetTimer DisarmCapsLayer, 0

    previous_send_level := SendLevel(1)

    try {
        SendEvent "{Blind}{" virtual_key "}"
        KeyWait physical_key
    }
    finally {
        SendLevel previous_send_level
        DisarmCapsLayer()
    }
}

UseArmedModifiedVirtualKey(virtual_key, modifier_key, physical_key)
{
    ; The one-shot has been consumed, so hide its indicator immediately.
    HideCapsLayerTip()
    SetTimer DisarmCapsLayer, 0

    previous_send_level := SendLevel(1)

    try {
        SendEvent "{Blind}{" modifier_key " down}{" virtual_key "}{" modifier_key " up}"
        KeyWait physical_key
    }
    finally {
        SendLevel previous_send_level
        DisarmCapsLayer()
    }
}

UseArmedNoOpKey(physical_key)
{
    HideCapsLayerTip()
    SetTimer DisarmCapsLayer, 0

    try {
        KeyWait physical_key
    }
    finally {
        DisarmCapsLayer()
    }
}

UseArmedRegisteredCommand(message_id, physical_key)
{
    ; The one-shot has been consumed, so hide its indicator immediately.
    HideCapsLayerTip()
    SetTimer DisarmCapsLayer, 0

    try {
        PostRegisteredCommand(message_id)
        KeyWait physical_key
    }
    finally {
        DisarmCapsLayer()
    }
}

UseArmedWindowCascadeCommand(command_id, physical_key)
{
    ; Monitor/cross-monitor parameters are intentionally unavailable here.
    HideCapsLayerTip()
    SetTimer DisarmCapsLayer, 0

    try {
        PostWindowCascadeCommand(command_id)
        KeyWait physical_key
    }
    finally {
        DisarmCapsLayer()
    }
}


; =============================================================================
; held virtual keys
; =============================================================================

HoldVirtualKey(virtual_key, physical_key)
{
    ; Use an elevated send level so companion AutoHotkey scripts can receive
    ; these virtual keys as hotkeys.
    previous_send_level := SendLevel(1)

    try {
        SendEvent "{Blind}{" virtual_key " down}"

        ; The virtual key is held only while both physical keys remain down.
        while GetKeyState("CapsLock", "P")
            && GetKeyState(physical_key, "P")
        {
            Sleep 10
        }
    }
    finally {
        SendEvent "{Blind}{" virtual_key " up}"
        SendLevel previous_send_level
    }
}

HoldModifiedVirtualKey(virtual_key, modifier_key, physical_key)
{
    ; Keep private macro triggers distinct from the public F13-F24 layer.
    previous_send_level := SendLevel(1)

    try {
        SendEvent "{Blind}{" modifier_key " down}{" virtual_key " down}"

        while GetKeyState("CapsLock", "P")
            && GetKeyState(physical_key, "P")
        {
            Sleep 10
        }
    }
    finally {
        SendEvent "{Blind}{" virtual_key " up}{" modifier_key " up}"
        SendLevel previous_send_level
    }
}


; =============================================================================
; Window Cascade integration
; =============================================================================

WindowCascadeRotateKeyIs(expected_key)
{
    global window_cascade_settings_path

    rotate_key := IniRead(
        window_cascade_settings_path,
        "Controls",
        "RotateKey",
        ""
    )

    ; Read the legacy INI section only to preserve an existing rotate-key choice.
    if rotate_key = ""
        rotate_key := IniRead(
            window_cascade_settings_path,
            "Standalone",
            "RotateKey",
            "Space"
        )

    if rotate_key != "Space" && rotate_key != "Tab"
        rotate_key := "Space"

    return rotate_key = expected_key
}

PostPlainWindowCascadeCommand(command_id)
{
    if !GetKeyState("Shift", "P") && !GetKeyState("Alt", "P")
        PostWindowCascadeCommand(command_id)
}

PostPlainWindowCascadeCommandOnce(command_id, physical_key)
{
    PostPlainWindowCascadeCommand(command_id)
    KeyWait physical_key
}

PostWindowCascadeRotateCommandOnce(physical_key)
{
    global cascade_command_rotate_layers

    ; Sample Alt once per press. KeyWait prevents held-key repeats or direction
    ; changes when Alt is released before the selected Space/Tab key.
    if !GetKeyState("Shift", "P") {
        direction := GetKeyState("Alt", "P") ? -1 : 1
        PostWindowCascadeCommand(cascade_command_rotate_layers, direction)
    }

    KeyWait physical_key
}

PostWindowCascadeCommand(command_id, parameter := 0)
{
    global window_cascade_command_message

    DllCall(
        "PostMessage",
        "ptr", 0xFFFF, ; HWND_BROADCAST
        "uint", window_cascade_command_message,
        "uptr", command_id,
        "ptr", parameter,
        "int"
    )
}

PostWindowCascadeCommandOnce(command_id, physical_key, parameter := 0)
{
    PostWindowCascadeCommand(command_id, parameter)
    KeyWait physical_key
}

PostAltOnlyWindowCascadeCommandOnce(command_id, physical_key)
{
    if GetKeyState("Alt", "P")
        PostWindowCascadeCommand(command_id)

    KeyWait physical_key
}


; =============================================================================
; Window Hotkeys integration
; =============================================================================

WindowHotkeysModifierHeld()
{
    return (
        GetKeyState("LWin", "P")
        || GetKeyState("RWin", "P")
    )
}

PostWindowHotkeysCommand(command_id)
{
    global window_hotkeys_command_message

    DllCall(
        "PostMessage",
        "ptr", 0xFFFF, ; HWND_BROADCAST
        "uint", window_hotkeys_command_message,
        "uptr", command_id,
        "ptr", 0,
        "int"
    )
}


; =============================================================================
; registered command integration
; =============================================================================

PostRegisteredCommand(message_id)
{
    ; Registered messages are safe to broadcast because only programs that
    ; registered the same message name will interpret them.
    DllCall(
        "PostMessage",
        "ptr", 0xFFFF, ; HWND_BROADCAST
        "uint", message_id,
        "uptr", 0,
        "ptr", 0,
        "int"
    )
}


; =============================================================================
; layer indicator
; =============================================================================

ShowCapsLayerTip()
{
    if ActiveWindowBlocksLayerTip()
        return

    CoordMode "Mouse", "Screen"
    CoordMode "ToolTip", "Screen"
    MouseGetPos &mouse_x, &mouse_y

    ; Capture the cursor position once instead of following it.
    ToolTip "caps mode", mouse_x + 14, mouse_y + 18, 2
}

HideCapsLayerTip()
{
    ToolTip , , , 2
}

ActiveWindowBlocksLayerTip()
{
    active_hwnd := WinExist("A")
    if !active_hwnd
        return false

    ; Suppress the mode indicator in maximized windows.
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


; =============================================================================
; help
; =============================================================================

ShowCapsLockLayerHelp(*)
{
    static help_gui := 0

    if help_gui {
        try help_gui.Destroy()
        help_gui := 0
        return
    }

    help_gui := Gui("+AlwaysOnTop", "CapsLock Layer")
    help_gui.SetFont("s10", "Cascadia Mono")

    help_text :=
    (
    "HINTS`n"
    "Hold Caps + key         Use the layer normally`n"
    "Tap Caps, then key      One-shot layer for 1.4 seconds`n"
    "Extra modifiers         Bypass one-shot Caps`n"
    "`n"
    "EXTRA KEYS`n"
    "Caps + Q / W / E / R    F13 - F16`n"
    "Caps + A / S / D / F    F17 - F20`n"
    "Caps + Z / X / C / V    F21 - F24`n"
    "Caps + 0 - 9            Numpad 0 - 9`n"
    "`n"
    "WINDOW CASCADE (when running)`n"
    "Caps + H                 Toggle Cascade help`n"
    "Caps + Space / Tab       Next layer (selected in Cascade's tray)`n"
    "Caps + Alt + Space / Tab Previous layer`n"
    "`n"
    "WINDOW HOTKEYS (when running)`n"
    "Caps + Win + H           Toggle Window Hotkeys help`n"
    "Caps + Win + Arrow       Move spatial focus`n"
    "Caps + G                 Cycle running Steam games`n"
    "`n"
    "Both companion scripts require CapsLock Layer.`n"
    "CapsLock Layer works without either companion.`n"
    "`n"
    "CAPS LOCK`n"
    "Double-tap Left Shift   Toggle actual Caps Lock"
    )

    help_gui.AddText("w610", help_text)

    help_gui.OnEvent("Close", CloseHelp)
    help_gui.OnEvent("Escape", CloseHelp)
    help_gui.Show()

    CloseHelp(*) {
        try help_gui.Destroy()
        help_gui := 0
    }
}


; =============================================================================
; startup
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
