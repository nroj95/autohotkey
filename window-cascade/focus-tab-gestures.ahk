; Internal Window Cascade module. Launch ..\window-cascade.ahk instead.
; Included into the same script; functions share the existing global state.
;
; Gesture contract:
; - consume a tab press and its matching release, not ordinary application clicks;
; - focus on press, preview only the tab, and rotate at most once on release;
; - keep the original target/monitor/slot rather than following later focus;
; - cancellation keeps the release owned until the physical button is released.

; =============================================================================
; mouse ownership and press-to-focus
; =============================================================================

HasFocusTabGesture()
{
    global focus_tab_pending_press, focus_tab_gesture

    return IsObject(focus_tab_pending_press) || IsObject(focus_tab_gesture)
}

CanStartFocusTabGesture()
{
    global focus_tab_pending_press
    global focus_corner_targets, focus_corner_overlays

    if HasFocusTabGesture()
        return true

    ; #HotIf may also be evaluated for release matching. Never claim a drag
    ; that started elsewhere merely because it ends over a tab.
    if !GetKeyState("LButton", "P")
        return false

    MouseGetPos(&mouse_x, &mouse_y, &overlay_hwnd)

    if !focus_corner_targets.Has(overlay_hwnd)
        return false

    target_hwnd := focus_corner_targets[overlay_hwnd]
    if !focus_corner_overlays.Has(target_hwnd)
        || !focus_corner_overlays[target_hwnd].shown
        return false

    ; Snapshot during hit-testing: a fast flick may leave the narrow tab before
    ; the hotkey thread starts. The pending press also owns a very quick release.
    focus_tab_pending_press := {
        target_hwnd: target_hwnd,
        overlay_hwnd: overlay_hwnd,
        start_x: mouse_x,
        start_y: mouse_y
    }
    return true
}

CanFinishFocusTabGesture()
{
    global focus_tab_release_point

    if !HasFocusTabGesture()
        return false

    ; Capture the release position before the pointer can continue travelling
    ; while the hotkey thread is queued (particularly during a fast flick).
    if !GetKeyState("LButton", "P") {
        MouseGetPos(&mouse_x, &mouse_y)
        focus_tab_release_point := {x: mouse_x, y: mouse_y}
    }
    return true
}

BeginFocusTabGesture(*)
{
    global focus_tab_pending_press, focus_tab_gesture
    global focus_corner_overlays, cascade_slot_tolerance
    global focus_tab_drag_alpha, focus_tab_gesture_poll_ms

    if IsObject(focus_tab_gesture) || !IsObject(focus_tab_pending_press)
        return

    ; Keep a fast release from observing a half-initialized gesture. There is
    ; no button-wait or drag loop here; tracking runs in a short-lived timer.
    previous_critical := A_IsCritical
    Critical "On"
    press := focus_tab_pending_press
    focus_tab_pending_press := 0
    gesture := {
        target_hwnd: press.target_hwnd,
        overlay_hwnd: press.overlay_hwnd,
        start_x: press.start_x,
        start_y: press.start_y,
        ready: false,
        cancelled: false,
        visual_changed: false,
        release_missing_since: 0,
        preview_offset: 0,
        preview_alpha: focus_tab_drag_alpha,
        slot_index: 0,
        consume_only: false
    }
    focus_tab_gesture := gesture

    try {
        CancelPendingAdoptionUndo()
        target := "ahk_id " gesture.target_hwnd
        marker := "ahk_id " gesture.overlay_hwnd

        if !focus_corner_overlays.Has(gesture.target_hwnd)
            || focus_corner_overlays[gesture.target_hwnd].gui.Hwnd != gesture.overlay_hwnd
            throw Error("The pressed focus tab no longer exists.")

        ; Focus is the first action; swipe recognition never delays it.
        WinActivate(target)

        WinGetPos(&target_x, &target_y, &target_width, &target_height, target)
        WinGetPos(&marker_x, &marker_y, , , marker)
        gesture.target_x := target_x
        gesture.target_y := target_y
        gesture.target_width := target_width
        gesture.target_height := target_height
        gesture.marker_x := marker_x
        gesture.marker_y := marker_y
        gesture.target_pid := WinGetPID(target)
        gesture.monitor_index := GetManagedCascadeMonitor(gesture.target_hwnd)
        gesture.was_topmost := !!(WinGetExStyle(marker) & 0x8)

        ; One-window geometry is enough to pin the slot. The live stack is
        ; checked once on press to decide whether a swipe can do anything.
        slots := BuildCascadeSlotStacks([gesture.target_hwnd], cascade_slot_tolerance)
        if slots.Length = 1
            gesture.slot_index := slots[1]["slot_index"]

        gesture.consume_only := !FocusTabSlotHasOtherLayers(
            gesture.target_hwnd,
            gesture.monitor_index,
            gesture.slot_index
        )

        gesture.ready := true
        if !IsFocusTabGestureTargetValid(gesture) {
            CancelFocusTabGesture()
            return
        }

        ; A single-layer slot is a pure press action. Keep ownership of the
        ; matching release, but hide the tab immediately and never preview it.
        if gesture.consume_only {
            HideFocusCornerOverlay(gesture.target_hwnd)
            QueueFocusCornerUpdate()
            return
        }

        ; Only the held tab becomes topmost, so its preview remains visible even
        ; when it moves slightly over the focused application. It never activates.
        gesture.visual_changed := true
        WinSetAlwaysOnTop(1, marker)
        WinSetTransparent(focus_tab_drag_alpha, marker)
    }
    catch Error as err {
        CancelFocusTabGesture()
        DebugError("BeginFocusTabGesture", err)
    }
    finally {
        SetTimer(UpdateFocusTabGesture, focus_tab_gesture_poll_ms)
        Critical(previous_critical)
    }
}

