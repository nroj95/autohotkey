; Internal Window Cascade module. Launch ..\window-cascade.ahk instead.
; Included into the same script; functions share the existing global state.
;
; Caps + M is one global disable/resume toggle. Keep the message receiver and
; dependency/lifetime bookkeeping alive, but do not run cascade work while off.

; =============================================================================
; global disable / resume
; =============================================================================

IsCascadeEnabled()
{
    global cascade_disabled, cascade_toggle_in_progress
    return !cascade_disabled && !cascade_toggle_in_progress
}

ToggleCascadeDisabled(*)
{
    global cascade_disabled, cascade_toggle_in_progress

    if cascade_toggle_in_progress
        return
    ; Complete a native drag or a paired tab click before hiding its target.
    if HasCascadeWindowDrag() || HasFocusTabClick() || GetKeyState("LButton", "P")
        return

    previous_critical := Critical("On")
    cascade_toggle_in_progress := true
    try {
        if cascade_disabled
            ResumeWindowCascade()
        else
            DisableWindowCascade()
    }
    catch Error as err {
        ; Leave the receiver alive and the saved restore set available for retry.
        cascade_disabled := true
        Suspend(true)
        StopCascadeActivity()
        DebugError("Toggle cascade disabled state", err)
    }
    finally {
        cascade_toggle_in_progress := false
        if !cascade_disabled {
            Suspend(false)
            StartCascadeActivity()
        }
        UpdateTrayMenu()
        Critical(previous_critical)
    }
}

DisableWindowCascade()
{
    global cascade_disabled, cascade_disabled_windows, cascade_membership_generation

    targets := CaptureCascadeDisableTargets()
    cascade_disabled := true
    cascade_membership_generation += 1
    Suspend(true)
    StopCascadeActivity()

    ; Empty cascades can be disabled too. Closing the final saved window later
    ; changes only the restore set, never the explicit disabled state.
    cascade_disabled_windows := []
    for target in targets {
        if !IsSameDisabledCascadeWindow(target)
            continue
        try {
            if WinGetMinMax(target.hwnd) = -1
                continue
            ; Publish before WinMinimize can yield to a native lifetime callback.
            cascade_disabled_windows.Push(target)
            WinMinimize(target.hwnd)
            if DllCall("IsIconic", "ptr", target.hwnd, "int") {
                ObserveCascadeMinimizedWindow(target.hwnd)
            } else {
                ForgetDisabledCascadeWindow(target.hwnd)
                DebugLog("Cascade minimize was not accepted. | hwnd=" target.hwnd)
            }
        }
        catch Error as err {
            ForgetDisabledCascadeWindow(target.hwnd)
            DebugError("Disable cascade window", err)
        }
    }
    DebugLog("Cascade disabled. | saved-windows=" cascade_disabled_windows.Length)
}

ResumeWindowCascade()
{
    global cascade_disabled, cascade_disabled_windows, cascade_membership_generation
    global current_foreground_hwnd, previous_foreground_hwnd

    RememberWindowsOpenedWhileDisabled()
    windows_to_restore := []
    for target in cascade_disabled_windows.Clone() {
        if !IsSameDisabledCascadeWindow(target)
            continue
        try {
            ; A manual restore/close while disabled relinquishes our ownership.
            if WinGetMinMax(target.hwnd) = -1
                && GetManagedCascadeMonitor(target.hwnd) = target.monitor
                windows_to_restore.Push(target.hwnd)
        }
    }

    ; Keep the transition gate and suspended mouse hotkeys until every restore
    ; request is issued. Register all monitor batches before restoring any window.
    cascade_disabled := false
    cascade_membership_generation += 1
    RestoreCascadeWindows(windows_to_restore)
    RememberWindowsOpenedWhileDisabled()
    cascade_disabled_windows := []
    current_foreground_hwnd := WinExist("A")
    previous_foreground_hwnd := 0
    DebugLog("Cascade resumed. | restored-windows=" windows_to_restore.Length)
}

CaptureCascadeDisableTargets()
{
    global cascade_history, placement_reservations

    targets := Map()
    ; Include reserved members so a just-posted placement cannot escape the toggle.
    for monitor_index, history in cascade_history.Clone() {
        try history := GetLiveCascadeHistory(monitor_index)
        catch
            continue
        for hwnd in history
            CaptureCascadeDisableTarget(targets, hwnd, monitor_index)
    }
    for hwnd, reservation in placement_reservations.Clone() {
        if targets.Has(hwnd)
            continue
        if CaptureCascadeDisableTarget(targets, hwnd, reservation["monitor"])
            RecordCascadeWindow(reservation["monitor"], hwnd)
    }

    windows := []
    for hwnd in targets
        windows.Push(hwnd)
    ordered := []
    for hwnd in SortCascadeWindowsByZOrder(windows, GetCascadeWindowZRanks())
        ordered.Push(targets[hwnd])
    return ordered
}

CaptureCascadeDisableTarget(targets, hwnd, monitor_index)
{
    ; Independently minimized or maximized/unmanaged windows are outside this set.
    if targets.Has(hwnd) || !IsCascadeWindow(hwnd)
        return false
    try {
        targets[hwnd] := {hwnd: hwnd, pid: WinGetPID(hwnd), monitor: monitor_index}
        return true
    }
    catch {
        return false
    }
}

