#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn


; =============================================================================
; mission
; =============================================================================
; - provide predictable win-key window management independent of Windows Snap.
; - maximize, minimize, restore, and place windows with simple win-key shortcuts.
; - toggle maximized windows into true borderless fullscreen with win+up.
; - cycle common half/third layouts with win+left and win+right.
; - provide direct quarter-screen placement from the navigation-key cluster.
; - move the active window clockwise by swapping geometry with nearby windows.
; - move focus spatially between nearby windows without moving them.
; - briefly highlight spatially focused windows with the Windows accent color.
; - cycle running Steam games while preserving their window state.
; - remember a just-minimized window until the user clicks elsewhere.
; - toggle all eligible windows minimized/restored with win+m.
; - keep one independent process with a root launcher and internal modules.
; =============================================================================


; =============================================================================
; script identity and shared state
; =============================================================================

A_IconTip := "Window Hotkeys"
try TraySetIcon(A_ScriptDir "\icons\window-hotkeys.ico")

; Initialize the same globals before logging, callbacks, or startup checks.
#Include "%A_ScriptDir%\window-hotkeys\settings.ahk"


; =============================================================================
; logging and cleanup
; =============================================================================

InitializeDebugLogging()

OnExit RestoreAllBorderlessWindows


; =============================================================================
; CapsLock Layer integration
; =============================================================================

steam_game_cycle_message := DllCall(
    "RegisterWindowMessage",
    "str", "WindowHotkeys.CycleSteamGames",
    "uint"
)

OnMessage(
    steam_game_cycle_message,
    HandleSteamGameCycleMessage
)


; =============================================================================
; tray menu and startup checks
; =============================================================================

A_TrayMenu.Delete()
A_TrayMenu.Add("How to use", ToggleWindowHotkeysHelp)
A_TrayMenu.Add()
A_TrayMenu.Add("Run at startup", ToggleStartup)
A_TrayMenu.Add()
A_TrayMenu.AddStandard()

UpdateStartupMenu()
SetTimer(CheckFancyZonesStartup, 1000)
CheckFancyZonesStartup()


; =============================================================================
; internal modules
; =============================================================================
; These files are parts of this script, not separate scripts to launch.
; Keep includes here; feature modules do not include one another.
; Keep the hotkey block intact so its #HotIf contexts retain their scope.

#Include "%A_ScriptDir%\window-hotkeys\controls.ahk"
#Include "%A_ScriptDir%\window-hotkeys\window-state.ahk"
#Include "%A_ScriptDir%\window-hotkeys\layouts.ahk"
#Include "%A_ScriptDir%\window-hotkeys\swapping.ahk"
#Include "%A_ScriptDir%\window-hotkeys\focus.ahk"
#Include "%A_ScriptDir%\window-hotkeys\steam.ahk"
#Include "%A_ScriptDir%\window-hotkeys\borderless.ahk"
#Include "%A_ScriptDir%\window-hotkeys\fancyzones.ahk"
#Include "%A_ScriptDir%\window-hotkeys\windows.ahk"
#Include "%A_ScriptDir%\window-hotkeys\interface.ahk"
#Include "%A_ScriptDir%\window-hotkeys\debug.ahk"
