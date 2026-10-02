; Internal Window Cascade module. Launch ..\window-cascade.ahk instead.
; Included into the same script; functions share the existing global state.

; =============================================================================
; adoption and cross-monitor commands
; =============================================================================

AdoptActiveWindow()
{
    global pending_adoption_undo

    hwnd := WinExist("A")

    if !hwnd || IsShellSurfaceWindow(hwnd)
        return

    ; A second Caps + Insert is the one-shot undo only while nothing else has
    ; consumed it. After cancellation this same command returns to normal re-slot.
    if IsPendingAdoptionUndoFor(hwnd) {
        UndoPendingAdoption()
        return
    }

    CancelPendingAdoptionUndo()

    managed_monitor := GetManagedCascadeMonitor(hwnd)

    ; Prune stale membership before deciding whether this is a true adoption.
    ; A window deliberately moved beyond release tolerance should be adoptable.
    if managed_monitor {
        GetLiveCascadeHistory(managed_monitor)
        managed_monitor := GetManagedCascadeMonitor(hwnd)
    }

    undo_snapshot := 0

    if !managed_monitor
        undo_snapshot := CaptureAdoptionUndoSnapshot(hwnd)

    target_monitor := GetMonitorForWindow(hwnd)

    if !target_monitor
        return

    if !PlaceCascadeWindowOnMonitor(hwnd, target_monitor)
        return

    if undo_snapshot
        pending_adoption_undo := undo_snapshot
}

CaptureAdoptionUndoSnapshot(hwnd)
{
    global handled_windows

    try {
        WinGetPos(
            &window_x,
            &window_y,
            &window_width,
            &window_height,
            "ahk_id " hwnd
        )
    }
    catch {
        return 0
    }

    return Map(
        "hwnd", hwnd,
        "x", window_x,
        "y", window_y,
        "width", window_width,
        "height", window_height,
        "was_handled", handled_windows.Has(hwnd)
    )
}

IsPendingAdoptionUndoFor(hwnd)
{
    global pending_adoption_undo

    return IsObject(pending_adoption_undo)
        && pending_adoption_undo.Has("hwnd")
        && pending_adoption_undo["hwnd"] = hwnd
}

CancelPendingAdoptionUndo()
{
    global pending_adoption_undo

    pending_adoption_undo := 0
}

UndoPendingAdoption()
{
    global pending_adoption_undo
    global handled_windows, placement_reservations

    if !IsObject(pending_adoption_undo)
        return false

    snapshot := pending_adoption_undo
    pending_adoption_undo := 0
    hwnd := snapshot["hwnd"]

    if !hwnd || !WinExist("ahk_id " hwnd)
        return false

    managed_monitor := GetManagedCascadeMonitor(hwnd)

    ; Stop the delayed placement correction before restoring the old geometry.
    CancelPlacementStabilization(hwnd)

    try {
        WinMove(
            snapshot["x"],
            snapshot["y"],
            snapshot["width"],
            snapshot["height"],
            "ahk_id " hwnd
        )
    }
    catch {
        ; If restoration fails, keep the window managed rather than leaving a
        ; half-undone state. A fresh placement also re-enables stabilization.
        if managed_monitor
            PlaceCascadeWindowOnMonitor(hwnd, managed_monitor)

        return false
    }

    RemoveCascadeWindowFromHistory(hwnd)
    RemoveWindowFromMinimizeState(hwnd)

    if placement_reservations.Has(hwnd)
        placement_reservations.Delete(hwnd)

    if snapshot["was_handled"]
        handled_windows[hwnd] := true
    else if handled_windows.Has(hwnd)
        handled_windows.Delete(hwnd)

    if managed_monitor
        QueueCascadeCompaction(managed_monitor)

    QueueFocusCornerUpdate()
    return true
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

    NormalizeAllCascadesMinimizedState()
    BringCascadeForward(target_monitor)
    QueueFocusCornerUpdate()
}

