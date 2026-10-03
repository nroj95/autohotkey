; Internal Window Cascade module. Launch ..\window-cascade.ahk instead.
; Included into the same script; functions share the existing global state.
;
; Drop contract:
; - preserve the original membership/slot throughout a native mouse drag;
; - resolve the visible top-left corner only after the move loop and mouse-up;
; - snap to the nearest eligible slot, or release an existing member;
; - a real drop can adopt an existing window; ordinary clicks/resizes cannot.

; =============================================================================
; native mouse interaction and move-loop tracking
; =============================================================================

CaptureCascadeMousePress(*)
{
    global cascade_mouse_press

    ; Finish the previous released drag before snapshotting a rapid new press.
    if HasCascadeWindowDrag()
        WatchCascadeWindowDrag()
    CancelPendingAdoptionUndo()
    cascade_mouse_press := 0
    if HasFocusTabClick()
        return

    MouseGetPos(&mouse_x, &mouse_y, &hover_hwnd)
    hwnd := DllCall("GetAncestor", "ptr", hover_hwnd, "uint", 2, "ptr") ; GA_ROOT
    cascade_mouse_press := GetCascadeMousePressSnapshot(hwnd)
}

GetCascadeMousePressSnapshot(hwnd)
{
    if !IsPlausibleTopLevelWindow(hwnd)
        return 0

    try {
        WinGetPos(&x, &y, &width, &height, hwnd)
        if !GetVisibleWindowBounds(hwnd, &frame_x, &frame_y, &frame_width, &frame_height)
            return 0

        ; Snapshot on down, not at the later event callback: a quick drag may
        ; already have moved by the time EVENT_SYSTEM_MOVESIZESTART is delivered.
        return {
            hwnd: hwnd, pid: WinGetPID(hwnd),
            x: x, y: y, width: width, height: height,
            frame_x: frame_x, frame_y: frame_y,
            monitor: GetMonitorForWindow(hwnd),
            minmax: WinGetMinMax(hwnd),
            dpi: DllCall("GetDpiForWindow", "ptr", hwnd, "uint"),
            resize: !!RegExMatch(A_Cursor, "^Size(NS|WE|NWSE|NESW)$"),
            down_tick: A_TickCount, up_tick: 0, cancelled: false
        }
    }
    catch {
        return 0
    }
}

CaptureCascadeMouseRelease(*)
{
    global cascade_mouse_press, cascade_window_drag

    if IsObject(cascade_mouse_press)
        cascade_mouse_press.up_tick := A_TickCount
    if IsObject(cascade_window_drag)
        cascade_window_drag.up_tick := A_TickCount

    ; Let the native move loop commit its final rectangle before examining it.
    if HasCascadeWindowDrag()
        SetTimer(WatchCascadeWindowDrag, -1)

    CaptureDesktopMonitorHint()
}

HasCascadeWindowDrag()
{
    global cascade_window_drag
    return IsObject(cascade_window_drag)
}

IsCascadeWindowBeingDragged(hwnd)
{
    global cascade_window_drag
    return IsObject(cascade_window_drag) && cascade_window_drag.hwnd = hwnd
}