FocusTabSlotHasOtherLayers(target_hwnd, monitor_index, slot_index)
{
    if !monitor_index || !slot_index
        return false

    for stack_info in GetCascadeSlotStacksForMonitor(monitor_index) {
        if stack_info["slot_index"] != slot_index
            continue

        contains_target := false

        for stack_hwnd in stack_info["windows"] {
            if stack_hwnd = target_hwnd {
                contains_target := true
                break
            }
        }

        return (
            contains_target
            && stack_info["windows"].Length > 1
        )
    }

    return false
}


IsHeldFocusTab(hwnd)
{
    global focus_tab_gesture

    return (
        IsObject(focus_tab_gesture)
        && !focus_tab_gesture.cancelled
        && !focus_tab_gesture.consume_only
        && focus_tab_gesture.target_hwnd = hwnd
    )
}

; =============================================================================
; gesture-only tracking and visual preview
; =============================================================================

UpdateFocusTabGesture()
{
    global focus_tab_gesture
    global focus_tab_drag_preview_limit_px
    global focus_tab_drag_alpha, focus_tab_swipe_ready_alpha

    if !IsObject(focus_tab_gesture) {
        SetTimer(UpdateFocusTabGesture, 0)
        return
    }

    ; This timer does only short queries/preview updates. Finish/cancel must
    ; not interrupt it halfway through restoring or moving the held overlay.
    Critical "On"
    gesture := focus_tab_gesture
    try {
        ; The mouse hook owns release outside the tab, even after another process
        ; is focused. SetCapture alone cannot provide that background guarantee.
        if !GetKeyState("LButton", "P") {
            ; Give an already-queued release hotkey time to finish normally.
            ; A genuinely missed release only cancels; it must not rotate later.
            if !gesture.release_missing_since
                gesture.release_missing_since := A_TickCount
            else if ((A_TickCount - gesture.release_missing_since) & 0xFFFFFFFF) >= 100
                StopFocusTabGesture()
            return
        }
        gesture.release_missing_since := 0

        if gesture.cancelled || gesture.consume_only
            return

        if !IsFocusTabGestureTargetValid(gesture)
            || GetKeyState("RButton", "P")
            || GetKeyState("MButton", "P") {
            CancelFocusTabGesture()
            return
        }

        MouseGetPos(&mouse_x, &mouse_y)
        delta_x := mouse_x - gesture.start_x
        delta_y := mouse_y - gesture.start_y
        direction := GetFocusTabSwipeDirection(delta_x, delta_y)

        ; A restrained preview moves the tab, never the application window.
        offset := Round(Max(
            -focus_tab_drag_preview_limit_px,
            Min(focus_tab_drag_preview_limit_px, delta_x / 3)
        ))
        alpha := direction && gesture.slot_index
            ? focus_tab_swipe_ready_alpha : focus_tab_drag_alpha

        if offset != gesture.preview_offset {
            DllCall(
                "SetWindowPos",
                "ptr", gesture.overlay_hwnd,
                "ptr", 0,
                "int", gesture.marker_x + offset,
                "int", gesture.marker_y,
                "int", 0,
                "int", 0,
                "uint", 0x0015, ; SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE
                "int"
            )
            gesture.preview_offset := offset
        }

        if alpha != gesture.preview_alpha {
            WinSetTransparent(alpha, "ahk_id " gesture.overlay_hwnd)
            gesture.preview_alpha := alpha
        }
    }
    catch Error as err {
        CancelFocusTabGesture()
        DebugError("UpdateFocusTabGesture", err)
    }
}

