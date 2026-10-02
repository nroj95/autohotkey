; Internal Window Hotkeys module; initialized once by the root launcher.
; Keep assignments at top level to preserve the existing global scope.

; =============================================================================
; defaults and shared state
; =============================================================================

last_minimized_hwnd := 0
home_minimized_windows := []
home_active_hwnd := 0
all_minimized_windows := []
all_active_hwnd := 0
borderless_windows := Map()
suspended_borderless_windows := Map()

steam_game_cycle := []
last_steam_game_hwnd := 0
steam_return_hwnd := 0

; Steam also distributes normal applications and tools. Their install path is
; indistinguishable from a game's path, so keep known non-game executables out
; of Caps+G explicitly instead of guessing from window behavior.
steam_game_excluded_executables := Map(
    "aseprite.exe", true
)

focus_highlight_guis := []
focus_highlight_duration_ms := 1500
focus_highlight_thickness := 12
focus_highlight_overlap := 2
focus_navigation_active := false
focus_navigation_hwnd := 0

startup_shortcut_path := A_Startup "\Window Hotkeys.lnk"
fancyzones_override_snap_disabled := false
fancyzones_hotkey_conflict := false

; CapsLock Layer is a required companion. These timings tolerate normal startup
; ordering and quick script reloads without introducing standalone operation.
caps_layer_startup_wait_ms := 5000
caps_layer_reload_grace_ms := 3000
caps_layer_check_ms := 1000
caps_layer_missing_since := 0
caps_layer_dependency_lost := false

window_hotkeys_command_message := 0

; Keep these command IDs in sync with capslock-layer.ahk.
window_hotkeys_command_focus_left := 1
window_hotkeys_command_focus_right := 2
window_hotkeys_command_focus_up := 3
window_hotkeys_command_focus_down := 4
window_hotkeys_command_show_help := 5


; =============================================================================
; debug settings
; =============================================================================

debug_enabled := true
debug_log_path := A_ScriptDir "\window-hotkeys-debug.log"
