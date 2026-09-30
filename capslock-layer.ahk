#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn

A_IconTip := "CapsLock Layer"

caps_layer_presence_mutex := DllCall(
    "CreateMutex",
    "ptr", 0,
    "int", false,
    "str", "Local\WindowCascade.CapsLockLayer",
    "ptr"
)

last_left_shift_release_ms := 0
double_tap_window_ms := 180

startup_shortcut_path := A_Startup "\CapsLock Layer.lnk"

window_cascade_focus_up_message := DllCall(
    "RegisterWindowMessage",
    "str", "WindowCascade.FocusUp",
    "uint"
)

window_cascade_focus_down_message := DllCall(
    "RegisterWindowMessage",
    "str", "WindowCascade.FocusDown",
    "uint"
)

window_cascade_adopt_active_message := DllCall(
    "RegisterWindowMessage",
    "str", "WindowCascade.AdoptActive",
    "uint"
)

window_cascade_cycle_stacks_message := DllCall(
    "RegisterWindowMessage",
    "str", "WindowCascade.CycleStacks",
    "uint"
)

window_cascade_toggle_minimize_message := DllCall(
    "RegisterWindowMessage",
    "str", "WindowCascade.ToggleMinimize",
    "uint"
)

window_cascade_bring_forward_message := DllCall(
    "RegisterWindowMessage",
    "str", "WindowCascade.BringForward",
    "uint"
)

window_cascade_close_all_message := DllCall(
    "RegisterWindowMessage",
    "str", "WindowCascade.CloseAll",
    "uint"
)

window_cascade_show_help_message := DllCall(
    "RegisterWindowMessage",
    "str", "WindowCascade.ShowHelp",
    "uint"
)

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

; Start with Caps Lock off, but allow the Shift gesture to toggle it.
SetCapsLockState "Off"


; =============================================================================
; mission
; =============================================================================
; - use caps lock as a left-hand modifier layer producing f13-f24.
; - keep caps lock itself from toggling capitalization.
; - toggle actual caps lock with a very fast double-tap of left shift.
; - expose f13-f24 as universal extra keys for apps and app-specific macros.
; - provide numpad 0-9 through caps lock on keyboards without a numpad.
; - optionally control Window Cascade when that standalone script is running.
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

; Caps Lock itself is reserved as a modifier.
CapsLock::return


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

; Optional Window Cascade navigation.
; These chords silently do nothing when Window Cascade is not running.
CapsLock & PgUp::PostRegisteredCommand(window_cascade_focus_up_message)
CapsLock & PgDn::PostRegisteredCommand(window_cascade_focus_down_message)
CapsLock & Backspace::PostRegisteredCommand(window_cascade_adopt_active_message)
CapsLock & Tab::PostRegisteredCommand(window_cascade_cycle_stacks_message)
CapsLock & Home::PostRegisteredCommand(window_cascade_bring_forward_message)
CapsLock & m::PostRegisteredCommand(window_cascade_toggle_minimize_message)
CapsLock & F4::PostRegisteredCommand(window_cascade_close_all_message)


CapsLock & h::PostRegisteredCommand(window_cascade_show_help_message)

; Window Hotkeys.
CapsLock & g::PostRegisteredCommand(window_hotkeys_cycle_steam_message)

; Diagnostics.
CapsLock & F7::PostRegisteredCommand(debug_reset_logs_message)


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
; help
; =============================================================================

ShowCapsLockLayerHelp(*)
{
    help_text := (
        "CAPS LOCK LAYER`n"
        "`n"
        "EXTRA KEYS`n"
        "Caps + Q / W / E / R    F13 - F16`n"
        "Caps + A / S / D / F    F17 - F20`n"
        "Caps + Z / X / C / V    F21 - F24`n"
        "Caps + 0 - 9            Numpad 0 - 9`n"
        "`n"
        "CAPS LOCK`n"
        "Double-tap Left Shift   Toggle actual Caps Lock`n"
        "`n"
        "WINDOW CASCADE`n"
        "Caps + PgUp             Previous cascade window`n"
        "Caps + PgDn             Next cascade window`n"
        "Caps + Backspace        Adopt active window`n"
        "Caps + Tab              Rotate stacked windows`n"
        "Caps + Home             Bring cascade to front`n"
        "Caps + M                Minimize / restore cascade`n"
        "Caps + F4               Close all cascade windows`n"
        "Caps + H                Window Cascade help`n"
        "`n"
        "WINDOW HOTKEYS`n"
        "Caps + G                Cycle Steam games`n"
        "`n"
        "DIAGNOSTICS`n"
        "Caps + F7               Reset script debug logs`n"
        "`n"
        "Window Cascade and Window Hotkeys commands silently do nothing "
        "when their companion script is not running."
    )

    MsgBox(
        help_text,
        "CapsLock Layer - How to use",
        "Iconi"
    )
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

; =============================================================================
; helpers
; =============================================================================

HoldVirtualKey(virtual_key, physical_key)
{
    ; Use an elevated send level so companion AutoHotkey scripts can receive
    ; these virtual keys as hotkeys.
    previous_send_level := SendLevel(1)

    try {
        SendEvent "{" virtual_key " down}"
        KeyWait physical_key
    }
    finally {
        SendEvent "{" virtual_key " up}"
        SendLevel previous_send_level
    }
}