GetFocusTabSwipeDirection(delta_x, delta_y)
{
    global focus_tab_swipe_threshold_px, focus_tab_swipe_horizontal_ratio

    if Abs(delta_x) < focus_tab_swipe_threshold_px
        || Abs(delta_x) < Abs(delta_y) * focus_tab_swipe_horizontal_ratio
        return 0

    return delta_x < 0 ? -1 : 1
}

IsFocusTabGestureTargetValid(gesture)
{
    global focus_corner_overlays

    if !gesture.ready || gesture.cancelled
        return false

    hwnd := gesture.target_hwnd
    if DllCall("GetForegroundWindow", "ptr") != hwnd
        || !DllCall("IsWindowVisible", "ptr", hwnd, "int")
        || !focus_corner_overlays.Has(hwnd)
        || focus_corner_overlays[hwnd].gui.Hwnd != gesture.overlay_hwnd
        return false

    try {
        target := "ahk_id " hwnd
        if WinGetMinMax(target) != 0
            || WinGetPID(target) != gesture.target_pid
            || !gesture.monitor_index
            || GetManagedCascadeMonitor(hwnd) != gesture.monitor_index
            return false

        WinGetPos(&x, &y, &width, &height, target)

        ; A moved/resized target or an automatic slot compaction invalidates the
        ; original gesture. Never apply it to whatever happens to replace it.
        return (
            Abs(x - gesture.target_x) <= 2
            && Abs(y - gesture.target_y) <= 2
            && Abs(width - gesture.target_width) <= 2
            && Abs(height - gesture.target_height) <= 2
        )
    }
    catch {
        return false
    }
}

; =============================================================================
; release, cancellation, and cleanup
; =============================================================================

FinishFocusTabGesture(*)
{
    global focus_tab_gesture, focus_tab_release_point

    previous_critical := A_IsCritical
    Critical "On"
    try {
        ; A very quick release can arrive before its press hotkey has run.
        if !IsObject(focus_tab_gesture)
            BeginFocusTabGesture()

        if !IsObject(focus_tab_gesture)
            return

        gesture := focus_tab_gesture
        direction := 0
        if (
            !gesture.consume_only
            && IsFocusTabGestureTargetValid(gesture)
            && gesture.slot_index
        ) {
            if IsObject(focus_tab_release_point) {
                mouse_x := focus_tab_release_point.x
                mouse_y := focus_tab_release_point.y
            } else {
                MouseGetPos(&mouse_x, &mouse_y)
            }
            direction := GetFocusTabSwipeDirection(
                mouse_x - gesture.start_x,
                mouse_y - gesture.start_y
            )
        }

        ; End mouse ownership and restore the tab before changing the stack.
        StopFocusTabGesture()

        if direction {
            RotateCascadeSlotForWindow(
                gesture.target_hwnd,
                direction,
                gesture.monitor_index,
                gesture.slot_index
            )
        }
    }
    catch Error as err {
        DebugError("FinishFocusTabGesture", err)
    }
    finally {
        StopFocusTabGesture()
        Critical(previous_critical)
    }
}

CancelFocusTabGesture(*)
{
    global focus_tab_gesture

    if !IsObject(focus_tab_gesture)
        return

    if focus_tab_gesture.cancelled
        return

    ; Retain ownership until mouse-up, even if the target closes or focus moves.
    ; Clearing it here could deliver an unmatched release to an unrelated app.
    focus_tab_gesture.cancelled := true
    RestoreFocusTabGestureVisual(focus_tab_gesture)
    QueueFocusCornerUpdate()
}

StopFocusTabGesture(queue_update := true)
{
    global focus_tab_pending_press, focus_tab_gesture, focus_tab_release_point

    gesture := focus_tab_gesture
    focus_tab_gesture := 0
    focus_tab_pending_press := 0
    focus_tab_release_point := 0
    SetTimer(UpdateFocusTabGesture, 0)

    if !IsObject(gesture)
        return

    RestoreFocusTabGestureVisual(gesture)
    if queue_update
        QueueFocusCornerUpdate()
}

RestoreFocusTabGestureVisual(gesture)
{
    global focus_corner_overlays
    global focus_corner_visible

    if !gesture.visual_changed
        return
    gesture.visual_changed := false

    if !focus_corner_overlays.Has(gesture.target_hwnd)
        return
    overlay := focus_corner_overlays[gesture.target_hwnd]
    if overlay.gui.Hwnd != gesture.overlay_hwnd
        return

    marker := "ahk_id " gesture.overlay_hwnd
    try overlay.gui.Hide()
    try WinSetAlwaysOnTop(gesture.was_topmost, marker)
    try WinSetTransparent(focus_corner_visible ? overlay.alpha : 1, marker)

    ; Mark it unplaced so the normal updater restores geometry, not the preview.
    overlay.shown := false
}