BeginCascadeWindowDrag(hwnd, event_time)
{
    global cascade_mouse_press, cascade_window_drag, cascade_drag_generation
    global known_windows, handled_windows, pending_windows, placement_reservations

    if HasCascadeWindowDrag() || HasFocusTabClick()
        return
    if !IsObject(cascade_mouse_press) || cascade_mouse_press.hwnd != hwnd {
        ; Recover a move-start notification that beat the ordinary down handler.
        ; The native event confirms a move loop; a held button confirms mouse input.
        if !GetKeyState("LButton", "P")
            return
        cascade_mouse_press := GetCascadeMousePressSnapshot(hwnd)
        if !IsObject(cascade_mouse_press)
            return
    }

    press := cascade_mouse_press
    ; Ignore keyboard move loops or a late event belonging to another click.
    if !GetKeyState("LButton", "P") {
        if !press.up_tick
            || ((event_time - press.down_tick) & 0xFFFFFFFF)
                > ((press.up_tick - press.down_tick) & 0xFFFFFFFF)
            return
    }
    if !WinExist(hwnd) || WinGetPID(hwnd) != press.pid
        return

    drag := press.Clone()
    drag.source_monitor := GetManagedCascadeMonitor(hwnd)
    drag.native_ended := false
    drag.completing := false
    cascade_window_drag := drag
    cascade_drag_generation += 1

    ; Manual interaction takes priority over launch settling and old corrections.
    ; Mark it handled so already-bound new-window timers become harmless too.
    CancelPendingAdoptionUndo()
    CancelPlacementStabilization(hwnd)
    known_windows[hwnd] := true
    handled_windows[hwnd] := true
    if pending_windows.Has(hwnd)
        pending_windows.Delete(hwnd)
    if placement_reservations.Has(hwnd)
        placement_reservations.Delete(hwnd)

    HideFocusCornerOverlay(hwnd)
    QueueFocusCornerUpdate()
    SetTimer(WatchCascadeWindowDrag, 50)
    DebugLog("Cascade drag started. | hwnd=" hwnd " | source-monitor=" drag.source_monitor)
}

EndCascadeWindowDrag(hwnd)
{
    global cascade_window_drag
    if !IsCascadeWindowBeingDragged(hwnd)
        return

    cascade_window_drag.native_ended := true
    SetTimer(WatchCascadeWindowDrag, -1)
}

CancelCascadeWindowDrop(*)
{
    global cascade_window_drag, cascade_mouse_press
    if IsObject(cascade_mouse_press)
        cascade_mouse_press.cancelled := true
    if IsObject(cascade_window_drag)
        cascade_window_drag.cancelled := true
}

IsNativeWindowMoveSizeActive(hwnd)
{
    thread_id := DllCall("GetWindowThreadProcessId", "ptr", hwnd, "ptr", 0, "uint")
    thread_info := Buffer(24 + 6 * A_PtrSize, 0)
    NumPut("uint", thread_info.Size, thread_info)
    if !thread_id || !DllCall("GetGUIThreadInfo", "uint", thread_id, "ptr", thread_info, "int")
        return -1

    return !!(NumGet(thread_info, 4, "uint") & 0x0002) ; GUI_INMOVESIZE
}

WatchCascadeWindowDrag()
{
    global cascade_window_drag

    if !IsObject(cascade_window_drag) {
        SetTimer(WatchCascadeWindowDrag, 0)
        return
    }
    drag := cascade_window_drag
    if drag.completing
        return

    try {
        if !WinExist(drag.hwnd) || WinGetPID(drag.hwnd) != drag.pid {
            StopCascadeWindowDrag(drag)
            return
        }

        ; Mouse-up alone can precede the final native geometry. The thread query
        ; recovers a missed end event without a timeout that snaps mid-drag.
        if (!drag.native_ended && IsNativeWindowMoveSizeActive(drag.hwnd) != 0)
            || (!drag.cancelled && !drag.up_tick && GetKeyState("LButton", "P"))
        {
            SetTimer(WatchCascadeWindowDrag, 50)
            return
        }

        if cascade_window_drag != drag
            return
        drag.completing := true
        CompleteCascadeWindowDrop(drag)
    }
    catch Error as err {
        drag.completing := true
        DebugError("CompleteCascadeWindowDrop", err)
    }
    finally {
        if drag.completing
            StopCascadeWindowDrag(drag)
    }
}

StopCascadeWindowDrag(expected_drag := 0)
{
    global cascade_window_drag, cascade_drag_generation, cascade_compaction_pending

    if IsObject(expected_drag) && cascade_window_drag != expected_drag
        return
    cascade_window_drag := 0
    cascade_drag_generation += 1
    SetTimer(WatchCascadeWindowDrag, 0)
    QueueFocusCornerUpdate()
    if cascade_compaction_pending.Count
        SetTimer(FlushCascadeCompactions, -120)
}

