#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn

Persistent

A_IconTip := "Window Cascade"
try TraySetIcon(A_ScriptDir "\icons\window-cascade.ico")

; Use virtual-screen coordinates so multi-monitor mouse positions match MonitorGet().
CoordMode "Mouse", "Screen"


; =============================================================================
; debug
; =============================================================================

debug_enabled := true
debug_log_path := A_ScriptDir "\window-cascade-debug.log"

InitializeDebugLogging()

OnExit(HandleScriptExit)


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

placement_enabled := true

settings_directory := EnvGet("LOCALAPPDATA") "\Window Cascade"
settings_path := settings_directory "\settings.ini"
rotate_key := IniRead(settings_path, "Controls", "RotateKey", "")

; Preserve the earlier standalone-only setting if it already exists.
if rotate_key = ""
    rotate_key := IniRead(settings_path, "Standalone", "RotateKey", "Space")

if rotate_key != "Space" && rotate_key != "Tab"
    rotate_key := "Space"

rotate_key_menu := 0

pending_windows := Map()
handled_windows := Map()
placement_reservations := Map()
startup_windows := Map()
known_windows := Map()
missed_window_poll_ms := 1000
cascade_history := Map()
cascade_reset_cursors := Map()
cascade_compaction_pending := Map()
layer_minimized_windows_by_monitor := Map()
monitor_minimized_windows_by_monitor := Map()

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

; Keep these command IDs in sync with capslock-layer.ahk.
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


; =============================================================================
; terminology
; =============================================================================
; - cascade: all managed cascade windows on one monitor.
; - slot: one canonical cascade position on that monitor.
; - stack: all windows currently sharing one slot.
; - layer: one depth across the slot stacks; depth 1 is the exposed layer.
; - slots and layers compact automatically so earlier positions stay filled.
; =============================================================================


; =============================================================================
; mission
; =============================================================================
; - detect new normal top-level windows through hooks and a polling fallback.
; - preserve the queued monitor through readiness retries and startup settling.
; - place them on the monitor where the user was already working.
; - detect desktop clicks from the window under the cursor, independent of foreground timing.
; - ignore the application's remembered position and size.
; - give managed windows a consistent monitor-relative size.
; - center the first managed window on each monitor.
; - define fixed cascade slots: center, then left/up, then right/down.
; - inspect actual window positions whenever a new window opens.
; - fill the least-used canonical slot so gaps are repaired before a new layer grows.
; - treat stack depth as layers: one window per slot at each depth.
; - keep plain management commands slot/layer-local and Shift commands monitor-wide.
; - compact holes forward across slots and layers after managed windows disappear.
; - rotate one slot across layers or rotate every slot to expose the next layer.
; - focus and swap current-layer windows by physical top-to-bottom order.
; - let manually moved windows relinquish their old slot automatically.
; - reject obvious child/helper windows before queueing placement.
; - forget destroyed window handles so recycled hwnd values remain safe.
; - optionally accept slot/layer/monitor commands from CapsLock Layer.
; - remain fully functional when CapsLock Layer is not installed or running.
; =============================================================================


; =============================================================================
; startup
; =============================================================================

BuildTrayMenu()

RegisterIntegrationMessages()

SeedStartupWindows()

StartWindowHooks()

SetTimer(WatchForMissedWindows, missed_window_poll_ms)

; Window events normally keep focus tabs aligned. Keep a slow timer only as
; insurance for an event that Windows may occasionally fail to deliver.
OnMessage(0x0202, HandleFocusCornerClick) ; WM_LBUTTONUP
SetTimer(UpdateFocusCornerOverlays, focus_corner_fallback_ms)

; FancyZones can directly compete with new-window placement.
SetTimer(CheckCompatibilitySettings, -500)

; =============================================================================
; standalone hotkeys
; =============================================================================
; Left Ctrl + Left Alt keeps the standalone layer away from common Alt-only
; app shortcuts and avoids treating Right Alt / AltGr as a cascade modifier.

#HotIf !IsCapsLockLayerRunning() && !ActiveWindowBlocksCascadeHotkeys()

<^<!Up::SwapActiveCascadeWindow(-1)
<^<!Down::SwapActiveCascadeWindow(1)
<^<!Left::RotateCurrentCascadeSlot(-1)
<^<!Right::RotateCurrentCascadeSlot(1)
<^<!PgUp::FocusCascadeLayerWindow(-1)
<^<!PgDn::FocusCascadeLayerWindow(1)

<^<!Backspace::
{
    AdoptActiveWindow()
    KeyWait "Backspace"
}

<^<!Home::
{
    BringCommandMonitorCascadeForward()
    KeyWait "Home"
}

<^<!m::
{
    ToggleCurrentCascadeLayerMinimize()
    KeyWait "m"
}

<^<!F4::
{
    CloseCurrentCascadeLayer()
    KeyWait "F4"
}

<^<!h::
{
    ToggleWindowCascadeHelp()
    KeyWait "h"
}

<^<!+m::
{
    ToggleCommandMonitorCascadeMinimize()
    KeyWait "m"
}

<^<!+F4::
{
    CloseCommandMonitorCascade()
    KeyWait "F4"
}

<^<!+F7::
{
    GatherCascadesToCommandMonitor()
    KeyWait "F7"
}

#HotIf !IsCapsLockLayerRunning() && !ActiveWindowBlocksCascadeHotkeys() && rotate_key = "Space"
<^<!Space::
{
    RotateCascadeLayers(1)
    KeyWait "Space"
}

#HotIf !IsCapsLockLayerRunning() && !ActiveWindowBlocksCascadeHotkeys() && rotate_key = "Tab"
<^<!Tab::
{
    RotateCascadeLayers(1)
    KeyWait "Tab"
}

#HotIf


IsCapsLockLayerRunning()
{
    static SYNCHRONIZE := 0x00100000

    mutex_handle := DllCall(
        "OpenMutex",
        "uint", SYNCHRONIZE,
        "int", false,
        "str", "Local\WindowCascade.CapsLockLayer",
        "ptr"
    )

    if !mutex_handle
        return false

    DllCall("CloseHandle", "ptr", mutex_handle)
    return true
}

