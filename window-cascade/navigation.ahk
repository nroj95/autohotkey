; Internal Window Cascade module. Launch ..\window-cascade.ahk instead.
; Included into the same script; functions share the existing global state.

; =============================================================================
; current-layer focus and swapping
; =============================================================================

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
    global placement_reservations

    if IsCascadeWindowBeingDragged(hwnd)
        return false
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

    if current_x = target_x && current_y = target_y
        return true

    ; Compaction must replace the previous stabilization destination, otherwise
    ; its delayed retry could pull a just-dropped window back to an old slot.
    CancelPlacementStabilization(hwnd)
    if placement_reservations.Has(hwnd)
        placement_reservations.Delete(hwnd)

    raw_target := GetRawRectForVisibleTarget(
        hwnd,
        target_x,
        target_y,
        current_width,
        current_height
    )

    if IsCascadeWindowBeingDragged(hwnd)
        return false
    placement_reservations[hwnd] := Map(
        "monitor", GetMonitorForWindow(hwnd), "x", target_x, "y", target_y
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
        if placement_reservations.Has(hwnd)
            placement_reservations.Delete(hwnd)
        return false
    }

    if !IsCascadeWindowBeingDragged(hwnd)
        SchedulePlacementStabilization(hwnd, target_x, target_y, current_width, current_height)
    return true
}


; =============================================================================
; slot and layer rotation
; =============================================================================

RotateCurrentCascadeSlot(direction)
{
    return RotateCascadeSlotForWindow(WinExist("A"), direction)
}

RotateCascadeSlotForWindow(
    target_hwnd,
    direction,
    expected_monitor := 0,
    expected_slot := 0
)
{
    if !target_hwnd || !WinExist("ahk_id " target_hwnd)
        || IsShellSurfaceWindow(target_hwnd)
        return 0

    monitor_index := GetMonitorForWindow(target_hwnd)

    if !monitor_index || (expected_monitor && monitor_index != expected_monitor)
        return 0

    stacks := GetCascadeSlotStacksForMonitor(monitor_index)
    z_ranks := GetCascadeWindowZRanks()

    for stack_info in stacks {
        ; A tab click can pin rotation to the slot it actually resolved.
        if expected_slot && stack_info["slot_index"] != expected_slot
            continue

        ordered_stack := SortCascadeWindowsByZOrder(
            stack_info["windows"],
            z_ranks
        )

        ; Preserve keyboard behavior: only rotate an exposed window's own stack.
        if ordered_stack.Length < 2 || ordered_stack[1] != target_hwnd
            continue

        next_hwnd := RotateCascadeStackWindows(
            ordered_stack,
            direction
        )

        if next_hwnd
            ActivateCascadeWindow(next_hwnd)

        QueueFocusCornerUpdate()
        return next_hwnd
    }

    return 0
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


; =============================================================================
; spatial ordering
; =============================================================================

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


; =============================================================================
; activation and bringing a cascade forward
; =============================================================================

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