; =============================================================================
; one release-time snap / adopt / detach decision
; =============================================================================

CompleteCascadeWindowDrop(drag)
{
    global cascade_slot_tolerance

    hwnd := drag.hwnd
    if drag.cancelled
        return

    WinGetPos(&x, &y, &width, &height, hwnd)
    if x = drag.x && y = drag.y && width = drag.width && height = drag.height
        return

    ; Edge resizes are not drop-to-join. DPI changes and restoring a maximized
    ; title-bar drag may change size without being an edge resize.
    resized := drag.resize || (
        drag.minmax = 0
        && drag.dpi = DllCall("GetDpiForWindow", "ptr", hwnd, "uint")
        && (width != drag.width || height != drag.height)
    )
    if resized || !IsCascadeWindow(hwnd) {
        if drag.source_monitor && !IsWindowInCascadeLayout(hwnd)
            ReleaseCascadeWindow(hwnd)
        return
    }

    monitor_index := GetMonitorForWindow(hwnd)
    if !monitor_index
        return
    if !GetVisibleWindowBounds(hwnd, &frame_x, &frame_y, &frame_width, &frame_height)
        return

    geometry := GetCanonicalCascadeGeometry(monitor_index)
    slot_index := FindNearestCascadeSlot(
        frame_x, frame_y, geometry.slots, cascade_slot_tolerance
    )

    if slot_index && HasCascadeDropDestination(monitor_index, drag) {
        if PlaceCascadeWindowOnMonitor(hwnd, monitor_index, geometry.slots[slot_index]) {
            RemoveWindowFromMinimizeState(hwnd)
            NormalizeAllCascadesMinimizedState()
            if drag.source_monitor
                QueueCascadeCompaction(drag.source_monitor)
            QueueCascadeCompaction(monitor_index)
            DebugLog("Cascade drop snapped. | hwnd=" hwnd
                " | monitor=" monitor_index " | slot=" slot_index)
            return
        }
        ; Do not keep a failed snap half-adopted or silently choose another slot.
        DebugLog("Cascade drop snap failed. | hwnd=" hwnd)
    }

    ReleaseCascadeWindow(hwnd)
}

HasCascadeDropDestination(monitor_index, drag)
{
    global cascade_history

    ; The last window can return to its own cascade. Do not create invisible
    ; drop zones on an otherwise empty monitor for unrelated existing windows.
    if drag.source_monitor = monitor_index
        return true
    if !cascade_history.Has(monitor_index)
        return false
    for hwnd in cascade_history[monitor_index] {
        if hwnd != drag.hwnd && IsCascadeWindow(hwnd)
            && GetMonitorForWindow(hwnd) = monitor_index
            return true
    }
    return false
}

ReleaseCascadeWindow(hwnd)
{
    global known_windows, handled_windows, pending_windows, placement_reservations

    source_monitor := GetManagedCascadeMonitor(hwnd)
    CancelPlacementStabilization(hwnd)
    RemoveCascadeWindowFromHistory(hwnd)
    RemoveWindowFromMinimizeState(hwnd)
    NormalizeAllCascadesMinimizedState()
    if pending_windows.Has(hwnd)
        pending_windows.Delete(hwnd)
    if placement_reservations.Has(hwnd)
        placement_reservations.Delete(hwnd)
    if WinExist(hwnd) {
        known_windows[hwnd] := true
        handled_windows[hwnd] := true
    } else {
        ; A close during drop processing must not leave a dead/reusable HWND known.
        if known_windows.Has(hwnd)
            known_windows.Delete(hwnd)
        if handled_windows.Has(hwnd)
            handled_windows.Delete(hwnd)
    }
    DestroyFocusCornerOverlay(hwnd)
    if source_monitor
        QueueCascadeCompaction(source_monitor)
    QueueFocusCornerUpdate()
    DebugLog("Cascade drop released. | hwnd=" hwnd " | source-monitor=" source_monitor)
}