ActiveWindowBlocksCascadeHotkeys()
{
    active_hwnd := WinExist("A")

    if !active_hwnd
        return false

    try {
        ; Maximized windows are intentionally outside cascade management.
        if WinGetMinMax("ahk_id " active_hwnd) = 1
            return true

        WinGetPos(
            &window_x,
            &window_y,
            &window_width,
            &window_height,
            "ahk_id " active_hwnd
        )
    }
    catch {
        return false
    }

    window_right := window_x + window_width
    window_bottom := window_y + window_height
    tolerance_px := 2

    ; Borderless/exclusive fullscreen normally covers one monitor exactly.
    Loop MonitorGetCount() {
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
; desktop monitor selection
; =============================================================================

; Do not rely on foreground timing here. Windows may keep Progman focused while
; the user clicks between monitors, or may update foreground focus after the
; mouse-up event. Inspect the actual window under the cursor instead.
~LButton Up::CaptureDesktopMonitorHint()

CaptureDesktopMonitorHint()
{
    global desktop_monitor_hint, desktop_monitor_hint_tick

    MouseGetPos(&mouse_x, &mouse_y, &hover_hwnd)

    if !hover_hwnd
        return

    root_hwnd := DllCall(
        "GetAncestor",
        "ptr", hover_hwnd,
        "uint", 2, ; GA_ROOT
        "ptr"
    )

    if !IsDesktopSurfaceWindow(hover_hwnd)
        && !IsDesktopSurfaceWindow(root_hwnd)
        return

    monitor_index := GetMonitorForPoint(mouse_x, mouse_y)

    if !monitor_index
        return

    desktop_monitor_hint := monitor_index
    desktop_monitor_hint_tick := A_TickCount

}


; =============================================================================
; optional caps lock layer integration
; =============================================================================

RegisterIntegrationMessages()
{
    global cascade_command_message

    cascade_command_message := DllCall(
        "RegisterWindowMessage",
        "str", "WindowCascade.Command",
        "uint"
    )

    OnMessage(cascade_command_message, HandleCascadeCommandMessage)
}

HandleCascadeCommandMessage(command_id, parameter, message_id, target_hwnd)
{
    global cascade_command_focus_previous, cascade_command_focus_next
    global cascade_command_rotate_slot_previous, cascade_command_rotate_slot_next
    global cascade_command_swap_window_up, cascade_command_swap_window_down
    global cascade_command_adopt_active, cascade_command_rotate_layers
    global cascade_command_toggle_minimize, cascade_command_bring_forward
    global cascade_command_close_active, cascade_command_close_scope
    global cascade_command_gather_to_monitor, cascade_command_show_help

    ; HWND_BROADCAST also reaches script-owned GUIs. Run each command only
    ; once through AutoHotkey's hidden main window.
    if target_hwnd != A_ScriptHwnd
        return

    if ActiveWindowBlocksCascadeHotkeys()
        return

    switch command_id {
        case cascade_command_focus_previous:
            FocusCascadeLayerWindow(-1)

        case cascade_command_focus_next:
            FocusCascadeLayerWindow(1)

        case cascade_command_rotate_slot_previous:
            RotateCurrentCascadeSlot(-1)

        case cascade_command_rotate_slot_next:
            RotateCurrentCascadeSlot(1)

        case cascade_command_swap_window_up:
            SwapActiveCascadeWindow(-1)

        case cascade_command_swap_window_down:
            SwapActiveCascadeWindow(1)

        case cascade_command_adopt_active:
            AdoptActiveWindow()

        case cascade_command_rotate_layers:
            RotateCascadeLayers(1)

        case cascade_command_toggle_minimize:
            if parameter
                ToggleCommandMonitorCascadeMinimize()
            else
                ToggleCurrentCascadeLayerMinimize()

        case cascade_command_bring_forward:
            BringCommandMonitorCascadeForward()

        case cascade_command_close_active:
            Send "!{F4}"

        case cascade_command_close_scope:
            if parameter
                CloseCommandMonitorCascade()
            else
                CloseCurrentCascadeLayer()

        case cascade_command_gather_to_monitor:
            GatherCascadesToCommandMonitor()

        case cascade_command_show_help:
            ToggleWindowCascadeHelp()
    }
}

GetManagedCascadeMonitor(hwnd)
{
    global cascade_history

    for monitor_index, history in cascade_history {
        for managed_hwnd in history {
            if managed_hwnd = hwnd
                return monitor_index
        }
    }

    return 0
}

RemoveCascadeWindowFromHistory(hwnd)
{
    global cascade_history

    for monitor_index, history in cascade_history {
        index := history.Length

        while index >= 1 {
            if history[index] = hwnd
                history.RemoveAt(index)

            index -= 1
        }
    }
}

IsWindowInCascadeLayout(hwnd)
{
    global cascade_release_tolerance

    if !hwnd || !WinExist("ahk_id " hwnd)
        return false

    stacks := BuildCascadeSlotStacks(
        [hwnd],
        cascade_release_tolerance
    )

    return stacks.Length > 0
}

AdoptActiveWindow()
{
    hwnd := WinExist("A")

    if !hwnd || IsShellSurfaceWindow(hwnd)
        return

    target_monitor := GetMonitorForWindow(hwnd)

    if target_monitor
        PlaceCascadeWindowOnMonitor(hwnd, target_monitor)
}

PlaceCascadeWindowOnMonitor(hwnd, target_monitor)
{
    global handled_windows, known_windows
    global window_width_ratio, window_height_ratio
    global edge_margin, minimum_width, minimum_height

    if !hwnd || !target_monitor || !WinExist("ahk_id " hwnd)
        return false

    window := "ahk_id " hwnd
    previous_monitor := GetManagedCascadeMonitor(hwnd)

    try {
        ; Explicit adoption/gathering is allowed to restore a window before
        ; applying canonical cascade geometry on the destination monitor.
        if WinGetMinMax(window) != 0
            WinRestore(window)

        if !IsCascadeWindow(hwnd)
            return false

        MonitorGetWorkArea(
            target_monitor,
            &work_left,
            &work_top,
            &work_right,
            &work_bottom
        )

        work_width := work_right - work_left
        work_height := work_bottom - work_top

        window_width := Floor(work_width * window_width_ratio)
        window_height := Floor(work_height * window_height_ratio)

        window_width := Max(minimum_width, window_width)
        window_height := Max(minimum_height, window_height)

        window_width := Min(
            window_width,
            work_width - edge_margin * 2
        )

        window_height := Min(
            window_height,
            work_height - edge_margin * 2
        )

        ; Exclude this window before choosing a destination. The normal
        ; least-used-slot allocator then fills the current layer first.
        RemoveCascadeWindowFromHistory(hwnd)

        position := GetNextCascadePosition(
            target_monitor,
            work_left,
            work_top,
            work_right,
            work_bottom,
            window_width,
            window_height
        )

        target_x := position[1]
        target_y := position[2]

        raw_target := GetRawRectForVisibleTarget(
            hwnd,
            target_x,
            target_y,
            window_width,
            window_height
        )

        WinMove(
            raw_target[1],
            raw_target[2],
            raw_target[3],
            raw_target[4],
            window
        )

        handled_windows[hwnd] := true
        known_windows[hwnd] := true

        RecordCascadeWindow(target_monitor, hwnd)

        SchedulePlacementStabilization(
            hwnd,
            target_x,
            target_y,
            window_width,
            window_height
        )

        if previous_monitor && previous_monitor != target_monitor
            QueueCascadeCompaction(previous_monitor)

        return true
    }
    catch Error as err {
        error_number := 0

        try
            error_number := err.Number

        if err.What = "WinMove" && error_number = 5 {
            handled_windows[hwnd] := true
            known_windows[hwnd] := true
        }

        ; A failed re-slot/gather must not silently drop an already managed
        ; window from its original monitor history.
        if previous_monitor
            && !GetManagedCascadeMonitor(hwnd)
            && WinExist("ahk_id " hwnd)
        {
            RecordCascadeWindow(previous_monitor, hwnd)
        }

        return false
    }
}

GatherCascadesToCommandMonitor()
{
    global cascade_history
    global layer_minimized_windows_by_monitor
    global monitor_minimized_windows_by_monitor

    target_monitor := GetCommandMonitor()

    if !target_monitor
        return

    windows_to_gather := []
    source_monitors := Map()
    seen := Map()

    ; Snapshot source histories first because successful placement moves each
    ; window into the destination history.
    for monitor_index, history in cascade_history {
        if monitor_index = target_monitor
            continue

        source_monitors[monitor_index] := true

        for hwnd in history {
            if seen.Has(hwnd) || !WinExist("ahk_id " hwnd)
                continue

            seen[hwnd] := true
            windows_to_gather.Push(hwnd)
        }
    }

    if windows_to_gather.Length = 0
        return

    ; Restore script-hidden destination layers before counting occupancy so
    ; imported windows fill the real current layer instead of overlapping it.
    if monitor_minimized_windows_by_monitor.Has(target_monitor) {
        RestoreCascadeWindows(
            monitor_minimized_windows_by_monitor[target_monitor]
        )
        monitor_minimized_windows_by_monitor.Delete(target_monitor)
    }

    if layer_minimized_windows_by_monitor.Has(target_monitor) {
        RestoreCascadeWindows(
            layer_minimized_windows_by_monitor[target_monitor]
        )
        layer_minimized_windows_by_monitor.Delete(target_monitor)
    }

    for hwnd in windows_to_gather
        PlaceCascadeWindowOnMonitor(hwnd, target_monitor)

    ; Every managed source window was gathered, so old per-monitor restore
    ; state must not retain handles that now belong to the destination monitor.
    for monitor_index in source_monitors {
        if layer_minimized_windows_by_monitor.Has(monitor_index)
            layer_minimized_windows_by_monitor.Delete(monitor_index)

        if monitor_minimized_windows_by_monitor.Has(monitor_index)
            monitor_minimized_windows_by_monitor.Delete(monitor_index)
    }

    BringCascadeForward(target_monitor)
    QueueFocusCornerUpdate()
}

GetCommandMonitor()
{
    active_hwnd := WinExist("A")

    if active_hwnd
        && !IsShellSurfaceWindow(active_hwnd)
    {
        monitor_index := GetMonitorForWindow(active_hwnd)

        if monitor_index
            return monitor_index
    }

    MouseGetPos(&mouse_x, &mouse_y)
    return GetMonitorForPoint(mouse_x, mouse_y)
}

GetCascadeSlotStacksForMonitor(monitor_index)
{
    global cascade_slot_tolerance

    windows := GetLiveCascadeHistory(monitor_index)

    if windows.Length = 0
        return []

    return BuildCascadeSlotStacks(
        windows,
        cascade_slot_tolerance
    )
}

GetCurrentCascadeLayerWindows(monitor_index)
{
    stacks := GetCascadeSlotStacksForMonitor(monitor_index)

    if stacks.Length = 0
        return []

    z_ranks := GetCascadeWindowZRanks()
    layer_windows := []

    for stack_info in stacks {
        ordered_stack := SortCascadeWindowsByZOrder(
            stack_info["windows"],
            z_ranks
        )

        if ordered_stack.Length
            layer_windows.Push(ordered_stack[1])
    }

    return GetSpatialCascadeOrder(layer_windows)
}

FocusCascadeLayerWindow(direction)
{
    monitor_index := GetCommandMonitor()

    if !monitor_index
        return

    ordered_windows := GetCurrentCascadeLayerWindows(monitor_index)

    if ordered_windows.Length = 0
        return

    active_hwnd := WinExist("A")
    active_index := 0

    Loop ordered_windows.Length {
        if ordered_windows[A_Index] = active_hwnd {
            active_index := A_Index
            break
        }
    }

    if active_index {
        target_index := active_index + (direction < 0 ? -1 : 1)

        if target_index < 1
            target_index := ordered_windows.Length
        else if target_index > ordered_windows.Length
            target_index := 1

        ActivateCascadeWindow(ordered_windows[target_index])
        return
    }

    ; If focus is outside the exposed layer, enter at the nearest window
    ; physically above/below the active window.
    target_hwnd := GetNearestSpatialCascadeWindow(
        ordered_windows,
        active_hwnd,
        direction
    )

    if target_hwnd
        ActivateCascadeWindow(target_hwnd)
}

SwapActiveCascadeWindow(direction)
{
    active_hwnd := WinExist("A")

    if !active_hwnd || IsShellSurfaceWindow(active_hwnd)
        return

    monitor_index := GetMonitorForWindow(active_hwnd)

    if !monitor_index
        return

    ordered_windows := GetCurrentCascadeLayerWindows(monitor_index)

    if ordered_windows.Length < 2
        return

    active_index := 0

    Loop ordered_windows.Length {
        if ordered_windows[A_Index] = active_hwnd {
            active_index := A_Index
            break
        }
    }

    ; Only an exposed current-layer window can move between slots.
    if !active_index
        return

    target_index := active_index + (direction < 0 ? -1 : 1)

    if target_index < 1
        target_index := ordered_windows.Length
    else if target_index > ordered_windows.Length
        target_index := 1

    target_hwnd := ordered_windows[target_index]

    if !TryGetVisibleFrameRect(
        active_hwnd,
        &active_x,
        &active_y,
        &active_width,
        &active_height,
        &active_inset_left,
        &active_inset_top,
        &active_inset_right,
        &active_inset_bottom
    ) {
        return
    }

    if !TryGetVisibleFrameRect(
        target_hwnd,
        &target_x,
        &target_y,
        &target_width,
        &target_height,
        &target_inset_left,
        &target_inset_top,
        &target_inset_right,
        &target_inset_bottom
    ) {
        return
    }

    ; Swap only the two exposed layer windows. Deeper windows remain in place.
    if !MoveCascadeWindowToSlot(target_hwnd, active_x, active_y)
        return

    if !MoveCascadeWindowToSlot(active_hwnd, target_x, target_y) {
        MoveCascadeWindowToSlot(target_hwnd, target_x, target_y)
        return
    }

    ; Keep both swapped windows above the deeper layers in their new slots,
    ; while preserving focus on the active window.
    z_flags := (
        0x0001  ; SWP_NOSIZE
        | 0x0002  ; SWP_NOMOVE
        | 0x0010  ; SWP_NOACTIVATE
        | 0x0200  ; SWP_NOOWNERZORDER
    )

    try DllCall(
        "SetWindowPos",
        "ptr", target_hwnd,
        "ptr", active_hwnd,
        "int", 0,
        "int", 0,
        "int", 0,
        "int", 0,
        "uint", z_flags,
        "int"
    )

    QueueFocusCornerUpdate()
}

MoveCascadeWindowToSlot(hwnd, target_x, target_y)
{
    if !TryGetVisibleFrameRect(
        hwnd,
        &current_x,
        &current_y,
        &current_width,
        &current_height,
        &inset_left,
        &inset_top,
        &inset_right,
        &inset_bottom
    ) {
        return false
    }

    raw_target := GetRawRectForVisibleTarget(
        hwnd,
        target_x,
        target_y,
        current_width,
        current_height
    )

    try {
        WinMove(
            raw_target[1],
            raw_target[2],
            raw_target[3],
            raw_target[4],
            "ahk_id " hwnd
        )
    }
    catch {
        return false
    }

    return true
}

RotateCurrentCascadeSlot(direction)
{
    active_hwnd := WinExist("A")

    if !active_hwnd || IsShellSurfaceWindow(active_hwnd)
        return

    monitor_index := GetMonitorForWindow(active_hwnd)

    if !monitor_index
        return

    stacks := GetCascadeSlotStacksForMonitor(monitor_index)
    z_ranks := GetCascadeWindowZRanks()

    for stack_info in stacks {
        ordered_stack := SortCascadeWindowsByZOrder(
            stack_info["windows"],
            z_ranks
        )

        ; The focused window must be the exposed member of this slot.
        if ordered_stack.Length < 2 || ordered_stack[1] != active_hwnd
            continue

        next_hwnd := RotateCascadeStackWindows(
            ordered_stack,
            direction
        )

        if next_hwnd
            ActivateCascadeWindow(next_hwnd)

        QueueFocusCornerUpdate()
        return
    }
}

RotateCascadeStackWindows(ordered_windows, direction)
{
    if ordered_windows.Length < 2
        return 0

    flags := (
        0x0001  ; SWP_NOSIZE
        | 0x0002  ; SWP_NOMOVE
        | 0x0010  ; SWP_NOACTIVATE
        | 0x0200  ; SWP_NOOWNERZORDER
    )

    try {
        if direction < 0 {
            ; Previous layer: bring the deepest window to the front.
            target_hwnd := ordered_windows[ordered_windows.Length]

            succeeded := DllCall(
                "SetWindowPos",
                "ptr", target_hwnd,
                "ptr", 0, ; HWND_TOP
                "int", 0,
                "int", 0,
                "int", 0,
                "int", 0,
                "uint", flags,
                "int"
            )

            return succeeded ? target_hwnd : 0
        }

        ; Next layer: move the exposed window behind the deepest window.
        current_hwnd := ordered_windows[1]
        deepest_hwnd := ordered_windows[ordered_windows.Length]

        succeeded := DllCall(
            "SetWindowPos",
            "ptr", current_hwnd,
            "ptr", deepest_hwnd,
            "int", 0,
            "int", 0,
            "int", 0,
            "int", 0,
            "uint", flags,
            "int"
        )

        return succeeded ? ordered_windows[2] : 0
    }
    catch {
        return 0
    }
}

GetSpatialCascadeOrder(windows)
{
    spatial_items := []

    ; History order is the final stable tie-breaker when windows occupy the
    ; exact same physical position.
    for history_index, hwnd in windows {
        if !TryGetWindowCenter(hwnd, &center_x, &center_y)
            continue

        item := Map(
            "hwnd", hwnd,
            "center_x", center_x,
            "center_y", center_y,
            "history_index", history_index
        )

        insert_index := spatial_items.Length + 1

        Loop spatial_items.Length {
            existing := spatial_items[A_Index]

            if SpatialItemComesBefore(item, existing) {
                insert_index := A_Index
                break
            }
        }

        spatial_items.InsertAt(insert_index, item)
    }

    ordered_windows := []

    for item in spatial_items
        ordered_windows.Push(item["hwnd"])

    return ordered_windows
}

SpatialItemComesBefore(item, existing)
{
    if item["center_y"] != existing["center_y"]
        return item["center_y"] < existing["center_y"]

    if item["center_x"] != existing["center_x"]
        return item["center_x"] < existing["center_x"]

    return item["history_index"] < existing["history_index"]
}

GetNearestSpatialCascadeWindow(
    ordered_windows,
    active_hwnd,
    direction
)
{
    if active_hwnd
        && WinExist("ahk_id " active_hwnd)
        && TryGetWindowCenter(
            active_hwnd,
            &active_center_x,
            &active_center_y
        )
    {
        target_hwnd := 0
        best_distance := 0

        for hwnd in ordered_windows {
            if !TryGetWindowCenter(hwnd, &center_x, &center_y)
                continue

            vertical_delta := center_y - active_center_y

            if direction < 0 {
                if vertical_delta >= 0
                    continue

                distance := -vertical_delta
            } else {
                if vertical_delta <= 0
                    continue

                distance := vertical_delta
            }

            if !target_hwnd || distance < best_distance {
                target_hwnd := hwnd
                best_distance := distance
            }
        }

        if target_hwnd
            return target_hwnd
    }

    ; No window remains in the requested direction, so wrap.
    return (
        direction < 0
        ? ordered_windows[ordered_windows.Length]
        : ordered_windows[1]
    )
}

TryGetWindowCenter(hwnd, &center_x, &center_y)
{
    if !TryGetVisibleFrameRect(
        hwnd,
        &x,
        &y,
        &width,
        &height,
        &inset_left,
        &inset_top,
        &inset_right,
        &inset_bottom
    ) {
        return false
    }

    center_x := x + width / 2
    center_y := y + height / 2

    return true
}

ActivateCascadeWindow(hwnd)
{
    if !hwnd
        return

    try {
        if WinGetMinMax("ahk_id " hwnd) = -1
            WinRestore("ahk_id " hwnd)

        WinActivate("ahk_id " hwnd)
    }
    catch {
        return
    }
}

BringCommandMonitorCascadeForward()
{
    monitor_index := GetCommandMonitor()

    if !monitor_index
        return

    BringCascadeForward(monitor_index)
}

BringCascadeForward(monitor_index)
{
    windows := GetLiveCascadeHistory(monitor_index)

    if windows.Length = 0
        return

    z_ranks := GetCascadeWindowZRanks()

    ordered_windows := SortCascadeWindowsByZOrder(
        windows,
        z_ranks
    )

    visible_windows := []

    for hwnd in ordered_windows {
        if !WinExist("ahk_id " hwnd)
            continue

        try {
            if WinGetMinMax("ahk_id " hwnd) = -1
                continue
        }
        catch {
            continue
        }

        visible_windows.Push(hwnd)
    }

    if visible_windows.Length = 0
        return

    last_used_hwnd := visible_windows[1]

    flags := (
        0x0001  ; SWP_NOSIZE
        | 0x0002  ; SWP_NOMOVE
        | 0x0010  ; SWP_NOACTIVATE
        | 0x0200  ; SWP_NOOWNERZORDER
    )

    ; Temporarily promote the whole cascade into the topmost band. Process
    ; bottom-to-top so its existing internal Z-order is preserved.
    index := visible_windows.Length

    while index >= 1 {
        hwnd := visible_windows[index]

        try DllCall(
            "SetWindowPos",
            "ptr", hwnd,
            "ptr", -1, ; HWND_TOPMOST
            "int", 0,
            "int", 0,
            "int", 0,
            "int", 0,
            "uint", flags,
            "int"
        )

        index -= 1
    }

    ; Immediately return the group to the normal Z band. Doing this in the
    ; same bottom-to-top order keeps every cascade window above unrelated
    ; normal windows without leaving the cascade always-on-top.
    index := visible_windows.Length

    while index >= 1 {
        hwnd := visible_windows[index]

        try DllCall(
            "SetWindowPos",
            "ptr", hwnd,
            "ptr", -2, ; HWND_NOTOPMOST
            "int", 0,
            "int", 0,
            "int", 0,
            "int", 0,
            "uint", flags,
            "int"
        )

        index -= 1
    }

    ActivateCascadeWindow(last_used_hwnd)
}

RotateCascadeLayers(direction := 1)
{
    monitor_index := GetCommandMonitor()

    if !monitor_index
        return

    stacks := GetCascadeSlotStacksForMonitor(monitor_index)

    if stacks.Length = 0
        return

    z_ranks := GetCascadeWindowZRanks()
    active_hwnd := WinExist("A")
    next_active_hwnd := 0

    for stack_info in stacks {
        ordered_stack := SortCascadeWindowsByZOrder(
            stack_info["windows"],
            z_ranks
        )

        if ordered_stack.Length < 2
            continue

        was_active := ordered_stack[1] = active_hwnd
        new_top_hwnd := RotateCascadeStackWindows(
            ordered_stack,
            direction
        )

        if was_active && new_top_hwnd
            next_active_hwnd := new_top_hwnd
    }

    if next_active_hwnd
        ActivateCascadeWindow(next_active_hwnd)

    QueueFocusCornerUpdate()
}

BuildCascadeSlotStacks(windows, tolerance)
{
    global window_width_ratio, window_height_ratio
    global edge_margin, minimum_width, minimum_height

    stacks := []
    stacks_by_slot := Map()

    for hwnd in windows {
        try {
            if WinGetMinMax("ahk_id " hwnd) = -1
                continue

            monitor_index := GetMonitorForWindow(hwnd)

            if !monitor_index
                continue

            MonitorGetWorkArea(
                monitor_index,
                &work_left,
                &work_top,
                &work_right,
                &work_bottom
            )

            work_width := work_right - work_left
            work_height := work_bottom - work_top

            canonical_width := Floor(
                work_width * window_width_ratio
            )

            canonical_height := Floor(
                work_height * window_height_ratio
            )

            canonical_width := Max(
                minimum_width,
                canonical_width
            )

            canonical_height := Max(
                minimum_height,
                canonical_height
            )

            canonical_width := Min(
                canonical_width,
                work_width - edge_margin * 2
            )

            canonical_height := Min(
                canonical_height,
                work_height - edge_margin * 2
            )

            slots := BuildCascadeSlots(
                work_left,
                work_top,
                work_right,
                work_bottom,
                canonical_width,
                canonical_height
            )

            if !TryGetVisibleFrameRect(
                hwnd,
                &window_x,
                &window_y,
                &window_width,
                &window_height,
                &window_inset_left,
                &window_inset_top,
                &window_inset_right,
                &window_inset_bottom
            ) {
                continue
            }
        }
        catch {
            continue
        }

        best_slot_index := FindNearestCascadeSlot(
            window_x,
            window_y,
            slots,
            tolerance
        )

        ; A manually moved window that is no longer near a canonical slot does
        ; not belong to any stack.
        if !best_slot_index
            continue

        stack_key :=
            monitor_index
            . ":"
            . best_slot_index

        if stacks_by_slot.Has(stack_key) {
            stacks_by_slot[stack_key]["windows"].Push(hwnd)
            continue
        }

        stack_info := Map(
            "slot_index", best_slot_index,
            "windows", [hwnd]
        )

        stacks_by_slot[stack_key] := stack_info
        stacks.Push(stack_info)
    }

    return stacks
}

QueueCascadeCompaction(monitor_index)
{
    global cascade_compaction_pending

    if !monitor_index
        return

    cascade_compaction_pending[monitor_index] := true

    ; Batch closes/destruction into one final compaction.
    SetTimer FlushCascadeCompactions, -120
}

FlushCascadeCompactions()
{
    global cascade_compaction_pending

    monitors := []

    for monitor_index in cascade_compaction_pending
        monitors.Push(monitor_index)

    cascade_compaction_pending := Map()

    for monitor_index in monitors
        CompactCascadeLayout(monitor_index)
}

CompactCascadeLayout(monitor_index)
{
    global cascade_slot_tolerance
    global layer_minimized_windows_by_monitor
    global monitor_minimized_windows_by_monitor
    global window_width_ratio, window_height_ratio
    global edge_margin, minimum_width, minimum_height

    ; A fully hidden monitor has nothing visible to compact.
    if monitor_minimized_windows_by_monitor.Has(monitor_index)
        return

    windows := GetLiveCascadeHistory(monitor_index)

    ; Keep a script-hidden layer out of compaction while packing the layers
    ; that remain visible. Restoring the hidden layer compacts everything.
    if layer_minimized_windows_by_monitor.Has(monitor_index) {
        visible_windows := []

        for hwnd in windows {
            try {
                if WinGetMinMax("ahk_id " hwnd) = -1
                    continue
            }
            catch {
                continue
            }

            visible_windows.Push(hwnd)
        }

        windows := visible_windows
    }

    if windows.Length = 0
        return

    stacks := BuildCascadeSlotStacks(
        windows,
        cascade_slot_tolerance
    )

    if stacks.Length = 0
        return

    MonitorGetWorkArea(
        monitor_index,
        &work_left,
        &work_top,
        &work_right,
        &work_bottom
    )

    work_width := work_right - work_left
    work_height := work_bottom - work_top

    window_width := Max(
        minimum_width,
        Floor(work_width * window_width_ratio)
    )

    window_height := Max(
        minimum_height,
        Floor(work_height * window_height_ratio)
    )

    window_width := Min(
        window_width,
        work_width - edge_margin * 2
    )

    window_height := Min(
        window_height,
        work_height - edge_margin * 2
    )

    slots := BuildCascadeSlots(
        work_left,
        work_top,
        work_right,
        work_bottom,
        window_width,
        window_height
    )

    if slots.Length = 0
        return

    z_ranks := GetCascadeWindowZRanks()
    stacks_by_slot := Map()
    maximum_depth := 0

    for stack_info in stacks {
        ordered_stack := SortCascadeWindowsByZOrder(
            stack_info["windows"],
            z_ranks
        )

        stacks_by_slot[stack_info["slot_index"]] := ordered_stack
        maximum_depth := Max(maximum_depth, ordered_stack.Length)
    }

    ; Read the current cascade layer-first and slot-first. Repacking this order
    ; makes every earlier slot/layer dense without changing layer order.
    ordered_windows := []

    Loop maximum_depth {
        layer_index := A_Index

        Loop slots.Length {
            slot_index := A_Index

            if !stacks_by_slot.Has(slot_index)
                continue

            stack_windows := stacks_by_slot[slot_index]

            if layer_index <= stack_windows.Length
                ordered_windows.Push(stack_windows[layer_index])
        }
    }

    target_stacks := []

    Loop slots.Length
        target_stacks.Push([])

    for linear_index, hwnd in ordered_windows {
        target_slot_index := Mod(linear_index - 1, slots.Length) + 1
        target_slot := slots[target_slot_index]

        MoveCascadeWindowToSlot(
            hwnd,
            target_slot[1],
            target_slot[2]
        )

        target_stacks[target_slot_index].Push(hwnd)
    }

    ; Keep each target stack in the same top-to-bottom layer order.
    z_flags := (
        0x0001  ; SWP_NOSIZE
        | 0x0002  ; SWP_NOMOVE
        | 0x0010  ; SWP_NOACTIVATE
        | 0x0200  ; SWP_NOOWNERZORDER
    )

    for stack_windows in target_stacks {
        if stack_windows.Length < 2
            continue

        Loop stack_windows.Length - 1 {
            upper_hwnd := stack_windows[A_Index]
            lower_hwnd := stack_windows[A_Index + 1]

            try DllCall(
                "SetWindowPos",
                "ptr", lower_hwnd,
                "ptr", upper_hwnd,
                "int", 0,
                "int", 0,
                "int", 0,
                "int", 0,
                "uint", z_flags,
                "int"
            )
        }
    }

    QueueFocusCornerUpdate()
}

GetCascadeWindowZRanks()
{
    ranks := Map()

    ; WinGetList returns top-level windows in Z-order.
    for rank, hwnd in WinGetList()
        ranks[hwnd] := rank

    return ranks
}

SortCascadeWindowsByZOrder(windows, ranks)
{
    ordered_windows := []

    for hwnd in windows {
        rank := (
            ranks.Has(hwnd)
            ? ranks[hwnd]
            : 2147483647
        )

        insert_index := ordered_windows.Length + 1

        Loop ordered_windows.Length {
            existing_hwnd := ordered_windows[A_Index]

            existing_rank := (
                ranks.Has(existing_hwnd)
                ? ranks[existing_hwnd]
                : 2147483647
            )

            if rank < existing_rank {
                insert_index := A_Index
                break
            }
        }

        ordered_windows.InsertAt(insert_index, hwnd)
    }

    return ordered_windows
}
GetLiveCascadeHistory(monitor_index)
{
    global cascade_history

    live_history := []

    if !cascade_history.Has(monitor_index)
        return live_history

    previous_count := cascade_history[monitor_index].Length

    for hwnd in cascade_history[monitor_index] {
        if !WinExist("ahk_id " hwnd)
            continue

        ; A minimized window has no useful cascade geometry. Keep its recorded
        ; membership so restoring it does not silently remove it from history.
        try {
            if WinGetMinMax("ahk_id " hwnd) = -1 {
                live_history.Push(hwnd)
                continue
            }
        }
        catch {
            continue
        }

        if GetMonitorForWindow(hwnd) != monitor_index
            continue

        if !IsWindowInCascadeLayout(hwnd)
            continue

        live_history.Push(hwnd)
    }

    cascade_history[monitor_index] := live_history

    if live_history.Length < previous_count
        QueueCascadeCompaction(monitor_index)

    return live_history
}


; =============================================================================
; window discovery and placement queue
; =============================================================================

SeedStartupWindows()
{
    global startup_windows, known_windows

    startup_windows := Map()
    known_windows := Map()

    for hwnd in WinGetList() {
        startup_windows[hwnd] := true
        known_windows[hwnd] := true
    }

}

QueueWindowPlacement(hwnd, source_hwnd)
{
    global pending_windows, known_windows, placement_delay_ms

    ; Once any discovery path adopts an HWND, the polling fallback no longer
    ; needs to rediscover the same window.
    known_windows[hwnd] := true


    pending_windows[hwnd] := true

    ; Snapshot once here. Readiness retries and settling reuse this monitor
    ; instead of sampling a later mouse position.
    MouseGetPos(&queue_mouse_x, &queue_mouse_y)
    queued_monitor := GetMonitorForPoint(
        queue_mouse_x,
        queue_mouse_y
    )

    DebugLog(
        "Queue placement."
        . " | target=" DebugDescribeWindow(hwnd)
        . " | source=" DebugDescribeWindow(source_hwnd)
        . " | queued-monitor=" queued_monitor
        . " | mouse=(" queue_mouse_x "," queue_mouse_y ")"
    )


    SetTimer(
        PlaceNewWindow.Bind(
            hwnd,
            source_hwnd,
            queued_monitor
        ),
        -placement_delay_ms
    )
}

WatchForMissedWindows()
{
    global known_windows
    global pending_windows, handled_windows
    global current_foreground_hwnd, previous_foreground_hwnd
    global placement_enabled

    for hwnd in WinGetList() {
        if known_windows.Has(hwnd)
            continue

        ; Record the HWND immediately. Rejected helper windows should not be
        ; reconsidered every polling cycle.
        known_windows[hwnd] := true

        DebugLog(
            "Poll discovered HWND."
            . " | " DebugDescribeWindow(hwnd)
        )

        if !placement_enabled
            continue

        if pending_windows.Has(hwnd) || handled_windows.Has(hwnd)
            continue

        if !IsPlausibleTopLevelWindow(hwnd) {
            DebugLog(
                "Poll rejected by top-level prefilter."
                . " | " DebugDescribeWindow(hwnd)
            )
            continue
        }

        source_hwnd := current_foreground_hwnd

        if source_hwnd = hwnd
            source_hwnd := previous_foreground_hwnd


        QueueWindowPlacement(hwnd, source_hwnd)
    }
}

TryQueueForegroundFallback(hwnd)
{
    global startup_windows
    global pending_windows, handled_windows
    global previous_foreground_hwnd
    global placement_enabled

    if !hwnd
        return

    ; Never adopt a window merely because it was already open when this script
    ; started.
    if startup_windows.Has(hwnd)
        return

    if !placement_enabled
        return

    if pending_windows.Has(hwnd) || handled_windows.Has(hwnd)
        return

    if !IsPlausibleTopLevelWindow(hwnd)
        return

    source_hwnd := previous_foreground_hwnd

    if source_hwnd = hwnd
        source_hwnd := 0


    QueueWindowPlacement(hwnd, source_hwnd)
}


; =============================================================================
; windows event hooks
; =============================================================================

StartWindowHooks()
{
    global win_event_callback
    global foreground_hook, window_show_hook, window_destroy_hook

    EVENT_SYSTEM_FOREGROUND := 0x0003
    EVENT_OBJECT_DESTROY := 0x8001
    EVENT_OBJECT_SHOW := 0x8002

    WINEVENT_OUTOFCONTEXT := 0x0000
    WINEVENT_SKIPOWNPROCESS := 0x0002
    flags := WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS

    win_event_callback := CallbackCreate(HandleWinEvent)

    foreground_hook := DllCall(
        "SetWinEventHook",
        "uint", EVENT_SYSTEM_FOREGROUND,
        "uint", EVENT_SYSTEM_FOREGROUND,
        "ptr", 0,
        "ptr", win_event_callback,
        "uint", 0,
        "uint", 0,
        "uint", flags,
        "ptr"
    )


    window_show_hook := DllCall(
        "SetWinEventHook",
        "uint", EVENT_OBJECT_SHOW,
        "uint", EVENT_OBJECT_SHOW,
        "ptr", 0,
        "ptr", win_event_callback,
        "uint", 0,
        "uint", 0,
        "uint", flags,
        "ptr"
    )


    window_destroy_hook := DllCall(
        "SetWinEventHook",
        "uint", EVENT_OBJECT_DESTROY,
        "uint", EVENT_OBJECT_DESTROY,
        "ptr", 0,
        "ptr", win_event_callback,
        "uint", 0,
        "uint", 0,
        "uint", flags,
        "ptr"
    )

    if !foreground_hook || !window_show_hook || !window_destroy_hook {

        MsgBox(
            "Could not install all Windows event hooks.`n`n"
            . "Window Cascade may not detect new windows correctly.",
            "Window Cascade",
            "Iconx"
        )
    }
}

StopWindowHooks()
{
    global win_event_callback
    global foreground_hook, window_show_hook, window_destroy_hook

    SetTimer(WatchForMissedWindows, 0)
    SetTimer(UpdateFocusCornerOverlays, 0)
    SetTimer(RunQueuedFocusCornerUpdate, 0)


    if foreground_hook {
        DllCall("UnhookWinEvent", "ptr", foreground_hook)
        foreground_hook := 0
    }

    if window_show_hook {
        DllCall("UnhookWinEvent", "ptr", window_show_hook)
        window_show_hook := 0
    }

    if window_destroy_hook {
        DllCall("UnhookWinEvent", "ptr", window_destroy_hook)
        window_destroy_hook := 0
    }

    if win_event_callback {
        CallbackFree(win_event_callback)
        win_event_callback := 0
    }
}

HandleWinEvent(
    hook_handle,
    event,
    hwnd,
    object_id,
    child_id,
    event_thread,
    event_time
)
{
    global current_foreground_hwnd, previous_foreground_hwnd
    global pending_windows, handled_windows
    global startup_windows
    global placement_enabled
    global desktop_monitor_hint, desktop_monitor_hint_tick

    try {
        EVENT_SYSTEM_FOREGROUND := 0x0003
        EVENT_OBJECT_DESTROY := 0x8001
        EVENT_OBJECT_SHOW := 0x8002
        OBJID_WINDOW := 0
        CHILDID_SELF := 0

        if event = EVENT_SYSTEM_FOREGROUND {
            if hwnd && hwnd != current_foreground_hwnd {
                previous_foreground_hwnd := current_foreground_hwnd
                current_foreground_hwnd := hwnd

                DebugLog(
                    "Foreground changed."
                    . " | current=" DebugDescribeWindow(hwnd)
                    . " | previous="
                    . DebugDescribeWindow(previous_foreground_hwnd)
                )

                if IsDesktopSurfaceWindow(hwnd) {
                    MouseGetPos(&mouse_x, &mouse_y)
                    monitor_index := GetMonitorForPoint(mouse_x, mouse_y)

                    if monitor_index {
                        desktop_monitor_hint := monitor_index
                        desktop_monitor_hint_tick := A_TickCount

                    }
                }
            }

            QueueFocusCornerUpdate()
            TryQueueForegroundFallback(hwnd)
            return
        }

        if object_id != OBJID_WINDOW || child_id != CHILDID_SELF || !hwnd
            return


        if event = EVENT_OBJECT_DESTROY {
            DebugLog(
                "Destroy event."
                . " | " DebugDescribeWindow(hwnd)
            )

            was_managed := !!GetManagedCascadeMonitor(hwnd)

            ForgetWindow(hwnd)

            if was_managed
                QueueFocusCornerUpdate()

            return
        }


        if event != EVENT_OBJECT_SHOW
            return

        if GetManagedCascadeMonitor(hwnd)
            QueueFocusCornerUpdate()

        DebugLog(
            "Show event."
            . " | pending=" pending_windows.Has(hwnd)
            . " | handled=" handled_windows.Has(hwnd)
            . " | " DebugDescribeWindow(hwnd)
        )

        ; EVENT_OBJECT_SHOW also fires when some existing minimized windows are
        ; restored. Only windows absent from the startup snapshot are new.
        if startup_windows.Has(hwnd) {
            DebugLog(
                "Show event skipped: window existed at script startup."
                . " | " DebugDescribeWindow(hwnd)
            )
            return
        }

        ; Cheap filtering here prevents Explorer controls, ribbon pieces,
        ; tooltips, and other child/helper windows from ever reaching the timer.
        if !IsPlausibleTopLevelWindow(hwnd)
            return


        if !placement_enabled {
            return
        }

        if pending_windows.Has(hwnd) {
            return
        }

        if handled_windows.Has(hwnd) {
            return
        }

        source_hwnd := current_foreground_hwnd

        ; If focus already moved to the new window, use the prior foreground window.
        if source_hwnd = hwnd
            source_hwnd := previous_foreground_hwnd

        DebugLog(
            "Show event accepted."
            . " | target=" DebugDescribeWindow(hwnd)
            . " | source=" DebugDescribeWindow(source_hwnd)
        )

        QueueWindowPlacement(hwnd, source_hwnd)
    }
    catch {
        return
    }
}

IsPlausibleTopLevelWindow(hwnd)
{
    if !hwnd
        return false

    if !DllCall("IsWindow", "ptr", hwnd, "int")
        return false

    ; Reject child controls before doing any higher-level AutoHotkey queries.
    root_hwnd := DllCall(
        "GetAncestor",
        "ptr", hwnd,
        "uint", 2, ; GA_ROOT
        "ptr"
    )

    if root_hwnd != hwnd
        return false

    try {
        style := WinGetStyle("ahk_id " hwnd)
        ex_style := WinGetExStyle("ahk_id " hwnd)
        window_class := WinGetClass("ahk_id " hwnd)
    }
    catch {
        return false
    }

    if style & 0x40000000 ; WS_CHILD
        return false

    if ex_style & 0x00000080 ; WS_EX_TOOLWINDOW
        return false

    if ex_style & 0x08000000 ; WS_EX_NOACTIVATE
        return false

    ; Owned top-level windows are normally dialogs or transient popups.
    if DllCall("GetWindow", "ptr", hwnd, "uint", 4, "ptr") ; GW_OWNER
        return false

    if window_class = "Shell_TrayWnd"
        || window_class = "Shell_SecondaryTrayWnd"
        || window_class = "Progman"
        || window_class = "WorkerW"
        || window_class = "NotifyIconOverflowWindow"
        || window_class = "tooltips_class32"
        || window_class = "Ghost"
        return false

    return true
}

ForgetWindow(hwnd)
{
    global pending_windows, handled_windows, placement_reservations
    global cascade_history
    global startup_windows, known_windows
    global current_foreground_hwnd, previous_foreground_hwnd

    affected_monitor := GetManagedCascadeMonitor(hwnd)

    if startup_windows.Has(hwnd)
        startup_windows.Delete(hwnd)

    if known_windows.Has(hwnd)
        known_windows.Delete(hwnd)

    if pending_windows.Has(hwnd) {
        pending_windows.Delete(hwnd)
    }

    if handled_windows.Has(hwnd) {
        handled_windows.Delete(hwnd)
    }

    if placement_reservations.Has(hwnd)
        placement_reservations.Delete(hwnd)

    if current_foreground_hwnd = hwnd
        current_foreground_hwnd := 0

    if previous_foreground_hwnd = hwnd
        previous_foreground_hwnd := 0

    RemoveWindowFromMinimizeState(hwnd)

    ; Remove the destroyed handle from per-monitor histories. This also avoids
    ; stale hwnd reuse after the application has been closed for a while.
    for monitor_index, history in cascade_history {
        index := history.Length

        while index >= 1 {
            if history[index] = hwnd
                history.RemoveAt(index)

            index -= 1
        }
    }

    if affected_monitor
        QueueCascadeCompaction(affected_monitor)
}

RemoveWindowFromMinimizeState(hwnd)
{
    global layer_minimized_windows_by_monitor
    global monitor_minimized_windows_by_monitor

    RemoveWindowFromMonitorWindowLists(
        layer_minimized_windows_by_monitor,
        hwnd
    )

    RemoveWindowFromMonitorWindowLists(
        monitor_minimized_windows_by_monitor,
        hwnd
    )
}

RemoveWindowFromMonitorWindowLists(window_lists, hwnd)
{
    empty_monitors := []

    for monitor_index, windows in window_lists {
        index := windows.Length

        while index >= 1 {
            if windows[index] = hwnd
                windows.RemoveAt(index)

            index -= 1
        }

        if windows.Length = 0
            empty_monitors.Push(monitor_index)
    }

    for monitor_index in empty_monitors
        window_lists.Delete(monitor_index)
}


; =============================================================================
; focus corners
; =============================================================================

QueueFocusCornerUpdate()
{
    global focus_corner_update_pending
    global focus_corner_update_ms

    if focus_corner_update_pending
        return

    focus_corner_update_pending := true

    SetTimer(
        RunQueuedFocusCornerUpdate,
        -focus_corner_update_ms
    )
}


RunQueuedFocusCornerUpdate()
{
    global focus_corner_update_pending

    focus_corner_update_pending := false
    UpdateFocusCornerOverlays()
}


UpdateFocusCornerOverlays()
{
    global focus_corner_overlays

    RefreshFocusCornerAccent()

    active_hwnd := DllCall(
        "GetForegroundWindow",
        "ptr"
    )

    ; The marker timer must never mutate cascade membership. A window can be
    ; temporarily between geometries while Explorer or placement settles.
    live_windows := GetCascadeWindowsForOverlay()
    live_targets := Map()
    visible_bounds := Map()

    highest_hwnd := 0
    highest_y := 0

    ; Cache geometry and identify the cascade window with the smallest Y.
    for hwnd in live_windows {
        live_targets[hwnd] := true

        if !DllCall(
            "IsWindowVisible",
            "ptr", hwnd,
            "int"
        ) {
            continue
        }

        try {
            if WinGetMinMax("ahk_id " hwnd) != 0
                continue
        }
        catch {
            continue
        }

        if !GetVisibleWindowBounds(
            hwnd,
            &window_x,
            &window_y,
            &window_width,
            &window_height
        ) {
            continue
        }

        visible_bounds[hwnd] := [
            window_x,
            window_y,
            window_width,
            window_height
        ]

        if !highest_hwnd || window_y < highest_y {
            highest_hwnd := hwnd
            highest_y := window_y
        }
    }

    for hwnd in live_windows {
        if (
            hwnd = active_hwnd
            || !visible_bounds.Has(hwnd)
        ) {
            HideFocusCornerOverlay(hwnd)
            continue
        }

        bounds := visible_bounds[hwnd]

        ShowFocusCornerOverlay(
            hwnd,
            bounds[1],
            bounds[2],
            bounds[3],
            bounds[4],
            hwnd = highest_hwnd
        )
    }

    stale_targets := []

    for hwnd, overlay in focus_corner_overlays {
        if !live_targets.Has(hwnd)
            stale_targets.Push(hwnd)
    }

    for hwnd in stale_targets
        DestroyFocusCornerOverlay(hwnd)
}


GetCascadeWindowsForOverlay()
{
    global cascade_history

    windows := []
    seen := Map()

    for monitor_index, history in cascade_history {
        for hwnd in history {
            if seen.Has(hwnd)
                continue

            if !WinExist("ahk_id " hwnd)
                continue

            if GetMonitorForWindow(hwnd) != monitor_index
                continue

            ; Do not remove a window from history just because a visual refresh
            ; catches it during a transient geometry change.
            if !IsWindowInCascadeLayout(hwnd)
                continue

            seen[hwnd] := true
            windows.Push(hwnd)
        }
    }

    return windows
}


ShowFocusCornerOverlay(
    hwnd,
    window_x,
    window_y,
    window_width,
    window_height,
    full_height := false
)
{
    global focus_corner_overlays
    global focus_corner_size
    global focus_corner_thickness
    global focus_corner_overlap
    global focus_corner_visible, focus_corner_visible_alpha

    if !focus_corner_overlays.Has(hwnd)
        CreateFocusCornerOverlay(hwnd)

    overlay := focus_corner_overlays[hwnd]

    if (
        overlay.shown
        && overlay.window_x = window_x
        && overlay.window_y = window_y
        && overlay.window_width = window_width
        && overlay.window_height = window_height
        && overlay.full_height = full_height
    ) {
        PlaceFocusCornerAboveTarget(hwnd, overlay)
        return
    }

    thickness := focus_corner_thickness
    overlap := focus_corner_overlap
    outside := thickness - overlap

    marker_x := window_x - outside

    if full_height {
        marker_y := window_y
        marker_height := window_height
    } else {
        marker_y :=
            window_y
            + window_height
            - focus_corner_size

        marker_height := focus_corner_size
    }

    overlay.gui.Show(
        "NA"
        . " x" marker_x
        . " y" marker_y
        . " w" thickness
        . " h" marker_height
    )

    WinSetTransparent(
        focus_corner_visible ? focus_corner_visible_alpha : 1,
        "ahk_id " overlay.gui.Hwnd
    )

    PlaceFocusCornerAboveTarget(hwnd, overlay)

    overlay.window_x := window_x
    overlay.window_y := window_y
    overlay.window_width := window_width
    overlay.window_height := window_height
    overlay.full_height := full_height
    overlay.shown := true
}


PlaceFocusCornerAboveTarget(hwnd, overlay)
{
    static SWP_NOSIZE := 0x0001
    static SWP_NOMOVE := 0x0002
    static SWP_NOACTIVATE := 0x0010

    if !WinExist("ahk_id " hwnd)
        return

    flags :=
        SWP_NOSIZE
        | SWP_NOMOVE
        | SWP_NOACTIVATE

    DllCall(
        "SetWindowPos",
        "ptr", overlay.gui.Hwnd,
        "ptr", hwnd,
        "int", 0,
        "int", 0,
        "int", 0,
        "int", 0,
        "uint", flags,
        "int"
    )
}


HideFocusCornerOverlay(hwnd)
{
    global focus_corner_overlays

    if !focus_corner_overlays.Has(hwnd)
        return

    overlay := focus_corner_overlays[hwnd]

    if !overlay.shown
        return

    try overlay.gui.Hide()

    overlay.shown := false
}


CreateFocusCornerOverlay(hwnd)
{
    global focus_corner_overlays
    global focus_corner_targets
    global focus_corner_accent_color

    marker_gui := Gui(
        "-Caption"
        . " +ToolWindow"
        . " +E0x08000000",
        "Window Cascade Focus Marker"
    )

    marker_gui.BackColor := focus_corner_accent_color

    focus_corner_targets[marker_gui.Hwnd] := hwnd

    focus_corner_overlays[hwnd] := {
        gui: marker_gui,
        shown: false,
        window_x: 0,
        window_y: 0,
        window_width: 0,
        window_height: 0,
        full_height: false
    }
}


DestroyFocusCornerOverlay(hwnd)
{
    global focus_corner_overlays
    global focus_corner_targets

    if !focus_corner_overlays.Has(hwnd)
        return

    overlay := focus_corner_overlays[hwnd]
    overlay_hwnd := overlay.gui.Hwnd

    try overlay.gui.Destroy()

    focus_corner_overlays.Delete(hwnd)

    if focus_corner_targets.Has(overlay_hwnd)
        focus_corner_targets.Delete(overlay_hwnd)
}


HandleFocusCornerClick(
    w_param,
    l_param,
    message,
    overlay_hwnd
)
{
    global focus_corner_targets

    if !focus_corner_targets.Has(overlay_hwnd)
        return

    target_hwnd := focus_corner_targets[overlay_hwnd]

    if !WinExist("ahk_id " target_hwnd) {
        DestroyFocusCornerOverlay(target_hwnd)
        return 0
    }

    HideFocusCornerOverlay(target_hwnd)

    try WinActivate("ahk_id " target_hwnd)

    return 0
}


ToggleFocusCornerVisibility(*)
{
    global focus_corner_visible, focus_corner_visible_alpha
    global focus_corner_overlays

    focus_corner_visible := !focus_corner_visible
    transparency := focus_corner_visible ? focus_corner_visible_alpha : 1

    for hwnd, overlay in focus_corner_overlays {
        try WinSetTransparent(
            transparency,
            "ahk_id " overlay.gui.Hwnd
        )
    }

    UpdateTrayMenu()
}


RefreshFocusCornerAccent()
{
    global focus_corner_overlays
    global focus_corner_accent_color
    global focus_corner_accent_check_tick
    global focus_corner_accent_check_ms

    if (
        focus_corner_accent_color != ""
        && A_TickCount - focus_corner_accent_check_tick
            < focus_corner_accent_check_ms
    ) {
        return
    }

    focus_corner_accent_check_tick := A_TickCount
    new_color := GetWindowsAccentHexColor()

    if new_color = focus_corner_accent_color
        return

    focus_corner_accent_color := new_color
    targets := []

    for hwnd, overlay in focus_corner_overlays
        targets.Push(hwnd)

    for hwnd in targets
        DestroyFocusCornerOverlay(hwnd)
}


GetVisibleWindowBounds(
    hwnd,
    &x,
    &y,
    &width,
    &height
)
{
    static DWMWA_EXTENDED_FRAME_BOUNDS := 9

    frame := Buffer(16, 0)

    result := DllCall(
        "dwmapi\DwmGetWindowAttribute",
        "ptr", hwnd,
        "uint", DWMWA_EXTENDED_FRAME_BOUNDS,
        "ptr", frame,
        "uint", frame.Size,
        "int"
    )

    if result != 0
        return false

    left := NumGet(frame, 0, "int")
    top := NumGet(frame, 4, "int")
    right := NumGet(frame, 8, "int")
    bottom := NumGet(frame, 12, "int")

    x := left
    y := top
    width := right - left
    height := bottom - top

    return width > 0 && height > 0
}


GetWindowsAccentHexColor()
{
    colorization_color := 0
    opaque_blend := 0

    result := DllCall(
        "dwmapi\DwmGetColorizationColor",
        "uint*", &colorization_color,
        "int*", &opaque_blend,
        "int"
    )

    if result != 0
        return "0078D4"

    red := (colorization_color >> 16) & 0xFF
    green := (colorization_color >> 8) & 0xFF
    blue := colorization_color & 0xFF

    return Format(
        "{:02X}{:02X}{:02X}",
        red,
        green,
        blue
    )
}

; =============================================================================
; placement
; =============================================================================

GetPlacementReadinessReason(hwnd)
{
    ; Query title and state in the same order as the placement path.
    retry_reason := ""

    try {
        candidate_title := WinGetTitle("ahk_id " hwnd)
        candidate_min_max := WinGetMinMax("ahk_id " hwnd)

        if candidate_title = ""
            retry_reason := "empty title"
        else if candidate_min_max != 0
            retry_reason := "minimized or maximized"
    }
    catch {
        retry_reason := "window state unavailable"
    }

    return retry_reason
}

PlaceNewWindow(
    hwnd,
    source_hwnd,
    queued_monitor := 0,
    retry_count := 0,
    settle_complete := false
)
{
    global pending_windows, handled_windows, placement_reservations
    global placement_ready_retry_ms, placement_ready_retry_limit
    global placement_settle_delay_ms
    global window_width_ratio, window_height_ratio
    global edge_margin, minimum_width, minimum_height

    try {
        if pending_windows.Has(hwnd)
            pending_windows.Delete(hwnd)

        DebugLog(
            "PlaceNewWindow begin."
            . " | retry=" retry_count
            . " | settled=" settle_complete
            . " | queued-monitor=" queued_monitor
            . " | target=" DebugDescribeWindow(hwnd)
            . " | source=" DebugDescribeWindow(source_hwnd)
        )

        if !WinExist("ahk_id " hwnd) {
            return
        }

        retry_reason := GetPlacementReadinessReason(hwnd)

        if retry_reason != ""
            && retry_count < placement_ready_retry_limit
        {
            next_retry := retry_count + 1
            pending_windows[hwnd] := true

            DebugLog(
                "Placement readiness retry."
                . " | reason=" retry_reason
                . " | retry=" next_retry
                . "/" placement_ready_retry_limit
                . " | target=" DebugDescribeWindow(hwnd)
            )

            SetTimer(
                PlaceNewWindow.Bind(
                    hwnd,
                    source_hwnd,
                    queued_monitor,
                    next_retry,
                    settle_complete
                ),
                -placement_ready_retry_ms
            )

            return
        }

        if !settle_complete {
            source_is_shell_or_gone := (
                !source_hwnd
                || !WinExist("ahk_id " source_hwnd)
                || IsShellSurfaceWindow(source_hwnd)
            )

            if queued_monitor && source_is_shell_or_gone {
                pending_windows[hwnd] := true

                SetTimer(
                    PlaceNewWindow.Bind(
                        hwnd,
                        source_hwnd,
                        queued_monitor,
                        retry_count,
                        true
                    ),
                    -placement_settle_delay_ms
                )

                return
            }
        }

        if !IsCascadeWindow(hwnd) {
            DebugLog(
                "Placement rejected by IsCascadeWindow."
                . " | " DebugDescribeWindow(hwnd)
            )
            return
        }

        target_monitor := GetTargetMonitor(hwnd, source_hwnd, queued_monitor)

        DebugLog(
            "Placement monitor resolved."
            . " | monitor=" target_monitor
            . " | queued-monitor=" queued_monitor
            . " | target=" DebugDescribeWindow(hwnd)
            . " | source=" DebugDescribeWindow(source_hwnd)
        )

        MonitorGetWorkArea(
            target_monitor,
            &work_left,
            &work_top,
            &work_right,
            &work_bottom
        )

        work_width := work_right - work_left
        work_height := work_bottom - work_top

        window_width := Floor(work_width * window_width_ratio)
        window_height := Floor(work_height * window_height_ratio)

        window_width := Max(minimum_width, window_width)
        window_height := Max(minimum_height, window_height)

        window_width := Min(window_width, work_width - edge_margin * 2)
        window_height := Min(window_height, work_height - edge_margin * 2)

        ; Slot selection and reservation must be atomic. An asynchronous move
        ; may not reach its target before another window needs a slot.
        Critical "On"

        try {
            position := GetNextCascadePosition(
                target_monitor,
                work_left,
                work_top,
                work_right,
                work_bottom,
                window_width,
                window_height
            )

            target_x := position[1]
            target_y := position[2]

            placement_reservations[hwnd] := Map(
                "monitor", target_monitor,
                "x", target_x,
                "y", target_y
            )
        }
        finally {
            Critical "Off"
        }

        raw_target := GetRawRectForVisibleTarget(
            hwnd,
            target_x,
            target_y,
            window_width,
            window_height
        )

        raw_target_x := raw_target[1]
        raw_target_y := raw_target[2]
        raw_target_width := raw_target[3]
        raw_target_height := raw_target[4]

        DebugLog(
            "Placement slot reserved."
            . " | monitor=" target_monitor
            . " | visible-rect=(" target_x "," target_y
            . " " window_width "x" window_height ")"
            . " | hwnd=" hwnd
        )

        DebugLog(
            "Moving cascade window."
            . " | monitor=" target_monitor
            . " | visible-rect=(" target_x "," target_y
            . " " window_width "x" window_height ")"
            . " | raw-rect=(" raw_target_x "," raw_target_y
            . " " raw_target_width "x" raw_target_height ")"
            . " | " DebugDescribeWindow(hwnd)
        )

        ; Post the placement request instead of blocking on applications whose
        ; window thread is temporarily busy, such as DST during startup.
        swp_flags := (
            0x4000  ; SWP_ASYNCWINDOWPOS
            | 0x0010  ; SWP_NOACTIVATE
            | 0x0004  ; SWP_NOZORDER
        )

        DebugLog(
            "SetWindowPos begin."
            . " | flags=" swp_flags
            . " | target=" DebugDescribeWindow(hwnd)
        )

        set_window_pos_start_tick := A_TickCount

        set_window_pos_result := DllCall(
            "SetWindowPos",
            "ptr", hwnd,
            "ptr", 0,
            "int", raw_target_x,
            "int", raw_target_y,
            "int", raw_target_width,
            "int", raw_target_height,
            "uint", swp_flags,
            "int"
        )

        set_window_pos_elapsed_ms :=
            A_TickCount - set_window_pos_start_tick

        DebugLog(
            "SetWindowPos returned."
            . " | result=" set_window_pos_result
            . " | elapsed-ms=" set_window_pos_elapsed_ms
            . " | target=" DebugDescribeWindow(hwnd)
        )

        if !set_window_pos_result {
            if placement_reservations.Has(hwnd)
                placement_reservations.Delete(hwnd)

            DebugLog(
                "SetWindowPos failed."
                . " | last-error=" A_LastError
                . " | target=" DebugDescribeWindow(hwnd)
            )
            return
        }

        handled_windows[hwnd] := true
        RecordCascadeWindow(target_monitor, hwnd)

        DebugLog(
            "Placement complete."
            . " | monitor=" target_monitor
            . " | " DebugDescribeWindow(hwnd)
        )

        SchedulePlacementStabilization(
            hwnd,
            target_x,
            target_y,
            window_width,
            window_height
        )

    }
    catch Error as err {
        error_number := 0

        try
            error_number := err.Number

        if err.What = "WinMove" && error_number = 5 {
            ; The window was successfully identified but Windows denied control.
            ; Treat it as handled so fallback detection does not retry it.
            handled_windows[hwnd] := true
            return
        }

        return
    }
}

SchedulePlacementStabilization(
    hwnd,
    target_x,
    target_y,
    target_width,
    target_height
)
{
    global placement_stabilize_delays_ms

    for delay_ms in placement_stabilize_delays_ms {
        SetTimer(
            StabilizePlacedWindow.Bind(
                hwnd,
                target_x,
                target_y,
                target_width,
                target_height,
                delay_ms
            ),
            -delay_ms
        )
    }
}

StabilizePlacedWindow(
    hwnd,
    target_x,
    target_y,
    target_width,
    target_height,
    delay_ms,
    attempt := 0,
    passive_stage := 0
)
{
    global handled_windows, placement_reservations
    global placement_stabilize_tolerance
    global placement_stabilize_retry_ms
    global placement_stabilize_retry_limit
    global placement_stabilize_confirmation_ms
    global placement_stabilize_backoff_delays_ms

    DebugLog(
        "Stabilization callback."
        . " | delay-ms=" delay_ms
        . " | attempt=" attempt
        . " | passive-stage=" passive_stage
        . " | hwnd=" hwnd
    )

    if !handled_windows.Has(hwnd) {
        if placement_reservations.Has(hwnd)
            placement_reservations.Delete(hwnd)

        return
    }

    if !WinExist("ahk_id " hwnd) {
        if placement_reservations.Has(hwnd)
            placement_reservations.Delete(hwnd)

        return
    }

    try {
        ; Do not fight an intentional maximize/minimize transition.
        if WinGetMinMax("ahk_id " hwnd) != 0 {
            if placement_reservations.Has(hwnd)
                placement_reservations.Delete(hwnd)

            return
        }

        if !TryGetVisibleFrameRect(
            hwnd,
            &current_x,
            &current_y,
            &current_width,
            &current_height,
            &current_inset_left,
            &current_inset_top,
            &current_inset_right,
            &current_inset_bottom
        ) {
            if placement_reservations.Has(hwnd)
                placement_reservations.Delete(hwnd)

            return
        }

        needs_correction := (
            Abs(current_x - target_x) > placement_stabilize_tolerance
            || Abs(current_y - target_y) > placement_stabilize_tolerance
            || Abs(current_width - target_width) > placement_stabilize_tolerance
            || Abs(current_height - target_height) > placement_stabilize_tolerance
        )

        DebugLog(
            "Stabilization check."
            . " | delay-ms=" delay_ms
            . " | matched=" (!needs_correction)
            . " | actual=("
            . current_x "," current_y " "
            . current_width "x" current_height
            . ")"
            . " | requested=("
            . target_x "," target_y " "
            . target_width "x" target_height
            . ")"
            . " | hwnd=" hwnd
        )

        if !needs_correction {
            if placement_reservations.Has(hwnd)
                placement_reservations.Delete(hwnd)

            DebugLog(
                "Placement reservation released."
                . " | reason=matched"
                . " | hwnd=" hwnd
            )

            return
        }

        if attempt >= placement_stabilize_retry_limit {
            ; Stop posting additional moves after the correction limit, but
            ; continue checking so the reserved slot is not reused prematurely.
            SetTimer(
                StabilizePlacedWindow.Bind(
                    hwnd,
                    target_x,
                    target_y,
                    target_width,
                    target_height,
                    placement_stabilize_confirmation_ms,
                    attempt,
                    passive_stage
                ),
                -placement_stabilize_confirmation_ms
            )

            DebugLog(
                "Stabilization confirmation-only recheck scheduled."
                . " | attempts=" attempt
                . " | delay-ms=" placement_stabilize_confirmation_ms
                . " | hwnd=" hwnd
            )

            return
        }

        ; A mismatch does not immediately mean that Cascade needs to fight the
        ; application. Give the window progressively more time to finish its
        ; own startup or asynchronous geometry changes.
        if passive_stage < placement_stabilize_backoff_delays_ms.Length {
            next_passive_stage := passive_stage + 1

            passive_delay_ms :=
                placement_stabilize_backoff_delays_ms[
                    next_passive_stage
                ]

            SetTimer(
                StabilizePlacedWindow.Bind(
                    hwnd,
                    target_x,
                    target_y,
                    target_width,
                    target_height,
                    passive_delay_ms,
                    attempt,
                    next_passive_stage
                ),
                -passive_delay_ms
            )

            DebugLog(
                "Stabilization passive recheck scheduled."
                . " | stage=" next_passive_stage
                . "/" placement_stabilize_backoff_delays_ms.Length
                . " | delay-ms=" passive_delay_ms
                . " | hwnd=" hwnd
            )

            return
        }

        ; The full passive grace period expired and the window is still wrong.
        ; Post one asynchronous correction, then begin a fresh passive cycle if
        ; the application overrides that correction too.
        next_attempt := attempt + 1

        raw_target_x := target_x - current_inset_left
        raw_target_y := target_y - current_inset_top

        raw_target_width := Max(
            1,
            target_width
            + current_inset_left
            + current_inset_right
        )

        raw_target_height := Max(
            1,
            target_height
            + current_inset_top
            + current_inset_bottom
        )

        swp_flags := (
            0x4000  ; SWP_ASYNCWINDOWPOS
            | 0x0010  ; SWP_NOACTIVATE
            | 0x0004  ; SWP_NOZORDER
        )

        DebugLog(
            "Stabilization SetWindowPos begin."
            . " | attempt=" next_attempt
            . " | passive-grace-complete=1"
            . " | hwnd=" hwnd
        )

        stabilization_start_tick := A_TickCount

        stabilization_result := DllCall(
            "SetWindowPos",
            "ptr", hwnd,
            "ptr", 0,
            "int", raw_target_x,
            "int", raw_target_y,
            "int", raw_target_width,
            "int", raw_target_height,
            "uint", swp_flags,
            "int"
        )

        stabilization_elapsed_ms :=
            A_TickCount - stabilization_start_tick

        DebugLog(
            "Stabilization SetWindowPos returned."
            . " | result=" stabilization_result
            . " | attempt=" next_attempt
            . " | elapsed-ms=" stabilization_elapsed_ms
            . " | hwnd=" hwnd
        )

        if !stabilization_result {
            if placement_reservations.Has(hwnd)
                placement_reservations.Delete(hwnd)

            DebugLog(
                "Placement reservation released."
                . " | reason=stabilization-failed"
                . " | last-error=" A_LastError
                . " | hwnd=" hwnd
            )

            return
        }

        SetTimer(
            StabilizePlacedWindow.Bind(
                hwnd,
                target_x,
                target_y,
                target_width,
                target_height,
                placement_stabilize_retry_ms,
                next_attempt,
                0
            ),
            -placement_stabilize_retry_ms
        )

        DebugLog(
            "Stabilization recheck scheduled."
            . " | attempt=" next_attempt
            . " | passive-stage=0"
            . " | delay-ms=" placement_stabilize_retry_ms
            . " | hwnd=" hwnd
        )
    }
    catch {
        return
    }
}

CenterCoordinate(work_start, work_size, window_size)
{
    return work_start + Floor((work_size - window_size) / 2)
}

GetNextCascadePosition(
    monitor_index,
    work_left,
    work_top,
    work_right,
    work_bottom,
    window_width,
    window_height
)
{
    global cascade_slot_tolerance, cascade_reset_cursors

    slots := BuildCascadeSlots(
        work_left,
        work_top,
        work_right,
        work_bottom,
        window_width,
        window_height
    )

    slot_counts := GetCascadeSlotCounts(
        monitor_index,
        slots,
        cascade_slot_tolerance
    )

    ; Reset Cascade starts one fresh sequential pass at slot 0 without
    ; forgetting any existing managed windows.
    if cascade_reset_cursors.Has(monitor_index) {
        selected_slot_index := cascade_reset_cursors[monitor_index]
        slot := slots[selected_slot_index]

        next_slot_index := selected_slot_index + 1

        if next_slot_index > slots.Length
            cascade_reset_cursors.Delete(monitor_index)
        else
            cascade_reset_cursors[monitor_index] := next_slot_index

        return slot
    }

    selected_slot_index := 1
    selected_count := slot_counts[1]

    ; Fill the least-used layer first. When several slots have the same count,
    ; the earlier canonical slot wins, so holes are repaired predictably.
    Loop slots.Length {
        slot_index := A_Index
        count := slot_counts[slot_index]

        if count < selected_count {
            selected_slot_index := slot_index
            selected_count := count
        }
    }

    return slots[selected_slot_index]
}


FindNearestCascadeSlot(
    window_x,
    window_y,
    slots,
    tolerance
)
{
    best_slot_index := 0
    best_distance := 0

    Loop slots.Length {
        slot_index := A_Index
        slot := slots[slot_index]

        delta_x := Abs(window_x - slot[1])
        delta_y := Abs(window_y - slot[2])

        if delta_x > tolerance || delta_y > tolerance
            continue

        distance := delta_x + delta_y

        if !best_slot_index
            || distance < best_distance
        {
            best_slot_index := slot_index
            best_distance := distance
        }
    }

    return best_slot_index
}
GetCascadeSlotCounts(
    monitor_index,
    slots,
    tolerance
)
{
    global cascade_history, placement_reservations

    counts := []

    Loop slots.Length
        counts.Push(0)

    if cascade_history.Has(monitor_index) {
        for hwnd in cascade_history[monitor_index] {
            if !WinExist("ahk_id " hwnd)
                continue

            ; A reserved window is counted at its intended slot below instead
            ; of at stale geometry from before its asynchronous move completes.
            if placement_reservations.Has(hwnd)
                continue

            if GetMonitorForWindow(hwnd) != monitor_index
                continue

            try {
                if WinGetMinMax("ahk_id " hwnd) = -1
                    continue
            }
            catch {
                continue
            }

            if !TryGetVisibleFrameRect(
                hwnd,
                &window_x,
                &window_y,
                &window_width,
                &window_height,
                &window_inset_left,
                &window_inset_top,
                &window_inset_right,
                &window_inset_bottom
            ) {
                continue
            }

            best_slot_index := FindNearestCascadeSlot(
                window_x,
                window_y,
                slots,
                tolerance
            )

            if best_slot_index
                counts[best_slot_index] += 1
        }
    }

    ; Reservations also include windows that have selected a slot but have not
    ; yet been recorded in cascade history.
    for reserved_hwnd, reservation in placement_reservations {
        if reservation["monitor"] != monitor_index
            continue

        if !WinExist("ahk_id " reserved_hwnd)
            continue

        best_slot_index := FindNearestCascadeSlot(
            reservation["x"],
            reservation["y"],
            slots,
            tolerance
        )

        if best_slot_index
            counts[best_slot_index] += 1
    }

    return counts
}
BuildCascadeSlots(
    work_left,
    work_top,
    work_right,
    work_bottom,
    window_width,
    window_height
)
{
    global cascade_x, cascade_y

    work_width := work_right - work_left
    work_height := work_bottom - work_top

    center_x := CenterCoordinate(
        work_left,
        work_width,
        window_width
    )

    center_y := CenterCoordinate(
        work_top,
        work_height,
        window_height
    )

    ; Slot 1 is the optimally centered position. Fill every position upward
    ; from center before continuing downward from center.
    slots := [[center_x, center_y]]

    ; Slots 2...N: left and upward from center until no more positions fit.
    step := 1

    Loop {
        x := center_x - cascade_x * step
        y := center_y - cascade_y * step

        if !CascadePositionFits(
            x,
            y,
            window_width,
            window_height,
            work_left,
            work_top,
            work_right,
            work_bottom
        ) {
            break
        }

        slots.Push([x, y])
        step += 1
    }

    ; Remaining slots: right and downward from center until the work area ends.
    step := 1

    Loop {
        x := center_x + cascade_x * step
        y := center_y + cascade_y * step

        if !CascadePositionFits(
            x,
            y,
            window_width,
            window_height,
            work_left,
            work_top,
            work_right,
            work_bottom
        ) {
            break
        }

        slots.Push([x, y])
        step += 1
    }

    return slots
}

CascadePositionFits(
    x,
    y,
    window_width,
    window_height,
    work_left,
    work_top,
    work_right,
    work_bottom
)
{
    global edge_margin

    return (
        x >= work_left + edge_margin
        && y >= work_top + edge_margin
        && x + window_width <= work_right - edge_margin
        && y + window_height <= work_bottom - edge_margin
    )
}

GetTargetMonitor(hwnd, source_hwnd, queued_monitor := 0)
{
    global desktop_monitor_hint, desktop_monitor_hint_tick
    global desktop_monitor_hint_max_age_ms

    ; Normal case: follow the real application window the user was working in.
    if source_hwnd
        && WinExist("ahk_id " source_hwnd)
        && !IsShellSurfaceWindow(source_hwnd)
    {
        monitor_index := GetMonitorForWindow(source_hwnd)

        if monitor_index {
            ; A real app interaction supersedes any older desktop-click hint.
            desktop_monitor_hint := 0
            desktop_monitor_hint_tick := 0

            return monitor_index
        }
    }

    ; Preserve the monitor where the launch was detected. This is newer than
    ; any earlier desktop-click hint and survives delayed application startup.
    if queued_monitor {
        desktop_monitor_hint := 0
        desktop_monitor_hint_tick := 0

        return queued_monitor
    }

    ; Special case: clicking empty desktop space explicitly selects that monitor
    ; when no newer launch snapshot is available.
    if desktop_monitor_hint {
        hint_age_ms := A_TickCount - desktop_monitor_hint_tick

        if hint_age_ms <= desktop_monitor_hint_max_age_ms {
            monitor_index := desktop_monitor_hint

            ; Consume the hint so one desktop click affects only the next launch.
            desktop_monitor_hint := 0
            desktop_monitor_hint_tick := 0

            return monitor_index
        }


        desktop_monitor_hint := 0
        desktop_monitor_hint_tick := 0
    }

    ; Final live-input fallback when no launch snapshot was available.
    MouseGetPos(&mouse_x, &mouse_y)
    monitor_index := GetMonitorForPoint(mouse_x, mouse_y)

    if monitor_index {
        return monitor_index
    }

    ; Final fallback: wherever the application initially created the window.
    monitor_index := GetMonitorForWindow(hwnd)

    if monitor_index {
        return monitor_index
    }

    monitor_index := MonitorGetPrimary()

    return monitor_index
}

GetMonitorForWindow(hwnd)
{
    try {
        WinGetPos(
            &x,
            &y,
            &width,
            &height,
            "ahk_id " hwnd
        )
    }
    catch {
        return 0
    }

    if width <= 0 || height <= 0
        return 0

    return GetMonitorForPoint(
        x + Floor(width / 2),
        y + Floor(height / 2)
    )
}

GetMonitorForPoint(x, y)
{
    monitor_count := MonitorGetCount()

    Loop monitor_count {
        MonitorGet(
            A_Index,
            &left,
            &top,
            &right,
            &bottom
        )

        if x >= left && x < right && y >= top && y < bottom
            return A_Index
    }

    return 0
}

RecordCascadeWindow(monitor_index, hwnd)
{
    global cascade_history

    if !cascade_history.Has(monitor_index)
        cascade_history[monitor_index] := []

    cascade_history[monitor_index].Push(hwnd)

    QueueFocusCornerUpdate()
}


; =============================================================================
; window filtering
; =============================================================================

IsCascadeWindow(hwnd)
{
    if !hwnd {
        return false
    }

    if !DllCall("IsWindowVisible", "ptr", hwnd, "int") {
        return false
    }

    try {
        min_max := WinGetMinMax("ahk_id " hwnd)
        style := WinGetStyle("ahk_id " hwnd)
        ex_style := WinGetExStyle("ahk_id " hwnd)
        window_class := WinGetClass("ahk_id " hwnd)
        title := WinGetTitle("ahk_id " hwnd)

        WinGetPos(
            &x,
            &y,
            &width,
            &height,
            "ahk_id " hwnd
        )
    }
    catch {
        return false
    }

    if min_max != 0 {
        return false
    }

    ; Require a normal captioned, resizable application window.
    if !(style & 0x00C00000) {
        return false
    }

    if !(style & 0x00040000) {
        return false
    }

    ; Ignore tool windows and windows that deliberately cannot activate.
    if ex_style & 0x00000080 {
        return false
    }

    if ex_style & 0x08000000 {
        return false
    }

    ; Owned top-level windows are normally dialogs or transient popups.
    if DllCall("GetWindow", "ptr", hwnd, "uint", 4, "ptr") {
        return false
    }

    if width < 1 || height < 1 {
        return false
    }

    if IsWindowCloaked(hwnd) {
        return false
    }

    if IsShellSurfaceWindow(hwnd) {
        return false
    }

    ; Empty-title windows are commonly invisible framework/helper windows.
    if title = "" {
        return false
    }

    return true
}

IsDesktopSurfaceWindow(hwnd)
{
    if !hwnd || !WinExist("ahk_id " hwnd)
        return false

    try window_class := WinGetClass("ahk_id " hwnd)
    catch
        return false

    return window_class = "Progman" || window_class = "WorkerW"
}

IsShellSurfaceWindow(hwnd)
{
    if !hwnd || !WinExist("ahk_id " hwnd)
        return false

    try window_class := WinGetClass("ahk_id " hwnd)
    catch
        return false

    return (
        window_class = "Shell_TrayWnd"
        || window_class = "Shell_SecondaryTrayWnd"
        || window_class = "Progman"
        || window_class = "WorkerW"
        || window_class = "NotifyIconOverflowWindow"
        || window_class = "tooltips_class32"
    )
}

IsWindowCloaked(hwnd)
{
    cloaked := 0

    result := DllCall(
        "dwmapi\DwmGetWindowAttribute",
        "ptr", hwnd,
        "uint", 14, ; DWMWA_CLOAKED
        "uint*", &cloaked,
        "uint", 4,
        "int"
    )

    return result = 0 && cloaked != 0
}


TryGetVisibleFrameRect(
    hwnd,
    &frame_x,
    &frame_y,
    &frame_width,
    &frame_height,
    &inset_left,
    &inset_top,
    &inset_right,
    &inset_bottom
)
{
    if !hwnd || !DllCall("IsWindow", "ptr", hwnd, "int")
        return false

    try {
        WinGetPos(
            &raw_x,
            &raw_y,
            &raw_width,
            &raw_height,
            "ahk_id " hwnd
        )
    }
    catch {
        return false
    }

    if raw_width <= 0 || raw_height <= 0
        return false

    ; Fall back to the raw HWND rectangle when DWM frame information is not
    ; available. This keeps ordinary Win32 behavior as the safe default.
    frame_x := raw_x
    frame_y := raw_y
    frame_width := raw_width
    frame_height := raw_height

    inset_left := 0
    inset_top := 0
    inset_right := 0
    inset_bottom := 0

    frame_rect := Buffer(16, 0)

    dwm_result := DllCall(
        "dwmapi\DwmGetWindowAttribute",
        "ptr", hwnd,
        "uint", 9, ; DWMWA_EXTENDED_FRAME_BOUNDS
        "ptr", frame_rect.Ptr,
        "uint", frame_rect.Size,
        "int"
    )

    if dwm_result != 0
        return true

    frame_left := NumGet(frame_rect, 0, "int")
    frame_top := NumGet(frame_rect, 4, "int")
    frame_right := NumGet(frame_rect, 8, "int")
    frame_bottom := NumGet(frame_rect, 12, "int")

    if frame_right <= frame_left || frame_bottom <= frame_top
        return true

    frame_x := frame_left
    frame_y := frame_top
    frame_width := frame_right - frame_left
    frame_height := frame_bottom - frame_top

    inset_left := frame_left - raw_x
    inset_top := frame_top - raw_y
    inset_right := (raw_x + raw_width) - frame_right
    inset_bottom := (raw_y + raw_height) - frame_bottom

    return true
}


GetRawRectForVisibleTarget(
    hwnd,
    visible_x,
    visible_y,
    visible_width,
    visible_height
)
{
    if !TryGetVisibleFrameRect(
        hwnd,
        &current_frame_x,
        &current_frame_y,
        &current_frame_width,
        &current_frame_height,
        &inset_left,
        &inset_top,
        &inset_right,
        &inset_bottom
    ) {
        return [
            visible_x,
            visible_y,
            visible_width,
            visible_height
        ]
    }

    raw_x := visible_x - inset_left
    raw_y := visible_y - inset_top

    raw_width := Max(
        1,
        visible_width + inset_left + inset_right
    )

    raw_height := Max(
        1,
        visible_height + inset_top + inset_bottom
    )

    return [
        raw_x,
        raw_y,
        raw_width,
        raw_height
    ]
}


; =============================================================================
; debug helpers
; =============================================================================

InitializeDebugLogging()
{
    global debug_enabled

    if !debug_enabled
        return

    reset_message := DllCall(
        "RegisterWindowMessage",
        "str", "WindowDebug.ResetLogs",
        "uint"
    )

    if reset_message {
        OnMessage(
            reset_message,
            HandleDebugResetLogsMessage
        )
    }

    OnError(LogUnhandledError)

    DebugLogSession("started")
}


HandleDebugResetLogsMessage(*)
{
    ResetDebugLog()
}


ResetDebugLog()
{
    global debug_enabled, debug_log_path

    if !debug_enabled
        return

    try {
        if FileExist(debug_log_path)
            FileDelete(debug_log_path)
    }
    catch Error as err {
        DebugLog(
            "Debug log reset failed."
            . " | message=" err.Message
        )
        return
    }

    DebugLogSession("reset")
}


DebugLogSession(reason)
{
    process_id := DllCall(
        "GetCurrentProcessId",
        "uint"
    )

    DebugLog(
        "Debug session " reason "."
        . " | pid=" process_id
        . " | ahk=" A_AhkVersion
        . ' | script="' A_ScriptFullPath '"'
    )
}


DebugLog(message)
{
    global debug_enabled, debug_log_path

    if !debug_enabled
        return

    timestamp := FormatTime(
        ,
        "yyyy-MM-dd HH:mm:ss"
    )

    try FileAppend(
        timestamp
        . " | tick=" A_TickCount
        . " | " message
        . "`n",
        debug_log_path,
        "UTF-8-RAW"
    )
}

DebugError(context, err)
{
    DebugLog(
        "ERROR in " context
        . " | message=" err.Message
        . " | what=" err.What
        . " | file=" err.File
        . " | line=" err.Line
    )

    if err.Stack != ""
        DebugLog(
            "STACK | "
            . StrReplace(
                StrReplace(err.Stack, "`r", ""),
                "`n",
                " | "
            )
        )
}


LogUnhandledError(err, mode)
{
    DebugError(
        "Unhandled error, mode=" mode,
        err
    )

    return 0
}


DebugDescribeWindow(hwnd)
{
    if !hwnd
        return "hwnd=0"

    if !DllCall("IsWindow", "ptr", hwnd, "int")
        return "hwnd=" hwnd " [invalid]"

    title := ""
    class_name := ""
    process_name := ""
    min_max := "?"
    x := "?"
    y := "?"
    width := "?"
    height := "?"

    try title := WinGetTitle("ahk_id " hwnd)
    try class_name := WinGetClass("ahk_id " hwnd)
    try process_name := WinGetProcessName("ahk_id " hwnd)
    try min_max := WinGetMinMax("ahk_id " hwnd)

    try {
        WinGetPos(
            &window_x,
            &window_y,
            &window_width,
            &window_height,
            "ahk_id " hwnd
        )

        x := window_x
        y := window_y
        width := window_width
        height := window_height
    }

    title := StrReplace(
        StrReplace(title, "`r", " "),
        "`n",
        " "
    )

    visible := DllCall(
        "IsWindowVisible",
        "ptr", hwnd,
        "int"
    )

    iconic := DllCall(
        "IsIconic",
        "ptr", hwnd,
        "int"
    )

    cloaked := false
    try cloaked := IsWindowCloaked(hwnd)

    return (
        "hwnd=" hwnd
        . ' exe="' process_name '"'
        . ' class="' class_name '"'
        . ' title="' title '"'
        . " minmax=" min_max
        . " visible=" visible
        . " iconic=" iconic
        . " cloaked=" cloaked
        . " rect=(" x "," y
        . " " width "x" height ")"
    )
}

; =============================================================================
; compatibility checks
; =============================================================================

CheckCompatibilitySettings(*)
{
    try {
        warnings := []

        fancyzones_settings_path :=
            EnvGet("LOCALAPPDATA") "\Microsoft\PowerToys\FancyZones\settings.json"


        if FileExist(fancyzones_settings_path) {
            fancyzones_settings := FileRead(
                fancyzones_settings_path,
                "UTF-8"
            )

            if RegExMatch(
                fancyzones_settings,
                '"fancyzones_appLastZone_moveWindows"\s*:\s*\{\s*"value"\s*:\s*true'
            ) {
                warnings.Push(
                    'FancyZones: "Move newly created windows to the last known zone" '
                    . "is enabled."
                )
            }
        }

        if warnings.Length = 0 {
            return
        }

        message :=
            "This setting may compete with Window Cascade:`n`n"

        for warning in warnings
            message .= "• " warning "`n`n"

        message .= "Window Cascade will not change PowerToys settings automatically."

        MsgBox(message, "Window Cascade", "Icon!")
    }
    catch {
        return
    }
}


; =============================================================================
; help
; =============================================================================

ToggleWindowCascadeHelp(*)
{
    static help_gui := 0

    if help_gui {
        try help_gui.Destroy()
        help_gui := 0
        return
    }

    help_gui := Gui("+AlwaysOnTop", "Window Cascade")
    help_gui.SetFont("s10", "Cascadia Mono")

    if IsCapsLockLayerRunning() {
        help_text :=
        (
        "Caps + H             Toggle this help`n"
        "`n"
        "HINTS`n"
        "Hold Caps + key      Run a command normally`n"
        "Tap Caps, then key   One-shot command for 1.4 seconds`n"
        "`n"
        "CONTROLS`n"
        "Caps + Up / Down          Swap visible window up / down`n"
        "Caps + Left / Right       Previous / next layer in this slot`n"
        "Caps + PgUp / PgDn        Focus visible window up / down`n"
        "Caps + Backspace          Adopt / re-slot active window`n"
        "Caps + Space / Tab        Rotate layers (tray setting)`n"
        "Caps + M                  Minimize / restore current layer`n"
        "Caps + F4                 Close current layer`n"
        "Caps + Delete             Close active window`n"
        "Caps + Home               Bring this monitor's cascade to front`n"
        "Caps + Shift + M          Minimize / restore all layers on monitor`n"
        "Caps + Shift + F4         Close all layers on monitor`n"
        "Caps + Shift + F7         Gather other monitors' cascades here"
        )
    } else {
        help_text :=
        (
        "Ctrl + Alt + H              Toggle this help`n"
        "`n"

        "CONTROLS`n"
        "Ctrl + Alt + Up / Down      Swap visible window up / down`n"
        "Ctrl + Alt + Left / Right   Previous / next layer in this slot`n"
        "Ctrl + Alt + PgUp / PgDn    Focus visible window up / down`n"
        "Ctrl + Alt + Backspace      Adopt / re-slot active window`n"
        "Ctrl + Alt + Space / Tab    Rotate layers (tray setting)`n"
        "Ctrl + Alt + M              Minimize / restore current layer`n"
        "Ctrl + Alt + F4             Close current layer`n"
        "Ctrl + Alt + Home           Bring this monitor's cascade to front`n"
        "Ctrl + Alt + Shift + M      Minimize / restore all layers on monitor`n"
        "Ctrl + Alt + Shift + F4     Close all layers on monitor`n"
        "Ctrl + Alt + Shift + F7     Gather other monitors' cascades here"
        )
    }

    help_text .=
    (
    "`n"
    "`n"
    "FOCUS TABS`n"
    "Click a window's left-edge focus tab to focus that cascade window.`n"
    "Use Show focus tabs in the tray to show or hide them.`n"
    "`n"
    "TRAY`n"
    "Pause cascading      Pause automatic placement`n"
    "Reset cascade        Restart the placement sequence`n"
    "Show focus tabs      Show / hide the faint focus tabs`n"
    "Check compatibility  Check conflicting settings"
    )

    help_gui.AddText("w720", help_text)

    help_gui.OnEvent("Close", CloseHelp)
    help_gui.OnEvent("Escape", CloseHelp)
    help_gui.Show()

    CloseHelp(*) {
        try help_gui.Destroy()
        help_gui := 0
    }
}

; =============================================================================
; tray menu
; =============================================================================

BuildTrayMenu()
{
    global rotate_key_menu

    A_TrayMenu.Delete()

    A_TrayMenu.Add("How to use", ToggleWindowCascadeHelp)
    A_TrayMenu.Add()
    A_TrayMenu.Add("Pause cascading", ToggleCascading)
    A_TrayMenu.Add("Reset cascade", ResetCascade)
    A_TrayMenu.Add("Show focus tabs", ToggleFocusCornerVisibility)
    A_TrayMenu.Add("Check compatibility", CheckCompatibilitySettings)

    rotate_key_menu := Menu()
    rotate_key_menu.Add("Space", SetRotateKey.Bind("Space"))
    rotate_key_menu.Add("Tab", SetRotateKey.Bind("Tab"))
    A_TrayMenu.Add("Rotate layers key", rotate_key_menu)

    A_TrayMenu.Add()
    A_TrayMenu.Add("Run at startup", ToggleStartup)
    A_TrayMenu.Add()
    A_TrayMenu.AddStandard()

    UpdateTrayMenu()
}

SetRotateKey(new_rotate_key, *)
{
    global settings_directory, settings_path, rotate_key

    if new_rotate_key != "Space" && new_rotate_key != "Tab"
        return

    try {
        DirCreate(settings_directory)
        IniWrite(new_rotate_key, settings_path, "Controls", "RotateKey")
    }
    catch Error as err {
        MsgBox(
            "Could not save the standalone rotate key.`n`n"
            . err.Message,
            "Window Cascade",
            "Iconx"
        )
        return
    }

    rotate_key := new_rotate_key
    UpdateTrayMenu()
}

ToggleCascading(*)
{
    global placement_enabled

    placement_enabled := !placement_enabled
    UpdateTrayMenu()
}

ResetCascade(*)
{
    global cascade_reset_cursors

    cascade_reset_cursors := Map()

    Loop MonitorGetCount()
        cascade_reset_cursors[A_Index] := 1
}

ToggleStartup(*)
{
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

        UpdateTrayMenu()
    }
    catch Error as err {
        MsgBox(
            "Could not update the startup shortcut.`n`n"
            . err.Message,
            "Window Cascade",
            "Iconx"
        )
    }
}

UpdateTrayMenu()
{
    global placement_enabled, startup_shortcut_path
    global focus_corner_visible
    global rotate_key, rotate_key_menu

    if placement_enabled
        A_TrayMenu.Uncheck("Pause cascading")
    else
        A_TrayMenu.Check("Pause cascading")

    if focus_corner_visible
        A_TrayMenu.Check("Show focus tabs")
    else
        A_TrayMenu.Uncheck("Show focus tabs")

    if IsObject(rotate_key_menu) {
        rotate_key_menu.Uncheck("Space")
        rotate_key_menu.Uncheck("Tab")
        rotate_key_menu.Check(rotate_key)
    }

    if FileExist(startup_shortcut_path)
        A_TrayMenu.Check("Run at startup")
    else
        A_TrayMenu.Uncheck("Run at startup")
}


; =============================================================================
; script cleanup
; =============================================================================

HandleScriptExit(exit_reason, exit_code)
{
    StopWindowHooks()
}


; =============================================================================
; managed window commands
; =============================================================================

CloseCurrentCascadeLayer()
{
    monitor_index := GetCommandMonitor()

    if !monitor_index
        return

    CloseCascadeWindowList(
        GetCurrentCascadeLayerWindows(monitor_index)
    )
}

CloseCommandMonitorCascade()
{
    global layer_minimized_windows_by_monitor
    global monitor_minimized_windows_by_monitor

    monitor_index := GetCommandMonitor()

    if !monitor_index
        return

    windows := GetCascadeWindowsForMonitorClose(monitor_index)
    CloseCascadeWindowList(windows)

    ; Closing a monitor cascade invalidates any script-owned restore state.
    if layer_minimized_windows_by_monitor.Has(monitor_index)
        layer_minimized_windows_by_monitor.Delete(monitor_index)

    if monitor_minimized_windows_by_monitor.Has(monitor_index)
        monitor_minimized_windows_by_monitor.Delete(monitor_index)
}

GetCascadeWindowsForMonitorClose(monitor_index)
{
    global placement_reservations

    windows := GetLiveCascadeHistory(monitor_index)
    seen := Map()

    for hwnd in windows
        seen[hwnd] := true

    ; Include windows already reserved for this monitor even if asynchronous
    ; placement has not reached cascade history yet.
    for hwnd, reservation in placement_reservations {
        if reservation["monitor"] != monitor_index
            continue

        if seen.Has(hwnd) || !WinExist("ahk_id " hwnd)
            continue

        seen[hwnd] := true
        windows.Push(hwnd)
    }

    return windows
}

CloseCascadeWindowList(windows)
{
    if windows.Length = 0
        return

    z_ranks := GetCascadeWindowZRanks()
    ordered_windows := SortCascadeWindowsByZOrder(
        windows,
        z_ranks
    )

    for hwnd in ordered_windows {
        if !WinExist("ahk_id " hwnd)
            continue

        try WinClose("ahk_id " hwnd)
    }
}

ToggleCurrentCascadeLayerMinimize()
{
    global layer_minimized_windows_by_monitor
    global monitor_minimized_windows_by_monitor

    monitor_index := GetCommandMonitor()

    if !monitor_index
        return

    ; A fully minimized monitor must be restored with the monitor-wide command.
    if monitor_minimized_windows_by_monitor.Has(monitor_index)
        return

    if layer_minimized_windows_by_monitor.Has(monitor_index) {
        windows := layer_minimized_windows_by_monitor[monitor_index]
        layer_minimized_windows_by_monitor.Delete(monitor_index)
        RestoreCascadeWindows(windows)
        QueueCascadeCompaction(monitor_index)
        QueueFocusCornerUpdate()
        return
    }

    windows := GetCurrentCascadeLayerWindows(monitor_index)
    minimized_windows := MinimizeCascadeWindows(windows)

    if minimized_windows.Length
        layer_minimized_windows_by_monitor[monitor_index] := minimized_windows

    QueueFocusCornerUpdate()
}

ToggleCommandMonitorCascadeMinimize()
{
    global layer_minimized_windows_by_monitor
    global monitor_minimized_windows_by_monitor

    monitor_index := GetCommandMonitor()

    if !monitor_index
        return

    if monitor_minimized_windows_by_monitor.Has(monitor_index) {
        windows := monitor_minimized_windows_by_monitor[monitor_index]
        monitor_minimized_windows_by_monitor.Delete(monitor_index)
        RestoreCascadeWindows(windows)
        QueueCascadeCompaction(monitor_index)
        QueueFocusCornerUpdate()
        return
    }

    ; If one layer was already hidden, absorb it into the monitor-wide toggle
    ; so Shift+M restores the complete cascade in one step.
    saved_windows := []
    seen := Map()

    if layer_minimized_windows_by_monitor.Has(monitor_index) {
        for hwnd in layer_minimized_windows_by_monitor[monitor_index] {
            if !WinExist("ahk_id " hwnd) || seen.Has(hwnd)
                continue

            seen[hwnd] := true
            saved_windows.Push(hwnd)
        }

        layer_minimized_windows_by_monitor.Delete(monitor_index)
    }

    visible_windows := MinimizeCascadeWindows(
        GetLiveCascadeHistory(monitor_index)
    )

    for hwnd in visible_windows {
        if seen.Has(hwnd)
            continue

        seen[hwnd] := true
        saved_windows.Push(hwnd)
    }

    if saved_windows.Length
        monitor_minimized_windows_by_monitor[monitor_index] := saved_windows

    QueueFocusCornerUpdate()
}

MinimizeCascadeWindows(windows)
{
    if windows.Length = 0
        return []

    z_ranks := GetCascadeWindowZRanks()
    ordered_windows := SortCascadeWindowsByZOrder(
        windows,
        z_ranks
    )

    windows_to_minimize := []

    ; Remember only windows visible before this toggle. Windows minimized by
    ; the user independently are never restored by Window Cascade.
    for hwnd in ordered_windows {
        if !WinExist("ahk_id " hwnd)
            continue

        try {
            if WinGetMinMax("ahk_id " hwnd) = -1
                continue
        }
        catch {
            continue
        }

        windows_to_minimize.Push(hwnd)
    }

    for hwnd in windows_to_minimize {
        try WinMinimize("ahk_id " hwnd)
    }

    return windows_to_minimize
}

RestoreCascadeWindows(windows)
{
    if windows.Length = 0
        return

    top_restored_hwnd := 0

    ; The saved list is top-to-bottom. Restore bottom-to-top first.
    Loop windows.Length {
        index := windows.Length - A_Index + 1
        hwnd := windows[index]

        if !WinExist("ahk_id " hwnd)
            continue

        try WinRestore("ahk_id " hwnd)
    }

    ; Rebuild the saved Z-order explicitly.
    flags := (
        0x0001  ; SWP_NOSIZE
        | 0x0002  ; SWP_NOMOVE
        | 0x0010  ; SWP_NOACTIVATE
        | 0x0200  ; SWP_NOOWNERZORDER
    )

    Loop windows.Length {
        index := windows.Length - A_Index + 1
        hwnd := windows[index]

        if !WinExist("ahk_id " hwnd)
            continue

        try DllCall(
            "SetWindowPos",
            "ptr", hwnd,
            "ptr", 0, ; HWND_TOP
            "int", 0,
            "int", 0,
            "int", 0,
            "int", 0,
            "uint", flags,
            "int"
        )
    }

    for hwnd in windows {
        if !WinExist("ahk_id " hwnd)
            continue

        top_restored_hwnd := hwnd
        break
    }

    if top_restored_hwnd
        ActivateCascadeWindow(top_restored_hwnd)
}