MoveCascadeWindowAcrossMonitor(hwnd, direction)
{
    global monitor_minimized_windows_by_monitor
    global all_cascades_minimized

    if !hwnd || !WinExist("ahk_id " hwnd)
        return

    if IsShellSurfaceWindow(hwnd) || !IsCascadeWindow(hwnd)
        return

    ; The CapsLock layer sends the hwnd that was active when the chord fired.
    ; Abort instead of moving a different window if focus changed meanwhile.
    if WinExist("A") != hwnd {
        DebugLog(
            "Cascade monitor move ignored: active window changed."
            . " | direction=" direction
            . " | " DebugDescribeWindow(hwnd)
        )
        return
    }

    source_monitor := GetMonitorForWindow(hwnd)

    if !source_monitor
        return

    target_monitor := GetAdjacentMonitor(source_monitor, direction)

    if !target_monitor {
        DebugLog(
            "Cascade monitor move ignored: no monitor in direction."
            . " | direction=" direction
            . " | source-monitor=" source_monitor
            . " | " DebugDescribeWindow(hwnd)
        )
        return
    }

    managed_monitor := GetManagedCascadeMonitor(hwnd)

    ; Hand the window directly to the destination cascade. Normal smart
    ; placement chooses the shallowest slot and earliest slot number on ties.
    RemoveWindowFromMinimizeState(hwnd)

    if !PlaceCascadeWindowOnMonitor(hwnd, target_monitor) {
        DebugLog(
            "Cascade monitor move destination placement failed."
            . " | source-monitor=" source_monitor
            . " | target-monitor=" target_monitor
            . " | " DebugDescribeWindow(hwnd)
        )
        return
    }

    ; Preserve an intentionally hidden destination cascade. A moved window
    ; becomes part of the same restore set immediately.
    if all_cascades_minimized
        || monitor_minimized_windows_by_monitor.Has(target_monitor)
    {
        if !monitor_minimized_windows_by_monitor.Has(target_monitor)
            monitor_minimized_windows_by_monitor[target_monitor] := []

        monitor_minimized_windows_by_monitor[target_monitor].Push(hwnd)
        try WinMinimize("ahk_id " hwnd)
    }

    DebugLog(
        "Window moved, adopted, and smart-sorted by destination cascade."
        . " | direction=" direction
        . " | source-monitor=" source_monitor
        . " | managed-monitor=" managed_monitor
        . " | target-monitor=" target_monitor
        . " | " DebugDescribeWindow(hwnd)
    )

    QueueFocusCornerUpdate()
}


; =============================================================================
; close commands
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

    NormalizeAllCascadesMinimizedState()
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


; =============================================================================
; minimize and restore commands
; =============================================================================

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
    global monitor_minimized_windows_by_monitor
    global all_cascades_minimized

    ; While the global toggle owns the restore set, keep its state atomic.
    if all_cascades_minimized
        return

    monitor_index := GetCommandMonitor()

    if !monitor_index
        return

    if monitor_minimized_windows_by_monitor.Has(monitor_index)
        RestoreMonitorCascade(monitor_index)
    else
        MinimizeMonitorCascade(monitor_index)

    QueueFocusCornerUpdate()
}

ToggleAllCascadesMinimize()
{
    global all_cascades_minimized
    global monitor_minimized_windows_by_monitor

    if all_cascades_minimized {
        monitors := []

        for monitor_index in monitor_minimized_windows_by_monitor
            monitors.Push(monitor_index)

        for monitor_index in monitors
            RestoreMonitorCascade(monitor_index)

        all_cascades_minimized := false
        QueueFocusCornerUpdate()
        return
    }

    minimized_any := false

    for monitor_index in GetCascadeMonitorIndices() {
        if MinimizeMonitorCascade(monitor_index)
            minimized_any := true
    }

    if minimized_any
        all_cascades_minimized := true

    QueueFocusCornerUpdate()
}

NormalizeAllCascadesMinimizedState()
{
    global all_cascades_minimized
    global monitor_minimized_windows_by_monitor

    ; Permanent cleanup can consume the final global restore set. Do not leave
    ; the global toggle owning an empty state, which would block monitor toggles.
    if all_cascades_minimized
        && monitor_minimized_windows_by_monitor.Count = 0
    {
        all_cascades_minimized := false
    }
}

GetCascadeMonitorIndices()
{
    global cascade_history
    global layer_minimized_windows_by_monitor
    global monitor_minimized_windows_by_monitor

    monitors := []
    seen := Map()

    for monitor_maps in [
        cascade_history,
        layer_minimized_windows_by_monitor,
        monitor_minimized_windows_by_monitor
    ] {
        for monitor_index in monitor_maps {
            if seen.Has(monitor_index)
                continue

            seen[monitor_index] := true
            monitors.Push(monitor_index)
        }
    }

    return monitors
}

MinimizeMonitorCascade(monitor_index)
{
    global layer_minimized_windows_by_monitor
    global monitor_minimized_windows_by_monitor

    ; An already-hidden monitor is already part of the requested scope.
    if monitor_minimized_windows_by_monitor.Has(monitor_index)
        return monitor_minimized_windows_by_monitor[monitor_index].Length > 0

    ; Absorb any older layer-only state so this monitor restores atomically.
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

    if saved_windows.Length {
        monitor_minimized_windows_by_monitor[monitor_index] := saved_windows
        return true
    }

    return false
}

RestoreMonitorCascade(monitor_index)
{
    global monitor_minimized_windows_by_monitor

    if !monitor_minimized_windows_by_monitor.Has(monitor_index)
        return false

    windows := monitor_minimized_windows_by_monitor[monitor_index]
    monitor_minimized_windows_by_monitor.Delete(monitor_index)
    NormalizeAllCascadesMinimizedState()
    RestoreCascadeWindows(windows)
    QueueCascadeCompaction(monitor_index)
    return true
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


; =============================================================================
; minimize state cleanup
; =============================================================================

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
