; Internal Window Cascade module; initialized once by the launcher.
; Keep assignments at top level to preserve the existing global scope.

; =============================================================================
; settings
; =============================================================================

; New windows use a predictable generic size instead of an app's remembered size.
window_width_ratio := 0.80
window_height_ratio := 0.80

; First branch moves left/up from center; second branch moves right/down.
cascade_x := 28
cascade_y := 24


; A manually moved window still counts as occupying a canonical slot when its
; top-left corner remains close enough to that slot.
cascade_slot_tolerance := 14

; A managed window leaves the cascade after being deliberately moved away
; from every canonical slot. Keep this looser than exact slot matching so
; small manual adjustments do not release a window accidentally.
cascade_release_tolerance := 56

placement_delay_ms := 60

; Some applications expose their real top-level window before it is ready for
; placement. Keep the original launch context while waiting briefly for it.
placement_ready_retry_ms := 200
placement_ready_retry_limit := 25

; Taskbar/shell launches may restore their remembered geometry shortly after
; becoming usable. Let that finish before applying the cascade placement.
placement_settle_delay_ms := 300

; Keep one late safety check in case an application changes geometry again.
placement_stabilize_delays_ms := [500]
placement_stabilize_tolerance := 6

; A busy window may not process an asynchronous placement immediately.
; Keep its slot reserved while retrying without blocking Window Cascade.
placement_stabilize_retry_ms := 500
placement_stabilize_retry_limit := 20
placement_stabilize_confirmation_ms := 2000

; If an application overrides a Cascade placement, give it time to finish
; managing its own geometry before posting another corrective move.
placement_stabilize_backoff_delays_ms := [1000, 2000, 4000]

edge_margin := 12
minimum_width := 320
minimum_height := 220

; Unfocused cascade windows get a clickable bottom-left focus marker.
focus_corner_size := 24
focus_corner_thickness := 22
focus_corner_overlap := 2
; Coalesce event-driven focus-tab updates. The slow timer below is only a
; fallback for Windows events that may occasionally be missed.
focus_corner_update_ms := 50
focus_corner_fallback_ms := 1000
focus_corner_accent_check_ms := 1000

; Focus tabs are shown faintly by default. Alpha 1 is reserved for the hidden
; state so the clickable overlay remains hit-testable.
focus_corner_visible := true
focus_corner_visible_alpha := 72

; The dependency must be running. Startup and reload grace periods tolerate
; normal process-start ordering without introducing standalone operation.
caps_layer_startup_wait_ms := 5000
caps_layer_reload_grace_ms := 3000
caps_layer_check_ms := 1000

placement_enabled := true

settings_directory := EnvGet("LOCALAPPDATA") "\Window Cascade"
settings_path := settings_directory "\settings.ini"
rotate_key := IniRead(settings_path, "Controls", "RotateKey", "")

; Read the legacy INI section only to preserve an existing rotate-key choice.
if rotate_key = ""
    rotate_key := IniRead(settings_path, "Standalone", "RotateKey", "Space")

if rotate_key != "Space" && rotate_key != "Tab"
    rotate_key := "Space"

; =============================================================================
; runtime state
; =============================================================================

rotate_key_menu := 0
caps_layer_missing_since := 0
caps_layer_dependency_lost := false

pending_windows := Map()
handled_windows := Map()
placement_reservations := Map()
startup_windows := Map()
known_windows := Map()
missed_window_poll_ms := 1000
cascade_history := Map()
cascade_compaction_pending := Map()
layer_minimized_windows_by_monitor := Map()
monitor_minimized_windows_by_monitor := Map()
all_cascades_minimized := false

focus_corner_overlays := Map()
focus_corner_targets := Map()
focus_corner_accent_color := ""
focus_corner_accent_check_tick := 0
focus_corner_update_pending := false

current_foreground_hwnd := WinExist("A")
previous_foreground_hwnd := 0

; Clicking empty desktop space can explicitly select a monitor for the next
; window without changing how normal app-to-app placement works.
desktop_monitor_hint := 0
desktop_monitor_hint_tick := 0
desktop_monitor_hint_max_age_ms := 5000

startup_shortcut_path := A_Startup "\Window Cascade.lnk"

win_event_callback := 0
foreground_hook := 0
window_show_hook := 0
window_destroy_hook := 0

cascade_command_message := 0

; =============================================================================
; CapsLock Layer command protocol
; =============================================================================

; Keep these command IDs in sync with capslock-layer.ahk.
cascade_command_focus_previous := 1
cascade_command_focus_next := 2
cascade_command_rotate_slot_previous := 3
cascade_command_rotate_slot_next := 4
cascade_command_swap_window_up := 5
cascade_command_swap_window_down := 6
cascade_command_adopt_active := 7
; Rotation parameter: 0/1 = next (including one-shot Caps), -1 = previous.
cascade_command_rotate_layers := 8
cascade_command_toggle_minimize := 9
cascade_command_bring_forward := 10
cascade_command_close_active := 11
cascade_command_close_scope := 12
cascade_command_gather_to_monitor := 13
cascade_command_show_help := 14
cascade_command_move_monitor_left := 15
cascade_command_move_monitor_right := 16
