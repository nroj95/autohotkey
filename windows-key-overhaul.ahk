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
; - Swap clockwise/counter-clockwise and navigate focus directly.
; - Preserve borderless fullscreen and Steam cycling as standalone features.
; - Offer Windows Snap setup and ScreenGrid; retain optional FancyZones support.
; =============================================================================

A_IconTip := "Windows Key Overhaul"
try TraySetIcon(A_ScriptDir "\icons\windows-key-overhaul.ico")

#Include "%A_ScriptDir%\windows-key-overhaul\settings.ahk"

; =============================================================================
; initialization
; =============================================================================

EnsureLegacyScriptIsStopped()
InitializeDebugLogging()
OnExit HandleWindowsKeyOverhaulExit

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
