#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn

; =============================================================================
; Windows Key Overhaul
; =============================================================================
; - Replace selected Windows-key shortcuts with predictable window management.
; - Use quarter/half widths: 2:6 = 25%, 4:4 = 50%.
; - Cycle edge, near-center, and centered layouts; place top/bottom tiles.
; - Stretch to neighboring visible window edges, or the monitor work-area edge.
; - Swap clockwise/counter-clockwise and navigate focus independently of CapsLock.
; - Preserve borderless fullscreen, Steam cycling, and optional legacy commands.
; - Offer Windows Snap setup and ScreenGrid; retain optional FancyZones support.
; =============================================================================

A_IconTip := "Windows Key Overhaul"

; Reuse the existing icon until an explicitly renamed icon is available.
if FileExist(A_ScriptDir "\icons\windows-key-overhaul.ico")
    TraySetIcon(A_ScriptDir "\icons\windows-key-overhaul.ico")
else
    try TraySetIcon(A_ScriptDir "\icons\window-hotkeys.ico")

#Include "%A_ScriptDir%\windows-key-overhaul\settings.ahk"

; =============================================================================
; initialization and backwards-compatible messages
; =============================================================================

EnsureLegacyScriptIsStopped()
InitializeDebugLogging()
OnExit HandleWindowsKeyOverhaulExit

; These are public message names, not script filenames. Keep them unchanged so
; existing CapsLock Layer installations can still send their optional commands.
window_hotkeys_command_message := DllCall(
    "RegisterWindowMessage", "str", "WindowHotkeys.Command", "uint"
)
OnMessage(window_hotkeys_command_message, HandleWindowsKeyOverhaulCommandMessage)

steam_game_cycle_message := DllCall(
    "RegisterWindowMessage", "str", "WindowHotkeys.CycleSteamGames", "uint"
)
OnMessage(steam_game_cycle_message, HandleSteamGameCycleMessage)

; =============================================================================
; tray menu and deferred startup guidance
; =============================================================================

A_TrayMenu.Delete()
A_TrayMenu.Add("How to use", ToggleWindowsKeyOverhaulHelp)
A_TrayMenu.Add()
A_TrayMenu.Add("Windows Snap settings", OpenWindowsSnapSettings)
A_TrayMenu.Add("ScreenGrid on GitHub", OpenScreenGridReleases)
A_TrayMenu.Add("Check FancyZones compatibility", CheckFancyZonesIntegration)
A_TrayMenu.Add()
A_TrayMenu.Add("Run at startup", ToggleStartup)
A_TrayMenu.Add()
A_TrayMenu.AddStandard()

UpdateStartupMenu()
SetTimer(InitializeDesktopIntegration, -500)

HandleWindowsKeyOverhaulExit(exit_reason, exit_code)
{
    try EndFocusNavigationSession()
    try RestoreAllVerticalStretches()
    try RestoreAllHorizontalStretches()
    try RestoreAllBorderlessWindows(exit_reason, exit_code)
}

; =============================================================================
; internal modules
; =============================================================================
; Settings execute before startup; the remaining modules define functions and
; hotkeys. Do not launch these modules as independent window-management scripts.

#Include "%A_ScriptDir%\windows-key-overhaul\controls.ahk"
#Include "%A_ScriptDir%\windows-key-overhaul\window-state.ahk"
#Include "%A_ScriptDir%\windows-key-overhaul\layout-geometry.ahk"
#Include "%A_ScriptDir%\windows-key-overhaul\layouts.ahk"
#Include "%A_ScriptDir%\windows-key-overhaul\swapping.ahk"
#Include "%A_ScriptDir%\windows-key-overhaul\focus.ahk"
#Include "%A_ScriptDir%\windows-key-overhaul\steam.ahk"
#Include "%A_ScriptDir%\windows-key-overhaul\borderless.ahk"
#Include "%A_ScriptDir%\windows-key-overhaul\fancyzones.ahk"
#Include "%A_ScriptDir%\windows-key-overhaul\windows.ahk"
#Include "%A_ScriptDir%\windows-key-overhaul\interface.ahk"
#Include "%A_ScriptDir%\windows-key-overhaul\startup.ahk"
#Include "%A_ScriptDir%\windows-key-overhaul\debug.ahk"