IsSameDisabledCascadeWindow(target)
{
    if !DllCall("IsWindow", "ptr", target.hwnd, "int")
        return false
    try return WinGetPID(target.hwnd) = target.pid
    catch
        return false
}

ForgetDisabledCascadeWindow(hwnd)
{
    global cascade_disabled_windows

    index := cascade_disabled_windows.Length
    while index >= 1 {
        if cascade_disabled_windows[index].hwnd = hwnd
            cascade_disabled_windows.RemoveAt(index)
        index -= 1
    }
}

; =============================================================================
; cancel active work, then resume only from current membership
; =============================================================================

StopCascadeActivity()
{
    global pending_windows, startup_windows, known_windows, handled_windows
    global placement_reservations, placement_stabilization_generations
    global cascade_restore_batches, cascade_close_batches, cascade_compaction_timer_pending
    global focus_corner_update_pending, focus_corner_overlays, focus_tab_click_generation
    global cascade_mouse_press, desktop_monitor_hint, desktop_monitor_hint_tick

    CancelNewWindowFocus()
    CancelPendingAdoptionUndo()
    StopFocusTabClick()
    focus_tab_click_generation += 1
    StopCascadeWindowDrag()
    cascade_mouse_press := 0
    desktop_monitor_hint := 0
    desktop_monitor_hint_tick := 0

    for callback in [WatchForMissedWindows, UpdateFocusCornerOverlays,
        RunQueuedFocusCornerUpdate, WatchCascadeWindowRestores,
        FlushCascadeCompactions, CheckCompatibilitySettings]
    {
        SetTimer(callback, 0)
    }
    focus_corner_update_pending := false
    cascade_compaction_timer_pending := false

    ; Bound one-shot timers cannot be cancelled by creating another Bind object.
    ; Invalidate their request identities/generations instead; late calls are no-ops.
    for hwnd in pending_windows.Clone() {
        startup_windows[hwnd] := true
        known_windows[hwnd] := true
        handled_windows[hwnd] := true
    }
    pending_windows.Clear()
    placement_reservations.Clear()
    placement_stabilization_generations.Clear()
    cascade_restore_batches.Clear()
    ; Closed/cancelled requests must not preserve an old compaction gate on resume.
    cascade_close_batches.Clear()

    ; Hidden means no hit target at all, not merely the normal alpha-1 tab setting.
    for hwnd in focus_corner_overlays.Clone()
        HideFocusCornerOverlay(hwnd)
}

StartCascadeActivity()
{
    if !IsCascadeEnabled()
        return

    global missed_window_poll_ms, focus_corner_fallback_ms, cascade_history
    global cascade_restore_batches, cascade_restore_poll_ms

    SetTimer(WatchForMissedWindows, missed_window_poll_ms)
    SetTimer(UpdateFocusCornerOverlays, focus_corner_fallback_ms)
    if cascade_restore_batches.Count
        SetTimer(WatchCascadeWindowRestores, cascade_restore_poll_ms)
    for monitor_index in cascade_history
        QueueCascadeCompaction(monitor_index)
    QueueFocusCornerUpdate()
}

RememberWindowsOpenedWhileDisabled()
{
    global startup_windows, known_windows

    ; Include hidden top-level windows too, so showing a disabled-time app later
    ; does not make it look like a fresh launch. Do not adopt any of this snapshot.
    previous_hidden := DetectHiddenWindows(true)
    try {
        for hwnd in WinGetList() {
            startup_windows[hwnd] := true
            known_windows[hwnd] := true
        }
    }
    finally {
        DetectHiddenWindows(previous_hidden)
    }
}

HandleDisabledCascadeWinEvent(event, hwnd, object_id, child_id)
{
    global startup_windows, known_windows, cascade_disabled, cascade_toggle_in_progress

    if !hwnd || object_id != 0 || child_id != 0
        return
    try {
        if event = 0x8001 { ; EVENT_OBJECT_DESTROY
            ForgetWindow(hwnd)
            return
        }
        if event = 0x0017 && cascade_disabled && !cascade_toggle_in_progress {
            ; A user-restored window is no longer part of the next global restore.
            ForgetDisabledCascadeWindow(hwnd)
            return
        }
        if (event = 0x8002 || event = 0x0003) && IsPlausibleTopLevelWindow(hwnd) {
            startup_windows[hwnd] := true
            known_windows[hwnd] := true
        }
    }
    catch Error as err {
        DebugError("Disabled cascade window bookkeeping", err)
    }
}

RestoreDisabledCascadeWindowsOnExit()
{
    global cascade_disabled_windows

    ; Native hooks are already stopped. Do not run layout, Z-order, or focus work
    ; during exit/reload, and never restore independently minimized applications.
    Loop cascade_disabled_windows.Length {
        target := cascade_disabled_windows[cascade_disabled_windows.Length - A_Index + 1]
        if !IsSameDisabledCascadeWindow(target)
            continue
        try {
            if WinGetMinMax(target.hwnd) = -1
                WinRestore(target.hwnd)
        }
    }
    cascade_disabled_windows := []
}
