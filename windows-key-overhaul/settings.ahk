; Internal Windows Key Overhaul module; initialized once by the root launcher.
; Keep assignments at top level to preserve the existing global scope.

; =============================================================================
; defaults and shared state
; =============================================================================

last_minimized_hwnd := 0
isolation_minimized_windows := []
isolation_active_hwnd := 0
all_minimized_windows := []
all_active_hwnd := 0
borderless_windows := Map()
suspended_borderless_windows := Map()
horizontal_stretch_windows := Map()
vertical_stretch_windows := Map()
layout_cycle_windows := Map()
center_tile_next_sides := Map()
normal_window_placements := Map()

steam_game_cycle := []
last_steam_game_hwnd := 0
steam_return_hwnd := 0

; Steam also distributes normal applications and tools. Their install path is
; indistinguishable from a game's path, so keep known non-game executables out
; of Shift+Win+G explicitly instead of guessing from window behavior.
steam_game_excluded_executables := Map(
    "aseprite.exe", true
)

focus_highlight_guis := []
focus_highlight_duration_ms := 1500
focus_highlight_thickness := 12
focus_highlight_overlap := 2
focus_navigation_active := false
focus_navigation_hwnd := 0

startup_shortcut_path := A_Startup "\Windows Key Overhaul.lnk"
legacy_startup_shortcut_path := A_Startup "\Window Hotkeys.lnk"
user_preferences_directory := A_AppData "\WindowsKeyOverhaul"
user_preferences_path := user_preferences_directory "\preferences.ini"
screengrid_releases_url := "https://github.com/TtesseractT/ScreenGrid/releases/latest"
fancyzones_integration_state := false
fancyzones_check_in_progress := false


; =============================================================================
; debug settings
; =============================================================================

debug_enabled := true
debug_log_path := A_ScriptDir "\windows-key-overhaul-debug.log"
